//  PlayDisplaySettings.swift
//  The independent show/hide preferences for Play mode's optional surfaces,
//  persisted across launches via UserDefaults. An @Observable so SwiftUI tracks
//  changes; the Bool properties read/write UserDefaults directly (the @AppStorage
//  equivalent for a model object, since @AppStorage is a View-only wrapper).
//
//  showMoveComments and showOpening are both engine-only/free (Stockfish's own
//  grading and the local Lichess opening book -- no network call either way).
//  showCoach is the ONLY one of these that costs Gemini credits (the written
//  per-move note, chat, and end-of-game debrief) -- kept as an independent
//  toggle specifically so a user can keep the free stuff on and turn off the
//  one thing that spends money, or vice versa.

import SwiftUI

@MainActor
@Observable
public final class PlayDisplaySettings {

    private let defaults: UserDefaults

    // Keys + defaults. Coach / captured / move list / move comments / opening
    // default ON; best-move OFF (opt-in, since live hints can feel like
    // cheating and add clutter).
    private enum Key {
        static let showBestMove = "play.showBestMove"
        static let showCaptured = "play.showCaptured"
        static let showMoveList = "play.showMoveList"
        static let showMoveComments = "play.showMoveComments"
        static let showOpening = "play.showOpening"
        static let showCoach    = "play.showCoach"
        static let defaultEngineSkill = "play.defaultEngineSkill"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Register defaults so first-launch reads return the intended values.
        defaults.register(defaults: [
            Key.showBestMove: false,
            Key.showCaptured: true,
            Key.showMoveList: true,
            Key.showMoveComments: true,
            Key.showOpening: true,
            Key.showCoach: true,
            Key.defaultEngineSkill: 6,
        ])
        // Seed the observation tracking so @Observable emits on change.
        _showBestMove = defaults.bool(forKey: Key.showBestMove)
        _showCaptured = defaults.bool(forKey: Key.showCaptured)
        _showMoveList = defaults.bool(forKey: Key.showMoveList)
        _showMoveComments = defaults.bool(forKey: Key.showMoveComments)
        _showOpening = defaults.bool(forKey: Key.showOpening)
        _showCoach    = defaults.bool(forKey: Key.showCoach)
        _defaultEngineSkill = defaults.integer(forKey: Key.defaultEngineSkill)
    }

    public var showBestMove: Bool {
        didSet { defaults.set(showBestMove, forKey: Key.showBestMove) }
    }
    public var showCaptured: Bool {
        didSet { defaults.set(showCaptured, forKey: Key.showCaptured) }
    }
    public var showMoveList: Bool {
        didSet { defaults.set(showMoveList, forKey: Key.showMoveList) }
    }
    /// The verdict chip + engine's top-3 candidate moves ("Best Moves" card).
    /// Free -- Stockfish only, no network.
    public var showMoveComments: Bool {
        didSet { defaults.set(showMoveComments, forKey: Key.showMoveComments) }
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
}
