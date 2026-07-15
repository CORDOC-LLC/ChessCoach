//  ManagedUsageClient.swift
//  Fetches token usage + estimated cost from chesscoach-gateway's
//  `GET /api/usage` — per-call events plus totals for whatever date range
//  the user picks. Ground truth lives entirely on the backend (the
//  usage_events table); this is a read-only client with no local caching,
//  since there's nothing to keep in sync.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One coaching call's token usage and estimated cost.
public struct ManagedUsageEvent: Identifiable, Equatable, Sendable {
    public var id: Date { createdAt }
    public let createdAt: Date
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let costUSD: Double
}

public struct ManagedUsageReport: Equatable, Sendable {
    public let since: Date
    public let until: Date
    public let events: [ManagedUsageEvent]
    public let totalInputTokens: Int
    public let totalOutputTokens: Int
    public let totalCostUSD: Double
}

public enum ManagedUsageClient {
    /// Fetches the usage report for `appUserId` over `[since, until]`. Throws
    /// `CoachError` with a user-legible message on any failure (not
    /// configured, not entitled, network error, bad response). `session`,
    /// `backendURL`, `debugToken`, and `appUserId` are injectable — same
    /// testable-closure pattern as `ManagedCoach`/`GeminiCoach` — defaulting
    /// to the real `ManagedCoachStore`-backed values.
    public static func fetchReport(
        since: Date,
        until: Date,
        session: URLSession = .shared,
        backendURL: @Sendable () -> String? = { ManagedCoachStore.loadBackendURL() },
        debugToken: @Sendable () -> String? = { ManagedCoachStore.loadDebugToken() },
        appUserId: @Sendable () -> String = { ManagedCoachStore.appUserId() }
    ) async throws -> ManagedUsageReport {
        guard let base = backendURL(), !base.isEmpty else {
            throw CoachError("Managed coach isn't configured.")
        }
        let outFormatter = Self.makeISOFormatter()
        var components = URLComponents(string: "\(base)/api/usage")
        components?.queryItems = [
            URLQueryItem(name: "appUserId", value: appUserId()),
            URLQueryItem(name: "since", value: outFormatter.string(from: since)),
            URLQueryItem(name: "until", value: outFormatter.string(from: until)),
        ]
        guard let url = components?.url else {
            throw CoachError("Invalid managed-coach backend URL.")
        }
        var request = URLRequest(url: url)
        if let token = debugToken(), !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Debug-Token")
        }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CoachError("Couldn't load usage (HTTP \(http.statusCode)).")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = Self.makeISOFormatter().date(from: string) { return date }
            if let date = ISO8601DateFormatter().date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unrecognized date format: \(string)")
        }
        let decoded = try decoder.decode(UsageResponse.self, from: data)
        return ManagedUsageReport(
            since: decoded.period.since, until: decoded.period.until,
            events: decoded.events.map {
                ManagedUsageEvent(
                    createdAt: $0.createdAt, model: $0.model,
                    inputTokens: $0.inputTokens, outputTokens: $0.outputTokens, costUSD: $0.costUSD
                )
            },
            totalInputTokens: decoded.totals.inputTokens,
            totalOutputTokens: decoded.totals.outputTokens,
            totalCostUSD: decoded.totals.costUSD
        )
    }

    private static func makeISOFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

// MARK: - Wire types (matches chesscoach-gateway's /api/usage response exactly)

private struct UsageResponse: Decodable {
    struct Period: Decodable { let since: Date; let until: Date }
    struct Event: Decodable {
        let createdAt: Date
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let costUSD: Double
    }
    struct Totals: Decodable { let inputTokens: Int; let outputTokens: Int; let costUSD: Double }

    let period: Period
    let events: [Event]
    let totals: Totals
}
