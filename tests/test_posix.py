"""POSIX launcher parity without contacting providers."""
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
git_bash = Path(os.environ.get('ProgramFiles', 'C:/Program Files')) / 'Git/bin/bash.exe'
shell = str(git_bash) if git_bash.exists() else shutil.which('sh')
if not shell:
    raise SystemExit('sh or Git Bash is required')
for script in ('claudex.sh', 'setup.sh'):
    subprocess.run([shell, '-n', str(root / script)], check=True)

with tempfile.TemporaryDirectory(prefix='claudex-posix-') as temporary:
    base = Path(temporary)
    install = base / 'install space'
    cwd = base / 'work space'
    install.mkdir()
    cwd.mkdir()
    shutil.copy2(root / 'claudex.sh', install / 'claudex.sh')
    for name in ('config.yaml', 'claudex-token.txt', 'cli-proxy-api'):
        (install / name).write_text('test-only')
    catalog = json.dumps({'data': [{'id': x} for x in ('gpt-6-astra', 'gpt-5.6-terra', 'k3')]})
    (install / 'curl').write_text("#!/bin/sh\nprintf '%s' '" + catalog + "'\n")
    (install / 'claude').write_text("#!/bin/sh\nprintf '%s\\0' \"$PWD\" \"$CLAUDE_CODE_SUBAGENT_MODEL\" \"$CLAUDE_CODE_MAX_CONTEXT_TOKENS\" \"$@\"\nexit 37\n")
    for name in ('curl', 'claude'):
        (install / name).chmod(0o755)
    # Pass the mock PATH as a shell positional value, never interpolate arguments into code.
    runner = base / 'run.sh'
    runner.write_text('#!/bin/sh\nPATH="$1:/usr/bin:/bin"\nexport PATH\nshift\nexec sh "$@"\n')
    normalized = subprocess.check_output([shell, '-c', 'pwd'], cwd=cwd).decode().strip()
    mock_bin = subprocess.check_output([shell, '-c', 'pwd'], cwd=install).decode().strip()
    count = 0
    for permission in ([], ['--dangerously-skip-permissions']):
        for model in ('gpt-6-astra', 'gpt-5.6-terra', 'k3[1m]'):
            for style in ('default', 'positional', 'flag'):
                if style == 'default' and model != 'gpt-6-astra':
                    continue
                selection = [] if style == 'default' else [model] if style == 'positional' else ['--model', model]
                tail = ['two words', '', 'a"b', 'a&b|c<d>e^f', '%literal%', '!literal!', '--', '--model']
                args = [*permission, *selection, *tail]
                runner.write_text('#!/bin/sh\nPATH=' + shlex.quote(mock_bin + ':/usr/bin:/bin') + '\nexport PATH\nexec sh ' + shlex.quote(mock_bin + '/claudex.sh') + ' ' + shlex.join(args) + '\n')
                result = subprocess.run([shell, str(runner)], cwd=cwd, capture_output=True)
                assert result.returncode == 37, result.stderr
                actual = result.stdout.decode().split('\0')[:-1]
                expected = [*permission, *selection, *tail] if style == 'flag' else ['--model', model, *permission, *tail]
                context = '1050000' if model == 'gpt-6-astra' else '1048576' if model == 'k3[1m]' else '372000'
                assert actual == [normalized, model, context, *expected], (actual, expected)
                count += 1
    print(f'PASS: shell syntax and {count} POSIX argv/cwd/model cases')
