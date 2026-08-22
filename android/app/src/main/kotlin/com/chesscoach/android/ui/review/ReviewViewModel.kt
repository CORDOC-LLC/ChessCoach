package com.chesscoach.android.ui.review

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.chesscoach.android.data.AssetRepository
import com.chesscoach.android.engine.EngineProvider
import com.chesscoach.core.chess.Board
import com.chesscoach.core.chess.Pgn
import com.chesscoach.core.data.Openings
import com.chesscoach.core.engine.EnginePool
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

private const val ANALYSIS_DEPTH = 14

data class ReviewUiState(
    val pgnInput: String = "",
    val boards: List<Board> = listOf(Board.starting()),
    val moveSan: List<String> = emptyList(),
    val index: Int = 0,
    val engineAvailable: Boolean = false,
    val evalCp: Double? = null,
    val isAnalyzing: Boolean = false,
    val openingName: String? = null,
    val error: String? = null,
) {
    val board: Board get() = boards[index]
    val canStepBack: Boolean get() = index > 0
    val canStepForward: Boolean get() = index < boards.lastIndex
}

class ReviewViewModel(
    private val engineProvider: EngineProvider,
    private val assetRepository: AssetRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(ReviewUiState())
    val state: StateFlow<ReviewUiState> = _state.asStateFlow()

    private var enginePool: EnginePool? = null
    private var openings: Openings? = null
    private var analysisJob: Job? = null

    init {
        val available = engineProvider.isEngineAvailable
        _state.update { it.copy(engineAvailable = available) }
        if (available) enginePool = engineProvider.createEnginePool()
        viewModelScope.launch { openings = assetRepository.openings() }
    }

    fun setPgnInput(text: String) {
        _state.update { it.copy(pgnInput = text) }
    }

    fun importPgn() {
        val pgn = _state.value.pgnInput
        val startFen = Pgn.startingFen(pgn)
        val startBoard = Board.fromFen(startFen)
        if (startBoard == null) {
            _state.update { it.copy(error = "Couldn't parse this PGN's starting position.") }
            return
        }
        val fens = Pgn.fens(pgn)
        val sans = Pgn.mainlineSan(pgn).take(fens.size)
        val boards = listOf(startBoard) + fens.mapNotNull { Board.fromFen(it) }

        if (boards.size == 1 && sans.isNotEmpty()) {
            _state.update { it.copy(error = "Couldn't replay this PGN's moves -- check for typos.") }
            return
        }

        _state.value = ReviewUiState(
            pgnInput = pgn,
            boards = boards,
            moveSan = sans,
            index = 0,
            engineAvailable = _state.value.engineAvailable,
            openingName = openings?.classifyFromFens(fens)?.name,
        )
        analyzeCurrentPosition()
    }

    fun stepForward() {
        val s = _state.value
        if (!s.canStepForward) return
        _state.update { it.copy(index = it.index + 1) }
        analyzeCurrentPosition()
    }

    fun stepBack() {
        val s = _state.value
        if (!s.canStepBack) return
        _state.update { it.copy(index = it.index - 1) }
        analyzeCurrentPosition()
    }

    fun jumpTo(index: Int) {
        val s = _state.value
        if (index !in s.boards.indices) return
        _state.update { it.copy(index = index) }
        analyzeCurrentPosition()
    }

    override fun onCleared() {
        super.onCleared()
        viewModelScope.launch { enginePool?.shutdown() }
    }

    private fun analyzeCurrentPosition() {
        val pool = enginePool ?: return
        analysisJob?.cancel()
        _state.update { it.copy(isAnalyzing = true, evalCp = null) }
        analysisJob = viewModelScope.launch {
            val fen = _state.value.board.fen()
            val result = runCatching { pool.analyse(fen, ANALYSIS_DEPTH, multipv = 1) }.getOrNull()
            _state.update { it.copy(isAnalyzing = false, evalCp = result?.best?.signedCp()) }
        }
    }
}
