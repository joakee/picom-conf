#!/usr/bin/env bash
# Regenerates monitors.conf from the current xrandr layout, for lock.glsl's
# per-monitor shader defines (see picom.conf's i3lock shader rule).
set -o errexit -o nounset -o pipefail

OUT="$(dirname "$(readlink -f "$0")")/monitors.conf"
TMP="$(mktemp "${OUT}.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

DISPLAY_RE="([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)"
rects=()

while read -r line; do
  if [[ $line == *" connected"* ]] && [[ $line =~ $DISPLAY_RE ]]; then
    width=${BASH_REMATCH[1]}
    height=${BASH_REMATCH[2]}
    x=${BASH_REMATCH[3]}
    y=${BASH_REMATCH[4]}
    rects+=("vec4($x.0, $y.0, $width.0, $height.0)")
  fi
done < <(xrandr --query)

if [[ ${#rects[@]} -eq 0 ]]; then
  echo "generate-monitor-defines: no connected monitors found via xrandr, leaving monitors.conf untouched" >&2
  exit 0
fi

joined=$(IFS=,; echo "${rects[*]}")

{
  printf 'NUM_MONITORS = "%d";\n' "${#rects[@]}"
  printf 'MONITOR_RECTS = "vec4[%d](%s)";\n' "${#rects[@]}" "$joined"
} > "$TMP"

mv -f "$TMP" "$OUT"
