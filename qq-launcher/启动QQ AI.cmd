@echo off
chcp 65001 >nul
title QQ AI - running (close this window to stop)
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.dsh\scripts\start-qq-ai.ps1"
echo.
echo Stopped. Press any key to close.
pause >nul
