//  GemmaChessApp.swift (macOS)
//  Thin shell: a multi-column NavigationSplitView UI over GemmaChessCore.

import SwiftUI
import GemmaChessCore

@main
struct GemmaChessApp: App {
    var body: some Scene {
        WindowGroup {
            GemmaRootView(style: .split)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentSize)
        .commands {
            // Additive Mac-native entry points -- the on-screen buttons
            // (back chevron / "New game" menu row, the header's undo icon,
            // the gear icon) stay the primary UI; these are a second path
            // to the same actions, posted via NotificationCenter since the
            // app shell has no direct reference to whichever PlayViewModel
            // is currently on screen. See GemmaChessCore's MacCommands.swift.
            CommandGroup(replacing: .newItem) {
                Button("New Game") {
                    NotificationCenter.default.post(name: .ccMacNewGame, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .undoRedo) {
                Button("Undo Move") {
                    NotificationCenter.default.post(name: .ccMacUndo, object: nil)
                }
                .keyboardShortcut("z", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .ccMacShowSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
