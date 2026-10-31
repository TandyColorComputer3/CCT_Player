#!/usr/bin/env bash
# Opt-in diagnostics; the ordinary build and all player variants stay unchanged.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
assembler="${LWASM_BIN:-lwasm}"
"$assembler" --6309 --format=os9 --includedir=. --list=build/cctnice.lst \
  -o build/cctnice tools/cctnice.asm
"$assembler" --6309 --format=os9 --includedir=. --define=CONTINUOUS_READ \
  --define=LATENCY_STRESS --list=build/diskstress.lst -o build/diskstress tools/diskload.asm
for mode in disk busy; do
  extra=()
  if [[ "$mode" == busy ]]; then extra=(--define=BUSY_BENCH); fi
  "$assembler" --6309 --format=os9 --includedir=. --define=REAL_BENCH \
    --define=PARK_BENCH --define=MUSIC_BENCH "${extra[@]}" \
    -o "build/music$mode" tools/diskbench.asm
done
cat build/cctnice build/timeload build/diskstress build/musicdisk build/musicbusy > build/latpack
printf '%s\n' 'Built opt-in scheduling helpers in build/latpack; stage only on an unmounted private image.'
