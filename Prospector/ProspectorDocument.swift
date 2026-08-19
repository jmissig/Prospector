//
//  ProspectorDocument.swift
//  Prospector
//

import Foundation

struct ProspectorManifest: Decodable {
    let formatVersion: Int
    let name: String
    let defaultModelID: String
    let models: [ManifestModel]

    struct ManifestModel: Decodable {
        let id: String
        let name: String
        let path: String
        let category: String?
        let startPose: ViewerPose?
    }
}

struct OpenedProspectorDocument: @unchecked Sendable {
    let name: String
    let models: [ModelDescriptor]
    let defaultModel: ModelDescriptor
    let packageURL: URL
    let state: ProspectorState?
    let stateWarning: String?
    let stateWritesEnabled: Bool
    let securityScope: SecurityScopedResource
}

final class SecurityScopedResource: @unchecked Sendable {
    let url: URL
    private let didStartAccessing: Bool

    init(url: URL) {
        self.url = url
        didStartAccessing = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if didStartAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

enum ProspectorDocumentError: LocalizedError {
    case invalidPackageExtension
    case packageIsNotDirectory
    case missingManifest
    case unreadableManifest(String)
    case unsupportedFormatVersion(Int)
    case emptyDocumentName
    case noModels
    case emptyModelField(modelID: String, field: String)
    case duplicateModelID(String)
    case invalidDefaultModelID(String)
    case invalidModelPath(modelID: String)
    case unsupportedModelType(modelID: String)
    case missingModel(modelID: String)

    var errorDescription: String? {
        switch self {
        case .invalidPackageExtension:
            return "Choose a .prospector package."
        case .packageIsNotDirectory:
            return "This .prospector item is not a document package."
        case .missingManifest:
            return "The package does not contain manifest.json."
        case .unreadableManifest(let message):
            return "The manifest could not be read: \(message)"
        case .unsupportedFormatVersion(let version):
            return "Manifest format version \(version) is not supported."
        case .emptyDocumentName:
            return "The manifest name cannot be empty."
        case .noModels:
            return "The manifest must contain at least one model."
        case .emptyModelField(let modelID, let field):
            return "Model “\(modelID)” has an empty \(field)."
        case .duplicateModelID(let modelID):
            return "The model ID “\(modelID)” is used more than once."
        case .invalidDefaultModelID(let modelID):
            return "The default model “\(modelID)” is not in the manifest."
        case .invalidModelPath(let modelID):
            return "Model “\(modelID)” has a path outside the package."
        case .unsupportedModelType(let modelID):
            return "Model “\(modelID)” must reference a .usdz file."
        case .missingModel(let modelID):
            return "The USDZ file for model “\(modelID)” is missing."
        }
    }
}

enum ProspectorDocumentLoader {
    static let packageExtension = "prospector"
    static let manifestFilename = "manifest.json"
    static let stateFilename = "state.json"
    static let supportedFormatVersion = 1

    static func load(from packageURL: URL) throws -> OpenedProspectorDocument {
        guard packageURL.pathExtension.lowercased() == packageExtension else {
            throw ProspectorDocumentError.invalidPackageExtension
        }

        let securityScope = SecurityScopedResource(url: packageURL)
        var coordinationError: NSError?
        var result: Result<OpenedProspectorDocument, Error>?

        NSFileCoordinator().coordinate(
            readingItemAt: packageURL,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result {
                try decodePackage(at: coordinatedURL, securityScope: securityScope)
            }
        }

        if let coordinationError {
            throw ProspectorDocumentError.unreadableManifest(coordinationError.localizedDescription)
        }

        guard let result else {
            throw ProspectorDocumentError.unreadableManifest("File coordination did not return a result.")
        }

        return try result.get()
    }

    private static func decodePackage(
        at packageURL: URL,
        securityScope: SecurityScopedResource
    ) throws -> OpenedProspectorDocument {
        let packageValues = try packageURL.resourceValues(forKeys: [.isDirectoryKey])
        guard packageValues.isDirectory == true else {
            throw ProspectorDocumentError.packageIsNotDirectory
        }

        let manifestURL = packageURL.appendingPathComponent(manifestFilename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ProspectorDocumentError.missingManifest
        }

        let manifest: ProspectorManifest
        do {
            let data = try Data(contentsOf: manifestURL)
            manifest = try JSONDecoder().decode(ProspectorManifest.self, from: data)
        } catch {
            throw ProspectorDocumentError.unreadableManifest(error.localizedDescription)
        }

        guard manifest.formatVersion == supportedFormatVersion else {
            throw ProspectorDocumentError.unsupportedFormatVersion(manifest.formatVersion)
        }

        let documentName = manifest.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !documentName.isEmpty else {
            throw ProspectorDocumentError.emptyDocumentName
        }
        guard !manifest.models.isEmpty else {
            throw ProspectorDocumentError.noModels
        }

        var modelIDs = Set<String>()
        let models = try manifest.models.map { model -> ModelDescriptor in
            let modelID = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelName = model.name.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !modelID.isEmpty else {
                throw ProspectorDocumentError.emptyModelField(modelID: "(unknown)", field: "id")
            }
            guard !modelName.isEmpty else {
                throw ProspectorDocumentError.emptyModelField(modelID: modelID, field: "name")
            }
            guard modelIDs.insert(modelID).inserted else {
                throw ProspectorDocumentError.duplicateModelID(modelID)
            }

            let modelURL = try validatedModelURL(
                for: model.path,
                modelID: modelID,
                packageURL: packageURL
            )

            return ModelDescriptor(
                id: modelID,
                displayName: modelName,
                source: .file(modelURL),
                category: model.category,
                startPose: try validatedPose(model.startPose, modelID: modelID, source: "manifest")
            )
        }

        let defaultModelID = manifest.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let defaultModel = models.first(where: { $0.id == defaultModelID }) else {
            throw ProspectorDocumentError.invalidDefaultModelID(defaultModelID)
        }

        let stateResult = loadState(
            at: packageURL,
            validModelIDs: Set(models.map(\.id))
        )

        return OpenedProspectorDocument(
            name: documentName,
            models: models,
            defaultModel: defaultModel,
            packageURL: packageURL,
            state: stateResult.state,
            stateWarning: stateResult.warning,
            stateWritesEnabled: stateResult.writesEnabled,
            securityScope: securityScope
        )
    }

    private static func loadState(
        at packageURL: URL,
        validModelIDs: Set<String>
    ) -> (state: ProspectorState?, warning: String?, writesEnabled: Bool) {
        let stateURL = packageURL.appendingPathComponent(stateFilename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return (nil, nil, true)
        }

        do {
            let data = try Data(contentsOf: stateURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(ProspectorState.self, from: data)
            try validate(state: state, validModelIDs: validModelIDs)
            return (state, nil, true)
        } catch {
            let message = error.localizedDescription
            return (
                nil,
                "state.json could not be used: \(message)",
                false
            )
        }
    }

    private static func validate(
        state: ProspectorState,
        validModelIDs: Set<String>
    ) throws {
        guard state.formatVersion == ProspectorState.supportedFormatVersion else {
            throw ProspectorStateError.unsupportedFormatVersion(state.formatVersion)
        }
        guard validModelIDs.contains(state.currentModelID) else {
            throw ProspectorStateError.invalidCurrentModelID(state.currentModelID)
        }

        var stateModelIDs = Set<String>()
        for modelState in state.modelStates {
            guard stateModelIDs.insert(modelState.modelID).inserted else {
                throw ProspectorStateError.duplicateModelID(modelState.modelID)
            }
            guard validModelIDs.contains(modelState.modelID),
                  modelState.pose.isFinite else {
                throw ProspectorStateError.invalidPose(modelState.modelID)
            }
        }
    }

    private static func validatedPose(
        _ pose: ViewerPose?,
        modelID: String,
        source: String
    ) throws -> ViewerPose? {
        guard let pose else { return nil }
        guard pose.isFinite else {
            throw ProspectorDocumentError.unreadableManifest(
                "Model “\(modelID)” has an invalid \(source) start pose."
            )
        }
        return pose
    }

    private static func validatedModelURL(
        for path: String,
        modelID: String,
        packageURL: URL
    ) throws -> URL {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty,
              !NSString(string: trimmedPath).isAbsolutePath else {
            throw ProspectorDocumentError.invalidModelPath(modelID: modelID)
        }

        let packageRoot = packageURL.standardizedFileURL.resolvingSymlinksInPath()
        let modelURL = packageURL
            .appendingPathComponent(trimmedPath, isDirectory: false)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let packagePrefix = packageRoot.path.hasSuffix("/") ? packageRoot.path : packageRoot.path + "/"

        guard modelURL.path.hasPrefix(packagePrefix) else {
            throw ProspectorDocumentError.invalidModelPath(modelID: modelID)
        }
        guard modelURL.pathExtension.lowercased() == "usdz" else {
            throw ProspectorDocumentError.unsupportedModelType(modelID: modelID)
        }

        let values = try? modelURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true else {
            throw ProspectorDocumentError.missingModel(modelID: modelID)
        }

        return modelURL
    }
}
