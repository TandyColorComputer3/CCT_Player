# Experimental standalone CoCoPSG IRQ player hardening

This investigation continues `27cb722` on `feature/multitasking-eou`.
The target remains HD6309, NitrOS-9 EOU Level II, 2 MB, NTSC, CoCoPSG in
MPI slot 2. Todd Wallace's original `cctplay` is unchanged. No kernel,
GMC, OPL3, or Speech/Sound Cartridge implementation was added.

## Installation and operation

Build explicitly:

```sh
bash scripts/build.sh
bash scripts/build-irq-stream.sh
python3 scripts/test-irq-package.py
python3 scripts/test-irq-prototype.py
python3 scripts/test-irq-dense.py
```

Install `build/cctirq-standalone` as `/dd/cmds/cctirq`, and
`build/cctstop` as `/dd/cmds/cctstop`, with executable permissions.
The combined file contains the `cctirq` program, `PSGStream` driver and
`psgs` descriptor. Do not install the fault-injection files.
The individual `build/cctirq` is retained for diagnostics with a separately
loaded driver; it is **not** the standalone installation file.

In the NitrOS-9 Shell:

```text
cctirq -l 0 /dd/music/track.vgm &
cctirq /dd/music/track.cct &
cctirq -l 0 /dd/music/list.m3u &
cctstop PID
```

Use the decimal process ID printed by Shell. `-l 0` suppresses extra VGM loops;
the inherited default is one extra loop. M3U starts with `#EXTM3U`, then
CR-terminated pathnames. Use one player at a time. The exclusive device owner
rejects another opener. Shell returns after loading the executable; the child
loads the complete music file before producing audio. Long file-loading latency
is not event lateness. Cold floppy loading can still lose typed characters.

No manual `load`, `iniz`, `deiniz`, or driver unload is required for the combined
file. Cold-launch tests start without CCTClock, PSGStream, or psgs resident.
CCTClock is a diagnostic comparison service, not a production dependency.

## Changes and why they were made

* Full-ring and terminal-drain polling sleeps four serviced ticks instead of
  one (`F$Sleep 5` under the measured EOU semantics). A full 256-record ring
  holds at least sixteen ticks at the unchanged 16-record IRQ limit. Four
  ticks can consume at most 64 records. Signals interrupt the sleep; playback
  deadlines and all register writes remain unchanged.
* Background errors go to standard error and return a nonzero OS-9 status.
  Help names `cctirq`; dual-AY headers are rejected before audio acquisition.
* The IRQ-only build omits suppressed banners, unreachable OPL/GMC busy loops,
  OPL probing and metadata printing. It also omits the suppressed slot-label
  self-modification. Comparison builds retain their original bytes.
* The compact program and driver fit in **one physical 8 KB code block**.
  Simply appending the driver to the former 9 KB program failed cold startup:
  mapping that driver required too much scarce system logical address space.
  The build now rejects a standalone package larger than 8192 bytes. There is
  no auxiliary launcher or extra user-held load link to strand on fatal exit.
* Driver Init/Term tracks successful IRQ and VIRQ registrations independently.
  Init failure before Open must not mute audio it never owned. An injected
  failure exposed the old unconditional Term mute; it is now absent. Removal
  errors retain ownership flags and propagate to IOMan.
* Host observation tolerates a temporarily unavailable system map when querying
  live queue status; initial/final table validation remains strict. An early
  periodic-I/O capture interrupted by that observer assertion is excluded.

## Measurement method

Read-only MAME Lua taps record PSG writes, driver calls, ring state, critical
sections and callbacks. A 100 microsecond sampler records hardware video edges,
IRQ acknowledgements, HALT/masking and process state. Instrumentation does not
write guest memory. Private project-local media and localhost bridge isolate
these tests from other emulator sessions. Raw JSON, WAV and screenshots remain
in ignored `emulator/images/reliability/` directories; music is not in Git.

`analyze-irq-stream.py` validates every ordered register write, including repeated
register 13 writes, and separates serviced-tick backlog from wall-clock delay.
`analyze-irq-fidelity.py` also handles original-player traces and measures PCM
activity/clipping. First-event-relative timing excludes startup and leading
source silence; IRQ epoch timing retains the leading silence. Do not compare
first-event-to-mute directly with a song that begins with a nonzero wait.

Fast runs use emulated timestamps. WAV recording also follows emulated time;
fast host playback is not a human listening test. PCM has four channels in this
MAME configuration: CoCoPSG music is channel 1 (zero-based). The original capture
configuration clips some music peaks; clipping is reported, not normalized away.
A complete ordered trace proves event preservation, **not identical sound**.

## Real music and fidelity

Existing local tracks: Arkanoid VGM/CCT and Flicky CCT. Additional public test
music was downloaded into ignored media from
[RomWBW's music collection](https://github.com/wwarthen/RomWBW/tree/3e337f730383c5da3a1337ecf80f6882683ef6aa/Source/Apps/VGM/Tunes),
pinned to `3e337f730383c5da3a1337ecf80f6882683ef6aa`:

* **Aggressive World**, Rastan Saga: 6,209 writes, 56.994376 seconds.
* **Forest Path**, Penguin Adventure: 8,613 writes, 57.112449 seconds.
* **Main BGM 2**, Super Qix: 4,860 writes, 72.251746 seconds.

The first two exercise frequent tone/noise/volume changes and thousands of
sub-tick waits; Super Qix includes a 19-write quantized tick. These are actual
music streams, not invented stress melodies. A private CCT wrapping of Penguin
Adventure preserves the VGM's complete event list and sample count; its 2 MHz
CCT clock setting matches the player's selection for that VGM. This is a test
conversion, not a claim of an independently distributed CCT edition.

The available single-chip real tracks provide limited repeated hardware-envelope
coverage. A separate original generated fixture exercises 120 register-13
retrigger writes, including repeated identical values and one-sample waits.
A downloaded dual-chip Tiger Heli track is an unsupported-format test, not a
single-chip fidelity result. Androids YM uses timer effects that cannot be
faithfully reduced to frame register dumps; it was excluded instead of silently
removing those effects. Broader envelope-heavy real-music listening remains a
release qualification item.

### Causes of audible differences

1. Deadlines round upward to 735-sample boundaries. This can compress or spread
   short intervals by nearly 16.67 ms; it cannot reproduce arbitrary sub-tick
   arpeggios, DAC streams or envelope timing. Register order and retriggers are
   preserved, but serialization within a callback takes real CPU time.
2. Only sixteen records execute per callback. Super Qix demonstrates a real
   one-tick deferral; this is distinct from a missing clock tick.
3. The measured NTSC video clock is approximately 59.92 Hz, while conversion
   uses nominal 60 Hz. The approximately 0.129% drift accumulates with duration.
4. Existing hardware selection is 1 or 2 MHz. The approximately 1.789773 MHz
   MSX tracks select 2 MHz: inferred pitch offset is about +192 cents. Super
   Qix's 1.5 MHz selects 2 MHz: about +498 cents. This is inherited clock
   selection, not an IRQ timing defect. No period values or song tempo were
   altered to hide it. Exact source-pitch reproduction needs appropriately
   clocked hardware or a separately evaluated conversion policy.
5. Conventional floppy HALT/masking loses service opportunities and clock ticks.
   An IRQ cannot execute through HALT or its mask. A queued song slows down
   with that clock even when its producer never underruns.

## Final measured results

Player CRC **5C3541**, driver CRC **D54642**, descriptor CRC **FF27A8**.
The program is 6,973 bytes with 1,987 bytes declared process data; the driver
is 1,089 bytes with 1,350 bytes declared system storage. The installable pack
is **8,101 bytes**, occupying one 8 KB code block. System storage rounds to
six 256-byte pages; process memory and music allocation still use physical
8 KB blocks. The earlier separate 9,912-byte player plus driver pack required
three code blocks in total.

All rows below preserve every source write with **zero underruns**. Epoch
duration and lateness start at the first serviced IRQ, including source-leading
silence. Deferrals count delay beyond the rounded deadline in serviced ticks.

| Stream | Writes | Nominal s | IRQ epoch s | Peak epoch lateness ms | Max deferred ticks |
| --- | ---: | ---: | ---: | ---: | ---: |
| Flicky CCT | 820 | 20.089977 | 20.126004 | 39.507 | 0 |
| Rastan VGM | 6209 | 56.994376 | 57.073773 | 80.285 | 0 |
| Penguin VGM | 8613 | 57.112449 | 57.190789 | 79.762 | 0 |
| Penguin CCT wrapper | 8613 | 57.112449 | 57.190789 | 79.762 | 0 |
| Super Qix VGM | 4860 | 72.251746 | 72.359911 | 108.907 | 1 |
| Envelope fixture | 127 | 3.000454 | 3.020761 | 35.897 | 1 |
| Mixed short waits | 179 | 1.149751 | 1.151886 | 32.553 | 1 |
| 255-write saturation | 255 | 0.250000 | 0.251920 | 1.890 | 0 |
| 210-second stream | 5269 | 210.000000 | 210.271507 | 271.400 | 0 |

The 210-second stream preserves **5,269 writes and 1,053 envelope writes**. Its
271 ms accumulated delay is consistent with the video-rate mismatch: all
12,600 video edges were serviced, with no delivery backlog or underrun.

### Ordinary activity versus floppy stress

These Flicky results use the same final build and private media layout. Peak
lateness here is first-event-relative, as in the earlier comparison reports.

| Workload | Playback s | Peak lateness ms | Video edges / clock ticks | Underruns |
| --- | ---: | ---: | ---: | ---: |
| Idle Shell | 20.125907 | 39.409 | 1206 / 1206 | 0 |
| Concurrent counter | 20.125906 | 39.409 | 1206 / 1206 | 0 |
| Shell commands / nonresident command loads | 20.125906 | 39.409 | 1206 / 1206 | 0 |
| VHD directory listings | 20.125938 | 39.419 | 1206 / 1206 | 0 |
| Small VHD file reads | 20.125906 | 39.409 | 1206 / 1206 | 0 |
| Two floppy directory listings | 21.460958 | 1374.461 | 1286 / 1206 | 0 |
| Periodic floppy reads | 22.462261 | 2375.764 | 1346 / 1206 | 0 |
| Sustained floppy reads (stress) | 26.434052 | 6347.557 | 1584 / 1206 | 0 |

All workload rows preserve 820 writes with zero serviced-deadline backlog.
The counter and Shell remained usable under ordinary activity. Floppy directory
operations lose 80 ticks (79 during HALT+mask, one mask-only); periodic reads
lose 140 (136 + 4); sustained reads lose 378 (369 + 9). Their extra elapsed
time relative to idle matches those deficits. This is clock loss, not producer
starvation. Floppy timing depends on disk layout/head movement and caching;
different stress percentages from earlier media are **not** evidence that the
producer optimization repaired clock loss.

### Audio evidence and original-player comparison

**PASS:** the user heard the final normal-speed `harden-listen-final` Flicky
capture and reported “Audible; no obvious problems.” This is a limited listening
pass, not a claim of inaudible quantization across all music.

WAV evidence includes `harden-measured-real-aggress.wav`,
`harden-measured-real-penguin.wav`, `harden-measured-real-cct.wav`,
`harden-measured-original-cct.wav`, `harden-measured-real-qix.wav`, and
`harden-listen-final.wav` in the ignored logs directory. The downloaded real
track captures have zero clipped samples on the PSG channel. Flicky clips
about 10% of that channel in this MAME capture configuration; physical analog
distortion cannot be inferred from it.

On the matched 8,613-write Penguin CCT musical window, the IRQ event span is
57.173896 s versus 58.311919 s for the original; maximum first-event-relative
error is 63.021 ms versus 1,199.720 ms. The original charges decoding/output
time in addition to its fixed-cycle sample waits and masks interrupts throughout
playback. It is not an elapsed-time reference. The first eight seconds have
100–8000 Hz average-spectrum cosine similarity **0.99265**, using 4,096-sample
Hann windows at 48 kHz. This phase/tempo-tolerant metric supports broadly similar
spectral content, but does not certify pitch, transients, or envelope identity.

The original additionally emits 97 non-mute writes after the matched converted
CCT stream and mutes at 77.417590 s. Its CCT loader does not initialize loop
state; the experimental loader already fixed that before this work. The exact
post-stream state in this original-player run was not isolated. Accordingly,
the comparison uses the matched musical window only and does not treat the
original completion sequence as a correctness oracle. Original VGM loading
of the downloaded Penguin file also fails with EOF; that is excluded from
audio comparisons. The original binary remains untouched.

## Overhead and queue sizing

The initial four-tick wakeup comparison on the same Flicky stream preserved all
820 writes, 20.125906 seconds first-event-to-mute and 39.409 ms maximum event
lateness. Full-ring rejections fell from 844 to 210; SetStat/GetStat calls fell
from 2,923 to 1,384 (52.7%). Sampled user-state producer time fell from 0.7088 to
0.4127 seconds (41.8%). These CPU samples cover the whole capture and omit
kernel service CPU time; they are not a total utilization measurement.

The ring remains 256 × 4 = 1024 bytes; there is no evidence justifying a larger
ring or a higher IRQ rate. The producer can queue seconds of sparse music, but
only about 267 ms at the maximum 960-record/s consumption rate. The unchanged
16-write budget bounds interrupt execution near 1.67 ms in the measured
fixtures. Producer publication remains about 86 microseconds with interrupts
masked, separately from OS-call overhead. No disk I/O, allocation or unbounded
parsing was added to IRQ context.


Before terminal publication, the final queue measurements were:

| Stream | Min / median records | Min / median lookahead ticks |
| --- | ---: | ---: |
| Flicky | 240 / 256 | 354 / 384 |
| Rastan | 239 / 254 | 73 / 150 |
| Penguin | 237 / 253 | 60 / 98 |
| Super Qix | 246 / 255 | 179 / 222 |
| Long stream | 240 / 256 | 572 / 616 |

Lookahead is inferred from validated publications and serviced ticks, not an
independent elapsed clock. Final drain naturally reduces occupancy and is
excluded from this steady-state table. Penguin retains at least one second
of serviced-clock lookahead in the measured run. This supports retaining the
existing ring size and four-tick wakeup.

The final Flicky producer uses approximately 0.4072 user-state seconds. The
210-second producer uses 3.0137 user-state seconds, 8,298 SetStat and 3,151
GetStat calls, and 3,000 full-ring retries; the checkpoint used approximately
6.413 seconds, 17,298 / 12,601 calls and 12,000 retries. Kernel CPU time remains
unmeasured. No atomic-clock reads are made by cctirq.

## Failure handling and ownership

Cold tests compare physical allocation maps, system-page maps, process/path
snapshots, IRQ poll tables, VIRQ tables and module residency before and after.
A PASS requires exact resource restoration, not merely a returned Shell prompt.
The three diagnostic builds inject failure before F$IRQ, after F$IRQ but before
successful F$VIRQ, and on the second owned allocation after one real allocation.
They do not patch the kernel or consume all available machine memory.


| Case | Result and evidence |
| --- | --- |
| Cold VGM, CCT, M3U completion | PASS: exact sequences, silence, exact memory/path/table restoration; no player/driver/descriptor left resident. |
| Missing file, empty file, dual AY | PASS: nonzero reported error, zero PSG writes, exact restoration. |
| Init before F$IRQ failure | PASS: zero PSG writes and no registration to remove. |
| VIRQ failure after F$IRQ | PASS: IRQ rollback, zero PSG writes, exact restoration. |
| Second allocation fails | PASS: first allocation released; no music, only owned cleanup mutes. |
| Stop with full ring | PASS: 256 pending records, owner cleared, zero underruns, exact restoration. |
| Dense paced real-track stop | PASS: 1,778 ordered writes then mute; 252 pending records, zero underruns. |
| Actual cctstop near-empty | PASS: two pending records; no later music; exact restoration. |
| Playlist-transition stop | PASS: first VGM finishes; second-track loading is cancelled and released. |
| Forced kill during loading | PASS: no musical writes, owned resources released. |
| Forced kill with queued CCT | PASS: remaining events cancelled and audio muted; exact restoration. |
| Repeated cold launch and stop cycles | PASS: two additional completion cycles and two additional sparse stop cycles restore resources exactly. |
| Unpaced 4,100-write burst / late stop | FAIL for smooth playback/stop delivery: underrun precedes stop, helper reports signal error because child has exited; PASS for fail-closed cleanup. |

The full, near-empty and paced stop captures end with PSG-channel AC RMS below
0.44 PCM units over the last second (0–32767 scale), consistent with silence.
No register writes are discarded during normal playback; cancellation intentionally
silences and abandons future events. Final diagnostic detach leaves no audio IRQ
or VIRQ registration. The private MAME guest and bridge were stopped afterward.

An extreme 4,100-write zero-wait stream can outrun the producer and fail closed
before a later stop reaches it. That is not a successful dense-playback stop
result. Ordinary paced music and this intentionally pathological burst must
remain separate acceptance categories.

## Physical testing and release boundaries

Use a backed-up installation on the real CoCo 3, CoCoSDC and Mega Mini MPI.
Install only the combined player and cctstop; record OS/driver versions, CPU,
RAM, MPI slot, PSG clock and audio routing. Start with a known 1/2 MHz tone and
Flicky, then the tested real tracks. Record analog audio externally and compare
musical duration, pitch and pauses with Shell/counter/command activity. Repeat
stop/restart, playlist-transition stop and forced termination, checking silence,
MPI restoration, free memory and device/module teardown.

Test conventional floppy-emulation access and CoCoSDC native-command access
separately, naming the installed NitrOS-9 disk driver in each result. MAME's
WD1773 floppy captures do not establish CoCoSDC native-mode compatibility or
physical HALT duration. Also outstanding: physical audio, PAL, 6809/512 KB,
GShell/mouse coverage and long modulo-tick wrap qualification.

Rollback: continue using the preserved relative, atomic-clock or cctpark
comparison variants; standalone cctirq does not replace any of them or change
boot/kernel modules. Keep the IRQ feature explicitly experimental.

## Release-readiness assessment and reproduction

**Suitable for broader opt-in testing of supported CoCoPSG music under ordinary
Shell/VHD activity.** Standalone loading, ownership, stopping and cleanup have
live evidence. It is not an exact-fidelity player for arbitrary AY music, and
ordinary conventional-floppy operations can still produce audible tempo stalls.
Do not describe it as universally smooth background playback during disk access.
No further IRQ frequency increase or kernel architecture change is justified by
these results. Retain the bounded queue and test physical storage next.

NOT RUN: exhaustive malformed/truncated-file fuzzing, physical hardware, general
real-track repeated hardware-envelope coverage, PAL, 6809/512 KB, and modulo-tick
wrap. These remain release qualifications, not inferred passes.

Compact evidence is in `IRQ-PLAYER-HARDENING-MEASUREMENTS.json`. Raw filenames
and SHA-256 values identify the private inputs and WAV captures. The host tools
can reproduce the analyses, for example:

```sh
python3 scripts/analyze-irq-stream.py TRACK.vgm CAPTURE.json
python3 scripts/analyze-irq-fidelity.py TRACK.vgm CAPTURE.json CAPTURE.wav
python3 scripts/compare-irq-audio.py TRACK.cct IRQ.json ORIGINAL.json
python3 scripts/test-irq-fidelity.py
```

For isolated MAME staging, copy modules from `build/` to an **unmounted** private
RBF image, set executable attributes, and stage permitted music separately.
`prepare-irq-fixture.py` generates `harden-sparse.vgm`, `harden-full.vgm` and a
header-bearing M3U test list. `irq-hardening-workload.lua` supplies cold-launch
and injected-failure cases; `irq-stream-workload.lua` supplies the instrumented
real-track/workload matrix. Diagnostic captures require the verified driver
layout from `build/psgstream.json` and the matching player CRC. Never stage over
mounted media or canonical EOU files.
