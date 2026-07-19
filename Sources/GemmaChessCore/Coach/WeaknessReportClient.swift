//  WeaknessReportClient.swift
//  A narrow, standalone client for chesscoach-gateway's `/api/weaknessReport`
//  endpoint (plan U3/U4) -- deliberately NOT a `CoachLLM` conformance (KTD-3).
//  Every existing coach call (`ManagedCoach`) sends a client-built `{system,
//  prompt}` pair; this feature's whole point is that the prompt never ships
//  in this open-source client, so the wire contract here is facts-in,
//  narrative-out instead. Mirrors `ManagedCoach`'s request-building and
//  error-handling shape, but with its own wire types.
//
//  Managed-backend only (plan R7) -- there is no BYOK variant of this client,
//  since a user's own Gemini key has no server in between to keep a prompt
//  private on.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class WeaknessReportClient: Sendable {

    private let session: URLSession
    private let backendURL: @Sendable () -> String?
    private let debugToken: @Sendable () -> String?
    private let appUserId: @Sendable () -> String?

    public init(
        session: URLSession = .shared,
        backendURL: @escaping @Sendable () -> String? = { ManagedCoachStore.loadBackendURL() },
        debugToken: @escaping @Sendable () -> String? = { ManagedCoachStore.loadDebugToken() },
        appUserId: @escaping @Sendable () -> String? = { ManagedCoachStore.appUserId() }
    ) {
        self.session = session
        self.backendURL = backendURL
        self.debugToken = debugToken
        self.appUserId = appUserId
    }

    /// Fetch a fresh narrative from `facts`. Pro-gated at the same
    /// interception point every other coach call site uses, even though this
    /// client bypasses `CoachOrchestrator`/`CoachLLM` entirely. `channel`
    /// defaults to `.current` (always `.local` in a test binary, where the
    /// gate silently bypasses) -- tests force `.appStore` explicitly to
    /// exercise the throw path deterministically, mirroring
    /// `ProEntitlementStoreTests`'s own testing style, since there is no
    /// injectable backend here to stand in for "the gate failed" the way
    /// `CoachOrchestrator`'s call sites do.
    public func generateReport(facts: WeaknessReportFacts, channel: BuildChannel = .current) async throws -> String {
        try await ProEntitlementStore.shared.requireProOrThrow(channel: channel)
        let request = try buildRequest(facts: facts)
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response, data: data)
        let decoded = try JSONDecoder().decode(WeaknessReportResponse.self, from: data)
        return decoded.text
    }

    private func buildRequest(facts: WeaknessReportFacts) throws -> URLRequest {
        guard let base = backendURL(), !base.isEmpty, let userId = appUserId(), !userId.isEmpty else {
            throw CoachError("Managed coach isn't configured.")
        }
        guard let url = URL(string: "\(base)/api/weaknessReport") else {
            throw CoachError("Invalid managed-coach backend URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = debugToken(), !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Debug-Token")
        }
        request.httpBody = try JSONEncoder().encode(
            WeaknessReportRequest(
                appUserId: userId,
                topMotifs: facts.topMotifs.map { .init(motif: $0.motif, count: $0.count) },
                weakestPhase: facts.weakestPhase,
                recentAccuracy: facts.recentAccuracy,
                lifetimeAccuracy: facts.lifetimeAccuracy,
                gamesAnalyzed: facts.gamesAnalyzed
            )
        )
        return request
    }

    /// Same status-code contract as `ManagedCoach.checkStatus` (they share the
    /// same entitlement/quota gate server-side, per KTD-4).
    private static func checkStatus(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 402: throw CoachError("You've reached this month's coaching limit. It resets on your next renewal.")
        case 403: throw CoachError("ChessCoach Pro isn't active right now.")
        case 429: throw CoachError("The managed coach is busy. Try again in a moment.")
        default:
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw CoachError("Weakness Report error (HTTP \(http.statusCode)): \(body.prefix(200))")
        }
    }
}

// MARK: - Wire types (matches chesscoach-gateway's /api/weaknessReport contract exactly)

private struct WeaknessReportRequest: Encodable {
    struct MotifCount: Encodable {
        let motif: String
        let count: Int
    }
    let appUserId: String
    let topMotifs: [MotifCount]
    let weakestPhase: String?
    let recentAccuracy: Double?
    let lifetimeAccuracy: Double?
    let gamesAnalyzed: Int
}

private struct WeaknessReportResponse: Decodable {
    let text: String
}
