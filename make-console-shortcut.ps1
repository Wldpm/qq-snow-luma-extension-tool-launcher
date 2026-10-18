<#
  生成「QQ桥接控制台」快捷方式（.url），令牌从桥接的 state\console-token 读取。

  为什么需要它：仓库里**不放真令牌**（模板用 <YOUR_CONSOLE_TOKEN> 占位），
  每个人的令牌不同，所以安装后用本脚本生成自己的快捷方式。

  用法：
    powershell -ExecutionPolicy Bypass make-console-shortcut.ps1
    powershell -ExecutionPolicy Bypass make-console-shortcut.ps1 -OutDir "D:\我的快捷方式"
    powershell -ExecutionPolicy Bypass make-console-shortcut.ps1 -BridgeDir "C:\Users\me\.dsh\qq-bridge"
#>
[CmdletBinding()]
param(
  [string]$BridgeDir = '',
  [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Expand-Cfg([string]$s) {
  if (-not $s) { return '' }
  # 先把字面量 \n 之类的双反斜杠还原，再展开环境变量
  return [Environment]::ExpandEnvironmentVariables($s)
}

$cfg = @{}
$cfgPath = Join-Path $root 'toolkit.config.json'
if (Test-Path $cfgPath) {
  try { $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}
if (-not $BridgeDir) { $BridgeDir = Expand-Cfg $cfg.bridgeDir }
if (-not $BridgeDir) { $BridgeDir = Join-Path $env:USERPROFILE '.dsh\qq-bridge' }
if (-not $OutDir)    { $OutDir = [Environment]::GetFolderPath('Desktop') }

$tokFile = Join-Path $BridgeDir 'state\console-token'
if (-not (Test-Path $tokFile)) {
  Write-Host "找不到 $tokFile" -ForegroundColor Red
  Write-Host "（桥接启动过至少一次才会生成控制台令牌）" -ForegroundColor DarkGray
  exit 1
}
$tok = (Get-Content $tokFile -Raw).Trim()
$url = "http://127.0.0.1:3100/?token=$tok"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$out = Join-Path $OutDir 'QQ桥接控制台.url'
$content = "[InternetShortcut]`r`nURL=$url`r`n"
[System.IO.File]::WriteAllText($out, $content, (New-Object System.Text.ASCIIEncoding))

Write-Host "✅ 已生成: $out" -ForegroundColor Green
Write-Host "   令牌来源: $tokFile （仓库里不保存真值）" -ForegroundColor DarkGray
Write-Host "   目标 URL: http://127.0.0.1:3100/?token=****" -ForegroundColor DarkGray