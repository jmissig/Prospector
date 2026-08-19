//
//  ContentView.swift
//  Prospector
//
//  Created by Christian Selig on 2025-08-20.
//

import SwiftUI
import RealityKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Bindable var modelSelection: ModelSelection
    @Bindable var immersivePresentation: ImmersivePresentationState
    
    var body: some View {
        VStack(spacing: 20) {
            if let documentName = modelSelection.documentName {
                Label(documentName, systemImage: "shippingbox.fill")
                    .font(.headline)
            } else {
                Text("Open a .prospector package from Files, or use a bundled model.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Picker("Model", selection: $modelSelection.selectedModel) {
                ForEach(modelSelection.models) { model in
                    Text(model.displayName)
                        .tag(model)
                }
            }
            .disabled(modelSelection.models.count < 2 || modelSelection.isOpeningDocument)

            documentStatus
            loadStatus

            Button(immersiveButtonTitle) {
                Task {
                    await toggleImmersiveSpace()
                }
            }
            .font(.title)
            .disabled(immersivePresentation.isTransitioning)

            if let message = immersivePresentation.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }

            Text("Version \(appVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(width: 460, height: 340)
        .task {
            guard immersivePresentation.beginWindowedLaunch() else { return }
            await dismissImmersiveSpace()
            immersivePresentation.didFinishDismissal()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background else { return }
            requestImmersiveDismissal()
        }
        .onDisappear {
            requestImmersiveDismissal()
        }
    }

    @ViewBuilder
    private var documentStatus: some View {
        if modelSelection.isOpeningDocument {
            ProgressView("Opening package…")
        } else if let message = modelSelection.documentError {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .multilineTextAlignment(.center)
        } else if let message = modelSelection.persistenceWarning {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var loadStatus: some View {
        switch modelSelection.loadState {
        case .idle:
            EmptyView()
        case .loading(let modelID) where modelID == modelSelection.selectedModel.id:
            ProgressView("Loading \(modelSelection.selectedModel.displayName)…")
        case .loaded(let modelID) where modelID == modelSelection.selectedModel.id:
            Label("Model loaded", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .failed(let modelID, let message) where modelID == modelSelection.selectedModel.id:
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .multilineTextAlignment(.center)
        default:
            EmptyView()
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var immersiveButtonTitle: String {
        switch immersivePresentation.phase {
        case .closed:
            "Enter Immersive View"
        case .opening:
            "Entering Immersive View…"
        case .open:
            "Exit Immersive View"
        case .closing:
            "Exiting Immersive View…"
        }
    }

    private func toggleImmersiveSpace() async {
        switch immersivePresentation.phase {
        case .closed:
            guard immersivePresentation.requestOpen() else { return }

            switch await openImmersiveSpace(id: "ImmersiveSpace") {
            case .opened:
                immersivePresentation.didOpen()
                if !immersivePresentation.wantsPresentation {
                    await dismissImmersiveSpace()
                    immersivePresentation.didFinishDismissal()
                }
            case .userCancelled:
                immersivePresentation.openWasCancelled()
            case .error:
                immersivePresentation.openFailed()
            @unknown default:
                immersivePresentation.openFailed()
            }
        case .open:
            await dismissImmersiveSpaceIfNeeded()
        case .opening, .closing:
            break
        }
    }

    private func requestImmersiveDismissal() {
        guard immersivePresentation.requestClose() else { return }
        Task {
            await dismissImmersiveSpace()
            immersivePresentation.didFinishDismissal()
        }
    }

    private func dismissImmersiveSpaceIfNeeded() async {
        guard immersivePresentation.requestClose() else { return }
        await dismissImmersiveSpace()
        immersivePresentation.didFinishDismissal()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView(
        modelSelection: ModelSelection(),
        immersivePresentation: ImmersivePresentationState()
    )
}
