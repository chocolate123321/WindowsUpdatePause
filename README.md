# Windows 更新暂停 9999 天

把 Windows 10/11 的「暂停更新」到期日设成从今天起 9999 天（约 27 年），
并提供配套的还原脚本。单文件、免安装、可整包分享给别人。

## 文件清单

| 文件 | 作用 |
| --- | --- |
| `Pause-WindowsUpdate.cmd` | 双击运行，暂停更新（推荐入口） |
| `Pause-WindowsUpdate.ps1` | 实际逻辑：提权 + 备份 + 写注册表 + 回读校验 |
| `Restore-WindowsUpdate.cmd` | 双击运行，撤销暂停、恢复自动更新 |
| `Restore-WindowsUpdate.ps1` | 实际逻辑：删值或从备份 .reg 还原 |
| `backup\\` | 每次执行前自动导出的注册表原值（首次运行时创建） |

## 用法

**普通用户**：双击 `Pause-WindowsUpdate.cmd` → UAC 点「是」→ 看清单 → 逐字输入 `YES` 回车。

**先看效果不写入**：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Pause-WindowsUpdate.ps1 -DryRun
```

**自定义天数**（上限 36500 天）：

```powershell
.\Pause-WindowsUpdate.ps1 -Days 3650
```

**静默执行**（跳过确认，给批处理用）：

```powershell
.\Pause-WindowsUpdate.ps1 -Days 9999 -Yes
```

**撤销**：

```powershell
.\Restore-WindowsUpdate.ps1                        # 删掉暂停相关值，恢复自动更新
.\Restore-WindowsUpdate.ps1 -FromReg .\backup\UX-Settings-20261108-170000.reg   # 完整还原旧值
```

## 原理

「设置 > Windows 更新」里的暂停状态存在这个键下：

```
HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings
```

本工具写入 7 个值：

| 值名 | 类型 | 内容 |
| --- | --- | --- |
| `PauseUpdatesStartTime` | REG_SZ | 暂停开始时间，UTC ISO 8601 |
| `PauseUpdatesExpiryTime` | REG_SZ | 暂停到期时间，UTC ISO 8601 |
| `PauseFeatureUpdatesStartTime` | REG_SZ | 功能更新暂停开始 |
| `PauseFeatureUpdatesEndTime` | REG_SZ | 功能更新暂停到期 |
| `PauseQualityUpdatesStartTime` | REG_SZ | 质量更新暂停开始 |
| `PauseQualityUpdatesEndTime` | REG_SZ | 质量更新暂停到期 |
| `FlightSettingsMaxPauseDays` | REG_DWORD | 设置页允许的最大暂停天数 |

时间格式固定为 `yyyy-MM-ddTHH:mm:ssZ`（UTC、秒级、无毫秒）。
`FlightSettingsMaxPauseDays` 设为 9999 后，设置页的「暂停 5 周」按钮上限也会同步变成 9999 天。

设置页每次都实时读这几个值，所以**改完不需要重启服务、不需要重启电脑**，
关掉设置窗口重开即可看到新日期。

## 已验证

在 Windows 11 24H2（10.0.26100）上实测：写完后设置页显示「已暂停更新至 2053-10-30」，
且 `PauseFeatureUpdatesEndTime` 与 `PauseQualityUpdatesEndTime` 回读值与写入值一致，无截断。

## 注意事项

- **必须管理员**：脚本会自动弹 UAC 提权，拒绝授权则什么都不做。
- **会改动系统配置**：写的是 HKLM 注册表，执行前会把整个键导出到 `backup\\`。
- **到期后会恢复更新**：9999 天后（约 2054 年）Windows 会自行恢复；在此之前重跑一次即可续期。
- **杀软可能误报**：脚本会提权 + 写注册表，部分安全软件会拦截。这是行为特征，不是病毒。
- **组策略优先**：如果目标机器被域策略或「配置自动更新」策略接管（`HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate`），
  脚本写的值可能被策略覆盖。脚本回读时会检测并提示。
- **不是永久关闭**：这是暂停，不是卸载更新功能。真有安全补丁需求时请手动恢复。
- 只改「暂停」相关值，不碰 `wuauserv`、`UsoSvc`、`WaaSMedicSvc` 等服务，也不改任何策略键。

## 分享给别人

把整个 `win-update-pause-20261108\\` 文件夹打包发出去即可，脚本不依赖本机任何绝对路径。
对方机器需要 Windows 10 1903 以上 / Windows 11，且 PowerShell 5.1 可用（系统自带）。
