# Minecraft Bedrock Dedicated Server

Server resmi Mojang di `itzg/minecraft-bedrock-server`, untuk Minecraft for Windows
(Bedrock) dan Minecraft Android/iOS dalam world yang sama. Semua pemain memakai
rilis Bedrock yang kompatibel, login akun Microsoft/Xbox, serta mengizinkan multiplayer
di pengaturan akun. Minecraft Java Edition membutuhkan server lain.

Default project: survival, normal, 10 pemain, autentikasi online aktif, cheats mati.
World, inventori pemain, konfigurasi, packs, serta file server tersimpan di `./data`.
Tidak ada privileged container, host networking, maupun Docker socket di container.

## 1. Networking dan versi

Ditinjau 31 Oktober 2026. BDS 1.26.50+ memakai NetherNet secara default. Changelog
26.60 menyatakan RakNet deprecated dan konfigurasi tanpa NetherNet menghasilkan error.
Project ini memakai **NetherNet**, bukan konfigurasi lama UDP 19132 saja.
Lihat [changelog Mojang 26.60](https://www.minecraft.net/nl-nl/article/minecraft--bedrock-edition-26-60-changelog),
[panduan protokol Mojang](https://mojang.github.io/bedrock-protocol-docs/guides/nether-net-onboarding-guide/),
dan [dokumentasi image](https://github.com/itzg/docker-minecraft-bedrock-server#nethernet).

| Koneksi | Default project | Keterangan |
| --- | --- | --- |
| NetherNet signaling | TCP 19132 | Port yang diisi pemain pada Add Server |
| NetherNet gameplay | UDP 19140–19155 | Satu port per koneksi; 16 port untuk 10 pemain dan reconnect |
| LAN discovery | UDP 7551 | Tidak dipakai project ini; tambahkan server melalui IP |
| RakNet lama | UDP 19132/19133 | Hanya untuk server/client lama yang masih mendukungnya |

Compose memakai bridge dengan port publishing pada Windows dan Ubuntu. Alamat
UDP yang diumumkan di `ADVERTISED_IP` harus IP yang bisa dijangkau pemain:

- Lokal: IPv4 LAN Windows dari `ipconfig`, misalnya `192.168.1.10`.
- VPS: IPv4 publik VPS, termasuk bila interface VPS sendiri mendapat IP privat.

Jangan isi IP WSL, container, `127.0.0.1`, atau hostname pada `ADVERTISED_IP` untuk
server LAN/VPS. Port host dan container dibuat sama agar alamat UDP hasil negosiasi
cocok. `UDP_PORT_RANGE` harus memiliki sedikitnya sejumlah `MAX_PLAYERS` port;
sisakan port untuk reconnect dan hindari overlap dengan `SERVER_PORT` atau layanan lain.

Untuk diagnosis versi tertentu, baca bagian Transport pada
`data/bedrock_server_how_to.html` setelah startup. Jangan mengaktifkan RakNet sebagai
solusi untuk client terbaru. Jika sengaja menjalankan BDS lama, konfigurasi NetherNet
dan healthcheck project ini perlu diganti mengikuti dokumentasi versi itu.

## 2. Menjalankan lokal: Windows 11 + Docker Desktop + WSL2

Pasang [Docker Desktop dengan WSL2](https://docs.docker.com/desktop/features/wsl/)
dan distro Ubuntu 24.04. Aktifkan Linux containers, WSL2 engine, serta WSL integration
untuk distro Ubuntu tersebut. Jadikan Ubuntu distro default untuk script PowerShell.
Jangan pasang daemon Docker kedua di distro yang memakai integrasi Docker Desktop.

Periksa di PowerShell:

```powershell
wsl --list --verbose
docker version
docker compose version
```

Di terminal Ubuntu WSL, pasang tool host yang diperlukan script:

```bash
sudo apt-get update
sudo apt-get install -y python3 util-linux
python3 --version
docker info
```

Gunakan Python 3.12+ (tersedia di Ubuntu 24.04). Script Bash dijalankan melalui WSL,
bukan Git Bash. File `.sh` harus LF; `.gitattributes` menjaganya saat checkout Git.

Di PowerShell, dari folder project ini:

```powershell
Copy-Item .env.example .env
notepad .env
ipconfig
```

Sesudah membaca [Minecraft EULA](https://www.minecraft.net/eula), isi `EULA=TRUE`.
Ganti `ADVERTISED_IP` dengan IPv4 LAN Windows yang benar. Atur reservasi DHCP di
router agar alamat tersebut stabil. `.env` tidak masuk Git.

```powershell
docker compose config --quiet
.\scripts\manage.ps1 start
.\scripts\manage.ps1 status
.\scripts\manage.ps1 logs
```

Download awal memerlukan internet dan dapat memakan beberapa menit. `Ctrl+C` pada
logs hanya menutup tampilan log. Bila kebijakan PowerShell memblokir script lokal,
jalankan `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\manage.ps1 start`
untuk proses itu saja, atau gunakan perintah Compose di bawah.

```powershell
.\scripts\manage.ps1 stop
.\scripts\manage.ps1 start
.\scripts\manage.ps1 restart
# Perintah langsung yang ekuivalen:
docker compose stop
docker compose up -d --wait --wait-timeout 600
docker compose restart
```

`stop` menyimpan world dan menghentikan container dengan grace period dua menit.
Hindari `kill`/Force Stop. Setelah mengubah `.env`, gunakan `up -d` atau `deploy`,
karena `restart` saja tidak menerapkan environment baru. Untuk upgrade gunakan
`deploy` yang membuat backup dahulu. Jangan menjalankan perintah Compose bersamaan
dengan backup, restore, atau deploy.

Bind mount `./data` bertahan saat container dihapus. Jangan hapus folder itu.
`unless-stopped` menghidupkan container setelah daemon restart, kecuali sebelumnya
dihentikan manual. Di Windows aktifkan Docker Desktop saat login; PC yang sleep,
mati, atau belum menjalankan Docker Desktop tidak melayani pemain.

## 3. Menghubungkan Windows dan HP

Minecraft → Play → Servers → Add Server:

| Pemain | Server Address | Port |
| --- | --- | --- |
| Host Windows | `127.0.0.1`, atau IPv4 LAN Windows | `19132` |
| Android/iOS satu Wi-Fi | IPv4 LAN Windows | `19132` |
| Semua pemain di VPS | IPv4 publik VPS atau domain A record | `19132` |

Masukkan alamat dan port di field terpisah. Pada HP izinkan akses local network bila
diminta. Hindari guest Wi-Fi/AP isolation. Discovery broadcast melintasi Docker
Desktop tidak dijamin, sehingga project memakai Add Server secara eksplisit.

Jika Minecraft Windows tidak dapat terhubung ke server di PC sendiri, gunakan
petunjuk loopback untuk paket Minecraft yang terpasang pada
[panduan resmi BDS](https://learn.microsoft.com/en-us/minecraft/creator/documents/bedrockserver/getting-started?view=minecraft-bedrock-stable).
Untuk paket UWP bernama `Microsoft.MinecraftUWP_8wekyb3d8bbwe`, jalankan sebagai Administrator:

```powershell
CheckNetIsolation.exe LoopbackExempt -a -n="Microsoft.MinecraftUWP_8wekyb3d8bbwe"
```

Nama paket/SID dapat berbeda pada build Windows terbaru atau Preview; ikuti panduan
resmi sesuai paket Anda. Jangan pakai Preview untuk bergabung ke server stable.

### Windows Firewall

Jalankan PowerShell Administrator pada jaringan rumah berprofil Private:

```powershell
New-NetFirewallRule -DisplayName "Bedrock NetherNet TCP" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 19132 -Profile Private -RemoteAddress LocalSubnet
New-NetFirewallRule -DisplayName "Bedrock NetherNet UDP" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 19140-19155 -Profile Private -RemoteAddress LocalSubnet
```

Sesuaikan port jika `.env` berubah dan izinkan aplikasi Docker Desktop bila Windows
meminta. Gunakan LAN Windows untuk perangkat lain, bukan IP distro WSL.
`netsh interface portproxy` hanya TCP dan tidak menyelesaikan jalur UDP NetherNet.
Tidak perlu port forwarding router untuk teman satu LAN. Internet hosting dari PC
memerlukan IP publik, forwarding TCP dan seluruh rentang UDP, serta advertised IP
publik; CGNAT atau NAT hairpin dapat menghalanginya. Gunakan VPS untuk production.

## 4. Backup dan restore

Backup otomatis maupun manual memakai cold snapshot: hentikan server dengan bersih,
pastikan exit code 0, arsipkan seluruh `data/` dan `.env`, periksa arsip, lalu hidupkan
kembali container hanya bila awalnya sedang berjalan. Pemain terputus sebentar selama
backup. File arsip `.tar.gz` baru dipublikasikan setelah validasi selesai.

```powershell
.\scripts\manage.ps1 backup
.\scripts\manage.ps1 restore -Archive .\backups\bedrock-TIMESTAMP-PID.tar.gz
```

Atau melalui Ubuntu/WSL, dari folder project:

```bash
bash scripts/backup.sh
bash scripts/restore.sh backups/bedrock-TIMESTAMP-PID.tar.gz
# Production: flag selalu sebelum nama arsip.
bash scripts/backup.sh --prod
bash scripts/restore.sh --prod backups/bedrock-TIMESTAMP-PID.tar.gz
```

Restore menolak path traversal, link, file device, arsip rusak, atau arsip tanpa
world/config. Ketik `RESTORE` untuk melanjutkan. World serta `.env` lama dipindahkan
ke `backups/pre-restore-*/`, tanpa penghapusan. Jika pergantian file gagal, script
mencoba mengembalikan data lama. Restore meninggalkan server berhenti supaya Anda
bisa meninjau IP, versi server, allowlist, dan nama world sebelum menjalankannya.
Jangan menjalankan `archive.py create/restore` langsung pada server aktif; gunakan Bash.

Arsip berisi `.env` dan mungkin identitas server, data pemain serta packs. Simpan
privat dan salin ke storage lain. Script tidak menghapus backup lama secara otomatis.
Backup di disk yang sama tidak melindungi dari kegagalan disk. Untuk migrasi/restore
pastikan ruang cukup untuk arsip terkompresi, data hasil ekstraksi, dan data lama.

Jika stop timeout/exit code bukan 0, script menolak snapshot. Periksa log dan kondisi
disk/RAM, hidupkan server sampai sehat, lalu hentikan kembali dengan bersih. Jika
backup gagal, script tetap mencoba menghidupkan kembali container yang tadi berjalan.
Lock mencegah beberapa script maintenance berjalan serentak; operator tetap harus
menghindari perubahan manual dan reboot selama operasi berlangsung.

### Jadwal lokal Windows

Contoh Task Scheduler harian pukul 04:00, menggunakan user Windows saat ini:

```powershell
$scriptPath = Join-Path $PWD 'scripts\manage.ps1'
$taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" backup"
$taskTrigger = New-ScheduledTaskTrigger -Daily -At '04:00'
$taskSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable
Register-ScheduledTask -TaskName 'MinecraftBedrockBackup' -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings
```

Docker Desktop dan sesi user harus aktif; PC sleep/mati tidak menjalankan backup.
Periksa Last Run Result pada Task Scheduler. Hindari jam bermain karena ada downtime.

## 5. Persiapan VPS

Target: Ubuntu 24.04 LTS x86_64 dengan Docker Engine dan Compose plugin. Data mesin
yang Anda kirim: 4 vCPU AMD EPYC, RAM 7.8 GiB, tanpa swap, disk 16 GB dengan sekitar
11 GB kosong. Ini titik awal yang wajar untuk world survival kecil hingga 10 pemain,
tetapi bukan jaminan performa untuk eksplorasi berat, add-on, atau farm besar.

Kernel `6.18.54-instabox` dan nama host saja belum memastikan Ubuntu, dukungan Docker,
IP publik, atau persistensi disk. `lsb_release` tidak wajib. Periksa:

```bash
cat /etc/os-release
uname -m
ps -p 1 -o comm=
docker version
docker compose version
docker info
df -h /
```

Harapkan `ID=ubuntu`, `VERSION_ID="24.04"`, arsitektur `x86_64`, dan daemon Docker
yang berfungsi. Jika ini shell dalam sandbox/container terbatas, periksa ke provider
apakah Docker, inbound TCP/UDP, systemd, disk persisten, serta layanan 24/7 didukung.
Jangan mengatasi kegagalan tersebut dengan menambahkan `privileged` ke game container.

Ikuti [instalasi Docker Engine resmi untuk Ubuntu](https://docs.docker.com/engine/install/ubuntu/).
Setelah Docker tersedia:

```bash
sudo apt-get update
sudo apt-get install -y python3 util-linux
sudo systemctl enable --now docker
```

Perintah contoh berikut menganggap user sudah punya akses Docker. Keanggotaan grup
`docker` memberikan akses setara root; ikuti pengaturan user pada dokumentasi Docker.

### Firewall VPS dan domain

Izinkan SSH terlebih dahulu supaya tidak kehilangan akses. Untuk SSH port standar:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 19132/tcp
sudo ufw allow 19140:19155/udp
sudo ufw enable
sudo ufw status
```

Jika SSH memakai port custom, izinkan port itu sebelum mengaktifkan UFW. Di firewall
provider/security group, izinkan inbound TCP 19132 dan UDP 19140–19155 ke VPS; batasi
SSH ke IP administrator jika memungkinkan. Izinkan outbound DNS, HTTPS untuk download
server/autentikasi, dan lalu lintas balasan. Sesuaikan aturan dengan port `.env`.

**Port Docker yang dipublish dapat melewati aturan UFW.** Jadikan firewall provider
sebagai pembatas eksternal; untuk filter tambahan host gunakan aturan Docker yang
sesuai backend, misalnya `DOCKER-USER` pada iptables. Jangan menganggap `ufw deny`
saja melindungi published port. Lihat
[dokumentasi firewall Docker](https://docs.docker.com/engine/network/packet-filtering-firewalls/).

Domain opsional: buat A record `mc.example.com` ke IPv4 publik VPS. Jika memakai
Cloudflare, pilih DNS only. Biarkan `ADVERTISED_IP` berisi IP literal publik.
Project ini berfokus pada IPv4; jangan menerbitkan AAAA sebelum jalur IPv6 signaling
dan gameplay diuji. Tidak perlu SRV record atau web proxy untuk koneksi IP/domain
dengan port eksplisit ini.

## 6. Migrasi lokal ke VPS tanpa kehilangan world

1. Catat versi BDS yang berjalan dari log atau `http://IP-LAN:19132/v1/join`.
   Isi versi persis itu di `BEDROCK_VERSION` sebelum snapshot terakhir, dan gunakan
   nilai image yang sama di kedua mesin (tag rilis atau digest disarankan).
2. Hentikan server lokal, lalu backup. Karena server sudah berhenti, backup tidak
   menyalakannya lagi. Jangan main lagi di world lokal setelah snapshot akhir.

```powershell
.\scripts\manage.ps1 stop
.\scripts\manage.ps1 backup
# Transfer arsip lewat SSH, ganti user/IP dan nama file.
scp .\backups\bedrock-TIMESTAMP-PID.tar.gz user@IP-VPS:~/
```

3. Salin source project melalui Git atau SCP, termasuk folder scripts dan file dot
   `.env.example`/`.gitattributes`. Jangan menyalin world yang masih aktif. Tempatkan
   project pada `/opt/minecraft-bedrock` di VPS; gunakan folder ini untuk contoh timer.

```bash
sudo mkdir -p /opt/minecraft-bedrock
sudo chown "$(id -un):$(id -gn)" /opt/minecraft-bedrock
# Salin/checkout source project ke folder tersebut terlebih dahulu.
cd /opt/minecraft-bedrock
mkdir -p data backups
cp .env.example .env
chmod 600 .env
# Isi EULA=TRUE dan ADVERTISED_IP; allowlist diperlukan untuk --prod.
nano .env
mv ~/bedrock-TIMESTAMP-PID.tar.gz backups/
bash scripts/restore.sh --prod backups/bedrock-TIMESTAMP-PID.tar.gz
```

4. Restore memulihkan `.env` lokal juga. Edit lagi `.env`: `ADVERTISED_IP=IP-PUBLIK-VPS`,
   `ALLOW_LIST_USERS=GamertagHost,GamertagTeman`, pastikan EULA dan versi yang dipin.
   Jangan mengubah `LEVEL_NAME`: nama berbeda bisa membuat world baru terlihat kosong.

```bash
nano .env
docker compose -f compose.yml -f compose.prod.yml config --quiet
bash scripts/deploy.sh --prod
docker compose -f compose.yml -f compose.prod.yml logs --tail 100
```

5. Host Windows dan HP mencoba bergabung ke IP publik/domain, memeriksa bangunan dan
   inventori yang sama. Setelah lolos, VPS menjadi satu sumber world yang dimainkan.
   Jangan menjalankan dua server aktif yang menulis folder data yang sama.

## 7. Backup otomatis production

Template systemd menjalankan backup setiap hari pukul 04:00 menurut timezone **host
VPS**, termasuk mengejar jadwal yang terlewat ketika mesin kembali hidup. `TZ` di
`.env` mengatur log container, bukan timezone timer host. Sesuaikan direktori unit
bila lokasi project berbeda. Instal unit dengan user pemilik project yang punya
akses Docker, supaya lock dan arsip tetap bisa diakses oleh operasi manual user itu.

```bash
sed "s/^User=.*/User=$(id -un)/" scripts/backup.service | sudo tee /etc/systemd/system/minecraft-bedrock-backup.service >/dev/null
sudo cp scripts/backup.timer /etc/systemd/system/minecraft-bedrock-backup.timer
sudo systemctl daemon-reload
sudo systemctl enable --now minecraft-bedrock-backup.timer
systemctl list-timers minecraft-bedrock-backup.timer
# Tes sekali; pemain akan terputus selama snapshot.
sudo systemctl start minecraft-bedrock-backup.service
sudo journalctl -u minecraft-bedrock-backup.service --no-pager -n 50
```

Backup penuh menyertakan file BDS sehingga ukurannya lebih besar daripada world saja.
Dengan sisa disk 11 GB, periksa `df -h`, `du -sh data backups`, dan `docker system df`
secara rutin, terutama setelah download/upgrade. Salin backup ke storage lain dan
hapus hanya arsip lama yang sudah Anda verifikasi aman untuk dibuang. Data rollback
`pre-restore-*` juga memakai ruang. Tidak ada pruning otomatis yang diam-diam
menghapus world atau salinan pemulihan. Pertimbangkan disk lebih besar sebelum
menyimpan riwayat panjang; server dapat rusak saat disk penuh.

## 8. Operasi production dan update

```bash
docker compose -f compose.yml -f compose.prod.yml ps
docker compose -f compose.yml -f compose.prod.yml logs -f --tail 100
docker compose -f compose.yml -f compose.prod.yml stop
docker compose -f compose.yml -f compose.prod.yml up -d --wait --wait-timeout 600
docker compose -f compose.yml -f compose.prod.yml restart
```

Production override memaksa allowlist aktif. Edit daftar gamertag di `.env` lalu
jalankan `deploy.sh --prod` untuk menerapkan perubahan. Autentikasi online tetap aktif
dan cheats tetap mati di kedua konfigurasi.

Untuk update, buat backup sebelum mengubah versi/image, ubah pin ke versi yang sesuai
client, lalu jalankan `bash scripts/deploy.sh --prod`. Deploy juga membuat snapshot
sebelum startup. `BEDROCK_VERSION=LATEST` mengecek rilis stable baru pada **setiap
startup**, termasuk setelah backup, restart atau reboot. Pin versi BDS dan image
untuk production agar update terkendali; pin image saja tidak memin server Mojang.

Jika upgrade gagal, hentikan server dan restore snapshot sebelum upgrade, lalu
kembalikan pin versi/image sebelumnya sebelum startup. Jangan menurunkan versi BDS
pada world yang sudah dibuka versi baru tanpa memulihkan backup world yang sesuai.
Deploy yang gagal tidak melakukan rollback world otomatis.

Healthcheck memeriksa HTTP NetherNet `/v1/join`, bukan ping RakNet. Status healthy
hanya membuktikan signaling di dalam container; tidak membuktikan firewall, UDP,
autentikasi atau kemampuan pemain bergabung. `unless-stopped` juga tidak otomatis
restart container hanya karena status unhealthy.

## 9. Verifikasi

Di Ubuntu/WSL dari root project:

```bash
python3 -m unittest discover -s tests -v
for script in scripts/*.sh tests/test_scripts.sh; do bash -n "$script" || exit; done
bash tests/test_scripts.sh
docker compose config --quiet
docker compose -f compose.yml -f compose.prod.yml config --quiet
```

Test script memakai Docker palsu pada folder sementara, bukan server/world Anda.
Config production memerlukan `ALLOW_LIST_USERS` terisi. Dari perangkat lain:

```bash
curl --fail http://IP-SERVER:19132/v1/join
```

Di PowerShell gunakan `curl.exe`. Respons harus JSON berisi versi dan informasi
server. Jika HTTP berhasil tetapi join gagal, periksa IP yang diumumkan, seluruh
rentang UDP, versi game, Microsoft login, izin multiplayer akun, dan allowlist.
`Test-NetConnection -Port` hanya memeriksa TCP. Uji akhir harus memakai dua client
Bedrock: Windows dan Android/iOS, termasuk akses dari luar LAN untuk VPS, serta
uji restore dan reboot. Test tanpa Docker tidak membuktikan hal-hal tersebut.

## Struktur

```text
compose.yml             # konfigurasi lokal dan dasar production
compose.prod.yml        # override allowlist production
.env.example            # contoh konfigurasi, salin menjadi .env
scripts/manage.ps1      # operasi Windows; maintenance memakai WSL
scripts/backup.sh       # cold backup manual / terjadwal
scripts/restore.sh      # restore dengan konfirmasi
scripts/deploy.sh       # pull, backup, startup dan tunggu healthcheck
scripts/common.sh       # Compose, lock, dan pemeriksaan clean stop
scripts/archive.py      # arsip aman dengan Python standard library
scripts/backup.service  # job systemd production
scripts/backup.timer    # jadwal harian production
tests/                  # uji arsip dan lifecycle script tanpa daemon Docker
data/                   # seluruh data persisten, tidak masuk Git
backups/                # arsip dan data sebelum restore, tidak masuk Git
```
