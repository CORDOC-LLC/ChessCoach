//  GemmaChessApp.swift (iOS)
//  Thin shell: a single-column, board-first UI over GemmaChessCore.

import SwiftUI
import GemmaChessCore

@main
struct GemmaChessApp: App {
    var body: some Scene {
        WindowGroup {
            GemmaRootView(style: .column)
        }
    }
}
