# Third-party notices

ChessCoach links Stockfish (GPLv3) directly into its app binary. Under GPLv3,
that makes the **whole combined binary** — this app's own Swift source
included — a single GPLv3 work. See `LICENSE` at the repo root for the full
text; this file credits every third-party component that ships in the app.

## Stockfish — GNU General Public License v3

Stockfish is a free and strong UCI chess engine, https://stockfishchess.org.
Copyright (C) 2004-2024 The Stockfish developers.

Compiled from source and linked into this app via
[chesskit-engine](https://github.com/chesskit-app/chesskit-engine). Full
license text: `Sources/GemmaChessCore/Resources/licenses/gplv3.txt` (also
shown in-app under Settings → Open Source Licenses).

## chesskit-swift and chesskit-engine — MIT License

Copyright (c) 2023 ChessKit (https://github.com/chesskit-app).

Chess rules/move-generation and the Stockfish UCI wrapper used by this app.
Full license text: `Sources/GemmaChessCore/Resources/licenses/chesskit-mit.txt`.

## Lichess `chess-openings` database — CC0 1.0 Universal (public domain)

https://github.com/lichess-org/chess-openings — vendored at
`Sources/GemmaChessCore/Resources/eco/`, used for live opening
classification. No attribution is legally required (CC0), credited here as a
courtesy.
