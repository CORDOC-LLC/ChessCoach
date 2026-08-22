package com.chesscoach.android.ui.puzzles

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.chesscoach.android.data.AssetRepository
import com.chesscoach.core.chess.Board
import com.chesscoach.core.chess.ChessLogic
import com.chesscoach.core.chess.Color
import com.chesscoach.core.chess.MoveGen
import com.chesscoach.core.chess.Square
import com.chesscoach.core.data.Puzzle
import com.chesscoach.core.data.PuzzleThemeInfo
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class PuzzleFeedback { NONE, CORRECT, INCORRECT, SOLVED }

data class PuzzleSolveState(
    val theme: String,
    val puzzles: List<Puzzle> = emptyList(),
    val index: Int = 0,
    val board: Board = Board.starting(),
    val playerColor: Color = Color.WHITE,
    val moveIndex: Int = 0,
    val selected: Square? = null,
    val legalTargets: Set<Square> = emptySet(),
    val lastMove: Pair<Square, Square>? = null,
    val feedback: PuzzleFeedback = PuzzleFeedback.NONE,
    val isLoading: Boolean = true,
) {
    val currentPuzzle: Puzzle? get() = puzzles.getOrNull(index)
    val solvedInSession: Boolean get() = feedback == PuzzleFeedback.SOLVED
}

class PuzzleSolveViewModel(
    private val theme: String,
    private val assetRepository: AssetRepository,
    private val puzzleLimit: Int? = null,
) : ViewModel() {

    private val _state = MutableStateFlow(PuzzleSolveState(theme = theme))
    val state: StateFlow<PuzzleSolveState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            val themes = assetRepository.puzzleThemes()
            val info = themes.firstOrNull { it.theme == theme } ?: return@launch
            val puzzles = assetRepository.puzzles(info).shuffled().let { if (puzzleLimit != null) it.take(puzzleLimit) else it }
            _state.update { it.copy(puzzles = puzzles, isLoading = false) }
            loadPuzzle(0)
        }
    }

    fun nextPuzzle() {
        val s = _state.value
        if (s.puzzles.isEmpty()) return
        loadPuzzle((s.index + 1) % s.puzzles.size)
    }

    fun retryPuzzle() {
        loadPuzzle(_state.value.index)
    }

    fun onSquareTap(square: Square) {
        val s = _state.value
        val puzzle = s.currentPuzzle ?: return
        if (s.feedback == PuzzleFeedback.SOLVED) return

        val selection = s.selected
        if (selection != null && square in s.legalTargets) {
            attemptMove(puzzle, selection, square)
            return
        }
        val piece = s.board.pieceAt(square)
        if (piece != null && piece.color == s.board.sideToMove) {
            val targets = MoveGen.legalMoves(s.board, square).map { it.to }.toSet()
            _state.update { it.copy(selected = square, legalTargets = targets) }
        } else {
            _state.update { it.copy(selected = null, legalTargets = emptySet()) }
        }
    }

    private fun attemptMove(puzzle: Puzzle, from: Square, to: Square) {
        val s = _state.value
        val expectedUci = puzzle.moves.getOrNull(s.moveIndex) ?: return
        // A promotion square yields 4 candidate moves (one per promoted piece), all
        // sharing `to` -- pick the one matching the puzzle's expected promotion
        // letter when present, defaulting to the first (queen) candidate otherwise.
        val candidates = MoveGen.legalMoves(s.board, from).filter { it.to == to }
        val move = candidates.firstOrNull { it.uci == expectedUci } ?: candidates.firstOrNull() ?: return
        val isCorrect = move.uci == expectedUci

        if (!isCorrect) {
            _state.update { it.copy(selected = null, legalTargets = emptySet(), feedback = PuzzleFeedback.INCORRECT) }
            return
        }

        val newBoard = s.board.applyMove(move)
        val nextIndex = s.moveIndex + 1
        val solved = nextIndex >= puzzle.moves.size
        _state.update {
            it.copy(
                board = newBoard,
                moveIndex = nextIndex,
                selected = null,
                legalTargets = emptySet(),
                lastMove = from to to,
                feedback = if (solved) PuzzleFeedback.SOLVED else PuzzleFeedback.CORRECT,
            )
        }
        if (!solved) playOpponentReply(puzzle, nextIndex)
    }

    private fun playOpponentReply(puzzle: Puzzle, moveIndex: Int) {
        viewModelScope.launch {
            delay(400)
            val s = _state.value
            val uci = puzzle.moves.getOrNull(moveIndex) ?: return@launch
            val move = ChessLogic.parseUci(s.board, uci) ?: return@launch
            val newBoard = s.board.applyMove(move)
            _state.update {
                it.copy(board = newBoard, moveIndex = moveIndex + 1, lastMove = move.from to move.to, feedback = PuzzleFeedback.NONE)
            }
        }
    }

    private fun loadPuzzle(index: Int) {
        val puzzle = _state.value.puzzles.getOrNull(index) ?: return
        val startBoard = Board.fromFen(puzzle.fen) ?: return
        // The puzzle's FEN is the position before the opponent's setup move
        // (moves[0]); the player's color is whoever moves next after that.
        val playerColor = startBoard.sideToMove.opposite()
        _state.update {
            it.copy(
                index = index,
                board = startBoard,
                playerColor = playerColor,
                moveIndex = 0,
                selected = null,
                legalTargets = emptySet(),
                lastMove = null,
                feedback = PuzzleFeedback.NONE,
            )
        }
        // moves[0] is the opponent's setup move, auto-played before the player acts.
        playOpponentReply(puzzle, 0)
    }
}
