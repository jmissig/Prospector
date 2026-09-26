import Foundation

@main
struct NavigationChecks {
    @MainActor
    static func main() async throws {
        let a = ModelDescriptor(id: "a", displayName: "A", resourceName: "A",
            startPose: ViewerPose(position: [1, 2, 3], yawRadians: 0.5))
        let b = ModelDescriptor(id: "b", displayName: "B", resourceName: "B",
            startPose: ViewerPose(position: [4, 5, 6], yawRadians: -1))
        let selection = ModelSelection(models: [a, b], selectedModel: a)
        precondition(selection.poseForLoading(a) == a.startPose)
        selection.recordPose(ViewerPose(position: [9, 8, 7], yawRadians: 1.75), for: a)
        selection.selectedModel = b
        let incoming = selection.poseForLoading(b)
        precondition(incoming.position == b.startPose!.position && incoming.yaw == 1.75)
        selection.recordPose(incoming, for: b)
        selection.selectedModel = a
        precondition(selection.poseForLoading(a).yaw == 1.75)
        // Recreating immersive navigation uses this same app-owned selection.
        precondition(selection.poseForLoading(a).yaw == 1.75)
        // Explicit starting-position reset remains authoritative for the session.
        selection.recordPose(a.startPose!, for: a)
        precondition(selection.poseForLoading(b).yaw == 0.5)
        selection.recordPose(ViewerPose(position: .zero, yawRadians: .nan), for: a)
        precondition(selection.poseForLoading(b).yaw == 0.5)
        let fresh = ModelSelection(models: [a, b], selectedModel: b)
        precondition(fresh.poseForLoading(b).yaw == -1)
        print("PASS: session yaw overrides incoming authored yaw; per-model positions, reset, invalid-pose rejection and fresh-session initialization")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".prospector")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("House.usdz"))
        let manifest: [String: Any] = ["formatVersion": 1, "name": "Fixture", "defaultModelID": "a",
            "models": ["a", "b"].map { ["id": $0, "name": $0, "path": "House.usdz", "statePath": "\($0).state.json"] }]
        try JSONSerialization.data(withJSONObject: manifest).write(to: root.appendingPathComponent("manifest.json"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for (id, pose) in [("a", a.startPose!), ("b", b.startPose!)] {
            try encoder.encode(ModelPositionState(modelID: id, pose: pose))
                .write(to: root.appendingPathComponent("\(id).state.json"))
        }
        let packageSelection = ModelSelection()
        await packageSelection.openPackage(at: root)
        precondition(packageSelection.documentError == nil, packageSelection.documentError ?? "")
        precondition(packageSelection.persistenceWarning == nil, packageSelection.persistenceWarning ?? "")
        let modelA = packageSelection.models[0], modelB = packageSelection.models[1]
        let initial = packageSelection.poseForLoading(modelA)
        if packageSelection.resumeLastPositions {
            precondition(initial == a.startPose)
        }
        packageSelection.recordPose(ViewerPose(position: [10, 11, 12], yawRadians: 2), for: modelA)
        packageSelection.selectedModel = modelB
        let switched = packageSelection.poseForLoading(modelB)
        precondition(switched.yaw == 2)
        if packageSelection.resumeLastPositions {
            precondition(switched.position == b.startPose!.position)
            precondition(packageSelection.poseForLoading(modelA).position == [10, 11, 12])
        }
        await packageSelection.flushPositionPersistence()
        print("PASS: synthetic package saved positions remain per-model while saved yaw is overridden by session yaw")
    }
}
