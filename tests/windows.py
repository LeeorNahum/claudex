import argparse
import base64
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest
import urllib.request
from shell_execute import shell_execute

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--installed', action='store_true')
parser.add_argument('--unc')
options, rest = parser.parse_known_args()
MODELS = ['gpt-6-astra', 'gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna', 'k3']


class Catalog(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({'data': [{'id': value} for value in MODELS]}).encode())

    def log_message(self, *args):
        pass


class Launchers(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = os.environ.copy()
        cls.temp = tempfile.TemporaryDirectory(prefix='claudex é ')
        cls.base = Path(cls.temp.name)
        cls.bin = cls.base / 'bin & ! % 日本'
        cls.cwd = cls.base / 'work & ! % é'
        cls.bin.mkdir()
        cls.cwd.mkdir()
        cls.capture = cls.base / 'capture.json'
        cls.ps = shutil.which('powershell.exe')
        cls.pwsh = shutil.which('pwsh.exe')
        source = Path(os.environ['USERPROFILE']) / '.local/bin' if options.installed else ROOT / 'dist'
        shutil.copy2(source / 'claudex.exe', cls.bin / 'claudex.exe')
        shutil.copy2(ROOT / 'claudex.cmd', cls.bin / 'claudex.cmd')
        shutil.copy2(Path(os.environ['USERPROFILE']) / '.local/bin/claudexyolo.exe', cls.bin / 'claudexyolo.exe')
        compiler = Path(os.environ['SystemRoot']) / 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
        subprocess.run([str(compiler), '/nologo', '/warnaserror+', '/reference:System.Web.Extensions.dll', '/out:' + str(cls.bin / 'claude.exe'), str(ROOT / 'tests/probe.cs')], check=True)
        cls.server = None
        cls.models = MODELS
        if options.installed:
            token = (Path(os.environ['USERPROFILE']) / '.local/share/claudex/claudex-token.txt').read_text().strip()
            request = urllib.request.Request('http://127.0.0.1:8317/v1/models', headers={'Authorization': 'Bearer ' + token})
            with urllib.request.urlopen(request, timeout=5) as response:
                cls.models = [item['id'] for item in json.load(response)['data']]
        if not options.installed:
            cls.server = http.server.ThreadingHTTPServer(('127.0.0.1', 8317), Catalog)
            threading.Thread(target=cls.server.serve_forever, daemon=True).start()
            os.environ['USERPROFILE'] = str(cls.base)
            data = cls.base / '.local/share/claudex'
            data.mkdir(parents=True)
            for filename in ('cli-proxy-api.exe', 'config.yaml', 'claudex-token.txt'):
                (data / filename).write_text('test-only')
        os.environ['PATH'] = str(cls.bin)
        os.environ['CLAUDEX_CAPTURE'] = str(cls.capture)
        os.environ['CLAUDEX_TEST_LITERAL'] = 'EXPANDED'
        for key in ('ANTHROPIC_API_KEY', 'OPENAI_API_KEY', 'CLAUDE_CODE_OAUTH_TOKEN'):
            os.environ[key] = 'test-only'
        cls.evidence = []

    @classmethod
    def tearDownClass(cls):
        if cls.server:
            cls.server.shutdown()
            cls.server.server_close()
        os.environ.clear()
        os.environ.update(cls.original)
        (ROOT / 'dist' / ('installed-tests.json' if options.installed else 'tests.json')).write_text(json.dumps(cls.evidence, ensure_ascii=False, indent=2), encoding='utf-8')
        cls.temp.cleanup()

    def capture_result(self, code, expected, model='gpt-6-astra', cwd=None):
        self.assertEqual(code, 37)
        result = json.loads(self.capture.read_text(encoding='utf-8-sig'))
        self.assertEqual(result['argv'], expected)
        self.assertEqual(result['cwd'], str(cwd or self.cwd))
        self.assertEqual(result['env']['CLAUDE_CODE_SUBAGENT_MODEL'], model)
        context = '1050000' if model == 'gpt-6-astra' else '1048576' if model == 'k3[1m]' else '262144' if model == 'k3' else '372000'
        self.assertEqual(result['env']['CLAUDE_CODE_MAX_CONTEXT_TOKENS'], context)
        self.assertTrue(result['credentialsCleared'])
        self.evidence.append(result)
        self.capture.unlink()

    def test_arguments_and_directories(self):
        cases = [[], [''], ['first', '', 'third', ''], ['two words', 'é日本', 'a"b', 'ends \\'],
                 ['a&b|c<d>e^f', '%CLAUDEX_TEST_LITERAL%', '!literal!', '$x;`'],
                 ['--', '--model', 'literal-model-value'], ['tab\there', 'line\nfeed'], ['x' * 8192]]
        for command in ('claudex', 'claudexyolo'):
            for args in cases:
                for shell in (False, True):
                    exe = self.bin / (command + '.exe')
                    code = shell_execute(exe, subprocess.list2cmdline(args), self.cwd) if shell else subprocess.run([str(exe), *args], cwd=self.cwd, capture_output=True, timeout=15).returncode
                    self.capture_result(code, ['--model', 'gpt-6-astra'] + (['--dangerously-skip-permissions'] if command.endswith('yolo') else []) + args)

    def test_explicit_model(self):
        for command in ('claudex', 'claudexyolo'):
            permission = ['--dangerously-skip-permissions'] if command.endswith('yolo') else []
            for model in ('gpt-6-astra', 'gpt-5.6-terra', 'k3[1m]'):
                if model.removesuffix('[1m]') not in self.models:
                    continue
                for style in ('positional', 'flag', 'equals'):
                    selection = [model] if style == 'positional' else ['--model', model] if style == 'flag' else ['--model=' + model]
                    args = [*selection, '-p', 'two "quoted" words', '', '%CLAUDEX_TEST_LITERAL%']
                    result = subprocess.run([str(self.bin / (command + '.exe')), *args], cwd=self.cwd, capture_output=True, timeout=15)
                    expected = ['--model', model, *permission, *args[1:]] if style == 'positional' else [*permission, *args]
                    self.capture_result(result.returncode, expected, model)

    def test_shells(self):
        for command in ('claudex', 'claudexyolo'):
            prefix = ['--model', 'gpt-6-astra'] + (['--dangerously-skip-permissions'] if command.endswith('yolo') else [])
            raw = command + ' "two words" "" "a&b|c^d" --flag'
            result = subprocess.run('"' + os.environ['COMSPEC'] + '" /d /v:off /s /c "' + raw + '"', cwd=self.cwd, capture_output=True, timeout=15)
            self.capture_result(result.returncode, prefix + ['two words', '', 'a&b|c^d', '--flag'])
            for ps in (self.ps, self.pwsh):
                if not ps:
                    continue
                modern = ps == self.pwsh
                args = ['two words', 'a&b|c^d', '%CLAUDEX_TEST_LITERAL%', '--flag'] + (['', 'a"b'] if modern else [])
                script = ("$PSNativeCommandArgumentPassing='Standard'; " if modern else '') + command + ' ' + ' '.join("'" + arg + "'" for arg in args) + '; exit $LASTEXITCODE'
                result = subprocess.run([ps, '-NoProfile', '-EncodedCommand', base64.b64encode(script.encode('utf-16-le')).decode()], cwd=self.cwd, capture_output=True, timeout=15)
                self.capture_result(result.returncode, prefix + args)

    def test_native_and_missing_models(self):
        for args in (['sonnet'], ['--model', 'opus'], ['gpt-does-not-exist'], ['--model']):
            result = subprocess.run([str(self.bin / 'claudex.exe'), *args], cwd=self.cwd, capture_output=True, timeout=15)
            self.assertEqual(result.returncode, 1)
            self.assertFalse(self.capture.exists())

    def test_positional_model_with_explicit_override(self):
        args = ['gpt-6-astra', '--model', 'gpt-5.6-terra', '', 'a"b', '%CLAUDEX_TEST_LITERAL%']
        for command in ('claudex', 'claudexyolo'):
            result = subprocess.run([str(self.bin / (command + '.exe')), *args], cwd=self.cwd, capture_output=True, timeout=15)
            self.capture_result(result.returncode, (['--dangerously-skip-permissions'] if command.endswith('yolo') else []) + args[1:], 'gpt-5.6-terra')

    def test_checkout_compatibility_entry(self):
        # The checkout's .cmd must use installed state, not look for config in the checkout.
        if not options.installed:
            self.skipTest('Requires installation')
        command = '"' + os.environ['COMSPEC'] + '" /d /v:off /s /c "claudex --version"'
        result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=15)
        self.capture_result(result.returncode, ['--model', 'gpt-6-astra', '--version'], cwd=ROOT)

    def test_renamed_launcher_and_relative_cli(self):
        renamed = self.cwd / 'claude.exe'
        shutil.copy2(self.bin / 'claudex.exe', renamed)
        result = subprocess.run([str(renamed)], cwd=self.cwd, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b'recursion', result.stderr)
        previous = os.environ['PATH']
        try:
            os.environ['PATH'] = '.;C:relative;\\relative'
            result = subprocess.run([str(self.bin / 'claudex.exe')], cwd=self.cwd, capture_output=True, timeout=15)
            self.assertEqual(result.returncode, 1)
            self.assertIn(b'absolute PATH', result.stderr)
        finally:
            os.environ['PATH'] = previous

    @unittest.skipUnless(options.unc, 'Pass --unc with an existing UNC directory')
    def test_unc(self):
        for command in ('claudex', 'claudexyolo'):
            args = ['', 'UNC & % ! é']
            code = shell_execute(self.bin / (command + '.exe'), subprocess.list2cmdline(args), options.unc)
            self.capture_result(code, ['--model', 'gpt-6-astra'] + (['--dangerously-skip-permissions'] if command.endswith('yolo') else []) + args, cwd=options.unc)

    @unittest.skipUnless(options.installed, 'Requires installation')
    def test_app_paths(self):
        for command in ('claudex', 'claudexyolo'):
            code = shell_execute(command, '"" "two words" "%CLAUDEX_TEST_LITERAL%"', self.cwd)
            self.capture_result(code, ['--model', 'gpt-6-astra'] + (['--dangerously-skip-permissions'] if command.endswith('yolo') else []) + ['', 'two words', '%CLAUDEX_TEST_LITERAL%'])


if __name__ == '__main__':
    unittest.main(argv=[__file__, *rest], verbosity=2)
