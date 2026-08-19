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
    @State private var interfaceRoot: Entity?
    @State private var isInterfacePlacementPending = false
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
    @State private var modelCoordinateSpace: ModelCoordinateSpace?
    @State private var navigationRuntime = NavigationRuntime()
    @State private var modeCueText: String?
    @State private var modeCueTask: Task<Void, Never>?
    @State private var isLocationsPanelPresented = false
    @State private var activeSavedLocationID: SavedLocation.ID?
    
    let movementSpeed: Float = 2.0
    let speedModeMultiplier: Float = 6.0
    let heightSpeed: Float = 1.5
    let lookRotationSpeed: Float = 2.25
    let defaultHeight: Float = 0
    let terrainProbeHeight: Float = 1.5
    let minimumWalkableNormalY: Float = 0.35
    let pinchOnDistance: Float = 0.02
    let pinchOffDistance: Float = 0.03
    let pinchHoldDuration: TimeInterval = 0.5
    let locationsPanelPosition = SIMD3<Float>(-0.55, -0.02, -1.0)
    let controllerGuidePosition = SIMD3<Float>(0, -0.43, -1.0)

    private enum ImmersiveAttachment: Hashable {
        case locations
        case controllerGuide
    }
    
    var body: some View {
        RealityView { content, attachments in
            let root = Entity()
            content.add(root)
            contentRoot = root

            let interface = Entity()
            interface.isEnabled = false
            content.add(interface)
            interfaceRoot = interface
            attachPanels(attachments, to: interface)

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
                placeInterfaceRelativeToHeadIfNeeded()

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
                
                // Query the physical headset only when an action needs it. Its yaw steers
                // horizontal movement, while its X/Z displacement positions terrain probes
                // under the user's real location.
                var headYaw: Float = 0
                var devicePosition = SIMD3<Float>.zero
                let needsDevicePose = movement != .zero || controllerManager.shouldResetHeight
                if needsDevicePose,
                   let worldTracking = worldTracking,
                   let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
                    let deviceTransform = deviceAnchor.originFromAnchorTransform
                    devicePosition = SIMD3<Float>(
                        deviceTransform.columns.3.x,
                        deviceTransform.columns.3.y,
                        deviceTransform.columns.3.z
                    )
                    let forward = SIMD3<Float>(deviceTransform.columns.2.x,
                                              deviceTransform.columns.2.y,
                                              deviceTransform.columns.2.z)
                    headYaw = atan2(forward.x, forward.z)
                }
                
                // Handle height reset
                if controllerManager.shouldResetHeight {
                    navigationRuntime.currentHeight = terrainSurfaceHeight(
                        below: navigationRuntime.playerPosition,
                        physicalDevicePosition: devicePosition,
                        virtualYaw: navigationRuntime.virtualYaw,
                        reportDiagnostics: true,
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
                        physicalDevicePosition: devicePosition,
                        virtualYaw: navigationRuntime.virtualYaw,
                        in: entity
                       ) {
                        navigationRuntime.currentHeight = terrainHeight
                        navigationRuntime.playerPosition.y = navigationRuntime.currentHeight
                    }
                    poseChanged = true
                }

                if poseChanged {
                    navigationRuntime.isTransformDirty = true
                }

                if navigationRuntime.isTransformDirty {
                    let yawRotation = simd_quatf(
                        angle: -navigationRuntime.virtualYaw,
                        axis: SIMD3<Float>(0, 1, 0)
                    )
                    let rotatedPosition = simd_act(yawRotation, navigationRuntime.playerPosition)
                    let transform: Transform
                    if let modelCoordinateSpace {
                        let navigationAdjustment = Transform(
                            rotation: yawRotation,
                            translation: -rotatedPosition
                        )
                        transform = Transform(
                            matrix: navigationAdjustment.matrix * modelCoordinateSpace.navigationFromModel
                        )
                    } else {
                        transform = Transform(
                            rotation: yawRotation,
                            translation: -rotatedPosition
                        )
                    }

                    entity.transform = transform
                    navigationRuntime.isTransformDirty = false
                }

                if poseChanged {
                    recordCurrentPoseIfNeeded()
                } else if navigationRuntime.wasPoseChanging {
                    recordCurrentPose()
                }
                navigationRuntime.wasPoseChanging = poseChanged
            }
        } update: { _, attachments in
            guard let interfaceRoot else { return }
            attachPanels(attachments, to: interfaceRoot)
            placeInterfaceRelativeToHeadIfNeeded()
        } attachments: {
            Attachment(id: ImmersiveAttachment.locations) {
                if isLocationsPanelPresented {
                    locationsPanel
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            Attachment(id: ImmersiveAttachment.controllerGuide) {
                if isLocationsPanelPresented {
                    ControllerGuideView(presentation: controllerManager.presentation)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
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
        .onTapGesture {
            setLocationsPanelPresented(!isLocationsPanelPresented)
        }
        .overlay(alignment: .top) {
            if !isLocationsPanelPresented, let modeCueText {
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
        .onChange(of: controllerManager.toggleLocationsRevision) { _, _ in
            setLocationsPanelPresented(!isLocationsPanelPresented)
        }
        .onChange(of: controllerManager.previousLocationRevision) { _, _ in
            jumpToAdjacentLocation(offset: -1)
        }
        .onChange(of: controllerManager.nextLocationRevision) { _, _ in
            jumpToAdjacentLocation(offset: 1)
        }
        .onChange(of: modelSelection.selectedModel) { _, _ in
            setLocationsPanelPresented(false)
            activeSavedLocationID = nil
        }
        .onDisappear {
            tearDownImmersiveView()
        }
    }

    private var locationsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(modelSelection.selectedModel.displayName)
                    .font(.headline)
                Spacer()
                Button {
                    setLocationsPanelPresented(false)
                } label: {
                    Label("Close saved locations", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }

            if modelSelection.savedLocations.isEmpty {
                ContentUnavailableView(
                    "No Saved Locations",
                    systemImage: "mappin.and.ellipse",
                    description: Text("Add your current position to jump back here later.")
                )
                .frame(height: 160)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(modelSelection.savedLocations) { location in
                            HStack {
                                Button(location.name) {
                                    jump(to: location)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Button("Delete \(location.name)", systemImage: "trash", role: .destructive) {
                                    modelSelection.deleteSavedLocation(location, for: modelSelection.selectedModel)
                                    if activeSavedLocationID == location.id { activeSavedLocationID = nil }
                                }
                                .labelStyle(.iconOnly)
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            Button("Add Location", systemImage: "plus") {
                if let location = modelSelection.addSavedLocation(
                    position: navigationRuntime.playerPosition,
                    for: modelSelection.selectedModel
                ) {
                    activeSavedLocationID = location.id
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    @MainActor
    private func attachPanels(_ attachments: RealityViewAttachments, to anchor: Entity) {
        if let locations = attachments.entity(for: ImmersiveAttachment.locations) {
            locations.position = locationsPanelPosition
            if locations.parent == nil {
                anchor.addChild(locations)
            }
        }

        if let controllerGuide = attachments.entity(for: ImmersiveAttachment.controllerGuide) {
            controllerGuide.position = controllerGuidePosition
            if controllerGuide.parent == nil {
                anchor.addChild(controllerGuide)
            }
        }
    }

    @MainActor
    private func placeInterfaceRelativeToHeadIfNeeded() {
        guard isInterfacePlacementPending,
              let interfaceRoot,
              let worldTracking,
              let deviceAnchor = worldTracking.queryDeviceAnchor(
                atTimestamp: CACurrentMediaTime()
              ) else { return }

        let deviceTransform = deviceAnchor.originFromAnchorTransform
        let devicePosition = SIMD3<Float>(
            deviceTransform.columns.3.x,
            deviceTransform.columns.3.y,
            deviceTransform.columns.3.z
        )
        let deviceBack = SIMD3<Float>(
            deviceTransform.columns.2.x,
            0,
            deviceTransform.columns.2.z
        )
        guard simd_length_squared(deviceBack) > 0.0001 else { return }

        // Sample the headset's position and yaw once when the panels open. A normal
        // world-space entity then keeps the SwiftUI attachments stationary instead of
        // making them follow every head movement like AnchorEntity(.head) did.
        let normalizedBack = simd_normalize(deviceBack)
        let yaw = atan2(normalizedBack.x, normalizedBack.z)
        interfaceRoot.position = devicePosition
        interfaceRoot.orientation = simd_quatf(
            angle: yaw,
            axis: SIMD3<Float>(0, 1, 0)
        )
        interfaceRoot.isEnabled = true
        isInterfacePlacementPending = false
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
        setLocationsPanelPresented(false)
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
            modelCoordinateSpace = ModelCoordinateSpace(
                importedRootTransform: entity.transform,
                modelBounds: entity.visualBounds(relativeTo: entity)
            )
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
        modelCoordinateSpace = nil
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
        interfaceRoot?.removeFromParent()
        interfaceRoot = nil
        isInterfacePlacementPending = false
        modelSelection.loadState = .idle
        setLocationsPanelPresented(false)

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
    private func setLocationsPanelPresented(_ isPresented: Bool) {
        guard isLocationsPanelPresented != isPresented else { return }

        if isPresented {
            interfaceRoot?.isEnabled = false
            isInterfacePlacementPending = true
        } else {
            interfaceRoot?.isEnabled = false
            isInterfacePlacementPending = false
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            isLocationsPanelPresented = isPresented
        }
        controllerManager.navigationEnabled = !isPresented

        if isPresented {
            placeInterfaceRelativeToHeadIfNeeded()
        }
    }

    @MainActor
    private func jump(to location: SavedLocation) {
        navigationRuntime.playerPosition = location.viewerPositionMeters.simdValue
        navigationRuntime.currentHeight = navigationRuntime.playerPosition.y
        navigationRuntime.isTransformDirty = true
        activeSavedLocationID = location.id
        recordCurrentPose()
        showModeCue(location.name)
    }

    @MainActor
    private func jumpToAdjacentLocation(offset: Int) {
        let locations = modelSelection.savedLocations
        guard !locations.isEmpty else {
            showModeCue("No Saved Locations")
            return
        }
        let currentIndex = activeSavedLocationID.flatMap { id in
            locations.firstIndex(where: { $0.id == id })
        }
        let destinationIndex: Int
        if let currentIndex {
            destinationIndex = (currentIndex + offset + locations.count) % locations.count
        } else {
            destinationIndex = offset < 0 ? locations.count - 1 : 0
        }
        jump(to: locations[destinationIndex])
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
    private func terrainSurfaceHeight(
        below position: SIMD3<Float>,
        physicalDevicePosition: SIMD3<Float>,
        virtualYaw: Float,
        reportDiagnostics: Bool = false,
        in entity: Entity
    ) -> Float? {
        guard let scene = entity.scene,
              let modelCoordinateSpace else { return nil }

        let yawRotation = simd_quatf(
            angle: -virtualYaw,
            axis: SIMD3<Float>(0, 1, 0)
        )
        let physicalHorizontalOffset = SIMD3<Float>(
            physicalDevicePosition.x,
            0,
            physicalDevicePosition.z
        )
        let probePosition = position + simd_act(yawRotation.inverse, physicalHorizontalOffset)
        let navigationOrigin = SIMD3<Float>(
            probePosition.x,
            position.y + terrainProbeHeight,
            probePosition.z
        )
        let navigationEnd = SIMD3<Float>(
            probePosition.x,
            min(
                modelCoordinateSpace.navigationBounds.min.y - terrainProbeHeight,
                navigationOrigin.y - 1
            ),
            probePosition.z
        )
        let modelOrigin = modelCoordinateSpace.modelPoint(fromNavigation: navigationOrigin)
        let modelEnd = modelCoordinateSpace.modelPoint(fromNavigation: navigationEnd)
        let modelRay = modelEnd - modelOrigin
        let rayLength = simd_length(modelRay)
        guard rayLength > 0 else { return nil }

        let candidates = scene.raycast(
            origin: modelOrigin,
            direction: modelRay / rayLength,
            length: rayLength,
            query: .all,
            relativeTo: entity
        ).compactMap { hit -> TerrainSurfaceCandidate? in
            let navigationPosition = modelCoordinateSpace.navigationPoint(fromModel: hit.position)
            let navigationNormal = modelCoordinateSpace.navigationNormal(fromModel: hit.normal)
            guard navigationNormal.y >= minimumWalkableNormalY else { return nil }

            return TerrainSurfaceCandidate(
                entityName: hit.entity.name,
                position: navigationPosition,
                normal: navigationNormal
            )
        }

        let selected = candidates.min {
            abs($0.position.y - position.y) < abs($1.position.y - position.y)
        }

#if DEBUG
        if reportDiagnostics {
            for (index, candidate) in candidates.enumerated() {
                print(
                    "Terrain probe candidate[\(index)] entity=\(candidate.entityName) "
                        + "height=\(candidate.position.y) normal=\(candidate.normal) "
                        + "offset=\(candidate.position.y - position.y)"
                )
            }
            if let selected {
                print(
                    "Terrain probe selected entity=\(selected.entityName) "
                        + "height=\(selected.position.y) normal=\(selected.normal) "
                        + "offset=\(selected.position.y - position.y)"
                )
            } else {
                print("Terrain probe found no upward-facing surface")
            }
        }
#endif

        return selected?.position.y
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

private struct ModelCoordinateSpace {
    let navigationFromModel: simd_float4x4
    let modelFromNavigation: simd_float4x4
    let navigationBounds: BoundingBox
    private let navigationNormalFromModel: simd_float3x3

    init(importedRootTransform: Transform, modelBounds: BoundingBox) {
        // Real asset evidence: USD layer metadata for all three 636 house exports declares
        // upAxis="Z". RealityKit imports them with an approximately -90-degree root
        // rotation about X to present Y-up content. An August 2026 inspection reproduced
        // the floor bug:
        // treating entity-local -Y as navigation down cast sideways through those models.
        // Keep every model/navigation conversion behind this full imported transform so
        // future assets with root translation or scale are correct as well.
        navigationFromModel = importedRootTransform.matrix
        modelFromNavigation = simd_inverse(navigationFromModel)

        let linearTransform = simd_float3x3(columns: (
            SIMD3<Float>(
                navigationFromModel.columns.0.x,
                navigationFromModel.columns.0.y,
                navigationFromModel.columns.0.z
            ),
            SIMD3<Float>(
                navigationFromModel.columns.1.x,
                navigationFromModel.columns.1.y,
                navigationFromModel.columns.1.z
            ),
            SIMD3<Float>(
                navigationFromModel.columns.2.x,
                navigationFromModel.columns.2.y,
                navigationFromModel.columns.2.z
            )
        ))
        navigationNormalFromModel = simd_transpose(simd_inverse(linearTransform))
        navigationBounds = modelBounds.transformed(by: navigationFromModel)
    }

    func navigationPoint(fromModel point: SIMD3<Float>) -> SIMD3<Float> {
        transformPoint(point, by: navigationFromModel)
    }

    func modelPoint(fromNavigation point: SIMD3<Float>) -> SIMD3<Float> {
        transformPoint(point, by: modelFromNavigation)
    }

    func navigationNormal(fromModel normal: SIMD3<Float>) -> SIMD3<Float> {
        simd_normalize(navigationNormalFromModel * normal)
    }

    private func transformPoint(
        _ point: SIMD3<Float>,
        by transform: simd_float4x4
    ) -> SIMD3<Float> {
        let transformed = transform * SIMD4<Float>(point, 1)
        return SIMD3<Float>(transformed.x, transformed.y, transformed.z) / transformed.w
    }
}

private struct TerrainSurfaceCandidate {
    let entityName: String
    let position: SIMD3<Float>
    let normal: SIMD3<Float>
}

@MainActor
private final class NavigationRuntime {
    var currentHeight: Float = 0
    var virtualYaw: Float = 0
    var playerPosition = SIMD3<Float>(0, 0, 0)
    var lastPersistenceSampleTime: TimeInterval = 0
    var wasPoseChanging = false
    var isTransformDirty = true

    var pose: ViewerPose {
        ViewerPose(position: playerPosition, yawRadians: virtualYaw)
    }

    func apply(_ pose: ViewerPose) {
        playerPosition = pose.position
        currentHeight = playerPosition.y
        virtualYaw = pose.yaw
        lastPersistenceSampleTime = CACurrentMediaTime()
        wasPoseChanging = false
        isTransformDirty = true
    }
}
