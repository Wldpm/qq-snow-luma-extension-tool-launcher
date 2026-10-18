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
  [switch]$Check,
  [switch]$Force
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
$cfgDst = Join-Path $TargetDir 'toolkit.config.json'
if (Test-Path $cfgSrc) {
  if ($Check) {
    if (Test-Path $cfgDst) { Write-Host '  ✅ toolkit.config.json 已存在' -ForegroundColor Green }
    else { Write-Host '  ⚠️  toolkit.config.json 缺失' -ForegroundColor Yellow }
  }
  elseif ((Test-Path $cfgDst) -and -not $Force) {
    # 已存在就保持不动 —— 那可能是用户按自己机器改过的，覆盖会让脚本读错路径
    Write-Host '  ✅ toolkit.config.json 已存在，保持不动（-Force 才覆盖）' -ForegroundColor Green
  }
  else {
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    Copy-Item $cfgSrc $cfgDst -Force
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

# ── 桌面入口文件夹 ────────────────────────────────────────────────────────
# 统一放 QQAI_Tools：启动 / 暂停 / 控制台。
# 里面的 .cmd 用绝对路径调 %USERPROFILE%\.dsh\scripts\ 下的脚本，
# **不依赖自身位置** —— 用户可以把整个文件夹挪到任何地方都不会报错。
Write-Host '  桌面入口文件夹（QQAI_Tools）：'
$desk = [Environment]::GetFolderPath('Desktop')
if ($desk -and (Test-Path $desk)) {
  $toolDir = Join-Path $desk 'QQAI_Tools'
  if (-not $Check) { New-Item -ItemType Directory -Force -Path $toolDir | Out-Null }
  # 启动 / 暂停：直接复制（里面用的是绝对路径调 .dsh\scripts\，不依赖自身位置）
  foreach ($e in @('启动QQ AI.cmd', '暂停QQ AI.cmd')) {
    $s = Join-Path $SrcDir $e
    if (-not (Test-Path $s)) { continue }
    $d = Join-Path $toolDir $e
    if ($Check) {
      if (Test-Path $d) { OK ("{0,-24} 已存在" -f $e) } else { Warn ("{0,-24} 缺失" -f $e) }
      continue
    }
    # 桌面已有的文件默认不动（用户可能自己改过）。要覆盖加 -Force。
    if ((Test-Path $d) -and -not $Force) { OK ("{0,-24} 已存在，保持不动（-Force 才覆盖）" -f $e); continue }
    Copy-Item $s $d -Force
    OK ("{0,-24} 已复制" -f $e)
  }

  # ★ 控制台快捷方式：必须用桥接的**真令牌**现场生成。
  #   仓库里那两个文件只是占位符模板（token=<YOUR_CONSOLE_TOKEN>），
  #   直接复制会把用户已经能用的真令牌冲掉 —— 2026-10-18 出过一次，别再犯。
  $tokenFile = Join-Path $env:USERPROFILE '.dsh\qq-bridge\state\console-token'
  $cfgFile   = Join-Path $env:USERPROFILE '.dsh\qq-bridge\config.json'
  $cport = 3100
  if (Test-Path $cfgFile) {
    try { $cj = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json; if ($cj.consolePort) { $cport = [int]$cj.consolePort } } catch {}
  }
  $ctok = ''
  if (Test-Path $tokenFile) { $ctok = (Get-Content $tokenFile -Raw).Trim() }

  if ($ctok) {
    if ($Check) { OK 'QQ桥接控制台    可生成（已读到令牌）' }
    else {
      # 已存在且令牌一致 → 不动（用户可能自己加了图标/热键）
      $urlPath = Join-Path $toolDir 'QQ桥接控制台.url'
      if ((Test-Path $urlPath) -and -not $Force) {
        $oldUrl = Get-Content $urlPath -Raw -Encoding UTF8
        if ($oldUrl.Contains($ctok)) {
          OK 'QQ桥接控制台 已存在且令牌一致，保持不动'
          $ctok = ''
        }
      }
    }
    if ($ctok) {
      $curl = "http://127.0.0.1:$cport/?token=$ctok"
      $urlText = "[InternetShortcut]`r`nURL=$curl`r`nIconIndex=2`r`nHotKey=0`r`nIDList=`r`nIconFile=C:\Windows\System32\SHELL32.dll`r`n"
      [System.IO.File]::WriteAllText((Join-Path $toolDir 'QQ桥接控制台.url'), $urlText, (New-Object System.Text.UTF8Encoding($false)))
      # 只生成 .url（双击直接开浏览器）；不再生成 .cmd，少弹一个黑框
      $staleCmd = Join-Path $toolDir 'QQ桥接控制台.cmd'
      if (Test-Path $staleCmd) { Remove-Item $staleCmd -Force -ErrorAction SilentlyContinue }
      OK 'QQ桥接控制台.url 已按当前令牌生成'
    }
  }
  else {
    Warn '读不到桥接令牌（qq-bridge\state\console-token）'
    Warn '  控制台快捷方式跳过 —— 桥接启动过一次才会有这个令牌，之后再跑一遍本脚本即可'
  }
  Write-Host ('    位置：' + $toolDir) -ForegroundColor DarkGray
  Write-Host '    控制台快捷方式已按桥接当前令牌生成，不需要手工填' -ForegroundColor DarkGray
}
else { Warn '找不到桌面目录，跳过桌面入口' }
Write-Host ''
Write-Host '  这些 .cmd 调的是 %USERPROFILE%\.dsh\scripts\ 下的脚本，所以部署后自动生效；' -ForegroundColor DarkGray
Write-Host '  整个 QQAI_Tools 文件夹可以随便挪，不依赖它自己的位置。' -ForegroundColor DarkGray
Write-Host ''