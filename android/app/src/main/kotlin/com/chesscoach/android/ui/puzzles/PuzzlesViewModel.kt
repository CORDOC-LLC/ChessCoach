package com.chesscoach.android.ui.puzzles

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.chesscoach.android.data.AssetRepository
import com.chesscoach.core.data.PuzzleThemeInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class PuzzlesListState(val themes: List<PuzzleThemeInfo> = emptyList(), val isLoading: Boolean = true)

class PuzzlesViewModel(private val assetRepository: AssetRepository) : ViewModel() {
    private val _state = MutableStateFlow(PuzzlesListState())
    val state: StateFlow<PuzzlesListState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            val themes = assetRepository.puzzleThemes()
            _state.value = PuzzlesListState(themes = themes, isLoading = false)
        }
    }
}
