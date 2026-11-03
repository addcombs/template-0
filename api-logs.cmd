@echo off
rem Saves the last 30 minutes of the API Lambda logs to logs\api-lambda.log.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\api-logs.ps1"
