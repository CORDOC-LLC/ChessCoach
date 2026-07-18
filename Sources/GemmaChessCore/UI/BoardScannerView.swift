//  BoardScannerView.swift
//  ChessCoach Pro feature: photograph a physical chess board and either ask the
//  coach about the resulting position or start a live game from it. The photo
//  is the ONE thing here that touches the network (Gemini vision via
//  chesscoach-gateway's `/api/vision`) — the recognized FEN then drives
//  ChessBoardView's preview and PlayViewModel's game entirely on-device, same
//  as every other position in the app.

import SwiftUI
import PhotosUI
import ChessKit
#if os(iOS)
import UIKit
#endif

/// What the scanner is doing right now.
private enum ScanPhase: Equatable {
    case picking
    case recognizing
    /// The scan came back; the user is checking/correcting the position.
    case reviewing
    /// The user confirmed the position looks right; show Ask/Play options.
    case confirmed
    case failed(String)
}

/// What tapping a board square does while reviewing.
private enum ReviewTool: Equatable {
    /// No tool armed: first tap picks up a piece, second tap drops it.
    case move
    /// A palette piece is armed: every tap stamps that piece.
    case place(kind: Piece.Kind, color: Piece.Color)
    /// Eraser armed: every tap empties the square.
    case erase
}

/// What the user wants to do with a recognized position.
private enum ScanIntent: Hashable {
    case ask, play
}

public struct BoardScannerView: View {
    var onStartGame: (_ fen: String, _ asWhite: Bool) -> Void

    @State private var phase: ScanPhase = .picking
    @State private var photoItem: PhotosPickerItem?
    #if os(iOS)
    @State private var showCamera = false
    #endif
    @State private var intent: ScanIntent = .ask
    @State private var question = ""
    @State private var answer: String?
    @State private var isAsking = false
    @State private var sideIsWhite = true
    /// The live, possibly-hand-corrected position -- distinct from
    /// `scannedFEN` so "Reset to scanned" can discard edits. Vision
    /// recognition isn't always exact (lighting, piece style, angle), so
    /// the user reviews and corrects the board before confirming.
    @State private var editedFEN = ""
    /// The FEN exactly as the vision model returned it.
    @State private var scannedFEN = ""
    @State private var tool: ReviewTool = .move
    /// The square whose piece is "picked up" while the move tool is active.
    @State private var pickedSquare: Square?
    private let coach = CoachOrchestrator()

    public init(onStartGame: @escaping (_ fen: String, _ asWhite: Bool) -> Void) {
        self.onStartGame = onStartGame
    }

    public var body: some View {
        ZStack {
            Form {
                switch phase {
                case .picking, .recognizing:
                    pickerSection
                case .reviewing:
                    reviewSection
                case .confirmed:
                    confirmedSection
                    intentSection(fen: editedFEN)
                case .failed(let message):
                    pickerSection
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Scan a Board")
        /// Prevent screen from auto-locking while recognizing — Gemini
        /// vision can take 10+ seconds on slow connections, and a blank
        /// screen mid-recognition looks like a hang.
        .onAppear { updateIdleTimer() }
        .onChange(of: phase) { _, _ in updateIdleTimer() }
        #if os(iOS)
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
    }

    private var pickerSection: some View {
        let isRecognizing = phase == .recognizing
        return Section {
            #if os(iOS)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    Label(isRecognizing ? "Reading the board…" : "Take a photo",
                          systemImage: "camera.fill")
                }
                .disabled(isRecognizing)
            }
            #endif
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(isRecognizing ? "Reading the board…" : "Choose a photo",
                      systemImage: "photo.on.rectangle")
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
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView(
                onCapture: { data in
                    showCamera = false
                    Task { await recognize(data: data) }
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        #endif
    }

    /// The review step: the user checks the scanned board against their
    /// real one and fixes anything the vision model got wrong -- move a
    /// piece (tap it, tap where it goes), add pieces from the palette, or
    /// erase -- then explicitly confirms before playing or asking the
    /// coach. No vision model reads every real photo perfectly, so this
    /// step is what makes the feature trustworthy.
    private var reviewSection: some View {
        Section {
            Text(reviewInstruction)
                .font(.footnote)
                .foregroundStyle(.secondary)

            ChessBoardView(
                fen: editedFEN, orientation: .white, arrows: [], lastMove: nil,
                selectedSquare: pickedSquare, legalDots: [],
                onTapSquare: handleReviewTap
            )
            .aspectRatio(1, contentMode: .fit)
            .listRowInsets(EdgeInsets())

            palette

            Button {
                editedFEN = FENBoardEditor.rotated180(fen: editedFEN)
                pickedSquare = nil
            } label: {
                Label("Rotate board 180°", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
            }
            .font(.footnote)

            HStack {
                if editedFEN != scannedFEN {
                    Button("Reset to scanned") {
                        editedFEN = scannedFEN
                        tool = .move
                        pickedSquare = nil
                    }
                    .font(.footnote)
                }
                Spacer()
                Button("Scan a different photo") {
                    phase = .picking; photoItem = nil; answer = nil
                    tool = .move; pickedSquare = nil
                }
                .font(.footnote)
            }

            Button {
                tool = .move
                pickedSquare = nil
                phase = .confirmed
            } label: {
                Text("Looks right — continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } header: {
            Text("Check the board")
        } footer: {
            Text("Compare with your real board and fix any differences before continuing.")
        }
    }

    private var reviewInstruction: String {
        switch tool {
        case .move:
            if pickedSquare != nil {
                return "Now tap the square where that piece should go."
            }
            return "To move a piece, tap it, then tap its square. To add a piece, pick one below, then tap the board."
        case .place(let kind, let color):
            return "Tap any square to place \(FENBoardEditor.glyph(kind: kind, color: color)). Tap it below again when done."
        case .erase:
            return "Tap any square to clear it. Tap ✕ below again when done."
        }
    }

    /// One tap handler for all three tools. Move: pick up, then drop
    /// (dropping onto an occupied square replaces that piece; tapping the
    /// picked square again puts it back). Place/erase: stamp every tap.
    private func handleReviewTap(_ square: Square) {
        switch tool {
        case .place(let kind, let color):
            editedFEN = FENBoardEditor.settingSquare(square, to: (kind, color), inFEN: editedFEN)
        case .erase:
            editedFEN = FENBoardEditor.settingSquare(square, to: nil, inFEN: editedFEN)
        case .move:
            if let from = pickedSquare {
                if from != square, let piece = FENBoardEditor.piece(at: from, inFEN: editedFEN) {
                    editedFEN = FENBoardEditor.settingSquare(from, to: nil, inFEN: editedFEN)
                    editedFEN = FENBoardEditor.settingSquare(square, to: piece, inFEN: editedFEN)
                }
                pickedSquare = nil
            } else if FENBoardEditor.piece(at: square, inFEN: editedFEN) != nil {
                pickedSquare = square
            }
        }
    }

    /// Piece palette: 6 white, 6 black, and an eraser. Tapping one arms it
    /// as a stamp (highlighted); tapping it again returns to move mode.
    private var palette: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Piece.Kind.allCases, id: \.self) { kind in
                    paletteButton(kind: kind, color: .white)
                }
                ForEach(Piece.Kind.allCases, id: \.self) { kind in
                    paletteButton(kind: kind, color: .black)
                }
                paletteToggle(isActive: tool == .erase, activate: { tool = .erase }) {
                    Text("✕").font(.title3).frame(width: 40, height: 40)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func paletteButton(kind: Piece.Kind, color: Piece.Color) -> some View {
        paletteToggle(
            isActive: tool == .place(kind: kind, color: color),
            activate: { tool = .place(kind: kind, color: color) }
        ) {
            Text(FENBoardEditor.glyph(kind: kind, color: color))
                .font(.title2)
                .frame(width: 40, height: 40)
        }
    }

    @ViewBuilder
    private func paletteToggle<Label: View>(
        isActive: Bool,
        activate: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        let button = Button {
            pickedSquare = nil
            if isActive { tool = .move } else { activate() }
        } label: {
            label()
        }
        if isActive {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    /// The confirmed position: a small read-only preview with a way back
    /// into editing, followed by the Ask/Play options.
    private var confirmedSection: some View {
        Section {
            ChessBoardView(
                fen: editedFEN, orientation: .white, arrows: [], lastMove: nil,
                selectedSquare: nil, legalDots: [], onTapSquare: { _ in }
            )
            .aspectRatio(1, contentMode: .fit)
            .listRowInsets(EdgeInsets())
            .padding(.top)

            HStack {
                Button("Edit position") { phase = .reviewing }
                    .font(.footnote)
                Spacer()
                Button("Scan a different photo") {
                    phase = .picking; photoItem = nil; answer = nil
                }
                .font(.footnote)
            }
        } header: {
            Text("Your position")
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

    #if os(iOS)
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = (phase == .recognizing)
    }
    #else
    private func updateIdleTimer() {}
    #endif

    private func recognize(_ item: PhotosPickerItem) async {
        guard let data = (try? await item.loadTransferable(type: Data.self)) ?? nil else {
            phase = .failed("Couldn't load that photo. Try another.")
            return
        }
        await recognize(data: data)
    }

    /// Downscales/recompresses the photo before sending — a full-resolution
    /// camera photo (often 10+ MB, more once base64-encoded) blows past
    /// Vercel's ~4.5 MB serverless request-body limit (HTTP 413,
    /// FUNCTION_PAYLOAD_TOO_LARGE) -- a hard platform ceiling the gateway
    /// can't raise. Never uploads the raw, undownscaled photo: if
    /// `downscaledJPEG` can't produce a small-enough image (undecodable
    /// data, or still oversized even at its smallest attempt), fail with a
    /// clear message instead of silently sending something that will 413.
    private func recognize(data: Data) async {
        phase = .recognizing
        answer = nil
        guard let upload = downscaledJPEG(data) else {
            phase = .failed("Couldn't process that photo. Try another, ideally a clear top-down shot.")
            return
        }
        do {
            var fen = try await ManagedVisionClient.recognizeBoard(imageData: upload)
            // Photos taken from Black's side often come back 180°-rotated
            // (the model reads the nearest edge as rank 1). When White's
            // pieces clearly sit in the top half, un-rotate before showing --
            // the user can still hit "Rotate board 180°" if we guessed wrong.
            if FENBoardEditor.looksRotated(fen: fen) {
                fen = FENBoardEditor.rotated180(fen: fen)
            }
            editedFEN = fen
            scannedFEN = fen
            tool = .move
            pickedSquare = nil
            phase = .reviewing
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

/// Resizes to at most `maxDimension` on the long edge, then re-encodes as
/// JPEG -- backing off quality (and, if still too large, dimension) until
/// the result fits `maxBytes`. 1600px, not the smaller 1024px tried
/// earlier: recognition accuracy on real photos (mis-set pieces) matters
/// far more than the Gemini tile/token savings a lower resolution bought --
/// getting the position wrong makes the feature useless regardless of cost.
/// The backoff loop below is a separate safety net so an unusually large or
/// detailed source photo can never produce a payload that blows past the
/// platform's request-body limit.
private func downscaledJPEG(
    _ data: Data,
    maxDimension: CGFloat = 1600,
    maxBytes: Int = 3_000_000
) -> Data? {
    #if canImport(UIKit)
    guard let image = UIImage(data: data) else { return nil }
    var dimension = maxDimension
    for _ in 0..<3 {
        let size = image.size
        let scale = min(1, dimension / max(size.width, size.height))
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        for quality: CGFloat in [0.7, 0.5, 0.3] {
            if let jpeg = resized.jpegData(compressionQuality: quality), jpeg.count <= maxBytes {
                return jpeg
            }
        }
        dimension /= 2
    }
    return nil
    #elseif canImport(AppKit)
    guard let image = NSImage(data: data) else { return nil }
    var dimension = maxDimension
    for _ in 0..<3 {
        let size = image.size
        let scale = min(1, dimension / max(size.width, size.height))
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        for quality: CGFloat in [0.7, 0.5, 0.3] {
            if let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]),
               jpeg.count <= maxBytes {
                return jpeg
            }
        }
        dimension /= 2
    }
    return nil
    #else
    return nil
    #endif
}

#if os(iOS)
/// Wraps `UIImagePickerController`'s camera source — SwiftUI has no native
/// camera-capture view (PhotosPicker only reaches the library).
private struct CameraCaptureView: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCaptureView
        init(_ parent: CameraCaptureView) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                parent.onCapture(data)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}
#endif
