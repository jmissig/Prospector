//
//  ProspectorApp.swift
//  Prospector
//
//  Created by Christian Selig on 2025-08-20.
//

import SwiftUI

@main
struct ProspectorApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var modelSelection = ModelSelection()

    var body: some Scene {
        WindowGroup {
            ContentView(modelSelection: modelSelection)
                .onOpenURL { url in
                    Task {
                        await modelSelection.openPackage(at: url)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .background else { return }
                    Task {
                        await modelSelection.flushPositionPersistence()
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 420)
        
        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveView(modelSelection: modelSelection)
        }
    }
}
