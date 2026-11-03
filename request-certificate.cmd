@echo off
rem AWS setup step 5a: requests (or checks) the ACM certificate for the domain in project.json. Log: logs\certificate.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\request-certificate.ps1"
