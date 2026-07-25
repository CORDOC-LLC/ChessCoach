//  AnnouncementStore.swift
//  Local read-state tracking + a small recently-seen cache for the occasional
//  in-app announcement (plan 2026-07-25-001). Entirely local -- no backend, no
//  account. Follows `ReviewPromptStore`'s API shape (plain enum, static funcs,
//  injectable `defaults:`), but its storage is necessarily richer: a
//  `Set<String>` of read IDs and a capped array of full `Announcement`s, both
//  JSON-encoded under their own keys rather than two bare scalars.
//
//  READ, NOT DISMISSED. An earlier version of this feature showed a banner on
//  Home that could be dismissed forever; announcements now live in a mailbox
//  reached from the Home toolbar, so the same stored set means "handled" rather
//  than "hidden." The storage KEY is deliberately unchanged from that version
//  (`announcements.dismissedIDs`): anything a user already dismissed carries
//  over as already-read, so an app update never resurfaces a handled
//  announcement as unread. Do not rename the key.

import Foundation

public enum AnnouncementStore {
    /// Oldest entries evict first once the recently-seen cache exceeds this.
    public static let recentlySeenCap = 10

    /// Named for the shipped-then-superseded "dismissed" semantics -- see this
    /// file's header. The value is now the set of READ announcement IDs; the
    /// key is kept verbatim so existing on-device data carries over.
    private static let readIDsKey = "announcements.dismissedIDs"
    private static let recentlySeenKey = "announcements.recentlySeen"

    /// The set of announcement IDs already read (or dismissed under the prior
    /// shipped behavior) on this device. Missing or corrupt data decodes as
    /// empty rather than crashing.
    public static func readIDs(defaults: UserDefaults = .standard) -> Set<String> {
        guard let data = defaults.data(forKey: readIDsKey),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return [] }
        return decoded
    }

    /// Recently-seen announcements, newest first. Independent of read state --
    /// a read announcement stays in this list so it can always be revisited.
    public static func recentlySeen(defaults: UserDefaults = .standard) -> [Announcement] {
        guard let data = defaults.data(forKey: recentlySeenKey),
              let decoded = try? JSONDecoder().decode([Announcement].self, from: data)
        else { return [] }
        return decoded
    }

    /// Whether `announcement` should count toward the mailbox's unread badge:
    /// not yet read, and not expired. Pure function, injectable `now:` for
    /// testability -- mirrors `ReviewPromptStore.shouldPrompt`'s pattern.
    ///
    /// Expiry suppresses the badge but never hides the announcement: an
    /// expired-but-unread entry is still listed and still readable, it just
    /// stops nagging.
    public static func isUnread(
        _ announcement: Announcement, readIDs: Set<String>, now: Date = Date()
    ) -> Bool {
        if readIDs.contains(announcement.id) { return false }
        if let expiresAt = announcement.expiresAt, expiresAt <= now { return false }
        return true
    }

    /// Whether anything in the recently-seen cache is unread -- the mailbox
    /// badge's single source of truth.
    ///
    /// Callers should cache this in view state rather than calling it from a
    /// SwiftUI `body`: it reads `UserDefaults` and JSON-decodes the whole
    /// cache, and this app has already shipped a launch hang caused by
    /// persisted-state reads inside a root view's body (see `GemmaRootView`).
    public static func hasUnread(now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        let read = readIDs(defaults: defaults)
        return recentlySeen(defaults: defaults).contains { isUnread($0, readIDs: read, now: now) }
    }

    /// Records that `announcement` was fetched, unconditionally -- called
    /// regardless of read state, so the mailbox lists it either way. Newest
    /// first; caps at `recentlySeenCap`, evicting the oldest. Re-seeing an
    /// announcement moves it back to the front without duplicating it.
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

    /// Marks a single announcement read. Other announcements are unaffected.
    public static func markRead(id: String, defaults: UserDefaults = .standard) {
        var ids = readIDs(defaults: defaults)
        ids.insert(id)
        guard let data = try? JSONEncoder().encode(ids) else { return }
        defaults.set(data, forKey: readIDsKey)
    }

    /// Clears all announcement state (for Settings' reset-progress family,
    /// mirroring `ReviewPromptStore.reset()`).
    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: readIDsKey)
        defaults.removeObject(forKey: recentlySeenKey)
    }
}
