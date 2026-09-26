import Foundation
import RealityKit

/// Optional, approximate scenery. All positions are in Y-up navigation meters,
/// before the user's movement/yaw, independently of a USDZ's import transform.
struct LandscapeConfiguration: Decodable, Hashable, Sendable {
    let texturePath: String
    let referencePositionMeters: [Float]
    let landmarkOffsetMeters: [Float]
    /// Normalized image coordinates, with (0,0) at the TOP left.
    let landmarkUV: [Float]
}

struct LandscapeEnvironment: Hashable, Sendable {
    let configuration: LandscapeConfiguration
    let textureURL: URL

    init(configuration: LandscapeConfiguration, packageURL: URL) throws {
        let c = configuration
        let path = c.texturePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = packageURL.standardizedFileURL.resolvingSymlinksInPath()
        let url = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard !path.isEmpty, !NSString(string: path).isAbsolutePath,
              url.path.hasPrefix(prefix),
              ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              c.referencePositionMeters.count == 3,
              c.referencePositionMeters.allSatisfy(\.isFinite),
              c.landmarkOffsetMeters.count == 3,
              c.landmarkOffsetMeters.allSatisfy(\.isFinite),
              c.landmarkUV.count == 2,
              c.landmarkUV.allSatisfy({ $0.isFinite && $0 > 0 && $0 < 1 }) else {
            throw ProspectorDocumentError.unreadableManifest("Invalid landscape texture path or calibration.")
        }
        let offset = SIMD3<Float>(c.landmarkOffsetMeters[0], c.landmarkOffsetMeters[1], c.landmarkOffsetMeters[2])
        let distance = simd_length(offset)
        guard distance.isFinite, distance >= 100, distance <= 100_000,
              hypot(offset.x, offset.z) > 1 else {
            throw ProspectorDocumentError.unreadableManifest("Landscape distance must be between 100 and 100,000 meters, with a horizontal landmark direction.")
        }
        self.configuration = c
        self.textureURL = url
    }

    @MainActor
    func makeEntity() async throws -> Entity {
        let texture = try await TextureResource(contentsOf: textureURL)
        try Task.checkCancellation()
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        material.faceCulling = .none

        let c = configuration
        let reference = SIMD3<Float>(c.referencePositionMeters[0], c.referencePositionMeters[1], c.referencePositionMeters[2])
        let offset = SIMD3<Float>(c.landmarkOffsetMeters[0], c.landmarkOffsetMeters[1], c.landmarkOffsetMeters[2])
        let radius = simd_length(offset)
        let bearing = atan2(offset.x, -offset.z)
        let elevation = asin(offset.y / radius)
        let anchorU = c.landmarkUV[0], anchorV = c.landmarkUV[1]
        // Include the exact calibration row and column; no interpolation error at
        // the landmark. Remaining pixels are explicitly approximate spherical scenery.
        let us = Array(Set((0...256).map { Float($0) / 256 } + [anchorU])).sorted()
        let vs = Array(Set((0...128).map { Float($0) / 128 } + [anchorV])).sorted()
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        for v in vs {
            let latitude: Float
            if v <= anchorV {
                latitude = .pi / 2 + (elevation - .pi / 2) * v / anchorV
            } else {
                latitude = elevation + (-.pi / 2 - elevation) * (v - anchorV) / (1 - anchorV)
            }
            for u in us {
                let azimuth = bearing + (u - anchorU) * 2 * .pi
                let direction = SIMD3<Float>(sin(azimuth) * cos(latitude), sin(latitude), -cos(azimuth) * cos(latitude))
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
        var mesh = MeshDescriptor(name: "Calibrated landscape")
        mesh.positions = MeshBuffers.Positions(positions)
        mesh.normals = MeshBuffers.Normals(normals)
        mesh.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        mesh.primitives = .triangles(indices)
        let entity = ModelEntity(mesh: try MeshResource.generate(from: [mesh]), materials: [material])
        entity.name = "Package landscape (non-collidable)"
        return entity
    }
}
