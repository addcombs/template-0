@echo off
rem Lists the build tools the app needs (Java 21, Maven, Node.js/npm) into logs\check-tools.log.
cd /d "%~dp0"
(
  echo == java & where java & java -version 2>&1
  echo == JAVA_HOME=%JAVA_HOME%
  echo == mvn & where mvn
  echo == node & where node & node -v
  echo == npm & where npm & call npm -v
  echo == jdks & dir /b "%USERPROFILE%\.jdks"
  echo == maven wrapper dists & dir /b /s "%USERPROFILE%\.m2\wrapper\dists" 2^>nul ^| findstr /i "bin\\mvn.cmd"
  echo == intellij maven & dir /b /s "%ProgramFiles%\JetBrains\*mvn.cmd" 2^>nul
  dir /b /s "%LOCALAPPDATA%\Programs\*mvn.cmd" 2>nul
  echo == ports & netstat -ano ^| findstr ":8080 :4200" ^| findstr LISTENING
  echo == done
) > logs\check-tools.log 2>&1
