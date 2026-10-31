# IRQ playback feasibility

Investigation following `7bff021`, 2026-10-31. MAME 0.289, HD6309 EOU,
2 MiB, NTSC, existing CoCoPSG slot 2. No production player or kernel change.

## Phase 1 gate

The retained, zero-overflow `lat-p128-1` MAME capture records 90 generated
vertical-border events, 90 video-status acknowledgements and 90 CCTClock IRQ
updates inside the player's 1.504793-second Sleep call. The player spends
1.475488 seconds sampled on the active queue and emits no PSG data writes.
Maximum acknowledgement spacing is 16.694 ms; acknowledgement-to-clock-update
latency is at most 145.270 us. At 100 us sampling, no HALT interval is
observed in that stall; the longest contiguous observed IRQ mask is 0.700 ms.
A mask seen in a border sample can already belong to IRQ service itself and
must not be interpreted as a missed interrupt. `scripts/analyze-irq-availability.py` reproduces
this correlation from the paired clock and scheduling captures. This confirms
that a registered VIRQ/IRQ consumer can execute during this measured system-work
stall. It does not establish availability during floppy HALT/masked intervals.

## Prototype design selected after that gate

The separate opt-in SCF driver uses the same documented F$VIRQ/F$IRQ
registration mechanism as CCTClock. IOMan owns system-visible driver static
storage. The prototype has 256 four-byte records (16-bit relative tick,
register, value), at most eight writes per callback, and one exclusive path.
A user helper preloads an entire deterministic sequence before starting it.
No live decoding/refill is required for the first experiment. The queue is
immutable while running; each record is fully copied before publishing count.
A terminal record is explicit. Empty without that record is an underrun:
stop and mute, with a visible status. Over-budget work remains ordered for the
next tick and is counted, never discarded. This is not yet a streaming API.

Each hardware transaction changes only the MPI SCS slot bits, preserving
CART routing and restoring the live byte before returning. The handler alone
owns PSG writes during its test; concurrent player output is prohibited.
The initial test uses the established CoCoPSG slot 2, VHD command loading,
and no sound detection or other cartridge support. Physical MPI/CoCoSDC
compatibility remains unverified. No GIME timer changes are made.

SS.Close and Term stop/mute before unregistering or freeing storage. A process
exit must close the path through OS-9. Init failures roll back registrations.
No process-memory pointers are accepted, and no file I/O, parsing, allocation,
blocking call or user intercept invocation occurs in the IRQ callback.

The 16-bit timeline is deliberately bounded to 32767 ticks per test, avoiding
ambiguous wrap comparisons. A future streaming design needs wrap-safe wider
timestamps, refill margins, owner lifetime and explicit underrun recovery.

## Timing result and recommendation

**Refine the opt-in design; do not integrate it into the production decoder yet.**
The fixed-stream experiment demonstrates that registered IRQ output substantially
reduces ordinary command-load interruptions without changing process priorities
or suppressing OS scheduling. It does not demonstrate streaming underrun-free
playback, physical MPI compatibility, or sample-accurate output.

The final driver is 607 bytes, CRC 58B646, requesting 1075 bytes of static data,
including its 1024-byte queue. Descriptor size is 38 bytes. A 211-record
preloaded stream contains all 210 original synthetic30 PSG writes plus an
explicit terminal record. The user helper never needs to decode or replenish
while playback is running. Its first serviced callback establishes tick zero.
The clock and queue drivers are separate registrations in one packed load.

The paired cases use identical generated music and Shell inputs five, fifteen
and twenty-five seconds after the first PSG write: full-path pwd, full-path
mfree and Shell echo. All measurements below use emulated seconds and the final
driver, with the idle queue registration present in both builds.

| Case | Duration s | Maximum lateness ms | p95 lateness ms |
|---|---:|---:|---:|
| cctpark idle | 30.021252 | 21.106 | 19.172 |
| IRQ idle | 30.038781 | 38.675 | 36.481 |
| cctpark commands, run 1 | 30.035755 | 1461.246 | 1153.241 |
| IRQ commands, run 1 | 30.038781 | 38.675 | 36.481 |
| cctpark commands, run 2 | 30.036906 | 1462.429 | 1080.283 |
| IRQ commands, run 2 | 30.038628 | 38.522 | 36.328 |

Every stream contains all 210 ordered writes and mute, with MPI restored to FF.
The paired command runs reduce maximum event lateness by approximately 97.4%.
This is a small controlled feasibility sample, not a general latency guarantee.
The approximately 39 ms residual accumulates largely from nominal 60 Hz timing
against MAME's slower video cadence. No tempo correction was introduced.
Maximum local excess over decoded waits is about 0.559 ms in the IRQ command
runs, versus 1.455 seconds in cctpark. All 1800 generated video events,
acknowledgements and clock-driver ticks match in those command windows.

The IRQ path makes zero CCTClock GetStat calls during playback. That does not
mean zero system-call overhead: the helper preloads 211 records through SetStat,
starts the stream, polls status about once per second, prints and closes.
The comparison cctpark cases make 3387–3388 clock calls under commands and
3599 while idle. PSG writes made in IRQ context inherit the interrupted PID;
that PID must not be labeled as the producer's CPU usage. The results omit
that misleading attribution for queue cases.

An initial speaker-disabled run was used for timing and WAV capture. After the
user reported silence, the private guest was saved and restarted with CoreAudio
and normal throttling. The user confirmed the repeating tones were audible.
The speaker-enabled command run retained all writes and measured 38.664 ms
maximum lateness. This confirms audibility, not a full musical-quality review.

## Callback budget and resolution

Measured entry-to-success-epilogue latency is 10.616 us when inactive, 48.609 us
median across the ordinary active/inactive capture, and 529.118 us maximum
for the five-write normal stream. Active-stream callbacks total 107.796 ms
across 30.039 seconds, approximately 0.36% of elapsed CPU time in the callback.
These instruction-fetch timestamps exclude the final CLRB/RTS instructions and
kernel interrupt/poll overhead; they are not total interrupt CPU cost. MPI
selection-to-restoration takes at most 15.645 us per transaction.

The strict limit is eight hardware writes per callback, including a final or
underrun mute. When the budget is exhausted, even that mute waits for the next
callback; this keeps the bound honest. No event is discarded or reordered.
The 50 Hz/short-wait stress fixture includes 120 envelope-shape writes,
including twenty closely spaced repeated writes. All 127 PSG pairs survive.
It reaches eight writes per callback, two over-budget ticks, maximum callback
838.655 us, and maximum event lateness 52.478 ms. This exposes audible-fidelity
risk in dense bursts; preserving order alone is insufficient.

60 Hz ceil quantization inherently introduces up to one tick of delay. A 50 Hz
stream alternates one- and two-tick spacings; distinct sub-tick events can share
a deadline. Identical register 13 writes restart the envelope and must never
be deduplicated. The prototype writes every event in sequence, but changes
sub-tick spacing and can spread a dense burst across additional ticks.

Offline decoding of privately held real music measures:

| Track | Writes | Peak writes/tick | Ticks exceeding budget 8 | Max ceil error ms | Peak writes in inclusive 2 s |
|---|---:|---:|---:|---:|---:|
| Arkanoid VGM | 266 | 14 | 2 | 10.408 | 141 |
| Ark1 CCT | 266 | 14 | 2 | 10.408 | 141 |
| Flicky CCT | 820 | 16 | 5 | 13.333 | 102 |

Two-second lookahead requires at least 564 / 564 / 408 bytes respectively with
four-byte entries, before margin and metadata. A 256-entry queue could cover
those measured windows, but neither complete track fits this fixed preload
protocol. Dense music has no universal two-second capacity bound. Raising the
IRQ budget to accommodate 14–16 writes requires another fairness/latency test;
it must not be inferred safe from the eight-write result. No GIME timer is
reprogrammed and no higher-frequency interrupt source is installed.

## System storage, ownership and lifecycle

IOMan allocates driver static storage in the system map; the 1075-byte request
requires five 256-byte allocator pages. SCF path/buffer and module bookkeeping
are additional costs. The first separate-pack attachment failed with RAM Full:
Level II lacked another system code mapping, despite free physical memory.
Packing the unchanged CCTClock/ctclock and queue modules together shares their
8 KiB code block and permits both to attach. A normal isolated load must not
silently replace a clock driver in use by another guest or process.

The owner is a system path-descriptor pointer. SS.Open rejects another path;
the probe also requests exclusive access. SetStat accepts timestamp/register
values through the caller's saved register frame, not a user buffer pointer.
A complete four-byte record is copied before Count is increased. Loading is
allowed only before Start, and the IRQ reads records only after Start publishes
Running under saved/restored CC. No live producer/consumer race is claimed
solved by this fixed-stream protocol. Appending after a terminal record,
appending while running, decreasing timestamps, invalid registers and capacity
exhaustion return an error.

The callback changes only the MPI SCS slot bits, retains the other six bits,
and restores the live selection after each register/value transaction. It uses
the same PSG select/data spacing as the existing player. The callback inherits IRQ/FIRQ masks from the dispatcher (observed entry CC
D0/F0); the transaction also saves/restores CC explicitly. Thus the entire
callback contributes to masked time, bounded by the measured 0.839 ms burst
case, plus dispatcher overhead. No parsing, I/O or OS call occurs there.
Other cctpark/original players must not access the PSG concurrently: ownership
is exclusive within this experimental device, not enforced against unrelated
raw hardware clients. No Mega Mini CART/audio routing register is changed.

Ordinary stop/close sets Stopped and mutes before releasing the path. The
intercept merely latches a flag; ordinary user code closes. Fatal process exit
was separately validated through OS-9 path cleanup. Term stops, removes
VIRQ then IRQ, propagating removal failures rather than pretending a live
registration is gone. Explicit iniz keeps an idle registration alive across
measurements by design; deiniz is required to measure final removal.

## Reproduction and compatibility

Read the EOU [technical reference](https://www.lcurtisboyle.com/nitros9/EOUDOCS/NitrOS-9_EOU_Level_2_Technical_Reference_Manual.pdf)
for driver static storage, SCF status calls, F$IRQ and F$VIRQ. The prototype
follows the existing tested CCTClock registration pattern. Source inspection
also used the local NitrOS-9 reference at f470fa52eb172b59b22c1b722074998cb42de9b1;
installed EOU modules are identified separately, not assumed byte-identical.

```
bash scripts/build-irq-prototype.sh
python3 scripts/test-irq-prototype.py
# Stage build/irqpack on a new, unmounted PRIVATE RBF image, set execute attrs.
# On an isolated guest only, detach/unlink old clockpack before replacing it.
# load /d1/irqpack
# iniz ctclock psgq
# irqprobe &
# cctstop <independently verified irqprobe PID>
# W
# deiniz psgq ctclock
# unlink CCTClock
```

The test pack's first module is CCTClock and owns its preload link; do not
blindly unlink arbitrary pre-existing references. The old automation-leased
counter and unrelated MAME sessions are outside this guest and untouched.
`irqburst`, `irqunder` and `irqover` are explicit diagnostic variants, not
production commands. `irqunder` deliberately omits the terminal record;
`irqover` attempts 257 records. The normal build does not include this pack.
Original synthetic fixtures and generated module/includes remain in ignored
build storage; no music or binary is committed.

Load the checked-in host addon through `reliability_load_irq`. `irq_capture`
uses the CRC/offsets in `build/irq-layout.json` and a bounded output path.
`irq_series` requires that layout plus independently verified CCTClock code
and storage addresses. In this guest they are 8192 and 20224, while PSGQueue
code/storage are 8417/18176. These are evidence, not a public ABI. The six-case
series records idle and repeated command comparisons; optional `prefix`
keeps separate final captures. It restores throttling after completion.

Analyze with `scripts/analyze-irq-playback.py TRACK CAPTURE...` and
`scripts/analyze-irq-resolution.py TRACK...`. Handler capture rejects drops,
incomplete pairs and non-restored MPI selection. The first exploratory
596-byte driver's clock capture used the wrong storage address and is excluded;
the final paired series uses the independently verified clock storage above.
The 597-byte exploratory driver did not reserve the final mute in its eight-write
budget. The final 607-byte driver checks that limit for normal, terminal and
underrun paths and was rerun through the comparison matrix.

Conventional floppy HALT and IRQ masking still block the output handler and
can lose clock ticks. This queue cannot reconstruct those edges or make elapsed
time accurate during those intervals. Physical CoCoSDC native commands use a
different path from WD1773 emulation. Inspect the installed rbsuper/llcocosdc or
rb1773 modules and cartridge population; do not infer hardware compatibility
from MAME VHD/floppy results. Mega Mini SCS/CART/audio routing, electrical timing,
and any interaction with DMA/HALT must be tested on the actual hardware.

Before production integration, validate a streaming ownership/refill protocol,
worst-case real-track burst budget, producer lookahead under loads exceeding
two seconds, hardware transaction coexistence, stop during playlist transitions,
and system-map pressure in the target boot. A 16-bit relative fixed-stream clock
is not a general long-running player timeline. M3U and live VGM/CCT decoder
integration are deliberately deferred; the existing variants remain unchanged.

## Live regression results

* **PASS:** Final paired synthetic idle/command matrix, two command repeats,
  complete register sequences, mutes, MPI FF, zero underruns/over-budget ticks.
  Seven PSG writes per command run occurred while Shell was the interrupted
  process; delivery continued independently of the user producer.
* **PASS:** Concurrent finite counter, visibly advancing through its output,
  with complete 210-write music and 38.675 ms maximum lateness. Counter progress
  is demonstrated by screenshots; no exact counter scheduling percentile is
  inferred from those screenshots.
* **PASS:** Dense 50 Hz/short-wait/envelope fixture: 127 ordered writes, all
  120 register-13 side-effect writes, eight-write bound, two reported budget
  deferrals, no underrun. Timing fidelity at this density remains limited.
* **PASS:** Deliberately missing terminal record reaches state 3, increments
  underruns once and mutes. A 257th entry is rejected with Device Busy, leaving
  capacity at 256; no partially published record is consumed.
* **PASS:** A second opener receives Error 250 / Device Busy while the original
  owner continues. Verified player PID 3 stops through cctstop: 118 ordered
  prefix writes then mute, owner cleared, 13.000 seconds quiet afterward.
* **PASS:** Independently verified PID 3 forcibly terminated with Shell KILL:
  83 ordered prefix writes then mute, owner cleared, 13.140 seconds quiet.
  This exercises OS-9 close cleanup without executing the probe's graceful
  close path. Subsequent playback restarts successfully.
* **PASS with timing limitation:** Floppy `dir /d1` completes while queued
  music preserves every write and MPI state. Duration is 31.290393 s, maximum
  lateness 1.290287 s; 1875 video events yield only 1800 acknowledgements and
  clock increments (75 lost ticks). Ten FDC commands are observed. This is
  not a remedy for masked/HALT time, nor evidence about native CoCoSDC.
* **PASS:** Original cctplay rebuild remains byte-identical, SHA-256
  eabe6b6f3910ebd1af557f64b02c1fb1e1802a3a07a1bf134016b1a4a6792f36.
  Normal relative, atomic-clock and cctpark builds are retained. Four new
  analyzer/fixture checks plus eight existing analysis tests pass.
* **NOT RUN:** Production decoder/M3U integration, stop during playlist
  transitions, live refill recovery, physical hardware, GShell/mouse,
  6809/512 KiB/PAL, exhaustive allocator audits and listener-rated real-song
  fidelity. Successful fixed-stream feasibility does not mark these PASS.


**PASS, registration cleanup:** With both explicit attachments, the VIRQ table
contains exactly the clock packet at 20253 and queue packet at 18205. The IRQ
poll table contains clock, queue and the pre-existing FDC entry. Removing only
psgq removes its packet and poll entry while retaining the clock and FDC.
Reattaching restores exactly one queue entry. Removing both psgq and ctclock
leaves an empty VIRQ table and precisely the original FDC poll entry. No duplicate
or orphaned registration is observed in these cycles. Table snapshots are
retained as `irq-tables-*.json` in the private evidence directory. Free process
RAM is 1800 KiB before the stop/ownership sequence and after final detach.
This aggregate check is not an exhaustive system-allocation audit.

Rollback is `deiniz` after closing all experimental paths, then removal of the
pack's known preload link. No boot, kernel or canonical disk needs restoration.
Do not unload a module whose IRQ registration remains active. The opt-in test
sources can be omitted entirely without changing cctplay or its comparison
variants. All changes are local; no push is part of this work.
