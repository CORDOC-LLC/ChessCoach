//  PlayView.swift
//  Play mode UI: a compact pre-game setup (side + engine strength), then a
//  space-efficient live board — eval bar, advantage read-out, tap-to-move board,
//  and a running coach panel that grades each of your moves.

import SwiftUI

/// Shows the new-game setup until a game is started, then the live game.
public struct PlayContainerView: View {
    @Bindable var vm: PlayViewModel
    var onExit: () -> Void
    @State private var started: Bool
    @State private var sideIsWhite = true

    /// `startedInitially`: skip the setup form and go straight to the live
    /// game -- used when `vm` was just loaded from a `SavedGame` (Resume, or
    /// opening a finished game for replay from Home/My Games).
    public init(vm: PlayViewModel, onExit: @escaping () -> Void, startedInitially: Bool = false) {
        self.vm = vm; self.onExit = onExit
        self._started = State(initialValue: startedInitially)
    }

    public var body: some View {
        if started {
            PlayView(vm: vm, onNewGame: { started = false })
        } else {
            setup
        }
    }

    private var setup: some View {
        Form {
            Section("New game") {
                Picker("You play", selection: $sideIsWhite) {
                    Text("White").tag(true)
                    Text("Black").tag(false)
                }
                .pickerStyle(.segmented)
                Stepper("Engine strength: \(vm.skill)/20", value: $vm.skill, in: 0...20)
                Text("Coach: \(coachLabel)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button {
                    vm.newGame(asWhite: sideIsWhite)
                    started = true
                } label: {
                    Text("Start playing").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Play")
        .toolbar { ToolbarItem(placement: .topBarLeadingCompat) { Button("Home", action: onExit) } }
    }

    private var coachLabel: String {
        switch vm.coachAvailability {
        case .gemini: return "Gemini"
        case .managed: return "ChessCoach Pro"
        case .unavailable(let reason): return "engine only — \(reason)"
        }
    }
}

/// The live game.
public struct PlayView: View {
    @Bindable var vm: PlayViewModel
    var onNewGame: () -> Void
    @State private var settings = PlayDisplaySettings()
    @State private var showChat = false

    public init(vm: PlayViewModel, onNewGame: @escaping () -> Void) {
        self.vm = vm; self.onNewGame = onNewGame
    }

    public var body: some View {
        VStack(spacing: 8) {
            header
            board
            if settings.showCaptured { capturedRow }
            if vm.hint != nil { hintCard }
            if settings.showMoveList {
                MoveListView(vm: vm)
                    .frame(maxHeight: 132)
                    .padding(.horizontal, 12)
            }
            if settings.showOpening, let opening = vm.opening {
                openingRow(opening)
            }
            if settings.showMoveComments {
                bestMovesCard
                    .padding(.horizontal, 12)
            }
            if settings.showCoach {
                coachCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
            } else if !settings.showMoveComments {
                Spacer(minLength: 0)
            }
        }
        .padding(.bottom, 8)
        .onChange(of: settings.showCoach, initial: true) { _, showCoach in
            vm.coachDisplayEnabled = showCoach
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    // Eval bar is a leading overlay so its height tracks the board exactly
    // (an HStack sibling stretched greedily and left a big gap).
    private var board: some View {
        ChessBoardView(
            fen: vm.displayFEN,
            orientation: vm.orientation,
            arrows: boardArrows,
            lastMove: vm.displayLastMove,
            selectedSquare: vm.selected,
            legalDots: vm.legalDots,
            onTapSquare: { vm.tap($0) }
        )
        .padding(.leading, 22)
        .overlay(alignment: .leading) {
            EvalBarView(winWhite: vm.winWhite, whiteAtBottom: vm.playerIsWhite)
                .frame(width: 14)
        }
        .padding(.horizontal, 12)
    }

    // MARK: Board arrows
    //
    // Best-move recommendation graphics are shown ONLY while a hint is active (the
    // lightbulb). There is no separate always-on best-move arrow — turning the hint
    // off removes every recommendation arrow from the board.

    private var boardArrows: [BoardArrow] {
        var arrows: [BoardArrow] = []
        // Neutral arrow for the move that was played, when browsing history.
        if let viewing = vm.viewingPly {
            let playedUCI = vm.moves.indices.contains(viewing) ? vm.moves[viewing] : nil
            if let uci = playedUCI, let a = BoardArrow(uci: uci, color: .gray, thick: false) {
                arrows.append(a)
            }
        }
        // Hint arrows: best (accent, thick) + alternative (gold, thin). Live board only.
        if let hint = vm.hint, !vm.isViewingHistory {
            if let a = BoardArrow(uci: hint.bestUCI, color: GemmaTheme.accent, thick: true) {
                arrows.append(a)
            }
            if let second = hint.secondUCI,
               let a = BoardArrow(uci: second, color: GemmaTheme.gold.opacity(0.9), thick: false) {
                arrows.append(a)
            }
        }
        return arrows
    }

    // MARK: Header
    //
    // One dense row: back, a status pill that now also carries the win-probability
    // pie + eval (so the old advantage chip no longer costs a row of its own), the
    // hint button, and a "⋯" menu that holds Resign and the show/hide toggles.

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onNewGame) {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .gemmaGlassPill()
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(GemmaTheme.accent)

            statusPill
            Spacer(minLength: 4)
            hintButton
            menuButton
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    /// Status text + a compact black/white win-probability pie + the eval number.
    private var statusPill: some View {
        HStack(spacing: 8) {
            if vm.engineThinking || vm.isCoaching { ProgressView().controlSize(.small) }
            Text(vm.status)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(vm.gameOver ? GemmaTheme.accent : .white)
                .lineLimit(1).minimumScaleFactor(0.7)
            WinPie(winWhite: vm.winWhite)
            Text(vm.evalText)
                .font(.subheadline.weight(.bold)).monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .gemmaGlassPill()
    }

    private var menuButton: some View {
        @Bindable var settings = settings
        return Menu {
            Section("Show") {
                Toggle(isOn: $settings.showCaptured) { Label("Captured pieces", systemImage: "trophy") }
                Toggle(isOn: $settings.showMoveList) { Label("Move list", systemImage: "list.bullet") }
                Toggle(isOn: $settings.showMoveComments) { Label("Best moves", systemImage: "chart.bar.fill") }
                Toggle(isOn: $settings.showOpening) { Label("Opening name", systemImage: "book.closed.fill") }
                Toggle(isOn: $settings.showCoach) { Label("Coach (uses credits)", systemImage: "bubble.left.fill") }
            }
            Section {
                Button { onNewGame() } label: { Label("New game", systemImage: "arrow.counterclockwise") }
                if !vm.gameOver {
                    Button(role: .destructive) { vm.resign() } label: { Label("Resign", systemImage: "flag") }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 30, height: 30)
                .gemmaGlassPill()
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Captured row
    //
    // A single slim row under the board: your captures at the leading edge, the
    // opponent's at the trailing edge (replaces the two flanking trays).

    private var capturedRow: some View {
        let cap = vm.capturedMaterial
        let playerCaptures = vm.playerIsWhite ? cap.capturedByWhite : cap.capturedByBlack
        let opponentCaptures = vm.playerIsWhite ? cap.capturedByBlack : cap.capturedByWhite
        let playerAdvantage = vm.playerIsWhite ? cap.delta : -cap.delta
        return HStack(spacing: 8) {
            CapturedTrayView(pieces: playerCaptures, advantage: playerAdvantage)
            Spacer(minLength: 8)
            CapturedTrayView(pieces: opponentCaptures, advantage: -playerAdvantage)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    /// The lightbulb is the single switch for best-move graphics: tap to show the
    /// hint (best + alternative arrows + rationale), tap again to hide them.
    private var hintButton: some View {
        let on = vm.hint != nil
        return Button { on ? vm.clearHint() : vm.requestHint() } label: {
            Image(systemName: on ? "lightbulb.fill" : "lightbulb")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(on ? GemmaTheme.gold : .white.opacity(0.7))
                .frame(width: 30, height: 30)
                .gemmaGlassPill()
        }
        .buttonStyle(PressableStyle())
        .disabled(!vm.userToMove || vm.isViewingHistory || vm.gameOver)
    }

    // MARK: Hint card (best + alternative + rationale, dismissible)

    @ViewBuilder
    private var hintCard: some View {
        if let hint = vm.hint {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(GemmaTheme.gold).font(.footnote)
                    Text(hint.summaryLabel)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if hint.isLoading { ProgressView().controlSize(.small) }
                    Button { vm.clearHint() } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.6))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }
                if let rationale = hint.rationale, !rationale.isEmpty {
                    Text(rationale.asCoachMarkdown)
                        .font(.footnote).foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gemmaGlass(cornerRadius: 16)
            .padding(.horizontal, 12)
        }
    }

    // MARK: Opening name (free -- local Lichess book lookup, no network)

    /// The named opening the game has followed so far ("London System · A45"),
    /// refined live as the line deepens — a persistent teaching label, so the
    /// user learns what their setup is called while they play it. Entirely
    /// independent of the Coach toggle: this never touches the network.
    private func openingRow(_ opening: Openings.Opening) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "book.closed.fill")
                .font(.caption2).foregroundStyle(GemmaTheme.gold)
            Text("\(opening.name) · \(opening.eco)")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    // MARK: Best Moves card (verdict + top-3 candidates + retry — all engine-
    // only, free, no Gemini/network involved)

    private var bestMovesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill").foregroundStyle(GemmaTheme.gold).font(.footnote)
                Text("Best Moves").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                if let v = vm.lastVerdict { verdictChip(v) }
                Spacer(minLength: 4)
                // Learning, not scorekeeping: undo any move, as many times in a
                // row as you like -- no restriction on how it was graded.
                if vm.canUndo {
                    Button { vm.undoLastMove() } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.caption2.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(GemmaTheme.gold)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            if vm.topMoves.isEmpty {
                Text("Play a move to see how the engine judged it, and its top 3 choices here.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(vm.topMoves.enumerated()), id: \.offset) { index, line in
                        HStack(spacing: 8) {
                            Text("\(index + 1).")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(width: 16, alignment: .trailing)
                            Text(line.lineSAN.first ?? "—")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer(minLength: 8)
                            Text(line.eval)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gemmaGlass(cornerRadius: 16)
    }

    // MARK: Coach card (written explanation + chat — the ONLY piece that spends
    // Gemini credits)

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap.fill").foregroundStyle(GemmaTheme.accent).font(.footnote)
                Text("Coach").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Spacer(minLength: 4)
                if vm.isCoaching || vm.isSummarizing {
                    ProgressView().controlSize(.small)
                }
                if vm.coachEnabled {
                    Button { showChat = true } label: {
                        Label("Ask", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.caption2.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(GemmaTheme.accent)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            // The focus line scrolls within the card's bounds so a long note never
            // pushes the layout or clips.
            ScrollView { focusLine }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .gemmaGlass(cornerRadius: 18)
        .sheet(isPresented: $showChat) { PlayCoachChatView(vm: vm) }
    }

    @ViewBuilder
    private var focusLine: some View {
        // Browsing a past ply (live game or a replayed finished one) shows THAT
        // move's own note, not the latest/overall one -- this is what makes
        // "walk through the moves and see where it went wrong" actually work.
        if let ply = vm.viewingPly {
            if let note = vm.note(forPly: ply), !note.isEmpty {
                Text(note.asCoachMarkdown)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                Text("No coach note recorded for this move.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
        // At game over the debrief takes the card: what mattered, the habit, the
        // one thing to practice.
        } else if vm.gameOver, let summary = vm.gameSummary, !summary.isEmpty {
            Text(summary.asCoachMarkdown)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        } else if vm.gameOver, vm.isSummarizing {
            Text("Looking back over the game…")
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
        } else if let note = vm.lastCoachNote, !note.isEmpty {
            Text(note.asCoachMarkdown)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        } else if vm.isCoaching {
            Text("Reading the position…")
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
        } else if !vm.coachEnabled {
            Text("Engine review only on this device. I'll still grade your moves.")
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
        } else if vm.lastVerdict == nil {
            Text("Make a move — I'll comment as you play.")
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
        }
    }

    /// Compact color-coded verdict chip ("Qh5 · Blunder", plus "best Nf3" when not
    /// the top move), sized to sit inline in the coach card header.
    private func verdictChip(_ v: MoveVerdict) -> some View {
        let color = MoveVerdict.color(for: v.classification)
        return HStack(spacing: 5) {
            Text("\(v.moveSAN) · \(v.classification.capitalized)")
                .font(.caption.weight(.bold))
            if let better = v.betterMoveSAN, !v.isBest {
                Text("best \(better)")
                    .font(.caption2).foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
        .lineLimit(1).minimumScaleFactor(0.7)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.22)))
        .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
    }
}

/// A compact win-probability read-out as a black/white pie: the white wedge is
/// White's win %, the rest is Black's. Replaces the old horizontal advantage bar so
/// the eval/win read-out fits inside the status pill instead of costing a row.
struct WinPie: View {
    let winWhite: Double
    var size: CGFloat = 20

    var body: some View {
        let frac = max(0, min(1, winWhite / 100))
        return ZStack {
            Circle().fill(GemmaTheme.pieceBlack)
            PieSlice(fraction: frac).fill(GemmaTheme.pieceWhite)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
        .accessibilityLabel("White win probability \(Int(winWhite.rounded())) percent")
    }
}

/// A pie wedge starting at 12 o'clock, sweeping clockwise for `fraction` of a turn.
struct PieSlice: Shape {
    var fraction: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        p.move(to: c)
        p.addArc(center: c, radius: r,
                 startAngle: .degrees(-90),
                 endAngle: .degrees(-90 + 360 * fraction),
                 clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// A chat sheet for asking the coach free-form questions during a game. Answers
/// stream in and are grounded in engine facts for the position you're viewing.
struct PlayCoachChatView: View {
    @Bindable var vm: PlayViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if vm.chat.isEmpty {
                                Text("Ask anything about this position — \"why was that a mistake?\", \"what's my plan?\", \"is my king safe?\"")
                                    .font(.footnote).foregroundStyle(.white.opacity(0.55))
                                    .padding(.top, 8)
                            }
                            ForEach(Array(vm.chat.enumerated()), id: \.offset) { i, msg in
                                bubble(msg).id(i)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: vm.chat.count) { _, _ in
                        withAnimation { proxy.scrollTo(vm.chat.count - 1, anchor: .bottom) }
                    }
                }
                inputRow
            }
            .background(GemmaTheme.Background().ignoresSafeArea())
            .navigationTitle("Ask the coach")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailingCompat) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder private func bubble(_ msg: (role: String, text: String)) -> some View {
        let isUser = msg.role == "user"
        HStack {
            if isUser { Spacer(minLength: 32) }
            Group {
                if msg.text.isEmpty {
                    ProgressView().controlSize(.small)
                } else {
                    Text(isUser ? AttributedString(msg.text) : msg.text.asCoachMarkdown)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(isUser ? 0.95 : 0.92))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(
                (isUser ? GemmaTheme.accent.opacity(0.22) : Color.white.opacity(0.08)),
                in: RoundedRectangle(cornerRadius: 14))
            if !isUser { Spacer(minLength: 32) }
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Ask the coach…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.white.opacity(0.08), in: Capsule())
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? GemmaTheme.accent : .white.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty && !vm.isAsking
    }

    private func send() {
        guard canSend else { return }
        let q = draft
        draft = ""
        Task { await vm.ask(q) }
    }
}

// Cross-platform toolbar placements (iOS bar vs macOS).
extension ToolbarItemPlacement {
    static var topBarLeadingCompat: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarLeading
        #else
        return .cancellationAction
        #endif
    }
    static var topBarTrailingCompat: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .primaryAction
        #endif
    }
}
