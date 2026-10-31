#!/usr/bin/env python3
"""Offline 60 Hz quantization and burst/lookahead requirements; no music copied."""
import argparse,collections,json,math,runpy
from pathlib import Path
read=runpy.run_path(str(Path(__file__).with_name('analyze-psg-timing.py')))['read_track']

def analyze(path):
 _,track=read(path,0);writes=track['writes'];ticks=[(w['sample']+734)//735 for w in writes]
 bursts=collections.Counter(ticks);errors=sorted(t/60-w['sample']/44100 for t,w in zip(ticks,writes));peak=0;j=0
 for i,w in enumerate(writes):
  while writes[j]['sample']<w['sample']-2*44100:j+=1
  peak=max(peak,i-j+1)
 return {'track':path.name,'writes':len(writes),'samples':track['samples'],'maximum_quantization_seconds':max(errors,default=0),
  'p95_quantization_seconds':errors[math.ceil(.95*len(errors))-1] if errors else 0,'maximum_writes_per_tick':max(bursts.values(),default=0),
  'ticks_above_eight_writes':sum(v>8 for v in bursts.values()),'maximum_writes_in_inclusive_two_seconds':peak,
  'four_byte_lookahead_storage':peak*4,'envelope_shape_writes':sum(w['register']==13 for w in writes)}

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('tracks',type=Path,nargs='+');a=p.parse_args();print(json.dumps([analyze(t) for t in a.tracks],indent=2))
