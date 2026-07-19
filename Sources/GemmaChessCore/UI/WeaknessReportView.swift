//  WeaknessReportView.swift
//  The Weakness Report screen (plan U7): a Pro-gated coach narrative built
//  from the unified Play + Review game history, with a free teaser stat for
//  non-Pro users and a deep link from the named flaw to a free Lesson/puzzle
//  theme. Themed to match this session's Home/Puzzles/Lessons redesigns.

import SwiftUI

public struct WeaknessReportView: View {
    @State var vm: WeaknessReportViewModel
    var onExit: () -> Void
    var onOpenLesson: (String) -> Void
    var onOpenPuzzleTheme: (String) -> Void
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.effective }

    public init(
        vm: WeaknessReportViewModel = WeaknessReportViewModel(),
        onExit: @escaping () -> Void,
        onOpenLesson: @escaping (String) -> Void,
        onOpenPuzzleTheme: @escaping (String) -> Void
    ) {
        self._vm = State(initialValue: vm)
        self.onExit = onExit
        self.onOpenLesson = onOpenLesson
        self.onOpenPuzzleTheme = onOpenPuzzleTheme
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if ProEntitlementStore.shared.isProActive {
                    unlockedContent
                } else {
                    lockedContent
                }
            }
            .padding(16)
        }
        .navigationTitle("Weakness Report")
        .toolbar {
            ToolbarItem(placement: .topBarLeadingCompat) { Button("Home", action: onExit) }
        }
        .sheet(isPresented: $vm.showPaywall) { PaywallView() }
        .onAppear {
            vm.loadTeaser()
            vm.loadCached()
        }
    }

    private var header: some View {
        Text("A coach-synthesized look at your recent play -- one recurring pattern, and a concrete way to work on it.")
            .font(.subheadline)
            .foregroundStyle(theme.textColor.opacity(0.7))
    }

    // MARK: Locked (free) state

    @ViewBuilder
    private var lockedContent: some View {
        if let motif = vm.teaserMotif {
            card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your most common miss recently").font(.caption).foregroundStyle(theme.textColor.opacity(0.6))
                    Text(motif).font(.title3.weight(.semibold)).foregroundStyle(theme.textColor)
                    Divider().overlay(theme.cardBorderColor)
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill").foregroundStyle(theme.textColor.opacity(0.5))
                        Text("Unlock why this happens and how to fix it").font(.subheadline)
                            .foregroundStyle(theme.textColor.opacity(0.7))
                    }
                    Button("Unlock with ChessCoach Pro") { vm.showPaywall = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            card {
                Text("Play a few more games and this card will show your first pattern.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textColor.opacity(0.7))
            }
        }
    }

    // MARK: Unlocked (Pro) state

    @ViewBuilder
    private var unlockedContent: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
        } else if let error = vm.loadError {
            card {
                Text(error).font(.subheadline).foregroundStyle(theme.textColor.opacity(0.7))
            }
            Button("Try again") { Task { await vm.generate() } }.buttonStyle(.borderedProminent)
        } else if let narrative = vm.narrative {
            card {
                VStack(alignment: .leading, spacing: 12) {
                    Text(narrative).font(.body).foregroundStyle(theme.textColor)
                    if let themeID = vm.suggestedThemeID {
                        deepLinkRow(themeID: themeID)
                    }
                }
            }
            refreshRow
        } else {
            card {
                Text("Ready to see your first Weakness Report.")
                    .font(.subheadline).foregroundStyle(theme.textColor.opacity(0.7))
            }
            Button("Generate report") { Task { await vm.generate() } }.buttonStyle(.borderedProminent)
        }
    }

    private func deepLinkRow(themeID: String) -> some View {
        Button {
            if LessonCatalog.lesson(id: themeID) != nil {
                onOpenLesson(themeID)
            } else {
                onOpenPuzzleTheme(themeID)
            }
        } label: {
            HStack {
                Image(systemName: "arrow.right.circle.fill").foregroundStyle(theme.accentColor)
                Text("Try a Lesson or puzzles on this").font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accentColor)
                Spacer()
            }
        }
        .buttonStyle(PressableStyle())
    }

    private var refreshRow: some View {
        HStack {
            if let generatedAt = WeaknessReportStore.generatedAt() {
                Text("Last updated \(generatedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2).foregroundStyle(theme.textColor.opacity(0.5))
            }
            Spacer()
            Button("Refresh") { Task { await vm.generate() } }
                .disabled(!vm.canRefresh)
                .buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(theme.cardBackgroundColor)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
