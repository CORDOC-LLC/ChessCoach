//  AnnouncementsView.swift
//  Settings' "Announcements" screen (plan 2026-07-24-001, U4): lets a user
//  revisit anything they dismissed on Home by accident. Reads
//  `AnnouncementStore`'s recently-seen cache directly -- independent of
//  dismiss state, so a dismissed announcement's full content and link stay
//  available here. No dismiss/undismiss action here; re-triggering the Home
//  banner is out of scope (see the plan's Scope Boundaries).

import SwiftUI
#if os(iOS)
import UIKit
#endif

public struct AnnouncementsView: View {
    @State private var announcements: [Announcement] = []
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

    public init() {}

    public var body: some View {
        Group {
            if announcements.isEmpty {
                Text("No announcements yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(announcements) { announcement in
                    row(for: announcement)
                }
            }
        }
        .navigationTitle("Announcements")
        .onAppear {
            announcements = AnnouncementStore.recentlySeen()
        }
    }

    private func isExpired(_ announcement: Announcement) -> Bool {
        guard let expiresAt = announcement.expiresAt else { return false }
        return expiresAt <= Date()
    }

    @ViewBuilder
    private func row(for announcement: Announcement) -> some View {
        let expired = isExpired(announcement)
        Button {
            #if os(iOS)
            guard !expired, let link = announcement.link, let url = URL(string: link) else { return }
            UIApplication.shared.open(url)
            #endif
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(announcement.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textColor)
                    Spacer(minLength: 8)
                    if expired {
                        Text("Expired")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(announcement.body)
                    .font(.caption)
                    .foregroundStyle(theme.textColor.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
        .disabled(expired || announcement.link == nil)
    }
}
