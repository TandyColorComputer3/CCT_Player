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

These commands cover a single-track playback check only. This checkout has no counter test utility, so the concurrent-process acceptance test remains **NOT RUN**; add and stage a helper process before claiming that milestone. Capture a screenshot, audible inspection, Shell counter rate, and timing/CPU evidence for that run.

## Scaffolding changes and rollback

- `scripts/build.sh` and `scripts/stage-test-disk.sh` now default to the actual ToolShed executable and reject a configured directory/non-executable file instead of trying to execute it.
- `scripts/run-mame.sh gmc` now selects MAME's installed slot option `gmc`. On macOS it also refuses to open images already held by another process.
- `scripts/stage-test-disk.sh` now refuses to recreate its DSK while another process has it open.
- `docs/DEVELOPMENT.md` now names the executable file rather than its containing directory.

If an environment uses another ToolShed installation, set `TOOLSHED_OS9` to that executable. To roll back these scaffolding-only changes, revert this documentation/script commit; the original assembly and tracked `cctplay` are unchanged.
