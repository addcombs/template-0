@echo off
rem AWS setup step 6: builds the UI and publishes it to the domain in project.json. Log: logs\deploy-ui.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\deploy-ui.ps1"
