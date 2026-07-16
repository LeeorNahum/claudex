@echo off
setlocal enabledelayedexpansion
set "SCRIPT_DIR=%~dp0"

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

REM Clear any stray real credentials first so nothing outranks the proxy override.
set ANTHROPIC_API_KEY=
set OPENAI_API_KEY=
set CLAUDE_CODE_OAUTH_TOKEN=

set ANTHROPIC_BASE_URL=http://127.0.0.1:8317
set ANTHROPIC_AUTH_TOKEN=!TOKEN!
REM Force subagents onto gpt-5.6-sol too. Without this, a subagent that
REM defaults to a real Anthropic model (e.g. claude-opus-4-8) gets a 502
REM from the proxy, since it only ever authenticates Codex/OpenAI models.
set CLAUDE_CODE_SUBAGENT_MODEL=gpt-5.6-sol
set CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=1
set CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=3
REM Claude Code's own context/compaction defaults are tuned for Anthropic's
REM real models, not an arbitrary swapped-in one, so it can compact at the
REM wrong point without this. 372000 matches gpt-5.6-sol's real context
REM window; re-check this if the model changes.
set CLAUDE_CODE_MAX_CONTEXT_TOKENS=372000
set CLAUDE_CODE_AUTO_COMPACT_WINDOW=372000
set ENABLE_TOOL_SEARCH=false
REM Deliberately no cd here: claude must launch from the caller's actual
REM working directory, not from SCRIPT_DIR. That was the bug.
claude --model gpt-5.6-sol %*
endlocal
