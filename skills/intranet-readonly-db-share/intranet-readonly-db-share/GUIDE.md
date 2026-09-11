# 公司内网数据库只读共享 · 完整指引

> 场景：公司内网里，某台 Windows 电脑上有一套数据库，同事想**只读研究**——能查、能导出，
> 但改不了库、碰不到代码和原始文件。本指引只做配置和命令，**不改任何一行代码**；不依赖
> Tailscale、不暴露公网，全程公司内部网络；同事可脱离 AI 独立照做。示例假设有本地管理员权限。
>
> 🖼 **图文版**：同目录 `artifact.html`，浏览器打开一页看懂（架构图 / 决策树 / 五步流程），零外链离线可开。

## 0. 原理：为什么"给副本"是最稳的只读

| 通道 | 做法 | 数据新鲜度 | 对原件的风险 | 适用 |
|---|---|---|---|---|
| A. 只读副本共享（主路径） | 定时导出快照 → SMB 只读共享目录 | 快照周期 | **零**（同事拿不到原件） | 研究、报表、日常分析 |
| B. 只读账号直连（分支） | 数据库建只读账号 + 端口限定内网放行 | 实时 | 低（有账号权限墙，但直连生产库） | 必须看实时数据 |

主路径的只读是**结构性的**：共享目录由操作系统强制只读，同事复制走的本来就是导出副本，
原件、代码、凭证一样都到不了对方手里。不是靠叮嘱，是没有第二条路。

## 1. 决策树：30 秒选通道

```text
同事需要的数据要实时吗？
├─ 不要（研究/报表/日常分析）→ 通道 A：只读副本共享（第 2 节）
│    文件型库（SQLite/DuckDB/Access/Excel）→ 复制/导出文件即快照
│    服务型库（SQL Server/MySQL/PostgreSQL）→ 备份/导出命令生成快照文件
└─ 要实时 → 通道 B：只读账号直连（第 4 节）
     按库建只读账号 + 端口只对公司内网网段放行
```

## 2. 主路径五步（A：只读副本共享）

### 第 1 步：建两个目录

```powershell
New-Item -ItemType Directory -Force -Path D:\DbStage, D:\DbShare
```

`D:\DbStage` 是**快照暂存区**（本机私有，谁都不共享）；`D:\DbShare` 是**共享目录**（即将对外只读）。分开是为了共享目录里永远只有干净的导出件。

### 第 2 步：把数据库安全地导出成快照（按库选命令）

| 库 | 安全快照命令（导出到 D:\DbStage） | 备注 |
|---|---|---|
| SQLite | `sqlite3 源库.db ".backup 'D:\DbStage\copy.db'"` | 在线备份 API，库在用也安全 |
| DuckDB | 无写入时直接复制；在写时源库执行 `EXPORT DATABASE 'D:\DbStage\db' (FORMAT PARQUET);` | 别裸拷正在写的文件 |
| Access / Excel | 关闭文件后直接复制到 D:\DbStage | 最简单 |
| SQL Server | `sqlcmd -E -Q "BACKUP DATABASE [库名] TO DISK='D:\DbStage\库名.bak'"` | .bak 可在同事机还原 |
| MySQL | `mysqldump --single-transaction -u 用户 -p 库名 > D:\DbStage\库名.sql` | --single-transaction 不锁库 |
| PostgreSQL | `pg_dump -U 用户 -f D:\DbStage\库名.sql 库名` | — |
| 任意库通用 | 导出 CSV / Parquet 到 D:\DbStage | Excel / DuckDB / PowerBI 都能吃 |

### 第 3 步：镜像到共享目录并建 SMB 只读共享

无域环境先建一个仅供共享的本地账号（管理员终端）：

```powershell
New-LocalUser -Name dbreader -Password (Read-Host -AsSecureString '输入共享账号密码') -AccountNeverExpires -PasswordNeverExpires
```

域环境跳过这步，后面 `-GrantAccount` 直接填域账号或域组（如 `DOMAIN\dept-group`）。

然后建只读共享（先 dry-run 看计划，确认后加 `-Apply`，需管理员）：

```powershell
pwsh -File scripts\snapshot-share.ps1 -StageDir D:\DbStage -ShareDir D:\DbShare -ShareName DbShare -GrantAccount dbreader
pwsh -File scripts\snapshot-share.ps1 -StageDir D:\DbStage -ShareDir D:\DbShare -ShareName DbShare -GrantAccount dbreader -Apply
```

脚本做了三件事：robocopy 镜像快照目录 → NTFS 只授权（RX）→ `New-SmbShare -ReadAccess` 建操作系统级只读共享。

### 第 4 步：网络连通（445 通常已通）

公司内网 Windows 之间的 SMB（445 端口）一般由"文件和打印机共享"策略放行，通常**无需额外操作**。同事连不上时按第 6 节排查；仍不通就联系 IT 开通——**不要自行做任何公网映射**。

### 第 5 步：定时快照 + 验证

定时快照（示例每小时一次；路径按实际改，`/TR` 内容含空格时整体加引号）：

```powershell
schtasks /Create /TN DbSnapshot-Hourly /SC HOURLY /TR "pwsh -NoProfile -File D:\dbshare\scripts\snapshot-share.ps1 -StageDir D:\DbStage -ShareDir D:\DbShare -Apply"
```

服务器侧一键体检（共享存在 / 目录非空 / 445 监听 / 打印给同事的地址）：

```powershell
pwsh -File scripts\verify-access.ps1 -ShareName DbShare
```

同事侧两连验证：

```powershell
Test-NetConnection <服务器IP> -Port 445     # TrueRemoteAddress 才算通
dir \\<服务器IP>\DbShare                    # 能列出快照文件
```

共享期间把服务器电源设为"从不睡眠"（设置 → 系统 → 电源），一睡眠同事全部失联。

## 3. 同事侧怎么用副本

| 拿到的副本 | 推荐打开方式 |
|---|---|
| .db（SQLite） | DB Browser for SQLite（免费） |
| .duckdb / .parquet | DuckDB CLI 或任何支持 DuckDB 的客户端 |
| .bak（SQL Server 备份） | 还原到本机 SQL Server 实例（SSMS） |
| .sql（mysqldump / pg_dump） | 本机导入后任意客户端查 |
| .csv / .xlsx | Excel / WPS 直接开 |
| .accdb（Access） | Access |

习惯：把副本**拷回本机再研究**，别在共享目录里直接改（反正也改不了，只读）。

## 4. 分支路径 B：只读账号直连（要实时才用）

能不用就不用——直连动了生产库本体。按库建只读账号：

| 库 | 只读账号命令 | 端口 |
|---|---|---|
| SQL Server | `CREATE LOGIN ro WITH PASSWORD='<强密码>';` → 库内 `CREATE USER ro FOR LOGIN ro;` `ALTER ROLE db_datareader ADD MEMBER ro;` | 1433 |
| MySQL | `CREATE USER 'ro'@'192.168.%' IDENTIFIED BY '<强密码>';` `GRANT SELECT ON 库名.* TO 'ro'@'192.168.%';` `FLUSH PRIVILEGES;` | 3306 |
| PostgreSQL | `CREATE ROLE ro LOGIN PASSWORD '<强密码>';` `GRANT CONNECT ON DATABASE 库名 TO ro;` `GRANT USAGE ON SCHEMA public TO ro;` `GRANT SELECT ON ALL TABLES IN SCHEMA public TO ro;` | 5432 |

端口放行（按实际办公网段，禁止 any）：

```powershell
pwsh -File scripts\setup-firewall.ps1 -Port 1433 -ScopeSubnet 192.168.0.0/16 -Apply
```

同事用 SSMS / DBeaver / Excel 数据连接 / PowerBI 直连即可。账号密码强 + 定期轮换，人走即撤。

## 5. 红线（开放期间全程有效）

- 客户敏感字段（姓名、证件号、手机号等）**能脱敏先脱敏**，共享范围最小必要；遵守公司数据安全制度，敏感范围先走审批再开放。
- 原件、代码目录、配置文件（含连接串里的密码）**绝不进共享目录**；只共享导出副本与只读账号。
- 账号一人一号（或按组），人员变动 / 项目结束立即撤；强密码并定期轮换。
- 一切端口只对公司内网网段开放；禁止公网端口映射、禁止路由器 DMZ。
- 快照周期按研究可接受的新鲜度定，别把高频导出做成拖垮生产库的新负载。

## 6. 故障排查

| 症状 | 大概率原因 | 处置 |
|---|---|---|
| 同事打不开 \\<IP>\DbShare 或要密码 | 共享账号没建对 / GrantAccount 没配 | 服务器侧跑 verify-access.ps1；确认共享 ReadAccess 含同事账号 |
| 能看到共享但里面是空的 | 快照没导出 / Stage 路径不对 | 手动跑一次 snapshot-share.ps1 -Apply 看 robocopy 结果 |
| Test-NetConnection 445 失败 | 445 被禁或跨网段不通 | 服务器查 Get-SmbShare 与防火墙"文件和打印机共享"规则；联系 IT |
| 副本文件打不开 / 损坏 | 快照时源库正在写（裸拷活文件） | 改用第 2 步各库安全导出命令，别直接复制在写的库文件 |
| 直连 1433/3306/5432 拒绝 | 端口没放行 / 只读账号没建 | setup-firewall.ps1 + 第 4 节账号命令 |

## 7. 收口与撤销（不用了就撤干净）

```powershell
Remove-SmbShare -Name DbShare -Force          # 撤共享
Remove-LocalUser -Name dbreader               # 撤共享账号（无域时）
Remove-NetFirewallRule -DisplayName IntranetDbReadonly-1433   # 直连路径撤端口
schtasks /Delete /TN DbSnapshot-Hourly /F     # 撤定时快照
```

## 8. 附：发给同事的一段话（可直接粘贴）

```text
我把数据库快照共享在公司内网了，只读：
1) 资源管理器地址栏输入 \\<服务器IP>\DbShare，账号密码我单独发你；
2) 把里面的副本拷回你本机再打开研究（共享目录是只读的，也改不了）；
3) 数据按周期自动更新；要在脚本里连实时库的话找我拿只读账号。
```
