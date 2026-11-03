@echo off
rem AWS setup step 3: creates the public function URL on the API's live alias. Log: logs\function-url.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\create-function-url.ps1"
