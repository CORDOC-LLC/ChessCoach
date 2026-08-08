---
title: "feat: Ship a native macOS build of ChessCoach"
date: 2026-08-08
type: feat
---

## Summary

`GemmaChessMac` (Apps/GemmaChessMac) already exists as an Xcode target and
builds successfully against `GemmaChessCore` — it is not a from-scratch
port. `RootView` already ships a `.split` (`NavigationSplitView`) layout
style for non-iPhone canvases, `ChessBoardView` uses tap gestures only (no
touch-only drag), and every iOS-only surface (camera board scanning,
haptics) is already `#if os(iOS)`-gated with no macOS call sites. The real
gaps are: no keyboard shortcuts/menu commands, no verified end-to-end smoke
pass on Mac, and a bundle-ID mismatch that currently blocks subscription
sharing with the iOS app. This plan closes those gaps and gets a signed,
locally-runnable Mac build with Pro working via Apple's Universal Purchase.

## Problem Frame

ChessCoach's iOS app is live; a macOS build exists as an Xcode target but
has never been verified end-to-end, has no Mac-native affordances (menu
bar commands, keyboard shortcuts), and its subscription entitlement is
disconnected from the iOS app because of a bundle-ID mismatch
(`com.cordoc.gemmachess.mac` vs `com.cordoc.gemmachess`). The goal is a
working, polished native Mac build where a user who already subscribed on
iPhone gets Pro on Mac for free (Universal Purchase), with no separate
Mac IAP setup.

## Scope Boundaries

**In scope:** verifying the existing Mac build end-to-end; adding
menu-bar commands and keyboard shortcuts; fixing the bundle ID so Universal
Purchase applies; adding macOS as a platform on the existing App Store
Connect app record; local signing/run verification.

**Out of scope / deferred:**
- Any redesign of `PlayView`/`RootView` layout beyond what `.split` already
  provides — visual polish beyond "correctly usable" is follow-up work.
- Board-scanning-via-webcam on Mac (BoardScannerView stays iOS-only;
  no camera feature parity is being added).
- Widgets, menu-bar extras, or other Mac-only feature additions.
- Actually submitting the Mac build to App Store review — this plan gets
  it to a signed, locally-verified, TestFlight-Mac-ready state.

## Key Technical Decisions

**KTD1 — Universal Purchase over a second product catalog.** Apple only
auto-shares a subscription across iOS and macOS when both platforms share
one bundle ID under one App Store Connect app record ("Universal
Purchase"). `GemmaChessMac` currently uses `com.cordoc.gemmachess.mac`, a
distinct ID, which would require a whole second RevenueCat/StoreKit
product set and paywall variant. Instead: change the Mac target's
`PRODUCT_BUNDLE_IDENTIFIER` to `com.cordoc.gemmachess` (matching iOS
exactly) and add "macOS" as an additional platform on the *existing* App
Store Connect app record for ChessCoach. `ProEntitlementStore` and
`PaywallView` need no code changes — RevenueCat resolves entitlements by
App User ID/receipt against the same app record regardless of platform.
**Alternative rejected:** keeping `.mac` as a separate app + separate
RevenueCat project — more setup, and a returning iOS subscriber would see
"no plans" or be asked to pay again on Mac, which is the exact bug this
session diagnosed and fixed for iOS.

**KTD2 — `.split` is the layout entry point; no new layout system.**
`GemmaRootView(style: .split)` is already wired in
`Apps/GemmaChessMac/GemmaChessApp.swift`. This plan verifies and hardens
that path rather than introducing a second Mac-specific root view.

## Implementation Units

### U1. Bundle ID + App Store Connect platform alignment for Universal Purchase

**Goal:** Make Mac and iOS share one app record so RevenueCat entitlements
carry over automatically.

**Requirements:** KTD1.

**Dependencies:** none.

**Files:**
- `project.yml` — change `GemmaChessMac`'s `PRODUCT_BUNDLE_IDENTIFIER`
  from `com.cordoc.gemmachess.mac` to `com.cordoc.gemmachess`.
- `Apps/GemmaChessMac/GemmaChessApp.swift` — no code change expected;
  re-verify after regen that `RevenueCat`/`ProEntitlementStore.configure`
  is reachable the same way it is on iOS (check `GemmaChessApp.swift` for
  both platforms share the same `.configure(apiKey:)` call site in
  `GemmaChessCore`, not duplicated per-platform).

**Approach:** In App Store Connect, add macOS as an additional platform to
the existing ChessCoach app record (My Apps → ChessCoach → app
settings → add platform), rather than creating a new app. Register a new
macOS App ID for `com.cordoc.gemmachess` in Certificates, Identifiers &
Profiles (the iOS App ID with this identifier already exists; a macOS
platform association or a fresh macOS App ID with the same bundle string
is needed — resolve exact ASC mechanics during implementation, this is
a deferred implementation-time detail, not a planning blocker). Regenerate
the Xcode project (`scripts/gen-project.sh`) after the `project.yml`
change and confirm automatic signing re-provisions cleanly.

**Patterns to follow:** `scripts/upload-testflight.sh`'s existing
provisioning-update flow (`-allowProvisioningUpdates`) for how automatic
signing already re-registers App IDs on archive.

**Test scenarios:**
- Happy path: after the bundle ID change, a fresh `xcodebuild build` for
  `GemmaChessMac` succeeds and produces a `.app` code-signed under
  `com.cordoc.gemmachess`.
- Integration: on a machine with an active TestFlight/sandbox Apple ID that
  already holds a ChessCoach Pro subscription from the iOS app,
  `ProEntitlementStore.refreshCustomerInfo()` on the Mac build reports
  `isProActive == true` without any purchase action on Mac (verifies
  Universal Purchase actually shares the entitlement).
- Error path: a non-subscribed Apple ID sees `packages` populated
  (offerings load) and can complete a real/sandbox purchase from the Mac
  paywall, after which `isProActive` flips true.

**Verification:** Build succeeds under the new bundle ID; an
already-subscribed test account shows Pro active on Mac without
purchasing again.

---

### U2. Menu-bar commands and keyboard shortcuts

**Goal:** Give the Mac build native menu-bar affordances instead of only
the touch-derived in-app buttons.

**Requirements:** none from an origin doc (fresh scope) — user-facing
parity expectation for a native Mac app.

**Dependencies:** none (independent of U1).

**Files:**
- `Apps/GemmaChessMac/GemmaChessApp.swift` — add a `.commands { }`
  modifier to the `WindowGroup` scene.
- `Sources/GemmaChessCore/UI/PlayView.swift` — expose the actions the
  commands need (new game, undo) as callable entry points if not already
  public/reachable from outside the view (check `onNewGame` closure
  already passed into `PlayView.init`).

**Approach:** Add an `App.commands` block with: Cmd+N for New Game
(wherever `onNewGame` currently originates from `RootView`/`Home`),
Cmd+Z for Undo (mirrors the existing in-board undo button in
`PlayView.header`), Cmd+, for Settings (opens the existing
`SettingsView` sheet). Keep this additive — do not remove or hide the
existing on-screen buttons; commands are a second entry point, not a
replacement (touch/iPad-style controls stay primary UI, per KTD2's
"verify and harden `.split`," not "redesign for Mac idioms").

**Patterns to follow:** SwiftUI's standard `CommandGroup(replacing:)` /
`CommandMenu` patterns; keep bindings on existing `@State`/view-model
methods rather than duplicating logic.

**Test scenarios:**
- Happy path: Cmd+Z while a live game has at least one move undoes the
  last ply, matching the on-screen Undo button's behavior exactly.
- Edge case: Cmd+Z with no moves played is a no-op (matches existing
  button's disabled/guard behavior — verify `PlayViewModel`'s undo already
  guards this; if not, this is a pre-existing bug to note, not fix here).
- Edge case: keyboard shortcuts are inert while a sheet (Settings,
  Paywall) is presented modally over the board, matching standard SwiftUI
  responder-chain behavior — no custom suppression should be needed, but
  verify Cmd+Z doesn't leak through the Settings sheet.

**Verification:** Each added shortcut visibly performs the same action as
its on-screen equivalent, confirmed by manual run on the Mac build.

---

### U3. End-to-end Mac smoke verification

**Goal:** Confirm the existing `.split` layout and full feature set (Play,
Puzzles, Lessons, Openings, Settings, Paywall) actually work end-to-end on
Mac, not just that it compiles.

**Requirements:** KTD2.

**Dependencies:** U1 (so the paywall test below has a working entitlement
path), U2 (so shortcuts are in place to verify).

**Files:** none created — this is a verification pass, not new code. Any
bugs found get filed as follow-up fixes rather than folded into this plan
silently (per Scope Boundaries).

**Approach:** Run `GemmaChessMac` locally (`xcodebuild ... -destination
'platform=macOS'` or via Xcode directly) and walk each top-level surface
reachable from `GemmaRootView(style: .split)`: Home, Play (new game,
resume in-progress game, move a piece by click, use a hint, view the
Coach card with a Pro account), Puzzles, Lessons, Openings, Settings
(theme picker, appearance editor), and the Paywall (from U1's Universal
Purchase check). Confirm no view assumes a touch-only affordance (e.g., a
swipe-to-dismiss with no mouse/keyboard equivalent) and no view is clipped
or unusable at the `minWidth: 900, minHeight: 600` floor already set in
`GemmaChessApp.swift`.

**Test scenarios:**
- Happy path: each of the 6 top-level screens (Home, Play, Puzzles,
  Lessons, Openings, Settings) opens, renders without layout errors, and
  its primary action (start game / solve a puzzle / open a lesson / view
  an opening / change a setting) completes successfully.
- Edge case: resize the window to exactly `900x600` (the enforced
  minimum) and confirm no content is clipped or overlapping on the
  Play screen (the most content-dense surface, per the earlier board-
  centering fix in this session).
- Integration: complete one full game to checkmate on Mac and confirm the
  game-over banner, share-card flow, and "My Games" persistence all work
  identically to iOS (shared `GemmaChessCore` stores, so this mainly
  guards against a Mac-only rendering regression).
- Test expectation: none beyond manual verification — this unit is a
  smoke pass, not new automated coverage; flag during execution if a gap
  found here is severe enough to warrant a regression test added to
  `Tests/GemmaChessCoreTests/`.

**Verification:** A written note (in the PR/commit description, not a new
doc) listing each surface checked and its pass/fail state; any fail is
either fixed in this unit if trivial or filed as a follow-up.

## Risks & Dependencies

- **App Store Connect platform-add mechanics are not fully knowable until
  attempted** — Apple's UI/process for adding macOS to an existing iOS-only
  app record can vary (deferred to U1's implementation-time discovery,
  explicitly, per the plan's own Approach note).
- **Automatic signing may require a fresh macOS App ID** even under the
  same bundle string, depending on the Apple Developer account's existing
  identifier state — resolve during U1, not blocking planning.
- No server-side (chesscoach-gateway) changes are needed: the gateway's
  RevenueCat webhook and entitlement checks are already platform-agnostic
  (keyed on App User ID / subscriber, not bundle ID).
