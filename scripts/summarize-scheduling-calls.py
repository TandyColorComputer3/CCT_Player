#!/usr/bin/env python3
"""Pair qualified player instruction-fetch taps and summarize queue residency."""
import argparse,collections,json,statistics,bisect
from pathlib import Path

def summarize(path):
 d=json.loads(path.read_text());events=d['events']
 if d['droppedEvents'] or any(e['kind']=='discontinuity' for e in events):raise ValueError('incomplete capture')
 samples=[e for e in events if e['kind']=='process-sample'];times=[e['seconds'] for e in samples]
 expected={c["label"]:d["config"]["base"]+c["offset"] for c in d["config"]["calls"]}
 pending={};spans=[];unmatched=0;prefetch=0
 for e in events:
  key=e.get('pid'),e.get('label')
  if e['kind'] in ('call-enter','call-return') and e['pc'] != expected[e['label']] + (1 if e['kind']=='call-enter' else 4):
   prefetch+=1;continue
  if e['kind']=='call-enter':
   if key in pending:raise ValueError('nested/repeated call entry')
   pending[key]=e
  elif e['kind']=='call-return':
   if key not in pending:unmatched+=1;continue
   a=pending.pop(key);dt=e['seconds']-a['seconds'];spans.append({'label':e['label'],'pid':e['pid'],'start':a['seconds'],'end':e['seconds'],'duration':dt,'request_x':a['x'],'result_x':e['x'],'result_y':e['y'],'carry':e['cc']&1})
 rows={}
 for label in sorted({e['label'] for e in spans}):
  values=sorted(e['duration'] for e in spans if e['label']==label)
  rows[label]={'count':len(values),'min':min(values),'median':statistics.median(values),'p95':values[int(.95*(len(values)-1))],'p99':values[int(.99*(len(values)-1))],'max':max(values)}
 longest=sorted(spans,key=lambda x:-x['duration'])[:12]
 for span in longest:
  bins=collections.defaultdict(float);begin,end=span['start'],span['end'];i=max(0,bisect.bisect_right(times,begin)-1)
  while i<len(samples) and times[i]<end:
   e=samples[i];dt=max(0,min(end,times[i+1] if i+1<len(times) else d['finish'])-max(begin,times[i]));state=e.get('state',0)
   category='unknown'
   if e.get('queue')=='active':category='ready-suspended' if state&8 else 'ready'
   elif e.get('queue') in ('sleep','wait'):category=e['queue']
   elif e.get('current')==span['pid']:category='current-system' if e['task']==0 else 'current-user'
   bins[category]+=dt;i+=1
  span['sampled_queue_seconds']=dict(bins)
 return {'capture':str(path),'calls':rows,'longest_calls':longest,'discarded_nonexecuted_prefetches':prefetch,'unmatched_returns':unmatched,'unfinished_calls':len(pending),'observed_priorities':sorted({e['priority'] for e in samples if 'priority' in e})}

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('captures',nargs='+',type=Path);a=p.parse_args();print(json.dumps([summarize(f) for f in a.captures],indent=2))
