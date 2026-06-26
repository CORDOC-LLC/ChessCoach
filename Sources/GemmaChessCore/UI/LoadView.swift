//  LoadView.swift
//  The entry screen: paste a PGN (or load a sample), pick a side, pull recent games
//  from a Lichess username, or reopen a previously-analysed game from local history.
//  Any of these routes ends in `vm.analyze(pgn:player:)`, which transitions the root
//  view to the review.

import SwiftUI

public struct LoadView: View {
    @Bindable var vm: ReviewViewModel

    @State private var pgn: String = ""
    @State private var side: String = "auto"
    @State private var username: String = ""
    @State private var lichessGames: [GameSummary] = []
    @State private var isFetching = false
    @State private var fetchError: String?
    @State private var history: [GameRecord] = []

    public init(vm: ReviewViewModel) { self.vm = vm }

    public var body: some View {
        Form {
            pgnSection
            lichessSection
            historySection
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Review")
        .overlay { if vm.isAnalyzing { analyzingOverlay } }
        .onAppear { history = HistoryStore().historyRows() }
        .alert("Couldn't analyze", isPresented: Binding(
            get: { vm.errorText != nil },
            set: { if !$0 { vm.errorText = nil } })) {
            Button("OK", role: .cancel) { vm.errorText = nil }
        } message: { Text(vm.errorText ?? "") }
    }

    // MARK: PGN

    private var pgnSection: some View {
        Section("Paste a game (PGN)") {
            TextEditor(text: $pgn)
                .frame(minHeight: 120)
                .font(.system(.footnote, design: .monospaced))
            Picker("Review side", selection: $side) {
                Text("Auto").tag("auto")
                Text("White").tag("white")
                Text("Black").tag("black")
            }
            .pickerStyle(.segmented)
            HStack {
                Button("Load sample game") { pgn = Self.samplePGN }
                Spacer()
                Button("Analyze") {
                    Task { await vm.analyze(pgn: pgn, player: side) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(pgn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isAnalyzing)
            }
        }
    }

    // MARK: Lichess

    private var lichessSection: some View {
        Section("Import from Lichess") {
            HStack {
                TextField("Lichess username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                Button("Fetch") { Task { await fetchLichess() } }
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isFetching)
            }
            if isFetching { ProgressView() }
            if let fetchError { Text(fetchError).foregroundStyle(.red).font(.footnote) }
            ForEach(lichessGames, id: \.gameID) { game in
                Button { Task { await vm.analyze(pgn: game.pgn, player: "auto") } } label: {
                    gameRow(white: game.white, black: game.black, result: game.result,
                            sub: [game.speed, game.opening].compactMap { $0 }.joined(separator: " · "))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: History

    private var historySection: some View {
        Section("My games") {
            if history.isEmpty {
                Text("Analysed games will appear here.").foregroundStyle(.secondary).font(.footnote)
            }
            ForEach(history, id: \.gameID) { rec in
                Button { Task { await vm.analyze(pgn: rec.pgn, player: rec.reviewedSide) } } label: {
                    gameRow(white: rec.white, black: rec.black, result: rec.result,
                            sub: [rec.speed, rec.opening, "acc \(Int(rec.accuracy.rounded()))%"]
                                .compactMap { $0 }.joined(separator: " · "))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func gameRow(white: String, black: String, result: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(white) vs \(black)").font(.subheadline).fontWeight(.medium)
            Text("\(result) · \(sub)").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var analyzingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView(value: vm.progress)
                    .frame(width: 180)
                Text("Analyzing… \(Int(vm.progress * 100))%")
                    .font(.subheadline)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func fetchLichess() async {
        isFetching = true
        fetchError = nil
        lichessGames = []
        defer { isFetching = false }
        do {
            lichessGames = try await LichessClient().fetchUserGames(username: username, max: 10)
            if lichessGames.isEmpty { fetchError = "No games found for that user." }
        } catch let error as LichessError {
            fetchError = error.message
        } catch {
            fetchError = error.localizedDescription
        }
    }

    /// A real, complete game (Morphy's "Opera Game", 1858) for one-tap demoing.
    static let samplePGN = """
    [Event "Paris"]
    [Site "Paris FRA"]
    [Date "1858.??.??"]
    [White "Paul Morphy"]
    [Black "Duke Karl / Count Isouard"]
    [Result "1-0"]

    1. e4 e5 2. Nf3 d6 3. d4 Bg4 4. dxe5 Bxf3 5. Qxf3 dxe5 6. Bc4 Nf6 7. Qb3 Qe7
    8. Nc3 c6 9. Bg5 b5 10. Nxb5 cxb5 11. Bxb5+ Nbd7 12. O-O-O Rd8 13. Rxd7 Rxd7
    14. Rd1 Qe6 15. Bxd7+ Nxd7 16. Qb8+ Nxb8 17. Rd8# 1-0
    """
}
