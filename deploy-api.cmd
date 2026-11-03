@echo off
rem Deploys the API to AWS Lambda (step 2 of the AWS setup). Log: logs\deploy-api.log (no secrets).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\deploy-api.ps1"
