# Clock reliability and practical background-playback limits

Investigation from `45217eb`, 2026-10-30/31. Target: MAME 0.289,
HD6309 EOU Level II, 2 MiB, NTSC, existing CoCoPSG in MPI slot 2.
No player, kernel, driver, boot, hardware support or tempo changes were made.
`cctplay`, `cctplaymt`, `cctcycle` and opt-in `cctpark` remain available.

## Decision

The existing architecture works well for an idle Shell and the lightweight
counter. It **does not yet establish acceptably smooth playback across ordinary
activity**. Even VHD command launches that lose no ticks can delay register
updates by over a second. Absolute deadlines recover total duration afterward,
not the missed musical articulation. Conventional floppy activity additionally
loses clock ticks, which this scheduler cannot recover.

Keep `cctpark` as the low-overhead opt-in build. Keep common utilities resident
where practical; this improves the measured launch case but does not eliminate
jitter. Do not compensate by speeding up songs, filtering PSG writes, disabling
scheduling, or preventing disk access. A bounded output queue merits a separate
ordinary-workload experiment on paper; it is not a remedy for HALT or masked
interrupts and is not implemented here.

## Measurement and uncertainty

`tools/reliability-observer.lua` runs outside the guest. It samples saved MAME
CPU/GIME state through `emu.item` and a coroutine using `emu.wait`. It observes
actual guest reads of `$FF92` through a read tap; it never reads that hardware
register itself. Taps return nil and preserve guest accesses. Separate taps
record PSG writes, MPI writes, FDC commands, clock GetStat snapshots and atomic
counter increments. The driver header/CRC and one-tick VIRQ packet are checked
before installing its address-specific taps. These offsets apply only to the
184-byte CCTClock, CRC `8F5EED`; re-establish addresses after reload.

A BODY-to-BOTTOM_BORDER video-state transition identifies generation of VBORD.
MAME's `mc6847_friend_device::next_scanline` enters the border and calls GIME's
`enter_bottom_border`, which raises then lowers VBORD in that callback. IRQ
master and VBORD enables remained set (saved register values `$6C`, `$09`).
This observes generation even while the CPU is halted, unlike a guest counter
or a frame callback used as an unqualified IRQ count. It does not imply a new
IRQ pin edge when the line is already asserted.

Primary implementation references:
[MAME video engine](https://github.com/mamedev/mame/blob/mame0289/src/devices/video/mc6847.cpp),
[GIME](https://github.com/mamedev/mame/blob/mame0289/src/mame/trs/gime.cpp),
[CoCo floppy controller](https://github.com/mamedev/mame/blob/mame0289/src/devices/bus/coco/coco_fdc.cpp),
[CPU execution state](https://github.com/mamedev/mame/blob/mame0289/src/emu/diexec.h),
[Lua coroutine waits](https://docs.mamedev.org/luascript/ref-common.html), and
[pass-through memory taps](https://docs.mamedev.org/luascript/ref-mem.html).

Root-cause captures use 10 microsecond sampling; ordinary workloads use 100
microseconds. Maximum recorded sampling gaps agree with those intervals within
floating-point precision. PSG, acknowledge and counter taps are timestamped
at the access, independently of sampling. CPU HALT (input line 66), CC.I/CC.F,
and process/task residency are **sampled estimates**, not instruction traces.
Short mask transitions can be missed; summed occupancy error can accumulate
across many transitions. The category at a video edge has up to one sample
interval of uncertainty. Overlap between HALT and masking is reported as
**overlap**, not assigned exclusively to either mechanism.

At 100 microseconds, the IRQ may already be acknowledged before the video-zone
sample. The analyzer associates an edge with that immediately preceding ACK
only if the sampled pending bit is clear and the ACK is within the sampling
gap. Otherwise naïve grouping incorrectly reports coalescence even at idle.
The first incomplete ACK group is excluded. Playback boundary counts have
one-edge phase uncertainty. Fully bounded groups reconcile with the count
deficit in the reported runs.

Process identity is derived from the system DAT image. The final observer
validates the descriptor against D.PrcDBT and reports unknown during temporary
mapping transitions. Early captures did not perform that validation; their
system-context owner counts must not be treated as CPU accounting. User-task
residency is more useful but still sampled. Kernel/IRQ/idle work attributed to
a current PID is not necessarily CPU work caused by that process.

The sampler stops after a bounded duration, restores throttling, and caps the
buffer at 1,500,000 events. Overflow, discontinuity, disabled VBORD or incomplete
PSG streams invalidate analysis. The first continuous-read capture overflowed
the earlier 600,000-event cap and is **rejected**; its replacement retained
800,330 events with zero drops. No results below use the rejected capture.

## Root cause: generated versus serviced time

Intervals run from the first sample-zero synthetic PSG data write to the final
mute. Synthetic30 contains 1,800 waits of 735 samples and all 210 register pairs.

| Workload | Emulated seconds | Video generations | Video ACKs | Atomic ticks | Lost/coalesced edges |
| --- | ---: | ---: | ---: | ---: | ---: |
| Idle | 30.028806 | 1,800 | 1,800 | 1,800 | 0 |
| Periodic floppy | 35.707687 | 2,140 | 1,800 | 1,800 | 340 |
| Continuous floppy | 50.417783 | 3,022 | 1,796 | 1,796 | 1,226 |

Every serviced video ACK produced a clock increment. Maximum observed
ACK-to-increment latency was 186.6 microseconds idle, 159.2 microseconds in
both disk cases. This is dispatch latency after acknowledgement, not latency
from original video generation. There is no measured loss inside the atomic
clock counter.

For fully bounded ACK groups, extra edges occurred in these sampled states:

| Workload | HALT and IRQ masked | IRQ masked, HALT clear | HALT only / neither |
| --- | ---: | ---: | ---: |
| Periodic floppy | 315 | 25 | 0 / 0 |
| Continuous floppy | 1,148 | 78 | 0 / 0 |

At nominal 60 ticks/second, the periodic categories represent 5.250 and
0.417 seconds of missing clock progress; continuous categories represent
19.133 and 1.300 seconds. The measured clock deficits are 5.708 and 20.484
seconds. Remaining differences include NTSC video cadence versus nominal 60,
start/end phase and output scheduling. These are count-based contributions,
not a claim that removing HALT alone would restore ticks while CC.I stays set.

Sampled periodic occupancy: 8.050 s HALT+IRQ mask, 4.610 s IRQ-mask-only,
23.048 s neither. Continuous: 29.954 s overlap, 6.203 s IRQ-mask-only,
14.261 s neither. CC.F was set for approximately 12.651 and 36.151 s,
respectively. These are platform-wide intervals, including the disk driver
and kernel, not long interrupt-off regions introduced by the player.
Masked time is not equal to lost time: a pending bit can retain one event,
and short critical sections need not cross more than one video boundary.

The source mechanism matches the observations. The emulated FDC asserts HALT
when DRQ is false and the DSKREG HALT-enable bit is set. GIME ORs each new
interrupt into a pending bit; reading IRQ status clears pending bits. It has
no queue containing the number of elapsed vertical events. The existing
clock's VIRQ work runs once per serviced video tick, not once per missed edge.

Serviced-clock lateness is separate. Periodic playback still lagged by up to
nine serviced ticks relative to the first-write epoch. Continuous playback
lagged by up to eight ticks relative to its captured initial clock snapshot.
Its first PSG write followed that snapshot by 219 ms; measuring only from the
first write would hide startup delay and produce apparent negative tick-domain
errors. Where available the analyzer uses the initial snapshot as the epoch.

## Ordinary activity versus stress

All following captures verified the complete ordered 210-pair stream and final
`07=3F` mute. Timing is emulated time, not host time. A local excess compares
successive nominal half-second event intervals; accumulated lateness compares
each event with its absolute sample position. Neither metric alone establishes
subjective audio quality. These new rows are single runs, not repeatability
statistics; five-run earlier idle/counter/disk comparisons remain in
[PERFORMANCE-OPTIMIZATION.md](PERFORMANCE-OPTIMIZATION.md).

| Workload | Duration s | Error | Worst local excess | Worst accumulated lateness | Clock calls |
| --- | ---: | ---: | ---: | ---: | ---: |
| Idle, 10 us observer | 30.028806 | +0.096% | 0.636 ms | 28.7 ms | not instrumented |
| Concurrent counter | 30.024747 | +0.082% | 0.635 ms | 24.6 ms | 3,599 |
| Three `dir /dd` | 30.032903 | +0.110% | 273 ms | 297 ms | 3,472 |
| Launch pwd, mfree, echo | 30.033052 | +0.110% | 1,535 ms | 1,537 ms | 3,384 |
| Three small-file listings | 30.033058 | +0.110% | 1,412 ms | 1,428 ms | 3,247 |
| Resident pwd/list/pwd | 30.027501 | +0.092% | 260 ms | 276 ms | 3,538 |
| Three `dir /d1` | 33.103841 | +10.346% | 719 ms | 3,110 ms | 3,449 |
| Periodic floppy reads | 35.707687 | +19.026% | 326 ms | 5,708 ms | not instrumented |
| Sustained floppy reads | 50.417783 | +68.059% | 685 ms | 20,418 ms | 2,224 |

Shell inputs were posted at 10, 20 and 28 seconds after capture start, with
playback launched in the background. The command row uses `/dd/cmds/pwd`,
`/dd/cmds/mfree`, then Shell `echo RESPONSIVE`. Small reads run
`/dd/cmds/list /dd/startup`: this includes opening, reading and printing the
small file, plus command-loading costs. It is not an isolated I$Read benchmark.
The resident comparison first loads pwd/list, then invokes their short module
names. It changes both residency and pathname lookup, so the improvement is
not a cycle-isolated measurement of the loader alone. Screenshots verify real
command output. `/dd` is the emulated VHD/EmuDsk path, **not CoCoSDC**.

VHD directory/command/read rows have 1,800 generations, ACKs and increments,
with no FDC commands. Thus their event stalls occur despite advancing time.
Player user-task entry gaps reached 1.559 s for command launches and 1.373 s
for small-file listings. These are dispatch/delivery gaps, not a measurement
of ready-queue wait alone. The resident case still has a 375 ms entry gap.
In that run, 1,794 ticks advanced with another validated process current;
being descheduled does not itself lose clock ticks.

The three floppy directory commands produced 28 FDC commands and lost 184
video edges (181 sampled during HALT+mask, three mask-only). Even occasional
conventional-floppy activity can therefore audibly disturb playback; the
problem is not confined to the sustained stress test.

The counter printed once per nominal second and continued through playback;
its foreground supervisor reaped both workloads. Shell commands and disk
reads completed, and final MPI selection was `$FF` in the fully instrumented
runs. Keyboard input is demonstrated by these commands. Mouse/GShell exercise
and human listening are **NOT RUN** in this investigation. Long held notes
follow from the measured register-update gaps; unchanged last registers are
not proof of audio silence or a stuck-note bug.

## Existing hardware and OS services

No safe process-readable, sufficiently resolved independent elapsed-time clock
was established for this CoCo 3 configuration. The detailed prior service
audit remains in [CLOCK-SCHEDULER-DESIGN.md](CLOCK-SCHEDULER-DESIGN.md):

* `F$Time` returns a writable, seconds-resolution calendar, not a monotonic
  fine clock. Optional Clock2 hardware does not create a universal timestamp
  API or justify assuming every EOU machine has an RTC.
* This boot returns `E$UnkSvc` for `F$TPS`; a rate query would not count elapsed
  ticks anyway. `F$Sleep` counts serviced ticks and is not an elapsed clock.
* `D.Tick` is private system state and advances through serviced video IRQs.
* `/nil` VRN's destructive SS.VCtr read has the previously documented
  copy/reset race. Even a repaired snapshot would inherit missing video ticks.
* GIME timer reload registers are write-only; ordinary reads return floating
  bus in the model. IRQ status is destructive and shared. There is no readable
  free-running counter or missed-expiration count exposed by these registers.
* PIA/keyboard polling and CPU loop counts do not supply time while halted or
  descheduled. Reassigning GIME timer/IRQ ownership is outside this investigation
  and would still not allow handler execution during HALT/masking.

See the [EOU technical reference](https://www.lcurtisboyle.com/nitros9/EOUDOCS/NitrOS-9_EOU_Level_2_Technical_Reference_Manual.pdf),
and the inspected [NitrOS-9 clock source](https://github.com/nitros9project/nitros9/blob/f470fa52eb172b59b22c1b722074998cb42de9b1/level2/modules/clock.asm).
Reference source revision is `f470fa52eb172b59b22c1b722074998cb42de9b1`;
it is not assumed byte-identical to every installed EOU component. Previously
identified live modules were Clock `972B38`, Krn `9D89BE`, SCF `3508DD`,
rb1773 `FBAA3C`.

## Physical CoCo 3 / CoCoSDC / Mega Mini MPI procedure

1. Record CPU, RAM, NTSC/PAL, EOU version, module identities (`ident` for clock,
   kernel, SCF, RBF stack and disk drivers), SDC firmware, MPI revision, slot
   routing and cartridge arrangement. Preserve a backup boot. Do not change
   the kernel, install a new IRQ source or import ROM/music into Git.
2. Identify the actual disk path. Conventional WD1773-compatible floppy
   emulation through `rb1773` is distinct from native SDC command mode through
   `rbsuper`/`llcocosdc` and its descriptors. Confirm the installed modules and
   descriptors; the presence of an SD card or `.DSK` file does not identify the
   transfer protocol. MAME EmuDsk/VHD and rb1773 tests verify neither native SDC
   latency nor physical Mega Mini routing.
3. Inspect the matching installed SDC driver before predictions. In the
   reference `llcocosdc`, CommSDC selects/restores MPI, sends native commands at
   `$FF40/$FF48`, polls status and transfers a 256-byte response. It masks
   IRQ/FIRQ when a conventional FDC is detected; the 6309 TFM receive path also
   explicitly masks interrupts. Its initialization disables SDC floppy
   emulation. Native access may reduce long mechanical/emulated waits, but
   cannot be presumed interrupt-friendly or HALT-free from these MAME tests.
4. Run the same generated synthetic30 and long30 fixtures, plus privately
   supplied VGM, CCT and M3U, first idle, then with counter, three directory
   listings, ordinary command launches, small reads, periodic reads, sustained
   reads. Run each case at least five times and distinguish cold command loads
   from resident commands. Test native SDC and floppy-emulation boot/driver
   configurations separately, with and without a conventional FDC if supported.
5. Record audio externally and compare event/track timing to an independent
   host timebase. If suitable passive equipment is available, capture video
   sync, HALT, IRQ/FIRQ pins, bus addresses/data for PSG/MPI writes and IRQ
   acknowledge reads. Pins alone do not reveal CC.I/CC.F: do not infer masks
   from IRQ assertion without service. Do not use guest serviced ticks as the
   reference for proving those same ticks accurate.
6. While playing, demonstrate visible counter progress, Shell input, GShell
   mouse/window activity and disk reads. Exercise stop during load/wait/loop/
   playlist transition, then immediate restart. Check mute, original MPI slot,
   memory/path/module state before and after repeated runs. Record audio gaps,
   missing/reordered writes, maximum lateness and timing error with PASS/FAIL/
   NOT RUN, not just subjective “sounds fine”.

Native SDC source reference:
[llcocosdc.asm](https://github.com/nitros9project/nitros9/blob/f470fa52eb172b59b22c1b722074998cb42de9b1/level1/coco1/modules/llcocosdc.asm).
All physical tests above remain **NOT RUN**. MMMPI OPL hardware is a separate
future sound target; this plan does not add support or claim its compatibility.

## CPU and system-call overhead; optimization choices

The unchanged long-wait candidate was rechecked on long30 (thirty one-second
waits, 35 PSG pairs). At 100 us sampling:

| Build | Duration | GetStat calls | Player user-task residency estimate |
| --- | ---: | ---: | ---: |
| `cctplaymt` | 30.030938 s | 1,830 | 0.5274 s (1.76%) |
| `cctpark` | 30.022653 s | 90 | 0.0517 s (0.17%) |

Both sequences and final mutes match. These confirm the existing 95.1% call
reduction and a substantial reduction in sampled user execution. Total
clock-system-call cycle cost and exact total CPU percentage are **NOT RUN**:
current-PID system residency includes interrupts, scheduler and idle work.
The approximately 0.53-to-0.05 s comparison must not be presented as exact
process-plus-kernel CPU usage or a universal percentage improvement.

Synthetic30 still makes roughly 3,600 calls when idle: each one-tick wait
normally checks before sleeping and again at the deadline. The finite counter
case used about 1.118 s of sampled player user-task time (3.73%). Fewer calls
under load are partly due to overdue events requiring no sleep, not an
improvement in achieved timing. Continuous reads used 2,224 calls while taking
50.4 seconds.

The smallest supported improvements are the already opt-in long-wait parking
and keeping common commands resident. Decoder batching already has a bounded
32-command yield budget. Removing that bound risks responsiveness; increasing
it has no demonstrated benefit against the measured missing-clock problem.
Integer division uses at most 89 subtract iterations per wait. It is a plausible
local CPU target, but these measurements do not identify it as the cause of
second-scale delivery gaps. No arithmetic rewrite is justified as a clock-loss
fix. Repeated quantized deadlines could eventually share a known-due result,
but that needs a separate dense-short-wait profile and stop/rollover validation;
no unmeasured cache is promoted here.

With only memory taps, synthetic30 took 30.025571 s versus 30.028806 s with the
10 us sampler; worst local excess was 0.636 ms in both. This single phase-varied
idle control finds no gross observer-induced slowdown; it does not establish
zero perturbation under disk load. HALT/mask occupancy has not been validated
against an instruction-exact trace or converged one-microsecond capture. The
fine root-cause counts and coarse ordinary cases reconcile generation/ACK/tick
counts, but their sampled occupancy precision must not be overstated.

Longest sampled contiguous HALT intervals were 100.53 ms periodic and 100.55 ms
continuous. Longest contiguous IRQ/FIRQ mask intervals reached 108.89 ms in
both. These are OS/platform limitations an event handler also faces.

## Next architecture, on paper only

An IRQ-driven bounded register queue could improve the **serviced-clock,
player-descheduled** cases: VHD command activity kept all 1,800 clock ticks,
while the producer had user-task entry gaps exceeding 1.5 seconds. A queue with
sufficient predecoded lookahead could continue consuming during such user
scheduling gaps. That is a measured reason to evaluate it, not a guarantee of
improvement: time spent inside non-reentrant shared device operations, MPI
ownership, interrupt masking, burst density, and refill deadlines still matter.

Before implementation, measure worst-case PSG transaction cost and choose a
strict per-IRQ drain budget. Determine lookahead from maximum **burst** event
density and measured producer gaps, not mean writes per second. A six-byte
(timestamp/register/value) record costs 1,536 bytes for 256 events before
indices/storage; 2 MiB physical RAM does not remove the 64 KiB system-map limit.
The design needs stop acknowledgement, ownership of MPI/sound ports, bounded
catch-up, underrun behavior, signal/playlist teardown and wrap-safe timestamps.
No parsing, allocation, disk I/O, blocking or printing belongs in the handler.

The current evidence supports researching that queue for ordinary scheduling
jitter. It cannot consume during HALT or a masked IRQ, cannot reconstruct lost
video edges, and does not fix the observed 19%/68% floppy slowdown. First measure
physical native SDC behavior before choosing a platform-wide next architecture.

## Regression status and evidence

* **PASS:** `bash scripts/build.sh`; module identification reports Good CRCs.
  `cctpark` remains 9,658 bytes, data 1,983, CRC `827191`; `cctplaymt` remains
  9,653 bytes, CRC `B3B649`. The original rebuild is byte-identical, SHA-256
  `eabe6b6f3910ebd1af557f64b02c1fb1e1802a3a07a1bf134016b1a4a6792f36`.
* **PASS:** Background synthetic VGM playback throughout the Shell workload
  matrix; all complete accepted streams contain every required pair and mute.
* **PASS:** Natural two-track M3U completion: Ark1 CCT 266 pairs, estimated
  4.434017 s (including nominal 276 initial samples), then Flicky CCT 820 pairs,
  20.113282 s. Ordered sequences, per-track mutes and final MPI `$FF` retained.
  The initial 45-second capture ended before the second track completed and
  is excluded from full-playlist acceptance; the 90-second rerun covers both.
* **PASS:** `-l f` looping fixture, independently verified live player PID 3,
  `cctstop 3`, ordered 85-pair prefix followed by `07=3F`, final MPI `$FF`,
  then 27.63 s without another PSG write. Shell `W` reaped the child; the
  process descriptor was absent afterward. Free process RAM was 1,784 KiB
  before and after. No reset or event overflow was reported. A prior run
  omitted `-l f` and completed normally; it is not counted as a stop test.
* **PASS:** Restarted CCT playback in the background after the stop: Flicky
  retained all 820 pairs and mute, 20.121277 s (+0.156%). Shell echo was
  injected during playback. The first 40-second attempt captured loading plus
  only 804 pairs; a 60-second rerun includes the complete stream.
* **PASS with limits:** MAME WAV recording contains non-DC audio and a quiet
  final second. Four-channel, 48 kHz, 16-bit capture; channel 1 (zero-based)
  whole-record mean-removed RMS 10,195.8 PCM counts, final second 0.424 counts.
  This verifies generated audio and quiet termination, not human-perceived
  smoothness. WAV capture uses MAME's documented sound recording API.
* **PASS:** Analyzer unit tests cover ACK-before-sample ordering, one real
  coalesced edge, overflow/discontinuity rejection, missing mute and disabled
  video IRQ. Count-conservation checks pass on the accepted workload captures.
* **NOT RUN:** Human listening, mouse/GShell responsiveness, physical CoCoSDC,
  Mega Mini electrical/routing behavior, PAL, 6809/512 KiB, exact CPU cycles,
  full 32-bit rollover and exhaustive system-allocation/path leak accounting.
  Aggregate memory equality is not proof that every kernel allocation is clean.

The guest retained its pre-existing explicit `iniz ctclock` attachment during
comparisons. A registered clock packet after a song is expected in that setup,
not evidence of a leaked player path. No driver lifetime code changed. Earlier
missing-clock, multiple-open and detach tests remain documented in
[PERFORMANCE-OPTIMIZATION.md](PERFORMANCE-OPTIMIZATION.md).

## Reproduction and rollback

Use a separate owned MAME guest and writable private media. Never stage an
image mounted by MAME. Build with `bash scripts/build.sh`; use the existing
private fixture and workload staging procedure. Keep driver/player/helper
packs loaded and `iniz ctclock` across the comparison. Run only one workload
at a time; foreground `parkdisk`, `busypark` and `parkcount` supervisors wait
for their workload children **after** audio ends. For direct background runs,
use Shell+ `W` to reap completed children before the next test.

Load the addon into the private bridge:

```lua
dofile('tools/reliability-observer.lua')(commands, mark_array, json_encode)
```

Then issue bridge commands (addresses shown identify this guest only):

```json
{"cmd":"reliability_speed","params":{"fast":true}}
{"cmd":"reliability_start","params":{"interval_us":10,"duration":45,"path":"emulator/images/reliability/logs/example.json","code":8192,"storage":22272}}
{"cmd":"type","params":{"text":"parkdisk{ENTER}"}}
```

Create the output directory first. `reliability_status` reports completion;
never reload the addon while active. Optional `inputs` contains ordered
`{"after":10,"text":"dir /dd{ENTER}"}` entries relative to capture start.
The caller must ensure that these are authorized Shell inputs and playback
runs in the background. They are posted through the natural keyboard, not
written into guest memory. Verify actual command output, since an input record
alone does not establish successful execution. `reliability_audio` starts WAV
recording with a project-private `path`; omit `path` to stop it.

```sh
python3 scripts/test-clock-reliability.py
python3 scripts/analyze-clock-reliability.py build/synthetic-30s.vgm \
  emulator/images/reliability/logs/periodic-10us.json
python3 scripts/summarize-psg-repeats.py <private-fixture> <capture.json>
```

Machine-readable results are in
[clock-reliability-results.json](clock-reliability-results.json). Raw traces,
audio, screenshots, fixtures and media remain ignored, with hashes recorded in
[clock-reliability-evidence.json](clock-reliability-evidence.json). No private
music, ROM, media or generated binaries are added to Git. The host bridge copy
is private and is not supplied by a clean checkout; the checked-in addon and
commands above document its required integration.

Rollback consists of removing the host observer addon; no guest or boot change
needs undoing. Continue choosing `cctpark`, `cctplaymt` or `cctcycle` explicitly.
No push is part of this investigation.
