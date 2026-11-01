#!/usr/bin/env bash
# Explicit opt-in; run build.sh first for the unchanged comparison helpers.
set -euo pipefail
cd "$(dirname "$0")/.."
a="${LWASM_BIN:-lwasm}"
python3 scripts/prepare-irq-fixture.py
"$a" --6309 --format=os9 --includedir=. --define=IRQ_STREAM_TEST --define=IRQ_UNDER -o build/streamunder tools/irqprobe.asm
"$a" --6309 --format=os9 --includedir=. --define=IRQ_STREAM_SUPERVISOR -o build/irqsuper tools/psgsuper.asm
"$a" --6309 --format=os9 --includedir=. --define=IRQ_STREAM_SUPERVISOR --define=FATAL_STOP -o build/irqkill tools/psgsuper.asm
for module in psgstream psgs; do
 "$a" --6309 --format=os9 --includedir=. --symbols --list="build/$module.lst" -o "build/$module" "tools/$module.asm"
done
"$a" --6309 --format=os9 --includedir=. --define=EXPERIMENTAL_PSG --define=CLOCK_SCHEDULER --define=IRQ_STREAM --symbols --list=build/cctirq.lst -o build/cctirq cct_os9.asm
"$a" --6309 --format=os9 --includedir=. --define=EXPERIMENTAL_PSG --define=CLOCK_SCHEDULER --define=IRQ_STREAM --define=GMC_IRQ --symbols --list=build/cctgmc.lst -o build/cctgmc cct_os9.asm
"$a" --6309 --format=os9 --includedir=. --define=GMC_DRIVER --symbols --list=build/gmcstream.lst -o build/gmcstream tools/psgstream.asm
"$a" --6309 --format=os9 --includedir=. --define=GMC_DRIVER -o build/gmcs tools/psgs.asm
"$a" --6309 --format=os9 --includedir=. --define=STREAM_WORKLOAD -o build/diskshort tools/diskload.asm
"$a" --6309 --format=os9 --includedir=. --define=STREAM_WORKLOAD --define=CONTINUOUS_READ -o build/diskburst tools/diskload.asm
cat build/clockpack build/psgstream build/psgs build/timeload build/countlong build/cctstop build/diskshort build/diskburst > build/streampack
python3 - <<'PY'
import json,re
from pathlib import Path
symbols=dict(re.findall(r'^\[ G\] (\w+)\s+([0-9A-F]+)$',Path('build/psgstream.lst').read_text(),re.M));b=Path('build/psgstream').read_bytes();p={'size':len(b),'crc':list(b[-3:])}
for k,n in [('irq','IRQ'),('ok','OK'),('ticks','Ticks'),('state','State'),('count','Count'),('budgets','Budgets'),('unders','Unders'),('owner','Owner'),('append','Append'),('busy','Busy'),('invalid','Invalid'),('locked','AppendLocked'),('unlock','AppendUnlock'),('unlockbusy','AppendBusy'),('unlockinvalid','AppendInvalid'),('setstat','SetStat'),('getstat','GetStat')]:p[k]=int(symbols[n],16)
Path('build/psgstream.json').write_text(json.dumps(p)+'\n')
symbols=dict(re.findall(r'^\[ G\] (\w+)\s+([0-9A-F]+)$',Path('build/gmcstream.lst').read_text(),re.M));b=Path('build/gmcstream').read_bytes();p={'size':len(b),'crc':list(b[-3:]),'gmc':True}
for k,n in [('irq','IRQ'),('ok','OK'),('ticks','Ticks'),('state','State'),('count','Count'),('budgets','Budgets'),('unders','Unders'),('owner','Owner'),('append','Append'),('busy','Busy'),('invalid','Invalid'),('locked','AppendLocked'),('unlock','AppendUnlock'),('unlockbusy','AppendBusy'),('unlockinvalid','AppendInvalid'),('setstat','SetStat'),('getstat','GetStat')]:p[k]=int(symbols[n],16)
Path('build/gmcstream.json').write_text(json.dumps(p)+'\n')
PY

# One physical code block: player + driver + descriptor. A cold I$Open can
# then map the driver using one system DAT slot; no extra load link is needed.
cat build/cctirq build/psgstream build/psgs > build/cctirq-standalone
[ "$(wc -c < build/cctirq-standalone)" -le 8192 ] || { echo "Standalone pack exceeds one system block" >&2; exit 1; }
cat build/cctgmc build/gmcstream build/gmcs > build/cctgmc-standalone
[ "$(wc -c < build/cctgmc-standalone)" -le 8192 ] || { echo "GMC pack exceeds one system block" >&2; exit 1; }
for fault in INIT VIRQ ALLOC; do
 "$a" --6309 --format=os9 --includedir=. --define="IRQ_FAIL_$fault" -o "build/psgstream-fail-$fault" tools/psgstream.asm
 cat build/cctirq "build/psgstream-fail-$fault" build/psgs > "build/cctirq-fail-$fault"
done
