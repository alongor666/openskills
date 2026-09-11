---
name: intranet-readonly-db-share
description: >-
  Use when 用户说"本机数据库共享给同事"、"内网只读开放数据库"、"同事要查数据库"、
  "数据库只读共享"、"把一台电脑的库开放给大家研究"，或要在公司内部网络里把某台电脑上
  的数据库开放给同事只读研究、不碰代码与原件时。主路径「只读副本共享」：定时导出快照
  → SMB 只读共享 → 同事内网拿副本用本地工具查，原件零风险、结构性只读；分支路径
  「只读账号直连」：SQL Server / MySQL / PostgreSQL 建只读账号 + 端口限定内网网段放行。
  内置「先探后问」：只读环境探针先行，AUQ 决策点表 + 全参数适配表，零硬编码可适配
  新环境。附环境探针、防火墙、快照共享、接入体检四个零依赖 PowerShell 脚本（探针只读、
  其余默认 dry-run），同事可脱离 AI 独立使用。触发词：数据库共享、内网只读、只读开放、
  数据共享目录、SMB 共享、环境探针、readonly database share、LAN db share。
user_invocable: true
version: "1.2.0"
---

# intranet-readonly-db-share：公司内网数据库只读共享

## Overview

公司内网某台 Windows 电脑上有数据库，同事要在内网**只读研究**：能查、能导出，但改不了库、
碰不到代码与原始文件。立场：**给副本、不给原件**——主路径「快照 → SMB 只读共享」的只读是
结构性的（共享目录由操作系统强制只读，同事拿到的本来就是导出件）；分支路径「只读账号直连」
留给必须看实时数据的场景。全程公司内部网络，不涉及 Tailscale、公网映射，零代码改动。图文版单页：[artifact.html](artifact.html)（浏览器打开，架构图 + 决策树 + 五步流程）。

| 通道 | 做法 | 新鲜度 | 对原件风险 | 适用 |
|---|---|---|---|---|
| A. 只读副本共享（主） | 定时导出快照 → SMB 只读目录 | 快照周期 | 零 | 研究 / 报表 / 日常分析 |
| B. 只读账号直连（分支） | 只读账号 + 端口限定内网放行 | 实时 | 低（直连生产库） | 必须实时 |

## 决策树

```text
同事需要的数据要实时吗？
├─ 不要 → 通道 A：只读副本共享（第 2 节 / GUIDE.md 主路径）
│    文件型（SQLite/DuckDB/Access/Excel）→ 按各库安全导出法生成快照
│    服务型（SQL Server/MySQL/PostgreSQL）→ 备份/导出命令生成快照文件
└─ 要实时 → 通道 B：只读账号直连（第 4 节 / GUIDE.md 分支）
     SQL Server → db_datareader + 1433；MySQL → SELECT 账号 + 3306
     PostgreSQL → 只读角色 + 5432；端口只对公司内网网段放行
```

## 第 0 步 · 先探后问（任何环境下手前必做）

本技能不假设环境。固定顺序：**探测（脚本能测）→ 提问（只能问人）→ 适配（改参数不改技能）**。
先跑只读探针 `scripts\probe-env.ps1`（零副作用），探测覆盖不到的才进入提问。

### 0.1 探明即适配（能探到的不问用户）

| 探什么 | 怎么探 | 探明后适配 |
|---|---|---|
| 操作系统 | probe 首项 | Windows=主路径；macOS/Linux=0.4 非 Windows 适配 |
| 管理员权限 | `net session` 被拒即非管理员 | 非管理员 → 0.4 降级路径，禁止绕权限硬来 |
| 数据库类型 | 服务名 / 1433·3306·5432 监听 / 数据文件扩展名 | 决定通道与安全导出命令 |
| 网络 profile | `Get-NetConnectionProfile` | Public 档拦截 SMB；改档影响整机策略，先问用户/IT |
| 数据盘容量 | 各盘剩余空间 | StageDir / ShareDir 选最大数据盘 |
| 共享名冲突 / 445 | `Get-SmbShare` / 445 监听 | 换 ShareName；Server 服务未跑先处理 |
| 导出工具在位 | sqlite3 / mysqldump / pg_dump / sqlcmd | 缺则换导出法或先补装 |

### 0.2 需求澄清（AUQ 决策点：探不到的才问人）

用运行端原生提问能力（Claude Code=AskUserQuestion，workbuddy 等 Agent 同理），每题给互斥选项与推荐项；非交互 / 超时按保守默认继续并在产出中声明。

| 决策点 | 为什么必须问 | 保守默认 |
|---|---|---|
| 开放哪套库、哪台机器 | 探测只能发现候选，选择权在用户 | 用户指定那台 |
| 通道 A / B | 新鲜度要求是业务决策，探不到 | A（副本共享） |
| 快照周期 | 新鲜度与生产库负载的权衡 | 每天一次 |
| 账号模式（域组 / 本地账号 / 一人一号） | 取决于对方环境与管理方式 | 本地最小账号 |
| 是否含个人敏感字段、审批是否完成 | 法律红线：未脱敏不得开放 | 视为敏感 → 绝对脱敏（不导出，或加盐哈希 / 掩码）＋ 审批通过后才开放 |
| （仅当 probe 报非管理员）走哪条降级路径 | 涉及 IT 协作，用户须知情 | 提 IT 工单，不硬来 |

### 0.3 可变值参数表（零硬编码声明）

| 可变值 | 默认 | 适配 |
|---|---|---|
| StageDir / ShareDir | D:\DbStage / D:\DbShare | 选 probe 显示容量最大的数据盘 |
| ShareName | DbShare | 与既有共享冲突即改 |
| GrantAccount | 本地 dbreader | 域环境填域组；一人一号按名单循环授权 |
| 端口 / ScopeSubnet | 1433 · 网段必填 | 按库型与 `ipconfig` 实测网段 |
| 快照周期 | 每天 | 按 0.2 AUQ 决策 |
| 平台 | Windows 主路径 | macOS / Linux 见 0.4 |

### 0.4 降级与非 Windows 适配

- **无管理员**：① 请 IT 在既有合规共享上开只读子目录；② 数据库端口本已放行 → 直接走通道 B 只读账号；③ 提 IT 工单开通。
- **非 Windows 服务器**：思路不变（导出快照 → 只读文件共享 → 定时任务）：Linux 用 smbd 只读共享 + cron，macOS 用系统文件共享 + launchd，导出命令（mysqldump / pg_dump / sqlite3）跨平台通用。本技能脚本仅 Windows 化是**声明过的边界**，其余平台由 Agent 按此思路现场适配。

## 主路径速查（A：只读副本共享）

**第 0 步先行**：跑 `scripts\probe-env.ps1` 只读探明权限 / 库型 / 网络档位，过 0.1 / 0.2 两张表再动手。

```powershell
# 1) 两个目录：D:\DbStage 暂存（私有） / D:\DbShare 共享（对外只读）
# 2) 按库安全导出快照到 D:\DbStage（SQLite 用 .backup / SQL Server 用 BACKUP DATABASE
#    / MySQL 用 mysqldump / Access·Excel 关闭后复制 —— 完整命令表见 GUIDE.md 第 2 步）
# 3) 镜像 + 建只读共享（先 dry-run 看计划，确认后加 -Apply，需管理员）
pwsh -File scripts\snapshot-share.ps1 -StageDir D:\DbStage -ShareDir D:\DbShare -ShareName DbShare -GrantAccount dbreader
pwsh -File scripts\snapshot-share.ps1 -StageDir D:\DbStage -ShareDir D:\DbShare -ShareName DbShare -GrantAccount dbreader -Apply
# 4) 定时快照（示例：每小时；TR 含空格时注意整体加引号）
schtasks /Create /TN DbSnapshot-Hourly /SC HOURLY /TR "pwsh -NoProfile -File <脚本路径>\snapshot-share.ps1 -StageDir D:\DbStage -ShareDir D:\DbShare -Apply"
# 5) 体检 + 交给同事地址
pwsh -File scripts\verify-access.ps1 -ShareName DbShare
```

无域环境先建共享账号：`New-LocalUser -Name dbreader -Password (Read-Host -AsSecureString 'pwd') -AccountNeverExpires`；域环境 `-GrantAccount` 直接填域组（如 `DOMAIN\dept-group`）。

## 分支路径（B：只读账号直连，要实时才用）

| 库 | 只读账号 | 端口 |
|---|---|---|
| SQL Server | 建登录 → `ALTER ROLE db_datareader ADD MEMBER <用户>` | 1433 |
| MySQL | `CREATE USER 'ro'@'192.168.%'` → `GRANT SELECT ON db.* TO ...` | 3306 |
| PostgreSQL | 只读角色：CONNECT + USAGE + SELECT | 5432 |

端口放行（按实际办公网段，禁止 any）：
```powershell
pwsh -File scripts\setup-firewall.ps1 -Port 1433 -ScopeSubnet 192.168.0.0/16 -Apply
```

## 脚本（默认 dry-run 只打印计划；`-Apply` 才落地）

| 脚本 | 用途 | 通道 |
|---|---|---|
| `snapshot-share.ps1` | robocopy 镜像快照目录 + 建 SMB 只读共享 + NTFS 只读授权 | A 主 |
| `verify-access.ps1` | 服务器侧体检：共享存在 / 目录非空 / 445 监听 / 给同事的地址 | A 主 |
| `setup-firewall.ps1` | 数据库端口入站放行（限定内网网段） | B 分支 |

## 红线（开放期间全程有效）

- **绝对脱敏（法律红线，不是可选项）**：姓名 / 证件号 / 手机号等个人敏感信息，能不导出的一律不导出；确需保留关联性的必须加盐哈希（如 SHA-256）或掩码（如 138****5678），默认不落明文。未脱敏一律不开放；遵守《个人信息保护法》与公司数据制度，敏感范围先审批后共享。
- 原件、代码目录、配置文件（含连接串密码）**绝不进共享目录**；只共享导出副本与只读账号。
- 账号一人一号（或按组），人员变动立即撤；强密码并定期轮换。
- 一切端口只对公司内网网段开放，禁止公网映射 / DMZ。
- 快照周期按研究可接受的新鲜度定，避免高频导出拖垮生产库。

## 收口（不用了就撤干净）

```powershell
Remove-SmbShare -Name DbShare -Force          # 撤共享
Remove-LocalUser -Name dbreader               # 撤共享账号（无域时）
Remove-NetFirewallRule -DisplayName IntranetDbReadonly-1433   # 直连路径撤端口
schtasks /Delete /TN DbSnapshot-Hourly /F     # 撤定时快照
```

完整逐步指引（各库安全导出命令表、同事侧工具表、故障排查、发给同事的一段话）见 [GUIDE.md](GUIDE.md)。

## 何时不用

- 数据库有数据中心正式实例、要长期多人用 → 走 IT 正式开权限，不要拿个人电脑当库服务器。
- 同事要跨网络 / 居家访问 → 超出本技能边界（本技能只覆盖公司内部网络）。

## 决策交互（运行端原生决策界面 · 全仓统一条款）

执行本技能遇到**真分叉**——关键参数缺失、多方案各有实质代价、产出形态影响后续用法、或操作不可逆——时，用当前运行端可用的结构化决策界面向用户提问；Claude Code 使用 AskUserQuestion，Codex 使用其可用的原生提问能力。不擅自替用户拍板，也不抛开放式问题让用户打字描述。

提问要顺滑：同一决策链的问题合并为一次调用（最多 4 题），每题 2-4 个互斥选项；选项 label 简短、description 讲清代价与影响；有推荐项时置于首位并在 label 末尾标注「（推荐）」；多选场景用 multiSelect，不拆成多题。

不问则不扰：答案能从上下文、既有文件与技能约定可靠推出时直接采用并在产出中说明依据；纯机械步骤与用户已明示的事项不再确认。非交互场景（定时任务 / CI / 提问超时）按最保守默认继续并在产出中声明。技能正文另有更具体提问点设计的，按正文执行，本条款兜底。

## 自进化（调用时问题沉淀 · 全仓统一条款）

本次调用中暴露的任何问题——文档误导 / 脚本报错 / 产物不达标 / 描述与触发错位 / 用户纠偏——收尾时追加一条到本技能目录的 `IMPROVEMENTS.md`（不存在则新建）：

`## YYYY-MM-DD · 调用场景一句话`，正文写问题现象（带错误输出或 文件:行号 证据）+ 根因猜测（可空）+ 建议修法（可空）。

约定：该文件只放未消化条目——消化后由复盘轮删除条目、处置记入 `docs/evolution/ledger/`，不在条目上打勾；当场已改技能源码修复的不必记；记录动作不阻塞当前任务。追加后当场在技能源仓 commit 并 push（或随手开 PR），禁止只留在本机工作树——未提交的反馈对其他端与评审轮不可见。复盘入口 `python3 scripts/skill_evolution.py scan`，机制见 `docs/SELF-EVOLUTION.md`。
