<#
  qq-launcher · 公共配置读取模块

  由 start-qq-ai.ps1 / pause-qq-ai.ps1 / remap-session.ps1 点源引用：
      . "$PSScriptRoot\_config.ps1"
      $__tk = Get-ToolkitConfig

  目的：脚本里**不再写死用户名与安装路径**；本机关键词集中在 <项目>\toolkit.config.json。
  查找顺序：
    1) 环境变量 TOOLKIT_CONFIG 指定的文件
    2) 本脚本所在目录（部署到 .dsh\scripts 时配置也会被一起复制过去）
    3) 上一级目录（项目根：qq-launcher\..\toolkit.config.json）
    4) %USERPROFILE%\.dsh\scripts\toolkit.config.json
  全都找不到时，用 %USERPROFILE% 与常见安装路径推导兜底，保证脚本仍能跑。

  ── 2026-10-18 改动：DSH 运行时改成「配置 → 按安装目录推导」两级探测 ──
  为什么：DSH 升级会改 runtime 布局。0.2.0 的 pnpm 在
  resources\runtime\pnpm\bin\pnpm.cjs，0.2.1 挪到了
  resources\runtime\primary-runtime\dependencies\pnpm\bin\pnpm.cjs。
  只要在一处写死，换台机器或升个版本就失效，而且失效时只报「找不到」，
  不告诉用户到底该改哪个字段 —— 这正是「安装不友好」的主因。
  现在：配置里填的路径若不存在，就按 DSH 安装目录去试两种布局；
  仍然找不到，返回值里的 Issues 会带出缺哪一项，由调用方打印可操作的提示。
#>

# 在 DSH 安装根目录下按候选相对路径找文件；找到返回绝对路径，找不到返回空串。
# DSH 安装根目录来源：DshExe 所在目录 → 几个常见安装位置。
# 正在运行的 DSH 进程 → 最可靠的安装位置来源（谁装在哪块盘、哪个目录都可能）。
# 只有在 DSH 已启动时才拿得到；拿不到就退回常见安装位置。
function Find-DshRootFromProcess {
  $procs = @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue)
  foreach ($p in $procs) {
    try {
      if ($p.Path) { return (Split-Path $p.Path -Parent) }
    } catch {}
  }
  return ''
}

# 在 DSH 安装根目录下按候选相对路径找文件；找到返回绝对路径，找不到返回空串。
# 根目录来源（按优先级）：DshExe 所在目录 → 环境变量 DSH_INSTALL_DIR → 运行中的进程
#                        → 两个常见安装位置。**不写死任何具体盘符**。
function Find-DshRuntimeFile {
  [CmdletBinding()]
  param(
    [string]$DshExe = '',
    [string[]]$Relative = @()
  )

  $roots = New-Object System.Collections.Generic.List[string]
  if ($DshExe -and (Test-Path $DshExe)) {
    $roots.Add((Split-Path $DshExe -Parent))
  }
  foreach ($p in @(
      $env:DSH_INSTALL_DIR,
      (Find-DshRootFromProcess),
      'C:\Program Files\DeepSeek Harness',
      (Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness')
    )) {
    if ($p -and (Test-Path $p) -and -not $roots.Contains($p)) { $roots.Add($p) }
  }

  foreach ($r in $roots) {
    foreach ($rel in $Relative) {
      $full = Join-Path $r $rel
      if (Test-Path $full) { return $full }
    }
  }
  return ''
}

function Get-ToolkitConfig {
  [CmdletBinding()]
  param([string]$ConfigPath = '')

  $candidates = @()
  # 顺序即优先级：显式传入的 -ConfigPath 最高（调用方明确指定的应该赢），其次才是环境变量。
  if ($ConfigPath) { $candidates += $ConfigPath }
  if ($env:TOOLKIT_CONFIG) { $candidates += $env:TOOLKIT_CONFIG }
  # $PSScriptRoot 只在「脚本文件里」有值；被人从命令行/REPL dot-source 进来时是空串，
  # 直接 Join-Path 会抛「参数不能为空」—— 这个函数被别人手动调用时不该崩。
  if ($PSScriptRoot) {
    $candidates += (Join-Path $PSScriptRoot 'toolkit.config.json')
    $parentDir = Split-Path $PSScriptRoot -Parent
    if ($parentDir) { $candidates += (Join-Path $parentDir 'toolkit.config.json') }
  }
  $candidates += (Join-Path $env:USERPROFILE '.dsh\scripts\toolkit.config.json')

  $raw = $null
  $used = ''
  foreach ($c in $candidates) {
    if ($c -and (Test-Path $c)) {
      try { $raw = Get-Content $c -Raw -Encoding UTF8 | ConvertFrom-Json; $used = $c; break } catch {}
    }
  }

  function ConvertFrom-Placeholder([string]$s) {
    if (-not $s) { return '' }
    return [Environment]::ExpandEnvironmentVariables($s)
  }

  $u = $env:USERPROFILE
  $cfg = [pscustomobject]@{
    BridgeDir     = ConvertFrom-Placeholder $raw.bridgeDir
    SnowlumaDir   = ConvertFrom-Placeholder $raw.snowlumaDir
    DshScriptsDir = ConvertFrom-Placeholder $raw.dshScriptsDir
    DshProfileDir = ConvertFrom-Placeholder $raw.dshProfileDir
    DshExe        = ConvertFrom-Placeholder $raw.dshExe
    DshNode       = ConvertFrom-Placeholder $raw.dshNode
    PnpmCli       = ConvertFrom-Placeholder $raw.pnpmCli
    QqExe         = ConvertFrom-Placeholder $raw.qqExe
    PclPath       = ConvertFrom-Placeholder $raw.pclPath
    OwnerQQ       = $raw.ownerQQ
    ConfigFile    = $used
    DshRoot       = ''
    Issues        = @()
  }

  # ── 兜底推导（配置缺失或字段为空时）──────────────────────────────────
  if (-not $cfg.BridgeDir)     { $cfg.BridgeDir     = Join-Path $u '.dsh\qq-bridge' }
  if (-not $cfg.SnowlumaDir)   { $cfg.SnowlumaDir   = Join-Path $u '.dsh\snowluma\app' }
  if (-not $cfg.DshScriptsDir) { $cfg.DshScriptsDir = Join-Path $u '.dsh\scripts' }
  if (-not $cfg.DshProfileDir) { $cfg.DshProfileDir = Join-Path $u '.dsh\profiles\desktop' }
  if (-not $cfg.QqExe)         { $cfg.QqExe         = 'C:\Program Files\Tencent\QQNT\QQ.exe' }
  if (-not $cfg.PclPath)       { $cfg.PclPath       = '' }

  # ── DSH 安装目录：配置无效就试常见安装位置 ──────────────────────────
  # 顺序：环境变量 DSH_INSTALL_DIR → 运行中的 DSH 进程 → 两个常见安装位置。
  # **不写死任何盘符**：作者的安装位置对别人没有意义，写死只会让人以为「这脚本只能在他机器上跑」。
  if (-not $cfg.DshExe -or -not (Test-Path $cfg.DshExe)) {
    $procRoot = Find-DshRootFromProcess
    foreach ($p in @(
        $(if ($env:DSH_INSTALL_DIR) { Join-Path $env:DSH_INSTALL_DIR 'DeepSeek Harness.exe' }),
        $(if ($procRoot) { Join-Path $procRoot 'DeepSeek Harness.exe' }),
        'C:\Program Files\DeepSeek Harness\DeepSeek Harness.exe',
        (Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\DeepSeek Harness.exe')
      )) {
      if ($p -and (Test-Path $p)) { $cfg.DshExe = $p; break }
    }
  }
  if ($cfg.DshExe -and (Test-Path $cfg.DshExe)) { $cfg.DshRoot = Split-Path $cfg.DshExe -Parent }

  # ── DSH 自带 node：配置无效就按安装目录推（覆盖两种 runtime 布局）────
  if (-not $cfg.DshNode -or -not (Test-Path $cfg.DshNode)) {
    $hit = Find-DshRuntimeFile -DshExe $cfg.DshExe -Relative @(
      'resources\runtime\primary-runtime\dependencies\node\bin\node.exe',
      'resources\runtime\node\bin\node.exe'
    )
    if ($hit) { $cfg.DshNode = $hit }
  }

  # ── DSH 自带 pnpm：同上（这是最容易过期的一项）─────────────────────
  if (-not $cfg.PnpmCli -or -not (Test-Path $cfg.PnpmCli)) {
    $hit = Find-DshRuntimeFile -DshExe $cfg.DshExe -Relative @(
      'resources\runtime\primary-runtime\dependencies\pnpm\bin\pnpm.cjs',
      'resources\runtime\pnpm\bin\pnpm.cjs'
    )
    if ($hit) { $cfg.PnpmCli = $hit }
  }

  # ── 缺失清单：调用方据此打印「该改哪一项」而不是泛泛的「找不到」──────
  $issues = New-Object System.Collections.Generic.List[string]
  if (-not $cfg.DshExe  -or -not (Test-Path $cfg.DshExe))  { $issues.Add('dshExe') }
  if (-not $cfg.DshNode -or -not (Test-Path $cfg.DshNode)) { $issues.Add('dshNode') }
  if (-not $cfg.PnpmCli -or -not (Test-Path $cfg.PnpmCli)) { $issues.Add('pnpmCli') }
  if (-not $cfg.BridgeDir -or -not (Test-Path $cfg.BridgeDir)) { $issues.Add('bridgeDir') }
  $cfg.Issues = @($issues)

  return $cfg
}

# 把缺失项翻译成人能照做的提示（供 start-qq-ai.ps1 / install.ps1 共用）。
# 返回字符串数组，每行一条；空数组表示一切正常。
# -Only 限定只报哪几项（启动脚本只关心致命项，不想顺带抱怨 pnpm）。
function Get-ToolkitConfigHints {
  [CmdletBinding()]
  param($Config, [string[]]$Only = @())

  $hints = @()
  if (-not $Config) { return @('配置为空') }

  $where = if ($Config.ConfigFile) { $Config.ConfigFile } else { 'toolkit.config.json' }
  $sel = if ($Only -and $Only.Count -gt 0) { $Only } else { @('dshExe', 'dshNode', 'pnpmCli', 'bridgeDir') }

  if (($sel -contains 'dshExe') -and ($Config.Issues -contains 'dshExe')) {
    $hints += "找不到 DSH 主程序（dshExe = '$($Config.DshExe)'）。"
    $hints += "  → 打开 $where，把 dshExe 改成你的「DeepSeek Harness.exe」完整路径。"
    $hints += "    一般在「<你安装 DSH 的目录>\DeepSeek Harness.exe」，例如 C:\Program Files\DeepSeek Harness\DeepSeek Harness.exe"
  }
  if (($sel -contains 'dshNode') -and ($Config.Issues -contains 'dshNode')) {
    $hints += "找不到 DSH 自带的 node（dshNode = '$($Config.DshNode)'）。"
    $hints += "  → 打开 $where，把 dshNode 改成：<DSH安装目录>\resources\runtime\primary-runtime\dependencies\node\bin\node.exe"
    $hints += "    （旧版 DSH 可能在 <DSH安装目录>\resources\runtime\node\bin\node.exe）"
  }
  if (($sel -contains 'pnpmCli') -and ($Config.Issues -contains 'pnpmCli')) {
    $hints += "找不到 DSH 自带的 pnpm（pnpmCli = '$($Config.PnpmCli)'）。"
    $hints += "  → 打开 $where，把 pnpmCli 改成：<DSH安装目录>\resources\runtime\primary-runtime\dependencies\pnpm\bin\pnpm.cjs"
    $hints += "    （旧版 DSH 可能在 <DSH安装目录>\resources\runtime\pnpm\bin\pnpm.cjs）"
    $hints += "    只有 install.ps1 装 node 依赖时才用到它，一键启动不受影响。"
  }
  if (($sel -contains 'bridgeDir') -and ($Config.Issues -contains 'bridgeDir')) {
    $hints += "找不到 qq-bridge 桥接目录（bridgeDir = '$($Config.BridgeDir)'）。"
    $hints += "  → 确认你已经 clone 了 qq-bridge，并在 $where 里把 bridgeDir 指到它。"
  }
  return $hints
}
