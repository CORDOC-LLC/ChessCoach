//  iCloudProgressSync.swift
//  Mirrors puzzle progress, rating, and streak state to the user's own
//  iCloud (via `NSUbiquitousKeyValueStore`) so it carries across their
//  devices. This is the user's own free iCloud storage -- no ChessCoach
//  backend involved, no cost, no account beyond the iCloud one the user
//  already has (or doesn't; see below). `UserDefaults` stays the local read
//  source of truth for every store; this type is a write-through mirror
//  plus a remote-change listener that merges incoming values back into
//  `UserDefaults`.
//
//  Merge semantics differ by data shape:
//   - Solved-puzzle-ID sets (`PuzzleProgressStore`) merge as a *union* --
//     losing a solved ID on a remote merge would incorrectly re-surface an
//     already-solved puzzle as new, so these are never allowed to shrink.
//   - Rating/streak scalars (`PuzzleRatingStore`, `PuzzleStreakStore`) merge
//     last-write-wins -- there's no meaningful way to "union" a rating or a
//     streak count, so the most recently written value simply replaces the
//     local one.
//
//  iCloud availability is best-effort and never load-bearing: if the user
//  isn't signed into iCloud (or it's otherwise unavailable),
//  `NSUbiquitousKeyValueStore` silently stores nothing, `object(forKey:)`
//  returns `nil`, and remote-change notifications simply never arrive with
//  new data. This file treats all of that as a normal no-op -- local-only
//  operation continues unaffected, nothing crashes, nothing is surfaced to
//  the user as an error.

import Foundation

/// The subset of `NSUbiquitousKeyValueStore`'s API this module depends on,
/// so tests can substitute an in-memory double instead of touching real
/// iCloud.
public protocol UbiquitousKeyValueStoring: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: UbiquitousKeyValueStoring {}

/// Mirrors local `UserDefaults` puzzle state to an injected
/// `UbiquitousKeyValueStoring` (real iCloud in production, an in-memory
/// double in tests) and merges remote changes back in.
// `@unchecked Sendable`: mutable state (`mergeRules`, `observerToken`) is
// only ever touched under `lock`, and the injected `keyValueStore`/
// `defaults`/`notificationCenter` are themselves safe to use concurrently
// (`UserDefaults` and `NSUbiquitousKeyValueStore` are documented
// thread-safe; the in-memory test double takes the same lock discipline).
// This lets `.shared` be a plain `static let` like the rest of this
// module's process-wide singletons (`ProEntitlementStore`, `EnginePool`)
// without forcing every call site in the (synchronous, non-async) puzzle
// stores onto an actor.
public final class iCloudProgressSync: @unchecked Sendable {

    /// How a key's value should be reconciled when a remote change
    /// notification carries a different value than what's stored locally.
    public enum MergeStrategy {
        /// Value is a `[String]` representing a set (e.g. solved puzzle
        /// IDs) -- remote and local are unioned, nothing already-present is
        /// ever lost.
        case unionStringSet
        /// Value is a scalar (`Int`, `Date`, ...) -- the remote value
        /// simply replaces the local one.
        case lastWriteWins
    }

    /// The real `NSUbiquitousKeyValueStore.default`-backed instance, wired
    /// to `UserDefaults.standard`, used as the default for production call
    /// sites in `PuzzleProgressStore`/`PuzzleRatingStore`/
    /// `PuzzleStreakStore`. Tests construct their own instance backed by an
    /// in-memory KV-store double instead of touching real iCloud.
    public static let shared = iCloudProgressSync()

    private let keyValueStore: UbiquitousKeyValueStoring
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var mergeRules: [(prefix: String, strategy: MergeStrategy)] = []
    private var observerToken: NSObjectProtocol?

    public init(
        keyValueStore: UbiquitousKeyValueStoring = NSUbiquitousKeyValueStore.default,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.keyValueStore = keyValueStore
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    deinit {
        if let observerToken {
            notificationCenter.removeObserver(observerToken)
        }
    }

    /// Mirrors `value` into the injected KV store under `key`. Callers
    /// (the three puzzle stores) are expected to have already written
    /// `value` to their local `UserDefaults` -- this only mirrors it
    /// onward. `nil` removes the key. A no-op, never a crash, if iCloud is
    /// unavailable.
    public func write(key: String, value: Any?) {
        keyValueStore.set(value, forKey: key)
    }

    /// Opportunistically nudges the KV store to sync with iCloud (e.g. on
    /// app foreground). Never depended on for correctness -- the OS syncs
    /// independently on its own schedule.
    @discardableResult
    public func synchronize() -> Bool {
        keyValueStore.synchronize()
    }

    /// Registers how keys starting with `keyPrefix` should be merged when a
    /// remote change notification arrives, and starts observing
    /// `NSUbiquitousKeyValueStore.didChangeExternallyNotification` if this
    /// is the first registered rule. Safe to call repeatedly (e.g. once per
    /// store at app startup).
    public func registerMergeRule(keyPrefix: String, strategy: MergeStrategy) {
        lock.lock()
        mergeRules.append((keyPrefix, strategy))
        lock.unlock()
        startObservingIfNeeded()
    }

    /// Registers the standard merge rules for all three puzzle stores:
    /// solved-ID sets (union) and rating/streak scalars (last-write-wins).
    /// Call once at app startup on `.shared`.
    public func registerPuzzleProgressMergeRules() {
        registerMergeRule(keyPrefix: PuzzleProgressStore.keyPrefix, strategy: .unionStringSet)
        registerMergeRule(keyPrefix: PuzzleRatingStore.key, strategy: .lastWriteWins)
        registerMergeRule(keyPrefix: PuzzleStreakStore.streakKeyPrefix, strategy: .lastWriteWins)
        registerMergeRule(keyPrefix: LessonProgressStore.defaultsKey, strategy: .lastWriteWins)
    }

    private func startObservingIfNeeded() {
        lock.lock()
        guard observerToken == nil else { lock.unlock(); return }
        lock.unlock()
        let token = notificationCenter.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleExternalChange(notification)
        }
        lock.lock()
        if observerToken == nil {
            observerToken = token
        } else {
            // Another thread won the race to register first; drop ours.
            notificationCenter.removeObserver(token)
        }
        lock.unlock()
    }

    private func handleExternalChange(_ notification: Notification) {
        guard let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
            return
        }
        lock.lock()
        let rules = mergeRules
        lock.unlock()
        for key in changedKeys {
            guard let strategy = rules.first(where: { key.hasPrefix($0.prefix) })?.strategy else { continue }
            merge(key: key, strategy: strategy)
        }
    }

    private func merge(key: String, strategy: MergeStrategy) {
        switch strategy {
        case .lastWriteWins:
            // No remote value (iCloud unavailable / nothing written yet) --
            // leave the local value untouched.
            guard let remoteValue = keyValueStore.object(forKey: key) else { return }
            defaults.set(remoteValue, forKey: key)

        case .unionStringSet:
            guard let remoteArray = keyValueStore.object(forKey: key) as? [String] else { return }
            let localArray = defaults.stringArray(forKey: key) ?? []
            let union = Set(localArray).union(remoteArray)
            defaults.set(Array(union), forKey: key)
        }
    }
}
