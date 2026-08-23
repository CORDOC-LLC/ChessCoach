package com.chesscoach.android.ui.review

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.chesscoach.android.data.SavedGameStore
import com.chesscoach.core.analysis.ReviewSession
import com.chesscoach.core.analysis.ReviewSessionBuilder
import com.chesscoach.core.chess.Board
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class SavedGameReviewUiState(
    val isLoading: Boolean = true,
    val notReviewable: Boolean = false,
    val session: ReviewSession? = null,
    val currentNode: Int = 0,
    val orientationIsWhite: Boolean = true,
) {
    val nodeCount: Int get() = session?.timeline?.size ?: 0
    val currentTimelineNode get() = session?.timeline?.getOrNull(currentNode)
    val currentFen: String? get() = currentTimelineNode?.fen
    val currentBoard: Board? get() = currentFen?.let { Board.fromFen(it) }
    val winWhiteCurrent: Double get() = currentTimelineNode?.winWhite ?: 50.0
    val winValues: List<Double> get() = session?.timeline?.map { it.winWhite } ?: emptyList()

    /** The graded move review for the current node, if the reviewed side played it. */
    val verdict get() = currentTimelineNode?.ply?.let { ply -> session?.allMoves?.firstOrNull { it.ply == ply } }
}

/** Loads one [com.chesscoach.core.chess.SavedGame] and builds its full
 *  [ReviewSession] (win graph + mistakes list) with zero re-analysis --
 *  Android counterpart of iOS's `ReviewViewModel.openHistoryRecord`, trimmed
 *  to the fast (`ReviewSessionBuilder`) path only. No coach, no paywall. */
class SavedGameReviewViewModel(
    private val gameId: String,
    private val savedGameStore: SavedGameStore,
) : ViewModel() {

    private val _state = MutableStateFlow(SavedGameReviewUiState())
    val state: StateFlow<SavedGameReviewUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            val game = savedGameStore.load(gameId)
            val session = game?.let { ReviewSessionBuilder.build(it) }
            if (session == null) {
                _state.update { it.copy(isLoading = false, notReviewable = true) }
            } else {
                _state.update {
                    it.copy(
                        isLoading = false, session = session, currentNode = 0,
                        orientationIsWhite = session.player == "white",
                    )
                }
            }
        }
    }

    fun goto(node: Int) {
        val s = _state.value
        if (s.nodeCount == 0) return
        _state.update { it.copy(currentNode = node.coerceIn(0, s.nodeCount - 1)) }
    }

    fun next() = goto(_state.value.currentNode + 1)
    fun prev() = goto(_state.value.currentNode - 1)
    fun flip() = _state.update { it.copy(orientationIsWhite = !it.orientationIsWhite) }

    fun gotoMistake(index: Int) {
        val mistake = _state.value.session?.mistakes?.getOrNull(index) ?: return
        goto(mistake.ply - 1)
    }
}
