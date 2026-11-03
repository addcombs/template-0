@echo off
rem Builds the API Lambda package: <app>-api\target\*-lambda.zip. Output: logs\build-lambda.log
for /d %%D in ("%~dp0*-api") do cd /d "%%D"
call mvn -P lambda --batch-mode --no-transfer-progress package > "%~dp0logs\build-lambda.log" 2>&1
echo Lambda build exit code %ERRORLEVEL%
pause
