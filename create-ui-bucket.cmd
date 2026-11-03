@echo off
rem AWS setup step 4: creates the private S3 bucket for the built UI. Log: logs\ui-bucket.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\create-ui-bucket.ps1"
