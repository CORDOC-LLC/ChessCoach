//  MotifToFreeContentMappingTests.swift
//  Covers MotifFreeContentMapping (plan U7): every motif Motifs.labels
//  defines has an explicit entry (exhaustiveness -- catches a future new
//  motif silently having no deep-link target), and every non-nil mapped
//  theme id is a real Lesson id (so a deep-link never points at nothing).

import Testing
@testable import GemmaChessCore

@Suite("MotifFreeContentMapping")
struct MotifToFreeContentMappingTests {

    @Test("every motif Motifs.labels defines has an explicit mapping entry")
    func everyMotifHasAnEntry() {
        for motif in Motifs.labels.keys {
            #expect(
                MotifFreeContentMapping.themeID.keys.contains(motif),
                "motif \(motif) has no entry in MotifFreeContentMapping.themeID"
            )
        }
    }

    @Test("every non-nil mapped theme id is a real Lesson id")
    func everyMappedThemeIsARealLesson() {
        let lessonIDs = Set(LessonCatalog.allLessons.map(\.theme))
        for (motif, themeID) in MotifFreeContentMapping.themeID {
            guard let themeID else { continue }
            #expect(lessonIDs.contains(themeID), "motif \(motif) maps to unknown theme \(themeID)")
        }
    }

    @Test("themeID(forMotif:) unwraps a mapped value and returns nil for an unmapped or unknown motif")
    func lookupHelper() {
        #expect(MotifFreeContentMapping.themeID(forMotif: "missed_fork") == "fork")
        #expect(MotifFreeContentMapping.themeID(forMotif: "pawn_grab") == nil)
        #expect(MotifFreeContentMapping.themeID(forMotif: "not_a_real_motif") == nil)
    }
}
