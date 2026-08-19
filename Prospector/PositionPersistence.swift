//
//  PositionPersistence.swift
//  Prospector
//

import Foundation
import simd

struct ViewerPosition: Codable, Hashable, Sendable {
    let x: Double
    let y: Double
    let z: Double

    init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    init(_ value: SIMD3<Float>) {
        self.init(x: Double(value.x), y: Double(value.y), z: Double(value.z))
    }

    var simdValue: SIMD3<Float> { SIMD3(Float(x), Float(y), Float(z)) }
    var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}

struct ViewerPose: Codable, Hashable, Sendable {
    let viewerPositionMeters: ViewerPosition
    let yawRadians: Double

    init(viewerPositionMeters: ViewerPosition, yawRadians: Double) {
        self.viewerPositionMeters = viewerPositionMeters
        self.yawRadians = yawRadians
    }

    init(position: SIMD3<Float>, yawRadians: Float) {
        self.init(viewerPositionMeters: ViewerPosition(position), yawRadians: Double(yawRadians))
    }

    static let origin = ViewerPose(
        viewerPositionMeters: ViewerPosition(x: 0, y: 0, z: 0),
        yawRadians: 0
    )

    var position: SIMD3<Float> { viewerPositionMeters.simdValue }
    var yaw: Float { Float(yawRadians) }
    var isFinite: Bool { viewerPositionMeters.isFinite && yawRadians.isFinite }
}

struct SavedLocation: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    let viewerPositionMeters: ViewerPosition

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        viewerPositionMeters: ViewerPosition
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.viewerPositionMeters = viewerPositionMeters
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, viewerPositionMeters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        viewerPositionMeters = try container.decode(ViewerPosition.self, forKey: .viewerPositionMeters)
    }
}

struct ModelPositionState: Codable, Sendable {
    static let supportedFormatVersion = 1

    let formatVersion: Int
    let modelID: String
    var updatedAt: Date
    var viewerPositionMeters: ViewerPosition
    var yawRadians: Double
    var savedLocations: [SavedLocation]

    init(
        modelID: String,
        pose: ViewerPose = .origin,
        updatedAt: Date = .now,
        savedLocations: [SavedLocation] = []
    ) {
        formatVersion = Self.supportedFormatVersion
        self.modelID = modelID
        self.updatedAt = updatedAt
        viewerPositionMeters = pose.viewerPositionMeters
        yawRadians = pose.yawRadians
        self.savedLocations = savedLocations
    }

    var pose: ViewerPose {
        ViewerPose(viewerPositionMeters: viewerPositionMeters, yawRadians: yawRadians)
    }

    mutating func record(_ pose: ViewerPose, at date: Date = .now) {
        updatedAt = date
        viewerPositionMeters = pose.viewerPositionMeters
        yawRadians = pose.yawRadians
    }
}

struct LoadedModelPositionState: Sendable {
    let state: ModelPositionState?
    let writesEnabled: Bool
}

enum ProspectorStateError: LocalizedError {
    case unsupportedFormatVersion(Int)
    case mismatchedModelID(expected: String, actual: String)
    case invalidPose(String)
    case invalidLocation(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormatVersion(let version):
            return "State format version \(version) is not supported. Position saving is disabled."
        case .mismatchedModelID(let expected, let actual):
            return "State for “\(expected)” identifies itself as “\(actual)”. Position saving is disabled."
        case .invalidPose(let modelID):
            return "State contains an invalid pose for “\(modelID)”. Position saving is disabled."
        case .invalidLocation(let modelID):
            return "State contains an invalid saved location for “\(modelID)”. Position saving is disabled."
        }
    }
}

@MainActor
final class PositionPersistenceCoordinator {
    private var states: [String: ModelPositionState]
    private let writers: [String: ModelPositionStateWriter]
    private var writesEnabled: [String: Bool]
    private var dirtyModelIDs: Set<String>
    private var revisions: [String: Int] = [:]
    private var lastSuccessfulWrite: [String: Date] = [:]
    private var debounceTask: Task<Void, Never>?
    private var writeTask: Task<String?, Never>?
    private let onWarning: (String) -> Void

    private let stationaryDelay: Duration = .seconds(2)
    private let continuousWriteInterval: TimeInterval = 30

    init(
        models: [ModelDescriptor],
        initialStates: [String: LoadedModelPositionState],
        onWarning: @escaping (String) -> Void
    ) {
        states = initialStates.compactMapValues(\.state)
        writers = Dictionary(uniqueKeysWithValues: models.compactMap { model in
            model.stateURL.map { (model.id, ModelPositionStateWriter(stateURL: $0)) }
        })
        writesEnabled = Dictionary(uniqueKeysWithValues: models.map {
            ($0.id, initialStates[$0.id]?.writesEnabled ?? ($0.stateURL != nil))
        })
        dirtyModelIDs = []
        self.onWarning = onWarning
    }

    deinit {
        debounceTask?.cancel()
        writeTask?.cancel()
    }

    func pose(for modelID: String) -> ViewerPose? { states[modelID]?.pose }
    func locations(for modelID: String) -> [SavedLocation] { states[modelID]?.savedLocations ?? [] }

    func record(pose: ViewerPose, for modelID: String) {
        guard pose.isFinite, writers[modelID] != nil else { return }
        var state = states[modelID] ?? ModelPositionState(modelID: modelID, pose: pose)
        state.record(pose)
        states[modelID] = state
        markDirty(modelID)
    }

    func addLocation(position: ViewerPosition, for modelID: String) -> SavedLocation? {
        guard position.isFinite, writers[modelID] != nil else { return nil }
        var state = states[modelID] ?? ModelPositionState(modelID: modelID)
        let usedNumbers = Set(state.savedLocations.compactMap { location -> Int? in
            let prefix = "Location "
            guard location.name.hasPrefix(prefix) else { return nil }
            return Int(location.name.dropFirst(prefix.count))
        })
        let number = sequence(first: 1, next: { $0 + 1 }).first(where: { !usedNumbers.contains($0) }) ?? 1
        let location = SavedLocation(name: "Location \(number)", viewerPositionMeters: position)
        state.savedLocations.append(location)
        state.updatedAt = .now
        states[modelID] = state
        markDirty(modelID)
        return location
    }

    func deleteLocation(id: SavedLocation.ID, for modelID: String) {
        guard var state = states[modelID] else { return }
        let oldCount = state.savedLocations.count
        state.savedLocations.removeAll(where: { $0.id == id })
        guard state.savedLocations.count != oldCount else { return }
        state.updatedAt = .now
        states[modelID] = state
        markDirty(modelID)
    }

    func flush() async -> String? {
        debounceTask?.cancel()
        debounceTask = nil
        if let writeTask { _ = await writeTask.value }

        for modelID in dirtyModelIDs.sorted() {
            if let warning = await writeNow(modelID) { return warning }
        }
        return nil
    }

    private func markDirty(_ modelID: String) {
        dirtyModelIDs.insert(modelID)
        revisions[modelID, default: 0] += 1
        let now = Date()
        if let lastWrite = lastSuccessfulWrite[modelID],
           now.timeIntervalSince(lastWrite) >= continuousWriteInterval {
            startWrite(modelID)
        } else {
            scheduleWrite(modelID)
        }
    }

    private func scheduleWrite(_ modelID: String) {
        guard writesEnabled[modelID] == true else { return }
        debounceTask?.cancel()
        let stationaryDelay = self.stationaryDelay
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: stationaryDelay)
            guard !Task.isCancelled else { return }
            self?.startWrite(modelID)
        }
    }

    private func startWrite(_ modelID: String) {
        guard writesEnabled[modelID] == true, dirtyModelIDs.contains(modelID), writeTask == nil else { return }
        debounceTask?.cancel()
        debounceTask = nil
        writeTask = Task { [weak self] in
            guard let self else { return nil }
            let warning = await writeNow(modelID)
            writeTask = nil
            if let warning { onWarning(warning) }
            if let nextModelID = dirtyModelIDs.sorted().first {
                scheduleWrite(nextModelID)
            }
            return warning
        }
    }

    private func writeNow(_ modelID: String) async -> String? {
        guard writesEnabled[modelID] == true,
              dirtyModelIDs.contains(modelID),
              let state = states[modelID],
              let writer = writers[modelID] else { return nil }
        let revision = revisions[modelID, default: 0]
        do {
            try await writer.write(state)
            if revisions[modelID, default: 0] == revision { dirtyModelIDs.remove(modelID) }
            lastSuccessfulWrite[modelID] = .now
            return nil
        } catch {
            writesEnabled[modelID] = false
            return "Position saving stopped for \(modelID): \(error.localizedDescription)"
        }
    }
}

actor ModelPositionStateWriter {
    private let stateURL: URL

    init(stateURL: URL) { self.stateURL = stateURL }

    func write(_ state: ModelPositionState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(state)
        data.append(0x0A)

        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: stateURL, options: [], error: &coordinationError) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
