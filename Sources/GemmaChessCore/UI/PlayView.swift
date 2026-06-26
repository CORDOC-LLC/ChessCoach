//  PlayView.swift
//  Play mode UI: a pre-game setup (pick side + engine strength), then the live
//  board with tap-to-move, a status line, and a running coach panel that comments
//  on each of your moves.

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

/// The live game: board + status + coach feed.
public struct PlayView: View {
    @Bindable var vm: PlayViewModel
    var onNewGame: () -> Void

    public init(vm: PlayViewModel, onNewGame: @escaping () -> Void) {
        self.vm = vm; self.onNewGame = onNewGame
    }

    public var body: some View {
        VStack(spacing: 10) {
            statusBar
            ChessBoardView(
                fen: vm.fen,
                orientation: vm.orientation,
                lastMove: vm.lastMove,
                selectedSquare: vm.selected,
                legalDots: vm.legalDots,
                onTapSquare: { vm.tap($0) }
            )
            .padding(.horizontal, 8)
            controls
            coachPanel
        }
        .navigationTitle("Play")
        .toolbar {
            ToolbarItem(placement: .topBarTrailingCompat) {
                Button("New game", action: onNewGame)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if vm.engineThinking || vm.isCoaching { ProgressView().controlSize(.small) }
            Text(vm.status)
                .font(.headline)
                .foregroundStyle(vm.gameOver ? Color.accentColor : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var controls: some View {
        HStack {
            Text("You: \(vm.playerIsWhite ? "White" : "Black")")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            if !vm.gameOver {
                Button("Resign", role: .destructive) { vm.resign() }
                    .buttonStyle(.bordered)
            } else {
                Button("New game", action: onNewGame)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal)
    }

    private var coachPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(.secondary)
                Text("Coach").font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal).padding(.vertical, 6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if vm.coachNotes.isEmpty {
                            Text(vm.coachEnabled
                                 ? "Make a move — I'll comment as you play."
                                 : "Engine review only on this device. I'll still grade your moves.")
                                .font(.footnote).foregroundStyle(.secondary)
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
        .frame(maxHeight: 200)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func noteRow(_ note: (role: String, text: String)) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: note.role == "engine" ? "cpu" : "graduationcap.fill")
                .font(.caption)
                .foregroundStyle(note.role == "engine" ? .orange : .blue)
                .frame(width: 18)
            Text(note.text)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
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
