//  GeminiCoach.swift
//  Optional cloud coach backend: Google's Gemini API, used with the user's own
//  API key. Small on-device models (Foundation Models, Gemma) are good at
//  summarizing pre-computed facts but their explanations are shallow; Gemini gives
//  a noticeably better-reasoned "why" for the same engine-grounded facts. This is
//  strictly an upgrade to the EXPLANATION layer — Stockfish still decides
//  everything; Gemini, like every other backend, only writes.
//
//  Entirely opt-in: with no key stored in `GeminiKeyStore`, availability reports
//  `.unavailable` and the orchestrator falls through to the on-device backend.
//  No new SPM dependency — the REST surface (generateContent /
//  streamGenerateContent) is small enough to call directly over URLSession.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class GeminiCoach: CoachLLM, Sendable {

    /// Fast + inexpensive; more than strong enough for grounded coaching prose.
    public static let defaultModel = "gemini-2.5-flash"

    private let session: URLSession
    private let baseURL: String
    private let model: @Sendable () -> String
    private let apiKey: @Sendable () -> String?

    /// `model` is a closure, not a fixed value, so changing the choice in Coach
    /// Settings takes effect on the NEXT call with no need to recreate the coach
    /// (mirrors how `apiKey` is re-read fresh every time, not captured once).
    public init(
        session: URLSession = .shared,
        baseURL: String = "https://generativelanguage.googleapis.com/v1beta",
        model: @escaping @Sendable () -> String = { GeminiKeyStore.loadModel() },
        apiKey: @escaping @Sendable () -> String? = { GeminiKeyStore.load() }
    ) {
        self.session = session
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
    }

    public var availability: CoachAvailability {
        guard let key = apiKey(), !key.isEmpty else {
            return .unavailable(reason: "Add a Gemini API key in Settings for richer coaching.")
        }
        _ = key
        return .gemini
    }

    public func generate(system: String, prompt: String, sessionID: String?) async throws -> CoachReply {
        guard let key = apiKey(), !key.isEmpty else {
            throw CoachError("No Gemini API key is set. Add one in Settings.")
        }
        guard let url = URL(string: "\(baseURL)/models/\(model()):generateContent?key=\(key)") else {
            throw CoachError("Invalid Gemini endpoint.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GeminiRequest(system: system, prompt: prompt))

        let (data, response) = try await session.data(for: request)
        try Self.checkHTTPStatus(response, data: data)
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = decoded.text else {
            throw CoachError(decoded.blockReason.map { "Gemini declined to answer: \($0)" }
                ?? "Gemini returned an empty response.")
        }
        return CoachReply(answer: text, sessionID: nil)
    }

    public func stream(system: String, prompt: String, sessionID: String?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard let key = apiKey(), !key.isEmpty else {
                    continuation.finish(throwing: CoachError("No Gemini API key is set. Add one in Settings."))
                    return
                }
                guard let url = URL(
                    string: "\(baseURL)/models/\(model()):streamGenerateContent?alt=sse&key=\(key)"
                ) else {
                    continuation.finish(throwing: CoachError("Invalid Gemini endpoint.")); return
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONEncoder().encode(GeminiRequest(system: system, prompt: prompt))

                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    try Self.checkHTTPStatus(response, data: nil)
                    var cumulative = ""
                    for try await line in bytes.lines {
                        guard let jsonText = line.dropPrefix("data: ") else { continue }
                        guard let chunkData = jsonText.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(GeminiResponse.self, from: chunkData),
                              let piece = chunk.text
                        else { continue }
                        cumulative += piece                 // Gemini streams DELTAS, not cumulative text
                        continuation.yield(cumulative)
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

    private static func checkHTTPStatus(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 400: throw CoachError("Gemini rejected the request (bad API key or malformed prompt).")
        case 401, 403: throw CoachError("Gemini API key was rejected. Check it in Settings.")
        case 429: throw CoachError("Gemini rate limit hit. Try again in a moment.")
        default:
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw CoachError("Gemini error (HTTP \(http.statusCode)): \(body.prefix(200))")
        }
    }

    private static func friendly(_ error: Error) -> String {
        "Couldn't reach Gemini: \(error.localizedDescription)"
    }
}

// MARK: - Wire types (minimal subset of the Gemini REST schema we actually use)

private struct GeminiRequest: Encodable {
    let systemInstruction: Part
    let contents: [Content]

    struct Part: Encodable { let parts: [Text] }
    struct Content: Encodable { let role: String; let parts: [Text] }
    struct Text: Encodable { let text: String }

    init(system: String, prompt: String) {
        systemInstruction = Part(parts: [Text(text: system)])
        contents = [Content(role: "user", parts: [Text(text: prompt)])]
    }

    enum CodingKeys: String, CodingKey { case systemInstruction = "system_instruction", contents }
}

private struct GeminiResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let text: String? }
            let parts: [Part]?
        }
        let content: Content?
        let finishReason: String?
    }
    struct PromptFeedback: Decodable { let blockReason: String? }

    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?

    var text: String? {
        candidates?.first?.content?.parts?.compactMap(\.text).joined()
    }
    var blockReason: String? { promptFeedback?.blockReason }
}

private extension StringProtocol {
    /// `dropFirst(prefix.count)` when `self` has the prefix, else nil — used to
    /// pull the JSON payload out of an SSE "data: {...}" line.
    func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
