@echo off
rem AWS setup step 5: creates the CloudFront distribution for the domain in project.json. Log: logs\cloudfront.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\create-cloudfront.ps1"
