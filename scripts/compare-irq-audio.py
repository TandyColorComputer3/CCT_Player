#!/usr/bin/env python3
"""Compare matched musical PCM windows, without claiming perceptual equivalence.

A Hann-windowed average spectrum ignores phase and is tolerant of small tempo
changes; it cannot establish transient/envelope fidelity. Uses standard Python.
"""
import argparse,array,cmath,json,math,runpy,wave
from pathlib import Path
HERE=Path(__file__).parent
read=runpy.run_path(str(HERE/'analyze-psg-timing.py'))['read_track']
pairs=runpy.run_path(str(HERE/'summarize-psg-repeats.py'))['pairs']

def spectrum(track,capture,channel,seconds):
 _,song=read(track,0);d=json.loads(capture.read_text());obs=pairs(d['events']);expected=[(w['register'],w['value']) for w in song['writes']]
 index=next(i for i in range(len(obs)-len(expected)+1) if [v[:2] for v in obs[i:i+len(expected)]]==expected)
 start=obs[index][2]-d['start'];size=4096;power=[0.]*(size//2)
 with wave.open(str(capture.with_suffix('.wav'))) as w:
  assert w.getsampwidth()==2 and 0<=channel<w.getnchannels()
  rate=w.getframerate();w.setpos(int(start*rate));a=array.array('h',w.readframes(int(seconds*rate)))[channel::w.getnchannels()]
  windows=len(a)//size;assert windows>0
  for offset in range(0,windows*size,size):
   values=a[offset:offset+size];mean=sum(values)/size
   v=[complex((x-mean)*(.5-.5*math.cos(2*math.pi*i/(size-1)))) for i,x in enumerate(values)]
   j=0
   for i in range(1,size):
    bit=size>>1
    while j&bit:j^=bit;bit>>=1
    j^=bit
    if i<j:v[i],v[j]=v[j],v[i]
   length=2
   while length<=size:
    root=cmath.exp(-2j*math.pi/length)
    for first in range(0,size,length):
     twiddle=1
     for j in range(first,first+length//2):
      u=v[j];t=twiddle*v[j+length//2];v[j]=u+t;v[j+length//2]=u-t;twiddle*=root
    length*=2
   for k in range(1,size//2):power[k]+=abs(v[k])**2/windows
 return rate,power

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('track',type=Path);p.add_argument('first',type=Path);p.add_argument('second',type=Path);p.add_argument('--channel',type=int,default=1);p.add_argument('--seconds',type=float,default=8);a=p.parse_args()
 r,x=spectrum(a.track,a.first,a.channel,a.seconds);r2,y=spectrum(a.track,a.second,a.channel,a.seconds);assert r==r2
 indices=range(math.ceil(100*4096/r),min(len(x),math.floor(8000*4096/r)+1))
 norm=math.sqrt(sum(x[k]**2 for k in indices)*sum(y[k]**2 for k in indices));assert norm>0
 print(json.dumps({'seconds':a.seconds,'channel':a.channel,'fft_size':4096,'frequency_resolution_hz':r/4096,
  'frequency_band_hz':[100,8000],'power_spectrum_cosine_similarity':sum(x[k]*y[k] for k in indices)/norm,
  'strongest_bins_hz':[[k*r/4096 for k in sorted(indices,key=lambda k:v[k],reverse=True)[:8]] for v in [x,y]],
  'limitation':'Phase/tempo-tolerant aggregate metric; not a perceptual or envelope-equivalence test.'},indent=2))
