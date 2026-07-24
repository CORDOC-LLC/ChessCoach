//  AnnouncementClient.swift
//  Fetches the current occasional announcement from chesscoach-gateway's
//  public, unauthenticated `/api/announcement` endpoint (plan 2026-07-24-001,
//  U1/U2). No App Attest, no entitlement gate -- this isn't a paid feature or
//  a trust boundary, just content shown to already-open-app users.
//
//  Fails soft everywhere (R7): any failure -- no backend configured, network
//  error, non-2xx, an undecodable or empty body -- returns nil, never throws.
//  A slow/unreachable gateway must never block or delay the Home screen.

import Foundation

public enum AnnouncementClient {
    /// Fetches the current active announcement, or `nil` on any failure
    /// (including "no backend configured" and "no announcement is active").
    /// `session:` is injectable for testing, mirroring `ManagedCoach`'s
    /// `session: URLSession = .shared` pattern.
    public static func fetchCurrent(
        backendURL: @Sendable () -> String? = { ManagedCoachStore.loadBackendURL() },
        session: URLSession = .shared
    ) async -> Announcement? {
        guard let base = backendURL(), !base.isEmpty,
              let url = URL(string: "\(base)/api/announcement")
        else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              !data.isEmpty
        else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Announcement.self, from: data)
    }
}
