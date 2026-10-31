# GMC IRQ integration: hardware and architecture gate

Status at `24ec221`: research PASS; GMC implementation and live playback NOT RUN.
The existing `cctirq` remains CoCoPSG only. This document records the boundary
before modifying its validated queue or claiming GMC compatibility.

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
budget and one physical 8 KB standalone package limit must be measured again.

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

No GMC playback, PCM capture, or regression result is claimed in this research
checkpoint. Rollback is the unchanged `cctirq` from `24ec221`.
