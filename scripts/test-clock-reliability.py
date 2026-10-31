#!/usr/bin/env python3
"""Portable tests for sampler ordering, loss counting and rejected evidence."""
import copy
import json
from pathlib import Path
import runpy
import tempfile
import unittest

analyze = runpy.run_path(str(Path(__file__).with_name('analyze-clock-reliability.py')))['analyze']


class ReliabilityTests(unittest.TestCase):
    def setUp(self):
        self.track = {'samples': 13230, 'writes': [
            {'sample': 0, 'register': 0, 'value': 1},
            {'sample': 13230, 'register': 0, 'value': 2}]}
        events = [{'kind': 'cpu-state', 'seconds': 0, 'halt': 0, 'mask': 0},
                  {'kind': 'schedule', 'seconds': 0, 'pid': 3, 'task': 1}]
        for t,value in [(.01,1),(.31,2),(.311,63)]:
            events += [{'kind':'psg-write','seconds':t-.000001,'address':0xff5e,
                        'data':7 if value==63 else 0,'pid':3},
                       {'kind':'psg-write','seconds':t,'address':0xff5f,'data':value,'pid':3}]
        for t in [0,.1,.2]:
            events.append(self.zone(t,1,0))
        # Deliberately alternate samples before/after servicing the same edge.
        for t,pending in [(.05,0),(.14990,8),(.25,0)]:
            events.append(self.zone(t,2,pending))
        for t in [.04995,.14995,.24995]:
            events += [{'kind':'irq-ack','seconds':t,'data':8},
                       {'kind':'clock-tick','seconds':t+.00002,'data':1}]
        self.data={'start':0,'finish':.4,'interval_us':100,'max_sample_gap':.0001,
                   'droppedEvents':0,'events':sorted(events,key=lambda e:e['seconds'])}

    @staticmethod
    def zone(t,zone,pending):
        return {'kind':'video-zone','seconds':t,'zone':zone,'pending':pending,
                'global':108,'enable':9,'halt':0,'mask':16}

    def run_capture(self,data=None):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'trace.json';path.write_text(json.dumps(data or self.data))
            return analyze(self.track,path)

    def test_ack_before_sample_does_not_invent_loss(self):
        result=self.run_capture()
        self.assertEqual(result['video_edges'],3)
        self.assertEqual(result['clock_ticks'],3)
        self.assertEqual(result['coalesced_edge_states'],{})
        self.assertEqual(result['post_ack_edge_samples_corrected'],2)

    def test_real_extra_edge_is_counted_once(self):
        self.data['events'] += [self.zone(.22,2,8),self.zone(.23,1,8)]
        self.data['events'].sort(key=lambda e:e['seconds'])
        result=self.run_capture()
        self.assertEqual(result['video_edges']-result['irq_acks'],1)
        self.assertEqual(result['coalesced_edge_states'],{'irq_mask_only':1})

    def test_overflow_and_discontinuity_rejected(self):
        for key in ['overflow','discontinuity']:
            data=copy.deepcopy(self.data)
            if key=='overflow':data['droppedEvents']=1
            else:data['events'].append({'kind':'discontinuity','seconds':.4})
            with self.assertRaises(ValueError):self.run_capture(data)

    def test_missing_mute_rejected(self):
        self.data['events']=[e for e in self.data['events'] if e['seconds']<.311]
        with self.assertRaises(ValueError):self.run_capture()

    def test_disabled_video_irq_rejected(self):
        for e in self.data['events']:
            if e['kind']=='video-zone':e['enable']=0
        with self.assertRaises(ValueError):self.run_capture()


if __name__=='__main__':unittest.main()
