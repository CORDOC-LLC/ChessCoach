---
title: "Coach Profile: Weakness Report"
date: 2026-07-19
tier: deep-feature
---

# Coach Profile: Weakness Report

## Problem Frame

ChessCoach already has a quiet, unfinished idea of personalization: `CoachingProfile`/`CoachingProfileBuilder` (`Sources/GemmaChessCore/History/CoachingProfile.swift`) aggregates a player's reviewed games into recent-form accuracy, top recurring tactical motifs, weakest game phase, and per-opening/per-speed stats — and a "Personalize" toggle in `CoachChatView.swift:35` feeds this into Review mode's coach chat. It's off by default, easy to miss, not separately monetized (it just quietly enriches an already-Pro coach call), and — critically — it only reads games explicitly imported into Review mode via `HistoryStore`. Play mode's own games (`SavedGameStore`, the primary "Play a game" loop from Home) never reach it. A user who only ever plays in-app would see an empty profile.

This brainstorm turns that quiet mechanism into a real, visible, monetizable feature: a **Weakness Report** — a coach-synthesized narrative that names a user's recurring pattern (a missed tactical motif, a weak game phase, a plateaued rating) and points them at a specific, free way to fix it (a Lesson, a puzzle theme). This is additive to the app's established priority order (virality → utility/ratings → monetization): it must never gate anything currently free, and its "point to the fix" behavior is designed to *drive* usage of free features (Lessons, Puzzles), not compete with them.

## Actors

- **Free user**: sees a real, locally-computed teaser stat on Home (e.g., a top recurring motif) with the narrative synthesis locked behind Pro.
- **Pro subscriber (managed backend)**: can open the full Weakness Report, request a refresh once enough new data exists.
- **Pro subscriber (BYOK Gemini, local/TestFlight only)**: explicitly does NOT get the Weakness Report — see R7/KTD-3.

## Requirements

- **R1**: A "Weakness Report" screen synthesizes a coach narrative from the user's aggregated play data — naming a specific recurring flaw (a missed motif, a weak phase, a plateaued rating trend) and pairing it with a concrete, free next step (a specific Lesson or puzzle theme).
- **R2**: The report is reached via a themed card on Home, below the existing action rows — not a new tab (Home's tab bar is a fixed four items per the just-shipped tab-bar redesign).
- **R3**: The report's underlying data source unifies Play mode's own games with Review-imported games. Play mode games are folded into the same `HistoryStore`/`GameRecord` pipeline Review already populates — as a deliberate, approved side effect, this also means Play mode games will now appear in Review mode's own game-history list, which today only shows explicitly-imported games.
- **R4**: Puzzle theme accuracy, Opening Trainer familiarity, and any other non-game local stats are explicitly out of scope for v1 — the report is built from game history only. (See Scope Boundaries.)
- **R5**: The report's narrative is cached, not regenerated on every open. A "Refresh" action exists but is disabled until enough new games have accumulated since the last generation (exact threshold deferred to planning — mirrors the existing `ReviewPromptStore` engagement-threshold pattern).
- **R6**: Local aggregation (motif counts, accuracy, phase-loss, the free teaser stat) computes lazily — only when the user actually views the Home card or report screen, never proactively in the background — and never triggers a network or LLM call regardless of Pro status. Only the narrative synthesis itself is a paid backend call, and it fires only when a Pro user explicitly opens/refreshes the report.
- **R7**: The Weakness Report is available only through the managed coach backend (`chesscoach-gateway`). BYOK Gemini users (local/TestFlight builds using their own API key) do not get this feature — the coaching prompt must never ship inside this open-source client.
- **R8**: Free (non-Pro) users see a real, already-free stat as a teaser (e.g., "Your most common miss this month: x-ray attacks (12x)") with the coach's narrative ("why this happens and how to fix it") locked behind a Pro upsell. Not a content-free "upgrade to see" card.
- **R9**: Tone is growth-framed and non-judgmental throughout, consistent with the app's persona ("kind, never shaming"). Every named flaw is immediately paired with a concrete, actionable next step — never stated as a bare criticism.
- **R10**: Product direction (not this feature's build scope): all coach prompts app-wide — not just the Weakness Report's — should eventually move server-side, retiring the BYOK Gemini path for coaching entirely. This is a deliberate long-term decision, captured here so it isn't lost, but its actual migration is deferred (see Scope Boundaries) — it touches four already-shipped call sites (chat, hint rationale, per-move notes, end-of-game summary) and is large enough to deserve its own brainstorm/plan.

## Key Decisions

- **Managed-backend-only, prompt stays private (R7).** The alternative — a simpler, client-side prompt for BYOK users alongside a richer private one for managed users — was considered and rejected: maintaining two prompt qualities is real ongoing cost, and the simpler public prompt would partially leak the private one's structure anyway.
- **Unify Play + Review game history, accept the side-effect (R3).** The alternative (merge the two sources only at report-build time, leaving Review's history list untouched) would avoid the side effect, but the user explicitly chose the unified/simpler data model, accepting that Play games now show up in Review's list too.
- **Teaser cost discipline (R6, R8).** Explicitly resolved after initial scoping: the free teaser must not create meaningful processing cost for users who never convert. Local aggregation is cheap and already happens elsewhere in the app (puzzle/motif stats); nothing new is computed proactively, and nothing paid is ever triggered for a free user.
- **Cache + gated manual refresh, not eager regeneration (R5).** Regenerating on every open would pay for an identical LLM call with no new data most of the time — real, avoidable backend cost for a feature that's supposed to be cost-justified. Auto-refresh-on-threshold (no user action) was also considered and rejected as harder to reason about than an explicit, gated button.
- **Growth-framed tone over blunt directness (R9).** A more clinical/blunt phrasing style was considered and rejected in favor of softer, coaching-app-style language, to protect the persona's "kind" trait.

## Scope Boundaries

**Non-goals:**
- No change to any currently-free feature's availability or gating.
- No puzzle/lesson/opening-trainer data sources in v1 (game history only — R4).
- No BYOK support for this feature (R7).

### Deferred for later
- Expanding the profile to also draw on Puzzle theme accuracy, Opening Trainer familiarity, and streak data (explicitly discussed as a future direction, not v1).
- Feeding the broadened profile into *every* coach call app-wide (ambient personalization everywhere), not just a dedicated report screen.
- Deeper engine analysis on demand and coach voice/personality customization — separate paid-surface ideas discussed alongside this one, explicitly out of scope here.

### Deferred to Follow-Up Work
- **Migrating all existing coach prompts server-side and retiring BYOK for coaching (R10).** This is a confirmed product direction, not a rejected idea — but migrating four already-shipped call sites (Play chat, Opening Trainer coach panel, Lessons Ask button, Review chat/summary) to a backend-prompt architecture, and deciding what happens to the BYOK path and `CoachBackendPreference` as a result, is a large, separate architectural change. It deserves its own brainstorm to work through backward compatibility and the BYOK sunset path, rather than folding into this feature's plan.
- The exact "enough new games" refresh threshold (R5) — a planning-time tuning call, not a product-shape decision.

## Outstanding Questions

- What exactly counts as "a recurring pattern" worth naming (minimum sample size — e.g., does 3 games with one blunder-motif count, or does it need 10+)? Deferred to planning; likely mirrors `CoachingProfileBuilder`'s existing aggregation thresholds.
- Whether abandoned/very-short Play games (e.g., resigned in under 10 plies) should be excluded from the unified history to avoid noise — deferred to planning.
- The exact free teaser stat to feature (top motif vs. weakest phase vs. something else) — a presentation-tier decision, deferred to planning.

## Success Criteria

- A Pro subscriber can open a Weakness Report from Home and see a specific, correctly-computed recurring pattern from their actual play (not a generic message), paired with a real, tappable pointer to a Lesson or puzzle theme.
- A free user sees a real personalized stat on the Home teaser, with zero backend/LLM calls made on their behalf.
- Play mode games are provably reflected in the report (verified via a game played entirely in Play mode, never reviewed, still surfacing a relevant pattern).
- No coaching prompt text for this feature exists anywhere in this open-source client repo.

## Sources & Research

- `Sources/GemmaChessCore/History/CoachingProfile.swift` — existing aggregation logic this feature extends.
- `Sources/GemmaChessCore/UI/CoachChatView.swift:35` — existing, low-visibility "Personalize" toggle.
- `Sources/GemmaChessCore/History/HistoryStore.swift:292,298` — `recordGame`/`appendRecord`, currently called only from `ReviewViewModel.swift:130`.
- `Sources/GemmaChessCore/Coach/CoachOrchestrator.swift` — existing `profileFacts` parameter threading, and the uniform `ProEntitlementStore.requireProOrThrow()` gate this feature reuses.
- `Sources/GemmaChessCore/Coach/CoachPrompt.swift` — existing client-side prompt templates (`chatInstructions`, `summaryInstructions`) that stay as-is for now per R10's deferred scope.
- `Sources/GemmaChessCore/Puzzles/PuzzleRatingStore.swift`, `PuzzleProgressStore.swift`, `Sources/GemmaChessCore/**/PlayStatsStore.swift`, `OpeningTrainerStore.swift` — verified these lack the time-series/accuracy-rate data some illustrative "flaws" would need (informed R4's decision to exclude them from v1).
