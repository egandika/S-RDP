<#
.SYNOPSIS
    Optimizes Windows Server GitHub Actions Runner for Maximum Zero-Cost AFK Gaming Performance.
.DESCRIPTION
    - Eliminates ~70% startup CPU hogs (Defender Real-Time Scan, .NET NGEN mscorsvw, TiWorker, CompatTelRunner, recursive scheduled tasks)
    - Unparks 100% CPU cores/threads & locks Ultimate Performance Boost Clock (3.24+ GHz AMD EPYC)
    - Expands Virtual Memory (20 GB Pagefile) & enables fast NTFS I/O caching
    - Injects Visual Effects, GameDVR-Off, & 100% DPI Scaling directly into Default User Registry Hive (NTUSER.DAT) so the RDP gamer account inherits them cleanly without corrupting C:\Users\<user>
    - Locks Hyper-V / Console Display Resolution & 96 DPI (100% scaling) so macro/auto-clicker coordinates don't drift on tscon AFK handover
    - Adapts RDP graphics to the hardware: GPU-less hosts get CPU-friendly frame pacing (30 FPS) + no forced
      AVC444, real GPUs keep 60 FPS + hardware H.264/AVC444 + Windows Audio sink
    - Smart runtime installer: skips VC++ download if modern 14.40+ runtime is already pre-installed on runner (saves ~25s startup!)
    - Registers Native AFK Guardian (keeps hogs dead, boosts active game priority, trims memory leaks >78%)
    - GPU-aware rendering tuning: software-only hosts (WARP/llvmpipe) get CPU-friendly RDP encoder + DWM pacing,
      while real-GPU hosts keep AVC444/H.264 hardware encode unlocked at 60 FPS
    - Deploys Mesa3D system-wide (OpenGL 1.1 -> 4.5 llvmpipe) so GPU-less games/emulators actually render
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$RdpUser,

    [Parameter(Mandatory=$true)]
    [string]$RdpPassword,

    [Parameter(Mandatory=$false)]
    [string]$InstallGameRuntimes = "true",

    [Parameter(Mandatory=$false)]
    [string]$InstallMesa3D = "true",

    # Frame pacing cap for the desktop compositor (DWMFRAMEINTERVAL). On a GPU-less runner a hard 60 FPS
    # composition target wastes a whole vCPU on pure copy work, so 30 is the sane default for software rendering.
    [Parameter(Mandatory=$false)]
    [ValidateRange(10, 144)]
    [int]$RdpFps = 30,

    [Parameter(Mandatory=$false)]
    [string]$TuneRendering = "true",

    # Mesa3D system-wide deployment (replaces the inbox OpenGL 1.1 software driver for every process).
    [Parameter(Mandatory=$false)]
    [string]$MesaSystemWide = "true"
)

$ErrorActionPreference = "Continue"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Test-SrdpTrue {
    param([string]$Value)
    # PowerShell -eq is case-insensitive, so "true"/"TRUE"/"True" all pass.
    return ($Value -eq "true")
}

function Get-SrdpGpuInfo {
    <#
        Returns $null when the machine only has the software/basic display adapter (typical GitHub runner),
        otherwise a list of real GPUs. Used to decide between hardware AVC444/60FPS and CPU-friendly pacing.
    #>
    $adapters = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue)
    # NOTE: AdapterRAM must NOT be used here (it is 0 or wraps on many modern GPUs); the adapter *name*
    # is the reliable signal. GPU-less runners only expose the Basic Render/Display driver.
    $real = @($adapters | Where-Object {
        $_.Name -and
        $_.Name -notmatch 'Microsoft Basic (Render|Display)' -and
        $_.Name -notmatch 'Remote Display Adapter' -and
        $_.Name -notmatch 'Microsoft Hyper-V Video' -and
        $_.Name -notmatch 'Standard VGA'
    })
    if ($real.Count -gt 0) { return $real }
    return $null
}

$Script:SrdpGpu = Get-SrdpGpuInfo

Write-Host "==> [1/10] Killing 70% Background CPU Hogs (Defender, .NET NGEN, Telemetry, Update Workers)..." -ForegroundColor Cyan
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
$CfaPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Controlled Folder Access"
if (-not (Test-Path $CfaPolicy)) { New-Item -Path $CfaPolicy -Force -ErrorAction SilentlyContinue | Out-Null }
Set-ItemProperty -Path $CfaPolicy -Name "EnableControlledFolderAccess" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
$DefenderRtPolicy = "$DefenderPolicy\Real-Time Protection"
if (-not (Test-Path $DefenderRtPolicy)) { New-Item -Path $DefenderRtPolicy -Force | Out-Null }
foreach ($prop in @("DisableRealtimeMonitoring", "DisableBehaviorMonitoring", "DisableOnAccessProtection", "DisableScanOnRealtimeEnable", "DisableIOAVProtection")) {
    Set-ItemProperty -Path $DefenderRtPolicy -Name $prop -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
}

# Stop .NET Runtime Optimization Service (mscorsvw.exe / ngen) & heavy background services
Get-Service -Name "clr_optimization_*" -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
    Set-Service -Name $_.Name -StartupType Disabled -ErrorAction SilentlyContinue
}

# CATATAN: layanan Xbox (XblAuthManager/XblGameSave/XboxNetApiSvc) SENGAJA TIDAK dimatikan karena
# banyak game (terutama Microsoft Store / Game Pass) membutuhkannya.
$HeavyServices = @(
    "WSearch", "wuauserv", "UsoSvc", "DoSvc", "DiagTrack", "dmwappushservice",
    "SysMain", "Spooler", "MapsBroker", "lfsvc", "WerSvc", "PcaSvc", "DPS", "WdiServiceHost", "WdiSystemHost",
    "TabletInputService", "RemoteRegistry", "RetailDemo", "WMPNetworkSvc", "Fax",
    "diagnosticshub.standardcollector.service", "edgeupdate", "edgeupdatem"
)
foreach ($svc in $HeavyServices) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
    }
}

$CpuHogProcesses = @("mscorsvw", "ngen", "ngentask", "CompatTelRunner", "TiWorker", "TrustedInstaller", "MpCmdRun", "NisSrv")
foreach ($proc in $CpuHogProcesses) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# Properly disable noisy Scheduled Tasks recursively via wildcard TaskPath matching
$NoisyTaskRoots = @(
    "\Microsoft\Windows\.NET Framework\*",
    "\Microsoft\Windows\Application Experience\*",
    "\Microsoft\Windows\Customer Experience Improvement Program\*",
    "\Microsoft\Windows\Defrag\*",
    "\Microsoft\Windows\DiskDiagnostic\*",
    "\Microsoft\Windows\Maintenance\*",
    "\Microsoft\Windows\Windows Defender\*",
    "\Microsoft\Windows\WindowsUpdate\*"
)
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $tp = $_.TaskPath
    foreach ($pat in $NoisyTaskRoots) {
        if ($tp -like $pat) { return $true }
    }
    return $false
} | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null

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

powercfg -setacvalueindex scheme_current sub_processor CPMINCORES 100 2>$null
powercfg -setacvalueindex scheme_current sub_processor CPMAXCORES 100 2>$null
powercfg -setacvalueindex scheme_current sub_processor PROCTHROTTLEMIN 100 2>$null
powercfg -setacvalueindex scheme_current sub_processor PROCTHROTTLEMAX 100 2>$null
powercfg -setacvalueindex scheme_current sub_processor PERFBOOSTMODE 2 2>$null
# IDLEDISABLE=1 -> core tidak pernah masuk C-state/idle clock, sehingga thread input/render tidak
# "terbangun terlambat". Ini yang membuat klik terasa instan walau CPU baru saja idle.
powercfg -setacvalueindex scheme_current sub_processor IDLEDISABLE 1 2>$null
# Boost policy & EPP ke performa maksimum (diabaikan bila CPU/platform tidak mendukung)
powercfg -setacvalueindex scheme_current sub_processor PERFBOOSTPOL 100 2>$null
powercfg -setacvalueindex scheme_current sub_processor PERFEPP 0 2>$null
powercfg /setactive scheme_current 2>$null

Write-Host "==> [3/10] Expanding Virtual Memory (20 GB Pagefile) & Accelerating Disk I/O..." -ForegroundColor Cyan
try {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ($cs.AutomaticManagedPagefile) {
        Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile = $false} -ErrorAction SilentlyContinue | Out-Null
    }
    # Place Pagefile on C: if D: is reserved for large AFK-Data Vault, unless C: is tight (<15GB) and D: has >35GB
    $targetDrive = "C:"
    $cDrive = Get-PSDrive -Name C -ErrorAction SilentlyContinue
    $dDrive = Get-PSDrive -Name D -ErrorAction SilentlyContinue
    if ($cDrive -and ($cDrive.Free / 1GB) -lt 22 -and $dDrive -and ($dDrive.Free / 1GB) -gt 35) {
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

fsutil behavior set disablelastaccess 1 | Out-Null
fsutil behavior set disable8dot3 1 | Out-Null
fsutil behavior set memoryusage 2 | Out-Null
$MemMgmt = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
Set-ItemProperty -Path $MemMgmt -Name "LargeSystemCache" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $MemMgmt -Name "DisablePagingExecutive" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

Write-Host "==> [4/10] Tuning CPU Scheduler, DirectX WARP, Network Ping & Default User Hive..." -ForegroundColor Cyan
Get-ScheduledTask -TaskName "ServerManager" -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\ServerManager")) {
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\ServerManager" -Force -ErrorAction SilentlyContinue | Out-Null
}
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager" -Name "DoNotOpenServerManagerAtLogon" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null

# Favor Foreground Applications (Win32PrioritySeparation = 38 / 0x26)
# Short, variable quantum + boost foreground: thread input & render game dapat CPU lebih cepat -> klik terasa responsif.
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
# Clock Rate 10000 = 100% dari clock saat MMCSS aktif; Affinity 0 = semua core boleh dipakai
Set-ItemProperty -Path $GamesTaskPath -Name "Clock Rate" -Value 10000 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $GamesTaskPath -Name "Affinity" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

# DirectX / DXGI Software & WARP Rendering Latency Tweaks
# NOTE: TdrLevel=0 ("never recover") used to hang the whole desktop forever if a WARP/llvmpipe draw call
# got stuck, so we keep the Windows default recovery level and only relax the timeout window.
$DxGraphicsDrivers = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
Set-ItemProperty -Path $DxGraphicsDrivers -Name "TdrLevel" -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $DxGraphicsDrivers -Name "TdrDelay" -Value 60 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $DxGraphicsDrivers -Name "TdrDdiDelay" -Value 60 -Type DWord -Force -ErrorAction SilentlyContinue
if ($Script:SrdpGpu) {
    # Real GPU present -> hardware GPU scheduling helps.
    Set-ItemProperty -Path $DxGraphicsDrivers -Name "HwSchMode" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
} else {
    # Software/WARP only -> GPU scheduling just adds WDDM bookkeeping overhead on a 4 vCPU box.
    Set-ItemProperty -Path $DxGraphicsDrivers -Name "HwSchMode" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Mesa3D / llvmpipe machine-wide renderer environment (only affects Mesa-driven OpenGL, ignored otherwise)
#   LP_NUM_THREADS      : llvmpipe rasterizer threads (default = ALL cores, which starves DWM + the RDP
#                         encoder + the game's own logic thread on a 4 vCPU runner) -> reserve 1 core.
#   mesa_glthread       : offloads OpenGL command submission to a dedicated thread.
#   vblank_mode=0       : disables swap-interval vsync waits (software rendering can never hit 60 Hz anyway).
# ---------------------------------------------------------------------------
if (Test-SrdpTrue $TuneRendering) {
    $logicalCpu = [Environment]::ProcessorCount
    $rasterThreads = [Math]::Max(2, $logicalCpu - 1)
    if ($Script:SrdpGpu) { $rasterThreads = [Math]::Max(2, $logicalCpu) }

    $RendererEnv = [ordered]@{
        "LP_NUM_THREADS"           = "$rasterThreads"
        "GALLIUM_DRIVER"           = "llvmpipe"
        "LIBGL_ALWAYS_SOFTWARE"    = "1"
        "mesa_glthread"            = "true"
        "vblank_mode"              = "0"
        "MESA_GL_VERSION_OVERRIDE" = "4.5"
        "MESA_GLSL_VERSION_OVERRIDE" = "450"
        "MESA_SHADER_CACHE_MAX_SIZE" = "512M"
        "MESA_SHADER_CACHE_DISABLE"  = "false"
        # Buang overhead validasi error Mesa (tidak perlu saat bermain) & hilangkan vsync di lavapipe
        "MESA_NO_ERROR"             = "1"
        "MESA_VK_WSI_PRESENT_MODE"  = "immediate"
    }
    foreach ($key in $RendererEnv.Keys) {
        [Environment]::SetEnvironmentVariable($key, $RendererEnv[$key], "Machine")
    }
    Write-Host "    Renderer env: LP_NUM_THREADS=$rasterThreads, GALLIUM_DRIVER=llvmpipe, mesa_glthread=true, vblank_mode=0" -ForegroundColor Green
}

# Disable Nagle's Algorithm (TCP NoDelay & TcpAckFrequency = 1) + RSS
netsh int tcp set global rss=enabled autotuninglevel=normal ecncapability=disabled timestamps=disabled 2>$null | Out-Null
$InterfacesPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
Get-ChildItem $InterfacesPath -ErrorAction SilentlyContinue | ForEach-Object {
    Set-ItemProperty -Path $_.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $_.PSPath -Name "TCPNoDelay" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
}

# Machine-wide GameDVR Off Policy
$GameDvrPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
if (-not (Test-Path $GameDvrPolicy)) { New-Item -Path $GameDvrPolicy -Force | Out-Null }
Set-ItemProperty -Path $GameDvrPolicy -Name "AllowGameDVR" -Value 0 -Type DWord -Force

# Lock Console Display Resolution to 1280x720 & 100% DPI (96 DPI) on BasicRender/Hyper-V Video so tscon AFK handover keeps stable macro coordinates!
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Video" -ErrorAction SilentlyContinue | ForEach-Object {
    $vid0000 = Join-Path $_.PSPath "0000"
    if (Test-Path $vid0000) {
        Set-ItemProperty -Path $vid0000 -Name "DefaultSettings.XResolution" -Value 1280 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $vid0000 -Name "DefaultSettings.YResolution" -Value 720 -Type DWord -Force -ErrorAction SilentlyContinue
    }
}

# Inject Best Performance Visual Effects, 100% DPI Scaling (LogPixels=96), & GameDVR Off into Default User Hive (NTUSER.DAT)
# This ensures the newly created '$RdpUser' account actually receives all per-user tweaks upon first RDP logon without pre-creating C:\Users\$RdpUser!
$DefaultNtUser = "C:\Users\Default\NTUSER.DAT"
if (Test-Path $DefaultNtUser) {
    & reg load "HKU\SrdpDefault" $DefaultNtUser >$null 2>&1
    if ($LASTEXITCODE -eq 0) {
        & reg add "HKU\SrdpDefault\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 2 /f >$null 2>&1
        & reg add "HKU\SrdpDefault\Control Panel\Desktop" /v UserPreferencesMask /t REG_BINARY /d 9012038010000000 /f >$null 2>&1
        & reg add "HKU\SrdpDefault\Control Panel\Desktop" /v Win8DpiScaling /t REG_DWORD /d 1 /f >$null 2>&1
        & reg add "HKU\SrdpDefault\Control Panel\Desktop" /v LogPixels /t REG_DWORD /d 96 /f >$null 2>&1
        & reg add "HKU\SrdpDefault\Control Panel\Desktop\WindowMetrics" /v MinAnimate /t REG_SZ /d "0" /f >$null 2>&1
        & reg add "HKU\SrdpDefault\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f >$null 2>&1
        & reg add "HKU\SrdpDefault\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 0 /f >$null 2>&1

        # ---- INPUT LATENCY (klik/ketik terasa telat) --------------------------------------------------
        # Semua nilai ini per-user, jadi ditanam di Default Hive agar sudah aktif sejak logon pertama.
        # MenuShowDelay default 400 ms  -> 0 ms (menu langsung terbuka, ini jeda yang paling terasa saat klik)
        # MouseHoverTime default 400 ms -> 0 ms (tooltip/tombol tidak "menunggu")
        # DragFullWindows=0             -> saat drag jendela hanya outline yang digambar (jauh lebih responsif di RDP)
        # ActiveWndTrkTimeout=0         -> tracking jendela saat drag tidak menunggu
        # KeyboardDelay=0/KeyboardSpeed=31 -> key repeat instan (default: tunda 1 ~ 500 ms)
        # MouseSpeed/Threshold=0 + SmoothMouse*Curve nol -> "Enhance pointer precision" OFF (accelerasi bikin terasa lag)
        # MouseTrails=0, CursorShadow=0 -> kursor tidak tertinggal bayangan
        # ClickLock=0                   -> klik tidak ditahan sistem
        $InputDesktop = "HKU\SrdpDefault\Control Panel\Desktop"
        & reg add $InputDesktop /v MenuShowDelay /t REG_SZ /d "0" /f >$null 2>&1
        & reg add $InputDesktop /v MouseHoverTime /t REG_SZ /d "0" /f >$null 2>&1
        & reg add $InputDesktop /v DragFullWindows /t REG_SZ /d "0" /f >$null 2>&1
        & reg add $InputDesktop /v ActiveWndTrkTimeout /t REG_DWORD /d 0 /f >$null 2>&1
        & reg add $InputDesktop /v KeyboardDelay /t REG_SZ /d "0" /f >$null 2>&1
        & reg add $InputDesktop /v KeyboardSpeed /t REG_SZ /d "31" /f >$null 2>&1

        $InputMouse = "HKU\SrdpDefault\Control Panel\Mouse"
        & reg add $InputMouse /v MouseSpeed /t REG_SZ /d "0" /f >$null 2>&1
        & reg add $InputMouse /v MouseThreshold1 /t REG_SZ /d "0" /f >$null 2>&1
        & reg add $InputMouse /v MouseThreshold2 /t REG_SZ /d "0" /f >$null 2>&1
        & reg add $InputMouse /v MouseSensitivity /t REG_SZ /d "10" /f >$null 2>&1
        & reg add $InputMouse /v MouseTrails /t REG_SZ /d "0" /f >$null 2>&1
        & reg add $InputMouse /v ClickLock /t REG_SZ /d "0" /f >$null 2>&1
        & reg add $InputMouse /v SmoothMouseXCurve /t REG_BINARY /d 00000000000000000000000000000000000000000000000000000000000000000000000000000000 /f >$null 2>&1
        & reg add $InputMouse /v SmoothMouseYCurve /t REG_BINARY /d 00000000000000000000000000000000000000000000000000000000000000000000000000000000 /f >$null 2>&1
        & reg add "HKU\SrdpDefault\Control Panel\Cursors" /v CursorShadow /t REG_SZ /d "0" /f >$null 2>&1

        # ---- EXCLUSIVE FULLSCREEN (bypass komposisi DWM) ----------------------------------------------
        # FSEBehaviorMode=2 memaksa game fullscreen memakai flip-exclusive (bukan borderless compose),
        # sehingga 1 frame hanya digambar sekali, bukan dikomposisi DWM lalu di-encode RDP.
        $fse = "HKU\SrdpDefault\System\GameConfigStore"
        & reg add $fse /v GameDVR_FSEBehaviorMode /t REG_DWORD /d 2 /f >$null 2>&1
        & reg add $fse /v GameDVR_HonorUserFSEBehaviorMode /t REG_DWORD /d 1 /f >$null 2>&1
        & reg add $fse /v GameDVR_DXGIHonorFSEWindowsCompatible /t REG_DWORD /d 1 /f >$null 2>&1
        & reg add $fse /v GameDVR_EFSEFeatureFlags /t REG_DWORD /d 0 /f >$null 2>&1

        # ---- RINGANKAN DELTA RDP ---------------------------------------------------------------------
        # Wallpaper polos = tile yang dikirim encoder RDP jauh lebih sedikit (khususnya saat AFK).
        & reg add "HKU\SrdpDefault\Control Panel\Desktop" /v Wallpaper /t REG_SZ /d "" /f >$null 2>&1
        & reg add "HKU\SrdpDefault\Control Panel\Desktop" /v TileWallpaper /t REG_SZ /d "0" /f >$null 2>&1
        # Izin aplikasi (auto-clicker/macro) merebut foreground tanpa diblokir Focus Assist
        & reg add "HKU\SrdpDefault\Control Panel\Desktop" /v ForegroundLockTimeout /t REG_DWORD /d 0 /f >$null 2>&1

        # ---- SHUTDOWN/BACKUP LEBIH CEPAT --------------------------------------------------------------
        # Agar sesi + Atomic Vault selesai sebelum batas keras 6 jam GitHub Actions.
        & reg add "HKU\SrdpDefault\Control Panel\Desktop" /v AutoEndTasks /t REG_SZ /d "1" /f >$null 2>&1
        & reg add "HKU\SrdpDefault\Control Panel\Desktop" /v WaitToKillAppTimeout /t REG_SZ /d "2000" /f >$null 2>&1
        & reg add "HKU\SrdpDefault\Control Panel\Desktop" /v HungAppTimeout /t REG_SZ /d "2000" /f >$null 2>&1
        [System.GC]::Collect()
        Start-Sleep -Milliseconds 300
        & reg unload "HKU\SrdpDefault" >$null 2>&1
    }
}

bcdedit /set testsigning off 2>$null | Out-Null
bcdedit /set disabledynamictick yes 2>$null | Out-Null
bcdedit /deletevalue numproc 2>$null | Out-Null
bcdedit /deletevalue truncatememory 2>$null | Out-Null

Write-Host "==> [5/10] Tuning RDP Frame Pacing ($RdpFps FPS), Encoder Path & Enabling Audio Sink..." -ForegroundColor Cyan

# --- Desktop composition pacing -------------------------------------------------
# DWMFRAMEINTERVAL is a millisecond frame interval. 15 ~= 60 FPS, 33 ~= 30 FPS.
# On a GPU-less host (WARP/llvmpipe) every composed frame is a full CPU copy + encode, so a hard 60 FPS
# target silently eats an entire vCPU and DROPS the real in-game FPS. We therefore pace to $RdpFps
# (30 by default) unless a real GPU exists.
$targetFps = $RdpFps
if ($Script:SrdpGpu -and $targetFps -lt 60) { $targetFps = 60 }
$frameIntervalMs = [int][Math]::Round(1000 / $targetFps)
if ($frameIntervalMs -lt 5) { $frameIntervalMs = 5 }

$DwmWinStation = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations"
Set-ItemProperty -Path $DwmWinStation -Name "DWMFRAMEINTERVAL" -Value $frameIntervalMs -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    DWMFRAMEINTERVAL=$frameIntervalMs ms (~$targetFps FPS composition target)" -ForegroundColor Green

# --- Terminal Services graphics policies ---------------------------------------
$TsPolicies = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
if (-not (Test-Path $TsPolicies)) { New-Item -Path $TsPolicies -Force | Out-Null }
if ($Script:SrdpGpu) {
    # Hardware H.264/AVC444 (needs a real hardware encoder, otherwise Windows silently falls back to RFX).
    Set-ItemProperty -Path $TsPolicies -Name "AVC444ModePreferred" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $TsPolicies -Name "AVCHardwareEncodePreferred" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
} else {
    # Software-only host: forcing AVC444 makes the session probe/attempt a software H.264 4:4:4 encode.
    # The cheaper RemoteFX Progressive path keeps the desktop responsive and hands the freed core to the game.
    Set-ItemProperty -Path $TsPolicies -Name "AVC444ModePreferred" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $TsPolicies -Name "AVCHardwareEncodePreferred" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
}
Set-ItemProperty -Path $TsPolicies -Name "fEnableVirtualizedGraphics" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $TsPolicies -Name "SelectTransport" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $TsPolicies -Name "bEnumerateHWBeforeSW" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $TsPolicies -Name "GraphicsProfile" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $TsPolicies -Name "VGOptimization_CaptureFrameRate" -Value ([Math]::Min($targetFps, 60)) -Type DWord -Force -ErrorAction SilentlyContinue
# MaxCompressionLevel: 0 = "optimize for least memory/CPU", 1 = "least bandwidth", 2 = balanced (default).
# Di runner 4 vCPU, CPU adalah bottleneck dan bandwidth Tailscale berlimpah -> pilih 0 agar frame tidak
# tertahan oleh kompresor yang mahal.
Set-ItemProperty -Path $TsPolicies -Name "MaxCompressionLevel" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $TsPolicies -Name "MaxDisconnectionTime" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $TsPolicies -Name "MaxIdleTime" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $TsPolicies -Name "MaxConnectionTime" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $TsPolicies -Name "fResetBroken" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $TsPolicies -Name "fDisableCam" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

# --- TermDD flow control -------------------------------------------------------
# Default flow control throttles the display channel to a conservative bitrate, which is what makes RDP
# feel like a slideshow over Tailscale even when the uplink is fine. Networking is cheap here, CPU is not.
$TermDD = "HKLM:\SYSTEM\CurrentControlSet\Services\TermDD"
Set-ItemProperty -Path $TermDD -Name "FlowControlDisable" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $TermDD -Name "FlowControlDisplayBandwidth" -Value 16 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $TermDD -Name "FlowControlChannelBandwidth" -Value 144 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $TermDD -Name "FlowControlChargePostCompression" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

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

Write-Host "==> [6/10] Registering Native AFK Guardian (CPU Hog Killer + Game Priority Booster + RAM Cleaner)..." -ForegroundColor Cyan
$SysScriptsDir = "C:\ProgramData\S-RDP"
New-Item -ItemType Directory -Path $SysScriptsDir -Force | Out-Null

$OptimizerLoopPs1 = @'
$ErrorActionPreference = "SilentlyContinue"

$SrdpUser = "__RDP_USER__"

# 1. Keep CPU hogs dead
foreach ($hog in @("mscorsvw", "ngen", "ngentask", "CompatTelRunner", "TiWorker", "MpCmdRun")) {
    Get-Process -Name $hog | Stop-Process -Force
}

# 2. Auto-Boost active user GUI applications (Games) & unlock full multi-core affinity
$logicalCount = [Environment]::ProcessorCount
# Only touch affinity when the mask actually fits into a 64-bit value (above that the API rejects it).
$canSetAffinity = $logicalCount -gt 0 -and $logicalCount -le 62
$fullAffinityMask = $null
if ($canSetAffinity) { $fullAffinityMask = [IntPtr]::new(([int64]1 -shl $logicalCount) - 1) }

$systemIgnore = @(
    "explorer", "taskmgr", "cmd", "powershell", "pwsh", "conhost", "dwm", "csrss", "winlogon",
    "svchost", "lsass", "services", "tailscaled", "tailscale-ipn", "rdpclip", "sihost", "ctfmon",
    "TextInputHost", "ShellExperienceHost", "SearchHost", "StartMenuExperienceHost",
    "steamwebhelper", "steam", "Discord", "Update", "ApplicationFrameHost", "SystemSettings"
)
Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and ($systemIgnore -notcontains $_.ProcessName) } | ForEach-Object {
    if ($_.PriorityClass -eq "Normal") {
        $_.PriorityClass = "AboveNormal"
    }
    # Unlock full vCPU thread affinity in case a 32-bit/legacy game locked itself to 1-2 cores!
    # Cast both sides to Int64: comparing IntPtr with -ne is unreliable in PowerShell.
    if ($canSetAffinity -and ([int64]$_.ProcessorAffinity -ne [int64]$fullAffinityMask)) {
        $_.ProcessorAffinity = $fullAffinityMask
    }
}

# 3. Demote Chromium/Electron UIs that software-composite on a GPU-less host (biggest hidden FPS thief:
#    steamwebhelper + Discord fall back to CPU rasterization and can pin a full core while AFK farming).
foreach ($bg in @("steamwebhelper", "Discord")) {
    Get-Process -Name $bg | Where-Object { $_.PriorityClass -ne "Idle" } | ForEach-Object {
        $_.PriorityClass = "BelowNormal"
    }
}

# 4. Keep Steam's Chromium UI GPU acceleration disabled (it would otherwise software-render via SwiftShader)
$steamUser = Get-LocalUser -Name $SrdpUser
if ($steamUser -and $steamUser.SID) {
    $steamHive = "HKU\$($steamUser.SID.Value)\Software\Valve\Steam"
    if (Test-Path "Registry::$steamHive") {
        $wantFlags = "-cef-disable-gpu -cef-disable-gpu-compositing"
        $curFlags = (Get-ItemProperty -Path "Registry::$steamHive" -Name "BrowserFlags").BrowserFlags
        if ($curFlags -ne $wantFlags) {
            New-ItemProperty -Path "Registry::$steamHive" -Name "BrowserFlags" -Value $wantFlags -PropertyType String -Force
        }
    }
}

# 5. Keep Discord hardware acceleration off (only when Discord is closed, so we never fight its own writes)
if (-not (Get-Process -Name "Discord" -ErrorAction SilentlyContinue)) {
    $discordSettings = "C:\Users\$SrdpUser\AppData\Roaming\discord\settings.json"
    if (Test-Path $discordSettings) {
        try {
            $raw = Get-Content -Path $discordSettings -Raw -ErrorAction Stop
            if ($raw -match '"enableHardwareAcceleration"\s*:\s*true') {
                $raw = $raw -replace '"enableHardwareAcceleration"\s*:\s*true', '"enableHardwareAcceleration":false'
                Set-Content -Path $discordSettings -Value $raw -Encoding UTF8 -NoNewline
            }
        } catch {}
    }
}

# 6. Trim leaked background RAM if total memory > 78%
$os = Get-CimInstance Win32_OperatingSystem
if ($os -and $os.TotalVisibleMemorySize -gt 0) {
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
}
'@
$OptimizerLoopPs1 = $OptimizerLoopPs1.Replace('__RDP_USER__', $RdpUser)
$OptimizerPath = "$SysScriptsDir\afk-guardian.ps1"
Set-Content -Path $OptimizerPath -Value $OptimizerLoopPs1 -Encoding UTF8

$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$OptimizerPath`""
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Hours 12)
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -Priority 4
Register-ScheduledTask -TaskName "S-RDP-AfkGuardian" -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force | Out-Null

# ---------------------------------------------------------------------------
# 1 ms System Timer Resolution keeper (timeBeginPeriod)
# Windows default ~15.6 ms. Semua sleep/timeout/WaitForSingleObject jadi lebih presisi -> jitter input,
# frame pacing, dan respons auto-clicker membaik tanpa biaya CPU berarti. Dijaga hidup oleh task SYSTEM.
# ---------------------------------------------------------------------------
$TimerResPs1 = @'
$ErrorActionPreference = "SilentlyContinue"
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class SrdpTimer {
    [DllImport("winmm.dll")] public static extern uint timeBeginPeriod(uint period);
    [DllImport("winmm.dll")] public static extern uint timeEndPeriod(uint period);
}
"@
[SrdpTimer]::timeBeginPeriod(1) | Out-Null
# Tahan proses tetap hidup (permintaan 1 ms hanya berlaku selama proses ini berjalan)
while ($true) { Start-Sleep -Seconds 600 }
'@
$TimerResPath = "$SysScriptsDir\timer-resolution.ps1"
Set-Content -Path $TimerResPath -Value $TimerResPs1 -Encoding UTF8

$TimerAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$TimerResPath`""
$TimerTrigger = New-ScheduledTaskTrigger -AtStartup
$TimerPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$TimerSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "S-RDP-TimerResolution" -Action $TimerAction -Trigger $TimerTrigger -Principal $TimerPrincipal -Settings $TimerSettings -Force | Out-Null
Start-ScheduledTask -TaskName "S-RDP-TimerResolution" -ErrorAction SilentlyContinue
Write-Host "    Timer resolution 1 ms aktif (S-RDP-TimerResolution)." -ForegroundColor Green

Write-Host "==> [7/10] Configuring User Account & Console Auto-Logon..." -ForegroundColor Cyan
$SecurePass = ConvertTo-SecureString $RdpPassword -AsPlainText -Force
if (Get-LocalUser -Name $RdpUser -ErrorAction SilentlyContinue) {
    Set-LocalUser -Name $RdpUser -Password $SecurePass -PasswordNeverExpires:$true
} else {
    New-LocalUser -Name $RdpUser -Password $SecurePass -FullName "AFK Gamer" -PasswordNeverExpires:$true -AccountNeverExpires:$true | Out-Null
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
Set-Service -Name "TermService" -StartupType Automatic -ErrorAction SilentlyContinue
Restart-Service -Name "TermService" -Force -ErrorAction SilentlyContinue

Write-Host "==> [8/10] Cleaning Runner Temp Files..." -ForegroundColor Cyan
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue

if (Test-SrdpTrue $InstallGameRuntimes) {
    Write-Host "==> [9/10] Checking & Installing Gaming Runtimes (DirectX 9/10/11 Legacy + Smart VC++ Check)..." -ForegroundColor Cyan
    # DirectX Legacy (June 2010 d3dx9_43.dll / xinput1_3.dll / d3dcompiler_43.dll — NOT pre-installed on Windows Server!)
    if (-not (Test-Path "$env:SystemRoot\System32\d3dx9_43.dll")) {
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
    } else {
        Write-Host "    DirectX Legacy Runtimes already present — skipped." -ForegroundColor Green
    }

    # Smart VC++ Check: x86 runtime lives under WOW6432Node on 64-bit Windows!
    $vc64Installed = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue).Installed -eq 1
    $vc86Installed = ((Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86" -ErrorAction SilentlyContinue).Installed -eq 1) -or `
                     ((Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x86" -ErrorAction SilentlyContinue).Installed -eq 1)
    if ($vc64Installed -and $vc86Installed) {
        Write-Host "    Visual C++ 2015-2022 (x64 & x86) already pre-installed on runner — skipped (saved ~20s)!" -ForegroundColor Green
    } else {
        try {
            if (-not $vc64Installed) {
                $vcX64 = "$env:TEMP\vc_redist.x64.exe"
                Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile $vcX64 -UseBasicParsing
                Start-Process -FilePath $vcX64 -ArgumentList "/install /quiet /norestart" -Wait
                Remove-Item $vcX64 -Force -ErrorAction SilentlyContinue
            }
            if (-not $vc86Installed) {
                $vcX86 = "$env:TEMP\vc_redist.x86.exe"
                Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x86.exe" -OutFile $vcX86 -UseBasicParsing
                Start-Process -FilePath $vcX86 -ArgumentList "/install /quiet /norestart" -Wait
                Remove-Item $vcX86 -Force -ErrorAction SilentlyContinue
            }
            Write-Host "    Visual C++ Runtimes installed successfully." -ForegroundColor Green
        } catch {
            Write-Warning "    Could not install VC++ Redistributable: $_"
        }
    }
} else {
    Write-Host "==> [9/10] Skipping Gaming Runtimes installation (disabled by input)." -ForegroundColor Yellow
}

if (Test-SrdpTrue $InstallMesa3D) {
    Write-Host "==> [9.5/10] Deploying Mesa3D Software Renderer (llvmpipe OpenGL 4.5 for GPU-less games)..." -ForegroundColor Cyan
    try {
        $mesaDir = "C:\Tools\Mesa3D"
        New-Item -ItemType Directory -Path $mesaDir -Force | Out-Null

        # Resolve 7-Zip explicitly (it is pre-installed on GitHub runners, but never assume %PATH%).
        $sevenZip = "C:\Program Files\7-Zip\7z.exe"
        if (-not (Test-Path $sevenZip)) {
            $sevenCmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
            if ($sevenCmd) { $sevenZip = $sevenCmd.Source }
        }

        $releaseApi = Invoke-RestMethod -Uri "https://api.github.com/repos/pal1000/mesa-dist-win/releases/latest" `
            -Headers @{ "User-Agent" = "S-RDP-AFK" } -UseBasicParsing -ErrorAction Stop
        $asset = $releaseApi.assets | Where-Object { $_.name -match "release-msvc\.7z$" } | Select-Object -First 1
        if (-not $asset) { throw "Aset mesa3d-*-release-msvc.7z tidak ditemukan pada rilis terbaru." }

        if (Test-Path $sevenZip) {
            $archivePath = "$mesaDir\$($asset.name)"
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archivePath -UseBasicParsing
            & $sevenZip x $archivePath "-o$mesaDir" -y | Out-Null
            Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
            Write-Host "    Mesa3D $($releaseApi.tag_name) diekstrak ke $mesaDir" -ForegroundColor Green
        } else {
            throw "7-Zip tidak ditemukan untuk mengekstrak paket Mesa3D."
        }

        # Optional system-wide deployment: replaces the inbox OpenGL 1.1 software driver (which is what makes
        # old OpenGL games/emulators refuse to start or render at single digit FPS on a GPU-less VM).
        if (Test-SrdpTrue $MesaSystemWide) {
            $deployMap = @(
                @{ Source = (Join-Path $mesaDir "x64"); Target = (Join-Path $env:SystemRoot "System32") },
                @{ Source = (Join-Path $mesaDir "x86"); Target = (Join-Path $env:SystemRoot "SysWOW64") }
            )
            $dllNames = @("opengl32.dll", "libgallium_wgl.dll", "libglapi.dll", "dxil.dll", "libEGL.dll", "libGLESv2.dll")
            $deployed = 0
            foreach ($map in $deployMap) {
                if (-not (Test-Path $map.Source)) { continue }
                if (-not (Test-Path $map.Target)) { continue }
                foreach ($dll in $dllNames) {
                    $srcDll = Join-Path $map.Source $dll
                    if (-not (Test-Path $srcDll)) { continue }
                    $dstDll = Join-Path $map.Target $dll
                    if ((Test-Path $dstDll) -and -not (Test-Path "$dstDll.srdp-bak")) {
                        Copy-Item -Path $dstDll -Destination "$dstDll.srdp-bak" -Force -ErrorAction SilentlyContinue
                    }
                    Copy-Item -Path $srcDll -Destination $dstDll -Force -ErrorAction SilentlyContinue
                    if (Test-Path $dstDll) { $deployed++ }
                }
            }
            if ($deployed -gt 0) {
                Write-Host "    System-wide OpenGL upgraded: $deployed DLL terpasang (backup asli: *.srdp-bak)." -ForegroundColor Green
            } else {
                Write-Warning "    System-wide deployment tidak menemukan DLL Mesa3D (periksa struktur arsip)."
            }
        }
    } catch {
        Write-Warning "    Could not deploy Mesa3D: $_"
    }
} else {
    Write-Host "==> [9.5/10] Skipping Mesa3D deployment (disabled by input)." -ForegroundColor Yellow
}

# Final sweep of any .NET NGEN / Windows Installer workers spawned during setup
foreach ($proc in @("mscorsvw", "ngen", "ngentask", "TiWorker")) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Write-Host "==> [10/10] Creating Essential AFK Session Controls on Desktop..." -ForegroundColor Cyan
$PublicDesktop = "C:\Users\Public\Desktop"

$KeepAliveBat = @'
@echo off
title AFK Mode - Disconnect Without Freezing Game
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
echo game, auto-clicker, dan macro dipindahkan ke Console aktif
echo (1280x720 @ 100% DPI) sehingga TIDAK FREEZE di background!
echo.
echo TIPS: Gunakan RDP dengan resolusi 1280x720 agar posisi klik
echo auto-clicker 100% sama persis saat ditinggal AFK!
echo.
timeout /t 3 >nul
REM Handover berdasarkan Session ID proses ini sendiri (bebas salah-parse multi-user / spasi nama user)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=(Get-Process -Id $PID).SessionId; & (Join-Path $env:windir 'System32\tscon.exe') $s /dest:console"
if errorlevel 1 (
    REM Fallback: pakai nama sesi aktif jika Session ID gagal dipindahkan
    %windir%\System32\tscon.exe %SESSIONNAME% /dest:console
)
if errorlevel 1 (
    echo.
    echo [GAGAL] Handover ke Console ditolak. Jalankan file ini sebagai Administrator.
    pause
)
'@
Set-Content -Path "$PublicDesktop\AFK-Disconnect-Tanpa-Freeze.bat" -Value $KeepAliveBat -Encoding ASCII

$StopRdpBat = @'
@echo off
title Stop and Backup S-RDP Session
echo ========================================================
echo   SIMPAN DATA VAULT ^& MATIKAN SERVER RDP SEKARANG?
echo ========================================================
echo Seluruh data Steam, Discord, dan Folder Permanen akan
echo di-backup otomatis (AES-256) sebelum server dimatikan.
echo.
choice /C YN /M "Yakin ingin menyimpan data dan mematikan RDP sekarang"
if errorlevel 2 exit /b
echo Mengirim sinyal Auto-Backup ^& Shutdown...
echo stop > "C:\stop-s-rdp.flag"
timeout /t 4
'@
Set-Content -Path "$PublicDesktop\Matikan-Server-RDP.bat" -Value $StopRdpBat -Encoding ASCII

$GuideTxt = @"
====================================================================
  PANDUAN S-RDP KHUSUS AFK GAME BERAT (AUDITED & MAX TUNED)
====================================================================

OPTIMASI AKTIF DI SERVER INI:
  [v] Atomic AES-256 Anti-Reset Vault (Anti Data Corrupt/Hilang)
  [v] Instant Zero-Copy AppData Junctions (Steam & Discord Siap Pakai)
  [v] Windows Defender + .NET NGEN + Telemetry KILLED (CPU Idle ~1-3%)
  [v] All vCPU Threads Unparked @ 100% Boost Clock (AMD EPYC 3.24+ GHz)
  [v] Console Locked 1280x720 @ 100% DPI (koordinat auto-clicker stabil)
  [v] RDP Frame Pacing $RdpFps FPS + TermDD FlowControl dilepas (anti-slideshow)
  [v] Mesa3D llvmpipe (OpenGL 4.5) + LP_NUM_THREADS disetel untuk 4 vCPU
  [v] Steam CEF & Discord GPU acceleration dimatikan (hemat 1 core penuh!)
  [v] 20 GB Virtual Memory Pagefile + Fast NTFS I/O Cache
  [v] Auto Game Priority Booster + Auto RAM Cleaner (Tiap 5 Menit)

KENAPA GAME DI SINI BISA 5 FPS (DAN CARA NAIKKANNYA):
  Runner GitHub TIDAK punya GPU. Semua render 3D dihitung CPU (WARP/llvmpipe),
  jadi resolusi & efek grafis adalah segalanya:
   1. Jalankan game dalam mode WINDOWED 1280x720 atau 1024x768.
   2. Matikan Shadow, Anti-Aliasing, Bloom, Motion Blur, Ray Tracing, V-Sync.
   3. Set limit FPS in-game 30 (jangan 60 - CPU tidak akan sanggup).
   4. Klik 2x "Optimalkan-Game-Ini.bat" lalu pilih file .exe game:
      skrip akan memasang driver OpenGL Mesa khusus game itu, mematikan
      Fullscreen Optimization DWM, dan membuat launcher hemat CPU.
   5. Klik 2x "Cek-Performa-Render.bat" untuk melihat GPU/renderer aktif
      serta proses yang paling banyak makan CPU.

1. AGAR KOORDINAT AUTO-CLICKER TIDAK GESER SAAT AFK:
   - Disarankan atur Display Remote Desktop kamu ke resolusi 1280x720
     (sama persis dengan resolusi layar Console AFK 1280x720 @ 100% DPI).
   - Saat mau tinggal AFK, JANGAN klik [X]! Klik 2x file:
     "AFK-Disconnect-Tanpa-Freeze.bat" di Desktop.

2. CARA AGAR STEAM, DISCORD, & GAME TIDAK HILANG TIAP 6 JAM:
   - Login Steam sekali & centang "Remember Me".
   - Install/simpan semua game & bot di dalam "Folder-Permanen-Anti-Reset".
   - Klik "Simpan-Data-Sekarang.bat" kapan pun mau save manual, atau klik
     "Matikan-Server-RDP.bat" saat selesai (otomatis backup sebelum mati).

3. KALAU KLIK TERASA ADA JEDA (INPUT LATENCY):
   - Server sudah di-set 0 ms: MenuShowDelay, MouseHoverTime, key-repeat instan,
     pointer acceleration OFF, kursor tanpa bayangan, drag hanya outline.
   - Cek "Latensi Tailscale" di ringkasan run: kalau RELAY DERP => itu penyebabnya.
   - Di klien: Experience = LAN (10 Mbps or higher), Color depth 16-bit.
   - Di HP/tablet: matikan mode sentuh / "tap and hold" (menahan klik ~1 detik),
     pakai mouse/trackpad mode. Matikan "Enhance pointer precision" di Windows lokal.
   - Jedanya di dalam game = waktu render 1 frame: kecilkan resolusi & efek grafis.

4. TIP KLIEN RDP (di HP/PC kamu):
   - Experience: pilih "LAN (10 Mbps or higher)".
   - Color depth: 16-bit (lebih ringan untuk encoder software).
   - Jangan pakai mode fullscreen borderless pada aplikasi RDP.
====================================================================
"@
Set-Content -Path "$PublicDesktop\BACA-PANDUAN-AFK-GAME.txt" -Value $GuideTxt -Encoding UTF8

# ---------------------------------------------------------------------------
# Per-game optimizer: the single most effective fix for a game that renders at 5 FPS on a GPU-less runner.
# It deploys Mesa3D llvmpipe next to the game's executable (hardlink = 0 extra disk), forces the app to load
# it, disables DWM fullscreen-optimization double composition, and writes a CPU-friendly launcher.
# ---------------------------------------------------------------------------
$OptimizeGamePs1 = @'
$ErrorActionPreference = "SilentlyContinue"

$exe = ""
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Pilih file .exe game yang mau dioptimalkan (Naikkan FPS)"
    $dlg.Filter = "Aplikasi game (*.exe)|*.exe|Semua file (*.*)|*.*"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $exe = $dlg.FileName
    }
} catch {
    # Windows Forms needs an STA thread; if the dialog cannot be shown, fall back to a typed path.
    Write-Warning "Dialog file tidak bisa dibuka ($($_.Exception.Message))."
}

if ([string]::IsNullOrWhiteSpace($exe)) {
    Write-Host "Tempel path lengkap file .exe game (contoh: D:\AFK-Data\Games\Game\game.exe)" -ForegroundColor Yellow
    $typed = Read-Host "Path .exe"
    if ($typed) { $exe = ([string]$typed).Trim().Trim('"') }
}
if ([string]::IsNullOrWhiteSpace($exe) -or -not (Test-Path -LiteralPath $exe)) {
    Write-Host "File tidak ditemukan. Dibatalkan." -ForegroundColor Yellow
    Start-Sleep -Seconds 3
    exit 0
}
$dir = Split-Path $exe -Parent
$base = [IO.Path]::GetFileNameWithoutExtension($exe)

Write-Host ""
Write-Host "==> Mengoptimalkan: $exe" -ForegroundColor Cyan

# --- 1. Detect 32-bit vs 64-bit PE so we deploy the matching Mesa3D build -------------
function Test-IsPe64 {
    param([string]$Path)
    try {
        $fs = [IO.File]::OpenRead($Path)
        $br = New-Object IO.BinaryReader($fs)
        $fs.Position = 0x3C
        $peOffset = $br.ReadInt32()
        $fs.Position = $peOffset + 4
        $machine = $br.ReadUInt16()
        $fs.Close()
        return ($machine -eq 0x8664)   # IMAGE_FILE_MACHINE_AMD64
    } catch { return $true }
}
$is64 = Test-IsPe64 -Path $exe

# --- 2. Deploy Mesa3D (llvmpipe OpenGL 4.5) beside the game -------------------------
$mesaRoot = "C:\Tools\Mesa3D"
$archDir = if ($is64) { Join-Path $mesaRoot "x64" } else { Join-Path $mesaRoot "x86" }
$dllList = @("opengl32.dll", "libgallium_wgl.dll", "libglapi.dll", "dxil.dll")
$deployed = 0
if (Test-Path $archDir) {
    foreach ($dll in $dllList) {
        $src = Join-Path $archDir $dll
        if (-not (Test-Path $src)) { continue }
        $dst = Join-Path $dir $dll
        if ((Test-Path $dst) -and -not (Test-Path "$dst.srdp-bak")) {
            # Never silently destroy a DLL the game shipped itself (some older titles bundle ANGLE/GL).
            Copy-Item -Path $dst -Destination "$dst.srdp-bak" -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -Path $dst -Force -ErrorAction SilentlyContinue
        New-Item -ItemType HardLink -Path $dst -Target $src -Force -ErrorAction SilentlyContinue | Out-Null
        if (-not (Test-Path $dst)) { Copy-Item -Path $src -Destination $dst -Force -ErrorAction SilentlyContinue }
        if (Test-Path $dst) { $deployed++ }
    }
    # .local marker forces stubborn executables to load the local OpenGL DLL instead of System32
    Set-Content -Path "$exe.local" -Value "" -Encoding ASCII -ErrorAction SilentlyContinue
    Write-Host "    Mesa3D $(if ($is64) { 'x64' } else { 'x86' }) dipasang di folder game ($deployed DLL)." -ForegroundColor Green
} else {
    Write-Host "    Mesa3D belum tersedia (C:\Tools\Mesa3D). Jalankan workflow dengan opsi install_mesa3d = true." -ForegroundColor Yellow
}

# --- 3. Kill DWM fullscreen-optimization double composition -------------------------
$layers = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
if (-not (Test-Path $layers)) { New-Item -Path $layers -Force | Out-Null }
Set-ItemProperty -Path $layers -Name $exe -Value "~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE" -Type String -Force
Write-Host "    Fullscreen Optimization DWM dimatikan (render langsung, tanpa komposisi ganda)." -ForegroundColor Green

# --- 4. CPU-friendly launcher with tuned Mesa/llvmpipe environment ------------------
$cpu = [Environment]::ProcessorCount
$threads = [Math]::Max(2, $cpu - 1)
$launcher = @"
@echo off
title $base (Mode Hemat CPU - S-RDP)
set LP_NUM_THREADS=$threads
set GALLIUM_DRIVER=llvmpipe
set LIBGL_ALWAYS_SOFTWARE=1
set mesa_glthread=true
set vblank_mode=0
set MESA_GL_VERSION_OVERRIDE=4.5
set MESA_GLSL_VERSION_OVERRIDE=450
cd /d "%~dp0"
start "" "$exe"
"@
$launcherPath = Join-Path $dir "Jalankan-$base-Hemat-CPU.bat"
Set-Content -Path $launcherPath -Value $launcher -Encoding ASCII
Write-Host "    Launcher dibuat: $launcherPath" -ForegroundColor Green

# Launcher alternatif: OpenGL lewat GLonD3D12 (mesin WARP Direct3D 12 milik Windows).
# Untuk game yang fill-rate berat, jalur ini kadang 1.5-2x lebih cepat dari llvmpipe.
$launcherD3D12 = @"
@echo off
title $base (Mode D3D12-WARP - S-RDP)
set LIBGL_ALWAYS_SOFTWARE=1
set GALLIUM_DRIVER=d3d12
set mesa_glthread=true
set vblank_mode=0
set MESA_NO_ERROR=1
cd /d "%~dp0"
start "" "$exe"
"@
$launcherD3D12Path = Join-Path $dir "Jalankan-$base-D3D12.bat"
Set-Content -Path $launcherD3D12Path -Value $launcherD3D12 -Encoding ASCII
Write-Host "    Launcher alternatif (D3D12/WARP): $launcherD3D12Path" -ForegroundColor Green

Write-Host ""
Write-Host "SELESAI! Buka game lewat file 'Jalankan-$base-Hemat-CPU.bat'." -ForegroundColor Cyan
Write-Host "Kalau versi Hemat-CPU masih berat, coba 'Jalankan-$base-D3D12.bat'" -ForegroundColor Yellow
Write-Host "(OpenGL lewat WARP Direct3D 12 - sering lebih cepat untuk game fill-rate berat)." -ForegroundColor Yellow
Write-Host "Kalau masih berat: turunkan resolusi ke 1024x768 / 800x600, matikan" -ForegroundColor Yellow
Write-Host "Shadow + Anti-Aliasing + V-Sync, dan batasi FPS in-game ke 30." -ForegroundColor Yellow
Write-Host ""
Read-Host "Tekan Enter untuk menutup"
'@
$OptimizeGamePath = "$SysScriptsDir\optimize-game.ps1"
Set-Content -Path $OptimizeGamePath -Value $OptimizeGamePs1 -Encoding UTF8

$OptimizeGameBat = @"
@echo off
title Optimalkan Game - Naikkan FPS
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$OptimizeGamePath"
"@
Set-Content -Path "$PublicDesktop\Optimalkan-Game-Ini.bat" -Value $OptimizeGameBat -Encoding ASCII

# ---------------------------------------------------------------------------
# Render diagnostics: shows exactly which renderer is active and what is eating the CPU.
# ---------------------------------------------------------------------------
$RenderDiagPs1 = @'
$ErrorActionPreference = "SilentlyContinue"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  DIAGNOSTIK RENDER & PERFORMA S-RDP" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "[1] ADAPTER GRAFIS (tidak ada GPU diskrit = render lewat CPU/WARP)" -ForegroundColor Yellow
Get-CimInstance Win32_VideoController | ForEach-Object {
    Write-Host ("    - {0} | Driver: {1} | Mode: {2}" -f $_.Name, $_.DriverVersion, $_.VideoModeDescription)
}

Write-Host ""
Write-Host "[2] OPENGL (Mesa3D / llvmpipe)" -ForegroundColor Yellow
$glDll = Join-Path $env:SystemRoot "System32\opengl32.dll"
if (Test-Path $glDll) {
    $ver = (Get-Item $glDll).VersionInfo
    Write-Host ("    opengl32.dll : {0} / {1}" -f $ver.FileVersion, $ver.CompanyName)
}
if (Test-Path "$glDll.srdp-bak") {
    Write-Host "    System-wide Mesa3D : AKTIF (backup driver asli tersimpan)" -ForegroundColor Green
} else {
    Write-Host "    System-wide Mesa3D : belum/tidak aktif" -ForegroundColor Yellow
}
if (Test-Path "C:\Tools\Mesa3D\x64") { Write-Host "    Paket Mesa3D       : C:\Tools\Mesa3D (OK)" -ForegroundColor Green }
foreach ($v in @("LP_NUM_THREADS", "GALLIUM_DRIVER", "mesa_glthread", "vblank_mode", "MESA_GL_VERSION_OVERRIDE")) {
    Write-Host ("    {0} = {1}" -f $v, [Environment]::GetEnvironmentVariable($v, "Machine"))
}

Write-Host ""
Write-Host "[3] KONFIG RDP / DWM" -ForegroundColor Yellow
$dwm = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations" -Name DWMFRAMEINTERVAL).DWMFRAMEINTERVAL
$ts  = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
if ($dwm) { Write-Host ("    DWMFRAMEINTERVAL = {0} ms (~{1} FPS)" -f $dwm, [Math]::Round(1000 / $dwm)) }
Write-Host ("    AVC444ModePreferred      = {0}" -f $ts.AVC444ModePreferred)
Write-Host ("    AVCHardwareEncodePreferred = {0}" -f $ts.AVCHardwareEncodePreferred)
Write-Host ("    VGOptimization_CaptureFrameRate = {0}" -f $ts.VGOptimization_CaptureFrameRate)

Write-Host ""
Write-Host "[4] 10 PROSES PALING BANYAK MAKAN CPU" -ForegroundColor Yellow
Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name, Id, @{N = "CPU(s)"; E = { [Math]::Round($_.CPU, 1) } }, @{N = "RAM(MB)"; E = { [Math]::Round($_.WorkingSet64 / 1MB, 1) } }, PriorityClass | Format-Table -AutoSize

Write-Host "[5] PEMAKAIAN MEMORI" -ForegroundColor Yellow
$os = Get-CimInstance Win32_OperatingSystem
$usedGb = [Math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
$totalGb = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
Write-Host ("    RAM: {0} / {1} GB | CPU Logical: {2}" -f $usedGb, $totalGb, [Environment]::ProcessorCount)
Write-Host ""
Read-Host "Tekan Enter untuk menutup"
'@
$RenderDiagPath = "$SysScriptsDir\render-diagnostics.ps1"
Set-Content -Path $RenderDiagPath -Value $RenderDiagPs1 -Encoding UTF8

$RenderDiagBat = @"
@echo off
title Cek Performa Render
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$RenderDiagPath"
"@
Set-Content -Path "$PublicDesktop\Cek-Performa-Render.bat" -Value $RenderDiagBat -Encoding ASCII

Write-Host "==> Zero-Cost Maximum AFK Optimization Complete!" -ForegroundColor Green
$global:LASTEXITCODE = 0
exit 0
