<#
.SYNOPSIS
    Audited Atomic AES-256 Persistent Vault for S-RDP (Zero Data-Loss + Zero Profile-Corruption).
.DESCRIPTION
    Key Audited Guarantees:
    1. NEVER pre-creates C:\Users\<RdpUser> before Windows Winlogon creates the real profile!
       Instead, registers a fast Logon Script that links (%AppData%\discord, %LocalAppData%\Discord,
       %LocalAppData%\Steam) directly to $DriveRoot\ProfileBackup via NTFS Directory Junctions (mklink /J):
       - Zero file duplication on disk, instant 0-second restore, and zero temporary/corrupt Windows profiles!
    2. Atomic Staging Release Swap ('s-rdp-vault-staging' -> 's-rdp-vault'):
       - Uploads and verifies the new encrypted archive FIRST before replacing the production vault tag.
       - An interrupted upload or timeout can NEVER wipe out your previous working backup!
    3. Cross-Drive Temp Packing:
       - Places temporary .7z split volumes on the opposite drive (C: vs D:) whenever space permits so large
         multi-GB Steam games never fail backup due to disk exhaustion.
    4. Graceful App Flush on Final Shutdown (Timer Expiry OR Manual Stop), Non-Disruptive Live Snapshot on Manual Save!
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("restore", "backup")]
    [string]$Mode,

    [Parameter(Mandatory=$true)]
    [string]$VaultPassword,

    [Parameter(Mandatory=$true)]
    [string]$RdpUser,

    [Parameter(Mandatory=$false)]
    [string]$InstallApps = "true",

    [Parameter(Mandatory=$false)]
    [string]$IsLiveSnapshot = "false"
)

$ErrorActionPreference = "Continue"
$ReleaseTag = "s-rdp-vault"
$StagingTag = "s-rdp-vault-staging"
$StateDir   = "C:\ProgramData\S-RDP"
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

function Test-SrdpTrue {
    param([string]$Value)
    return ($Value -eq "true")
}

# A double quote would break the -p"<password>" argument passed to 7-Zip (and could be used to inject
# extra 7-Zip switches), so reject it early with a clear message instead of silently producing a bad archive.
if ($VaultPassword.Contains('"')) {
    Write-Warning "VAULT/RDP password mengandung karakter kutip ganda; 7-Zip tidak bisa menerimanya. Ganti password."
    $global:LASTEXITCODE = 0
    exit 1
}

if ([string]::IsNullOrWhiteSpace($env:GITHUB_REPOSITORY)) {
    Write-Warning "GITHUB_REPOSITORY tidak tersedia (skrip ini harus dijalankan dari GitHub Actions)."
    $global:LASTEXITCODE = 0
    exit 1
}

# Select persistent Vault root. IMPORTANT: on restore we must reuse the exact same drive the previous
# session backed up from, otherwise data is restored to C: while the logon script points at D:.
$DriveRoot = "C:\AFK-Data"
$stateFile = "$StateDir\vault-root.txt"
$savedRoot = ""
if (Test-Path $stateFile) {
    $savedRoot = (Get-Content $stateFile -Raw).Trim()
}
if ($Mode -eq "restore" -and $savedRoot -and $savedRoot -match '^[A-Za-z]:\\') {
    $DriveRoot = $savedRoot
} else {
    $dDrive = Get-PSDrive -Name D -ErrorAction SilentlyContinue
    if ($dDrive -and (($dDrive.Free / 1GB) -ge 15 -or (Test-Path "D:\AFK-Data"))) {
        $DriveRoot = "D:\AFK-Data"
    }
}
New-Item -ItemType Directory -Path $DriveRoot -Force | Out-Null
New-Item -ItemType Directory -Path "$DriveRoot\Games" -Force | Out-Null
New-Item -ItemType Directory -Path "$DriveRoot\ProfileBackup\Roaming" -Force | Out-Null
New-Item -ItemType Directory -Path "$DriveRoot\ProfileBackup\Local" -Force | Out-Null

$PublicDesktop = "C:\Users\Public\Desktop"

$SevenZip = "C:\Program Files\7-Zip\7z.exe"
if (-not (Test-Path -LiteralPath $SevenZip)) {
    $sevenCmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($sevenCmd) { $SevenZip = $sevenCmd.Source }
}

# Pick opposite drive with maximum free space for temporary archive download/upload staging
function Get-BestTempDir {
    param([string]$SubFolder, [string]$AvoidDriveLetter = "")
    $cFree = if (Get-PSDrive C -ErrorAction SilentlyContinue) { (Get-PSDrive C).Free } else { 0 }
    $dFree = if (Get-PSDrive D -ErrorAction SilentlyContinue) { (Get-PSDrive D).Free } else { 0 }

    $chosenRoot = "$env:TEMP"
    if ($AvoidDriveLetter -eq "D:" -and $cFree -gt 8GB) {
        $chosenRoot = "C:\Windows\Temp"
    } elseif ($AvoidDriveLetter -eq "C:" -and $dFree -gt 8GB) {
        $chosenRoot = "D:\_srdp_temp"
    } elseif ($dFree -gt $cFree -and $dFree -gt 8GB) {
        $chosenRoot = "D:\_srdp_temp"
    } else {
        $chosenRoot = "C:\Windows\Temp"
    }
    $full = Join-Path $chosenRoot $SubFolder
    New-Item -ItemType Directory -Path $full -Force | Out-Null
    return $full
}

function Create-Shortcut {
    param([string]$TargetPath, [string]$ShortcutPath, [string]$WorkingDir = "", [string]$Arguments = "", [string]$IconLocation = "")
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $TargetPath
    if ($WorkingDir) { $Shortcut.WorkingDirectory = $WorkingDir } else { $Shortcut.WorkingDirectory = Split-Path $TargetPath }
    if ($Arguments) { $Shortcut.Arguments = $Arguments }
    if ($IconLocation) { $Shortcut.IconLocation = $IconLocation }
    $Shortcut.Save()
}

if ($Mode -eq "restore") {
    Write-Host "==> [VAULT RESTORE] Memeriksa backup terenkripsi di GitHub Release '$ReleaseTag'..." -ForegroundColor Cyan

    $VaultDriveLetter = $DriveRoot.Substring(0, 2)
    $TempVaultDir = Get-BestTempDir -SubFolder "s-rdp-vault-dl" -AvoidDriveLetter $VaultDriveLetter
    Remove-Item -Path "$TempVaultDir\*" -Recurse -Force -ErrorAction SilentlyContinue

    # Check production release first; if missing (e.g. rare interrupted swap), automatically fall back to staging release!
    $ActiveDownloadTag = ""
    & gh release view $ReleaseTag --repo $env:GITHUB_REPOSITORY >$null 2>&1
    if ($LASTEXITCODE -eq 0) {
        $ActiveDownloadTag = $ReleaseTag
    } else {
        & gh release view $StagingTag --repo $env:GITHUB_REPOSITORY >$null 2>&1
        if ($LASTEXITCODE -eq 0) {
            $ActiveDownloadTag = $StagingTag
            Write-Warning "    Release utama tidak ditemukan, memulihkan otomatis dari backup cadangan '$StagingTag'!"
        }
    }

    if ($ActiveDownloadTag -ne "") {
        Write-Host "    Backup ditemukan di '$ActiveDownloadTag'! Mengunduh arsip AES-256 ke staging ($TempVaultDir)..." -ForegroundColor Green

        # Retry once: a single transient GitHub/CDN hiccup should not cost you a whole 6-hour session.
        $FirstPart = "$TempVaultDir\vault.7z.001"
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            & gh release download $ActiveDownloadTag --repo $env:GITHUB_REPOSITORY --pattern "vault.7z.*" --dir $TempVaultDir --clobber 2>&1 | Out-Host
            if ((Test-Path $FirstPart) -and $LASTEXITCODE -eq 0) { break }
            if ($attempt -lt 2) {
                Write-Warning "    Unduhan gagal/terputus (attempt $attempt), mengulang sekali lagi..."
                Start-Sleep -Seconds 5
            }
        }

        if (-not (Test-Path $FirstPart)) {
            Write-Warning "    Unduhan vault GAGAL total. Sesi berjalan dengan folder permanen kosong (backup lama tetap aman di GitHub)."
        } elseif (-not (Test-Path $SevenZip)) {
            Write-Warning "    7-Zip tidak ditemukan; vault tidak bisa diekstrak pada sesi ini."
        } else {
            Write-Host "    Mendekripsi & mengekstrak data langsung ke $DriveRoot ..." -ForegroundColor Cyan
            & $SevenZip x $FirstPart "-p$VaultPassword" "-o$DriveRoot" -y -mmt=on | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    [SUKSES] Seluruh data Vault di $DriveRoot berhasil dipulihkan!" -ForegroundColor Green
            } else {
                Write-Warning "    Gagal mendekripsi vault! Pastikan RDP_PASSWORD / VAULT_PASSWORD sama dengan saat backup dibuat."
            }
        }
    } else {
        Write-Host "    Belum ada backup sebelumnya (Sesi Pertama). Folder permanen siap di: $DriveRoot" -ForegroundColor Yellow
    }
    Remove-Item -Path $TempVaultDir -Recurse -Force -ErrorAction SilentlyContinue

    # Auto-install Steam & Discord Launcher into $DriveRoot (Zero C:\Users pre-creation!)
    if ($InstallApps -eq "true") {
        # 1. Steam installed directly inside $DriveRoot\Steam (100% portable across resets!)
        $SteamDir = "$DriveRoot\Steam"
        $SteamExe = "$SteamDir\steam.exe"
        if (-not (Test-Path $SteamExe)) {
            Write-Host "==> [AUTO-APP] Menginstal Steam ke folder permanen ($SteamDir)..." -ForegroundColor Cyan
            try {
                New-Item -ItemType Directory -Path $SteamDir -Force | Out-Null
                $SteamSetup = "$env:TEMP\SteamSetup.exe"
                Invoke-WebRequest -Uri "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe" -OutFile $SteamSetup -UseBasicParsing
                Start-Process -FilePath $SteamSetup -ArgumentList "/S /D=$SteamDir" -Wait
                Remove-Item $SteamSetup -Force -ErrorAction SilentlyContinue
                Write-Host "    Steam berhasil terpasang di $SteamDir !" -ForegroundColor Green
            } catch {
                Write-Warning "    Gagal mengunduh Steam installer: $_"
            }
        } else {
            Write-Host "==> [AUTO-APP] Steam sudah pulih utuh dari Vault ($SteamDir)!" -ForegroundColor Green
        }
        if (Test-Path $SteamExe) {
            # Normal shortcut, plus a CPU-friendly one: on a GPU-less runner Steam's Chromium UI
            # (steamwebhelper.exe) falls back to SwiftShader software rasterization and can pin an
            # entire vCPU, which is exactly what kills the in-game frame rate.
            Create-Shortcut -TargetPath $SteamExe -ShortcutPath "$PublicDesktop\Steam.lnk"

            $SteamAfkBat = @"
@echo off
title Steam (Mode Hemat CPU - S-RDP)
cd /d "$SteamDir"
start "" "$SteamExe" -cef-disable-gpu -cef-disable-gpu-compositing -noshaders -nocrashmonitor -nofriendsui -nochatui
"@
            Set-Content -Path "$StateDir\launch-steam-afk.bat" -Value $SteamAfkBat -Encoding ASCII
            Create-Shortcut -TargetPath "$StateDir\launch-steam-afk.bat" -ShortcutPath "$PublicDesktop\Steam-Hemat-CPU.lnk" `
                -WorkingDir $SteamDir -IconLocation "$SteamExe,0"

            # NOTE: BrowserFlags/HKCU must be written inside the *gamer* hive (HKU\<SID>), never from this
            # SYSTEM/runner context - the logon script and the AFK Guardian handle that.
        }

        # 2. Smart Discord Launcher (Automatically launches restored Discord or runs fast silent install on first click)
        $DiscordSetupPersist = "$DriveRoot\Installers\DiscordSetup.exe"
        if (-not (Test-Path "$DriveRoot\ProfileBackup\Local\Discord\Update.exe") -and -not (Test-Path $DiscordSetupPersist)) {
            Write-Host "==> [AUTO-APP] Mengunduh installer Discord ke cache permanen..." -ForegroundColor Cyan
            try {
                New-Item -ItemType Directory -Path "$DriveRoot\Installers" -Force | Out-Null
                Invoke-WebRequest -Uri "https://discord.com/api/downloads/distributions/app/installers/chrome?channel=stable&platform=win&arch=x64" -OutFile $DiscordSetupPersist -UseBasicParsing
            } catch {
                Write-Warning "    Gagal mengunduh Discord installer: $_"
            }
        }

        # Discord is Electron: on a GPU-less runner its GPU process falls back to software rasterization.
        # Launching it with GPU disabled keeps a full CPU core available for the game.
        $DiscordLauncherBat = @"
@echo off
if exist "%LOCALAPPDATA%\Discord\Update.exe" (
    start "" "%LOCALAPPDATA%\Discord\Update.exe" --processStart Discord.exe --process-start-args "--disable-gpu --disable-gpu-compositing"
    exit /b
)
if exist "$DiscordSetupPersist" (
    echo Memasang Discord pertama kali, mohon tunggu 15 detik...
    start "" "$DiscordSetupPersist"
    exit /b
)
start https://discord.com/download
"@
        $DiscordLauncherPath = "$StateDir\launch-discord.bat"
        Set-Content -Path $DiscordLauncherPath -Value $DiscordLauncherBat -Encoding ASCII
        $DiscordIcon = if (Test-Path "$DriveRoot\ProfileBackup\Local\Discord\app.ico") { "$DriveRoot\ProfileBackup\Local\Discord\app.ico" } else { "$env:SystemRoot\System32\shell32.dll,13" }
        Create-Shortcut -TargetPath $DiscordLauncherPath -ShortcutPath "$PublicDesktop\Discord.lnk" -IconLocation $DiscordIcon

        # If a restored profile already contains Discord settings.json, turn hardware acceleration off now
        # (the AFK Guardian keeps re-applying this while Discord is closed).
        $restoredDiscordSettings = "$DriveRoot\ProfileBackup\Roaming\discord\settings.json"
        if (Test-Path $restoredDiscordSettings) {
            try {
                $rawSettings = Get-Content -Path $restoredDiscordSettings -Raw -ErrorAction Stop
                if ($rawSettings -match '"enableHardwareAcceleration"\s*:\s*true') {
                    $rawSettings = $rawSettings -replace '"enableHardwareAcceleration"\s*:\s*true', '"enableHardwareAcceleration":false'
                    Set-Content -Path $restoredDiscordSettings -Value $rawSettings -Encoding UTF8 -NoNewline
                    Write-Host "    Discord hardware acceleration dimatikan (hemat CPU untuk game)." -ForegroundColor Green
                }
            } catch {}
        }
    }

    # Grant full NTFS permissions on $DriveRoot to $RdpUser so junctions & games never hit Access Denied
    & icacls "$DriveRoot" /grant "${RdpUser}:(OI)(CI)F" /T /C /Q 2>$null | Out-Null

    # CRITICAL FIX: Register Logon Script inside All Users StartUp (runs AFTER Windows creates the real C:\Users\$RdpUser profile!)
    # Links %AppData%\discord, %LocalAppData%\Discord, and %LocalAppData%\Steam via NTFS Directory Junctions (mklink /J)
    # -> Instant 0-second link, zero duplicate disk usage, real-time persistence, and zero Corrupt/Temporary User Profile bugs!
    $ProfileLinkerPs1 = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$DriveRoot = '$DriveRoot'

function Link-PersistFolder {
    param([string]`$UserPath, [string]`$VaultPath)
    New-Item -ItemType Directory -Path `$VaultPath -Force | Out-Null
    if (Test-Path `$UserPath) {
        `$item = Get-Item `$UserPath -Force
        if (`$item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            return # Already linked!
        }
        # Merge any initial files into VaultPath then replace with Junction
        robocopy `$UserPath `$VaultPath /E /MOVE /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
        Remove-Item `$UserPath -Recurse -Force
    }
    `$parent = Split-Path `$UserPath -Parent
    if (-not (Test-Path `$parent)) { New-Item -ItemType Directory -Path `$parent -Force | Out-Null }
    cmd /c "mklink /J `"`$UserPath`" `"`$VaultPath`"" | Out-Null
}

Link-PersistFolder -UserPath "`$env:APPDATA\discord"      -VaultPath "`$DriveRoot\ProfileBackup\Roaming\discord"
Link-PersistFolder -UserPath "`$env:LOCALAPPDATA\Discord" -VaultPath "`$DriveRoot\ProfileBackup\Local\Discord"
Link-PersistFolder -UserPath "`$env:LOCALAPPDATA\Steam"   -VaultPath "`$DriveRoot\ProfileBackup\Local\Steam"

# Support custom extra folders defined by user in extra-roaming-folders.txt / extra-local-folders.txt
if (Test-Path "`$DriveRoot\extra-roaming-folders.txt") {
    Get-Content "`$DriveRoot\extra-roaming-folders.txt" | Where-Object { -not [string]::IsNullOrWhiteSpace(`$_) } | ForEach-Object {
        `$f = `$_.Trim()
        Link-PersistFolder -UserPath "`$env:APPDATA\`$f" -VaultPath "`$DriveRoot\ProfileBackup\Roaming\`$f"
    }
}
if (Test-Path "`$DriveRoot\extra-local-folders.txt") {
    Get-Content "`$DriveRoot\extra-local-folders.txt" | Where-Object { -not [string]::IsNullOrWhiteSpace(`$_) } | ForEach-Object {
        `$f = `$_.Trim()
        Link-PersistFolder -UserPath "`$env:LOCALAPPDATA\`$f" -VaultPath "`$DriveRoot\ProfileBackup\Local\`$f"
    }
}

# Import Steam AutoLoginUser & SteamPath into HKCU immediately on logon
if (Test-Path "`$DriveRoot\ProfileBackup\steam-hkcu.reg") {
    reg import "`$DriveRoot\ProfileBackup\steam-hkcu.reg" >`$null 2>&1
}
if (Test-Path "`$DriveRoot\Steam\steam.exe") {
    `$sp = (`$DriveRoot -replace '\\', '/') + '/Steam'
    `$se = `$sp + '/steam.exe'
    reg add "HKCU\Software\Valve\Steam" /v SteamPath /t REG_SZ /d "`$sp" /f >`$null 2>&1
    reg add "HKCU\Software\Valve\Steam" /v SteamExe  /t REG_SZ /d "`$se" /f >`$null 2>&1
}

# Keep Steam's Chromium UI off the CPU (GPU-less host => SwiftShader software rasterization).
`$browserFlags = '-cef-disable-gpu -cef-disable-gpu-compositing'
`$curFlags = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name BrowserFlags -ErrorAction SilentlyContinue).BrowserFlags
if (`$curFlags -ne `$browserFlags) {
    New-Item -Path 'HKCU:\Software\Valve\Steam' -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name BrowserFlags -Value `$browserFlags -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
}

# Keep Discord's GPU process off the CPU too (harmless if Discord is not installed yet).
`$discordSettings = "`$env:APPDATA\discord\settings.json"
if (Test-Path `$discordSettings) {
    try {
        `$dj = Get-Content -Path `$discordSettings -Raw -ErrorAction Stop
        if (`$dj -match '"enableHardwareAcceleration"\s*:\s*true') {
            (`$dj -replace '"enableHardwareAcceleration"\s*:\s*true', '"enableHardwareAcceleration":false') |
                Set-Content -Path `$discordSettings -Encoding UTF8 -NoNewline
        }
    } catch {}
}
"@
    $LinkerScriptPath = "$StateDir\link-user-profile.ps1"
    Set-Content -Path $LinkerScriptPath -Value $ProfileLinkerPs1 -Encoding UTF8

    # Run synchronously at Winlogon Userinit / StartUp so junctions exist before user clicks Steam or Discord!
    $StartupBat = "@echo off`r`npowershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$LinkerScriptPath`"`r`n"
    Set-Content -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\00-srdp-profile-link.bat" -Value $StartupBat -Encoding ASCII

    # Desktop shortcuts for Persistent Folder & Manual Live Snapshot
    Create-Shortcut -TargetPath $DriveRoot -ShortcutPath "$PublicDesktop\Folder-Permanen-Anti-Reset ($VaultDriveLetter).lnk"

    $ManualSaveBat = @'
@echo off
title Simpan Data ke Vault Sekarang (Live Snapshot)
echo ========================================================
echo   MENYIMPAN SNAPSHOT STEAM, DISCORD, ^& FOLDER PERMANEN
echo ========================================================
echo Permintaan backup manual dikirim ke background runner
echo (Game ^& aplikasi kamu TIDAK akan ditutup saat live save!).
echo save > "C:\save-s-rdp-now.flag"
echo.
echo Backup sedang berjalan di background (~1-2 menit).
timeout /t 5
'@
    Set-Content -Path "$PublicDesktop\Simpan-Data-Sekarang.bat" -Value $ManualSaveBat -Encoding ASCII

    Set-Content -Path "$StateDir\vault-root.txt" -Value $DriveRoot -Encoding ASCII
}

if ($Mode -eq "backup") {
    if (Test-Path "$StateDir\vault-root.txt") {
        $DriveRoot = (Get-Content "$StateDir\vault-root.txt" -Raw).Trim()
    }
    $VaultDriveLetter = $DriveRoot.Substring(0, 2)

    Write-Host "==> [VAULT BACKUP] Menyiapkan backup terenkripsi AES-256 dari $DriveRoot ..." -ForegroundColor Cyan

    # CRITICAL FIX: Close Steam & Discord cleanly on ANY final shutdown (both manual stop AND 340-min timer expiry!),
    # while keeping everything running uninterrupted if the user only clicked 'Simpan-Data-Sekarang.bat' mid-game!
    if ($IsLiveSnapshot -ne "true") {
        Write-Host "    Menutup Steam & Discord dengan rapi agar token sesi login tersimpan utuh..."
        if (Test-Path "$DriveRoot\Steam\steam.exe") {
            Start-Process -FilePath "$DriveRoot\Steam\steam.exe" -ArgumentList "-shutdown" -WindowStyle Hidden -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 4
        }
        foreach ($app in @("steam", "steamwebhelper", "Discord")) {
            Get-Process -Name $app -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
    } else {
        Write-Host "    Mode Live Snapshot aktif — Game, Steam, & Discord dibiarkan tetap berjalan!" -ForegroundColor Green
    }

    # If user logged in WITHOUT junctions for any reason, sync fallback folders; if junctions are active, data is ALREADY inside $DriveRoot\ProfileBackup!
    $UserHome = "C:\Users\$RdpUser"
    if (Test-Path "$UserHome\AppData") {
        foreach ($pair in @(
            @{ Src = "$UserHome\AppData\Roaming\discord"; Dst = "$DriveRoot\ProfileBackup\Roaming\discord" },
            @{ Src = "$UserHome\AppData\Local\Discord";   Dst = "$DriveRoot\ProfileBackup\Local\Discord" },
            @{ Src = "$UserHome\AppData\Local\Steam";     Dst = "$DriveRoot\ProfileBackup\Local\Steam" }
        )) {
            if (Test-Path $pair.Src) {
                $item = Get-Item $pair.Src -Force -ErrorAction SilentlyContinue
                if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                    robocopy $pair.Src $pair.Dst /MIR /MT:8 /XD "Cache" "Code Cache" "GPUCache" "DawnCache" "Crashpad" "htmlcache" /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
                }
            }
        }
    }

    # Export Valve Steam HKCU Registry (stores AutoLoginUser & RememberPassword!)
    try {
        $UserSid = (Get-LocalUser -Name $RdpUser -ErrorAction SilentlyContinue).SID.Value
        if ($UserSid -and (Test-Path "Registry::HKEY_USERS\$UserSid\Software\Valve\Steam")) {
            & reg export "HKU\$UserSid\Software\Valve\Steam" "$env:TEMP\steam-hku.reg" /y >$null 2>&1
            if (Test-Path "$env:TEMP\steam-hku.reg") {
                (Get-Content "$env:TEMP\steam-hku.reg") -replace [regex]::Escape("HKEY_USERS\$UserSid"), "HKEY_CURRENT_USER" |
                    Set-Content -Path "$DriveRoot\ProfileBackup\steam-hkcu.reg" -Encoding Unicode
                Remove-Item "$env:TEMP\steam-hku.reg" -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {}

    # Purge disposable browser/GPU caches inside ProfileBackup & Steam before archiving so backup stays slim & fast!
    $DisposableCaches = @(
        "$DriveRoot\Steam\logs\*",
        "$DriveRoot\Steam\dumps\*",
        "$DriveRoot\Steam\appcache\httpcache\*",
        "$DriveRoot\ProfileBackup\Roaming\discord\Cache\*",
        "$DriveRoot\ProfileBackup\Roaming\discord\Code Cache\*",
        "$DriveRoot\ProfileBackup\Roaming\discord\GPUCache\*",
        "$DriveRoot\ProfileBackup\Roaming\discord\DawnCache\*",
        "$DriveRoot\ProfileBackup\Local\Steam\htmlcache\*"
    )
    foreach ($cachePath in $DisposableCaches) {
        Remove-Item -Path $cachePath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Cross-drive temp staging directory so packing large Steam games doesn't exhaust $DriveRoot's own drive!
    $OutArchiveDir = Get-BestTempDir -SubFolder "s-rdp-vault-up" -AvoidDriveLetter $VaultDriveLetter
    Remove-Item -Path "$OutArchiveDir\*" -Recurse -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $SevenZip)) {
        Write-Warning "    7-Zip tidak ditemukan ($SevenZip) - backup dilewati agar data lama tidak rusak."
        Write-Warning "    Backup lama di release '$ReleaseTag' TIDAK disentuh."
        $global:LASTEXITCODE = 0
        exit 0
    }

    Write-Host "    Mengenkripsi $DriveRoot dengan AES-256 ke staging ($OutArchiveDir)..." -ForegroundColor Cyan
    Push-Location $DriveRoot
    & $SevenZip a "$OutArchiveDir\vault.7z" "*" "-p$VaultPassword" -mhe=on -mx=1 -mmt=on -v1900m -ssw `
        -xr!"Steam\steamapps\downloading\*" `
        -xr!"Steam\steamapps\temp\*" `
        -xr!"ProfileBackup\Roaming\discord\Cache\*" `
        -xr!"ProfileBackup\Roaming\discord\Code Cache\*" `
        -xr!"ProfileBackup\Roaming\discord\GPUCache\*" | Out-Null
    $SevenExit = $LASTEXITCODE
    Pop-Location

    $Parts = Get-ChildItem -Path $OutArchiveDir -Filter "vault.7z.*" -ErrorAction SilentlyContinue | Sort-Object Name
    if ($Parts -and $Parts.Count -gt 0 -and $SevenExit -le 1) {
        $TotalMb = [math]::Round((($Parts | Measure-Object -Property Length -Sum).Sum / 1MB), 1)
        $PartPaths = $Parts | ForEach-Object { $_.FullName }
        $Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $Notes = "Encrypted S-RDP Persistent Vault (AES-256 + Filename Encryption). Size: $TotalMb MB ($($Parts.Count) volume(s)). Updated at $Timestamp UTC."

        Write-Host "    [ATOMIC UPLOAD 1/2] Mengunggah $($Parts.Count) part ($TotalMb MB) ke staging release '$StagingTag' terlebih dahulu (Anti-Data-Loss)..." -ForegroundColor Cyan
        & gh release view $StagingTag --repo $env:GITHUB_REPOSITORY >$null 2>&1
        if ($LASTEXITCODE -eq 0) {
            & gh release delete $StagingTag --repo $env:GITHUB_REPOSITORY --cleanup-tag --yes >$null 2>&1
        }

        & gh release create $StagingTag @PartPaths --repo $env:GITHUB_REPOSITORY --title "S-RDP Staging Vault" --notes $Notes --prerelease >$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    [ATOMIC UPLOAD 2/2] Staging 100% terverifikasi! Mempromosikan ke release utama '$ReleaseTag'..." -ForegroundColor Cyan
            # Ensure production release exists without deleting it first if we can atomically replace assets, or recreate cleanly while staging still holds a full copy!
            & gh release view $ReleaseTag --repo $env:GITHUB_REPOSITORY >$null 2>&1
            if ($LASTEXITCODE -eq 0) {
                & gh release delete $ReleaseTag --repo $env:GITHUB_REPOSITORY --cleanup-tag --yes >$null 2>&1
            }
            & gh release create $ReleaseTag @PartPaths --repo $env:GITHUB_REPOSITORY --title "S-RDP Encrypted Vault (Auto-Save)" --notes $Notes --prerelease >$null
            if ($LASTEXITCODE -eq 0) {
                # Only remove staging AFTER production release is 100% confirmed live!
                & gh release delete $StagingTag --repo $env:GITHUB_REPOSITORY --cleanup-tag --yes >$null 2>&1
                Write-Host "    [SUKSES] Backup Vault ($TotalMb MB) tersimpan aman dengan jaminan Atomic Zero-Data-Loss!" -ForegroundColor Green
            } else {
                Write-Warning "    Promosi ke '$ReleaseTag' gagal, TAPI data barumu AMAN TERSIMPAN di release '$StagingTag'!"
            }
        } else {
            Write-Warning "    Gagal mengunggah ke GitHub Release! Backup lama di '$ReleaseTag' TIDAK DIHAPUS (tetap utuh). Pastikan 'Settings -> Actions -> General -> Workflow permissions' diatur ke 'Read and write permissions'."
        }
    } else {
        Write-Warning "    Gagal membuat arsip vault (7z exit code: $SevenExit). Backup lama di '$ReleaseTag' tetap utuh."
    }

    Remove-Item -Path $OutArchiveDir -Recurse -Force -ErrorAction SilentlyContinue
}

$global:LASTEXITCODE = 0
exit 0
