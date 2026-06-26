//  PlayView.swift
//  Play mode UI: a compact pre-game setup (side + engine strength), then a
//  space-efficient live board — eval bar, advantage read-out, tap-to-move board,
//  and a running coach panel that grades each of your moves.

import SwiftUI

/// Shows the new-game setup until a game is started, then the live game.
public struct PlayContainerView: View {
    @Bindable var vm: PlayViewModel
    var onExit: () -> Void
    @State private var started = false
    @State private var sideIsWhite = true

    public init(vm: PlayViewModel, onExit: @escaping () -> Void) {
        self.vm = vm; self.onExit = onExit
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
        case .foundationModels: return "Apple Intelligence (on-device)"
        case .gemma: return "Gemma (on-device)"
        case .unavailable(let reason): return "engine only — \(reason)"
        }
    }
}

/// The live game.
public struct PlayView: View {
    @Bindable var vm: PlayViewModel
    var onNewGame: () -> Void
    @State private var settings = PlayDisplaySettings()

    public init(vm: PlayViewModel, onNewGame: @escaping () -> Void) {
        self.vm = vm; self.onNewGame = onNewGame
    }

    public var body: some View {
        VStack(spacing: 8) {
            header
            if settings.showCaptured { capturedTray(forOpponent: true) }
            board
            if settings.showCaptured { capturedTray(forOpponent: false) }
            infoStrip
            if settings.showMoveList {
                MoveListView(vm: vm)
                    .frame(maxHeight: 132)
                    .padding(.horizontal, 12)
            }
            if settings.showCoach {
                coachCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.bottom, 8)
        .task(id: bestMoveTargetFEN) {
            if let f = bestMoveTargetFEN { vm.requestBestMove(forFEN: f) }
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

    // MARK: Best-move arrows

    /// The FEN whose best move we need analysed right now, or nil if the hint is off.
    private var bestMoveTargetFEN: String? {
        guard settings.showBestMove else { return nil }
        if vm.isViewingHistory { return vm.displayFEN }
        if vm.userToMove, !vm.gameOver { return vm.fen }
        return nil
    }

    private var boardArrows: [BoardArrow] {
        var arrows: [BoardArrow] = []
        if let viewing = vm.viewingPly {
            let playedUCI = vm.moves.indices.contains(viewing) ? vm.moves[viewing] : nil
            if let uci = playedUCI, let a = BoardArrow(uci: uci, color: .gray, thick: false) {
                arrows.append(a)
            }
            if settings.showBestMove, let best = vm.bestMove(forFEN: vm.displayFEN),
               best != playedUCI, let a = BoardArrow(uci: best, color: GemmaTheme.accent, thick: true) {
                arrows.append(a)
            }
        } else if settings.showBestMove, vm.userToMove, !vm.gameOver,
                  let best = vm.bestMove(forFEN: vm.fen),
                  let a = BoardArrow(uci: best, color: GemmaTheme.accent, thick: true) {
            arrows.append(a)
        }
        return arrows
    }

    // MARK: Header + toggle bar

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onNewGame) {
                Label("New game", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(GemmaTheme.accent)
            HStack(spacing: 6) {
                if vm.engineThinking || vm.isCoaching { ProgressView().controlSize(.small) }
                Text(vm.status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(vm.gameOver ? GemmaTheme.accent : .white)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .gemmaGlassPill()
            Spacer()
            toggleBar
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var toggleBar: some View {
        HStack(spacing: 6) {
            toggleButton("scope", on: settings.showBestMove) { settings.showBestMove.toggle() }
            toggleButton("trophy", on: settings.showCaptured) { settings.showCaptured.toggle() }
            toggleButton("list.bullet", on: settings.showMoveList) { settings.showMoveList.toggle() }
            toggleButton("bubble.left.fill", on: settings.showCoach) { settings.showCoach.toggle() }
        }
    }

    private func toggleButton(_ icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(on ? GemmaTheme.accent : .white.opacity(0.5))
                .frame(width: 30, height: 30)
                .gemmaGlassPill()
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Captured trays

    @ViewBuilder
    private func capturedTray(forOpponent: Bool) -> some View {
        let cap = vm.capturedMaterial
        let playerCaptures = vm.playerIsWhite ? cap.capturedByWhite : cap.capturedByBlack
        let opponentCaptures = vm.playerIsWhite ? cap.capturedByBlack : cap.capturedByWhite
        let playerAdvantage = vm.playerIsWhite ? cap.delta : -cap.delta
        if forOpponent {
            CapturedTrayView(pieces: opponentCaptures, advantage: -playerAdvantage)
                .padding(.horizontal, 14)
        } else {
            CapturedTrayView(pieces: playerCaptures, advantage: playerAdvantage)
                .padding(.horizontal, 14)
        }
    }

    // MARK: Info strip

    private var infoStrip: some View {
        HStack(spacing: 12) {
            AdvantageChip(winWhite: vm.winWhite, eval: vm.evalText)
            Spacer()
            Text("You: \(vm.playerIsWhite ? "White" : "Black")")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
            if vm.gameOver {
                Button("New game", action: onNewGame)
                    .buttonStyle(.borderedProminent).controlSize(.small)
            } else {
                Button("Resign", role: .destructive) { vm.resign() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: Coach card (verdict + focus line)

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "graduationcap.fill").foregroundStyle(GemmaTheme.accent)
                Text("Coach").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                if vm.isCoaching { ProgressView().controlSize(.small) }
            }
            if let v = vm.lastVerdict {
                verdictLine(v)
            }
            focusLine
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gemmaGlass(cornerRadius: 18)
    }

    @ViewBuilder
    private var focusLine: some View {
        if let note = vm.lastCoachNote, !note.isEmpty {
            Text(note.asCoachMarkdown)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !vm.coachEnabled {
            Text("Engine review only on this device. I'll still grade your moves.")
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
        } else if vm.lastVerdict == nil {
            Text("Make a move — I'll comment as you play.")
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
        }
    }

    private func verdictLine(_ v: MoveVerdict) -> some View {
        HStack(spacing: 8) {
            Text("\(v.moveSAN) · \(v.classification.capitalized)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    Capsule().fill(MoveVerdict.color(for: v.classification).opacity(0.22))
                )
                .overlay(Capsule().stroke(MoveVerdict.color(for: v.classification).opacity(0.6), lineWidth: 1))
            if let better = v.betterMoveSAN, !v.isBest {
                Text("best was \(better)")
                    .font(.footnote).foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
        }
    }
}

/// A compact advantage read-out: a mini win-bar + eval number + who's ahead.
struct AdvantageChip: View {
    let winWhite: Double
    let eval: String

    var body: some View {
        let whiteAhead = winWhite >= 50
        let pct = whiteAhead ? Int(winWhite.rounded()) : Int((100 - winWhite).rounded())
        HStack(spacing: 9) {
            miniBar
            Text(eval)
                .font(.subheadline.weight(.bold)).monospacedDigit()
                .foregroundStyle(.white)
            Text("\(whiteAhead ? "White" : "Black") \(pct)%")
                .font(.caption).foregroundStyle(.white.opacity(0.75))
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12).padding(.vertical, 7)
        .gemmaGlassPill()
    }

    private var miniBar: some View {
        GeometryReader { g in
            let wf = max(0, min(1, winWhite / 100))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.55))
                Capsule().fill(Color.white).frame(width: g.size.width * wf)
            }
        }
        .frame(width: 54, height: 8)
        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
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
