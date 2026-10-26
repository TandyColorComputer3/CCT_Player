# CCT_Player — NitrOS-9 EOU multitasking port

## Mission (non-negotiable)
Turn Todd Wallace's CoCo ChipTunes Player 1.6 into a NitrOS-9 Level II Ease of Use (EOU) player that plays music **without freezing the operating system**. Playback must coexist with Shell/GShell, keyboard and mouse input, disk I/O, interrupts, and unrelated processes. Do not merely remove interrupt masks and assume it works. Preserve VGM/CCT/M3U compatibility and existing sound-chip support as practical; document regressions.

## Original baseline / provenance
- Original author: Todd Wallace / dragonbytes, repository https://github.com/dragonbytes/CCT_Player.
- Our fork: https://github.com/TandyColorComputer3/CCT_Player.
- Original source: `cct_os9.asm`; binary baseline: `cctplay`; original include files: `os9.d`, `rbf.d`, `scf.d`.
- The original repository has no explicit license file. Retain attribution, do not invent a license, and do not import copyrighted music or ROMs into Git.
- Keep `main` as the unchanged upstream baseline. Develop on `feature/multitasking-eou`; small, reviewable commits. Retain `upstream` Git remote.

## Target platform & toolchain
- NitrOS-9 EOU **Level II**, CoCo 3; primary target HD6309 at 1.78 MHz and 2 MB RAM; later verify Motorola 6809 and 512 KB where practical.
- Assemble natively formatted position-independent OS-9 modules using host `lwasm --6309 --format=os9`. Inspect module header/reentrancy/CRC with ToolShed `os9 ident`. Use EOU-specific docs, not unverified original Microware assumptions.
- The CoCo 3 MMU maps 8 KB blocks into a **maximum 64 KB logical process address space**, despite 2 MB physical RAM. Preserve code/data separation and process-local data in U; use PCR for constants, BSR/LBSR for reentrant calls.
- Prefer system calls, bounded queues, small modules, and F$Sleep/F$Wait/F$Send as appropriate. Driver/IRQ work requires OS-9-compliant system-state entry, privilege and cleanup.
- Reference EOU Technical Reference Manual, current EOU kernel/runtime evidence, GFX2/windowing manuals as applicable, and official LWTOOLS docs.

## Confirmed source blockers: start here
- `PLAY_CHIP_OPL`, `PLAY_CHIP_SN76489`, `PLAY_CHIP_YM2149` contain `ORCC #$50` for *the entirety* of playback. This suppresses OS-9 IRQ/FIRQ scheduling.
- `VGM_WAIT_SAMPLES`, `VGM_SN76489_WAIT_SAMPLES`, `VGM_YM2149_WAIT_SAMPLES` implement 44,100-samples/sec timing as CPU-cycle busy loops (41-cycle approximation). Simply enabling IRQs changes timing and causes jitter.
- `VGM_CMD_START_DATA_LOOP`, `VGM_GET_RAM_BLOCK` and other paths write `$FFA9` directly (logical $2000 bank mapping). A process switch can invalidate this unsynchronized mapping; audit use of F$AllRAM/F$MapBlk/F$ClrBlk/F$DelRAM and process DAT image.
- The wait loops probe keyboard PIA registers `$FF02/$FF00` directly; replace with OS-9-compatible input or signals. Keyboard scanning is not owned by a foreground player.
- Other shorter `ORCC #$50` masks exist for sound-chip detection/stop; strictly bound them, save/restore CC on **all** paths, and check whether any mask is necessary. Do not disable interrupts while sleeping, yielding, parsing, or doing I/O.
- Preserve/restore MPI slot ($FF7F), sound PIA ($FF23), clock state and any modified hardware configuration; avoid stealing OS-9's shared resources.
- Existing `strPlayingFrozen` message describes a limitation, not the desired behavior.

## Architecture guidance (research/measure before committing)
1. Snapshot baseline build, ident, boot, known sample test, and responsiveness. Never claim MAME playback tested without live evidence.
2. Separate file parsing/loop/playlist state from sound-chip event output and from timing. Write a playback scheduler design in docs before replacing the original loop.
3. Convert VGM's 44.1 kHz sample waits into timestamped events; retain fractional timing and 50/60 Hz wait semantics. F$Sleep alone offers tick granularity and cannot reproduce every sub-tick event. Measure audible jitter, missed register writes, deadline overrun and CPU usage. Consider a bounded tick-driven system service (F$VIRQ + properly installed F$IRQ through driver context), paired with a yielding user process/producer queue, **only when justified by measured needs**. Do not hook random IRQ vectors or add privileged calls from user state.
4. Keep IRQ handlers deterministic and short: no disk I/O, blocking OS calls, dynamic allocation, printing, or unbounded VGM parsing inside interrupt context. Restore registers, DP, task map and interrupt state as required.
5. Do not patch the kernel or system boot on first implementation; prototype in a regular player process and introduce a dedicated OS-9 driver only if necessary for stable timing.
6. First playable target: CoCoPSG (YM2149) in MAME MPI slot 2; next GMC (SN76489) in slot 1. Original MMMPI OPL3 is a separate **real-hardware** target (not emulated by our standard MAME configuration).
7. Preserve all existing OS-9 file formats and error paths. Seek, EOF, RAM failure, BREAK, signals, looping, playlist transitions and stop must release mapped blocks, paths and audio hardware.

## Acceptance criteria (must demonstrate, not assert)
- While a track plays, an unrelated process continues updating a visible counter at least once per second; shell remains usable and OS-9 ticks continue. MAME keyboard/mouse input and disk access still work.
- Track timing and audible notes are stable enough against the original, with measured deviation documented; no stuck notes on completion/abort. No long interrupt-off windows.
- Test clean stop and restart; VGM waits/loops, CCT file, M3U playlist, bad file, no compatible hardware, large/zero-length track, several consecutive tracks, and multiple process loads.
- No clobbering MMU mappings, orphaned modules, allocator leaks, unclosed paths, wrong MPI slot, or broken system state after return to Shell/GShell.
- Verify `os9 ident` module CRC/type/data size, 6309 EOU + 2MB MAME smoke test; add 6809/512KB coverage only when code truly supports it.
- Use screenshots, run logs, checksums and human-audible inspection as evidence. Status labels: NOT RUN / PASS / FAIL, never inferred PASS.

## Workflow
- `bash scripts/build.sh` builds the source using LWASM.
- `bash scripts/setup-mame.sh` copies canonical EOU media into **ignored, project-local, writable** images without overwriting existing copies; `--reset` intentionally refreshes them with MAME stopped.
- `bash scripts/stage-test-disk.sh [song.vgm ...]` creates an RBF test disk; do not do this while MAME has the disk mounted.
- `bash scripts/run-mame.sh [base|psg|gmc] [--mcp]` boots `coco3h`, 2 MB, 63EMU helper and EOU VHD, and optionally the existing MCP Lua bridge. RGB color setting is configured once via the MAME UI.
- Never modify canonical files in `/Volumes/SEDONA/Projects/CoCo3_MCP_Server_NOS9/media`; never commit ROMs, VHD/DSK images, song dumps, private paths or generated binaries.
- Document each architecture change with rationale, exact build/test commands, current observed limitations, and rollback. See `docs/DEVELOPMENT.md`.

## Human-oriented assembly comments
For new/modified ASM, explain intent, register inputs/outputs, clobbers, process context (user/system/IRQ), byte layout, timing/critical-section budget, error exit, and all OS-9 calls. Prefer meaningful names and small labeled routines. Do not make source-wide cosmetic rewrites while fixing the scheduler.
