@echo off
chcp 65001 >nul
title QQ AI - 暂停
rem 不需要管理员：停 QQ AI 只操作自己的进程。
rem 自定义动作里若需要管理员（比如给某个程序传 --memory），在 pause-custom.ps1 里
rem 用 Start-Process -Verb RunAs 单独提权，系统会自己弹 UAC。
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.dsh\scripts\pause-qq-ai.ps1"
echo.
pause >nul
