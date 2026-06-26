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
            board
            if settings.showCaptured { capturedRow }
            if vm.hint != nil { hintCard }
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
                Toggle(isOn: $settings.showCoach) { Label("Coach", systemImage: "bubble.left.fill") }
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

    // MARK: Coach card (verdict + focus line)

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap.fill").foregroundStyle(GemmaTheme.accent).font(.footnote)
                Text("Coach").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                if let v = vm.lastVerdict { verdictChip(v) }
                Spacer(minLength: 4)
                if vm.isCoaching {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small)
                        Text("Analyzing…")
                            .font(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
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
    }

    @ViewBuilder
    private var focusLine: some View {
        if let note = vm.lastCoachNote, !note.isEmpty {
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
