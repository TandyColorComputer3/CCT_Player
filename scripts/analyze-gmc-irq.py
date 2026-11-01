#!/usr/bin/env python3
"""Compare a single-chip SN76489 VGM with MAME's $FF41 trace and PCM tail."""
import argparse
import array
import json
import math
import wave
from pathlib import Path


def decode(path):
    data = Path(path).read_bytes()
    if data[:4] != b'Vgm ':
        raise ValueError('not a VGM file')
    clock = int.from_bytes(data[12:16], 'little')
    if clock == 0 or clock & 0x40000000:
        raise ValueError('missing or dual SN76489 clock')
    version = int.from_bytes(data[8:12], 'little')
    relative = int.from_bytes(data[0x34:0x38], 'little') if version >= 0x150 else 0
    pos = 0x34 + relative if relative else 0x40
    writes, samples = [], 0
    while pos < len(data):
        command = data[pos]
        pos += 1
        if command == 0x50:
            writes.append((data[pos], samples)); pos += 1
        elif command == 0x4f:
            pos += 1  # stereo byte does not address the mono GMC
        elif command == 0x61:
            samples += int.from_bytes(data[pos:pos + 2], 'little'); pos += 2
        elif command == 0x62:
            samples += 735
        elif command == 0x63:
            samples += 882
        elif 0x70 <= command <= 0x7f:
            samples += command - 0x6f
        elif command == 0x66:
            return writes, samples, clock
        else:
            raise ValueError(f'unsupported VGM command ${command:02x} at {pos-1:x}')
    raise ValueError('missing VGM end command')


def analyze(source, capture, wav_path):
    events, samples, clock = decode(source)
    expected = [value for value, _ in events]
    trace = json.loads(Path(capture).read_text())
    writes = [e for e in trace['events'] if e['kind'] == 'gmc-write']
    actual = [e['data'] for e in writes]
    mute = [0x9f, 0xbf, 0xdf, 0xff]
    complete = actual[:len(expected)] == expected
    trailing = actual[len(expected):]
    if not complete or not trailing or len(trailing) % 4 or trailing != mute * (len(trailing)//4):
        raise AssertionError(f'GMC bytes differ: expected {len(expected)}, captured {len(actual)}')
    with wave.open(str(wav_path)) as recording:
        channels, rate = recording.getnchannels(), recording.getframerate()
        pcm = array.array('h'); pcm.frombytes(recording.readframes(recording.getnframes()))
        last = pcm[-rate*channels:]
        peak = max(map(abs, pcm))
        # MAME's CoCo PIA channel can retain a DC offset after playback.
        # Silence is an AC check on each independent output channel.
        tail_ac = []
        for channel in range(channels):
            values = last[channel::channels]
            mean = sum(values)/len(values)
            tail_ac.append(math.sqrt(sum((v-mean)**2 for v in values)/len(values)))
        tail_rms = max(tail_ac)
        seconds = recording.getnframes()/rate
    if peak < 100 or tail_rms > 1:
        raise AssertionError(f'PCM activity/silence failed: peak={peak}, tail RMS={tail_rms}')
    errors = [(writes[i]['seconds']-writes[0]['seconds'])-(sample-events[0][1])/44100
              for i,(_,sample) in enumerate(events)]
    return dict(source_writes=len(expected),captured_writes=len(actual),mute_groups=len(trailing)//4,
                samples=samples,expected_seconds=samples/44100,first_to_mute_seconds=writes[len(expected)]['seconds']-writes[0]['seconds'],
                max_event_lateness_seconds=max(errors),min_event_lateness_seconds=min(errors),
                source_clock_hz=clock,hardware_clock_hz=4000000,pitch_difference_cents=1200*math.log2(4000000/clock),
                wav_seconds=seconds,wav_peak=peak,wav_last_second_ac_rms=tail_rms)

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    for key in ('source','capture','wav'):parser.add_argument(key)
    args=parser.parse_args()
    print(json.dumps(analyze(args.source,args.capture,args.wav),indent=2))
