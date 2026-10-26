# Environment and original-player baseline

**Run date:** 2026-10-25
**Branch:** `feature/multitasking-eou`
**Scope:** build/tooling and source audit only. No playback-engine source was changed.

## Repository and provenance

| Check | Result | Evidence |
| --- | --- | --- |
| Development branch | **PASS** | `git branch --show-current` returned `feature/multitasking-eou`; initial HEAD was `2d73d2d`. |
| Remotes | **PASS** | `origin` points to the TandyColorComputer3 fork; `upstream` points to dragonbytes/CCT_Player. Both remain configured. |
| Upstream baseline | **PASS** | `cct_os9.asm`, `os9.d`, `rbf.d`, and `scf.d` have no diff against `origin/main`. `main` was not changed. |
| Original source and binary | **PASS** | Initial checkout was clean. `cctplay` SHA-256: `eabe6b6f3910ebd1af557f64b02c1fb1e1802a3a07a1bf134016b1a4a6792f36`. Source/include hashes are preserved in this turn's command output; no source/include file was modified. |

## Toolchain and module

| Check | Result | Evidence |
| --- | --- | --- |
| LWASM | **PASS** | `lwasm --version` reports LWTOOLS 4.22. |
| ToolShed | **PASS** | Installed ToolShed `os9` executable ran `ident`, `format`, `copy`, `attr`, and `dir`. Its executable is nested under the `build/unix/os9/` directory. |
| Original rebuild | **PASS** | `bash scripts/build.sh` assembled with `--6309 --format=os9`; `cmp -s cctplay build/cctplay` returned success. Both files have SHA-256 `eabe6b6f3910ebd1af557f64b02c1fb1e1802a3a07a1bf134016b1a4a6792f36`. |
| ToolShed module identity | **PASS** | `os9 ident build/cctplay`: module size `$2234` (8,756 bytes), CRC `$7A98E7` (Good), header parity `$3F`, execution offset `$0ED1` (3,793), data size `$0798` (1,944), edition `$0D`, Program module / 6809 object code / re-entrant / read-only. |
| Staged file attributes | **PASS** | `stage-test-disk.sh` ran ToolShed `attr -e -pe` on the copied module successfully. The module header independently identifies it as an executable Program module. |

The original tracked binary and rebuild are identical, so this confirms the build does not silently change baseline behavior. It does not prove playback behavior.

## MAME and MCP setup

| Check | Result | Evidence |
| --- | --- | --- |
| Installed MAME | **PASS** | `/Applications/Emulators/Ample.app/Contents/MacOS/mame64 -version` reports `0.289 (ample-289-u2)`. |
| Target driver | **PASS** | `-listdevices coco3h` identifies Color Computer 3 NTSC with HD6309. |
| CoCoPSG/GMC/MPI option names | **PASS (listed)** | `/Applications/Emulators/Ample.app/Contents/MacOS/mame64 coco3h -ext multi -listslots` lists `ext:multi:slot1`, `slot2`, and `slot4`. Both slot 1 and slot 2 list `ccpsg` and `gmc`; slot 4 lists `fdc`. This verifies the launcher's `-ext multi -ext:multi:slot4 fdc`, PSG `-ext:multi:slot2 ccpsg`, and GMC `-ext:multi:slot1 gmc` selections against this MAME build. It corrected the old `games_master` spelling to `gmc`. |
| General driver validation | **PASS** | `mame64 -validate coco3h` returned exit code 0. This does not instantiate the selected MPI slot configuration. |
| Duplicate-launch protection | **PASS** | `bash scripts/run-mame.sh psg` detected that the active process already had `63EMU.DSK` open and exited 1 before launching another MAME instance. |
| Configured PSG/GMC boot | **NOT RUN** | An unmanaged MAME process already held the project-local boot DSK and working VHD open; the MCP connector reported `running=false, bridge=false`. I did not start a second MAME process or reset either image. Desktop-control permission was denied, so I could not inspect or operate the active window. |
| Headless fallback | **FAIL** | A no-disk `coco3h -video none -seconds_to_run 1` launch exited 134 while initializing SDL/OpenGL (`Setting SDL_VIDEO_GL_DRIVER`). This is not a normal GUI launch and does not establish that the project launcher fails. |
| Audio, EOU boot, Shell responsiveness | **NOT RUN** | No guest screenshot, audible sample, or interactive test log was available. The open image handles establish only that MAME opened the local media, not that EOU booted or a track played. |
| Existing MCP integration | **PARTIAL** | CoCo3 MCP tools are available and the bridge script exists. `coco_status` reported no MCP-managed process or bridge. Starting its configured instance was avoided because its documented default media points at the MCP project's canonical VHD rather than this project's working copy. |

MAME's `-validate` and `-showconfig` front-end verbs do not prove a normal machine launch with dynamically populated slot options. The installed device list verifies the card identifiers; actual PSG/GMC instantiation still needs an interactive run after the active MAME session is released.

## Private emulator images and staging disk

`bash scripts/setup-mame.sh` completed without replacing the existing project-local copies. Their checksums match the canonical inputs:

| Image | SHA-256 | Result |
| --- | --- | --- |
| `63EMU.DSK` | `9a51adb8656b9f003c7f822352c291487362f1b4c43aac1a16672d5d2bcb4c40` | **PASS**, local copy matches source |
| `eou-working.vhd` | `dda00e4f54b349ebcce932b8546021b42cca5ba14cb6213598f828f20e11e4b8` | **PASS**, local copy matches source |

`bash scripts/stage-test-disk.sh` completed successfully with no songs supplied. It created the ignored, project-local 40-track, double-sided RBF floppy (368,640 bytes) and copied/marked `cctplay`. No VGM/CCT/M3U sample is present in the tracked repository, so no music or audio playback was tested. At inspection time, MAME had not opened `chiptunes-test.dsk`.

## Source audit summary

- All three chip playback entries mask IRQ/FIRQ for the complete playback loop. The normal cleanup restores `$FF7F` MPI selection and `$FF23` PIA state, but the playback path does not restore the pre-play value of `$FFD9`.
- The VGM waits use per-sample CPU-cycle loops and scan `$FF02/$FF00` for BREAK/ESC. Removing the long interrupt masks alone would alter timing and would leave direct keyboard polling in the foreground.
- VGM/CCT loaders allocate RAM with OS-9 calls, but playback directly changes the `$2000` MMU bank through `$FFA9`.
- The signal handler sets `abortFlag`; cancellation is not used as the sub-tick event scheduler. The player currently has no `F$Sleep`, `F$Wait`, `F$Send`, `F$VIRQ`, or `F$IRQ` call in its playback path.
- OPL output uses MMMPI registers and is a real-hardware target. CoCoPSG and GMC have MAME slot devices, with identifiers `ccpsg` and `gmc`.

Detailed architecture recommendation: [MULTITASKING-DESIGN.md](MULTITASKING-DESIGN.md).

## Reproduction commands

```sh
lwasm --version
bash scripts/build.sh
cmp -s cctplay build/cctplay
bash scripts/setup-mame.sh
bash scripts/stage-test-disk.sh
/Applications/Emulators/Ample.app/Contents/MacOS/mame64 -version
/Applications/Emulators/Ample.app/Contents/MacOS/mame64 -listdevices coco3h
/Applications/Emulators/Ample.app/Contents/MacOS/mame64 -listslots coco3h
/Applications/Emulators/Ample.app/Contents/MacOS/mame64 coco3h -ext multi -listslots
```

To complete the pending runtime baseline after MAME is no longer using the working images, stage a legally sourced or synthetic PSG VGM and launch the configured machine with these commands:

```sh
bash scripts/stage-test-disk.sh /absolute/path/to/sample.vgm
bash scripts/run-mame.sh psg
```

At DECB's `OK` prompt enter `DOS`. In the EOU Shell run:

```text
load /d1/cctplay
cctplay -psg 2 /d1/sample.vgm
```

For GMC, close MAME, then use `bash scripts/run-mame.sh gmc`; at the EOU Shell run:

```text
load /d1/cctplay
cctplay -gmc 1 /d1/sample.vgm
```

These commands cover a single-track playback check only. At the original Phase 1 snapshot there was no counter test utility, so the concurrent-process acceptance test remained **NOT RUN**. The later prototype follow-up below adds and stages a helper utility, but its guest execution remains **NOT RUN**. Capture a screenshot, audible inspection, Shell counter rate, and timing/CPU evidence before claiming that milestone.

## Scaffolding changes and rollback

- `scripts/build.sh` and `scripts/stage-test-disk.sh` now default to the actual ToolShed executable and reject a configured directory/non-executable file instead of trying to execute it.
- `scripts/run-mame.sh gmc` now selects MAME's installed slot option `gmc`. On macOS it also refuses to open images already held by another process.
- `scripts/stage-test-disk.sh` now refuses to recreate its DSK while another process has it open.
- `docs/DEVELOPMENT.md` now names the executable file rather than its containing directory.

If an environment uses another ToolShed installation, set `TOOLSHED_OS9` to that executable. To roll back these scaffolding-only changes, revert this documentation/script commit; the original assembly and tracked `cctplay` are unchanged.

## Experimental CoCoPSG prototype follow-up

**Run date:** 2026-10-25
**Branch:** `feature/multitasking-eou`
**Scope:** conditional PSG-only process-timing prototype, counter utility, generated tone file, and build/staging documentation. The default executable remains the original baseline.

| Check | Result | Evidence |
| --- | --- | --- |
| Baseline rebuild | **PASS** | `bash scripts/build.sh` assembled `build/cctplay`; the build script's `cmp -s cctplay build/cctplay` check passed. Tracked `cctplay` remains untouched. |
| Experimental player build | **PASS** | LWASM `--6309 --format=os9 --define=EXPERIMENTAL_PSG` built `build/cctplaymt`. |
| Counter build | **PASS** | `tools/cctcounter.asm` built as `build/cctcounter`. |
| ToolShed module identity | **PASS** | `cctplay`: size `$2234` (8,756 bytes), CRC `$7A98E7` Good, exec `$0ED1`, data `$0798`, edition `$0D`; `cctplaymt`: size `$220A` (8,714 bytes), CRC `$B13E7A` Good, exec `$0D33`, data `$07AB`, edition `$0D`; `cctcount`: size `$5B` (91 bytes), CRC `$4FB5C6` Good, exec `$0016`, data `$0006`, edition `$01`. All identify as Program / 6809 object code / re-entrant / read-only. |
| Synthetic PSG test file | **PASS (generated)** | `build/synthetic-psg.vgm`, 256 bytes, generated from the repository script; guest parsing and audio remain untested. |
| Private test floppy | **PASS** | `bash scripts/stage-test-disk.sh` created the 368,640-byte ignored `emulator/images/chiptunes-test.dsk`; ToolShed listed `cctplay`, `cctplaymt`, `cctcount`, and `synthetic.vgm`. Its open-file guard found no MAME handle to this test floppy. |
| Static PSG control-flow review | **PASS (static only)** | The experimental PSG entry path does not enter the original long `ORCC #$50` playback section; its VGM reader uses process DAT mappings through `F$MapBlk`/`F$ClrBlk`, and signal checks use `abortFlag`. This is source evidence, not guest scheduling/MMU evidence. |
| Counter execution on EOU | **NOT RUN** | The CoCo3 MCP server reports `running=false, bridge=false`. An unmanaged MAME process still has this project's `eou-working.vhd` and `63EMU.DSK` open. No MAME window, VHD, or mounted disk was changed. |
| PSG audio / concurrency / responsiveness | **NOT RUN** | No guest run, audible inspection, screenshot, or counter-during-playback evidence was obtained. |
| Timing, CPU, resource cleanup | **NOT RUN** | No guest event trace, duration measurement, CPU estimate, or repeated-playback cleanup check was available. |

The process prototype uses the existing 44.1 kHz sample countdown for short waits, and coarse `F$Sleep` for waits of at least two NTSC ticks. It does not compensate relative waits for interrupt or scheduler lateness; drift and audio quality are unmeasured. The prototype is not evidence that the OS remains responsive during playback.

To run once the existing unmanaged MAME session releases the project media, see the two-window CoCoPSG commands in [PSG-PROTOTYPE.md](PSG-PROTOTYPE.md). The staging disk is project-local; the canonical EOU images and the working VHD must not be reset or replaced for this test.

## CoCoPSG hardware and loader diagnosis

**Run date:** 2026-10-26
**Environment:** isolated private copies of the EOU boot media; visible MAME 0.289 `coco3h`, HD6309, 2 MB, MPI slot 2 `ccpsg`. Canonical media and the unrelated MAME/MCP processes were not changed.

| Check | Result | Evidence |
| --- | --- | --- |
| Standalone `psgprobe` | **PASS** | The re-entrant OS-9 module programmed `$FF5E/$FF5F`, slept for 120 ticks, silenced the chip, and restored saved YM, PSG-control, PIA, and MPI state. MCP captured 22 writes over a 1.977-second active interval. The user reported hearing the tone. |
| `psgprobe` module identity | **PASS** | Current ToolShed `os9 ident`: size `$00C2`, CRC `$E049D3` Good, exec `$0016`, data `$0007`, Program / 6809 object / re-entrant / read-only. The final byte added after the audible run only forces a zero `F$Exit` status; the exercised hardware path is unchanged. |
| MAME WAV capture | **PASS** | `emulator/images/demo/psgprobe-capture.wav` is RIFF PCM, 16-bit, four channels, 48 kHz. During the tone, channel 1 has AC RMS 8153.68, AC peak 9220, and approximately 250 zero-crossing cycles/second; comparison windows before and after have no comparable AC signal. This is a real square-wave tone, not silence or DC. |
| Synthetic long VGM guest file | **PASS** | Host and guest size are 2,559 bytes. SHA-256 is `b87c4bd79d2b36fa1654e88ae3454cd9de85de99ab72f0aef43ccf8c1d7e3840`; VGM version is 1.51, data begins at `$80`, total samples are 1,323,000 (30 seconds), AY clock is 2,000,000 Hz, variant is YM2149, and the stream ends in `A0 08 00 66`. |
| Loader system calls | **PASS** | Conditional `cctplaydbg` trace reached successful `I$Open`, header/data `I$Read`, `SS.Size`, `I$Seek`, `F$AllRAM`, `F$MapBlk`, `F$ClrBlk`, and `I$Close`. The loader was not looping or blocked on file I/O. |
| Loading failure root cause | **CONFIRMED** | `reservedMMUflag` was allocated with `RMB` but never initialized. A stale nonzero byte caused the loader to run the special `$E000` `F$ClrBlk` cleanup even when `F$MapBlk` had returned `$A000`. An in-context MAME capture showed valid player opcodes in the `$E000` page before cleanup and unrelated system bytes afterward; the next subroutine call therefore faulted before any PSG write. |
| Loader correction | **PASS** | The experimental VGM and CCT paths now clear `reservedMMUflag` before each mapping sequence. They also retain the exact `F$MapBlk` base across `I$Read` before calling `F$ClrBlk`. These changes are conditional on `EXPERIMENTAL_PSG`; the baseline rebuild remains byte-identical to tracked `cctplay`. |
| Fixed 30-second player run | **PASS** | `cctplaymt -psg 2 /d1/synthetic-30s.vgm` printed metadata and the 30-second length, emitted repeated expected YM writes, silenced the channel, printed `Playback complete!`, and returned to the Shell prompt. The bounded capture recorded its first 256 register writes and then overflowed while observation continued; overflow limits event-count analysis but does not invalidate the captured writes. |
| Fixed-player human audio check | **NOT CONFIRMED** | The standalone probe was heard. The fixed long-player run has register-write and completion evidence, but no separate user confirmation of hearing that run is recorded. |
| Multitasking acceptance test | **NOT RUN in this diagnostic** | This run isolated sound hardware and the loader fault. It did not run `cctcount` concurrently, so it is not evidence that the full multitasking milestone passes. |

The fixed experimental module identifies as size `$221A` (8,730 bytes), CRC `$ABC711` Good, exec `$0D33`, data `$07AB`, Program / 6809 object / re-entrant / read-only. The original `cctplay` still rebuilds with SHA-256 `eabe6b6f3910ebd1af557f64b02c1fb1e1802a3a07a1bf134016b1a4a6792f36` and CRC `$7A98E7`.

CoreAudio enumeration differs by execution context. Sandboxed `system_profiler SPAudioDataType` returned an empty device list, while the visible logged-in MAME process, launched with `-sound coreaudio`, produced the user-audible probe and the non-silent WAV. Installed MAME reports `-sound` backends `coreaudio`, `sdl`, `portaudio`, and `none`, with `-audio_latency`, SDL `-audiodriver`, 48 kHz sampling, and `-wavwrite`. Therefore the sandbox result is not evidence that the Mac lacks an output device.
