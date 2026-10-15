"""Check real Darwin CPU units against Python's process CPU clock, without an app."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

@unittest.skipUnless(os.uname().sysname == 'Darwin', 'Darwin accounting helper')
class MetricsTests(unittest.TestCase):
    def test_cpu_time_matches_process_clock(self):
        with tempfile.TemporaryDirectory() as folder:
            helper = str(Path(folder) / 'metrics')
            subprocess.run(['clang', '-Wall', '-Wextra', '-Werror', str(Path(__file__).with_name('metrics.c')), '-o', helper], check=True)
            child = subprocess.Popen(['python3', '-u', '-c',
                "import time; print('ready'); input(); start=time.process_time(); "
                "exec('while time.process_time()-start < .2: pass'); "
                "print(time.process_time()-start); input()"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
            try:
                self.assertEqual(child.stdout.readline().strip(), 'ready')
                def sample():
                    return json.loads(subprocess.check_output([helper, str(child.pid)], text=True))[0]
                before = sample()
                child.stdin.write('go\n'); child.stdin.flush()
                expected = float(child.stdout.readline())
                after = sample()
                actual = (after['cpu_ns'] - before['cpu_ns']) / 1e9
                self.assertGreater(actual / expected, .8)
                self.assertLess(actual / expected, 1.2)
                self.assertGreater(after['footprint'], 0)
            finally:
                child.stdin.write('done\n'); child.stdin.flush(); child.stdin.close()
                child.wait(timeout=5); child.stdout.close()
                self.assertEqual(child.returncode, 0)
