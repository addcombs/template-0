@echo off
rem Sets up, verifies and starts the app (API on 8080, UI on 4200). Logs go to logs\.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-all.ps1"
