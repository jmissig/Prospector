//
//  ImmersiveView.swift
//  Prospector
//
//  Created by Christian Selig on 2025-08-20.
//

import SwiftUI
import RealityKit
import ARKit

struct ImmersiveView: View {
    let modelSelection: ModelSelection

    @StateObject private var controllerManager = GameControllerManager()
    @State private var contentRoot: Entity?
    @State private var isRealityViewReady = false
    @State private var sceneEntity: Entity?
    @State private var loadedModel: ModelDescriptor?
    @State private var updateSubscription: EventSubscription?
    @State private var worldTracking: WorldTrackingProvider?
    @State private var handTracking: HandTrackingProvider?
    @State private var arkitStartupTask: Task<Void, Never>?
    @State private var handTrackingTask: Task<Void, Never>?
    @State private var modelLoadingTask: Task<Void, Never>?
    @State private var modelLoadRequestID = UUID()
    @State private var arkitSession = ARKitSession()
    @State private var isImmersiveActive = false
    @State private var isContentVisible: Bool = true
    @State private var leftPinchActive: Bool = false
    @State private var rightPinchActive: Bool = false
    @State private var leftPinchStartTime: TimeInterval?
    @State private var rightPinchStartTime: TimeInterval?
    @State private var baseRotation: simd_quatf?
    @State private var navigationRuntime = NavigationRuntime()
    @State private var modeCueText: String?
    @State private var modeCueTask: Task<Void, Never>?
    
    let movementSpeed: Float = 2.0
    let speedModeMultiplier: Float = 6.0
    let heightSpeed: Float = 1.5
    let lookRotationSpeed: Float = 2.25
    let defaultHeight: Float = 0
    let terrainProbeHeight: Float = 1.5
    let pinchOnDistance: Float = 0.02
    let pinchOffDistance: Float = 0.03
    let pinchHoldDuration: TimeInterval = 0.5
    
    var body: some View {
        RealityView { content in
            let root = Entity()
            content.add(root)
            contentRoot = root
            isImmersiveActive = true
            isRealityViewReady = true
            
            // Create environment sphere
            if let exrURL = Bundle.main.url(forResource: "meadow_2_4k", withExtension: "exr") {
                do {
                    // Load the texture
                    let texture = try await TextureResource(contentsOf: exrURL)
                    
                    // Create material with the texture
                    var material = UnlitMaterial()
                    material.color = .init(texture: .init(texture))
                    
                    // Create a large sphere mesh (inverted to show texture on inside)
                    let sphereMesh = MeshResource.generateSphere(radius: 1000)
                    
                    // Create model entity with inverted sphere
                    let sphereEntity = ModelEntity(mesh: sphereMesh, materials: [material])
                    
                    // Scale the sphere negatively on one axis to invert normals (show inside)
                    sphereEntity.scale = SIMD3<Float>(-1, 1, 1)

                    content.add(sphereEntity)
                } catch {
                    print("Failed to load environment texture: \(error)")
                }
            }
            
            startARKit()
            
            updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                guard let entity = sceneEntity else { return }
                
                if entity.isEnabled != isContentVisible {
                    entity.isEnabled = isContentVisible
                }
                
                let deltaTime = Float(event.deltaTime)
                let movement = controllerManager.movementVector
                let lookInput = controllerManager.lookVector
                let heightAdjust = controllerManager.heightAdjustment
                let speedMultiplier = controllerManager.speedModeEnabled ? speedModeMultiplier : 1
                var poseChanged = false
                
                // Get head orientation if available
                var headYaw: Float = 0
                if let worldTracking = worldTracking,
                   let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
                    let deviceTransform = deviceAnchor.originFromAnchorTransform
                    let forward = SIMD3<Float>(deviceTransform.columns.2.x,
                                              deviceTransform.columns.2.y,
                                              deviceTransform.columns.2.z)
                    headYaw = atan2(forward.x, forward.z)
                }
                
                var transform = entity.transform
                
                // Handle height reset
                if controllerManager.shouldResetHeight {
                    navigationRuntime.currentHeight = terrainSurfaceHeight(
                        below: navigationRuntime.playerPosition,
                        in: entity
                    ) ?? defaultHeight
                    navigationRuntime.playerPosition.y = navigationRuntime.currentHeight
                    poseChanged = true
                }
                
                // Handle height adjustment from shoulder buttons
                if heightAdjust != 0 {
                    navigationRuntime.currentHeight += heightAdjust * heightSpeed * speedMultiplier * deltaTime
                    navigationRuntime.playerPosition.y = navigationRuntime.currentHeight
                    poseChanged = true
                }

                // Handle look rotation from right thumbstick (yaw)
                if lookInput.x != 0 {
                    let yawDelta = -lookInput.x * lookRotationSpeed * deltaTime
                    navigationRuntime.virtualYaw += yawDelta
                    if navigationRuntime.virtualYaw > .pi {
                        navigationRuntime.virtualYaw -= 2 * .pi
                    } else if navigationRuntime.virtualYaw < -.pi {
                        navigationRuntime.virtualYaw += 2 * .pi
                    }
                    poseChanged = true
                }
                
                // Handle horizontal movement
                if movement != .zero {
                    let moveDistance = movementSpeed * speedMultiplier * deltaTime
                    
                    // Apply combined head + virtual yaw to movement vector
                    let combinedYaw = headYaw + navigationRuntime.virtualYaw
                    let cosYaw = cos(combinedYaw)
                    let sinYaw = sin(combinedYaw)
                    
                    // Rotate the movement vector by the head yaw
                    let rotatedX = movement.x * cosYaw - movement.y * sinYaw
                    let rotatedZ = movement.x * sinYaw + movement.y * cosYaw
                    
                    // Apply the rotated movement to the player
                    navigationRuntime.playerPosition.x += rotatedX * moveDistance
                    navigationRuntime.playerPosition.z -= rotatedZ * moveDistance

                    if controllerManager.terrainFollowEnabled,
                       let terrainHeight = terrainSurfaceHeight(
                        below: navigationRuntime.playerPosition,
                        in: entity
                       ) {
                        navigationRuntime.currentHeight = terrainHeight
                        navigationRuntime.playerPosition.y = navigationRuntime.currentHeight
                    }
                    poseChanged = true
                }

                let yawRotation = simd_quatf(
                    angle: -navigationRuntime.virtualYaw,
                    axis: SIMD3<Float>(0, 1, 0)
                )
                let rotatedPosition = simd_act(yawRotation, navigationRuntime.playerPosition)
                transform.translation = -rotatedPosition
                if let baseRotation = baseRotation {
                    transform.rotation = simd_mul(yawRotation, baseRotation)
                } else {
                    transform.rotation = yawRotation
                }
                
                entity.transform = transform

                if poseChanged {
                    recordCurrentPoseIfNeeded()
                } else if navigationRuntime.wasPoseChanging {
                    recordCurrentPose()
                }
                navigationRuntime.wasPoseChanging = poseChanged
            }
        }
        .task(id: ModelLoadRequest(
            model: modelSelection.selectedModel,
            catalogRevision: modelSelection.catalogRevision,
            isRealityViewReady: isRealityViewReady
        )) {
            guard isRealityViewReady else { return }
            await replaceModel(
                modelSelection.selectedModel,
                catalogRevision: modelSelection.catalogRevision
            )
        }
        .overlay(alignment: .top) {
            if let modeCueText {
                Text(modeCueText)
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 40)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .onChange(of: controllerManager.terrainFollowEnabled) { _, isEnabled in
            showModeCue(isEnabled ? "Terrain Follow On" : "Terrain Follow Off")
        }
        .onChange(of: controllerManager.speedModeEnabled) { _, isEnabled in
            showModeCue(isEnabled ? "Speed Mode On" : "Speed Mode Off")
        }
        .onChange(of: modelSelection.poseResetRevision) { _, _ in
            resetToStartingPosition()
        }
        .onDisappear {
            tearDownImmersiveView()
        }
    }

    @MainActor
    private func replaceModel(_ model: ModelDescriptor, catalogRevision: Int) async {
        let previousTask = modelLoadingTask
        previousTask?.cancel()
        if let previousTask {
            await previousTask.value
        }

        guard !Task.isCancelled, isImmersiveActive else { return }

        let requestID = UUID()
        modelLoadRequestID = requestID
        let task = Task { @MainActor in
            await loadModel(model, catalogRevision: catalogRevision)
        }
        modelLoadingTask = task
        await task.value

        if modelLoadRequestID == requestID {
            modelLoadingTask = nil
        }
    }

    @MainActor
    private func loadModel(_ model: ModelDescriptor, catalogRevision: Int) async {
        modelSelection.loadState = .loading(modelID: model.id)

        if let loadedModel {
            modelSelection.recordPose(navigationRuntime.pose, for: loadedModel)
            await modelSelection.flushPositionPersistence()
        }

        guard isCurrentLoad(model, catalogRevision: catalogRevision) else { return }

        unloadCurrentModel()

        do {
            let entity: Entity
            switch model.source {
            case .bundled(let resourceName):
                entity = try await Entity(named: resourceName, in: Bundle.main)
            case .file(let url):
                entity = try await Entity(contentsOf: url)
            }
            try Task.checkCancellation()
            try await generateStaticMeshCollisionShapes(for: entity)

            guard isCurrentLoad(model, catalogRevision: catalogRevision),
                  let contentRoot else { return }

            entity.isEnabled = isContentVisible
            contentRoot.addChild(entity)
            sceneEntity = entity
            loadedModel = model
            baseRotation = entity.transform.rotation
            navigationRuntime.apply(modelSelection.poseForLoading(model))
            modelSelection.recordPose(navigationRuntime.pose, for: model)
            modelSelection.loadState = .loaded(modelID: model.id)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentLoad(model, catalogRevision: catalogRevision) else { return }

            modelSelection.loadState = .failed(
                modelID: model.id,
                message: "Couldn’t load \(model.displayName): \(error.localizedDescription)"
            )
        }
    }

    @MainActor
    private func isCurrentLoad(_ model: ModelDescriptor, catalogRevision: Int) -> Bool {
        !Task.isCancelled
            && isImmersiveActive
            && modelSelection.selectedModel == model
            && modelSelection.catalogRevision == catalogRevision
    }

    @MainActor
    private func unloadCurrentModel() {
        sceneEntity?.removeFromParent()
        sceneEntity = nil
        loadedModel = nil
        baseRotation = nil
        navigationRuntime.wasPoseChanging = false
    }

    @MainActor
    private func startARKit() {
        guard arkitStartupTask == nil, worldTracking == nil, isImmersiveActive else { return }

        arkitStartupTask = Task { @MainActor in
            defer {
                arkitStartupTask = nil
            }

            let worldProvider = WorldTrackingProvider()
            worldTracking = worldProvider
            var providers: [any DataProvider] = [worldProvider]

            if HandTrackingProvider.isSupported {
                let handProvider = HandTrackingProvider()
                handTracking = handProvider
                providers.append(handProvider)

                _ = await arkitSession.requestAuthorization(
                    for: HandTrackingProvider.requiredAuthorizations
                )
                guard !Task.isCancelled, isImmersiveActive else { return }
            }

            do {
                try await arkitSession.run(providers)
                guard !Task.isCancelled, isImmersiveActive else { return }

                if let handTracking {
                    startHandTrackingUpdates(with: handTracking)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, isImmersiveActive else { return }
                print("Failed to start ARKit session: \(error)")
            }
        }
    }

    @MainActor
    private func stopARKit() {
        arkitStartupTask?.cancel()
        handTrackingTask?.cancel()
        arkitSession.stop()
        arkitStartupTask = nil
        handTrackingTask = nil
        worldTracking = nil
        handTracking = nil
        leftPinchActive = false
        rightPinchActive = false
        leftPinchStartTime = nil
        rightPinchStartTime = nil
    }

    @MainActor
    private func tearDownImmersiveView() {
        guard isImmersiveActive || isRealityViewReady else { return }

        isImmersiveActive = false
        isRealityViewReady = false
        recordCurrentPose()

        modelLoadingTask?.cancel()
        modelLoadingTask = nil
        modelLoadRequestID = UUID()
        unloadCurrentModel()

        updateSubscription?.cancel()
        updateSubscription = nil
        stopARKit()

        modeCueTask?.cancel()
        modeCueTask = nil
        modeCueText = nil
        contentRoot = nil
        modelSelection.loadState = .idle

        Task {
            await modelSelection.flushPositionPersistence()
        }
    }
    
    @MainActor
    private func startHandTrackingUpdates(with provider: HandTrackingProvider) {
        handTrackingTask?.cancel()
        handTrackingTask = Task { @MainActor in
            for await update in provider.anchorUpdates {
                guard !Task.isCancelled, isImmersiveActive else { return }
                handleHandAnchorUpdate(update)
            }
        }
    }
    
    @MainActor
    private func handleHandAnchorUpdate(_ update: AnchorUpdate<HandAnchor>) {
        let anchor = update.anchor
        let chirality = anchor.chirality
        
        if update.event == .removed || !anchor.isTracked {
            setPinchStartTime(nil, for: chirality)
            setPinchActive(false, for: chirality)
            return
        }
        
        guard let handSkeleton = anchor.handSkeleton else {
            setPinchStartTime(nil, for: chirality)
            setPinchActive(false, for: chirality)
            return
        }
        
        let thumb = handSkeleton.joint(.thumbTip)
        let middle = handSkeleton.joint(.middleFingerTip)
        
        guard thumb.isTracked, middle.isTracked else {
            setPinchStartTime(nil, for: chirality)
            setPinchActive(false, for: chirality)
            return
        }
        
        let originFromAnchor = anchor.originFromAnchorTransform
        let thumbWorld = simd_mul(originFromAnchor, thumb.anchorFromJointTransform)
        let middleWorld = simd_mul(originFromAnchor, middle.anchorFromJointTransform)
        
        let thumbPosition = SIMD3<Float>(thumbWorld.columns.3.x, thumbWorld.columns.3.y, thumbWorld.columns.3.z)
        let middlePosition = SIMD3<Float>(middleWorld.columns.3.x, middleWorld.columns.3.y, middleWorld.columns.3.z)
        let distance = simd_distance(thumbPosition, middlePosition)
        
        let isPinching = isPinchActive(for: chirality)
        
        if !isPinching && distance <= pinchOnDistance {
            let now = CACurrentMediaTime()
            let startTime = pinchStartTime(for: chirality) ?? now
            setPinchStartTime(startTime, for: chirality)
            if now - startTime >= pinchHoldDuration {
                setPinchActive(true, for: chirality)
                setPinchStartTime(nil, for: chirality)
                toggleContentVisibility()
            }
        } else if !isPinching && distance > pinchOnDistance {
            setPinchStartTime(nil, for: chirality)
        } else if isPinching && distance >= pinchOffDistance {
            setPinchActive(false, for: chirality)
            setPinchStartTime(nil, for: chirality)
        }
    }
    
    @MainActor
    private func toggleContentVisibility() {
        isContentVisible.toggle()
        sceneEntity?.isEnabled = isContentVisible
    }

    @MainActor
    private func recordCurrentPoseIfNeeded() {
        let now = CACurrentMediaTime()
        guard now - navigationRuntime.lastPersistenceSampleTime >= 0.25 else { return }

        navigationRuntime.lastPersistenceSampleTime = now
        recordCurrentPose()
    }

    @MainActor
    private func recordCurrentPose() {
        guard let loadedModel else { return }
        modelSelection.recordPose(navigationRuntime.pose, for: loadedModel)
    }

    @MainActor
    private func resetToStartingPosition() {
        guard let loadedModel else { return }

        navigationRuntime.apply(loadedModel.startPose ?? .origin)
        recordCurrentPose()
        Task {
            await modelSelection.flushPositionPersistence()
        }
        showModeCue("Reset to Starting Position")
    }

    @MainActor
    private func showModeCue(_ text: String) {
        modeCueTask?.cancel()

        withAnimation(.easeOut(duration: 0.15)) {
            modeCueText = text
        }

        modeCueTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) {
                    modeCueText = nil
                }
            }
        }
    }

    @MainActor
    private func generateStaticMeshCollisionShapes(for entity: Entity) async throws {
        try Task.checkCancellation()

        if let modelEntity = entity as? ModelEntity,
           let mesh = modelEntity.model?.mesh {
            do {
                let shape = try await ShapeResource.generateStaticMesh(from: mesh)
                try Task.checkCancellation()
                modelEntity.collision = CollisionComponent(shapes: [shape], isStatic: true)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                modelEntity.generateCollisionShapes(recursive: false, static: true)
            }
        }

        for child in entity.children {
            try Task.checkCancellation()
            try await generateStaticMeshCollisionShapes(for: child)
        }
    }

    @MainActor
    private func terrainSurfaceHeight(below position: SIMD3<Float>, in entity: Entity) -> Float? {
        guard let scene = entity.scene else { return nil }

        let bounds = entity.visualBounds(relativeTo: entity)
        let verticalExtent = max(bounds.extents.y, 1)
        let origin = SIMD3<Float>(position.x, position.y + terrainProbeHeight, position.z)
        let rayLength = verticalExtent + abs(origin.y - bounds.center.y) + terrainProbeHeight

        return scene.raycast(
            origin: origin,
            direction: SIMD3<Float>(0, -1, 0),
            length: rayLength,
            query: .nearest,
            relativeTo: entity
        ).first?.position.y
    }
    
    @MainActor
    private func isPinchActive(for chirality: HandAnchor.Chirality) -> Bool {
        switch chirality {
        case .left:
            return leftPinchActive
        case .right:
            return rightPinchActive
        @unknown default:
            return false
        }
    }
    
    @MainActor
    private func setPinchActive(_ isActive: Bool, for chirality: HandAnchor.Chirality) {
        switch chirality {
        case .left:
            leftPinchActive = isActive
        case .right:
            rightPinchActive = isActive
        @unknown default:
            break
        }
    }

    @MainActor
    private func pinchStartTime(for chirality: HandAnchor.Chirality) -> TimeInterval? {
        switch chirality {
        case .left:
            return leftPinchStartTime
        case .right:
            return rightPinchStartTime
        @unknown default:
            return nil
        }
    }

    @MainActor
    private func setPinchStartTime(_ time: TimeInterval?, for chirality: HandAnchor.Chirality) {
        switch chirality {
        case .left:
            leftPinchStartTime = time
        case .right:
            rightPinchStartTime = time
        @unknown default:
            break
        }
    }
}

#Preview {
    ImmersiveView(modelSelection: ModelSelection())
}

private struct ModelLoadRequest: Equatable {
    let model: ModelDescriptor
    let catalogRevision: Int
    let isRealityViewReady: Bool
}

@MainActor
private final class NavigationRuntime {
    var currentHeight: Float = 0
    var virtualYaw: Float = 0
    var playerPosition = SIMD3<Float>(0, 0, 0)
    var lastPersistenceSampleTime: TimeInterval = 0
    var wasPoseChanging = false

    var pose: ViewerPose {
        ViewerPose(position: playerPosition, yawRadians: virtualYaw)
    }

    func apply(_ pose: ViewerPose) {
        playerPosition = pose.position
        currentHeight = playerPosition.y
        virtualYaw = pose.yaw
        lastPersistenceSampleTime = CACurrentMediaTime()
        wasPoseChanging = false
    }
}
