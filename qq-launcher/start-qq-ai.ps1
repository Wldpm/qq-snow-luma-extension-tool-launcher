$ErrorActionPreference = 'Continue'
# ── 读取 toolkit.config.json（本机关键词集中在配置里，可用参数或环境变量覆盖）──
. "$PSScriptRoot\_config.ps1"
$__tk = Get-ToolkitConfig
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ── 配置自检：缺 DSH 自带的 node / 桥接目录就跑不起来 ──────────────────────
# 这两项指向「别人的 DSH 安装位置」，每台机器都不一样。宁可在这里停下并说清
# 要改哪个文件的哪个字段，也不要让窗口一闪而过、让人以为是脚本坏了。
$__fatal = @($__tk.Issues | Where-Object { $_ -eq 'dshNode' -or $_ -eq 'bridgeDir' })
if ($__fatal.Count -gt 0) {
  Write-Host ''
  Write-Host '==================================================' -ForegroundColor Red
  Write-Host '   配置没填好，一键启动无法继续' -ForegroundColor Red
  Write-Host '==================================================' -ForegroundColor Red
  Write-Host ''
  Get-ToolkitConfigHints -Config $__tk -Only $__fatal | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
  Write-Host ''
  $cfgShown = if ($__tk.ConfigFile) { $__tk.ConfigFile } else { '没找到 toolkit.config.json（应放在项目根或本脚本同目录）' }
  Write-Host ('  配置文件: ' + $cfgShown) -ForegroundColor Gray
  Write-Host ''
  if (-not $env:TOOLKIT_NO_PAUSE) {
    try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch {}
  }
  exit 1
}

$sl = $__tk.SnowlumaDir
$slNode = Join-Path $sl 'node.exe'
$brNode = $__tk.DshNode
$repo = $__tk.BridgeDir
$dshExe = $__tk.DshExe
$qqExe = $__tk.QqExe
$logDir = "$($__tk.BridgeDir)\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$boot = Join-Path $logDir "start-$stamp.log"

function Say($m) {
  $line = "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
  Write-Host $line
  Add-Content -Path $boot -Value $line -Encoding UTF8
}
function PortUp([int]$p) { [bool](Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue) }

# ── DSH 端口自动发现 ────────────────────────────────────────────────
# DSH 0.2.x 起 Web 服务改用 listen(0)（随机空闲端口），重启一次端口就变，
# 所以不能再把端口写死。这里通过「DeepSeek Harness 进程监听了哪些端口」来发现。
function Get-DshListenPorts {
  $procs = @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue)
  if ($procs.Count -eq 0) { return @() }
  $pids = @($procs | ForEach-Object { $_.Id })
  $ports = @()
  try {
    $conns = Get-NetTCPConnection -State Listen -ErrorAction Stop
    $ports = @($conns | Where-Object { $pids -contains $_.OwningProcess } | ForEach-Object { [int]$_.LocalPort })
  } catch {
    # PowerShell 5.1 上 Get-NetTCPConnection 偶发不可用 → netstat 兜底
    $lines = netstat -ano -p TCP 2>$null | Select-String 'LISTENING'
    foreach ($l in $lines) {
      if ($l.Line -match '(\d+\.\d+\.\d+\.\d+|\[::\]):(\d+)\s+\S+\s+LISTENING\s+(\d+)') {
        if ($pids -contains [int]$matches[3]) { $ports += [int]$matches[2] }
      }
    }
  }
  return @($ports | Where-Object { $_ -gt 0 } | Select-Object -Unique)
}

# 把桥接 config.json 里的 dsh.baseUrl 同步成 DSH 当前端口。
# 桥接读的是启动时配置，所以必须在本脚本启动桥接「之前」调用。
function Sync-DshBaseUrl {
  $cfgPath = Join-Path $__tk.BridgeDir 'config.json'
  if (-not (Test-Path $cfgPath)) { Say ('找不到桥接配置: ' + $cfgPath + '（跳过端口同步）'); return }
  $ports = @(Get-DshListenPorts)
  if ($ports.Count -eq 0) { Say 'DSH 未在监听（可能还没起来）→ 保持桥接原有 DSH 地址'; return }

  $cur = ''
  try {
    $raw = Get-Content $cfgPath -Raw -Encoding UTF8
    if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
    $cur = [string](($raw | ConvertFrom-Json).dsh.baseUrl)
  } catch { }

  $curPort = 0
  if ($cur -match '^https?://127\.0\.0\.1:(\d+)') { $curPort = [int]$matches[1] }
  # 原端口如果还在监听就继续用（避免误切到同进程的其它内部端口），否则取第一个
  $pick = if ($curPort -gt 0 -and ($ports -contains $curPort)) { $curPort } else { $ports[0] }
  $want = 'http://127.0.0.1:' + $pick
  if ($cur -eq $want) { Say ('DSH 端口 = ' + $pick + '（桥接配置已正确）'); return }

  # 用 node 改 JSON：PowerShell 的 ConvertTo-Json 会转义中文/换行，容易改坏配置
  $js = @'
const fs = require('fs');
const p = process.argv[2], u = process.argv[3];
if (!p || !u) { console.error('missing args: need <configPath> <url>'); process.exit(1); }
let t = fs.readFileSync(p, 'utf8');
if (t.charCodeAt(0) === 0xFEFF) t = t.slice(1);
const c = JSON.parse(t);
const o = c.dsh && c.dsh.baseUrl;
c.dsh = c.dsh || {};
c.dsh.baseUrl = u;
fs.writeFileSync(p, JSON.stringify(c, null, 2), 'utf8');
// 读回校验：确认真的落盘（防止"日志说成功、实际没写"）
const back = JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, '')).dsh.baseUrl;
if (back !== u) { console.error('verify failed: ' + back); process.exit(2); }
console.log('baseUrl: ' + o + ' -> ' + back + ' (verified)');
'@
  try {
    # 用临时 .js 文件执行：PowerShell 5.1 向原生程序传「多行参数」时引号/换行转义不可靠
    $jsFile = Join-Path $env:TEMP ('dsh-port-' + [guid]::NewGuid().ToString('N') + '.cjs')
    [System.IO.File]::WriteAllText($jsFile, $js, (New-Object System.Text.UTF8Encoding($false)))
    $out = & $brNode $jsFile $cfgPath $want 2>&1
    $nodeExit = $LASTEXITCODE
    if ($nodeExit -eq 0) { Say ("DSH 端口变化: {0} → {1}（已写入并校验通过）" -f $cur, $want) } else { Say ("❌ 写入失败 exit=$nodeExit，请手工改 dsh.baseUrl") }
    if ($out) { Say ([string]$out) }
  } catch {
    Say ('自动同步 DSH 端口失败: ' + $_.Exception.Message + '（请手工检查桥接 config.json）')
  } finally {
    if ($jsFile) { Remove-Item $jsFile -Force -ErrorAction SilentlyContinue }
  }
}

# ── 启动前清理残留桥接进程 ──────────────────────────────────────────
# 直接关窗口只关掉宿主 PowerShell，bridge.js 可能变成孤儿进程继续跑。
# 双击启动时若它没占住 3100（或已卡死），就会起第二个实例：两个桥接同时
# follow 同一个 DSH 会话，turn/start 与 turn/end 互相错位 → 会话被永久判为
# "繁忙"、所有唤醒被暂存（就是日志里反复刷的那句）。
# 所以启动前必须按「端口 + 命令行」把残留清干净 —— 这正是 pause-qq-ai.ps1
# 的 A 档做法，现在内置到启动流程里。
function Clear-StaleBridge {
  $killed = 0
  # 1) 占用 3100 的进程
  try {
    $conns = @(Get-NetTCPConnection -LocalPort 3100 -State Listen -ErrorAction SilentlyContinue)
    foreach ($cn in $conns) {
      if ($cn -and $cn.OwningProcess) {
        Stop-Process -Id $cn.OwningProcess -Force -ErrorAction SilentlyContinue
        Say ("  已停止占用 3100 的进程 (PID {0})" -f $cn.OwningProcess)
        $killed++
      }
    }
  } catch {
    $lines = netstat -ano -p TCP 2>$null | Select-String ':3100\s' | Select-String 'LISTENING'
    foreach ($l in $lines) {
      if ($l.Line -match ':3100\s+\S+\s+LISTENING\s+(\d+)') {
        Stop-Process -Id ([int]$matches[1]) -Force -ErrorAction SilentlyContinue
        Say ("  已停止占用 3100 的进程 (PID {0}, via netstat)" -f $matches[1])
        $killed++
      }
    }
  }
  # 2) 命令行含 qq-bridge 且是 bridge.js 的 node 进程（不碰 DSH 启动的 mcp-*.js）
  $procs = @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*qq-bridge*bridge.js*' })
  foreach ($pr in $procs) {
    Stop-Process -Id $pr.ProcessId -Force -ErrorAction SilentlyContinue
    Say ("  已停止残留桥接进程 (PID {0})" -f $pr.ProcessId)
    $killed++
  }
  # 3) 过期锁文件（记录的 PID 已不存在）
  $lock = Join-Path $__tk.BridgeDir 'state\bridge.lock'
  if (Test-Path $lock) {
    $pidText = ''
    try { $pidText = [string](Get-Content $lock -Raw -ErrorAction SilentlyContinue) } catch { }
    if ($pidText) { $pidText = $pidText.Trim() }
    $alive = $false
    if ($pidText -match '^\d+$') { $alive = [bool](Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue) }
    if (-not $alive) {
      Remove-Item $lock -Force -ErrorAction SilentlyContinue
      Say '  已删除过期桥接锁文件'
      $killed++
    }
  }
  if ($killed -gt 0) { Start-Sleep -Seconds 2; Say '  残留清理完成，继续启动' }
  else { Say '  没有残留桥接进程' }
}
function Repair-SessionMapping {
  $mapFile  = "$($__tk.BridgeDir)\state\sessions.json"
  $wsFile   = "$env:USERPROFILE\.dsh\storages\workspace.json"
  $sessRoot = "$env:USERPROFILE\.dsh\sessions"
  if (-not (Test-Path $mapFile)) { Say '没有会话映射文件，桥接会新建会话'; return }
  try { $map = Get-Content $mapFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Say ('会话映射解析失败，跳过自检：' + $_.Exception.Message); return }
  $keys = @($map.sessions.PSObject.Properties.Name)
  if ($keys.Count -eq 0) { Say '会话映射为空 → 桥接本次会新建会话'; return }

  $archived = @()
  if (Test-Path $wsFile) {
    try { $ws = Get-Content $wsFile -Raw -Encoding UTF8 | ConvertFrom-Json; $archived = @($ws.global.archivedSessionIds) } catch {}
  }
  # 兼容 PowerShell 5.1：它没有 -Directory 参数（那是 PS6+ 的），用 PSIsContainer 过滤
  $dirs = @(Get-ChildItem $sessRoot -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | Select-Object -ExpandProperty Name)

  $bad = 0
  foreach ($k in $keys) {
    $sid = [string]$map.sessions.$k
    $isArchived = $archived -contains $sid
    $exists = $dirs -contains $sid
    if ($isArchived -or -not $exists) {
      $reason = if ($isArchived) { '已归档' } else { '在 DSH 中找不到' }
      Say ("会话映射 {0} → {1} 有问题（{2}）：清除该映射，让桥接新建会话" -f $k, $sid, $reason)
      $map.sessions.PSObject.Properties.Remove($k)
      if ($map.sessionPolicies) { $map.sessionPolicies.PSObject.Properties.Remove($k) }
      $bad++
    }
  }
  if ($bad -gt 0) {
    Copy-Item $mapFile ($mapFile + '.bak-' + (Get-Date -Format yyyyMMdd-HHmmss)) -Force -ErrorAction SilentlyContinue
    ($map | ConvertTo-Json -Depth 6) | Set-Content -Path $mapFile -Encoding UTF8
    Say ("已修复 {0} 条映射；桥接启动后会建立新会话" -f $bad)
  } else {
    Say '会话映射健康（未归档且会话都在）'
  }
}

Write-Host ''
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host '   QQ AI   ｜  关掉本窗口即停止服务' -ForegroundColor Cyan
Write-Host '   控制台: http://127.0.0.1:3100' -ForegroundColor Cyan
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host ''

# ── DSH 与 QQ 不由本脚本启动：缺了就先提醒，等你在窗口里按任意键再继续 ──
function Wait-AnyKey([string]$tip) {
  Say $tip
  try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }
  catch { $null = Read-Host '按回车继续' }
}

$dshAlive = { [bool](Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -eq 'DeepSeek Harness' }) }
if (-not (& $dshAlive)) {
  Say ''
  Say '⚠️ 没有检测到 DeepSeek Harness（DSH）。'
  Say ('   请先启动：' + $dshExe)
  Say '   等它完全加载后再回来。'
  Wait-AnyKey '   启动好 DSH 后，按任意键继续 ...'
  if (-not (& $dshAlive)) {
    Say '❌ 仍未检测到 DSH，已退出（启动 DSH 后重新双击「启动QQ AI」）'
    exit 1
  }
  # 端口是随机分配的，等它开始监听即可
  for ($i = 0; $i -lt 45; $i++) { if (@(Get-DshListenPorts).Count -gt 0) { break }; Start-Sleep -Seconds 2 }
  Say 'DSH 已就绪'
} else { Say 'DSH 已在运行' }

$qqAlive = { [bool](Get-Process -Name QQ -ErrorAction SilentlyContinue) }
if (-not (& $qqAlive)) {
  Say ''
  Say '⚠️ 没有检测到 QQ。'
  Say ('   请先启动：' + $qqExe)
  Say '   并确认已登录要用的那个小号。'
  Wait-AnyKey '   启动好 QQ 并登录后，按任意键继续 ...'
  if (-not (& $qqAlive)) {
    Say '❌ 仍未检测到 QQ，已退出（启动 QQ 后重新双击「启动QQ AI」）'
    exit 1
  }
  Say 'QQ 已就绪'
} else { Say 'QQ 已在运行' }

if (-not (PortUp 5099)) {
  Say '启动 SnowLuma ...'
  Start-Process -FilePath $slNode -ArgumentList 'index.mjs' -WorkingDirectory $sl -WindowStyle Hidden
  for ($i=0; $i -lt 30 -and -not (PortUp 5099); $i++) { Start-Sleep -Seconds 1 }
} else { Say 'SnowLuma 已在运行' }

Say '等待小号 OneBot (127.0.0.1:3021) ...'
for ($i=0; $i -lt 45; $i++) { if (PortUp 3021) { break }; Start-Sleep -Seconds 2 }
Say ('OneBot 3021 就绪 = ' + (PortUp 3021))

Say '检查会话映射（已归档 / 找不到 → 自动改为新建会话）'
Repair-SessionMapping

# 关键一步：DSH 每次重启端口都会变（listen(0) 随机分配），
# 桥接只读启动时的配置，所以必须在拉起桥接之前把新端口写进 config.json。
Say '同步 DSH 端口到桥接配置 ...'
Sync-DshBaseUrl

Say '检查残留桥接进程（关窗口可能留下孤儿进程）...'
Clear-StaleBridge

if (PortUp 3100) {
  Say '⚠️ 3100 仍被占用，无法启动桥接。请手动关掉占用它的窗口/进程后重试。'
  exit 1
}

$bridgeLog = Join-Path $logDir "bridge-$stamp.log"
Say '启动 QQ 桥接 —— 以下为实时日志'
Write-Host ('  日志同时写入: ' + $bridgeLog) -ForegroundColor DarkGray
Write-Host ''
Set-Location $repo
& $brNode (Join-Path $repo 'src\bridge.js') 2>&1 | ForEach-Object {
  Write-Host $_
  Add-Content -Path $bridgeLog -Value $_ -Encoding UTF8
}
Say '桥接已退出'