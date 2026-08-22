package com.chesscoach.core.data

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DataTest {

    @Test
    fun parsesCatalogAndPuzzleFiles() {
        val catalogJson = """
            {"themes":[{"theme":"fork","count":2,"minRating":552,"maxRating":2693,"file":"fork.json","sizeKB":38.7}]}
        """.trimIndent()
        val catalog = PuzzleCatalog.parseCatalog(catalogJson)
        assertEquals(1, catalog.size)
        assertEquals("fork", catalog[0].theme)
        assertEquals(2, catalog[0].count)

        val puzzlesJson = """
            {"theme":"fork","puzzles":[
              {"id":"03sd0","fen":"8/8/8/3k4/p3pp1p/P1P4P/4K3/7B w - - 0 60","moves":["h1g2","f4f3"],"rating":552,"themes":["fork","endgame"]}
            ]}
        """.trimIndent()
        val puzzles = PuzzleCatalog.parsePuzzles(puzzlesJson)
        assertEquals(1, puzzles.size)
        assertEquals("03sd0", puzzles[0].id)
        assertEquals(listOf("h1g2", "f4f3"), puzzles[0].moves)
        assertEquals(552, puzzles[0].rating)
    }

    @Test
    fun lessonCatalogIsInternallyConsistent() {
        val all = LessonCatalog.allLessons
        assertTrue(all.isNotEmpty())
        assertEquals(all.size, all.map { it.id }.toSet().size, "lesson ids must be unique")
        assertNotNull(LessonCatalog.lesson("fork"))
        assertNull(LessonCatalog.lesson("does-not-exist"))
    }

    @Test
    fun openingsClassifiesFromEcoTsv() {
        val tsv = "eco\tname\tpgn\n" +
            "B20\tSicilian Defense\t1. e4 c5\n" +
            "C50\tItalian Game\t1. e4 e5 2. Nf3 Nc6 3. Bc4\n"
        val openings = Openings.load(listOf(tsv))
        assertEquals(2, openings.lines.size)

        val fens = com.chesscoach.core.chess.Pgn.fens("1. e4 e5 2. Nf3 Nc6 3. Bc4")
        val classified = openings.classifyFromFens(fens)
        assertEquals("Italian Game", classified?.name)
        assertEquals("C50", classified?.eco)
    }

    @Test
    fun openingsSearchIsCaseInsensitive() {
        val tsv = "eco\tname\tpgn\nB20\tSicilian Defense\t1. e4 c5\n"
        val openings = Openings.load(listOf(tsv))
        assertEquals(1, openings.search("sicilian").size)
        assertEquals(1, openings.search("b20").size)
        assertEquals(0, openings.search("caro-kann").size)
    }
}
