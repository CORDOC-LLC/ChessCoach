package com.chesscoach.core.chess

enum class GameStatus {
    NORMAL, CHECK, CHECKMATE, STALEMATE;

    val isTerminal: Boolean get() = this == CHECKMATE || this == STALEMATE

    companion object {
        fun of(board: Board): GameStatus {
            val inCheck = MoveGen.isInCheck(board, board.sideToMove)
            val hasMoves = MoveGen.legalMoves(board).isNotEmpty()
            return when {
                inCheck && !hasMoves -> CHECKMATE
                inCheck -> CHECK
                !hasMoves -> STALEMATE
                else -> NORMAL
            }
        }
    }
}
