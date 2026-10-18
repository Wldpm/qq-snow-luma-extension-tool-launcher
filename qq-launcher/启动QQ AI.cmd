@echo off
chcp 65001 >nul
title QQ AI - 关闭此窗口即停止服务
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.dsh\scripts\start-qq-ai.ps1"
echo.
echo 服务已停止，按任意键关闭窗口。
pause >nul
