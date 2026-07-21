---
date: 2026-07-21
topic: unified-coach-card
---

# Unified Coach Card in Play

## Summary

Merge Play's "Move Review" card and "Coach" card into one Coach card that owns all commentary about the move just played: engine verdict + a short engine comment on both tiers, with the Pro coach's written prose added beneath for subscribers. The hint (bulb) stays a separate surface for the move about to be played, becomes engine-only on every tier, and shows as its own compact card above Coach while the bulb is on. A single Coach toggle replaces today's separate Move Review and Coach switches.

---

## Problem Frame

Play currently splits engine commentary across three differently-controlled surfaces: a hint card that appears only after tapping the lightbulb (no toggle of its own), a "Move Review" card gated by `showMoveComments`, and a "Coach" card gated by `showCoach`. Free users see Stockfish-derived content in two places and Pro users see LLM prose in a third, so the same conceptual thing ("the app commenting on my game") is scattered, and the toggle set in the ⋯ menu doesn't map to how users think about it. The felt result (screenshots IMG_0359/IMG_0358) is an overwhelming stack of cards with no single, simple way to turn coaching on or off.

---

## Key Decisions

- **Coach explains the last move; Stockfish suggests the next one.** The Coach card is exclusively backward-looking commentary; the hint (bulb) is exclusively forward-looking suggestion. This one rule replaces the current hint/review/coach split.
- **Pro adds, never replaces.** The engine verdict and engine comment render identically on both tiers; Pro prose appears beneath them. Free users see a complete card with nothing visibly locked.
- **Hints are engine-only on every tier.** The current Pro-streamed hint rationale is removed. This trades away a small Pro feature for a clean cost story (a lit bulb never spends credits) and a clean mental model.
- **One Coach toggle, no sub-toggles.** Users who want less commentary turn Coach off entirely; granular control is not offered.

---

## Requirements

**Coach card**

- R1. One "Coach" card replaces the current "Move Review" and "Coach" cards in Play's in-game layout.
- R2. After each player move, the card shows the Stockfish verdict (Best/Good/Inaccuracy/Blunder etc.) and a short engine-derived comment, on both tiers.
- R3. For Pro users with an active entitlement, the coach's written prose streams in beneath the engine content of the same card.
- R4. The card's right-side button reads "Ask" for Pro users (opens coach chat, as today) and "Free" for free users; tapping "Free" opens the Pro paywall.
- R5. A single "Coach" toggle in the ⋯ menu shows/hides the whole card and replaces the current `showMoveComments` and `showCoach` toggles; when off, no coach network calls fire (preserving today's credit-stopping behavior of `showCoach`).

**Hint (bulb)**

- R6. The bulb is an on/off control; while on, a compact hint card appears above the Coach card with the suggested move and a one-line template rationale.
- R7. Hint content is Stockfish-only and identical on both tiers; the Pro-streamed hint rationale is removed.
- R8. Bulb off removes the hint card; the bulb never triggers network calls or credit spend on any tier.

**Toggles**

- R9. Remaining engine-display toggles (e.g. the best-move arrow) fold into or sit beside the single Coach toggle in the ⋯ menu; the menu must not present more commentary toggles than Coach plus the bulb-independent board options (captured pieces, move list, opening name).

---

## Acceptance Examples

- AE1. **Covers R2, R3.** Given a Pro user with Coach on plays an inaccuracy, when the move completes, then the card shows the "Inaccuracy" verdict and engine comment immediately, and the coach's prose streams in below them.
- AE2. **Covers R2, R4.** Given a free user with Coach on plays a blunder, when the move completes, then the card shows the "Blunder" verdict and engine comment with no locked/greyed content, and the card's button reads "Free"; tapping it opens the paywall.
- AE3. **Covers R6, R7, R8.** Given any user turns the bulb on, when a new position is reached, then the hint card shows the engine's suggested move and template rationale with no network call; turning the bulb off removes the card.
- AE4. **Covers R5.** Given a Pro user turns the Coach toggle off, when they continue playing, then no coach card renders and no coach network requests are made.

---

## Scope Boundaries

- Coach chat behavior, the gateway, prompts, and entitlement logic are unchanged — this is Play's in-game commentary UI only.
- Review, Puzzles, Lessons, and Opening Trainer coaching surfaces are untouched.
- No per-feature sub-toggles under Coach (deliberately rejected; revisit only if users ask).
- End-of-game summary/debrief placement is unchanged.

---

## Outstanding Questions

Deferred to planning:

- Exact fate of the `showBestMove` (best-move arrow) toggle — fold into the bulb, into Coach, or keep as a board option (R9 sets the constraint; planning picks the mechanism).
- Whether the bulb's on-state persists across games/app launches or resets per game.
- Visual treatment of the verdict (chip as today vs. inline) within the unified card.

---

## Sources / Research

- Current surfaces and gating: `Sources/GemmaChessCore/UI/PlayView.swift` (hintCard, bestMovesCard, coachCard, ⋯ "Show" menu), `Sources/GemmaChessCore/ViewModels/PlayDisplaySettings.swift` (toggle keys/defaults), `Sources/GemmaChessCore/ViewModels/PlayViewModel.swift` (`requestHint`, `lastVerdict`/`topMoves`, `coachDisplayEnabled`).
- Free hint templates: `Sources/GemmaChessCore/Coach/HintRationaleTemplates.swift` (sole caller today is `requestHint`).
- Prior decisions this builds on: `docs/plans/2026-06-26-001-feat-play-ui-enhancements-plan.md` (current card/toggle structure), `docs/plans/2026-07-18-001-feat-free-tier-feature-expansion-plan.md` (gating rule: backend calls are Pro-only; noted that hints mixed free+Pro content).
