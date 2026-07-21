//  GameImportView.swift
//  U4 — import games by pasting/uploading a PGN blob or by fetching a public
//  Chess.com/Lichess account's game history. Entirely free: both account fetches are
//  public, unauthenticated third-party reads, and analysis is the same local Stockfish
//  sweep every other reviewed game uses -- see `GameImportClient` and
//  `HistoryStore.analyzeAndRecordGame`, which this view calls rather than inventing a
//  parallel intake.
//
//  Each fetched/split game is listed for one-tap "Analyze" (mirroring `LoadView`'s
//  existing per-game rows), not auto-analyzed in bulk -- a full engine sweep per game
//  is real work, so the user picks which of their games to review right now.

import SwiftUI

public struct GameImportView: View {
    private let client: GameImportClient

    @State private var pastedPGN = ""
    @State private var pastedGames: [String] = []
    @State private var pasteMessage: String?

    @State private var platform: GameImportClient.Platform = .chessCom
    @State private var username = ""
    @State private var isFetching = false
    @State private var fetchError: String?
    @State private var fetchedGames: [String] = []
    @State private var detectedHandle: String?
    /// Shown above the account-fetch results when the fetch actually turned up
    /// games to review -- nudges toward the Weakness Report, which is where
    /// imported+reviewed games pay off. See `shouldShowImportNudge`.
    @State private var showReviewNudge = false

    /// Which game (by index into whichever list it came from) is currently being
    /// analyzed, so its row can show a spinner instead of the whole screen blocking.
    @State private var analyzingKey: String?
    @State private var importError: String?

    public init(client: GameImportClient = GameImportClient()) {
        self.client = client
    }

    public var body: some View {
        Form {
            pasteSection
            accountSection
            if !pastedGames.isEmpty { gamesSection(title: "Pasted games", games: pastedGames, keyPrefix: "paste") }
            if !fetchedGames.isEmpty {
                if showReviewNudge { reviewNudgeSection }
                gamesSection(title: "\(platform.displayName) games", games: fetchedGames, keyPrefix: "account")
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Import Games")
        .alert("Couldn't analyze that game", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "") }
    }

    // MARK: Paste

    private var pasteSection: some View {
        Section("Paste or upload a PGN") {
            TextEditor(text: $pastedPGN)
                .frame(minHeight: 120)
                .font(.system(.footnote, design: .monospaced))
            HStack {
                Button("Split into games") {
                    pastedGames = client.importPastedPGN(pastedPGN)
                    pasteMessage = pastedGames.isEmpty ? "No valid games found in that text." : nil
                }
                .disabled(pastedPGN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                if !pastedGames.isEmpty {
                    Text("\(pastedGames.count) game\(pastedGames.count == 1 ? "" : "s") found")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let pasteMessage {
                Text(pasteMessage).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Account

    private var accountSection: some View {
        Section("Import from an account") {
            Picker("Platform", selection: $platform) {
                ForEach(GameImportClient.Platform.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                Button("Fetch") { Task { await fetchAccount() } }
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isFetching)
            }
            if isFetching { ProgressView().frame(maxWidth: .infinity) }
            if let fetchError { Text(fetchError).font(.footnote).foregroundStyle(.red) }
        }
    }

    private func fetchAccount() async {
        isFetching = true
        fetchError = nil
        fetchedGames = []
        detectedHandle = nil
        showReviewNudge = false
        defer { isFetching = false }
        let name = username.trimmingCharacters(in: .whitespaces)
        var thrownError: GameImportError?
        do {
            let games = try await client.importAccount(platform: platform, username: name)
            fetchedGames = games
            detectedHandle = GameImportClient.detectSelfHandle(games: games, username: name)
            if games.isEmpty { fetchError = "No public games found for that username." }
        } catch let error as GameImportError {
            fetchError = error.message
            thrownError = error
        } catch {
            fetchError = error.localizedDescription
        }
        showReviewNudge = Self.shouldShowImportNudge(games: fetchedGames, fetchError: thrownError)
    }

    /// Pure decision for whether the post-import nudge toward the Weakness Report
    /// should show: only when the fetch actually succeeded (no thrown
    /// `GameImportError`) and turned up at least one game. A valid empty result
    /// (username exists, zero public games) and any failed fetch both resolve to
    /// `false` -- there's nothing yet to point the user toward reviewing.
    /// Extracted as a pure, static function (rather than left inline in
    /// `fetchAccount()`) so it's unit-testable without driving SwiftUI `@State`.
    static func shouldShowImportNudge(games: [String], fetchError: GameImportError?) -> Bool {
        fetchError == nil && !games.isEmpty
    }

    /// A small callout pointing at the Weakness Report -- imported games only pay
    /// off there once a few have actually been analyzed, so this nudges the user
    /// toward that rather than leaving the fresh import as a silent list.
    private var reviewNudgeSection: some View {
        Section {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
                Text("Analyze a few of these games to feed your Weakness Report -- a coach-synthesized look at your recent play.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Results

    private func gamesSection(title: String, games: [String], keyPrefix: String) -> some View {
        Section(title) {
            ForEach(Array(games.enumerated()), id: \.offset) { index, pgn in
                let key = "\(keyPrefix)-\(index)"
                let headers = MultiPGN.headers(ofPGN: pgn)
                Button {
                    Task { await analyze(pgn: pgn, key: key) }
                } label: {
                    HStack {
                        gameRow(headers: headers)
                        Spacer()
                        if analyzingKey == key { ProgressView() }
                    }
                }
                .buttonStyle(.plain)
                .disabled(analyzingKey != nil)
            }
        }
    }

    private func gameRow(headers: [String: String]) -> some View {
        let white = headers["White"] ?? "?"
        let black = headers["Black"] ?? "?"
        let result = headers["Result"] ?? "*"
        let sub = [headers["TimeControl"], headers["Opening"]].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(white) vs \(black)").font(.subheadline).fontWeight(.medium)
            Text([result, sub].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func analyze(pgn: String, key: String) async {
        guard analyzingKey == nil else { return }
        analyzingKey = key
        defer { analyzingKey = nil }
        let identity = detectedHandle.map { PlayerIdentity(username: $0) } ?? PlayerIdentity()
        do {
            _ = try await HistoryStore.analyzeAndRecordGame(pgn: pgn, player: "auto", identity: identity)
        } catch let error as AnalysisError {
            importError = error.message
        } catch {
            importError = error.localizedDescription
        }
    }
}
