//  OnboardingStore.swift
//  Tracks whether the user has completed the first-launch onboarding walkthrough
//  (see OnboardingView). A plain UserDefaults flag -- no need for an @Observable
//  store, since this is read once at GemmaRootView's init and never watched live.

import Foundation

public enum OnboardingStore {
    private static let completedKey = "onboarding.completed"

    public static func hasCompleted(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: completedKey)
    }

    public static func markCompleted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completedKey)
    }

    /// Lets a user replay the walkthrough from Settings without affecting
    /// first-launch detection for anyone else (there's only one user per
    /// device, but this keeps the intent explicit at the call site).
    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: completedKey)
    }
}
