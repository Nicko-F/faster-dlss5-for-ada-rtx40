import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('report', ROOT/'tools/report_results.py')
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


class ResultsTest(unittest.TestCase):
    def test_per_run_reciprocal_and_missing_reference(self):
        data = dict(nr=[], gameRuns=[dict(resolution='test', fps=dict(
            original=[100, 200], community=[50, 100], optimized=[100, 100]))],
            externalReference=dict(renderTimeMs=dict(test=None)))
        _, rows = report.calculate(data)
        self.assertEqual(rows[0]['communityAddedMs'], 7.5)
        self.assertEqual(rows[0]['optimizedAddedMs'], 2.5)
        self.assertIsNone(rows[0]['belowReferencePercent'])

    def test_export_keeps_methods_and_all_repeats(self):
        data = json.loads((ROOT/'benchmarks/results-2026-09-10.json').read_text(encoding='utf-8'))
        nr, game = report.calculate(data)
        self.assertEqual(len(nr), 5)
        self.assertEqual(len(game), 3)
        self.assertEqual(len(data['nr']), 10)
        self.assertTrue(all(len(v) == 2 for r in data['gameRuns'] for v in r['fps'].values()))
        self.assertFalse(data['controlledCrossGpuComparison'])
        self.assertAlmostEqual(game[2]['savedMs'], 1.29787076299977)


if __name__ == '__main__':
    unittest.main()
