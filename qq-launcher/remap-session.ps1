param([string]$SessionId, [string]$Key = '')
$ErrorActionPreference = 'Continue'
# ── 读取 toolkit.config.json（本机关键词集中在配置里，可用参数或环境变量覆盖）──
. "$PSScriptRoot\_config.ps1"
$__tk = Get-ToolkitConfig

# 会话 key 里含 QQ 号，**不写死在脚本里**（脚本会入库，号码不该跟着走）。
# 优先级：-Key 参数 → toolkit.config.json 的 ownerQQ → 现场输入。
if (-not $Key -and $__tk.OwnerQQ) { $Key = "private:$($__tk.OwnerQQ)" }
if (-not $Key) { $Key = Read-Host '要挂回哪个会话 key（如 private:123456 或 group:987654）' }
if ($Key -notmatch '^(private|group):\d+$') {
  Write-Host '会话 key 无效，已取消（格式：private:QQ号 或 group:群号）' -ForegroundColor Yellow
  exit 1
}
$sessRoot = "$env:USERPROFILE\.dsh\sessions"
$mapFile  = "$($__tk.BridgeDir)\state\sessions.json"
$node = $__tk.DshNode

$cands = Get-ChildItem $sessRoot -Recurse -Filter 'session.v4.jsonl.zstd' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -like '*qq-bridge-state-agents*' } |
  ForEach-Object { [pscustomobject]@{ Id = $_.Directory.Name; KB = [math]::Round($_.Length/1KB,1); Last = $_.LastWriteTime } } |
  Sort-Object Last -Descending

if (-not $SessionId) {
  if (-not $cands -or @($cands).Count -eq 0) {
    Write-Host '没有可挂回的 QQ 会话（qq-bridge 还没产生过会话？）' -ForegroundColor Yellow
    exit 1
  }
  Write-Host ''
  Write-Host '可挂回的 QQ 会话（按时间倒序）:' -ForegroundColor Cyan
  $i = 1
  $cands | ForEach-Object { Write-Host ("  [{0}] {1}   {2} KB   {3}" -f $i, $_.Id, $_.KB, $_.Last); $i++ }
  Write-Host ''
  # 防呆：非数字、超范围都重问，别让手滑输错就直接退出
  $idx = -1
  $max = @($cands).Count
  while ($true) {
    $pick = Read-Host ("输入序号 1-$max（直接回车取消）")
    if (-not $pick) { Write-Host '已取消'; exit 0 }
    if ($pick.Trim() -notmatch '^\d+$') { Write-Host ("  ✗ 只填数字（1 - $max）") -ForegroundColor Red; continue }
    $n = [int]$pick.Trim()
    if ($n -lt 1 -or $n -gt $max) { Write-Host ("  ✗ 范围是 1 - $max") -ForegroundColor Red; continue }
    $idx = $n - 1
    break
  }
  $SessionId = $cands[$idx].Id
}

$c = Get-NetTCPConnection -LocalPort 3100 -State Listen -ErrorAction SilentlyContinue
if ($c) { Stop-Process -Id $c.OwningProcess -Force; Write-Host '已停桥接（避免它覆盖映射）'; Start-Sleep -Seconds 2 }

$env:TOOLKIT_MAPFILE = $mapFile
& $node -e "const fs=require('fs');const p=process.env.TOOLKIT_MAPFILE;const j=JSON.parse(fs.readFileSync(p,'utf8'));j.sessions=j.sessions||{};j.sessions['$Key']='$SessionId';fs.writeFileSync(p,JSON.stringify(j,null,2)+'\n','utf8');console.log('已挂回: '+'$Key'+' -> '+'$SessionId')"
Write-Host ''
Write-Host '完成。双击桌面「启动QQ AI」让桥接用这个会话继续。' -ForegroundColor Green