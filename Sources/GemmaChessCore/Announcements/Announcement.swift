//  Announcement.swift
//  The occasional-message wire struct -- field names match chesscoach-gateway's
//  /api/announcement contract exactly (plan 2026-07-24-001, U1/U2).

import Foundation

public struct Announcement: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var body: String
    public var link: String?
    public var expiresAt: Date?

    public init(id: String, title: String, body: String, link: String? = nil, expiresAt: Date? = nil) {
        self.id = id; self.title = title; self.body = body
        self.link = link; self.expiresAt = expiresAt
    }
}
