import Foundation
import RealityKit

@main
struct TerrainChecks {
    @MainActor
    static func main() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try await NavigationDiagnosticsChecks.run(in: base)
        let package = base.appendingPathComponent("Test.prospector")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data().write(to: package.appendingPathComponent("House.usdz"))
        let model: [String: Any] = ["id": "house", "name": "House", "path": "House.usdz"]
        func open(_ terrain: [[String: Any]]? = nil, models: [[String: Any]]? = nil) throws -> OpenedProspectorDocument {
            var manifest: [String: Any] = ["formatVersion": 1, "name": "Fixture", "defaultModelID": "house", "models": models ?? [model]]
            if let terrain { manifest["terrains"] = terrain }
            try JSONSerialization.data(withJSONObject: manifest).write(to: package.appendingPathComponent("manifest.json"))
            return try ProspectorDocumentLoader.load(from: package)
        }
        func rejects(_ operation: () throws -> Void) {
            do { try operation(); fatalError("Expected validation rejection") } catch {}
        }
        let old = try open()
        precondition(old.models[0].terrain == nil)
        let assets = [["id": "land", "path": "Terrain/missing.usdz"]]
        var withTerrain = model
        withTerrain["terrainID"] = "land"
        let missing = try open(assets, models: [withTerrain])
        precondition(missing.models[0].terrain?.placement == .identity)
        var second = withTerrain
        second["id"] = "second"
        second["statePath"] = "second.state.json"
        second["terrainPlacement"] = ["translationMeters": [10, 20, 30], "yawRadians": 1.0]
        let shared = try open(assets, models: [withTerrain, second])
        precondition(shared.models[0].terrain?.url == shared.models[1].terrain?.url)
        precondition(shared.models[0].terrain?.placement != shared.models[1].terrain?.placement)
        rejects { _ = try open(assets + assets, models: [withTerrain]) }
        rejects { _ = try open([], models: [withTerrain]) }
        rejects { _ = try open([["id": "land", "path": "../outside.usdz"]]) }
        rejects { _ = try open([["id": "land", "path": "/tmp/outside.usdz"]]) }
        rejects { _ = try open([["id": "land", "path": "Terrain/file.fbx"]]) }
        rejects { _ = try open([["id": "", "path": "Terrain/file.usdz"]]) }
        let outside = base.appendingPathComponent("outside.usdz")
        try Data().write(to: outside)
        try FileManager.default.createSymbolicLink(at: package.appendingPathComponent("escape.usdz"), withDestinationURL: outside)
        rejects { _ = try open([["id": "land", "path": "escape.usdz"]]) }
        var orphan = model
        orphan["terrainPlacement"] = ["translationMeters": [0, 0, 0], "yawRadians": 0]
        rejects { _ = try open(models: [orphan]) }
        rejects { _ = try TerrainConfiguration.descriptor(id: "land", placement: .init(translationMeters: [0, 0], yawRadians: 0), assets: ["land": outside]) }
        rejects { _ = try TerrainConfiguration.descriptor(id: "land", placement: .init(translationMeters: [0, .infinity, 0], yawRadians: 0), assets: ["land": outside]) }
        rejects { _ = try TerrainConfiguration.descriptor(id: "land", placement: .init(translationMeters: [0, 0, 0], yawRadians: .nan), assets: ["land": outside]) }
        print("PASS: legacy packages, shared/absent/missing terrain, reference/path/symlink/placement validation")

        let parent = Entity()
        let descriptor = TerrainDescriptor(url: outside, placement: .init(translationMeters: [10, 2, 3], yawRadians: .pi / 2))
        var loadCount = 0
        let source = ModelEntity(mesh: .generateBox(size: 1))
        source.position = [1, 0, 0]
        source.generateCollisionShapes(recursive: true)
        source.components.set(InputTargetComponent())
        let child = ModelEntity(mesh: .generateBox(size: 0.1))
        child.generateCollisionShapes(recursive: true)
        child.components.set(InputTargetComponent())
        source.addChild(child)
        let layer = TerrainLayer { _ in loadCount += 1; return source }
        let navigation = Transform(translation: [0, 5, 0])
        layer.updateNavigation(navigation)
        layer.load(descriptor, revision: 1, parent: parent, scope: nil) { precondition($0 == nil) }
        try await until { parent.children.count == 1 }
        precondition(source.position == SIMD3<Float>(1, 0, 0))
        precondition(simd_distance(source.position(relativeTo: parent), SIMD3<Float>(10, 7, 2)) < 0.001)
        precondition(source.components[CollisionComponent.self] == nil && child.components[CollisionComponent.self] == nil)
        precondition(source.components[InputTargetComponent.self] == nil && child.components[InputTargetComponent.self] == nil)
        let identity = parent.children.first!
        layer.prepare(for: descriptor, revision: 1)
        precondition(!identity.isEnabled)
        layer.load(descriptor, revision: 1, parent: parent, scope: nil) { precondition($0 == nil) }
        precondition(loadCount == 1 && identity.isEnabled && parent.children.count == 1)
        layer.updateNavigation(Transform(translation: [0, 10, 0]))
        precondition(simd_distance(source.position(relativeTo: parent), SIMD3<Float>(10, 12, 2)) < 0.001)
        layer.load(nil, revision: 1, parent: parent, scope: nil) { precondition($0 == nil) }
        precondition(parent.children.isEmpty)
        print("PASS: placement/import composition, current navigation, interaction stripping, reuse and no-terrain switch")

        var continuation: CheckedContinuation<Entity, Error>?
        var calls = 0
        let delayed = TerrainLayer { _ in
            calls += 1
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        delayed.load(descriptor, revision: 1, parent: parent, scope: nil) { precondition($0 == nil) }
        try await until { calls == 1 }
        delayed.load(descriptor, revision: 2, parent: parent, scope: nil) { precondition($0 == nil) }
        precondition(calls == 1)
        continuation!.resume(returning: Entity())
        try await until { calls == 2 }
        precondition(parent.children.isEmpty)
        delayed.clear()
        continuation!.resume(returning: Entity())
        for _ in 0..<10 { await Task.yield() }
        precondition(parent.children.isEmpty)
        var warning: String?
        let failing = TerrainLayer { _ in throw CocoaError(.fileReadCorruptFile) }
        failing.load(descriptor, revision: 1, parent: parent, scope: nil) { warning = $0 }
        try await until { warning != nil }
        precondition(parent.children.isEmpty)
        print("PASS: serialized loads, stale package rejection, cancellation/teardown, nonfatal load failure")
        guard CommandLine.arguments.count == 2 else { fatalError("Pass the packaged fixture USDZ") }
        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let realLayer = TerrainLayer()
        realLayer.updateNavigation(navigation)
        var realWarning: String?
        realLayer.load(TerrainDescriptor(url: fixtureURL, placement: descriptor.placement),
                       revision: 3, parent: parent, scope: nil) { realWarning = $0 }
        try await until { !parent.children.isEmpty || realWarning != nil }
        precondition(realWarning == nil)
        let bounds = parent.visualBounds(relativeTo: parent)
        precondition(simd_distance(bounds.center, SIMD3<Float>(16, 13.5, -2)) < 0.001,
                     "USD meters/Y-up/import transform must be applied exactly once: \(bounds.center)")
        realLayer.clear()
        let unavailable = TerrainLayer()
        var unavailableWarning: String?
        unavailable.load(missing.models[0].terrain, revision: 4, parent: parent, scope: nil) { unavailableWarning = $0 }
        try await until { unavailableWarning != nil }
        precondition(parent.children.isEmpty)
        print("PASS: real USDZ load, Y-up/meters/root-transform fixture, actual missing-file recovery")
        print("All terrain checks passed.")
    }

    @MainActor
    static func until(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        fatalError("Timed out waiting for terrain load")
    }
}
