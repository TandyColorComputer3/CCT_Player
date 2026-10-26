#!/usr/bin/env bash
# Make private writable copies. Never edit the canonical MCP media.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
media="${MCP_MEDIA_DIR:-/Volumes/SEDONA/Projects/CoCo3_MCP_Server_NOS9/media}"
out="$root/emulator/images"
reset=0
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "--reset" ]; }; then
  echo "Usage: bash scripts/setup-mame.sh [--reset]" >&2
  exit 2
fi
if [ "$#" -eq 1 ]; then reset=1; fi
mkdir -p "$out" "$root/emulator/logs" "$root/emulator/screenshots"
copy_one() {
  local from="$1" to="$2"
  if [ ! -f "$from" ]; then
    echo "Source image missing: $from" >&2
    return 1
  fi
  if [ -e "$to" ] && [ "$reset" -eq 0 ]; then
    echo "Preserving existing working image: $to"
  else
    cp -p "$from" "$to"
    chmod u+w "$to"
    echo "Private media ready: $to"
  fi
}
copy_one "$media/63EMU.DSK" "$out/63EMU.DSK"
copy_one "$media/63SDC-MCP-DEV.VHD" "$out/eou-working.vhd"
echo "Prepared. --reset will replace existing private boot/VHD copies; only use with MAME stopped."
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$out/63EMU.DSK" "$out/eou-working.vhd"
fi
