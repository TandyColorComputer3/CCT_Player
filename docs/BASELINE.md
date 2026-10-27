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

## Concurrent CoCoPSG milestone

**Run date:** 2026-10-26
**Environment:** the same visible, isolated MAME 0.289 `coco3h` session, HD6309 native mode, 2 MB, MPI slot 2 `ccpsg`, private EOU VHD/boot floppy, and private generated test floppy. No canonical image or unrelated emulator process was changed.

An earlier concurrent-run note incorrectly described the EOU clock as 100 Hz and used 441 VGM samples per coarse tick. The EOU manual specifies 60 Hz for NTSC and 50 Hz for PAL, so the current player uses 735 and 882 VGM samples per tick, respectively. `F$Sleep`'s EOU queue semantics require requesting one more tick than the intended sleep. The counter in the historical run slept 100 ticks (about 1.67 seconds); the current helper requests 61 ticks to sleep 60 ticks (about one NTSC second). The measured timing follow-up, including the remaining drift and exact limitations, is in [TIMING-ANALYSIS.md](TIMING-ANALYSIS.md).

| Check | Result | Evidence |
| --- | --- | --- |
| Counter alone | **PASS (historical 100-tick helper)** | `/d1/cctcount &` printed increasing four-digit values while the Shell accepted commands. The helper in that run slept 100 ticks, about 1.67 seconds at the tested 60 Hz NTSC rate. Current source requests 61 ticks to sleep 60. |
| Counter during playback | **PASS** | `concurrent-final-mid.png` visibly contains the player banner and counter values `0007` through `0016` during active playback. Counter output continues after the player banner and through completion. SHA-256: `5624f315f311bb1fa2a23fadedb8d789c726c5bda9a8575a0cf63a1235d80a34`. |
| PSG writes during concurrency | **PASS** | The bounded MAME tap captured 422 writes to `$FF5E/$FF5F`, `invalid=false`, `dropped=0`. The first eight writes at 147.473619--147.473966 s select/write YM registers 7=`$3E`, 8=`$0F`, 0=`$C8`, and 1=`$00`. The next pitch pair begins at 147.995474 s; the next one-second boundary is 148.496119 s. |
| WAV audio during concurrency | **PASS** | `concurrent-final.wav` is 16-bit, four-channel, 48 kHz PCM. Mean-removed 10 ms window analysis finds one continuous non-DC active run from 147.47 through 177.82 seconds. SHA-256: `2e687a637f4983bd472f238a63c31e80df2047e4196c03e2d586810afc00d478`. |
| Duration | **PASS with measured drift (historical run)** | That earlier concurrent build's audio window measured 30.35 s (+1.17%). The later event-level timing capture uses MAME emulated register timestamps and measures the 30-second fixture at 29.126 s (−2.91%); see [TIMING-ANALYSIS.md](TIMING-ANALYSIS.md). These results are from different builds and measurement methods. |
| Shell responsiveness and exit | **PASS** | After natural completion, `procs -e` ran successfully. `concurrent-final-processes.png` shows `cctcount` plus Shell processes and no `cctplaymt`; counter values `0028` through `0038` continue below the process table. SHA-256: `c1aa07caf3a0ad5c9d6638bbe9933ef5725b66f87229842d7e2b130aeb4d42ea`. |
| Stuck-note cleanup | **PASS** | The WAV returns to zero AC activity after 177.82 s and remains there for the rest of the capture. The write count is the 420 address/data writes encoded by the fixture plus one final two-write cleanup operation. |
| Experimental module identity | **PASS** | Final `cctplaymt`: 8,739 bytes, CRC `$AB6512` Good, exec `$0D33`, data `$07AB`; Program / 6809 object / re-entrant / read-only. `cctcount`: 91 bytes, CRC `$45EA1F` Good. |
| Original executable | **PASS (unchanged)** | `cmp -s cctplay build/cctplay` succeeds; both SHA-256 values remain `eabe6b6f3910ebd1af557f64b02c1fb1e1802a3a07a1bf134016b1a4a6792f36`, and CRC remains `$7A98E7`. |
| CPU utilization | **NOT RUN** | Scheduling and duration were observed, but no trustworthy guest CPU-share profiler was available. |
| Real third-party CoCoPSG VGM | **NOT RUN** | No existing legally staged non-synthetic PSG track is present in the repository/private disk. No music was downloaded or added. |

The evidence files live under the ignored `emulator/images/demo/` test area and are intentionally not Git content. The final visible private MAME session was restarted after WAV finalization; its media remain private copies.

## Background real-music and playlist milestone

**Run date:** 2026-10-26--27
**Environment:** repeated cold boots of the isolated visible MAME 0.289 `coco3h` instance, HD6309 native mode, 2 MB, private EOU media, MPI slot 2 `ccpsg`, and `-wavwrite`. No canonical image or unrelated MAME process was changed.

The approximate WAV-duration estimates in this historical section are superseded for timing by [TIMING-ANALYSIS.md](TIMING-ANALYSIS.md), which measures register events directly against MAME's emulated clock.

The music used for runtime testing came from the original author's publicly distributed ChipTunes archive and was kept outside Git. `ARKNOID1/TRACK01.CCT` (195,372 samples, 4.4302 seconds) and `FLICKY/TRACK01.CCT` (885,968 samples, 20.0900 seconds) were copied only to the ignored test disk. A private standards-compliant VGM 1.51 wrapper around the Arkanoid YM2149 command stream tested the VGM loader without importing music into the repository. The private M3U contained those two CCT paths in order.

| Check | Result | Evidence / limitation |
| --- | --- | --- |
| Exact background launch | **PASS** | `cctplaymt -psg 2 /d1/arkanoid-real.vgm &` returned `&003` and the Shell prompt immediately. An intact concurrent `echo CC-CLEAR-TEST` completed while the player was active. |
| Real VGM decoding and audio | **PASS with timing limitation** | The cold-boot run produced 534 non-dropped writes to `$FF5E/$FF5F`, exited naturally, and disappeared from `procs`. `real-vgm-background.wav` is 48 kHz, four-channel PCM; after DC rejection its PSG channel contains a non-silent varying signal during the track. The old approximate six-second WAV window is not a precise playback duration; the later direct trace measures 4.247630 seconds from first event to mute for 4.430204 seconds expected (−3.980%). |
| Original CCT files | **PASS with timing limitation** | Both private original CCT files decoded and wrote their real YM2149 register streams. The Arkanoid track generated 534 port writes; FLICKY generated 1,642. No format conversion was needed for the CCT runs. |
| Two-entry M3U | **PASS** | On the final exact build, `cctplaymt -psg 2 /d1/real-two.m3u &` generated 2,176 non-dropped writes (534 + 1,642), advanced to the second file, exited naturally, and left no `cctplaymt` entry in `procs`. Each loader close now invalidates its stored OS-9 path, and the already-read playlist path is not closed again during final cleanup. |
| Background terminal output | **PASS for player output** | Production `cctplaymt` suppresses banners, metadata, filenames, and completion text after the Shell prompt returns. `cctplaydbg` retains them for foreground diagnosis. Quiet-return paths explicitly return carry clear, matching a successful `I$Write`; preserving a stale carry reproduced a fatal VGM control-flow/MMU failure and was corrected. |
| Shell keyboard behavior | **PASS with automation caveat** | The player no longer scans PIA keyboard registers and did not consume character-paced input. MAME `post_coded` can overrun the guest when a whole command is injected during floppy activity; screenshots show truncated `echo` commands and the resulting Shell `Error #216`. Character-paced `echo SLOW-OK` arrived intact. This is not a player-generated error. |
| Graceful stop | **PASS** | `load cctstop` followed by a background FLICKY run and `cctstop 3` stopped register activity at 768 writes. `procs` showed no player, `echo POST-STOP` succeeded, and the guest remained healthy. `cctstop` uses `F$Send`/`S$Intrpt`; the player follows its normal silence, mapping, RAM, path, MPI, PIA, and PSG-control cleanup. |
| Signal handler safety | **PASS** | The first stop attempt exposed that direct-page state is not safe on signal entry. The experimental handler now stores `abortFlag` through the `F$Icpt` U context. Repeating the stop no longer corrupted the guest. |
| Natural completion and silence | **PASS** | Both VGM and M3U runs exited naturally. The cleanup writes silence before restoring hardware state; post-run `procs` and Shell commands succeeded. Captured PSG activity ends rather than continuing as a stuck note. |
| Final module identity | **PASS** | `cctplaymt`: 8,767 bytes, CRC `$9BDED9` Good, exec `$0D33`, data `$07AB`, Program / 6809 object / re-entrant / read-only. `cctstop`: 143 bytes, CRC `$077B9E` Good, re-entrant / read-only. |
| Original executable | **PASS (unchanged)** | `build/cctplay` and tracked `cctplay` remain byte-identical, SHA-256 `eabe6b6f3910ebd1af557f64b02c1fb1e1802a3a07a1bf134016b1a4a6792f36`, CRC `$7A98E7`. |
| Loop-option runtime | **NOT RUN** | Parsing remains in the shared source, but no real loop-bearing PSG file was exercised in this run. |
| GMC under MAME | **NOT RUN in this milestone** | Installed `-listslots` still proves `gmc` is the valid slot-1 device. The multitasking executable remains PSG-only; no GMC audio run was performed here. |
| OPL2/OPL3 | **NOT RUN** | The unchanged baseline retains OPL support; standard MAME does not provide the project MMMPI OPL target, so this remains a later real-hardware test. |

Ignored evidence from these runs includes `emulator/logs/evidence/real-vgm-background.wav` (SHA-256 `5676c1758787bc283ef52440219d9337c8356a2644b27a6984af8778dde5f8b2`) and `emulator/logs/evidence/final-real-playlist.wav` (SHA-256 `4306138e186b9b645e1093ffd0fc4853a08464e3913fd4c49dceaca8a260f5fa`). The final post-path-bookkeeping M3U run separately reproduced the exact 2,176-write count with `invalid=false`, `dropped=0` and no remaining player process.

Module sizes and CRCs in this historical section identify the builds used for those milestones. The current timing build is `cctplaymt` size `$2290` (8,848 bytes), CRC `$D2549B` Good, and the corrected one-second test counter is 91 bytes, CRC `$86E3C1` Good; see [PSG-PROTOTYPE.md](PSG-PROTOTYPE.md).

The remaining blocker to calling real music playback fully correct is timing, not scheduling or file compatibility. Later event-level traces show the synthetic fine-loop case 2.914% early and the real Arkanoid VGM / Flicky CCT 3.980% / 3.675% early, rather than the slow durations inferred from earlier WAV windows. Wait classes and register output are now counted in [TIMING-ANALYSIS.md](TIMING-ANALYSIS.md); decoding CPU time and the coarse sleep phase are not yet separated by direct runtime instrumentation. GMC and player loop-bearing files remain separate pending tests; they were not inferred from the PSG result.
