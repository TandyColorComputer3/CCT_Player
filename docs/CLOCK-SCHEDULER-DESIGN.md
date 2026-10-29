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
and clearing it can lose a tick. The reference kernel unmasks interrupts on
user-system-call entry and SCF does not bracket this GetStat with a mask.
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
the 16-bit wait first avoids overflow when adding its remainder. A signed
modulo-32-bit target-minus-now comparison handles counter rollover, provided
the separation is below 2^31 ticks. The clock wraps in about 2.27 years;
the comparison range is about 1.13 years. Song loops retain the timeline;
playlist entries establish a new epoch after their load.

Before waiting, and after each `F$Sleep X=1`, the player reads the clock.
Already-due waits complete immediately. Parser, PSG-write and preemption
time therefore consume the deadline budget instead of extending it. There
is no empirical command debt or sleep-phase correction on this path.
At most 32 decoded write/wait operations pass without a scheduling yield;
all writes remain in order, including overdue writes. This bounds catch-up
work without silently discarding events. Extremely dense zero-wait streams
can still exceed available CPU bandwidth.

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

Use `unlink CCTClock ctclock` only after all clock paths close. Reverting
the scheduler commits or building without `CLOCK_SCHEDULER` restores the
relative engine. No canonical image, original executable or kernel change
is part of this experiment. The historical reboot remains **UNRESOLVED /
NOT REPRODUCED**.
