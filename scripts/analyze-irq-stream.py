#!/usr/bin/env python3
"""Audit streaming publication, IRQ cost and process CPU samples from captures."""
import argparse,collections,json,runpy
from pathlib import Path
HERE=Path(__file__).parent
base=runpy.run_path(str(HERE/'analyze-irq-playback.py'))['analyze']
dense=runpy.run_path(str(HERE/'analyze-irq-dense.py'))['analyze']
read=runpy.run_path(str(HERE/'analyze-psg-timing.py'))['read_track']
clock=runpy.run_path(str(HERE/'analyze-clock-reliability.py'))['analyze']

def audit(capture):
 d=json.loads(capture.read_text());events=d['events'];assert not d['droppedEvents']
 pending=None;locked=None;durations=[];accepted=rejected=0;pids=set();wraps=collections.Counter()
 for e in events:
  k=e['kind']
  if k=='append-enter':
   assert pending is None;pending=e;pids.add(e['current'])
  elif k in ('append-ok','append-reject'):
   assert pending is not None and (pending['cc']^e['cc'])&0x50==0
   if k=='append-ok':
    accepted+=1
    if pending['tail']==255 and e['tail']==0:wraps['tail']+=1
   else:rejected+=1
   pending=None
  elif k=='append-locked':assert locked is None;locked=e['seconds']
  elif k=='append-unlock':
   assert locked is not None;durations.append(e['seconds']-locked);locked=None
 assert pending is None and locked is None
 controls=[e for e in events if e['kind'] in ('control-read','control-write')]
 r={'accepted_records':accepted,'full_or_state_rejections':rejected,'producer_pids':sorted(pids),'tail_wraps':wraps['tail'],
    'maximum_append_masked_body_seconds':max(durations,default=None),
    'driver_calls':dict(collections.Counter(e['kind'] for e in events if e['kind'] in ('setstat','getstat'))),
    'control_accesses':[(e['kind'],e['data']) for e in controls]}
 # Explicit producer PID comes from SCF Append, never from the interrupted IRQ.
 cp=capture.with_name(capture.stem+'-clock.json')
 if cp.exists() and len(pids)==1:
  c=json.loads(cp.read_text());pid=next(iter(pids));schedule={};halt=False;last=c['start'];user=0
  for e in c['events']+[{'kind':'end','seconds':c['finish']}]:
   if schedule.get('pid')==pid and schedule.get('task')==1 and not halt:user+=e['seconds']-last
   if e['kind']=='schedule':schedule=e
   if e['kind']=='cpu-state':halt=bool(e['halt'])
   last=e['seconds']
  r['sampled_producer_user_seconds_whole_capture']=user
 return r

def analyze(track,capture,irq=True):
 r=dense(track,capture) if irq else base(track,capture)
 if irq:r.update(audit(capture))
 _,t=read(track,0);cp=capture.with_name(capture.stem+'-clock.json')
 if cp.exists() and t['writes'][0]['sample']==0:
  c=clock(t,cp)
  # The clock analyzer's IRQ PID attribution is intentionally excluded.
  r['clock']={k:c[k] for k in ('video_edges','irq_acks','clock_ticks','clock_calls','coalesced_edge_states','longest_sampled_interval_seconds')}
 return r

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('track',type=Path);p.add_argument('capture',type=Path);p.add_argument('--park',action='store_true');a=p.parse_args();print(json.dumps(analyze(a.track,a.capture,not a.park),indent=2))
