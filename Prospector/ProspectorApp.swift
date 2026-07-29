//
//  ProspectorApp.swift
//  Prospector
//
//  Created by Christian Selig on 2025-08-20.
//

import SwiftUI

@main
struct ProspectorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 200)
        
        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveView()
        }
    }
}
