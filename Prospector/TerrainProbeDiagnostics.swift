//
//  TerrainProbeDiagnostics.swift
//  Prospector
//

import Foundation

struct TerrainProbeDiagnosticVector: Codable, Sendable {
    let x: Double
    let y: Double
    let z: Double

    init(_ value: SIMD3<Float>) {
        x = Double(value.x)
        y = Double(value.y)
        z = Double(value.z)
    }
}

struct TerrainProbeHitDiagnostic: Codable, Sendable {
    let rawIndex: Int
    let entityName: String
    let modelPosition: TerrainProbeDiagnosticVector
    let modelNormal: TerrainProbeDiagnosticVector
    let navigationPosition: TerrainProbeDiagnosticVector
    let navigationNormal: TerrainProbeDiagnosticVector
    let accepted: Bool
    let rejectionReason: String?
}

struct TerrainProbeDiagnosticEntry: Codable, Sendable {
    let timestamp: Date
    let systemUptimeSeconds: Double
    let modelID: String
    let resetRequestRevision: Int
    let navigationPosition: TerrainProbeDiagnosticVector
    let virtualYawRadians: Double
    let deviceAnchorAvailable: Bool
    let physicalDevicePosition: TerrainProbeDiagnosticVector
    let navigationRayOrigin: TerrainProbeDiagnosticVector?
    let navigationRayEnd: TerrainProbeDiagnosticVector?
    let modelRayOrigin: TerrainProbeDiagnosticVector?
    let modelRayEnd: TerrainProbeDiagnosticVector?
    let rawHitCount: Int
    let hits: [TerrainProbeHitDiagnostic]
    let selectedRawHitIndex: Int?
    let selectedHeight: Double?
    let appliedHeight: Double
    let defaultHeight: Double
    let usedDefaultHeight: Bool
    let outcome: String
}

actor TerrainProbeDiagnosticLogger {
    static let filename = "terrain-probe.jsonl"

    private let logURL: URL
    // Keep the opened package's security scope alive until pending appends finish.
    private let securityScope: SecurityScopedResource
    private var writesEnabled = true

    init(packageURL: URL, securityScope: SecurityScopedResource) {
        logURL = packageURL.appendingPathComponent(Self.filename, isDirectory: false)
        self.securityScope = securityScope
    }

    func append(_ entry: TerrainProbeDiagnosticEntry) throws {
        guard writesEnabled else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(entry)
        data.append(0x0A)

        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: logURL,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                    let handle = try FileHandle(forWritingTo: coordinatedURL)
                    defer { try? handle.close() }
                    _ = try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: coordinatedURL, options: .atomic)
                }
            } catch {
                writeError = error
            }
        }

        if let coordinationError {
            writesEnabled = false
            throw coordinationError
        }
        if let writeError {
            writesEnabled = false
            throw writeError
        }
    }
}
