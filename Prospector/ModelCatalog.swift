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
    let stateURL: URL?
    let category: String?
    let startPose: ViewerPose?

    init(
        id: String,
        displayName: String,
        source: ModelSource,
        stateURL: URL? = nil,
        category: String? = nil,
        startPose: ViewerPose? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.source = source
        self.stateURL = stateURL
        self.category = category
        self.startPose = startPose
    }

    init(
        id: String,
        displayName: String,
        resourceName: String,
        category: String? = nil,
        startPose: ViewerPose? = nil
    ) {
        self.init(
            id: id,
            displayName: displayName,
            source: .bundled(resourceName: resourceName),
            stateURL: nil,
            category: category,
            startPose: startPose
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
    private(set) var persistenceWarning: String?
    private(set) var isOpeningDocument = false
    private(set) var catalogRevision = 0
    private(set) var poseResetRevision = 0
    private(set) var savedLocations: [SavedLocation] = []

    var resumeLastPositions: Bool {
        didSet {
            UserDefaults.standard.set(resumeLastPositions, forKey: Self.resumePreferenceKey)
        }
    }

    var selectedModel: ModelDescriptor {
        didSet {
            guard selectedModel != oldValue else { return }
            loadState = .idle
            refreshSavedLocations()
            Task {
                await flushPositionPersistence()
            }
        }
    }

    var loadState: ModelLoadState = .idle

    @ObservationIgnored private var documentAccess: SecurityScopedResource?
    @ObservationIgnored private var positionPersistence: PositionPersistenceCoordinator?
    @ObservationIgnored private var openRequestID = UUID()

    init(
        models: [ModelDescriptor] = ModelCatalog.models,
        selectedModel: ModelDescriptor = ModelCatalog.defaultModel
    ) {
        self.models = models
        self.selectedModel = selectedModel
        resumeLastPositions = UserDefaults.standard.object(forKey: Self.resumePreferenceKey) as? Bool ?? true
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

            await flushPositionPersistence()
            guard requestID == openRequestID, !Task.isCancelled else { return }

            let persistence = PositionPersistenceCoordinator(
                models: document.models,
                initialStates: document.modelStates,
                onWarning: { [weak self] warning in
                    self?.persistenceWarning = warning
                }
            )
            models = document.models
            positionPersistence = persistence
            selectedModel = document.defaultModel
            refreshSavedLocations()
            documentName = document.name
            documentAccess = document.securityScope
            persistenceWarning = document.stateWarning
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

    func recordPose(_ pose: ViewerPose, for model: ModelDescriptor) {
        guard models.contains(model) else { return }
        positionPersistence?.record(pose: pose, for: model.id)
    }

    func poseForLoading(_ model: ModelDescriptor) -> ViewerPose {
        if resumeLastPositions,
           let persistedPose = positionPersistence?.pose(for: model.id) {
            return persistedPose
        }

        return model.startPose ?? .origin
    }

    func requestResetToStartingPosition() {
        poseResetRevision += 1
    }

    @discardableResult
    func addSavedLocation(position: SIMD3<Float>, for model: ModelDescriptor) -> SavedLocation? {
        guard model == selectedModel else { return nil }
        let location = positionPersistence?.addLocation(
            position: ViewerPosition(position),
            for: model.id
        )
        refreshSavedLocations()
        return location
    }

    func deleteSavedLocation(_ location: SavedLocation, for model: ModelDescriptor) {
        guard model == selectedModel else { return }
        positionPersistence?.deleteLocation(id: location.id, for: model.id)
        refreshSavedLocations()
    }

    func flushPositionPersistence() async {
        guard let positionPersistence else { return }

        if let warning = await positionPersistence.flush() {
            persistenceWarning = warning
        }
    }

    private static let resumePreferenceKey = "resumeLastPositions"

    private func refreshSavedLocations() {
        savedLocations = positionPersistence?.locations(for: selectedModel.id) ?? []
    }
}
