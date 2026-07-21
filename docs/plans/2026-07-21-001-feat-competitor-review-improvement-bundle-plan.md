---
title: "feat: Competitor-Review-Driven Improvement Bundle"
date: 2026-07-21
origin: docs/brainstorms/2026-07-21-competitor-review-improvement-bundle-requirements.md
depth: Deep
---

# feat: Competitor-Review-Driven Improvement Bundle

## Summary

Four features (a fifth — username import — turned out to already be shipped) that each target a specific competitor-review complaint or praise pattern, all constrained to zero backend/API cost: a human-like engine opponent (opt-in, opening variety plus MultiPV-weighted move sampling at low skill), free local "why" hint explanations (no LLM), shareable result cards for game-over and puzzle moments (`ImageRenderer`, on-device), a free-tier onboarding slide, and a small nudge on the existing import screen pointing users toward the Weakness Report. Everything runs on-device or against the free public chess.com/Lichess APIs already integrated; ChessCoach's own gateway is untouched.

## Problem Frame

Research into App Store/review feedback for Dr. Wolf, Noctie, chess.com, and Lichess (see origin) surfaced concrete, actionable gaps against ChessCoach's current state. Planning-time research (this document) additionally found that username import (chess.com + Lichess, browse-and-pick, per-game analyze) already shipped under `docs/plans/2026-07-18-001-feat-free-tier-feature-expansion-plan.md` — its fetch counts and differentiated error messages are being kept as-is rather than downgraded to match the original brainstorm's simpler assumptions (see origin's Finding 1 resolution). What's actually missing from that feature is a small nudge connecting a successful import to the Weakness Report, which is in scope here (U5).

Planning-time research also found no existing "puzzle streak" concept matching the brainstorm's original framing. Two real candidates exist instead: `PuzzleRushSession.correctCount` (a timed-run score) and `PuzzleStreakStore`'s daily-solve streak. Both get their own share-card variant (see origin's Finding 2 resolution).

(see origin: docs/brainstorms/2026-07-21-competitor-review-improvement-bundle-requirements.md)

## Requirements

- **R1 — Human-like opponent.** An opt-in, off-by-default "Human-like" toggle in Play setup. When on, at lower skill settings only: opening moves draw varied lines from the bundled ECO book, and replies use MultiPV-weighted sampling instead of always-best.
- **R2 — Free hint explanations.** The existing free hint gains a one-line, template-based "why" rationale derived from facts already computed for that hint (no LLM, no network), visually marked as free-tier.
- **R3 — Shareable result cards.** Game-over (Play), Puzzle Rush session-end, and daily-streak-milestone moments each offer a share-sheet card image, rendered on-device.
- **R4 — Free-tier onboarding slide.** A new onboarding page stating what's free (no ads, no daily puzzle cap, no cheaters).
- **R5 — Import → Weakness Report nudge.** After a successful account import, a light prompt points the user toward reviewing a few of the freshly-imported games.
- **R6 — App Store copy.** A text file with free-tier-messaging copy for the App Store description, delivered as a non-code artifact.
- **Cost constraint (all units):** no calls to ChessCoach's gateway, no LLM calls, no new dependencies, every network/parse/render path fails soft (never crashes the app).

## Key Technical Decisions

### KTD-1: Human-like opening variety reuses `Openings.lines`, gated to book depth, not full-game replay

The bundled ECO book (`Openings.lines`, already lazily parsed once per process — see `Sources/GemmaChessCore/Chess/Openings.swift`) contains every vendored line's full move sequence. Rather than building a new opening-selection dataset, `newGame`/the engine-reply path picks a random line whose SAN prefix matches moves played so far, and continues along it for a bounded number of plies (a "book depth," not indefinitely) before handing off entirely to normal engine play. This reuses parsed, already-in-memory data with no new file I/O.

### KTD-2: Move sampling — weighted pick over MultiPV candidates, engine-side, only at low skill

`EnginePool.playMove` currently always requests MultiPV=1 (single best move) and relies solely on Stockfish's "Skill Level" for imprecision (`Sources/GemmaChessCore/Engine/EnginePool.swift:127-152`). The human-like path instead requests MultiPV (e.g. 3-5, reusing the pattern already used by `EnginePool.analyse`/`requestHint`'s two-line request) and applies a skill-scaled weighted random pick across the returned candidate lines — never the caller passing a made-up "human" move, always a real engine-approved candidate at real engine strength, just not always rank #1. Only fires below a defined low-skill threshold; at/above it, behavior is byte-for-byte identical to today (MultiPV=1, best-only).

### KTD-3: Hint rationale — new engine-free fact-to-template layer, not a `Motifs` reuse

`Motifs.tagMotifs` (`Sources/GemmaChessCore/History/Motifs.swift`) tags *mistakes already made* by comparing a played move against the best move — backward-looking. The hint's "why" needs the opposite: explain the *recommended* move before it's played. Rather than repurposing `Motifs`, a new small function builds one-line rationales directly from the `EngineLineReport`/`CoachLineInfo` data `requestHint` already computes (`Sources/GemmaChessCore/ViewModels/PlayViewModel.swift:279-336`), using the same low-level primitives `Motifs` already relies on (`BoardAttacks.parseUCI`, `.value`, hanging/fork detection) to classify the recommended move's nature (captures material, escapes/creates a threat, develops, etc.) and pick a template sentence. No LLM, no new engine calls — it consumes the analysis `requestHint` already ran.

### KTD-4: Share cards render with `ImageRenderer`, not a custom drawing pass

Per user direction: `ImageRenderer` (SwiftUI, iOS 16+, already comfortably within the app's iOS 18 deployment target) snapshots an already-built SwiftUI view into a `UIImage` in one render pass — the simplest and lightest-weight option, and avoids hand-rolled `UIGraphicsImageRenderer` drawing code (the pattern `BoardScannerView.swift:485` uses for a different purpose — downscaling a captured photo, not composing new content). Each card is a small, static-content SwiftUI view (theme-styled, a handful of `Text`/`Image` elements) — rendering it is a single lightweight pass, not a repeated or animated one.

### KTD-5: Import nudge is UI-only — no change to `GameImportClient`/`GameImportView`'s existing fetch/error behavior

Per the reconciliation decision in origin: the existing import implementation (fetch counts, differentiated `GameImportError` messages) stays exactly as shipped. This plan only adds a post-fetch prompt in `GameImportView` pointing at the fetched list.

## Implementation Units

### U1. Human-like opponent — opening book variety

**Goal:** When the Human-like toggle is on, opening moves for the first several plies are drawn from a randomly selected matching ECO line instead of always the engine's own choice.

**Requirements:** R1

**Dependencies:** none

**Files:**
- Modify: `Sources/GemmaChessCore/Chess/Openings.swift` (a lookup helper: given moves-played-so-far as SAN, return matching lines and a random continuation move)
- Modify: `Sources/GemmaChessCore/ViewModels/PlayViewModel.swift` (engine-reply path consults the book helper first, before calling `EnginePool.playMove`, while `humanLikeEnabled` is true and within the book-depth window)
- Modify: `Sources/GemmaChessCore/ViewModels/PlayDisplaySettings.swift` (persist the toggle, mirroring `defaultEngineSkill`'s pattern)
- Test: `Tests/GemmaChessCoreTests/OpeningsHumanLikeTests.swift` (new)
- Test: `Tests/GemmaChessCoreTests/PlayHumanLikeOpeningTests.swift` (new)

**Approach:** A book-continuation lookup takes the SAN moves played so far and the side to move, filters `Openings.lines` to lines whose prefix matches exactly, and returns a random pick from those lines' next move. When no line matches (game has left book, or moves-so-far is empty and this is White's very first move — every line still has *a* first move, so this only becomes empty once the game diverges from every vendored line), the caller falls through to normal engine play for the rest of the game. Bound the window to a small fixed ply count (e.g. first 6-8 plies) so the effect is "varied openings," not "the engine can't play its own game."

**Patterns to follow:** `Openings.search`'s case-insensitive filtering style; `OpeningTrainerViewModel`'s existing consumption of `Openings.lines` for a similar "pick from matching lines" need.

**Test scenarios:**
- Happy path: with the toggle on and an empty move history, the book helper returns a move consistent with some real ECO line's first move.
- Happy path: given a SAN prefix matching multiple lines (e.g. after 1.e4), the helper's random pick is always among lines whose prefix actually matches — never a move from an unrelated line.
- Edge case: a SAN prefix matching zero lines (an unusual continuation) returns nil, and the caller falls through to `EnginePool.playMove` unchanged.
- Edge case: past the book-depth ply window, the book helper is never consulted even if a matching line still exists deeper.
- Integration: `PlayViewModel.newGame` + a few plies with the toggle on produces a legal, playable game exactly like the toggle-off path, differing only in which specific opening moves the engine chooses.
- Toggle-off regression: with the toggle off, engine replies are byte-for-byte the same as before this unit (no book consultation at all).

**Verification:** A game played with the toggle on visibly varies its opening choice across repeated new games at the same skill; a game with the toggle off is unaffected.

---

### U2. Human-like opponent — weighted MultiPV move sampling

**Goal:** At lower skill settings with the toggle on, engine replies (once out of book) are chosen via weighted random sampling across the engine's own top candidate moves, not always rank #1.

**Requirements:** R1

**Dependencies:** U1 (shares the toggle's persisted setting; independent otherwise — can be built in parallel and only integrates at the `PlayViewModel` call site)

**Files:**
- Modify: `Sources/GemmaChessCore/Engine/EnginePool.swift` (a new/extended entry point requesting MultiPV replies for a "human-like" move choice, reusing `analyse`'s existing MultiPV plumbing rather than `playMove`'s single-line path)
- Modify: `Sources/GemmaChessCore/ViewModels/PlayViewModel.swift` (the engine-reply path picks via weighted sampling when human-like is on and skill is below the low-skill threshold, else calls the existing `playMove` unchanged)
- Test: `Tests/GemmaChessCoreTests/EnginePoolHumanLikeSamplingTests.swift` (new)

**Approach:** Reuse `EnginePool.analyse(fen:depth:multipv:)`'s existing MultiPV request/response path (already used by `requestHint`) to get the top N candidate lines for the position, then weight-sample one — weighting scaled so higher skill within the "low skill" band still favors the best move more strongly than lower skill (e.g. skill-proportional falloff), and never below-skill-band. Above the low-skill threshold, or with the toggle off, the reply path is unchanged (`EnginePool.playMove`, MultiPV=1). Cache/analysis-reuse behavior already present in `EnginePool` (its `cache` dictionary) applies automatically since this reuses `analyse`, not a new bespoke call.

**Technical design:**
```
if humanLikeEnabled && skill < lowSkillThreshold {
    lines = EnginePool.analyse(fen, depth, multipv: N).lines   // top N candidates
    move = weightedSample(lines, skillFactor: skill)            // lower skill -> flatter weights
} else {
    move = EnginePool.playMove(fen, depth, skill)                // unchanged today
}
```
Directional only — exact weighting curve and N are implementation-time choices informed by manual play-testing.

**Patterns to follow:** `requestHint`'s existing `EngineLine.evaluate(...multipv: 2)` call for the request shape; `EnginePool`'s `Key`-based cache for why reusing `analyse` (not a parallel bespoke path) is free performance-wise.

**Test scenarios:**
- Happy path: at a skill below the threshold with the toggle on, sampled moves are always among the engine's own top-N candidates for that position (never an arbitrary/illegal move).
- Happy path: repeated calls at the same low-skill position occasionally choose a non-best candidate (statistically, over many trials) — verifies the sampling isn't secretly always picking index 0.
- Edge case: at/above the low-skill threshold, behavior is identical to calling `playMove` directly (byte-for-byte same move given the same engine state) — no MultiPV path taken.
- Edge case: fewer than N legal candidate lines exist (e.g. very few legal moves) — sampling degrades gracefully to whatever the engine actually returned, no crash on an out-of-bounds weighted pick.
- Toggle-off regression: with the toggle off, `PlayViewModel`'s reply path is unchanged from before this unit regardless of skill.

**Verification:** At a low skill with the toggle on, observed reply moves are not always the engine's single best move across several games, while always remaining legal, engine-sourced candidates.

---

### U3. Free local "why" hint explanations

**Goal:** The existing free hint (`PlayViewModel.requestHint`) shows a one-line, template-based rationale for the recommended move with no network call, visually marked as free-tier, without disturbing the existing Pro coach rationale path.

**Requirements:** R2

**Dependencies:** none

**Files:**
- Create: `Sources/GemmaChessCore/Coach/HintRationaleTemplates.swift` (fact classification + template selection, engine-free)
- Modify: `Sources/GemmaChessCore/ViewModels/PlayViewModel.swift` (`requestHint` populates a free rationale immediately from the already-computed `EngineLineReport`, before/independent of the existing Pro coach streaming path)
- Modify: `Sources/GemmaChessCore/UI/PlayView.swift` (hint card shows the free rationale with a small free-tier label; Pro coach's richer streamed rationale, when present, supersedes/augments it in the existing slot)
- Test: `Tests/GemmaChessCoreTests/HintRationaleTemplatesTests.swift` (new)

**Approach:** Given the recommended move's UCI, the position FEN, and the `EngineLineReport` `requestHint` already has in hand, classify the move using the same low-level primitives `Motifs.swift` already exposes (`BoardAttacks.parseUCI`, `.value`, hanging-piece/fork detection) plus the report's own eval/mate data: does it capture material, deliver/threaten mate, escape or block a threat, or none of those (a quieter developing/positional move)? Map the classification to a short template sentence (e.g. "Wins a pawn" / "Threatens mate in 2" / "Defends the knight on f3"). Distinct field from the existing Pro `hint?.rationale` (which streams from the coach) so the two can't collide — e.g. `hint?.freeRationale` populated synchronously, `hint?.rationale` unchanged, populated later only when Pro coaching is enabled.

**Patterns to follow:** `Motifs.tagMotifs`'s use of `BoardAttacks` primitives for engine-free classification; `HintInfo`'s existing struct shape for adding a new field without disturbing existing call sites.

**Test scenarios:**
- Happy path: a position where the best move captures a piece of clear material value produces a "wins material" template with the correct piece name.
- Happy path: a position where the best move delivers or sets up a forced mate produces a mate-specific template.
- Happy path: a quiet developing move with none of the above produces a sensible fallback template rather than an empty string.
- Edge case: the recommended move is ambiguous between two classifications (e.g. captures AND threatens mate) — a defined priority order picks one template, not a crash or blank output.
- Edge case: malformed/unparseable UCI (should not happen given `requestHint`'s existing guards, but the classifier itself must not crash on bad input) falls back to a generic template rather than throwing.
- Integration: `PlayViewModel.requestHint` populates the free rationale synchronously (same tick as the best-move arrows appear), independent of whether the Pro coach is enabled/available — verified by requesting a hint with coaching disabled and confirming the free rationale is still present.

**Verification:** Requesting a hint with the Pro coach off still shows a plausible, engine-grounded one-line "why," and it never differs in content from what the engine actually found for that position.

---

### U4. Shareable result cards — rendering + Play game-over

**Goal:** A reusable on-device card-rendering utility, first wired to the Play mode game-over banner, producing an image the iOS share sheet can send.

**Requirements:** R3

**Dependencies:** none

**Files:**
- Create: `Sources/GemmaChessCore/UI/ShareCardRenderer.swift` (generic `ImageRenderer`-based "render this SwiftUI view to `UIImage`" utility)
- Create: `Sources/GemmaChessCore/UI/GameResultShareCard.swift` (the card's SwiftUI content for a finished Play game — result, opening name if known, theme-styled)
- Modify: `Sources/GemmaChessCore/UI/PlayView.swift` (`GameOverBanner` gains a share button wired to render + present the share sheet)
- Test: `Tests/GemmaChessCoreTests/ShareCardRendererTests.swift` (new)

**Approach:** `ShareCardRenderer` wraps `ImageRenderer(content:)`, fixing a card size and scale, and returns an optional `UIImage` (nil on render failure — fails soft, never crashes; the share button simply doesn't appear/no-ops if rendering fails). `GameResultShareCard` is a plain themed SwiftUI view (no live game state dependencies beyond what's passed in), so it's cheap to instantiate and render once, on-demand, only when the user taps "Share" — never rendered proactively or repeatedly.

**Patterns to follow:** Existing themed-card styling (`theme.cardBackgroundColor`/`cardBorderColor`, `RoundedRectangle` overlays) used throughout `RootView.swift`/`WeaknessReportView.swift`, so the card visually matches the app.

**Test scenarios:**
- Happy path: rendering a `GameResultShareCard` with a win result produces a non-nil image of the expected fixed size.
- Happy path: rendering with a loss/draw result also succeeds (verifies the renderer isn't accidentally coupled to one outcome's layout).
- Edge case: an unusually long opening name or player-facing string doesn't crash the render pass (truncation/wrapping handled by the card's own layout, not the renderer).
- Failure path: if `ImageRenderer` returns nil (documented possibility, e.g. extreme memory pressure), the share button's action becomes a no-op rather than presenting a broken/empty share sheet.

**Verification:** Tapping Share on a finished Play game's game-over banner presents the iOS share sheet with a legible result-card image attached, and the app never crashes if rendering fails.

---

### U5. Shareable result cards — Puzzle Rush and daily-streak variants

**Goal:** Puzzle Rush's session-end summary and a daily-streak milestone each get their own share card, reusing U4's renderer.

**Requirements:** R3

**Dependencies:** U4 (reuses `ShareCardRenderer`)

**Files:**
- Create: `Sources/GemmaChessCore/UI/PuzzleRushShareCard.swift`
- Create: `Sources/GemmaChessCore/UI/StreakShareCard.swift`
- Modify: `Sources/GemmaChessCore/UI/PuzzleRushView.swift` (session-end summary gains a share button)
- Modify: `Sources/GemmaChessCore/UI/PuzzlesView.swift` or wherever streak state is first surfaced post-solve (a share button/prompt appears only at defined milestone thresholds, e.g. 5/10/30 days)
- Test: `Tests/GemmaChessCoreTests/PuzzleShareCardsTests.swift` (new)

**Approach:** `PuzzleRushShareCard` renders `correctCount` (and `wrongAttempts` if present) from the finished `PuzzleRushSession`. `StreakShareCard` renders `PuzzleStreakStore.currentStreak`, but the share affordance itself only appears when the just-updated streak crosses a milestone threshold (a small fixed list, e.g. 5, 10, 30, 50, 100) — not on every single day's solve, to avoid the button feeling like noise. Both reuse `ShareCardRenderer` from U4 unchanged.

**Patterns to follow:** U4's `GameResultShareCard` as the template for card composition; `PuzzleStreakStore.recordSolve`'s existing return value (the resulting streak) as the natural place to check "did this cross a milestone."

**Test scenarios:**
- Happy path: rendering a Puzzle Rush card with a representative `correctCount` produces a non-nil image.
- Happy path: rendering a streak card at a milestone value (e.g. 10) produces a non-nil image showing that count.
- Edge case: a streak that increments but does NOT land on a milestone (e.g. 6) does not trigger the share affordance to appear.
- Edge case: a streak that resets to 1 (broken streak) never shows a milestone share prompt for the reset value.
- Integration: `PuzzleStreakStore.recordSolve`'s returned streak value, when it equals a milestone, is what the calling view uses to decide whether to surface the share button — covered by a test asserting the milestone-check helper's boundary values precisely (4→no, 5→yes, 6→no, 9→no, 10→yes).

**Verification:** Finishing a Puzzle Rush run always offers a share option; solving a puzzle only offers a streak share option on milestone days, and the rendered card values match the actual session/streak data.

---

### U6. Free-tier onboarding slide

**Goal:** Onboarding gains a fifth page stating what's free (no ads, no daily puzzle cap, no cheaters).

**Requirements:** R4

**Dependencies:** none

**Files:**
- Modify: `Sources/GemmaChessCore/UI/OnboardingView.swift` (append a new `OnboardingPage` to the existing static `pages` array)
- Test expectation: none -- pure content addition to an existing, already-tested static array/paging view; no new behavior to unit test beyond what's already covered for the paging mechanism itself.

**Approach:** A single new `OnboardingPage` entry, styled identically to the existing four, placed last (after "Sharpen Your Tactics, Free," which it naturally extends). Copy states the three free-tier facts plainly, avoiding comparison-to-named-competitors language.

**Patterns to follow:** The existing four `OnboardingPage` entries' icon/title/body/footnote shape exactly.

**Verification:** Onboarding's page indicator shows 5 dots instead of 4, and swiping to the last page shows the new free-tier content.

---

### U7. Import → Weakness Report nudge

**Goal:** After a successful account import in `GameImportView`, a light prompt points the user toward reviewing a few of the freshly-fetched games.

**Requirements:** R5

**Dependencies:** none

**Files:**
- Modify: `Sources/GemmaChessCore/UI/GameImportView.swift` (`fetchAccount()`'s success path sets a nudge-visible flag when `fetchedGames` is non-empty; a small text/callout renders above `gamesSection` when set)
- Test: `Tests/GemmaChessCoreTests/GameImportNudgeTests.swift` (new, or an addition to existing `GameImportView`-adjacent tests if a SwiftUI-view-level test target already exists for it — otherwise this is primarily a `fetchAccount()` state-transition test at the view-model-ish level GameImportView already exposes via its `@State`)

**Approach:** A pure UI addition — no change to `GameImportClient`'s fetch/error logic (per KTD-5). The nudge is a plain themed text/callout, dismissed implicitly once the user analyzes at least one game (or simply always visible while `fetchedGames` is non-empty and the list section is showing — implementation-time call on exact dismiss behavior).

**Patterns to follow:** `WeaknessReportView`'s existing tone/copy style ("a coach-synthesized look at your recent play...") for cross-referencing the Weakness Report by name.

**Test scenarios:**
- Happy path: a successful fetch with 1+ games sets the nudge-visible state.
- Edge case: a successful fetch with zero games (valid empty response, not an error) does not show the nudge (nothing to review yet).
- Edge case: a failed fetch (any `GameImportError` case) does not show the nudge.

**Verification:** Importing games with the Weakness Report gap in mind, a user sees a specific pointer toward reviewing some of what they just imported, not just a silent list.

---

## Non-Code Deliverable

### App Store description copy (R6)

Not an implementation unit — a text file with free-tier-messaging copy for the App Store listing (no ads, no daily puzzle cap, no cheaters), written once product copy is finalized alongside U6's in-app wording so the two stay consistent. No file path constraint; delivered wherever the App Store Connect metadata workflow expects it.

---

## Scope Boundaries

### Deferred for later (carried from origin)
- Puzzle-session-complete (non-Rush, non-streak) share cards
- Weakness Report share cards
- Distinguishing network-failure vs. not-found error states for username import (already exceeded by the existing implementation — no work needed)
- A user-adjustable fetch count for username import
- Surfacing free-tier messaging in Settings in addition to onboarding

### Outside this plan's scope entirely (carried from origin)
- Any change to Pro-gated coach behavior, prompts, or the gateway
- Any new backend endpoint or LLM call
- Deeper engine-analysis features or coach personality customization

## Open Questions (deferred to implementation)

- Exact low-skill threshold (U2) and book-depth ply window (U1) — tune via manual play-testing, not a planning-time decision.
- Exact MultiPV count and weighting curve for sampling (U2) — same.
- Exact milestone thresholds for the streak share card (U5) beyond the illustrative 5/10/30/50/100 list.
- Exact hint-rationale template wording and priority order when multiple classifications apply (U3).
- Exact free-tier-label visual treatment on the hint card (U3) — a small tag/icon, left to implementation-time UI judgment per origin's resolution ("you can label it as free").

## Sources & Research

- Origin: `docs/brainstorms/2026-07-21-competitor-review-improvement-bundle-requirements.md`
- Prior plan (username import's actual origin): `docs/plans/2026-07-18-001-feat-free-tier-feature-expansion-plan.md`
- Code read directly during planning: `Sources/GemmaChessCore/Chess/Openings.swift`, `Sources/GemmaChessCore/Engine/EnginePool.swift`, `Sources/GemmaChessCore/Engine/EngineLine.swift`, `Sources/GemmaChessCore/History/Motifs.swift`, `Sources/GemmaChessCore/ViewModels/PlayViewModel.swift`, `Sources/GemmaChessCore/UI/GameImportView.swift`, `Sources/GemmaChessCore/Import/GameImportClient.swift`, `Sources/GemmaChessCore/Puzzles/PuzzleStreakStore.swift`, `Sources/GemmaChessCore/Puzzles/PuzzleRushSession.swift`, `Sources/GemmaChessCore/UI/PuzzleRushView.swift`, `Sources/GemmaChessCore/UI/OnboardingView.swift`, `Sources/GemmaChessCore/UI/PlayView.swift`, `Sources/GemmaChessCore/UI/BoardScannerView.swift` (existing `UIGraphicsImageRenderer` precedent, ruled out per KTD-4).
