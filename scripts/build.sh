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
"$assembler" --6309 --format=os9 --define=EXPERIMENTAL_PSG --includedir="$root" \
  -o build/cctplaymt-relative cct_os9.asm
"$assembler" --6309 --format=os9 --define=EXPERIMENTAL_PSG --define=CYCLE_BASELINE \
  --includedir="$root" --list=build/cctcycle.lst --symbols -o build/cctcycle cct_os9.asm
"$assembler" --6309 --format=os9 --define=EXPERIMENTAL_PSG --define=CLOCK_SCHEDULER \
  --includedir="$root" --list=build/cctplaymt.lst --symbols \
  -o build/cctplaymt cct_os9.asm
echo "Built experimental CoCoPSG player $root/build/cctplaymt"
"$assembler" --6309 --format=os9 --define=EXPERIMENTAL_PSG --define=CLOCK_SCHEDULER --define=TIMING_TRACE \
  --includedir="$root" --list=build/ccttiming.lst --symbols \
  -o build/ccttiming cct_os9.asm
echo "Built PSG end-marker diagnostic $root/build/ccttiming"
"$assembler" --6309 --format=os9 --define=EXPERIMENTAL_PSG --define=CLOCK_SCHEDULER --define=LOADER_TRACE \
  --includedir="$root" --list=build/cctplaydbg.lst --symbols \
  -o build/cctplaydbg cct_os9.asm
echo "Built loader diagnostic player $root/build/cctplaydbg"
"$assembler" --6309 --format=os9 --includedir="$root" \
  --list=build/cctcounter.lst --symbols -o build/cctcounter tools/cctcounter.asm
"$assembler" --6309 --format=os9 --includedir="$root" \
  --list=build/timeload.lst --symbols -o build/timeload tools/timeload.asm
"$assembler" --6309 --format=os9 --includedir="$root" \
  --list=build/diskload.lst --symbols -o build/diskload tools/diskload.asm
"$assembler" --6309 --format=os9 --includedir="$root" \
  --list=build/diskbench.lst --symbols -o build/diskbench tools/diskbench.asm
"$assembler" --6309 --format=os9 --includedir="$root" --define=REAL_BENCH=1 \
  --list=build/diskreal.lst --symbols -o build/diskreal tools/diskbench.asm
echo "Built OS-9 counter utility $root/build/cctcounter"
"$assembler" --6309 --format=os9 --includedir="$root" \
  --list=build/psgprobe.lst --symbols -o build/psgprobe tools/psgprobe.asm
echo "Built CoCoPSG hardware probe $root/build/psgprobe"
"$assembler" --6309 --format=os9 --includedir="$root" \
  --list=build/cctstop.lst --symbols -o build/cctstop tools/cctstop.asm
"$assembler" --6309 --format=os9 --includedir="$root" \
  --list=build/psgsuper.lst --symbols -o build/psgsuper tools/psgsuper.asm
echo "Built graceful background stop utility $root/build/cctstop"
"$assembler" --6309 --format=os9 --includedir="$root" \
  --list=build/tpsprobe.lst --symbols -o build/tpsprobe tools/tpsprobe.asm
echo "Built OS-9 clock-rate probe $root/build/tpsprobe"
"$assembler" --6309 --format=os9 --includedir="$root" \
  --list=build/sleepprb.lst --symbols -o build/sleepprb tools/sleepprobe.asm
"$assembler" --6309 --format=os9 --includedir="$root" \
  --list=build/sigprb.lst --symbols -o build/sigprb tools/signal-sleepprobe.asm
echo "Built OS-9 sleep timing probes"
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
"$tool" ident build/ccttiming
"$tool" ident build/cctplaydbg
"$tool" ident build/cctcounter
"$tool" ident build/timeload
"$tool" ident build/diskload
"$tool" ident build/diskbench
"$tool" ident build/diskreal
"$tool" ident build/psgprobe
"$tool" ident build/cctstop
"$tool" ident build/psgsuper
"$tool" ident build/tpsprobe
"$tool" ident build/sleepprb
"$tool" ident build/sigprb

# Keep descriptor and driver in one physical 8 KB module block.
for module in cctclock ctclock clockprobe; do
  "$assembler" --6309 --format=os9 --includedir="$root" \
    --list="build/$module.lst" --symbols -o "build/$module" "tools/$module.asm"
  "$tool" ident "build/$module"
done
cat build/cctclock build/ctclock > build/clockpack
"$tool" ident build/cctcycle

for mode in IDLE COUNTER; do
  if [[ "$mode" == IDLE ]]; then out=idlebench; else out=countbench; fi
  "$assembler" --6309 --format=os9 --includedir="$root" --define="${mode}_BENCH" \
    --list="build/$out.lst" --symbols -o "build/$out" tools/diskbench.asm
  "$tool" ident "build/$out"
done
"$assembler" --6309 --format=os9 --includedir="$root" --define=LONG_WORKLOAD \
  --list=build/countlong.lst --symbols -o build/countlong tools/timeload.asm
"$tool" ident build/countlong
