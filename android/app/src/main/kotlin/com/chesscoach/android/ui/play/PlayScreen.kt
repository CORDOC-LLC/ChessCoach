package com.chesscoach.android.ui.play

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chesscoach.android.ui.board.BoardArrow
import com.chesscoach.android.ui.board.ChessBoardView
import com.chesscoach.android.ui.board.EvalBarView
import com.chesscoach.android.ui.board.WinPie
import com.chesscoach.android.ui.theme.ChessCoachTheme
import com.chesscoach.android.ui.theme.ThemedGlassCard
import com.chesscoach.android.ui.theme.ThemedPrimaryButton
import com.chesscoach.android.ui.theme.ThemedSecondaryButton
import com.chesscoach.core.chess.Color as ChessColor
import com.chesscoach.core.chess.MoveGrade
import com.chesscoach.core.chess.PieceType

/** Color for a move-quality classification, matching iOS `MoveVerdict.color(for:theme:)`:
 *  best/excellent/good -> accent, inaccuracy -> accent2, mistake/blunder -> fixed warm colors. */
private fun gradeColor(grade: MoveGrade): Color = when (grade) {
    MoveGrade.BEST, MoveGrade.EXCELLENT, MoveGrade.GOOD -> ChessCoachTheme.accent
    MoveGrade.INACCURACY -> ChessCoachTheme.accent2
    MoveGrade.MISTAKE -> Color(0xFFFF9800)
    MoveGrade.BLUNDER -> Color(0xFFE53935)
}

@Composable
fun PlayScreen(viewModel: PlayViewModel, resumeGameId: String? = null, onBack: () -> Unit) {
    val state by viewModel.state.collectAsState()
    var showSetup by remember { mutableStateOf(resumeGameId == null) }
    var showMenu by remember { mutableStateOf(false) }

    Box(modifier = Modifier.fillMaxSize().background(ChessCoachTheme.bg)) {
        Column(modifier = Modifier.fillMaxSize().statusBarsPadding().padding(bottom = 8.dp)) {
            PlayHeader(
                state = state,
                onBack = onBack,
                onToggleHint = viewModel::toggleHintMode,
                onUndo = viewModel::retakeLastMove,
                onMenu = { showMenu = true },
                menuExpanded = showMenu,
                onDismissMenu = { showMenu = false },
                onNewGame = { showMenu = false; showSetup = true },
                onResign = { showMenu = false; viewModel.resign() },
            )

            if (!state.engineAvailable) {
                Text(
                    "Stockfish engine binary not bundled in this build.",
                    color = ChessCoachTheme.mutedText,
                    fontSize = 12.sp,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                )
            }

            BoardWithEvalBar(state, onSquareClick = viewModel::onSquareTap)

            CapturedRow(state)

            if (state.hint != null) {
                Spacer(Modifier.height(8.dp))
                HintCard(state.hint!!, onClose = viewModel::clearHint)
            }

            Spacer(Modifier.height(8.dp))
            MoveListCard(state.moveSan, modifier = Modifier.height(120.dp).padding(horizontal = 12.dp))

            if (state.openingName != null) {
                Spacer(Modifier.height(4.dp))
                OpeningRow(state.openingName!!, state.openingEco)
            }

            Spacer(Modifier.height(8.dp))
            if (state.gameOver && !state.gameOverDismissed) {
                GameOverBanner(
                    state = state,
                    onContinue = viewModel::dismissGameOverBanner,
                    modifier = Modifier.padding(horizontal = 12.dp),
                )
            } else {
                AnalysisCard(state, modifier = Modifier.weight(1f).padding(horizontal = 12.dp))
            }
        }
    }

    state.pendingPromotion?.let {
        PromotionDialog(onChoose = viewModel::choosePromotion, onDismiss = viewModel::cancelPromotion)
    }

    if (showSetup) {
        GameSetupDialog(
            onStart = { color, skill ->
                viewModel.newGame(color, skill)
                showSetup = false
            },
            onDismiss = { showSetup = false },
        )
    }
}

@Composable
private fun PlayHeader(
    state: PlayUiState,
    onBack: () -> Unit,
    onToggleHint: () -> Unit,
    onUndo: () -> Unit,
    onMenu: () -> Unit,
    menuExpanded: Boolean,
    onDismissMenu: () -> Unit,
    onNewGame: () -> Unit,
    onResign: () -> Unit,
) {
    ThemedGlassCard(
        cornerRadius = 20,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp).padding(top = 8.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = "Back",
                tint = ChessCoachTheme.accent,
                modifier = Modifier.size(20.dp).clickable(onClick = onBack),
            )
            Spacer(Modifier.width(12.dp))
            if (state.isEngineThinking || state.isGrading) {
                CircularProgressIndicator(
                    color = ChessCoachTheme.accent,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(14.dp).padding(end = 2.dp),
                )
                Spacer(Modifier.width(6.dp))
            }
            Text(
                statusText(state),
                color = if (state.gameOver) ChessCoachTheme.accent else ChessCoachTheme.text,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
            )
            Spacer(Modifier.width(8.dp))
            WinPie(winWhite = state.winWhite, size = 18.dp)
            Spacer(Modifier.width(6.dp))
            Text(state.evalText, color = ChessCoachTheme.text, fontSize = 13.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.weight(1f))
            Icon(
                Icons.Filled.Lightbulb,
                contentDescription = "Hint",
                tint = if (state.hintMode) ChessCoachTheme.accent2 else ChessCoachTheme.text.copy(alpha = 0.7f),
                modifier = Modifier.size(20.dp).clickable(
                    enabled = state.hintMode || (state.isPlayerTurn && !state.gameOver),
                    onClick = onToggleHint,
                ),
            )
            Spacer(Modifier.width(14.dp))
            Icon(
                Icons.AutoMirrored.Filled.Undo,
                contentDescription = "Undo",
                tint = if (state.canUndo) ChessCoachTheme.text.copy(alpha = 0.8f) else ChessCoachTheme.text.copy(alpha = 0.25f),
                modifier = Modifier.size(20.dp).clickable(enabled = state.canUndo, onClick = onUndo),
            )
            Spacer(Modifier.width(14.dp))
            Box {
                Icon(
                    Icons.Filled.MoreVert,
                    contentDescription = "More options",
                    tint = ChessCoachTheme.text.copy(alpha = 0.8f),
                    modifier = Modifier.size(20.dp).clickable(onClick = onMenu),
                )
                DropdownMenu(
                    expanded = menuExpanded,
                    onDismissRequest = onDismissMenu,
                    containerColor = ChessCoachTheme.surface,
                ) {
                    DropdownMenuItem(
                        text = { Text("New game", color = ChessCoachTheme.text) },
                        onClick = onNewGame,
                    )
                    if (!state.gameOver) {
                        DropdownMenuItem(
                            text = { Text("Resign", color = Color(0xFFE53935)) },
                            onClick = onResign,
                        )
                    }
                }
            }
        }
    }
}

private fun statusText(state: PlayUiState): String {
    state.resultText?.let { return it }
    return when {
        state.isEngineThinking -> "Engine is thinking…"
        state.board.sideToMove == state.playerColor -> "Your move"
        else -> "Opponent's move"
    }
}

@Composable
private fun BoardWithEvalBar(state: PlayUiState, onSquareClick: (com.chesscoach.core.chess.Square) -> Unit) {
    // Hint arrows: best (accent, thick) + alternative (gold, thin) -- direct
    // match for iOS's board-drawn hint recommendation.
    val arrows = remember(state.hint, state.board) {
        val hint = state.hint ?: return@remember emptyList<BoardArrow>()
        buildList {
            com.chesscoach.core.chess.ChessLogic.parseUci(state.board, hint.bestUci)?.let {
                add(BoardArrow(it.from, it.to, ChessCoachTheme.accent, thick = true))
            }
            hint.altUci?.let { altUci ->
                com.chesscoach.core.chess.ChessLogic.parseUci(state.board, altUci)?.let {
                    add(BoardArrow(it.from, it.to, ChessCoachTheme.accent2.copy(alpha = 0.9f), thick = false))
                }
            }
        }
    }
    Box(modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp).aspectRatio(1f)) {
        ChessBoardView(
            board = state.board,
            whiteAtBottom = state.playerColor == ChessColor.WHITE,
            selectedSquare = state.selected,
            legalTargets = state.legalTargets,
            lastMove = state.lastMove,
            checkSquare = state.checkSquare,
            arrows = arrows,
            onSquareClick = onSquareClick,
            modifier = Modifier.padding(start = 22.dp),
        )
        EvalBarView(
            winWhite = state.winWhite,
            whiteAtBottom = state.playerColor == ChessColor.WHITE,
            ringColor = ChessCoachTheme.accent2,
            modifier = Modifier.align(Alignment.CenterStart).fillMaxHeight(),
        )
    }
}

@Composable
private fun CapturedRow(state: PlayUiState) {
    val cap = state.capturedMaterial
    val playerCaptures = if (state.playerColor == ChessColor.WHITE) cap.capturedByWhite else cap.capturedByBlack
    val opponentCaptures = if (state.playerColor == ChessColor.WHITE) cap.capturedByBlack else cap.capturedByWhite
    val playerAdvantage = if (state.playerColor == ChessColor.WHITE) cap.delta else -cap.delta
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        CapturedTray(playerCaptures, playerAdvantage)
        CapturedTray(opponentCaptures, -playerAdvantage)
    }
}

@Composable
private fun CapturedTray(pieces: List<Char>, advantage: Int) {
    androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        pieces.forEach { ch ->
            Box(
                modifier = Modifier
                    .size(21.dp)
                    .background(
                        if (ch.isLowerCase()) Color.White.copy(alpha = 0.85f) else Color.White.copy(alpha = 0.10f),
                        CircleShape,
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Text(ch.uppercaseChar().toString(), fontSize = 11.sp, color = Color.Black.copy(alpha = 0.75f), fontWeight = FontWeight.Bold)
            }
        }
        if (advantage > 0) {
            Text(
                "+$advantage",
                color = ChessCoachTheme.accent,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(start = 2.dp),
            )
        }
    }
}

@Composable
private fun HintCard(hint: HintInfo, onClose: () -> Unit) {
    ThemedGlassCard(cornerRadius = 16, modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp)) {
        Column(Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Lightbulb, contentDescription = null, tint = ChessCoachTheme.accent2, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text(
                    hint.altSan?.let { "${hint.bestSan} (or $it)" } ?: hint.bestSan,
                    color = ChessCoachTheme.text,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                )
                Spacer(Modifier.weight(1f))
                Icon(
                    Icons.Filled.Close,
                    contentDescription = "Close hint",
                    tint = ChessCoachTheme.text.copy(alpha = 0.6f),
                    modifier = Modifier.size(16.dp).clickable(onClick = onClose),
                )
            }
            Text(hint.rationale, color = ChessCoachTheme.text.copy(alpha = 0.9f), fontSize = 12.sp, modifier = Modifier.padding(top = 4.dp))
        }
    }
}

@Composable
private fun MoveListCard(sanMoves: List<String>, modifier: Modifier = Modifier) {
    ThemedGlassCard(cornerRadius = 18, modifier = modifier.fillMaxWidth()) {
        Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Moves", color = ChessCoachTheme.text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(ChessCoachTheme.text.copy(alpha = 0.1f)))
        if (sanMoves.isEmpty()) {
            Text(
                "No moves yet.",
                color = ChessCoachTheme.faintText,
                fontSize = 12.sp,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            )
        } else {
            val rows = (sanMoves.size + 1) / 2
            LazyColumn(modifier = Modifier.fillMaxWidth().weight(1f, fill = false)) {
                items(rows) { row ->
                    val whiteIdx = row * 2
                    val blackIdx = whiteIdx + 1
                    Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 2.dp)) {
                        Text(
                            "${row + 1}.",
                            color = ChessCoachTheme.mutedText,
                            fontSize = 13.sp,
                            modifier = Modifier.width(28.dp),
                        )
                        Text(sanMoves[whiteIdx], color = ChessCoachTheme.text, fontSize = 13.sp, modifier = Modifier.weight(1f))
                        Text(
                            if (blackIdx < sanMoves.size) sanMoves[blackIdx] else "",
                            color = ChessCoachTheme.text,
                            fontSize = 13.sp,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun OpeningRow(name: String, eco: String?) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("📖", fontSize = 11.sp)
        Spacer(Modifier.width(5.dp))
        Text(
            if (eco != null) "$name · $eco" else name,
            color = ChessCoachTheme.text.copy(alpha = 0.7f),
            fontSize = 12.sp,
            maxLines = 1,
        )
    }
}

@Composable
private fun VerdictChip(grade: MoveGrade, san: String?, betterSan: String?) {
    val color = gradeColor(grade)
    Row(
        modifier = Modifier
            .background(color.copy(alpha = 0.22f), RoundedCornerShape(50))
            .padding(horizontal = 8.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            if (san != null) "$san · ${grade.label}" else grade.label,
            color = ChessCoachTheme.text,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
        )
        if (betterSan != null) {
            Spacer(Modifier.width(4.dp))
            Text("best $betterSan", color = ChessCoachTheme.text.copy(alpha = 0.75f), fontSize = 10.sp)
        }
    }
}

@Composable
private fun AnalysisCard(state: PlayUiState, modifier: Modifier = Modifier) {
    ThemedGlassCard(cornerRadius = 18, modifier = modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("🔎", fontSize = 13.sp)
                Spacer(Modifier.width(6.dp))
                Text("Analysis", color = ChessCoachTheme.text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                if (state.lastGrade != null) {
                    Spacer(Modifier.width(6.dp))
                    VerdictChip(state.lastGrade!!, state.lastGradeSan, state.lastBetterSan)
                }
            }
            Column(modifier = Modifier.padding(top = 6.dp).verticalScroll(rememberScrollState())) {
                state.lastEngineComment?.let {
                    Text(it, color = ChessCoachTheme.text.copy(alpha = 0.9f), fontSize = 13.sp, modifier = Modifier.padding(bottom = 6.dp))
                }
                if (state.topMoves.isNotEmpty()) {
                    state.topMoves.forEachIndexed { i, line ->
                        Row(modifier = Modifier.fillMaxWidth().padding(vertical = 1.dp)) {
                            Text(
                                "${i + 1}.",
                                color = ChessCoachTheme.text.copy(alpha = 0.4f),
                                fontSize = 12.sp,
                                modifier = Modifier.width(16.dp),
                            )
                            Text(line.san, color = ChessCoachTheme.text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                            Text(line.evalText, color = ChessCoachTheme.text.copy(alpha = 0.6f), fontSize = 12.sp)
                        }
                    }
                } else if (state.lastGrade == null) {
                    Text(
                        "Make a move — I'll grade it.",
                        color = ChessCoachTheme.text.copy(alpha = 0.6f),
                        fontSize = 13.sp,
                    )
                }
            }
        }
    }
}

@Composable
private fun GameOverBanner(state: PlayUiState, onContinue: () -> Unit, modifier: Modifier = Modifier) {
    ThemedGlassCard(cornerRadius = 18, modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(state.resultText ?: "Game over", color = ChessCoachTheme.text, fontSize = 17.sp, fontWeight = FontWeight.Bold)
            state.accuracy?.let { acc ->
                Spacer(Modifier.height(6.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("${acc.toInt()}%", color = ChessCoachTheme.text, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.width(5.dp))
                    Text(accuracyBand(acc), color = ChessCoachTheme.accent2, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                }
                if (state.qualityCounts.isNotEmpty()) {
                    Spacer(Modifier.height(6.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        state.qualityCounts.forEach { q ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(Modifier.size(5.dp).background(gradeColor(q.grade), CircleShape))
                                Spacer(Modifier.width(3.dp))
                                Text("${q.count} ${q.grade.label}", color = ChessCoachTheme.text.copy(alpha = 0.7f), fontSize = 10.sp)
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            ThemedPrimaryButton("Continue", onClick = onContinue)
        }
    }
}

private fun accuracyBand(acc: Double): String = when {
    acc >= 90 -> "Excellent"
    acc >= 75 -> "Great"
    acc >= 60 -> "Good"
    acc >= 45 -> "Inaccurate"
    else -> "Needs work"
}

@Composable
private fun PromotionDialog(onChoose: (PieceType) -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = ChessCoachTheme.surface,
        titleContentColor = ChessCoachTheme.text,
        textContentColor = ChessCoachTheme.text,
        title = { Text("Promote to") },
        text = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(PieceType.QUEEN, PieceType.ROOK, PieceType.BISHOP, PieceType.KNIGHT).forEach { type ->
                    ThemedSecondaryButton(type.name.take(1), onClick = { onChoose(type) })
                }
            }
        },
        confirmButton = {},
    )
}

@Composable
private fun GameSetupDialog(onStart: (ChessColor, Int) -> Unit, onDismiss: () -> Unit) {
    var color by remember { mutableStateOf(ChessColor.WHITE) }
    var skill by remember { mutableStateOf(10f) }

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = ChessCoachTheme.surface,
        titleContentColor = ChessCoachTheme.text,
        textContentColor = ChessCoachTheme.text,
        title = { Text("New game") },
        text = {
            Column {
                Text("Play as", color = ChessCoachTheme.mutedText, fontSize = 13.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 6.dp)) {
                    listOf(ChessColor.WHITE, ChessColor.BLACK).forEach { c ->
                        val selected = c == color
                        val label = (if (c == ChessColor.WHITE) "White" else "Black") + if (selected) " *" else ""
                        ThemedSecondaryButton(label, onClick = { color = c })
                    }
                }
                Text(
                    "Opponent strength: ${skill.toInt()}/20",
                    color = ChessCoachTheme.mutedText,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(top = 16.dp),
                )
                Slider(
                    value = skill,
                    onValueChange = { skill = it },
                    valueRange = 0f..20f,
                    steps = 19,
                    colors = SliderDefaults.colors(
                        thumbColor = ChessCoachTheme.accent,
                        activeTrackColor = ChessCoachTheme.accent,
                        inactiveTrackColor = ChessCoachTheme.text.copy(alpha = 0.16f),
                    ),
                )
            }
        },
        confirmButton = { ThemedPrimaryButton("Start", modifier = Modifier.padding(bottom = 4.dp), onClick = { onStart(color, skill.toInt()) }) },
        dismissButton = { ThemedSecondaryButton("Cancel", onClick = onDismiss) },
    )
}
