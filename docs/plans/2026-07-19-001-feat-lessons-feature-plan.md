# feat: Lessons feature (concept explanation + curated puzzle practice)

**Type:** feat
**Depth:** Standard

---

## Summary

Dr. Wolf and Lichess's "Learn" module both pair a short concept explanation with a curated block of practice items (Lichess's Learn stages, Dr. Wolf's 10-20-item lessons). ChessCoach already has the practice-item half of this — themed puzzle packs (fork, pin, skewer, and 17 others) drawn from a vendored CC0 Lichess puzzle dataset — but nothing that explains a concept before drilling it. This plan adds a **Lessons** feature: a browsable list of lessons, each showing a short, original explanation followed by 10-20 practice puzzles pulled from the matching existing theme pack, reusing `PuzzleViewModel`'s existing solve mechanics. Lessons stay entirely free (fully local, no backend calls) and sync completion state via the existing `iCloudProgressSync` seam.

Lichess's Learn module (part of `lichess-org/lila`, AGPLv3+) is used only as **structural inspiration** — its stage/level shape, not its code or text. See KTD-1 for why this fully avoids AGPL entanglement.

---

## Problem Frame

ChessCoach's puzzle packs are already organized by exact tactical theme, but a user browsing Puzzles mode sees a bare theme name ("Forks") with no explanation of what a fork actually is before being dropped into puzzles. Dr. Wolf's lesson format — explain, then practice a curated sequence — is a proven, well-liked shape (per this session's earlier competitor research) that ChessCoach can build cheaply on top of data it already has, without sourcing any new licensed content.

---

## Requirements

- **R1**: A browsable Lessons list, grouped into stages (tactical motifs matching existing puzzle themes; checkmate patterns), each showing completion status.
- **R2**: Each lesson opens to a short, original, static (bundled, no network) explanation of the concept before practice begins.
- **R3**: After the explanation, the lesson presents 10-20 practice puzzles pulled from the matching existing theme pack, difficulty-ascending, reusing `PuzzleViewModel`'s existing tap-to-move solve mechanics rather than new move-validation logic.
- **R4**: Per-lesson completion (not started / in progress / completed) tracked locally, consistent with `PuzzleProgressStore`/`OpeningTrainerStore`'s existing `UserDefaults`-backed, dependency-injectable pattern.
- **R5**: Lessons are entirely free — no `ProEntitlementStore.requireProOrThrow()` gate anywhere in this feature, consistent with the established "local = free, backend-calling = Pro" rule (see `docs/plans/2026-07-18-001-feat-free-tier-feature-expansion-plan.md`).
- **R6**: Lesson completion state syncs via the existing `iCloudProgressSync` seam (`NSUbiquitousKeyValueStore`), consistent with how puzzle rating/streak already sync.
- **R7**: No lesson explanation text, code, or curated example positions are copied from `lichess-org/lila`'s Learn module — see KTD-1.

---

## Scope Boundaries

### Non-goals (this plan)
- Any new backend/cloud service (none — consistent with every prior plan in this repo).
- Piece-movement/"how does a knight move" basics stages — no existing puzzle-pack equivalent, and building fresh move-legality teaching mechanics is a materially different feature than "explain a tactic, then drill it." Deferred (see below).
- Video content.
- Adaptive/AI-driven lesson sequencing — lesson order and content are static and curated for this pass.
- A new content-licensing regime for the app as a whole — this plan only establishes the rule for lesson text specifically (KTD-1).

### Deferred to Follow-Up Work
- Piece-movement/basics stages (how each piece moves, check/checkmate/stalemate definitions) — worth a separate plan once a "teach a rule, verify understanding" interaction shape (distinct from "solve a tactic") is designed.
- Endgame stages beyond what the existing `endgame` puzzle theme already covers.

---

## Key Technical Decisions

### KTD-1: Lichess's Learn module is structural inspiration only — no copied text, code, or curated positions

**Decision**: This feature's lesson explanations are 100% original writing (authored during implementation, not sourced from lila), and its practice positions come exclusively from the already-vendored CC0 Lichess puzzle dataset (`PuzzleData/`) — never from lila's own curated Learn example positions. Only the general shape (a stage groups related lessons; a lesson pairs a short explanation with a bounded practice set) is taken as inspiration.

**Rationale (researched, not assumed)**: `lichess-org/lila` is confirmed AGPLv3-or-later (its `COPYING.md`/`LICENSE`), and the Learn module's code and lesson text live directly inside `lila` (`ui/learn/src`) with no separate or more permissive license carved out for that directory's lesson content — the only exceptions listed in `COPYING.md` are one SVG (CC0) and piece images (GPLv2+), not lesson text. No lichess.org page or GitHub org doc documents a code/content license split (a 2011 forum post references a since-abandoned pre-AGPL CC BY-NC scheme, not the current state). Per the FSF's GPL FAQ, GPLv3 and AGPLv3 code *can* be combined into one program (each license's §13 grants mutual compatibility), but the combined work must then satisfy both licenses' terms — in practice, AGPLv3's network-source-disclosure clause would extend to the combined work. Copying lila's actual lesson text or example positions into this GPLv3 client would therefore create real, non-trivial licensing consequences for the whole app, not just an attribution nicety.

Structural inspiration alone doesn't have this problem: copyright's idea-expression dichotomy (a well-established doctrine, also reflected in TRIPS Article 9(2)) protects only specific expression — exact wording, exact code — not underlying ideas, facts, methods, or abstract organizational structures. "Group lessons into stages" and "a fork is when one piece attacks two undefended targets" are unprotectable facts/structure regardless of who organized them that way first.

**Caveat**: This is research grounding a product decision, not a legal opinion — flagged in the plan per the researcher's own note. If there's ever doubt about a specific piece of copy sounding too close to a known Learn lesson's wording, rewrite it before shipping.

### KTD-2: Lessons are a thin content+navigation layer over existing stores, not a new content pipeline

**Decision**: A lesson is a static, bundled data structure — `{id, title, stageID, bodyText, theme, puzzleCount}` — resolved at runtime to a slice of the matching theme's already-downloaded puzzle pack (via the same `PuzzleDownloadStore`/`PuzzleModels` used by Puzzles mode and Puzzle Rush). No new puzzle format, no new download path.

**Rationale**: Mirrors KTD-2 from `docs/plans/2026-07-18-001-feat-free-tier-feature-expansion-plan.md` (Puzzle Rush reusing puzzle data as-is) — the same reasoning applies here even more directly, since a lesson's practice set is just a bounded, ordered subset of one theme's pack.

### KTD-3: Lesson content is a Swift data literal, not a bundled JSON/text-file resource

**Decision**: Lesson metadata and body text live in a Swift source file (e.g. a `static let lessons: [Lesson]` catalog), not an external `.json`/`.md` resource bundled via `Bundle.module`.

**Rationale**: ~15-20 short entries is small enough that a plain Swift literal is simpler to author, review, and test than introducing a bundle-resource loading path (`Openings.swift`'s TSV-loading complexity exists because that dataset is ~3.7k lines vendored from an external source — lesson content here is neither large nor externally sourced, so it doesn't need that treatment). Easy to move to a resource file later if content grows substantially.

### KTD-4: Lesson progress tracks three states, not a binary solved/unsolved flag

**Decision**: `LessonProgress` per lesson is `notStarted | inProgress(solvedCount: Int) | completed`, not just a boolean, mirroring `OpeningFamiliarity`'s richer state over `PuzzleProgressStore`'s flatter solved-ID-set model.

**Rationale**: R1 requires showing completion status in the list, and "3 of 15 solved" is a materially better in-list signal than a binary flag — cheap to add given the lesson catalog is small and each lesson's puzzle count is fixed and known upfront (unlike puzzle packs, which can grow).

---

## Implementation Units

### U1. Lesson catalog + local progress store

**Goal**: Define the static lesson catalog (stages, lessons, body text) and a `UserDefaults`-backed progress store mirroring `PuzzleProgressStore`/`OpeningTrainerStore`'s pattern.

**Requirements**: R1, R2, R4, R6

**Dependencies**: None

**Files**:
- Create: `Sources/GemmaChessCore/Lessons/LessonCatalog.swift`
- Create: `Sources/GemmaChessCore/Lessons/LessonProgressStore.swift`
- Test: `Tests/GemmaChessCoreTests/LessonProgressStoreTests.swift`

**Approach**: `LessonCatalog.stages: [LessonStage]`, each `LessonStage { id, title, lessons: [Lesson] }`; `Lesson { id, title, theme: String (matches an existing `PuzzleThemeInfo.theme` id), bodyText: String, puzzleCount: Int }`. `LessonProgressStore` persists `[lessonID: LessonProgress]` as JSON in `UserDefaults` (mirrors `OpeningTrainerStore`'s single-blob approach over per-key entries, since progress is read/written as a whole map), with a `recordAttempt(lessonID:solvedCount:isComplete:defaults:sync:)`-shaped update function. Write-through to `iCloudProgressSync` on every update (same pattern as `PuzzleRatingStore`/`PuzzleStreakStore` — register a merge rule with `iCloudProgressSync` for this store's key).

**Patterns to follow**: `Sources/GemmaChessCore/Openings/OpeningTrainerStore.swift` (richer per-item state, single JSON blob in `UserDefaults`); `Sources/GemmaChessCore/Sync/iCloudProgressSync.swift`'s existing merge-rule registration used by `PuzzleRatingStore`/`PuzzleStreakStore`.

**Test scenarios**:
- Fresh install: every lesson reports `notStarted`.
- Recording a partial attempt (e.g. 5 of 15 solved) sets `inProgress(solvedCount: 5)`.
- Recording completion (all puzzles solved) sets `completed`.
- Progress persists across a fresh store instance reading the same `UserDefaults` suite (round-trip, mirroring `OpeningTrainerStoreTests`' existing style).
- A write mirrors into the injected `iCloudProgressSync` (mirrors `iCloudProgressSyncTests`' existing write-through assertions for the other stores).
- Catalog integrity: every `Lesson.theme` in `LessonCatalog` matches a real theme id already present in `PuzzleModels`/the curated puzzle themes list (a plain unit test iterating the catalog against the known theme id set) — catches a typo'd theme reference at test time rather than at runtime.

**Verification**: A lesson's progress can be recorded and read back correctly in all three states, iCloud write-through fires, and every catalog entry references a real, existing puzzle theme.

---

### U2. Lesson session view model (practice sequencing over existing puzzle data)

**Goal**: Given a `Lesson`, resolve its practice sequence from the matching downloaded theme pack and drive a solve session reusing `PuzzleViewModel`'s existing move-validation approach.

**Requirements**: R3, R4

**Dependencies**: U1

**Files**:
- Create: `Sources/GemmaChessCore/ViewModels/LessonViewModel.swift`
- Test: `Tests/GemmaChessCoreTests/LessonViewModelTests.swift`

**Approach**: `LessonViewModel` loads the theme's downloaded pack (via `PuzzleDownloadStore`, same as `PuzzleViewModel`/`PuzzleRushSession` already do), takes the lesson's configured `puzzleCount` puzzles in difficulty-ascending order (reuse `PuzzleRushSession.order(_:)`'s banding approach, or a simpler plain ascending sort — implementation-time call, since a fixed curated lesson doesn't need replay variety the way Rush does), and exposes the same tap-to-move / feedback / advance state machine shape as `PuzzleViewModel`, updating `LessonProgressStore` after each solved puzzle and marking the lesson `completed` once the sequence is exhausted.

**Patterns to follow**: `Sources/GemmaChessCore/ViewModels/PuzzleViewModel.swift`'s tap-to-move state machine (reuse the shape, don't reinvent move validation); `Sources/GemmaChessCore/Puzzles/PuzzleRushSession.swift`'s pattern of loading a puzzle pool from `PuzzleDownloadStore` and progressing through it.

**Test scenarios**:
- A lesson whose theme pack is already downloaded loads its configured practice sequence in ascending difficulty order.
- A lesson whose theme pack is NOT downloaded yet reports a clear "download this pack first" state (mirrors `PuzzleRushSession.isEmpty`'s existing empty-state handling), rather than crashing or silently showing nothing.
- Solving a puzzle correctly advances to the next; `LessonProgressStore` reflects the new solved count.
- Solving the last puzzle in the sequence marks the lesson `completed` in `LessonProgressStore`.
- A wrong answer surfaces feedback and allows retry of the same puzzle (mirrors normal Puzzles mode's existing retry behavior — NOT Puzzle Rush's penalty/end-of-run behavior, since a curated lesson isn't timed).

**Verification**: A full lesson can be driven start-to-finish in a test against a small fixture puzzle set, ending in `LessonProgressStore` reporting `completed`.

---

### U3. Lessons UI — stage/lesson browse list, explanation screen, practice session

**Goal**: User-facing screens: a stage-grouped lesson list (with completion status), a lesson's explanation screen, and the practice session itself.

**Requirements**: R1, R2, R3

**Dependencies**: U1, U2

**Files**:
- Create: `Sources/GemmaChessCore/UI/LessonsView.swift`
- Modify: `Sources/GemmaChessCore/UI/RootView.swift` (Home entry point, following the existing `Mode` enum + `moreSheet` pattern used for Opening Trainer/Game Import)

**Approach**: List screen groups `LessonCatalog.stages` into sections, each lesson row showing title + completion status (icon for `completed`, "X of N" for `inProgress`, nothing extra for `notStarted` — mirrors `OpeningTrainerContainerView`'s `lineRow` familiarity-badge pattern). Tapping a lesson shows its explanation (a simple static text screen with a "Start practice" button) before handing off to the practice session view (built over `LessonViewModel`, visually similar to `PuzzlesView`'s existing solve screen).

**Patterns to follow**: `Sources/GemmaChessCore/UI/OpeningTrainerView.swift`'s `OpeningTrainerContainerView`/list-then-session structure; `Sources/GemmaChessCore/UI/RootView.swift`'s existing `Mode` enum + `moreSheet` entry-point pattern (Lessons is exactly the shape of Opening Trainer/Game Import — add a `.lessons` case and a "Lessons" row in the More sheet, per the Home decluttering already done in this repo).

**Test scenarios**:
- `Test expectation: none -- this unit is UI composition over U1/U2, which already carry the behavioral test coverage; no new business logic is introduced here.`

**Verification**: Home's More sheet has a working "Lessons" entry point; the list, explanation, and practice screens compose without runtime errors and reflect `LessonProgressStore`/`LessonViewModel` state correctly when exercised manually (or via a UI smoke pass if the project's test setup supports it).

---

## System-Wide Impact

- **Home navigation** (`RootView.swift`) gains one more More-sheet entry — no crowding concern since that sheet was built in this repo specifically to absorb new secondary features without growing Home itself.
- **Settings** (`SettingsView.swift`) should get a "Reset lesson progress" action, consistent with the existing reset actions for puzzle progress/rating and opening-trainer familiarity.
- No impact to `chesscoach-gateway` or any backend — this feature makes zero network calls.

---

## Open Questions (deferred to implementation)

- Exact lesson roster and body text (which ~15-20 lessons, grouped into which stages, and their explanation copy) — this is real content-writing work belonging to implementation, not something this plan pre-drafts.
- Per-lesson `puzzleCount` (10 vs. 15 vs. 20) and whether it's uniform across all lessons or varies by theme — an easy implementation-time tuning knob with no architectural consequence.
- Whether difficulty-ascending ordering for a lesson's practice set reuses `PuzzleRushSession.order(_:)`'s banding logic directly or a simpler plain sort — noted as an implementation-time call in U2's Approach.

---

## Sources & Research

- `lichess-org/lila` license verification (this session): confirmed AGPLv3-or-later via the repo's `COPYING.md`/`LICENSE` (https://github.com/lichess-org/lila/blob/master/COPYING.md); Learn module code/content lives at `ui/learn/src` within `lila` itself, not a separately-licensed repo; no documented code/content license split on lichess.org or at the GitHub org level. Directly shaped KTD-1.
- FSF GPL FAQ (https://www.gnu.org/licenses/gpl-faq.html) on GPLv3/AGPLv3 combination and the network-source-disclosure consequence of combining with AGPL-licensed code — shaped KTD-1's rationale for avoiding literal reuse.
- Idea-expression dichotomy (copyright doctrine, also reflected in TRIPS Article 9(2)) — the legal basis for why structural/taxonomic inspiration (stage grouping, "explain then practice" shape) is safe while literal text/code copying is not. Shaped KTD-1.
- Repo research (this session): `Sources/GemmaChessCore/Puzzles/PuzzleModels.swift`, `PuzzleDownloadStore.swift`, `PuzzleProgressStore.swift`, `ViewModels/PuzzleViewModel.swift`, `Puzzles/PuzzleRushSession.swift`, `Openings/OpeningTrainerStore.swift`, `Sync/iCloudProgressSync.swift`, `UI/OpeningTrainerView.swift`, `UI/RootView.swift`, `PuzzleData/README.md` — confirmed puzzle data is CC0/vendored-on-demand (not bundled), confirmed existing store/sync/UI patterns this plan reuses rather than reinvents.
