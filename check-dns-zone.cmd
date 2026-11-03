@echo off
rem Read-only: lists Route 53 hosted zones for the apex domain in project.json. Log: logs\dns-zone.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\check-dns-zone.ps1"
