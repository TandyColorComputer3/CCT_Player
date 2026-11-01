# GMC IRQ integration: hardware and architecture gate

The hardware gate was recorded at `ab63772`. The opt-in `cctgmc` implementation
now uses the established IRQ queue; `cctirq` remains the CoCoPSG program.

## Hardware and source format

Todd Wallace's original `PLAY_CHIP_SN76489` handles VGM `$50` followed by one
raw SN76489 command byte. Its waits are `$61` (16-bit little-endian 44,100 Hz
samples), `$62` (735 samples), `$63` (882 samples), and `$70`–`$7f` (1–16
samples); `$66` ends or loops the stream. The original routine writes each
`$50` operand directly to `$FF41`, with settling instructions after the write.
It selects the GMC in MPI slot 1 by default. The original sound-off sequence
writes `$9f,$bf,$df,$ff` to silence all four channels. It masks interrupts for
the entire song, so it cannot serve as a background implementation.

The existing CCT loader accepts only header chip codes 1, 2 and 3 (OPL3,
OPL2, YM2149/AY). It has **no defined GMC CCT code**. Therefore a CCT file
cannot honestly be called supported GMC input without a separately specified
format. An M3U can list GMC VGM tracks once the GMC backend exists.

[MAME's GMC cartridge implementation](https://github.com/mamedev/mame/blob/master/src/devices/bus/coco/coco_gmc.cpp)
uses a 4 MHz SN76489AN and routes SCS offset 1 (`$FF41`) directly to the chip's
single-byte `write` method. Offset 0 is ROM bank selection. [MAME's SN76489
implementation](https://github.com/mamedev/mame/blob/master/src/devices/sound/sn76496.cpp)
sets the latched register from bits 6–4 when bit 7 is set. A following byte
with bit 7 clear applies to that latched register; for tone periods its six
low bits supply the high period bits. Noise writes can reset the shift
register. Thus byte order, duplicate bytes and latch/data pairing are
observable and must be preserved. The GMC has no CoCoPSG style register-select
and data ports; the CoCoPSG `$FF5D` control setting does not apply.

The source VGM clock must be checked against the GMC's fixed 4 MHz clock.
MAME's emulated clock is exactly 4 MHz; a VGM recorded for another SN clock
can play at a different pitch if written unchanged. VGM variant and dual-chip
flags also need explicit compatibility checks before opening audio.

## Safe implementation boundary

The four-byte queue record (modulo serviced tick, register, value), 256-entry
ring, 16-entry IRQ budget, producer sleep/retry, owned file blocks and IOMan
path cleanup can be reused. For GMC, one record would carry one raw command
byte; the register field can distinguish data from FE wait marker and FF end.
The append validator and IRQ output must be chip specific. A GMC IRQ writer
must save the live `$FF7F`, change only SCS slot bits to slot 1, write one byte
to `$FF41`, restore `$FF7F`, and preserve the incoming CC. Stop and completion
must emit all four mute bytes in order, with measured safe spacing, and must
not restore a CoCoPSG control register it never owned. The 16-write callback
budget is retained and the one physical 8 KB standalone package limit is
checked by the build and tests. GMC callback duration remains unmeasured.

The current producer's CoCoPSG parser accepts `$A0` register/value pairs.
GMC VGM parsing needs its own `$50` one-byte path while sharing the sample-to-
tick accumulator and process-safe file mapping. Its output backend must not
reuse `WritePSG`, which performs two writes to `$FF5E/$FF5F`. The old GMC busy
loop and direct `$FFA9` map must remain unreachable in the background build.

## Test gate

Before a GMC release claim, capture ordered `$FF41` writes and WAV for real
SN VGM tracks, then verify duration, pitch, event lateness, queue occupancy,
IRQ cost, Shell/counter responsiveness, command loading, M3U transitions,
stop/kill, MPI restoration during disk access and exact memory/IRQ/VIRQ
teardown. Compare the same workloads against CoCoPSG without changing its
timing. Conventional floppy stress remains subject to the previously measured
OS clock loss. Real GMC hardware and CoCoSDC native access require separate
physical tests.

## Implementation and use

`bash scripts/build.sh` followed by `bash scripts/build-irq-stream.sh` creates
`build/cctgmc-standalone` (program, `GMCStream` driver, `gmcs` descriptor).
Install that single file as `/dd/cmds/cctgmc` with executable attributes, and
install `build/cctstop`. The program opens `/gmcs` itself; no manual driver
load or kernel change is needed. Shell usage follows the original player flag:

```text
cctgmc -gmc 1 -l 0 /dd/music/song.vgm &
cctgmc -gmc 1 -l 0 /dd/music/list.m3u &
cctstop PID
```

The existing four-byte queue stores each SN `$50` operand as register 0 and
raw value, preserving repeats and latch/data adjacency. VGM `$4F` stereo
control consumes its operand but produces no sound write on the mono GMC;
an operand equal to `$50` was tested to catch parser misalignment. The established
sample-to-tick accumulator, bounded 16-event callback, 256-entry ring,
process-safe loader mapping and driver-owned allocation cleanup are shared.
`GMCStream` has a GMC-only write routine: it saves live `$FF7F`, selects SCS
slot 1, writes one byte to `$FF41`, waits the original minimum instruction
spacing, then restores `$FF7F` and CC. Completion and stop issue all four
volume-latch mutes. No CoCoPSG control register is accessed in the GMC build.
The package is 7,946 bytes, within the one-block cold-load limit. `os9 ident`
reports a 6,864-byte program with 1,987 bytes of process data, a 1,043-byte
driver with 1,350 bytes of system data, and a 39-byte descriptor. Kernel CPU
time and queue occupancy were not measured in this run. Rollback is
to omit the opt-in `cctgmc` package; `cctirq` builds byte-identically to
`ab63772` from the modified source.

CCT chip codes 1–3 remain unchanged and are rejected by `cctgmc` with an
unsupported chip/format message. A future GMC CCT format would need a new,
specified chip identifier, payload framing and timing definition; reusing a
current CCT code would reinterpret existing files.

## Live MAME results

Isolated `coco3h`, HD6309, 2 MB, EOU Level II, `-ext:multi:slot1 gmc`, private
floppy and VHD copies, MAME 0.289. Source events were decoded independently
with `scripts/analyze-gmc-irq.py` and compared with host taps on `$FF41`.
WAVs and JSON captures are under ignored `emulator/images/reliability/logs/`.
The real track was `lemmin01.vgm` from
[RomWBW's pinned music tree](https://github.com/wwarthen/RomWBW/tree/3e337f730383c5da3a1337ecf80f6882683ef6aa/Source/Apps/VGM/Tunes),
SHA-256 `6ea0562dbd795bfffc3d5d97ad1e6a9084e9100b91f3d39909f3e18f248a7250`.
The source's 3,579,540 Hz clock plays about 192 cents high on fixed 4 MHz GMC;
no tempo or command byte was changed to hide that pitch difference.

| Case | Status | Evidence |
| --- | --- | --- |
| Generated three-tone/noise, repeated latch/data | PASS | 560/560 ordered source bytes, 12 subsequent mute bytes; first sound to mute 1.3351 s versus 1.3333 s of waits; maximum relative event lateness 2.66 ms. WAV peak 27,209 and last-second RMS 0. |
| Real `lemmin01.vgm` completion | PASS | Final build: 20,359/20,359 ordered source bytes, 12 subsequent mute bytes; first sound to mute 53.6691 s versus 53.6000 s of waits; maximum relative lateness 69.77 ms. WAV peak 15,479 and last-second AC RMS 0. |
| `$4F` operand equal to `$50` | PASS | The final parser skipped the mono-irrelevant stereo byte; all 560 musical writes remained aligned, with 12 cleanup mutes, an active WAV and a silent tail. |
| 255 zero-wait GMC writes | PASS for integrity | All 255 bytes reached `$FF41` in order, followed by 12 mute bytes; no IRQ/VIRQ remained. This exceeds one callback budget and deferred the final event by 251.7 ms. It is a stress case, not a smooth timing result. |
| Background Shell and command load | PASS | Prompt returned with player PID while music ran; `mfree` completed. A typed `pwd` path did not exist on this guest, so that command is not counted as a pass. |
| Directory commands | FAIL as an activity test | `dir /d1` returned OS-9 error 203; no successful directory workload is claimed. |
| Floppy access during real playback | PASS | Song loaded from `/d1` and 274 FDC commands were observed in the full capture. Sustained concurrent floppy stress was NOT RUN. |
| `cctstop` during real playback | PASS | 5,617 source bytes were delivered in order before cancellation, followed by two complete four-byte mute groups. IRQ/VIRQ tables emptied; final PCM second silent. |
| Forced `kill` during real playback | PASS | After 2,842 musical bytes, four mute bytes ended the capture; IRQ/VIRQ tables emptied; final PCM second silent. |
| Repeated startup/completion | PASS | Separate synthetic and real runs cold-loaded and detached the driver. A final-build synthetic cycle restored all 256 physical allocation entries, 32 system-page entries, and the process/path snapshot exactly. |
| M3U (`DF213C` build) | PASS | Two generated VGM tracks: all 1,120 musical writes and 24 mute writes matched the exact playlist order; WAV peak 27,209, final AC RMS 0, IRQ/VIRQ tables empty. |
| Unsupported CoCoPSG CCT on `cctgmc` | PASS | Visible unsupported chip/format error and OS-9 error 203; zero `$FF41` writes; IRQ/VIRQ tables empty. |
| MPI transaction integrity | PASS in MAME | All 20,371 `$FF41` writes in the complete real capture were bracketed by `$FF7F` selection `$fc` and restoration `$ff`; no mismatches. Median and maximum select-to-restore interval were 15.64 microseconds. |
| Human listening | PASS | The user heard the `DF213C` real-track run at normal speed and reported “sounded good no breaks.” The final parser revision had the same ordered real-track sound bytes; it was not listened to separately. |
| M3U stop during transition | NOT RUN | Natural two-track sequencing passed; signal arrival at the transition boundary remains to test. |
| Queue occupancy, IRQ cost, user/kernel CPU | NOT RUN | The consumer budget and ring size are unchanged; comparative costs still need a matching instrumented capture. |
| Physical GMC/MPI and CoCoSDC | NOT RUN | MAME's cartridge and WD1773 floppy do not establish physical behavior. |

The final standalone build has program CRC `48DBFF`, driver CRC `A8CF38`, and
descriptor CRC `61BC49`; `os9 ident` reports good CRCs and expected OS-9
module types. The real-track/stop/kill measurements above used an earlier
GMC program CRC `D456AE`; subsequent changes revised help/error text and
rejected dual-SN headers. Program CRC `DF213C` passed the M3U byte/audio test,
CCT rejection, and a second complete real-track capture at normal speed:
20,359/20,359 source bytes, 12 mute bytes, 53.6691 seconds first-to-mute,
69.77 ms maximum relative lateness, WAV peak 15,440 and final-second maximum
channel AC RMS 0.46 PCM units. `mfree` completed visibly during the music.
This trace and the earlier unthrottled real capture had the same event timing
within measurement precision. The `DF213C` forced-kill cycle restored the
physical allocation, system-page and process/path snapshots exactly and left
the IRQ/VIRQ tables empty. Its PID and `DF213C` module CRC were checked before
the kill. The `48DBFF` revision consumes `$4F` stereo operands explicitly;
its authentic-track capture again preserved 20,359/20,359 sound bytes and 12
mutes, with 53.6691 seconds first-to-mute, 69.77 ms maximum relative lateness,
WAV peak 15,479 and final AC RMS 0. The final `$4F` and dense fixtures also
passed. Normal completion, graceful stop and forced kill have separate live
evidence; pending music is intentionally discarded only on a stop.

The CoCoPSG `cctirq` player and `PSGStream` driver were reassembled from
`ab63772` and compared byte-for-byte to the current artifacts: PASS. A separate
CoCoPSG MAME boot completed Flicky CCT playback: 825 PSG data writes (the
previously validated 820 music writes plus cleanup), with IRQ/VIRQ tables
empty after completion. Its WAV recording ended before the final mute, so
final-silence audio on this regression run is NOT RUN. Existing VGM/M3U and
playlist-stop results remain in `IRQ-PLAYER-HARDENING.md`; they were not
repeated in this GMC phase. Original `cctplay` and rebuilt `build/cctplay`
remain byte-identical, SHA-256 `eabe6b6f3910ebd1af557f64b02c1fb1e1802a3a07a1bf134016b1a4a6792f36`.

The initial `anna.vgm` attempt was rejected as an unsupported mixed-chip file;
its stream contains YM2612 commands. An initial 72-second `lemmin01` capture
ended before the song because floppy loading took roughly 28 emulated seconds.
It is excluded from complete-track metrics. The longer 100-second capture
includes loading, all music writes, completion and silence. The final package
and CoCoPSG results are listed above.

The queue still follows NitrOS-9 serviced ticks. CPU HALT and masked floppy
intervals can lose those ticks, so sustained floppy traffic can stretch tempo
as documented in `IRQ-PLAYER-HARDENING.md`. This GMC work did not alter the
clock source, the OS scheduler, or the CoCoPSG event timing.
