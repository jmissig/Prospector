//
//  ProspectorApp.swift
//  Prospector
//
//  Created by Christian Selig on 2025-08-20.
//

import SwiftUI

@main
struct ProspectorApp: App {
    @State private var modelSelection = ModelSelection()

    var body: some Scene {
        WindowGroup {
            ContentView(modelSelection: modelSelection)
                .onOpenURL { url in
                    Task {
                        await modelSelection.openPackage(at: url)
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 320)
        
        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveView(modelSelection: modelSelection)
        }
    }
}
