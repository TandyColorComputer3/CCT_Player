#!/usr/bin/env bash
# Build the baseline and experimental CoCoPSG player from shared source.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
assembler="${LWASM_BIN:-lwasm}"
mkdir -p build
if ! command -v "$assembler" >/dev/null 2>&1; then
  echo "Missing LWASM: $assembler (set LWASM_BIN if installed elsewhere)" >&2
  exit 1
fi
"$assembler" --6309 --format=os9 --list=build/cctplay.lst --symbols -o build/cctplay cct_os9.asm
echo "Built $root/build/cctplay"
if [ -f cctplay ] && ! cmp -s cctplay build/cctplay; then
  echo "Baseline rebuild differs from the original cctplay binary." >&2
  exit 1
fi
"$assembler" --6309 --format=os9 --define=EXPERIMENTAL_PSG \
  --includedir="$root" --list=build/cctplaymt.lst --symbols \
  -o build/cctplaymt cct_os9.asm
echo "Built experimental CoCoPSG player $root/build/cctplaymt"
"$assembler" --6309 --format=os9 --define=EXPERIMENTAL_PSG --define=LOADER_TRACE \
  --includedir="$root" --list=build/cctplaydbg.lst --symbols \
  -o build/cctplaydbg cct_os9.asm
echo "Built loader diagnostic player $root/build/cctplaydbg"
"$assembler" --6309 --format=os9 --includedir="$root" \
  --list=build/cctcounter.lst --symbols -o build/cctcounter tools/cctcounter.asm
echo "Built OS-9 counter utility $root/build/cctcounter"
"$assembler" --6309 --format=os9 --includedir="$root" \
  --list=build/psgprobe.lst --symbols -o build/psgprobe tools/psgprobe.asm
echo "Built CoCoPSG hardware probe $root/build/psgprobe"
python3 scripts/make-synthetic-psg-vgm.py build/synthetic-psg.vgm
tool="${TOOLSHED_OS9:-/Users/magneto-optimus/Documents/Coding/toolshed-2.2/build/unix/os9/os9}"
if [[ "$tool" == */* ]]; then
  if [[ ! -f "$tool" || ! -x "$tool" ]]; then
    echo "ToolShed os9 not found or not executable: $tool" >&2
    exit 1
  fi
elif ! command -v "$tool" >/dev/null 2>&1; then
  echo "ToolShed os9 not found: $tool" >&2
  exit 1
fi
"$tool" ident build/cctplay
"$tool" ident build/cctplaymt
"$tool" ident build/cctplaydbg
"$tool" ident build/cctcounter
"$tool" ident build/psgprobe
