//
//  ContentView.swift
//  Prospector
//
//  Created by Christian Selig on 2025-08-20.
//

import SwiftUI
import RealityKit

struct ContentView: View {
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    @Bindable var modelSelection: ModelSelection
    @State private var showImmersiveSpace = false
    
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

            Button(showImmersiveSpace ? "Exit Immersive View" : "Enter Immersive View") {
                Task {
                    if showImmersiveSpace {
                        await dismissImmersiveSpace()
                        showImmersiveSpace = false
                    } else {
                        await openImmersiveSpace(id: "ImmersiveSpace")
                        showImmersiveSpace = true
                    }
                }
            }
            .font(.title)
        }
        .padding()
        .frame(width: 460, height: 320)
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
}

#Preview(windowStyle: .automatic) {
    ContentView(modelSelection: ModelSelection())
}
