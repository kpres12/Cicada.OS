#!/usr/bin/env bash
# Thumbnail cache for MAGI-04. Runs on every open of the pattern bay, because
# the wallpaper directory belongs to the user and changes underneath us.
#
# Full-size decodes in the bay would stall the compositor on the MBA-class
# prototype the moment the row scrolled, so plates are always drawn from a
# height-500 thumbnail, never the original.
set -euo pipefail

CONFIG="${1:?usage: cache.sh <shell-dir>}/config.json"
[[ -r "${CONFIG}" ]] || exit 0

wallpaper_path="$(jq -r '.wallpaper_path' "${CONFIG}")"
cache_path="$(jq -r '.cache_path' "${CONFIG}")"
batch="$(jq -r '.cache_batch_size // 4' "${CONFIG}")"

[[ -d "${wallpaper_path}" ]] || exit 0
mkdir -p "${cache_path}"

# ImageMagick 7 ships `magick`; 6 ships `convert`. Arch is on 7, but the
# fallback costs one line and keeps this working on an older install layer.
if command -v magick >/dev/null 2>&1; then
  thumb() { magick "$1" -thumbnail x500 -strip -quality 85 "$2"; }
elif command -v convert >/dev/null 2>&1; then
  thumb() { convert "$1" -thumbnail x500 -strip -quality 85 "$2"; }
else
  exit 0
fi

# Drop stale thumbnails for plates that are no longer in the bay. Without this
# the cache only ever grows, and deleted wallpapers keep showing up.
shopt -s nullglob
for cached in "${cache_path}"/*; do
  [[ -f "${cached}" ]] || continue
  if [[ ! -f "${wallpaper_path}/$(basename "${cached}")" ]]; then
    rm -f -- "${cached}"
  fi
done

while IFS= read -r -d '' img; do
  out="${cache_path}/$(basename "${img}")"

  # Regenerate when the source is newer, not only when the thumb is missing —
  # otherwise editing a wallpaper in place leaves the old plate on screen.
  if [[ -f "${out}" && "${out}" -nt "${img}" ]]; then
    continue
  fi

  thumb "${img}" "${out}" 2>/dev/null &

  if (( batch > 0 )); then
    while (( $(jobs -rp | wc -l) >= batch )); do
      wait -n
    done
  fi
done < <(find "${wallpaper_path}" -maxdepth 1 -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0)

wait
