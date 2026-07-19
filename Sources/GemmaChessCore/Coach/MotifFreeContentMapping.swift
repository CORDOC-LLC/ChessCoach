//  MotifFreeContentMapping.swift
//  Maps a `Motifs` key (from `HistoryStore`/`CoachingProfile`'s tactical
//  tagging) to the matching free Lesson/puzzle theme id, so the Weakness
//  Report's named flaw can point directly at a concrete, free next step
//  (plan U7/R1/R9). `Motifs.labels`' keys ("missed_fork", "back_rank", ...)
//  don't match `LessonCatalog`/puzzle theme ids ("fork", "backRankMate", ...)
//  verbatim -- this is a deliberate, hand-authored lookup, not a rename.
//
//  Lesson ids and puzzle theme ids are identical 1:1 for every bundled theme
//  (see `LessonCatalog.swift`), so one mapping serves both "open this Lesson"
//  and "practice this puzzle theme".

public enum MotifFreeContentMapping {
    /// `nil` means no direct free-content pointer exists for that motif --
    /// the Weakness Report simply omits a deep-link row for it rather than
    /// forcing an inaccurate mapping. Every key `Motifs.labels` defines MUST
    /// have an entry here (even if its value is `nil`) -- see
    /// `MotifToFreeContentMappingTests`'s exhaustiveness test, which catches
    /// a future new motif silently having no mapping at all.
    public static let themeID: [String: String?] = [
        "hung_piece": "hangingPiece",
        "pawn_grab": nil,
        "missed_capture": "hangingPiece",
        "missed_fork": "fork",
        "allowed_fork": "fork",
        "allowed_mate": "mateIn1",
        "back_rank": "backRankMate",
        "missed_mate": "mateIn1",
        "time_trouble": nil,
    ]

    /// The free Lesson/puzzle theme id for `motif`, or `nil` if there's no
    /// direct mapping (either because the motif isn't recognized at all, or
    /// because it's deliberately unmapped per `themeID` above).
    public static func themeID(forMotif motif: String) -> String? {
        themeID[motif].flatMap { $0 }
    }
}
