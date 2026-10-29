#!/usr/bin/env bash
# Launch the project's established HD6309 / 2MB EOU stack with optional sound cart.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mame="${MAME_BIN:-/Applications/Emulators/Ample.app/Contents/MacOS/mame64}"
img="$root/emulator/images"
roms="${MAME_ROMPATH:-$HOME/Library/Application Support/Ample/roms}"
bridge="${MCP_BRIDGE:-/Volumes/SEDONA/Projects/CoCo3_MCP_Server_NOS9/MCP/scripts/bridge.lua}"
mode="${1:-base}"
if [ "$#" -gt 0 ]; then shift; fi
with_mcp=0
if [ "${1:-}" = "--mcp" ]; then
  with_mcp=1
  shift
fi
if [ "$#" -gt 0 ]; then
  echo "Usage: bash scripts/run-mame.sh [base|psg|gmc] [--mcp]" >&2
  exit 2
fi
if [ ! -x "$mame" ] && ! command -v "$mame" >/dev/null 2>&1; then
  echo "MAME binary missing: $mame" >&2
  exit 1
fi
if [ ! -f "$img/63EMU.DSK" ] || [ ! -f "$img/eou-working.vhd" ]; then
  echo "First run: bash scripts/setup-mame.sh" >&2
  exit 1
fi
args=(coco3h -ramsize 2M -window -skip_gameinfo
      -flop1 "$img/63EMU.DSK" -hard1 "$img/eou-working.vhd"
      -ext multi -ext:multi:slot4 fdc)
if [ -d "$roms" ]; then
  args+=(-rompath "$roms")
fi
if [ -f "$img/chiptunes-test.dsk" ]; then
  args+=(-flop2 "$img/chiptunes-test.dsk")
fi
case "$mode" in
  base) ;;
  psg) args+=(-ext:multi:slot2 ccpsg) ;;
  gmc) args+=(-ext:multi:slot1 gmc) ;;
  *) echo "Unknown sound mode: $mode (use base, psg, or gmc)" >&2; exit 2 ;;
esac
if [ "$with_mcp" -eq 1 ]; then
  if [ ! -f "$bridge" ]; then
    echo "MCP bridge missing: $bridge" >&2
    exit 1
  fi
  args+=(-autoboot_script "$bridge" -autoboot_delay 0)
fi
if command -v lsof >/dev/null 2>&1; then
  media_images=("$img/63EMU.DSK" "$img/eou-working.vhd")
  if [ -f "$img/chiptunes-test.dsk" ]; then
    media_images+=("$img/chiptunes-test.dsk")
  fi
  for media_image in "${media_images[@]}"; do
    if lsof -t -- "$media_image" >/dev/null 2>&1; then
      echo "Media image is already open: $media_image" >&2
      echo "Close the existing emulator before launching another instance." >&2
      exit 1
    fi
  done
fi
echo "Launching $mode mode: coco3h / HD6309 / 2MB / EOU"
echo "At the BASIC OK prompt: DOS. In EOU, load /d1/clockpack before cctplaymt."
echo "Load /d1/cctcount and run cctcount in a second Shell window for the counter."
exec "$mame" "${args[@]}"
