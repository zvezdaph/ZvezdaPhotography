@echo off
rem Compila PeopleCare Central Operations per Windows x64.
rem Inoltra tutti gli argomenti a build_windows.ps1, ad esempio:
rem   scripts\build_windows.bat -SkipChecks -BuildNumber 42
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_windows.ps1" %*
exit /b %ERRORLEVEL%
