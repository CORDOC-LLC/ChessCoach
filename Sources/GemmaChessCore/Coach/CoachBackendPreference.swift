//  CoachBackendPreference.swift
//  On channels where both the managed coach (ChessCoach Pro) and Gemini BYOK
//  are offered (local dev, TestFlight), lets the user explicitly pick which
//  one actually answers -- rather than a silent, hardcoded priority order.
//
//  This matters because `ManagedCoach.availability` only checks "is a backend
//  URL configured", never whether a real request would actually succeed (that
//  would require a network round-trip just to render Settings). If the
//  managed coach is misconfigured or its entitlement check fails server-side,
//  a fixed "managed always wins when configured" priority order would leave
//  a user's own working Gemini key permanently unreachable with no way to
//  switch to it. An explicit, persisted choice fixes that: the user can
//  always flip to BYOK themselves as a working fallback.
//
//  Irrelevant on App Store production, where only the managed coach is ever
//  offered (`BuildChannel.allowsGeminiBYOK == false` there) -- there is
//  nothing to choose between.

import Foundation

public enum CoachBackendChoice: String, Sendable {
    case managed
    case byok
}

public enum CoachBackendPreference {
    private static let key = "coach.backendPreference"

    /// Defaults to `.managed` -- unchanged behavior for anyone who's never
    /// touched the picker.
    public static func current(defaults: UserDefaults = .standard) -> CoachBackendChoice {
        guard let raw = defaults.string(forKey: key), let choice = CoachBackendChoice(rawValue: raw) else {
            return .managed
        }
        return choice
    }

    public static func set(_ choice: CoachBackendChoice, defaults: UserDefaults = .standard) {
        defaults.set(choice.rawValue, forKey: key)
    }
}
