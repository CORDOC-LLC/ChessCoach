package com.chesscoach.android.ui.board

import androidx.compose.foundation.Canvas
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color as UiColor
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.chesscoach.android.ui.theme.ChessCoachTheme
import com.chesscoach.core.chess.Board
import com.chesscoach.core.chess.Square
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/** One recommendation/annotation arrow drawn over the board -- a direct
 *  analog of iOS's `BoardArrow` (hint best/alt moves, check attackers). */
data class BoardArrow(val from: Square, val to: Square, val color: UiColor, val thick: Boolean = false)

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
    arrows: List<BoardArrow> = emptyList(),
    onSquareClick: (Square) -> Unit = {},
) {
    Box(modifier = modifier.fillMaxWidth().aspectRatio(1f)) {
        Column(modifier = Modifier.fillMaxSize()) {
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
        if (arrows.isNotEmpty()) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val cell = size.width / 8f
                fun center(sq: Square): Offset {
                    val col = if (whiteAtBottom) sq.file else 7 - sq.file
                    val row = if (whiteAtBottom) 7 - sq.rank else sq.rank
                    return Offset((col + 0.5f) * cell, (row + 0.5f) * cell)
                }
                for (arrow in arrows) {
                    val from = center(arrow.from)
                    val to = center(arrow.to)
                    val strokeWidth = if (arrow.thick) cell * 0.14f else cell * 0.09f
                    val dx = to.x - from.x
                    val dy = to.y - from.y
                    val len = hypot(dx, dy)
                    if (len < 1f) continue
                    val angle = atan2(dy, dx)
                    // Pull the line's end back from the target square's center so
                    // the arrowhead doesn't bury itself under a piece glyph.
                    val shortenBy = cell * 0.32f
                    val lineEnd = Offset(to.x - cos(angle) * shortenBy, to.y - sin(angle) * shortenBy)
                    drawLine(
                        color = arrow.color,
                        start = from,
                        end = lineEnd,
                        strokeWidth = strokeWidth,
                        cap = androidx.compose.ui.graphics.StrokeCap.Round,
                    )
                    val headLen = cell * 0.22f
                    val headAngle = 0.5f
                    val p1 = Offset(
                        lineEnd.x - headLen * cos(angle - headAngle),
                        lineEnd.y - headLen * sin(angle - headAngle),
                    )
                    val p2 = Offset(
                        lineEnd.x - headLen * cos(angle + headAngle),
                        lineEnd.y - headLen * sin(angle + headAngle),
                    )
                    val path = androidx.compose.ui.graphics.Path().apply {
                        moveTo(lineEnd.x, lineEnd.y)
                        lineTo(p1.x, p1.y)
                        lineTo(p2.x, p2.y)
                        close()
                    }
                    drawPath(path, color = arrow.color)
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
    val base = if (isLight) ChessCoachTheme.boardLight else ChessCoachTheme.boardDark
    val highlight = ChessCoachTheme.accent2.copy(alpha = 0.5f)
    val piece = board.pieceAt(square)

    Box(
        modifier = modifier
            .background(base)
            .then(if (isLastMove) Modifier.background(highlight) else Modifier)
            .then(if (isCheck) Modifier.border(3.dp, UiColor(0xFFCC3333)) else Modifier)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (piece != null) {
            Image(
                painter = painterResource(piece.drawableRes()),
                contentDescription = "${piece.color} ${piece.type} on ${square.notation}",
                modifier = Modifier.fillMaxSize().then(if (isSelected) Modifier.background(highlight) else Modifier),
            )
        } else if (isSelected) {
            Box(Modifier.fillMaxSize().background(highlight))
        }
        if (isLegalTarget) {
            val dotSize = if (piece == null) 0.28f else 0.85f
            Box(
                Modifier
                    .fillMaxSize(dotSize)
                    .clip(CircleShape)
                    .background(ChessCoachTheme.accent.copy(alpha = 0.33f))
                    .let { if (piece != null) it.border(4.dp, ChessCoachTheme.accent.copy(alpha = 0.53f), CircleShape) else it },
            )
        }
    }
}
