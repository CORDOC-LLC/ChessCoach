//  ManagedCoach.swift
//  The developer-hosted, metered coach backend (chesscoach-gateway). Calls
//  ChessCoach's OWN `/api/coach` endpoint, never a provider directly -- the
//  backend picks the provider/model server-side.
//
//  Plan 2026-07-21-002 (U1/KTD-2/KTD-3): this used to send a client-assembled
//  `{system, prompt}` pair -- the actual coaching instructions, plaintext in
//  this open-source client. It now sends `{kind, facts}`: `kind` says which
//  persona applies ("chat"/"moveNote"/"summary"), `facts` is one of
//  `CoachOrchestrator`'s structured payload types (`ChatFacts`,
//  `SummaryImportedFacts`, `SummaryPlayFacts`). The gateway assembles the
//  actual prompt from these server-side and never returns it. Mirrors
//  `WeaknessReportClient`'s request-building/error-handling shape (facts-in,
//  narrative-out), generalized to the three coach "kinds".
//
//  Entitlement is checked server-side (RevenueCat) -- this file just attaches
//  `appUserId` and an optional App Attest header to every call. `appUserId`/
//  backend URL/debug token all come from `ManagedCoachStore`, which reads the
//  real RevenueCat subscriber ID once the SDK is configured (see that file's
//  header comment).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class ManagedCoach: Sendable {

    private let session: URLSession
    private let backendURL: @Sendable () -> String?
    private let debugToken: @Sendable () -> String?
    private let appUserId: @Sendable () -> String?
    /// A model override, sent ONLY alongside a debug token -- the backend
    /// silently drops it on any non-bypassed (real subscriber) request, so
    /// this is purely a local-testing lever for comparing models on
    /// latency/price/accuracy, never something a paying user can steer.
    private let debugModel: @Sendable () -> String?

    public init(
        session: URLSession = .shared,
        backendURL: @escaping @Sendable () -> String? = { ManagedCoachStore.loadBackendURL() },
        debugToken: @escaping @Sendable () -> String? = { ManagedCoachStore.loadDebugToken() },
        appUserId: @escaping @Sendable () -> String? = { ManagedCoachStore.appUserId() },
        debugModel: @escaping @Sendable () -> String? = { ManagedCoachStore.loadDebugModel() }
    ) {
        self.session = session
        self.backendURL = backendURL
        self.debugToken = debugToken
        self.appUserId = appUserId
        self.debugModel = debugModel
    }

    public var availability: CoachAvailability {
        guard let url = backendURL(), !url.isEmpty else {
            return .unavailable(reason: "Managed coach isn't configured.")
        }
        _ = url
        return .managed
    }

    /// Non-streaming call. `facts` is `ChatFacts` for `.chat`/`.moveNote`, or
    /// one of the summary facts payloads for `.summary` -- whatever shape
    /// matches `kind` on the wire.
    public func generate<Facts: Encodable & Sendable>(
        kind: CoachRequestKind, facts: Facts, sessionID: String?
    ) async throws -> CoachReply {
        let request = try buildRequest(kind: kind, facts: facts, stream: false)
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response, data: data)
        let decoded = try JSONDecoder().decode(CoachResponse.self, from: data)
        return CoachReply(answer: decoded.text, sessionID: nil)
    }

    public func stream<Facts: Encodable & Sendable>(
        kind: CoachRequestKind, facts: Facts, sessionID: String?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(kind: kind, facts: facts, stream: true)
                    let (bytes, response) = try await session.bytes(for: request)
                    try Self.checkStatus(response, data: nil)
                    for try await line in bytes.lines {
                        guard let jsonText = line.dropPrefix("data: ") else { continue }
                        if jsonText == "[DONE]" { break }
                        guard let chunkData = jsonText.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(CoachResponse.self, from: chunkData)
                        else { continue }
                        continuation.yield(chunk.text)   // already cumulative (server contract)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error as? CoachError ?? CoachError(Self.friendly(error)))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: helpers

    /// The model override to send, or nil to let the server decide. Only
    /// ever non-nil when a debug token is ALSO present -- the backend enforces
    /// this too, but computing it the same way here means a tester never
    /// accidentally sends a model override that a production build would
    /// silently ignore, keeping the two paths honest with each other.
    static func effectiveModel(debugToken: String?, debugModel: String?) -> String? {
        guard let debugToken, !debugToken.isEmpty else { return nil }
        guard let debugModel, !debugModel.isEmpty else { return nil }
        return debugModel
    }

    private func buildRequest<Facts: Encodable & Sendable>(
        kind: CoachRequestKind, facts: Facts, stream: Bool
    ) throws -> URLRequest {
        guard let base = backendURL(), !base.isEmpty, let userId = appUserId(), !userId.isEmpty else {
            throw CoachError("Managed coach isn't configured.")
        }
        guard let url = URL(string: "\(base)/api/coach") else {
            throw CoachError("Invalid managed-coach backend URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = debugToken(), !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Debug-Token")
        }
        let model = Self.effectiveModel(debugToken: debugToken(), debugModel: debugModel())
        request.httpBody = try JSONEncoder().encode(
            CoachRequestBody(
                kind: kind.rawValue, facts: facts, stream: stream, appUserId: userId,
                // No App Attest client yet -- the field is optional on the wire and
                // the gateway soft-fails its absence, same as `/api/weaknessReport`.
                attestation: nil, model: model
            )
        )
        return request
    }

    private static func checkStatus(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 402: throw CoachError("You've reached this month's coaching limit. It resets on your next renewal.")
        case 403: throw CoachError("ChessCoach Pro isn't active right now. Try again shortly, or check "
            + "Coach Settings.")
        case 429: throw CoachError("The managed coach is busy. Try again in a moment.")
        default:
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw CoachError("Managed coach error (HTTP \(http.statusCode)): \(body.prefix(200))")
        }
    }

    private static func friendly(_ error: Error) -> String {
        "Couldn't reach the managed coach: \(error.localizedDescription)"
    }
}

// MARK: - Wire types (matches chesscoach-gateway's /api/coach contract exactly)

private struct CoachRequestBody<Facts: Encodable & Sendable>: Encodable {
    let kind: String
    let facts: Facts
    let stream: Bool
    let appUserId: String
    let attestation: Attestation?
    let model: String?

    struct Attestation: Encodable {
        let keyId: String
        let assertion: String
    }
}

private struct CoachResponse: Decodable {
    let text: String
    let model: String?
}

private extension StringProtocol {
    func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
