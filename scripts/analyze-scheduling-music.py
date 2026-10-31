#!/usr/bin/env python3
"""Verify the three-track real-music sequence and report event timing.

Fixture directory must contain arkanoid.vgm, ark1.cct, flicky.cct. Initial
samples before the first PSG write are added only as a duration estimate.
Percentiles describe event errors, not raw inter-event gaps.
"""
import argparse,bisect,json,math,runpy
from pathlib import Path
HERE=Path(__file__).parent
read=runpy.run_path(str(HERE/'analyze-psg-timing.py'))['read_track']
pairs=runpy.run_path(str(HERE/'summarize-psg-repeats.py'))['pairs']

def analyze(fixtures,capture):
 d=json.loads(capture.read_text());events=d['events']
 if d.get('droppedEvents') or d.get('resetCount') or any(e['kind']=='discontinuity' for e in events):raise ValueError('incomplete capture')
 observed=pairs(events);pos=0;rows=[]
 ticks=[e['seconds'] for e in events if e['kind']=='clock-tick']
 for name in ['arkanoid.vgm','ark1.cct','flicky.cct']:
  _,track=read(fixtures/name,0);writes=track['writes'];seq=[(e['register'],e['value']) for e in writes]
  found=next((i for i in range(pos,len(observed)-len(seq)) if [(r,v) for r,v,t in observed[i:i+len(seq)]]==seq and observed[i+len(seq)][:2]==(7,63)),None)
  if found is None:raise ValueError(f'{capture}: incomplete ordered {name}')
  segment=observed[found:found+len(seq)];start=segment[0][2];end=observed[found+len(seq)][2]
  errors=[e[2]-start-(w['sample']-writes[0]['sample'])/44100 for e,w in zip(segment,writes)]
  local=[b[2]-a[2]-(wb['sample']-wa['sample'])/44100 for a,b,wa,wb in zip(segment,segment[1:],writes,writes[1:]) if wb['sample']>wa['sample']]
  sorted_errors=sorted(errors);inside=lambda e:start<=e['seconds']<=end
  due_ticks=bisect.bisect_right(ticks,end)-bisect.bisect_left(ticks,start)
  rows.append({'track':name,'pairs':len(seq),'first_write':start,'mute':end,'estimated_seconds':end-start+writes[0]['sample']/44100,'expected_seconds':track['samples']/44100,
   'max_event_lateness':max(errors),'p95_event_lateness':sorted_errors[math.ceil(.95*len(errors))-1],'p99_event_lateness':sorted_errors[math.ceil(.99*len(errors))-1],
   'max_local_excess':max(local,default=0),'ticks':due_ticks,'clock_deficit':end-start-due_ticks/60,
   'clock_calls':sum(e['kind']=='clock-call' and inside(e) for e in events),'fdc_commands':sum(e['kind']=='fdc-command' and inside(e) for e in events),
   'posted_inputs':[e for e in events if e['kind']=='host-input' and inside(e)]})
  pos=found+len(seq)+1
 return {'capture':str(capture),'tracks':rows,'remaining_pairs':len(observed)-pos,'final_mpi':next((e['data'] for e in reversed(events) if e['kind']=='mpi-write'),None)}

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('fixtures',type=Path);p.add_argument('captures',type=Path,nargs='+');a=p.parse_args();print(json.dumps([analyze(a.fixtures,c) for c in a.captures],indent=2))
