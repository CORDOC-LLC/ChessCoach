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

    /// The piece currently on `square`, or nil when empty (or the FEN is
    /// malformed).
    static func piece(at square: Square, inFEN fen: String) -> (kind: Piece.Kind, color: Piece.Color)? {
        let fields = fen.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let placement = fields.first else { return nil }
        let grid = placementGrid(placement)
        let fileIndex = square.file.number - 1
        let rankIndex = 8 - square.rank.value
        guard grid.indices.contains(rankIndex), grid[rankIndex].indices.contains(fileIndex),
              let ch = grid[rankIndex][fileIndex] else { return nil }
        let kind: Piece.Kind
        switch Character(ch.lowercased()) {
        case "p": kind = .pawn
        case "n": kind = .knight
        case "b": kind = .bishop
        case "r": kind = .rook
        case "q": kind = .queen
        case "k": kind = .king
        default: return nil
        }
        return (kind, ch.isUppercase ? .white : .black)
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

    /// Returns the FEN with the piece placement rotated 180° -- what you need
    /// when a board photo was taken from Black's side, so the vision model
    /// read rank 8 as rank 1 and file h as file a. Castling and en passant
    /// are reset to "-" (square identities changed, so any scanned rights
    /// are meaningless after rotation); side to move and counters pass through.
    static func rotated180(fen: String) -> String {
        var fields = fen.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard !fields.isEmpty else { return fen }
        let grid = placementGrid(fields[0])
        let rotated = grid.reversed().map { Array($0.reversed()) }
        fields[0] = placementString(rotated)
        if fields.count > 2 { fields[2] = "-" }   // castling
        if fields.count > 3 { fields[3] = "-" }   // en passant
        return fields.joined(separator: " ")
    }

    /// True when the placement looks upside down -- White's pieces sit mostly
    /// in the top half (ranks 5-8) and Black's mostly in the bottom half.
    /// Used to auto-correct a board photographed from Black's side.
    static func looksRotated(fen: String) -> Bool {
        let placement = fen.split(separator: " ", maxSplits: 1).first.map(String.init) ?? fen
        let grid = placementGrid(placement)
        var whiteSum = 0, whiteCount = 0, blackSum = 0, blackCount = 0
        for (rowIndex, row) in grid.enumerated() {
            let rank = 8 - rowIndex
            for cell in row {
                guard let ch = cell else { continue }
                if ch.isUppercase { whiteSum += rank; whiteCount += 1 }
                else { blackSum += rank; blackCount += 1 }
            }
        }
        guard whiteCount > 0, blackCount > 0 else { return false }
        let whiteAvg = Double(whiteSum) / Double(whiteCount)
        let blackAvg = Double(blackSum) / Double(blackCount)
        // Require a clear separation, not a toss-up, before second-guessing the scan.
        return whiteAvg > blackAvg + 1.0
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
