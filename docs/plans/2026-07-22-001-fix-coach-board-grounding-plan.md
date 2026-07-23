---
title: "fix: Ground coach prompts in verified board facts"
type: fix
date: 2026-07-22
---

# fix: Ground coach prompts in verified board facts

**Target repos:** this repo (GemmaChess, client) and the nested `chesscoach-gateway/` repo (private, separate git repo).

## Summary

Wire the current board position into the per-move coach note, and extend the same FEN-grounding mechanism to the end-of-game summary — so the LLM narrates verified facts instead of inventing pieces and squares it was never shown.

---

## Problem Frame

A user reported the Pro coach's per-move note claiming "Black's queen move to c7 is attacking your pawn on c4" when no pawn was on c4 in the actual position. Investigation found the anti-hallucination mechanism this bug needs already exists: `ChatFacts.fen` and the gateway's `boardFactsText(fen)` (`chesscoach-gateway/lib/coachChatPrompt.ts`) parse a FEN into a verified piece list and instruct the model to state only what that list confirms — built specifically to stop small models from misreading FEN and hallucinating pieces. But `PlayViewModel.streamCoachNote` — the exact call site behind this bug — never passes `fen:`, so the model gets no board grounding for the position it's asked to comment on (including the opponent's reply, which happens after the graded move and is otherwise ungrounded). The end-of-game summary path has no FEN field anywhere in its facts schema, so it has never had this protection at all.

External research (academic FEN-parsing benchmarks, several open-source Stockfish+LLM coaching projects, and general RAG/grounding literature) converges on exactly the pattern already built here: don't hand the model raw FEN and hope it parses it — hand it a precomputed, verified piece list plus an explicit "state only what's given" instruction. No new architecture is needed; this plan closes the two places that mechanism isn't reaching.

This is a single reported instance, not a measured rate — the fix is worth making regardless of frequency because it closes a plumbing gap in an already-decided architecture (reusing existing, tested infrastructure) rather than proposing new work to justify.

---

## Key Technical Decisions

- **Reuse `boardFactsText`/`ChatFacts.fen`; do not build a new grounding mechanism.** Both academic literature and this repo's own existing (but incompletely wired) implementation agree: precomputed piece-list grounding, not raw FEN reasoning, is correct. `chesscoach-gateway/lib/coachChatPrompt.ts`'s `boardFactsText`/`placementFromFEN` and the client's `FENBoardEditor.piece(at:inFEN:)` (if ever needed client-side) are the only FEN-parsing utilities this plan touches — no duplicate.
- **Separate "which FEN grounds the wire payload" from "should a fresh engine line be computed."** `CoachOrchestrator.buildChatFacts` currently computes a fresh `current` engine analysis whenever `fen` is non-nil and no `currentFacts` override was supplied (see KTD rationale in Approach). Passing `fen:` from `streamCoachNote` for grounding alone would silently add a redundant Stockfish call the move-note flow doesn't need. Add a distinct grounding-only channel so `ChatFacts.fen` is populated without triggering that extra analysis.
- **Summary grounding covers the flagged moves only, not every ply.** Sending a FEN (and the resulting piece list) for every move in `records`/`mistakes` would bloat the prompt for long games. Ground only the moves already selected as summary-worthy (`CoachFlaggedMove` entries, and — for the live-Play summary — the worst `PlayMoveRecord` mistakes), matching the existing "flagged" selection the summary already makes. This is a scoped decision, not full coverage: summary narrative about unflagged moves stays ungrounded by design, on the assumption that hallucination risk concentrates on the specific positions being commented on in detail (the flagged ones), not brief overall-trend prose. If summaries turn out to hallucinate outside flagged-move commentary, that's a signal to widen this scope, not evidence this plan chose wrong.
- **Wire-contract mirroring convention holds.** Any new field lands in the Swift `Codable` struct and the matching TS Zod schema in the same change, with an identical name — the established pattern from the server-side-prompts migration (`docs/plans/2026-07-21-002-feat-server-side-coach-prompts-plan.md`, KTD-5).

---

## Requirements

**Per-move coach note**

- R1. `PlayViewModel.streamCoachNote`'s request includes the live position (after the opponent's reply) so the gateway can ground its note in a verified piece list, covering the part of the note that discusses the opponent's reply as well as the graded move.
- R2. Adding this grounding does not add a second Stockfish analysis call to the per-move-note flow.

**End-of-game summary**

- R3. `CoachFlaggedMove` (imported-game summary) and `CoachPromptBuilder.PlayMoveRecord` (live-Play summary) carry the FEN of their position, mirrored exactly in the gateway's `CoachFlaggedMoveSchema`/`PlayMoveRecordSchema`.
- R4. The gateway's summary prompt builders (`gameFactsText`, `playGameFactsText`) call `boardFactsText` for the flagged/worst moves and include the same "state only verified facts" instruction the chat/moveNote path already uses.

**Both**

- R5. Neither change alters the client/gateway wire contract for existing fields — only additive fields.

---

## Implementation Units

### U1. Ground the per-move coach note in the post-reply position

- **Goal:** Fix the exact call site behind the reported hallucination.
- **Requirements:** R1, R2, R5.
- **Dependencies:** none.
- **Files:** `Sources/GemmaChessCore/Coach/CoachOrchestrator.swift` (`answerStream`/`answer`/`buildChatFacts`), `Sources/GemmaChessCore/ViewModels/PlayViewModel.swift` (`streamCoachNote`), `Tests/GemmaChessCoreTests/` (existing coach-orchestrator/managed-coach test file — extend, don't create a new one; grep for the current `CoachOrchestratorTests`/mock-URLProtocol pattern first).
- **Approach:** Add a grounding-only FEN channel to `CoachOrchestrator.answerStream`/`answer`/`buildChatFacts` — distinct from the existing `fen:` parameter, which also triggers a fresh `current` engine-line computation when no `currentFacts` override is supplied. The new channel only sets `ChatFacts.fen`; it must not touch `current`. `streamCoachNote` passes the live `self.fen` (the position after the opponent's reply, per its existing doc comment) through this new channel alongside its existing `lastMove`/`moveFen`. The free-form chat call site (`PlayViewModel.swift` ~line 929) is unaffected — it keeps using the existing `fen:` parameter since it wants the fresh current-line analysis.
- **Technical design:** Directional only — `buildChatFacts(..., groundingFen: String? = nil, ...)` with `ChatFacts(fen: fen ?? groundingFen, ...)`. `fen` wins the precedence only because `streamCoachNote` is the sole caller that will ever pass `groundingFen` and it never passes `fen`; the free-form chat call site passes `fen` and never `groundingFen`, so the two are mutually exclusive in practice today. The `if current == nil, let fen { ... }` analysis-triggering branch stays keyed on the original `fen` parameter only, unchanged — `groundingFen` must never reach it.
- **Patterns to follow:** `CoachOrchestrator.swift`'s existing `currentFacts`/`moveFacts` override pattern (a caller-supplied value skips the redundant engine call) — the new grounding channel follows the same "skip work the caller doesn't need" shape.
- **Test scenarios:**
  - `streamCoachNote`'s built `ChatFacts.fen` equals the live post-reply position, not the pre-move `fromFEN`.
  - Adding grounding does not add an extra `EngineLine.evaluate` call in the moveNote path (assert engine-call count, or that `current` in the built facts is nil when no `currentFacts` override was given).
  - The free-form chat call site's existing behavior (fresh `current` computed from `fen:`) is unchanged.
- **Verification:** Existing coach-orchestrator tests pass; a new/extended test confirms the moveNote request body carries `fen` for the post-reply position with no extra engine call.

### U2. Add FEN grounding to game-summary facts (client)

- **Goal:** Give both summary paths the same piece-list protection chat/moveNote already has.
- **Requirements:** R3, R5.
- **Dependencies:** none (parallel to U1).
- **Files:** `Sources/GemmaChessCore/Coach/CoachPrompt.swift` (`CoachFlaggedMove`, `CoachPromptBuilder.PlayMoveRecord`), `Sources/GemmaChessCore/ViewModels/ReviewViewModel.swift` (flagged-move build site), `Sources/GemmaChessCore/ViewModels/PlayViewModel.swift` (`PlayMoveRecord` build site, ~line 555), `Tests/GemmaChessCoreTests/CoachPromptTests.swift`.
- **Approach:** Add an optional `fen: String?` to both structs (optional so older persisted `SavedGame` data — `PlayMoveRecord` is `Codable` and persisted — decodes without migration). Populate `CoachFlaggedMove.fen` in `ReviewViewModel` from `MoveReview.fenAfter` (already carried on each `session.mistakes` entry — no lookup needed); populate `PlayMoveRecord.fen` in `PlayViewModel` from the local `afterFEN` in scope at its build site. Both are the position after the flagged move, matching what the move's classification/eval describe.
- **Patterns to follow:** `PlayMoveRecord`'s existing optional-field precedent (`bestUCI` is already optional for the same forward-compatibility reason, per its doc comment) — mirror that shape for `fen`.
- **Test scenarios:**
  - Encoding a `CoachFlaggedMove`/`PlayMoveRecord` with `fen` set produces JSON containing the field with the exact wire name.
  - Decoding older persisted JSON without a `fen` field succeeds with `fen == nil` (backward compatibility for saved games).
  - Both build sites populate `fen` from the correct position (the flagged move's resulting position, not an off-by-one ply).
- **Verification:** `CoachPromptTests` (or nearest existing file) passes; a saved game persisted before this change still loads.

### U3. Consume summary FEN grounding server-side

- **Target repo:** `chesscoach-gateway/`.
- **Goal:** The summary prompt states only verified facts for its flagged moves, same as chat/moveNote.
- **Requirements:** R4, R5.
- **Dependencies:** U2 (needs the field to exist on the wire).
- **Files:** `chesscoach-gateway/lib/coachFacts.ts` (`CoachFlaggedMoveSchema`, `PlayMoveRecordSchema`), `chesscoach-gateway/lib/coachSummaryPrompt.ts` (`gameFactsText`, `playGameFactsText`), `chesscoach-gateway/test/coachSummaryPrompt.test.ts`.
- **Approach:** Mirror the new `fen` field into both Zod schemas with the identical name. In `gameFactsText`/`playGameFactsText`, call the existing `boardFactsText` (already in `coachChatPrompt.ts` — import/reuse rather than duplicate) for each flagged move's `fen` when present, and append the same "state only verified facts" instruction line already used in the chat/moveNote persona.
- **Patterns to follow:** `coachChatPrompt.ts`'s existing `boardFactsText` call sites (chat/moveNote current- and move-position branches) — same invocation shape, same instruction wording, applied per flagged move instead of per single position.
- **Test scenarios:**
  - A flagged move with `fen` present produces a prompt containing that move's verified piece list.
  - A flagged move without `fen` (older/optional-field-absent data) produces the existing text-only behavior with no crash.
  - The "state only verified facts" instruction appears in the assembled summary prompt.
- **Verification:** `coachSummaryPrompt.test.ts` passes; existing `test/coach.test.ts` still passes (no wire-contract regression).

### U4. Manual verification against the reported case

- **Goal:** Confirm the fix actually stops the reported hallucination, not just that the plumbing compiles.
- **Requirements:** R1, R4.
- **Dependencies:** U1, U3.
- **Files:** none (manual/device verification).
- **Test expectation:** none — this is a manual verification step, not an automated test.
- **Approach:** Replay the reported position (Indian Defense line, `c5` played, engine review "Good · best hxg6") on-device with Coach on, several times (LLM output is non-deterministic — one clean pass doesn't establish the fix worked, only that it didn't reproduce that time), and confirm the per-move note no longer references a piece not on the board. Spot-check one end-of-game summary on a game with a clear blunder to confirm the summary's flagged-move commentary is grounded too.
- **Verification:** No fabricated piece/square claims in either surface across repeated (not single) manual replays.

---

## Scope Boundaries

- Does not add a post-hoc verification/cross-check pass (comparing LLM output against facts after generation). This would catch hallucinations regardless of whether the model obeys the grounding instruction, making it arguably the more robust fix — deferred here because it needs its own design (what counts as a false-positive flag, what happens to a flagged response) rather than reusing existing infrastructure the way U1-U3 do. Revisit if manual verification (U4) shows grounding alone isn't sufficient.
- Does not add attacked/defended-square precomputation beyond the existing piece list — a further-hardening option noted by research, not required to fix the reported case.
- Does not touch the Weakness Report or Opening Trainer coaching paths — out of scope for this report.

### Deferred to Follow-Up Work

- Precomputed attacker/defender call-outs (e.g., "e5 is attacked by Nf3") as a stronger grounding layer than a piece list alone, if hallucinations persist after this fix.
- A regex/string-match verification pass that flags LLM output mentioning squares/pieces absent from the verified fact set, before displaying it to the user.

---

## Risks & Dependencies

- **Grounding facts don't guarantee the model uses them.** This plan assumes the missing FEN is the root cause of the reported hallucination, but the existing free-form chat path already passes `fen:` today — if that path has ever shown similar hallucinations despite having grounding, the model is sometimes ignoring facts it was given, not just missing them, and this plan's fix would be necessary but not sufficient. Worth a quick check of any prior chat-path reports before treating this as closed after U1-U3 ship.
- **`EnginePool`'s single busy gate**: if U1's grounding-only channel is implemented incorrectly and does trigger a fresh `current` analysis, it adds one more serialized engine call to an already-sequential per-move flow (analysis → opponent reply → coach note). U1's test scenario for "no extra engine call" exists specifically to catch this. The simpler alternative — accept the redundant engine call rather than add a new parameter — was not chosen because the per-move flow already runs three serialized engine calls (grading, opponent reply, and today's move-note request); a fourth avoidable one is worth the small added parameter surface.
- **Cross-repo sequencing**: U3 depends on U2's field existing on the wire; deploying the gateway change before the client change ships would be a no-op (missing field just means no grounding, not an error, since the field is optional) — low risk, but land client before gateway to avoid a window where the gateway expects a field older clients don't send (this is backward-compatible either order given the field is optional, so no strict ordering requirement, unlike the earlier breaking `/api/coach` schema change).

---

## Sources / Research

- Reported case: Indian Defense A45 game, verdict "c5 · Good, best hxg6," note claiming a nonexistent pawn on c4.
- Existing grounding mechanism: `chesscoach-gateway/lib/coachChatPrompt.ts` (`boardFactsText`, `placementFromFEN`), built during `docs/plans/2026-07-21-002-feat-server-side-coach-prompts-plan.md` (KTD-4/KTD-5) specifically to prevent FEN-hallucination in chat/moveNote — this plan closes the gap between that mechanism and the call sites/paths that don't yet use it.
- Client call sites: `Sources/GemmaChessCore/ViewModels/PlayViewModel.swift` (`streamCoachNote`, `~line 860`; free-form chat call, `~line 929`), `Sources/GemmaChessCore/Coach/CoachOrchestrator.swift` (`answer`/`answerStream`/`buildChatFacts`).
- External research: academic FEN-parsing/board-state-tracking benchmarks (PGN2FEN, ChessQA, LLM Chess, arXiv 2512.15033/2507.00726) confirm LLMs are unreliable at deriving board state from raw FEN, validating the existing piece-list-grounding approach over raw-FEN prompting. General RAG/grounding literature converges on the same "structured fact block + explicit abstention/state-only-verified-facts instruction" pattern already implemented in `boardFactsText`. Several open-source Stockfish+LLM coaching projects (e.g., stockfish-coach, LLM-ChessCoach) confirm "deterministic engine computes facts, LLM only narrates them" as the standard architecture — consistent with this repo's existing design, not requiring a different approach.
