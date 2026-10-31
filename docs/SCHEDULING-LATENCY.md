# Scheduling latency during ordinary EOU activity

Investigation following `5753add`, 2026-10-31. MAME 0.289, HD6309,
2 MiB, NTSC EOU Level II, CoCoPSG slot 2; private writable media only.
No player, clock driver, kernel, disk driver or timing constants changed.

## Result and smallest supported improvement

The existing process scheduler cannot guarantee smooth music during ordinary
command loading. The player becomes **ready but cannot run while system-mode
work continues**. Raising its priority does not remove the approximately
1.5-second interruptions. Absolute deadlines subsequently catch up; accurate
song duration is not smooth articulation.

Keeping a frequently used utility resident and invoking its short module name
is a useful, limited operational improvement. In the measured `pwd` comparison,
maximum event lateness fell from 1.41–1.53 seconds to 27–145 milliseconds.
This changes both residency and pathname lookup, so it is not an isolated
measurement of loader cost. It does not fix directory or file operations.
No production priority option or speculative decoder optimization is justified
by these results. `cctpark` stays opt-in and all comparison builds remain.
The general ordinary-activity success criterion remains **unmet**.

## Method and reproducibility

Build diagnostic helpers with `bash scripts/build-scheduling-tools.sh`.
The test-only `cctnice 128..160 <cctpark arguments>` forks the player, applies
`F$SPrior` to that child only, waits and reaps it. It does not forward signals;
identify and signal the actual player when stopping it. The normal build is
unchanged. `musicdisk` and `musicbusy` fork a finite reader and three actual
music tracks, avoiding host keyboard injection while floppy I/O is active.
`diskstress` performs 920 read-only open/read/close cycles of 256 bytes.

Load `tools/reliability-observer.lua` through the private bridge, then invoke
`reliability_load_scheduling`. `scheduling_start` takes the verified cctpark
base 49152, target offset 709 and call offsets: Epoch 7480, Budget 7565,
GetStat 7692, Sleep 7739. These are version-specific, not a public ABI.
The sampler verifies the player's module identity before accepting call taps.
`scheduling_series` with `first`/`last` selects the eight cases in
`tools/scheduling-workloads.lua`; preconditions and required resident helpers
are documented there. Do not reload observers while captures are active.

Host-only instruction-fetch and memory taps record actual PSG writes, atomic
clock snapshots, user SWI2 calls and returns. Queue samples use 500 us for
priority runs and 1 ms for music; clock/HALT/mask sampling uses 100 us.
Read taps return no replacement value. No process memory or guest hardware is
modified by instrumentation. The analyzer excludes pre-interrupt opcode
prefetches (PC at the opcode rather than one byte past it). Queue residency
and executing-module attribution are sampled estimates, not instruction-exact
CPU accounting. Unknown/mapping-transition intervals remain unassigned.
The process/queue sampler follows its first identified player PID; later playlist
children are validated by PSG sequences, not attributed to that first PID.
Module ranges are a startup snapshot; subsequently loaded modules can remain
unknown. The single-player priority cases supply the queue diagnosis.

Run `scripts/summarize-scheduling-calls.py CAPTURE...` and
`scripts/analyze-scheduling-music.py FIXTURE_DIRECTORY CAPTURE...`.
Fixtures are privately held `arkanoid.vgm`, `ark1.cct`, `flicky.cct`.
Music inputs occur 0.2 seconds after each track's first PSG data write.
Synthetic priority runs use `synthetic30.vgm`, full-path `pwd` and `mfree`
commands at capture seconds 10 and 20, and `echo RESPONSIVE` at 28.
Raw captures and WAV files remain ignored; portable results and hashes are
beside this document. Do not treat human audio listening as completed merely
because a WAV exists.

## Where the long delay occurs

In `lat-p128-1`, the player calls `F$Sleep(X=2)` at emulated second
5878.6586151671. Its last clock snapshot is tick 330526; its deadline is
330527. That tick is serviced at 5878.6661312082. The first sampled active
queue membership is 5878.6679198977, but Sleep returns only at
5880.1634079563: **1.504793 s** after entry.

Of that interval, sampled residency assigns 9 ms to the sleep queue,
1.475488 s to the active queue, about 20 ms to unknown transitions, and
0.3 ms to current system execution. Ninety clock ticks advance. Thus this
is primarily A (ready without CPU), caused by D (system-mode execution),
not a request to sleep for 1.5 seconds or lost video time.

At priority 160, a 1.5385-second interruption includes about 0.9845 s
sampled in Shell's RBF system context, 0.2725 s in process 1's Krn,
0.050 s in Shell's Krn and 0.037 s in IOMan. This is sampled attribution,
not proof that every instruction in each module blocks scheduling.
In priority 129's overlapping Shell work, I$Open takes 470.206 ms,
F$NMLoad 517.175 ms and F$Fork 493.581 ms. I$ReadLn also includes waiting
for keyboard input and must not be counted as disk transfer time.

The inspected NitrOS-9 reference (commit
`f470fa52eb172b59b22c1b722074998cb42de9b1`) has a system-state IRQ path
that services D.SvcIRQ and returns to interrupted system work; user-state
interrupt handling has the scheduling path. This agrees with live queue,
PC/module and tick evidence. The reference tree is not asserted byte-identical
to EOU: installed Krn CRC 9D89BE, RBF 53B416, SCF 3508DD, EmuDsk CF433F.
`F$SPrior` changes process priority, not the kernel's preemption rules.

### Clock service latency

A default-priority GetStat enters at 5880.1730879603, reads the atomic clock
at 5880.1736075795, and returns at 5880.3202033470. The snapshot occurs
0.520 ms after entry; another **146.596 ms** elapses before the user resumes.
The call's 147.115 ms duration includes 140.783 ms confirmed on the active
queue. Median GetStat is 0.783 ms, p99 0.950 ms in this run.
This does not establish SCF serialization as the bottleneck: the clock read
already completed. A faster interface would not make a ready user process
preempt system work. No unsafe direct clock access is introduced.

## Priority experiment

Default observed priority is 128. Every accepted synthetic run preserves all
210 ordered PSG pairs and the final mute, restores MPI to FF, and has equal
video-edge, acknowledgement and clock-tick counts (1799 or 1800 depending
on phase). No long mask/HALT interval accounts for these interruptions.

| Priority / run | Duration s | Maximum event lateness s | Maximum local excess s | Clock calls | User-task residency s |
|---|---:|---:|---:|---:|---:|
| 128 / 1 | 30.021788 | 1.486227 | 1.491582 | 3384 | 1.052388 |
| 128 / 2 | 30.027036 | 1.484131 | 1.488825 | 3382 | 1.052836 |
| 129 / 1 | 30.021702 | 1.483849 | 1.489290 | 3385 | 1.056202 |
| 136 / 1 | 30.021460 | 1.482998 | 1.490307 | 3392 | 1.057060 |
| 160 / 1 | 30.036182 | 1.484166 | 1.479715 | 3394 | 1.056882 |

Event error is measured against decoded waits, not raw inter-write gaps.
These are small-sample comparisons; no statistical latency guarantee follows.
The repeat at 128 confirms the long-gap behavior. An attempted second 160
capture is excluded because host keyboard queues overlapped at second 20.

Synthetic p95/p99 event lateness in seconds is .768/1.486 (128 run 1),
.755/1.484 (128 run 2), .769/1.483 (129), .643/1.483 (136), and
.643/1.484 (160). The upper tail remains effectively unchanged.

User-task residency is approximately 3.5% of playback, excluding kernel work
on the player's behalf. Reported system-task residency also includes interrupt
and mapping attribution ambiguity, so it is not exact player CPU consumption.
The original long-wait clock-call reduction (1830 to 90) remains unchanged;
this short-wait synthetic fixture naturally has many more calls.

Shell ReadLn return through Fork return for `pwd`/`mfree`, respectively:
129: 1.507/1.412 s; 136: 1.772/1.404 s; 160: 1.506/1.408 s.
Shell commands finish, the concurrent counter progresses, and no improvement
in longest musical gaps is evident. These runs do not isolate disk throughput
from path lookup, loading and scheduling; a priority-dependent bytes/sec claim
would be unsupported. In the separate default-priority floppy music captures,
reader PID 4 returns 82 successful 256-byte reads during 180 s (20,992 bytes,
116.62 bytes/capture-second), and 230 during 360 s (58,880 bytes, 163.56
bytes/capture-second). These windows include startup and competition, periodic
sleeps where applicable, and only part of each finite reader; they are workload
progress rates, not raw device bandwidth or priority comparisons. Priorities 129–160 are diagnostic only, not recommended
defaults; maximum priority was not tested.

## Actual VGM, CCT and playlist matrix

Each ordinary case runs the same M3U: Arkanoid VGM, Ark1 CCT, Flicky CCT.
All 266, 266 and 820 expected PSG pairs, respectively, appear in order with
end mutes. Arkanoid and Ark1 have identical register streams and are assigned
by known playlist order. Duration estimates add the decoded initial wait to
first-write-to-mute elapsed time; event errors are anchored at the first write.
The result JSON includes p95/p99 errors, calls, tick counts and exact times.

| Workload | Estimated duration s (VGM / CCT / Flicky) | Maximum event lateness s (same order) |
|---|---|---|
| Idle Shell | 4.434 / 4.434 / 20.115 | .009 / .009 / .028 |
| Concurrent counter | 4.417 / 4.422 / 20.102 | .008 / .009 / .016 |
| Directory `/dd` | 4.432 / 4.434 / 20.115 | .338 / .320 / .354 |
| Full-path `pwd` | 4.432 / 4.434 / 20.115 | 1.451 / 1.529 / 1.408 |
| `list /dd/startup` | 4.880 / 4.872 / 20.110 | 1.362 / 1.617 / 1.199 |
| Resident short-name `pwd` | 4.434 / 4.434 / 20.113 | .145 / .127 / .027 |
| Periodic floppy reader | 5.401 / 5.218 / 23.645 | .976 / .804 / 3.560 |
| Sustained floppy reader | 6.904 / 7.818 / 32.967 | 2.478 / 3.392 / 12.885 |

Periodic floppy clock deficits over the write-to-mute windows are approximately
.978, .795 and 3.679 s (phase uncertainty of a tick). These are clock-loss
workloads, unlike the no-loss ordinary command synthetic runs. Preserve the
previous controlled 340/1226 lost-tick results in CLOCK-RELIABILITY.md;
these different songs and reader lengths are not replacements for that baseline.

The sustained 360-second capture includes all three complete tracks and mutes;
its clock deficits are 2.531, 3.462 and 12.867 seconds. The finite 920-read
reader continued after playback and was reaped before the next test. Severe
loading delays also separate these tracks; the table measures playback itself.

Audio was captured for music cases; ordered timestamp analysis establishes
long held states and catch-up bursts. Human-audible quality assessment remains
NOT RUN. No listening PASS is inferred from event or WAV capture.

## Bounded event output: justified next experiment, not yet implemented

The measurements now justify evaluating an OS-9 driver-owned predecoded event
queue for ordinary command loading: interrupts and clock service continue while
the producer is ready but descheduled. A handler might deliver already-buffered
events in those intervals. It cannot execute during CPU HALT or masking, cannot
recover coalesced video ticks, and cannot help if its queue runs dry.

A prototype must use registered OS-9 driver/IRQ facilities, with allocation,
parsing, file loading and queue replenishment confined to the user process.
At 60 Hz, event quantization alone is up to about 16.7 ms; batching cannot
preserve arbitrary sub-tick articulation. Bound the writes per tick and measure
IRQ occupancy, keyboard service and disk throughput before considering release.
Excess events must be reported, never silently discarded.

Provision lookahead exceeding the measured 1.62-second ordinary stall, with
margin; capacity must follow measured peak writes per lookahead window, not
average song rate. For illustration only, 1024 entries of four-byte deadline
plus register/value consume 6144 bytes before metadata. This does not establish
adequacy for all songs and occupies most of an 8 KiB block; Level II still has
a 64 KiB logical address limit. Use OS-9-managed mapping, not producer MMU
register writes from an interrupt handler.

MPI ownership remains a release blocker for that design. An IRQ can interrupt
a user sound write or disk transaction. Saving/restoring FF7F alone is not proof
that changing cartridge selection mid-transaction is safe. Define exclusive
sound-register ownership, selection serialization, bounded critical sections,
and compatibility with the actual disk driver before implementing output.
Stop must atomically cancel queued events, mute under the same ownership,
restore selection, detach IRQ/clock references and free buffers after the
handler cannot access them. No queue or new interrupt source is installed here.

## Physical hardware and limits

Repeat the matrix on the actual CoCo 3, CoCoSDC and Mega Mini MPI, recording
CPU, RAM, EOU version, driver modules, clock rate and slot configuration.
Measure PSG bus timestamps and video/IRQ timing externally where practical;
repeat cold and resident command launches, stop/restart and resource snapshots.
Identify conventional WD1773 floppy-emulation access separately from CoCoSDC
native-command access and its actual NitrOS-9 driver. MAME FDC/VHD behavior is
not CoCoSDC compatibility evidence. Native access could have different HALT,
masking and system-mode occupancy; no improvement is assumed. Follow the full
procedure in [CLOCK-RELIABILITY.md](CLOCK-RELIABILITY.md).

## Regression and evidence status

* **PASS:** Full build and ToolShed module checks. `cctpark` remains 9658 bytes,
  data 1983, CRC 827191; original `cctplay` rebuild is byte-identical with SHA-256
  eabe6b6f3910ebd1af557f64b02c1fb1e1802a3a07a1bf134016b1a4a6792f36.
  No production source changed. Diagnostic modules: cctnice CRC 82ABA1,
  diskstress 5E1432, musicdisk E70997, musicbusy 350B9A.
* **PASS:** Eight complete real-music workload cases, ordered VGM/CCT sequences,
  three-track M3U in ordinary cases, natural mutes and final MPI FF. Floppy
  supervisors play the same ordered tracks directly rather than parse M3U.
* **PASS:** Fresh infinite-loop stop: verified live player PID 3, `cctstop 3`,
  69 ordered pairs followed by mute, MPI FF, then 38.027 seconds without PSG
  writes. `W` reaps the child, its descriptor disappears, and free process RAM
  is 1792 KiB before and after. Aggregate equality is not a full allocator audit.
* **PASS:** Background Flicky restart after that stop, complete 820-pair stream
  and mute; detailed duration and tick results are in the results JSON.
* **PASS:** Four-channel 48 kHz 16-bit WAV captures for all eight music cases;
  final-second mean-removed RMS on the PSG channel is approximately 0.424 PCM
  counts. This supports quiet termination, not perceptual smoothness.
* **PASS:** Five clock-reliability and three scheduling-analyzer unit tests.
* **NOT RUN:** Human listening, physical CoCoSDC/Mega Mini tests, mouse/GShell,
  6809/512 KiB, exact instruction-cycle attribution, exhaustive path/allocation
  leak checks, and isolated priority-dependent device throughput.

The guest retains its deliberate pre-existing `iniz ctclock` attachment;
that registered clock packet is not a leaked player open. Earlier missing-clock,
error-path and detach tests remain in PERFORMANCE-OPTIMIZATION.md and
CLOCK-RELIABILITY.md; they were not newly rerun here.

Rejected evidence is retained privately: initial host-launched floppy cases
had corrupted keyboard text and no playback; an early cctnice F$Chain design
failed Error 223 and was replaced by Fork/Wait; one command line exceeded the
host bridge's input length. The 180-second sustained capture omitted the end
of Flicky and is superseded by the complete 360-second capture. Priority 160's
second capture stopped on keyboard-queue overlap. None is counted as a PASS.

Only the owned private guest is used. Canonical media, unrelated MAME sessions,
kernel, disk drivers and original player remain untouched. Rollback consists
of omitting the scheduling addon and diagnostic helpers; ordinary builds have
no dependency on them.
