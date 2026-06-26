//  FoundationModelsCoach.swift
//  Apple Foundation Models backend (U14) — the primary coach on iOS/macOS 26
//  Apple-Intelligence devices. Grounded summarization of pre-built engine facts,
//  exactly the workload the on-device model is designed for.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public final class FoundationModelsCoach: CoachLLM {

    public init() {}

    public var availability: CoachAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .foundationModels
            case .unavailable(let reason):
                return .unavailable(reason: Self.describe(reason))
            @unknown default:
                return .unavailable(reason: "Foundation Models unavailable")
            }
        }
        #endif
        return .unavailable(reason: "Requires iOS/macOS 26 with Apple Intelligence")
    }

    public func generate(system: String, prompt: String, sessionID: String?) async throws -> CoachReply {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            let session = LanguageModelSession(instructions: system)
            do {
                let response = try await session.respond(to: prompt)
                return CoachReply(answer: response.content, sessionID: nil)
            } catch {
                throw CoachError(Self.friendly(error))
            }
        }
        #endif
        throw CoachError("Foundation Models is unavailable on this device.")
    }

    // MARK: helpers

    #if canImport(FoundationModels)
    @available(iOS 26, macOS 26, *)
    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to use the on-device coach."
        case .modelNotReady:
            return "The on-device model is still downloading. Try again shortly."
        @unknown default:
            return "Foundation Models is unavailable."
        }
    }
    #endif

    private static func friendly(_ error: Error) -> String {
        let text = String(describing: error).lowercased()
        if text.contains("guardrail") {
            return "The on-device model declined to answer that. Try rephrasing."
        }
        if text.contains("context") || text.contains("exceeded") {
            return "The conversation got too long for the on-device model. Start a fresh question."
        }
        if text.contains("language") || text.contains("locale") {
            return "The on-device model doesn't support this language yet."
        }
        return "The on-device coach couldn't answer: \(error.localizedDescription)"
    }
}
