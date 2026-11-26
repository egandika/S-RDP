<#
.SYNOPSIS
    AES-256 Encrypted Persistent Vault for S-RDP (Zero External Cloud Needed).
.DESCRIPTION
    Restores or backs up Steam (including games & login sessions), Discord, saved AppData,
    and the entire D:\AFK-Data (or C:\AFK-Data) persistent workspace to a GitHub Release ('s-rdp-vault')
    encrypted with 7-Zip AES-256 + Header Encryption (-mhe=on) split into <1.9GB volumes so even
    multi-GB games persist across 6-hour GitHub Actions resets safely!
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
    [string]$InstallApps = "true"
)

$ErrorActionPreference = "Continue"
$ReleaseTag = "s-rdp-vault"

# Determine persistent drive root: prefer D:\AFK-Data if D: exists and has >15 GB free, otherwise C:\AFK-Data
$DriveRoot = "C:\AFK-Data"
$dDrive = Get-PSDrive -Name D -ErrorAction SilentlyContinue
if ($dDrive -and (($dDrive.Free / 1GB) -gt 15 -or (Test-Path "D:\AFK-Data"))) {
    $DriveRoot = "D:\AFK-Data"
}
New-Item -ItemType Directory -Path $DriveRoot -Force | Out-Null
New-Item -ItemType Directory -Path "$DriveRoot\Games" -Force | Out-Null
New-Item -ItemType Directory -Path "$DriveRoot\ProfileBackup" -Force | Out-Null

$UserHome = "C:\Users\$RdpUser"
$AppDataRoaming = "$UserHome\AppData\Roaming"
$AppDataLocal = "$UserHome\AppData\Local"
$PublicDesktop = "C:\Users\Public\Desktop"

# Locate 7z.exe (pre-installed on all GitHub Windows runners)
$SevenZip = "C:\Program Files\7-Zip\7z.exe"
if (-not (Test-Path $SevenZip)) {
    $SevenZip = (Get-Command 7z.exe -ErrorAction SilentlyContinue).Source
}

function Create-Shortcut {
    param([string]$TargetPath, [string]$ShortcutPath, [string]$WorkingDir = "", [string]$Arguments = "")
    if (-not (Test-Path $TargetPath)) { return }
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $TargetPath
    if ($WorkingDir) { $Shortcut.WorkingDirectory = $WorkingDir } else { $Shortcut.WorkingDirectory = Split-Path $TargetPath }
    if ($Arguments) { $Shortcut.Arguments = $Arguments }
    $Shortcut.Save()
}

if ($Mode -eq "restore") {
    Write-Host "==> [VAULT RESTORE] Checking for encrypted backup in GitHub Release '$ReleaseTag'..." -ForegroundColor Cyan

    $TempVaultDir = "$env:TEMP\s-rdp-vault-dl"
    Remove-Item -Path $TempVaultDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $TempVaultDir -Force | Out-Null

    $ReleaseExists = $false
    & gh release view $ReleaseTag --repo $env:GITHUB_REPOSITORY >$null 2>&1
    if ($LASTEXITCODE -eq 0) {
        $ReleaseExists = $true
    }

    if ($ReleaseExists) {
        Write-Host "    Backup ditemukan! Mengunduh arsip terenkripsi AES-256 dengan kecepatan tinggi..." -ForegroundColor Green
        & gh release download $ReleaseTag --repo $env:GITHUB_REPOSITORY --pattern "vault.7z.*" --dir $TempVaultDir --clobber
        $FirstPart = "$TempVaultDir\vault.7z.001"

        if (Test-Path $FirstPart) {
            Write-Host "    Mendekripsi & mengekstrak data ke $DriveRoot ..." -ForegroundColor Cyan
            # Extract contents directly into $DriveRoot
            & $SevenZip x $FirstPart "-p$VaultPassword" "-o$DriveRoot" -y -mmt=on | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    [SUKSES] Data aplikasi & game di $DriveRoot berhasil dipulihkan!" -ForegroundColor Green

                # Ensure user profile folders exist before restoring AppData
                New-Item -ItemType Directory -Path $AppDataRoaming -Force | Out-Null
                New-Item -ItemType Directory -Path $AppDataLocal -Force | Out-Null

                # Restore saved AppData (Discord, Steam Local config, Game saves)
                if (Test-Path "$DriveRoot\ProfileBackup\Roaming") {
                    Write-Host "    Memulihkan sesi AppData\Roaming (Discord & konfigurasi game)..."
                    robocopy "$DriveRoot\ProfileBackup\Roaming" "$AppDataRoaming" /E /MT:8 /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
                }
                if (Test-Path "$DriveRoot\ProfileBackup\Local") {
                    Write-Host "    Memulihkan sesi AppData\Local (Discord App & Steam WebHelper/Tokens)..."
                    robocopy "$DriveRoot\ProfileBackup\Local" "$AppDataLocal" /E /MT:8 /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
                }

                # Restore Steam Registry entries under a Login Script for RdpUser so HKCU gets AutoLoginUser & SteamPath immediately on logon!
                $StartupDir = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
                $SteamRestoreCmd = "@echo off`r`n"
                if (Test-Path "$DriveRoot\ProfileBackup\steam-hkcu.reg") {
                    $SteamRestoreCmd += "reg import `"$DriveRoot\ProfileBackup\steam-hkcu.reg`" >nul 2>&1`r`n"
                }
                if (Test-Path "$DriveRoot\Steam\steam.exe") {
                    $sp = $DriveRoot.Replace('\','/') + "/Steam"
                    $se = $DriveRoot.Replace('\','/') + "/Steam/steam.exe"
                    $SteamRestoreCmd += "reg add `"HKCU\Software\Valve\Steam`" /v SteamPath /t REG_SZ /d `"$sp`" /f >nul 2>&1`r`n"
                    $SteamRestoreCmd += "reg add `"HKCU\Software\Valve\Steam`" /v SteamExe /t REG_SZ /d `"$se`" /f >nul 2>&1`r`n"
                }
                Set-Content -Path "$StartupDir\restore-steam-session.bat" -Value $SteamRestoreCmd -Encoding ASCII
            } else {
                Write-Warning "    Gagal mendekripsi vault! Pastikan RDP_PASSWORD / VAULT_PASSWORD sama dengan saat backup dibuat."
            }
        }
        Remove-Item -Path $TempVaultDir -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "    Belum ada backup sebelumnya (Sesi Pertama). Folder permanen disiapkan di: $DriveRoot" -ForegroundColor Yellow
    }

    # Auto-install Steam & Discord on first run (or if missing) into persistent/portable paths!
    if ($InstallApps -eq "true") {
        # 1. Steam (Installed directly inside $DriveRoot\Steam so ALL Steam login tokens & games stay persistent!)
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
            Write-Host "==> [AUTO-APP] Steam sudah tersedia dari Backup Vault ($SteamDir) — Tidak perlu download ulang!" -ForegroundColor Green
        }
        if (Test-Path $SteamExe) {
            Create-Shortcut -TargetPath $SteamExe -ShortcutPath "$PublicDesktop\Steam.lnk"
        }

        # 2. Discord Installer / Restored App
        $DiscordUpdateExe = "$AppDataLocal\Discord\Update.exe"
        $DiscordSetupPersist = "$DriveRoot\Installers\DiscordSetup.exe"
        if (-not (Test-Path $DiscordUpdateExe)) {
            Write-Host "==> [AUTO-APP] Menyiapkan Discord Installer cepat..." -ForegroundColor Cyan
            try {
                New-Item -ItemType Directory -Path "$DriveRoot\Installers" -Force | Out-Null
                if (-not (Test-Path $DiscordSetupPersist)) {
                    Invoke-WebRequest -Uri "https://discord.com/api/downloads/distributions/app/installers/chrome?channel=stable&platform=win&arch=x64" -OutFile $DiscordSetupPersist -UseBasicParsing
                }
                Create-Shortcut -TargetPath $DiscordSetupPersist -ShortcutPath "$PublicDesktop\Discord (Klik Sekali Untuk Buka).lnk"
                Write-Host "    Discord siap di Desktop!" -ForegroundColor Green
            } catch {
                Write-Warning "    Gagal mengunduh Discord installer: $_"
            }
        } else {
            Create-Shortcut -TargetPath $DiscordUpdateExe -Arguments "--processStart Discord.exe" -ShortcutPath "$PublicDesktop\Discord.lnk"
            Write-Host "==> [AUTO-APP] Discord sudah pulih dari Backup Vault!" -ForegroundColor Green
        }
    }

    # Fix file ownership/permissions for RdpUser so restored AppData & Steam folders are 100% writable
    & icacls "$DriveRoot" /grant "${RdpUser}:(OI)(CI)F" /T /C /Q 2>$null | Out-Null
    if (Test-Path $UserHome) {
        & icacls "$UserHome\AppData" /grant "${RdpUser}:(OI)(CI)F" /T /C /Q 2>$null | Out-Null
    }

    # Create Desktop Shortcut to Persistent Folder & Manual Save Trigger
    Create-Shortcut -TargetPath $DriveRoot -ShortcutPath "$PublicDesktop\Folder-Permanen-Anti-Reset ($($DriveRoot.Substring(0,2))).lnk"

    $ManualSaveBat = @'
@echo off
title Simpan Data ke Vault Sekarang
echo ========================================================
echo   MENYIMPAN DATA STEAM, DISCORD, & FOLDER PERMANEN
echo ========================================================
echo Permintaan backup manual dikirim ke background runner...
echo save > "C:\save-s-rdp-now.flag"
echo Tunggu sekitar 1-2 menit, cek statusnya di log GitHub Actions!
timeout /t 5
'@
    Set-Content -Path "$PublicDesktop\Simpan-Data-Sekarang.bat" -Value $ManualSaveBat -Encoding ASCII

    # Record active DriveRoot path for backup phase
    Set-Content -Path "C:\Windows\Temp\s-rdp-vault-root.txt" -Value $DriveRoot -Encoding ASCII
}

if ($Mode -eq "backup") {
    if (Test-Path "C:\Windows\Temp\s-rdp-vault-root.txt") {
        $DriveRoot = (Get-Content "C:\Windows\Temp\s-rdp-vault-root.txt" -Raw).Trim()
    }
    Write-Host "==> [VAULT BACKUP] Menyimpan & mengenkripsi data sesi sebelum RDP mati..." -ForegroundColor Cyan

    # Gracefully close Steam & Discord briefly if shutting down so SQLite/VDF login token files flush cleanly without lock/corruption
    if (Test-Path "C:\stop-s-rdp.flag") {
        foreach ($app in @("steam", "steamwebhelper", "Discord")) {
            Get-Process -Name $app -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
    }

    # Copy essential user AppData directories into $DriveRoot\ProfileBackup
    New-Item -ItemType Directory -Path "$DriveRoot\ProfileBackup\Roaming" -Force | Out-Null
    New-Item -ItemType Directory -Path "$DriveRoot\ProfileBackup\Local" -Force | Out-Null

    # Roaming folders to persist (Discord session, Macro configs, Game saves in Roaming)
    $RoamingTargets = @("discord")
    if (Test-Path "$DriveRoot\extra-roaming-folders.txt") {
        $RoamingTargets += (Get-Content "$DriveRoot\extra-roaming-folders.txt" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    foreach ($folder in $RoamingTargets) {
        if (Test-Path "$AppDataRoaming\$folder") {
            Write-Host "    Menyalin AppData\Roaming\$folder ..."
            # Exclude bulky temporary GPUCache/Code Cache so backup finishes in seconds!
            robocopy "$AppDataRoaming\$folder" "$DriveRoot\ProfileBackup\Roaming\$folder" /MIR /MT:8 /XD "Cache" "Code Cache" "GPUCache" "DawnCache" "Crashpad" /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
        }
    }

    # Local folders to persist (Steam local VDF login token & Discord installation)
    $LocalTargets = @("Steam", "Discord")
    if (Test-Path "$DriveRoot\extra-local-folders.txt") {
        $LocalTargets += (Get-Content "$DriveRoot\extra-local-folders.txt" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    foreach ($folder in $LocalTargets) {
        if (Test-Path "$AppDataLocal\$folder") {
            Write-Host "    Menyalin AppData\Local\$folder ..."
            robocopy "$AppDataLocal\$folder" "$DriveRoot\ProfileBackup\Local\$folder" /MIR /MT:8 /XD "htmlcache" "Cache" "Code Cache" "GPUCache" /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
        }
    }

    # Export Valve Steam HKCU Registry (stores AutoLoginUser & RememberPassword flag!)
    try {
        $UserSid = (Get-LocalUser -Name $RdpUser -ErrorAction SilentlyContinue).SID.Value
        if ($UserSid -and (Test-Path "Registry::HKEY_USERS\$UserSid\Software\Valve\Steam")) {
            $regContent = reg export "HKU\$UserSid\Software\Valve\Steam" "$env:TEMP\steam-hku.reg" /y 2>$null
            if (Test-Path "$env:TEMP\steam-hku.reg") {
                (Get-Content "$env:TEMP\steam-hku.reg") -replace [regex]::Escape("HKEY_USERS\$UserSid"), "HKEY_CURRENT_USER" |
                    Set-Content -Path "$DriveRoot\ProfileBackup\steam-hkcu.reg" -Encoding Unicode
                Remove-Item "$env:TEMP\steam-hku.reg" -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {}

    # Clean Steam download cache/logs before archiving to save space & speed
    Remove-Item -Path "$DriveRoot\Steam\logs\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$DriveRoot\Steam\appcache\httpcache\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$DriveRoot\Steam\dumps\*" -Recurse -Force -ErrorAction SilentlyContinue

    # Create encrypted multi-volume 7z archive (<1900MB per volume, fast compression -mx=1 so multi-GB games pack in seconds, AES-256 + encrypted filenames -mhe=on)
    $OutArchiveDir = "$env:TEMP\s-rdp-vault-up"
    Remove-Item -Path $OutArchiveDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $OutArchiveDir -Force | Out-Null

    Write-Host "    Mengenkripsi $DriveRoot dengan AES-256 (7-Zip Split Volumes 1900MB)..." -ForegroundColor Cyan
    Push-Location $DriveRoot
    & $SevenZip a "$OutArchiveDir\vault.7z" "*" "-p$VaultPassword" -mhe=on -mx=1 -mmt=on -v1900m -ssw -xr!"Steam\steamapps\downloading\*" -xr!"Steam\steamapps\temp\*" | Out-Null
    $SevenExit = $LASTEXITCODE
    Pop-Location

    $Parts = Get-ChildItem -Path $OutArchiveDir -Filter "vault.7z.*" -ErrorAction SilentlyContinue
    if ($Parts -and $Parts.Count -gt 0) {
        $TotalMb = [math]::Round((($Parts | Measure-Object -Property Length -Sum).Sum / 1MB), 1)
        Write-Host "    Arsip terenkripsi siap ($($Parts.Count) part, Total: $TotalMb MB). Mengunggah ke GitHub Release '$ReleaseTag'..." -ForegroundColor Cyan

        # Ensure release exists; delete old vault parts first so stale higher-numbered chunks don't linger
        & gh release view $ReleaseTag --repo $env:GITHUB_REPOSITORY >$null 2>&1
        if ($LASTEXITCODE -eq 0) {
            & gh release delete $ReleaseTag --repo $env:GITHUB_REPOSITORY --cleanup-tag --yes >$null 2>&1
        }

        $Notes = "🔒 Encrypted S-RDP Persistent Vault (AES-256 + Header Encrypted). Updated automatically at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC. Cannot be opened without secret password."
        $PartPaths = $Parts | ForEach-Object { $_.FullName }
        & gh release create $ReleaseTag @PartPaths --repo $env:GITHUB_REPOSITORY --title "S-RDP Encrypted Vault (Auto-Save)" --notes $Notes --prerelease
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    [SUKSES] Backup Vault berhasil disimpan ke GitHub Release '$ReleaseTag'!" -ForegroundColor Green
        } else {
            Write-Warning "    Gagal mengunggah ke GitHub Release! Pastikan 'Settings -> Actions -> General -> Workflow permissions' diatur ke 'Read and write permissions'."
        }
    } else {
        Write-Warning "    Tidak ada file vault yang dihasilkan (7z exit code: $SevenExit)."
    }

    Remove-Item -Path $OutArchiveDir -Recurse -Force -ErrorAction SilentlyContinue
}
