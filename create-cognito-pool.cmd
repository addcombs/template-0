@echo off
rem Creates the app's own Cognito user pool, app client and sign-in domain. Log: logs\cognito-pool.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\create-cognito-pool.ps1"
