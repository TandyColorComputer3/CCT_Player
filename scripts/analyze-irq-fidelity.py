#!/usr/bin/env python3
"""Host-only event and PCM evidence; waveform statistics are not a listening test.

Accepts both original-player and IRQ captures. It deliberately does not apply
IRQ-specific MPI assertions to the original, which selects a slot for a track.
WAV channel indices are zero based. Report clipping instead of concealing it.
"""
import argparse,array,collections,hashlib,json,math,runpy,statistics,struct,wave
from pathlib import Path
HERE=Path(__file__).parent
read=runpy.run_path(str(HERE/'analyze-psg-timing.py'))['read_track']
pairs=runpy.run_path(str(HERE/'summarize-psg-repeats.py'))['pairs']

def analyze(track,capture,wav):
 waits,song=read(track,0);d=json.loads(capture.read_text())
 assert not d.get('droppedEvents',d.get('dropped',0))
 assert not any(e['kind']=='discontinuity' for e in d['events'])
 observed=pairs(d['events']);expected=[(e['register'],e['value']) for e in song['writes']]
 index=next((i for i in range(len(observed)-len(expected)+1) if [(r,v) for r,v,_ in observed[i:i+len(expected)]]==expected),None)
 if index is None:raise ValueError('complete ordered musical stream not found')
 stream=observed[index:index+len(expected)];first=stream[0][2];origin=song['writes'][0]['sample']
 errors=[t-first-(e['sample']-origin)/44100 for (_,_,t),e in zip(stream,song['writes'])]
 raw=track.read_bytes();clock=struct.unpack_from('<I',raw,116)[0]&0x3fffffff if song['format']=='VGM' else (2000000 if raw[35] else 1000000)
 selected=2000000 if clock>=1500000 else 1000000
 result={'track_sha256':hashlib.sha256(raw).hexdigest(),'writes':len(stream),'expected_seconds':song['samples']/44100,
  'musical_event_span_seconds':stream[-1][2]-first,'first_event_sample':origin,'max_error_seconds':max(errors),'min_error_seconds':min(errors),
  'source_clock_hz':clock,'selected_clock_hz':selected,'inferred_pitch_error_cents':1200*math.log2(selected/clock),
  'short_wait_count':sum(w['count']<735 for w in waits),'minimum_wait_samples':min((w['count'] for w in waits),default=0),
  'register_counts':dict(collections.Counter(e['register'] for e in song['writes'])),
  'max_writes_per_quantized_tick':max(collections.Counter((e['sample']+734)//735 for e in song['writes']).values())}
 # Timing is referenced to first event; startup disk loading is excluded.
 following=observed[index+len(expected):]
 result['nonmute_writes_after_matched_music']=sum(v[:2]!=(7,63) for v in following)
 result['immediate_final_mute']=bool(following and following[0][:2]==(7,63))
 mute=next((v for v in following if v[:2]==(7,63)),None)
 if mute:result['first_event_to_mute_seconds']=mute[2]-first
 with wave.open(str(wav)) as w:
  assert w.getsampwidth()==2 and w.getcomptype()=='NONE'
  rate=w.getframerate();channels=w.getnchannels()
  start=max(0,int((first-d['start'])*rate));end=int((stream[-1][2]-d['start'])*rate)
  if end>w.getnframes():raise ValueError('WAV ends before the matched musical stream')
  assert end>start;w.setpos(start);pcm=array.array('h',w.readframes(end-start))
  result['pcm']={'rate':rate,'channels':channels,'window_frames':end-start,'channel_stats':[]}
  for c in range(channels):
   values=pcm[c::channels];mean=statistics.mean(values);blocks=[values[i:i+rate//100] for i in range(0,len(values),rate//100)]
   rms=[statistics.pstdev(b) for b in blocks if b]
   result['pcm']['channel_stats'].append({'channel':c,'dc_mean':mean,'ac_rms':statistics.pstdev(values),
    'peak':max(abs(v) for v in values),'clipped_fraction':sum(abs(v)>=32767 for v in values)/len(values),
    'quiet_10ms_blocks':sum(v<2 for v in rms),'blocks':len(rms)})
 result['maximum_ceiling_quantization_seconds']=max(((e['sample']+734)//735*735-e['sample'])/44100 for e in song['writes'])
 result['wav_sha256']=hashlib.sha256(wav.read_bytes()).hexdigest()
 return result

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('track',type=Path);p.add_argument('capture',type=Path);p.add_argument('wav',type=Path);a=p.parse_args()
 print(json.dumps(analyze(a.track,a.capture,a.wav),indent=2))
