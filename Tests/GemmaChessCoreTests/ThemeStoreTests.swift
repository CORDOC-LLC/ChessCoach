//  ThemeStoreTests.swift

import Testing
import Foundation
@testable import GemmaChessCore

@MainActor
@Suite("ThemeStore")
struct ThemeStoreTests {

    private static func scratchDefaults() -> UserDefaults {
        let suite = "ThemeStoreTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test("fresh store defaults to Gambit with no customs")
    func freshStoreDefaults() {
        let store = ThemeStore(defaults: Self.scratchDefaults())
        #expect(store.active.id == "gambit")
        #expect(store.customs.isEmpty)
    }

    @Test("apply(id:) sets active and persists across a fresh instance")
    func applyPersists() {
        let defaults = Self.scratchDefaults()
        let store = ThemeStore(defaults: defaults)
        store.apply(id: "night")
        #expect(store.active.id == "night")

        let reloaded = ThemeStore(defaults: defaults)
        #expect(reloaded.active.id == "night")
    }

    @Test("newDraft(from:) then save upserts into customs and applies it")
    func newDraftThenSave() {
        let defaults = Self.scratchDefaults()
        let store = ThemeStore(defaults: defaults)
        store.newDraft(from: .gambit)
        #expect(store.draft != nil)
        var draft = store.draft!
        draft.accent = "#123456"
        store.save(draft)

        #expect(store.draft == nil)
        #expect(store.active.id == draft.id)
        #expect(store.active.accent == "#123456")
        #expect(store.customs.contains { $0.id == draft.id })

        let reloaded = ThemeStore(defaults: defaults)
        #expect(reloaded.customs.contains { $0.id == draft.id })
        #expect(reloaded.active.id == draft.id)
    }

    @Test("editDraft on a preset forks a new custom copy, preset stays untouched")
    func editDraftForksPreset() throws {
        let store = ThemeStore(defaults: Self.scratchDefaults())
        store.editDraft(id: "gambit")
        let draft = try #require(store.draft)
        #expect(draft.kind == .custom)
        #expect(draft.id != "gambit")
        #expect(draft.name == "The Gambit Room copy")
        #expect(store.presets.first { $0.id == "gambit" }?.name == "The Gambit Room")
    }

    @Test("editDraft on an existing custom theme edits in place")
    func editDraftEditsCustomInPlace() {
        let store = ThemeStore(defaults: Self.scratchDefaults())
        store.newDraft(from: .gambit)
        var draft = store.draft!
        draft.name = "Mine"
        store.save(draft)
        let savedID = draft.id

        store.editDraft(id: savedID)
        #expect(store.draft?.id == savedID)
        #expect(store.isEditingExistingCustom)
    }

    @Test("isEditingExistingCustom is false for a brand-new draft")
    func isEditingExistingCustomFalseForNewDraft() {
        let store = ThemeStore(defaults: Self.scratchDefaults())
        store.newDraft(from: .gambit)
        #expect(!store.isEditingExistingCustom)
    }

    @Test("delete on the active custom theme falls back to gambit")
    func deleteActiveFallsBackToGambit() {
        let store = ThemeStore(defaults: Self.scratchDefaults())
        store.newDraft(from: .night)
        let draft = store.draft!
        store.save(draft)
        #expect(store.active.id == draft.id)

        store.delete(id: draft.id)
        #expect(store.active.id == "gambit")
        #expect(!store.customs.contains { $0.id == draft.id })
    }

    @Test("delete on a non-active custom theme leaves activeID unchanged")
    func deleteNonActiveLeavesActiveUnchanged() {
        let store = ThemeStore(defaults: Self.scratchDefaults())
        store.newDraft(from: .night)
        let draftA = store.draft!
        store.save(draftA)

        store.newDraft(from: .study)
        let draftB = store.draft!
        store.save(draftB)
        #expect(store.active.id == draftB.id)

        store.delete(id: draftA.id)
        #expect(store.active.id == draftB.id)
    }

    @Test("malformed stored JSON does not crash -- customs empty")
    func malformedStoredJSONIsSafe() {
        let defaults = Self.scratchDefaults()
        defaults.set(Data("not json".utf8), forKey: "cc_custom_themes")
        let store = ThemeStore(defaults: defaults)
        #expect(store.customs.isEmpty)
    }

    @Test("effective returns draft while editing, falls back to active once cleared")
    func effectiveTracksDraft() {
        let store = ThemeStore(defaults: Self.scratchDefaults())
        #expect(store.effective.id == store.active.id)

        store.newDraft(from: .night)
        #expect(store.effective.id == store.draft!.id)
        #expect(store.effective.id != store.active.id)

        store.cancelEdit()
        #expect(store.effective.id == store.active.id)
    }

    @Test("cancelEdit discards the draft without persisting")
    func cancelEditDiscardsDraft() {
        let defaults = Self.scratchDefaults()
        let store = ThemeStore(defaults: defaults)
        store.newDraft(from: .gambit)
        store.cancelEdit()
        #expect(store.draft == nil)
        #expect(store.customs.isEmpty)

        let reloaded = ThemeStore(defaults: defaults)
        #expect(reloaded.customs.isEmpty)
    }
}
