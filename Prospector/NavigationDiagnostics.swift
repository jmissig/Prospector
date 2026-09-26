import Foundation

struct NavigationDiagnosticEntry: Codable, Sendable {
    let timestamp: Date
    let uptimeSeconds: Double
    let sessionID: UUID
    let sequence: Int
    let source: String
    let details: String
}

/// Serial, coordinated writes off the main actor. Only event-triggered entries;
/// no timer, frame-by-frame disk writes, or observed state that wakes the scene.
actor NavigationDiagnosticWriter {
    static let filename = "navigation-diagnostics.jsonl"
    private let scope: SecurityScopedResource
    private let maximumBytes: Int
    private var writesEnabled = true

    init(scope: SecurityScopedResource, maximumBytes: Int = 1_048_576) {
        self.scope = scope
        self.maximumBytes = maximumBytes
    }

    func append(_ entry: NavigationDiagnosticEntry) throws {
        guard writesEnabled else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            var line = try encoder.encode(entry)
            line.append(0x0A)
            guard line.count <= maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
            let root = scope.url.standardizedFileURL.resolvingSymlinksInPath()
            let url = root.appendingPathComponent(Self.filename)
            var coordinationError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { target in
                do {
                    // A package must not redirect diagnostics into another file.
                    guard target.resolvingSymlinksInPath().deletingLastPathComponent() == root else {
                        throw CocoaError(.fileWriteNoPermission)
                    }
                    let values = try? target.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                    guard values?.isSymbolicLink != true else { throw CocoaError(.fileWriteNoPermission) }
                    if FileManager.default.fileExists(atPath: target.path) {
                        guard values?.isRegularFile == true else { throw CocoaError(.fileWriteNoPermission) }
                        let handle = try FileHandle(forUpdating: target)
                        defer { try? handle.close() }
                        let size = try handle.seekToEnd()
                        if size + UInt64(line.count) <= UInt64(maximumBytes) {
                            try handle.write(contentsOf: line)
                        } else {
                            // Keep complete recent lines, reserving room for this entry.
                            let keep = min(maximumBytes / 2, maximumBytes - line.count)
                            try handle.seek(toOffset: size > UInt64(keep) ? size - UInt64(keep) : 0)
                            let tail = try handle.read(upToCount: keep) ?? Data()
                            var retained = Data()
                            if let newline = tail.firstIndex(of: 0x0A) {
                                retained.append(tail.suffix(from: tail.index(after: newline)))
                            }
                            retained.append(line)
                            try retained.write(to: target, options: .atomic)
                        }
                    } else {
                        try line.write(to: target, options: .atomic)
                    }
                } catch { writeError = error }
            }
            if let coordinationError { throw coordinationError }
            if let writeError { throw writeError }
        } catch {
            writesEnabled = false
            throw error
        }
    }
}
