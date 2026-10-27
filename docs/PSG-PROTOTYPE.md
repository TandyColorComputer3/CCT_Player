# Experimental CoCoPSG process prototype

**Status:** background CoCoPSG VGM/CCT/M3U playback, natural completion, and stop with a preloaded helper are demonstrated in isolated EOU MAME. The measured timing correction and its limitations are in [TIMING-ANALYSIS.md](TIMING-ANALYSIS.md). On-demand stop attempts caused guest reboots; their cause is unresolved. GMC, OPL, and loop-bearing-file coverage remain pending.

## What changed

The reference program remains the normal `cctplay` build. `scripts/build.sh` assembles the shared source twice: without defines for the original baseline, then with `EXPERIMENTAL_PSG` for `cctplaymt`. The script checks that the baseline rebuild is byte-identical to the tracked binary. The experiment dispatches only YM2149/AY CCT tracks to the PSG backend and rejects other chip types; the original OPL and GMC paths remain available only through the default build.

The experimental PSG playback path has three responsibilities:

1. `VGM_YM2149_NEXT_COMMAND`, `VGM_YM2149_CMD_CHIP`, `VGM_YM2149_CMD_WAIT_MANUAL`, and the frame/short-wait labels fetch and decode the supported VGM command stream.
2. `VGM_PSG_COARSE_WAIT` handles long waits using OS-9 `F$Sleep`, then `VGM_YM2149_WAIT_FINE_LOOP` burns the remaining VGM sample count. The decoder retains the VGM 44.1 kHz sample unit and the existing 735/882 sample frame waits.
3. `VGM_PSG_WRITE_REG` performs the bounded PSG register-select/data-port sequence.

The player no longer holds IRQ/FIRQ masked for the experimental playback loop. OS-9 clock interrupts can preempt the user process. Nominal 60 Hz NTSC / 50 Hz PAL ticks correspond to 735 / 882 VGM samples. Long waits use `F$Sleep`; short waits use the interruptible HD6309 fine loop. The player accounts for measured command cost and average sleep phase in sample units. It does not compare commands against an absolute monotonic deadline.

## MMU and resource handling

The experimental stream reader no longer changes `$FFA9`. It maps one allocated physical song block into an unallocated process DAT slot with `F$MapBlk`, uses its returned logical address, and removes it with `F$ClrBlk` before mapping the next page. A one-block guard allocation is mapped first; because EOU `F$MapBlk` maps from the top down, the stream page is placed below that guard. The guard and stream state live in the process data area. See the [EOU Technical Reference Manual, F$MapBlk](https://www.lcurtisboyle.com/nitros9/EOUDOCS/NitrOS-9_EOU_Level_2_Technical_Reference_Manual.pdf).

The process continues to own its file paths, allocated song blocks, and signal intercept. The signal handler sets the existing `abortFlag` through the U local-storage pointer supplied to `F$Icpt`; it does not assume DP is valid on asynchronous signal entry. Experimental waits check the flag without scanning `$FF02/$FF00`. The player selects the requested PSG slot before saving its control register. The startup snapshot of MPI selection and `$FF23` PIA state is restored during cleanup; PSG output is silenced, mappings are cleared, and the guard block is released before song RAM is returned. Loader-owned paths are marked invalid immediately after `I$Close`, including between playlist entries.

Normal completion and `cctstop` signal cleanup with a preloaded helper have run successfully on EOU. The player stops PSG writes and leaves the Shell usable. On-demand helper loading has also coincided with guest reboots; that failure remains unresolved. Production `cctplaymt` is quiet after background launch so asynchronous metadata cannot overwrite the returned prompt; `cctplaydbg` remains the foreground diagnostic build.

MPI selection, `$FF23`, and the PSG are global hardware resources. This prototype has no OS-9 device lock or IPC ownership protocol. The controlled concurrency run used only the counter as the second process; simultaneous use by another audio or MPI program remains untested and unsupported by this prototype.

## Timing and expected load

The final MAME trace measured a 30-second synthetic file at 29.959 seconds, the Arkanoid PSG VGM at an estimated 4.458 versus 4.430 seconds, and Flicky CCT at 19.964 versus 20.090 seconds. All recorded register sequences matched. The controlled 10- and 30-second fixtures ranged from −0.72% to +0.86% in this run. Full measurements and the initial-wait estimate are in [TIMING-ANALYSIS.md](TIMING-ANALYSIS.md).

The correction is calibrated for the tested NTSC/HD6309 configuration and remains relative. One synthetic event was about 176 ms late even though its total duration was accurate. Decode CPU time, total CPU share, and scheduler wait time were not separately measured. `F$TPS` returned `E$UnkSvc` on this EOU boot; a true absolute-deadline scheduler still needs a verified monotonic time source. PAL, 6809, extreme event rates and other workloads are untested. The present evidence does not justify a driver or kernel change.

## Build and static validation

Run from the repository root:

```sh
bash -n scripts/*.sh
bash scripts/build.sh
cmp -s cctplay build/cctplay
```

The current successful build produced:

| Module | Size | CRC | Header result |
| --- | ---: | --- | --- |
| Original `cctplay` | 8,756 bytes | `$7A98E7` | Program, 6809 object code, re-entrant, read-only |
| Experimental `cctplaymt` | 8,988 bytes | `$05B97E` | Program, 6809 object code, re-entrant, read-only |
| End-marker diagnostic `ccttiming` | 8,997 bytes | `$6F48CC` | Program, 6809 object code, re-entrant, read-only |
| Counter `cctcount` | 91 bytes | `$86E3C1` | Program, 6809 object code, re-entrant, read-only |
| Graceful stop `cctstop` | 143 bytes | `$077B9E` | Program, 6809 object code, re-entrant, read-only |
| Clock probe `tpsprobe` | 140 bytes | `$2C9AF5` | Program, 6809 object code, re-entrant, read-only |

ToolShed reported each CRC as Good. The generated test VGM is 256 bytes, contains a YM2149 clock/variant header, tone writes, two 30-frame note sections made from 735-sample waits, a silence write, and an end command. The generated file contains no imported music.

To recreate only the private stage floppy, after confirming it is not mounted:

```sh
bash scripts/stage-test-disk.sh
```

This stages the players, timing and hardware probes, counter, `cctstop`, and `synthetic.vgm` on `emulator/images/chiptunes-test.dsk`. Set `CCT_TEST_DISK` to an absolute path inside `emulator/images/` to select a different private disk. The script refuses to rewrite a disk it detects as open. Do not reset or overwrite the project EOU VHD for this test.

## Runtime verification commands

Runtime verification is **PASS for the synthetic concurrent milestone** in the isolated private session. The exact reproduction commands are:

```sh
bash scripts/build.sh
bash scripts/stage-test-disk.sh
bash scripts/run-mame.sh psg
```

At Disk BASIC's `OK` prompt, enter `DOS`. In the EOU Shell select the private command directory and preload the commands:

```text
chx /d1
load cctplaymt cctstop
```

Run a file or playlist in the background:

```text
cctplaymt -psg 2 /d1/track.vgm &
```

Shell prints a PID such as `&003`. The prompt must return immediately. To stop through normal cleanup, run `cctstop 3`; do not use a fatal kill. Check that Shell input still works and the track starts/stops without a stuck note. Record guest logs/screenshots and an audible inspection. Then compare the default reference with:

```text
load /d1/cctplay
cctplay -psg 2 /d1/synthetic.vgm
```

The ordinary MAME run script selects `coco3h`, HD6309, 2 MB, MPI slot 2 `ccpsg`, plus the established EOU media. Wait until no MAME process has those media open before launching or staging. `scripts/run-mame.sh` and `scripts/stage-test-disk.sh` enforce their project-image guards.

## Historical evidence matrix

These entries describe the earlier concurrent milestone and its builds. The latest timing and stop results are in [TIMING-ANALYSIS.md](TIMING-ANALYSIS.md).

| Check | Result | Evidence / limitation |
| --- | --- | --- |
| Baseline build | **PASS** | `build/cctplay` matches tracked `cctplay` byte for byte. |
| Experimental module build | **PASS** | LWASM `--6309 --format=os9 --define=EXPERIMENTAL_PSG` completed. |
| Counter module build | **PASS** | LWASM build completed; ToolShed header and CRC are valid. |
| Module headers/CRCs | **PASS** | `os9 ident` reports valid CRCs and re-entrant Program modules for all three. |
| Synthetic VGM generation | **PASS** | 256-byte generated YM2149 tone/silence test. Guest parsing is not demonstrated. |
| Private floppy staging | **PASS** | `bash scripts/stage-test-disk.sh` created the 368,640-byte project-local test floppy and listed `cctplay`, `cctplaymt`, `cctcount`, and `synthetic.vgm`. The script's `lsof` guard found no open handle to this floppy. |
| Counter running on EOU | **PASS (historical 100-tick helper)** | The counter advanced while sleeping 100 ticks between updates and while Shell commands ran; at 60 Hz NTSC that interval was about 1.67 seconds. Current source requests 61 ticks to sleep 60 ticks (~1 second). |
| Audio and PSG hardware behavior | **PASS** | 422 non-dropped `$FF5E/$FF5F` writes and a 30.35-second non-DC WAV signal. |
| Counter + playback concurrency / Shell responsiveness | **PASS** | Counter values advance on the same screen as the playback banner; post-run `procs -e` succeeds and shows no player process. |
| Timing drift | **PASS with measured drift** | 30.000-second fixture produced 30.35 seconds of active audio (+1.17%); startup half-second events measured 0.5006--0.5219 seconds. |
| CPU utilization | **NOT RUN** | No reliable guest CPU-share profiler was available. |
| Cleanup | **PASS for normal and signal stop** | Player exits, disappears from `procs`, register activity stops, and the Shell remains healthy after `cctstop`. |

## Known limits and next steps

- Real VGM, two original CCT files, and a two-entry M3U load and play in the background. The measured tracks meet 1% total-duration accuracy in the latest run, but event jitter and on-demand stop failures remain open.
- Relative delay loops compensate for estimated command and sleep costs, but not observed interrupt, scheduler, or disk delays. Counter progress and total duration passed in the measured runs; the synthetic trace still showed substantial local lateness.
- The current POC is PSG-only. GMC and OPL playback continue to use the original interrupt-masked routines in the byte-identical default build and are excluded from `cctplaymt` dispatch.
- Loop-bearing files, bad files, GMC, OPL hardware, 6809, and 512 KB remain untested. Cross-page playback, normal cleanup, two-entry path cleanup, and signal stop have runtime coverage.
- Further work should characterize event jitter and the on-demand stop failure before considering a different timing mechanism.
- Rollback this experiment by reverting the prototype commit. The tracked original `cctplay` and baseline build remain intact.
