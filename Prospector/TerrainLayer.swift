import Foundation
import RealityKit

/// A single optional visual layer. Loads are serialized even if RealityKit does
/// not immediately stop decoding on cancellation. No collision or gesture setup.
@MainActor
final class TerrainLayer {
    private let loadEntity: @MainActor (URL) async throws -> Entity

    init(loadEntity: @escaping @MainActor (URL) async throws -> Entity = { try await Entity(contentsOf: $0) }) {
        self.loadEntity = loadEntity
    }

    private var task: Task<Void, Never>?
    private var requestID = UUID()
    private var assetURL: URL?
    private var packageRevision: Int?
    private var root: Entity?
    private var placementRoot: Entity?
    private var navigationTransform = Transform()

    func updateNavigation(_ transform: Transform) {
        navigationTransform = transform
        root?.transform = transform
    }

    func prepare(for descriptor: TerrainDescriptor?, revision: Int) {
        requestID = UUID()
        task?.cancel()
        if descriptor?.url != assetURL || revision != packageRevision || descriptor == nil {
            detach()
        }
        root?.isEnabled = false
    }

    func load(
        _ descriptor: TerrainDescriptor?, revision: Int, parent: Entity,
        scope: SecurityScopedResource?, warning: @escaping (String?) -> Void
    ) {
        prepare(for: descriptor, revision: revision)
        warning(nil)
        guard let descriptor else { return }
        if let root, let placementRoot {
            placementRoot.transform = Self.placementTransform(descriptor.placement)
            root.transform = navigationTransform
            root.isEnabled = true
            return
        }
        let request = requestID
        let previous = task
        task = Task { @MainActor in
            // Keep access to this specific package through uncancellable decoding.
            defer { withExtendedLifetime(scope) {} }
            if let previous { await previous.value }
            guard !Task.isCancelled, request == requestID else { return }
            do {
                let entity = try await loadEntity(descriptor.url)
                try Task.checkCancellation()
                guard request == requestID else { return }
                Self.removeInteraction(from: entity)
                let container = Entity()
                container.name = "Surrounding terrain (visual only)"
                let placement = Entity()
                placement.transform = Self.placementTransform(descriptor.placement)
                // Preserve RealityKit's imported root transform exactly once.
                placement.addChild(entity)
                container.addChild(placement)
                container.transform = navigationTransform
                parent.addChild(container)
                root = container
                placementRoot = placement
                assetURL = descriptor.url
                packageRevision = revision
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, request == requestID else { return }
                warning("Surrounding terrain is unavailable. The model remains usable.")
            }
        }
    }

    func clear() {
        requestID = UUID()
        task?.cancel()
        // Keep the canceled task as the serialization barrier until it completes.
        detach()
    }

    private func detach() {
        root?.removeFromParent()
        root = nil
        placementRoot = nil
        assetURL = nil
        packageRevision = nil
    }

    static func placementTransform(_ placement: TerrainPlacement) -> Transform {
        Transform(
            rotation: simd_quatf(angle: placement.yawRadians, axis: SIMD3<Float>(0, 1, 0)),
            translation: SIMD3<Float>(placement.translationMeters[0], placement.translationMeters[1], placement.translationMeters[2])
        )
    }

    static func removeInteraction(from entity: Entity) {
        entity.components.remove(CollisionComponent.self)
        entity.components.remove(InputTargetComponent.self)
        entity.components.remove(PhysicsBodyComponent.self)
        entity.components.remove(PhysicsMotionComponent.self)
        for child in entity.children { removeInteraction(from: child) }
    }
}
