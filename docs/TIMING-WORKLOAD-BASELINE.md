# CoCoPSG timing under concurrent workloads

2026-10-28. This is a baseline of `dd83f7c`, not a scheduler correction.
The experimental player is unchanged (SHA-256
`666f91ea6a3292e2c0b96f46547698b78bef7dd3215269cc0bc40f8c5035cb8d`,
9,381 bytes, live and ToolShed CRC `$4BB36C`, reentrant). The original `cctplay`
still matches its rebuild, SHA-256
`eabe6b6f3910ebd1af557f64b02c1fb1e1802a3a07a1bf134016b1a4a6792f36`.
The previous reported reboot remains **UNRESOLVED / NOT REPRODUCED**.

## Results

The synthetic VGM has 1,323,000 decoded samples, 1,800 `$62` waits of 735
samples and 210 PSG writes. It has no loop and its first write is at sample 0.
Durations below are MAME emulated time from first PSG data write to final
`07=3F` mute; the production build does not timestamp its `$66` end command.
The sample standard deviation is computed over five runs in each workload.
Every stream contained the complete 210 pairs in order, followed immediately
by the mute. No PSG/FDC events were dropped, and no reset was reported.

| Workload | Five first-write-to-mute durations (s) | Error min / max / mean / sample SD |
| --- | --- | --- |
| Idle | 29.379299, 29.379467, 29.379585, 29.378664, 29.379575 | -2.0711% / -2.0681% / -2.0689% / 0.0013 percentage points |
| Counter | 29.778564, 29.779090, 29.779343, 29.792293, 29.778803 | -0.7381% / -0.6924% / -0.7279% / 0.0199 percentage points |
| Floppy | 45.299976, 45.754515, 45.863912, 45.250976, 45.195639 | +50.6521% / +52.8797% / +51.5767% / 1.0385 percentage points |

`timeload` prints a line and sleeps 61 ticks, 60 times, then exits; each
counter run verified that module CRC `$12274D` remained active until playback
completed. The floppy test uses `diskload`, a read-only process that opens,
reads 256 bytes from, and closes `/d1/ark1.cct` once per 61 requested ticks,
for 230 iterations. The supervisor `diskbench` starts the reader and five
sequential player children, checks their `F$Wait` statuses, then waits for the
reader; the guest printed `DISKBENCH OK`. There were 252–261 FDC command writes
within each playback interval. This is a **MAME floppy** workload, not a
CoCoSDC measurement. It is a defined periodic small-read workload, not a
claim about all disk workloads. An earlier host-typed launch lost characters
while the reader was active and returned `Error #216`; no player started and
that attempt is excluded. The guest supervisor avoids that automation failure.
Long captures wrapped the frame-sample ring
(14,713 discarded samples); the separate event buffer had **zero** dropped
events. The first sampled disk run retained its complete playback interval.

One run of each real track per workload was practical in this baseline. The
Arkanoid VGM and Ark1 CCT contain the same 266-pair stream; Flicky has 820
pairs. In each row the whole expected sequence and the next mute matched.
The 276 samples before the first Arkanoid/Ark1 write (6.259 ms) are added as
an **estimate**, not a measured startup interval. Flicky's first event is at
sample 0. These single observations are not a repeatability statistic.

| Track, decoded duration | Idle estimated s | Counter estimated s | Floppy estimated s |
| --- | ---: | ---: | ---: |
| Arkanoid VGM, 4.430204 s | 4.441446 (+0.254%) | 4.428224 (-0.045%) | 6.527292 (+47.336%) |
| Ark1 CCT, 4.430204 s | 4.434775 (+0.103%) | 4.484793 (+1.232%) | 6.502318 (+46.772%) |
| Flicky CCT, 20.089977 s | 19.851733 (-1.186%) | 19.985434 (-0.520%) | 28.571076 (+42.216%) |

For the floppy real-track run, `diskreal` spawned the reader and the three
tracks, checked their statuses, then waited for the reader. It printed
`DISKBENCH OK`; there were respectively 36, 36 and 162 FDC command writes
within the observed playback intervals. Channel 2 of the private MAME WAV had
mean-removed one-second RMS values of 7,724, 7,522 and 13,506 16-bit PCM counts
for the idle real tracks, confirming non-DC audio generation. This is not a
human audio-quality assessment.

**Target below 1%: FAIL** for this scheduler and these workloads. A comparison
with a changed scheduler is **NOT RUN** because no sufficiently resolved,
safe monotonic time source was established. The bounded experiment does not
prove all ordinary user-process schedulers cannot meet the target.

## Why the measured duration changes

The player's coarse wait is entered only for at least two whole tick intervals.
All 1,800 synthetic waits are 735 samples or less after debt subtraction, so
**none uses F$Sleep**. They are interruptible CPU-cycle fine waits. When the
player is preempted, elapsed wall/emulated time passes but the remaining loop
count does not advance; the relative scheduler has no timestamp with which to
shorten the next wait. This explains why the same decoded sample count gets
longer with extra runnable work. The existing fixed command debt compensates
an average amount of CPU work; it cannot measure actual preemption or tick
phase. The code caps debt at a tick and distributes the fractional wait-cost
allowance in eighths; it does not carry an absolute wall-time error.

In one fully retained playback window, 1,807 of 2,717 frame samples showed
the player with a saved PC in its fine-wait loop, 21 showed another player
PC, 746 showed `diskload`, and 143 were other/unknown. This sampling is tied
to video frames and is not a precise CPU profiler; task identity during system
work is also limited. The observed 45.342 s playback had 252 FDC writes.
These data support preemption as the dominant source in this fixture; they do
not individually apportion floppy IRQ service, scheduler latency, host time,
or disk-process CPU. With the counter, brief work can be missed by frame
sampling, so the approximately 0.400 s increase cannot be split reliably.

Local event timing and accumulated drift are separate. In the five floppy
runs the worst individual nominal 0.5-second inter-event interval was late by
570.4–653.0 ms. In the sampled floppy run, one such interval was 1.130 s,
0.630 s late, with nine FDC commands in the interval. Its accumulated event
lateness reached approximately 15.35 s. The first idle run's median local
half-second interval was about 10.75 ms early, accumulating to about 0.621 s
early by the last event. Correlation with disk activity does not establish the
cost of each individual IRQ or call.

The existing probe measured five repetitions in this guest. Marker-to-marker
F$Sleep durations were X=1: 1.143 ms; X=2: 10.562–14.980 ms; X=3:
33.871–34.038 ms; X=4: 49.877–50.044 ms; X=10: 149.757–150.173 ms;
X=61: 1001.269 ms. All returned X=0. These include call, marker and scheduling
overhead; X=61 is consistent with about 60 NTSC video ticks. They do not
separately isolate phase and wakeup latency. `tpsprobe` again printed
`TPS!A=00 B=D0` (`E$UnkSvc`). Historical controlled decoder/write cost and
early-wakeup observations are in [TIMING-ANALYSIS.md](TIMING-ANALYSIS.md).

A separate visible guest ran the synthetic fixture with no timing observer or
write taps. Its MAME WAV active-audio interval was 29.39 s, using 10 ms RMS
windows; the observer-enabled guest's first idle WAV interval was also 29.39 s
at that resolution. This one idle comparison does not rule out smaller effects
or quantify tracing overhead under floppy load.

## Scheduler evaluation

The locally available NitrOS-9 reference clock source copies six bytes for
`F$Time` and keeps `D.Tick` in system state; `F$STime` can alter the clock.
The tested EOU rejects `F$TPS`. Neither proves a process-accessible monotonic
sub-tick timestamp. See the [NitrOS-9 clock source at the inspected reference
revision](https://github.com/nitros9project/nitros9/blob/f470fa52eb172b59b22c1b722074998cb42de9b1/level2/modules/clock.asm).
The GIME interrupt/timer and MPI state are shared with the OS and other
devices; their availability as a non-disruptive process clock is not proven.
Polling a whole-second wall clock cannot bound individual event lateness and
can jump when the clock is set. Retuning a fixed fine-loop or debt constant
would improve one workload at the expense of another and cannot compensate for
unknown time spent descheduled. Substituting one-tick sleeps also does not
provide the required event resolution or a verified deadline.

No new scheduler was implemented, and no timing constant, interrupt handler,
kernel or hardware support was changed. A future prototype needs a verified
monotonic source, bounded catch-up and independent jitter/responsiveness tests.
The disk results justify investigating an OS-compliant timing mechanism, but
do not establish that a kernel extension or dedicated driver is the only
possible solution.

## Other checks and reproduction

During a fresh background synthetic run, Shell accepted `echo TIMINGOK`;
an initially nonresident floppy-loaded `cctstop` sent signal 3 to the verified
player PID and the last PSG pair was `07=3F`. `mfree` was 1,784 KiB before
and after, the Shell prompt returned, and there was no reset notification.
This is one aggregate cleanup check. Existing natural M3U and transition-stop
coverage for this exact player is documented in
[PLAYLIST-STOP-TIMING.md](PLAYLIST-STOP-TIMING.md); it was not rerun as a new
scheduler regression because the player was not changed.

The test configuration was visible MAME `0.289 (ample-289-u2)`, `coco3h`,
HD6309, 2 MiB, NTSC EOU, MPI slot 2 `ccpsg`, slot 4 `fdc`, with private boot,
VHD and RBF test floppy copies. Initial boot and VHD SHA-256 values were
`9a51adb8656b9f003c7f822352c291487362f1b4c43aac1a16672d5d2bcb4c40` and
`7bef15fab761db2084517ebadaa5b7ee42a667ee7131fcf629ee8c3531835681`.
The test floppy before the idle/counter run had SHA-256
`a43ff96ca5cc56e7c866eb02fa3fe805d9dcccebf3636c8216206f878fa81241`;
the supervised floppy image had SHA-256
`eda6a42978e12f971262a39cc299c5136eb5db44c00784a5458d4b304af78ad2`.
The observer source SHA-256 was
`b8e9cbf543735fedb5b5ec01ec36718a420c837203eb702e0d0f8d43a6723b36`.
The fixture SHA-256 values were synthetic
`b87c4bd79d2b36fa1654e88ae3454cd9de85de99ab72f0aef43ccf8c1d7e3840`,
Arkanoid `7e8bba36ecbfe429c1cd0ff4d6e6490f4ab0e491279a5c6b3c7157e6be703698`,
Ark1 `7a8029ee746f7645e1d6c5a1874a0aa50353216ff2643e5bbf5ae766ac60f442`,
and Flicky `65ae436ba023bbe62fcdcbb7266f3283d600c0b5e1bd7aa56ec206aa9940337c`.
The observer/analyzer and disk helpers are host/test diagnostics, not part of
the player. Private music, media, logs and WAV are ignored and not committed.

```sh
bash scripts/build.sh
# Supply original private fixtures with these basenames; never stage a mounted disk.
CCT_TEST_DISK="$PWD/emulator/images/timing-new/media/repro.dsk" \
  bash scripts/stage-test-disk.sh "$FIXTURE_DIR/synthetic30.vgm" \
  "$FIXTURE_DIR/arkanoid.vgm" "$FIXTURE_DIR/ark1.cct" "$FIXTURE_DIR/flicky.cct"
# In a second terminal, use the existing private bridge/observer copy:
node emulator/images/timing-new/mcp/bridge-host.js
# With private, unmounted boot and VHD copies at BOOT_COPY and VHD_COPY:
/Applications/Emulators/Ample.app/Contents/MacOS/mame64 coco3h \
  -ramsize 2M -window -skip_gameinfo -natural \
  -flop1 "$BOOT_COPY" -hard1 "$VHD_COPY" \
  -flop2 "$PWD/emulator/images/timing-new/media/repro.dsk" \
  -ext multi -ext:multi:slot4 fdc -ext:multi:slot2 ccpsg \
  -rompath "$HOME/Library/Application Support/Ample/roms" \
  -cfg_directory emulator/images/timing-new/cfg \
  -nvram_directory emulator/images/timing-new/nvram \
  -state_directory emulator/images/timing-new/states \
  -snapshot_directory emulator/images/timing-new/snapshots \
  -autoboot_script emulator/images/timing-new/mcp/scripts/bridge.lua \
  -autoboot_delay 0 -sound coreaudio \
  -wavwrite emulator/images/timing-new/logs/repro.wav
# With the private EOU guest and the local Lua observer running:
# chx /d1; load cctplaymt diskload diskbench diskreal timeload
# diskbench &   (five synthetic streams with the bounded floppy workload)
# diskreal &    (three real streams with the same workload)
python3 scripts/summarize-psg-repeats.py "$FIXTURE_DIR/synthetic30.vgm" \
  emulator/images/timing-new/logs/trace-baseline-disk-supervised.json
```

The captured emulated-time evidence is in ignored
`emulator/images/timing-new/logs/trace-baseline-*`; the no-observer WAV is in
`emulator/images/timing-plain/logs/`. Recreate the private visible MAME launch
using these separate images and the local test bridge at
`emulator/images/timing-new/mcp/scripts/bridge.lua`. The bridge and observer
copies are local ignored test artifacts, not provided by a clean Git checkout;
their exact source hashes are recorded above. No canonical media or
original MCP server files are changed. The player process data size is 1,970
bytes; `diskload` requests 387 data bytes and `diskbench` 3 (OS-9 allocation and
stack rounding add overhead). Precise player CPU percentage is **NOT RUN**.
