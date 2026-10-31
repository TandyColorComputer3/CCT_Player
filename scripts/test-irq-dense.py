#!/usr/bin/env python3
"""Fixture coverage and independent capacity/budget arithmetic checks."""
import runpy,struct,tempfile,unittest
from pathlib import Path
HERE=Path(__file__).parent
make=runpy.run_path(str(HERE/'prepare-irq-dense.py'))['make']
read=runpy.run_path(str(HERE/'analyze-psg-timing.py'))['read_track']

class DenseTests(unittest.TestCase):
 def track(self,mode):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'tone.vgm';p.write_bytes(make(mode));return read(p,0)[1]
 def test_full_capacity(self):
  t=self.track('saturation');self.assertEqual(len(t['writes'])+1,256)
  self.assertEqual(t['samples'],11025)
  # Even with no producer costs, eight writes/tick need 32 interrupts.
  self.assertGreaterEqual((len(t['writes'])+1+7)//8,32)
 def test_short_and_frame_wait_opcodes(self):
  data=make('mixed');pos=128;short=set();frames=set()
  while data[pos]!=0x66:
   op=data[pos];pos+=1
   if op==0xa0:pos+=2
   elif op==0x61:pos+=2
   elif op in (0x62,0x63):frames.add(op)
   elif 0x70<=op<=0x7f:short.add(op-0x6f)
   else:self.fail(f'unknown generated opcode {op}')
  self.assertEqual(short,set(range(1,17)));self.assertEqual(frames,{0x62,0x63})
 def test_streaming_crosses_pages(self):
  data=make('streamlong');self.assertGreater(len(data),16384)
  t=self.track('streamlong');self.assertEqual(t['samples'],210*44100)
  self.assertGreater(len(t['writes']),5000)
 def test_long_and_side_effects(self):
  t=self.track('long');self.assertEqual(t['samples'],210*44100)
  self.assertLessEqual(len(t['writes'])+1,256)
  self.assertEqual(sum(w['register']==13 for w in t['writes']),45)
  self.assertTrue({0,2,4,8,9,10}.issubset({w['register'] for w in t['writes']}))

if __name__=='__main__':unittest.main()
