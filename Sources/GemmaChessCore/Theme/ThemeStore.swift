//  ThemeStore.swift
//  Holds the active theme, the user's custom themes, and the in-progress
//  editor draft. Persists to UserDefaults under the design handoff's own key
//  names (cc_custom_themes / cc_active_theme) so this app's storage layout
//  matches the reference prototype's localStorage layout 1:1. On-device only
//  -- no theme ever leaves the device, matching SavedGameStore's model.

import SwiftUI

@MainActor
@Observable
public final class ThemeStore {

    private let defaults: UserDefaults

    private enum Key {
        static let customThemes = "cc_custom_themes"
        static let activeTheme = "cc_active_theme"
    }

    public private(set) var customs: [Theme]
    public private(set) var activeID: String

    /// The theme currently being edited, or nil when the picker (not the
    /// editor) is showing. Set by `newDraft(from:)`/`editDraft(id:)`, cleared
    /// by `save(_:)`/`cancelEdit()`.
    public var draft: Theme?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.customs = (try? JSONDecoder().decode(
            [Theme].self, from: defaults.data(forKey: Key.customThemes) ?? Data()
        )) ?? []
        self.activeID = defaults.string(forKey: Key.activeTheme) ?? Theme.gambit.id
    }

    /// The 4 built-in presets -- always these 4, never persisted.
    public var presets: [Theme] { Theme.presets }

    /// Every theme available to the picker, presets first.
    public var allThemes: [Theme] { presets + customs }

    /// The currently active theme -- customs win over presets on id clash
    /// (shouldn't happen, ids are namespaced, but customs are checked first
    /// since they're more likely to be the live edit target). Falls back to
    /// Gambit if `activeID` matches nothing (e.g. its custom theme was
    /// deleted from under it, or the stored id is corrupt).
    public var active: Theme {
        customs.first(where: { $0.id == activeID })
            ?? presets.first(where: { $0.id == activeID })
            ?? .gambit
    }

    /// What every screen should actually render: the live draft while
    /// editing, otherwise the active theme.
    public var effective: Theme { draft ?? active }

    /// Applies a theme by id and persists it. The Appearance sheet stays
    /// open after this so the user can compare themes.
    public func apply(id: String) {
        activeID = id
        persistActive()
    }

    /// Starts a new custom theme, seeded from `theme`'s colors/type but with
    /// a fresh identity -- used by "Create a new theme".
    public func newDraft(from theme: Theme) {
        var copy = theme
        copy.id = "c\(UUID().uuidString.prefix(8))"
        copy.name = "My Theme"
        copy.kind = .custom
        draft = copy
    }

    /// Starts editing an existing theme by id. Editing a preset forks a new
    /// custom copy (presets stay pristine); editing a custom theme edits it
    /// in place. No-op if `id` matches nothing.
    public func editDraft(id: String) {
        if let existing = customs.first(where: { $0.id == id }) {
            draft = existing
        } else if let preset = presets.first(where: { $0.id == id }) {
            var copy = preset
            copy.id = "c\(UUID().uuidString.prefix(8))"
            copy.name = "\(preset.name) copy"
            copy.kind = .custom
            draft = copy
        }
    }

    /// Whether `draft` is an in-place edit of an already-saved custom theme
    /// (vs. a brand-new one) -- the Appearance sheet uses this to decide
    /// whether to show Delete and whether the title reads "Edit"/"New".
    public var isEditingExistingCustom: Bool {
        guard let draft else { return false }
        return customs.contains { $0.id == draft.id }
    }

    /// Saves `draft` (upsert into customs), makes it active, persists, and
    /// clears the draft.
    public func save(_ theme: Theme) {
        var updated = customs
        if let index = updated.firstIndex(where: { $0.id == theme.id }) {
            updated[index] = theme
        } else {
            updated.append(theme)
        }
        customs = updated
        activeID = theme.id
        persistCustoms()
        persistActive()
        draft = nil
    }

    /// Discards the in-progress edit without persisting anything.
    public func cancelEdit() {
        draft = nil
    }

    /// Removes a custom theme. If it was active, falls back to Gambit.
    public func delete(id: String) {
        customs.removeAll { $0.id == id }
        persistCustoms()
        if activeID == id {
            apply(id: Theme.gambit.id)
        }
    }

    // MARK: - Persistence

    private func persistCustoms() {
        guard let data = try? JSONEncoder().encode(customs) else { return }
        defaults.set(data, forKey: Key.customThemes)
    }

    private func persistActive() {
        defaults.set(activeID, forKey: Key.activeTheme)
    }
}
