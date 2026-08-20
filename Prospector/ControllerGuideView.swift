//
//  ControllerGuideView.swift
//  Prospector
//

import SwiftUI

struct ControllerGuideView: View {
    let presentation: ControllerPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let presentation {
                HStack(alignment: .firstTextBaseline) {
                    Label("Controller", systemImage: "gamecontroller.fill")
                        .font(.headline)
                    Spacer()
                    Text(presentation.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    horizontalControl(presentation.leftTrigger, action: "Move down")
                    Spacer(minLength: 24)
                    horizontalControl(presentation.rightTrigger, action: "Move up")
                }

                Divider()

                HStack(alignment: .top, spacing: 18) {
                    dpadSection(presentation)
                        .frame(width: 210)

                    Divider()

                    sticksSection(presentation)
                        .frame(width: 190)

                    Divider()

                    faceButtonsSection(presentation)
                        .frame(width: 230)
                }

                Divider()

                HStack(spacing: 10) {
                    Image(systemName: "hand.tap")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 28)
                    Text("Double tap")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("Next location")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Double tap: Next location")

                Label(
                    "Navigation is paused while saved locations are open.",
                    systemImage: "pause.circle"
                )
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
        .padding(24)
        .frame(width: 760)
        .fixedSize(horizontal: false, vertical: true)
        .glassBackgroundEffect(in: .rect(cornerRadius: 32))
        .accessibilityElement(children: .contain)
        .allowsHitTesting(false)
    }

    private func horizontalControl(
        _ control: ControllerElementPresentation,
        action: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: control.symbolName)
                .font(.title2)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(control.localizedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(action)
                    .font(.subheadline.weight(.medium))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(control.localizedName): \(action)")
    }

    private func iconControl(
        _ control: ControllerElementPresentation,
        action: String,
        prominent: Bool = false
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: control.symbolName)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .frame(height: 28)
            Text(action)
                .font(.caption.weight(prominent ? .semibold : .regular))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(prominent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(control.localizedName): \(action)")
    }

    private func dpadSection(_ presentation: ControllerPresentation) -> some View {
        VStack(spacing: 10) {
            Text("D-pad")
                .font(.subheadline.weight(.semibold))

            iconControl(presentation.dpadUp, action: "Land on surface")
                .frame(width: 88)
            HStack(spacing: 8) {
                iconControl(presentation.dpadLeft, action: "Speed mode")
                    .frame(width: 80)
                Image(systemName: "dpad.fill")
                    .font(.title)
                    .foregroundStyle(.tertiary)
                    .frame(width: 34)
                iconControl(presentation.dpadRight, action: "Terrain follow")
                    .frame(width: 80)
            }
            iconControl(presentation.dpadDown, action: "Unassigned")
                .frame(width: 88)
        }
    }

    private func sticksSection(_ presentation: ControllerPresentation) -> some View {
        VStack(spacing: 18) {
            Text("Sticks")
                .font(.subheadline.weight(.semibold))
            HStack(alignment: .top, spacing: 28) {
                iconControl(presentation.leftThumbstick, action: "Move")
                iconControl(presentation.rightThumbstick, action: "Virtual turn")
            }
            Spacer(minLength: 0)
        }
    }

    private func faceButtonsSection(_ presentation: ControllerPresentation) -> some View {
        VStack(spacing: 10) {
            Text("Saved Locations")
                .font(.subheadline.weight(.semibold))

            iconControl(presentation.buttonY, action: "Next location")
                .frame(width: 110)
            HStack(alignment: .top, spacing: 22) {
                iconControl(presentation.buttonX, action: "Previous location")
                    .frame(width: 110)
                iconControl(presentation.buttonA, action: "Dismiss", prominent: true)
                    .frame(width: 90)
            }
        }
    }
}
