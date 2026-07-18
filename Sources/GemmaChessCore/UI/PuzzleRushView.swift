//  PuzzleRushView.swift
//  Puzzle Rush UI: a countdown, a running correct count, and the board --
//  solve as many puzzles as possible before either the clock runs out or a
//  wrong move ends the run. Entirely free -- no coach, no network beyond the
//  puzzle packs already downloaded via normal Puzzles mode.

import SwiftUI
import ChessKit

public struct PuzzleRushView: View {
    @State private var session: PuzzleRushSession
    var onExit: () -> Void
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

    /// A live countdown driver -- ticks the session once a second while a run
    /// is active. Purely a UI concern; `PuzzleRushSession` itself takes an
    /// explicit time on every `tick(at:)` call, so tests never depend on this.
    @State private var timerTask: Task<Void, Never>?

    public init(
        durationSeconds: Int = PuzzleRushSession.defaultDurationSeconds,
        onExit: @escaping () -> Void
    ) {
        _session = State(initialValue: PuzzleRushSession(durationSeconds: durationSeconds))
        self.onExit = onExit
    }

    public var body: some View {
        VStack(spacing: 10) {
            header
            content
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .task { startRun() }
        .onDisappear { timerTask?.cancel() }
    }

    private func startRun() {
        let pool = PuzzleRushSession.loadPuzzlePool()
        session.start(puzzles: pool)
        timerTask?.cancel()
        guard !pool.isEmpty else { return }
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                session.tick()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onExit) {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .gemmaGlassPill()
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(theme.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Puzzle Rush").font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
                Text("\(session.correctCount) solved this run")
                    .font(.caption2).foregroundStyle(theme.textColor.opacity(0.6))
            }
            Spacer()
            if session.isActive {
                Label(timeLabel(session.remainingSeconds), systemImage: "timer")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(session.remainingSeconds <= 10 ? .red : theme.accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        if session.isEmpty {
            downloadFirstCard
        } else if session.hasEnded {
            resultCard
        } else if let puzzle = session.currentPuzzle {
            board(for: puzzle)
        }
    }

    private func board(for puzzle: Puzzle) -> some View {
        ChessBoardView(
            fen: session.fen,
            orientation: session.orientation,
            arrows: [],
            lastMove: session.lastMove,
            selectedSquare: session.selected,
            legalDots: session.legalDots,
            boardLight: theme.boardLightColor,
            boardDark: theme.boardDarkColor,
            highlightColor: theme.accent2Color,
            accentColor: theme.accentColor,
            onTapSquare: { session.tap($0) }
        )
        .padding(.horizontal, 22)
        .id(puzzle.id)
    }

    private var downloadFirstCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.circle").font(.largeTitle).foregroundStyle(theme.accent2Color)
            Text("Download a puzzle pack first.")
                .font(.headline).foregroundStyle(theme.textColor)
            Text("Puzzle Rush pulls from packs you've already downloaded in Puzzles mode — grab at least one, then come back.")
                .font(.subheadline).foregroundStyle(theme.textColor.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Back to Puzzles", action: onExit)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var resultCard: some View {
        VStack(spacing: 10) {
            Image(systemName: resultIcon).font(.largeTitle).foregroundStyle(theme.accent2Color)
            Text(resultTitle).font(.headline).foregroundStyle(theme.textColor)
            Text("\(session.correctCount) solved this run.")
                .font(.subheadline).foregroundStyle(theme.textColor.opacity(0.7))
            HStack(spacing: 10) {
                Button("Back to Puzzles", action: onExit)
                    .buttonStyle(.bordered)
                Button("Play again") { startRun() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var resultIcon: String {
        switch session.endReasonForDisplay {
        case .wrongAnswer: return "xmark.circle.fill"
        case .timeExpired: return "timer"
        case .queueExhausted, nil: return "party.popper.fill"
        }
    }

    private var resultTitle: String {
        switch session.endReasonForDisplay {
        case .wrongAnswer: return "Not quite — run over."
        case .timeExpired: return "Time's up!"
        case .queueExhausted, nil: return "Every puzzle solved!"
        }
    }

    private func timeLabel(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private extension PuzzleRushSession {
    /// A small display-only convenience so the view doesn't have to unwrap.
    var endReasonForDisplay: PuzzleRushEndReason? { endReason }
}
