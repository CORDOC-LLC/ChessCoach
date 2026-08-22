package com.chesscoach.android.ui.navigation

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.chesscoach.android.data.AssetRepository
import com.chesscoach.android.engine.EngineProvider
import com.chesscoach.android.ui.home.HomeScreen
import com.chesscoach.android.ui.lessons.LessonDetailScreen
import com.chesscoach.android.ui.lessons.LessonsScreen
import com.chesscoach.android.ui.openings.OpeningsScreen
import com.chesscoach.android.ui.openings.OpeningsViewModel
import com.chesscoach.android.ui.play.PlayScreen
import com.chesscoach.android.ui.play.PlayViewModel
import com.chesscoach.android.ui.puzzles.PuzzleSolveScreen
import com.chesscoach.android.ui.puzzles.PuzzleSolveViewModel
import com.chesscoach.android.ui.puzzles.PuzzlesScreen
import com.chesscoach.android.ui.puzzles.PuzzlesViewModel
import com.chesscoach.android.ui.review.ReviewScreen
import com.chesscoach.android.ui.review.ReviewViewModel
import com.chesscoach.android.ui.settings.SettingsScreen
import com.chesscoach.core.data.LessonCatalog

private object Routes {
    const val HOME = "home"
    const val PLAY = "play"
    const val REVIEW = "review"
    const val PUZZLES = "puzzles"
    const val PUZZLE_SOLVE = "puzzleSolve/{theme}"
    const val LESSONS = "lessons"
    const val LESSON_DETAIL = "lessonDetail/{lessonId}"
    const val LESSON_PRACTICE = "lessonPractice/{lessonId}"
    const val OPENINGS = "openings"
    const val SETTINGS = "settings"

    fun puzzleSolve(theme: String) = "puzzleSolve/$theme"
    fun lessonDetail(id: String) = "lessonDetail/$id"
    fun lessonPractice(id: String) = "lessonPractice/$id"
}

@Composable
fun ChessCoachNavHost(
    assetRepository: AssetRepository,
    engineProvider: EngineProvider,
    navController: NavHostController = rememberNavController(),
) {
    NavHost(navController = navController, startDestination = Routes.HOME) {
        composable(Routes.HOME) {
            HomeScreen(
                onPlay = { navController.navigate(Routes.PLAY) },
                onReview = { navController.navigate(Routes.REVIEW) },
                onPuzzles = { navController.navigate(Routes.PUZZLES) },
                onLessons = { navController.navigate(Routes.LESSONS) },
                onOpenings = { navController.navigate(Routes.OPENINGS) },
                onSettings = { navController.navigate(Routes.SETTINGS) },
            )
        }
        composable(Routes.PLAY) {
            val vm: PlayViewModel = viewModel(factory = viewModelFactory {
                initializer { PlayViewModel(engineProvider, assetRepository) }
            })
            PlayScreen(vm, onBack = { navController.popBackStack() })
        }
        composable(Routes.REVIEW) {
            val vm: ReviewViewModel = viewModel(factory = viewModelFactory {
                initializer { ReviewViewModel(engineProvider, assetRepository) }
            })
            ReviewScreen(vm)
        }
        composable(Routes.PUZZLES) {
            val vm: PuzzlesViewModel = viewModel(factory = viewModelFactory {
                initializer { PuzzlesViewModel(assetRepository) }
            })
            PuzzlesScreen(vm, onThemeClick = { theme -> navController.navigate(Routes.puzzleSolve(theme)) })
        }
        composable(Routes.PUZZLE_SOLVE) { backStackEntry ->
            val theme = backStackEntry.arguments?.getString("theme") ?: return@composable
            val vm: PuzzleSolveViewModel = viewModel(factory = viewModelFactory {
                initializer { PuzzleSolveViewModel(theme, assetRepository) }
            })
            PuzzleSolveScreen(vm)
        }
        composable(Routes.LESSONS) {
            LessonsScreen(onLessonClick = { id -> navController.navigate(Routes.lessonDetail(id)) })
        }
        composable(Routes.LESSON_DETAIL) { backStackEntry ->
            val id = backStackEntry.arguments?.getString("lessonId") ?: return@composable
            val lesson = LessonCatalog.lesson(id) ?: return@composable
            LessonDetailScreen(lesson, onPractice = { navController.navigate(Routes.lessonPractice(id)) })
        }
        composable(Routes.LESSON_PRACTICE) { backStackEntry ->
            val id = backStackEntry.arguments?.getString("lessonId") ?: return@composable
            val lesson = LessonCatalog.lesson(id) ?: return@composable
            val vm: PuzzleSolveViewModel = viewModel(factory = viewModelFactory {
                initializer { PuzzleSolveViewModel(lesson.theme, assetRepository, lesson.puzzleCount) }
            })
            PuzzleSolveScreen(vm)
        }
        composable(Routes.OPENINGS) {
            val vm: OpeningsViewModel = viewModel(factory = viewModelFactory {
                initializer { OpeningsViewModel(assetRepository) }
            })
            OpeningsScreen(vm)
        }
        composable(Routes.SETTINGS) {
            SettingsScreen(assetRepository)
        }
    }
}
