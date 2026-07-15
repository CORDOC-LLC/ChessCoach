//  ManagedVisionClient.swift
//  Recognizes a chess position from a board photo via chesscoach-gateway's
//  `POST /api/vision` — a paid-tier (managed coach) capability, same gate as
//  every other managed call. This is the ONE place a photo touches the
//  network; the FEN it returns is handed straight to `ChessLogic`/Stockfish,
//  which do everything else entirely on-device.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Thrown when the backend couldn't confidently read a position out of the
/// photo (HTTP 422) — distinct from `CoachError` so callers can show a
/// specific "try a clearer photo" message rather than a generic failure.
public struct BoardRecognitionFailure: Error, Equatable, Sendable {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
}

public enum ManagedVisionClient {
    /// Recognizes the position in `imageData`, returning a normalized FEN.
    /// Throws `CoachError` for configuration/entitlement/network failures
    /// (same taxonomy as `ManagedCoach`) and `BoardRecognitionFailure` when
    /// the backend responded but couldn't read a position. Same injectable
    /// closures as `ManagedCoach`/`ManagedUsageClient`.
    public static func recognizeBoard(
        imageData: Data,
        mediaType: String = "image/jpeg",
        session: URLSession = .shared,
        backendURL: @Sendable () -> String? = { ManagedCoachStore.loadBackendURL() },
        debugToken: @Sendable () -> String? = { ManagedCoachStore.loadDebugToken() },
        appUserId: @Sendable () -> String = { ManagedCoachStore.appUserId() }
    ) async throws -> String {
        guard let base = backendURL(), !base.isEmpty else {
            throw CoachError("Managed coach isn't configured.")
        }
        guard let url = URL(string: "\(base)/api/vision") else {
            throw CoachError("Invalid managed-coach backend URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = debugToken(), !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Debug-Token")
        }
        request.httpBody = try JSONEncoder().encode(
            VisionRequest(
                appUserId: appUserId(),
                imageBase64: imageData.base64EncodedString(),
                mediaType: mediaType
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CoachError("Couldn't reach the managed coach.")
        }
        switch http.statusCode {
        case 200..<300:
            let decoded = try JSONDecoder().decode(VisionResponse.self, from: data)
            return decoded.fen
        case 402:
            throw CoachError("You've reached this month's coaching limit. It resets on your next renewal.")
        case 403:
            throw CoachError("ChessCoach Pro isn't active. Subscribe in Settings to scan a board.")
        case 422:
            let decoded = try? JSONDecoder().decode(VisionErrorResponse.self, from: data)
            throw BoardRecognitionFailure(
                decoded?.reason ?? "Couldn't recognize a chess position in that photo."
            )
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CoachError("Managed coach error (HTTP \(http.statusCode)): \(body.prefix(200))")
        }
    }
}

// MARK: - Wire types (matches chesscoach-gateway's /api/vision contract exactly)

private struct VisionRequest: Encodable {
    let appUserId: String
    let imageBase64: String
    let mediaType: String
}

private struct VisionResponse: Decodable {
    let fen: String
}

private struct VisionErrorResponse: Decodable {
    let error: String
    let reason: String
}
