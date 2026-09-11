# openskills · 公开技能集

可公开复用的 AI 技能集。本仓是**发布渠道**：技能的唯一事实源在私有仓 alongor666-skills，本仓只镜像收录其中不涉密、跨团队可复用的条目。

## 安装

```bash
npx skills add alongor666/openskills --skill intranet-readonly-db-share
```

逐个单装（逗号批量会静默失败）；公开仓无需任何 GitHub 凭据。

## 收录清单

| 技能 | 用途 | 版本 |
|---|---|---|
| intranet-readonly-db-share | 公司内网把一台 Windows 电脑上的数据库只读开放给同事研究：主路径「快照导出 → SMB 只读共享」原件零风险，分支「只读账号直连」要实时才用；附 3 个零依赖 PowerShell 脚本（默认 dry-run） | 1.0.0 |

## 收录标准

- 不含公司名、内部网络地址、账号凭据、业务数据
- 通用场景、跨团队可复用，配置即用不依赖特定项目
- 各 SKILL.md 末尾「决策交互 / 自进化」两条统一条款源自私有技能治理仓约定，随文保留

## License

MIT
