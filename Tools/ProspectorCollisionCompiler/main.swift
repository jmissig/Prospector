import Foundation
import RealityKit

private struct Metrics {
    var entities = 0
    var eligibleModels = 0
    var collisionModels = 0
}

private struct CollisionInstallation {
    var exact = 0
    var fallback = 0
}

@MainActor
private func collectMetrics(from entity: Entity) -> Metrics {
    var metrics = Metrics()

    func visit(_ entity: Entity) {
        metrics.entities += 1
        if let modelEntity = entity as? ModelEntity,
           modelEntity.model?.mesh != nil {
            metrics.eligibleModels += 1
            if modelEntity.components[CollisionComponent.self] != nil {
                metrics.collisionModels += 1
            }
        }
        for child in entity.children {
            visit(child)
        }
    }

    visit(entity)
    return metrics
}

@MainActor
private func installRuntimeEquivalentCollisions(on entity: Entity) async throws -> CollisionInstallation {
    var installation = CollisionInstallation()

    if let modelEntity = entity as? ModelEntity,
       let mesh = modelEntity.model?.mesh {
        do {
            let shape = try await ShapeResource.generateStaticMesh(from: mesh)
            modelEntity.components.set(CollisionComponent(shapes: [shape], isStatic: true))
            installation.exact += 1
        } catch {
            modelEntity.generateCollisionShapes(recursive: false, static: true)
            installation.fallback += 1
        }
    }

    for child in entity.children {
        let childInstallation = try await installRuntimeEquivalentCollisions(on: child)
        installation.exact += childInstallation.exact
        installation.fallback += childInstallation.fallback
    }
    return installation
}

private func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private func installAtomically(from temporaryURL: URL, to outputURL: URL) throws {
    var coordinationError: NSError?
    var installError: Error?
    NSFileCoordinator().coordinate(
        writingItemAt: outputURL.deletingLastPathComponent(),
        options: .forMerging,
        error: &coordinationError
    ) { coordinatedDirectory in
        let coordinatedOutput = coordinatedDirectory.appendingPathComponent(outputURL.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: coordinatedOutput.path) {
                _ = try FileManager.default.replaceItemAt(coordinatedOutput, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: coordinatedOutput)
            }
        } catch {
            installError = error
        }
    }
    if let coordinationError { throw coordinationError }
    if let installError { throw installError }
}

@main
private struct ProspectorCollisionCompiler {
    @MainActor
    static func main() async {
        do {
            try await run()
        } catch {
            writeError("prospector-collision-compiler: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    @MainActor
    private static func run() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            writeError("usage: prospector-collision-compiler input.usdz output.reality")
            Foundation.exit(64)
        }

        let inputURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        let outputURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
        guard inputURL.pathExtension.lowercased() == "usdz",
              outputURL.pathExtension.lowercased() == "reality" else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let inputValues = try inputURL.resourceValues(forKeys: [.isRegularFileKey])
        guard inputValues.isRegularFile == true else {
            throw CocoaError(.fileNoSuchFile)
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporaryURL = outputURL.deletingLastPathComponent().appendingPathComponent(
            ".\(outputURL.deletingPathExtension().lastPathComponent).\(UUID().uuidString).reality"
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let clock = ContinuousClock()
        let loadStart = clock.now
        let entity = try await Entity(contentsOf: inputURL)
        let loadDuration = loadStart.duration(to: clock.now)

        let collisionStart = clock.now
        let installation = try await installRuntimeEquivalentCollisions(on: entity)
        let collisionDuration = collisionStart.duration(to: clock.now)
        let processed = collectMetrics(from: entity)
        guard processed.eligibleModels > 0,
              processed.collisionModels == processed.eligibleModels else {
            throw CocoaError(.coderInvalidValue)
        }

        let exportStart = clock.now
        try await entity.write(to: temporaryURL)
        let exportDuration = exportStart.duration(to: clock.now)

        let reloadStart = clock.now
        let reloaded = try await Entity(contentsOf: temporaryURL)
        let reloadDuration = reloadStart.duration(to: clock.now)
        let reloadedMetrics = collectMetrics(from: reloaded)
        guard reloadedMetrics.eligibleModels == processed.eligibleModels,
              reloadedMetrics.collisionModels == processed.collisionModels else {
            throw CocoaError(.coderInvalidValue)
        }

        try installAtomically(from: temporaryURL, to: outputURL)

        let outputBytes = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let report: [String: Any] = [
            "input": inputURL.path,
            "output": outputURL.path,
            "outputBytes": outputBytes,
            "entities": reloadedMetrics.entities,
            "eligibleModels": reloadedMetrics.eligibleModels,
            "collisionModels": reloadedMetrics.collisionModels,
            "exactCollisions": installation.exact,
            "fallbackCollisions": installation.fallback,
            "loadSeconds": seconds(loadDuration),
            "collisionSeconds": seconds(collisionDuration),
            "exportSeconds": seconds(exportDuration),
            "reloadSeconds": seconds(reloadDuration),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys]
        )
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
