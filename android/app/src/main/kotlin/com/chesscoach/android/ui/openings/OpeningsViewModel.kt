package com.chesscoach.android.ui.openings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.chesscoach.android.data.AssetRepository
import com.chesscoach.core.chess.Board
import com.chesscoach.core.chess.Pgn
import com.chesscoach.core.data.Openings
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class OpeningsUiState(
    val query: String = "",
    val lines: List<Openings.OpeningLine> = emptyList(),
    val isLoading: Boolean = true,
    val selected: Openings.OpeningLine? = null,
    val boards: List<Board> = listOf(Board.starting()),
    val plyIndex: Int = 0,
)

class OpeningsViewModel(private val assetRepository: AssetRepository) : ViewModel() {
    private val _state = MutableStateFlow(OpeningsUiState())
    val state: StateFlow<OpeningsUiState> = _state.asStateFlow()

    private var openings: Openings? = null

    init {
        viewModelScope.launch {
            val loaded = assetRepository.openings()
            openings = loaded
            _state.update { it.copy(lines = loaded.lines, isLoading = false) }
        }
    }

    fun setQuery(query: String) {
        _state.update { it.copy(query = query) }
        val result = openings?.search(query) ?: return
        _state.update { it.copy(lines = result) }
    }

    fun selectLine(line: Openings.OpeningLine) {
        val fens = Pgn.fens(line.sanMoves.joinToString(" "))
        val boards = listOf(Board.starting()) + fens.mapNotNull { Board.fromFen(it) }
        _state.update { it.copy(selected = line, boards = boards, plyIndex = 0) }
    }

    fun closeLine() {
        _state.update { it.copy(selected = null, boards = listOf(Board.starting()), plyIndex = 0) }
    }

    fun stepForward() {
        _state.update { if (it.plyIndex < it.boards.lastIndex) it.copy(plyIndex = it.plyIndex + 1) else it }
    }

    fun stepBack() {
        _state.update { if (it.plyIndex > 0) it.copy(plyIndex = it.plyIndex - 1) else it }
    }
}
