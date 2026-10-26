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
- ToolShed `os9` (default: `/Users/magneto-optimus/Documents/Coding/toolshed-2.2/build/unix/os9`)
- Optional MCP Lua bridge: `/Volumes/SEDONA/Projects/CoCo3_MCP_Server_NOS9/MCP/scripts/bridge.lua`, with the MCP server running separately

Any binary path can be overridden with environment variables: `LWASM_BIN`, `TOOLSHED_OS9`, `MAME_BIN`, `MAME_ROMPATH`, `MCP_MEDIA_DIR`, `MCP_BRIDGE`.

## Prepare and run
```bash
bash scripts/setup-mame.sh
bash scripts/build.sh
bash scripts/stage-test-disk.sh /absolute/path/to/sample.vgm
bash scripts/run-mame.sh psg
```
At DECB's `OK` prompt enter `DOS`. After the 6309 EOU Shell loads, stage/launch the module from the second floppy (usually `/d1`):
```text
load /d1/cctplay
cctplay -psg 2 /d1/sample.vgm
```
Use the actual staged file name in the final command. The original v1.6 intentionally freezes NitrOS-9 during playback; baseline running is **not** a multitasking success.

Other modes:
```bash
bash scripts/run-mame.sh base           # no optional sound cartridge
bash scripts/run-mame.sh gmc            # Game Master Cartridge in MPI slot 1
bash scripts/run-mame.sh psg --mcp      # CoCoPSG in MPI slot 2 + existing MCP Lua bridge
```
Set RGB mode once via the MAME configuration screen (usual `screen_config` port value 1) and save; this script does not rewrite the user's MAME configuration. Close MAME before reformatting/re-staging test disks or resetting working VHD media.

## Project layout
- `cct_os9.asm`, `os9.d`, `rbf.d`, `scf.d`: original version 1.6 source/include files
- `cctplay`: original prebuilt binary, useful for baseline verification
- `build/cctplay`: local rebuilt module; `build/cctplay.lst`: assembler listing
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

**Do not confuse an assembly that succeeds or an emulator that boots with a proven multitasking player.**
