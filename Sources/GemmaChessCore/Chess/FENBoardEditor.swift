//  FENBoardEditor.swift
//  Lets a user hand-edit the piece-placement field of a FEN string one
//  square at a time -- used by BoardScannerView to correct whatever a
//  board-scan vision model got wrong before playing from the position.
//  Only touches placement; side-to-move/castling/en-passant/counters pass
//  through unchanged.

import ChessKit

enum FENBoardEditor {
    /// Returns a new FEN with `square` set to `piece` (or emptied when
    /// `piece` is nil).
    static func settingSquare(
        _ square: Square,
        to piece: (kind: Piece.Kind, color: Piece.Color)?,
        inFEN fen: String
    ) -> String {
        var fields = fen.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard !fields.isEmpty else { return fen }
        var grid = placementGrid(fields[0])
        let fileIndex = square.file.number - 1
        let rankIndex = 8 - square.rank.value
        guard grid.indices.contains(rankIndex), grid[rankIndex].indices.contains(fileIndex) else { return fen }
        grid[rankIndex][fileIndex] = piece.map { fenChar(kind: $0.kind, color: $0.color) }
        fields[0] = placementString(grid)
        return fields.joined(separator: " ")
    }

    static func glyph(kind: Piece.Kind, color: Piece.Color) -> String {
        let white: [Piece.Kind: String] = [
            .pawn: "♙", .knight: "♘", .bishop: "♗", .rook: "♖", .queen: "♕", .king: "♔",
        ]
        let black: [Piece.Kind: String] = [
            .pawn: "♟", .knight: "♞", .bishop: "♝", .rook: "♜", .queen: "♛", .king: "♚",
        ]
        return (color == .white ? white : black)[kind] ?? "?"
    }

    private static func fenChar(kind: Piece.Kind, color: Piece.Color) -> Character {
        let letter: Character
        switch kind {
        case .pawn: letter = "p"
        case .knight: letter = "n"
        case .bishop: letter = "b"
        case .rook: letter = "r"
        case .queen: letter = "q"
        case .king: letter = "k"
        }
        return color == .white ? Character(letter.uppercased()) : letter
    }

    /// row 0 = rank 8 ... row 7 = rank 1; column 0 = file a ... column 7 = file h.
    private static func placementGrid(_ placement: String) -> [[Character?]] {
        var grid: [[Character?]] = []
        for rankStr in placement.split(separator: "/", omittingEmptySubsequences: false) {
            var row: [Character?] = []
            for ch in rankStr {
                if ch.isNumber, let n = ch.wholeNumberValue {
                    row.append(contentsOf: Array(repeating: nil, count: n))
                } else {
                    row.append(ch)
                }
            }
            while row.count < 8 { row.append(nil) }
            grid.append(Array(row.prefix(8)))
        }
        while grid.count < 8 { grid.append(Array(repeating: nil, count: 8)) }
        return Array(grid.prefix(8))
    }

    private static func placementString(_ grid: [[Character?]]) -> String {
        grid.map { row -> String in
            var s = ""
            var emptyRun = 0
            for cell in row {
                if let c = cell {
                    if emptyRun > 0 { s += "\(emptyRun)"; emptyRun = 0 }
                    s.append(c)
                } else {
                    emptyRun += 1
                }
            }
            if emptyRun > 0 { s += "\(emptyRun)" }
            return s
        }.joined(separator: "/")
    }
}
