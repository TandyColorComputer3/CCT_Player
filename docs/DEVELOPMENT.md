# CCT_Player EOU development & test workflow

## Clone and checkout (macOS / SEDONA)
If the named project folder already exists but is EMPTY, clone into it:
```bash
mkdir -p /Volumes/SEDONA/Projects/chiptunes-player-nitros9
cd /Volumes/SEDONA/Projects/chiptunes-player-nitros9
git clone --branch feature/multitasking-eou https://github.com/TandyColorComputer3/CCT_Player.git .
git remote add upstream https://github.com/dragonbytes/CCT_Player.git
git remote -v
```
If that directory already contains a Git checkout, do not clone again: use `git fetch origin` and `git switch --track origin/feature/multitasking-eou` (or `git switch feature/multitasking-eou` if it already exists).

## Dependencies
- macOS MAME: `/Applications/Emulators/Ample.app/Contents/MacOS/mame64` (usual local installation)
- CoCo 3/HD6309 MAME driver: `coco3h`, `-ramsize 2M`
- EOU canonical test media: `/Volumes/SEDONA/Projects/CoCo3_MCP_Server_NOS9/media/63EMU.DSK` and `63SDC-MCP-DEV.VHD`
- LWTOOLS `lwasm` (use `lwasm --version`)
- ToolShed `os9` (default executable: `/Users/magneto-optimus/Documents/Coding/toolshed-2.2/build/unix/os9/os9`)
- Optional MCP Lua bridge: `/Volumes/SEDONA/Projects/CoCo3_MCP_Server_NOS9/MCP/scripts/bridge.lua`, with the MCP server running separately

Any binary path can be overridden with environment variables: `LWASM_BIN`, `TOOLSHED_OS9`, `MAME_BIN`, `MAME_ROMPATH`, `MCP_MEDIA_DIR`, `MCP_BRIDGE`.

## Prepare and run
```bash
bash scripts/setup-mame.sh
bash scripts/build.sh
bash scripts/stage-test-disk.sh
bash scripts/run-mame.sh psg
```
The build produces the byte-identical baseline `build/cctplay`, experimental PSG player `build/cctplaymt`, end-marker diagnostic `build/ccttiming`, verbose loader diagnostic `build/cctplaydbg`, counter `build/cctcounter`, stop helper `build/cctstop`, and hardware and clock probes. The player now requires the optional `clockpack` (CCTClock driver and ctclock descriptor in one allocation). `build/cctplaymt-relative` reproduces the exact `6eb11eb` relative-delay binary, and `cctcycle` makes that engine available under another module name. See [CLOCK-SCHEDULER-DESIGN.md](CLOCK-SCHEDULER-DESIGN.md) for measurements and the remaining floppy timing limitation. The private test floppy contains those modules and `synthetic.vgm`; extra music paths passed to `stage-test-disk.sh` are copied only to the ignored private disk. Set `CCT_TEST_DISK` to an absolute path inside `emulator/images/` to stage a separate unmounted disk.

At DECB's `OK` prompt enter `DOS`. After the 6309 EOU Shell loads, select the private test disk for command lookup:
```text
chx /d1
load clockpack
```
Start a supported PSG file with Shell's normal background operator:
```text
cctplaymt -psg 2 /d1/synthetic.vgm &
```
Shell prints the background PID as (for example) `&003`. To request the player's normal signal-driven cleanup rather than killing it fatally, run `cctstop 3`. Twenty on-demand floppy-loaded stop cycles passed under the conditions in [STABILITY-ANALYSIS.md](STABILITY-ANALYSIS.md); the earlier reported reboots remain unresolved. Controlled playlist-transition stops pass; see [PLAYLIST-STOP-TIMING.md](PLAYLIST-STOP-TIMING.md). The production `cctplaymt` is intentionally quiet after launch so its output cannot overwrite the returned Shell prompt; use `cctplaydbg` in the foreground for loader diagnostics.

The original reference remains available as `load /d1/cctplay` followed by `cctplay -psg 2 /d1/synthetic.vgm`. The original remains foreground/frozen behavior and is not the multitasking command.

Other modes:
```bash
bash scripts/run-mame.sh base           # no optional sound cartridge
bash scripts/run-mame.sh gmc            # Game Master Cartridge in MPI slot 1
bash scripts/run-mame.sh psg --mcp      # CoCoPSG in MPI slot 2 + existing MCP Lua bridge
```
Set RGB mode once via the MAME configuration screen (usual `screen_config` port value 1) and save; this script does not rewrite the user's MAME configuration. Close MAME before reformatting/re-staging test disks or resetting working VHD media.

On macOS, `run-mame.sh` and `stage-test-disk.sh` use `lsof` to stop when one of their project-local images is already open. The ToolShed override must name the executable file, not its containing directory.

## Project layout
- `cct_os9.asm`: Todd Wallace's version 1.6 source with conditional experimental PSG code; the default build preserves the original binary. `os9.d`, `rbf.d`, `scf.d` are the original includes.
- `cctplay`: original prebuilt binary, useful for baseline verification
- `build/cctplay`: byte-identical baseline rebuild; `build/cctplay.lst`: assembler listing
- `build/cctplaymt`: experimental CoCoPSG tick-deadline module; requires `clockpack`
- `tools/cctcounter.asm`: independent counter process (requests 61 ticks to sleep 60 ticks, about one second at 60 Hz NTSC)
- `tools/tpsprobe.asm`: prints the read-only `F$TPS` result and marks errors with `TPS!`
- `tools/sleepprobe.asm`, `tools/signal-sleepprobe.asm`: select-port markers for normal and signal-interrupted `F$Sleep` measurements
- `scripts/make-timing-fixtures.py`: generates controlled PSG wait/write streams under `build/timing-fixtures/`
- `tools/cctstop.asm`: sends `S$Intrpt` to a background player PID
- `tools/psgsuper.asm`: forks a player, signals only its returned child PID, and collects its exit status for transition tests
- `tools/timeload.asm`: bounded 60-line counter workload for repeatable timing tests
- `tools/diskload.asm`, `tools/diskbench.asm`: bounded read-only floppy workload and guest supervisors for repeated timing tests
- `tools/cctclock.asm`, `tools/ctclock.asm`: optional atomic tick clock, packed together as `clockpack`; no boot-image changes
- `tools/psg-clock-scheduler.inc`: elapsed tick deadlines and retained sample fractions in ordinary player context
- `tools/clockprobe.asm`: independent before/after tick snapshots for clock-loss measurements
- `idlebench`, `countbench`, `countlong`: five-track supervisors and extended counter workload built from the existing test sources
- `scripts/summarize-psg-repeats.py`: verify PSG sequences and summarize timing errors from MAME observer captures
- `docs/TIMING-WORKLOAD-BASELINE.md`: repeated idle, counter and floppy measurements and scheduler evaluation
- `docs/PLAYLIST-STOP-TIMING.md`: stop-phase evidence, MPI audit, matched timing measurements and unresolved limitations
- `scripts/make-synthetic-psg-vgm.py`: original generated test tone (ignored output under `build/`)
- `emulator/images/63EMU.DSK`: private boot helper copy
- `emulator/images/eou-working.vhd`: private EOU hard drive copy
- `emulator/images/chiptunes-test.dsk`: private RBF stage disk in MAME floppy 2
- `AGENTS.md`: agent rules for the multitasking port

## Test criteria to record
1. Baseline: `os9 ident`, filename, version, sound device, source image SHA-256.
2. Playback: track format, duration, intro/loop behavior, stop/BREAK, no stuck note.
3. Scheduling: second Shell counter increments during play; window/menu/mouse still responds; file I/O works.
4. Resources: no permanent IRQ mask; MMU mapping survives task switching; paths/files/RAM/hardware restored at exit.
5. CPU: MAME HD6309 2MB primary, 6809 and 512KB conditional follow-up.

MAME natural-keyboard automation posts a complete string much faster than a person types. During private floppy I/O, the guest can miss injected characters even though it accepts character-paced input. Treat a mangled automated command as an automation limitation and retain the screenshot; do not attribute Shell `Error #216` to the player unless the full command is visible and intact.

**Do not confuse an assembly that succeeds or an emulator that boots with a proven multitasking player.**
