<#
.SYNOPSIS
    Optimizes Windows Server GitHub Actions Runner for AFK Gaming & Headless Execution.
.DESCRIPTION
    - Configures Ultimate/High Performance power plan & disables sleep/screen-off
    - Optimizes Windows visual effects & disables unnecessary background services (Windows Search, SysMain, Windows Update) to free CPU & 16GB RAM for the game
    - Configures AutoLogon to local console session so games continue rendering even before/after RDP connection
    - Installs DirectX End-User Runtime & VC++ Redistributables (optional toggle)
    - Installs Virtual Audio Cable / Windows Audio service so games that crash without audio device run smoothly
    - Creates Desktop Helper Scripts:
        1. "Disconnect-Keep-Game-Running.bat" (uses tscon to hand over RDP session to Console so game/macro/AFK never freezes when closing RDP!)
        2. "Stop-RDP-Session.bat" (cleanly terminates the GitHub Action early when done)
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

Write-Host "==> [1/7] Configuring Power Plan & Disabling Sleep/Screen Timeout..." -ForegroundColor Cyan
# Activate High Performance Power Plan
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
powercfg /change monitor-timeout-ac 0
powercfg /change monitor-timeout-dc 0
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change hibernate-timeout-ac 0
powercfg /change hibernate-timeout-dc 0

Write-Host "==> [2/7] Optimizing CPU, Memory & Disabling Heavy Background Services..." -ForegroundColor Cyan
# Disable Windows Server Manager auto-launch at logon
Get-ScheduledTask -TaskName "ServerManager" -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager" -Name "DoNotOpenServerManagerAtLogon" -Value 1 -PropertyType DWORD -Force | Out-Null

# Set Processor Scheduling to favor Foreground Applications (Games) instead of Background Services (Win32PrioritySeparation = 38 / 0x26)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 38 -Type DWord -Force

# Set Visual Effects for Best Performance
$VisualFxPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
if (-not (Test-Path $VisualFxPath)) { New-Item -Path $VisualFxPath -Force | Out-Null }
Set-ItemProperty -Path $VisualFxPath -Name "VisualFXSetting" -Value 2 -Type DWord -Force

# Stop heavy background services that steal CPU spikes during AFK gaming
$HeavyServices = @("WSearch", "wuauserv", "DiagTrack", "SysMain", "Spooler")
foreach ($svc in $HeavyServices) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
    }
}

# Enable Windows Audio Service (Many games crash on startup if Windows Audio service is stopped!)
if (Get-Service -Name "Audiosrv" -ErrorAction SilentlyContinue) {
    Set-Service -Name "Audiosrv" -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name "Audiosrv" -ErrorAction SilentlyContinue
}
if (Get-Service -Name "AudioEndpointBuilder" -ErrorAction SilentlyContinue) {
    Set-Service -Name "AudioEndpointBuilder" -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name "AudioEndpointBuilder" -ErrorAction SilentlyContinue
}

# Enable RDP Audio playback redirection so game sees a valid audio sink
$RdpWinStation = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
Set-ItemProperty -Path $RdpWinStation -Name "fDisableAudioCapture" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $RdpWinStation -Name "AudioEnumeratorDll" -Value "rdpendp.dll" -Type String -Force -ErrorAction SilentlyContinue
# Keep disconnected RDP sessions alive indefinitely (Never end disconnected session)
Set-ItemProperty -Path $RdpWinStation -Name "MaxDisconnectionTime" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $RdpWinStation -Name "MaxIdleTime" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $RdpWinStation -Name "MaxConnectionTime" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

Write-Host "==> [3/7] Configuring User Account & Console Auto-Logon for AFK Persistence..." -ForegroundColor Cyan
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

# Enable Remote Desktop & Disable strict NLA if connecting from mobile RDP clients easily, while strictly protected by Tailscale private network
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $RdpWinStation -Name "UserAuthentication" -Value 0 -Type DWord -Force
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

Write-Host "==> [4/7] Freeing Extra Disk Space on C: Drive for Heavy Games..." -ForegroundColor Cyan
# GitHub Windows runners carry pre-installed SDKs; clean temp folders quickly without slowing startup
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue

if ($InstallGameRuntimes -eq "true") {
    Write-Host "==> [5/7] Installing Gaming Runtimes (DirectX 9/10/11 Legacy + VC++ Redistributables)..." -ForegroundColor Cyan
    try {
        # DirectX End-User Runtime Web Installer / Redist
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
        # Latest VC++ 2015-2022 Redistributable (x64 & x86)
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
    Write-Host "==> [5/7] Skipping Gaming Runtimes installation (disabled by input)." -ForegroundColor Yellow
}

if ($InstallMesa3D -eq "true") {
    Write-Host "==> [6/7] Downloading Mesa3D Software Renderer (OpenGL/D3D CPU Acceleration Pack) to C:\Tools\Mesa3D..." -ForegroundColor Cyan
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
            Write-Host "    Mesa3D extracted to $mesaDir (Run systemwidedeploy.cmd inside if a game encounters OpenGL/GPU errors)." -ForegroundColor Green
        }
    } catch {
        Write-Warning "    Could not download Mesa3D: $_"
    }
} else {
    Write-Host "==> [6/7] Skipping Mesa3D download (disabled by input)." -ForegroundColor Yellow
}

Write-Host "==> [7/7] Creating AFK Helper Shortcuts on Public Desktop..." -ForegroundColor Cyan
$PublicDesktop = "C:\Users\Public\Desktop"

# 1. Disconnect-Keep-Game-Running.bat
# Crucial for AFK Gaming: When closing normal RDP (X button), Windows unloads the virtual display driver, causing DirectX games & auto-clickers to freeze/blackscreen.
# Running this script transfers the active RDP session to the local virtual Console display so the game & macros keep rendering 100% while disconnected!
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

# 2. Stop-RDP-Server.bat (Gracefully stop workflow early to save GitHub Actions minutes)
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
   - Batasi FPS Limit ke 15 - 30 FPS agar CPU tidak 100% terus-menerus.

3. JIKA GAME ERROR "GPU NOT SUPPORTED / OPENGL ERROR":
   - Jika saat start workflow kamu mengaktifkan opsi Mesa3D, buka folder
     C:\Tools\Mesa3D lalu jalankan per-app deployment ke folder .exe game kamu.

4. TIPS PENYIMPANAN GAME BESAR:
   - Drive D:\ di GitHub Runner kadang punya ruang kosong tambahan selain C:\.
     Cek This PC untuk memilih drive paling lega saat install game besar.

5. HEMAT KUOTA MENIT:
   - Klik 2x "Matikan-Server-RDP.bat" di Desktop jika sudah selesai AFK
     sebelum waktu habis.
====================================================================
"@
Set-Content -Path "$PublicDesktop\BACA-PANDUAN-AFK-GAME.txt" -Value $GuideTxt -Encoding UTF8

Write-Host "==> AFK Gaming Optimization Complete!" -ForegroundColor Green
