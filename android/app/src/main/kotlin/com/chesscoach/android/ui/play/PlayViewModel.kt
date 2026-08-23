package com.chesscoach.android.ui.play

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.chesscoach.android.data.AssetRepository
import com.chesscoach.android.data.SavedGameStore
import com.chesscoach.android.engine.EngineProvider
import com.chesscoach.core.chess.Board
import com.chesscoach.core.chess.CapturedMaterial
import com.chesscoach.core.chess.ChessLogic
import com.chesscoach.core.chess.Color
import com.chesscoach.core.chess.GameStatus
import com.chesscoach.core.chess.HintRationaleTemplates
import com.chesscoach.core.chess.Move
import com.chesscoach.core.chess.MoveCommentTemplates
import com.chesscoach.core.chess.MoveGen
import com.chesscoach.core.chess.MoveGrade
import com.chesscoach.core.chess.PieceType
import com.chesscoach.core.chess.PlayMoveRecord
import com.chesscoach.core.chess.San
import com.chesscoach.core.chess.SavedGame
import com.chesscoach.core.chess.Square
import com.chesscoach.core.data.Openings
import com.chesscoach.core.engine.EnginePool
import com.chesscoach.core.eval.Evaluation
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

private const val ANALYSIS_DEPTH = 14
private const val PLAY_DEPTH = 12

data class HintInfo(val bestSan: String, val altSan: String?, val rationale: String, val bestUci: String, val altUci: String?)

data class TopMoveLine(val san: String, val evalText: String)

data class PlaySnapshot(val board: Board, val moveSan: List<String>, val lastMove: Pair<Square, Square>?)

/** Quality-count entry for the game-over banner's strip ("3 Best", "1 Blunder", ...). */
data class QualityCount(val grade: MoveGrade, val count: Int)

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
    val isGrading: Boolean = false,
    val skillLevel: Int = 10,
    val lastGrade: MoveGrade? = null,
    val lastGradeSan: String? = null,
    val lastBetterSan: String? = null,
    val lastEngineComment: String? = null,
    val topMoves: List<TopMoveLine> = emptyList(),
    val openingName: String? = null,
    val openingEco: String? = null,
    val pendingPromotion: Pair<Square, Square>? = null,
    val hintMode: Boolean = false,
    val hint: HintInfo? = null,
    val winWhite: Double = 50.0,
    val evalText: String = "+0.00",
    val capturedMaterial: CapturedMaterial = CapturedMaterial(emptyList(), emptyList(), 0),
    val checkSquare: Square? = null,
    val resigned: Boolean = false,
    val accuracy: Double? = null,
    val qualityCounts: List<QualityCount> = emptyList(),
    val gameOverDismissed: Boolean = false,
    val error: String? = null,
) {
    val isPlayerTurn: Boolean get() = board.sideToMove == playerColor && !status.isTerminal && !resigned
    val canUndo: Boolean get() = moveSan.isNotEmpty() && !isEngineThinking
    val gameOver: Boolean get() = status.isTerminal || resigned

    /** Result text matching iOS's PlayViewModel.status/resultText phrasing. */
    val resultText: String?
        get() = when {
            resigned -> "You resigned."
            status == GameStatus.CHECKMATE -> {
                val loserToMove = board.sideToMove
                val playerLost = loserToMove == playerColor
                if (playerLost) "Checkmate — you lose." else "Checkmate — you win! 🎉"
            }
            status == GameStatus.STALEMATE -> "Stalemate — it's a draw."
            else -> null
        }
}

class PlayViewModel(
    private val engineProvider: EngineProvider,
    private val assetRepository: AssetRepository,
    private val savedGameStore: SavedGameStore? = null,
) : ViewModel() {

    private val _state = MutableStateFlow(PlayUiState())
    val state: StateFlow<PlayUiState> = _state.asStateFlow()

    private var enginePool: EnginePool? = null
    private var openings: Openings? = null
    private val history = mutableListOf<PlaySnapshot>()
    private val playerMoveAccuracies = mutableListOf<Double>()
    private val qualityTally = mutableMapOf<MoveGrade, Int>()
    private var moveGen = 0

    // Persistence: enough to rebuild a full ReviewSession later with zero
    // re-analysis (see core's ReviewSessionBuilder). Keyed by ply index
    // (not append order) so the player-grading coroutine and the engine-eval
    // coroutine -- which race each other -- can't corrupt ordering; a ply
    // that never gets a value (a race/engine hiccup) just makes this game
    // ungradeable later rather than silently misaligning the array.
    private var gameId: String = SavedGameStore.newId()
    private var startedAt: Long = 0L
    private var startFen: String = Board.starting().fen()
    private val winAfterMoverByPly = mutableMapOf<Int, Double>()
    private val moveRecords = mutableListOf<PlayMoveRecord>()

    init {
        val available = engineProvider.isEngineAvailable
        _state.update { it.copy(engineAvailable = available) }
        if (available) enginePool = engineProvider.createEnginePool()
        viewModelScope.launch {
            openings = assetRepository.openings()
        }
    }

    fun newGame(playerColor: Color, skillLevel: Int) {
        moveGen++
        history.clear()
        playerMoveAccuracies.clear()
        qualityTally.clear()
        winAfterMoverByPly.clear()
        moveRecords.clear()
        gameId = SavedGameStore.newId()
        startedAt = System.currentTimeMillis()
        startFen = Board.starting().fen()
        _state.value = PlayUiState(
            playerColor = playerColor,
            skillLevel = skillLevel,
            engineAvailable = _state.value.engineAvailable,
        )
        updateCheckSquare()
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

    /** Toggles hint MODE: while on, the hint stays up and refreshes for every
     *  new position on the player's turn -- mirrors iOS's lightbulb. */
    fun toggleHintMode() {
        val turningOn = !_state.value.hintMode
        _state.update { it.copy(hintMode = turningOn, hint = if (turningOn) it.hint else null) }
        if (turningOn) requestHint()
    }

    fun clearHint() {
        _state.update { it.copy(hintMode = false, hint = null) }
    }

    fun requestHint() {
        val pool = enginePool ?: return
        val s = _state.value
        if (!s.isPlayerTurn) return
        val gen = moveGen
        viewModelScope.launch {
            val fen = s.board.fen()
            runCatching { pool.analyse(fen, ANALYSIS_DEPTH, multipv = 2) }.onSuccess { result ->
                if (gen != moveGen) return@onSuccess
                val bestUci = result.lines.getOrNull(0)?.pvUci?.firstOrNull() ?: return@onSuccess
                val best = san(s.board, bestUci)
                val altUci = result.lines.getOrNull(1)?.pvUci?.firstOrNull()
                val alt = altUci?.let { san(s.board, it) }
                val bestMove = ChessLogic.parseUci(s.board, bestUci)
                val rationale = bestMove?.let { HintRationaleTemplates.rationale(s.board, it) }
                    ?: "A solid move that improves the position."
                if (best != null) _state.update { it.copy(hint = HintInfo(best, alt, rationale, bestUci, altUci)) }
            }
        }
    }

    /** Undo the most recent player/engine move pair (or the lone player move, if
     *  the engine hasn't replied yet). */
    fun retakeLastMove() {
        if (history.isEmpty()) return
        moveGen++
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
                lastGradeSan = null,
                lastBetterSan = null,
                lastEngineComment = null,
                topMoves = emptyList(),
                hint = null,
                resigned = false,
                capturedMaterial = CapturedMaterial.from(board),
            )
        }
        updateCheckSquare()
        if (s.hintMode) requestHint()
    }

    fun resign() {
        if (_state.value.gameOver) return
        _state.update { it.copy(resigned = true, hint = null, hintMode = false) }
        finalizeIfNeeded()
    }

    fun dismissGameOverBanner() {
        _state.update { it.copy(gameOverDismissed = true) }
    }

    override fun onCleared() {
        super.onCleared()
        viewModelScope.launch { enginePool?.shutdown() }
    }

    // MARK: private

    private fun san(board: Board, uci: String): String? = ChessLogic.sanFromUci(uci, board.fen())

    private fun updateCheckSquare() {
        val s = _state.value
        val inCheck = MoveGen.isInCheck(s.board, s.board.sideToMove)
        _state.update { it.copy(checkSquare = if (inCheck) s.board.kingSquare(s.board.sideToMove) else null) }
    }

    private fun winWhiteFromSideToMoveRelative(cp: Double, sideToMoveIsWhite: Boolean): Double {
        val winForMover = Evaluation.winPercent(cp)
        return if (sideToMoveIsWhite) winForMover else 100.0 - winForMover
    }

    private fun applyPlayerMove(uci: String) {
        moveGen++
        val gen = moveGen
        val s = _state.value
        val fenBefore = s.board.fen()
        val move = ChessLogic.parseUci(s.board, uci) ?: return
        val san = San.of(s.board, move)
        val newBoard = s.board.applyMove(move)
        val plyIndex = history.size

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
                isGrading = it.engineAvailable,
                capturedMaterial = CapturedMaterial.from(newBoard),
                openingName = openings?.match(newBoard.fen())?.name ?: it.openingName,
                openingEco = openings?.match(newBoard.fen())?.eco ?: it.openingEco,
            )
        }
        updateCheckSquare()
        checkpoint()
        gradeLastMove(fenBefore, newBoard.fen(), move, san, gen, plyIndex)
        if (!newStatus.isTerminal) requestEngineMove() else finalizeIfNeeded()
    }

    private fun gradeLastMove(fenBefore: String, fenAfter: String, move: Move, moveSan: String, gen: Int, plyIndex: Int) {
        val pool = enginePool ?: return
        viewModelScope.launch {
            runCatching {
                val boardBefore = Board.fromFen(fenBefore)!!
                val before = pool.analyse(fenBefore, ANALYSIS_DEPTH, multipv = 3)
                val playedBestMove = ChessLogic.parseUci(boardBefore, before.best.pvUci.first())
                val after = pool.analyse(fenAfter, ANALYSIS_DEPTH, multipv = 1)
                val actualCpForMover = -after.best.signedCp()
                val wasBest = playedBestMove?.from == move.from && playedBestMove.to == move.to
                val grade = MoveGrade.classify(before.best.signedCp(), actualCpForMover, wasBest)
                val betterSan = if (!wasBest) before.best.pvUci.firstOrNull()?.let { san(boardBefore, it) } else null
                val bestUci = before.best.pvUci.firstOrNull()
                val boardAfter = Board.fromFen(fenAfter)!!
                val comment = MoveCommentTemplates.comment(boardBefore, boardAfter, move, grade, betterSan)
                val topMoves = before.lines.take(3).mapNotNull { line ->
                    val pv = line.pvUci.firstOrNull() ?: return@mapNotNull null
                    san(boardBefore, pv)?.let { TopMoveLine(it, Evaluation.evalText(line.cp, line.mate)) }
                }
                // The mover-relative win% drop for this ply's accuracy contribution.
                val winBefore = Evaluation.winPercent(before.best.signedCp())
                val winAfter = Evaluation.winPercent(actualCpForMover)
                playerMoveAccuracies.add(Evaluation.moveAccuracy(winBefore, winAfter))
                qualityTally[grade] = (qualityTally[grade] ?: 0) + 1
                moveRecords.add(
                    PlayMoveRecord(
                        moveNumber = plyIndex / 2 + 1, san = moveSan,
                        classification = grade.name.lowercase(), winBefore = winBefore, winAfter = winAfter,
                        betterSan = betterSan, bestUci = bestUci, fen = fenAfter,
                    )
                )
                winAfterMoverByPly[plyIndex] = winAfter
                // White-relative win% for the status readout, from this same
                // "after" analysis (side to move has flipped to the opponent).
                val winWhite = winWhiteFromSideToMoveRelative(after.best.signedCp(), boardAfter.sideToMove == Color.WHITE)
                Triple(grade, betterSan, comment) to (topMoves to (winWhite to after.best))
            }.onSuccess { (gradeInfo, rest) ->
                checkpoint()
                if (gen != moveGen) return@onSuccess
                val (grade, betterSan, comment) = gradeInfo
                val (topMoves, winInfo) = rest
                val (winWhite, bestLine) = winInfo
                _state.update {
                    it.copy(
                        lastGrade = grade,
                        lastGradeSan = moveSan,
                        lastBetterSan = betterSan,
                        lastEngineComment = comment,
                        topMoves = topMoves,
                        isGrading = false,
                        winWhite = winWhite,
                        evalText = Evaluation.evalText(bestLine.cp, bestLine.mate),
                    )
                }
            }.onFailure {
                if (gen == moveGen) _state.update { s -> s.copy(isGrading = false) }
            }
        }
    }

    private fun requestEngineMove() {
        val pool = enginePool ?: return
        val s = _state.value
        val gen = moveGen
        _state.update { it.copy(isEngineThinking = true) }
        viewModelScope.launch {
            val fen = s.board.fen()
            val skill = s.skillLevel
            val uci = runCatching {
                if (skill < EnginePool.LOW_SKILL_THRESHOLD) pool.humanLikeMove(fen, PLAY_DEPTH, skill)
                else pool.playMove(fen, PLAY_DEPTH, skill)
            }.getOrNull()

            if (gen != moveGen) return@launch
            _state.update { it.copy(isEngineThinking = false) }
            if (uci == null) return@launch

            val current = _state.value
            val move = ChessLogic.parseUci(current.board, uci) ?: return@launch
            val san = San.of(current.board, move)
            val newBoard = current.board.applyMove(move)
            val plyIndex = history.size
            history.add(PlaySnapshot(newBoard, current.moveSan + san, move.from to move.to))
            val newStatus = GameStatus.of(newBoard)
            _state.update {
                it.copy(
                    board = newBoard,
                    moveSan = it.moveSan + san,
                    lastMove = move.from to move.to,
                    status = newStatus,
                    capturedMaterial = CapturedMaterial.from(newBoard),
                    openingName = openings?.match(newBoard.fen())?.name ?: it.openingName,
                    openingEco = openings?.match(newBoard.fen())?.eco ?: it.openingEco,
                )
            }
            updateCheckSquare()
            checkpoint()
            // The engine's own reply is skill-weighted for move SELECTION, so
            // grading it needs a separate, honest full-strength eval -- same
            // reasoning as iOS's PlayViewModel (see EnginePool's header).
            runCatching { pool.analyse(newBoard.fen(), ANALYSIS_DEPTH, multipv = 1) }.onSuccess { result ->
                // Mover-relative (the engine's own perspective) win% right
                // after its move -- the analysis evaluates from the side now
                // to move (the player), so flip it. Parallels gradeLastMove's
                // actualCpForMover for the player's own moves.
                winAfterMoverByPly[plyIndex] = Evaluation.winPercent(-result.best.signedCp())
                checkpoint()
                if (gen != moveGen) return@onSuccess
                val winWhite = winWhiteFromSideToMoveRelative(result.best.signedCp(), newBoard.sideToMove == Color.WHITE)
                _state.update { it.copy(winWhite = winWhite, evalText = Evaluation.evalText(result.best.cp, result.best.mate)) }
            }
            if (newStatus.isTerminal) finalizeIfNeeded()
            else if (_state.value.hintMode) requestHint()
        }
    }

    private fun finalizeIfNeeded() {
        val accuracy = Evaluation.aggregateAccuracy(playerMoveAccuracies)
        val counts = qualityTally.entries
            .sortedBy { it.key.ordinal } // enum declaration order: BEST..BLUNDER
            .map { QualityCount(it.key, it.value) }
        _state.update { it.copy(accuracy = accuracy, qualityCounts = counts) }
        val store = savedGameStore ?: return
        viewModelScope.launch {
            store.save(toSavedGame(isGameOver = true))
            store.setInProgressGameId(null)
        }
    }

    /** Fire-and-forget mid-game checkpoint -- one small JSON write per ply, so
     *  a killed app can resume from that granularity (mirrors iOS's
     *  `SavedGameStore.save` call after every ply). */
    private fun checkpoint() {
        val store = savedGameStore ?: return
        if (_state.value.gameOver) return // finalizeIfNeeded owns the terminal write
        viewModelScope.launch {
            store.save(toSavedGame(isGameOver = false))
            store.setInProgressGameId(gameId)
        }
    }

    private fun toSavedGame(isGameOver: Boolean): SavedGame {
        val s = _state.value
        val fenHistory = listOf(startFen) + history.map { it.board.fen() }
        val plyCount = s.moveSan.size
        val winAfterMover = (0 until plyCount).map { winAfterMoverByPly[it] }
            .takeIf { it.size == plyCount && it.all { v -> v != null } }
            ?.map { it!! }
        return SavedGame(
            id = gameId, startedAt = startedAt, updatedAt = System.currentTimeMillis(),
            playerIsWhite = s.playerColor == Color.WHITE, startFen = startFen,
            moves = moveUcis(),
            sanMoves = s.moveSan, fenHistory = fenHistory, skill = s.skillLevel,
            isGameOver = isGameOver, resultText = if (isGameOver) s.resultText else null,
            openingName = s.openingName, openingEco = s.openingEco,
            moveRecords = moveRecords.toList(), winAfterMover = winAfterMover,
        )
    }

    /** UCI move list reconstructed from `history`'s squares (PlaySnapshot only
     *  keeps the from/to squares, not the raw UCI token). Promotions never
     *  round-trip through this (the promotion piece letter is lost), which is
     *  fine here -- `moves` is only used to size/pair `winAfterMover` and to
     *  rebuild a display PGN, neither of which replays these UCI strings
     *  through the engine. */
    private fun moveUcis(): List<String> = history.map { snap ->
        val to = snap.lastMove
        if (to == null) "" else to.first.notation + to.second.notation
    }
}
