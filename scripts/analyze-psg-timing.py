#!/usr/bin/env python3
"""Summarize supported YM2149 VGM/CCT timing and optional MAME write traces.

This is a host-side diagnostic: it does not change the player or the guest.
The optional JSON trace is the entry array returned by the MAME MCP
capture_results command. It pairs writes to $FF5E/$FF5F with decoded VGM events
and reports accumulated lateness against the first captured register write.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

SAMPLE_RATE = 44_100
CPU_HZ = 1_780_000
HD6309_CYCLES_PER_SAMPLE = 41


def parse_stream(data: bytes, start: int, label: str, loop_start: int | None = None,
                 extra_loops: int = 0) -> tuple[list[dict], dict]:
    pc = start
    samples = 0
    waits: list[dict] = []
    writes: list[dict] = []
    command_counts: dict[str, int] = {}
    loops_left = extra_loops
    seen_end = False
    while pc < len(data):
        op_at = pc
        op = data[pc]
        pc += 1
        command_counts[f"{op:02X}"] = command_counts.get(f"{op:02X}", 0) + 1
        if op == 0xA0:
            if pc + 2 > len(data):
                raise ValueError(f"{label}: truncated A0 command at 0x{op_at:X}")
            writes.append({"sample": samples, "register": data[pc], "value": data[pc + 1]})
            pc += 2
        elif op == 0x61:
            if pc + 2 > len(data):
                raise ValueError(f"{label}: truncated 61 wait at 0x{op_at:X}")
            delay = struct.unpack_from("<H", data, pc)[0]
            pc += 2
            waits.append({"sample": samples, "count": delay, "kind": "manual"})
            samples += delay
        elif op == 0x62 or op == 0x63:
            delay = 735 if op == 0x62 else 882
            waits.append({"sample": samples, "count": delay, "kind": "frame735" if op == 0x62 else "frame882"})
            samples += delay
        elif 0x70 <= op <= 0x7F:
            delay = (op & 0x0F) + 1
            waits.append({"sample": samples, "count": delay, "kind": "short"})
            samples += delay
        elif op == 0x66:
            if loop_start is not None and loops_left > 0:
                loops_left -= 1
                pc = loop_start
            else:
                seen_end = True
                break
        else:
            raise ValueError(f"{label}: unsupported PSG command 0x{op:02X} at 0x{op_at:X}")
    if not seen_end:
        raise ValueError(f"{label}: missing 0x66 end command")
    return waits, {"writes": writes, "samples": samples, "commands": command_counts,
                   "extra_loops_applied": extra_loops - loops_left}


def read_track(path: Path, loop_count: int) -> tuple[list[dict], dict]:
    data = path.read_bytes()
    if path.suffix.lower() == ".vgm":
        if len(data) < 0x40 or data[:4] != b"Vgm ":
            raise ValueError(f"{path}: missing VGM header")
        version = struct.unpack_from("<I", data, 0x08)[0]
        start = 0x40 if version >= 0x150 and struct.unpack_from("<I", data, 0x34)[0] else 0x40
        data_rel = struct.unpack_from("<I", data, 0x34)[0]
        if data_rel:
            start = 0x34 + data_rel
        total = struct.unpack_from("<I", data, 0x18)[0]
        loop_rel = struct.unpack_from("<I", data, 0x1C)[0]
        loop_samples = struct.unpack_from("<I", data, 0x20)[0]
        loop_start = 0x1C + loop_rel if loop_rel else None
        # A zero-sample or out-of-file loop offset is not a playable loop.
        if loop_start is not None and (
            not loop_samples or loop_start < start or loop_start >= len(data)
        ):
            loop_start = None
        loops = loop_count if loop_start is not None else 0
        waits, result = parse_stream(data, start, str(path), loop_start, loops)
        result.update({"format": "VGM", "version": f"{version >> 8}.{version & 0xFF:02X}",
                       "header_samples": total, "header_loop_samples": loop_samples,
                       "loop_offset": loop_rel, "requested_extra_loops": loop_count,
                       "expected_samples_from_header": total + loops * loop_samples})
        if loop_rel and loop_samples and result["samples"] != total + loops * loop_samples:
            result["header_stream_sample_check"] = "mismatch; stream parser count retained"
        else:
            result["header_stream_sample_check"] = "match" if result["samples"] == total + loops * loop_samples else "no loop metadata"
        return waits, result
    if path.suffix.lower() == ".cct":
        if len(data) < 6656:
            raise ValueError(f"{path}: shorter than CCT header/data offset")
        chip = data[34]
        if chip != 3:
            raise ValueError(f"{path}: CCT chip type {chip}, expected YM2149 type 3")
        waits, result = parse_stream(data, 6656, str(path))
        result.update({"format": "CCT", "version": None, "cct_chip_type": chip,
                       "header_loop_samples": 0, "loop_offset": 0,
                       "requested_extra_loops": loop_count,
                       "expected_samples_from_header": None,
                       "header_stream_sample_check": "CCT stream end; no VGM loop header"})
        return waits, result
    raise ValueError(f"{path}: only .vgm and .cct are supported")


def schedule_summary(waits: list[dict], samples_per_tick: int, tick_hz: int) -> dict:
    ticks = fine = coarse_events = 0
    kinds: dict[str, int] = {}
    for wait in waits:
        n = wait["count"]
        kinds[wait["kind"]] = kinds.get(wait["kind"], 0) + 1
        whole, remainder = divmod(n, samples_per_tick)
        if whole < 2:
            fine += n
        else:
            ticks += whole
            fine += remainder
            coarse_events += 1
    return {
        "samples_per_tick": samples_per_tick,
        "coarse_sleep_events": coarse_events,
        "coarse_sleep_ticks": ticks,
        "fine_delay_samples": fine,
        "coarse_sleep_seconds_at_nominal_tick_rate": ticks / tick_hz,
        "fine_loop_seconds_at_nominal_41_cycles_per_sample":
            fine * HD6309_CYCLES_PER_SAMPLE / CPU_HZ,
        "fine_loop_nominal_sample_seconds": fine / SAMPLE_RATE,
        "wait_event_kinds": kinds,
    }


def analyze_capture(path: Path, writes: list[dict], total_samples: int) -> dict:
    raw = json.loads(path.read_text())
    events = raw.get("entries", raw.get("events", raw)) if isinstance(raw, dict) else raw
    if not isinstance(events, list):
        raise ValueError(f"{path}: expected an array or object with entries/events array")
    psg = [e for e in events if isinstance(e, dict) and e.get("offset") in (0xFF5E, 0xFF5F)]
    pairs = []
    i = 0
    while i + 1 < len(psg):
        if psg[i].get("offset") == 0xFF5E and psg[i + 1].get("offset") == 0xFF5F:
            pairs.append({"register": psg[i].get("data"), "value": psg[i + 1].get("data"),
                          "address_seconds": psg[i].get("seconds"),
                          "seconds": psg[i + 1].get("seconds")})
            i += 2
        else:
            i += 1
    aligned = 0
    for candidate in range(len(pairs)):
        if candidate + len(writes) > len(pairs):
            break
        if all(pairs[candidate + j]["register"] == w["register"] and
               pairs[candidate + j]["value"] == w["value"] for j, w in enumerate(writes)):
            aligned = candidate
            break
    if not writes or len(pairs) < aligned + len(writes):
        return {"psg_port_writes": len(psg), "paired_register_writes": len(pairs),
                "expected_register_writes": len(writes), "sequence_match": False}
    actual = pairs[aligned:aligned + len(writes)]
    after_stream = pairs[aligned + len(writes):]
    first_s = actual[0]["seconds"]
    first_sample = writes[0]["sample"]
    lateness = [a["seconds"] - first_s - (w["sample"] - first_sample) / SAMPLE_RATE
                for a, w in zip(actual, writes)]
    bus_write_us = [(p["seconds"] - p["address_seconds"]) * 1_000_000
                    for p in actual if p.get("address_seconds") is not None and
                    p.get("seconds") is not None]
    result = {
        "psg_port_writes": len(psg),
        "paired_register_writes": len(pairs),
        "expected_register_writes": len(writes),
        "sequence_match": True,
        "matched_start_pair": aligned,
        "first_write_emulated_seconds": first_s,
        "last_write_emulated_seconds": actual[-1]["seconds"],
        "expected_first_to_last_seconds": (writes[-1]["sample"] - first_sample) / SAMPLE_RATE,
        "measured_first_to_last_seconds": actual[-1]["seconds"] - first_s,
        "expected_from_first_write_to_track_end_seconds": (total_samples - first_sample) / SAMPLE_RATE,
        "measured_first_write_to_end_marker_seconds": None,
        "estimated_track_start_to_end_marker_seconds": None,
        "end_marker_register_value": None,
        "end_to_end_error_percent": None,
        "post_stream_register_pairs": len(after_stream),
        "median_address_to_data_write_us": sorted(bus_write_us)[len(bus_write_us) // 2]
        if bus_write_us else None,
        "last_write_lateness_seconds": lateness[-1],
        "max_positive_event_lateness_seconds": max(lateness),
        "minimum_event_lateness_seconds": min(lateness),
    }
    # The experimental cleanup path writes YM mixer register 7=$3F after the
    # decoded stream. Use that observed mute write as the guest-side end marker.
    # Other extra writes are reported but do not silently become a duration.
    mute = next((p for p in after_stream
                 if p.get("register") == 7 and p.get("value") == 0x3F), None)
    if mute and mute.get("seconds") is not None:
        elapsed = mute["seconds"] - first_s
        estimated_full = elapsed + first_sample / SAMPLE_RATE
        expected = total_samples / SAMPLE_RATE
        result.update({"measured_first_write_to_end_marker_seconds": elapsed,
                       "estimated_track_start_to_end_marker_seconds": estimated_full,
                       "end_marker_register_value": "07=3F",
                       "end_to_end_error_percent": 100 * (estimated_full / expected - 1)
                       if expected else None})
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tracks", nargs="+", type=Path)
    parser.add_argument("--tick-hz", type=int, choices=(50, 60), default=60)
    parser.add_argument("--loop-count", type=int, default=1,
                        help="extra passes through VGM loop section (default matches cctplaymt)")
    parser.add_argument("--capture", type=Path,
                        help="MAME capture_results JSON for one track")
    args = parser.parse_args()
    if args.loop_count < 0:
        parser.error("--loop-count must be nonnegative")
    out = []
    try:
        for path in args.tracks:
            waits, result = read_track(path, args.loop_count)
            result["filename"] = path.name
            result["expected_seconds"] = result["samples"] / SAMPLE_RATE
            result["event_count"] = sum(result["commands"].values())
            result["wait_count"] = len(waits)
            result["psg_register_writes"] = len(result["writes"])
            result["sample_wait_total"] = sum(w["count"] for w in waits)
            result["historical_100hz_441_samples_per_tick_model"] = schedule_summary(waits, 441, 100)
            result["ntsc_60hz_735_samples"] = schedule_summary(waits, 735, 60)
            result["pal_50hz_882_samples"] = schedule_summary(waits, 882, 50)
            result["target_tick_clock"] = schedule_summary(waits, SAMPLE_RATE // args.tick_hz, args.tick_hz)
            expected_writes = result.pop("writes")
            if args.capture and len(args.tracks) == 1:
                result["mame_capture"] = analyze_capture(args.capture, expected_writes,
                                                          result["samples"])
            out.append(result)
    except (OSError, ValueError, struct.error) as exc:
        print(f"timing analysis: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
