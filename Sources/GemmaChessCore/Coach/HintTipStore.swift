//  HintTipStore.swift
//  Whether the one-time "what does the hint button do" callout in Play mode's
//  header has already been shown -- see PlayView.hintTipBubble.

import Foundation

public enum HintTipStore {
    private static let key = "hint.tipSeen"

    public static func hasSeenTip() -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    public static func markSeen() {
        UserDefaults.standard.set(true, forKey: key)
    }
}
