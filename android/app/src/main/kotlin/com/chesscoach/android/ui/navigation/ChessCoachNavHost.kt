package com.chesscoach.android.ui.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
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
import com.chesscoach.android.ui.theme.ChessCoachTheme
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

    /** Routes the tab bar shows on -- everything else (a chessboard screen,
     *  or Settings) hides it, mirroring iOS `GemmaRootView.isBoardOnScreen`. */
    val TAB_ROUTES = setOf(HOME, LESSONS, OPENINGS, PUZZLES)
}

@Composable
fun ChessCoachNavHost(
    assetRepository: AssetRepository,
    engineProvider: EngineProvider,
    navController: NavHostController = rememberNavController(),
) {
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.hierarchy?.firstOrNull()?.route
    val showTabBar = currentRoute in Routes.TAB_ROUTES

    Scaffold(
        containerColor = ChessCoachTheme.bg,
        bottomBar = {
            if (showTabBar) {
                val activeTab = when (currentRoute) {
                    Routes.LESSONS -> HomeTab.Lessons
                    Routes.OPENINGS -> HomeTab.Openings
                    Routes.PUZZLES -> HomeTab.Puzzles
                    else -> HomeTab.Home
                }
                GlobalTabBar(activeTab = activeTab) { tab ->
                    val route = when (tab) {
                        HomeTab.Home -> Routes.HOME
                        HomeTab.Lessons -> Routes.LESSONS
                        HomeTab.Openings -> Routes.OPENINGS
                        HomeTab.Puzzles -> Routes.PUZZLES
                    }
                    if (route != currentRoute) {
                        navController.navigate(route) {
                            popUpTo(Routes.HOME) { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    }
                }
            }
        },
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().background(ChessCoachTheme.bg)) {
            NavHost(
                navController = navController,
                startDestination = Routes.HOME,
                modifier = Modifier.padding(padding),
            ) {
                composable(Routes.HOME) {
                    HomeScreen(
                        onPlay = { navController.navigate(Routes.PLAY) },
                        onReview = { navController.navigate(Routes.REVIEW) },
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
                    ReviewScreen(vm, onBack = { navController.popBackStack() })
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
                    PuzzleSolveScreen(vm, onBack = { navController.popBackStack() })
                }
                composable(Routes.LESSONS) {
                    LessonsScreen(onLessonClick = { id -> navController.navigate(Routes.lessonDetail(id)) })
                }
                composable(Routes.LESSON_DETAIL) { backStackEntry ->
                    val id = backStackEntry.arguments?.getString("lessonId") ?: return@composable
                    val lesson = LessonCatalog.lesson(id) ?: return@composable
                    LessonDetailScreen(
                        lesson,
                        onBack = { navController.popBackStack() },
                        onPractice = { navController.navigate(Routes.lessonPractice(id)) },
                    )
                }
                composable(Routes.LESSON_PRACTICE) { backStackEntry ->
                    val id = backStackEntry.arguments?.getString("lessonId") ?: return@composable
                    val lesson = LessonCatalog.lesson(id) ?: return@composable
                    val vm: PuzzleSolveViewModel = viewModel(factory = viewModelFactory {
                        initializer { PuzzleSolveViewModel(lesson.theme, assetRepository, lesson.puzzleCount) }
                    })
                    PuzzleSolveScreen(vm, onBack = { navController.popBackStack() })
                }
                composable(Routes.OPENINGS) {
                    val vm: OpeningsViewModel = viewModel(factory = viewModelFactory {
                        initializer { OpeningsViewModel(assetRepository) }
                    })
                    OpeningsScreen(vm)
                }
                composable(Routes.SETTINGS) {
                    SettingsScreen(assetRepository, onBack = { navController.popBackStack() })
                }
            }
        }
    }
}
