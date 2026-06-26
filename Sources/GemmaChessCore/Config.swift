//  Config.swift
//  Tunable constants, ported from the source project's `server/config.py`.
//  On-device there is no environment layer; these are the built-in defaults
//  (Settings, U21, overrides the user-facing ones at runtime).

import Foundation

public enum GCConfig {
    /// Depth for on-demand single-position analysis.
    public static let defaultDepth = 18
    /// Depth for the full-game sweep (lower, to keep long games fast).
    public static let sweepDepth = 16
    /// Signed-cp magnitude used to represent a forced mate.
    public static let mateScoreCp = 10_000
    /// Engine search threads.
    public static let engineThreads = 2
    /// Engine transposition hash (MB).
    public static let engineHashMB = 128
}
