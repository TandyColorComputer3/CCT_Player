# CoCoPSG timing analysis

**Run date:** 2026-10-26
**Build under test:** `cctplaymt`, 6309 native mode, EOU Level II, 2 MB, NTSC, CoCoPSG in MPI slot 2.
**MAME clock source:** `manager.machine.time` from the existing Lua bridge. Durations below are emulated time, not host wall time.

## Measurement set and observed timing

The host analyzer decodes the stream before playback. The bridge captures writes to `$FF5E/$FF5F` with emulated timestamps; each YM2149 register write is an address/data pair. The player's final mute write, register 7=`$3F`, provides an end marker. All captures used below matched the full VGM/CCT register sequence and included exactly one extra mute pair.

| Track | Expected file duration and loops | Commands and writes | Current scheduler model (NTSC) | MAME elapsed and error |
| --- | --- | --- | --- | --- |
| `synthetic30.vgm` (2,559 bytes) | 1,323,000 samples = **30.000000 s**; no loop point, so `-l1` adds no pass | 1,800 `0x62` waits; 210 YM writes; 422 port writes captured (210 address/data pairs + mute) | 0 coarse sleeps / 0 ticks; 1,323,000 fine-delay samples | First write 84.934197 s; mute at 114.059951 s; **29.125754 s**, −2.914% |
| `arkanoid.vgm` (1,303 bytes) | Header total 195,372 samples = **4.430204 s**; loop offset and loop samples are zero | 232 waits (72 manual, 23 `0x62`, 137 short); 266 YM writes; 534 port writes captured (266 pairs + mute) | 49 coarse sleep calls / 174 modeled ticks; 67,482 fine samples | First write 132.183673 s; mute at 136.431304 s; **4.247630 s** from first event to mute. Including its initial 255-sample wait gives 4.253889 s versus 4.430204 s expected (−3.980%). |
| `ark1.cct` (88,576 bytes) | 195,372 decoded samples = **4.430204 s**; CCT has no VGM loop header | 232 waits; 266 YM writes | Same stream as `arkanoid.vgm` | Played as the first M3U entry. Separate completion duration was not captured. |
| `flicky.cct` (88,576 bytes) | 885,968 decoded samples = **20.089977 s**; CCT has no VGM loop header | 255 waits (177 manual, 78 `0x63`); 820 YM writes; 1,642 port writes captured (820 pairs + mute) | 132 coarse sleep calls / 988 modeled ticks; 159,788 fine samples | First write 166.702192 s; mute at 186.053962 s; **19.351770 s**, −3.675% |

The normal real PSG VGM and the dense real CCT both run early in this build. No dense real-world CoCoPSG VGM was present in the repository or private test disk: the dense VGM case is **NOT RUN**. `Doom_Theme.vgm` is an OPL3 file and is not a valid substitute for this PSG timing test.

The playback source defaults to one extra pass through a VGM loop section (`-l1`). These VGM fixtures have no loop point, so their header sample counts are the exact expected durations without extra passes. The analyzer accepts `--loop-count N` and adds `N × loop_samples` for a valid VGM loop. CCT expected duration is the decoded sum of its wait commands; the CCT files tested here have no loop metadata.

Loop arithmetic was checked separately with a small generated VGM header (20 base samples, 10 loop samples): the analyzer returned 20, 30, and 50 samples for loop counts 0, 1, and 3. This validates the host calculation only; runtime playback of a loop-bearing song is **NOT RUN**.

## What the traces show

- A previous run routed one-tick 735-sample waits into `F$Sleep` as `X=1`. EOU defines `X=1` as yielding the rest of the current time slice, so those waits were dropped: the synthetic run emitted only 2.451 seconds of PSG data in 30 expected seconds. The current code keeps one-tick waits in the fine loop.
- An earlier coarse-wait call also treated `X=1` as a completed N-tick sleep. The corrected call requests `N+1` ticks and accounts for the returned remainder. After those fixes, the synthetic fine-loop-only case moved from 27.565 seconds to 29.126 seconds when two NOPs were added to the interruptible loop.
- The final VGM writes progressively lead the expected sample timeline: final data-write lateness was −176 ms for Arkanoid and −737 ms for Flicky. Maximum positive event lateness stayed below 3.4 ms. The error is a persistent short timing budget, not a captured burst of late writes.
- The synthetic file uses only short, fine-loop waits. Its −2.91% result therefore measures the fine delay plus command/output overhead. Arkanoid and Flicky also use coarse sleeps; their additional early bias is consistent with coarse-wait phase/rate error, but that split is derived from stream wait counts, not from a guest-side sleep counter.
- MAME recorded the full command sequences: `sequence_match=true`, no missing register pairs, and the bridge status at the end of the run was `invalid=false`, `dropped=0`. Median time from YM address write to data write was 5.03 μs. This measures the bus pair only; command-decoding CPU time was not isolated.
- `after-nplus1-finecal.wav` is a 4-channel, 16-bit, 48 kHz PCM MAME capture. FFmpeg reports a −13.2 dB mean and non-silent output; it contains several runs and intervening silence, so it is not a track-isolated loudness or audio-quality comparison. No human listening comparison was performed in this timing run.

## Timing architecture assessment

The current player retains each VGM wait as an integer number of 44,100 Hz samples, as required by the [VGM specification](https://vgmrips.theclassicgamer.net/VGM_Specification). NTSC divides exactly into 735 samples per 60 Hz EOU tick; PAL divides exactly into 882 samples per 50 Hz EOU tick. The [EOU Technical Reference Manual](https://www.lcurtisboyle.com/nitros9/EOUDOCS/NitrOS-9_EOU_Level_2_Technical_Reference_Manual.pdf) documents those tick rates and the `F$Sleep` return/countdown behavior. The coarse conversion leaves the exact sample remainder for the fine loop, so integer conversion does not discard samples. The player uses `F$Sleep` only when at least two whole ticks remain and never masks interrupts in the playback loop.

The current implementation still applies waits relatively: it delays by each event's sample count after decoding the event. It does not maintain a cumulative absolute deadline, so any per-event calibration error can accumulate. A correct absolute-deadline loop would accumulate a 32-bit sample target and compare it to an elapsed-time source; if late, it would emit every register change in order and shorten only later waits, with bounded work between yields.

The EOU `F$Sleep` API reports tick counts and can wake early for a signal. `F$TPS` reports the ticks-per-second rate but not the current sub-tick phase. `F$Time` has one-second granularity. Thus an ordinary user process lacks a verified sub-tick monotonic clock for comparing an absolute sample deadline across preemption. A `tpsprobe` module now builds and is included by the stage-disk script, but it was not executed in this run. A new private MAME launch aborted in macOS `NSApplication` registration before the machine started; Launch Services also returned `kLSNoExecutableErr` for `Ample.app`. The already-running unrelated MAME session was left untouched.

These measurements do **not** prove that ordinary OS-9 process scheduling cannot meet 1% timing. They do show that the current calibration misses that target by 2.9–4.0% on the available PSG tracks. The next experiment should first run `tpsprobe`, then adjust only the fine/coarse timing calibration and rerun the same trace. No driver or kernel change is justified by these measurements alone. A dense real VGM, isolated CPU-utilization measurement, and post-adjustment audio test remain outstanding.

## Scheduler and audio regressions

The private MAME run kept `cctcount &` active during the VGM/CCT playback tests. That V2 disk contained the historical 100-tick counter (about 1.67 seconds per update); screenshots show it advancing and the Shell prompt returning after each background launch. Current counter source requests 61 ticks to sleep 60 ticks (about one NTSC second), but that updated helper did not get a live MAME run. The two-entry `/d1/real-two.m3u` run emitted 2,176 YM port writes (Ark1 and Flicky stream writes plus two final mute pairs) and completed naturally. A screen capture of the active Arkanoid VGM run is [v2-ark-mid.png](../emulator/images/timing-run/snapshots/v2-ark-mid.png). This confirms scheduling and file/playlist progress for the measured build; guest CPU percentage was not measured.

The current-run `cctstop` retest is **NOT RUN**: the stop command was issued only after the 30-second player had naturally finished, so it returned `E$BPrcID`. Earlier milestone testing had demonstrated graceful stop on a CCT track, but this timing run does not count as a stop regression pass.

## Reproduction commands

Build and validate the modules and analyzer:

```sh
bash -n scripts/*.sh
bash scripts/build.sh
python3 scripts/analyze-psg-timing.py emulator/images/timing-run/media/v3-stage/synthetic30.vgm --capture emulator/images/timing-run/logs/v2-synthetic30.json
python3 scripts/analyze-psg-timing.py emulator/images/timing-run/media/v3-stage/arkanoid.vgm --capture emulator/images/timing-run/logs/v2-arkanoid.json
python3 scripts/analyze-psg-timing.py emulator/images/timing-run/media/v3-stage/flicky.cct --capture emulator/images/timing-run/logs/v2-flicky.cct.json
```

The exact isolated MAME launch used for the follow-up is below. It uses private copies under `emulator/images/timing-run/`; do not replace them while MAME has them open. This command could not start MAME from the Codex process on this run, so live retesting after the timing analysis is **NOT RUN**.

```sh
/Applications/Emulators/Ample.app/Contents/MacOS/mame64 coco3h -ramsize 2M -window -skip_gameinfo \
  -flop1 "$PWD/emulator/images/timing-run/media/63EMU.DSK" \
  -hard1 "$PWD/emulator/images/timing-run/media/eou-working.vhd" \
  -flop2 "$PWD/emulator/images/timing-run/media/timing-test-v4.dsk" \
  -ext multi -ext:multi:slot4 fdc -ext:multi:slot2 ccpsg \
  -rompath "$HOME/Library/Application Support/Ample/roms" \
  -cfg_directory "$PWD/emulator/images/timing-run/config" \
  -nvram_directory "$PWD/emulator/images/timing-run/nvram" \
  -state_directory "$PWD/emulator/images/timing-run/states" \
  -snapshot_directory "$PWD/emulator/images/timing-run/snapshots" \
  -autoboot_script "$PWD/emulator/images/timing-run/mcp/scripts/bridge.lua" \
  -autoboot_delay 0 -wavwrite "$PWD/emulator/images/timing-run/logs/timing-final-v3.wav" \
  -sound coreaudio
```

At a fresh BASIC `OK` prompt, enter `DOS` once; if the machine is already in EOU, continue at the Shell. Run `chx /d1`, `load cctplaymt cctcount cctstop tpsprobe`, then `tpsprobe`. Start the counter with `cctcount &`; run each track as `cctplaymt -psg 2 /d1/<file> &`. For a graceful-stop measurement, start the 30-second fixture and issue `cctstop <player-pid>` immediately, before it can finish. Capture `$FF5E/$FF5F` writes, emulated time, a screenshot during playback, and a fresh WAV for each track.
