//  PlayDisplaySettings.swift
//  The four independent show/hide preferences for Play mode's optional surfaces,
//  persisted across launches via UserDefaults. An @Observable so SwiftUI tracks
//  changes; the Bool properties read/write UserDefaults directly (the @AppStorage
//  equivalent for a model object, since @AppStorage is a View-only wrapper).

import SwiftUI

@MainActor
@Observable
public final class PlayDisplaySettings {

    private let defaults: UserDefaults

    // Keys + defaults. Coach / captured / move list default ON; best-move OFF
    // (opt-in, since live hints can feel like cheating and add clutter).
    private enum Key {
        static let showBestMove = "play.showBestMove"
        static let showCaptured = "play.showCaptured"
        static let showMoveList = "play.showMoveList"
        static let showCoach    = "play.showCoach"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Register defaults so first-launch reads return the intended values.
        defaults.register(defaults: [
            Key.showBestMove: false,
            Key.showCaptured: true,
            Key.showMoveList: true,
            Key.showCoach: true,
        ])
        // Seed the observation tracking so @Observable emits on change.
        _showBestMove = defaults.bool(forKey: Key.showBestMove)
        _showCaptured = defaults.bool(forKey: Key.showCaptured)
        _showMoveList = defaults.bool(forKey: Key.showMoveList)
        _showCoach    = defaults.bool(forKey: Key.showCoach)
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
    public var showCoach: Bool {
        didSet { defaults.set(showCoach, forKey: Key.showCoach) }
    }
}
