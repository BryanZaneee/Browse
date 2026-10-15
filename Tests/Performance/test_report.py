import unittest
from run import summary, content_pids, usage_delta
class ReportTests(unittest.TestCase):
    def test_summary_rejects_missing_or_invalid_samples(self):
        for values in ([], [float('nan')], [-1], [float('inf')]):
            with self.assertRaises(ValueError): summary(values)
        self.assertEqual(summary([1, 9, 3]), {'median': 3, 'min': 1, 'max': 9, 'n': 3})
    def test_only_attributed_unique_processes(self):
        self.assertEqual(content_pids([{'process': 0}, {'process': 7}, {'process': 7}, {'process': 1}, {}], 1), [7])
    def test_pid_reuse_is_not_idle(self):
        first = [{'pid': 7, 'start': 1, 'cpu_ns': 10, 'footprint': 100}]
        last = [{'pid': 7, 'start': 2, 'cpu_ns': 20, 'footprint': 200}]
        self.assertIn('unavailable', usage_delta(first, last, 1))
        last[0]['start'] = 1; last[0]['cpu_ns'] = 500000010
        self.assertEqual(usage_delta(first, last, 1)['cpu_percent_one_core'], 50)
    def test_accounting_error_is_not_zero(self):
        self.assertIn('unavailable', usage_delta([{'pid': 7, 'error': 3}], [], 1))
if __name__ == '__main__': unittest.main()
