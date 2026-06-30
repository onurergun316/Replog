#!/bin/bash
#
# build-exercise-db.sh — one-shot dev tool (not shipped in the app).
#
# Builds the on-device exercise catalog that Replog bundles:
#   1. Copies the Free Exercise DB JSON into Resources/exercises.json
#   2. Compresses every demo photo (1746 jpgs, ~101 MB) to HEIC (~520px, q50),
#      landing the whole image set at ≈20 MB — the owner's acceptable ceiling.
#
# Source DB lives one level above the repo (not committed):
#   ../../free-exercise-db-main   (relative to this script's repo)
#
# Usage:  ./Replog/Scripts/build-exercise-db.sh
# Re-runnable: skips images already converted.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo root = .../Replog (the Xcode project dir). Script is at Replog/Replog/Scripts.
RES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/Resources"
SRC_DB="$(cd "$SCRIPT_DIR/../../.." && pwd)/free-exercise-db-main"

IMG_SRC="$SRC_DB/exercises"
IMG_DST="$RES_DIR/ExerciseImages"
JSON_SRC="$SRC_DB/dist/exercises.json"

MAX_DIM=420      # longest-side pixels
QUALITY=42       # HEIC quality (0-100)

if [[ ! -d "$IMG_SRC" ]]; then
  echo "ERROR: source DB not found at $IMG_SRC" >&2
  exit 1
fi

mkdir -p "$RES_DIR" "$IMG_DST"

echo "==> Copying exercises.json"
cp "$JSON_SRC" "$RES_DIR/exercises.json"

echo "==> Compressing images ($MAX_DIM px, HEIC q$QUALITY) — parallel"
export IMG_SRC IMG_DST MAX_DIM QUALITY

# Convert one image: arg = absolute source jpg path.
# Output uses FLAT, globally-unique names "<id>__<n>.heic" (no subdirectories) because
# Xcode flattens synchronized-group resources into the bundle root — nested same-named
# files (every exercise has 0.jpg/1.jpg) would otherwise collide. The resolver in
# ExerciseImageView reconstructs this name from the JSON image path.
convert_one() {
  local src="$1"
  local rel="${src#"$IMG_SRC"/}"            # e.g. Battling_Ropes/0.jpg
  local flat="${rel//\//__}"                # e.g. Battling_Ropes__0.jpg
  local out="$IMG_DST/${flat%.jpg}.heic"    # e.g. .../Battling_Ropes__0.heic
  [[ -f "$out" ]] && return 0               # already done
  sips -Z "$MAX_DIM" -s format heic -s formatOptions "$QUALITY" "$src" --out "$out" >/dev/null 2>&1 || {
    echo "WARN: failed $rel" >&2
    return 0
  }
}
export -f convert_one

find "$IMG_SRC" -name '*.jpg' -print0 \
  | xargs -0 -P 8 -I{} bash -c 'convert_one "$@"' _ {}

COUNT=$(find "$IMG_DST" -name '*.heic' | wc -l | tr -d ' ')
SIZE=$(du -sh "$IMG_DST" | cut -f1)
echo "==> Done: $COUNT HEIC images, total $SIZE in $IMG_DST"
