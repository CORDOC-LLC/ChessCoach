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
    /// Themes unlocked via an in-place "Download" tap this session -- not
    /// bundled and not yet cached on disk when the list first rendered, but
    /// `PuzzleDownloadStore.downloadPack` succeeded, so the row should flip
    /// to unlocked without waiting for a re-launch to re-check the cache.
    @State private var sessionUnlockedThemes: Set<String> = []
    @State private var downloadingThemes: Set<String> = []
    @State private var downloadErrors: [String: String] = [:]
    /// Explicit expand/collapse choices the user has made, keyed by stage --
    /// overrides the default-expanded state (see `isExpandedBinding`), same
    /// shape as `OpeningTrainerContainerView.manualExpansion`.
    @State private var manualExpansion: [String: Bool] = [:]
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

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
        ScrollView {
            VStack(spacing: 12) {
                Text("Free — pairs a short explanation of a chess concept with a curated set of "
                    + "practice puzzles.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(LessonCatalog.stages) { stage in
                    stageGroup(stage)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("Lessons")
        .toolbar {
            ToolbarItem(placement: .topBarLeadingCompat) { Button("Home", action: onExit) }
        }
    }

    private func stageGroup(_ stage: LessonStage) -> some View {
        DisclosureGroup(isExpanded: isExpandedBinding(for: stage.id)) {
            VStack(spacing: 10) {
                ForEach(stage.lessons) { lesson in
                    lessonRow(lesson)
                }
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Text(stage.title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(stage.lessons.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Every stage starts expanded (KTD-2 -- there's no search field here to
    /// drive a collapse-by-default rule the way Opening Trainer's does), but
    /// once the user explicitly toggles one, that choice wins from then on.
    private func isExpandedBinding(for stage: String) -> Binding<Bool> {
        Binding(
            get: { manualExpansion[stage] ?? true },
            set: { manualExpansion[stage] = $0 }
        )
    }

    /// A theme's data is available (bundled at build time, already cached on
    /// disk, or just downloaded this session) once any of these is true --
    /// mirrors `PuzzlesView`'s bundled/downloaded row-state check.
    private func isUnlocked(_ lesson: Lesson) -> Bool {
        PuzzleDownloadStore.isBundled(theme: lesson.theme)
            || PuzzleDownloadStore.isDownloaded(theme: lesson.theme)
            || sessionUnlockedThemes.contains(lesson.theme)
    }

    @ViewBuilder
    private func lessonRow(_ lesson: Lesson) -> some View {
        if isUnlocked(lesson) {
            unlockedLessonRow(lesson)
        } else {
            lockedLessonRow(lesson)
        }
    }

    private func unlockedLessonRow(_ lesson: Lesson) -> some View {
        Button {
            selectedLesson = lesson
        } label: {
            lessonCardShell {
                HStack(spacing: 12) {
                    Image(systemName: "book.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.accent2Color)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lesson.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.textColor)
                        Text("\(lesson.puzzleCount) puzzles")
                            .font(.caption).foregroundStyle(theme.textColor.opacity(0.6))
                    }
                    Spacer()
                    progressBadge(for: lesson)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    /// A theme not yet bundled or downloaded (e.g. one of the "Special Moves"
    /// lessons awaiting curated puzzle data -- see `LessonCatalog`). Tapping
    /// attempts the same on-demand download `LessonViewModel.start()` uses;
    /// on success the row flips to `unlockedLessonRow` in place, on failure
    /// the error surfaces inline rather than crashing or failing silently.
    private func lockedLessonRow(_ lesson: Lesson) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                downloadTheme(lesson)
            } label: {
                lessonCardShell {
                    HStack(spacing: 12) {
                        Image(systemName: "book.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(theme.textColor.opacity(0.4))
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(lesson.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("\(lesson.puzzleCount) puzzles")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if downloadingThemes.contains(lesson.theme) {
                            ProgressView()
                        } else {
                            Label("Download", systemImage: "lock.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(PressableStyle())
            .disabled(downloadingThemes.contains(lesson.theme))
            if let error = downloadErrors[lesson.theme] {
                Text(error)
                    .font(.caption2).foregroundStyle(.red)
                    .padding(.horizontal, 14)
            }
        }
    }

    /// The shared card shell every lesson row renders onto -- mirrors
    /// `HomeView.secondaryActionCard`/`beginnersCard`'s trio of
    /// `theme.cardBackgroundColor`/`cardBorderColor`/`PressableStyle` (KTD-3),
    /// reused here for both the unlocked and locked row content.
    private func lessonCardShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(theme.cardBackgroundColor)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func downloadTheme(_ lesson: Lesson) {
        guard !downloadingThemes.contains(lesson.theme) else { return }
        downloadingThemes.insert(lesson.theme)
        downloadErrors[lesson.theme] = nil
        Task {
            do {
                _ = try await PuzzleDownloadStore.downloadPack(theme: lesson.theme)
                downloadingThemes.remove(lesson.theme)
                sessionUnlockedThemes.insert(lesson.theme)
            } catch {
                downloadingThemes.remove(lesson.theme)
                downloadErrors[lesson.theme] = (error as? PuzzleError)?.message ?? error.localizedDescription
            }
        }
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
    @State private var showAskPanel = false
    @State private var questionText = ""
    /// Presented once per completion when `ReviewPromptStore.shouldPrompt`
    /// allows it -- a local, screen-owned sheet rather than a shared
    /// coordinator, mirroring `BoardScannerView`'s `showPaywall` pattern
    /// (plan U6/KTD-7).
    @State private var showReviewPrompt = false
    private var theme: Theme { themeStore.effective }

    var body: some View {
        VStack(spacing: 10) {
            header
            content
            if vm.currentPuzzle != nil {
                askCoachSection
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $vm.showPaywall) { PaywallView() }
        .sheet(isPresented: $showReviewPrompt) { ReviewPromptView() }
        .onChange(of: vm.isLessonComplete) { _, isComplete in
            guard isComplete else { return }
            checkReviewPrompt()
        }
    }

    /// Checked once a lesson finishes (`vm.isLessonComplete` flips true in
    /// `LessonViewModel.finishPuzzle()`) -- one of the two engagement events
    /// `ReviewPromptStore.shouldPrompt` gates on (the other is a finished
    /// game, checked from `PlayViewModel`/`PlayView`). Counts are computed
    /// here rather than read from a store-owned convenience, per U5's
    /// Approach: `ReviewPromptStore` takes caller-supplied totals instead of
    /// duplicating `LessonProgressStore`/`PlayStatsStore`'s own counters.
    private func checkReviewPrompt() {
        let lessonsCompleted = LessonCatalog.allLessons.filter {
            LessonProgressStore.progress(for: $0.id) == .completed
        }.count
        let gamesPlayed = PlayStatsStore.current().totalGames
        if ReviewPromptStore.shouldPrompt(lessonsCompleted: lessonsCompleted, gamesPlayed: gamesPlayed) {
            showReviewPrompt = true
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
                Text(vm.lesson.title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textColor)
                if !vm.puzzles.isEmpty {
                    Text("\(min(vm.puzzleIndex + 1, vm.totalCount)) of \(vm.totalCount)")
                        .font(.caption2).foregroundStyle(theme.textColor.opacity(0.6))
                }
            }
            Spacer()
            if vm.currentPuzzle != nil {
                sideToMoveBadge
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    /// Which side the solver is playing this puzzle -- puzzles can start with
    /// either color to move, so this isn't assumable from the lesson alone.
    private var sideToMoveBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(vm.solverIsWhite ? Color.white : Color.black)
                .overlay(Circle().stroke(theme.textColor.opacity(0.35), lineWidth: 1))
                .frame(width: 11, height: 11)
            Text(vm.solverIsWhite ? "Playing White" : "Playing Black")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textColor)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(theme.cardBackgroundColor, in: Capsule())
        .overlay(Capsule().stroke(theme.cardBorderColor, lineWidth: 1))
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

    /// Pro-gated "Ask the coach" affordance -- a free-form question about the
    /// current puzzle, mirroring `OpeningTrainerView`'s `coachPanel`.
    private var askCoachSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showAskPanel.toggle()
            } label: {
                Label("Ask the coach", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accentColor)

            if showAskPanel {
                HStack {
                    TextField("Ask a question about this puzzle...", text: $questionText)
                        #if os(iOS)
                        .textInputAutocapitalization(.sentences)
                        #endif
                    Button("Ask") {
                        let text = questionText
                        questionText = ""
                        Task { await vm.askQuestion(text) }
                    }
                    .disabled(vm.isAskingCoach || questionText.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if vm.isAskingCoach {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let answer = vm.coachAnswer {
                    Text(answer).font(.subheadline).foregroundStyle(theme.textColor)
                } else if let error = vm.coachError {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 14)
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
