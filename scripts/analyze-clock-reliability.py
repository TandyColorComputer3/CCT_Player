#!/usr/bin/env python3
"""Analyze bounded host sampler captures; CPU intervals are sampled estimates.

Supply a zero-extra-loop fixture and capture. Exact ordered PSG pairs delimit
playback. Loss attribution counts coalesced video edges, not elapsed HALT as
lost ticks. Boundary groups and sampled states have explicit uncertainty.
"""
import argparse
import bisect
import collections
import json
from pathlib import Path
import runpy


def analyze(track, path):
    if not track['writes'] or track['writes'][0]['sample']!=0:
        raise ValueError('clock-domain analysis requires a sample-zero first write')
    data = json.loads(path.read_text())
    events = data['events']
    if data['droppedEvents'] or data.get('resetCount',0) or any(e['kind'] == 'discontinuity' for e in events):
        raise ValueError('incomplete capture')
    if data['max_sample_gap']>data['interval_us']/1000000*1.01:
        raise ValueError('sampling gap exceeds configured resolution')
    if any(a['seconds']>b['seconds'] for a,b in zip(events,events[1:])):
        raise ValueError('nonmonotonic capture')
    routines = runpy.run_path(str(Path(__file__).with_name('summarize-psg-repeats.py')))
    pairs = routines['pairs'](events)
    expected = [(w['register'], w['value']) for w in track['writes']]
    first = next((i for i in range(len(pairs)-len(expected))
                 if [(r,v) for r,v,t in pairs[i:i+len(expected)]] == expected
                 and pairs[i+len(expected)][:2] == (7,63)),None)
    if first is None:
        raise ValueError('no complete ordered stream followed by mute')
    segment = pairs[first:first+len(expected)]
    start, end = segment[0][2], pairs[first+len(expected)][2]
    inside = lambda e: start <= e['seconds'] < end
    edges=[]; previous=None
    for e in events:
        if e['kind']=='video-zone':
            if previous==1 and e['zone']==2:
                if not e['global']&32 or not e['enable']&8:
                    raise ValueError('video IRQ disabled at sampled generation')
                edges.append(e)
            previous=e['zone']
    acks=[e['seconds'] for e in events if e['kind']=='irq-ack' and e['data']&8]
    ticks=[e['seconds'] for e in events if e['kind']=='clock-tick']
    edge_times=[e['seconds'] for e in edges]
    # An edge can be serviced between the transition and the next sample.
    # A cleared pending bit plus an ACK within one sampling interval identifies
    # that ordering; place it just before that ACK for grouping only. Retain
    # original timestamps for playback-boundary counts (one-edge uncertainty).
    grouped_times=[]; corrected=0
    for e in edges:
        t=e['seconds']; i=bisect.bisect_right(acks,t)-1
        if not e['pending']&8 and i>=0 and t-acks[i]<=data['max_sample_gap']+1e-9:
            t=acks[i]-1e-9; corrected+=1
        grouped_times.append(t)
    bins=collections.defaultdict(float)
    state={'halt':0,'mask':0}; schedule={'pid':None,'task':None}; last=data['start']
    player=next((e.get('pid') for e in events if e['kind']=='psg-write' and abs(e['seconds']-start)<.0001),None)
    for e in events + [{'kind':'end','seconds':data['finish']}]:
        dt=max(0,min(end,e['seconds'])-max(start,last))
        if dt:
            h=bool(state['halt']); masked=bool(state['mask']&16)
            bins['halt_and_irq_mask' if h and masked else 'halt_only' if h else 'irq_mask_only' if masked else 'neither']+=dt
            if state['mask']&64: bins['firq_mask']+=dt
            if not h and player is not None and schedule['pid']==player:
                bins['player_user' if schedule['task']==1 else 'player_system']+=dt
        if e['kind']=='cpu-state': state=e
        if e['kind']=='schedule': schedule=e
        last=e['seconds']
    # Count extra edges in fully bounded acknowledgement groups. First edge
    # latches pending; each subsequent edge coalesces. Sampled attribution is
    # the state at each extra edge, not an assertion about exclusive causality.
    loss=collections.Counter(); grouped_edges=0; groups=0
    for a,b in zip(acks,acks[1:]):
        if a<start or b>end: continue
        group=edges[bisect.bisect_right(grouped_times,a):bisect.bisect_right(grouped_times,b)]
        grouped_edges+=len(group);groups+=1
        for e in group[1:]:
            h=bool(e['halt']); mask=bool(e['mask']&16)
            loss['halt_and_irq_mask' if h and mask else 'halt_only' if h else 'irq_mask_only' if mask else 'neither_or_sampling_boundary']+=1
    count=lambda times:bisect.bisect_left(times,end)-bisect.bisect_left(times,start)
    calls_before=[e['seconds'] for e in events if e['kind']=='clock-call'
                  and e.get('pid')==player and e['seconds']<=start]
    epoch=calls_before[-1] if calls_before else start
    origin_tick=bisect.bisect_right(ticks,epoch)
    residual=[]; cumulative=[]; local=[]
    for i,(r,v,t) in enumerate(segment):
        target=(track['writes'][i]['sample']-track['writes'][0]['sample'])/44100
        cumulative.append(t-start-target)
        residual.append((bisect.bisect_right(ticks,t)-origin_tick)/60-target)
        if i and track['writes'][i]['sample']!=track['writes'][i-1]['sample']:
            local.append(t-segment[i-1][2]-(track['writes'][i]['sample']-track['writes'][i-1]['sample'])/44100)
    latency=[t-acks[bisect.bisect_right(acks,t)-1] for t in ticks if start<=t<end and bisect.bisect_right(acks,t)]
    visits=[e['seconds'] for e in events if inside(e) and e['kind']=='schedule'
            and e['pid']==player and e['task']==1]
    tick_owners=[e for e in events if inside(e) and e['kind']=='clock-tick' and 'pid' in e]
    longest={}
    for name,predicate in [('halt',lambda e:bool(e['halt'])),
                           ('irq_mask',lambda e:bool(e['mask']&16)),
                           ('firq_mask',lambda e:bool(e['mask']&64))]:
        began=None; maximum=0
        for e in events+[{'kind':'cpu-state','seconds':data['finish'],'halt':0,'mask':0}]:
            if e['kind']!='cpu-state':continue
            if predicate(e):
                if began is None:began=e['seconds']
            elif began is not None:
                maximum=max(maximum,max(0,min(end,e['seconds'])-max(start,began)))
                began=None
        longest[name]=maximum
    return dict(capture=str(path),interval_us=data['interval_us'],max_sample_gap=data['max_sample_gap'],
      first_write=start,mute=end,pairs=len(segment),duration=end-start,
      duration_error_percent=100*((end-start+track['writes'][0]['sample']/44100)/(track['samples']/44100)-1),
      video_edges=count(edge_times),irq_acks=count(acks),clock_ticks=count(ticks),
      clock_calls=(sum(e['kind']=='clock-call' and inside(e) for e in events)
                   if data.get('clock_calls_observed') or any(e['kind']=='clock-call' for e in events) else None),
      fdc_commands=sum(e['kind']=='fdc-command' and inside(e) for e in events),
      clock_deficit_seconds=end-start-count(ticks)/60,
      serviced_lateness_epoch=('initial clock snapshot' if calls_before else 'first PSG write; startup phase excluded'),
      epoch_to_first_write_seconds=start-epoch,
      max_ack_to_tick_seconds=max(latency),
      max_local_lateness_seconds=max(local,default=0),max_accumulated_lateness_seconds=max(cumulative),
      max_serviced_clock_lateness_seconds=max(residual),min_serviced_clock_error_seconds=min(residual),
      max_player_user_entry_gap_seconds=max((b-a for a,b in zip(visits,visits[1:])),default=None),
      ticks_with_other_process_current=(sum(e['pid'] not in (0,player) for e in tick_owners) if tick_owners else None),
      sampled_seconds=dict(bins),player_pid=player,
      longest_sampled_interval_seconds=longest,
      complete_ack_groups=groups,edges_in_complete_ack_groups=grouped_edges,coalesced_edge_states=dict(loss),
      post_ack_edge_samples_corrected=corrected,
      final_mpi=next((e['data'] for e in reversed(events) if e['kind']=='mpi-write'),None))


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('track',type=Path);p.add_argument('captures',type=Path,nargs='+');args=p.parse_args()
    read=runpy.run_path(str(Path(__file__).with_name('analyze-psg-timing.py')))['read_track']
    _,track=read(args.track,0)
    print(json.dumps([analyze(track,path) for path in args.captures],indent=2))

if __name__=='__main__':main()
