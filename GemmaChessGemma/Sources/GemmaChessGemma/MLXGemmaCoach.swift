//  MLXGemmaCoach.swift
//  Gemma-via-MLX coach backend (U15) — the on-device fallback for devices without
//  Apple Intelligence (iOS 18–25 / older hardware). Implements the same `CoachLLM`
//  protocol as the Foundation Models backend, so the orchestrator can append it:
//
//      CoachOrchestrator(backends: [FoundationModelsCoach(), MLXGemmaCoach()])
//
//  Uses the PROVEN `gemma3n_E2B/E4B_it_lm_4bit` MLX builds (the Gemma-4 4-bit MLX
//  quants have a Per-Layer-Embedding quantization bug as of 2026-06 — see the plan).
//  Kept in a SEPARATE SwiftPM package so the large MLX dependency and the multi-GB
//  model never burden the FM-first device build.

import Foundation
import GemmaChessCore
import MLXLLM
import MLXLMCommon

public actor MLXGemmaCoach: CoachLLM {

    /// Model tier. E2B (~4.5 GB on disk, ~4 GB RAM) is the safe iPhone default;
    /// E4B (~7 GB) suits Macs and high-RAM iPads.
    public enum Tier: Sendable {
        case e2b, e4b
        var configuration: ModelConfiguration {
            switch self {
            case .e2b: return LLMRegistry.gemma3n_E2B_it_lm_4bit
            case .e4b: return LLMRegistry.gemma3n_E4B_it_lm_4bit
            }
        }
    }

    private let tier: Tier
    private let maxTokens: Int
    private let progressHandler: (@Sendable (Double) -> Void)?
    private var container: ModelContainer?

    /// - Parameters:
    ///   - tier: defaults by device RAM (E4B on ≥ ~8 GB, else E2B).
    ///   - maxTokens: generation cap (coaching answers are short).
    ///   - onDownloadProgress: first-run model download progress (0...1).
    public init(
        tier: Tier? = nil,
        maxTokens: Int = 700,
        onDownloadProgress: (@Sendable (Double) -> Void)? = nil
    ) {
        self.tier = tier ?? Self.defaultTier()
        self.maxTokens = maxTokens
        self.progressHandler = onDownloadProgress
    }

    /// E4B on high-RAM devices (Mac / ≥ ~8 GB), E2B otherwise.
    public static func defaultTier() -> Tier {
        ProcessInfo.processInfo.physicalMemory >= 7_500_000_000 ? .e4b : .e2b
    }

    /// MLX runs on Apple Silicon (all modern iPhones/iPads + M-series Macs). Real
    /// readiness — model download + memory — surfaces on first `generate()`.
    public nonisolated var availability: CoachAvailability { .gemma }

    public func generate(system: String, prompt: String, sessionID: String?) async throws -> CoachReply {
        let modelContainer: ModelContainer
        do {
            modelContainer = try await loadModel()
        } catch {
            throw CoachError("Couldn't load the on-device Gemma model: \(error.localizedDescription)")
        }

        var mutableParams = GenerateParameters()
        mutableParams.maxTokens = maxTokens
        mutableParams.temperature = 0.6
        let params = mutableParams

        let input = UserInput(chat: [
            .init(role: .system, content: system),
            .init(role: .user, content: prompt),
        ])

        do {
            let output = try await modelContainer.perform { (context: ModelContext) -> String in
                let lmInput = try await context.processor.prepare(input: input)
                let result = try MLXLMCommon.generate(
                    input: lmInput, parameters: params, context: context
                ) { (_: [Int]) -> GenerateDisposition in .more }
                return result.output
            }
            return CoachReply(answer: output.trimmingCharacters(in: .whitespacesAndNewlines), sessionID: nil)
        } catch {
            throw CoachError("The on-device Gemma model couldn't answer: \(error.localizedDescription)")
        }
    }

    // MARK: private

    private func loadModel() async throws -> ModelContainer {
        if let container { return container }
        // Downloads on first use (resumable) into the Hugging Face cache, then loads.
        // To target Application Support instead, pass a custom `HubApi(downloadBase:)`.
        let handler = progressHandler
        let loaded = try await LLMModelFactory.shared.loadContainer(
            configuration: tier.configuration
        ) { progress in
            handler?(progress.fractionCompleted)
        }
        container = loaded
        return loaded
    }
}
