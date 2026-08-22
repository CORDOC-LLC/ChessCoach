package com.chesscoach.android.ui.board

import androidx.annotation.DrawableRes
import com.chesscoach.android.R
import com.chesscoach.core.chess.Color
import com.chesscoach.core.chess.Piece
import com.chesscoach.core.chess.PieceType

@DrawableRes
fun Piece.drawableRes(): Int = when (color) {
    Color.WHITE -> when (type) {
        PieceType.PAWN -> R.drawable.piece_wp
        PieceType.KNIGHT -> R.drawable.piece_wn
        PieceType.BISHOP -> R.drawable.piece_wb
        PieceType.ROOK -> R.drawable.piece_wr
        PieceType.QUEEN -> R.drawable.piece_wq
        PieceType.KING -> R.drawable.piece_wk
    }
    Color.BLACK -> when (type) {
        PieceType.PAWN -> R.drawable.piece_bp
        PieceType.KNIGHT -> R.drawable.piece_bn
        PieceType.BISHOP -> R.drawable.piece_bb
        PieceType.ROOK -> R.drawable.piece_br
        PieceType.QUEEN -> R.drawable.piece_bq
        PieceType.KING -> R.drawable.piece_bk
    }
}
