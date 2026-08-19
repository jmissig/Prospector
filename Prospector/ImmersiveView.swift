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
    @State private var updateSubscription: EventSubscription?
    @State private var worldTracking: WorldTrackingProvider?
    @State private var handTracking: HandTrackingProvider?
    @State private var handTrackingTask: Task<Void, Never>?
    @State private var arkitSession = ARKitSession()
    @State private var currentHeight: Float = 0
    @State private var isContentVisible: Bool = true
    @State private var leftPinchActive: Bool = false
    @State private var rightPinchActive: Bool = false
    @State private var leftPinchStartTime: TimeInterval?
    @State private var rightPinchStartTime: TimeInterval?
    @State private var virtualYaw: Float = 0
    @State private var baseRotation: simd_quatf?
    @State private var playerPosition = SIMD3<Float>(0, 0, 0)
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
            
            // Initialize world tracking for head orientation
            if worldTracking == nil {
                Task { @MainActor in
                    let worldProvider = WorldTrackingProvider()
                    worldTracking = worldProvider
                    
                    var providers: [any DataProvider] = [worldProvider]
                    
                    if HandTrackingProvider.isSupported {
                        let handProvider = HandTrackingProvider()
                        handTracking = handProvider
                        providers.append(handProvider)
                        
                        _ = await arkitSession.requestAuthorization(for: HandTrackingProvider.requiredAuthorizations)
                    }
                    
                    do {
                        try await arkitSession.run(providers)
                    } catch {
                        print("Failed to start ARKit session: \(error)")
                    }
                    
                    if let handTracking = handTracking {
                        startHandTrackingUpdates(with: handTracking)
                    }
                }
            }
            
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
                    currentHeight = terrainSurfaceHeight(below: playerPosition, in: entity) ?? defaultHeight
                    playerPosition.y = currentHeight
                }
                
                // Handle height adjustment from shoulder buttons
                if heightAdjust != 0 {
                    currentHeight += heightAdjust * heightSpeed * speedMultiplier * deltaTime
                    playerPosition.y = currentHeight
                }

                // Handle look rotation from right thumbstick (yaw)
                if lookInput.x != 0 {
                    let yawDelta = -lookInput.x * lookRotationSpeed * deltaTime
                    virtualYaw += yawDelta
                    if virtualYaw > .pi {
                        virtualYaw -= 2 * .pi
                    } else if virtualYaw < -.pi {
                        virtualYaw += 2 * .pi
                    }
                }
                
                // Handle horizontal movement
                if movement != .zero {
                    let moveDistance = movementSpeed * speedMultiplier * deltaTime
                    
                    // Apply combined head + virtual yaw to movement vector
                    let combinedYaw = headYaw + virtualYaw
                    let cosYaw = cos(combinedYaw)
                    let sinYaw = sin(combinedYaw)
                    
                    // Rotate the movement vector by the head yaw
                    let rotatedX = movement.x * cosYaw - movement.y * sinYaw
                    let rotatedZ = movement.x * sinYaw + movement.y * cosYaw
                    
                    // Apply the rotated movement to the player
                    playerPosition.x += rotatedX * moveDistance
                    playerPosition.z -= rotatedZ * moveDistance

                    if controllerManager.terrainFollowEnabled,
                       let terrainHeight = terrainSurfaceHeight(below: playerPosition, in: entity) {
                        currentHeight = terrainHeight
                        playerPosition.y = currentHeight
                    }
                }

                let yawRotation = simd_quatf(angle: -virtualYaw, axis: SIMD3<Float>(0, 1, 0))
                let rotatedPosition = simd_act(yawRotation, playerPosition)
                transform.translation = -rotatedPosition
                if let baseRotation = baseRotation {
                    transform.rotation = simd_mul(yawRotation, baseRotation)
                } else {
                    transform.rotation = yawRotation
                }
                
                entity.transform = transform
            }
        }
        .task(id: ModelLoadRequest(
            model: modelSelection.selectedModel,
            catalogRevision: modelSelection.catalogRevision,
            isRealityViewReady: isRealityViewReady
        )) {
            guard isRealityViewReady else { return }
            await loadModel(
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
        .onDisappear {
            updateSubscription?.cancel()
            handTrackingTask?.cancel()
            modeCueTask?.cancel()
            sceneEntity = nil
            contentRoot = nil
            isRealityViewReady = false
            modelSelection.loadState = .idle
            handTrackingTask = nil
            modeCueTask = nil
        }
    }

    @MainActor
    private func loadModel(_ model: ModelDescriptor, catalogRevision: Int) async {
        guard let contentRoot else { return }

        modelSelection.loadState = .loading(modelID: model.id)

        do {
            let entity: Entity
            switch model.source {
            case .bundled(let resourceName):
                entity = try await Entity(named: resourceName, in: Bundle.main)
            case .file(let url):
                entity = try await Entity(contentsOf: url)
            }
            await generateStaticMeshCollisionShapes(for: entity)

            guard !Task.isCancelled,
                  modelSelection.selectedModel == model,
                  modelSelection.catalogRevision == catalogRevision else {
                return
            }

            entity.isEnabled = isContentVisible
            let previousEntity = sceneEntity
            previousEntity?.removeFromParent()
            contentRoot.addChild(entity)
            sceneEntity = entity
            baseRotation = entity.transform.rotation
            modelSelection.loadState = .loaded(modelID: model.id)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled,
                  modelSelection.selectedModel == model,
                  modelSelection.catalogRevision == catalogRevision else {
                return
            }

            modelSelection.loadState = .failed(
                modelID: model.id,
                message: "Couldn’t load \(model.displayName): \(error.localizedDescription)"
            )
        }
    }
    
    @MainActor
    private func startHandTrackingUpdates(with provider: HandTrackingProvider) {
        handTrackingTask?.cancel()
        handTrackingTask = Task {
            for await update in provider.anchorUpdates {
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
    private func generateStaticMeshCollisionShapes(for entity: Entity) async {
        if let modelEntity = entity as? ModelEntity,
           let mesh = modelEntity.model?.mesh {
            if let shape = try? await ShapeResource.generateStaticMesh(from: mesh) {
                modelEntity.collision = CollisionComponent(shapes: [shape], isStatic: true)
            } else {
                modelEntity.generateCollisionShapes(recursive: false, static: true)
            }
        }

        for child in entity.children {
            await generateStaticMeshCollisionShapes(for: child)
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
