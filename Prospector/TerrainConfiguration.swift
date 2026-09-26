import Foundation

struct TerrainAsset: Decodable, Hashable, Sendable {
    let id: String
    let path: String
}

struct TerrainPlacement: Decodable, Hashable, Sendable {
    let translationMeters: [Float]
    let yawRadians: Float

    static let identity = TerrainPlacement(translationMeters: [0, 0, 0], yawRadians: 0)

    var isValid: Bool {
        translationMeters.count == 3 && translationMeters.allSatisfy(\.isFinite) && yawRadians.isFinite
    }
}

struct TerrainDescriptor: Hashable, Sendable {
    let url: URL
    let placement: TerrainPlacement
}

/// Validates configuration, not availability: a missing optional asset is handled
/// after house loading, without preventing the package from opening.
enum TerrainConfiguration {
    static func resolveAssets(_ assets: [TerrainAsset], packageURL: URL) throws -> [String: URL] {
        let root = packageURL.standardizedFileURL.resolvingSymlinksInPath()
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var result: [String: URL] = [:]
        for asset in assets {
            let id = asset.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let path = asset.path.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
            guard !id.isEmpty, result[id] == nil, !path.isEmpty,
                  !NSString(string: path).isAbsolutePath,
                  !path.split(separator: "/").contains(".."),
                  url.path.hasPrefix(prefix), url.pathExtension.lowercased() == "usdz" else {
                throw ConfigurationError.invalidAsset
            }
            result[id] = url
        }
        return result
    }

    static func descriptor(id: String?, placement: TerrainPlacement?, assets: [String: URL]) throws -> TerrainDescriptor? {
        guard let id else {
            guard placement == nil else { throw ConfigurationError.invalidPlacement }
            return nil
        }
        guard let url = assets[id.trimmingCharacters(in: .whitespacesAndNewlines)] else {
            throw ConfigurationError.unknownAsset
        }
        let placement = placement ?? .identity
        guard placement.isValid else { throw ConfigurationError.invalidPlacement }
        return TerrainDescriptor(url: url, placement: placement)
    }

    enum ConfigurationError: LocalizedError {
        case invalidAsset, unknownAsset, invalidPlacement
        var errorDescription: String? {
            switch self {
            case .invalidAsset: "Terrain must have a unique nonempty ID and a contained relative USDZ path."
            case .unknownAsset: "The model refers to an unknown terrain ID."
            case .invalidPlacement: "Terrain placement requires a terrain ID, three finite meter coordinates, and a finite yaw."
            }
        }
    }
}
