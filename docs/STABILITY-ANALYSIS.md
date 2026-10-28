# PSG Shell stability investigation

2026-10-27; checkpoint `d4f98b1`. These results are from MAME 0.289,
`coco3h`, HD6309, 2 MB, EOU Level II, slot 2 `ccpsg`, and slot 4 `fdc`.
The guest used disposable private copies of the boot floppy, EOU virtual hard
disk and test floppy. These are MAME storage tests, not CoCoSDC tests. The
original `cctplay` SHA-256 was
`eabe6b6f3910ebd1af557f64b02c1fb1e1802a3a07a1bf134016b1a4a6792f36`.

## Findings at the checkpoint

**The earlier reboot is UNRESOLVED / NOT REPRODUCED.** A visible isolated
session was instrumented from the host. There was no emulator reset notification
in the following cases; the Shell remained visible and accepted further
commands. This is not evidence that the earlier incident was a reset or that it
has been fixed. The cases below were performed sequentially in one boot, with
module residency checked before each relevant load; they are not independent
fresh-boot repetitions.

The guest `devs` command identifies `/d1` as RBF using `rb1773` at `$FF40`, and
`/dd` as RBF using `EmuDsk` at `$FF80`. Byte-for-byte identical `stbutil` and
`cctstop` executables were staged on both private devices. `stbutil` only
prints `STBUTIL OK` and exits; it was absent from the module directory before
its load. A generated 120-second PSG stream provided a long playback window.

| Test | Result | Observation |
| --- | --- | --- |
| Harmless utility without playback | PASS, both devices | `STBUTIL OK`; Shell returned. Fresh loads were observed via module-directory writes. |
| Same utility during playback, `/d1` | FAIL | `Error #240 - Unit Error`; PSG writes continued and Shell returned. |
| Same utility during playback, `/dd` | PASS | `STBUTIL OK`; VHD commands and continuing PSG writes captured. |
| Load absent `cctstop` without executing, `/d1` | FAIL | `load /d1/cctstop` gave `Error #240`; it remained nonresident; no signal write was captured. |
| Load absent `cctstop` without executing, `/dd` | PASS | Module directory showed `cctstop` resident; no signal was sent; PSG writes continued. |
| Execute resident `cctstop` from `/dd` | PASS, one cycle | Verified player PID 3 received signal 3; player module disappeared; register 7 was set to 63 and MPI returned to `$FF`. |
| On-demand absent `cctstop`, `/d1` | FAIL | `Error #240`; no signal was sent; player remained active and PSG writes continued. |
| On-demand absent `cctstop`, `/dd` | PASS, one cycle | Verified player PID 3 received signal 3; player exited; final register 7 write was 63; Shell returned. |

`cctstop` residency was checked from the actual OS-9 module directory rather
than inferred from command history. `unlink cctstop` and a subsequent directory
check preceded the on-demand cases. The signal tap monitored the verified player
process descriptor, not an arbitrary PID. Module directory, signal byte, PSG,
MPI, FDC and VHD writes and frame-sampled CPU registers, process descriptor,
DAT and MMU state were recorded by a bounded host-side Lua observer. These are
local ignored artifacts under `emulator/images/stability-run/`; they include
`trace-boot2-idle-floppy.json`, `trace-boot2-idle-vhd.json`,
`trace-boot2-play-floppy.json`, `trace-boot2-play-vhd.json`,
`trace-boot2-load-only-floppy.json`, `trace-boot2-load-only-vhd.json`,
`trace-boot2-resident-stop.json`, and `trace-boot2-ondemand-{floppy,vhd}.json`.
Trace buffers for these specific captures did not overflow. Frame sampling can
miss individual instructions; a lack of a sampled instruction is not proof
that it did not execute.

At playback start the checkpoint selects `$F1` at `$FF7F` and leaves it there
until cleanup. At rest the selection was `$FF`. The PSG is in MPI slot 2 while
the floppy controller is in slot 4. The differential failure implicates the
player's long-lived MPI selection in the floppy failure; it does not establish
the cause of the old reported reboots. Virtual hard disk access remains working
in this MAME configuration. Restoring the prior slot only at playback exit is
not sufficient for concurrent floppy access.

## Uncommitted MPI transaction experiment

A separate private build selects the PSG only for each register transaction,
then restores the selection present on entry. Its save/select/write/restore
sequence masks IRQ/FIRQ briefly; the measured `$F1`-to-`$FF` interval was
17.879 microseconds in this MAME trace, excluding the mask instructions around
it. This is an experiment, not an accepted patch: floppy transfer interrupt
latency, competing MPI users, and all cleanup/error paths still require testing.
It did not change any wait or delay constant. The experiment source and binary
remain ignored under `emulator/images/stability-run/build/mpi-candidate*`;
the binary SHA-256 is
`15de837a7b6ce900ebb75a9c7a641ffce98cfb2794970e69ea878370beb30b2f`.

In one fresh boot, `/d1/stbutil` succeeded during playback, with 33 FDC
commands and continued PSG writes observed. One genuinely nonresident
`/d1/cctstop 3` then loaded, sent signal 3 to the verified player, and produced
mixer silence (`07=3F`); the Shell returned and no reset notification occurred.
This is **one** successful on-demand floppy stop, not the requested 20 cycles.

A separate natural-completion test decoded 1,323,000 samples (30.000 seconds)
from `synthetic30.vgm`. All 210 expected register/value pairs appeared in order,
followed by `07=3F`, and the player exited. First register data to final mute
was **29.372720 emulated seconds**, **2.091% fast**, compared with the prior
checkpoint's 29.958991 seconds for the same fixture. The cause of this
regression is not established; the runs have different instrumentation and
conditions. The private MAME WAV contained a variable PSG-channel waveform
during the fixture (roughly 8,148 PCM counts standard deviation in a one-second
window after removing its DC mean), and was effectively constant after
completion. The WAV header remains unfinished while MAME is running. Thus the
candidate addresses the observed floppy symptom in one case, but its timing and
stability are not validated and it was not promoted into the player.

Evidence: `trace-candidate-play-floppy-complete.json`,
`trace-candidate-ondemand-floppy-complete.json`,
`trace-candidate-synthetic30.json` and `candidate.wav` in the ignored private
run directory. The synthetic fixture SHA-256 is
`b87c4bd79d2b36fa1654e88ae3454cd9de85de99ab72f0aef43ccf8c1d7e3840`.

## Ownership and signal audit

The experimental signal intercept stores the signal in `abortFlag,U` using the
U local-storage pointer supplied at signal entry, and returns via `RTI`; it
does not rely on asynchronous DP. The VGM command and fine-wait paths test the
flag, and normal PSG cleanup silences register 7 before releasing mappings.
The tested resident and VHD on-demand signal paths reached this cleanup.
Other interrupted loader and playlist paths need live validation.

The stream mapping and guard mapping are tracked separately: `F$AllRAM` owns
the guard block, `F$MapBlk` reserves its slot, and `F$ClrBlk` precedes
`F$DelRAM` in normal cleanup. Error paths remain a concern: if `F$ClrBlk`
fails, cleanup continues toward releasing allocations; a failed loader read
may also leave a transient mapping without an explicit cleanup flag. These are
static audit observations, not reproduced causes of the earlier reboot.

`EXIT_CHECK_PLAYLIST` can advance to the next entry before checking `abortFlag`;
that path needs an observed stop-during-transition test. Do not infer a pass
from the successful single-track stop.

## Existing 176 ms timing outlier

The earlier synthetic-30 trace reports maximum positive event lateness of
175.941 ms. It is not exclusively total-duration drift: at sample 66,150 the
stream was already about 50.134 ms late, and the following nominal 500 ms gap
lasted approximately 625.292 ms, adding roughly 125.292 ms in one interval.
Several same-sample writes add a small further amount. The final playback
completion was about 41 ms early. The old trace contains PSG timestamps but no
correlated sleep, task-switch, disk or automation timestamps, so it cannot
identify the cause of that gap. Duration accuracy and inter-event jitter are
separate measurements; no delay constant was changed to hide this outlier.

## Remaining acceptance work

Capture and classify any actual recurrence of the reboot. Validate a bounded
MPI selection/restore experiment under floppy load, with disk transfers,
signal delivery, register order, audio, timing and all error exits checked.
Repeat on-demand stops at different positions and playlist transitions across
multiple clean boots; the requested 20-cycle stability target has not been
met. Retest full register streams, duration, M3U and ordinary Shell/disk
activity after any code correction. Do not treat one successful VHD stop as
universal stability.
