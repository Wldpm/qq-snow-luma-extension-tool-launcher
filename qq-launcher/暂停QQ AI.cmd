@echo off
chcp 65001 >nul
title QQ AI - pause
rem No admin required: this only stops your own QQ AI processes.
rem If a custom action needs admin, use Start-Process -Verb RunAs in pause-custom.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.dsh\scripts\pause-qq-ai.ps1"
echo.
pause >nul
