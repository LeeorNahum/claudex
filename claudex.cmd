@echo off
setlocal DisableDelayedExpansion
if exist "%~dp0claudex.exe" goto adjacent
"%USERPROFILE%\.local\bin\claudex.exe" %*
exit /b %errorlevel%
:adjacent
"%~dp0claudex.exe" %*
exit /b %errorlevel%
