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

    var simdValue: SIMD3<Float> {
        SIMD3(Float(x), Float(y), Float(z))
    }

    var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}

struct ViewerPose: Codable, Hashable, Sendable {
    let viewerPositionMeters: ViewerPosition
    let yawRadians: Double

    init(viewerPositionMeters: ViewerPosition, yawRadians: Double) {
        self.viewerPositionMeters = viewerPositionMeters
        self.yawRadians = yawRadians
    }

    init(position: SIMD3<Float>, yawRadians: Float) {
        self.init(
            viewerPositionMeters: ViewerPosition(position),
            yawRadians: Double(yawRadians)
        )
    }

    static let origin = ViewerPose(
        viewerPositionMeters: ViewerPosition(x: 0, y: 0, z: 0),
        yawRadians: 0
    )

    var position: SIMD3<Float> {
        viewerPositionMeters.simdValue
    }

    var yaw: Float {
        Float(yawRadians)
    }

    var isFinite: Bool {
        viewerPositionMeters.isFinite && yawRadians.isFinite
    }
}

struct ProspectorState: Codable, Sendable {
    static let supportedFormatVersion = 1

    let formatVersion: Int
    var updatedAt: Date
    var currentModelID: String
    var modelStates: [ModelState]

    struct ModelState: Codable, Sendable {
        let modelID: String
        var updatedAt: Date
        var viewerPositionMeters: ViewerPosition
        var yawRadians: Double

        var pose: ViewerPose {
            ViewerPose(
                viewerPositionMeters: viewerPositionMeters,
                yawRadians: yawRadians
            )
        }
    }

    init(currentModelID: String, updatedAt: Date = .now, modelStates: [ModelState] = []) {
        formatVersion = Self.supportedFormatVersion
        self.updatedAt = updatedAt
        self.currentModelID = currentModelID
        self.modelStates = modelStates
    }

    func pose(for modelID: String) -> ViewerPose? {
        modelStates.first(where: { $0.modelID == modelID })?.pose
    }

    mutating func record(_ pose: ViewerPose, for modelID: String, at date: Date) {
        updatedAt = date

        let modelState = ModelState(
            modelID: modelID,
            updatedAt: date,
            viewerPositionMeters: pose.viewerPositionMeters,
            yawRadians: pose.yawRadians
        )

        if let index = modelStates.firstIndex(where: { $0.modelID == modelID }) {
            modelStates[index] = modelState
        } else {
            modelStates.append(modelState)
        }
    }
}

enum ProspectorStateError: LocalizedError {
    case unsupportedFormatVersion(Int)
    case duplicateModelID(String)
    case invalidCurrentModelID(String)
    case invalidPose(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormatVersion(let version):
            return "State format version \(version) is not supported. Position saving is disabled."
        case .duplicateModelID(let modelID):
            return "state.json contains duplicate entries for “\(modelID)”. Position saving is disabled."
        case .invalidCurrentModelID(let modelID):
            return "state.json references unknown current model “\(modelID)”. Position saving is disabled."
        case .invalidPose(let modelID):
            return "state.json contains an invalid pose for “\(modelID)”. Position saving is disabled."
        }
    }
}

@MainActor
final class PositionPersistenceCoordinator {
    private let writer: ProspectorStateWriter
    private var state: ProspectorState
    private var writesEnabled: Bool
    private var isDirty = false
    private var revision = 0
    private var lastSuccessfulWrite: Date?
    private var debounceTask: Task<Void, Never>?
    private var writeTask: Task<String?, Never>?
    private let onWarning: (String) -> Void

    private let stationaryDelay: Duration = .seconds(2)
    private let continuousWriteInterval: TimeInterval = 30

    init(
        packageURL: URL,
        initialState: ProspectorState?,
        writesEnabled: Bool,
        onWarning: @escaping (String) -> Void
    ) {
        writer = ProspectorStateWriter(packageURL: packageURL)
        state = initialState ?? ProspectorState(currentModelID: "")
        self.writesEnabled = writesEnabled
        self.onWarning = onWarning
    }

    deinit {
        debounceTask?.cancel()
        writeTask?.cancel()
    }

    func pose(for modelID: String) -> ViewerPose? {
        state.pose(for: modelID)
    }

    func setCurrentModel(_ modelID: String) {
        guard state.currentModelID != modelID else { return }
        state.currentModelID = modelID
        state.updatedAt = .now
        isDirty = true
        revision += 1
        scheduleWrite()
    }

    func record(pose: ViewerPose, for modelID: String) {
        guard pose.isFinite else { return }

        let now = Date()
        state.record(pose, for: modelID, at: now)
        isDirty = true
        revision += 1

        if let lastSuccessfulWrite,
           now.timeIntervalSince(lastSuccessfulWrite) >= continuousWriteInterval {
            startWrite()
        } else {
            scheduleWrite()
        }
    }

    func flush() async -> String? {
        debounceTask?.cancel()
        debounceTask = nil

        if let writeTask {
            _ = await writeTask.value
        }

        guard isDirty, writesEnabled else { return nil }
        return await writeNow()
    }

    private func scheduleWrite() {
        guard writesEnabled else { return }

        debounceTask?.cancel()
        let stationaryDelay = self.stationaryDelay
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: stationaryDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.startWrite()
        }
    }

    private func startWrite() {
        guard writesEnabled, isDirty, writeTask == nil else { return }

        debounceTask?.cancel()
        debounceTask = nil
        writeTask = Task { [weak self] in
            guard let self else { return nil }
            let warning = await writeNow()
            writeTask = nil
            if let warning {
                onWarning(warning)
            }
            return warning
        }
    }

    private func writeNow() async -> String? {
        guard writesEnabled, isDirty else { return nil }

        let snapshot = state
        let snapshotRevision = revision
        do {
            try await writer.write(snapshot)
            isDirty = revision != snapshotRevision
            lastSuccessfulWrite = .now
            if isDirty {
                scheduleWrite()
            }
            return nil
        } catch {
            writesEnabled = false
            debounceTask?.cancel()
            debounceTask = nil
            return "Position saving stopped: \(error.localizedDescription)"
        }
    }
}

actor ProspectorStateWriter {
    private let stateURL: URL

    init(packageURL: URL) {
        stateURL = packageURL.appendingPathComponent(
            ProspectorDocumentLoader.stateFilename,
            isDirectory: false
        )
    }

    func write(_ state: ProspectorState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(state)
        data.append(0x0A)

        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: stateURL,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let writeError {
            throw writeError
        }
    }
}
