"""Fast runner controls; optional argv[1] is the runner's Nix store path."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

runner = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else Path(__file__).with_name('error-plane-runner.py')
spec = importlib.util.spec_from_file_location('runner', runner)
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)


class RunnerTests(unittest.TestCase):
    def budget(self, env, n=9):
        with patch.object(r.os, 'cpu_count', return_value=8), patch.object(r.os, 'sched_getaffinity', return_value={0, 1, 2, 3}, create=True):
            return r.worker_count(env, n)

    def test_default_affinity(self):
        self.assertEqual(self.budget({}), 4)

    def test_build_budget(self):
        self.assertEqual(self.budget({'NIX_BUILD_CORES': '2'}), 2)
        self.assertEqual(self.budget({'NIX_BUILD_CORES': '0'}), 4)

    def test_explicit_budget(self):
        self.assertEqual(self.budget({'GEN_ERROR_JOBS': '3', 'NIX_BUILD_CORES': '1'}), 3)
        self.assertEqual(self.budget({'GEN_ERROR_JOBS': '99'}, 2), 2)

    def test_invalid_budget_refused(self):
        for value in ('', 'bad', '-1', '1.2', '0'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.budget({'GEN_ERROR_JOBS': value})

    def exercise(self, cells, outcomes, jobs='1', declared=True):
        calls = []
        def evaluate(env, expr):
            if expr == r.LIST:
                return subprocess.CompletedProcess([], 0, json.dumps({'cells': cells, 'declared': declared}), '')
            path = tuple(json.loads(env['GEN_CELL']))
            calls.append(path)
            return subprocess.CompletedProcess([], *outcomes[path])
        out = io.StringIO()
        with patch.dict(os.environ, {'GEN_ERROR_JOBS': jobs}), patch.object(sys, 'argv', ['runner', '/root']), patch.object(r, 'nix_eval', side_effect=evaluate), patch.object(r.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'nix fake\n', '')), contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            result = r.main()
        return result, out.getvalue(), calls

    def test_budget_preserves_every_cell_and_verdict(self):
        cells = [{'path': ['suite', 'test'+str(i)], 'error': i % 2 == 0, 'msg': '^refusal$'} for i in range(12)]
        outcomes = {tuple(c['path']): (1, '', 'error: refusal') if c['error'] else (0, 'true', '') for c in cells}
        serial = self.exercise(cells, outcomes)
        parallel = self.exercise(cells, outcomes, '3')
        self.assertEqual(serial[:2], parallel[:2])
        self.assertEqual(serial[0], 0)
        self.assertCountEqual(parallel[2], [tuple(c['path']) for c in cells])
        self.assertEqual(len(parallel[2]), 12)

    def test_failures_and_signal_never_pass(self):
        cell = {'path': ['test'], 'error': True, 'msg': ''}
        for outcome in ((0, '"NOERROR"', ''), (-9, '', '')):
            self.assertEqual(self.exercise([cell], {('test',): outcome})[0], 1)
        cell['msg'] = '^wanted$'
        self.assertEqual(self.exercise([cell], {('test',): (1, '', 'error: other')})[0], 1)
        cell['error'] = False
        self.assertEqual(self.exercise([cell], {('test',): (0, 'false', '')})[0], 1)

    def test_empty_declared_refuses(self):
        self.assertEqual(self.exercise([], {})[0], 1)
        self.assertEqual(self.exercise([], {}, declared=False)[0], 0)

    def test_message_boundary_unchanged(self):
        self.assertEqual(r.errmsg('error: outer\n       error: refusal\n       more'), 'refusal\nmore')
        self.assertEqual(r.errmsg('error: unexpected validation error: "s"'), 'unexpected validation error: "s"')


if __name__ == '__main__':
    unittest.main()
