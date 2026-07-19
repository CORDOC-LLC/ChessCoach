//  LessonsView.swift
//  Lessons UI: a stage-grouped list (with per-lesson completion status), a
//  short explanation screen, then the practice session itself -- reusing
//  `LessonViewModel`'s puzzle-solving state machine. Entirely free -- no
//  coach, no network beyond the puzzle pack download `LessonViewModel`
//  already handles (same as normal Puzzles mode).

import SwiftUI

/// Shows the stage/lesson list until a lesson is selected, then its
/// explanation + practice flow.
public struct LessonsContainerView: View {
    var onExit: () -> Void
    @State private var selectedLesson: Lesson?
    @Environment(ThemeStore.self) private var themeStore

    public init(onExit: @escaping () -> Void) {
        self.onExit = onExit
    }

    public var body: some View {
        if let lesson = selectedLesson {
            LessonExplanationView(lesson: lesson, onBack: { selectedLesson = nil })
        } else {
            stageList
        }
    }

    private var stageList: some View {
        List {
            Section {
                Text("Free — pairs a short explanation of a chess concept with a curated set of "
                    + "practice puzzles.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(LessonCatalog.stages) { stage in
                Section(stage.title) {
                    ForEach(stage.lessons) { lesson in
                        lessonRow(lesson)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Lessons")
        .toolbar {
            ToolbarItem(placement: .topBarLeadingCompat) { Button("Home", action: onExit) }
        }
    }

    private func lessonRow(_ lesson: Lesson) -> some View {
        Button {
            selectedLesson = lesson
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lesson.title).font(.subheadline.weight(.semibold))
                    Text("\(lesson.puzzleCount) puzzles")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                progressBadge(for: lesson)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func progressBadge(for lesson: Lesson) -> some View {
        switch LessonProgressStore.progress(for: lesson.id) {
        case .completed:
            Image(systemName: "checkmark.seal.fill").foregroundStyle(themeStore.effective.accentColor)
        case .inProgress(let solvedCount):
            Text("\(solvedCount)/\(lesson.puzzleCount)")
                .font(.caption2).foregroundStyle(themeStore.effective.accent2Color)
        case .notStarted:
            EmptyView()
        }
    }
}

/// A lesson's original explanation, with a "Start practice" action that
/// hands off to `LessonPracticeView`.
private struct LessonExplanationView: View {
    let lesson: Lesson
    var onBack: () -> Void
    @State private var vm: LessonViewModel?
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

    var body: some View {
        if let vm {
            LessonPracticeView(vm: vm, onExit: onBack)
        } else {
            explanation
        }
    }

    private var explanation: some View {
        VStack(spacing: 16) {
            header
            ScrollView {
                Text(lesson.bodyText)
                    .font(.body)
                    .foregroundStyle(theme.textColor)
                    .lineSpacing(3)
                    .padding(20)
            }
            Button {
                let newVM = LessonViewModel(lesson: lesson)
                vm = newVM
                Task { await newVM.start() }
            } label: {
                Label("Start practice", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .gemmaGlassPill()
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(theme.accentColor)
            Text(lesson.title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }
}

/// The practice session for a single lesson, over `LessonViewModel`.
private struct LessonPracticeView: View {
    @Bindable var vm: LessonViewModel
    var onExit: () -> Void
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

    var body: some View {
        VStack(spacing: 10) {
            header
            content
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
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
                Text(vm.lesson.title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
                if !vm.puzzles.isEmpty {
                    Text("\(min(vm.puzzleIndex + 1, vm.totalCount)) of \(vm.totalCount)")
                        .font(.caption2).foregroundStyle(theme.textColor.opacity(0.6))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoadingPack {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
        } else if let error = vm.loadError {
            errorCard(error)
        } else if vm.isSessionComplete {
            completeCard
        } else if let puzzle = vm.currentPuzzle {
            board(for: puzzle)
            statusCard
        }
    }

    private func board(for puzzle: Puzzle) -> some View {
        ChessBoardView(
            fen: vm.fen,
            orientation: vm.orientation,
            arrows: [],
            lastMove: vm.lastMove,
            selectedSquare: vm.selected,
            legalDots: vm.legalDots,
            boardLight: theme.boardLightColor,
            boardDark: theme.boardDarkColor,
            highlightColor: theme.accent2Color,
            accentColor: theme.accentColor,
            onTapSquare: { vm.tap($0) }
        )
        .padding(.horizontal, 22)
        .id(puzzle.id)
    }

    @ViewBuilder
    private var statusCard: some View {
        HStack(spacing: 8) {
            if let feedback = vm.feedback {
                Image(systemName: icon(for: feedback)).foregroundStyle(color(for: feedback))
            }
            Text(vm.status).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
            Spacer()
            if vm.feedback == .solved {
                Button("Next") { vm.nextPuzzle() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .gemmaGlassPill()
        .padding(.horizontal, 12)
    }

    private func icon(for feedback: PuzzleFeedback) -> String {
        switch feedback {
        case .correct: return "checkmark.circle.fill"
        case .incorrect: return "xmark.circle.fill"
        case .solved: return "star.fill"
        }
    }
    private func color(for feedback: PuzzleFeedback) -> Color {
        switch feedback {
        case .correct: return theme.accentColor
        case .incorrect: return .red
        case .solved: return theme.accent2Color
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.slash").font(.largeTitle).foregroundStyle(theme.accent2Color)
            Text(message)
                .font(.subheadline).foregroundStyle(theme.textColor.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await vm.start() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var completeCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "party.popper.fill").font(.largeTitle).foregroundStyle(theme.accent2Color)
            Text("Lesson complete!").font(.headline).foregroundStyle(theme.textColor)
            Text("\(vm.solvedCount) of \(vm.totalCount) solved.")
                .font(.subheadline).foregroundStyle(theme.textColor.opacity(0.7))
            Button("Back to lessons", action: onExit)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}
