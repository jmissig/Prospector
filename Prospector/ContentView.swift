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
    @State private var showImmersiveSpace = false
    
    var body: some View {
        VStack {
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
            .padding()
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
