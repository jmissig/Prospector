//
//  ImmersivePresentationState.swift
//  Prospector
//

import Observation

enum ImmersivePresentationPhase: Equatable {
    case closed
    case opening
    case open
    case closing
}

@MainActor
@Observable
final class ImmersivePresentationState {
    private(set) var phase: ImmersivePresentationPhase = .closed
    private(set) var errorMessage: String?
    private(set) var wantsPresentation = false
    private var hasEnforcedWindowedLaunch = false

    var isTransitioning: Bool {
        phase == .opening || phase == .closing
    }

    /// Returns true once per app process so launch can reject visionOS scene restoration.
    func beginWindowedLaunch() -> Bool {
        guard !hasEnforcedWindowedLaunch else { return false }

        hasEnforcedWindowedLaunch = true
        wantsPresentation = false
        errorMessage = nil
        phase = .closing
        return true
    }

    func requestOpen() -> Bool {
        guard phase == .closed else { return false }

        wantsPresentation = true
        errorMessage = nil
        phase = .opening
        return true
    }

    func requestClose() -> Bool {
        wantsPresentation = false
        errorMessage = nil

        guard phase != .closed, phase != .closing else { return false }
        phase = .closing
        return true
    }

    func didOpen() {
        phase = wantsPresentation ? .open : .closing
    }

    func openWasCancelled() {
        wantsPresentation = false
        phase = .closed
    }

    func openFailed() {
        wantsPresentation = false
        phase = .closed
        errorMessage = "Couldn’t open immersive view."
    }

    /// Returns whether the space appeared after a close had already been requested.
    func immersiveViewDidAppear() -> Bool {
        if wantsPresentation {
            phase = .open
            errorMessage = nil
            return false
        }

        phase = .closing
        return true
    }

    func immersiveViewDidDisappear() {
        wantsPresentation = false
        phase = .closed
    }

    func didFinishDismissal() {
        wantsPresentation = false
        phase = .closed
    }
}
