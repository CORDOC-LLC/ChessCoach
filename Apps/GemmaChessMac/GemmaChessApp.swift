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
    }
}
