//  CoachLLM.swift
//  Shared types for the coach backend. Used to define `CoachLLM`, a
//  provider-agnostic protocol over multiple backends (`ManagedCoach`,
//  `GeminiCoach`) that each took a plain (system, prompt) text pair.
//
//  Plan 2026-07-21-002 (U1/KTD-3): prompt assembly moved server-side, and
//  BYOK (`GeminiCoach`) was retired, leaving `ManagedCoach` as the only
//  backend. With exactly one conformer, the protocol no longer earned its
//  keep -- `CoachOrchestrator` now depends on `ManagedCoach` directly. This
//  file keeps the shared value types every part of the coach stack still
//  needs.

import Foundation

/// Which coach backend is live for this device/session.
public enum CoachAvailability: Equatable, Sendable {
    /// The developer-hosted, metered coach (chesscoach-gateway). The
    /// backend's own `/api/coach` endpoint decides the provider/model and
    /// assembles the actual prompt -- this app only ever sends structured
    /// facts. Opt-in via subscription (or, for local testing before
    /// RevenueCat, a debug bypass token).
    case managed
    /// No coach backend is configured -- the UI hides chat and keeps the engine
    /// review. `reason` is a short, user-facing explanation.
    case unavailable(reason: String)
}

/// One coach answer plus the backend's conversation handle (for multi-turn chat).
public struct CoachReply: Equatable, Sendable {
    public let answer: String
    /// Opaque thread id a backend may use to continue the conversation; nil if stateless.
    public let sessionID: String?

    public init(answer: String, sessionID: String? = nil) {
        self.answer = answer
        self.sessionID = sessionID
    }
}

/// Which persona/prompt the gateway should build for a `/api/coach` request --
/// mirrors the wire contract's `kind` discriminator exactly (`"chat"`,
/// `"moveNote"`, `"summary"`).
public enum CoachRequestKind: String, Sendable, Encodable {
    case chat
    case moveNote
    case summary
}

/// Raised with a user-facing message when a coach call can't complete.
public struct CoachError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}
