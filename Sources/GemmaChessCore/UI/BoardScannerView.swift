//  BoardScannerView.swift
//  ChessCoach Pro feature: photograph a physical chess board and either ask the
//  coach about the resulting position or start a live game from it. The photo
//  is the ONE thing here that touches the network (Gemini vision via
//  chesscoach-gateway's `/api/vision`) — the recognized FEN then drives
//  ChessBoardView's preview and PlayViewModel's game entirely on-device, same
//  as every other position in the app.

import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
    #if os(iOS)
    @State private var showCamera = false
    #endif
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
            let fen = try await ManagedVisionClient.recognizeBoard(imageData: upload)
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

/// Resizes to at most `maxDimension` on the long edge, then re-encodes as
/// JPEG -- backing off quality (and, if still too large, dimension) until
/// the result fits `maxBytes`. 1024px is a Gemini cost lever, not just a
/// payload-size one: Gemini tiles images into ~768x768 chunks and bills
/// per tile, so a board photo (a simple, high-contrast 8x8 grid -- not a
/// texture-heavy image) doesn't need 1600px worth of tiles to read
/// reliably. The backoff loop below is a separate safety net so an
/// unusually large or detailed source photo can never produce a payload
/// that blows past the platform's request-body limit.
private func downscaledJPEG(
    _ data: Data,
    maxDimension: CGFloat = 1024,
    maxBytes: Int = 2_000_000
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
