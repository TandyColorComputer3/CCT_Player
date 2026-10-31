#!/usr/bin/env python3
"""Check PCM evidence diagnostics with an exact-bin tone and missing writes."""
import array,json,math,runpy,tempfile,unittest,wave
from pathlib import Path
HERE=Path(__file__).parent
read=runpy.run_path(str(HERE/'analyze-psg-timing.py'))['read_track']
spectrum=runpy.run_path(str(HERE/'compare-irq-audio.py'))['spectrum']
analyze=runpy.run_path(str(HERE/'analyze-irq-fidelity.py'))['analyze']

class FidelityTests(unittest.TestCase):
 def test_tone_and_sequence_validation(self):
  track=Path('build/irq-synthetic30.vgm');_,song=read(track,0)
  events=[]
  for w in song['writes']:
   for address,data in [(0xff5e,w['register']),(0xff5f,w['value'])]:events.append({'kind':'psg-write','seconds':w['sample']/44100,'address':address,'data':data})
  with tempfile.TemporaryDirectory() as temp:
   cap=Path(temp)/'tone.json';cap.write_text(json.dumps({'start':0,'events':events,'droppedEvents':0}));wav=cap.with_suffix('.wav')
   with wave.open(str(wav),'wb') as w:
    w.setnchannels(1);w.setsampwidth(2);w.setframerate(48000)
    tone=array.array('h',(int(10000*math.sin(2*math.pi*40*i/4096)) for i in range(8192)))
    w.writeframes((tone*176).tobytes())
   rate,power=spectrum(track,cap,0,8192/48000)
   self.assertEqual(rate,48000);self.assertEqual(max(range(len(power)),key=power.__getitem__),40)
   self.assertEqual(analyze(track,cap,wav)['pcm']['channel_stats'][0]['clipped_fraction'],0)
   events.pop(3);cap.write_text(json.dumps({'start':0,'events':events,'droppedEvents':0}))
   with self.assertRaises(ValueError):analyze(track,cap,wav)

if __name__=='__main__':unittest.main()
