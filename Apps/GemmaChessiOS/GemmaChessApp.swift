//  GemmaChessApp.swift (iOS)
//  Thin shell: a single-column, board-first UI over GemmaChessCore.

import SwiftUI
import GemmaChessCore

@main
struct GemmaChessApp: App {
    init() {
        // Wires in the TestFlight-only managed-coach debug token, generated
        // (gitignored, never committed) from local.env -- see
        // ManagedCoachStore.configureTestFlightToken and scripts/gen-project.sh.
        ManagedCoachStore.configureTestFlightToken(ManagedCoachSecrets.testFlightToken)
    }

    var body: some Scene {
        WindowGroup {
            GemmaRootView(style: .column)
        }
    }
}
