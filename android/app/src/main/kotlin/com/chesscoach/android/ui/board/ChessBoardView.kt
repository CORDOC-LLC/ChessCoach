package com.chesscoach.android.ui.board

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color as UiColor
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.chesscoach.android.ui.theme.BoardDark
import com.chesscoach.android.ui.theme.BoardHighlight
import com.chesscoach.android.ui.theme.BoardLight
import com.chesscoach.core.chess.Board
import com.chesscoach.core.chess.Square

/** Renders one 8x8 board with tap-to-select-and-move interaction. Stateless: the
 *  caller owns selection/highlight state and reacts to [onSquareClick]. Shared by
 *  every screen that shows a board (Play, Review, Puzzles, Lessons, Openings). */
@Composable
fun ChessBoardView(
    board: Board,
    modifier: Modifier = Modifier,
    whiteAtBottom: Boolean = true,
    selectedSquare: Square? = null,
    legalTargets: Set<Square> = emptySet(),
    lastMove: Pair<Square, Square>? = null,
    checkSquare: Square? = null,
    onSquareClick: (Square) -> Unit = {},
) {
    Column(modifier = modifier.fillMaxWidth().aspectRatio(1f)) {
        for (row in 0 until 8) {
            Row(Modifier.fillMaxWidth().weight(1f)) {
                for (col in 0 until 8) {
                    val file = if (whiteAtBottom) col else 7 - col
                    val rank = if (whiteAtBottom) 7 - row else row
                    val square = Square.of(file, rank)
                    BoardSquare(
                        square = square,
                        board = board,
                        isSelected = square == selectedSquare,
                        isLegalTarget = square in legalTargets,
                        isLastMove = lastMove?.let { square == it.first || square == it.second } == true,
                        isCheck = square == checkSquare,
                        onClick = { onSquareClick(square) },
                        modifier = Modifier.weight(1f).aspectRatio(1f),
                    )
                }
            }
        }
    }
}

@Composable
private fun BoardSquare(
    square: Square,
    board: Board,
    isSelected: Boolean,
    isLegalTarget: Boolean,
    isLastMove: Boolean,
    isCheck: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isLight = (square.file + square.rank) % 2 == 1
    val base = if (isLight) BoardLight else BoardDark
    val piece = board.pieceAt(square)

    Box(
        modifier = modifier
            .background(base)
            .then(if (isLastMove) Modifier.background(BoardHighlight) else Modifier)
            .then(if (isCheck) Modifier.border(3.dp, UiColor(0xFFCC3333)) else Modifier)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (piece != null) {
            Image(
                painter = painterResource(piece.drawableRes()),
                contentDescription = "${piece.color} ${piece.type} on ${square.notation}",
                modifier = Modifier.fillMaxSize().then(if (isSelected) Modifier.background(BoardHighlight) else Modifier),
            )
        } else if (isSelected) {
            Box(Modifier.fillMaxSize().background(BoardHighlight))
        }
        if (isLegalTarget) {
            val dotSize = if (piece == null) 0.28f else 0.85f
            Box(
                Modifier
                    .fillMaxSize(dotSize)
                    .clip(CircleShape)
                    .background(if (piece == null) UiColor(0x552E7D32) else UiColor(0x552E7D32))
                    .let { if (piece != null) it.border(4.dp, UiColor(0x882E7D32), CircleShape) else it },
            )
        }
    }
}
