@echo off
rem AWS setup step 1 (database): creates the app's schema in the shared database and applies <app>-api\db\migrations. Log: logs\migrations.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\apply-migrations.ps1" %*
