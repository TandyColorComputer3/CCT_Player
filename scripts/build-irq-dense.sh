#!/usr/bin/env bash
# Isolated diagnostic budget comparison; preserve normal IRQ/player builds.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-mixed}"
budget="${2:-8}"
case "$mode" in saturation|mixed|long) ;; *) echo "fixed queue mode must be saturation, mixed or long" >&2; exit 1;; esac
case "$budget" in 8|12|16) ;; *) echo 'budget must be 8, 12 or 16' >&2; exit 1;; esac
python3 scripts/prepare-irq-dense.py "$mode"
assembler="${LWASM_BIN:-lwasm}"
mkdir -p build/irq-dense
"$assembler" --6309 --format=os9 --includedir=. --define="IRQ_BUDGET=$budget" \
 --symbols --list=build/irq-dense/driver.lst -o build/irq-dense/PSGQueue tools/psgqueue.asm
"$assembler" --6309 --format=os9 --includedir=. --define=IRQ_CUSTOM \
 -o build/irq-dense/irqdense tools/irqprobe.asm
cat build/clockpack build/irq-dense/PSGQueue build/psgq build/irq-dense/irqdense build/timeload build/countlong build/cctstop > "build/irq-dense/$mode-$budget.pack"
python3 - "$mode" "$budget" <<'PY'
import json,re,sys
from pathlib import Path
symbols=dict(re.findall(r'^\[ G\] (\w+)\s+([0-9A-F]+)$',Path('build/irq-dense/driver.lst').read_text(),re.M));b=Path('build/irq-dense/PSGQueue').read_bytes();p={'size':len(b),'crc':list(b[-3:])}
for key,name in [('irq','IRQ'),('ok','OK'),('ticks','Ticks'),('state','State'),('count','Count'),('budgets','Budgets'),('unders','Unders'),('owner','Owner')]:p[key]=int(symbols[name],16)
Path(f'build/irq-dense/{sys.argv[1]}-{sys.argv[2]}.json').write_text(json.dumps(p,indent=2)+'\n')
PY
