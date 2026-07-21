//  PlayView.swift
//  Play mode UI: a compact pre-game setup (side + engine strength), then a
//  space-efficient live board — eval bar, advantage read-out, tap-to-move board,
//  and a running coach panel that grades each of your moves.

import SwiftUI
import ChessKit

/// Shows the new-game setup until a game is started, then the live game.
public struct PlayContainerView: View {
    @Bindable var vm: PlayViewModel
    var onExit: () -> Void
    @State private var started: Bool
    @State private var sideIsWhite = true
    @State private var settings = PlayDisplaySettings()

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
                    .onChange(of: vm.skill) { _, new in settings.defaultEngineSkill = new }
                Toggle("Human-like opponent", isOn: Binding(
                    get: { settings.humanLikeEnabled },
                    set: { settings.humanLikeEnabled = $0 }
                ))
                Text("Varies its opening moves instead of always playing the same one.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Coach: \(coachLabel)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button {
                    vm.humanLikeEnabled = settings.humanLikeEnabled
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
        .toolbar {
            ToolbarItem(placement: .topBarLeadingCompat) { Button("Home", action: onExit) }
            ToolbarItem(placement: .topBarTrailingCompat) {
                NavigationLink(destination: SettingsView()) { Image(systemName: "gearshape") }
            }
        }
        .onAppear {
            vm.skill = settings.defaultEngineSkill
            vm.humanLikeEnabled = settings.humanLikeEnabled
        }
    }

    private var coachLabel: String {
        switch vm.coachAvailability {
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
    @State private var showGameOverBanner = false
    @State private var showAppearance = false
    @State private var showPaywall = false
    @State private var showHintTip = !HintTipStore.hasSeenTip()
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

    public init(vm: PlayViewModel, onNewGame: @escaping () -> Void) {
        self.vm = vm; self.onNewGame = onNewGame
    }

    public var body: some View {
        VStack(spacing: 8) {
            header
            if showHintTip { hintTipBubble }
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
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.bottom, 8)
        .onChange(of: settings.showCoach, initial: true) { _, showCoach in
            vm.coachDisplayEnabled = showCoach
        }
        .overlay {
            // Only on a LIVE transition into game-over (see the onChange below) --
            // reopening an already-finished game (My Games) shouldn't replay this.
            if showGameOverBanner, let outcome = vm.outcome {
                GameOverBanner(
                    resultText: vm.resultText ?? "Game over", outcome: outcome, stats: vm.stats,
                    openingName: vm.opening?.name
                ) {
                    withAnimation(.easeOut(duration: 0.25)) { showGameOverBanner = false }
                }
                .transition(AnyTransition.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .onChange(of: vm.gameOver) { _, isOver in
            if isOver {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    showGameOverBanner = true
                }
            } else {
                showGameOverBanner = false   // e.g. Undo un-ended the game
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $showAppearance) { AppearanceView() }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $vm.showReviewPrompt) { ReviewPromptView() }
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
            checkSquare: checkInfo?.king,
            boardLight: theme.boardLightColor,
            boardDark: theme.boardDarkColor,
            highlightColor: theme.accent2Color,
            accentColor: theme.accentColor,
            onTapSquare: { vm.tap($0) }
        )
        .padding(.leading, 22)
        .overlay(alignment: .leading) {
            EvalBarView(winWhite: vm.winWhite, whiteAtBottom: vm.playerIsWhite, ringColor: theme.accent2Color)
                .frame(width: 14)
        }
        .padding(.horizontal, 12)
    }

    // MARK: Board arrows
    //
    // Best-move recommendation graphics are shown ONLY while a hint is active (the
    // lightbulb). There is no separate always-on best-move arrow — turning the hint
    // off removes every recommendation arrow from the board.

    /// Whenever the shown position is in check (including checkmate), the checked
    /// king's square and the piece(s) directly attacking it -- this is what
    /// actually shows WHY it's check/mate, not just that it is.
    private var checkInfo: (king: Square, attackers: [Square])? {
        ChessLogic.checkAttackers(forFEN: vm.displayFEN)
    }

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
            if let a = BoardArrow(uci: hint.bestUCI, color: theme.accentColor, thick: true) {
                arrows.append(a)
            }
            if let second = hint.secondUCI,
               let a = BoardArrow(uci: second, color: theme.accent2Color.opacity(0.9), thick: false) {
                arrows.append(a)
            }
        }
        // Check/checkmate: an arrow from every attacking piece straight to the king.
        if let checkInfo {
            for attacker in checkInfo.attackers {
                arrows.append(BoardArrow(from: attacker, to: checkInfo.king, color: .red, thick: true))
            }
        }
        return arrows
    }

    // MARK: Header
    //
    // One cohesive glass bar rather than several separately-floating pills:
    // back, status text + win-probability pie + eval, a spacer, then the hint,
    // Undo, and "⋯" (Appearance/Resign/show-hide) icon buttons -- all sitting
    // on one continuous glass background instead of each carrying its own.
    // Appearance lives inside the "⋯" menu rather than its own icon, so the
    // bar only surfaces the two things you reach for mid-game (hint, undo).

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: onNewGame) {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(theme.accentColor)

            statusReadout
            Spacer(minLength: 4)
            hintButton
            undoButton
            menuButton
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .gemmaGlass(cornerRadius: 20)
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    /// A one-time callout explaining what the lightbulb does, since an
    /// icon-only toggle in a glass header isn't self-explanatory on first
    /// use. Dismisses (and never shows again) on tap, or the first time the
    /// hint button itself is used.
    private var hintTipBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill").foregroundStyle(theme.accent2Color).font(.caption)
            Text("Tap the bulb for the engine's best move here.")
                .font(.caption).foregroundStyle(theme.textColor.opacity(0.85))
            Spacer(minLength: 4)
            Button { dismissHintTip() } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold)).foregroundStyle(theme.textColor.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .gemmaGlass(cornerRadius: 12)
        .padding(.horizontal, 14)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func dismissHintTip() {
        HintTipStore.markSeen()
        withAnimation { showHintTip = false }
    }

    /// Status text + a compact black/white win-probability pie + the eval number.
    private var statusReadout: some View {
        HStack(spacing: 8) {
            if vm.engineThinking || vm.isCoaching { ProgressView().controlSize(.small) }
            Text(vm.status)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(vm.gameOver ? theme.accentColor : theme.textColor)
                .lineLimit(1).minimumScaleFactor(0.7)
            WinPie(winWhite: vm.winWhite)
            Text(vm.evalText)
                .font(.subheadline.weight(.bold)).monospacedDigit()
                .foregroundStyle(theme.textColor)
        }
    }

    /// Learning, not scorekeeping: undo any move, as many times in a row as
    /// you like, regardless of how it was graded. Lives in the header (not
    /// the Move Review card below) since it's a mid-game action you reach
    /// for constantly, not something tied to reading engine feedback.
    private var undoButton: some View {
        Button { vm.undoLastMove() } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(vm.canUndo ? theme.textColor.opacity(0.8) : theme.textColor.opacity(0.25))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(PressableStyle())
        .disabled(!vm.canUndo)
        .accessibilityLabel("Undo last move")
    }

    private var menuButton: some View {
        @Bindable var settings = settings
        return Menu {
            Section("Show") {
                Toggle(isOn: $settings.showCaptured) { Label("Captured pieces", systemImage: "trophy") }
                Toggle(isOn: $settings.showMoveList) { Label("Move list", systemImage: "list.bullet") }
                Toggle(isOn: $settings.showMoveComments) { Label("Move review", systemImage: "chart.bar.fill") }
                Toggle(isOn: $settings.showOpening) { Label("Opening name", systemImage: "book.closed.fill") }
                Toggle(isOn: $settings.showCoach) { Label("Coach (uses credits)", systemImage: "bubble.left.fill") }
            }
            Section {
                Button { showAppearance = true } label: { Label("Appearance & themes", systemImage: "paintpalette.fill") }
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
                .foregroundStyle(theme.textColor.opacity(0.8))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("More options")
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
        return Button {
            if showHintTip { dismissHintTip() }
            on ? vm.clearHint() : vm.requestHint()
        } label: {
            Image(systemName: on ? "lightbulb.fill" : "lightbulb")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(on ? theme.accent2Color : theme.textColor.opacity(0.7))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(PressableStyle())
        .disabled(!vm.userToMove || vm.isViewingHistory || vm.gameOver)
        .accessibilityLabel(on ? "Hide best move hint" : "Show best move hint")
        .accessibilityHint("Shows the engine's best move for the current position.")
    }

    // MARK: Hint card (best + alternative + rationale, dismissible)

    @ViewBuilder
    private var hintCard: some View {
        if let hint = vm.hint {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(theme.accent2Color).font(.footnote)
                    Text(hint.summaryLabel)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if hint.isLoading { ProgressView().controlSize(.small) }
                    Button { vm.clearHint() } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold)).foregroundStyle(theme.textColor.opacity(0.6))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }
                if let freeRationale = hint.freeRationale, !freeRationale.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Text("FREE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.accent2Color)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(theme.accent2Color.opacity(0.18)))
                            .overlay(Capsule().stroke(theme.accent2Color.opacity(0.5), lineWidth: 1))
                        Text(freeRationale)
                            .font(.footnote).foregroundStyle(theme.textColor.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let rationale = hint.rationale, !rationale.isEmpty {
                    Text(rationale.asCoachMarkdown)
                        .font(.footnote).foregroundStyle(theme.textColor.opacity(0.9))
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
                .font(.caption2).foregroundStyle(theme.accent2Color)
            Text("\(opening.name) · \(opening.eco)")
                .font(.caption).foregroundStyle(theme.textColor.opacity(0.7))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    // MARK: Move Review card (verdict on the move you just played + the top-3
    // continuations the engine considered there -- all engine-only, free, no
    // Gemini/network involved). Distinct from the hint (lightbulb): this is
    // always-on feedback about a move already played; the hint is an
    // on-demand suggestion for the move about to be played.

    private var bestMovesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill").foregroundStyle(theme.accent2Color).font(.footnote)
                Text("Move Review").font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
                if let v = vm.lastVerdict { verdictChip(v) }
                Spacer(minLength: 4)
            }
            if vm.topMoves.isEmpty {
                Text("Play a move and I'll grade it here, with the engine's top 3 choices.")
                    .font(.footnote).foregroundStyle(theme.textColor.opacity(0.6))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(vm.topMoves.enumerated()), id: \.offset) { index, line in
                        HStack(spacing: 8) {
                            Text("\(index + 1).")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(theme.textColor.opacity(0.4))
                                .frame(width: 16, alignment: .trailing)
                            Text(line.lineSAN.first ?? "—")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(theme.textColor)
                            Spacer(minLength: 8)
                            Text(line.eval)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(theme.textColor.opacity(0.6))
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
                Image(systemName: "graduationcap.fill").foregroundStyle(theme.accentColor).font(.footnote)
                Text("Coach").font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
                Spacer(minLength: 4)
                if vm.isCoaching || vm.isSummarizing {
                    ProgressView().controlSize(.small)
                }
                if vm.coachEnabled {
                    Button { openChat() } label: {
                        Label("Ask", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.caption2.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(theme.accentColor)
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
                    .foregroundStyle(theme.textColor.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                Text("No coach note recorded for this move.")
                    .font(.footnote).foregroundStyle(theme.textColor.opacity(0.6))
            }
        // At game over the debrief takes the card: what mattered, the habit, the
        // one thing to practice.
        } else if vm.gameOver, let summary = vm.gameSummary, !summary.isEmpty {
            Text(summary.asCoachMarkdown)
                .font(.callout)
                .foregroundStyle(theme.textColor.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        } else if vm.gameOver, vm.isSummarizing {
            Text("Looking back over the game…")
                .font(.footnote).foregroundStyle(theme.textColor.opacity(0.6))
        } else if let note = vm.lastCoachNote, !note.isEmpty {
            Text(note.asCoachMarkdown)
                .font(.callout)
                .foregroundStyle(theme.textColor.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        } else if vm.isCoaching {
            Text("Reading the position…")
                .font(.footnote).foregroundStyle(theme.textColor.opacity(0.6))
        } else if !vm.coachEnabled {
            Text("Engine review only on this device. I'll still grade your moves.")
                .font(.footnote).foregroundStyle(theme.textColor.opacity(0.6))
        } else if let error = vm.lastCoachError {
            // A configuration/entitlement/network failure -- shown specifically
            // (rather than a silent blank card) so it's obvious what to fix,
            // e.g. during TestFlight testing.
            VStack(alignment: .leading, spacing: 3) {
                Label("Coach unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(theme.textColor.opacity(0.65))
                if BuildChannel.current.requiresProEntitlement {
                    Button("Subscribe to ChessCoach Pro") { showPaywall = true }
                        .font(.caption.weight(.semibold))
                }
            }
        } else if vm.lastVerdict == nil {
            Text("Make a move — I'll comment as you play.")
                .font(.footnote).foregroundStyle(theme.textColor.opacity(0.6))
        }
    }

    /// Compact color-coded verdict chip ("Qh5 · Blunder", plus "best Nf3" when not
    /// the top move), sized to sit inline in the coach card header.
    private func verdictChip(_ v: MoveVerdict) -> some View {
        let color = MoveVerdict.color(for: v.classification, theme: theme)
        return HStack(spacing: 5) {
            Text("\(v.moveSAN) · \(v.classification.capitalized)")
                .font(.caption.weight(.bold))
            if let better = v.betterMoveSAN, !v.isBest {
                Text("best \(better)")
                    .font(.caption2).foregroundStyle(theme.textColor.opacity(0.75))
            }
        }
        .foregroundStyle(theme.textColor)
        .lineLimit(1).minimumScaleFactor(0.7)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.22)))
        .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
    }

    /// Opens coach chat, unless this channel requires an active
    /// entitlement and the user doesn't have one -- shows the paywall
    /// instead (see `BuildChannel.requiresProEntitlement`).
    private func openChat() {
        if BuildChannel.current.requiresProEntitlement, !ProEntitlementStore.shared.isProActive {
            showPaywall = true
        } else {
            showChat = true
        }
    }
}

/// A brief animated card announcing how the game ended -- makes the moment
/// impossible to miss, instead of only a small status-pill text change.
/// Tap anywhere to dismiss (the board underneath still shows the final
/// position, with the check/checkmate arrows if it ended that way).
struct GameOverBanner: View {
    let resultText: String
    let outcome: PlayOutcome
    let stats: PlayStats
    var openingName: String?
    var onDismiss: () -> Void

    @Environment(ThemeStore.self) private var themeStore
    @State private var appeared = false
    #if os(iOS)
    @State private var shareImage: ShareImageBox?
    #endif
    private var theme: Theme { themeStore.effective }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(tint)
                .scaleEffect(appeared ? 1 : 0.4)
                .opacity(appeared ? 1 : 0)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(theme.textColor)
            Text(resultText)
                .font(.subheadline)
                .foregroundStyle(theme.textColor.opacity(0.75))
                .multilineTextAlignment(.center)
            Text("\(stats.wins)W · \(stats.losses)L · \(stats.draws)D")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(theme.textColor.opacity(0.55))
                .padding(.top, 4)
            #if os(iOS)
            Button {
                shareGame()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(theme.accentColor)
            .padding(.top, 6)
            #endif
            Text("Tap to dismiss")
                .font(.caption2)
                .foregroundStyle(theme.textColor.opacity(0.4))
                .padding(.top, 2)
        }
        .padding(28)
        .frame(maxWidth: 300)
        .gemmaGlass(cornerRadius: 24)
        .shadow(color: tint.opacity(0.35), radius: 24)
        .onTapGesture(perform: onDismiss)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.05)) {
                appeared = true
            }
        }
        #if os(iOS)
        .sheet(item: $shareImage) { box in
            ActivityShareSheet(items: [box.image])
        }
        #endif
    }

    #if os(iOS)
    /// Renders the share card off the live banner and presents the system
    /// share sheet. If rendering fails for any reason, this is a safe
    /// no-op -- never presents a broken/empty share sheet.
    private func shareGame() {
        let card = GameResultShareCard(resultText: resultText, outcome: outcome, openingName: openingName)
            .environment(themeStore)
        guard let image = ShareCardRenderer.render(card, size: GameResultShareCard.cardSize) else {
            return
        }
        shareImage = ShareImageBox(image: image)
    }
    #endif

    private var icon: String {
        switch outcome {
        case .win: return "crown.fill"
        case .loss: return "flag.fill"
        case .draw: return "equal.circle.fill"
        }
    }
    private var title: String {
        switch outcome {
        case .win: return "You won!"
        case .loss: return "Game over"
        case .draw: return "Draw"
        }
    }
    private var tint: Color {
        switch outcome {
        case .win: return themeStore.effective.accent2Color
        case .loss: return .red
        case .draw: return theme.textColor.opacity(0.8)
        }
    }
}

#if os(iOS)
/// `.sheet(item:)` needs `Identifiable`; `UIImage` isn't, so this wraps one
/// rendered share-card image per presentation.
private struct ShareImageBox: Identifiable {
    let id = UUID()
    let image: UIImage
}
#endif

/// A compact win-probability read-out as a black/white pie: the white wedge is
/// White's win %, the rest is Black's. Replaces the old horizontal advantage bar so
/// the eval/win read-out fits inside the status pill instead of costing a row.
struct WinPie: View {
    let winWhite: Double
    var size: CGFloat = 20

    var body: some View {
        let frac = max(0, min(1, winWhite / 100))
        return ZStack {
            // Fixed piece fills, matching the board's pieces (never theme-tied).
            Circle().fill(Color(hex: "#181310"))
            PieSlice(fraction: frac).fill(Color(hex: "#f4eee0"))
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
    @Environment(ThemeStore.self) private var themeStore
    @State private var draft = ""
    private var theme: Theme { themeStore.effective }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if vm.chat.isEmpty {
                                Text("Ask anything about this position — \"why was that a mistake?\", \"what's my plan?\", \"is my king safe?\"")
                                    .font(.footnote).foregroundStyle(theme.textColor.opacity(0.55))
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
            .background(
                ZStack { theme.bgColor; theme.backgroundGradient }.ignoresSafeArea()
            )
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
                        .foregroundStyle(theme.textColor.opacity(isUser ? 0.95 : 0.92))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(
                (isUser ? theme.accentColor.opacity(0.22) : theme.textColor.opacity(0.08)),
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
                .background(theme.textColor.opacity(0.08), in: Capsule())
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? theme.accentColor : theme.textColor.opacity(0.3))
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
