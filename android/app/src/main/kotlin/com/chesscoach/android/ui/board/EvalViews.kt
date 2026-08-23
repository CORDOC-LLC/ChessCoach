package com.chesscoach.android.ui.board

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import kotlin.math.min

/** A thin vertical evaluation bar -- direct port of iOS `EvalBarView`. The
 *  fill shows the win% for whichever side sits at the bottom of the board,
 *  so it tracks orientation. Fixed black/white fill regardless of theme. */
@Composable
fun EvalBarView(winWhite: Double, whiteAtBottom: Boolean, ringColor: Color, modifier: Modifier = Modifier) {
    val whiteFrac = (winWhite / 100.0).coerceIn(0.0, 1.0)
    val bottomFrac = (if (whiteAtBottom) whiteFrac else 1.0 - whiteFrac).toFloat()
    Column(
        modifier = modifier
            .width(14.dp)
            .fillMaxHeight()
            .clip(RoundedCornerShape(3.dp)),
    ) {
        Box(Modifier.fillMaxWidth().weight((1f - bottomFrac).coerceAtLeast(0.0001f)).background(Color.Black.copy(alpha = 0.85f)))
        Box(Modifier.fillMaxWidth().weight(bottomFrac.coerceAtLeast(0.0001f)).background(Color.White))
    }
}

/** A compact win-probability read-out as a black/white pie: the white wedge
 *  is White's win%, the rest is Black's -- direct port of iOS `WinPie`. */
@Composable
fun WinPie(winWhite: Double, modifier: Modifier = Modifier, size: androidx.compose.ui.unit.Dp = 20.dp) {
    val frac = (winWhite / 100.0).coerceIn(0.0, 1.0).toFloat()
    Canvas(modifier = modifier.then(Modifier.size(size))) {
        val d = min(this.size.width, this.size.height)
        val r = d / 2f
        val center = Offset(this.size.width / 2f, this.size.height / 2f)
        drawCircle(color = Color(0xFF181310), radius = r, center = center)
        if (frac > 0f) {
            val sweep = 360f * frac
            drawArc(
                color = Color(0xFFF4EEE0),
                startAngle = -90f,
                sweepAngle = sweep,
                useCenter = true,
                topLeft = Offset(center.x - r, center.y - r),
                size = androidx.compose.ui.geometry.Size(r * 2, r * 2),
            )
        }
        drawCircle(color = Color.White.copy(alpha = 0.25f), radius = r, center = center, style = Stroke(width = 1f))
    }
}
