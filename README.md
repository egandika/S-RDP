# 🎮 S-RDP — Windows AFK Gaming RDP (GitHub Actions + Tailscale)

Workflow GitHub Actions siap pakai untuk membuat **Windows Server Remote Desktop (RDP)** dengan jaringan privat **Tailscale**, yang sudah dioptimasi khusus untuk **AFK game berat, macro, dan auto-clicker** tanpa *freeze* saat koneksi RDP ditutup.

---

## ✨ Fitur Utama (Khusus AFK Game — Zero-Cost Max Tuned)

- **💾 Anti-Reset 6 Jam (Atomic AES-256 Vault + Instant NTFS Junctions)**: Otomatis menginstal **Steam & Discord**, menghubungkan folder profil via **NTFS Directory Junction (`mklink /J`)** (0 detik waktu salin, bebas duplikasi ruang disk, & bebas bug *Corrupt User Profile*), serta menyimpan seluruh isi **`D:\AFK-Data`** ke GitHub Release (`s-rdp-vault`) dengan **Atomic Staging Swap** (`s-rdp-vault-staging` → `s-rdp-vault`) berenkripsi **7-Zip AES-256 + Filename Encryption (`-mhe=on`)** sehingga backup lama mustahil terhapus jika koneksi terputus!
- **🎯 Locked Console Resolution (`1280x720 @ 100% DPI`)**: Menyeragamkan resolusi & skala DPI layar Console dengan RDP agar titik koordinat *Auto-Clicker / Macro* tidak bergeser saat pindah ke mode AFK (`tscon`).
- **♾️ Opsi Auto-Restart Estafet 24/7 (`auto_restart_chain`)**: Selesai backup di akhir jam ke-6, workflow bisa otomatis menyalakan sesi RDP baru untuk menyambung sesi sebelumnya.
- **🔥 Kill 70% Background CPU Hogs (Idle CPU ~1–3%)**: Mematikan paksa penyedot CPU bawaan runner GitHub (*Windows Defender Real-Time Scan `MsMpEng.exe`*, *`.NET Runtime Optimization mscorsvw.exe`*, *`TiWorker`*, *`CompatTelRunner`*, dan *Scheduled Maintenance*) sehingga 100% tenaga 4 vCPU AMD EPYC (3.24+ GHz Boost) murni dipakai oleh game.
- **🚀 CPU Core Unparking + Auto Game Priority Booster**: Membuka seluruh *CPU Core Parking* (`CPMINCORES=100%`), mengunci *Boost Mode* di 100%, serta otomatis menaikkan prioritas proses `.exe` game aktif ke `AboveNormal` setiap 5 menit.
- **🖥️ RDP Frame Pacing Adaptif + TermDD FlowControl Dilepas**: `DWMFRAMEINTERVAL` dihitung otomatis dari opsi **`rdp_fps`** (default **30 FPS** — angka paling seimbang untuk render CPU; `60` hanya berguna kalau runner punya GPU), plus `FlowControlDisable=1`, `VGOptimization_CaptureFrameRate`, dan `MaxCompressionLevel` supaya layar RDP tidak lagi terasa seperti *slideshow*. Mode **AVC444/H.264 hardware encode hanya dinyalakan bila benar-benar ada GPU** (lihat [kenapa 5 FPS](#-kenapa-game-cuma-5-fps-akar-masalah--solusinya)).
- **🧩 Mesa3D llvmpipe System-Wide (OpenGL 4.5)**: Mengganti driver OpenGL software bawaan Windows (**OpenGL 1.1**, penyebab game/emulator menolak jalan atau render super lambat) dengan **Mesa3D llvmpipe OpenGL 4.5** yang dipasang *system-wide* (`System32` + `SysWOW64`, driver asli dibackup `.srdp-bak`) **dan** per-game lewat tombol **`Optimalkan-Game-Ini.bat`**.
- **🔧 Tuning Renderer untuk Runner Tanpa GPU**: `LP_NUM_THREADS` disetel ke `vCPU - 1` (llvmpipe default memakai **semua** core sehingga DWM + encoder RDP + logika game berebut CPU → inilah penyebab FPS drop drastis), `mesa_glthread=true`, `vblank_mode=0`, `MESA_GL_VERSION_OVERRIDE=4.5`, shader cache 512 MB, dan `HwSchMode` dimatikan bila tidak ada GPU.
- **🧯 Steam & Discord Tidak Lagi Mencuri Core**: Steam `steamwebhelper.exe` dan Discord (Chromium/Electron) dipaksa **tanpa GPU acceleration** (`BrowserFlags = -cef-disable-gpu -cef-disable-gpu-compositing`, `--disable-gpu`, `enableHardwareAcceleration:false`, prioritas `BelowNormal`, shortcut **`Steam-Hemat-CPU`**) — di mesin tanpa GPU keduanya jatuh ke *software rasterizer* dan bisa memakan **1 core penuh**.
- **🩺 Diagnostik & Optimizer Game Bawaan**: **`Cek-Performa-Render.bat`** menampilkan GPU/adapter, status Mesa3D, nilai `DWMFRAMEINTERVAL`, dan 10 proses paling berat; **`Optimalkan-Game-Ini.bat`** memasang Mesa3D khusus game pilihanmu, mematikan *Fullscreen Optimization* DWM, dan membuat launcher hemat CPU.
- **🧠 20 GB Virtual Memory Pagefile + Fast Disk I/O + Native RAM Cleaner**: Memperbesar Pagefile hingga **20 GB** (total kapasitas memori efektif ~36 GB), mempercepat NTFS I/O Cache, dan membersihkan *Memory Leak* otomatis (`EmptyWorkingSet`) saat pemakaian RAM menyentuh >78%.
- **⚡ MMCSS Gaming + DirectX WARP Tuned + TCP NoDelay**: Mengalokasikan prioritas *Multimedia Class Scheduler* penuh ke game (`SystemResponsiveness=0`), mengoptimalkan DirectX TDR untuk CPU software rendering, mematikan *Nagle's Algorithm* (`TCPNoDelay` + RSS), serta menyalakan *Windows Audio Service*.
- **🛡️ Anti-Freeze Saat Tutup RDP (`AFK-Disconnect-Tanpa-Freeze.bat`)**: Memindahkan sesi aktif ke `Console` (`tscon`) agar render game 3D, macro, atau auto-clicker tetap jalan 100% di belakang layar saat RDP ditutup.
- **📦 Pre-installed Game Runtimes**: Otomatis memasang **DirectX 9/10/11 End-User Legacy Runtimes** dan **Visual C++ Redistributable 2015–2022 (x86 & x64)** supaya game tidak error `.dll` (`d3dx9_43.dll`, `vcruntime140.dll`, dll).
- **🖥️ Direktori Mesa3D Lengkap**: Paket `mesa3d-*-release-msvc.7z` diekstrak ke `C:\Tools\Mesa3D` (folder `x64` & `x86`), sehingga launcher per-game maupun `opengl32.dll` system-wide selalu memakai versi Mesa3D terbaru.
- **💾 Opsi Ekstra Ruang Penyimpanan (+30 GB SSD)**: Tersedia opsi pembersihan SDK bawaan runner jika game yang ingin diinstal berukuran besar.
- **🔒 Aman & Privat dengan Tailscale**: Port `3389` tidak diekspos ke internet publik, hanya bisa diakses dari perangkat HP/PC milikmu yang terhubung ke jaringan Tailscale yang sama.

---

## 🚀 Persiapan Awal (Cuma Sekali Setup)

### 1. Buat Tailscale Auth Key
1. Buat akun gratis / login ke [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys).
2. Pastikan kamu juga sudah menginstal & login aplikasi **Tailscale** di HP atau PC yang akan dipakai meremote.
3. Buka menu **Settings** → **Keys** → klik **Generate auth key...**
4. Atur konfigurasi key seperti berikut:
   - **Reusable**: ✅ **Aktifkan (Centang)** *(agar bisa dipakai berkali-kali setiap menyalakan RDP)*.
   - **Ephemeral**: ✅ **Aktifkan (Centang)** *(agar node RDP otomatis terhapus dari daftar perangkat Tailscale setelah workflow selesai)*.
   - **Expiration**: Pilih `90 days` (maksimal).
5. Klik **Generate key**, lalu **Copy** kode key yang diawali `tskey-auth-...`.

### 2. Tambahkan Secrets ke Repository GitHub
1. Buka repository GitHub ini → klik tab **Settings**.
2. Di menu kiri, pilih **Secrets and variables** → **Actions**.
3. Klik tombol hijau **New repository secret**, lalu tambahkan **2 secret wajib** berikut:

| Nama Secret | Isi / Contoh Nilai | Keterangan |
| :--- | :--- | :--- |
| `TS_AUTHKEY` | `tskey-auth-kxxxxxCNTRL-xxxxxxxxxxxx` | **Wajib** — Auth Key dari Tailscale pada Langkah 1. |
| `RDP_PASSWORD` | `AfkGaming#2026!` | **Wajib** — Password login RDP sekaligus password enkripsi AES-256 Vault (**Wajib min. 8 karakter** kombinasi huruf besar, kecil, angka, dan simbol). |
| `VAULT_PASSWORD` | *(Opsional)* | Password terpisah khusus enkripsi Vault jika tidak ingin memakai `RDP_PASSWORD`. |
| `PAT_TOKEN` | *(Opsional)* | Classic Personal Access Token (`repo`, `workflow`) — hanya diperlukan jika kamu mencentang `auto_restart_chain` untuk jalan estafet otomatis > 12 jam nonstop. |

> **⚙️ Penting untuk Fitur Anti-Reset (Vault):**  
> Buka **Settings** → **Actions** → **General** → scroll ke **Workflow permissions**, pastikan terpilih **Read and write permissions**, lalu klik **Save** (agar GitHub Actions diizinkan menyimpan file backup terenkripsi ke Release).

---

## ▶️ Cara Menjalankan RDP

1. Buka tab **Actions** di repository GitHub kamu.
2. Pilih workflow **Windows AFK Gaming RDP (Tailscale)** di panel sebelah kiri.
3. Klik tombol **Run workflow**, lalu sesuaikan opsi jika perlu:
   - **Durasi sesi RDP**: Pilih `60` s/d `330` menit (~5 jam 30 menit, menyisakan buffer aman 30 menit untuk Atomic Auto-Backup sebelum batas keras 6 jam GitHub Actions).
   - **Pilih Spesifikasi Runner (`runner_os`)**:
     - `windows-2022` *(Default Direkomendasikan — Gratis Public Repo)*: **4 vCPU** (`2 Physical Cores / 4 Logical Threads` AMD EPYC x64 @ 3.24+ GHz) + **16 GB RAM**. Kompatibilitas game `.exe` x64 paling tinggi & ringan.
     - `windows-11-arm` *(Gratis Public Repo — **4 Physical Cores Murni!**)*: Menggunakan prosesor Azure Cobalt 100 **4 Full Physical Cores** (`4 Cores / 4 Threads`) + **16 GB RAM** dengan **Windows 11 Desktop** + emulator Microsoft Prism x64! Cocok dicoba jika ingin 4 core fisik murni tanpa pembagian Hyper-Threading.
     - `windows-2025` / `windows-latest`: **4 vCPU** x64 + **16 GB RAM** (Windows Server 2025).
     - `windows-2022-8core` s/d `64core`: Opsi **8 hingga 64 vCPU** (hingga **256 GB RAM**) — khusus jika organisasi/akun GitHub kamu sudah mengaktifkan *GitHub Larger Runners*.
   - **Username Login RDP**: Default `gamer` (1–20 karakter: huruf, angka, titik, `_`, `-`). Nilai tidak valid akan ditolak sebelum workflow jalan.
   - **Nama Perangkat Tailscale**: Default `s-rdp-afk` (huruf kecil, angka, `-`).
   - **Install Game Runtimes**: Biarkan `true` agar DirectX & VC++ langsung terpasang.
   - **Deploy Mesa3D (`install_mesa3d`)**: Biarkan `true`. Ini yang membuat OpenGL naik dari 1.1 → 4.5 dan game/emulator bisa render di runner tanpa GPU.
   - **Tuning Renderer GPU-less (`tune_rendering`)**: Biarkan `true` (menyetel `LP_NUM_THREADS`, `mesa_glthread`, `vblank_mode=0`, dan encoder RDP hemat CPU).
   - **Batas FPS RDP (`rdp_fps`)**: `30` (default, paling stabil) · `24` / `15` kalau CPU masih penuh · `60` hanya untuk runner ber-GPU.
   - **Bersihkan SDK bawaan**: Centang `true` jika ukuran game besar dan butuh tambahan ruang kosong ~30 GB.
4. Klik **Run workflow** dan tunggu sekitar **2–3 menit**.
5. Buka run yang sedang berjalan → lihat di bagian **Summary** (atau buka log step **`Tampilkan Informasi Koneksi RDP`**) untuk melihat **IP Tailscale** kamu (contoh: `100.x.y.z`).

---

## 💻 Cara Login dari PC / HP

1. Pastikan aplikasi **Tailscale** di PC / HP kamu dalam posisi **Connected**.
2. Buka aplikasi Remote Desktop:
   - **Windows**: Buka **Remote Desktop Connection** (`mstsc`).
   - **Android / iOS / macOS**: Install aplikasi resmi **Windows App** (dulunya Microsoft Remote Desktop) dari Play Store / App Store.
3. Masukkan **IP Tailscale** (`100.x.y.z`), Username (`gamer`), dan Password sesuai `RDP_PASSWORD`.

---

## 💾 Cara Kerja Anti-Reset 6 Jam (Steam, Discord, & Game)

1. **Steam & Discord Otomatis Siap di Desktop**:
   - **Steam** terinstal langsung di dalam folder permanen (`D:\AFK-Data\Steam`). Saat pertama kali login Steam, pastikan centang **"Remember Me"** — di sesi-sesi 6 jam berikutnya, **Steam + semua game yang sudah kamu download di dalamnya langsung terbuka dan auto-login tanpa Steam Guard/download ulang!**
   - **Discord** otomatis disiapkan di Desktop dan data `%AppData%\discord` serta `%LocalAppData%\Discord` ikut di-backup. *(Catatan keamanan Discord: kadang sistem enkripsi DPAPI Windows / deteksi IP baru Discord meminta konfirmasi login ulang saat ganti VM, tapi aplikasinya sendiri langsung siap tanpa perlu download ulang).*
2. **Simpan Semua Game/Bot Non-Steam di `Folder-Permanen-Anti-Reset`**:
   - Klik 2x shortcut **`Folder-Permanen-Anti-Reset`** (`D:\AFK-Data`) di Desktop, lalu taruh semua game launcher lain, macro, atau script AFK kamu di dalam sana.
   - Semua data dienkripsi **AES-256 (`-mhe=on`)** memakai `RDP_PASSWORD` kamu sehingga 100% aman dari orang luar walaupun repository bersifat Public.
3. **Kapan Data Disimpan Otomatis?**
   - Otomatis tersimpan saat timer durasi habis (misal menit ke-340).
   - Otomatis tersimpan saat kamu klik 2x **`Matikan-Server-RDP.bat`** di Desktop.
   - Bisa disimpan manual kapan saja selagi RDP menyala dengan klik 2x **`Simpan-Data-Sekarang.bat`** di Desktop!
   - *(Hindari klik tombol merah **Cancel workflow** paksa di web GitHub karena akan memutus proses sebelum backup terunggah).*

---

## 🧰 Semua Tool di Desktop RDP

| File | Fungsi |
| :--- | :--- |
| `Steam.lnk` / `Steam-Hemat-CPU.lnk` | Steam normal, atau versi hemat CPU (Chromium UI tanpa GPU acceleration). |
| `Discord.lnk` | Menjalankan Discord yang sudah dipulihkan dari Vault (atau instal otomatis saat pertama diklik). |
| `Folder-Permanen-Anti-Reset (X:).lnk` | Membuka folder Vault permanen tempat game & bot harus disimpan. |
| `Optimalkan-Game-Ini.bat` | Pilih `.exe` game → Mesa3D llvmpipe dipasang khusus game itu, Fullscreen Optimization DWM dimatikan, launcher hemat CPU dibuat. |
| `Cek-Performa-Render.bat` | Diagnostik: adapter GPU, status Mesa3D, `DWMFRAMEINTERVAL`, `LP_NUM_THREADS`, 10 proses terberat, pemakaian RAM. |
| `AFK-Disconnect-Tanpa-Freeze.bat` | Pindahkan sesi ke Console (`tscon`) supaya game tetap render saat RDP ditutup. |
| `Simpan-Data-Sekarang.bat` | Live snapshot Vault tanpa menutup game. |
| `Matikan-Server-RDP.bat` | Backup final + hentikan sesi (mencegah auto-restart). |
| `BACA-PANDUAN-AFK-GAME.txt` | Ringkasan semua tips di atas, tersimpan offline di Desktop. |

---

## ⚠️ PENTING: Cara Tinggal AFK Agar Game Tidak Freeze!

Saat kamu sudah menyalakan game, bot, atau auto-clicker di dalam RDP dan ingin menutup aplikasi Remote Desktop di HP/PC:

> **JANGAN langsung klik tombol silang `[X]` / Disconnect di aplikasi Remote Desktop!**  
> Jika langsung ditutup, Windows akan mencopot layar virtual sehingga render game & auto-clicker macet/hitam.

**Cara yang benar:**
1. Lihat di **Desktop RDP**, klik 2x file **`AFK-Disconnect-Tanpa-Freeze.bat`**.
2. Dalam 3 detik, koneksi RDP kamu akan otomatis diputus dan sesi layar dipindahkan ke *Local Console* aktif.
3. Game, macro, dan auto-clicker akan tetap berjalan normal 100% di belakang layar!
4. Kapan pun kamu ingin mengecek progres AFK, cukup sambungkan ulang RDP seperti biasa.

---

## 🐢 Kenapa Game Cuma 5 FPS? (Akar Masalah & Solusinya)

Runner GitHub `windows-2022` = **4 vCPU + 16 GB RAM + TANPA GPU** (hanya *Microsoft Basic Render Driver* / WARP). Artinya **seluruh pixel 3D dihitung oleh CPU**. Itu bukan bug skrip, tapi memang batas fisik — dan sisanya adalah perang memperebutkan 4 core yang sama:

| # | Penyedot CPU (sebelum diperbaiki) | Dampak | Perbaikan di repo ini |
| :-- | :--- | :--- | :--- |
| 1 | **DWM dipaksa 60 FPS** (`DWMFRAMEINTERVAL=15`) padahal render CPU tidak mungkin 60 | 1 core habis hanya untuk *copy/compose* frame | Pacing adaptif `rdp_fps` (default **30**) |
| 2 | **`LP_NUM_THREADS` default = semua core** | Game + DWM + encoder saling berebut → stutter, FPS jatuh | `LP_NUM_THREADS = vCPU − 1` |
| 3 | **OpenGL masih driver bawaan Windows 1.1** | Game/emulator OpenGL gagal jalan atau sangat lambat | Mesa3D llvmpipe **OpenGL 4.5** (system-wide + per-game) |
| 4 | **Steam `steamwebhelper.exe`** software-render Chromium UI | Bisa memakan **1 core penuh** | `-cef-disable-gpu -cef-disable-gpu-compositing` + `BrowserFlags` + prioritas `BelowNormal` |
| 5 | **Discord (Electron) GPU process** jatuh ke software | Makan core + RAM | `--disable-gpu`, `enableHardwareAcceleration:false`, `BelowNormal` |
| 6 | **AVC444/H.264 hardware encode dipaksa** di mesin tanpa hardware encoder | Percobaan encode software 4:4:4 yang mahal | Otomatis **dimatikan** bila tidak ada GPU |
| 7 | **TermDD FlowControl konservatif** | RDP terasa *slideshow* walau bandwidth Tailscale longgar | `FlowControlDisable=1` + `CaptureFrameRate` |
| 8 | **Fullscreen Optimization DWM** | Frame 3D dikomposisi dua kali | `~ DISABLEDXMAXIMIZEDWINDOWEDMODE` via `Optimalkan-Game-Ini.bat` |
| 9 | Defender realtime, `mscorsvw`, `TiWorker`, telemetri, WinSearch | 1–3% CPU saat idle & spike saat startup | Dimatikan total |

### Langkah praktis menaikkan FPS (berurutan)
1. **`Optimalkan-Game-Ini.bat`** (Desktop) → pilih file `.exe` game → jalankan lewat **`Jalankan-<nama>-Hemat-CPU.bat`** yang otomatis dibuat.
2. Resolusi game **1024x768 / 800x600** (720p sudah berat untuk software render).
3. **Windowed / Borderless**, V-Sync **OFF**, FPS limit in-game **30**.
4. Matikan **Shadow, Anti-Aliasing, Bloom, Motion Blur, Post-Processing, Ray Tracing**, tekstur ke *Low*.
5. Kalau masih <15 FPS: jalankan ulang workflow dengan **`rdp_fps = 24`** (atau `15`), lalu cek **`Cek-Performa-Render.bat`** untuk melihat proses mana yang masih rakus CPU.
6. Untuk game 2D / idle / *auto-battler* / Discord Quest farming, kombinasi di atas biasanya sudah **30–60 FPS stabil**.

> **Ekspektasi realistis:** game 3D modern (AAA) **tidak akan** playable di runner gratis tanpa GPU, sekeras apa pun tuning-nya — hardware-nya memang tidak ada. Yang bisa dicapai: game 2D/indie/emulator ringan dan game AFK berjalan mulus, serta semua game setidaknya *bisa dijalankan* dengan Mesa3D.

### Kenapa tidak pakai GPU virtual (Virtual Display Driver / parsec-vdd)?
Keduanya driver *display* virtual, **bukan GPU** — render tetap di CPU, ditambah risiko *driver signing / test mode* yang bisa membuat runner gagal boot. Karena itu repo ini memilih jalur **Mesa3D + WARP + tuning CPU**, yang 100% aman dan gratis.

### Tips Klien RDP (sisi kamu, di HP/PC)
- **Experience:** `LAN (10 Mbps or higher)`.
- **Color depth:** `16-bit` (meringankan encoder software).
- Jangan pakai mode *fullscreen borderless* pada aplikasi Remote Desktop.
- Jika sudah selesai AFK sebelum timer habis, klik 2x **`Matikan-Server-RDP.bat`** di Desktop untuk menghemat kuota menit GitHub Actions.
