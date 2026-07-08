//  SavedGamesView.swift
//  "My Games" -- every Play mode game saved on this device, most recent first.
//  Tapping one loads it: an unfinished game continues where it left off, a
//  finished one opens for move-by-move replay (see PlayViewModel.load).

import SwiftUI

/// Pure, testable formatting for one row: what to show for a saved game.
enum SavedGameRowFormatter {
    static func title(_ game: SavedGame) -> String {
        "\(game.sideLabel) vs Stockfish (skill \(game.skill))"
    }

    static func subtitle(_ game: SavedGame) -> String {
        var parts: [String] = []
        if game.isGameOver {
            parts.append(game.resultText ?? "Game over")
        } else {
            parts.append("In progress")
        }
        if let name = game.openingName, !name.isEmpty { parts.append(name) }
        return parts.joined(separator: " · ")
    }
}

public struct SavedGamesView: View {
    var onSelect: (SavedGame) -> Void
    @State private var games: [SavedGame]

    public init(onSelect: @escaping (SavedGame) -> Void) {
        self.onSelect = onSelect
        self._games = State(initialValue: SavedGameStore.loadAll())
    }

    public var body: some View {
        List {
            Section {
                Text("Saved on this device only — never uploaded anywhere.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if games.isEmpty {
                Section {
                    Text("No games saved yet. Play a game and it'll show up here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(games) { game in
                        Button { onSelect(game) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(SavedGameRowFormatter.title(game))
                                    .font(.subheadline.weight(.semibold))
                                Text(SavedGameRowFormatter.subtitle(game))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("My Games")
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { SavedGameStore.delete(id: games[index].id) }
        games.remove(atOffsets: offsets)
    }
}
