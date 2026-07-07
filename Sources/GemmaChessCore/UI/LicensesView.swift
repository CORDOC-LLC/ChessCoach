//  LicensesView.swift
//  Open-source attribution, required reading given Stockfish (GPLv3) is linked
//  directly into this app's binary — GPLv3 requires crediting it and making the
//  full license text available to anyone who receives the app.

import SwiftUI

/// One third-party component: name, license, a short note, and its full license
/// text (loaded from a bundled resource, or nil when none applies, e.g. CC0).
private struct LicenseEntry: Identifiable {
    let id = UUID()
    let name: String
    let license: String
    let note: String
    let resourceFile: String?
}

public struct LicensesView: View {
    public init() {}

    private let entries: [LicenseEntry] = [
        LicenseEntry(
            name: "Stockfish",
            license: "GNU General Public License v3.0",
            note: "The chess engine that analyses every position and grades every move. "
                + "Compiled from source and linked into this app, which makes ChessCoach's "
                + "own source GPLv3 as well — it's published in full alongside this app.",
            resourceFile: "gplv3"
        ),
        LicenseEntry(
            name: "chesskit-swift & chesskit-engine",
            license: "MIT License",
            note: "Chess rules, move generation, and the Stockfish UCI wrapper.",
            resourceFile: "chesskit-mit"
        ),
        LicenseEntry(
            name: "Lichess chess-openings",
            license: "CC0 1.0 (public domain)",
            note: "The opening database used to name your line as you play it (e.g. "
                + "\"London System\"). No attribution required — credited as a courtesy.",
            resourceFile: nil
        ),
        LicenseEntry(
            name: "Apple Foundation Models",
            license: "Apple system framework",
            note: "The on-device model that explains the engine's verdicts in plain English.",
            resourceFile: nil
        ),
        LicenseEntry(
            name: "Gemma (via MLX)",
            license: "Gemma Terms of Use",
            note: "A fallback coach model on devices without Apple Intelligence.",
            resourceFile: nil
        ),
    ]

    public var body: some View {
        List {
            Section {
                Text("ChessCoach is built on the projects below. Because Stockfish (GPLv3) "
                    + "is compiled into this app, ChessCoach's own source is open too — "
                    + "GPLv3 requires it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                NavigationLink {
                    LicenseDetailView(entry: entry.name, license: entry.license,
                                      note: entry.note, resourceFile: entry.resourceFile)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name).font(.body.weight(.medium))
                        Text(entry.license).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Open Source Licenses")
    }
}

private struct LicenseDetailView: View {
    let entry: String
    let license: String
    let note: String
    let resourceFile: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(note)
                    .font(.subheadline)
                if let text = licenseText {
                    Divider()
                    Text(text)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(entry)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var licenseText: String? {
        guard let resourceFile,
              let url = Bundle.module.url(forResource: resourceFile, withExtension: "txt",
                                          subdirectory: "licenses"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return text
    }
}
