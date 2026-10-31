# Clock-source diagnosis and bounded sleep experiment

Development date: 2026-10-30. Starting checkpoint: `bbdaf36`.
Scope: standalone CoCoPSG, HD6309 EOU Level II, MAME 0.289, 2 MiB.
The original executable, relative scheduler and checkpoint clock scheduler
remain available and unchanged. No kernel, disk driver, IRQ hook, timer,
sound-write filtering or system-context output queue is introduced.

## Measurement method

Use a separate, exclusively owned guest with project-private media. The
host observer records `manager.machine.time` inside callbacks for guest
PSG writes, guest reads of `$FF92`, OS clock updates and CCTClock accesses.
It does **not** read `$FF92` itself: doing so would acknowledge interrupts.
Read taps return no value and therefore preserve the guest's read result.
See [MAME's pass-through handler API](https://docs.mamedev.org/luascript/ref-mem.html).

`tools/performance-observer.lua` is a host diagnostic loaded by a local Lua
bridge, not an OS-9 module. Its `performance_start` command takes verified
system-map `code` and `storage` addresses. It validates the baseline driver's
size/CRC and its active one-tick VIRQ packet before installing taps. Keep
the device attached with `iniz ctclock` across comparisons, then release it
with `deiniz ctclock`. Addresses must be re-established after a reload; they
are not process-logical addresses or portable constants.

The four GetStat byte reads are distinguished from the IRQ's INC read by
the baseline driver's callback PC. Count the first byte only, once per
GetStat. Count writes to the low counter byte once per increment, including
its rollover to zero. The analyzer rejects overflow, resets, mismatched
driver addresses, and intervals without established observation coverage.
Frame callbacks measure independent video cadence, **not actual IRQ line
assertions**. Frame-aligned process samples are not CPU percentages.

The earlier private observer was extended for the initial baseline. Its
clock watch began during the first idle song, so that song is excluded
from clock-count comparisons. PSG integrity and duration remain usable.
A first disk profile used the wrong storage address and is excluded from
clock measurements. The subsequent verified address was `$5700`, code
`$2000`; these are evidence for that guest only.

## Measured clock-source findings

* Idle clock probe: 600 ticks and 600 video acknowledgements over
  10.012308 seconds. This interval includes probe overhead and initial phase.
* Five idle synthetic30 repeats: 30.019764, 30.035278, 30.034684,
  30.034694, 30.034694 seconds. Duration error +0.06588% to +0.11759%.
  All 210 PSG pairs and final mute matched in every run. **PASS**.
* Fully observed idle playback: 1,800 acknowledgements and 1,800 clock
  increments per song. Maximum observed acknowledgement-to-increment
  latency was 195.6 microseconds.
* A 31.657427-second periodic-floppy observation contained 1,897 video
  frame callbacks, 1,581 video acknowledgements, 1,581 clock increments,
  2,864 GetStat calls and 200 FDC commands. Nominal clock progress was
  only 26.35 seconds. The largest acknowledgement gap was 123.929 ms;
  maximum acknowledgement-to-increment latency was 159.2 microseconds.
* Five periodic-floppy synthetic30 repeats: 35.730326, 35.765382,
  35.962456, 36.060076, 35.608290 seconds, +18.6943% to +20.2003%.
  All pairs and mutes matched. Duration target: **FAIL**.
* Four complete profiled floppy songs contained 1,800 / 1,799 / 1,800 /
  1,800 acknowledgements and exactly the same number of clock increments.
  The clock deficit was 5.61–6.06 seconds. Each song made 3,250–3,267
  GetStat calls; longest acknowledgement gap reached 138.896 ms.
  Acknowledgement-to-increment latency remained at most 159.2 microseconds.
* Relative to the first PSG write, event positions lagged their nominal
  sample positions by at most 8 / 6 / 10 / 8 **serviced ticks** in those
  four runs. Epoch uncertainty is about one tick. Thus player delivery
  latency exists even after clock loss is factored out. Maximum local
  half-second event-interval excess was 326.3–347.7 ms. These are event
  delivery measurements, not isolated dispatcher execution costs.

This separates missing clock progress from delayed handling **after an
acknowledgement**. It does not distinguish CPU HALT from IRQ masking, nor
directly timestamp the initial assertion of each video interrupt. MAME's
GIME implementation latches pending IRQ bits by OR, rather than counting
every edge. Multiple vertical-border events before acknowledgement can
therefore coalesce. The matching serviced-count deficit supports that
mechanism; it is not evidence that GetStat itself loses ticks.

Reference: [MAME 0.289 GIME source](https://github.com/mamedev/mame/blob/mame0289/src/mame/trs/gime.cpp),
`enter_bottom_border`, `interrupt_rising_edge`, and IRQ-status reads.

## Optimization under test

The checkpoint wakes and reads the clock for each tick even when the next
event is many ticks away. `cctpark` is an opt-in comparison build using
`CLOCK_PARK_LONG`. For a positive remaining distance `d`, it requests
`F$Sleep X=max(2,d)`. In this EOU boot, positive sleep requests count one
fewer tick than X, so longer waits normally wake one tick before the target.
Every wake still reads the atomic clock and compares the unchanged absolute
deadline. Signals and errors retain the existing cleanup path. This is not
an estimate of elapsed time from the requested sleep count.

The distance is bounded to 90 ticks by the existing sequential 16-bit wait
decoder. The change uses 6809 instructions and no extra data storage.
Fractional samples, deadline rollover arithmetic, ordered PSG writes,
32-command yield budget and MPI transactions are unchanged. No repeated
register write is removed, including envelope control writes.

Build identity: 9,658 bytes, data 1,983 bytes, CRC `827191` Good.
The checkpoint player remains 9,653 bytes, CRC `B3B649`; original `cctplay`
still rebuilds byte-for-byte. The candidate remains opt-in because the
all-workload timing target is not met; it is not promoted over `cctplaymt`.

## Before/after results

All durations use MAME emulated seconds and exact PSG-stream matching plus
the next final mute. Synthetic30 begins with a sample-zero write. Arkanoid
and Ark1 have 276 initial samples, added as a nominal startup **estimate**.
No captured sound-register event was dropped or reordered in the accepted
runs. Early baselines used throttling and CoreAudio; paired long-wait,
candidate, counter and continuous-read profiles used `-nothrottle -sound
none`. These are guest-time comparisons, not host CPU or listening tests.

| Synthetic30 workload | Repeats per build | Checkpoint mean duration error | Candidate mean duration error | <1% |
| --- | ---: | ---: | ---: | --- |
| Idle | 5 | +0.10608% | +0.07513% | PASS |
| Counter | 5 | +0.11003% | +0.08528% | PASS |
| Periodic floppy reads | 5 | +19.41769% | +19.35063% | FAIL |
| Back-to-back read-only operations | 2 | +67.80224% | +68.38002% | FAIL |

The small differences between builds are not evidence that longer parking
fixes disk timing. The synthetic fixture's one-tick waits use the same
sleep request in both builds. Candidate periodic-floppy worst local
half-second-interval excess reached **431.5 ms**, versus 347.7 ms for the
checkpoint; there is no claim of improved disk jitter.

`diskbusy` performs the same 230 open/read-256/close operations as `diskload`
with the inter-operation sleep omitted. `busybase` and `busypark` fork that
reader plus one synthetic30 player and reap both children. In both repeated
comparisons, the reader was active throughout playback, then exited normally.
Checkpoint durations were 50.333653 / 50.347690 seconds; candidate durations
were 50.405219 / 50.622792 seconds. The four intervals had 1,802 / 1,800 /
1,796 / 1,804 serviced ticks, with exactly matching clock increments.
Their clock deficits were 20.30–20.56 seconds. The maximum observed
acknowledgement-to-increment delay remained 159.3 microseconds.

The long30 fixture uses thirty 44,100-sample waits, with 35 PSG pairs.
Two accepted paired observations measured:

| Build | Durations (s) | GetStat calls during playback | Data bytes |
| --- | --- | --- | ---: |
| Checkpoint | 30.036066, 30.029093 | 1,830, 1,830 | 1,983 |
| Candidate | 30.027423, 30.023586 | 89, 90 | 1,983 |

This is **95.1% fewer clock calls** for that fixture, not 95.1% less total
CPU usage. End-to-end duration remains within 0.13%; all 35 pairs and mute
match. Code size rises five bytes including the shorter module name, with
no extra driver, queue, user data or interrupt-off section. Exact CPU
percentage and total clock-call cycle cost remain unmeasured. Integer
division and decoder arithmetic were left unchanged: the current evidence
does not identify them as the cause of accumulated disk slowdown.

| Real track / condition | Checkpoint estimated s | Candidate estimated s | Integrity |
| --- | ---: | ---: | --- |
| Arkanoid VGM, idle | historical clock baseline in design doc | 4.433066 | 266 pairs + mute |
| Ark1 CCT in M3U, idle, two runs | not rerun paired | 4.434074, 4.431203 | 266 pairs + mute each |
| Flicky CCT in M3U, idle, two runs | not rerun paired | 20.121051, 20.120846 | 820 pairs + mute each |
| Arkanoid VGM, periodic floppy | 5.384605 | 5.218094 | 266 pairs + mute each |
| Ark1 CCT, periodic floppy | 5.527782 | 5.449121 | 266 pairs + mute each |
| Flicky CCT, periodic floppy | 23.880502 | 24.057886 | 820 pairs + mute each |

The real-track disk rows are single observations per build, not repeatability
statistics. `diskreal` and `parkreal` run the same three-track order and
bounded reader. Distinct startup phases are not controlled closely enough
to interpret the smaller candidate Arkanoid duration as an improvement.

## Resource and stop checks

* **PASS:** Candidate infinite-loop fixture stopped via preloaded `cctstop`
  sent to its independently verified PID. Final PSG pair `07=3F`, final MPI
  `$FF`; no further PSG writes during 99.8 emulated seconds of observation.
  Free process RAM was **1,800 KiB before and after**. This aggregate check
  does not prove every system allocator or IRQ-table entry leak-free.
* **PASS:** Two overlapping `clkprobe` processes opened the same device.
  Ordered snapshots were 0, 70, 605, 670. Closing the first path did not
  reset or stop the second path's clock. After the final close, the observed
  VIRQ table contained no packet. Neither probe writes PSG data.
* **PASS with limits:** Removing the explicit `iniz` attachment cleared the
  VIRQ entry; unloading the two known preload links prevented playback,
  leaving only the cleanup mute. Reloading `clockpack` restored a complete
  long30 playback. IRQ-poll-table absence was not independently decoded.
* **PASS:** Packed test helpers stage and load, retaining one preload link.
  Foreground supervisors print `DISKBENCH OK` and reap their children.
* **NOT RUN:** Detailed system-allocation accounting, full 32-bit rollover,
  and a new on-demand floppy-loaded `cctstop` test for the candidate.

Shell+ does not automatically reap every asynchronous child while idle at
its prompt. Accumulating background benchmark jobs eventually produced
`Error #207` before a new player could start. The descriptors had `Dead`
set and cleared DAT images. Shell+'s built-in **`W`** collected their exit
statuses; subsequent foreground playback worked without reset. The command
is `W`, not the external pathname `wait`. Use foreground supervisors for
batch tests, or `W` after background jobs finish. The failed launches emitted
no music and are excluded from timing statistics. This is an observed test
harness resource failure, not evidence of a player RAM leak.

One later MAME process exited with a host exception after 35,244 emulated
seconds at approximately 37x speed: `Something went very wrong,
ppos=4497744344, pbase=202942687, pbase+wp=203027050`. That in-progress capture
was lost and excluded. The cause is unresolved; it is **not classified as
an OS-9 reboot**. The final candidate real-track disk comparison was rerun
in a fresh emulator session from the private idle checkpoint. Earlier saved
captures remain valid within their recorded no-reset/zero-overflow bounds.

## Fine timing and output queue decision

A relative CPU delay after a coarse tick cannot identify time spent
descheduled and does not repair lost video ticks. It could refine spacing
within an uninterrupted burst, but its wall-time accuracy under disk load
remains unproven. Do not claim sample accuracy or add such a delay without
a measured, independent fine-time source.

A possible bounded system-context queue would require explicit sound-device
ownership, producer/consumer indices, wrap-safe timestamp comparison,
underrun/stop handling and teardown while IRQ dispatch may be active.
For sizing only, 256 entries of four timestamp bytes plus register/value
consume 1,536 bytes before indices, driver storage and code; eight-byte
entries consume 2,048 bytes. Level II system-map pressure matters even with
2 MiB of physical RAM. Neither size guarantees enough musical lookahead:
coverage depends on event density. A drain limit must be derived from a
measured per-write cost and interrupt-latency budget. Those costs and a safe
limit are **NOT MEASURED**. This queue would still stop during globally
masked IRQs or CPU HALT and would not recover coalesced clock ticks.
No queue is implemented or recommended as a proven disk-timing remedy.

## Real hardware and limits

These are MAME floppy measurements, not physical CoCoSDC or Mega Mini
measurements. CoCoSDC transfer latency, IRQ masking and MPI save/restore
depend on the installed driver and cartridges. Mega Mini routing and
hardware ownership require separate tests. No claim about their timing
follows from the emulated floppy result.

Exact player CPU utilization, total time inside disk calls, actual video
IRQ assertions, full counter rollover, human listening, physical hardware,
6809 and PAL remain **NOT RUN**. FDC command counts are not disk-call time.
The full real-track × workload × repeat matrix, a separate normal Shell
command-loading timing series, and mouse responsiveness were not completed
in this pass. The all-workload final success criterion remains **FAIL**.

## Reproduction and rollback

```
bash scripts/build.sh
# Use an unmounted private disk and the existing privately held fixtures.
# Load clockpack; iniz ctclock; load the player and packed workload helpers.
# load perfpack       (idlebench, countbench, diskbench, parkidle, parkcount,
#                      parkdisk, diskreal, diskload, countlong and probes)
# load busypack       (busybase, busypark, diskbusy)
# Run one supervisor at a time and wait for its workload child to exit.
# performance_start: {code: <verified system address>, storage: <verified U>}
# performance_finish: {path: <project-private JSON output>}
python3 scripts/summarize-psg-repeats.py <fixture> <capture>
python3 scripts/analyze-clock-progress.py <capture> \
  --start <first-write-time> --end <mute-time> \
  --code <verified-address> --storage <verified-address>
```

The observer buffer holds at most 500,000 events; any overflow invalidates
the capture. Avoid overlapping players and PSG-marker probes. `cctplaymt`
and `cctcycle` retain the original comparison engines; selecting either
instead of `cctpark` rolls back the experiment without changing the boot.
Private traces, media, copyrighted music and generated modules are ignored.
Their retained filenames, sizes and SHA-256 identities are recorded in
[performance-evidence.json](performance-evidence.json). Evidence is under
`emulator/images/performance/`; screenshots include `mfree-before.png`,
`mfree-after2.png`, `after-w.png`, and `two-clock-paths.png` in its
`snapshots/` directory. The original executable SHA-256 remains
`eabe6b6f3910ebd1af557f64b02c1fb1e1802a3a07a1bf134016b1a4a6792f36`.
