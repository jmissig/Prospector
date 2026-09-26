import Foundation
import RealityKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main
struct PanoramaChecks {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func config(_ fields: [String: Any]) throws -> LandscapeConfiguration {
            try JSONDecoder().decode(LandscapeConfiguration.self, from: JSONSerialization.data(withJSONObject: fields))
        }
        let base: [String: Any] = ["projection": "equirectangular", "texturePath": "test.png",
            "referencePositionMeters": [10, 20, 30], "radiusMeters": 2000]
        func environment(_ changes: [String: Any] = [:]) throws -> LandscapeEnvironment {
            try LandscapeEnvironment(configuration: config(base.merging(changes) { _, new in new }), packageURL: root)
        }
        func rejects(_ action: () throws -> Void) {
            do { try action(); fatalError("Expected rejection") } catch {}
        }
        func near(_ actual: SIMD3<Float>, _ expected: SIMD3<Float>) {
            precondition(simd_distance(actual, expected) < 0.00001, "\(actual) != \(expected)")
        }
        let legacy = try config(["texturePath": "old-missing.png", "referencePositionMeters": [0,0,0],
                                 "landmarkUV": [0.42,0.2], "landmarkOffsetMeters": [0,300,-2000]])
        let legacyResult = try LandscapeEnvironment.resolve(legacy, packageURL: root)
        let absentResult = try LandscapeEnvironment.resolve(nil, packageURL: root)
        let meadowResult = try LandscapeEnvironment.resolve(config(["projection":"meadow"]), packageURL: root)
        precondition(legacyResult == nil && absentResult == nil && meadowResult == nil)
        rejects { _ = try config(["projection":"landmark"]) }
        rejects { _ = try config(["projection":"typo"]) }
        rejects { _ = try environment(["texturePath":"../escape.png"]) }
        rejects { _ = try environment(["radiusMeters":0]) }
        rejects { _ = try environment(["referencePositionMeters":[0,1]]) }
        let outside = root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + "-outside.png")
        try Data().write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.png"), withDestinationURL: outside)
        rejects { _ = try environment(["texturePath":"link.png"]) }
        print("PASS: missing/legacy mode and explicit Meadow fallback; unknown mode, radius, position and unsafe paths rejected")

        let env = try environment()
        near(env.direction(u:0.5,v:0), [0,1,0])
        near(env.direction(u:0.5,v:1), [0,-1,0])
        near(env.direction(u:0.5,v:0.5), [0,0,-1])
        near(env.direction(u:0.75,v:0.5), [1,0,0])
        near(env.direction(u:0.25,v:0.5), [-1,0,0])
        near(env.direction(u:0,v:0.5), [0,0,1])
        near(env.direction(u:1,v:0.5), env.direction(u:0,v:0.5))
        let positiveYaw = try environment(["yawOffsetRadians":Float.pi/2])
        let negativeYaw = try environment(["yawOffsetRadians":-Float.pi/2])
        near(positiveYaw.direction(u:0.5,v:0.5), [1,0,0])
        near(negativeYaw.direction(u:0.5,v:0.5), [-1,0,0])
        let irrelevantLandmark = try environment(["landmarkUV":[0.7,0.05], "landmarkOffsetMeters":[1,900,2]])
        for v: Float in [0,0.125,0.25,0.5,0.75,0.875,1] {
            let direction = env.direction(u:0.5,v:v)
            precondition(abs(asin(direction.y) - (.pi/2-v * .pi)) < 0.00001)
            near(direction, irrelevantLandmark.direction(u:0.5,v:v))
        }
        print("PASS: horizon, poles, linear latitude, seam, east/west handedness, ±yaw and landmark independence")

        // Exercise the actual manifest decoder, not just standalone configuration.
        try Data().write(to: root.appendingPathComponent("House.usdz"))
        let package = root.appendingPathComponent("Synthetic.prospector")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data().write(to: package.appendingPathComponent("House.usdz"))
        for fields in [base, ["landmarkUV":[0.5,0.1]], ["projection":"meadow"]] {
            let manifest: [String:Any] = ["formatVersion":1,"name":"Synthetic","defaultModelID":"house",
                "models":[["id":"house","name":"House","path":"House.usdz","environment":fields]]]
            try JSONSerialization.data(withJSONObject:manifest).write(to:package.appendingPathComponent("manifest.json"))
            let document = try ProspectorDocumentLoader.load(from: package)
            precondition((document.defaultModel.environment != nil) == (fields["projection"] as? String == "equirectangular"))
        }
        print("PASS: real package manifest decoding for new, legacy, and Meadow environments")

        for width in [4096,8192] {
            let name = "panorama-\(width).png"
            try writeImage(width:width, height:width/2, to:root.appendingPathComponent(name))
            let textureEnvironment = try environment(["texturePath":name])
            var report: LandscapeTextureReport?
            let entity = try await textureEnvironment.makeEntity { report = $0 }
            guard let report else { fatalError("Missing texture report") }
            precondition(report.sourceWidth == width && report.sourceHeight == width/2)
            precondition(report.loadedWidth >= 4096 && report.loadedHeight >= 2048)
            precondition(entity.components[CollisionComponent.self] == nil)
            precondition(entity.components[InputTargetComponent.self] == nil)
            let bounds = entity.visualBounds(relativeTo:entity)
            near(bounds.center, env.reference)
            precondition(abs(bounds.extents.x - 4000) < 0.001)
            print("PASS: actual RealityKit texture/entity load — \(report.summary); visual-only shell centered at reference")
        }
        try Data("not an image".utf8).write(to:root.appendingPathComponent("test.png"))
        do { _ = try await env.loadTexture(); fatalError("Expected corrupt-image failure") } catch {}
        let corrupt = try await env.loadBackdrop()
        precondition(corrupt.entity == nil && corrupt.status.contains("Using Meadow"))
        let missing = try await environment(["texturePath":"missing.png"]).loadBackdrop()
        precondition(missing.entity == nil && missing.status.contains("Using Meadow"))
        try writeImage(width:2048,height:1024,to:root.appendingPathComponent("small.png"))
        let small = try await environment(["texturePath":"small.png"]).loadBackdrop()
        precondition(small.entity == nil && small.status.contains("2048×1024"))
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await env.loadBackdrop()
        }
        do { _ = try await cancelled.value; fatalError("Cancellation must propagate") }
        catch is CancellationError {} // Do not substitute Meadow into stale loads.
        for size in [(2048,1024),(4096,4096),(8192,2048)] {
            rejects { try LandscapeEnvironment.validateEquirectangularDimensions(width:size.0,height:size.1) }
        }
        print("PASS: missing/corrupt/sub-4K images select Meadow; non-2:1 rejected; cancellation propagates")
        print("All panorama checks passed on macOS. No headset or simulator runtime verification.")
    }

    static func writeImage(width:Int, height:Int, to url:URL) throws {
        guard let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.setFillColor(CGColor(red:0.1,green:0.4,blue:0.8,alpha:1))
        context.fill(CGRect(x:0,y:0,width:width,height:height))
        context.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1))
        context.fill(CGRect(x:0,y:height/2,width:width,height:8))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
