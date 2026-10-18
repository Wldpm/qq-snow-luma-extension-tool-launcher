$ErrorActionPreference = 'SilentlyContinue'
# ── 读取 toolkit.config.json（本机关键词集中在配置里，自定义动作里也能用 $__tk）──
. "$PSScriptRoot\_config.ps1"
$__tk = Get-ToolkitConfig

function Get-FreeGB { [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1) }
function PortUp([int]$p) { [bool](Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue) }
function Stop-Port([int]$p) { $c = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue; if ($c) { Stop-Process -Id $c.OwningProcess -Force } }
function Stop-ByCmd([string]$pat) { Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like $pat } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force } }

$before = Get-FreeGB
Write-Host ''
Write-Host ("开始前可用内存: {0} GB" -f $before) -ForegroundColor Cyan
Write-Host ''
Write-Host '停止 QQ AI：桥接 / SnowLuma / MCP ...' -ForegroundColor Green
Stop-Port 3100
Stop-Port 5099
Stop-ByCmd '*qq-bridge*'
Start-Sleep -Seconds 2
Write-Host '    已停止（QQ 客户端与微信永不被动）' -ForegroundColor Green

# ── 自定义动作 ────────────────────────────────────────────────────────────
# 仓库只带「停掉 QQ AI」这一个通用动作。关浏览器、调内存优化、关别的 DSH 实例
# 这类高度依赖个人环境的操作，写在同目录 pause-custom.ps1 里，不随仓库分发。
$customFile = Join-Path $PSScriptRoot 'pause-custom.ps1'
if (Test-Path $customFile) {
  try {
    . $customFile
    if (Get-Command Invoke-PauseCustom -ErrorAction SilentlyContinue) { Invoke-PauseCustom }
    else { Write-Host '    pause-custom.ps1 里没有 Invoke-PauseCustom 函数，已跳过' -ForegroundColor Yellow }
  }
  catch {
    Write-Host ('    自定义动作出错（已忽略）: ' + $_.Exception.Message) -ForegroundColor Yellow
  }
}
else {
  Write-Host ''
  Write-Host '    没有 pause-custom.ps1 —— 只做了「停止 QQ AI」。' -ForegroundColor DarkGray
  Write-Host '    想额外关程序 / 腾内存：照着 pause-custom.example.ps1 建一个就行' -ForegroundColor DarkGray
}

Start-Sleep -Seconds 2
$after = Get-FreeGB
Write-Host ''
Write-Host ("腾完后可用内存: {0} GB（多出 {1} GB）" -f $after, [math]::Round($after - $before, 1)) -ForegroundColor Cyan
Write-Host '恢复: 双击桌面「启动QQ AI」' -ForegroundColor Yellow
Write-Host ''
