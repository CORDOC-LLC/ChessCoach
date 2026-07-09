#!/usr/bin/env python3
# Curates PuzzleData/packs/*.json from the decompressed Lichess puzzle CSV.
# See PuzzleData/README.md for the source, license (CC0), and format.
#
# Usage (from repo root):
#   curl -O https://database.lichess.org/lichess_db_puzzle.csv.zst
#   unzstd lichess_db_puzzle.csv.zst
#   python3 scripts/curate-puzzles.py

import csv, json, heapq, sys, os

IN_PATH = "lichess_db_puzzle.csv"
OUT_DIR = "PuzzleData/packs"
os.makedirs(OUT_DIR, exist_ok=True)

THEMES = [
    "fork", "pin", "skewer", "discoveredAttack", "doubleCheck",
    "backRankMate", "smotheredMate", "hangingPiece", "trappedPiece",
    "sacrifice", "deflection", "attraction", "clearance", "xRayAttack",
    "zugzwang", "mateIn1", "mateIn2", "mateIn3", "endgame", "opening",
]

BUCKETS = [(0, 1200), (1200, 1600), (1600, 2000), (2000, 9999)]
CAP_PER_BUCKET = 50  # -> up to 200 puzzles per theme pack

# heaps[theme][bucket_index] = min-heap of (popularity, counter, row_dict)
heaps = {t: [[] for _ in BUCKETS] for t in THEMES}
counter = 0

csv.field_size_limit(sys.maxsize)
with open(IN_PATH, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        try:
            rating = int(row["Rating"])
            popularity = int(row["Popularity"])
        except (KeyError, ValueError):
            continue
        theme_set = set(row["Themes"].split())
        bucket_idx = None
        for i, (lo, hi) in enumerate(BUCKETS):
            if lo <= rating < hi:
                bucket_idx = i
                break
        if bucket_idx is None:
            continue
        for t in THEMES:
            if t not in theme_set:
                continue
            h = heaps[t][bucket_idx]
            counter += 1
            entry = (popularity, counter, {
                "id": row["PuzzleId"],
                "fen": row["FEN"],
                "moves": row["Moves"].split(),
                "rating": rating,
                "themes": sorted(theme_set),
            })
            if len(h) < CAP_PER_BUCKET:
                heapq.heappush(h, entry)
            elif entry[0] > h[0][0]:
                heapq.heapreplace(h, entry)

catalog = []
for t in THEMES:
    puzzles = []
    for bucket in heaps[t]:
        puzzles.extend(item[2] for item in bucket)
    puzzles.sort(key=lambda p: p["rating"])
    out_path = os.path.join(OUT_DIR, f"{t}.json")
    with open(out_path, "w", encoding="utf-8") as out:
        json.dump({"theme": t, "puzzles": puzzles}, out, separators=(",", ":"))
    size_kb = os.path.getsize(out_path) / 1024
    catalog.append({
        "theme": t,
        "count": len(puzzles),
        "minRating": puzzles[0]["rating"] if puzzles else None,
        "maxRating": puzzles[-1]["rating"] if puzzles else None,
        "file": f"{t}.json",
        "sizeKB": round(size_kb, 1),
    })
    print(f"{t}: {len(puzzles)} puzzles, {size_kb:.1f} KB")

with open(os.path.join(os.path.dirname(OUT_DIR), "catalog.json"), "w", encoding="utf-8") as out:
    json.dump({"themes": catalog}, out, indent=2)

print("Done.")
