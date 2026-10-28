# Playlist stop and timing repeatability

Baseline: `b57eb94`; the reported historical reboot remains **UNRESOLVED /
NOT REPRODUCED**. These tests do not establish its cause. The player still uses
ordinary OS-9 process scheduling; no kernel or timing constants were changed.

## MPI transaction audit

The previous experimental transaction restored the live MPI byte, but its
selection value included upper bits captured at startup; the common cleanup then
wrote that old startup byte again. Initialization, each register write,
diagnostic marker, and mixer/control restore now read the live `$FF7F` value,
retain bits 2–7, replace only SCS slot bits 0–1, and restore the byte read at
entry. Each hardware transaction saves and restores the incoming CC; no sleep,
file I/O, decoder, or playlist transition runs with interrupts masked.
Initialization tests the latched stop while masked and checks again after
restoring CC; an already claimed PSG uses normal mute/control cleanup.

The test trace saw `$FF -> $FD -> $FF` for the selected slot, with paired
writes and no reset. In the final idle synthetic capture, the 212 selection-to-
restore intervals ranged from 17.9 to 30.8 microseconds of emulated time;
these intervals do not include every instruction that saves or restores CC.
This is a static and MAME-specific audit; it does not prove
coordination with other programs changing the MPI or worst-case floppy interrupt
latency. The previous `$F1` value discarded other low selection bits.

## Playlist stop

`SIGNAL_HANDLER` still only sets `abortFlag,U` and returns with `RTI`. The flag
is never cleared between tracks. Cleanup checks it before advancing a playlist;
the next-track path checks it before opening and after acquiring a path and
header. Loader boundaries check it after safe completion of allocation and
mapping operations, after a completed read has been unmapped, and before stream
startup. A read mapping is recorded separately, so an interrupted/error exit
can clear it and the `$E000` reservation before freeing song blocks. If the
read-map clear fails, manual block freeing is skipped rather than freeing a
possibly mapped block; that error path has not been fault-injected.

`psgsuper TICKS PATH` is a test supervisor, not an audio service. It forks the
player, retains the child PID returned by `F$Fork`, requests `S$Intrpt` through
`F$Send`, retries `E$USigP` at most three times with two-tick sleeps, then
collects the child's status with `F$Wait`. It prints `SUP PID=xx SEND=xx
WAIT=xx` as hex. Its child is not reaped before the send attempt. The EOU
[technical manual](https://www.lcurtisboyle.com/nitros9/EOUDOCS/NitrOS-9_EOU_Level_2_Technical_Reference_Manual.pdf)
describes `F$Fork`, `F$Send` and `F$Wait`; actual phase attribution below comes
from MAME tracing, not the requested tick count. Pending-signal retries were
implemented but not deliberately forced in this run.

Playlist-stop candidate at `42dd06f`: SHA-256
`86b459ebcef89182cee3b7c18a289add18a82262e3c0c9b8225a347ea718221e`,
9,377 bytes, live module CRC `$BF0B8C`, ToolShed CRC good and reentrant.
The live module directory, size and CRC were read from MAME's physical RAM.
Supervisor SHA-256
`0893ad8021de3cdd9ca5316887edc29fa76af894e1d263768eddf4d7fcc9525a`,
CRC `$9B130F`, 459 bytes, reentrant.

All four trials used the private two-entry Ark1/Flicky playlist, a preloaded
supervisor and player, and a real signal to the returned child PID. Each showed
`SEND=00 WAIT=00`, final mixer mute, no reset, and a returned Shell prompt.
There were no dropped observer events. That candidate's trace timestamps:

| Requested ticks | Observed signal phase | Evidence |
| ---: | --- | --- |
| 600 | First track | Signal 1.813 s after its first register write; final mute 5.9 ms later; no second track. |
| 720 | Near end of first track | Signal 4.048 s after its first write, with the first track's decoded duration 4.430 s; final mute 6.5 ms later; no second track. |
| 900 | Loading next track | Signal 5.700 s after first-track mute, with floppy commands surrounding delivery; no second-track PSG write. |
| 1240 | Just after second track begins | Signal 0.584 s after its first register write; final mute 6.5 ms later. |

For the 900-tick trial the system signal byte cleared approximately 0.208 s
after it was written, after in-flight disk activity. This distinguishes signal
delivery from the later handler opportunity. A second transition-load stop
with the counter running also returned successfully and made no second-track
PSG writes. The separate on-demand floppy-loaded `cctstop` test targeted the
verified player PID and passed with a final `07=3F` mixer write. `mfree` was
1,816 KiB before and after that test in the final-candidate guest; a separate
counter-loaded transition test held at 1,808 KiB. These aggregate observations do
not prove all allocator and fault paths are leak-free.

Natural completion also ran: both complete register streams matched (266 and
820 PSG pairs), with two mutes. First-track estimated duration was 4.432 s
against 4.430 s decoded, and the second was 19.864 s against 20.090 s. The
nominal samples before the first write are added to these estimates; they are
not directly timestamped. A separate old anomaly, diagnosed in the next section, limits the
strength of this natural-playlist result.

## CCT end-command anomaly: diagnosis and focused fix

A private MAME observer tapped reads of the known Ark1 CCT tail and writes to
the process-local map state. In the slow run with `42dd06f`, the player read
`61 FF 00 66` at offsets `$0493`–`$0496` correctly. Immediately after `$66`,
it took the loop path with an invalid saved loop offset `$7910` and a stale
block-list pointer `$8E06`, switched mappings, and scanned `$FF` bytes before
muting 10.864 seconds after the last music write. In the matched normal run,
the same `$66` went directly to mute 4.518 ms after the last music write. This
is a control-flow and stream-state error, not accumulated timing drift. CCT
loading did not initialize `vgmLoopCount`, although the common `$66` handler
uses it to decide whether to branch through the VGM loop pointers. Process
memory can contain a nonzero old value; a preceding VGM may also leave loop
state. CCT has no VGM loop offset. The experimental CCT loader now clears the
counter for each track. VGM loop setup and all delay constants are unchanged.

The fixed player SHA-256 is
`666f91ea6a3292e2c0b96f46547698b78bef7dd3215269cc0bc40f8c5035cb8d`,
9,381 bytes, live module CRC `$4BB36C`, ToolShed CRC good and reentrant. The
same MAME 0.289 HD6309/2 MiB EOU configuration used a separate private boot
floppy and VHD with the hashes recorded above. The fixed test floppy before
mounting was SHA-256
`a0d81c2a23d17641441cd55b5da82b08ef8f37cbf0771c46cad5f336ddf23f9d`;
the read-only observer source SHA-256 was
`41112671b7041faff035294f8398cbfc2012ce3b79f14cd40408d48f407703bc`.
The trace taps include only the relevant logical tail reads and map-state
writes; no guest memory was modified to induce the incident.

- Four Ark1 CCT runs matched all 266 register pairs and muted 4.427284,
  4.429724, 4.428491 and 4.428861 seconds after the first write. Decoded
  duration is 4.430204 seconds, including 276 samples (6.259 ms) before that
  first write; do not compare those measured boundaries as full durations.
  Each `$66` read was followed by mute in about 0.072 ms.
- The real Ark1/Flicky playlist completed both 266- and 820-pair streams and
  muted twice. Flicky's observed first-write-to-mute interval was 19.865 s
  for 20.090 s decoded; the CCT loop fix does not resolve general timing error.
- A generated VGM with a 0.5-second loop, played for the default extra loop,
  matched all 10 expected register pairs. It also played as the first entry in
  a VGM/CCT playlist, followed by the complete 266-pair Ark1 stream. The loop
  fixture SHA-256 is
  `81bb1631bdf3e21a5451ed2d92dd6b34d8d32f92b0d0b4529310c2b5a5062bdb`.
- A real `F$Send` from the preloaded supervisor during the next-track load
  returned `SEND=00 WAIT=00`, with no second-track PSG write. The Shell prompt
  returned. No capture dropped events or saw a MAME reset.
- A 30-second synthetic VGM regression matched all 210 register pairs and
  measured 29.379309 seconds first-write-to-mute, or -2.069%. This is an idle
  single observation, not proof of a general 1% timing target.

These observations support the specific stale CCT loop-state diagnosis, but do
not prove the absence of other timing or memory defects. Private captures are
`trace-anomaly-tail-{1,2}.json`, `trace-loopfix-ark-{1,2,3,4}.json`,
`trace-loopfix-playlist-{natural,stop}.json`,
`trace-loopfix-vgm-{loop,cct-playlist}.json`, and
`trace-loopfix-synthetic30.json` under ignored `emulator/images/stability-run/`.
The historical reboot is still **UNRESOLVED / NOT REPRODUCED**.

## Timing comparison and limits

The fixed 30-second fixture contains 1,323,000 decoded samples, no loop, and
210 PSG register pairs. Its SHA-256 is
`b87c4bd79d2b36fa1654e88ae3454cd9de85de99ab72f0aef43ccf8c1d7e3840`.
The boundary is the observed first PSG data write to the observed final
`07=3F` data write; its first event is at sample zero. The end `$66` command
was not independently marked in these production captures. All six timing
runs below used the same intermediate stop candidate (SHA-256
`ea03306ff8e195f737c8192bff1643aa7ff578d3fb2480c03f345be5415f9945`,
CRC `$3B4103`), same boot/media and observer; the only deliberate guest
workload difference was a background `cctcount` printing once per nominal
second. The supervisor was resident but idle. Each stream matched all 210
pairs, and no capture dropped events.

| Guest workload | First-write to mute, seconds | Error versus 30.000 s |
| --- | --- | --- |
| Idle, three runs | 29.378446, 29.378678, 29.378674 | -2.072%, -2.071%, -2.071% |
| `cctcount`, three runs | 29.778773, 29.779635, 29.778665 | -0.737%, -0.735%, -0.738% |

A second matched comparison used the `42dd06f` candidate and the same visible guest,
private media and observer for all four runs. `timeload` prints 60 numbered lines,
sleeps 61 requested ticks between lines, and exits naturally; its module CRC is
`$12274D` and SHA-256 is
`e3db7497107f0c43542a884ab1fd58b1b8d2ce97555a0a48720195fdacead253`.
The module remained active until after the player exited on both workload runs.
All 210 expected PSG pairs matched in every capture; no events were dropped.

| Final build workload | First-write to mute, seconds | Error versus 30.000 s |
| --- | --- | --- |
| Idle, two runs | 29.379299, 29.379299 | -2.069%, -2.069% |
| `timeload`, two runs | 29.791883, 29.791883 | -0.694%, -0.694% |

These are observed emulated timestamps, not host wall time. The first event is
at sample zero; the mute is observed, but the actual `$66` command is not
independently timestamped, so the small end-to-mute interval is included. The
preceding three idle measurements (29.378160, 29.379575 and 29.379575 s) used
the immediately preceding candidate, CRC `$CA6B12`, before the extra guard
reservation stop check; they are not attributed to the final binary.

The earlier counter workload adds about 0.400 s
in this setup; it does not fully reconstruct the old 29.959 s run. Comparing
aligned old and new counter traces shows the old stream gained about 188 ms
relative to the new one around event 13 and retained about 180 ms of that
difference at mute. The old event gap and prior drift therefore account for much
of the remaining measured duration difference, but the old trace does not
record enough task, disk or automation state to establish its cause. Its exact
conditions cannot be reconstructed. No wait constant was changed to fit a run.

The fixed environment was MAME `0.289 (ample-289-u2)`, visible `coco3h`,
HD6309, 2 MiB, MPI slot 2 `ccpsg`, slot 4 `fdc`, private EOU VHD and boot
floppy. The visible launch used `coco3h -ramsize 2M -window -skip_gameinfo
-natural -ext multi -ext:multi:slot4 fdc -ext:multi:slot2 ccpsg`, private
`-flop1`, `-flop2`, `-hard1`, config/NVRAM/state directories, the Lua bridge,
`-sound coreaudio` and a private `-wavwrite` capture. Initial private VHD SHA-256:
`7bef15fab761db2084517ebadaa5b7ee42a667ee7131fcf629ee8c3531835681`;
boot floppy SHA-256:
`9a51adb8656b9f003c7f822352c291487362f1b4c43aac1a16672d5d2bcb4c40`.
The intermediate test floppy SHA-256 before launch was
`1db5c4291575495a2c2ac8821feac3c6c4d8b394d8768ba7a8024334a5c7ab0b`.
The host observer SHA-256 was
`d7cceffefe494918f0bd1237f28d9a3e37e77a6b27892343add7fcfc16da1268`;
`scripts/analyze-psg-timing.py` SHA-256 was
`624c620774289aa4d4dfb0742044f62bf95f2548a2d5b3c7dea2686471383997`.
The `42dd06f` guest's test disk SHA-256 before mounting was
`2b7fef3a95ad171d1b6fec5f6756ba423ab6f80a8e54005448af6fb0d16ff69a`;
the extended host observer SHA-256 was
`3c992b9f9e535aa04a730ea8f7d1c21a52176270b740717de17198f3c6baba76`.
The guest module directory confirmed CRC `$BF0B8C` and size 9,377 for every
matched run of that candidate. The guest was otherwise idle except for the usual EOU boot
processes; in workload runs only `timeload` was deliberately added. The same
private guest and floppy were used for all four final runs.

**Historical idle playlist anomaly, diagnosed above:** in three idle runs of the intermediate
candidate, the first track muted at approximately 15.295, 15.296 and 4.437 s
for a decoded 4.430 s track. A fresh control using the unchanged `b57eb94`
module (live CRC `$7AE209`) produced 15.291 and 4.431 s under the same
observer. In the long-gap case, saved HD6309 frames show the decoder continuing
to inspect `$FF` bytes; no additional expected register writes occurred before
mute. This is not explained by a delayed mute alone. It predates the playlist-stop
change in the tested configuration; the targeted investigation above
identifies a CCT loop-state defect. The counter-workload timing differences
remain independent and are not a general timing-quality pass.

Evidence is retained locally under ignored `emulator/images/stability-run/`,
including `trace-verified-super-{600,720,900,1240}.json`,
`trace-verified-ondemand.json`, `trace-verified-playlist-natural.json`,
`trace-verified-matched-{idle,load}-{1,2}.json`,
`trace-stopwork2-{idle,counter}-{1,2,3}.json`,
`trace-stopwork2-playlist-stack-{1,2}.json`, and
`trace-b57-playlist-control-{1,2}.json`. These private traces and music are not
committed.
