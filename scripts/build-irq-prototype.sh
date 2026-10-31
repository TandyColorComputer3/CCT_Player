#!/usr/bin/env bash
# Opt-in fixed-stream proof of concept. Does not alter normal player builds.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
python3 scripts/prepare-irq-fixture.py
assembler="${LWASM_BIN:-lwasm}"
for pair in 'psgqueue PSGQueue' 'psgq psgq' 'irqprobe irqprobe'; do
  read -r source output <<< "$pair"
  "$assembler" --6309 --format=os9 --includedir=. --symbols \
    --list="build/$source.lst" -o "build/$output" "tools/$source.asm"
done
for variant in BURST UNDER OVER; do
  output="irq$(echo "$variant" | tr '[:upper:]' '[:lower:]')"
  "$assembler" --6309 --format=os9 --includedir=. --define="IRQ_$variant" \
    -o "build/$output" tools/irqprobe.asm
done
# A shared physical block avoids a second 8 KiB system-map code allocation.
cat build/clockpack build/PSGQueue build/psgq build/irqprobe build/irqburst build/irqunder build/irqover build/cctstop > build/irqpack
tool="${TOOLSHED_OS9:-$HOME/Documents/Coding/toolshed-2.2/build/unix/os9/os9}"
"$tool" ident build/irqpack
python3 - <<'PY'
import json,re
from pathlib import Path
symbols=dict(re.findall(r'^\[ G\] (\w+)\s+([0-9A-F]+)$',Path('build/psgqueue.lst').read_text(),re.M))
b=Path('build/PSGQueue').read_bytes()
p={'size':len(b),'crc':list(b[-3:])}
for key,name in [('irq','IRQ'),('ok','OK'),('ticks','Ticks'),('state','State'),('count','Count'),('budgets','Budgets'),('unders','Unders'),('owner','Owner')]:p[key]=int(symbols[name],16)
Path('build/irq-layout.json').write_text(json.dumps(p,indent=2)+'\n')
PY
