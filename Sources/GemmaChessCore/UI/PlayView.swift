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

    public init(vm: PlayViewModel, onNewGame: @escaping () -> Void) {
        self.vm = vm; self.onNewGame = onNewGame
    }

    public var body: some View {
        VStack(spacing: 10) {
            header
            // Eval bar is a leading overlay so its height tracks the board exactly
            // (an HStack sibling stretched greedily and left a big gap).
            ChessBoardView(
                fen: vm.fen,
                orientation: vm.orientation,
                lastMove: vm.lastMove,
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
            infoStrip
            coachPanel
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onNewGame) {
                Label("New game", systemImage: "chevron.left")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(GemmaTheme.accent)
            Spacer()
            HStack(spacing: 7) {
                if vm.engineThinking || vm.isCoaching { ProgressView().controlSize(.small) }
                Text(vm.status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(vm.gameOver ? GemmaTheme.accent : .white)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .gemmaGlassPill()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

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

    private var coachPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(GemmaTheme.accent)
                Text("Coach").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal).padding(.vertical, 6)
            Divider().overlay(Color.white.opacity(0.1))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if vm.coachNotes.isEmpty {
                            Text(vm.coachEnabled
                                 ? "Make a move — I'll comment as you play."
                                 : "Engine review only on this device. I'll still grade your moves.")
                                .font(.footnote).foregroundStyle(.white.opacity(0.6))
                                .padding(.horizontal)
                        }
                        ForEach(Array(vm.coachNotes.enumerated()), id: \.offset) { _, note in
                            noteRow(note)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: vm.coachNotes.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gemmaGlass(cornerRadius: 18)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func noteRow(_ note: (role: String, text: String)) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: note.role == "engine" ? "cpu" : "graduationcap.fill")
                .font(.caption)
                .foregroundStyle(note.role == "engine" ? GemmaTheme.gold : GemmaTheme.accent)
                .frame(width: 18)
            Text(note.text.asCoachMarkdown)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
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
