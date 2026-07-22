//  PlayDisplaySettings.swift
//  The independent show/hide preferences for Play mode's optional surfaces,
//  persisted across launches via UserDefaults. An @Observable so SwiftUI tracks
//  changes; the Bool properties read/write UserDefaults directly (the @AppStorage
//  equivalent for a model object, since @AppStorage is a View-only wrapper).
//
//  showCaptured, showMoveList, and showOpening are all engine-only/free (local
//  state and the local Lichess opening book -- no network call either way).
//  showCoach is the ONLY one of these that spends credits (the written
//  per-move note, chat, and end-of-game debrief) -- kept as an independent
//  toggle specifically so a user can keep the free stuff on and turn off the
//  one thing that spends money, or vice versa.

import SwiftUI

@MainActor
@Observable
public final class PlayDisplaySettings {

    private let defaults: UserDefaults

    // Keys + defaults. Coach / captured / move list / opening default ON.
    private enum Key {
        static let showCaptured = "play.showCaptured"
        static let showMoveList = "play.showMoveList"
        static let showOpening = "play.showOpening"
        static let showCoach    = "play.showCoach"
        static let defaultEngineSkill = "play.defaultEngineSkill"
        static let humanLikeEnabled = "play.humanLikeEnabled"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Register defaults so first-launch reads return the intended values.
        defaults.register(defaults: [
            Key.showCaptured: true,
            Key.showMoveList: true,
            Key.showOpening: true,
            Key.showCoach: true,
            Key.defaultEngineSkill: 6,
            Key.humanLikeEnabled: false,
        ])
        // Seed the observation tracking so @Observable emits on change.
        _showCaptured = defaults.bool(forKey: Key.showCaptured)
        _showMoveList = defaults.bool(forKey: Key.showMoveList)
        _showOpening = defaults.bool(forKey: Key.showOpening)
        _showCoach    = defaults.bool(forKey: Key.showCoach)
        _defaultEngineSkill = defaults.integer(forKey: Key.defaultEngineSkill)
        _humanLikeEnabled = defaults.bool(forKey: Key.humanLikeEnabled)
    }

    public var showCaptured: Bool {
        didSet { defaults.set(showCaptured, forKey: Key.showCaptured) }
    }
    public var showMoveList: Bool {
        didSet { defaults.set(showMoveList, forKey: Key.showMoveList) }
    }
    /// The recognized opening name/ECO label. Free -- local book lookup only.
    public var showOpening: Bool {
        didSet { defaults.set(showOpening, forKey: Key.showOpening) }
    }
    /// The written coach explanation (per-move note, chat, debrief). The ONLY
    /// one of these toggles that spends Gemini credits.
    public var showCoach: Bool {
        didSet { defaults.set(showCoach, forKey: Key.showCoach) }
    }
    /// Opponent (Stockfish) strength (0-20) to preselect for the next new
    /// game -- remembers whatever was last played, and is editable directly
    /// from Settings too.
    public var defaultEngineSkill: Int {
        didSet { defaults.set(defaultEngineSkill, forKey: Key.defaultEngineSkill) }
    }
    /// Opt-in "Human-like" opponent (plan R1): when on, the opening plies draw
    /// varied lines from the bundled ECO book instead of always the engine's
    /// own top choice. Off by default -- this changes how the opponent plays,
    /// so it should never surprise someone who didn't ask for it.
    public var humanLikeEnabled: Bool {
        didSet { defaults.set(humanLikeEnabled, forKey: Key.humanLikeEnabled) }
    }
}
