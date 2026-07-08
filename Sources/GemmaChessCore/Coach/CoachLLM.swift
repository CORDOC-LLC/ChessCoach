//  CoachLLM.swift
//  The provider-agnostic seam for the coach.
//
//  Backends are deliberately "dumb": they take a system instruction + a fully-
//  composed user prompt and return text. ALL prompt and fact construction lives
//  in `CoachPromptBuilder` (this file's companion), so the engine-grounding
//  contract — "Stockfish computes, the model only explains" — is enforced in
//  one tested place. This mirrors the source project's `server/claude_bridge.py`,
//  minus the `claude -p` subprocess.
//
//  On-device backends (Apple Foundation Models, Gemma via MLX) were tried and
//  dropped — quality wasn't good enough to ship. Every coach backend is now a
//  network call (the managed coach or BYOK Gemini); only the engine (Stockfish)
//  runs on-device.

import Foundation

/// Which coach backend is live for this device/session.
public enum CoachAvailability: Equatable, Sendable {
    /// Google Gemini (cloud), used with the user's own API key.
    case gemini
    /// The developer-hosted, metered coach (chesscoach-gateway). Same
    /// explanation-only contract as every other backend — the backend's own
    /// `/coach` endpoint decides the provider/model, this app never talks to
    /// one directly. Opt-in via subscription (or, for local testing before
    /// U6 wires up RevenueCat, a debug bypass token).
    case managed
    /// No coach backend is configured — the UI hides chat and keeps the engine
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

/// A backend that turns a (system, prompt) pair into coaching text. Implemented
/// by `GeminiCoach` and `ManagedCoach`; selected by `CoachOrchestrator`.
public protocol CoachLLM: Sendable {
    /// The state to show the UI (drives whether chat is offered at all).
    var availability: CoachAvailability { get }

    /// Answer a position question. `system` is the coach persona/instructions;
    /// `prompt` is the engine-grounded facts + the user's question. `sessionID`
    /// continues a prior thread when the backend supports it.
    func generate(system: String, prompt: String, sessionID: String?) async throws -> CoachReply

    /// Stream the answer as it's produced, yielding the *cumulative* text so far on
    /// each step (so the UI can show it filling in). Backends that can't stream get
    /// a default that emits the whole answer once.
    func stream(system: String, prompt: String, sessionID: String?) -> AsyncThrowingStream<String, Error>
}

public extension CoachLLM {
    /// Default: fall back to a single non-streaming call, emitted as one chunk.
    func stream(system: String, prompt: String, sessionID: String?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let reply = try await generate(system: system, prompt: prompt, sessionID: sessionID)
                    continuation.yield(reply.answer)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Raised with a user-facing message when a coach call can't complete.
public struct CoachError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}
