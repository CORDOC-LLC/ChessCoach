//  AnnouncementsView.swift
//  The mailbox (plan 2026-07-25-001): every announcement this device has seen,
//  read or not. Reached from Home's toolbar envelope and from Settings.
//
//  Reading is an explicit act: tapping a row marks THAT announcement read and
//  clears its share of the Home badge. A user who opens the mailbox, reads the
//  text, and taps nothing keeps the badge -- the tap is an acknowledgment, not
//  a side effect of scrolling past. Because of that, every row is tappable,
//  including ones with no link and ones already expired; making those inert
//  would leave them permanently un-markable.

import SwiftUI
#if os(iOS)
import UIKit
#endif

public struct AnnouncementsView: View {
    /// Injectable so tests can drive read state against a scratch suite --
    /// the store's own house style. Both call sites (Home's toolbar and
    /// Settings) use the default.
    private let defaults: UserDefaults
    @State private var announcements: [Announcement] = []
    @State private var readIDs: Set<String> = []
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

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
        .onAppear(perform: reload)
    }

    /// Reloads both the cache and read state. Runs on every appearance, so an
    /// announcement fetched while this screen was open surfaces next time it
    /// appears rather than mutating the list mid-read.
    private func reload() {
        announcements = AnnouncementStore.recentlySeen(defaults: defaults)
        readIDs = AnnouncementStore.readIDs(defaults: defaults)
    }

    private func isExpired(_ announcement: Announcement, now: Date = Date()) -> Bool {
        guard let expiresAt = announcement.expiresAt else { return false }
        return expiresAt <= now
    }

    /// Unread here means "not yet acknowledged" -- deliberately NOT the store's
    /// `isUnread`, which also excludes expired entries because those shouldn't
    /// badge. In the list an expired announcement can still be unread and still
    /// needs its dot, so the two states are shown independently: the dot answers
    /// "have I dealt with this?", the Expired caption answers "is it still live?"
    private func isUnread(_ announcement: Announcement) -> Bool {
        !readIDs.contains(announcement.id)
    }

    /// A row opens its link only when one exists and the announcement is still
    /// live -- a stale offer shouldn't be actionable, but tapping still marks
    /// it read.
    private func openableLink(for announcement: Announcement) -> URL? {
        guard !isExpired(announcement), let link = announcement.link else { return nil }
        return URL(string: link)
    }

    @ViewBuilder
    private func row(for announcement: Announcement) -> some View {
        let expired = isExpired(announcement)
        let unread = isUnread(announcement)
        Button {
            AnnouncementStore.markRead(id: announcement.id, defaults: defaults)
            readIDs.insert(announcement.id)
            #if os(iOS)
            if let url = openableLink(for: announcement) {
                UIApplication.shared.open(url)
            }
            #endif
        } label: {
            HStack(alignment: .top, spacing: 10) {
                // Leading dot marks unread; the title's weight carries the same
                // signal so it doesn't rely on spotting a small colored circle.
                Circle()
                    .fill(unread ? theme.accent2Color : .clear)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(announcement.title)
                            .font(unread ? .subheadline.weight(.bold) : .subheadline)
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unread ? "\(announcement.title), unread" : announcement.title)
    }
}
