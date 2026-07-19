//  LessonCatalog.swift
//  A "Lesson" pairs a short, original explanation of a tactical/positional
//  concept with a curated block of practice puzzles pulled from an existing
//  theme pack (see `LessonViewModel`). Entirely free, entirely local -- no
//  network, no coach.
//
//  Structurally inspired by Lichess's "Learn" module (grouping related
//  lessons into stages, explaining a concept before practicing it) but every
//  word of `bodyText` below is original writing, and every practice position
//  comes from ChessCoach's own vendored CC0 Lichess puzzle dataset
//  (`PuzzleData/`) -- never from lila's own curated example positions. lila
//  (lichess-org/lila, which the Learn module ships inside) is AGPLv3-licensed
//  with no separate license carved out for its lesson content, so nothing
//  here is copied from it; only the general "stage groups lessons; a lesson
//  explains then practices" shape is taken as inspiration. See
//  docs/plans/2026-07-19-001-feat-lessons-feature-plan.md (KTD-1) for the
//  full reasoning.

import Foundation

/// One lesson: an explanation plus a bounded practice set.
public struct Lesson: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    /// Matches an existing puzzle theme id (`Puzzle.themes` / `PuzzleThemeInfo.theme`
    /// in `PuzzleModels.swift`) -- the theme pack this lesson's practice
    /// puzzles are pulled from.
    public let theme: String
    /// Original, self-authored explanation of the concept -- see this file's
    /// header for the licensing reasoning behind why this is never copied
    /// from an external source.
    public let bodyText: String
    /// How many puzzles from `theme`'s pack this lesson practices, in
    /// ascending difficulty.
    public let puzzleCount: Int

    public init(id: String, title: String, theme: String, bodyText: String, puzzleCount: Int = 15) {
        self.id = id
        self.title = title
        self.theme = theme
        self.bodyText = bodyText
        self.puzzleCount = puzzleCount
    }
}

/// A group of related lessons, shown as one section in the Lessons list.
public struct LessonStage: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let lessons: [Lesson]

    public init(id: String, title: String, lessons: [Lesson]) {
        self.id = id
        self.title = title
        self.lessons = lessons
    }
}

/// The static, bundled lesson curriculum. A plain Swift literal rather than
/// a loaded resource file (see this plan's KTD-3) -- small enough (~20
/// entries) that this is simpler to author, review, and test than a
/// bundle-loading path.
public enum LessonCatalog {

    public static let stages: [LessonStage] = [
        LessonStage(id: "attacking-two-at-once", title: "Attacking Two Pieces at Once", lessons: [
            Lesson(
                id: "fork", title: "Forks", theme: "fork",
                bodyText: "A fork is when a single piece attacks two (or more) enemy pieces at the same "
                    + "time, so the opponent can't save both. Knights are especially good at this, "
                    + "since the squares a knight attacks are awkward to defend or block all at once. "
                    + "Look for a square where moving one of your pieces there would attack two "
                    + "undefended, or more valuable, enemy pieces simultaneously."
            ),
            Lesson(
                id: "discoveredAttack", title: "Discovered Attacks", theme: "discoveredAttack",
                bodyText: "A discovered attack happens when you move one piece out of the way, "
                    + "revealing an attack from a different piece that was blocked behind it. "
                    + "Because the piece that moves is often making its own threat too, the opponent "
                    + "can end up facing two problems from a single move."
            ),
            Lesson(
                id: "doubleCheck", title: "Double Checks", theme: "doubleCheck",
                bodyText: "A double check is a special discovered attack: the piece you move gives "
                    + "check itself, and the piece it uncovers behind it also gives check -- two "
                    + "pieces checking the king at once. Since no single move can block or capture "
                    + "both attackers simultaneously, the king almost always has to move."
            ),
            Lesson(
                id: "xRayAttack", title: "X-Ray Attacks", theme: "xRayAttack",
                bodyText: "An x-ray attack is when a piece attacks or defends a square through another "
                    + "piece standing in the way, the same way an x-ray passes through what's in front "
                    + "of it. The influence is still real: if the blocking piece ever moves or is "
                    + "captured, the attack or defense behind it is suddenly active."
            ),
        ]),
        LessonStage(id: "removing-the-defense", title: "Removing the Defense", lessons: [
            Lesson(
                id: "pin", title: "Pins", theme: "pin",
                bodyText: "A piece is pinned when it can't move (or shouldn't) because doing so would "
                    + "expose a more valuable piece behind it to attack. The strongest pins are against "
                    + "the king, since moving the pinned piece would be illegal -- it would leave the "
                    + "king in check. Bishops, rooks, and queens create pins along the lines they attack."
            ),
            Lesson(
                id: "skewer", title: "Skewers", theme: "skewer",
                bodyText: "A skewer is a pin in reverse: a valuable piece is attacked first, and when "
                    + "it moves out of the way (as it usually must), a less valuable piece standing "
                    + "behind it gets captured instead. The valuable piece isn't protecting anything -- "
                    + "it just has to move, exposing what's behind it."
            ),
            Lesson(
                id: "deflection", title: "Deflection", theme: "deflection",
                bodyText: "Deflection means forcing an enemy piece away from a square or duty it needs "
                    + "to stay on -- often a piece defending something important. Once it's pulled "
                    + "away, whatever it was protecting becomes vulnerable."
            ),
            Lesson(
                id: "attraction", title: "Attraction", theme: "attraction",
                bodyText: "Attraction means forcing an enemy piece -- often the king -- onto a specific "
                    + "square, usually with a sacrifice, where it becomes vulnerable to a follow-up "
                    + "tactic like a fork or a mating attack."
            ),
            Lesson(
                id: "clearance", title: "Clearance", theme: "clearance",
                bodyText: "A clearance move gets one of your own pieces out of the way -- sometimes by "
                    + "sacrificing it -- specifically to open up a square, rank, file, or diagonal so "
                    + "another one of your pieces can use it."
            ),
        ]),
        LessonStage(id: "material-and-sacrifice", title: "Material Grabs and Sacrifices", lessons: [
            Lesson(
                id: "hangingPiece", title: "Hanging Pieces", theme: "hangingPiece",
                bodyText: "A hanging piece is one that isn't defended by anything, and can simply be "
                    + "captured for free -- or captured before it can be recaptured, winning material. "
                    + "Spotting hanging pieces, yours and your opponent's, is one of the most basic and "
                    + "most valuable habits in chess."
            ),
            Lesson(
                id: "trappedPiece", title: "Trapped Pieces", theme: "trappedPiece",
                bodyText: "A trapped piece has no safe square to move to, even though nothing is "
                    + "attacking it yet. It isn't lost immediately, but once its escape routes are "
                    + "cut off, it can be won later by simply bringing an attacker to it."
            ),
            Lesson(
                id: "sacrifice", title: "Sacrifices", theme: "sacrifice",
                bodyText: "A sacrifice is deliberately giving up material -- a pawn, a piece, even the "
                    + "queen -- because what you get back is worth more: a forced checkmate, winning "
                    + "back even more material, or a decisive positional advantage."
            ),
        ]),
        LessonStage(id: "checkmate-patterns", title: "Checkmate Patterns", lessons: [
            Lesson(
                id: "backRankMate", title: "Back-Rank Mate", theme: "backRankMate",
                bodyText: "A king trapped on its own back rank, boxed in by its own pawns which block "
                    + "its only escape squares, can be checkmated by a rook or queen sliding along that "
                    + "rank -- the king simply has nowhere to run."
            ),
            Lesson(
                id: "smotheredMate", title: "Smothered Mate", theme: "smotheredMate",
                bodyText: "A smothered mate happens when a king is checkmated by a knight while "
                    + "completely surrounded by its own pieces, which block every possible escape "
                    + "square -- smothered by its own army."
            ),
            Lesson(
                id: "mateIn1", title: "Mate in 1", theme: "mateIn1",
                bodyText: "Checkmate delivered in a single move. Find the one move that ends the game "
                    + "right now.",
                puzzleCount: 10
            ),
            Lesson(
                id: "mateIn2", title: "Mate in 2", theme: "mateIn2",
                bodyText: "A forced checkmate in exactly two of your moves, no matter how the opponent "
                    + "responds in between."
            ),
            Lesson(
                id: "mateIn3", title: "Mate in 3", theme: "mateIn3",
                bodyText: "A forced checkmate in exactly three of your moves -- every possible reply "
                    + "the opponent tries still leads to the same result.",
                puzzleCount: 10
            ),
        ]),
        LessonStage(id: "endgame-and-openings", title: "Endgames and Openings", lessons: [
            Lesson(
                id: "zugzwang", title: "Zugzwang", theme: "zugzwang",
                bodyText: "Zugzwang is a position where a player would rather do nothing, because any "
                    + "legal move they make only makes their position worse. Since passing isn't "
                    + "allowed in chess, they're forced to weaken themselves anyway.",
                puzzleCount: 10
            ),
            Lesson(
                id: "endgame", title: "Endgames", theme: "endgame",
                bodyText: "The endgame is the phase of the game with few pieces left on the board, "
                    + "where king activity, passed pawns, and precise calculation matter more than "
                    + "opening theory or piece development."
            ),
            Lesson(
                id: "opening", title: "Openings", theme: "opening",
                bodyText: "The opening is the first phase of the game, where both sides develop their "
                    + "pieces, fight for the center, and get their king to safety. The choices made "
                    + "here shape everything that follows -- see the Opening Trainer to drill named "
                    + "lines move by move."
            ),
        ]),
        LessonStage(id: "special-moves", title: "Special Moves", lessons: [
            // These five themes aren't curated/uploaded to the puzzle host yet
            // (see this plan's Non-goals) -- the lessons below still explain
            // the concept, but `LessonsView` shows them locked behind a
            // "Download" row until `PuzzleDownloadStore.isBundled`/
            // `isDownloaded` reports true for the theme, which won't happen
            // until that data exists. Expected, not a bug.
            Lesson(
                id: "promotion", title: "Promotion", theme: "promotion",
                bodyText: "A pawn that reaches the far end of the board is promoted, becoming any "
                    + "piece the player chooses (almost always a queen). This is one of the most "
                    + "powerful tools in the endgame, since a lowly pawn can become the game's "
                    + "strongest piece."
            ),
            Lesson(
                id: "enPassant", title: "En Passant", theme: "enPassant",
                bodyText: "A special pawn-capture rule: if an enemy pawn moves two squares forward "
                    + "and lands beside your pawn, your pawn can capture it as though it had only "
                    + "moved one square -- but only on the very next move, or the chance is gone "
                    + "for good."
            ),
            Lesson(
                id: "castling", title: "Castling", theme: "castling",
                bodyText: "A special king-and-rook move made once per game, moving the king two "
                    + "squares toward a rook (which hops to the other side) to tuck the king away "
                    + "safely and connect the rooks. Only legal if neither piece has moved yet, the "
                    + "squares between them are empty, and the king isn't in check or moving through "
                    + "check."
            ),
            Lesson(
                id: "quietMove", title: "Quiet Moves", theme: "quietMove",
                bodyText: "Not every winning move is a capture or a check -- sometimes the best move "
                    + "is a quiet one that improves a piece's position or sets up a threat for later, "
                    + "without any immediate fireworks. These are often the hardest tactical moves to "
                    + "spot, since there's no obvious forcing continuation to follow."
            ),
            Lesson(
                id: "defensiveMove", title: "Defensive Moves", theme: "defensiveMove",
                bodyText: "Sometimes the best move on the board isn't an attack at all -- it's the "
                    + "one move that holds off an opponent's threat. Finding the single correct "
                    + "defensive resource is its own skill, distinct from finding an attack."
            ),
        ]),
    ]

    /// Every lesson across every stage, flattened.
    public static var allLessons: [Lesson] { stages.flatMap(\.lessons) }

    public static func lesson(id: String) -> Lesson? {
        allLessons.first { $0.id == id }
    }
}
