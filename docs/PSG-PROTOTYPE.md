# Experimental CoCoPSG process prototype

**Status:** source/build prototype only. Runtime playback, counter scheduling, audio, and Shell responsiveness are **NOT RUN**.

## What changed

The reference program remains the normal `cctplay` build. `scripts/build.sh` assembles the shared source twice: without defines for the original baseline, then with `EXPERIMENTAL_PSG` for `cctplaymt`. The script checks that the baseline rebuild is byte-identical to the tracked binary. The experiment dispatches only YM2149/AY CCT tracks to the PSG backend and rejects other chip types; the original OPL and GMC paths remain available only through the default build.

The experimental PSG playback path has three responsibilities:

1. `VGM_YM2149_NEXT_COMMAND`, `VGM_YM2149_CMD_CHIP`, `VGM_YM2149_CMD_WAIT_MANUAL`, and the frame/short-wait labels fetch and decode the supported VGM command stream.
2. `VGM_PSG_COARSE_WAIT` handles long waits using OS-9 `F$Sleep`, then `VGM_YM2149_WAIT_FINE_LOOP` burns the remaining VGM sample count. The decoder retains the VGM 44.1 kHz sample unit and the existing 735/882 sample frame waits.
3. `VGM_PSG_WRITE_REG` performs the bounded PSG register-select/data-port sequence.

The player no longer holds IRQ/FIRQ masked for the experimental playback loop. OS-9 clock interrupts can preempt the user process. Long waits of two or more 60 Hz ticks use `F$Sleep`; waits under that threshold use the CPU-cycle loop. The fine loop enters its coarse-wait conversion once per wait, not once per sample.

## MMU and resource handling

The experimental stream reader no longer changes `$FFA9`. It maps one allocated physical song block into an unallocated process DAT slot with `F$MapBlk`, uses its returned logical address, and removes it with `F$ClrBlk` before mapping the next page. A one-block guard allocation is mapped first; because EOU `F$MapBlk` maps from the top down, the stream page is placed below that guard. The guard and stream state live in the process data area. See the [EOU Technical Reference Manual, F$MapBlk](https://www.lcurtisboyle.com/nitros9/EOUDOCS/NitrOS-9_EOU_Level_2_Technical_Reference_Manual.pdf).

The process continues to own its file paths, allocated song blocks, and signal intercept. The signal handler sets the existing `abortFlag`; experimental waits check it without scanning `$FF02/$FF00`. The player selects the requested PSG slot before saving its control register. The existing startup snapshot of MPI selection and `$FF23` PIA state is restored during cleanup; PSG output is silenced, mappings are cleared, and the guard block is released before song RAM is returned. These cleanup paths have only passed static inspection and assembly so far. They have not been exercised on EOU.

MPI selection, `$FF23`, and the PSG are global hardware resources. This prototype has no OS-9 device lock or IPC ownership protocol. The first controlled concurrency run should use only the counter as the second process; simultaneous use by another audio or MPI program remains untested and unsupported by this prototype.

## Timing and expected load

The original delay loop approximates 40.58 CPU cycles per VGM sample at the target fast CPU mode. The prototype keeps a per-sample loop for sub-tick waits, with interrupts enabled; interrupt handling and competing processes therefore add lateness. It does not maintain absolute deadlines or compensate later events for earlier overrun. Repeated waits can accumulate duration drift.

`F$Sleep` avoids spinning throughout long rests, but it is tick-granular and the time to resume the process depends on OS-9 scheduling. It is used only for coarse waits, never as an individual-event timer. The short-wait path still consumes player CPU between scheduler interrupts. CPU share, register-write jitter, missed events, and total duration deviation have not been measured. No audible-quality claim is made.

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
| Experimental `cctplaymt` | 8,714 bytes | `$B13E7A` | Program, 6809 object code, re-entrant, read-only |
| Counter `cctcount` | 91 bytes | `$4FB5C6` | Program, 6809 object code, re-entrant, read-only |

ToolShed reported each CRC as Good. The generated test VGM is 256 bytes, contains a YM2149 clock/variant header, tone writes, two 30-frame note sections made from 735-sample waits, a silence write, and an end command. The generated file contains no imported music.

To recreate only the private stage floppy, after confirming it is not mounted:

```sh
bash scripts/stage-test-disk.sh
```

This stages `cctplay`, `cctplaymt`, `cctcount`, and `synthetic.vgm` on `emulator/images/chiptunes-test.dsk`. It refuses to rewrite that disk while a process has it open. Do not reset or overwrite the project EOU VHD for this test.

## Runtime verification commands

Runtime verification is currently **NOT RUN**. The CoCo3 MCP server reports no managed MAME process/bridge, and an unmanaged MAME process has the project EOU VHD and `63EMU.DSK` open. Do not start another emulator against those media or disturb that session. Once it is safe to launch the project test setup, use:

```sh
bash scripts/build.sh
bash scripts/stage-test-disk.sh
bash scripts/run-mame.sh psg
```

At Disk BASIC's `OK` prompt, enter `DOS`. In one EOU Shell window, test the counter alone:

```text
load /d1/cctcount
cctcount
```

It prints a four-digit value and sleeps for 60 clock ticks between updates. In a second Shell window, run the PSG tone test:

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
| Counter running on EOU | **NOT RUN** | MCP bridge is not running; active unmanaged MAME session is not to be changed. |
| Audio and PSG hardware behavior | **NOT RUN** | No guest execution or audible evidence. |
| Counter + playback concurrency / Shell responsiveness | **NOT RUN** | Acceptance criteria are not demonstrated. |
| Jitter, drift, CPU use, resource cleanup | **NOT RUN** | No timing trace or guest resource inspection. |

## Known limits and next steps

- Runtime scheduling is not proven. A successful assembly does not establish OS responsiveness.
- Relative delay loops do not compensate for interrupts, scheduler delay, or disk latency. Measure counter rate and track duration before deciding whether this process-timed path is useful.
- The current POC is PSG-only. GMC and OPL playback continue to use the original interrupt-masked routines in the default build and are excluded from `cctplaymt` dispatch.
- Signal abort, loop transitions, cross-page reads, map cleanup, path cleanup, and device-state restoration need runtime tests, including bad files and repeated tracks.
- If timing fails, keep the decoder/backend interface and replace only the timing/event sink with an EOU-compliant queued driver. Do not add an interrupt handler or kernel patch before the process measurements justify it.
- Rollback this experiment by reverting the prototype commit. The tracked original `cctplay` and baseline build remain intact.
