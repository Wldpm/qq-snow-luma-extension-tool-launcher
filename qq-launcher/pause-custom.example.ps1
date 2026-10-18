<#
  pause-custom.example.ps1 —— 「暂停 QQ AI」的自定义动作

  怎么用：
    1. 把本文件复制成同目录的 pause-custom.ps1
    2. 改下面的 Invoke-PauseCustom 函数（或保持原样）
    3. 双击「暂停QQ AI」时，停完 QQ AI 之后会自动调用它

  为什么这么设计：
    仓库里只保留「停掉 QQ AI」这一个通用动作。像关浏览器、调内存优化、
    关掉其它程序这种高度依赖个人环境的操作，放在 pause-custom.ps1 里自己定义，
    不会跟着仓库发给别人，也不会因为别人机器上没有那个程序而报错。

  注意：
    · pause-custom.ps1 已在 .gitignore 里，你的个人配置不会进仓库
    · 需要管理员权限的操作（给别的程序传 --memory 之类）用
      Start-Process -Verb RunAs，系统会自己弹 UAC，不需要整个脚本提权
    · 别放会一直等待的操作，否则双击后窗口会卡住
#>

function Invoke-PauseCustom {
  Write-Host '     （未配置自定义动作）' -ForegroundColor DarkGray

  # ── 例子 1：调用某个程序自带的内存优化 ──────────────────────────────
  # Start-Process -FilePath 'C:\你的程序\程序.exe' -ArgumentList '--memory' -Verb RunAs
  # Start-Sleep -Seconds 15

  # ── 例子 2：关掉占内存的浏览器 ──────────────────────────────────────
  # Get-Process -Name chrome, msedge, firefox -ErrorAction SilentlyContinue | Stop-Process -Force

  # ── 例子 3：关掉所有 DeepSeek Harness 实例 ──────────────────────────
  # Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Stop-Process -Force
}
