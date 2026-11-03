@echo off
rem Switches the app's sign-in to Cognito managed login with the default style. Log: logs\managed-login.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\switch-managed-login.ps1"
