#!/usr/bin/env python3
"""Check call pairing and rejection rules with constructed diagnostic evidence."""
import copy
import json
from pathlib import Path
import runpy
import tempfile
import unittest

summarize = runpy.run_path(str(Path(__file__).with_name('summarize-scheduling-calls.py')))['summarize']

class CallTests(unittest.TestCase):
    def setUp(self):
        self.data = {'droppedEvents': 0, 'finish': 2, 'config': {
            'base': 100, 'calls': [{'label': 'Sleep', 'offset': 10}]},
            'events': [
                {'kind': 'process-sample', 'seconds': 0, 'queue': 'sleep', 'priority': 128},
                self.call('call-enter', 0, 110),  # Prefetch before IRQ; not executed.
                self.call('call-enter', .1, 111),
                {'kind': 'process-sample', 'seconds': .2, 'queue': 'active'},
                self.call('call-return', 1.2, 114)]}

    @staticmethod
    def call(kind, seconds, pc):
        return dict(kind=kind, seconds=seconds, pc=pc, pid=3, label='Sleep',
                    x=2, y=0, cc=0)

    def run_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)/'capture.json'
            p.write_text(json.dumps(self.data))
            return summarize(p)

    def test_prefetch_and_queue_accounting(self):
        result = self.run_data()
        self.assertEqual(result['discarded_nonexecuted_prefetches'], 1)
        self.assertEqual(result['calls']['Sleep']['count'], 1)
        span = result['longest_calls'][0]
        self.assertAlmostEqual(span['duration'], 1.1)
        self.assertAlmostEqual(span['sampled_queue_seconds']['sleep'], .1)
        self.assertAlmostEqual(span['sampled_queue_seconds']['ready'], 1)

    def test_reject_incomplete_or_nested(self):
        original = copy.deepcopy(self.data)
        for error in ['overflow', 'discontinuity', 'nested']:
            self.data = copy.deepcopy(original)
            if error == 'overflow': self.data['droppedEvents'] = 1
            elif error == 'discontinuity': self.data['events'].append({'kind':'discontinuity'})
            else: self.data['events'].insert(3, self.call('call-enter', .15, 111))
            with self.assertRaises(ValueError): self.run_data()

    def test_unfinished_call_is_visible(self):
        self.data['events'].pop()
        self.assertEqual(self.run_data()['unfinished_calls'], 1)

if __name__ == '__main__':
    unittest.main()
