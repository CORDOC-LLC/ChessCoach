//  MacCommands.swift
//  Notification.Name bridge between GemmaChessMac's App-scene `.commands {}`
//  menu bar and the deep view hierarchy those commands act on (an
//  in-progress PlayViewModel, the Settings sheet). NotificationCenter is the
//  right tool here rather than a plumbed environment action: the Mac app
//  shell has no reference to whichever PlayView instance is currently on
//  screen, and RootView already uses NotificationCenter for a comparable
//  cross-component sync (see its `UserDefaults.didChangeNotification`
//  observer). Posting is Mac-only (GemmaChessApp.swift); observing is
//  harmless on iOS since these names are simply never posted there.

import Foundation

public extension Notification.Name {
    /// Posted by the Mac menu bar's "New Game" command (Cmd+N).
    static let ccMacNewGame = Notification.Name("com.cordoc.gemmachess.mac.newGame")
    /// Posted by the Mac menu bar's "Undo" command (Cmd+Z).
    static let ccMacUndo = Notification.Name("com.cordoc.gemmachess.mac.undo")
    /// Posted by the Mac menu bar's "Settings…" command (Cmd+,).
    static let ccMacShowSettings = Notification.Name("com.cordoc.gemmachess.mac.showSettings")
}
