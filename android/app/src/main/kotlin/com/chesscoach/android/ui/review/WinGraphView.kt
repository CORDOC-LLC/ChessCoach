package com.chesscoach.android.ui.review

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import com.chesscoach.android.ui.theme.ChessCoachTheme
import kotlin.math.roundToInt

/** Win% (White's perspective) line + filled-area graph over the game timeline,
 *  with a marker at the current node and tap/drag-to-scrub. Port of iOS
 *  `WinGraphView` as a Compose `Canvas`. */
@Composable
fun WinGraphView(values: List<Double>, currentIndex: Int, onScrub: (Int) -> Unit, modifier: Modifier = Modifier) {
    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(56.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(ChessCoachTheme.surface.copy(alpha = 0.5f))
            .pointerInput(values.size) {
                if (values.size < 2) return@pointerInput
                val stepX = size.width / (values.size - 1).toFloat()
                detectTapGestures { offset -> onScrub(((offset.x / stepX).roundToInt()).coerceIn(0, values.size - 1)) }
            }
            .pointerInput(values.size) {
                if (values.size < 2) return@pointerInput
                val stepX = size.width / (values.size - 1).toFloat()
                detectDragGestures { change, _ ->
                    onScrub(((change.position.x / stepX).roundToInt()).coerceIn(0, values.size - 1))
                }
            },
    ) {
        val w = size.width
        val h = size.height
        val n = values.size.coerceAtLeast(1)
        val stepX = if (n > 1) w / (n - 1) else w

        fun y(v: Double) = h * (1f - (v.coerceIn(0.0, 100.0) / 100.0).toFloat())

        // 50% midline.
        drawLine(
            color = Color.Gray.copy(alpha = 0.4f),
            start = Offset(0f, h / 2), end = Offset(w, h / 2),
            strokeWidth = 1f,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f)),
        )

        if (values.size >= 2) {
            val accent = ChessCoachTheme.accent
            val linePath = androidx.compose.ui.graphics.Path().apply {
                values.forEachIndexed { i, v ->
                    val pt = Offset(i * stepX, y(v))
                    if (i == 0) moveTo(pt.x, pt.y) else lineTo(pt.x, pt.y)
                }
            }
            val areaPath = androidx.compose.ui.graphics.Path().apply {
                moveTo(0f, h)
                values.forEachIndexed { i, v -> lineTo(i * stepX, y(v)) }
                lineTo((values.size - 1) * stepX, h)
                close()
            }
            drawPath(areaPath, color = accent.copy(alpha = 0.18f))
            drawPath(linePath, color = accent, style = Stroke(width = 1.5.dp.toPx(), cap = StrokeCap.Round))
        }

        if (values.indices.contains(currentIndex)) {
            val x = currentIndex * stepX
            drawLine(
                color = Color.White.copy(alpha = 0.6f),
                start = Offset(x, 0f), end = Offset(x, h),
                strokeWidth = 1.5f,
            )
        }
    }
}
