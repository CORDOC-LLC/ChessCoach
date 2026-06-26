# GemmaChess

A native **iOS + macOS** chess coach: Stockfish-grounded full-game review with a
position-aware conversational coach that runs **fully on-device** — Apple
Foundation Models where available, Gemma 3n (E2B/E4B) via MLX as a fallback, and
engine-only review where no on-device model fits.

A native Swift reimplementation of
[tintins-chess-analysis](https://github.com/Chess-analysis-mcp/tintins-chess-analysis).
The defining contract, inherited from that project: **Stockfish computes; the
model only explains.** The LLM never reasons about chess — it turns pre-computed
engine facts into plain-English coaching, which is what makes a small on-device
model viable.

## Layout

- `Sources/GemmaChessCore/` — the cross-platform core (SwiftPM package).
- `Tests/GemmaChessCoreTests/` — Swift Testing suite.
- `GemmaChessiOS/`, `GemmaChessMac/` — thin Xcode app targets (UI only). *Not yet created.*
- `docs/plans/` — the implementation plan.

## Build & test the core

```bash
swift test
```

## Status

Early scaffolding. Implemented: evaluation math (win%, classification, accuracy,
speed bucketing). See the plan in `docs/plans/` for the full unit breakdown.

## License

To be determined — note the Stockfish (GPLv3) obligation discussed in the plan's
risks before publishing.
