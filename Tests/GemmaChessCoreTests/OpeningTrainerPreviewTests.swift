//  OpeningTrainerPreviewTests.swift
//  Covers the Moves panel's step-by-step board preview: stepping forward/
//  backward through a line without disturbing the real drill state, jumping
//  directly to a move, and snapping back to wherever the live drill actually
//  is.

import Testing
import Foundation
@testable import GemmaChessCore

@MainActor
@Suite("OpeningTrainerViewModel: step-by-step move preview")
struct OpeningTrainerPreviewTests {

    private let line = Openings.OpeningLine(eco: "C50", name: "Italian Game", sanMoves: ["e4", "e5", "Nf3", "Nc6"])

    @Test("preview starts at index 0 on a fresh drill, independent of the live drill state")
    func previewStartsAtZero() {
        let vm = OpeningTrainerViewModel(defaults: UserDefaults(suiteName: #function)!)
        vm.start(line: line, userIsWhite: true)

        #expect(vm.previewIndex == 0)
        #expect(vm.previewFEN == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        #expect(vm.previewMoveUCI == "e2e4")
        #expect(vm.canStepPreviewBackward == false)
        #expect(vm.canStepPreviewForward)
    }

    @Test("stepping forward advances the preview position without touching the live drill")
    func stepForwardAdvancesPreviewOnly() {
        let vm = OpeningTrainerViewModel(defaults: UserDefaults(suiteName: #function)!)
        vm.start(line: line, userIsWhite: true)
        let liveFENBefore = vm.fen

        vm.stepPreviewForward()

        #expect(vm.previewIndex == 1)
        #expect(vm.previewMoveUCI == "e7e5")
        #expect(vm.fen == liveFENBefore)   // the real drill position is untouched
        #expect(vm.canStepPreviewBackward)
    }

    @Test("stepping forward is clamped at the line's last move")
    func stepForwardClampsAtEnd() {
        let vm = OpeningTrainerViewModel(defaults: UserDefaults(suiteName: #function)!)
        vm.start(line: line, userIsWhite: true)

        for _ in 0..<10 { vm.stepPreviewForward() }

        #expect(vm.previewIndex == line.sanMoves.count - 1)
        #expect(vm.canStepPreviewForward == false)
    }

    @Test("stepping backward is clamped at zero")
    func stepBackwardClampsAtZero() {
        let vm = OpeningTrainerViewModel(defaults: UserDefaults(suiteName: #function)!)
        vm.start(line: line, userIsWhite: true)

        vm.stepPreviewBackward()

        #expect(vm.previewIndex == 0)
        #expect(vm.canStepPreviewBackward == false)
    }

    @Test("jumpPreview moves directly to a specific move, clamped to the line's bounds")
    func jumpPreviewClampsToBounds() {
        let vm = OpeningTrainerViewModel(defaults: UserDefaults(suiteName: #function)!)
        vm.start(line: line, userIsWhite: true)

        vm.jumpPreview(to: 2)
        #expect(vm.previewIndex == 2)
        #expect(vm.previewMoveUCI == "g1f3")

        vm.jumpPreview(to: 99)
        #expect(vm.previewIndex == line.sanMoves.count - 1)

        vm.jumpPreview(to: -5)
        #expect(vm.previewIndex == 0)
    }

    @Test("resetPreviewToCurrentMove snaps back to wherever the live drill actually is")
    func resetSnapsToLiveMoveCursor() {
        let vm = OpeningTrainerViewModel(defaults: UserDefaults(suiteName: #function)!)
        vm.start(line: line, userIsWhite: true)   // user plays White; moveCursor starts at 0

        vm.stepPreviewForward()
        vm.stepPreviewForward()
        #expect(vm.previewIndex == 2)

        vm.resetPreviewToCurrentMove()
        #expect(vm.previewIndex == vm.moveCursorForDisplay)
    }
}
