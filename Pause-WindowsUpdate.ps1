<#
.SYNOPSIS
    把 Windows 更新的「暂停更新」到期日推后到指定天数之后（默认 9999 天）。
.DESCRIPTION
    设置 > Windows 更新 里的「暂停更新」状态，来自注册表键
      HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings
    下的 6 个字符串值 + 1 个 DWORD：
      PauseUpdatesStartTime          暂停开始时间（UTC，ISO 8601）
      PauseUpdatesExpiryTime         暂停到期时间（UTC，ISO 8601）
      PauseFeatureUpdatesStartTime   功能更新暂停开始
      PauseFeatureUpdatesEndTime     功能更新暂停到期
      PauseQualityUpdatesStartTime   质量更新暂停开始
      PauseQualityUpdatesEndTime     质量更新暂停到期
      FlightSettingsMaxPauseDays     设置页允许的最大暂停天数（DWORD）
    改完不需要重启服务，下次打开设置页即可看到新的到期日。
.PARAMETER Days
    暂停天数，默认 9999，允许 1 - 36500。
.PARAMETER DryRun
    只显示将要写入的值，不改注册表。
.PARAMETER Yes
    跳过交互确认（供批处理调用），同时不再等待回车。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Pause-WindowsUpdate.ps1 -DryRun
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Pause-WindowsUpdate.ps1 -Days 9999
.NOTES
    适用于 Windows 10 1903+ 与 Windows 11，需要管理员权限。
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 36500)][int]$Days = 9999,
    [switch]$DryRun,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$RegistryPath = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'

# ---- 没有管理员权限就自提升 ----
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '[*] 需要管理员权限，正在重新以管理员身份启动...' -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'), '-Days', $Days)
    if ($DryRun) { $argList += '-DryRun' }
    if ($Yes)    { $argList += '-Yes' }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs | Out-Null
    } catch {
        Write-Host ('[x] 提权被取消或失败：' + $_.Exception.Message) -ForegroundColor Red
        Read-Host '按回车退出' | Out-Null
    }
    exit
}

# ---- 计算起止时间（UTC，秒级）----
$startUtc = (Get-Date).ToUniversalTime()
$startUtc = $startUtc.AddTicks(-($startUtc.Ticks % [TimeSpan]::TicksPerSecond))
$endUtc   = $startUtc.AddDays($Days)
$startText = $startUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
$endText   = $endUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")

$entries = @(
    [pscustomobject]@{ Name = 'PauseUpdatesStartTime';         Kind = 'String'; Value = $startText },
    [pscustomobject]@{ Name = 'PauseUpdatesExpiryTime';        Kind = 'String'; Value = $endText },
    [pscustomobject]@{ Name = 'PauseFeatureUpdatesStartTime';  Kind = 'String'; Value = $startText },
    [pscustomobject]@{ Name = 'PauseFeatureUpdatesEndTime';    Kind = 'String'; Value = $endText },
    [pscustomobject]@{ Name = 'PauseQualityUpdatesStartTime';  Kind = 'String'; Value = $startText },
    [pscustomobject]@{ Name = 'PauseQualityUpdatesEndTime';    Kind = 'String'; Value = $endText },
    [pscustomobject]@{ Name = 'FlightSettingsMaxPauseDays';    Kind = 'DWord';  Value = $Days }
)

# ---- 当前状态 ----
Write-Host ''
Write-Host '=== 当前状态 ===' -ForegroundColor Cyan
if (Test-Path $RegistryPath) {
    $current = Get-ItemProperty -Path $RegistryPath -ErrorAction SilentlyContinue
    if ($current.PauseUpdatesExpiryTime) {
        Write-Host ('  已暂停更新，到期：' + $current.PauseUpdatesExpiryTime)
    } else {
        Write-Host '  当前未处于暂停状态'
    }
} else {
    Write-Host '  注册表键不存在，将自动创建'
}

# ---- 计划 ----
Write-Host ''
Write-Host '=== 将要写入 ===' -ForegroundColor Cyan
Write-Host ('  键：' + $RegistryPath)
foreach ($e in $entries) {
    Write-Host ('  ' + $e.Name.PadRight(30) + $e.Value)
}
Write-Host ('  暂停天数：' + $Days)
Write-Host ('  到期日：' + $endUtc.ToString('yyyy-MM-dd HH:mm:ss') + ' UTC（本地 ' + $endUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') + '）')

if ($DryRun) {
    Write-Host ''
    Write-Host '[DryRun] 未修改注册表。' -ForegroundColor Yellow
    if (-not $Yes) { Read-Host '按回车退出' | Out-Null }
    exit 0
}

# ---- 确认 ----
if (-not $Yes) {
    Write-Host ''
    $answer = Read-Host '确认修改请逐字输入 YES（其他任意内容取消）'
    if ($answer -cne 'YES') {
        Write-Host '已取消，未做任何修改。' -ForegroundColor Yellow
        Read-Host '按回车退出' | Out-Null
        exit 1
    }
}

# ---- 备份现有键 ----
$backupFile = ''
try {
    $scriptDir = [System.IO.Path]::GetDirectoryName($PSCommandPath)
    $backupDir = Join-Path $scriptDir 'backup'
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    $backupFile = Join-Path $backupDir ('UX-Settings-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.reg')
    if (Test-Path $RegistryPath) {
        & reg.exe export 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' $backupFile /y | Out-Null
        if ($LASTEXITCODE -ne 0) { $backupFile = '' }
    }
} catch {
    $backupFile = ''
}
if ($backupFile) {
    Write-Host ('[*] 已备份原值：' + $backupFile) -ForegroundColor DarkGray
} else {
    Write-Host '[!] 备份失败（不影响写入，但撤销时只能手动删值）' -ForegroundColor Yellow
}

# ---- 写入 ----
if (-not (Test-Path $RegistryPath)) { New-Item -Path $RegistryPath -Force | Out-Null }
foreach ($e in $entries) {
    if ($e.Kind -eq 'DWord') {
        New-ItemProperty -Path $RegistryPath -Name $e.Name -Value ([int]$e.Value) -PropertyType DWord -Force | Out-Null
    } else {
        New-ItemProperty -Path $RegistryPath -Name $e.Name -Value ([string]$e.Value) -PropertyType String -Force | Out-Null
    }
}

# ---- 回读校验 ----
$after = Get-ItemProperty -Path $RegistryPath
$bad = @()
foreach ($e in $entries) {
    $got = $after.($e.Name)
    if ([string]$got -ne [string]$e.Value) { $bad += ($e.Name + ' 期望=' + $e.Value + ' 实际=' + $got) }
}

Write-Host ''
if ($bad.Count -eq 0) {
    Write-Host '[OK] 全部写入并回读校验通过。' -ForegroundColor Green
    Write-Host ('     打开「设置 > Windows 更新」，应显示已暂停更新至 ' + $endUtc.ToLocalTime().ToString('yyyy-MM-dd') + '。') -ForegroundColor Green
    Write-Host '     若设置页仍显示旧日期，关闭设置窗口重开一次即可。' -ForegroundColor DarkGray
} else {
    Write-Host '[!] 回读不一致，可能被系统策略覆盖：' -ForegroundColor Red
    $bad | ForEach-Object { Write-Host ('     ' + $_) -ForegroundColor Red }
}

if (-not $Yes) { Read-Host '按回车退出' | Out-Null }
