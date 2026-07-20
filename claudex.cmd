@echo off
setlocal enabledelayedexpansion
set "SCRIPT_DIR=%~dp0"

REM claudex is Claude Code plus compatibility for other models and providers.
REM Bare claudex (or a native Claude model/alias) launches Claude Code untouched.
REM A canonical proxy model id (gpt-*, k3, kimi-*) routes that session through
REM the local CLIProxyAPI instead. One session speaks to exactly one backend.
set "MODE=native"
set "MODEL="
set "ARGS="
set "FIRST=%~1"
if not defined FIRST goto args_done
if "!FIRST:~0,1!"=="-" goto args_done
for %%m in (sonnet opus haiku fable default opusplan) do if /i "!FIRST!"=="%%m" (set "MODEL=!FIRST!"& goto consume)
if "!FIRST:~0,7!"=="claude-" (set "MODEL=!FIRST!"& goto consume)
if "!FIRST:~0,4!"=="gpt-" (set "MODE=proxy"& set "MODEL=!FIRST!"& goto consume)
if "!FIRST:~0,5!"=="kimi-" (set "MODE=proxy"& set "MODEL=!FIRST!"& goto consume)
if "!FIRST!"=="k3" (set "MODE=proxy"& set "MODEL=!FIRST!"& goto consume)
if "!FIRST!"=="k3[1m]" (set "MODE=proxy"& set "MODEL=!FIRST!"& goto consume)
REM Not a model id: treat it as a prompt/argument for Claude Code as-is.
goto args_done

:consume
REM The model argument is consumed; rebuild the remaining args for claude.
:collect
shift
if "%~1"=="" goto args_done
set ARGS=!ARGS! %1
goto collect

:args_done
if "!MODE!"=="proxy" goto proxy_mode

REM Native mode: plain Claude Code with the normal saved login. Clear stray
REM non-Anthropic credentials so nothing hijacks the native session, but leave
REM the real Claude auth surface completely untouched.
set OPENAI_API_KEY=
if defined MODEL (
  claude --model !MODEL!!ARGS!
) else (
  claude %*
)
goto end

:proxy_mode
if not exist "%SCRIPT_DIR%cli-proxy-api.exe" (
  echo claudex: not set up yet. Run setup.cmd first.
  exit /b 1
)
if not exist "%SCRIPT_DIR%config.yaml" (
  echo claudex: not set up yet. Run setup.cmd first.
  exit /b 1
)
if not exist "%SCRIPT_DIR%claudex-token.txt" (
  echo claudex: not set up yet. Run setup.cmd first.
  exit /b 1
)
set /p TOKEN=<"%SCRIPT_DIR%claudex-token.txt"

REM Curl config file keeps the bearer token out of the process command line
REM (tasklist/Process Explorer show argv to any local user, not config-file contents).
(echo header = "Authorization: Bearer !TOKEN!")>"%SCRIPT_DIR%curl-auth.cfg"

curl.exe -fsS -K "%SCRIPT_DIR%curl-auth.cfg" http://127.0.0.1:8317/v1/models >nul 2>&1
if errorlevel 1 (
  echo claudex: starting the local proxy...
  REM -WorkingDirectory sets the NEW cli-proxy-api.exe process's own cwd, so its
  REM relative auth-dir in config.yaml still resolves correctly, without touching
  REM this script's own cwd (which must stay wherever the caller actually is).
  powershell -NoProfile -Command "Start-Process -FilePath '%SCRIPT_DIR%cli-proxy-api.exe' -ArgumentList '-config','%SCRIPT_DIR%config.yaml' -WindowStyle Hidden -WorkingDirectory '%SCRIPT_DIR%' -RedirectStandardOutput '%SCRIPT_DIR%proxy.log' -RedirectStandardError '%SCRIPT_DIR%proxy.err.log'"
  set READY=0
  for /l %%i in (1,1,30) do (
    if "!READY!"=="0" (
      curl.exe -fsS -K "%SCRIPT_DIR%curl-auth.cfg" http://127.0.0.1:8317/v1/models >nul 2>&1
      if not errorlevel 1 set READY=1
      REM ping as a sleep: timeout.exe refuses to run under redirected stdin
      REM even with /nobreak, which silently breaks this loop under
      REM automation. ping has no such requirement and no PATH-shadowing risk.
      if "!READY!"=="0" "%SystemRoot%\System32\ping.exe" -n 2 127.0.0.1 >nul
    )
  )
  if "!READY!"=="0" (
    echo claudex: proxy did not become ready in time. Check proxy.log and proxy.err.log in
    echo %SCRIPT_DIR% for errors, or run "cli-proxy-api.exe -codex-login" again if the OAuth credential expired.
    exit /b 1
  )
)

REM Preflight: only launch against a model the proxy actually has credentials
REM for. This turns the proxy's opaque "502 unknown provider" into a clear,
REM actionable error before any session starts.
curl.exe -fsS -K "%SCRIPT_DIR%curl-auth.cfg" -o "%TEMP%\claudex-models.json" http://127.0.0.1:8317/v1/models 2>nul
REM The [1m] long-context suffix is Claude Code notation; the catalog lists the base id.
set "CATALOG_ID=!MODEL!"
if "!MODEL!"=="k3[1m]" set "CATALOG_ID=k3"
powershell -NoProfile -Command "$ids = (Get-Content '%TEMP%\claudex-models.json' -Raw | ConvertFrom-Json).data.id; if ($ids -contains '!CATALOG_ID!') { exit 0 } else { exit 1 }"
if errorlevel 1 (
  echo claudex: the local proxy has no credentials for model '!MODEL!'.
  if "!CATALOG_ID!"=="k3" (
    echo claudex: Kimi needs a one-time login: cd /d "%SCRIPT_DIR%" ^&^& cli-proxy-api.exe -kimi-login
  ) else if "!MODEL:~0,5!"=="kimi-" (
    echo claudex: Kimi needs a one-time login: cd /d "%SCRIPT_DIR%" ^&^& cli-proxy-api.exe -kimi-login
  ) else (
    echo claudex: if the Codex OAuth credential expired, re-run: cd /d "%SCRIPT_DIR%" ^&^& cli-proxy-api.exe -codex-login
  )
  echo claudex: models the proxy currently serves:
  powershell -NoProfile -Command "(Get-Content '%TEMP%\claudex-models.json' -Raw | ConvertFrom-Json).data.id | ForEach-Object { '  ' + $_ }"
  exit /b 1
)

REM Clear any stray real credentials first so nothing outranks the proxy override.
set ANTHROPIC_API_KEY=
set OPENAI_API_KEY=
set CLAUDE_CODE_OAUTH_TOKEN=

set ANTHROPIC_BASE_URL=http://127.0.0.1:8317
set ANTHROPIC_AUTH_TOKEN=!TOKEN!
REM Pin every internal model tier to the selected model. Without these, Claude
REM Code's subagents and background calls default to real Anthropic ids
REM (e.g. claude-opus-4-8, claude-haiku-4-5) and get a 502 from the proxy,
REM since it only holds Codex/Kimi credentials, never Anthropic ones.
set CLAUDE_CODE_SUBAGENT_MODEL=!MODEL!
set ANTHROPIC_DEFAULT_HAIKU_MODEL=!MODEL!
set ANTHROPIC_DEFAULT_SONNET_MODEL=!MODEL!
set ANTHROPIC_DEFAULT_OPUS_MODEL=!MODEL!
set ANTHROPIC_DEFAULT_FABLE_MODEL=!MODEL!
REM Let /model list the proxy's real catalog, so switching between proxy-served
REM models mid-session works and unregistered models never appear.
set CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1
set CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=1
set CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=3
set ENABLE_TOOL_SEARCH=false
REM Gentle rate-limit smoothing: upstream quotas are account-level and shared
REM by every claudex terminal, so parallel sessions will sometimes 429. Retry
REM with exponential backoff until the quota window frees up, instead of
REM erroring out the whole thread.
set CLAUDE_CODE_MAX_RETRIES=15
set CLAUDE_CODE_RETRY_WATCHDOG=1
REM Claude Code's own context/compaction defaults are tuned for Anthropic's
REM real models, not an arbitrary swapped-in one, so it can compact at the
REM wrong point without this. Values track each supported model's real window;
REM unknown ids keep Claude Code's defaults.
set "CONTEXT_TOKENS="
if "!MODEL:~0,8!"=="gpt-5.6-" set "CONTEXT_TOKENS=372000"
if "!MODEL!"=="k3" set "CONTEXT_TOKENS=262144"
if "!MODEL!"=="k3[1m]" set "CONTEXT_TOKENS=1048576"
if "!MODEL:~0,5!"=="kimi-" set "CONTEXT_TOKENS=262144"
if defined CONTEXT_TOKENS (
  set CLAUDE_CODE_MAX_CONTEXT_TOKENS=!CONTEXT_TOKENS!
  set CLAUDE_CODE_AUTO_COMPACT_WINDOW=!CONTEXT_TOKENS!
)
REM Deliberately no cd here: claude must launch from the caller's actual
REM working directory, not from SCRIPT_DIR. That was the bug.
claude --model !MODEL!!ARGS!

:end
endlocal
