#!/usr/bin/env python3
"""Verify fixed-stream IRQ output and measure bounded handler and MPI costs."""
import argparse,json,math,runpy,statistics
from pathlib import Path
HERE=Path(__file__).parent
read=runpy.run_path(str(HERE/'analyze-psg-timing.py'))['read_track']
pairs=runpy.run_path(str(HERE/'summarize-psg-repeats.py'))['pairs']

def analyze(track,capture):
 d=json.loads(capture.read_text());events=d['events']
 if d['droppedEvents'] or any(e['kind']=='discontinuity' for e in events):raise ValueError('incomplete capture')
 _,song=read(track,0);expected=[(w['register'],w['value']) for w in song['writes']];observed=pairs(events)
 start=next((i for i in range(len(observed)-len(expected)) if [(a,b) for a,b,_ in observed[i:i+len(expected)]]==expected and observed[i+len(expected)][:2]==(7,63)),None)
 if start is None:raise ValueError('missing/reordered writes or final mute')
 stream=observed[start:start+len(expected)];epoch=stream[0][2];end=observed[start+len(expected)][2]
 errors=sorted(t-epoch-(w['sample']-song['writes'][0]['sample'])/44100 for (_,_,t),w in zip(stream,song['writes']))
 spans=[];pending=None;writes=0
 for e in events:
  if e['kind']=='handler-enter':
   if pending:raise ValueError('nested/unclosed IRQ')
   pending=e;writes=0
  elif e['kind']=='psg-write' and e['address']==0xff5f and e['in_handler']:writes+=1
  elif e['kind']=='handler-exit':
   if pending is None:raise ValueError('unmatched IRQ exit')
   spans.append({'seconds':e['seconds']-pending['seconds'],'writes':writes,'state':pending['state'],'budgets':e['budgets'],'underruns':e['underruns']});pending=None
 if pending:raise ValueError('capture ends inside handler')
 # Every selection/restoration must be paired, including system Close mutes.
 selections=[e for e in events if e['kind']=='mpi-write']
 if len(selections)%2:raise ValueError('unpaired MPI selection')
 for a,b in zip(selections[::2],selections[1::2]):
  if a['data'] != (b['data']&252)|1:raise ValueError('MPI bits not preserved')
 durations=[s['seconds'] for s in spans];running=[s for s in spans if s['state']==1]
 return {'capture':str(capture),'pairs':len(expected),'duration':end-epoch,'maximum_event_lateness':max(errors),'minimum_event_error':min(errors),
  'p95_event_lateness':errors[math.ceil(.95*len(errors))-1],'p99_event_lateness':errors[math.ceil(.99*len(errors))-1],
  'handler_calls':len(spans),'maximum_handler_seconds':max(durations,default=0),'median_handler_seconds':statistics.median(durations) if durations else 0,
  'running_handler_seconds':sum(s['seconds'] for s in running),'max_psg_writes_per_handler':max((s['writes'] for s in spans),default=0),
  'over_budget_ticks':max((s['budgets'] for s in spans),default=0),'underruns':max((s['underruns'] for s in spans),default=0),
  'final_mpi':selections[-1]['data'] if selections else None,'maximum_mpi_selection_seconds':max((b['seconds']-a['seconds'] for a,b in zip(selections[::2],selections[1::2])),default=0),
  'writes_in_irq':sum(e['kind']=='psg-write' and e['address']==0xff5f and e['in_handler'] for e in events)}

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('track',type=Path);p.add_argument('captures',type=Path,nargs='+');a=p.parse_args();print(json.dumps([analyze(a.track,c) for c in a.captures],indent=2))
