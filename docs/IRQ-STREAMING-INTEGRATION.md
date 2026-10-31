# IRQ streaming integration

Work from `4244c44`, 2026-10-31. Opt-in HD6309 EOU Level II experiment,
MAME 0.289 `coco3h`, NTSC, 2 MiB, CoCoPSG in MPI slot 2. No kernel,
boot-image, interrupt-frequency or sound-hardware-support change.

Real VGM/CCT decoding can feed a bounded IRQ queue while Shell remains usable.
The ordinary command/read cases reduce peak event lateness from approximately
1.3 seconds with `cctpark` to approximately 40 ms. This does not solve floppy
clock loss or make 60 Hz delivery sample-accurate. Keep `cctirq` opt-in.

## Dense-event gate

All events are present before Start in these tests, isolating consumer capacity
from producer scheduling. Generated original fixtures cover three voices,
1–16 sample waits, 735/882-sample waits, repeated register-13 triggers, full
256-entry capacity and 210 seconds of sustained notes. PAL-format waits on this
NTSC guest do not validate a PAL machine or 50 Hz OS clock.

| Fixture | Budget | Nominal seconds | First-write to mute seconds | Peak lateness | Maximum callback | Deferred ticks |
|---|---:|---:|---:|---:|---:|---:|
| Saturation, 255 writes | 8 | 0.250000 | 0.517955 | 267.848 ms | 0.839 ms | 31 |
| Saturation, 255 writes | 12 | 0.250000 | 0.350750 | 100.644 ms | 1.223 ms | 21 |
| Saturation, 255 writes | 16 | 0.250000 | 0.251775 | 1.742 ms | 1.586 ms | 0 |
| Mixed short/frame waits, 179 writes | 8 | 1.149751 | 1.151781 | 201.373 ms | 0.839 ms | 21 |
| Mixed short/frame waits, 179 writes | 16 | 1.149751 | 1.151781 | 32.452 ms | 1.607 ms | 9 |
| Long sustain, 187 writes | 8 | 210.000000 | 210.271408 | 271.301 ms | 0.839 ms | 1 |

**PASS:** every register/value remains ordered, including all repeated envelope
triggers; no underruns; terminal mute; live MPI restoration; final queue empty.
The saturation cases wrap both indices to zero. The long run has 12,600 video
edges, acknowledgements and clock increments, with no coalesced ticks. Its
0.129% drift follows the nominal 60 Hz versus approximately 59.92 Hz video rate.
Only its initial sixteen-write burst spills by one serviced tick.

Sixteen is the largest **tested** budget, not a universal safe maximum. It
supports a theoretical sustained 16 × 59.92 ≈ 959 writes/second; the short
saturation test demonstrates frame-sized delivery, not an indefinite throughput
or peripheral-latency guarantee. The explicit overflow policy is to retain
excess records for later ticks, preserving order and reporting budget deferrals.
No write, including register 13, is coalesced. Short waits remain quantized and
bursty music can accumulate backlog. Do not raise IRQ frequency to hide this.

## Ownership, synchronization and cleanup

`PSGStream`/`psgs` are separate from the unchanged fixed-stream `PSGQueue`/`psgq`.
`cctirq` is built only by `build-irq-stream.sh`; normal build targets retain their
existing schedulers and binary identities. The descriptor is for slot 2 only;
other MPI selections are rejected. Other players must not access the same PSG
concurrently: the driver enforces ownership among its own openers, not unrelated
legacy hardware writers.

IOMan owns the queue and bookkeeping in system-visible static storage. The
producer passes scalar values through SCF's system register frame. IRQ code
never reads a process-local buffer or DAT mapping. It performs no OS calls,
allocation, file access, printing, parsing or blocking work.

Append validates state, capacity, order and register number under saved CC,
copies all four bytes, then publishes Tail and Count. IRQ updates Head/Count
under dispatcher masks. Full queues return E$DevBsy; the user starts once,
sleeps/retries, and retains the same event. A running empty queue enters an
underrun state and mutes; later publication fails closed. End seals publication.
Wraparound uses modulo indices plus a separate count, allowing all 256 slots.

Deadlines are 16-bit modular serviced ticks. The producer retains exact sample
remainders, rounds only event deadlines upward and inserts internal FE no-op
records across 4096-tick silences. Successive deadline gaps stay below 32768;
markers consume the same bounded budget. Parsing yields every 32 commands.
The ring starts when full, or at EOF for a short track. Natural EOF drains to a
timed terminal; abort cancels instead. Loops retain the timeline; playlists close
and reopen ownership between tracks. This is whole-file loading followed by
streaming **events**, not a new disk-streaming file decoder.

Forced termination exposed an inherited loader defect: F$AllRAM allocations
survive F$Exit unless explicitly released. The initial kill test silenced the
PSG and restored control but leaked eleven 8 KiB blocks (88 KiB). This was a
FAIL and prompted the allocation-ownership revision, not a passing queue test.

The final experimental driver also owns allocation/map records. Scalar SetStat
$84/$85/$86/$87 invoke F$AllRAM/F$MapBlk/F$ClrBlk/F$DelRAM in ordinary system
process context, recording success before returning to user state. Normal
cleanup unmaps before freeing; freeing a still-mapped block is rejected. Close
stops consumption, restores PSG control, clears remaining owned mappings, then
releases remaining blocks. No explicit mask surrounds these OS calls. The path
belongs to the opening process; `cctirq` never forks with it open. This private
API is not a general inheritable/shared memory-allocation service.

Reference kernel source `f470fa52eb172b59b22c1b722074998cb42de9b1` explains the
allocation distinction: `level2/modules/kernel/{fallram,fdelram,fclrblk}.asm`
and the Level II branch of `level1/modules/kernel/fexit.asm`. Live EOU bitmap,
path and process snapshots validate the actual cleanup behavior. No kernel code
is modified. Driver Close captures/restores PSG control even when user cleanup
cannot execute. The original user hardware cleanup remains bounded and retains
MPI/CC restoration.

## Measurement method

Host-side pass-through taps validate module size/CRC before using listing
symbols. They record callback entry/exit, ordered PSG writes, MPI and control
transactions, append publication, critical-section boundaries and SCF calls.
The 100 µs clock sampler records video generation, IRQ acknowledgements,
serviced ticks, HALT/masks and process scheduling. Taps do not acknowledge IRQs
or write guest memory. Callback costs exclude the final return/dispatcher;
masked append-body costs exclude the few instructions entering/leaving the mask.

Normal-speed captures include dense fixtures and an audible real VGM/CCT/M3U
playlist (player CRC 0E4E32, before allocation-ownership revision). The user
confirmed: “Audible, no obvious problems.” Final B2589C repeats the event/timing
and lifecycle checks with unthrottled emulation. Automated matrix
and lifecycle repetitions use unthrottled emulation; all reported timing is
emulated time, not host elapsed time. WAVs retain emulated audio timing. Accepted
captures require no dropped events or discontinuity. IRQ writes inherit the
interrupted PID: producer CPU estimates instead use the PID observed at Append.

Lateness tables use first musical write as epoch, to match the earlier
`cctpark` measurements. Additional callback-epoch metrics are in the JSON data.
Arkanoid's first event is at sample 276; its first-write-to-mute duration is not
its full nominal song duration. Startup/file-loading delay is reported separately
and must not be mistaken for musical tempo or event lateness.

## Ordinary activity and floppy workloads

All six matched workload pairs use the same 820-write Flicky CCT, no extra loop.
The nominal song length is 20.089977 seconds. Each is one controlled run, not a
statistical latency bound. All final streaming runs preserve all writes, report
zero underruns/deferrals, and restore their resource snapshots.

| Workload | IRQ seconds | IRQ peak lateness | cctpark seconds | cctpark peak lateness |
|---|---:|---:|---:|---:|
| counter | 20.125906 | 39.409 ms | 20.104736 | 18.934 ms |
| commands | 20.125907 | 39.409 ms | 20.110449 | 1248.275 ms |
| directory | 20.125955 | 39.565 ms | 20.160189 | 242.553 ms |
| small-read | 20.125906 | 39.409 ms | 20.110755 | 1330.099 ms |
| periodic | 22.812712 | 2726.216 ms | 22.796059 | 2712.607 ms |
| sustained | 31.040001 | 10953.815 ms | 31.184249 | 11113.032 ms |

Idle CCT: 20.125906 seconds, peak 39.409 ms; all 820 writes plus timed mute.
The VGM case preserves all 266 writes and wraps the ring. Its first-write to
mute interval is 4.422852 seconds; use the JSON callback-epoch duration when
comparing with its 4.430204-second nominal length.

Counter runs emit sixty visible updates. Command runs load full-path `pwd` and
`mfree`, then echo; directory runs list `/dd` and `/dd/cmds`; small reads list
`/dd/startup` twice. These VHD activities are separate from the floppy cases.
Periodic floppy work performs 32 open/read-256/close cycles with 61-tick sleeps;
stress performs 128 cycles without sleeps. Both begin after music starts and
finish naturally. The Shell remains usable; floppy HALT can drop emulated
keyboard characters, which must not be mistaken for a player deadlock.

Normal workloads have 1206 video edges/acks/clock ticks and no coalescence.
Floppy results below count missing serviced ticks rather than attributing all
HALT time directly to clock loss:

| Floppy workload | Video edges | Clock ticks | Coalesced while HALT + IRQ mask | Coalesced with IRQ mask only |
|---|---:|---:|---:|---:|
| periodic | 1367 | 1206 | 155 | 6 |
| sustained | 1860 | 1206 | 628 | 26 |

No event is late relative to its rounded **serviced** tick in these final
streaming runs. Disk slowdown is unrecovered elapsed time; the IRQ queue cannot
execute through CPU HALT or its masked interrupt. See [CLOCK-RELIABILITY.md](CLOCK-RELIABILITY.md)
for the hardware-reference investigation and CoCoSDC distinctions.

## Playlist, long-stream and lifecycle results

**PASS:** the final M3U run plays VGM → CCT → CCT, preserving all 1352 musical
writes in order, with only expected mute transactions between tracks. Durations
are 4.422852, 20.125906 and 4.422852 seconds from each first write to mute.
Physical-block/system-page/process-path snapshots return to their starting state.

**PASS:** the generated 210-second streaming file crosses three file-data pages,
delivers all 5269 writes (1053 envelope writes), wraps Tail twenty times and ends
with an empty ring. It takes 210.271514 seconds; no underrun, deferral, missed
serviced deadline or lost clock tick occurs. Four owned blocks are allocated and
freed; seven mapping/clear operations cover loading and playback. Resource
snapshots match. This is concurrent refill and page reuse, not a fixed preload.
The accepted capture contains 152172 events and no drops. An earlier long-loop
capture overflowed the old 100000-event observer bound and is **not accepted**;
the host-only bound is now 250000.

| Lifecycle case | Result and evidence |
|---|---|
| Graceful stop with pending/full ring and loops | PASS: stop after 14 musical writes; 256 queued records remain stopped; no later musical write; exact resource restoration. |
| Stop during a dense burst | PASS with prelaunched supervisor: 176 ordered writes, 199 records still pending, no underrun; all later transactions mute only. An IRQ batch completes before user-state cancellation can execute. |
| Stop while next playlist track loads | PASS with supervisor: first track's 266 writes complete; second track never starts; all allocations/maps released. |
| Forced kill during playback | PASS after ownership fix: 141 musical writes, pending events silenced, PSG control 1 → 0 restored, exact memory/path restoration. |
| Forced kill during file loading | PASS with supervisor: two allocations, zero musical writes, close mute, exact memory/path restoration. |
| Empty/missing file and wrong slot | PASS for cleanup/no musical output; no surviving owner or allocation. |
| Empty running queue | PASS: intentional four-write helper reaches underrun, mutes, closes and releases ownership. |
| Second opener | PASS: rejected while the original stream continues; no foreign musical writes or ownership transfer. |
| Restart after these cases | PASS: complete 820-write CCT, no underrun and exact resource restoration. |
| Automatic final-path teardown, without iniz psgs | PASS: complete CCT, resource snapshot restored, PSGStream link count returns to zero, PSG IRQ/VIRQ registrations removed. |

Final explicit detach/unload leaves no VIRQ packet and only the pre-existing
FDC poll entry. The earlier failed-version allocation leak was confined to the
isolated test guest; that RAM state was discarded with the test guest shutdown.

A zero-wait 4100-write stress fixture plus Shell-launched stop can exhaust the
256-record lookahead before the stop command reaches the producer. This is a
**timing/refill failure**, followed by correct fail-closed mute and cleanup; it
is not smooth playback or a passing timely-stop test. The prelaunched supervisor
separates cancellation correctness from command-loading latency. The default
sixteen-record budget is about 267 ms of buffering at saturation, versus roughly
ten seconds in the long streaming fixture. Ordinary tested workloads do not
underrun. Do not extrapolate their result to arbitrary zero-wait bursts.

Supervisor commands use ordinary F$Fork/F$Sleep/F$Send/F$Wait and retain their
child PID until reaping: `irqkill 60 /d1/flicky.cct`,
`irqsuper 150 /d1/cancel.vgm`, and `irqsuper 480 /d1/irq-real.m3u`.
Copy `irqkill`, `irqsuper`, `streamunder` and the generated fixtures to the private
test image as well as the player/pack. `prepare-irq-dense.py cancel` and
`prepare-irq-dense.py streamlong` generate the original streaming fixtures.
Natural-keyboard command loss during floppy operations invalidated two typed
stop attempts; the successful supervisor cases above replace those attempts.

Register 0–13 audio writes are supported. PSG I/O-port registers 14/15 are not
supported by this experimental queue and fail validation; no compatibility claim
is made for tracks using them or additional chips. Timestamp rollover beyond
65535 serviced ticks and injected kernel registration/unmapping failures are
**NOT RUN**; the signed-gap bound and rollback paths have been audited. The new
path remains experimental, with the unchanged players available for comparison.

## Cost and practical limits

Final module identities (`os9 ident`: good CRC, reentrant OS-9 modules):

| Module | Code bytes | Data bytes | CRC |
|---|---:|---:|---|
| cctirq | 9912 | 1986 | B2589C |
| PSGStream | 1043 | 1348 | 29B6B2 |
| psgs | 39 | descriptor | FF27A8 |

Driver data contains the 1024-byte event ring plus SCF state, allocation flags
and eight mapping records. IOMan allocation granularity and the shared code
block add overhead beyond these declared sizes. `cctirq` uses three additional
process-data bytes versus `cctpark`; loaded music still occupies its original
F$AllRAM blocks. `streampack` keeps the driver, descriptor and small test helpers
in one physical module block, avoiding unnecessary system-map slots.

The final full 16-write callback measures 1.640 ms. The 820-write song spends
about 0.1403 seconds in running callbacks, roughly 0.70% of its musical duration.
Idle attached callbacks are about 10.6 µs. The longest observed masked append
body is about 86.1 µs; add entry/exit instructions to bound the whole mask.
Incoming IRQ/FIRQ mask bits match on all recorded append success/rejection exits.
Whole-system masking under ordinary workloads can reach about 2.1 ms including
dispatcher/other service work; this is not just the PSG callback.

The idle real-track run uses 821 accepted records, 844 full-queue retries, 1717
SetStat and 1206 GetStat calls, and **zero clock-service calls**. It spends about
0.7064 sampled seconds in producer user state over loading, decoding and cleanup.
These driver calls include allocation/mapping services. Counter/command variants
have different retry counts because the consumer runs while the producer is
scheduled elsewhere. This prototype improves scheduling latency, not total
system-call count: `cctpark` uses only 477–639 clock reads in the matched real
track runs. Do not claim the IRQ version is cheaper solely because clock calls
are zero. System-state time includes kernel/interrupt work and is not an exact
exclusive producer CPU measurement.

Potential next optimization is bounded refill batches or a low-water wakeup
policy, measured against responsiveness and minimum buffered time. Keep complete
atomic event publication and retain every PSG write. No such batching/wakeup
optimization is hidden in these results. A faster interrupt or arbitrary GIME
source takeover is not justified. Accurate sub-tick music needs a separately
validated timing architecture; elapsed-time accuracy through floppy HALT still
requires a reliable external reference or platform change.

## Reproduction and evidence

Build the unchanged comparison targets, then the explicit experiments:

```sh
bash scripts/build.sh
bash scripts/build-irq-prototype.sh
bash scripts/build-irq-dense.sh saturation 8
bash scripts/build-irq-dense.sh saturation 12
bash scripts/build-irq-dense.sh saturation 16
bash scripts/build-irq-dense.sh mixed 8
bash scripts/build-irq-dense.sh mixed 16
bash scripts/build-irq-dense.sh long 8
bash scripts/build-irq-stream.sh
python3 scripts/test-irq-dense.py
python3 scripts/prepare-irq-dense.py cancel
python3 scripts/prepare-irq-dense.py streamlong
```

Copy `streampack` and `cctirq` onto an unmounted private RBF test image and set
execution attributes. Do not overwrite mounted or canonical images. In the
isolated EOU guest, `load /d1/streampack`, `iniz ctclock psgs`, then
`load /d1/cctirq`. Example: `cctirq -psg 2 -l 0 /d1/flicky.cct &`.
`ctclock` is present for measurement; the streaming producer does not read it.
Use a `#EXTM3U` header followed by CR for playlists, as required by the existing
loader. Shell `W` reaps background children; `cctstop PID` requests graceful stop.

`build/psgstream.json` contains verified offsets for the host observer.
`irq_stream_matrix` in `tools/irq-stream-workload.lua` runs the matched cases;
`irq_stream_lifecycle` runs bounded lifecycle cases. Load these only into an
exclusively owned bridge/guest. The harness verifies player CRC and captures
before/after module, physical-block, system-page and process-path state. Detach
`psgs ctclock` and inspect IRQ tables after use. The only remaining poll entry
should be the pre-existing FDC; no VIRQ packet should remain.

Analyze individual captures with:

```sh
python3 scripts/analyze-irq-stream.py TRACK CAPTURE.json
python3 scripts/analyze-irq-stream.py TRACK PARK-CAPTURE.json --park
```

Compact accepted results are in [IRQ-STREAMING-MEASUREMENTS.json](IRQ-STREAMING-MEASUREMENTS.json).
Raw JSON, WAV, screenshots, private images and supplied songs remain ignored
under `emulator/images/reliability/`. No ROMs, songs or binaries are committed.
The early short-window CCT capture ended before playback completion and is not
a PASS. An initially headerless playlist was rejected and corrected. A typed
kill during floppy loading lost a space; its completed playback is not evidence
of forced termination. The supervisor case replaces that invalid attempt.

Rollback: stop active playback, detach `psgs`, unload the test modules, and run
`cctpark` or the unchanged comparison builds. Original `cctplay` SHA-256 remains
`eabe6b6f3910ebd1af557f64b02c1fb1e1802a3a07a1bf134016b1a4a6792f36`.

## Physical hardware follow-up

MAME verifies event order, queue ownership, lifecycle, OS service behavior and
emulated floppy HALT/clock effects. It does not validate real CoCoSDC timing,
Mega Mini MPI electrical behavior, real PSG bus margins, or 6809/512 KiB use.
Those targets are **NOT RUN**.

On the HD6309 CoCo 3 with CoCoSDC and Mega Mini MPI:

1. Record EOU version, CPU mode, RAM, video standard, MPI slots and driver/module
   identities. Back up media and retain a known-good `cctpark` setup.
2. Run the original generated tone, dense/mixed fixtures and real permitted
   VGM/CCT/M3U tracks. Compare recorded audio duration, envelope retriggers,
   audible breaks, Shell response and a visible once-per-second counter.
3. Repeat commands, directory listings and small reads separately from periodic
   and sustained reads. Record each device descriptor and its driver. Distinguish
   WD1773-compatible floppy emulation (`rb1773`-style path) from CoCoSDC native
   command access using the actual SDC driver installed in that EOU build.
   Neither a native-driver result nor compatibility is implied by MAME floppy
   results. Do not guess driver identity from the `/dN` pathname alone.
4. Repeat graceful stop, forced termination, playlist-load cancellation and
   restart. Check mfree/processes, no stuck notes, restored MPI/control, and IRQ
   registration removal. Use external PSG/video timing observation if available;
   guest serviced ticks alone cannot measure missed ticks.
5. Keep the sixteen-record budget experimental until interrupt latency and all
   active peripherals pass on hardware. Do not compensate by changing song tempo,
   suppressing disk access, changing the kernel or stealing an OS interrupt.
