<#
.SYNOPSIS
    Optimizes Windows Server GitHub Actions Runner for AFK Gaming & Headless Execution.
.DESCRIPTION
    - Configures Ultimate/High Performance power plan & disables sleep/screen-off/CPU throttling
    - Unlocks RDP 60 FPS cap (DWMFRAMEINTERVAL = 15), enables AVC444/H.264 & UDP low-latency transport
    - Configures 20 GB NVMe Pagefile (Virtual Memory) to prevent Out-Of-Memory crashes on heavy games
    - Applies Multimedia Class Scheduler Service (MMCSS) Gaming CPU/GPU priority & TCP NoDelay (Nagle off)
    - Registers a lightweight native Windows API Auto-RAM Cleaner (trims memory leaks when RAM > 80%)
    - Disables heavy background services (Windows Search, SysMain, Windows Update, Telemetry)
    - Enables Windows Audio service so games that crash without an audio sink run smoothly
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

Write-Host "==> [1/9] Configuring Ultimate/High Performance Power Plan & Zero Throttling..." -ForegroundColor Cyan
# Duplicate Ultimate Performance plan if available, fallback to High Performance
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
# Force minimum & maximum CPU processor state to 100%
powercfg -setacvalueindex scheme_current sub_processor PROCTHROTTLEMIN 100 2>$null
powercfg -setacvalueindex scheme_current sub_processor PROCTHROTTLEMAX 100 2>$null
powercfg /setactive scheme_current 2>$null

Write-Host "==> [2/9] Expanding NVMe Virtual Memory (Pagefile) to 20 GB..." -ForegroundColor Cyan
# Heavy games running software/WARP rendering commit huge virtual memory; expanding pagefile prevents sudden OOM crashes
try {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ($cs.AutomaticManagedPagefile) {
        Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile = $false} -ErrorAction SilentlyContinue | Out-Null
    }
    # Prefer D:\ if it has >30GB free space, otherwise C:\
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
    Write-Warning "    Pagefile tuning skipped or requires reboot to fully apply: $_"
}

Write-Host "==> [3/9] Tuning CPU Scheduler, MMCSS Gaming Priority & Network Low-Latency..." -ForegroundColor Cyan
# Disable Windows Server Manager auto-launch at logon
Get-ScheduledTask -TaskName "ServerManager" -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager" -Name "DoNotOpenServerManagerAtLogon" -Value 1 -PropertyType DWORD -Force | Out-Null

# Favor Foreground Applications (Win32PrioritySeparation = 38 / 0x26 = Short Quantum, Variable, High Foreground Boost)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 38 -Type DWord -Force

# Multimedia Class Scheduler Service (MMCSS) — Reserve 0% CPU for background throttling, 100% for Games
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

# Disable Nagle's Algorithm (TCP NoDelay & TcpAckFrequency = 1) for lower online game ping spikes
$InterfacesPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
Get-ChildItem $InterfacesPath -ErrorAction SilentlyContinue | ForEach-Object {
    Set-ItemProperty -Path $_.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $_.PSPath -Name "TCPNoDelay" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
}

# Disable GameDVR / Xbox Game Bar background recording overhead
$GameConfigPath = "HKCU:\System\GameConfigStore"
if (-not (Test-Path $GameConfigPath)) { New-Item -Path $GameConfigPath -Force | Out-Null }
Set-ItemProperty -Path $GameConfigPath -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force
$GameDvrPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
if (-not (Test-Path $GameDvrPolicy)) { New-Item -Path $GameDvrPolicy -Force | Out-Null }
Set-ItemProperty -Path $GameDvrPolicy -Name "AllowGameDVR" -Value 0 -Type DWord -Force

# Set Visual Effects for Best Performance
$VisualFxPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
if (-not (Test-Path $VisualFxPath)) { New-Item -Path $VisualFxPath -Force | Out-Null }
Set-ItemProperty -Path $VisualFxPath -Name "VisualFXSetting" -Value 2 -Type DWord -Force

# Stop heavy background services that steal CPU/Disk spikes during AFK gaming
$HeavyServices = @("WSearch", "wuauserv", "DiagTrack", "SysMain", "Spooler", "MapsBroker", "lfsvc")
foreach ($svc in $HeavyServices) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
    }
}

Write-Host "==> [4/9] Unlocking RDP 60 FPS, H.264/AVC444 & Audio Sink..." -ForegroundColor Cyan
# Unlock Windows RDP 60 FPS (Default Windows Server caps RDP DWM at 30 FPS; DWMFRAMEINTERVAL = 15 -> ~60 FPS)
$DwmWinStation = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations"
Set-ItemProperty -Path $DwmWinStation -Name "DWMFRAMEINTERVAL" -Value 15 -Type DWord -Force -ErrorAction SilentlyContinue

# Enable H.264/AVC 444 Graphics Mode & Low-Latency RDP Policies
$TsPolicies = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
if (-not (Test-Path $TsPolicies)) { New-Item -Path $TsPolicies -Force | Out-Null }
Set-ItemProperty -Path $TsPolicies -Name "AVC444ModePreferred" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $TsPolicies -Name "AVCHardwareEncodePreferred" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $TsPolicies -Name "fEnableVirtualizedGraphics" -Value 1 -Type DWord -Force
# Keep session active & never disconnect on idle via Group Policy too
Set-ItemProperty -Path $TsPolicies -Name "MaxDisconnectionTime" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $TsPolicies -Name "MaxIdleTime" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $TsPolicies -Name "MaxConnectionTime" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $TsPolicies -Name "fResetBroken" -Value 0 -Type DWord -Force

# Enable Windows Audio Service (Many games crash on startup if Windows Audio service is stopped!)
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

Write-Host "==> [5/9] Registering Native Auto-RAM Cleaner (Zero Third-Party Bloat)..." -ForegroundColor Cyan
# Native Win32 EmptyWorkingSet script that runs silently every 10 minutes and trims leaked working sets only when RAM usage > 78%
$SysScriptsDir = "C:\Windows\Temp\S-RDP"
New-Item -ItemType Directory -Path $SysScriptsDir -Force | Out-Null
$RamCleanerPs1 = @'
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
"@ -ErrorAction SilentlyContinue
    Get-Process | Where-Object { $_.MainWindowHandle -eq 0 } | ForEach-Object {
        try { [void][MemCleaner]::EmptyWorkingSet($_.Handle) } catch {}
    }
    [System.GC]::Collect()
}
'@
$RamCleanerPath = "$SysScriptsDir\auto-ram-clean.ps1"
Set-Content -Path $RamCleanerPath -Value $RamCleanerPs1 -Encoding UTF8

$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$RamCleanerPath`""
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration (New-TimeSpan -Hours 12)
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "S-RDP-AutoRamCleaner" -Action $Action -Trigger $Trigger -Principal $Principal -Force | Out-Null

Write-Host "==> [6/9] Configuring User Account & Console Auto-Logon for AFK Persistence..." -ForegroundColor Cyan
$SecurePass = ConvertTo-SecureString $RdpPassword -AsPlainText -Force
if (Get-LocalUser -Name $RdpUser -ErrorAction SilentlyContinue) {
    Set-LocalUser -Name $RdpUser -Password $SecurePass -PasswordNeverExpires $true
} else {
    New-LocalUser -Name $RdpUser -Password $SecurePass -FullName "AFK Gamer" -PasswordNeverExpires -AccountNeverExpires | Out-Null
}

foreach ($grp in @("Administrators", "Remote Desktop Users")) {
    Add-LocalGroupMember -Group $grp -Member $RdpUser -ErrorAction SilentlyContinue
}

# Disable Ctrl+Alt+Del requirement & Configure AutoAdminLogon so Console has an active GUI session
$WinlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $WinlogonPath -Name "AutoAdminLogon" -Value "1" -Type String -Force
Set-ItemProperty -Path $WinlogonPath -Name "DefaultUserName" -Value $RdpUser -Type String -Force
Set-ItemProperty -Path $WinlogonPath -Name "DefaultPassword" -Value $RdpPassword -Type String -Force
Set-ItemProperty -Path $WinlogonPath -Name "DefaultDomainName" -Value $env:COMPUTERNAME -Type String -Force

# Disable Windows Lock Screen so session never locks while on Console
$PersonalizePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
if (-not (Test-Path $PersonalizePolicy)) { New-Item -Path $PersonalizePolicy -Force | Out-Null }
Set-ItemProperty -Path $PersonalizePolicy -Name "NoLockScreen" -Value 1 -Type DWord -Force

# Enable Remote Desktop (TCP + UDP 3389 for smoother 60FPS streaming over Tailscale)
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $RdpWinStation -Name "UserAuthentication" -Value 0 -Type DWord -Force
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

# Restart TermService quietly if possible so 60FPS DWMFRAMEINTERVAL & AVC444 policies take effect immediately
Restart-Service -Name "TermService" -Force -ErrorAction SilentlyContinue

Write-Host "==> [7/9] Cleaning Temp Files on C: Drive..." -ForegroundColor Cyan
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue

if ($InstallGameRuntimes -eq "true") {
    Write-Host "==> [8/9] Installing Gaming Runtimes (DirectX 9/10/11 Legacy + VC++ Redistributables)..." -ForegroundColor Cyan
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
    Write-Host "==> [8/9] Skipping Gaming Runtimes installation (disabled by input)." -ForegroundColor Yellow
}

if ($InstallMesa3D -eq "true") {
    Write-Host "==> [8.5/9] Downloading Mesa3D Software Renderer (OpenGL/D3D CPU Acceleration Pack) to C:\Tools\Mesa3D..." -ForegroundColor Cyan
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

Write-Host "==> [9/9] Creating Essential AFK Session Controls on Desktop..." -ForegroundColor Cyan
$PublicDesktop = "C:\Users\Public\Desktop"

# 1. AFK-Disconnect-Tanpa-Freeze.bat
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

# 2. Matikan-Server-RDP.bat (Gracefully stop workflow early to save GitHub Actions minutes)
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

# 3. AFK Gaming Guide on Desktop
$GuideTxt = @"
====================================================================
  PANDUAN S-RDP KHUSUS AFK GAME BERAT
====================================================================

OPTIMASI AKTIF DI SERVER INI:
  [v] RDP 60 FPS Unlocked + AVC444/H.264 Low-Latency Mode
  [v] Ultimate Performance Power Plan (100% Unthrottled CPU)
  [v] 20 GB NVMe Pagefile (Anti Out-Of-Memory Crash)
  [v] Native Auto-RAM Cleaner (Otomatis jalan tiap 10 menit jika RAM >78%)
  [v] MMCSS Gaming Priority + TCP NoDelay (Anti Ping Spike)

1. PENTING AGAR GAME TIDAK FREEZE SAAT TUTUP RDP:
   - JANGAN langsung klik tombol silang [X] di aplikasi Remote Desktop
     kalau game kamu pakai auto-clicker / macro layar / render 3D!
   - Klik 2x file "AFK-Disconnect-Tanpa-Freeze.bat" di Desktop.
   - Script itu akan memutus RDP kamu dan memindahkan layar ke Console
     aktif, sehingga game & bot jalan terus 100% di background.
   - Kapan pun mau ngecek lagi, tinggal login RDP seperti biasa!

2. TIPS SETTING GRAFIS GAME (KARENA TANPA GPU FISIK):
   - Setel game ke Windowed Mode (resolusi rendah misal 800x600 atau 1024x768).
   - Matikan Shadow, Anti-Aliasing, Bloom, V-Sync, dan efek partikel.
   - Batasi FPS Limit in-game ke 15 - 30 FPS saat ditinggal AFK.

3. HEMAT KUOTA MENIT:
   - Klik 2x "Matikan-Server-RDP.bat" di Desktop jika sudah selesai AFK
     sebelum waktu habis.
====================================================================
"@
Set-Content -Path "$PublicDesktop\BACA-PANDUAN-AFK-GAME.txt" -Value $GuideTxt -Encoding UTF8

Write-Host "==> AFK Gaming System Optimization Complete!" -ForegroundColor Green
