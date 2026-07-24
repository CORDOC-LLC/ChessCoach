//  AnnouncementStore.swift
//  Local dismissed-ID tracking + a small recently-seen cache for the
//  occasional in-app announcement banner (plan 2026-07-24-001, U2).
//  Entirely local -- no backend, no account. Follows `ReviewPromptStore`'s
//  API shape (plain enum, static funcs, injectable `defaults:`), but its
//  storage is necessarily richer: a `Set<String>` of dismissed IDs and a
//  capped array of full `Announcement`s, both JSON-encoded under their own
//  keys rather than ReviewPromptStore's two bare scalars.
//
//  Dismissing is permanent, per announcement ID (plan KTD): once dismissed,
//  that ID never shows on Home again on this device. `recordSeen` is called
//  unconditionally on every successful fetch, independent of dismiss state,
//  so Settings' Announcements screen can still show something a user
//  dismissed by accident.

import Foundation

public enum AnnouncementStore {
    /// Oldest entries evict first once the recently-seen cache exceeds this.
    public static let recentlySeenCap = 10

    private static let dismissedIDsKey = "announcements.dismissedIDs"
    private static let recentlySeenKey = "announcements.recentlySeen"

    /// The set of announcement IDs dismissed on this device. Missing or
    /// corrupt data decodes as empty rather than crashing.
    public static func dismissedIDs(defaults: UserDefaults = .standard) -> Set<String> {
        guard let data = defaults.data(forKey: dismissedIDsKey),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return [] }
        return decoded
    }

    /// Recently-seen announcements, newest first. Independent of dismiss
    /// state -- a dismissed announcement stays in this list.
    public static func recentlySeen(defaults: UserDefaults = .standard) -> [Announcement] {
        guard let data = defaults.data(forKey: recentlySeenKey),
              let decoded = try? JSONDecoder().decode([Announcement].self, from: data)
        else { return [] }
        return decoded
    }

    /// Whether `announcement` should show on Home right now: not expired and
    /// not already dismissed. Pure function, injectable `now:` for testability
    /// -- mirrors `ReviewPromptStore.shouldPrompt`'s injectable-clock pattern.
    public static func shouldShow(
        _ announcement: Announcement, dismissedIDs: Set<String>, now: Date = Date()
    ) -> Bool {
        if dismissedIDs.contains(announcement.id) { return false }
        if let expiresAt = announcement.expiresAt, expiresAt <= now { return false }
        return true
    }

    /// Records that `announcement` was fetched, unconditionally -- called
    /// regardless of whether it will actually show (regardless of
    /// `shouldShow`), so Settings can list it even if it's already dismissed
    /// or expired. Newest-first; caps at `recentlySeenCap`, evicting the
    /// oldest entries. A re-seen announcement (same id) is not deduplicated
    /// specially -- callers only fetch one current announcement at a time,
    /// so duplicates would only arise from repeated identical fetches, which
    /// harmlessly just move it back to the front.
    public static func recordSeen(_ announcement: Announcement, defaults: UserDefaults = .standard) {
        var seen = recentlySeen(defaults: defaults)
        seen.removeAll { $0.id == announcement.id }
        seen.insert(announcement, at: 0)
        if seen.count > recentlySeenCap {
            seen.removeLast(seen.count - recentlySeenCap)
        }
        guard let data = try? JSONEncoder().encode(seen) else { return }
        defaults.set(data, forKey: recentlySeenKey)
    }

    /// Permanently hides `id` on Home (plan KTD: dismiss is forever, per ID).
    public static func dismiss(id: String, defaults: UserDefaults = .standard) {
        var ids = dismissedIDs(defaults: defaults)
        ids.insert(id)
        guard let data = try? JSONEncoder().encode(ids) else { return }
        defaults.set(data, forKey: dismissedIDsKey)
    }

    /// Clears all announcement state (for Settings' reset-progress family,
    /// mirroring `ReviewPromptStore.reset()`).
    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: dismissedIDsKey)
        defaults.removeObject(forKey: recentlySeenKey)
    }
}
