#!/usr/bin/env bash
# Reformat ONLY the project-local test floppy; optionally add song files.
# Never run while MAME is accessing the image.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
img="$root/emulator/images/chiptunes-test.dsk"
tool="${TOOLSHED_OS9:-/Users/magneto-optimus/Documents/Coding/toolshed-2.2/build/unix/os9/os9}"
if command -v lsof >/dev/null 2>&1 && lsof -t -- "$img" >/dev/null 2>&1; then
  echo "Test disk is already open: $img" >&2
  echo "Close MAME before recreating the staged disk." >&2
  exit 1
fi
if [[ "$tool" == */* ]]; then
  if [[ ! -f "$tool" || ! -x "$tool" ]]; then
    echo "Missing or non-executable ToolShed os9: $tool" >&2
    exit 1
  fi
elif ! command -v "$tool" >/dev/null 2>&1; then
  echo "Missing ToolShed os9: $tool" >&2
  exit 1
fi
binary="$root/build/cctplay"
if [ ! -f "$binary" ]; then
  echo "No rebuilt module; using unchanged upstream binary as baseline."
  binary="$root/cctplay"
fi
if [ ! -f "$binary" ]; then
  echo "Missing player binary. Run bash scripts/build.sh" >&2
  exit 1
fi
experimental="$root/build/cctplaymt"
diagnostic="$root/build/cctplaydbg"
counter="$root/build/cctcounter"
probe="$root/build/psgprobe"
clockprobe="$root/build/tpsprobe"
stopper="$root/build/cctstop"
synthetic="$root/build/synthetic-psg.vgm"
if [ ! -f "$experimental" ] || [ ! -f "$diagnostic" ] || [ ! -f "$counter" ] || [ ! -f "$probe" ] || [ ! -f "$clockprobe" ] || [ ! -f "$stopper" ] || [ ! -f "$synthetic" ]; then
  echo "Missing experiment artifacts. Run bash scripts/build.sh" >&2
  exit 1
fi
mkdir -p "$(dirname "$img")"
echo "Recreating PRIVATE stage disk (not the EOU boot or VHD): $img"
rm -f "$img"
"$tool" format -ds -t40 -e -nCCTTEST "$img"
for entry in "cctplay:$binary" "cctplaymt:$experimental" "cctplaydbg:$diagnostic" "cctcount:$counter" "psgprobe:$probe" "tpsprobe:$clockprobe" "cctstop:$stopper"; do
  name="${entry%%:*}"
  module="${entry#*:}"
  "$tool" copy "$module" "$img,$name"
  "$tool" attr -e -pe "$img,$name"
  "$tool" ident "$img,$name"
done
"$tool" copy "$synthetic" "$img,synthetic.vgm"
echo "Staged generated YM2149 tone test: /d1/synthetic.vgm"
for song in "$@"; do
  if [ ! -f "$song" ]; then
    echo "Song file not found: $song" >&2
    exit 1
  fi
  base="$(basename "$song")"
  if [ "${#base}" -gt 29 ]; then
    echo "Song filename too long for OS-9 (29 chars max): $base" >&2
    exit 1
  fi
  "$tool" copy "$song" "$img,$base"
  echo "Staged song: /d1/$base"
done
"$tool" dir "$img,"
echo "Ready. Close/relaunch MAME before mounting the newly generated test floppy."
