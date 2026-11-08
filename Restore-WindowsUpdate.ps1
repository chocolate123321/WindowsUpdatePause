<#
.SYNOPSIS
    撤销 Pause-WindowsUpdate.ps1 造成的「暂停更新到 9999 天」设置。
.DESCRIPTION
    默认删除 HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings 下与本工具相关的 7 个值，
    恢复成「未暂停」状态。
    也可以指定 -FromReg 导入 Pause-WindowsUpdate.ps1 自动生成的备份文件（完整还原）。
.PARAMETER FromReg
    备份 .reg 文件路径；给了它就改用 reg import 还原，而不是删值。
.PARAMETER DryRun
    只显示将要做什么，不动注册表。
.PARAMETER Yes
    跳过交互确认。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-WindowsUpdate.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-WindowsUpdate.ps1 -FromReg .\backup\UX-Settings-20261108-170000.reg
.NOTES
    需要管理员权限。
#>
[CmdletBinding()]
param(
    [string]$FromReg = '',
    [switch]$DryRun,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$RegistryPath = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'

$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '[*] 需要管理员权限，正在重新以管理员身份启动...' -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'))
    if ($FromReg) { $argList += @('-FromReg', ('"' + $FromReg + '"')) }
    if ($DryRun)  { $argList += '-DryRun' }
    if ($Yes)     { $argList += '-Yes' }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs | Out-Null
    } catch {
        Write-Host ('[x] 提权被取消或失败：' + $_.Exception.Message) -ForegroundColor Red
        Read-Host '按回车退出' | Out-Null
    }
    exit
}

$names = @(
    'PauseUpdatesStartTime', 'PauseUpdatesExpiryTime',
    'PauseFeatureUpdatesStartTime', 'PauseFeatureUpdatesEndTime',
    'PauseQualityUpdatesStartTime', 'PauseQualityUpdatesEndTime',
    'FlightSettingsMaxPauseDays'
)

Write-Host ''
if ($FromReg) {
    if (-not (Test-Path $FromReg)) {
        Write-Host ('[x] 找不到备份文件：' + $FromReg) -ForegroundColor Red
        Read-Host '按回车退出' | Out-Null
        exit 1
    }
    Write-Host '=== 将要执行 ===' -ForegroundColor Cyan
    Write-Host ('  从备份导入：' + $FromReg)
    if ($DryRun) { Write-Host ''; Write-Host '[DryRun] 未修改注册表。' -ForegroundColor Yellow; if (-not $Yes) { Read-Host '按回车退出' | Out-Null }; exit 0 }
    if (-not $Yes) {
        $answer = Read-Host '确认还原请逐字输入 YES（其他任意内容取消）'
        if ($answer -cne 'YES') { Write-Host '已取消。' -ForegroundColor Yellow; Read-Host '按回车退出' | Out-Null; exit 1 }
    }
    & reg.exe import $FromReg
    if ($LASTEXITCODE -eq 0) { Write-Host '[OK] 已从备份还原。' -ForegroundColor Green }
    else { Write-Host '[x] 导入失败。' -ForegroundColor Red }
} else {
    Write-Host '=== 将要删除的值 ===' -ForegroundColor Cyan
    $names | ForEach-Object { Write-Host ('  ' + $_) }
    if ($DryRun) { Write-Host ''; Write-Host '[DryRun] 未修改注册表。' -ForegroundColor Yellow; if (-not $Yes) { Read-Host '按回车退出' | Out-Null }; exit 0 }
    if (-not $Yes) {
        $answer = Read-Host '确认删除请逐字输入 YES（其他任意内容取消）'
        if ($answer -cne 'YES') { Write-Host '已取消。' -ForegroundColor Yellow; Read-Host '按回车退出' | Out-Null; exit 1 }
    }
    if (Test-Path $RegistryPath) {
        foreach ($n in $names) {
            Remove-ItemProperty -Path $RegistryPath -Name $n -ErrorAction SilentlyContinue
        }
        $left = (Get-ItemProperty -Path $RegistryPath).PauseUpdatesExpiryTime
        if ($left) {
            Write-Host ('[!] 仍存在 PauseUpdatesExpiryTime=' + $left + '，可能被组策略接管。') -ForegroundColor Yellow
        } else {
            Write-Host '[OK] 已恢复为未暂停状态。' -ForegroundColor Green
            Write-Host '     关闭并重新打开「设置 > Windows 更新」即可看到。' -ForegroundColor DarkGray
        }
    } else {
        Write-Host '[i] 注册表键不存在，本来就没设置过。' -ForegroundColor DarkGray
    }
}

if (-not $Yes) { Read-Host '按回车退出' | Out-Null }
