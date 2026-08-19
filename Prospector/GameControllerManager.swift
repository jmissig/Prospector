//
//  GameControllerManager.swift
//  Prospector
//
//  Created by Christian Selig on 2025-08-20.
//

import SwiftUI
import GameController
import simd

class GameControllerManager: ObservableObject {
    @Published var movementVector = SIMD2<Float>(0, 0)
    @Published var lookVector = SIMD2<Float>(0, 0)
    @Published var heightAdjustment: Float = 0
    @Published var shouldResetHeight = false
    @Published var terrainFollowEnabled = false
    @Published var speedModeEnabled = false
    @Published var toggleLocationsRevision = 0
    @Published var previousLocationRevision = 0
    @Published var nextLocationRevision = 0

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
        controller = GCController.controllers().first
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
    }
    
    @objc private func controllerDidConnect(_ notification: Notification) {
        if let controller = notification.object as? GCController {
            self.controller = controller
            startPollingInput()
        }
    }
    
    @objc private func controllerDidDisconnect(_ notification: Notification) {
        if notification.object as? GCController == self.controller {
            self.controller = nil
            movementVector = SIMD2<Float>(0, 0)
            lookVector = SIMD2<Float>(0, 0)
            heightAdjustment = 0
        }
    }
    
    private func startPollingInput() {
        guard let controller = controller,
              let gamepad = controller.extendedGamepad else { return }
        
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
                self.shouldResetHeight = true
                // Reset the flag after a short delay to ensure it's processed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.shouldResetHeight = false
                }
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
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
