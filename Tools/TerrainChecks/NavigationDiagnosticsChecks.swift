import Foundation

enum NavigationDiagnosticsChecks {
    static func run(in base: URL) async throws {
        let package = base.appendingPathComponent("Diagnostics.prospector")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let scope = SecurityScopedResource(url: package)
        let writer = NavigationDiagnosticWriter(scope: scope, maximumBytes: 2048)
        let session = UUID()
        func entry(_ sequence: Int) -> NavigationDiagnosticEntry {
            .init(timestamp: .now, uptimeSeconds: Double(sequence), sessionID: session,
                  sequence: sequence, source: "test", details: "input\nquoted \"value\"")
        }
        let sentinel = package.appendingPathComponent("house.state.json")
        try Data("preserve saved positions".utf8).write(to: sentinel)
        for sequence in 1...25 { try await writer.append(entry(sequence)) }
        let url = package.appendingPathComponent(NavigationDiagnosticWriter.filename)
        let data = try Data(contentsOf: url)
        precondition(data.count <= 2048)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try data.split(separator: 0x0A).map { try decoder.decode(NavigationDiagnosticEntry.self, from: Data($0)) }
        precondition(entries.count > 1 && entries.count < 25)
        precondition(entries.last?.sequence == 25)
        precondition(entries.map(\.sequence) == entries.map(\.sequence).sorted())
        precondition(entries.allSatisfy { $0.sessionID == session })
        let savedState = try String(contentsOf: sentinel, encoding: .utf8)
        precondition(savedState == "preserve saved positions")
        let reopened = NavigationDiagnosticWriter(scope: scope, maximumBytes: 2048)
        try await reopened.append(entry(26))
        let reopenedData = try Data(contentsOf: url)
        precondition(reopenedData.count <= 2048)
        let last = try decoder.decode(NavigationDiagnosticEntry.self, from: Data(reopenedData.split(separator: 0x0A).last!))
        precondition(last.sequence == 26)
        print("PASS: diagnostic append/reopen, bounded complete JSONL retention, saved-state preservation")

        let unsafePackage = base.appendingPathComponent("Symlink.prospector")
        try FileManager.default.createDirectory(at: unsafePackage, withIntermediateDirectories: true)
        let outside = base.appendingPathComponent("outside-log.jsonl")
        try Data("untouched".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: unsafePackage.appendingPathComponent(NavigationDiagnosticWriter.filename), withDestinationURL: outside)
        let unsafe = NavigationDiagnosticWriter(scope: SecurityScopedResource(url: unsafePackage))
        do { try await unsafe.append(entry(1)); fatalError("Must reject symlink logging") } catch {}
        try await unsafe.append(entry(2)) // failure disables retries
        let outsideContents = try String(contentsOf: outside, encoding: .utf8)
        precondition(outsideContents == "untouched")
        print("PASS: diagnostic symlink escape rejection and stop-on-failure")
    }
}
