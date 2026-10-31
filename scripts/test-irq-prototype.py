#!/usr/bin/env python3
"""Host checks for generated queue records and rejection of corrupt IRQ evidence."""
import copy,json,runpy,tempfile,unittest
from pathlib import Path
HERE=Path(__file__).parent
analyze=runpy.run_path(str(HERE/'analyze-irq-playback.py'))['analyze']
read=runpy.run_path(str(HERE/'analyze-psg-timing.py'))['read_track']

class IRQTests(unittest.TestCase):
 def setUp(self):
  self.track=Path('build/irq-synthetic30.vgm');_,song=read(self.track,0)
  events=[]
  for w in song['writes']+[{'sample':song['samples'],'register':7,'value':63}]:
   t=w['sample']/44100
   events.extend([dict(kind='mpi-write',seconds=t,data=253),dict(kind='psg-write',seconds=t,address=0xff5e,data=w['register'],in_handler=True),dict(kind='psg-write',seconds=t+.00001,address=0xff5f,data=w['value'],in_handler=True),dict(kind='mpi-write',seconds=t+.00002,data=255)])
  self.data={'events':events,'droppedEvents':0}
 def run_data(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'capture.json';p.write_text(json.dumps(self.data));return analyze(self.track,p)
 def test_complete_stream(self):
  r=self.run_data();self.assertEqual(r['pairs'],210);self.assertEqual(r['final_mpi'],255);self.assertAlmostEqual(r['duration'],30)
 def test_missing_write_or_mute_rejected(self):
  self.data['events'].pop(-2)
  with self.assertRaises(ValueError):self.run_data()
 def test_overflow_and_mpi_corruption_rejected(self):
  original=copy.deepcopy(self.data)
  self.data['droppedEvents']=1
  with self.assertRaises(ValueError):self.run_data()
  self.data=original;self.data['events'][0]['data']=1
  with self.assertRaises(ValueError):self.run_data()
 def test_fixed_capacity_and_side_effect_writes(self):
  _,s=read(Path('build/irq-burst.vgm'),0)
  shapes=[w for w in s['writes'] if w['register']==13]
  self.assertEqual(len(shapes),120)
  self.assertLessEqual(len(s['writes'])+1,256)
  self.assertEqual(len(Path('build/irq-over.inc').read_text().splitlines()),257)

if __name__=='__main__':unittest.main()
