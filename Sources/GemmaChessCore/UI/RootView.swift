//  RootView.swift
//  The shared app entry. Both app shells embed `GemmaRootView()`. It owns the single
//  ReviewViewModel and switches between the load screen and the review. The layout
//  adapts to the requested style: a single navigation stack (iPhone, board-first) or
//  a split view (macOS / iPad), with `.automatic` choosing by size class on iOS.

import SwiftUI

/// How the root lays out its load + review surfaces.
public enum GemmaLayoutStyle: Sendable {
    /// Pick automatically (split on regular width, stack on compact).
    case automatic
    /// Single-column navigation stack (board-first).
    case column
    /// Two-column NavigationSplitView.
    case split
}

public struct GemmaRootView: View {
    @State private var vm = ReviewViewModel()
    private let style: GemmaLayoutStyle

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init(style: GemmaLayoutStyle = .automatic) {
        self.style = style
    }

    public var body: some View {
        if resolvedUsesSplit {
            splitLayout
        } else {
            stackLayout
        }
    }

    private var resolvedUsesSplit: Bool {
        switch style {
        case .split: return true
        case .column: return false
        case .automatic:
            #if os(macOS)
            return true
            #elseif os(iOS)
            return horizontalSizeClass == .regular
            #else
            return false
            #endif
        }
    }

    // MARK: Layouts

    private var stackLayout: some View {
        NavigationStack {
            if vm.session == nil {
                LoadView(vm: vm)
            } else {
                ReviewScreen(vm: vm, onNewGame: { vm.session = nil })
            }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            LoadView(vm: vm)
                .frame(minWidth: 280)
        } detail: {
            NavigationStack {
                if vm.session == nil {
                    ContentUnavailableView(
                        "No game loaded",
                        systemImage: "checkerboard.rectangle",
                        description: Text("Paste a PGN, import from Lichess, or open a past game."))
                } else {
                    ReviewScreen(vm: vm, onNewGame: { vm.session = nil })
                }
            }
        }
    }
}
