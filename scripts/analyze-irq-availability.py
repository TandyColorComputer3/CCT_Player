#!/usr/bin/env python3
"""Correlate the longest qualified player Sleep with serviced video interrupts."""
import bisect
import json
from pathlib import Path
import runpy
import argparse

summarize = runpy.run_path(str(Path(__file__).with_name('summarize-scheduling-calls.py')))['summarize']

def analyze(capture, calls):
    d = json.loads(capture.read_text())
    if d['droppedEvents'] or d.get('resetCount') or any(e['kind']=='discontinuity' for e in d['events']):
        raise ValueError('incomplete capture')
    span = max((s for s in summarize(calls)['longest_calls'] if s['label']=='Sleep'),key=lambda s:s['duration'])
    a,b=span['start'],span['end']
    events=[e for e in d['events'] if a<=e['seconds']<=b]
    ack=[e['seconds'] for e in events if e['kind']=='irq-ack' and e['data']&8]
    ticks=[e['seconds'] for e in events if e['kind']=='clock-tick']
    # Edge generation is independently sampled from the MAME video zone.
    zones=[e for e in events if e['kind']=='video-zone']
    edges=[e for e in zones if e['zone']==2]
    latency=[]
    for t in ticks:
        i=bisect.bisect_right(ack,t)-1
        if i>=0: latency.append(t-ack[i])
    cpu=[e for e in d['events'] if e['kind']=='cpu-state'];times=[e['seconds'] for e in cpu]
    maximum={'halt':0.,'irq_mask':0.};running=dict(maximum)
    for i in range(max(0,bisect.bisect_right(times,a)-1),len(cpu)):
        e=cpu[i]
        if e['seconds']>=b:break
        dt=max(0,min(b,times[i+1] if i+1<len(times) else b)-max(a,e['seconds']))
        for key,on in [('halt',e['halt']!=0),('irq_mask',bool(e['mask']&16))]:
            running[key]=running[key]+dt if on else 0
            maximum[key]=max(maximum[key],running[key])
    return dict(capture=str(capture),calls=str(calls),sleep=span,
        longest_sampled_intervals=maximum,edge_halt_count=sum(e['halt']!=0 for e in edges),
        edge_irq_mask_count=sum(bool(e['mask']&16) for e in edges),
        generated_border_edges=len(edges),video_acknowledgements=len(ack),clock_irq_callbacks=len(ticks),
        maximum_ack_gap=max((y-x for x,y in zip(ack,ack[1:])),default=0),
        maximum_ack_to_clock=max(latency,default=0),
        psg_data_writes=sum(e['kind']=='psg-write' and e['address']==0xff5f for e in events))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('capture',type=Path);p.add_argument('calls',type=Path);a=p.parse_args()
    print(json.dumps(analyze(a.capture,a.calls),indent=2))
