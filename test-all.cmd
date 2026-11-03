@echo off
rem Runs the UI unit tests and the API verify build without starting servers. Output: logs\test-*.log
for /d %%D in ("%~dp0*-ui") do cd /d "%%D"
call npm test -- --watch=false > "%~dp0logs\test-ui.log" 2>&1
echo UI tests exit code %ERRORLEVEL%
for /d %%D in ("%~dp0*-api") do cd /d "%%D"
call mvn --batch-mode --no-transfer-progress verify > "%~dp0logs\test-api.log" 2>&1
echo API verify exit code %ERRORLEVEL%
pause
