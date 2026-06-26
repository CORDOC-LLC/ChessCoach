//  ChessBoardView.swift
//  A pure-presentation, dependency-free SwiftUI chess board. It renders pieces from
//  a FEN placement field using Unicode glyphs, flips for orientation, highlights the
//  last move, and overlays move arrows. No chess logic lives here — callers pass a
//  FEN, an orientation, optional last-move squares, and a list of arrows.

import SwiftUI
import ChessKit

/// Which colour sits at the bottom of the board.
public enum BoardOrientation: Sendable, Equatable {
    case white, black
    public var whiteAtBottom: Bool { self == .white }
}

/// One arrow to draw on the board (square → square). Colours by convention:
/// gray = played move, green = engine best, red = refutation.
public struct BoardArrow: Identifiable, Sendable {
    public let id = UUID()
    public var from: Square
    public var to: Square
    public var color: Color
    public var thick: Bool

    public init(from: Square, to: Square, color: Color, thick: Bool) {
        self.from = from; self.to = to; self.color = color; self.thick = thick
    }

    /// Build from a UCI/LAN move ("e2e4"); nil if the squares don't parse.
    public init?(uci: String, color: Color, thick: Bool = false) {
        guard uci.count >= 4,
              let from = BoardGeometry.square(String(uci.prefix(2))),
              let to = BoardGeometry.square(String(uci.dropFirst(2).prefix(2)))
        else { return nil }
        self.init(from: from, to: to, color: color, thick: thick)
    }
}

/// Square ↔ display-coordinate helpers, shared by the board and its arrow overlay.
public enum BoardGeometry {

    /// Parse "e4" into a `Square`, validating file/rank (ChessKit's init falls back
    /// to a1 on bad input, so we validate before trusting it).
    public static func square(_ notation: String) -> Square? {
        let chars = Array(notation.lowercased())
        guard chars.count == 2,
              let file = chars.first, ("a"..."h").contains(file),
              let rankChar = chars.last, let rank = rankChar.wholeNumberValue,
              (1...8).contains(rank)
        else { return nil }
        return Square(notation.lowercased())
    }

    /// Centre point of a square within a board of side `side`, honouring orientation.
    public static func center(file: Int, rank: Int, side: CGFloat, whiteAtBottom: Bool) -> CGPoint {
        let sq = side / 8
        let col = whiteAtBottom ? (file - 1) : (8 - file)
        let row = whiteAtBottom ? (8 - rank) : (rank - 1)
        return CGPoint(x: (CGFloat(col) + 0.5) * sq, y: (CGFloat(row) + 0.5) * sq)
    }

    public static func center(_ square: Square, side: CGFloat, whiteAtBottom: Bool) -> CGPoint {
        center(file: square.file.number, rank: square.rank.value, side: side, whiteAtBottom: whiteAtBottom)
    }

    /// The square at a display point within a board of side `side`, or nil if outside.
    public static func square(atPoint p: CGPoint, side: CGFloat, whiteAtBottom: Bool) -> Square? {
        guard side > 0, p.x >= 0, p.y >= 0, p.x < side, p.y < side else { return nil }
        let sq = side / 8
        let col = Int(p.x / sq), row = Int(p.y / sq)
        let file = whiteAtBottom ? (col + 1) : (8 - col)
        let rank = whiteAtBottom ? (8 - row) : (row + 1)
        guard (1...8).contains(file), (1...8).contains(rank) else { return nil }
        let letter = Square.File.allCases[file - 1].rawValue
        return square("\(letter)\(rank)")
    }

    /// `Square` for a file/rank pair (1...8 each), or nil.
    public static func square(file: Int, rank: Int) -> Square? {
        guard (1...8).contains(file), (1...8).contains(rank) else { return nil }
        return square("\(Square.File.allCases[file - 1].rawValue)\(rank)")
    }

    /// Unicode glyph for a FEN piece character ("K","q",...), or nil for empties.
    public static func glyph(for piece: Character) -> String? {
        switch piece {
        case "K": return "\u{2654}"; case "Q": return "\u{2655}"; case "R": return "\u{2656}"
        case "B": return "\u{2657}"; case "N": return "\u{2658}"; case "P": return "\u{2659}"
        case "k": return "\u{265A}"; case "q": return "\u{265B}"; case "r": return "\u{265C}"
        case "b": return "\u{265D}"; case "n": return "\u{265E}"; case "p": return "\u{265F}"
        default: return nil
        }
    }

    /// Parse a FEN's placement field into `[index: piece]` keyed by `(rank-1)*8 + (file-1)`.
    public static func placement(fromFEN fen: String) -> [Int: Character] {
        var out: [Int: Character] = [:]
        let placement = fen.split(separator: " ", maxSplits: 1).first.map(String.init) ?? fen
        let ranks = placement.split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { return out }
        for (i, row) in ranks.enumerated() {
            let rank = 8 - i               // first row of the field is rank 8
            var file = 1
            for ch in row {
                if let n = ch.wholeNumberValue, !ch.isLetter {
                    file += n
                } else if glyph(for: ch) != nil {
                    out[(rank - 1) * 8 + (file - 1)] = ch
                    file += 1
                }
            }
        }
        return out
    }
}

/// A pure-presentation chess board.
public struct ChessBoardView: View {
    public var fen: String
    public var orientation: BoardOrientation
    public var arrows: [BoardArrow]
    public var lastMove: (from: Square, to: Square)?
    /// Interaction (Play mode): the selected origin square, the legal destinations to
    /// dot, and a tap handler. When `onTapSquare` is nil the board is display-only.
    public var selectedSquare: Square?
    public var legalDots: [Square]
    public var onTapSquare: ((Square) -> Void)?

    public init(
        fen: String,
        orientation: BoardOrientation = .white,
        arrows: [BoardArrow] = [],
        lastMove: (from: Square, to: Square)? = nil,
        selectedSquare: Square? = nil,
        legalDots: [Square] = [],
        onTapSquare: ((Square) -> Void)? = nil
    ) {
        self.fen = fen; self.orientation = orientation
        self.arrows = arrows; self.lastMove = lastMove
        self.selectedSquare = selectedSquare; self.legalDots = legalDots
        self.onTapSquare = onTapSquare
    }

    private let light = Color(red: 0.93, green: 0.85, blue: 0.71)
    private let dark = Color(red: 0.71, green: 0.53, blue: 0.39)
    private let highlight = Color.yellow.opacity(0.45)

    public var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let sq = side / 8
            let placement = BoardGeometry.placement(fromFEN: fen)
            let whiteBottom = orientation.whiteAtBottom

            ZStack(alignment: .topLeading) {
                ForEach(0..<64, id: \.self) { display in
                    let col = display % 8
                    let row = display / 8
                    // Map display cell → board file/rank, honouring orientation.
                    let file = whiteBottom ? (col + 1) : (8 - col)
                    let rank = whiteBottom ? (8 - row) : (row + 1)
                    let isLight = (file + rank) % 2 == 1
                    let highlighted = isHighlighted(file: file, rank: rank)
                    let cellSquare = BoardGeometry.square(file: file, rank: rank)
                    let isSelected = selectedSquare != nil && cellSquare == selectedSquare
                    let isDot = cellSquare.map { legalDots.contains($0) } ?? false

                    ZStack {
                        Rectangle().fill(isLight ? light : dark)
                        if highlighted || isSelected {
                            Rectangle().fill(isSelected ? Color.green.opacity(0.40) : highlight)
                        }
                        if let ch = placement[(rank - 1) * 8 + (file - 1)],
                           let glyph = BoardGeometry.glyph(for: ch) {
                            Text(glyph)
                                .font(.system(size: sq * 0.78))
                                .foregroundStyle(ch.isUppercase ? Color.white : Color.black)
                                .shadow(color: .black.opacity(0.25), radius: 0.5)
                        }
                        if isDot {
                            Circle()
                                .fill(Color.green.opacity(0.55))
                                .frame(width: sq * 0.28, height: sq * 0.28)
                        }
                    }
                    .frame(width: sq, height: sq)
                    .position(x: CGFloat(col) * sq + sq / 2, y: CGFloat(row) * sq + sq / 2)
                    .onTapGesture {
                        if let onTapSquare, let cellSquare { onTapSquare(cellSquare) }
                    }
                }

                ArrowsOverlay(arrows: arrows, side: side, whiteAtBottom: whiteBottom)
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func isHighlighted(file: Int, rank: Int) -> Bool {
        guard let lm = lastMove,
              (1...8).contains(file), (1...8).contains(rank) else { return false }
        let letter = Square.File.allCases[file - 1].rawValue
        guard let sq = BoardGeometry.square("\(letter)\(rank)") else { return false }
        return sq == lm.from || sq == lm.to
    }
}

/// Canvas overlay that draws the move arrows.
struct ArrowsOverlay: View {
    var arrows: [BoardArrow]
    var side: CGFloat
    var whiteAtBottom: Bool

    var body: some View {
        Canvas { context, size in
            let boardSide = min(size.width, size.height)
            let sq = boardSide / 8
            for arrow in arrows {
                let p0 = BoardGeometry.center(arrow.from, side: boardSide, whiteAtBottom: whiteAtBottom)
                let p1 = BoardGeometry.center(arrow.to, side: boardSide, whiteAtBottom: whiteAtBottom)
                draw(arrow: arrow, from: p0, to: p1, squareSize: sq, in: context)
            }
        }
    }

    private func draw(arrow: BoardArrow, from p0: CGPoint, to p1: CGPoint, squareSize sq: CGFloat, in context: GraphicsContext) {
        let dx = p1.x - p0.x, dy = p1.y - p0.y
        let len = max(sqrt(dx * dx + dy * dy), 0.001)
        let ux = dx / len, uy = dy / len
        let lineWidth = sq * (arrow.thick ? 0.20 : 0.12)
        let head = sq * 0.34
        // Shaft stops short of the target centre so the head fits.
        let end = CGPoint(x: p1.x - ux * head, y: p1.y - uy * head)

        var shaft = Path()
        shaft.move(to: p0)
        shaft.addLine(to: end)
        context.stroke(
            shaft,
            with: .color(arrow.color.opacity(0.85)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

        // Arrowhead triangle.
        let px = -uy, py = ux   // perpendicular
        var headPath = Path()
        headPath.move(to: p1)
        headPath.addLine(to: CGPoint(x: end.x + px * head * 0.5, y: end.y + py * head * 0.5))
        headPath.addLine(to: CGPoint(x: end.x - px * head * 0.5, y: end.y - py * head * 0.5))
        headPath.closeSubpath()
        context.fill(headPath, with: .color(arrow.color.opacity(0.95)))
    }
}
