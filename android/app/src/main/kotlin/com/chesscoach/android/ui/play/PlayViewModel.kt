package com.chesscoach.android.ui.play

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.chesscoach.android.data.AssetRepository
import com.chesscoach.android.engine.EngineProvider
import com.chesscoach.core.chess.Board
import com.chesscoach.core.chess.ChessLogic
import com.chesscoach.core.chess.Color
import com.chesscoach.core.chess.GameStatus
import com.chesscoach.core.chess.MoveGen
import com.chesscoach.core.chess.PieceType
import com.chesscoach.core.chess.San
import com.chesscoach.core.chess.Square
import com.chesscoach.core.data.Openings
import com.chesscoach.core.engine.EnginePool
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

private const val ANALYSIS_DEPTH = 14
private const val PLAY_DEPTH = 12

data class HintInfo(val bestSan: String, val altSan: String?)

data class PlaySnapshot(val board: Board, val moveSan: List<String>, val lastMove: Pair<Square, Square>?)

data class PlayUiState(
    val board: Board = Board.starting(),
    val moveSan: List<String> = emptyList(),
    val selected: Square? = null,
    val legalTargets: Set<Square> = emptySet(),
    val lastMove: Pair<Square, Square>? = null,
    val status: GameStatus = GameStatus.NORMAL,
    val playerColor: Color = Color.WHITE,
    val engineAvailable: Boolean = false,
    val isEngineThinking: Boolean = false,
    val skillLevel: Int = 10,
    val lastGrade: MoveGrade? = null,
    val openingName: String? = null,
    val pendingPromotion: Pair<Square, Square>? = null,
    val hint: HintInfo? = null,
    val error: String? = null,
) {
    val isPlayerTurn: Boolean get() = board.sideToMove == playerColor && !status.isTerminal
}

class PlayViewModel(
    private val engineProvider: EngineProvider,
    private val assetRepository: AssetRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(PlayUiState())
    val state: StateFlow<PlayUiState> = _state.asStateFlow()

    private var enginePool: EnginePool? = null
    private var openings: Openings? = null
    private val history = mutableListOf<PlaySnapshot>()

    init {
        val available = engineProvider.isEngineAvailable
        _state.update { it.copy(engineAvailable = available) }
        if (available) enginePool = engineProvider.createEnginePool()
        viewModelScope.launch {
            openings = assetRepository.openings()
        }
    }

    fun newGame(playerColor: Color, skillLevel: Int) {
        history.clear()
        _state.value = PlayUiState(
            playerColor = playerColor,
            skillLevel = skillLevel,
            engineAvailable = _state.value.engineAvailable,
        )
        if (playerColor == Color.BLACK) requestEngineMove()
    }

    fun onSquareTap(square: Square) {
        val s = _state.value
        if (!s.isPlayerTurn || s.pendingPromotion != null) return

        val currentSelection = s.selected
        if (currentSelection != null && square in s.legalTargets) {
            val movingPiece = s.board.pieceAt(currentSelection)
            val isPromotion = movingPiece?.type == PieceType.PAWN && (square.rank == 0 || square.rank == 7)
            if (isPromotion) {
                _state.update { it.copy(pendingPromotion = currentSelection to square, selected = null, legalTargets = emptySet()) }
            } else {
                applyPlayerMove(currentSelection.notation + square.notation)
            }
            return
        }

        val piece = s.board.pieceAt(square)
        if (piece != null && piece.color == s.playerColor) {
            val targets = MoveGen.legalMoves(s.board, square).map { it.to }.toSet()
            _state.update { it.copy(selected = square, legalTargets = targets) }
        } else {
            _state.update { it.copy(selected = null, legalTargets = emptySet()) }
        }
    }

    fun choosePromotion(type: PieceType) {
        val pending = _state.value.pendingPromotion ?: return
        val promoChar = type.symbol.lowercaseChar()
        applyPlayerMove("${pending.first.notation}${pending.second.notation}$promoChar")
        _state.update { it.copy(pendingPromotion = null) }
    }

    fun cancelPromotion() {
        _state.update { it.copy(pendingPromotion = null) }
    }

    fun requestHint() {
        val pool = enginePool ?: return
        val s = _state.value
        if (!s.isPlayerTurn) return
        viewModelScope.launch {
            val fen = s.board.fen()
            runCatching { pool.analyse(fen, ANALYSIS_DEPTH, multipv = 2) }.onSuccess { result ->
                val best = result.lines.getOrNull(0)?.pvUci?.firstOrNull()?.let { ChessLogic.sanFromUci(it, fen) }
                val alt = result.lines.getOrNull(1)?.pvUci?.firstOrNull()?.let { ChessLogic.sanFromUci(it, fen) }
                if (best != null) _state.update { it.copy(hint = HintInfo(best, alt)) }
            }
        }
    }

    fun clearHint() {
        _state.update { it.copy(hint = null) }
    }

    /** Undo the most recent player/engine move pair (or the lone player move, if
     *  the engine hasn't replied yet). */
    fun retakeLastMove() {
        if (history.isEmpty()) return
        val s = _state.value
        // sideToMove == playerColor means the engine already replied (turn is back
        // to the player) -- undo that reply plus the player's move. Otherwise only
        // the player's move needs undoing.
        val popCount = if (s.board.sideToMove == s.playerColor) minOf(2, history.size) else 1
        repeat(popCount) { history.removeLastOrNull() }
        val restored = history.lastOrNull()
        val board = restored?.board ?: Board.starting()
        _state.update {
            it.copy(
                board = board,
                moveSan = restored?.moveSan ?: emptyList(),
                lastMove = restored?.lastMove,
                status = GameStatus.of(board),
                selected = null,
                legalTargets = emptySet(),
                lastGrade = null,
                hint = null,
            )
        }
    }

    override fun onCleared() {
        super.onCleared()
        viewModelScope.launch { enginePool?.shutdown() }
    }

    // MARK: private

    private fun applyPlayerMove(uci: String) {
        val s = _state.value
        val fenBefore = s.board.fen()
        val move = ChessLogic.parseUci(s.board, uci) ?: return
        val san = San.of(s.board, move)
        val newBoard = s.board.applyMove(move)

        history.add(PlaySnapshot(newBoard, s.moveSan + san, move.from to move.to))
        val newStatus = GameStatus.of(newBoard)
        _state.update {
            it.copy(
                board = newBoard,
                moveSan = it.moveSan + san,
                selected = null,
                legalTargets = emptySet(),
                lastMove = move.from to move.to,
                status = newStatus,
                hint = null,
                openingName = openings?.match(newBoard.fen())?.name ?: it.openingName,
            )
        }
        gradeLastMove(fenBefore, newBoard.fen())
        if (!newStatus.isTerminal) requestEngineMove()
    }

    private fun gradeLastMove(fenBefore: String, fenAfter: String) {
        val pool = enginePool ?: return
        viewModelScope.launch {
            runCatching {
                val before = pool.analyse(fenBefore, ANALYSIS_DEPTH, multipv = 1)
                val playedBestMove = ChessLogic.parseUci(Board.fromFen(fenBefore)!!, before.best.pvUci.first())
                val after = pool.analyse(fenAfter, ANALYSIS_DEPTH, multipv = 1)
                val actualCpForMover = -after.best.signedCp()
                val wasBest = _state.value.lastMove?.let { (from, to) ->
                    playedBestMove?.from == from && playedBestMove.to == to
                } ?: false
                MoveGrade.classify(before.best.signedCp(), actualCpForMover, wasBest)
            }.onSuccess { grade -> _state.update { it.copy(lastGrade = grade) } }
        }
    }

    private fun requestEngineMove() {
        val pool = enginePool ?: return
        val s = _state.value
        _state.update { it.copy(isEngineThinking = true) }
        viewModelScope.launch {
            val fen = s.board.fen()
            val skill = s.skillLevel
            val uci = runCatching {
                if (skill < EnginePool.LOW_SKILL_THRESHOLD) pool.humanLikeMove(fen, PLAY_DEPTH, skill)
                else pool.playMove(fen, PLAY_DEPTH, skill)
            }.getOrNull()

            _state.update { it.copy(isEngineThinking = false) }
            if (uci == null) return@launch

            val current = _state.value
            val move = ChessLogic.parseUci(current.board, uci) ?: return@launch
            val san = San.of(current.board, move)
            val newBoard = current.board.applyMove(move)
            history.add(PlaySnapshot(newBoard, current.moveSan + san, move.from to move.to))
            _state.update {
                it.copy(
                    board = newBoard,
                    moveSan = it.moveSan + san,
                    lastMove = move.from to move.to,
                    status = GameStatus.of(newBoard),
                    openingName = openings?.match(newBoard.fen())?.name ?: it.openingName,
                )
            }
        }
    }
}
