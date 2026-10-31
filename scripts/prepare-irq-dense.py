#!/usr/bin/env python3
"""Original dense/multivoice/long fixtures; no copyrighted tracks are included."""
import argparse,struct,runpy
from pathlib import Path
read=runpy.run_path(str(Path(__file__).with_name('analyze-psg-timing.py')))['read_track']

def make(mode):
 cmd=bytearray();samples=0
 def write(r,v):cmd.extend((0xa0,r,v))
 def wait(n,opcode=None):
  nonlocal samples
  samples+=n
  if opcode is not None:cmd.append(opcode)
  elif 1<=n<=16:cmd.append(0x70+n-1)
  else:cmd.extend((0x61,n&255,n>>8))
 def voices(i):
  for r,v in [(0,180+i%40),(1,0),(2,220+i%30),(3,0),(4,100+i%50),(5,1),(6,7),(7,0x38),(8,12),(9,10),(10,16),(11,255),(12,0),(13,10),(13,10),(13,14)]:write(r,v)
 if mode=='cancel':
  for r,v in [(7,0x38),(8,12),(0,180),(1,0)]:write(r,v)
  for i in range(4096):write(13,i%16)
 else:voices(0)
 if mode=='cancel':pass
 elif mode=='saturation':
  for i in range(1,15):wait(735,0x62);voices(i)
  wait(735,0x62)
  for _ in range(12):write(13,10)  # fill all 256 slots including final mute marker
 elif mode=='mixed':
  for n in range(1,17):wait(n);write(13,10);write(n%6,n*7)
  for i in range(4):wait(735,0x62);voices(i);wait(882,0x63);voices(i+1)
  wait(44100)
 elif mode=='streamlong':
  for i in range(1050):
   wait(8820)
   for r,v in [(0,180+i%40),(2,220+i%30),(4,100+i%50),(8,12),(13,10)]:write(r,v)
 elif mode=='long':
  # 210 seconds continuously enabled; update all three pitches/envelope
  # after each five-second sustain. Enough records to fit fixed preload.
  for i in range(42):
   for _ in range(5):wait(44100)
   for r,v in [(0,180+i%40),(2,220+i%30),(4,100+i%50),(13,10)]:write(r,v)
 else:raise ValueError(mode)
 if mode!='cancel':write(8,0);write(9,0);write(10,0)
 cmd.append(0x66)
 h=bytearray(128);h[:4]=b'Vgm ';struct.pack_into('<I',h,8,0x151);struct.pack_into('<I',h,0x18,samples);struct.pack_into('<I',h,0x34,0x4c);struct.pack_into('<I',h,0x74,2000000);h[0x78]=0 if mode=='cancel' else 16
 data=h+cmd;struct.pack_into('<I',data,4,len(data)-4);return data

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('mode',choices=['saturation','mixed','long','cancel','streamlong']);a=p.parse_args()
 f=Path('build/irq-dense-'+a.mode+'.vgm');f.write_bytes(make(a.mode));_,t=read(f,0)
 if a.mode in ('cancel','streamlong'):
  print(a.mode,len(t['writes']),'streaming-only fixture');raise SystemExit(0)
 events=[((w['sample']+734)//735,w['register'],w['value']) for w in t['writes']]+[((t['samples']+734)//735,255,0)]
 assert len(events)<=256 and events[-1][0]<32768
 Path('build/irq-dense.inc').write_text(''.join(f'        fdb {tick},${r:02x}{v:02x}\n' for tick,r,v in events))
 print(a.mode,len(events),t['samples']/44100)
