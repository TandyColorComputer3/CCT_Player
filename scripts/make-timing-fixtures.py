#!/usr/bin/env python3
"""Generate original PSG streams for measuring wait and write overhead."""

from pathlib import Path
import struct
import sys


def make_fixture(seconds: int, mode: str) -> bytes:
    commands = bytearray()

    def write(register: int, value: int) -> None:
        commands.extend((0xA0, register, value))

    def wait(samples: int) -> None:
        if 1 <= samples <= 16:
            commands.append(0x70 + samples - 1)
        elif samples == 735:
            commands.append(0x62)
        else:
            commands.append(0x61)
            commands.extend(struct.pack("<H", samples))

    for register, value in ((7, 0x3E), (8, 0x0F), (0, 200), (1, 0)):
        write(register, value)

    event = 0
    for _ in range(seconds):
        if mode in ("short", "tiny", "dense"):
            intervals = [735] * 60
        elif mode == "long":
            intervals = [44100]
        else:
            intervals = [735] * 30 + [22050]
        for samples in intervals:
            if mode == "tiny":
                for _ in range(45):
                    wait(16)
                wait(15)
            else:
                wait(samples)
            event += 1
            write(0, 180 + (event % 40))
            if mode == "dense":
                write(1, 0)
                write(8, 8 + (event % 8))
                write(7, 0x3E)

    write(8, 0)  # The last stream write marks its sample endpoint.
    commands.append(0x66)
    header = bytearray(0x80)
    header[:4] = b"Vgm "
    struct.pack_into("<I", header, 0x08, 0x151)
    struct.pack_into("<I", header, 0x18, seconds * 44100)
    struct.pack_into("<I", header, 0x34, 0x4C)
    struct.pack_into("<I", header, 0x74, 2_000_000)
    header[0x78] = 0x10
    image = header + commands
    if len(image) < 256:
        image.extend(b"\0" * (256 - len(image)))
    struct.pack_into("<I", image, 0x04, len(image) - 4)
    return bytes(image)


def main() -> None:
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("build/timing-fixtures")
    target.mkdir(parents=True, exist_ok=True)
    for seconds in (10, 30):
        for mode in ("short", "tiny", "long", "mixed", "dense"):
            path = target / f"{mode}{seconds}.vgm"
            path.write_bytes(make_fixture(seconds, mode))
            print(f"{path}: {seconds * 44100} samples, {path.stat().st_size} bytes")


if __name__ == "__main__":
    main()
