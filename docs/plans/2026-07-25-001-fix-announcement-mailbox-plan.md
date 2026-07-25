---
title: "fix: Announcement mailbox replaces the Home banner"
type: fix
date: 2026-07-25
---

# fix: Announcement mailbox replaces the Home banner

## Summary

Replace the Home announcement card with a permanently-visible mail icon beside the gear, badged when an announcement is unread. This removes a layout shift that fires on every visit to Home, and changes dismissal from "gone forever" to read/unread so a message can always be found again.

---

## Problem Frame

The announcement card renders in `HomeView.actions` after an async fetch, positioned directly above the "Resume game"/"Play a game" buttons. `HomeView.onDisappear` clears the fetch-task guard, so every return to Home re-fetches and the card pops in late — shoving the primary call to action down the screen each time. The shipped plan (`docs/plans/2026-07-24-001-feat-announcement-banner-plan.md`) reasoned that rendering no placeholder meant "Home's layout never shifts." That was wrong: skipping a placeholder avoids a skeleton→content shift but guarantees a nothing→content shift, which is the more disruptive one, and placing the card above the primary buttons made it maximally so.

Dismissal is the second problem. "Dismissed = hidden forever" is harsh for a message carrying a promo code or a launch link — a mis-tap destroys access to it from the one surface where it was visible.

---

## Key Technical Decisions

- **The icon lives in the fixed top-trailing overlay, not the content stack.** `HomeView` already renders `settingsButton` in `.overlay(alignment: .topTrailing)`, which sits outside the `ScrollView`'s layout flow. A badge appearing there when a fetch resolves moves nothing. This is what structurally kills the bug, rather than tuning when the card appears.
- **Reuse the existing dismissed-ID storage as read-IDs; no migration.** The store already persists a `Set<String>` under `announcements.dismissedIDs` on real TestFlight devices. Read state has identical shape and semantics ("this ID has been handled"), so the existing key is reinterpreted rather than migrated. Anything already dismissed stays un-badged and is still readable in the mailbox — an update never resurrects a handled announcement as unread.
- **The badge is a dot, not a count.** The gateway serves one active announcement at a time (`GET /api/announcement` returns the single most recent non-expired row), so a count would only ever read 0 or 1. A dot states exactly what's known without implying a queue.
- **Read is per-announcement, triggered by tapping its row.** Chosen over mark-all-read-on-open. Consequence worth naming: a user who opens the mailbox, reads the fully-visible text, and taps nothing keeps the badge — the tap is an explicit acknowledgment, not a side effect of reading. This also means rows must be tappable even without a link, which they currently are not.
- **Fetch on every Home appearance, and drop the once-per-lifetime guard.** The guard existed to limit how often a layout-shifting card could appear. With the icon fixed in place, a refetch is invisible and strictly better: a newly-posted announcement badges without needing an app relaunch. In-flight fetches are still cancelled on disappear.

---

## Requirements

**Layout and placement**

- R1. Announcements no longer render in Home's content stack; the announcement card is removed.
- R2. A mail icon sits beside the gear in Home's top-trailing overlay and is always present, whether or not any announcement exists.
- R3. An arriving or resolving fetch causes no layout movement anywhere on Home.

**Read state**

- R4. The icon shows an unread marker when at least one known announcement is unread, and no marker otherwise.
- R5. Tapping an announcement's row marks that announcement read; other announcements are unaffected.
- R6. Announcements dismissed under the previous shipped behavior are treated as read, so an app update does not surface them as unread.
- R7. A read announcement remains fully readable in the mailbox — title, body, and its link still shown. (An *expired* announcement stays readable too, but its link is no longer actionable; read state and expiry are independent.)

**Access and accessibility**

- R8. Tapping the mail icon opens the existing announcements list.
- R9. Unread state is conveyed to VoiceOver as text, not by the visual marker alone.

---

## Implementation Units

### U1. Read-state API on the store

- **Goal:** The store answers "is anything unread" and "mark this one read," reusing the existing persisted IDs.
- **Requirements:** R4, R5, R6.
- **Dependencies:** none.
- **Files:** `Sources/GemmaChessCore/Announcements/AnnouncementStore.swift`, `Tests/GemmaChessCoreTests/AnnouncementStoreTests.swift`.
- **Approach:** Reframe the dismissed-ID set as read-IDs, keeping the same `UserDefaults` key so existing device data carries over untouched (R6) — rename the API surface, not the storage. The rename is safe: `dismissedIDs()`/`dismiss(id:)`/`shouldShow(...)` have no callers outside `HomeView` (deleted by U2) and this unit's own test file, so no compatibility shim is needed. Add a way to mark a single announcement read and a way to ask whether any entry in the recently-seen cache is unread. Fold `shouldShow(_:dismissedIDs:now:)` into the unread predicate rather than leaving a dead function, since unread means the same thing minus the expiry rule (an expired-but-unread announcement should still be readable, and should not badge). The four existing `shouldShow*` tests, plus the `shouldShow` assertion inside the `recordSeen` test, are rewritten against the new predicate — the test target won't compile until they are.
- **Patterns to follow:** the file's own existing shape — plain `enum`, static funcs, injectable `defaults: UserDefaults = .standard`, JSON-encoded values, corrupt data decoding as empty rather than crashing.
- **Test scenarios:**
  - A freshly-seen announcement reads as unread; after marking read, it does not.
  - Marking one announcement read leaves another unread.
  - IDs written under the old dismissed-ID key read as already-read (R6) — construct the defaults directly with the old key to prove the carry-over.
  - An expired announcement does not count toward unread, but is still returned by the recently-seen cache (R7).
  - `reset()` clears read state along with the cache.
  - Corrupt or missing stored data reads as "nothing read, nothing unread" rather than crashing.
- **Verification:** `AnnouncementStoreTests` pass, including the old-key carry-over case.

### U2. Mail icon with unread badge on Home

- **Goal:** Replace the card with a fixed, badged icon.
- **Requirements:** R1, R2, R3, R8, R9.
- **Dependencies:** U1.
- **Files:** `Sources/GemmaChessCore/UI/RootView.swift` (the nested `HomeView` struct, not `GemmaRootView`).
- **Approach:** Add a mail button beside `settingsButton` in the top-trailing overlay (an `HStack` of the two), styled to match the gear's circular treatment and spaced so the two 34pt circles don't crowd or mis-tap on the narrowest supported device. Delete `announcementCard` and its slot in `actions`, and delete the `announcement` state that fed it. Navigate via a new `.navigationDestination(isPresented:)` to `AnnouncementsView`, mirroring how `showSettings`/`showBeginners` already work here.
  **Unread state lives in `@State`, never read from the store inside `body`.** The unread predicate needs `recentlySeen()`, which does a `UserDefaults` read plus a full JSON decode — doing that inline in `body` is the same shape of mistake as the `@AppStorage`-in-body read that previously pinned the CPU and tripped iOS's launch watchdog in this app (see `GemmaRootView`'s comments). Hold a `hasUnread` flag in `@State` and recompute it only at named points: on `onAppear`, after the fetch task's `recordSeen` completes, and when the pushed list is dismissed — `.onChange(of: showAnnouncements)` firing on the false transition is the explicit return trigger, since `.navigationDestination(isPresented:)` gives the source view no return callback and `UserDefaults` behind a static enum is unobserved, so nothing would otherwise re-evaluate the badge.
  Keep the fetch in `.onAppear` but drop the once-per-lifetime guard — it now only calls `recordSeen` so the badge reflects the latest server state; still cancel any in-flight task on disappear. The icon has no loading or error affordance: an in-flight or failed fetch simply leaves the badge at its last-known value, consistent with the client's fail-soft contract. A fetch landing while the list is already open surfaces on the list's next appearance rather than mid-screen.
  Accessibility (R9): the button carries a label naming both the destination and the unread state (e.g. "Announcements, unread" vs "Announcements"), since the dot alone conveys nothing to VoiceOver. Size and contrast the dot to stay legible for low-vision users without becoming its own tap target — the whole button stays the target.
- **Patterns to follow:** `settingsButton` for the button/background/`PressableStyle` treatment; the existing `.navigationDestination(isPresented:)` pairs in `HomeView.body`.
- **Test scenarios:** UI composition — this repo has no snapshot tests; the badge predicate itself is covered by U1's store tests.
  - Test expectation: none for the view — the unread decision is U1's pure function; this unit is placement and wiring only.
- **Verification:** On device, Home shows no announcement card; the mail icon sits beside the gear and never moves; posting a new announcement and returning to Home badges the icon with no content shift; tapping opens the list; VoiceOver announces the unread state.

### U3. Unread rows and tap-to-read in the list

- **Goal:** The list distinguishes unread entries and lets a tap mark one read.
- **Requirements:** R5, R7.
- **Dependencies:** U1.
- **Files:** `Sources/GemmaChessCore/UI/AnnouncementsView.swift`.
- **Approach:** Give each row an unread affordance (a leading dot and emphasized title) driven by the store. Make every row tappable — currently rows are disabled when expired or link-less, which under per-row read semantics would make those announcements permanently unreadable-as-read. A tap marks that announcement read and, when a live link exists, opens it; an expired row still marks read but does not open its link. Reload `recentlySeen()` on each appearance (it already does) and refresh displayed read state after a tap so the row updates in place.
  **Unread and expired can both be true at once** — a fetched-but-never-tapped announcement can expire while still unread, so this is reachable, not hypothetical. Both markers coexist: the leading unread dot and the trailing "Expired" caption serve different questions ("have I dealt with this?" vs "is this still valid?"). Keep the unread emphasis on the title so the row doesn't read as contradictory.
  **Add a defaults-injection seam.** The view is `public init() {}` today and calls the store hard-wired to `.standard`, so the tap test below cannot be written as stated. Give it a defaulted `defaults:` parameter threaded through its store calls, matching the house style the store itself already uses — both existing call sites (Settings' `NavigationLink` and the new Home destination) keep compiling unchanged.
  Rows carry their unread state in the accessibility label for the same reason as the icon (R9).
- **Patterns to follow:** the file's existing row structure, empty state, and expired-row treatment — this unit adjusts them rather than restructuring the screen.
- **Test scenarios:** Composition is untested here, but the read transition is not:
  - Tapping a row calls through to the store's mark-read for that announcement's ID only — assert via the store's state, using an injected test `UserDefaults`.
  - An expired row marks read without attempting to open a link.
  - Extract whatever logic decides "is this row unread / should this tap open a link" as a pure function so it can be asserted without a view.
- **Verification:** On device, unread announcements are visually distinct; tapping one clears its marker and the Home badge; a link-less announcement can still be marked read.

---

## Scope Boundaries

- No gateway changes — `/api/announcement` and its admin POST path are untouched.
- Settings keeps its existing Announcements entry; the mail icon is an additional route to the same screen, not a replacement.
- No push notifications. Deliberately deferred: iOS grants one meaningful permission prompt, better spent later on a feature the user actively wants (practice reminders, streak warnings), with announcements riding the permission that earns. Adding it now also means APNs keys, device-token storage, a send path, and token-invalidation handling for a user base that doesn't yet exist to re-engage.

### Deferred to Follow-Up Work

- A mark-all-read affordance, if per-row tapping proves tedious once there's more than one announcement in play.
- Multiple concurrently-active announcements, which would turn the badge dot into a genuine count.

---

## Risks & Dependencies

- **Reinterpreting the stored key is a one-way door.** Once shipped, old dismissed-IDs *are* read-IDs; there's no way to later distinguish "dismissed the banner" from "read in the mailbox" for pre-update data. Acceptable because the two mean the same thing to the user, and the alternative (a fresh key) makes an already-handled announcement badge on update.
- **The badge depends on the recently-seen cache, not the server.** Unread is computed from what this device has fetched, capped at 10 entries. A user who never opens Home never fetches, so nothing badges — correct, but it means the mailbox is not a delivery guarantee. That is the accepted limit of an in-app channel and the reason push was considered at all.
- **Read-without-tapping keeps the badge.** A direct consequence of the per-row read trigger. If it reads as broken in practice, the fix is small — switch the trigger to mark-all-on-open.
- **A superseded announcement with no expiry badges until tapped.** `expiresAt` is optional, so an announcement the server has already replaced isn't expired from the client's view — it sits in the cache as unread until the user opens the mailbox and taps it. The expiry rule only un-badges announcements an admin actually set an expiry on, so setting one is the practical mitigation. Combined with mark-all-read being deferred, the badge can stay lit for a message that's no longer current.

---

## Sources / Research

- The bug: `Sources/GemmaChessCore/UI/RootView.swift` — `HomeView.onAppear`'s fetch guard, `onDisappear` clearing `announcementFetchTask`, `announcementCard`, and the `actions` stack ordering that places it above the primary buttons.
- Placement target: the same file's `.overlay(alignment: .topTrailing) { settingsButton }` and the `.navigationDestination(isPresented:)` pairs alongside it.
- Existing announcement surface: `Sources/GemmaChessCore/Announcements/AnnouncementStore.swift` (dismissed-ID set, recently-seen cache, injectable defaults), `AnnouncementClient.swift` (fail-soft fetch), `Announcement.swift`, `Sources/GemmaChessCore/UI/AnnouncementsView.swift` (list, empty state, expired rows).
- Superseded reasoning: `docs/plans/2026-07-24-001-feat-announcement-banner-plan.md` — its no-placeholder decision is the specific claim this plan corrects.
