# 🎮 S-RDP — Windows AFK Gaming RDP (GitHub Actions + Tailscale)

Workflow GitHub Actions siap pakai untuk membuat **Windows Server Remote Desktop (RDP)** dengan jaringan privat **Tailscale**, yang sudah dioptimasi khusus untuk **AFK game berat, macro, dan auto-clicker** tanpa *freeze* saat koneksi RDP ditutup.

---

## ✨ Fitur Utama (Khusus AFK Game — Zero-Cost Max Tuned)

> **Semua fitur data & kompatibilitas sudah DITANAM PERMANEN (tanpa centang):**
> Anti-Reset 6 Jam (Atomic AES-256 Vault), pembersihan SDK GitHub (+~30 GB), Mesa3D Software GPU Renderer,
> DirectX 9/10/11 Legacy + VC++ Redistributable, serta auto-install **Steam & Discord**.
> **Username RDP selalu `egandika`** — tidak perlu diisi lagi. Fitur *Auto-Restart 24/7* sudah **dihapus**.

- **💾 Anti-Reset 6 Jam (Atomic AES-256 Vault + Instant NTFS Junctions)**: Otomatis menginstal **Steam & Discord**, menghubungkan folder profil via **NTFS Directory Junction (`mklink /J`)** (0 detik waktu salin, bebas duplikasi ruang disk, & bebas bug *Corrupt User Profile*), serta menyimpan seluruh isi **`D:\AFK-Data`** ke GitHub Release (`s-rdp-vault`) dengan **Atomic Staging Swap** (`s-rdp-vault-staging` → `s-rdp-vault`) berenkripsi **7-Zip AES-256 + Filename Encryption (`-mhe=on`)** sehingga backup lama mustahil terhapus jika koneksi terputus!
- **🎯 Locked Console Resolution (`1280x720 @ 100% DPI`)**: Menyeragamkan resolusi & skala DPI layar Console dengan RDP agar titik koordinat *Auto-Clicker / Macro* tidak bergeser saat pindah ke mode AFK (`tscon`).
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
- **⏱️ Timer Resolution 1 ms Tetap Hidup (`timeBeginPeriod(1)`) — Anti-Stutter**: Windows menurunkan resolusi timer ke ~15,6 ms saat idle, sehingga game, sleeper macro, dan `Sleep()` internal jadi *patah-patah*. Task **`S-RDP-TimerResolution`** berjalan sebagai `SYSTEM` sejak boot dan menahan resolusi timer di **1 ms** selama sesi hidup.
- **🎞️ Fullscreen Exclusive + Wallpaper Mati**: `GameDVR_FSEBehaviorMode=2` memaksa game yang mendukung FSE untuk **keluar dari komposisi DWM** (frame 3D tidak di-*copy* dua kali), wallpaper/`TileWallpaper` dikosongkan, dan `ForegroundLockTimeout=0` menghilangkan jeda saat aplikasi mengambil fokus.
- **🗂️ Shader Cache Mesa Permanen di Vault**: Stutter terbesar llvmpipe adalah **kompilasi shader** saat game pertama kali dibuka. `MESA_SHADER_CACHE_DIR` diarahkan ke **`D:\AFK-Data\ShaderCache`** (ikut ter-backup), jadi di sesi ke-2 dan seterusnya game langsung mulus sejak frame pertama.
- **🎮 Launcher Ganda: llvmpipe vs GLonD3D12**: `Optimalkan-Game-Ini.bat` sekarang membuat **dua** launcher — `Jalankan-<nama>-Hemat-CPU.bat` (llvmpipe) dan `Jalankan-<nama>-D3D12.bat` (`GALLIUM_DRIVER=d3d12`, OpenGL lewat **WARP Direct3D 12**). Untuk game *fill-rate* berat, jalur D3D12 sering **1,5–2× lebih cepat** dari llvmpipe.
- **🌐 File Klien `.rdp` Siap Pakai (Artefak)**: Tiap run mengunggah **`S-RDP-Optimal.rdp`** berisi IP Tailscale run tersebut + setting klien paling rendah latensi (`16-bit`, `LAN`, animasi/wallpaper OFF, `1280x720`, clipboard ON, redirection OFF). Cukup unduh di tab **Artifacts** → double-click.
- **🧹 Pembersihan Sisa: Service & Kompresi RDP**: `MaxCompressionLevel=0` (kompresor V1 = paling ringan di CPU), Controlled Folder Access off, MMCSS `Clock Rate=10000` + `Affinity=0`, serta pruning service mati (`TabletInputService`, `RemoteRegistry`, `RetailDemo`, `WMPNetworkSvc`, `Fax`, `diagnosticshub`, `edgeupdate*`) — Xbox service **sengaja dibiarkan** karena dipakai overlay & save cloud game.
- **🖥️ Direktori Mesa3D Lengkap**: Paket `mesa3d-*-release-msvc.7z` diekstrak ke `C:\Tools\Mesa3D` (folder `x64` & `x86`), sehingga launcher per-game maupun `opengl32.dll` system-wide selalu memakai versi Mesa3D terbaru.
- **💾 Ekstra Ruang Penyimpanan (+~30 GB SSD)**: Pembersihan SDK bawaan runner (Android SDK, GHC/ghcup, CodeQL, .NET SDK) **selalu dijalankan otomatis** supaya game besar punya ruang lega.
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
   - **Nama Perangkat Tailscale**: Default `s-rdp-afk` (huruf kecil, angka, `-`).
   - **Batas FPS RDP (`rdp_fps`)**: `30` (default, paling stabil) · `24` / `15` kalau CPU masih penuh · `60` hanya untuk runner ber-GPU.
   - **Tuning Renderer GPU-less (`tune_rendering`)**: Biarkan `true` (menyetel `LP_NUM_THREADS`, `mesa_glthread`, `vblank_mode=0`, dan encoder RDP hemat CPU).
4. Klik **Run workflow** dan tunggu sekitar **2–3 menit**.
5. Buka run yang sedang berjalan → lihat di bagian **Summary** (atau buka log step **`Tampilkan Informasi Koneksi RDP`**) untuk melihat **IP Tailscale** kamu (contoh: `100.x.y.z`).

> ℹ️ **Tidak ada centang yang perlu diatur lagi.** Anti-Reset Vault, pembersihan SDK (+~30 GB), Mesa3D,
> DirectX + VC++, serta instalasi Steam & Discord **selalu dijalankan otomatis**, dan username RDP selalu **`egandika`**.

---

## 💻 Cara Login dari PC / HP

1. Pastikan aplikasi **Tailscale** di PC / HP kamu dalam posisi **Connected**.
2. Buka aplikasi Remote Desktop:
   - **Windows**: Buka **Remote Desktop Connection** (`mstsc`).
   - **Android / iOS / macOS**: Install aplikasi resmi **Windows App** (dulunya Microsoft Remote Desktop) dari Play Store / App Store.
3. Masukkan **IP Tailscale** (`100.x.y.z`), Username **`egandika`**, dan Password sesuai `RDP_PASSWORD`.
4. **(Disarankan) Pakai file `.rdp` otomatis**: di halaman **Actions → run yang sedang jalan → bagian bawah `Artifacts`**, unduh **`S-RDP-Optimal-<run id>`** → ekstrak → **double-click `S-RDP-Optimal.rdp`** → masukkan password. File ini sudah membawa IP run tersebut + seluruh setting klien *low-latency* (lihat tabel di bawah), jadi tidak ada lagi salah setting *Experience/color depth*.

### Isi `S-RDP-Optimal.rdp` (dan alasannya)

| Setting | Nilai | Alasan |
| :--- | :--- | :--- |
| `session bpp` | `16` | Encoder RDP software 30–40% lebih ringan → frame sampai lebih awal. |
| `connection type` | `6` (LAN) + `networkautodetect:0` | Auto-detect sering **menurunkan** mode grafis & menambah jeda; LAN dipaksa. |
| `desktopwidth/height` | `1280x720` | Cocok dengan *Locked Console Resolution* repo ini; titik klik macro tidak bergeser. |
| `disable wallpaper / full window drag / menu anims / themes / cursor setting` | `1` | 5 sumber frame terbuang di sisi klien. |
| `allow font smoothing` / `desktop composition` | `0` | Blur AA font & komposisi tambahan = kerja ekstra tiap frame. |
| `keyboardhook` | `2` | Hook keyboard hanya saat *fullscreen* → tidak ada overhead saat windowed. |
| `redirectclipboard` | `1` | Copy-paste tetap jalan (kebutuhan login Steam Guard / kode Discord). |
| `redirectprinters/comports/smartcards/posdevices`, `drivestoredirect`, `usbdevicestoredirect`, `camerastoredirect` | OFF | Setiap redirection = kanal RPC yang dicek tiap detik. |
| `autoreconnection enabled` | `1` | Tailscale putus 2 detik (pindah Wi-Fi) → sesi **tidak** mati, game **tidak** freeze. |
| `bitmapcachepersistenable` | `1` | Cache bitmap antar-sesi → UI Windows tidak di-render ulang tiap konek. |

> Butuh versi 1080p? Ubah `desktopwidth/desktopheight` jadi `1920`/`1080` **dan** `rdp_fps = 24`, karena encoder software harus mengompres 2,25× pixel lebih banyak. Template tanpa IP ada di [`client/S-RDP-Optimal.rdp`](client/S-RDP-Optimal.rdp).
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
| `Optimalkan-Game-Ini.bat` | Pilih `.exe` game → Mesa3D llvmpipe dipasang khusus game itu, Fullscreen Optimization DWM dimatikan, lalu dibuat **dua** launcher: `Jalankan-<nama>-Hemat-CPU.bat` (llvmpipe) & `Jalankan-<nama>-D3D12.bat` (WARP D3D12). |
| `Cek-Performa-Render.bat` | Diagnostik: adapter GPU, status Mesa3D, `DWMFRAMEINTERVAL`, `LP_NUM_THREADS`, 10 proses terberat, pemakaian RAM. |
| `AFK-Disconnect-Tanpa-Freeze.bat` | Pindahkan sesi ke Console (`tscon`) supaya game tetap render saat RDP ditutup. |
| `AutoStart-Steam.bat` | Toggle: aktifkan agar **Steam langsung jalan sendiri** tiap sesi baru selesai restore (tanpa klik). |
| `Simpan-Data-Sekarang.bat` | Live snapshot Vault tanpa menutup game. |
| `Matikan-Server-RDP.bat` | Backup final + hentikan sesi lebih awal (hemat kuota menit Actions). |
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

## ⌨️ Klik / Ketik Terasa Ada Jeda? (Input Latency)

Jeda saat klik di RDP datang dari **4 sumber**, dan yang pertama paling sering: **rute jaringan Tailscale**.

| # | Sumber jeda | Status di repo ini |
| :-- | :--- | :--- |
| 1 | **Koneksi lewat RELAY DERP** (bukan direct) → tiap klik menempuh rute jauh (50–300 ms) | Workflow sekarang **mengukur & melaporkan** di Summary: baris **Latensi Tailscale** + daftar peer `DIRECT (...) / RELAY ...`. Kalau muncul *RELAY DERP* → itu penyebabnya, bukan server. |
| 2 | **`MenuShowDelay` & `MouseHoverTime` default 400 ms** (Windows sengaja menunda menu/tombol) | Ditimpa jadi **0 ms** (Default Hive + logon script, jadi aktif sejak logon pertama) |
| 3 | **Pointer acceleration** ("Enhance pointer precision") + bayangan/jejak kursor | `MouseSpeed/Threshold=0`, `SmoothMouse*Curve` dinolkan, `CursorShadow=0`, `MouseTrails=0`, `ClickLock=0` |
| 4 | **Animasi drag & key-repeat lambat** | `DragFullWindows=0`, `ActiveWndTrkTimeout=0`, `KeyboardDelay=0`, `KeyboardSpeed=31` |

Nilai tersebut langsung diterapkan ke sesi berjalan lewat `SystemParametersInfo` (`SPI_SETMENUSHOWDELAY`, `SPI_SETKEYBOARDDELAY`, `SPI_SETKEYBOARDSPEED`), jadi tidak perlu logout.

### Yang harus kamu atur di sisi klien (HP/PC) — ini yang paling menentukan
1. **Experience: `LAN (10 Mbps or higher)`** — jangan `Detect connection quality`. Auto-detect sering menurunkan mode grafis dan menambah jeda input.
2. **Color depth `16-bit`** (di tab Display) — encoder software lebih cepat = frame sampai lebih awal.
3. **Matikan "Enhance pointer precision"** di Windows lokalmu: *Settings → Bluetooth & devices → Mouse → Additional mouse settings → Pointer Options → uncheck*.
4. **HP/tablet: matikan mode sentuh / "tap and hold"** di aplikasi Remote Desktop. Mode sentuh menahan klik ~0,5–1 detik untuk menebak klik-kanan — ini bukan lag server, tapi terasa seperti lag. Pakai **mouse mode / trackpad mode**.
5. Jangan pakai **fullscreen borderless** pada aplikasi RDP.

### Kalau jedanya di dalam game (bukan menu Windows)
Jeda itu = **waktu render 1 frame**. Di runner tanpa GPU artinya 50–150 ms saat game berat. Yang menurunkan: **resolusi lebih kecil**, efek grafis mati, dan `rdp_fps` lebih tinggi (**`60`** membuat desktop/klik terasa lebih responsif, tapi memakan CPU — trade-off dengan FPS game).

**`rdp_fps` 15 / 24 / 30 / 60 — pilih yang mana?**

| `rdp_fps` | `DWMFRAMEINTERVAL` | Efek | Biaya CPU untuk DWM+encoder | Pakai saat |
| :--- | :--- | :--- | :--- | :--- |
| `15` | 66 ms | Desktop terasa *patah-patah*, klik masih nyaman | ~1/4 | Game 3D berat (berapa pun FPS-nya, menang di CPU) |
| `24` | 41 ms | Batas nyaman mata untuk gerakan lambat | ~1/2 | Game 3D sedang / 1080p |
| **`30`** (default) | **33 ms** | **Titik seimbang**: desktop mulus, 2–3 core tersisa untuk game | ~2/3 core | Hampir semua kasus (2D, idle, auto-battler, Quest farming) |
| `60` | 15 ms | Klik paling responsif, tapi DWM+encoder bisa makan **2 core penuh** dari 4 → game turun 20–60% FPS | 1,5–2 core | Hanya runner ber-GPU, atau game 2D sangat ringan |

Aturan praktis: **kalau FPS game turun saat `rdp_fps` dinaikkan, berarti CPU-nya yang jadi botol** — turunkan fps, jangan naikkan resolusi.

> Catatan jujur: tweak driver `MouseDataQueueSize` / `KeyboardDataQueueSize` **sengaja tidak dipakai** di sini karena nilainya hanya dibaca saat driver dimuat (butuh reboot), dan runner tidak pernah reboot → efeknya cuma placebo.

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

---

## ✅ Checklist Lengkap Tuning (Anti-Bolong)

Daftar **seluruh** knob optimasi yang relevan untuk runner Windows tanpa GPU, apa yang dipakai repo ini, dan **kenapa** sesuatu yang tidak dipakai memang sengaja dilewati. Kalau kamu menemukan tweak di internet dan tidak ada di tabel ini, berarti tweak itu tidak berefek di lingkungan *runner ephemeral tanpa GPU*.

### 1. CPU & Scheduler
| Tweak | Status | Detail / alasan |
| :--- | :--- | :--- |
| Core parking dibuka | ✅ | `CPMINCORES=100` (semua core selalu siap). |
| Boost mode dikunci | ✅ | `PERFBOOSTMODE=2`, `PERFBOOSTPOL=100`, `PERFEPP=0` (performance → power, bukan sebaliknya). |
| Power plan | ✅ | Skema *High Performance* dipaksa + `IDLEDISABLE=1` (tidak pernah turun ke *idle states*). |
| Skema *Ultimate Performance* | ⛔ sengaja tidak | Butuh `powercfg -duplicatescheme` ulang tiap boot (runner ephemeral) → untungnya marjinal, risikonya gagal diam-diam. |
| `Win32PrioritySeparation` | ✅ | `38` = *short quantum, variable, boost foreground* (paling responsif untuk game windowed). |
| MMCSS untuk game | ✅ | Task `Games` → `GPU Priority=8`, `Priority=6`, `Scheduling Category=High`, `SFIO Priority=High`, `Clock Rate=10000`, `Affinity=0`. |
| `SystemResponsiveness` | ✅ | `0` = 100% CPU ke aplikasi, sisa ke background. (`100` justru **kebalikan** dan sering salah kutip di tweak internet.) |
| Timer resolution 1 ms | ✅ | Task `S-RDP-TimerResolution` → `timeBeginPeriod(1)` ditahan sepanjang sesi. |
| Prioritas proses game | ✅ | Auto-boost `AboveNormal` tiap 5 menit untuk `.exe` game aktif. |
| `ThreadPriority` per-thread | ⛔ sengaja tidak | Nilai `31` (real-time) hanya untuk thread audio pro; di server RDP berisiko **membekukan** input/DWM. |
| Affinity dipaku ke core tertentu | ⛔ sengaja tidak | Dengan 4 vCPU, pinning game ke 2 core justru mematikan *turbo* & membuat DWM kelaparan. |

### 2. Memori
| Tweak | Status | Detail |
| :--- | :--- | :--- |
| Pagefile besar | ✅ | 20 GB (total efektif ~36 GB) supaya game + shader cache tidak OOM. |
| Native RAM cleaner | ✅ | `EmptyWorkingSet` saat RAM >78% (mencegah *memory leak* Chrome/Electron). |
| `LargeSystemCache` | ✅ di-**0**-kan | Default server = `1` (cache file-system besar). Di 16 GB, itu menekan *working set* game → disetel `0`. |
| `ClearPageFileAtShutdown` | ⛔ sengaja tidak | Memperlambat shutdown, nol dampak performa. |
| Memory compression (SysMain) | ⛔ sengaja tidak | SysMain dimatikan total (service mati), kompresi memori ikut tidak relevan. |
| `DisablePagingExecutive` | ✅ `1` | Kernel & driver tetap di RAM (tidak ada *page-in* saat frame butuh driver call). |

### 3. Disk & I/O
| Tweak | Status | Detail |
| :--- | :--- | :--- |
| Pembersihan SDK runner | ✅ | +~30 GB (Android SDK, GHC, CodeQL, .NET SDK). |
| NTFS I/O dipercepat | ✅ | `fsutil behavior set memoryusage 2` (cache metadata lebih agresif), `disablelastaccess 1` (tidak ada tulis timestamp tiap file dibaca), `disable8dot3 1` (lookup nama file lebih cepat). |
| Defrag/TRIM manual | ⛔ tidak perlu | Runner memakai SSD ephemeral; TRIM otomatis. |
| `Prefetch/Superfetch` | ⛔ dimatikan | Di disk ephemeral, prefetch hanya menulis file yang tidak pernah terpakai ulang. |
| Shader cache persisten | ✅ | `MESA_SHADER_CACHE_DIR → D:\AFK-Data\ShaderCache` + `MESA_SHADER_CACHE_MAX_SIZE=512M`. |
| Cache Steam diarsipkan | ⛔ dikecualikan | `steamapps\shadercache`, `downloading`, `httpcache` bisa GB-an & selalu bisa dibuat ulang → vault jadi cepat. |

### 4. GPU / Renderer
| Tweak | Status | Detail |
| :--- | :--- | :--- |
| Mesa3D llvmpipe OpenGL 4.5 | ✅ | System-wide (`System32`/`SysWOW64`) + per-game, driver asli dibackup `.srdp-bak`. |
| `LP_NUM_THREADS = vCPU − 1` | ✅ | Mencegah llvmpipe merebut semua core dari DWM/encoder. |
| `mesa_glthread`, `vblank_mode=0` | ✅ | Perintah GL dikirim paralel, tidak menunggu vsync 60 Hz. |
| `MESA_NO_ERROR=1` | ✅ | Melewati cek error GL per-call (mahal di software render). |
| `MESA_VK_WSI_PRESENT_MODE=immediate` | ✅ | Untuk game Vulkan: present tanpa antre vsync. |
| GLonD3D12 (`GALLIUM_DRIVER=d3d12`) | ✅ | Launcher alternatif: OpenGL di atas **WARP D3D12**. |
| DirectX 9/10/11 legacy + VC++ | ✅ | Supaya game DX9 tidak gagal `.dll`/fallback ke path lambat. |
| WARP tuning | ✅ | `HwSchMode=0` (tanpa GPU, GPU scheduling hanya menambah overhead), TDR longgar (`TdrLevel=3`, `TdrDelay=60`). |
| AVC444 / H.264 hardware encode | ✅ adaptif | **Dimatikan** bila tidak ada GPU (software 4:4:4 = mahal), dinyalakan hanya bila GPU terdeteksi. |
| `VGOptimization_CaptureFrameRate` | ✅ | Frame capture dibatasi agar encoder tidak mengejar FPS yang mustahil. |
| Fullscreen Exclusive (FSE) | ✅ | `GameDVR_FSEBehaviorMode=2` + `DXGIHonorFSEWindowsCompatible=1` → frame tidak dikomposisi dua kali. |
| `~ DISABLEDXMAXIMIZEDWINDOWEDMODE` | ✅ | Per-game lewat `Optimalkan-Game-Ini.bat`. |
| Virtual Display Driver / parsec-vdd | ⛔ sengaja tidak | Itu driver *display*, **bukan GPU** — render tetap CPU, plus risiko *driver signing*/boot gagal. |

### 5. Jaringan & Latensi
| Tweak | Status | Detail |
| :--- | :--- | :--- |
| Tailscale, port 3389 tidak publik | ✅ | Hanya perangkat di tailnet yang bisa masuk. |
| Deteksi **DIRECT vs RELAY** | ✅ | Dilaporkan di Summary tiap run (`tailscale status --json`). RELAY DERP = sumber jeda, bukan server. |
| `tailscale ping` RTT | ✅ | Angka nyata per-peer, bukan tebakan. |
| `TCPNoDelay` + `TCPAckFrequency=1` | ✅ | Nagle dimatikan → paket klik tidak ditahan. |
| `NetworkThrottlingIndex = 0xffffffff` | ✅ | MMCSS berhenti membatasi paket jaringan ke 10 paket/ms saat multimedia aktif. |
| RSS / autotuning | ✅ | Antrean jaringan multi-core. |
| Kompresi RDP | ✅ | `MaxCompressionLevel=0` = kompresor V1 (paling ringan di CPU). Naikkan ke `2` **hanya** kalau bandwidth Tailscale-mu terbatas. |
| TermDD `FlowControlDisable` | ✅ | `FlowControlDisable=1` + `FlowControlDisplayBandwidth`/`ChannelBandwidth` dilepas. |
| QoS / DSCP marking | ⛔ sengaja tidak | Tailscale (WireGuard UDP) sudah punya jalur sendiri; marking tidak dihormati antar-AS. |
| MTU tuning manual | ⛔ sengaja tidak | Tailscale mengatur MTU 1280 otomatis & aman untuk semua link. |

### 6. Input
| Tweak | Status | Detail |
| :--- | :--- | :--- |
| `MenuShowDelay` / `MouseHoverTime` | ✅ | `0` ms (Default Hive + logon script + `SystemParametersInfo`). |
| Pointer acceleration & jejak | ✅ | `MouseSpeed=0`, `SmoothMouse*Curve` dinolkan, `MouseTrails=0`, `CursorShadow=0`. |
| Key repeat | ✅ | `KeyboardDelay=0`, `KeyboardSpeed=31`. |
| Drag & window track | ✅ | `DragFullWindows=0`, `ActiveWndTrkTimeout=0`. |
| `MouseDataQueueSize` / `KeyboardDataQueueSize` | ⛔ sengaja tidak | Dibaca **hanya saat driver dimuat** → butuh reboot; runner tidak pernah reboot → placebo murni. |
| `SPI_SETMOUSE`/`SPI_SETKEYBOARD*` saat logon | ✅ | Diterapkan ulang tiap logon supaya tidak hilang setelah `tscon`. |
| Setting klien (16-bit, LAN, mouse mode) | ✅ | Otomatis lewat artefak `S-RDP-Optimal.rdp`. |

### 7. Service, Startup & Keamanan
| Tweak | Status | Detail |
| :--- | :--- | :--- |
| Defender realtime, `mscorsvw`, `TiWorker` | ✅ dimatikan | Penyedot CPU #1 di runner. |
| Controlled Folder Access | ✅ `0` | CFA mencegat tulis file game/save (I/O lambat + false positive). |
| Service mati: `TabletInputService`, `RemoteRegistry`, `RetailDemo`, `WMPNetworkSvc`, `Fax`, `diagnosticshub`, `edgeupdate*` | ✅ | Tidak dipakai di sesi gaming. |
| Xbox services (`XblAuthManager`, `XblGameSave`, `XboxNetApiSvc`, `XboxGipSvc`) | ⛔ **sengaja dibiarkan** | Dibutuhkan overlay, save cloud, dan banyak game Microsoft Store/Game Pass. |
| `DiagTrack`, `WSearch`, `SysMain`, telemetri | ✅ | Dimatikan + *Scheduled Maintenance* dimatikan. |
| `AudioSrv` | ✅ dinyalakan | Banyak game crash/macet tanpa audio endpoint. |
| Disk quota / UAC prompt | ✅ | Quota off, UAC tidak mengganggu macro. |

### 8. Sesi & Persistensi
| Tweak | Status | Detail |
| :--- | :--- | :--- |
| Anti-freeze saat tutup RDP | ✅ | `tscon` ke Console; game/macro tetap render. |
| Auto-Restart 24/7 | 🗑️ dihapus | Sesuai permintaan: tidak ada auto-restart. |
| Vault AES-256 `-mhe=on` | ✅ | Atomic staging swap; tidak ada plaintext kredensial di repo Public. |
| Auto-start Steam | ✅ opsional | Toggle `AutoStart-Steam.bat` → Steam jalan sendiri tiap logon. |
| Auto-login Windows (plaintext `DefaultPassword`) | ⛔ sengaja tidak | Password tersimpan plaintext di registry/Disk → bocor ke vault. Login RDP manual lebih aman. |

> **Ringkas:** 60+ knob dipakai, 12 knob populer **sengaja ditolak** dengan alasan teknis di atas. Itu bukan kelalaian — itu daftar yang sudah diuji terhadap karakteristik runner: **ephemeral, 4 vCPU, tanpa GPU, tanpa reboot**.
