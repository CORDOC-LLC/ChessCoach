# Puzzle data

Curated from the [Lichess puzzle database](https://database.lichess.org/#puzzles)
(`lichess_db_puzzle.csv.zst`, ~6.06M puzzles), released under
**CC0 1.0 Universal** — public domain, no attribution required, free for any
use including commercial.

## Why this isn't bundled into the app

The full Lichess database is ~1.1GB uncompressed. Rather than ship any of it
inside the app binary, ChessCoach downloads a theme's pack on demand the first
time a user opens it (see `ManagedVisionClient`-style pattern: a plain HTTPS
GET, cached to disk after the first download). This is a **free** feature —
no entitlement, no token cost, just static JSON — so it's hosted as GitHub
Release assets on this public repo rather than routed through the paid
`chesscoach-gateway` backend.

## Format

- `catalog.json` — the theme list: id, puzzle count, rating range, file name,
  size. This is what `PuzzlesView` shows before any pack is downloaded.
- `packs/<theme>.json` — `{ "theme": "...", "puzzles": [...] }`, each puzzle:
  `{ "id", "fen", "moves" (UCI, opponent's setup move first), "rating",
  "themes" }`.

## Curation method

`scripts/curate-puzzles.py` streams the full CSV once, buckets puzzles by
rating (`<1200`, `1200-1600`, `1600-2000`, `2000+`) per theme, and keeps the
top 50-by-popularity in each bucket — so every pack has ~200 puzzles spread
across skill levels, not just whatever the most popular *overall* happened to
be. 20 themes are curated for now: fork, pin, skewer, discoveredAttack,
doubleCheck, backRankMate, smotheredMate, hangingPiece, trappedPiece,
sacrifice, deflection, attraction, clearance, xRayAttack, zugzwang, mateIn1,
mateIn2, mateIn3, endgame, opening.

To regenerate: download `lichess_db_puzzle.csv.zst` from
`database.lichess.org`, decompress, and run
`python3 scripts/curate-puzzles.py` against it.
