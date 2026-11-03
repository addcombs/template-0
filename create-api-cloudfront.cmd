@echo off
rem AWS setup step 5b: creates the CloudFront distribution for the API domain (api.<domain> from project.json). Log: logs\api-cloudfront.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\create-api-cloudfront.ps1"
