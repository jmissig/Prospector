import Foundation
import RealityKit
import ImageIO
import OSLog

/// Optional, approximate scenery. All positions are in Y-up navigation meters,
/// before the user's movement/yaw, independently of a USDZ's import transform.
enum LandscapeProjection: String, Decodable, Hashable, Sendable {
    case meadow
    case equirectangular
}

struct LandscapeConfiguration: Decodable, Hashable, Sendable {
    let projection: LandscapeProjection?
    let texturePath: String?
    let referencePositionMeters: [Float]?
    let yawOffsetRadians: Float?
    let radiusMeters: Float?

    var resolvedProjection: LandscapeProjection { projection ?? .meadow }
    var yaw: Float { yawOffsetRadians ?? 0 }
}

struct LandscapeEnvironment: Hashable, Sendable {
    let configuration: LandscapeConfiguration
    let textureURL: URL
    let radius: Float
    let reference: SIMD3<Float>
    private let packageRoot: URL

    /// Missing mode (including old landmark manifests) explicitly selects Meadow.
    static func resolve(_ configuration: LandscapeConfiguration?, packageURL: URL) throws -> LandscapeEnvironment? {
        guard let configuration, configuration.resolvedProjection == .equirectangular else { return nil }
        return try LandscapeEnvironment(configuration: configuration, packageURL: packageURL)
    }

    init(configuration: LandscapeConfiguration, packageURL: URL) throws {
        let c = configuration
        guard c.resolvedProjection == .equirectangular,
              let position = c.referencePositionMeters, position.count == 3,
              position.allSatisfy(\.isFinite), c.yaw.isFinite,
              let radius = c.radiusMeters, radius.isFinite, radius >= 100, radius <= 100_000,
              let path = c.texturePath else {
            throw ProspectorDocumentError.unreadableManifest("Equirectangular environments require a texturePath, finite referencePositionMeters/yaw, and radiusMeters between 100 and 100,000.")
        }
        self.radius = radius
        packageRoot = packageURL.standardizedFileURL.resolvingSymlinksInPath()
        reference = SIMD3<Float>(position[0], position[1], position[2])
        textureURL = try Self.textureURL(path, in: packageURL)
        self.configuration = c
    }

    private static func textureURL(_ path: String, in packageURL: URL) throws -> URL {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = packageURL.standardizedFileURL.resolvingSymlinksInPath()
        let url = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard !path.isEmpty, !NSString(string: path).isAbsolutePath,
              url.path.hasPrefix(prefix),
              ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()) else {
            throw ProspectorDocumentError.unreadableManifest("Invalid landscape texture path.")
        }
        return url
    }

    /// Image UVs use a top-left origin. Positive azimuth turns -Z toward +X.
    func direction(u: Float, v: Float) -> SIMD3<Float> {
        let latitude = Float.pi / 2 - v * .pi
        let azimuth = (u - 0.5) * 2 * .pi + configuration.yaw
        return SIMD3<Float>(sin(azimuth) * cos(latitude), sin(latitude), -cos(azimuth) * cos(latitude))
    }

    @MainActor
    func loadTexture() async throws -> (TextureResource, LandscapeTextureReport) {
        try Task.checkCancellation()
        // Recheck containment at load time, including initially dangling symlinks.
        let checkedURL = try Self.textureURL(configuration.texturePath ?? "", in: packageRoot)
        guard (try? checkedURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let source = CGImageSourceCreateWithURL(checkedURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw LandscapeTextureError.invalidImage
        }
        try Self.validateEquirectangularDimensions(width: width, height: height)
        let texture = try await TextureResource(contentsOf: checkedURL)
        try Task.checkCancellation()
        let report = LandscapeTextureReport(sourceWidth: width, sourceHeight: height,
            loadedWidth: texture.width, loadedHeight: texture.height)
        Logger(subsystem: "Prospector", category: "Environment").info("\(report.summary, privacy: .public)")
        try Self.validateEquirectangularDimensions(width: texture.width, height: texture.height)
        return (texture, report)
    }

    static func validateEquirectangularDimensions(width: Int, height: Int) throws {
        guard width >= 4096, height >= 2048, width == 2 * height else {
            throw LandscapeTextureError.dimensions(width, height)
        }
    }

    /// A failed optional photograph must not prevent the house from loading.
    /// A nil entity lets the existing immersive lifecycle enable bundled Meadow.
    @MainActor
    func loadBackdrop() async throws -> (entity: Entity?, status: String) {
        var status = ""
        do {
            let entity = try await makeEntity { status = $0.summary }
            return (entity, status)
        } catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            return (nil, "Using Meadow: panorama unavailable. \(error.localizedDescription)")
        }
    }

    @MainActor
    func makeEntity(reportTexture: (LandscapeTextureReport) -> Void = { _ in }) async throws -> Entity {
        let (texture, report) = try await loadTexture()
        reportTexture(report)
        try Task.checkCancellation()
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        material.faceCulling = .none

        let us = (0...256).map { Float($0) / 256 }
        let vs = (0...128).map { Float($0) / 128 }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        for v in vs {
            for u in us {
                let direction = direction(u: u, v: v)
                positions.append(reference + radius * direction)
                normals.append(-direction)
                uvs.append(SIMD2<Float>(u, 1 - v))
            }
        }
        for row in 0..<(vs.count - 1) {
            for column in 0..<(us.count - 1) {
                let a = UInt32(row * us.count + column)
                let b = a + 1, d = a + UInt32(us.count), e = d + 1
                indices += [a, d, b, b, d, e]
            }
        }
        var mesh = MeshDescriptor(name: "Equirectangular landscape")
        mesh.positions = MeshBuffers.Positions(positions)
        mesh.normals = MeshBuffers.Normals(normals)
        mesh.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        mesh.primitives = .triangles(indices)
        let entity = ModelEntity(mesh: try MeshResource.generate(from: [mesh]), materials: [material])
        entity.name = "Package landscape (non-collidable)"
        return entity
    }
}

struct LandscapeTextureReport: Equatable, Sendable {
    let sourceWidth: Int
    let sourceHeight: Int
    let loadedWidth: Int
    let loadedHeight: Int
    var dimensionsChanged: Bool { sourceWidth != loadedWidth || sourceHeight != loadedHeight }
    var summary: String {
        "Panorama: source \(sourceWidth)×\(sourceHeight), loaded \(loadedWidth)×\(loadedHeight)"
            + (dimensionsChanged ? " — runtime dimensions changed" : "")
    }
}

private enum LandscapeTextureError: LocalizedError {
    case invalidImage
    case dimensions(Int, Int)
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not read panorama image dimensions."
        case .dimensions(let w, let h): return "Equirectangular panorama is \(w)×\(h); requires 2:1 and at least 4096×2048, including after loading."
        }
    }
}
