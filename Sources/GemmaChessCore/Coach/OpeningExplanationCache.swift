//  OpeningExplanationCache.swift
//  Seam for caching opening-trainer coach explanations, so a canned question
//  like "why is Nf3 the book move here?" is answered by an LLM call ONCE per
//  (line, move) -- not once per user, since the correct answer for a fixed
//  named opening line's fixed move is the same for everybody. This is a
//  meaningful cost saver once the coaching feature (U-coach, Pro-gated) sees
//  real traffic: the opening book is a small, static, shared dataset (~3.7k
//  ECO lines), so the space of distinct explanations is bounded and highly
//  repeatable across users.
//
//  This file is deliberately prep, not the real thing: `NoOpOpeningExplanationCache`
//  is the default and only implementation today (always a miss, discards
//  writes) -- there is no backend yet. The plan is a shared SQL-backed cache
//  (e.g. Supabase/Postgres) keyed on `(lineID, moveIndex)` -> explanation text,
//  read/written by `chesscoach-gateway` (see docs/plans/2026-07-08-001-feat-paid-tier-metering-backend-plan.md
//  for that backend's shape) rather than the client, so the cache is shared
//  across every user's device instead of siloed per-install. Swapping in a
//  real implementation later is just conforming a new type to this protocol
//  and changing `OpeningTrainerViewModel`'s default -- no call-site changes.
//
//  Caching NEVER bypasses the Pro entitlement check: a cache hit still only
//  happens after `CoachOrchestrator` (or an equivalent gate) has confirmed
//  the caller is entitled. The cache exists to cut AI-provider cost on calls
//  that were already authorized, not to give free users a back door to
//  coaching content.

import Foundation

/// A cache for canned, per-(line, move) opening explanations. Free-form
/// follow-up questions are NOT cached here -- only the deterministic "why is
/// this the book move" explanation, since that's the part that's identical
/// across users and worth deduplicating.
public protocol OpeningExplanationCache: Sendable {
    /// A previously-stored explanation for this line/move, or `nil` on a miss.
    func cachedExplanation(lineID: String, moveIndex: Int) async -> String?

    /// Stores a freshly-generated explanation for reuse by any future caller
    /// hitting the same `(lineID, moveIndex)`.
    func store(explanation: String, lineID: String, moveIndex: Int) async
}

/// Always a miss, discards every write -- the only implementation until a
/// real backend-backed cache exists (see this file's header). Safe as a
/// permanent default: with no cache, behavior is identical to "no cache
/// exists," which is exactly today's state.
public struct NoOpOpeningExplanationCache: OpeningExplanationCache {
    public init() {}
    public func cachedExplanation(lineID: String, moveIndex: Int) async -> String? { nil }
    public func store(explanation: String, lineID: String, moveIndex: Int) async {}
}
