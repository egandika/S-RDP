# 🎮 S-RDP — Windows AFK Gaming RDP (GitHub Actions + Tailscale)

Workflow GitHub Actions siap pakai untuk membuat **Windows Server Remote Desktop (RDP)** dengan jaringan privat **Tailscale**, yang sudah dioptimasi khusus untuk **AFK game berat, macro, dan auto-clicker** tanpa *freeze* saat koneksi RDP ditutup.

---

## ✨ Fitur Utama (Khusus AFK Game — Zero-Cost Max Tuned)

- **💾 Anti-Reset 6 Jam (Encrypted Vault AES-256 Tanpa Cloud Luar!)**: Otomatis menginstal **Steam & Discord**, lalu menyimpan seluruh isi folder **`D:\AFK-Data`** (termasuk game Steam yang sudah terunduh, sesi login *Remember Me* Steam, AppData Discord, & macro) ke GitHub Release (`s-rdp-vault`) dengan enkripsi militer **7-Zip AES-256 + Filename Encryption (`-mhe=on`)** yang dipecah per 1.9 GB (mendukung ukuran game puluhan GB!). Begitu RDP sesi berikutnya nyala, semua aplikasi & game langsung pulih dalam hitungan detik tanpa download ulang!
- **♾️ Opsi Auto-Restart Estafet 24/7 (`auto_restart_chain`)**: Selesai backup di akhir jam ke-6, workflow bisa otomatis menyalakan sesi RDP baru untuk menyambung sesi sebelumnya.
- **🔥 Kill 70% Background CPU Hogs (Idle CPU ~1–3%)**: Mematikan paksa penyedot CPU bawaan runner GitHub (*Windows Defender Real-Time Scan `MsMpEng.exe`*, *`.NET Runtime Optimization mscorsvw.exe`*, *`TiWorker`*, *`CompatTelRunner`*, dan *Scheduled Maintenance*) sehingga 100% tenaga 4 vCPU AMD EPYC (3.24+ GHz Boost) murni dipakai oleh game.
- **🚀 CPU Core Unparking + Auto Game Priority Booster**: Membuka seluruh *CPU Core Parking* (`CPMINCORES=100%`), mengunci *Boost Mode* di 100%, serta otomatis menaikkan prioritas proses `.exe` game aktif ke `AboveNormal` setiap 5 menit.
- **🖥️ Unlock RDP 60 FPS + AVC444/H.264 Low-Latency**: Membuka kunci batas bawaan Windows Server (30 FPS → **60 FPS** via `DWMFRAMEINTERVAL=15`) serta mengaktifkan mode grafis H.264/AVC444 supaya kontrol layar jauh lebih halus.
- **🧠 20 GB Virtual Memory Pagefile + Fast Disk I/O + Native RAM Cleaner**: Memperbesar Pagefile hingga **20 GB** (total kapasitas memori efektif ~36 GB), mempercepat NTFS I/O Cache, dan membersihkan *Memory Leak* otomatis (`EmptyWorkingSet`) saat pemakaian RAM menyentuh >78%.
- **⚡ MMCSS Gaming + DirectX WARP Tuned + TCP NoDelay**: Mengalokasikan prioritas *Multimedia Class Scheduler* penuh ke game (`SystemResponsiveness=0`), mengoptimalkan DirectX TDR untuk CPU software rendering, mematikan *Nagle's Algorithm* (`TCPNoDelay` + RSS), serta menyalakan *Windows Audio Service*.
- **🛡️ Anti-Freeze Saat Tutup RDP (`AFK-Disconnect-Tanpa-Freeze.bat`)**: Memindahkan sesi aktif ke `Console` (`tscon`) agar render game 3D, macro, atau auto-clicker tetap jalan 100% di belakang layar saat RDP ditutup.
- **📦 Pre-installed Game Runtimes**: Otomatis memasang **DirectX 9/10/11 End-User Legacy Runtimes** dan **Visual C++ Redistributable 2015–2022 (x86 & x64)** supaya game tidak error `.dll` (`d3dx9_43.dll`, `vcruntime140.dll`, dll).
- **🖥️ Opsi Mesa3D Software GPU Renderer**: Karena GitHub Runner standar menggunakan CPU 4-Core / 16 GB RAM tanpa VGA diskrit, tersedia opsi unduh otomatis **Mesa3D (Gallium llvmpipe)** di `C:\Tools\Mesa3D` untuk game yang membutuhkan akselerasi OpenGL/Direct3D berbasis CPU.
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
   - **Durasi sesi RDP**: Pilih `60` s/d `350` menit (~5 jam 50 menit, batas maksimal GitHub Actions adalah 6 jam per run).
   - **Versi Windows Server**: `windows-2022` (direkomendasikan karena paling stabil untuk game) atau `windows-2025`.
   - **Username Login RDP**: Default `gamer`.
   - **Install Game Runtimes**: Biarkan `true` agar DirectX & VC++ langsung terpasang.
   - **Download Mesa3D**: Centang `true` hanya jika game kamu komplain error OpenGL / GPU tidak terdeteksi.
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

## ⚠️ PENTING: Cara Tinggal AFK Agar Game Tidak Freeze!

Saat kamu sudah menyalakan game, bot, atau auto-clicker di dalam RDP dan ingin menutup aplikasi Remote Desktop di HP/PC:

> **JANGAN langsung klik tombol silang `[X]` / Disconnect di aplikasi Remote Desktop!**  
> Jika langsung ditutup, Windows akan mencopot layar virtual sehingga render game & auto-clicker macet/hitam.

**Cara yang benar:**
1. Lihat di **Desktop RDP**, klik 2x file **`AFK-Disconnect-Tanpa-Freeze.bat`**.
2. Dalam 3 detik, koneksi RDP kamu akan otomatis diputus dan sesi layar dipindahkan ke *Local Console* aktif.
3. Game, macro, dan auto-clicker akan tetap berjalan normal 100% di belakang layar!
4. Kapan pun kamu ingin mengecek progres AFK, cukup sambungkan ulang RDP seperti biasa.

### Tips Tambahan Setting Grafis Game
Karena runner GitHub menggunakan CPU 4 vCPU + 16 GB RAM tanpa GPU fisik:
- Gunakan **Windowed Mode** dengan resolusi rendah (`800x600`, `1024x768`, atau `1280x720`).
- Matikan efek berat (*Shadow*, *Anti-Aliasing*, *Bloom*, *Motion Blur*).
- Batasi **FPS Limit ke 15–30 FPS** di pengaturan in-game agar CPU tetap dingin dan stabil selama berjam-jam AFK.
- Jika sudah selesai AFK sebelum timer habis, klik 2x **`Matikan-Server-RDP.bat`** di Desktop untuk menghemat kuota menit GitHub Actions.
