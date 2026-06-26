//  ChessBoardView.swift
//  A pure-presentation, dependency-free SwiftUI chess board. It renders pieces from
//  a FEN placement field using Unicode glyphs, flips for orientation, highlights the
//  last move, and overlays move arrows. No chess logic lives here — callers pass a
//  FEN, an orientation, optional last-move squares, and a list of arrows.

import SwiftUI
import ChessKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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

    /// True if a FEN char names a piece.
    public static func glyph(for piece: Character) -> String? { filledGlyph(for: piece) }

    /// A chess glyph for a piece char of either colour, or nil. We use the OUTLINE
    /// set (U+2654–2659) for BOTH colours because the filled set (U+265A–F) is
    /// missing from the system UI font (renders as tofu); colour + a drawn outline
    /// at the call site distinguishes white from black.
    public static func filledGlyph(for piece: Character) -> String? {
        switch Character(piece.lowercased()) {
        case "k": return "\u{2654}"; case "q": return "\u{2655}"; case "r": return "\u{2656}"
        case "b": return "\u{2657}"; case "n": return "\u{2658}"; case "p": return "\u{2659}"
        default: return nil
        }
    }

    /// Asset name for a FEN piece char, e.g. 'K' → "wK", 'n' → "bN".
    public static func pieceCode(for ch: Character) -> String {
        (ch.isUppercase ? "w" : "b") + ch.uppercased()
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

    private let light = GemmaTheme.boardLight
    private let dark = GemmaTheme.boardDark
    private let highlight = GemmaTheme.gold.opacity(0.45)

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
                        if let ch = placement[(rank - 1) * 8 + (file - 1)] {
                            BoardPiece(ch: ch, size: sq * 0.88)
                        }
                        if isDot {
                            Circle()
                                .fill(GemmaTheme.accent.opacity(0.70))
                                .frame(width: sq * 0.30, height: sq * 0.30)
                                .shadow(color: GemmaTheme.accent.opacity(0.5), radius: 3)
                        }
                        coordinateLabel(file: file, rank: rank, col: col, row: row, sq: sq, isLight: isLight)
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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// File letters inside the bottom-row cells (bottom-trailing) and rank numbers
    /// inside the left-column cells (top-leading). Coloured with the *opposite*
    /// square colour for contrast on both light and dark squares, semibold.
    @ViewBuilder
    private func coordinateLabel(file: Int, rank: Int, col: Int, row: Int, sq: CGFloat, isLight: Bool) -> some View {
        let labelColor = (isLight ? dark : light).opacity(0.95)
        if row == 7, (1...8).contains(file) {
            Text(String(Square.File.allCases[file - 1].rawValue))
                .font(.system(size: sq * 0.20, weight: .semibold))
                .foregroundStyle(labelColor)
                .padding(3)
                .frame(width: sq, height: sq, alignment: .bottomTrailing)
        }
        if col == 0, (1...8).contains(rank) {
            Text("\(rank)")
                .font(.system(size: sq * 0.20, weight: .semibold))
                .foregroundStyle(labelColor)
                .padding(3)
                .frame(width: sq, height: sq, alignment: .topLeading)
        }
    }

    private func isHighlighted(file: Int, rank: Int) -> Bool {
        guard let lm = lastMove,
              (1...8).contains(file), (1...8).contains(rank) else { return false }
        let letter = Square.File.allCases[file - 1].rawValue
        guard let sq = BoardGeometry.square("\(letter)\(rank)") else { return false }
        return sq == lm.from || sq == lm.to
    }
}

/// A board piece: real cburnett vector artwork when the asset is available,
/// falling back to an outlined glyph (e.g. in pure-SPM previews/tests).
struct BoardPiece: View {
    let ch: Character
    let size: CGFloat

    var body: some View {
        if let image = Self.art(BoardGeometry.pieceCode(for: ch)) {
            image
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.28), radius: 0.8, y: 0.6)
        } else if let glyph = BoardGeometry.filledGlyph(for: ch) {
            PieceGlyph(glyph: glyph, isWhite: ch.isUppercase, size: size)
        }
    }

    /// Load a piece image from the package's asset catalog, or nil if absent.
    static func art(_ name: String) -> Image? {
        #if canImport(UIKit)
        if let ui = UIImage(named: name, in: .module, compatibleWith: nil) { return Image(uiImage: ui) }
        #elseif canImport(AppKit)
        if let ns = Bundle.module.image(forResource: name) { return Image(nsImage: ns) }
        #endif
        return nil
    }
}

/// A chess piece rendered from a filled glyph with a drawn outline, so white pieces
/// stay legible on light squares and black pieces on dark squares.
struct PieceGlyph: View {
    let glyph: String
    let isWhite: Bool
    let size: CGFloat

    var body: some View {
        let fill = isWhite ? GemmaTheme.pieceWhite : GemmaTheme.pieceBlack
        let outline = isWhite ? Color.black.opacity(0.85) : Color.white.opacity(0.50)
        ZStack {
            Text(glyph).font(.system(size: size)).foregroundStyle(outline).scaleEffect(1.10)
            Text(glyph).font(.system(size: size)).foregroundStyle(fill)
        }
        .shadow(color: .black.opacity(0.28), radius: 1, y: 0.5)
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
