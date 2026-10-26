# Experimental CoCoPSG process prototype

**Status:** synthetic CoCoPSG concurrency milestone demonstrated in isolated EOU MAME; broader format, abort, repeated-load, and hardware coverage remains pending.

## What changed

The reference program remains the normal `cctplay` build. `scripts/build.sh` assembles the shared source twice: without defines for the original baseline, then with `EXPERIMENTAL_PSG` for `cctplaymt`. The script checks that the baseline rebuild is byte-identical to the tracked binary. The experiment dispatches only YM2149/AY CCT tracks to the PSG backend and rejects other chip types; the original OPL and GMC paths remain available only through the default build.

The experimental PSG playback path has three responsibilities:

1. `VGM_YM2149_NEXT_COMMAND`, `VGM_YM2149_CMD_CHIP`, `VGM_YM2149_CMD_WAIT_MANUAL`, and the frame/short-wait labels fetch and decode the supported VGM command stream.
2. `VGM_PSG_COARSE_WAIT` handles long waits using OS-9 `F$Sleep`, then `VGM_YM2149_WAIT_FINE_LOOP` burns the remaining VGM sample count. The decoder retains the VGM 44.1 kHz sample unit and the existing 735/882 sample frame waits.
3. `VGM_PSG_WRITE_REG` performs the bounded PSG register-select/data-port sequence.

The player no longer holds IRQ/FIRQ masked for the experimental playback loop. OS-9 clock interrupts can preempt the user process. On the tested EOU system, coarse waits use the 100 Hz clock (441 VGM samples per tick); the call passes N+1 because this `F$Sleep` path counts down to one. The remaining 0--440 samples use the measured/padded interruptible HD6309 loop. The fine loop enters its coarse-wait conversion once per wait, not once per sample.

## MMU and resource handling

The experimental stream reader no longer changes `$FFA9`. It maps one allocated physical song block into an unallocated process DAT slot with `F$MapBlk`, uses its returned logical address, and removes it with `F$ClrBlk` before mapping the next page. A one-block guard allocation is mapped first; because EOU `F$MapBlk` maps from the top down, the stream page is placed below that guard. The guard and stream state live in the process data area. See the [EOU Technical Reference Manual, F$MapBlk](https://www.lcurtisboyle.com/nitros9/EOUDOCS/NitrOS-9_EOU_Level_2_Technical_Reference_Manual.pdf).

The process continues to own its file paths, allocated song blocks, and signal intercept. The signal handler sets the existing `abortFlag`; experimental waits check it without scanning `$FF02/$FF00`. The player selects the requested PSG slot before saving its control register. The existing startup snapshot of MPI selection and `$FF23` PIA state is restored during cleanup; PSG output is silenced, mappings are cleared, and the guard block is released before song RAM is returned. Normal-completion cleanup has now run successfully on EOU: the player exited, disappeared from `procs -e`, and left no audible stuck note. Signal-abort and repeated-load cleanup still require runtime tests.

MPI selection, `$FF23`, and the PSG are global hardware resources. This prototype has no OS-9 device lock or IPC ownership protocol. The controlled concurrency run used only the counter as the second process; simultaneous use by another audio or MPI program remains untested and unsupported by this prototype.

## Timing and expected load

The original delay loop approximates 40.58 CPU cycles per VGM sample at the target fast CPU mode. Live timing showed that the first experimental fine loop was only about 28 cycles/sample. The current HD6309 path adds a measured 13-cycle pad and keeps interrupts enabled; interrupt handling and competing processes can still add lateness. It does not maintain absolute deadlines or compensate later events for earlier overrun. The final 30-second concurrent fixture measured 30.35 seconds (+1.17%).

`F$Sleep` avoids spinning throughout long rests, but it is tick-granular and the time to resume the process depends on OS-9 scheduling. It is used only for coarse waits, never as an individual-event timer. The short-wait path still consumes player CPU between scheduler interrupts. Startup event intervals and total duration were measured, but CPU share and worst-case jitter across varied workloads remain unmeasured. No broad music-quality claim is made from the synthetic tone.

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
| Experimental `cctplaymt` | 8,739 bytes | `$AB6512` | Program, 6809 object code, re-entrant, read-only |
| Counter `cctcount` | 91 bytes | `$45EA1F` | Program, 6809 object code, re-entrant, read-only |

ToolShed reported each CRC as Good. The generated test VGM is 256 bytes, contains a YM2149 clock/variant header, tone writes, two 30-frame note sections made from 735-sample waits, a silence write, and an end command. The generated file contains no imported music.

To recreate only the private stage floppy, after confirming it is not mounted:

```sh
bash scripts/stage-test-disk.sh
```

This stages `cctplay`, `cctplaymt`, `cctcount`, and `synthetic.vgm` on `emulator/images/chiptunes-test.dsk`. It refuses to rewrite that disk while a process has it open. Do not reset or overwrite the project EOU VHD for this test.

## Runtime verification commands

Runtime verification is **PASS for the synthetic concurrent milestone** in the isolated private session. The exact reproduction commands are:

```sh
bash scripts/build.sh
bash scripts/stage-test-disk.sh
bash scripts/run-mame.sh psg
```

At Disk BASIC's `OK` prompt, enter `DOS`. In one EOU Shell window, test the counter alone:

```text
load /d1/cctcount
cctcount &
```

It prints a four-digit value and sleeps for 100 EOU clock ticks between updates. Leave it in the background with `&`; from the available Shell, run the PSG tone test:

```text
load /d1/cctplaymt
cctplaymt -psg 2 /d1/synthetic.vgm
```

Check that the counter continues to change, Shell input still works, and the tone starts/stops without a stuck note. Record guest logs/screenshots and an audible inspection. Then compare the default reference with:

```text
load /d1/cctplay
cctplay -psg 2 /d1/synthetic.vgm
```

The ordinary MAME run script selects `coco3h`, HD6309, 2 MB, MPI slot 2 `ccpsg`, plus the established EOU media. Wait until no MAME process has those media open before launching or staging. `scripts/run-mame.sh` and `scripts/stage-test-disk.sh` enforce their project-image guards.

## Evidence matrix

| Check | Result | Evidence / limitation |
| --- | --- | --- |
| Baseline build | **PASS** | `build/cctplay` matches tracked `cctplay` byte for byte. |
| Experimental module build | **PASS** | LWASM `--6309 --format=os9 --define=EXPERIMENTAL_PSG` completed. |
| Counter module build | **PASS** | LWASM build completed; ToolShed header and CRC are valid. |
| Module headers/CRCs | **PASS** | `os9 ident` reports valid CRCs and re-entrant Program modules for all three. |
| Synthetic VGM generation | **PASS** | 256-byte generated YM2149 tone/silence test. Guest parsing is not demonstrated. |
| Private floppy staging | **PASS** | `bash scripts/stage-test-disk.sh` created the 368,640-byte project-local test floppy and listed `cctplay`, `cctplaymt`, `cctcount`, and `synthetic.vgm`. The script's `lsof` guard found no open handle to this floppy. |
| Counter running on EOU | **PASS** | The counter advances while sleeping 100 ticks between updates and while Shell commands run. |
| Audio and PSG hardware behavior | **PASS** | 422 non-dropped `$FF5E/$FF5F` writes and a 30.35-second non-DC WAV signal. |
| Counter + playback concurrency / Shell responsiveness | **PASS** | Counter values advance on the same screen as the playback banner; post-run `procs -e` succeeds and shows no player process. |
| Timing drift | **PASS with measured drift** | 30.000-second fixture produced 30.35 seconds of active audio (+1.17%); startup half-second events measured 0.5006--0.5219 seconds. |
| CPU utilization | **NOT RUN** | No reliable guest CPU-share profiler was available. |
| Cleanup | **PASS for normal completion** | Player exits, disappears from `procs -e`, and WAV AC activity returns to zero; abort/repeated-load cleanup remains untested. |

## Known limits and next steps

- Synthetic PSG scheduling is proven for one normal-completion run; broader workloads and repeated runs remain to be tested.
- Relative delay loops do not compensate for interrupts, scheduler delay, or disk latency. Measure counter rate and track duration before deciding whether this process-timed path is useful.
- The current POC is PSG-only. GMC and OPL playback continue to use the original interrupt-masked routines in the default build and are excluded from `cctplaymt` dispatch.
- Signal abort, loop transitions, cross-page reads, map cleanup, path cleanup, and device-state restoration need runtime tests, including bad files and repeated tracks.
- If timing fails, keep the decoder/backend interface and replace only the timing/event sink with an EOU-compliant queued driver. Do not add an interrupt handler or kernel patch before the process measurements justify it.
- Rollback this experiment by reverting the prototype commit. The tracked original `cctplay` and baseline build remain intact.
