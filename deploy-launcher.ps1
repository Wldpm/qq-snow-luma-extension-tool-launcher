<#
  dsh-qq-toolkit · 部署 qq-launcher

  把本目录（qq-launcher）里的脚本本体同步到运行位置，使桌面上的快捷方式
  （「启动QQ AI.cmd」/「暂停QQ AI.cmd」/「QQ桥接控制台.url」）无需改动即可继续工作。

  设计约定（与 texkit 一致）：
    · 工作区 = 源（可 git、可版本管理）
    · %USERPROFILE%\.dsh\scripts\ = 部署副本（桌面壳按绝对路径调用它）
    · .cmd / .url 是"桌面入口"，**不**部署到 scripts（需要时手工放到桌面或你的文件夹）

  用法：
    powershell -ExecutionPolicy Bypass deploy-launcher.ps1                 # 复制并校验
    powershell -ExecutionPolicy Bypass deploy-launcher.ps1 -Check          # 只比对，不复制
    powershell -ExecutionPolicy Bypass deploy-launcher.ps1 -TargetDir "C:\...\.dsh\scripts"
#>
[CmdletBinding()]
param(
  [string]$TargetDir = (Join-Path $env:USERPROFILE '.dsh\scripts'),
  [switch]$Check
)

$ErrorActionPreference = 'Stop'
$SrcDir = Join-Path $PSScriptRoot 'qq-launcher'

function OK($m)   { Write-Host "  ✅ $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  ⚠️  $m" -ForegroundColor Yellow }
function Bad($m)  { Write-Host "  ❌ $m" -ForegroundColor Red }

Write-Host ''
Write-Host '=== dsh-qq-toolkit · 部署 qq-launcher ===' -ForegroundColor Cyan
Write-Host "  源   : $SrcDir"
Write-Host "  目标 : $TargetDir"
Write-Host ('  模式 : ' + $(if ($Check) { '只校验（不复制）' } else { '复制并校验' }))
Write-Host ''

if (-not (Test-Path $SrcDir)) { Bad "源目录不存在：$SrcDir"; exit 1 }

# 只部署脚本本体：.ps1 / .txt（.cmd/.url 是桌面入口）
$files = Get-ChildItem $SrcDir | Where-Object { $_.Extension -in '.ps1', '.txt' }
# 一并把项目根的 toolkit.config.json 部署过去（脚本要靠它找本机路径）
$cfgSrc = Join-Path $PSScriptRoot 'toolkit.config.json'
if (Test-Path $cfgSrc) {
  if (-not $Check) {
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    Copy-Item $cfgSrc (Join-Path $TargetDir 'toolkit.config.json') -Force
    Write-Host '  ✅ 已复制 toolkit.config.json' -ForegroundColor Green
  }
} else { Write-Host '  ⚠️  项目根没有 toolkit.config.json' -ForegroundColor Yellow }
if (-not $files) { Bad '源目录里没有 .ps1 / .txt'; exit 1 }
Write-Host ("  待处理 {0} 个文件：" -f $files.Count)
$files | ForEach-Object { Write-Host ("    {0,-28} {1,6:N1} KB" -f $_.Name, ($_.Length / 1KB)) }
Write-Host ''

if (-not $Check) {
  New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
  $copied = 0; $failed = 0
  foreach ($f in $files) {
    try {
      Copy-Item $f.FullName (Join-Path $TargetDir $f.Name) -Force -ErrorAction Stop
      $copied++
    } catch {
      Bad ("复制失败 {0} -> {1}" -f $f.Name, $_.Exception.Message)
      $failed++
    }
  }
  OK "已复制 $copied 个$(if ($failed) { "，失败 $failed 个" })"
  Write-Host ''
}

# 哈希校验
Write-Host '  哈希校验：'
$same = 0; $diff = 0; $missing = 0
foreach ($f in $files) {
  $t = Join-Path $TargetDir $f.Name
  if (-not (Test-Path $t)) { Bad ("{0,-28} 目标缺失" -f $f.Name); $missing++; continue }
  $a = (Get-FileHash $f.FullName -Algorithm MD5).Hash
  $b = (Get-FileHash $t -Algorithm MD5).Hash
  if ($a -eq $b) { OK ("{0,-28} 一致" -f $f.Name); $same++ }
  else { Warn ("{0,-28} 不一致（需重新部署）" -f $f.Name); $diff++ }
}

Write-Host ''
if ($diff -eq 0 -and $missing -eq 0) {
  OK "全部一致（$same 个）—— 桌面快捷方式可直接使用"
} else {
  Warn "一致 $same / 不一致 $diff / 缺失 $missing"
}
Write-Host ''
Write-Host '  提醒：桌面壳（启动QQ AI.cmd / 暂停QQ AI.cmd / QQ桥接控制台.url）' -ForegroundColor DarkGray
Write-Host ('        调用的是 ' + $TargetDir + ' 下的脚本，所以本脚本部署后它们自动生效。') -ForegroundColor DarkGray
Write-Host ''
