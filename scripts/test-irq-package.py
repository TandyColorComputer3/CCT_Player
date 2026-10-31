#!/usr/bin/env python3
"""Guard cold-start packaging against scarce EOU system DAT slots."""
from pathlib import Path
import unittest

def modules(data):
 out=[];offset=0
 while offset<len(data):
  b=data[offset:];assert b[:2]==b'\x87\xcd'
  size=int.from_bytes(b[2:4],'big');assert 13<=size<=len(b)
  name_at=int.from_bytes(b[4:6],'big');name=''
  for v in b[name_at:size]:
   name+=chr(v&127)
   if v&128:break
  out.append((name,offset,size,b[6]));offset+=size
 return out

class PackageTests(unittest.TestCase):
 def test_installation_fits_one_system_block(self):
  for p in [Path('build/cctirq-standalone'),*Path('build').glob('cctirq-fail-*')]:
   with self.subTest(path=p):
    b=p.read_bytes();self.assertLessEqual(len(b),8192)
    m=modules(b);self.assertEqual([v[0] for v in m],['cctirq','PSGStream','psgs'])
    self.assertEqual([v[3] for v in m],[0x11,0xe1,0xf1])
 def test_original_unchanged(self):
  self.assertEqual(Path('cctplay').read_bytes(),Path('build/cctplay').read_bytes())

if __name__=='__main__':unittest.main()
