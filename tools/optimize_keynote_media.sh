#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
ASSETS_DIR="assets"

usage() {
  cat <<'USAGE'
Usage:
  tools/optimize_keynote_media.sh --report
  tools/optimize_keynote_media.sh --convert
  tools/optimize_keynote_media.sh --patch-json
  tools/optimize_keynote_media.sh --convert --patch-json

What it does:
  --report      Show GIF/MP4 counts and the largest GIF files.
  --convert     Convert every GIF under assets/ to a same-path .mp4 file.
  --patch-json  Update Keynote JSON/JSONP references from .gif to .mp4.

Notes:
  - Original GIF files are kept.
  - JSON/JSONP files are backed up once as *.bak before patching.
  - MP4 settings target smooth local presentation playback, not archival quality.
USAGE
}

report() {
  echo "Media summary:"
  find "$ASSETS_DIR" -type f \( -name '*.gif' -o -name '*.mp4' \) -print0 |
    xargs -0 du -k |
    awk '{sum+=$1; n++} END {printf "  all dynamic media: %d files, %.1f MB\n", n, sum/1024}'

  find "$ASSETS_DIR" -type f -name '*.gif' -print0 |
    xargs -0 du -k |
    awk '{sum+=$1; n++} END {printf "  GIF: %d files, %.1f MB\n", n, sum/1024}'

  find "$ASSETS_DIR" -type f -name '*.mp4' -print0 |
    xargs -0 du -k |
    awk '{sum+=$1; n++} END {printf "  MP4: %d files, %.1f MB\n", n, sum/1024}'

  echo
  echo "Largest GIFs:"
  find "$ASSETS_DIR" -type f -name '*.gif' -print0 |
    xargs -0 du -h |
    sort -hr |
    head -20
}

convert_gifs() {
  local converted=0
  local skipped=0

  while IFS= read -r gif; do
    local mp4="${gif//.gif/.mp4}"
    if [[ -s "$mp4" && "$mp4" -nt "$gif" ]]; then
      skipped=$((skipped + 1))
      continue
    fi

    echo "Converting: $gif"
    ffmpeg -nostdin -hide_banner -loglevel error -y \
      -i "$gif" \
      -movflags +faststart \
      -pix_fmt yuv420p \
      -vf "fps=24,scale='trunc(iw/2)*2:trunc(ih/2)*2'" \
      -c:v libx264 \
      -preset veryfast \
      -crf 28 \
      "$mp4"
    converted=$((converted + 1))
  done < <(find "$ASSETS_DIR" -type f -name '*.gif')

  echo "Converted $converted GIF(s); skipped $skipped already-fresh MP4(s)."
}

patch_json() {
  local patched=0

  while IFS= read -r file; do
    if [[ ! -f "$file.bak" ]]; then
      cp "$file" "$file.bak"
    fi

    perl -0pi -e 's/\.gif/\.mp4/g' "$file"
    patched=$((patched + 1))
  done < <(find "$ASSETS_DIR" -type f \( -name '*.json' -o -name '*.jsonp' \))

  echo "Patched $patched JSON/JSONP file(s). Backups are next to the originals as *.bak."
}

do_report=false
do_convert=false
do_patch=false

if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

for arg in "$@"; do
  case "$arg" in
    --report) do_report=true ;;
    --convert) do_convert=true ;;
    --patch-json) do_patch=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage; exit 2 ;;
  esac
done

if [[ "$do_report" == true ]]; then
  report
fi

if [[ "$do_convert" == true ]]; then
  convert_gifs
fi

if [[ "$do_patch" == true ]]; then
  patch_json
fi
