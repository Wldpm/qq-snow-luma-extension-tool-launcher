# qq_launcher

一键把 QQ AI 的整套服务拉起来：**DSH → QQ → SnowLuma → OneBot → 桥接**。
附带「暂停 / 腾内存」和「会话映射挂回」。

---

## 这是什么

一组 PowerShell 脚本 + 桌面入口，把原本要手动开四五个窗口的流程合成「双击一次」。

它**不包含** DSH、QQ、SnowLuma、qq-bridge 本体 —— 只是按顺序把已经装好的它们拉起来，
并在中途做几件容易忘的事：等 OneBot 就绪、同步 DSH 的随机端口、检查会话映射。

---

## 能干什么

| 我要… | 双击 | 效果 |
|---|---|---|
| 启动整套服务 | 启动QQ AI | 依次检查 DSH/QQ → 等 OneBot → 同步端口 → 拉起桥接（窗口内实时日志，关窗即停） |
| 全停 / 腾内存 | 暂停QQ AI | 停掉桥接 + SnowLuma + MCP；可选追加自定义动作 |
| 看桥接控制台 | QQ桥接控制台 | 打开带令牌的控制台页面 |
| 会话乱了想挂回 | 运行 `remap-session.ps1` | 列出历史会话，选一个挂回去 |

---

## 安装

### 依赖

| 依赖 | 必需 | 说明 |
|---|---|---|
| Windows PowerShell 5.1+ | ✅ | 系统自带 |
| DSH | ✅ | 用它的 node 跑桥接；安装位置自动探测 |
| QQ（QQNT） | ✅ | 要登录机器人账号 |
| SnowLuma | ✅ | QQ 网关，另装 |
| qq-bridge | ✅ | 桥接本体，第三方仓库，另 clone |
| 任意可选程序（游戏启动器之类） | ⭕ | 只有「暂停」的自定义动作会用到 |

### 自己动手

```powershell
cd <这个文件夹>

# 1) 准备配置
copy toolkit.config.example.json toolkit.config.json

# 2) 部署到运行位置
powershell -ExecutionPolicy Bypass -File deploy-launcher.ps1
```

第 1 步之后**只在 DSH 不在默认位置时才需要改** `toolkit.config.json`：

| 字段 | 改成 |
|---|---|
| `dshExe` | `<你的DSH安装目录>\DeepSeek Harness.exe` |
| `dshNode` | `<你的DSH安装目录>\resources\runtime\primary-runtime\dependencies\node\bin\node.exe` |

DSH 正在运行时脚本会按进程路径自己找，多数情况不用改。填错也不卡死 ——
会探测两种常见目录结构，探不到才停下并说明改哪个字段。

**不需要管理员**：它只写你自己的用户目录。要不要管理员只在自定义动作里单独决定（见下）。

### 让 AI 帮你装

把下面这段发给 DSH 里的 AI：

> 我在 `<把这个文件夹的完整路径粘这里>` 下载了 QQ AI 的启动器仓库（qq_launcher）。
> 帮我部署：读它的 README.md，确认我 DSH 装在哪（别猜，用探测或者直接问我），
> 把 `toolkit.config.json` 准备好（复制模板 + 改好路径），然后运行 `deploy-launcher.ps1`。
> 装完告诉我怎么启动、怎么暂停、出问题先看哪里。

### 怎么算装好了

按顺序确认，三条全对上才算成功：

| # | 检查什么 | 应该看到 |
|---|---|---|
| 1 | `deploy-launcher.ps1` 跑完 | 最后一行 **`全部一致（N 个）—— 桌面快捷方式可直接使用`** |
| 2 | 双击桌面「启动QQ AI」 | 窗口里依次出现 DSH / QQ / SnowLuma / OneBot 的状态，最后打印 `控制台: http://127.0.0.1:3100` |
| 3 | 浏览器打开那个地址 | 能打开控制台页面 |

第 2 步卡住时，窗口里的提示会直接告诉你缺哪一环（DSH 没开、QQ 没登录、OneBot 没起来）。

---

## 装不上？对照这张表

| 现象 | 怎么办 |
|---|---|
| 双击后窗口一闪就没了 | 别双击 `.ps1`。用桌面 `.cmd` 入口，或右键 →「使用 PowerShell 运行」 |
| 提示「禁止运行脚本 / 无法加载文件」 | 命令里的 `-ExecutionPolicy Bypass` 不能省 |
| 提示「找不到 DSH 自带的 node」 | 改 `toolkit.config.json` 的 `dshNode`（路径格式见上表） |
| 提示「没有检测到 DSH」 | 先手动打开 DSH，等它加载完，再在窗口里按任意键继续 |
| 改了脚本但没生效 | 忘了跑 `deploy-launcher.ps1` —— 桌面调的是 `.dsh\scripts\` 里的副本 |
| 不确定有没有同步成功 | `deploy-launcher.ps1 -Check`，只比对不复制 |

---

## 暂停时想额外腾内存 / 关程序

仓库里只带「停掉 QQ AI」这一个**通用**动作（桥接 + SnowLuma + MCP），因为它对任何人都成立。
像关浏览器、调某个程序的内存优化、关掉别的 DSH 实例这种**高度依赖个人环境**的操作，
放在本机自定义文件里：

1. 把 `qq-launcher/pause-custom.example.ps1` 复制成 `qq-launcher/pause-custom.ps1`
2. 改里面的 `Invoke-PauseCustom` 函数
3. 双击「暂停QQ AI」时，停完 QQ AI 之后会自动调用它

`pause-custom.ps1` 已在 `.gitignore` 里，个人配置不会跟着仓库发给别人。
example 里给了三个例子（调程序内存优化 / 关浏览器 / 关 DSH），取消注释即可用。
需要管理员的操作在那个函数里用 `Start-Process -Verb RunAs` 单独提权，系统会自己弹 UAC。

---

## 内部细节

### 脚本清单

| 文件 | 作用 |
|---|---|
| `qq-launcher/start-qq-ai.ps1` | 主入口：检查 → 等 OneBot → 同步端口 → 拉桥接 |
| `qq-launcher/pause-qq-ai.ps1` | 停 QQ AI，然后调用自定义动作 |
| `qq-launcher/pause-custom.example.ps1` | 自定义动作模板 |
| `qq-launcher/remap-session.ps1` | 会话映射挂回 |
| `qq-launcher/_config.ps1` | 配置读取 + DSH 路径自动探测 |
| `qq-launcher/*.cmd`、`*.url` | 桌面入口（模板，控制台令牌需自行生成） |
| `deploy-launcher.ps1` | 部署到 `%USERPROFILE%\.dsh\scripts\` 并 MD5 校验 |
| `make-console-shortcut.ps1` | 生成带真令牌的控制台快捷方式 |

### 哪些是源码

✅ 进 git；❌ 生成物 / 本机状态，已在 `.gitignore` 里。

| 文件 | 入库 |
|---|---|
| `qq-launcher/*.ps1`、`*.cmd`、`*.url` | ✅ 源码 |
| `deploy-launcher.ps1`、`make-console-shortcut.ps1` | ✅ 源码 |
| `toolkit.config.example.json` | ✅ 入库 |
| `qq-launcher/pause-custom.ps1`、`pcl-path.txt`、`toolkit.config.json` | ❌ 本机状态 |

### 给 Agent 的说明

> 以下是给 AI 的执行指令。

**部署**

1. 入口 `deploy-launcher.ps1`。它把 `qq-launcher\*.ps1` 和 `toolkit.config.json` 复制到 `%USERPROFILE%\.dsh\scripts\`，脚本按绝对路径调那边。
2. 改路径只动 `toolkit.config.json`，不要改 `_config.ps1` 的探测逻辑。
3. `-Check` 只比对不复制；正常部署会自己做 MD5 校验。
4. 不要用管理员权限；不要手动改 `%USERPROFILE%\.dsh\scripts\` 里的副本（会被下次部署覆盖）。

**部署后**

5. 报告结果：部署到哪、MD5 是否全部一致。
6. 告诉用户怎么测：双击「启动QQ AI」看 DSH / QQ / SnowLuma / OneBot 依次就绪，最后打印 `控制台: http://127.0.0.1:3100` 且浏览器能打开；再双击「暂停QQ AI」确认能停掉。
7. 停下来问用户谁来测 —— 原话：「你自己试，还是要我代你搞？」
8. 用户说「你来搞吧」再动手；说「我自己来」就到此为止 —— 启动和暂停会动真实进程，该由用户决定谁来做，不要默认代劳。

**用户想要额外动作时**

9. 让他改 `qq-launcher/pause-custom.ps1`（或从 `pause-custom.example.ps1` 复制）。不要把这些动作写进 `pause-qq-ai.ps1` —— 那是要发给别人的通用部分。