#!/usr/bin/env python3
"""Summarize exact PSG sequences in bounded MAME observer JSON captures.

Usage: summarize-psg-repeats.py track.vgm trace1.json [trace2.json ...]
The parser is shared with analyze-psg-timing.py; only zero-extra-loop tracks are
accepted. Each reported interval runs from the first observed data write through
the subsequent 07=3F mute. Any samples before the first write are added only to
an *estimated* full duration. Lost observer events invalidate a capture; frame
sample rollover is reported separately and does not invalidate port writes.
"""
from __future__ import annotations

import argparse
import json
import math
import runpy
import statistics
from pathlib import Path


def pairs(events: list[dict]) -> list[tuple[int, int, float]]:
    result = []
    selection = None
    for event in events:
        if event.get("kind") != "psg-write":
            continue
        addr = event.get("address", event.get("offset"))
        if addr == 0xFF5E:
            selection = event["data"]
        elif addr == 0xFF5F and selection is not None:
            result.append((selection, event["data"], event["seconds"]))
            selection = None
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("track", type=Path)
    parser.add_argument("captures", type=Path, nargs="+")
    args = parser.parse_args()
    routines = runpy.run_path(str(Path(__file__).with_name("analyze-psg-timing.py")))
    _, track = routines["read_track"](args.track, 0)
    writes = track["writes"]
    expected = [(w["register"], w["value"]) for w in writes]
    if not expected or not track["samples"]:
        raise ValueError("track has no timed register stream")
    rows = []
    for capture in args.captures:
        data = json.loads(capture.read_text())
        if data.get("droppedEvents", 0):
            raise ValueError(f"{capture}: observer events were dropped")
        events = data["events"]
        observed = pairs(events)
        pos = 0
        found = 0
        while pos + len(expected) <= len(observed):
            segment = observed[pos:pos + len(expected)]
            if [(r, v) for r, v, _ in segment] != expected:
                pos += 1
                continue
            mute_at = pos + len(expected)
            if mute_at >= len(observed) or observed[mute_at][:2] != (7, 0x3F):
                raise ValueError(f"{capture}: stream is not followed immediately by final mute")
            start = segment[0][2]
            mute = observed[mute_at][2]
            duration = mute - start
            estimate = duration + writes[0]["sample"] / 44100
            expected_duration = track["samples"] / 44100
            local = []
            accumulated = []
            for i in range(1, len(writes)):
                delta = (writes[i]["sample"] - writes[i - 1]["sample"]) / 44100
                if delta:
                    local.append(segment[i][2] - segment[i - 1][2] - delta)
                accumulated.append(segment[i][2] - start -
                                   (writes[i]["sample"] - writes[0]["sample"]) / 44100)
            rows.append({"capture": str(capture), "first_write_seconds": start,
                         "final_mute_seconds": mute, "first_to_mute_seconds": duration,
                         "estimated_full_seconds": estimate,
                         "error_percent": 100 * (estimate / expected_duration - 1),
                         "max_local_lateness_seconds": max(local) if local else None,
                         "max_accumulated_lateness_seconds": max(accumulated) if accumulated else None,
                         "min_accumulated_error_seconds": min(accumulated) if accumulated else None,
                         "median_accumulated_error_seconds": statistics.median(accumulated) if accumulated else None,
                         "p95_absolute_event_error_seconds": sorted(map(abs, accumulated))[
                             math.ceil(.95 * len(accumulated)) - 1] if accumulated else None,
                         "fdc_commands_during_playback": sum(
                             e.get("kind") == "fdc-command" and start <= e["seconds"] <= mute
                             for e in events),
                         "dropped_frame_samples": data.get("droppedSamples", 0),
                         "reset_count": data.get("resetCount")})
            found += 1
            pos = mute_at + 1
        if not found:
            raise ValueError(f"{capture}: no complete matching sequence and mute")
    errors = [r["error_percent"] for r in rows]
    print(json.dumps({"expected_samples": track["samples"],
                      "expected_seconds": track["samples"] / 44100,
                      "first_write_sample": writes[0]["sample"],
                      "expected_register_pairs": len(expected), "runs": rows,
                      "error_percent_min": min(errors), "error_percent_max": max(errors),
                      "error_percent_mean": statistics.mean(errors),
                      "error_percent_sample_stddev": statistics.stdev(errors) if len(errors) > 1 else None},
                     indent=2))


if __name__ == "__main__":
    main()
