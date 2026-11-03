@echo off
rem One-off: backs up admin.users to logs\ and clears every row's old Cognito link (cognito_sub). Log: logs\unlink-users.log
setlocal
set ROOT=%~dp0
for /f "delims=" %%J in ('dir /b /s "%USERPROFILE%\.m2\repository\org\postgresql\postgresql\postgresql-*.jar" 2^>nul ^| findstr /v sources') do set PGJAR=%%J
if not defined PGJAR (echo PostgreSQL driver not found in %USERPROFILE%\.m2. Run build-lambda.cmd first. & pause & exit /b 1)
java --class-path "%PGJAR%" "%ROOT%scripts\UnlinkUsers.java" "%ROOT%." > "%ROOT%logs\unlink-users.log" 2>&1
type "%ROOT%logs\unlink-users.log"
pause
