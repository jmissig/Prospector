//
//  GameControllerManager.swift
//  Prospector
//
//  Created by Christian Selig on 2025-08-20.
//

import SwiftUI
import GameController
import simd
import UIKit

struct ControllerElementPresentation: Equatable {
    let localizedName: String
    let symbolName: String

    init(element: GCControllerElement, fallbackName: String, fallbackSymbolName: String) {
        let providedName = element.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let providedName, !providedName.isEmpty {
            localizedName = providedName
        } else {
            localizedName = fallbackName
        }
        symbolName = element.sfSymbolsName ?? fallbackSymbolName
    }
}

struct ControllerPresentation: Equatable {
    let name: String
    let buttonA: ControllerElementPresentation
    let buttonX: ControllerElementPresentation
    let buttonY: ControllerElementPresentation
    let leftThumbstick: ControllerElementPresentation
    let rightThumbstick: ControllerElementPresentation
    let leftTrigger: ControllerElementPresentation
    let rightTrigger: ControllerElementPresentation
    let dpadUp: ControllerElementPresentation
    let dpadDown: ControllerElementPresentation
    let dpadLeft: ControllerElementPresentation
    let dpadRight: ControllerElementPresentation
}

class GameControllerManager: ObservableObject {
    @Published var movementVector = SIMD2<Float>(0, 0)
    @Published var lookVector = SIMD2<Float>(0, 0)
    @Published var heightAdjustment: Float = 0
    @Published var resetHeightRevision = 0
    @Published var terrainFollowEnabled = false
    @Published var speedModeEnabled = false
    @Published var toggleLocationsRevision = 0
    @Published var previousLocationRevision = 0
    @Published var nextLocationRevision = 0
    @Published private(set) var presentation: ControllerPresentation?

    var navigationEnabled = true {
        didSet {
            guard !navigationEnabled else { return }
            movementVector = .zero
            lookVector = .zero
            heightAdjustment = 0
        }
    }
    
    private var controller: GCController?
    private let heightSpeed: Float = 1.0
    
    init() {
        setupController()
        observeControllerConnection()
    }
    
    private func setupController() {
        controller = GCController.controllers().first(where: { $0.extendedGamepad != nil })
        startPollingInput()
    }
    
    private func observeControllerConnection() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidConnect),
            name: .GCControllerDidConnect,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidDisconnect),
            name: .GCControllerDidDisconnect,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func controllerDidConnect(_ notification: Notification) {
        if let controller = notification.object as? GCController,
           controller.extendedGamepad != nil {
            activateController(controller)
        }
    }
    
    @objc private func controllerDidDisconnect(_ notification: Notification) {
        if notification.object as? GCController == self.controller {
            activateController(
                GCController.controllers().first(where: { $0.extendedGamepad != nil })
            )
        }
    }

    @objc private func applicationDidBecomeActive() {
        refreshPresentation()
    }

    private func activateController(_ controller: GCController?) {
        removeInputHandlers(from: self.controller)
        self.controller = controller
        resetContinuousInput()
        startPollingInput()
    }
    
    private func startPollingInput() {
        guard let controller = controller,
              let gamepad = controller.extendedGamepad else {
            presentation = nil
            return
        }

        refreshPresentation()
        
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            guard let self = self else { return }
            
            self.movementVector = self.navigationEnabled ? SIMD2<Float>(xValue, yValue) : .zero
        }

        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            guard let self = self else { return }

            self.lookVector = self.navigationEnabled ? SIMD2<Float>(xValue, yValue) : .zero
        }
        
        // Left trigger (L2/LT) - decrease height
        gamepad.leftTrigger.valueChangedHandler = { [weak self] _, value, _ in
            guard let self = self else { return }

            guard self.navigationEnabled else { self.heightAdjustment = 0; return }
            if value > 0.1 {
                self.heightAdjustment = -self.heightSpeed
            } else if self.heightAdjustment < 0 {
                self.heightAdjustment = 0
            }
        }
        
        // Right trigger (R2/RT) - increase height
        gamepad.rightTrigger.valueChangedHandler = { [weak self] _, value, _ in
            guard let self = self else { return }

            guard self.navigationEnabled else { self.heightAdjustment = 0; return }
            if value > 0.1 {
                self.heightAdjustment = self.heightSpeed
            } else if self.heightAdjustment > 0 {
                self.heightAdjustment = 0
            }
        }
        
        // D-pad up - reset height
        gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            guard let self = self else { return }
            if pressed && self.navigationEnabled {
                self.resetHeightRevision += 1
            }
        }

        gamepad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            guard let self = self else { return }

            if pressed && self.navigationEnabled {
                self.terrainFollowEnabled.toggle()
            }
        }

        gamepad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            guard let self = self else { return }

            if pressed && self.navigationEnabled {
                self.speedModeEnabled.toggle()
            }
        }

        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.toggleLocationsRevision += 1
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, self?.navigationEnabled == true else { return }
            self?.previousLocationRevision += 1
        }
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, self?.navigationEnabled == true else { return }
            self?.nextLocationRevision += 1
        }
    }

    private func refreshPresentation() {
        guard let controller,
              let gamepad = controller.extendedGamepad else {
            presentation = nil
            return
        }

        presentation = ControllerPresentation(
            name: controller.vendorName ?? controller.productCategory,
            buttonA: .init(element: gamepad.buttonA, fallbackName: "A", fallbackSymbolName: "a.circle.fill"),
            buttonX: .init(element: gamepad.buttonX, fallbackName: "X", fallbackSymbolName: "x.circle.fill"),
            buttonY: .init(element: gamepad.buttonY, fallbackName: "Y", fallbackSymbolName: "y.circle.fill"),
            leftThumbstick: .init(
                element: gamepad.leftThumbstick,
                fallbackName: "Left Stick",
                fallbackSymbolName: "l.joystick.tilt.left"
            ),
            rightThumbstick: .init(
                element: gamepad.rightThumbstick,
                fallbackName: "Right Stick",
                fallbackSymbolName: "r.joystick.tilt.right"
            ),
            leftTrigger: .init(
                element: gamepad.leftTrigger,
                fallbackName: "Left Trigger",
                fallbackSymbolName: "l2.button.roundedtop.horizontal.fill"
            ),
            rightTrigger: .init(
                element: gamepad.rightTrigger,
                fallbackName: "Right Trigger",
                fallbackSymbolName: "r2.button.roundedtop.horizontal.fill"
            ),
            dpadUp: .init(element: gamepad.dpad.up, fallbackName: "D-pad Up", fallbackSymbolName: "dpad.up.fill"),
            dpadDown: .init(
                element: gamepad.dpad.down,
                fallbackName: "D-pad Down",
                fallbackSymbolName: "dpad.down.fill"
            ),
            dpadLeft: .init(
                element: gamepad.dpad.left,
                fallbackName: "D-pad Left",
                fallbackSymbolName: "dpad.left.fill"
            ),
            dpadRight: .init(
                element: gamepad.dpad.right,
                fallbackName: "D-pad Right",
                fallbackSymbolName: "dpad.right.fill"
            )
        )
    }

    private func removeInputHandlers(from controller: GCController?) {
        guard let gamepad = controller?.extendedGamepad else { return }

        gamepad.leftThumbstick.valueChangedHandler = nil
        gamepad.rightThumbstick.valueChangedHandler = nil
        gamepad.leftTrigger.valueChangedHandler = nil
        gamepad.rightTrigger.valueChangedHandler = nil
        gamepad.dpad.up.pressedChangedHandler = nil
        gamepad.dpad.right.pressedChangedHandler = nil
        gamepad.dpad.left.pressedChangedHandler = nil
        gamepad.buttonA.pressedChangedHandler = nil
        gamepad.buttonX.pressedChangedHandler = nil
        gamepad.buttonY.pressedChangedHandler = nil
    }

    private func resetContinuousInput() {
        movementVector = .zero
        lookVector = .zero
        heightAdjustment = 0
    }
    
    deinit {
        removeInputHandlers(from: controller)
        NotificationCenter.default.removeObserver(self)
    }
}
