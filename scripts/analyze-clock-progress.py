#!/usr/bin/env python3
"""Compare independent MAME time, video acknowledgements and CCTClock writes.

Use performance-observer.lua output, or a stability observer with irq-ack and
system-write events. Bounds must be independently chosen PSG/marker timestamps.
Frames are cadence samples, never reported as actual IRQ assertions. Clock
reads include INC's read-modify-write access; only GetStat PCs count as calls.
"""
import argparse
import json
import statistics
from pathlib import Path


def analyze(data, start, end, code, storage, watch_start=None):
    if data.get('droppedEvents', 0) or data.get('resetCount', 0):
        raise ValueError('overflow or reset invalidates this interval')
    if end <= start:
        raise ValueError('end must follow start')
    if 'config' in data:
        if data['config'] != {'code': code, 'storage': storage}:
            raise ValueError('driver address configuration mismatch')
        watch_start = next(e['seconds'] for e in data['events'] if e['kind'] == 'start')
    if watch_start is None or start < watch_start:
        raise ValueError('clock-watch coverage must be established for the entire interval')
    events = [e for e in data['events'] if start < e['seconds'] <= end]
    irq = [e for e in events if e['kind'] == 'irq-ack' and e['data'] & 8]
    # Baseline INC Ticks+3,U callback PC is the following instruction ($A4).
    ticks = [e for e in events if e['kind'] in ('clock-write', 'system-write')
             and e.get('address') == storage + 37 and e.get('pc') == code + 164
             and e.get('u') == storage and e.get('task') == 0]
    reads = [e for e in events if e['kind'] == 'clock-read'
             and e.get('address') == storage + 34 and e.get('pc') == code + 145]
    gaps = [b['seconds']-a['seconds'] for a, b in zip(irq, irq[1:])]
    # Match increment to the latest preceding acknowledgement. This measures
    # dispatch-to-increment latency, not assertion-to-handler latency.
    latencies = []
    j = 0
    for tick in ticks:
        while j + 1 < len(irq) and irq[j+1]['seconds'] <= tick['seconds']:
            j += 1
        if irq and irq[j]['seconds'] <= tick['seconds']:
            latencies.append(tick['seconds']-irq[j]['seconds'])
    return {
        'start_seconds': start, 'end_seconds': end, 'elapsed_seconds': end-start,
        'video_acknowledgements': len(irq), 'clock_increments': len(ticks),
        'clock_nominal_seconds': len(ticks)/60,
        'clock_nominal_deficit_seconds': end-start-len(ticks)/60,
        'getstat_calls_observed': len(reads) if any(e['kind']=='clock-read' for e in events) else None,
        'max_video_ack_gap_seconds': max(gaps, default=None),
        'median_video_ack_gap_seconds': statistics.median(gaps) if gaps else None,
        'max_ack_to_clock_increment_seconds': max(latencies, default=None),
        'fdc_commands': sum(e['kind']=='fdc-command' for e in events),
        'actual_video_irq_assertions': 'NOT MEASURED',
        'cpu_utilization': 'NOT MEASURED',
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('capture', type=Path)
    p.add_argument('--start', type=float, required=True)
    p.add_argument('--end', type=float, required=True)
    p.add_argument('--code', type=lambda x: int(x, 0), required=True)
    p.add_argument('--storage', type=lambda x: int(x, 0), required=True)
    p.add_argument('--watch-start', type=float, help='verified watch start for legacy stability captures')
    a = p.parse_args()
    print(json.dumps(analyze(json.loads(a.capture.read_text()), a.start, a.end, a.code, a.storage, a.watch_start), indent=2))


if __name__ == '__main__':
    main()
