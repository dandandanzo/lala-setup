#!/data/data/com.termux/files/usr/bin/bash

# ================================================
# ROBLOX MULTI-INSTANCE TWEAK SCRIPT
# Cloud Phone Android 10 | RAM 4GB
# 5-6 Instance Optimizer
# ================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════╗"
echo "║   ROBLOX CLOUD TWEAK - 5-6 INSTANCE ║"
echo "║     Android 10 | RAM 4GB Optimizer   ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"

# ================================================
# === FIX DPKG LOCK (TAMBAHAN BARU) ===
# ================================================
fix_dpkg_lock() {
    LOCK_FILE="$PREFIX/var/lib/dpkg/lock-frontend"
    LOCK_FILE2="$PREFIX/var/lib/dpkg/lock"

    echo -e "${YELLOW}[*] Mengecek dpkg lock...${NC}"

    # Cek apakah lock file ada
    if [ -f "$LOCK_FILE" ] || [ -f "$LOCK_FILE2" ]; then

        # Cari PID yang memegang lock
        LOCK_PID=$(fuser "$LOCK_FILE" 2>/dev/null || fuser "$LOCK_FILE2" 2>/dev/null)

        if [ -n "$LOCK_PID" ]; then
            echo -e "${YELLOW}[!] Lock dipegang oleh PID: $LOCK_PID — mencoba kill...${NC}"
            kill -9 $LOCK_PID 2>/dev/null
            sleep 2

            # Cek ulang apakah masih locked
            STILL_LOCKED=$(fuser "$LOCK_FILE" 2>/dev/null || fuser "$LOCK_FILE2" 2>/dev/null)
            if [ -n "$STILL_LOCKED" ]; then
                echo -e "${RED}[!] Proses masih lock setelah kill, mencoba paksa hapus lock...${NC}"
            fi
        else
            echo -e "${YELLOW}[!] Lock file ada tapi tidak ada proses aktif — stale lock, hapus langsung...${NC}"
        fi

        # Hapus lock file
        rm -f "$LOCK_FILE" 2>/dev/null
        rm -f "$LOCK_FILE2" 2>/dev/null
        echo -e "${GREEN}[✓] Lock file dihapus${NC}"

        # Repair dpkg state
        echo -e "${YELLOW}[*] Memperbaiki dpkg state...${NC}"
        dpkg --configure -a 2>/dev/null
        echo -e "${GREEN}[✓] dpkg state diperbaiki${NC}"

    else
        echo -e "${GREEN}[✓] Tidak ada dpkg lock, lanjut...${NC}"
    fi
}

# === UPDATE & INSTALL TOOLS (dengan deteksi dependency) ===
install_tools() {
    echo -e "${YELLOW}[*] Mengecek dependency...${NC}"

    # Fix lock sebelum install apapun
    fix_dpkg_lock

    TOOLS=("procps" "htop" "lua53" "sqlite")
    MISSING=()

    for tool in "${TOOLS[@]}"; do
        if ! pkg list-installed 2>/dev/null | grep -q "^$tool"; then
            MISSING+=("$tool")
            echo -e "${RED}[✗] $tool belum terinstall${NC}"
        else
            echo -e "${GREEN}[✓] $tool sudah terinstall, skip${NC}"
        fi
    done

    if [ ! -d "$HOME/storage" ]; then
        echo -e "${RED}[✗] Storage permission belum disetup${NC}"
        echo -e "${YELLOW}[*] Menjalankan termux-setup-storage...${NC}"
        termux-setup-storage
        echo -e "${GREEN}[✓] Storage permission selesai${NC}"
    else
        echo -e "${GREEN}[✓] Storage sudah disetup, skip${NC}"
    fi

    if [ ${#MISSING[@]} -eq 0 ]; then
        echo -e "${GREEN}[✓] Semua dependency sudah lengkap, skip install${NC}"
    else
        echo -e "${YELLOW}[*] Menginstall: ${MISSING[*]}...${NC}"

        # Retry loop jika masih ada lock saat install
        MAX_RETRY=3
        RETRY=0
        SUCCESS=false

        while [ $RETRY -lt $MAX_RETRY ]; do
            pkg update -y -q && pkg upgrade -y -q && pkg install -y -q "${MISSING[@]}"
            if [ $? -eq 0 ]; then
                SUCCESS=true
                break
            else
                RETRY=$((RETRY + 1))
                echo -e "${YELLOW}[!] Install gagal (percobaan $RETRY/$MAX_RETRY), fix lock lagi...${NC}"
                fix_dpkg_lock
                sleep 2
            fi
        done

        if $SUCCESS; then
            echo -e "${GREEN}[✓] Semua dependency berhasil diinstall${NC}"
        else
            echo -e "${RED}[✗] Gagal install setelah $MAX_RETRY percobaan. Cek koneksi atau jalankan ulang.${NC}"
        fi
    fi
}

# === KILL PROSES TIDAK PENTING ===
kill_bloat() {
    echo -e "${YELLOW}[*] Membersihkan proses bloatware...${NC}"

    BLOAT_APPS=(
        "com.google.android.youtube"
        "com.google.android.apps.maps"
        "com.google.android.gm"
        "com.android.calendar"
        "com.android.browser"
        "com.android.email"
        "com.google.android.music"
        "com.android.wallpaper"
        "com.android.stk"
    )

    for app in "${BLOAT_APPS[@]}"; do
        su -c "am force-stop $app" 2>/dev/null
    done

    echo -e "${GREEN}[✓] Bloatware dihentikan${NC}"
}

# === DISABLE ANIMASI ===
disable_animations() {
    echo -e "${YELLOW}[*] Menonaktifkan animasi sistem...${NC}"

    su -c "settings put global window_animation_scale 0"
    su -c "settings put global transition_animation_scale 0"
    su -c "settings put global animator_duration_scale 0"
    su -c "settings put global fancy_ime_animations 0" 2>/dev/null
    su -c "settings put global dismiss_keyguard_on_sim_restore 0" 2>/dev/null
    su -c "settings put system notification_animation 0" 2>/dev/null

    echo -e "${GREEN}[✓] Semua animasi dinonaktifkan${NC}"
}

# === ENABLE ANIMASI (restore) ===
enable_animations() {
    echo -e "${YELLOW}[*] Mengembalikan animasi sistem...${NC}"

    su -c "settings put global window_animation_scale 1"
    su -c "settings put global transition_animation_scale 1"
    su -c "settings put global animator_duration_scale 1"
    su -c "settings put global fancy_ime_animations 1" 2>/dev/null
    su -c "settings put system notification_animation 1" 2>/dev/null

    echo -e "${GREEN}[✓] Animasi dikembalikan ke normal${NC}"
}

# === OPTIMIZE MEMORY ===
optimize_memory() {
    echo -e "${YELLOW}[*] Optimasi memori untuk 5-6 instance...${NC}"

    su -c "echo 3 > /proc/sys/vm/drop_caches"
    su -c "echo 10 > /proc/sys/vm/swappiness"
    su -c "echo 10 > /proc/sys/vm/dirty_ratio"
    su -c "echo 5 > /proc/sys/vm/dirty_background_ratio"
    su -c "echo 524288 > /proc/sys/fs/inotify/max_user_watches"
    su -c "echo 524288 > /proc/sys/fs/inotify/max_queued_events"
    su -c "echo 1024 > /proc/sys/fs/inotify/max_user_instances"
    su -c "echo 50 > /proc/sys/vm/vfs_cache_pressure"
    su -c "echo 204800 > /proc/sys/vm/min_free_kbytes"

    echo -e "${GREEN}[✓] Memory dioptimasi${NC}"
}

# === OPTIMIZE CPU ===
optimize_cpu() {
    echo -e "${YELLOW}[*] Optimasi CPU governor...${NC}"

    CPU_COUNT=$(nproc)

    for i in $(seq 0 $((CPU_COUNT-1))); do
        CPU_PATH="/sys/devices/system/cpu/cpu$i/cpufreq"

        if [ -d "$CPU_PATH" ]; then
            if echo "schedutil" | su -c "tee $CPU_PATH/scaling_governor" 2>/dev/null; then
                :
            elif echo "interactive" | su -c "tee $CPU_PATH/scaling_governor" 2>/dev/null; then
                :
            fi

            MAX_FREQ=$(su -c "cat $CPU_PATH/cpuinfo_max_freq" 2>/dev/null)
            if [ -n "$MAX_FREQ" ]; then
                su -c "echo $MAX_FREQ > $CPU_PATH/scaling_max_freq" 2>/dev/null
            fi
        fi
    done

    echo -e "${GREEN}[✓] CPU dioptimasi (${CPU_COUNT} core)${NC}"
}

# === OPTIMIZE GPU ===
optimize_gpu() {
    echo -e "${YELLOW}[*] Optimasi GPU...${NC}"

    GPU_PATHS=(
        "/sys/class/kgsl/kgsl-3d0/devfreq"
        "/sys/class/misc/mali0/device"
        "/sys/kernel/gpu"
    )

    for GPU_PATH in "${GPU_PATHS[@]}"; do
        if [ -d "$GPU_PATH" ]; then
            su -c "echo performance > $GPU_PATH/governor" 2>/dev/null
            su -c "echo 1 > $GPU_PATH/force_clk_on" 2>/dev/null
        fi
    done

    su -c "echo 0 > /sys/class/kgsl/kgsl-3d0/throttling" 2>/dev/null

    echo -e "${GREEN}[✓] GPU dioptimasi${NC}"
}

# === OPTIMIZE NETWORK ===
optimize_network() {
    echo -e "${YELLOW}[*] Optimasi jaringan untuk multi-instance...${NC}"

    su -c "echo 1 > /proc/sys/net/ipv4/tcp_fastopen"
    su -c "echo 1 > /proc/sys/net/ipv4/tcp_low_latency"
    su -c "echo bbr > /proc/sys/net/ipv4/tcp_congestion_control" 2>/dev/null || \
    su -c "echo cubic > /proc/sys/net/ipv4/tcp_congestion_control" 2>/dev/null
    su -c "echo '4096 87380 16777216' > /proc/sys/net/ipv4/tcp_rmem"
    su -c "echo '4096 65536 16777216' > /proc/sys/net/ipv4/tcp_wmem"
    su -c "echo 16777216 > /proc/sys/net/core/rmem_max"
    su -c "echo 16777216 > /proc/sys/net/core/wmem_max"

    echo -e "${GREEN}[✓] Jaringan dioptimasi${NC}"
}

# === SET ROBLOX PRIORITY (AUTO DETECT) ===
set_roblox_priority() {
    echo -e "${YELLOW}[*] Mendeteksi package Roblox...${NC}"

    ROBLOX_PACKAGES=$(su -c "pm list packages" 2>/dev/null | grep "com.roblox" | sed 's/package://')

    if [ -z "$ROBLOX_PACKAGES" ]; then
        echo -e "${RED}[!] Tidak ada package Roblox ditemukan di device!${NC}"
        return
    fi

    echo -e "${GREEN}[✓] Package ditemukan:${NC}"
    echo "$ROBLOX_PACKAGES"

    for PKG in $ROBLOX_PACKAGES; do
        echo -e "${YELLOW}[*] Mengatur prioritas: $PKG${NC}"

        PIDS=$(su -c "pidof $PKG" 2>/dev/null)

        if [ -z "$PIDS" ]; then
            echo -e "${YELLOW}[!] $PKG belum berjalan, skip...${NC}"
            continue
        fi

        for PID in $PIDS; do
            su -c "renice -10 -p $PID" 2>/dev/null
            su -c "chrt -f -p 10 $PID" 2>/dev/null
            su -c "echo -500 > /proc/$PID/oom_score_adj" 2>/dev/null
            echo -e "${GREEN}[✓] PID $PID ($PKG) prioritas ditingkatkan${NC}"
        done
    done
}

# === DISABLE SERVICES TIDAK PENTING ===
disable_services() {
    echo -e "${YELLOW}[*] Menonaktifkan service tidak penting...${NC}"

    SERVICES=(
        "logd"
        "statsd"
        "traced"
        "perfetto"
        "mdnsd"
    )

    for svc in "${SERVICES[@]}"; do
        su -c "stop $svc" 2>/dev/null
    done

    echo -e "${GREEN}[✓] Services dihentikan${NC}"
}

# === MONITOR RAM LIVE ===
monitor_ram() {
    echo -e "${CYAN}[*] Monitor RAM (tekan Ctrl+C untuk berhenti)...${NC}"

    while true; do
        TOTAL=$(cat /proc/meminfo | grep MemTotal | awk '{print $2}')
        FREE=$(cat /proc/meminfo | grep MemAvailable | awk '{print $2}')
        USED=$((TOTAL - FREE))
        PERCENT=$((USED * 100 / TOTAL))

        TOTAL_MB=$((TOTAL / 1024))
        FREE_MB=$((FREE / 1024))
        USED_MB=$((USED / 1024))

        echo -ne "\r${CYAN}RAM: ${USED_MB}MB / ${TOTAL_MB}MB dipakai (${PERCENT}%) | Free: ${FREE_MB}MB${NC}   "
        sleep 2
    done
}

# === AUTO CLEAN MEMORY ===
auto_clean_memory() {
    echo -e "${YELLOW}[*] Menjalankan auto memory cleaner (background)...${NC}"

    EXISTING_PID=$(pgrep -f "mem_cleaner.sh")
    if [ -n "$EXISTING_PID" ]; then
        echo -e "${GREEN}[✓] Auto cleaner sudah berjalan (PID: $EXISTING_PID), skip${NC}"
        return
    fi

    cat > "$HOME/mem_cleaner.sh" << 'CLEANER'
#!/data/data/com.termux/files/usr/bin/bash

while true; do
    FREE=$(cat /proc/meminfo | grep MemAvailable | awk '{print $2}')
    FREE_MB=$((FREE / 1024))

    if [ $FREE_MB -lt 400 ]; then
        su -c "echo 1 > /proc/sys/vm/drop_caches" 2>/dev/null
        echo "$(date): Cache dibersihkan, free RAM: ${FREE_MB}MB"
    fi

    sleep 30
done
CLEANER

    chmod +x "$HOME/mem_cleaner.sh"
    nohup bash "$HOME/mem_cleaner.sh" > "$HOME/mem_clean.log" 2>&1 &
    echo -e "${GREEN}[✓] Auto cleaner berjalan (PID: $!)${NC}"
}

# === EXIT SCRIPT ===
exit_script() {
    echo ""
    echo -e "${YELLOW}[*] Keluar dari script...${NC}"

    CLEANER_PID=$(pgrep -f "mem_cleaner.sh")
    if [ -n "$CLEANER_PID" ]; then
        echo -e "${GREEN}[✓] Auto memory cleaner tetap berjalan di background (PID: $CLEANER_PID)${NC}"
        echo -e "${CYAN}[i] Lihat log cleaner: tail -f $HOME/mem_clean.log${NC}"
    else
        echo -e "${CYAN}[i] Auto memory cleaner tidak berjalan${NC}"
    fi

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         INFO SETELAH EXIT                ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║ ✅ Tweak kernel/memory → masih aktif     ║${NC}"
    echo -e "${CYAN}║ ✅ Animasi nonaktif → masih nonaktif     ║${NC}"
    echo -e "${CYAN}║ ✅ Prioritas Roblox → masih aktif        ║${NC}"
    echo -e "${CYAN}║ ✅ Auto memory cleaner → tetap jalan     ║${NC}"
    echo -e "${CYAN}║ ⚠️  Semua reset otomatis saat reboot     ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}Keluar dari script. Selamat bermain Roblox!${NC}"
    exit 0
}

# === HELPER: JALANKAN STEP DENGAN SPINNER & TUNGGU SELESAI ===
run_step() {
    local LABEL="$1"
    local FUNC="$2"
    local SPIN='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    echo -e "\n${CYAN}┌─────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ▶ Langkah: ${LABEL}${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────┘${NC}"

    # Jalankan fungsi di subshell background, sembunyikan output
    ($FUNC) > /dev/null 2>&1 &
    local STEP_PID=$!

    # Spinner selama proses berjalan
    while kill -0 $STEP_PID 2>/dev/null; do
        i=$(( (i+1) % ${#SPIN} ))
        echo -ne "\r${YELLOW}  [${SPIN:$i:1}] Menunggu ${LABEL} selesai...${NC}   "
        sleep 0.15
    done

    # Tunggu dan ambil exit code
    wait $STEP_PID
    local STATUS=$?

    # Hapus baris spinner, ganti dengan status final
    echo -ne "\r                                                  \r"

    if [ $STATUS -eq 0 ]; then
        echo -e "${GREEN}  [✓] ${LABEL} → SELESAI${NC}"
    else
        echo -e "${RED}  [✗] ${LABEL} → GAGAL (exit: $STATUS), lanjut ke langkah berikutnya...${NC}"
    fi

    sleep 0.5
    return $STATUS
}

# === FULL OPTIMIZE ===
full_optimize() {
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════╗"
    echo "║     MEMULAI FULL OPTIMIZATION...     ║"
    echo "╚══════════════════════════════════════╝"
    echo -e "${NC}"

    TOTAL=8
    CURRENT=0

    step_progress() {
        CURRENT=$((CURRENT+1))
        echo -e "${CYAN}  [Step $CURRENT/$TOTAL]${NC}"
    }

    step_progress; run_step "Kill Bloatware"     kill_bloat
    step_progress; run_step "Disable Animasi"    disable_animations
    step_progress; run_step "Optimasi Memory"    optimize_memory
    step_progress; run_step "Optimasi CPU"       optimize_cpu
    step_progress; run_step "Optimasi GPU"       optimize_gpu
    step_progress; run_step "Optimasi Network"   optimize_network
    step_progress; run_step "Disable Services"   disable_services
    step_progress; run_step "Auto Clean Memory"  auto_clean_memory

    # set_roblox_priority dijalankan terakhir langsung (butuh Roblox sudah berjalan)
    echo -e "\n${CYAN}┌─────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ ▶ [Step 9/9] Set Roblox Priority        │${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────┘${NC}"
    set_roblox_priority

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       ✓ SEMUA LANGKAH SELESAI!       ║${NC}"
    echo -e "${GREEN}║   Siap untuk 5-6 instance Roblox     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
}

# === MAIN MENU ===
show_menu() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           MAIN MENU            ║${NC}"
    echo -e "${CYAN}╠════════════════════════════════╣${NC}"
    echo -e "${CYAN}║ 1.  Full Optimize (Auto)       ║${NC}"
    echo -e "${CYAN}║ 2.  Optimize Memory Only       ║${NC}"
    echo -e "${CYAN}║ 3.  Optimize CPU/GPU           ║${NC}"
    echo -e "${CYAN}║ 4.  Set Roblox Priority        ║${NC}"
    echo -e "${CYAN}║ 5.  Monitor RAM Live           ║${NC}"
    echo -e "${CYAN}║ 6.  Disable Animasi            ║${NC}"
    echo -e "${CYAN}║ 7.  Enable Animasi             ║${NC}"
    echo -e "${CYAN}║ 8.  Cek & Install Tools        ║${NC}"
    echo -e "${CYAN}║ 9.  Fix dpkg Lock              ║${NC}"
    echo -e "${CYAN}║ 0.  Keluar                     ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════╝${NC}"
    echo -ne "Pilih [0-9]: "
}

# === RUN SCRIPT ===
if [ "$1" == "--auto" ]; then
    full_optimize
    exit 0
fi

install_tools

while true; do
    show_menu
    read -r CHOICE
    case $CHOICE in
        1) full_optimize ;;
        2) optimize_memory ;;
        3) optimize_cpu; optimize_gpu ;;
        4) set_roblox_priority ;;
        5) monitor_ram ;;
        6) disable_animations ;;
        7) enable_animations ;;
        8) install_tools ;;
        9) fix_dpkg_lock ;;
        0) exit_script ;;
        *) echo -e "${RED}Pilihan tidak valid${NC}" ;;
    esac
done
