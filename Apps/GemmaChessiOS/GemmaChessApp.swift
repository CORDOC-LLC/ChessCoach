//  GemmaChessApp.swift (iOS)
//  Thin shell: a single-column, board-first UI over GemmaChessCore.

import SwiftUI
import GemmaChessCore

@main
struct GemmaChessApp: App {
    /// RevenueCat's iOS public SDK key (project "ChessCoach", app "ChessCoach
    /// iOS") -- public keys are meant to ship in client code, unlike the
    /// debug bypass token below.
    private static let revenueCatAPIKey = "appl_DIpzDSCiFSZEpScItwsipIGNdCr"

    init() {
        // Wires in the TestFlight-only managed-coach debug token, generated
        // (gitignored, never committed) from local.env -- see
        // ManagedCoachStore.configureTestFlightToken and scripts/gen-project.sh.
        ManagedCoachStore.configureTestFlightToken(ManagedCoachSecrets.testFlightToken)
        ProEntitlementStore.shared.configure(apiKey: Self.revenueCatAPIKey)
    }

    var body: some Scene {
        WindowGroup {
            GemmaRootView(style: .column)
        }
    }
}
