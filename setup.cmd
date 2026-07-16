@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

if exist cli-proxy-api.exe (
  echo cli-proxy-api.exe already present, skipping download.
) else (
  echo Downloading CLIProxyAPI...
  for /f "delims=" %%v in ('curl.exe -fsSL "https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest" ^| findstr /r "\"tag_name\""') do set TAGLINE=%%v
  for /f tokens^=4delims^=^" %%v in ("!TAGLINE!") do set TAG=%%v
  if "!TAG!"=="" (
    echo Could not determine the latest CLIProxyAPI release tag. Aborting.
    exit /b 1
  )
  echo Latest release: !TAG!
  curl.exe -fsSL -o cliproxy.zip "https://github.com/router-for-me/CLIProxyAPI/releases/download/!TAG!/CLIProxyAPI_!TAG:v=!_windows_amd64.zip"
  if errorlevel 1 (
    echo Download failed. Check the asset name still matches at:
    echo https://github.com/router-for-me/CLIProxyAPI/releases
    exit /b 1
  )
  REM Extract to a throwaway folder first: the release zip also bundles its
  REM own README.md/README_CN.md/config.example.yaml, which would silently
  REM overwrite this repo's own README.md if extracted directly into cwd.
  if exist _cliproxy_extract rmdir /s /q _cliproxy_extract
  powershell -NoProfile -Command "Expand-Archive -Path 'cliproxy.zip' -DestinationPath '_cliproxy_extract' -Force"
  if not exist _cliproxy_extract\cli-proxy-api.exe (
    echo Extraction failed: cli-proxy-api.exe was not produced. cliproxy.zip was kept for inspection.
    exit /b 1
  )
  move /y _cliproxy_extract\cli-proxy-api.exe . >nul
  rmdir /s /q _cliproxy_extract
  del cliproxy.zip
)

if not exist claudex-token.txt (
  echo Generating a local proxy token...
  for /f "delims=" %%t in ('openssl rand -hex 32 2^>nul') do set TOKEN=%%t
  if "!TOKEN!"=="" (
    echo openssl not found; falling back to a weaker token source.
    set TOKEN=%RANDOM%%RANDOM%%RANDOM%%RANDOM%
  )
  (echo !TOKEN!)>claudex-token.txt
)
set /p TOKEN=<claudex-token.txt

if not exist config.yaml (
  echo Writing config.yaml...
  (
    echo host: "127.0.0.1"
    echo port: 8317
    echo auth-dir: 'auth'
    echo api-keys:
    echo   - "!TOKEN!"
    echo debug: false
  )>config.yaml
)

echo.
echo Setup files are ready. Two things left, both one-time:
echo   1. cli-proxy-api.exe -codex-login   (opens a browser, authenticate with your ChatGPT/Codex account)
echo   2. Then just run claudex.cmd whenever you want Claude Code routed through GPT-5.6 Sol.
echo.
echo Never run -claude-login. It routes your real Claude subscription through a third-party
echo tool, which violates Anthropic's Consumer Terms and has led to real account suspensions.
echo.
echo Config, the local proxy token, and the OAuth credential are all under this folder
echo and are gitignored. Do not commit them.
endlocal
