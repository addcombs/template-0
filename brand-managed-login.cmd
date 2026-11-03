@echo off
rem Applies the app's colours (config\managed-login-branding.json) to the Cognito managed-login page. Log: logs\managed-login.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\brand-managed-login.ps1"
