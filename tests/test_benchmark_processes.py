#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('benchmark', Path(__file__).resolve().parents[1] / 'scripts/benchmark-processes.py')
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)


class SamplerTests(unittest.TestCase):
    def test_stat_handles_spaces_and_parentheses_in_process_name(self):
        with tempfile.TemporaryDirectory() as temporary:
            proc = Path(temporary)
            (proc / '7').mkdir()
            fields = ['S'] + ['0'] * 21
            fields[11], fields[12], fields[19] = '13', '17', '99'
            (proc / '7/stat').write_text('7 (a ) weird process) ' + ' '.join(fields))
            self.assertEqual(benchmark.stat(7, proc), (99, 30))
            (proc / '7/status').write_text('voluntary_ctxt_switches: 2\n')
            with self.assertRaises(benchmark.InvalidSample):
                benchmark.counters(7, 99, proc=proc)
            (proc / '7/status').write_text('voluntary_ctxt_switches: 2\nnonvoluntary_ctxt_switches: 3\n')
            (proc / '7/smaps_rollup').write_text('Rss: 40 kB\n')
            with self.assertRaises(benchmark.InvalidSample):
                benchmark.counters(7, 99, memory=True, proc=proc)
            with self.assertRaises(benchmark.InvalidSample):
                benchmark.counters(7, 100, proc=proc)

    def run_sample(self, snapshots, reader=None):
        calls = iter(snapshots)
        clock = iter([10.0, 12.0])
        return benchmark.sample('fixture', 2, 7, discover=lambda *_: next(calls),
                                read=reader or (lambda *_: (3, 4, 100, 200)),
                                sleep=lambda _: None, clock=lambda: next(clock))

    def test_pid_start_identity_and_process_set_changes_invalidate_every_boundary(self):
        initial = {7: ('shell', 99)}
        for changed in ({}, {7: ('shell', 100)}, {**initial, 8: ('backend', 1)}):
            for boundary in (1, 2, 3):
                snapshots = [initial] * 4
                snapshots[boundary] = changed
                with self.assertRaises(benchmark.InvalidSample):
                    self.run_sample(snapshots)

    def test_unreadable_memory_never_becomes_zero(self):
        def read(*args):
            if len(args) == 3:
                raise benchmark.InvalidSample('vanished')
            return 3, 4, 0, 0
        with self.assertRaises(benchmark.InvalidSample):
            self.run_sample([{7: ('shell', 99)}] * 4, read)

    def test_stable_sample(self):
        self.assertEqual(self.run_sample([{7: ('shell', 99)}] * 4)[1], {'shell': [100, 200]})


if __name__ == '__main__':
    unittest.main()
