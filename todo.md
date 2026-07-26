# App Store screenshots — capture list

Raw in-app captures that get composed into marketed App Store artboards via the
Butterkit MCP (device frame + headline overlay + background). These are the
**source** images, not the finished screenshots — don't add text or borders
yourself, that happens in the composition step.

Supersedes `docs/suggested_screenshots.md`, which predates Puzzles, Lessons,
Opening Trainer, the Weakness Report, and the redesigned share card.

## Target spec

| Thing | Value |
|---|---|
| Final artboard | **1290 × 2796** (`app_store_iphone`, 6.9″) |
| Optional second set | 1242 × 2688 (`app_store_iphone_6_5`) |
| Max screenshots | 10 per locale |
| What actually matters | **The first 2–3.** App Store search results often show only those. |

Your iPhone 16e captures at 1170 × 2532 (6.1″). That is a different aspect
ratio to the 6.9″ target, but it does **not** matter for the shots below —
Butterkit composes each capture *inside* a device frame on the artboard, so the
source is scaled into a mockup rather than uploaded raw. Consistency of *look*
across the set matters more than pixel size.

---

## Division of labour

**I can capture these myself** in a 6.9″ simulator (I already drive one for
layout checks) — don't spend time on them unless you want a specific position
on the board:

- Home screen
- Puzzles theme list / a puzzle mid-solve
- Lessons list
- Opening Trainer
- Live hint on the board
- Instant move rating
- Game-over card + the new share card
- Onboarding free-tier slide

**Only you can capture these** — they need a real camera or real accumulated
data that a fresh simulator doesn't have:

- Board scanning (needs a physical board and a camera)
- The Pro coach writing real prose (needs your entitlement + network)
- Weakness Report with genuine history behind it

So the list below is split accordingly. **Start with the ⭐ ones** — those are
the three I can't produce.

---

## ⭐ YOU: 1. Board scanning

- **Why it sells:** nothing else in the category does this, and it's the most
  "wow" single frame in the app.
- **Setup:** a real board with a real mid-game position on it — pieces clearly
  lit, board filling most of the frame, shot from roughly straight above.
- **Capture:** the **review step** right after recognition, where the detected
  position is shown next to "You play: White / Black". That frame proves it
  worked; the camera viewfinder alone doesn't.
- **Avoid:** a starting position (looks like a stock photo), a cluttered table,
  glare.
- **Draft headline:** "Snap a photo of any board."

## ⭐ YOU: 2. The coach explaining a real mistake

- **Why it sells:** this is the product's actual differentiator — the engine
  finds it, the coach explains it in words.
- **Setup:** play until you make a genuine mistake or blunder, with the Coach
  toggle on and Pro active, and wait for the written explanation to stream in.
- **Capture:** board visible on top, coach card below with **several lines of
  real prose** — not a one-liner, not a loading state.
- **Avoid:** placeholder text, an empty card, an error state.
- **Draft headline:** "A coach that explains why — not just what."

## ⭐ YOU: 3. Weakness Report

- **Why it sells:** personalised, and it's the payoff for playing regularly.
- **Setup:** your device already has the history for this. Open Home → the
  coach card ("Your coach has something to tell you") → the report.
- **Capture:** the report screen showing a **named recurring weakness** and the
  written narrative beneath it. Scroll to wherever it looks strongest.
- **Avoid:** the empty/"not enough games yet" state.
- **Draft headline:** "Find the mistake you keep repeating."

---

## ME: the rest — ✅ CAPTURED

Seven captures live in `screenshots/raw/`, all exactly **1290 × 2796**, all with
a clean 9:41 status bar and full battery. Captured in an iPhone 16 Plus
simulator, driven by a temporary launch-argument hook (since `simctl` has no
tap command and `idb` isn't installed). **The hook has been fully reverted —
`git diff` against source is empty.**

| File | Screen | Notes |
|---|---|---|
| `01-home.png` | Home | |
| `04-live-hint.png` | Live hint | Ng5 best-move arrow + alt, rationale line, eval bar. Move list and coach card hidden so the shot says one thing. |
| `05-move-rating.png` | Instant move rating | "Ng5 · Best" verdict chip, engine's top 3 with evals, opening identified |
| `06-puzzles.png` | Puzzles | Shows "Free — Lichess CC0", 200 puzzles/theme, rating bands |
| `07-lessons.png` | Lessons | |
| `08-openings.png` | Opening Trainer | Real ECO list with line counts |
| `09-game-over-card.png` | Game over | Scholar's mate + the mating-net teaching overlay + the redesigned card |

Still missing, and honestly optional:

- **Onboarding free-tier slide** ("No ads. No daily caps.") — reachable only by
  tapping through onboarding, which the launch-arg hook can't do. Grab it on
  your device if you want it: delete and reinstall, then swipe to the slide.

Original plan, for reference:

| # | Screen | Draft headline | Why it's here |
|---|---|---|---|
| 4 | Live hint — bulb on, arrow on the board, one-line reason | "See the best move before you play it." | The headline free-tier feature; leads the listing |
| 5 | Instant move rating — a move just graded Blunder/Best | "Know instantly if that was a mistake." | Immediate feedback, the second free hook |
| 6 | Puzzles — theme list showing the range | "Thousands of puzzles. No daily limit." | Directly answers the #1 competitor complaint |
| 7 | Lessons — stage list | "Start from zero." | The beginner promise in the description |
| 8 | Opening Trainer | "Drill the openings you actually play." | Depth, for the not-quite-beginner |
| 9 | Share card — the new board-hero result card | "Show off your best move." | New, visual, and doubles as the reach vehicle |
| 10 | Onboarding free-tier slide | "No ads. No daily caps. Works offline." | Closes on the free-tier positioning |

---

## Capture hygiene (applies to your three)

- **Same theme throughout.** Pick one (The Gambit Room is what's in the current
  build) and don't switch mid-set — a palette change between screenshots reads
  as a different app.
- **Clean status bar.** Do Not Disturb on, so no notification banner lands
  mid-capture. Battery over 50% looks better than a red sliver.
- **No personal data on screen** — the Weakness Report shot is the one to check
  before sending.
- **Portrait only.**
- **Send them as-is.** Don't crop, annotate, or add text — cropping breaks the
  frame fit in composition.

## Then what

Paste the three back into this conversation. I'll:

1. Capture the other seven in the 6.9″ simulator.
2. Put everything in a folder Butterkit can read (`design_link_screenshot_folder`).
3. Build the 1290 × 2796 artboards — device frame, background, headline per shot.
4. Export, and upload via `asc_upload_screenshots` once you approve the set.

## Status — 2026-07-26

**1.0.0 is submitted for Apple review.** The keyword/description work and this
screenshot set go live with approval.

Seven composed 6.5" artboards are exported to
`screenshots/raw/iPhone 6.5" for App Store/`, covering Moves and Review, Coach
Explanation, Best Move Hints, Move Review, Lessons, Puzzles, and Openings.

### Worth fixing on the next screenshot update

Screenshots can be replaced without submitting a new binary, so none of this
blocks the review:

- **"SOS" in the status bar** on several captures — the device had no carrier
  signal. Reads as a broken phone to a careful viewer.
- **Screen-recording indicator** (orange pill around the clock) on the Lessons,
  Puzzles, and Openings captures.
- Both are avoided by capturing with a normal signal and using the screenshot
  button rather than screen recording.
- **Theme note:** the app is themed and these captures use a light theme. Any
  future additions must use the SAME theme or the set reads as two apps. The
  dark captures in `screenshots/raw/*.png` are Gambit Room and do NOT match
  this set — they were produced for a 6.9" set that was never adopted.
