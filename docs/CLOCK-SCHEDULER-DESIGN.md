# Elapsed-time CoCoPSG scheduler experiment

Starting checkpoint: `6eb11eb`. Target: existing NTSC HD6309 EOU Level II,
2 MB, visible MAME 0.289, CoCoPSG slot 2 and floppy controller slot 4.
The optional module below is a clock for the standalone player. It does not
parse music, write sound registers, alter the kernel, or extend hardware support.

## Available clocks and ownership

| Source | Resolution / semantics | Decision |
| --- | --- | --- |
| EOU Clock `D.Tick` | Countdown of serviced vertical-border interrupts; reloads every nominal second. Private system-map variable, not a timestamp ABI. | Do not read a presumed user logical address. |
| `F$Time` | Six-byte calendar packet, seconds resolution. `F$STime` can change it; Clock2 may refresh it. | Not monotonic or sufficiently resolved. |
| `F$TPS` | This boot returns carry and `E$UnkSvc`, as measured previously. | Unavailable. A tick-rate query would not itself be elapsed time. |
| `/nil`, VRN `SS.VCtr` | 32-bit count of VIRQ ticks for a registered process/path; **destructive** read resets it. | Supported API, but installed implementation has a read/reset race; unsuitable for a frequently polled reliable clock. |
| GIME timer | Programmable 12-bit reload, approximately 279 ns or horizontal-line units; 1986/1987 reload differences. Counter value is not readable through normal hardware registers. | No safe free-running timestamp established. Do not read IRQ status to poll time: reading acknowledges shared interrupts. |
| `F$VIRQ` + `F$IRQ` | Documented driver-context registration using the existing video clock. Nominal 60 Hz NTSC / 50 Hz PAL. | Small optional atomic tick-snapshot driver; no new hardware interrupt source. |

The [EOU technical reference](https://www.lcurtisboyle.com/nitros9/EOUDOCS/NitrOS-9_EOU_Level_2_Technical_Reference_Manual.pdf)
documents VRN in chapter 8 and the VIRQ, IRQ and status-call interfaces.
The installed VRN is 506 bytes, CRC `D29DA3`; a matching binary extracted
read-only from the private VHD has the unmasked copy/clear sequence at
module offsets `$95..$A3`. It loads two words, stores them in the caller's
register frame, then clears both words. An IRQ between copying the low word
and clearing it can lose a tick. The matching installed Krn binary has
`ANDCC #$AF` at offset `$2CB` on the user-system-call dispatch path; the
reference SCF does not bracket this GetStat with a mask. This is a race
identified by inspection, not a measured VRN lost-counter experiment.
We neither patch VRN nor mask an entire I/O call in user state.

Reference source inspected: NitrOS-9 revision
`f470fa52eb172b59b22c1b722074998cb42de9b1`, especially
`level2/modules/clock.asm`, `level2/modules/kernel/krn.asm`,
`level1/modules/vrn.asm`, `scf.asm`, `ioman.asm`, `rb1773.asm`, and
`level1/coco1/modules/llcocosdc.asm`. This source tree is reference evidence,
not an assertion that every instruction matches this EOU boot. Live boot
module identities: Clock `972B38`, Krn `9D89BE`, SCF `3508DD`, rb1773 `FBAA3C`.

The [MAME 0.289 GIME implementation](https://github.com/mamedev/mame/blob/mame0289/src/mame/trs/gime.cpp)
confirms the write-only reload registers and destructive IRQ/FIRQ status
reads, plus the timer period/reload differences. EOU already owns GIME
interrupt enables, task selection, video and IRQ dispatch. A faster GIME
timer would require explicit ownership and driver registration, and cannot
recover an arbitrary number of expirations while interrupts are masked.
It is therefore not an automatic solution to disk-induced clock loss.

## Architecture choice

A normal user process can retain its decoder, buffers, signals and hardware
transactions. What it lacks is a reliable elapsed-time snapshot. `F$Sleep`
is a scheduling request, not such a snapshot: phase, early wakeups and time
spent descheduled must not be added as estimated elapsed time.

Prototype B adds **only** the missing atomic tick API. `CCTClock` and its
`ctclock` SCF descriptor load dynamically, without changing OS9Boot. Init
registers a one-tick repeating VIRQ packet and an IRQ-poll entry. A failed
VIRQ registration rolls back the IRQ entry. Term removes VIRQ before IRQ.
The handler clears its software pending bit and increments four bytes;
there are no OS calls, allocation, parsing, I/O, signals or PSG accesses in
the handler. GetStat `$80` returns X:Y, an atomic non-destructive 32-bit
snapshot, using a short saved/restored CC section. Mutable state is private
driver storage addressed by U. Shared users receive the same time base;
each player owns its own path and deadlines.

Driver and descriptor must be loaded from **one concatenated pack**. The
first separate-module load exhausted system mapping space despite 1,768 KiB
of free process RAM. The packed 225-byte load and subsequent probe worked.
This is the distinction between physical RAM and Level II's 64 KB system
logical map, not a reason to modify the boot image.

Tick resolution is approximately 16.7 ms. This prototype deliberately
quantizes sub-tick deadlines rather than synthesizing an unmeasured fine
clock from CPU cycles. It establishes elapsed-time compensation across
ordinary task switches, but cannot promise sample-accurate delivery or
recover clock interrupts that the OS never services. A scheduled-output
queue/driver would reduce process wakeup latency; it would still be blocked
by globally masked IRQs and CPU HALT. Such a queue is not implemented here.

## Scheduler implementation

`CLOCK_SCHEDULER` selects the new path. The original default build remains
byte-identical to `cctplay`. `build/cctplaymt-relative` reproduces the exact
`6eb11eb` experimental binary; `cctcycle` provides the same relative engine
under a separate module name for comparisons.

At each song start the player opens `/ctclock` and snapshots its epoch.
Every decoded wait advances a 32-bit whole-tick deadline and a fractional
sample remainder. For NTSC, with `S=735` (PAL build: 882):

```
q, r = divmod(wait_samples, S)
q2, fraction = divmod(previous_fraction + r, S)
deadline += q + q2
delivery_tick = deadline + (fraction != 0)
```

All arithmetic is integer; no fractional samples are discarded. Dividing
the 16-bit wait first avoids overflow when adding its remainder. The
modulo-32-bit target-minus-now comparison relies on future targets being
at most 90 ticks away: each previous wait completes before the next 16-bit
wait is added. Lateness must stay below 2^31 ticks for its sign test.
The clock wraps in about 2.27 years; the supported lateness range is about
1.13 years. Song loops retain the timeline;
playlist entries establish a new epoch after their load.

Before waiting, and after each `F$Sleep X=2`, the player reads the clock.
Already-due waits complete immediately. Parser, PSG-write and preemption
time therefore consume the deadline budget instead of extending it. There
is no empirical command debt or sleep-phase correction on this path.
At most 32 decoded write/wait operations pass without a scheduling yield;
all writes remain in order, including overdue writes. This bounds catch-up
work without silently discarding events. Extremely dense zero-wait streams
can still exceed available CPU bandwidth.
The budget yield uses X=1. Future tick deadlines use X=2 to park for a
tick instead of repeatedly rescheduling immediately on an otherwise idle
system. Neither requested count is treated as measured elapsed time.

Clock errors latch an error and stop request; normal cleanup silences the
PSG and closes the path. No cleanup runs in the signal intercept. Existing
U-relative signal handling, playlist stop latch, guard/mapping cleanup and
live MPI selection save/restore transactions remain in place. No critical
section spans parsing, sleeping, file I/O or playlist transitions.

## Initial live checks

* **PASS:** CCTClock 184 bytes, CRC `8F5EED`; descriptor 41 bytes, CRC
  `643AD0`; all are reentrant OS-9 modules with valid header/CRC.
* **PASS:** Packed load, open, 600 probe sleeps and clean close. Tick
  snapshots differed by 600 over 10.007255 emulated seconds. The interval
  includes arbitrary initial tick phase and probe overhead.
* **PASS, preliminary:** First deadline-player synthetic30 stream lasted
  30.034036 seconds, +0.11345%, all 210 pairs and final mute matched.
* **FAIL, preliminary:** First periodic-floppy run lasted 35.568983 seconds,
  +18.5633%, all 210 pairs matched. This is improved duration, not target
  acceptance. Repeated measurements and clock-loss diagnosis follow.

Private evidence is under `emulator/images/timing-new/logs/trace-clock-*`.
All timings are MAME emulated seconds; no host wall-clock claims.

## Physical compatibility and limits

The clock API uses 6809 instructions, but register-frame offsets are built
for the HD6309 EOU ABI. A 6809 build needs matching `H6309` definitions;
6809, PAL and 512 KB validation are **NOT RUN**. Nominal 60 Hz differs
slightly from MAME's approximately 59.92 Hz video cadence; this is a small
systematic duration error, not an empirical fine-loop correction.

The MAME floppy driver can mask IRQ/FIRQ while waiting for and transferring
sectors, with CPU HALT between bytes. The GIME pending bit is not a count
of all missed video edges. IRQ servicing, process scheduling, and even this
driver's clock can therefore pause or lose ticks during disk operations.
Physical CoCoSDC uses a different transfer/interrupt path and must be tested
with its actual driver; these MAME floppy results are not CoCoSDC results.
The inspected `llcocosdc` saves/restores MPI selection and conditionally
masks IRQ/FIRQ when it detects a floppy controller in the MPI. Thus even
CoCoSDC latency depends on cartridge population and the installed driver;
we cannot promise that replacing the storage medium removes this limitation.
The clock never selects MPI slots or touches cartridge ports. Existing PSG
transactions preserve the live MPI selection. Mega Mini routing, physical
CoCoPSG, CoCoSDC interaction and OPL3 remain hardware validation work.

## Reproduction and rollback

```
bash scripts/build.sh
# Stage a new, unmounted project-private test disk with the same fixtures.
CCT_TEST_DISK="$PWD/emulator/images/clock-test.dsk" \
  bash scripts/stage-test-disk.sh "$FIXTURE_DIR"/*.vgm "$FIXTURE_DIR"/*.cct
# In the isolated guest, after mounting this disk:
# chx /d1
# load clockpack
# cctplaymt -psg 2 /d1/synthetic30.vgm &
# cctstop <verified-player-pid>
```

Use `unlink CCTClock` only after all clock paths close; the descriptor in
the same pack has no independent preload link in the tested loader. Reverting
the scheduler commits or building without `CLOCK_SCHEDULER` restores the
relative engine. No canonical image, original executable or kernel change
is part of this experiment. The historical reboot remains **UNRESOLVED /
NOT REPRODUCED**.

## Final five-repeat matrix

The final player is **9,653 bytes, CRC `B3B649` Good**, data 1,983 bytes,
live module identity verified. SHA-256:
`05ee55b64485c7fa128b0d7099fb9eec7cc13cea83a1396a7c807f137887e953`.
Clockpack SHA-256:
`b75745756b198ab102c11b1f3defa3d9b1faff09738ac9fa8dab507c6bb43641`.
The earlier preliminary player used X=1 for future waits; the final player
uses X=2. Both read the same clock and retain the same deadlines. Results
from those binaries are not pooled.

The fixture is unchanged from `6eb11eb`: synthetic30, 1,323,000 samples,
1,800 waits of 735 samples, 210 PSG pairs, no loop. Boundaries are the first
observed PSG data write and the immediately following final mixer mute;
no initial/trailing interval is estimated for this fixture. Every one of
the 15 streams matched all 210 register pairs in order and the final mute.

| Workload | Five durations, emulated seconds | Error min / max / mean / sample SD (percentage points) | <1% |
| --- | --- | --- | --- |
| Idle | 30.023437, 30.022980, 30.023140, 30.022657, 30.023150 | +0.07552 / +0.07812 / **+0.07691** / 0.00095 | PASS |
| Counter | 30.022622, 30.021961, 30.022015, 30.009936, 30.027383 | +0.03312 / +0.09128 / **+0.06928** / 0.02157 | PASS |
| Floppy | 35.739303, 35.856842, 36.022669, 36.000543, 36.052607 | +19.13101 / +20.17536 / **+19.78131** / 0.44164 | FAIL |

The old means were -2.0689%, -0.7279%, and +51.5767%, respectively.
Supervisors wait for each player and check its exit status. The counter
uses the same six-byte output, increment and 61-tick sleep as `timeload`,
extended from 60 to 230 iterations to cover all five players continuously.
Unlike the earlier individually launched counter runs, its phase is not
restarted per song. The idle supervisor remains asleep between forks.
The floppy workload is the **unchanged** `diskload` CRC `7D2EEE`, 230
open/read-256/close/sleep-61 iterations, and unchanged `diskbench` CRC
`557E9F`. It produced 220, 220, 220, 229 and 230 FDC commands inside the
five music intervals. All three supervisors eventually printed
`DISKBENCH OK`; the counter and reader ended naturally. No test workload
was killed. Three existing Shell processes remained.

### Event quality is a separate result

Event error is `(actual-first_write) - (decoded_sample-first_sample)/44100`.
Local interval error uses consecutive events with a nonzero decoded wait.
The p95 column is the range of per-run nearest-rank 95th percentiles of
absolute event error, including same-deadline register commands.

| Workload | Largest cumulative event lateness | Largest local interval lateness | p95 absolute event error |
| --- | ---: | ---: | ---: |
| Idle | 23.291 ms | 0.636 ms | 20.577–21.357 ms |
| Counter | 27.238 ms | 0.636 ms | 19.936–26.116 ms |
| Floppy | 6,052.461 ms | 431.324 ms | 5,464.502–5,821.833 ms |

The small idle drift includes the nominal-60 conversion and arbitrary
starting tick phase. Frame timestamps measured a median 16.6881533 ms
period, approximately **59.92275 Hz**. No delay constant was retuned to
cancel this difference. Tick quantization can bunch events; good total
duration is not a claim of sample-accurate timing or subjective audio quality.

### Independent evidence of clock loss

`clkprobe` opens its own clock path and reads two snapshots around 600
one-tick sleeps, with no VGM decoder or sound data writes. Under the still
active floppy workload its snapshots advanced **730 ticks in 14.513748
emulated seconds**, spanning 91 FDC commands. An uninterrupted video clock
would span approximately 869.70 ticks in that interval: about **140 ticks
were not represented**, with roughly one tick of boundary uncertainty.
Extra scheduler latency alone would increase both elapsed time and the
count; it cannot explain this deficit. The installed rb1773 binary contains
`ORCC #$50` at offset `$1B1`, matching its masked transfer path in source.
GIME pending interrupts latch a condition rather than counting every edge.

Consequently this prototype corrects CPU-only relative waits and ordinary
preemption drift, but **does not provide accurate elapsed time during this
floppy driver's interrupt-masked activity**. Raising the GIME IRQ frequency
or moving writes into another IRQ handler cannot recover uncounted time or
execute sound updates while the CPU is halted/masked. A readable independent
clock or a different proven storage/interrupt behavior is needed before
claiming the all-workload target. No kernel/disk-driver workaround or higher
frequency interrupt experiment was introduced.

## Functional regression results

| Test | Actual result |
| --- | --- |
| Arkanoid real VGM | PASS: all 266 pairs; estimated 4.433331 s vs decoded 4.430204 s, +0.07059%. |
| M3U Ark1 CCT then Flicky CCT, counter active | PASS: all 266 and 820 pairs; separate final mutes; 4.433075 s estimated (+0.06481%) and 20.118487 s (+0.14191%). |
| Generated one-second loop, `-l 1` | PASS: ten pairs across two passes, then mute; 1.993327 s vs 2.000 s, -0.33365%. |
| Background Shell | PASS: prompt returned and `echo CLOCKLIVE` executed during synthetic playback. |
| Preloaded `psgsuper`, playlist stop | PASS for the observed phases: 180/420-tick requests stopped during initial CCT loading, with no sound writes; 900 stopped after the complete first track with no second stream. All reported `SEND=00 WAIT=00`. These are not claims of stops at the originally intended musical positions. |
| On-demand floppy-loaded `cctstop` | PASS: PID 3 verified as the active player; 104 expected prefix pairs then final mute at 15.456772 s. Signal 3 was observed at 6064.078440, mute at 6064.107527 (29.087 ms later), with 18 FDC commands during playback. |
| Cleanup / memory | PASS under these conditions: 1,744 KiB free before/after stop and again after unloading/reloading the clock pack. Clock links returned to preload-only; player and workload processes exited. No reset notifications. |
| Missing optional clock | PASS: after verified pack unload, player returned error 221 (`Module Not Found`), emitted only final mute, and exited. Pack restored afterward. |
| Original baseline | PASS: `cmp cctplay build/cctplay`; relative comparison build SHA remains `666f91ea6a3292e2c0b96f46547698b78bef7dd3215269cc0bc40f8c5035cb8d`. |

Arkanoid/Ark1 start with 276 samples before the first PSG write. Their
estimated durations add nominal 276/44100 seconds; that initial interval
was not directly timestamped. Flicky starts at sample zero. CCT stop
captures repeatedly show the player's saved PC at module offset `$1486`,
the `I$Read` operand at the CCT loader, rather than a playback wait loop.
The 180-tick case records signal 3 pending and subsequently cleared before
any PSG activity. The signal intercept and stop latch were not changed.

MAME's continuously recorded 48 kHz, four-channel PCM WAV contains non-DC
audio on channel 2: one-second mean-removed RMS approximately 8,332 for
Arkanoid, 8,400 for Ark1 and 14,059 for Flicky. The successful on-demand
stop capture measured 8,163 while playing and 0.438 two seconds after mute
(16-bit PCM counts). These prove signal generation and final silence, not
a new human listening assessment. The visible emulator is left running.

Two automation attempts are excluded from successful-stop counts: a
character-paced command lost characters during floppy activity and was
rejected by the supervisor before forking; a later `cctstop` reached F$Send
after the 30-second player had already exited and returned error 224.
The successful repeat verified the live PID and queued stop earlier.

Exact CPU utilization remains **NOT RUN**. Retained frame samples within
idle playback all observed PID 1, and counter playback almost always did;
this frame-synchronous sampling strongly aliases tick wakeups and cannot
be turned into a CPU percentage. The new wait parks with `F$Sleep X=2`;
the IRQ body itself is bounded, but dispatcher/GetStat overhead has not
been cycle-profiled. Sub-tick accuracy, extreme event density, PAL/6809,
physical CoCoSDC/Mega Mini and human audio quality remain unvalidated.

## Evidence identity and commands

Same running isolated MAME process as the preceding baseline, no reset or
state load. Launch: MAME `0.289 (ample-289-u2)`, `coco3h -ramsize 2M
-window -natural -ext multi -ext:multi:slot2 ccpsg -ext:multi:slot4 fdc`,
CoreAudio and `-wavwrite`, private `timing-new` media/config/bridge paths.
The current private floppy was mounted through the bridge; boot and VHD
were not changed. Boot SHA remains `9a51adb8656b9f003c7f822352c291487362f1b4c43aac1a16672d5d2bcb4c40`,
VHD `7bef15fab761db2084517ebadaa5b7ee42a667ee7131fcf629ee8c3531835681`.
Final idle/counter disk SHA `3d0406086cd2fbc37a8d77b9faf0fd30fd3c6ba6a1a0c328bf050b32f33b5dee`;
disk/regression copy with extra original test fixtures
`40f6ec76386d40ef5f23e51de7bf5499e2dc651ba8315181752150ac4ea99273`.
Music fixture hashes are exactly those in TIMING-WORKLOAD-BASELINE.md.

Observer SHA `b8e9cbf543735fedb5b5ec01ec36718a420c837203eb702e0d0f8d43a6723b36`;
updated summary analyzer `4eff0f784bb15bba1e1dc9bfc7585e964a7de2d36ed87bcc17ce56227ec5b518`;
unchanged decoder analyzer `624c620774289aa4d4dfb0742044f62bf95f2548a2d5b3c7dea2686471383997`.
Trace hashes for `trace-clock-final-{idle,counter,disk}.json`:

```
idle    3a10ccdd320952e3e697c2a04e372bb1975a18a43ea60828c2c89eaf8f2d92cb
counter 7e7fd665d7ecd8018a56c7beaffce410398680e627801ee34e0797969f7ef2d2
disk    9b6292621c1328992e4b5142a832c8f15f982ea0e466d88207da0d85b1c9b1fc
```

All final traces have zero dropped PSG/FDC events and zero resets. Frame
sample rings wrapped by 1,907 / 1,644 / 5,654 samples respectively; frame
coverage is incomplete and that loss is distinct from the intact event
streams. Functional regression captures did not wrap. Evidence remains
ignored/project-local; no music, binary, image or ROM is committed.

```
# Guest: preload tested modules; run one bounded workload at a time.
# load clockpack cctplaymt idlebench countbench countlong diskbench diskload
# idlebench &
# countbench &
# diskbench &
# Wait for each supervisor AND its workload to finish before changing load.
python3 scripts/summarize-psg-repeats.py "$FIXTURE_DIR/synthetic30.vgm" \
  emulator/images/timing-new/logs/trace-clock-final-idle.json
```

The remaining all-workload timing failure is explicit. The historical
reboot remains **UNRESOLVED / NOT REPRODUCED**, independently of these
timing and functional results.
