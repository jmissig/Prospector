//
//  ControllerGuideView.swift
//  Prospector
//

import SwiftUI

struct ControllerGuideView: View {
    let presentation: ControllerPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let presentation {
                HStack(alignment: .firstTextBaseline) {
                    Text("Controller Controls")
                        .font(.headline)
                    Spacer()
                    Text(presentation.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 22) {
                    control(presentation.buttonA, action: "Dismiss", emphasized: true)
                    control(presentation.buttonX, action: "Previous location")
                    control(presentation.buttonY, action: "Next location")
                    Divider()
                        .frame(height: 58)
                    control(presentation.leftThumbstick, action: "Move")
                    control(presentation.rightThumbstick, action: "Virtual turn")
                    control(presentation.leftTrigger, action: "Move down")
                    control(presentation.rightTrigger, action: "Move up")
                }

                Divider()

                HStack(alignment: .center, spacing: 18) {
                    Text("D-pad")
                        .font(.subheadline.weight(.semibold))
                    dpadControl(presentation.dpadUp, action: "Land on surface")
                    dpadControl(presentation.dpadLeft, action: "Speed mode")
                    dpadControl(presentation.dpadRight, action: "Terrain follow")
                    dpadControl(presentation.dpadDown, action: "Unassigned")
                }
                .opacity(0.55)

                Text("Navigation controls are paused while saved locations are open.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Label("No Controller Connected", systemImage: "gamecontroller")
                    .font(.headline)
                Text("Pair a controller to see its controls here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 780)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .allowsHitTesting(false)
    }

    private func control(
        _ control: ControllerElementPresentation,
        action: String,
        emphasized: Bool = false
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: control.symbolName)
                .font(.title2)
            Text(control.localizedName)
                .font(.caption2)
                .lineLimit(1)
            Text(action)
                .font(.caption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(emphasized ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(control.localizedName): \(action)")
    }

    private func dpadControl(
        _ control: ControllerElementPresentation,
        action: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: control.symbolName)
                .font(.title3)
            Text(action)
                .font(.caption)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(control.localizedName): \(action)")
    }
}
