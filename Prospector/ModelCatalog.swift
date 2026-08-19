//
//  ModelCatalog.swift
//  Prospector
//

import Foundation
import Observation

enum ModelSource: Hashable, Sendable {
    case bundled(resourceName: String)
    case file(URL)
}

struct ModelDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let source: ModelSource
    let category: String?

    init(
        id: String,
        displayName: String,
        source: ModelSource,
        category: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.source = source
        self.category = category
    }

    init(
        id: String,
        displayName: String,
        resourceName: String,
        category: String? = nil
    ) {
        self.init(
            id: id,
            displayName: displayName,
            source: .bundled(resourceName: resourceName),
            category: category
        )
    }
}

enum ModelCatalog {
    static let models: [ModelDescriptor] = [
        ModelDescriptor(
            id: "example-model",
            displayName: "Example Model",
            resourceName: "YourModelName"
        ),
    ]

    static let defaultModel = models[0]
}

enum ModelLoadState: Equatable {
    case idle
    case loading(modelID: ModelDescriptor.ID)
    case loaded(modelID: ModelDescriptor.ID)
    case failed(modelID: ModelDescriptor.ID, message: String)
}

@MainActor
@Observable
final class ModelSelection {
    private(set) var models: [ModelDescriptor]
    private(set) var documentName: String?
    private(set) var documentError: String?
    private(set) var isOpeningDocument = false
    private(set) var catalogRevision = 0

    var selectedModel: ModelDescriptor {
        didSet {
            guard selectedModel != oldValue else { return }
            loadState = .idle
        }
    }

    var loadState: ModelLoadState = .idle

    @ObservationIgnored private var documentAccess: SecurityScopedResource?
    @ObservationIgnored private var openRequestID = UUID()

    init(
        models: [ModelDescriptor] = ModelCatalog.models,
        selectedModel: ModelDescriptor = ModelCatalog.defaultModel
    ) {
        self.models = models
        self.selectedModel = selectedModel
    }

    func openPackage(at url: URL) async {
        let requestID = UUID()
        openRequestID = requestID
        isOpeningDocument = true
        documentError = nil

        do {
            let document = try await Task.detached(priority: .userInitiated) {
                try ProspectorDocumentLoader.load(from: url)
            }.value

            guard requestID == openRequestID, !Task.isCancelled else { return }

            models = document.models
            selectedModel = document.defaultModel
            documentName = document.name
            documentAccess = document.securityScope
            catalogRevision += 1
            loadState = .idle
            isOpeningDocument = false
        } catch is CancellationError {
            guard requestID == openRequestID else { return }
            isOpeningDocument = false
        } catch {
            guard requestID == openRequestID else { return }
            documentError = error.localizedDescription
            isOpeningDocument = false
        }
    }
}
