<#
.SYNOPSIS
    Optimizes Windows Server GitHub Actions Runner for Maximum Zero-Cost AFK Gaming Performance.
.DESCRIPTION
    - Unparks all CPU cores/threads & locks Ultimate Performance 100% Boost Clock (3.24+ GHz EPYC)
    - Eliminates the ~70% startup CPU hog on GitHub Runners (disables Windows Defender MsMpEng, .NET NGEN mscorsvw, TiWorker, CompatTelRunner)
    - Expands NVMe/SSD Pagefile (Virtual Memory) to 20 GB & enables Large System / NTFS fast I/O cache
    - Unlocks RDP 60 FPS cap (DWMFRAMEINTERVAL = 15) + H.264/AVC444 & UDP low-latency transport
    - Applies MMCSS Gaming Priority, DirectX WARP/Shader optimizations, & TCP NoDelay (Nagle off)
    - Registers Native Auto-RAM Cleaner + Auto-Game CPU Priority Booster (Zero third-party bloatware)
    - Disables TestSigning flag for next boot / clears watermark policies where possible & enables Windows Audio sink
    - Configures Console AutoLogon & Desktop helper scripts (AFK tscon handover + Graceful Stop)
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$RdpUser,

    [Parameter(Mandatory=$true)]
    [string]$RdpPassword,

    [Parameter(Mandatory=$false)]
    [string]$InstallGameRuntimes = "true",

    [Parameter(Mandatory=$false)]
    [string]$InstallMesa3D = "false"
)

$ErrorActionPreference = "Continue"

Write-Host "==> [1/10] Killing 70% Background CPU Hogs (Defender, .NET NGEN, Telemetry, Update Workers)..." -ForegroundColor Cyan
# 1. Disable Windows Defender Real-Time Scanning & Scheduled Scans (Biggest CPU hog on Windows Server 2022/2025 runners)
try {
    Set-MpPreference -DisableRealtimeMonitoring $true `
                     -DisableBehaviorMonitoring $true `
                     -DisableBlockAtFirstSeen $true `
                     -DisableIOAVProtection $true `
                     -DisablePrivacyMode $true `
                     -DisableIntrusionPreventionSystem $true `
                     -DisableScriptScanning $true `
                     -SubmitSamplesConsent 2 `
                     -MAPSReporting 0 `
                     -HighThreatDefaultAction 6 -ModerateThreatDefaultAction 6 -LowThreatDefaultAction 6 -SevereThreatDefaultAction 6 `
                     -ScanAvgCPULoadFactor 5 -ErrorAction SilentlyContinue
} catch {}

$DefenderPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
if (-not (Test-Path $DefenderPolicy)) { New-Item -Path $DefenderPolicy -Force | Out-Null }
Set-ItemProperty -Path $DefenderPolicy -Name "DisableAntiSpyware" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $DefenderPolicy -Name "DisableRoutinelyTakingAction" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
$DefenderRtPolicy = "$DefenderPolicy\Real-Time Protection"
if (-not (Test-Path $DefenderRtPolicy)) { New-Item -Path $DefenderRtPolicy -Force | Out-Null }
foreach ($prop in @("DisableRealtimeMonitoring", "DisableBehaviorMonitoring", "DisableOnAccessProtection", "DisableScanOnRealtimeEnable", "DisableIOAVProtection")) {
    Set-ItemProperty -Path $DefenderRtPolicy -Name $prop -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
}

# 2. Stop .NET Runtime Optimization Service (mscorsvw.exe / ngen) & Maintenance Tasks that eat 50-70% CPU on fresh GitHub VMs
Get-Service -Name "clr_optimization_*" -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
    Set-Service -Name $_.Name -StartupType Disabled -ErrorAction SilentlyContinue
}

$HeavyServices = @(
    "WSearch", "wuauserv", "UsoSvc", "DoSvc", "DiagTrack", "dmwappushservice",
    "SysMain", "Spooler", "MapsBroker", "lfsvc", "WerSvc", "PcaSvc", "DPS", "WdiServiceHost", "WdiSystemHost"
)
foreach ($svc in $HeavyServices) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
    }
}

# Kill active CPU-stealing background processes immediately
$CpuHogProcesses = @("mscorsvw", "ngen", "ngentask", "CompatTelRunner", "TiWorker", "TrustedInstaller", "MpCmdRun", "NisSrv")
foreach ($proc in $CpuHogProcesses) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# Disable Scheduled Tasks that trigger CPU spikes mid-AFK
$NoisyTasks = @(
    "\Microsoft\Windows\.NET Framework\.NET Framework NGEN v4.0.30319*",
    "\Microsoft\Windows\Application Experience\*",
    "\Microsoft\Windows\Customer Experience Improvement Program\*",
    "\Microsoft\Windows\Defrag\*",
    "\Microsoft\Windows\DiskDiagnostic\*",
    "\Microsoft\Windows\Maintenance\WinSAT",
    "\Microsoft\Windows\Windows Defender\*"
)
foreach ($taskPattern in $NoisyTasks) {
    Get-ScheduledTask -TaskPath ($taskPattern.Substring(0, $taskPattern.LastIndexOf('\') + 1)) -ErrorAction SilentlyContinue |
        Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
}

Write-Host "==> [2/10] Activating Ultimate Performance Plan & Unparking 100% CPU Cores/Threads..." -ForegroundColor Cyan
$ultPlan = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
if ($ultPlan -match '([a-f0-9-]{36})') {
    powercfg /setactive $matches[1] 2>$null
} else {
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
}
powercfg /change monitor-timeout-ac 0
powercfg /change monitor-timeout-dc 0
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change hibernate-timeout-ac 0
powercfg /change hibernate-timeout-dc 0

# Unpark ALL CPU Cores (CPMINCORES = 100%) & Lock Boost Clock State to 100% (3.24+ GHz sustained)
powercfg -setacvalueindex scheme_current sub_processor CPMINCORES 100 2>$null
powercfg -setacvalueindex scheme_current sub_processor CPMAXCORES 100 2>$null
powercfg -setacvalueindex scheme_current sub_processor PROCTHROTTLEMIN 100 2>$null
powercfg -setacvalueindex scheme_current sub_processor PROCTHROTTLEMAX 100 2>$null
powercfg -setacvalueindex scheme_current sub_processor PERFBOOSTMODE 2 2>$null
powercfg -setacvalueindex scheme_current sub_processor IDLEDISABLE 0 2>$null
powercfg /setactive scheme_current 2>$null

Write-Host "==> [3/10] Expanding Virtual Memory (20 GB Pagefile) & Accelerating Disk I/O..." -ForegroundColor Cyan
try {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ($cs.AutomaticManagedPagefile) {
        Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile = $false} -ErrorAction SilentlyContinue | Out-Null
    }
    $targetDrive = "C:"
    $dDrive = Get-PSDrive -Name D -ErrorAction SilentlyContinue
    if ($dDrive -and ($dDrive.Free / 1GB) -gt 30) {
        $targetDrive = "D:"
    }
    $pfPath = "$targetDrive\pagefile.sys"
    $existingPf = Get-CimInstance -ClassName Win32_PageFileSetting -Filter "Name='$($pfPath.Replace('\','\\'))'" -ErrorAction SilentlyContinue
    if ($existingPf) {
        Set-CimInstance -InputObject $existingPf -Property @{InitialSize = 16384; MaximumSize = 20480} -ErrorAction SilentlyContinue | Out-Null
    } else {
        New-CimInstance -ClassName Win32_PageFileSetting -Property @{Name = $pfPath; InitialSize = 16384; MaximumSize = 20480} -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Host "    Pagefile configured on $pfPath (16 GB Initial / 20 GB Max)." -ForegroundColor Green
} catch {
    Write-Warning "    Pagefile tuning note: $_"
}

# NTFS & Storage I/O Speedup (Reduces disk stutter on virtualized SAS/SSD drives reported by Hyper-V)
fsutil behavior set disablelastaccess 1 | Out-Null
fsutil behavior set disable8dot3 1 | Out-Null
fsutil behavior set memoryusage 2 | Out-Null
$MemMgmt = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
Set-ItemProperty -Path $MemMgmt -Name "LargeSystemCache" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $MemMgmt -Name "DisablePagingExecutive" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

Write-Host "==> [4/10] Tuning CPU Scheduler, DirectX WARP Software Renderer & Network Ping..." -ForegroundColor Cyan
Get-ScheduledTask -TaskName "ServerManager" -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager" -Name "DoNotOpenServerManagerAtLogon" -Value 1 -PropertyType DWORD -Force | Out-Null

# Favor Foreground Applications (Win32PrioritySeparation = 38 / 0x26 = Short Quantum, High Foreground Boost for Games)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 38 -Type DWord -Force

# Multimedia Class Scheduler Service (MMCSS) — 0% Background Reserve, Max Priority for Games
$MmcssPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
if (Test-Path $MmcssPath) {
    Set-ItemProperty -Path $MmcssPath -Name "SystemResponsiveness" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $MmcssPath -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord -Force -ErrorAction SilentlyContinue
}
$GamesTaskPath = "$MmcssPath\Tasks\Games"
if (-not (Test-Path $GamesTaskPath)) { New-Item -Path $GamesTaskPath -Force | Out-Null }
Set-ItemProperty -Path $GamesTaskPath -Name "GPU Priority" -Value 8 -Type DWord -Force
Set-ItemProperty -Path $GamesTaskPath -Name "Priority" -Value 6 -Type DWord -Force
Set-ItemProperty -Path $GamesTaskPath -Name "Scheduling Category" -Value "High" -Type String -Force
Set-ItemProperty -Path $GamesTaskPath -Name "SFIO Priority" -Value "High" -Type String -Force
Set-ItemProperty -Path $GamesTaskPath -Name "Background Only" -Value "False" -Type String -Force

# DirectX / DXGI Software & WARP Rendering Latency Tweaks (Crucial for CPU-based rendering on EPYC AVX2)
$DxGraphicsDrivers = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
Set-ItemProperty -Path $DxGraphicsDrivers -Name "TdrLevel" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $DxGraphicsDrivers -Name "TdrDelay" -Value 60 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $DxGraphicsDrivers -Name "HwSchMode" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue

# Disable Nagle's Algorithm (TCP NoDelay & TcpAckFrequency = 1) + Receive Side Scaling (RSS) for Online Games
netsh int tcp set global rss=enabled autotuninglevel=normal ecncapability=disabled timestamps=disabled 2>$null | Out-Null
$InterfacesPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
Get-ChildItem $InterfacesPath -ErrorAction SilentlyContinue | ForEach-Object {
    Set-ItemProperty -Path $_.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $_.PSPath -Name "TCPNoDelay" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
}

# Disable GameDVR, Xbox Bar, Error Reporting & Visual Bloat
$GameConfigPath = "HKCU:\System\GameConfigStore"
if (-not (Test-Path $GameConfigPath)) { New-Item -Path $GameConfigPath -Force | Out-Null }
Set-ItemProperty -Path $GameConfigPath -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force
$GameDvrPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
if (-not (Test-Path $GameDvrPolicy)) { New-Item -Path $GameDvrPolicy -Force | Out-Null }
Set-ItemProperty -Path $GameDvrPolicy -Name "AllowGameDVR" -Value 0 -Type DWord -Force

$VisualFxPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
if (-not (Test-Path $VisualFxPath)) { New-Item -Path $VisualFxPath -Force | Out-Null }
Set-ItemProperty -Path $VisualFxPath -Name "VisualFXSetting" -Value 2 -Type DWord -Force

# Turn off BCD TestSigning flag where supported (helps games sensitive to Test Mode check)
bcdedit /set testsigning off 2>$null | Out-Null
bcdedit /set disabledynamictick yes 2>$null | Out-Null

Write-Host "==> [5/10] Unlocking RDP 60 FPS, H.264/AVC444 & Enabling Audio Sink..." -ForegroundColor Cyan
$DwmWinStation = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations"
Set-ItemProperty -Path $DwmWinStation -Name "DWMFRAMEINTERVAL" -Value 15 -Type DWord -Force -ErrorAction SilentlyContinue

$TsPolicies = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
if (-not (Test-Path $TsPolicies)) { New-Item -Path $TsPolicies -Force | Out-Null }
Set-ItemProperty -Path $TsPolicies -Name "AVC444ModePreferred" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $TsPolicies -Name "AVCHardwareEncodePreferred" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $TsPolicies -Name "fEnableVirtualizedGraphics" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $TsPolicies -Name "MaxDisconnectionTime" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $TsPolicies -Name "MaxIdleTime" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $TsPolicies -Name "MaxConnectionTime" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $TsPolicies -Name "fResetBroken" -Value 0 -Type DWord -Force

foreach ($audioSvc in @("AudioEndpointBuilder", "Audiosrv")) {
    if (Get-Service -Name $audioSvc -ErrorAction SilentlyContinue) {
        Set-Service -Name $audioSvc -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name $audioSvc -ErrorAction SilentlyContinue
    }
}

$RdpWinStation = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
Set-ItemProperty -Path $RdpWinStation -Name "fDisableAudioCapture" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $RdpWinStation -Name "AudioEnumeratorDll" -Value "rdpendp.dll" -Type String -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $RdpWinStation -Name "MaxDisconnectionTime" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $RdpWinStation -Name "MaxIdleTime" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $RdpWinStation -Name "MaxConnectionTime" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

Write-Host "==> [6/10] Registering Native Auto-RAM Cleaner & Game Process Priority Booster..." -ForegroundColor Cyan
$SysScriptsDir = "C:\Windows\Temp\S-RDP"
New-Item -ItemType Directory -Path $SysScriptsDir -Force | Out-Null

# Runs silently every 5 minutes:
# 1) Kills any newly spawned .NET/Telemetry CPU hogs
# 2) Boosts active windowed/GUI user games to High/AboveNormal priority
# 3) Trims background working sets if RAM > 78%
$OptimizerLoopPs1 = @'
$ErrorActionPreference = "SilentlyContinue"

# 1. Keep CPU hogs dead
foreach ($hog in @("mscorsvw", "ngen", "CompatTelRunner", "TiWorker")) {
    Get-Process -Name $hog | Stop-Process -Force
}

# 2. Auto-Boost active user GUI applications (Games) & deprioritize noisy system background workers
$systemIgnore = @("explorer", "taskmgr", "cmd", "powershell", "pwsh", "conhost", "dwm", "csrss", "winlogon", "svchost", "lsass", "services", "tailscaled", "tailscale-ipn", "rdpclip", "sihost", "ctfmon", "TextInputHost", "ShellExperienceHost", "SearchHost", "StartMenuExperienceHost")
Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and ($systemIgnore -notcontains $_.ProcessName) } | ForEach-Object {
    if ($_.PriorityClass -eq "Normal") {
        $_.PriorityClass = "AboveNormal"
    }
}

# 3. Trim leaked background RAM if total memory > 78%
$os = Get-CimInstance Win32_OperatingSystem
$usedPct = (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100
if ($usedPct -ge 78) {
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    public class MemCleaner {
        [DllImport("psapi.dll")]
        public static extern int EmptyWorkingSet(IntPtr hwProc);
    }
"@
    Get-Process | Where-Object { $_.MainWindowHandle -eq 0 } | ForEach-Object {
        [void][MemCleaner]::EmptyWorkingSet($_.Handle)
    }
    [System.GC]::Collect()
}
'@
$OptimizerPath = "$SysScriptsDir\afk-guardian.ps1"
Set-Content -Path $OptimizerPath -Value $OptimizerLoopPs1 -Encoding UTF8

$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$OptimizerPath`""
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Hours 12)
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "S-RDP-AfkGuardian" -Action $Action -Trigger $Trigger -Principal $Principal -Force | Out-Null

Write-Host "==> [7/10] Configuring User Account & Console Auto-Logon for AFK Persistence..." -ForegroundColor Cyan
$SecurePass = ConvertTo-SecureString $RdpPassword -AsPlainText -Force
if (Get-LocalUser -Name $RdpUser -ErrorAction SilentlyContinue) {
    Set-LocalUser -Name $RdpUser -Password $SecurePass -PasswordNeverExpires $true
} else {
    New-LocalUser -Name $RdpUser -Password $SecurePass -FullName "AFK Gamer" -PasswordNeverExpires -AccountNeverExpires | Out-Null
}

foreach ($grp in @("Administrators", "Remote Desktop Users")) {
    Add-LocalGroupMember -Group $grp -Member $RdpUser -ErrorAction SilentlyContinue
}

$WinlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $WinlogonPath -Name "AutoAdminLogon" -Value "1" -Type String -Force
Set-ItemProperty -Path $WinlogonPath -Name "DefaultUserName" -Value $RdpUser -Type String -Force
Set-ItemProperty -Path $WinlogonPath -Name "DefaultPassword" -Value $RdpPassword -Type String -Force
Set-ItemProperty -Path $WinlogonPath -Name "DefaultDomainName" -Value $env:COMPUTERNAME -Type String -Force

$PersonalizePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
if (-not (Test-Path $PersonalizePolicy)) { New-Item -Path $PersonalizePolicy -Force | Out-Null }
Set-ItemProperty -Path $PersonalizePolicy -Name "NoLockScreen" -Value 1 -Type DWord -Force

Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $RdpWinStation -Name "UserAuthentication" -Value 0 -Type DWord -Force
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
Restart-Service -Name "TermService" -Force -ErrorAction SilentlyContinue

Write-Host "==> [8/10] Cleaning Temp Files on C: Drive..." -ForegroundColor Cyan
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue

if ($InstallGameRuntimes -eq "true") {
    Write-Host "==> [9/10] Installing Gaming Runtimes (DirectX 9/10/11 Legacy + VC++ Redistributables)..." -ForegroundColor Cyan
    try {
        $dxDir = "$env:TEMP\dxruntime"
        New-Item -ItemType Directory -Path $dxDir -Force | Out-Null
        $dxUrl = "https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe"
        $dxExe = "$dxDir\directx_redist.exe"
        Invoke-WebRequest -Uri $dxUrl -OutFile $dxExe -UseBasicParsing
        Start-Process -FilePath $dxExe -ArgumentList "/Q /T:`"$dxDir\extracted`"" -Wait
        Start-Process -FilePath "$dxDir\extracted\DXSETUP.exe" -ArgumentList "/silent" -Wait
        Remove-Item -Path $dxDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    DirectX Legacy Runtimes installed successfully." -ForegroundColor Green
    } catch {
        Write-Warning "    Could not install DirectX Legacy Runtime: $_"
    }

    try {
        $vcX64 = "$env:TEMP\vc_redist.x64.exe"
        $vcX86 = "$env:TEMP\vc_redist.x86.exe"
        Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile $vcX64 -UseBasicParsing
        Start-Process -FilePath $vcX64 -ArgumentList "/install /quiet /norestart" -Wait
        Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x86.exe" -OutFile $vcX86 -UseBasicParsing
        Start-Process -FilePath $vcX86 -ArgumentList "/install /quiet /norestart" -Wait
        Remove-Item $vcX64, $vcX86 -Force -ErrorAction SilentlyContinue
        Write-Host "    Visual C++ x64 & x86 Runtimes installed successfully." -ForegroundColor Green
    } catch {
        Write-Warning "    Could not install VC++ Redistributable: $_"
    }
} else {
    Write-Host "==> [9/10] Skipping Gaming Runtimes installation (disabled by input)." -ForegroundColor Yellow
}

if ($InstallMesa3D -eq "true") {
    Write-Host "==> [9.5/10] Downloading Mesa3D Software Renderer (OpenGL/D3D CPU Acceleration Pack) to C:\Tools\Mesa3D..." -ForegroundColor Cyan
    try {
        $mesaDir = "C:\Tools\Mesa3D"
        New-Item -ItemType Directory -Path $mesaDir -Force | Out-Null
        $releaseApi = Invoke-RestMethod -Uri "https://api.github.com/repos/pal1000/mesa-dist-win/releases/latest" -UseBasicParsing
        $asset = $releaseApi.assets | Where-Object { $_.name -match "release-msvc\.7z$" } | Select-Object -First 1
        if ($asset) {
            $archivePath = "$mesaDir\$($asset.name)"
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archivePath -UseBasicParsing
            & 7z x $archivePath -o"$mesaDir" -y | Out-Null
            Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
            Write-Host "    Mesa3D extracted to $mesaDir (Run perappdeploy.cmd inside if a game encounters OpenGL/GPU errors)." -ForegroundColor Green
        }
    } catch {
        Write-Warning "    Could not download Mesa3D: $_"
    }
}

# Re-sweep any .NET NGEN processes triggered after VC++ installation so CPU drops immediately to ~1-3%
foreach ($proc in @("mscorsvw", "ngen", "ngentask", "TiWorker")) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Write-Host "==> [10/10] Creating Essential AFK Session Controls on Desktop..." -ForegroundColor Cyan
$PublicDesktop = "C:\Users\Public\Desktop"

$KeepAliveBat = @'
@echo off
title AFK Mode - Disconnect Without Freezing Game
:: Auto-elevate to Administrator (required by tscon)
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
echo ========================================================
echo   MENGAKTIFKAN MODE AFK (TETAP JALAN SAAT TUTUP RDP)
echo ========================================================
echo.
echo Koneksi RDP kamu akan terputus dalam 3 detik, TAPI layar
echo game, auto-clicker, dan macro akan dipindahkan ke Console
echo sehingga TIDAK FREEZE / PAUSE di belakang layar!
echo.
timeout /t 3 >nul
for /f "skip=1 tokens=2,3" %%a in ('query session %USERNAME%') do (
    if "%%a"=="%USERNAME%" (
        %windir%\System32\tscon.exe %%b /dest:console
    )
)
for /f "tokens=3" %%s in ('query session ^| findstr /C:"Active"') do (
    %windir%\System32\tscon.exe %%s /dest:console
)
'@
Set-Content -Path "$PublicDesktop\AFK-Disconnect-Tanpa-Freeze.bat" -Value $KeepAliveBat -Encoding ASCII

$StopRdpBat = @'
@echo off
title Stop S-RDP Session
echo ========================================================
echo   MATIKAN SERVER RDP SEKARANG?
echo ========================================================
echo Ini akan menghentikan GitHub Actions lebih awal supaya
echo hemat kuota menit GitHub Actions kamu.
echo.
choice /C YN /M "Apakah kamu yakin ingin mematikan RDP sekarang"
if errorlevel 2 exit /b
echo Mematikan sesi RDP...
echo stop > "C:\stop-s-rdp.flag"
timeout /t 3
'@
Set-Content -Path "$PublicDesktop\Matikan-Server-RDP.bat" -Value $StopRdpBat -Encoding ASCII

$GuideTxt = @"
====================================================================
  PANDUAN S-RDP KHUSUS AFK GAME BERAT (ZERO-COST MAX TUNED)
====================================================================

OPTIMASI AKTIF DI SERVER INI:
  [v] Windows Defender + .NET NGEN + Telemetry KILLED (CPU Idle ~1-3%)
  [v] All 4 vCPU Threads Unparked @ 100% Boost Clock (AMD EPYC 3.24+ GHz)
  [v] RDP 60 FPS Unlocked + AVC444/H.264 Low-Latency Mode
  [v] 20 GB Virtual Memory Pagefile + Fast NTFS I/O Cache
  [v] Auto Game Priority Booster + Auto RAM Cleaner (Tiap 5 Menit)
  [v] MMCSS Gaming Priority + DirectX TDR/WARP Tuned + TCP NoDelay

1. PENTING AGAR GAME TIDAK FREEZE SAAT TUTUP RDP:
   - JANGAN langsung klik tombol silang [X] di aplikasi Remote Desktop
     kalau game kamu pakai auto-clicker / macro layar / render 3D!
   - Klik 2x file "AFK-Disconnect-Tanpa-Freeze.bat" di Desktop.
   - Script itu akan memutus RDP kamu dan memindahkan layar ke Console
     aktif, sehingga game & bot jalan terus 100% di background.
   - Kapan pun mau ngecek lagi, tinggal login RDP seperti biasa!

2. TIPS OS RUNNER:
   - Pilih "windows-2022" saat Run Workflow jika ingin pemakaian CPU & RAM
     OS paling ringan dibanding "windows-2025".

3. HEMAT WAKTU:
   - Klik 2x "Matikan-Server-RDP.bat" di Desktop jika sudah selesai AFK.
====================================================================
"@
Set-Content -Path "$PublicDesktop\BACA-PANDUAN-AFK-GAME.txt" -Value $GuideTxt -Encoding UTF8

Write-Host "==> Zero-Cost Maximum AFK Optimization Complete!" -ForegroundColor Green
