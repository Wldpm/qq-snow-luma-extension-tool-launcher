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
# ── 二次确认 ────────────────────────────────────────────────────────────
# 暂停是不可逆操作（停了就得重开），所以要求输入 A 确认。
# 启动脚本不需要这个 —— 启动没有破坏性。
Write-Host '即将停止 QQ AI（桥接 + SnowLuma + MCP）' -ForegroundColor Yellow
Write-Host '  · QQ 客户端和微信不会被停' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  输入 A 确认停止；直接回车取消。' -ForegroundColor Yellow
$confirm = (Read-Host '  > ').Trim().ToUpper()
if ($confirm -ne 'A') {
  Write-Host ''
  Write-Host '  已取消 —— 什么都没停。' -ForegroundColor Green
  Write-Host ''
  return
}
Write-Host ''
Write-Host '正在停止 ...' -ForegroundColor Green
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
  # ★ 这段只在「还没自定义」时出现（pause-custom.ps1 不存在）。
  #   一旦用户建了这个文件，就说明他已经在自定义了，不再打扰他。
  Write-Host ''
  Write-Host ('=' * 66) -ForegroundColor DarkGray
  Write-Host '  这个脚本可以自定义' -ForegroundColor Cyan
  Write-Host ('=' * 66) -ForegroundColor DarkGray
  Write-Host ''
  Write-Host '  它现在只做一件事：停掉 QQ AI（桥接 + SnowLuma + MCP）。' -ForegroundColor Gray
  Write-Host '  如果你还想顺手做点别的，比如：' -ForegroundColor Gray
  Write-Host '    · 关掉正在占内存的浏览器' -ForegroundColor DarkGray
  Write-Host '    · 叫某个程序做一次内存整理' -ForegroundColor DarkGray
  Write-Host '    · 关掉其它 DeepSeek Harness 窗口' -ForegroundColor DarkGray
  Write-Host '  都可以自己加，不用改这个文件。' -ForegroundColor Gray
  Write-Host ''
  Write-Host '  在哪里加：' -ForegroundColor Yellow
  Write-Host ('    ' + $customFile) -ForegroundColor White
  Write-Host '    这个文件现在还不存在 —— 把同目录的 pause-custom.example.ps1' -ForegroundColor DarkGray
  Write-Host '    复制一份、改名为 pause-custom.ps1，再改里面的内容即可。' -ForegroundColor DarkGray
  Write-Host '    建好之后，这里就不再显示这段提示了。' -ForegroundColor DarkGray
  Write-Host ''
  Write-Host '  不会写？把这一屏截下来发给 AI（比如 DSH 里的助手），说：' -ForegroundColor Yellow
  Write-Host '    「这是 QQ AI 启动器带的暂停脚本，我想让它顺便把 XX 也关掉，' -ForegroundColor Gray
  Write-Host '      帮我改 pause-custom.ps1」' -ForegroundColor Gray
  Write-Host '  它看到上面的路径和说明，就知道该往哪写。' -ForegroundColor DarkGray
  Write-Host ''
  Write-Host '  窗口太长、一屏截不全？用 QQ 截屏自带的「长截屏」：' -ForegroundColor Yellow
  Write-Host '    1. 按 Ctrl+Alt+A 唤起 QQ 截屏' -ForegroundColor Gray
  Write-Host '    2. 框住这个窗口' -ForegroundColor Gray
  Write-Host '    3. 点工具栏上的「长截屏」，然后往下滚动鼠标' -ForegroundColor Gray
  Write-Host ''
  Write-Host ('=' * 66) -ForegroundColor DarkGray
  Write-Host ''
}

Start-Sleep -Seconds 2
$after = Get-FreeGB
Write-Host ''
Write-Host ("腾完后可用内存: {0} GB（多出 {1} GB）" -f $after, [math]::Round($after - $before, 1)) -ForegroundColor Cyan
Write-Host '恢复: 双击桌面「启动QQ AI」' -ForegroundColor Yellow
Write-Host ''
