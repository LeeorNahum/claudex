@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "VERSION=dev"
if exist VERSION for /f "usebackq delims=" %%v in ("VERSION") do set "VERSION=%%v"

set "INSTALL_DIR=%USERPROFILE%\.local\share\claudex"
set "BIN_DIR=%USERPROFILE%\.local\bin"

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"

if exist "%INSTALL_DIR%\cli-proxy-api.exe" (
  echo cli-proxy-api.exe already installed, skipping download.
) else (
  echo Downloading CLIProxyAPI...
  for /f "delims=" %%v in ('curl.exe -fsSL "https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest" ^| findstr /r "\"tag_name\""') do set TAGLINE=%%v
  for /f tokens^=4delims^=^" %%v in ("!TAGLINE!") do set TAG=%%v
  if "!TAG!"=="" (
    echo Could not determine the latest CLIProxyAPI release tag. Aborting.
    exit /b 1
  )
  echo Latest release: !TAG!
  set "WIN_ARCH=amd64"
  if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "WIN_ARCH=aarch64"
  if /i "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "WIN_ARCH=aarch64"
  curl.exe -fsSL -o "%TEMP%\claudex-cliproxy.zip" "https://github.com/router-for-me/CLIProxyAPI/releases/download/!TAG!/CLIProxyAPI_!TAG:v=!_windows_!WIN_ARCH!.zip"
  if errorlevel 1 (
    echo Download failed. Check the asset name still matches at:
    echo https://github.com/router-for-me/CLIProxyAPI/releases
    exit /b 1
  )
  REM Extract to a throwaway folder first: the release zip also bundles its
  REM own README.md/README_CN.md/config.example.yaml, which would silently
  REM overwrite this repo's own README.md if extracted directly into cwd.
  if exist "%TEMP%\claudex_cliproxy_extract" rmdir /s /q "%TEMP%\claudex_cliproxy_extract"
  powershell -NoProfile -Command "Expand-Archive -Path '%TEMP%\claudex-cliproxy.zip' -DestinationPath '%TEMP%\claudex_cliproxy_extract' -Force"
  if not exist "%TEMP%\claudex_cliproxy_extract\cli-proxy-api.exe" (
    echo Extraction failed: cli-proxy-api.exe was not produced. %TEMP%\claudex-cliproxy.zip was kept for inspection.
    exit /b 1
  )
  move /y "%TEMP%\claudex_cliproxy_extract\cli-proxy-api.exe" "%INSTALL_DIR%\" >nul
  rmdir /s /q "%TEMP%\claudex_cliproxy_extract"
  del "%TEMP%\claudex-cliproxy.zip"
)

if not exist "%INSTALL_DIR%\claudex-token.txt" (
  echo Generating a local proxy token...
  for /f "delims=" %%t in ('openssl rand -hex 32 2^>nul') do set TOKEN=%%t
  if "!TOKEN!"=="" (
    REM No openssl: fall back to .NET's cryptographic RNG, never %RANDOM%.
    for /f "delims=" %%t in ('powershell -NoProfile -Command "$b = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); -join ($b | ForEach-Object { $_.ToString('x2') })"') do set TOKEN=%%t
  )
  if "!TOKEN!"=="" (
    echo Could not generate a token. Aborting.
    exit /b 1
  )
  (echo !TOKEN!)>"%INSTALL_DIR%\claudex-token.txt"
)
set /p TOKEN=<"%INSTALL_DIR%\claudex-token.txt"

if not exist "%INSTALL_DIR%\config.yaml" (
  echo Writing config.yaml...
  (
    echo host: "127.0.0.1"
    echo port: 8317
    echo auth-dir: 'auth'
    echo api-keys:
    echo   - "!TOKEN!"
    echo debug: false
    echo request-retry: 3
  )>"%INSTALL_DIR%\config.yaml"
) else (
  REM One additive migration for installs from before v2.0.0: proxy-side retry
  REM smooths transient upstream errors (403/408/5xx) without touching anything
  REM else in the user's existing config.
  findstr /b /c:"request-retry:" "%INSTALL_DIR%\config.yaml" >nul 2>&1
  if errorlevel 1 (
    echo Adding request-retry to your existing config.yaml...
    (echo request-retry: 3)>>"%INSTALL_DIR%\config.yaml"
  )
)

REM The launcher script is plain code, not user state: always refresh it so
REM re-running setup after a git pull picks up fixes without touching the
REM token, config, or OAuth credential already sitting in INSTALL_DIR.
copy /y claudex.cmd "%INSTALL_DIR%\claudex.cmd" >nul

REM The repo checkout is only needed to run this script. Once installed,
REM claudex runs entirely from INSTALL_DIR; the PATH shim is the only thing
REM a user's shell ever needs to find.
(
  echo @echo off
  echo call "%INSTALL_DIR%\claudex.cmd" %%*
)>"%BIN_DIR%\claudex.cmd"

powershell -NoProfile -Command "$binDir = [Environment]::ExpandEnvironmentVariables('%BIN_DIR%'); $userPath = [Environment]::GetEnvironmentVariable('Path','User'); if (-not $userPath) { $userPath = '' }; if (($userPath -split ';') -notcontains $binDir) { [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $binDir), 'User'); Write-Host 'Added' $binDir 'to your PATH. Open a new terminal for it to take effect.' } else { Write-Host $binDir 'is already on your PATH.' }"

echo.
echo claudex v!VERSION! installed to %INSTALL_DIR%
echo Two things left, both one-time:
echo   1. cd /d "%INSTALL_DIR%" ^&^& cli-proxy-api.exe -codex-login   (opens a browser, authenticate with your ChatGPT/Codex account)
echo   2. Open a new terminal, then run claudex.
echo.
echo How to use it:
echo   claudex                 normal Claude Code, your Claude login, untouched
echo   claudex gpt-5.6-sol     that session runs GPT-5.6 Sol through the local proxy
echo   claudex gpt-5.6-terra   same for Terra (also gpt-5.6-luna)
echo   claudex k3              Kimi K3, after a one-time cli-proxy-api.exe -kimi-login
echo.
echo Never run -claude-login. It routes your real Claude subscription through a third-party
echo tool, which violates Anthropic's Consumer Terms and has led to real account suspensions.
echo.
echo Config, the local proxy token, and the OAuth credential all live in %INSTALL_DIR%,
echo not in this source checkout, and are not tracked by git. This folder you're running
echo setup from is no longer needed once setup finishes.
endlocal
