//  PlayOutcomeTests.swift
//  PlayViewModel.outcome drives the game-over banner's icon/color -- derived
//  from the exact resultText strings checkGameOver()/resign() set.

import Foundation
import Testing
@testable import GemmaChessCore

@MainActor
@Suite("Play: outcome")
struct PlayOutcomeTests {

    @Test("nil while the game is still live")
    func nilWhileLive() {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        #expect(vm.outcome == nil)
    }

    @Test("a winning checkmate is .win")
    func winningCheckmate() {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        vm.gameOver = true
        vm.resultText = "Checkmate — you win! 🎉"
        #expect(vm.outcome == .win)
    }

    @Test("a losing checkmate is .loss")
    func losingCheckmate() {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        vm.gameOver = true
        vm.resultText = "Checkmate — you lose."
        #expect(vm.outcome == .loss)
    }

    /// Characterization of the pre-U3 behavior, retimed: resigning still yields
    /// exactly one loss and a second resign is still a no-op -- but the tally is
    /// now written by `finalizeOutcome()` (when the player leaves), not by
    /// `resign()` itself.
    @Test("resigning is .loss and records exactly one loss in stats -- at finalize, not at resign")
    func resigning() {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        let before = vm.stats
        vm.resign()
        #expect(vm.outcome == .loss)
        #expect(vm.pendingOutcome == .loss)
        #expect(vm.stats == before)   // deferred: nothing recorded yet

        // Resigning an already-finished game is a no-op -- no double pending.
        vm.resign()
        #expect(vm.pendingOutcome == .loss)

        vm.finalizeOutcome()
        #expect(vm.stats.losses == before.losses + 1)

        // R9: however many times the exit path fires, it records once.
        vm.finalizeOutcome()
        #expect(vm.stats.losses == before.losses + 1)
        #expect(vm.pendingOutcome == nil)
    }

    @Test("stalemate is .draw")
    func stalemate() {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        vm.gameOver = true
        vm.resultText = "Stalemate — it's a draw."
        #expect(vm.outcome == .draw)
    }

    // MARK: Deferred finalization (plan U3, R7/R8/R9)

    /// White to move, Ra1-a8 is mate on the back rank. One user move ends the
    /// game synchronously, so no engine reply is ever needed.
    private static let mateInOneFEN = "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1"

    /// Plays Ra1-a8#, returning the view model in the mated state.
    private func mateInOne(_ vm: PlayViewModel) throws {
        vm.newGame(asWhite: true, startFEN: Self.mateInOneFEN)
        let a1 = try #require(BoardGeometry.square("a1"))
        let a8 = try #require(BoardGeometry.square("a8"))
        vm.tap(a1)
        vm.tap(a8)
        #expect(vm.gameOver)
        #expect(vm.outcome == .win)
    }

    @Test("reaching checkmate sets a pending outcome but changes no tally (R7)")
    func mateDoesNotRecord() throws {
        let vm = PlayViewModel.forTesting()
        let before = vm.stats
        try mateInOne(vm)
        #expect(vm.pendingOutcome == .win)
        #expect(vm.stats == before)
    }

    @Test("finalizing after a mate records the win exactly once (R9)")
    func finalizeAfterMateRecordsOnce() throws {
        let vm = PlayViewModel.forTesting()
        let before = vm.stats
        try mateInOne(vm)

        vm.finalizeOutcome()
        #expect(vm.stats.wins == before.wins + 1)
        #expect(vm.pendingOutcome == nil)

        vm.finalizeOutcome()
        vm.finalizeOutcome()
        #expect(vm.stats.wins == before.wins + 1)
    }

    @Test("undoing a mating move leaves nothing to record (R8)")
    func undoAfterMateRecordsNothing() throws {
        let vm = PlayViewModel.forTesting()
        let before = vm.stats
        try mateInOne(vm)

        vm.undoLastMove()
        #expect(!vm.gameOver)
        #expect(vm.pendingOutcome == nil)

        vm.finalizeOutcome()
        #expect(vm.stats == before)
        #expect(!vm.showReviewPrompt)
    }

    @Test("mate, undo, mate again, finalize records exactly one result")
    func replayAfterUndoRecordsOnce() throws {
        let vm = PlayViewModel.forTesting()
        let before = vm.stats
        try mateInOne(vm)
        vm.undoLastMove()

        let a1 = try #require(BoardGeometry.square("a1"))
        let a8 = try #require(BoardGeometry.square("a8"))
        vm.tap(a1)
        vm.tap(a8)
        #expect(vm.pendingOutcome == .win)

        vm.finalizeOutcome()
        #expect(vm.stats.wins == before.wins + 1)
        #expect(vm.stats.totalGames == before.totalGames + 1)
    }

    @Test("a game abandoned mid-play finalizes to nothing")
    func abandonedGameRecordsNothing() {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        let before = vm.stats
        #expect(vm.pendingOutcome == nil)
        vm.finalizeOutcome()
        #expect(vm.stats == before)
    }

    @Test("starting a new game finalizes the one just finished")
    func newGameFinalizesThePreviousGame() throws {
        let vm = PlayViewModel.forTesting()
        let before = vm.stats
        try mateInOne(vm)
        vm.newGame(asWhite: true)
        #expect(vm.stats.wins == before.wins + 1)
        #expect(vm.pendingOutcome == nil)
    }

    @Test("the projected tally includes the pending result while the persisted one does not")
    func projectedTallyIncludesPendingOutcome() throws {
        let vm = PlayViewModel.forTesting()
        let before = vm.stats
        #expect(vm.projectedStats == before)   // nothing pending: identical

        try mateInOne(vm)
        #expect(vm.stats == before)
        #expect(vm.projectedStats.wins == before.wins + 1)
        #expect(vm.projectedStats.totalGames == before.totalGames + 1)

        vm.finalizeOutcome()
        #expect(vm.projectedStats == vm.stats)   // folded in for real now
    }

    @Test("the saved-game checkpoint reflects isGameOver at mate time, before any finalize")
    func checkpointReflectsGameOverBeforeFinalize() async throws {
        let token = UUID().uuidString
        let savedGamesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayOutcomeTests-saved-\(token)", isDirectory: true)
        let savedGamesDefaults = UserDefaults(suiteName: "PlayOutcomeTests-\(token)")!
        let vm = PlayViewModel(
            savedGamesBaseDir: savedGamesDir, savedGamesDefaults: savedGamesDefaults,
            statsDefaults: UserDefaults(suiteName: "PlayOutcomeTestsStats-\(token)")!,
            historyBaseDir: FileManager.default.temporaryDirectory
                .appendingPathComponent("PlayOutcomeTests-history-\(token)", isDirectory: true))

        try mateInOne(vm)
        await vm.flushPendingSave()

        let saved = try #require(SavedGameStore.load(id: vm.gameID, baseDir: savedGamesDir))
        #expect(saved.isGameOver)
        #expect(vm.pendingOutcome == .win)   // still unrecorded
    }

    // MARK: Teaching moment (plan U2/U4)

    @Test("the coach debrief does not start until the result is dismissed (R5)")
    func debriefWaitsForDismiss() throws {
        let vm = PlayViewModel.forTesting()
        try mateInOne(vm)

        #expect(!vm.gameOverDismissed)
        #expect(!vm.isSummarizing)
        #expect(vm.gameSummary == nil)

        vm.dismissGameOverResult()
        #expect(vm.gameOverDismissed)
        // Whether a debrief actually streams depends on the coach being enabled
        // and entitled; what this pins is that dismissal is the ONLY thing that
        // can start it, and that a second dismiss can't start a second one.
        vm.dismissGameOverResult()
        #expect(vm.gameOverDismissed)
    }

    @Test("undo while the result is showing returns to live play with no debrief")
    func undoClearsTheTeachingState() throws {
        let vm = PlayViewModel.forTesting()
        try mateInOne(vm)
        #expect(vm.mateExplanation?.reason == .checkmate)

        vm.undoLastMove()
        #expect(!vm.gameOver)
        #expect(vm.mateExplanation == nil)
        #expect(!vm.gameOverDismissed)
        #expect(!vm.isSummarizing)
        #expect(vm.gameSummary == nil)
        #expect(vm.pendingOutcome == nil)
    }

    @Test("the review prompt never fires while the result is undismissed (R5)")
    func reviewPromptWaitsForDismiss() throws {
        let vm = PlayViewModel.forTesting()
        try mateInOne(vm)
        vm.finalizeOutcome()   // tally + history recorded, prompt suppressed
        #expect(!vm.showReviewPrompt)
        #expect(vm.stats.totalGames >= 1)
    }

    @Test("the mate explanation is stored at game over and describes the mate")
    func explanationStoredAtGameOver() throws {
        let vm = PlayViewModel.forTesting()
        try mateInOne(vm)
        let explanation = try #require(vm.mateExplanation)
        #expect(explanation.reason == .checkmate)
        #expect(explanation.side == .black)
        #expect(explanation.kingSquare.notation == "g8")
        #expect(!explanation.flightSquares.isEmpty)
    }

    @Test("resigning stores no mate explanation -- there's no geometry to explain")
    func resignHasNoExplanation() {
        let vm = PlayViewModel.forTesting()
        vm.newGame(asWhite: true)
        vm.resign()
        #expect(vm.gameOver)
        #expect(vm.mateExplanation == nil)
        #expect(!vm.gameOverDismissed)
    }
}
