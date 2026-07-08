//  ManagedCoach.swift
//  The developer-hosted, metered coach backend (chesscoach-gateway). Calls
//  ChessCoach's OWN `/coach` endpoint, never a provider directly — the backend
//  picks the provider/model server-side (plan KTD-3), so this file has zero
//  provider-specific parsing, unlike GeminiCoach which necessarily knows
//  Gemini's wire format.
//
//  Entitlement is checked server-side (RevenueCat, plan KTD-8) — this file
//  just attaches `appUserId` and an optional App Attest header to every call.
//  Until U6 wires up RevenueCat client-side, `appUserId`/backend URL/debug
//  token all come from `ManagedCoachStore`, which is deliberately temporary
//  scaffolding for local testing (see that file's header comment).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class ManagedCoach: CoachLLM, Sendable {

    private let session: URLSession
    private let backendURL: @Sendable () -> String?
    private let debugToken: @Sendable () -> String?
    private let appUserId: @Sendable () -> String?
    /// A model override, sent ONLY alongside a debug token — the backend
    /// silently drops it on any non-bypassed (real subscriber) request, so
    /// this is purely a local-testing lever for comparing models on
    /// latency/price/accuracy, never something a paying user can steer.
    private let debugModel: @Sendable () -> String?

    public init(
        session: URLSession = .shared,
        backendURL: @escaping @Sendable () -> String? = { ManagedCoachStore.loadBackendURL() },
        debugToken: @escaping @Sendable () -> String? = { ManagedCoachStore.loadDebugToken() },
        appUserId: @escaping @Sendable () -> String? = { ManagedCoachStore.debugAppUserId() },
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

    public func generate(system: String, prompt: String, sessionID: String?) async throws -> CoachReply {
        let request = try buildRequest(system: system, prompt: prompt, stream: false)
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response, data: data)
        let decoded = try JSONDecoder().decode(CoachResponse.self, from: data)
        return CoachReply(answer: decoded.text, sessionID: nil)
    }

    public func stream(system: String, prompt: String, sessionID: String?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(system: system, prompt: prompt, stream: true)
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
    /// ever non-nil when a debug token is ALSO present — the backend enforces
    /// this too (KTD-3), but computing it the same way here means a tester
    /// never accidentally sends a model override that a production build
    /// would silently ignore, keeping the two paths honest with each other.
    static func effectiveModel(debugToken: String?, debugModel: String?) -> String? {
        guard let debugToken, !debugToken.isEmpty else { return nil }
        guard let debugModel, !debugModel.isEmpty else { return nil }
        return debugModel
    }

    private func buildRequest(system: String, prompt: String, stream: Bool) throws -> URLRequest {
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
            CoachRequest(system: system, prompt: prompt, stream: stream, appUserId: userId, model: model)
        )
        return request
    }

    private static func checkStatus(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 402: throw CoachError("You've reached this month's coaching limit. It resets on your next renewal.")
        case 403: throw CoachError("ChessCoach Pro isn't active. Subscribe in Settings for the managed coach.")
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

// MARK: - Wire types (matches chesscoach-gateway's /coach contract exactly)

private struct CoachRequest: Encodable {
    let system: String
    let prompt: String
    let stream: Bool
    let appUserId: String
    let model: String?
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
