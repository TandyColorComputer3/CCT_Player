#!/usr/bin/env python3
"""Create a short, original YM2149 VGM tone test in the ignored build dir."""

from pathlib import Path
import struct
import sys


def make_vgm() -> bytes:
    # VGM 1.50 header with AY/YM2149 clock/variant fields and data at $80.
    header = bytearray(0x80)
    header[0:4] = b"Vgm "
    struct.pack_into("<I", header, 0x08, 0x00000150)
    samples_per_frame = 735
    frames_per_note = 30
    struct.pack_into("<I", header, 0x18, samples_per_frame * frames_per_note * 2)
    struct.pack_into("<I", header, 0x34, 0x4C)  # data offset is relative to $34
    struct.pack_into("<I", header, 0x74, 2_000_000)
    header[0x78] = 0x10  # YM2149

    commands = bytearray()

    def write(register: int, value: int) -> None:
        commands.extend((0xA0, register, value))

    write(7, 0x3E)   # tone A enabled; other channels/noise disabled
    write(8, 0x0F)   # channel A maximum volume
    write(0, 0xC8)   # period 200
    write(1, 0x00)
    commands.extend((0x62,) * frames_per_note)
    write(0, 0x2C)   # period 300
    write(1, 0x01)
    commands.extend((0x62,) * frames_per_note)
    write(8, 0x00)   # silence channel A before end
    commands.append(0x66)

    image = header + commands
    if len(image) < 256:
        image.extend(b"\0" * (256 - len(image)))
    struct.pack_into("<I", image, 0x04, len(image) - 4)
    return bytes(image)


def main() -> None:
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("build/synthetic-psg.vgm")
    target.parent.mkdir(parents=True, exist_ok=True)
    content = make_vgm()
    target.write_bytes(content)
    print(f"Wrote {target} ({len(content)} bytes, generated test tone only)")


if __name__ == "__main__":
    main()
