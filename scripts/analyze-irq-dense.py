#!/usr/bin/env python3
"""Validate dense output and separate serviced-tick backlog from wall-time drift."""
import argparse,json,runpy
from pathlib import Path
HERE=Path(__file__).parent
base=runpy.run_path(str(HERE/'analyze-irq-playback.py'))['analyze']
read=runpy.run_path(str(HERE/'analyze-psg-timing.py'))['read_track']

def analyze(track,capture):
 result=base(track,capture);d=json.loads(capture.read_text());_,song=read(track,0)
 entries=[e for e in d['events'] if e['kind']=='handler-enter'];exits=[e for e in d['events'] if e['kind']=='handler-exit']
 current=None;reg=None;out=[]
 for e in d['events']:
  if e['kind']=='handler-enter':current=(e['ticks']+1)&65535
  if e['kind']=='handler-exit':current=None
  if e['kind']=='psg-write':
   if e['address']==0xff5e:reg=e['data']
   elif current is not None:out.append((reg,e['data'],current))
 expected=[(w['register'],w['value']) for w in song['writes']]
 if [(r,v) for r,v,t in out[:len(expected)]]!=expected:raise ValueError('IRQ stream does not match fixture')
 lateness=[t-(w['sample']+734)//735 for (r,v,t),w in zip(out,song['writes'])]
 running=[e for e in entries if e['state']==1]
 epoch=next(e['seconds'] for e in running if e['ticks']==65535)
 musical=[e['seconds'] for e in d['events'] if e['kind']=='psg-write' and e['address']==0xff5f and e['in_handler']][:len(expected)]
 absolute=[t-epoch-w['sample']/44100 for t,w in zip(musical,song['writes'])]
 result.update(epoch_to_first_write=musical[0]-epoch,maximum_epoch_event_lateness=max(absolute),minimum_epoch_event_error=min(absolute),epoch_duration=result['duration']+musical[0]-epoch)
 result.update(expected_seconds=song['samples']/44100,maximum_serviced_tick_lateness=max(lateness),
  minimum_serviced_tick_lateness=min(lateness),max_occupancy=max(e['count'] for e in entries),
  final_head=exits[-1].get('head'),final_tail=exits[-1].get('tail'),final_count=exits[-1]['count'],
  full_ring_observed=any(e['count']==256 and e.get('head')==0 and e.get('tail')==0 for e in entries),
  envelope_writes=sum(w['register']==13 for w in song['writes']),
  expected_full_rate_writes_per_second=len(expected)/(song['samples']/44100))
 return result

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('track',type=Path);p.add_argument('capture',type=Path);a=p.parse_args();print(json.dumps(analyze(a.track,a.capture),indent=2))
