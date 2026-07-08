//  BoardScannerView.swift
//  ChessCoach Pro feature: photograph a physical chess board and either ask the
//  coach about the resulting position or start a live game from it. The photo
//  is the ONE thing here that touches the network (Gemini vision via
//  chesscoach-gateway's `/api/vision`) — the recognized FEN then drives
//  ChessBoardView's preview and PlayViewModel's game entirely on-device, same
//  as every other position in the app.

import SwiftUI
import PhotosUI

/// What the scanner is doing right now.
private enum ScanPhase: Equatable {
    case picking
    case recognizing
    case recognized(fen: String)
    case failed(String)
}

/// What the user wants to do with a recognized position.
private enum ScanIntent: Hashable {
    case ask, play
}

public struct BoardScannerView: View {
    var onStartGame: (_ fen: String, _ asWhite: Bool) -> Void

    @State private var phase: ScanPhase = .picking
    @State private var photoItem: PhotosPickerItem?
    @State private var intent: ScanIntent = .ask
    @State private var question = ""
    @State private var answer: String?
    @State private var isAsking = false
    @State private var sideIsWhite = true
    private let coach = CoachOrchestrator()

    public init(onStartGame: @escaping (_ fen: String, _ asWhite: Bool) -> Void) {
        self.onStartGame = onStartGame
    }

    public var body: some View {
        Form {
            switch phase {
            case .picking, .recognizing:
                pickerSection
            case .recognized(let fen):
                previewSection(fen: fen)
                intentSection(fen: fen)
            case .failed(let message):
                pickerSection
                Section { Text(message).foregroundStyle(.red) }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Scan a Board")
    }

    private var pickerSection: some View {
        let isRecognizing = phase == .recognizing
        return Section {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(isRecognizing ? "Reading the board…" : "Choose a photo",
                      systemImage: "camera.viewfinder")
            }
            .disabled(isRecognizing)
            if isRecognizing {
                ProgressView().frame(maxWidth: .infinity)
            }
            Text("Works best with a clear, top-down shot of the whole board.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("ChessCoach Pro")
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await recognize(newItem) }
        }
    }

    private func previewSection(fen: String) -> some View {
        Section("Recognized position") {
            ChessBoardView(
                fen: fen, orientation: .white, arrows: [], lastMove: nil,
                selectedSquare: nil, legalDots: [], onTapSquare: nil
            )
            .aspectRatio(1, contentMode: .fit)
            .listRowInsets(EdgeInsets())
            .padding()
            Button("Scan a different photo") {
                phase = .picking; photoItem = nil; answer = nil
            }
            .font(.footnote)
        }
    }

    @ViewBuilder
    private func intentSection(fen: String) -> some View {
        Section {
            Picker("What next?", selection: $intent) {
                Text("Ask about it").tag(ScanIntent.ask)
                Text("Start a game").tag(ScanIntent.play)
            }
            .pickerStyle(.segmented)
        }
        switch intent {
        case .ask:
            askSection(fen: fen)
        case .play:
            playSection(fen: fen)
        }
    }

    private func askSection(fen: String) -> some View {
        Section("Ask the coach") {
            TextField("e.g. \"How can I checkmate in 2?\"", text: $question, axis: .vertical)
                .lineLimit(1...4)
            Button("Ask") { Task { await ask(fen: fen) } }
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAsking)
            if isAsking {
                ProgressView().frame(maxWidth: .infinity)
            } else if let answer {
                Text(answer.asCoachMarkdown)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
    }

    private func playSection(fen: String) -> some View {
        Section("Start a game from here") {
            Picker("You play", selection: $sideIsWhite) {
                Text("White").tag(true)
                Text("Black").tag(false)
            }
            .pickerStyle(.segmented)
            Button("Start playing") { onStartGame(fen, sideIsWhite) }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Actions

    private func recognize(_ item: PhotosPickerItem) async {
        phase = .recognizing
        answer = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                phase = .failed("Couldn't load that photo. Try another.")
                return
            }
            let fen = try await ManagedVisionClient.recognizeBoard(imageData: data)
            phase = .recognized(fen: fen)
        } catch let e as BoardRecognitionFailure {
            phase = .failed(e.reason)
        } catch let e as CoachError {
            phase = .failed(e.message)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func ask(fen: String) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isAsking else { return }
        isAsking = true
        defer { isAsking = false }
        do {
            let reply = try await coach.answer(question: q, fen: fen)
            answer = reply.answer
        } catch let e as CoachError {
            answer = e.message
        } catch {
            answer = error.localizedDescription
        }
    }
}
