@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

if not exist cli-proxy-api.exe (
  echo claudex: not set up yet. Run setup.cmd first.
  exit /b 1
)
if not exist config.yaml (
  echo claudex: not set up yet. Run setup.cmd first.
  exit /b 1
)
if not exist claudex-token.txt (
  echo claudex: not set up yet. Run setup.cmd first.
  exit /b 1
)
set /p TOKEN=<claudex-token.txt

REM Curl config file keeps the bearer token out of the process command line
REM (tasklist/Process Explorer show argv to any local user, not config-file contents).
(echo header = "Authorization: Bearer !TOKEN!")>curl-auth.cfg

curl.exe -fsS -K curl-auth.cfg http://127.0.0.1:8317/v1/models >nul 2>&1
if errorlevel 1 (
  echo claudex: starting the local proxy...
  powershell -NoProfile -Command "Start-Process -FilePath '%~dp0cli-proxy-api.exe' -ArgumentList '-config','%~dp0config.yaml' -WindowStyle Hidden -WorkingDirectory '%~dp0' -RedirectStandardOutput '%~dp0proxy.log' -RedirectStandardError '%~dp0proxy.err.log'"
  set READY=0
  for /l %%i in (1,1,30) do (
    if "!READY!"=="0" (
      curl.exe -fsS -K curl-auth.cfg http://127.0.0.1:8317/v1/models >nul 2>&1
      if not errorlevel 1 set READY=1
      REM ping as a sleep: timeout.exe refuses to run under redirected stdin
      REM even with /nobreak, which silently breaks this loop under
      REM automation. ping has no such requirement and no PATH-shadowing risk.
      if "!READY!"=="0" "%SystemRoot%\System32\ping.exe" -n 2 127.0.0.1 >nul
    )
  )
  if "!READY!"=="0" (
    echo claudex: proxy did not become ready in time. Check proxy.log and proxy.err.log in this
    echo folder for errors, or run "cli-proxy-api.exe -codex-login" again if the OAuth credential expired.
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
claude --model gpt-5.6-sol %*
endlocal
