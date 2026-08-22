package com.chesscoach.core.data

/** One lesson: an explanation plus a bounded practice set pulled from a puzzle
 *  theme pack. Ported 1:1 from the iOS `LessonCatalog.swift` -- every word of
 *  [bodyText] is original writing (see that file's header for the licensing
 *  reasoning: nothing here is copied from Lichess's own "Learn" module). */
data class Lesson(
    val id: String,
    val title: String,
    /** Matches a [com.chesscoach.core.data.PuzzleThemeInfo.theme] -- the theme
     *  pack this lesson's practice puzzles are pulled from. */
    val theme: String,
    val bodyText: String,
    /** How many puzzles from [theme]'s pack this lesson practices, ascending
     *  difficulty. */
    val puzzleCount: Int = 15,
)

/** A group of related lessons, shown as one section in the Lessons list. */
data class LessonStage(val id: String, val title: String, val lessons: List<Lesson>)

object LessonCatalog {

    val stages: List<LessonStage> = listOf(
        LessonStage("attacking-two-at-once", "Attacking Two Pieces at Once", listOf(
            Lesson(
                "fork", "Forks", "fork",
                "A fork is when a single piece attacks two (or more) enemy pieces at the same " +
                    "time, so the opponent can't save both. Knights are especially good at this, " +
                    "since the squares a knight attacks are awkward to defend or block all at once. " +
                    "Look for a square where moving one of your pieces there would attack two " +
                    "undefended, or more valuable, enemy pieces simultaneously."
            ),
            Lesson(
                "discoveredAttack", "Discovered Attacks", "discoveredAttack",
                "A discovered attack happens when you move one piece out of the way, " +
                    "revealing an attack from a different piece that was blocked behind it. " +
                    "Because the piece that moves is often making its own threat too, the opponent " +
                    "can end up facing two problems from a single move."
            ),
            Lesson(
                "doubleCheck", "Double Checks", "doubleCheck",
                "A double check is a special discovered attack: the piece you move gives " +
                    "check itself, and the piece it uncovers behind it also gives check -- two " +
                    "pieces checking the king at once. Since no single move can block or capture " +
                    "both attackers simultaneously, the king almost always has to move."
            ),
            Lesson(
                "xRayAttack", "X-Ray Attacks", "xRayAttack",
                "An x-ray attack is when a piece attacks or defends a square through another " +
                    "piece standing in the way, the same way an x-ray passes through what's in front " +
                    "of it. The influence is still real: if the blocking piece ever moves or is " +
                    "captured, the attack or defense behind it is suddenly active."
            ),
        )),
        LessonStage("removing-the-defense", "Removing the Defense", listOf(
            Lesson(
                "pin", "Pins", "pin",
                "A piece is pinned when it can't move (or shouldn't) because doing so would " +
                    "expose a more valuable piece behind it to attack. The strongest pins are against " +
                    "the king, since moving the pinned piece would be illegal -- it would leave the " +
                    "king in check. Bishops, rooks, and queens create pins along the lines they attack."
            ),
            Lesson(
                "skewer", "Skewers", "skewer",
                "A skewer is a pin in reverse: a valuable piece is attacked first, and when " +
                    "it moves out of the way (as it usually must), a less valuable piece standing " +
                    "behind it gets captured instead. The valuable piece isn't protecting anything -- " +
                    "it just has to move, exposing what's behind it."
            ),
            Lesson(
                "deflection", "Deflection", "deflection",
                "Deflection means forcing an enemy piece away from a square or duty it needs " +
                    "to stay on -- often a piece defending something important. Once it's pulled " +
                    "away, whatever it was protecting becomes vulnerable."
            ),
            Lesson(
                "attraction", "Attraction", "attraction",
                "Attraction means forcing an enemy piece -- often the king -- onto a specific " +
                    "square, usually with a sacrifice, where it becomes vulnerable to a follow-up " +
                    "tactic like a fork or a mating attack."
            ),
            Lesson(
                "clearance", "Clearance", "clearance",
                "A clearance move gets one of your own pieces out of the way -- sometimes by " +
                    "sacrificing it -- specifically to open up a square, rank, file, or diagonal so " +
                    "another one of your pieces can use it."
            ),
        )),
        LessonStage("material-and-sacrifice", "Material Grabs and Sacrifices", listOf(
            Lesson(
                "hangingPiece", "Hanging Pieces", "hangingPiece",
                "A hanging piece is one that isn't defended by anything, and can simply be " +
                    "captured for free -- or captured before it can be recaptured, winning material. " +
                    "Spotting hanging pieces, yours and your opponent's, is one of the most basic and " +
                    "most valuable habits in chess."
            ),
            Lesson(
                "trappedPiece", "Trapped Pieces", "trappedPiece",
                "A trapped piece has no safe square to move to, even though nothing is " +
                    "attacking it yet. It isn't lost immediately, but once its escape routes are " +
                    "cut off, it can be won later by simply bringing an attacker to it."
            ),
            Lesson(
                "sacrifice", "Sacrifices", "sacrifice",
                "A sacrifice is deliberately giving up material -- a pawn, a piece, even the " +
                    "queen -- because what you get back is worth more: a forced checkmate, winning " +
                    "back even more material, or a decisive positional advantage."
            ),
        )),
        LessonStage("checkmate-patterns", "Checkmate Patterns", listOf(
            Lesson(
                "backRankMate", "Back-Rank Mate", "backRankMate",
                "A king trapped on its own back rank, boxed in by its own pawns which block " +
                    "its only escape squares, can be checkmated by a rook or queen sliding along that " +
                    "rank -- the king simply has nowhere to run."
            ),
            Lesson(
                "smotheredMate", "Smothered Mate", "smotheredMate",
                "A smothered mate happens when a king is checkmated by a knight while " +
                    "completely surrounded by its own pieces, which block every possible escape " +
                    "square -- smothered by its own army."
            ),
            Lesson("mateIn1", "Mate in 1", "mateIn1", "Checkmate delivered in a single move. Find the one move that ends the game right now.", puzzleCount = 10),
            Lesson(
                "mateIn2", "Mate in 2", "mateIn2",
                "A forced checkmate in exactly two of your moves, no matter how the opponent " +
                    "responds in between."
            ),
            Lesson("mateIn3", "Mate in 3", "mateIn3", "A forced checkmate in exactly three of your moves -- every possible reply the opponent tries still leads to the same result.", puzzleCount = 10),
        )),
        LessonStage("endgame-and-openings", "Endgames and Openings", listOf(
            Lesson("zugzwang", "Zugzwang", "zugzwang", "Zugzwang is a position where a player would rather do nothing, because any legal move they make only makes their position worse. Since passing isn't allowed in chess, they're forced to weaken themselves anyway.", puzzleCount = 10),
            Lesson(
                "endgame", "Endgames", "endgame",
                "The endgame is the phase of the game with few pieces left on the board, " +
                    "where king activity, passed pawns, and precise calculation matter more than " +
                    "opening theory or piece development."
            ),
            Lesson(
                "opening", "Openings", "opening",
                "The opening is the first phase of the game, where both sides develop their " +
                    "pieces, fight for the center, and get their king to safety. The choices made " +
                    "here shape everything that follows -- see the Opening Trainer to drill named " +
                    "lines move by move."
            ),
        )),
        LessonStage("special-moves", "Special Moves", listOf(
            // These five themes aren't curated puzzle packs yet (matches the iOS
            // catalog) -- the lessons still explain the concept; the Lessons screen
            // should show them locked until a matching PuzzleThemeInfo exists.
            Lesson(
                "promotion", "Promotion", "promotion",
                "A pawn that reaches the far end of the board is promoted, becoming any " +
                    "piece the player chooses (almost always a queen). This is one of the most " +
                    "powerful tools in the endgame, since a lowly pawn can become the game's " +
                    "strongest piece."
            ),
            Lesson(
                "enPassant", "En Passant", "enPassant",
                "A special pawn-capture rule: if an enemy pawn moves two squares forward " +
                    "and lands beside your pawn, your pawn can capture it as though it had only " +
                    "moved one square -- but only on the very next move, or the chance is gone " +
                    "for good."
            ),
            Lesson(
                "castling", "Castling", "castling",
                "A special king-and-rook move made once per game, moving the king two " +
                    "squares toward a rook (which hops to the other side) to tuck the king away " +
                    "safely and connect the rooks. Only legal if neither piece has moved yet, the " +
                    "squares between them are empty, and the king isn't in check or moving through " +
                    "check."
            ),
            Lesson(
                "quietMove", "Quiet Moves", "quietMove",
                "Not every winning move is a capture or a check -- sometimes the best move " +
                    "is a quiet one that improves a piece's position or sets up a threat for later, " +
                    "without any immediate fireworks. These are often the hardest tactical moves to " +
                    "spot, since there's no obvious forcing continuation to follow."
            ),
            Lesson(
                "defensiveMove", "Defensive Moves", "defensiveMove",
                "Sometimes the best move on the board isn't an attack at all -- it's the " +
                    "one move that holds off an opponent's threat. Finding the single correct " +
                    "defensive resource is its own skill, distinct from finding an attack."
            ),
        )),
    )

    val allLessons: List<Lesson> get() = stages.flatMap { it.lessons }

    fun lesson(id: String): Lesson? = allLessons.firstOrNull { it.id == id }
}
