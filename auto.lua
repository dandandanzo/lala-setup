#!/data/data/com.termux/files/usr/bin/lua
-- ============================================================
--   DanzoInstall Termux Manager v12
--   Website : https://danzoinstall.anistioj.workers.dev
--   Folder  : 9pxaypjv
--   Deps    : pkg install lua54 curl
-- ============================================================

local BASE_URL  = "https://danzoinstall.anistioj.workers.dev"
local R2_URL    = "https://pub-ff1d15d748904c1bb178166d90f22db5.r2.dev"
local TMP_DIR      = os.getenv("HOME") .. "/danzo_tmp"
local DEST         = "/storage/emulated/0/Download"
local COOKIE_FILE  = "/storage/emulated/0/Download/cookie.txt"
local WEBHOOK_CFG  = os.getenv("HOME") .. "/danzo_tmp/webhook.cfg"

-- ── Preset Folders ───────────────────────────────────────────
local PRESET_FOLDERS = {
    { name = "Codex",   id = "2z8whpzj" },
    { name = "Cryptic", id = "844gr7st" },
    { name = "Delta",   id = "f8ujxmej" },
    { name = "PunkX",   id = "q78znem3" },
    { name = "Ronix",   id = "dzf52ez7" },
}

-- ── Warna ───────────────────────────────────────────────────
local R  = "\27[0m"
local G  = "\27[0m"
local Y  = "\27[0m"
local B  = "\27[1m"
local CY = "\27[1m"
local NC = "\27[0m"

-- ── Print helpers ────────────────────────────────────────────
local function p(s)  io.write((s or "").."\n"); io.stdout:flush() end
local function pr(s) io.write(s or "");         io.stdout:flush() end

local function divider()
    p(CY.."  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"..NC)
end

local function trunc(s, max)
    s = s or "?"
    if #s > max then return s:sub(1, max-3).."..." end
    return s
end

local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end

-- ── FIX: baca input dari /dev/tty ────────────────────────────
local function read_line()
    io.stdout:flush()
    local tty = io.open("/dev/tty", "r")
    if tty then
        local line = tty:read("*l") or ""
        tty:close()
        return line
    end
    return io.read("*l") or ""
end

-- ── Shell ────────────────────────────────────────────────────
local function exec(cmd)
    local h = io.popen(cmd.." 2>&1 </dev/null")
    local r = h:read("*a"); h:close()
    return r or ""
end

local function exec_code(cmd) return os.execute(cmd) end

local function check_cmd(n)
    return trim(exec("command -v "..n)) ~= ""
end

local function restore_tty()
    os.execute("stty sane </dev/tty 2>/dev/null")
end

local function get_filesize(path)
    local f = io.open(path, "rb")
    if not f then return 0 end
    local s = f:seek("end") or 0; f:close(); return s
end

local function file_exists(path)
    if not path then return false end
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

local function file_size(path)
    local h = io.popen("du -h '"..path.."' | cut -f1")
    local s = h:read("*l"); h:close()
    return s or "?"
end

-- ── Banner ───────────────────────────────────────────────────
local function banner()
    exec_code("clear 2>/dev/null")
    divider()
    local title = "IPANTOOLS"
    local width = 44
    local pad = math.floor((width - #title) / 2)
    p(B..string.rep(" ", pad)..title..NC)
    divider()
end

-- ── Deps ─────────────────────────────────────────────────────
local function ensure_deps()
    p(CY.."[~] Cek dependensi..."..NC)
    if not check_cmd("curl") then
        p(R.."[✗] curl tidak ada! Jalankan: pkg install curl"..NC)
        os.exit(1)
    end
    p(G.."  [✓] curl"..NC)
    local r = exec("su -c 'id' 2>/dev/null")
    if r:find("uid=0") then
        p(G.."  [✓] Root tersedia — install tanpa popup ✓"..NC)
    else
        p(Y.."  [!] Root tidak terdeteksi"..NC)
    end
    exec_code("mkdir -p '"..TMP_DIR.."'")
    exec_code("mkdir -p '"..DEST.."'")
    p("")
end

-- ════════════════════════════════════════════════════════════
--   PARSE SELECTION (dari script user)
-- ════════════════════════════════════════════════════════════
local function parse_selection(input, max)
    input = trim(input):lower()
    if input == "all" then
        local sel = {}
        for i = 1, max do table.insert(sel, i) end
        return sel
    end
    if input == "" then return {} end
    local selected, seen = {}, {}
    for part in (input..","):gmatch("([^,]+),") do
        part = trim(part)
        local a, b = part:match("^(%d+)%-(%d+)$")
        if a and b then
            a, b = tonumber(a), tonumber(b)
            if a > b then a, b = b, a end
            for i = a, math.min(b, max) do
                if not seen[i] then table.insert(selected, i); seen[i] = true end
            end
        else
            local n = tonumber(part)
            if n and n >= 1 and n <= max and not seen[n] then
                table.insert(selected, n); seen[n] = true
            end
        end
    end
    table.sort(selected)
    return selected
end

-- ════════════════════════════════════════════════════════════
--   INSTALL APK (persis snippet user)
-- ════════════════════════════════════════════════════════════
local function install_apk(filepath, num, total)
    divider()
    if not filepath or not file_exists(filepath) then
        p(string.format("  [%d/%d] "..R.."[✗] Dilewati (download gagal)"..NC, num, total))
        p(""); return false
    end
    local name = filepath:match("([^/]+)$")
    p(string.format("  [%d/%d] 📲 "..B.."%s"..NC, num, total, trunc(name, 36)))
    pr("        Menginstall...\n")
    local out = exec("su -c \"pm install -r '"..filepath.."'\"")
    restore_tty()
    if out:lower():match("success") then
        p(G.."        [✓] Berhasil diinstall"..NC); p(""); return true
    end
    out = exec("su -c \"pm install -r -d '"..filepath.."'\"")
    restore_tty()
    if out:lower():match("success") then
        p(G.."        [✓] Berhasil diinstall"..NC); p(""); return true
    end
    p(R.."        [✗] Gagal: "..(out:match("[^\n]+$") or "?")..NC)
    p(""); return false
end

-- ════════════════════════════════════════════════════════════
--   FORWARD DECLARATION
-- ════════════════════════════════════════════════════════════
local menu_download  -- dideklarasi awal supaya menu_uninstall boleh panggil

-- ════════════════════════════════════════════════════════════
--   UNINSTALL (dari script user, dengan read_line fix)
-- ════════════════════════════════════════════════════════════
local KNOWN_PACKAGES = {
    { name = "WhatsApp",    pkg = "com.whatsapp" },
    { name = "Instagram",   pkg = "com.instagram.android" },
    { name = "TikTok",      pkg = "com.zhiliaoapp.musically" },
    { name = "Telegram",    pkg = "org.telegram.messenger" },
    { name = "YouTube",     pkg = "com.google.android.youtube" },
    { name = "Facebook",    pkg = "com.facebook.katana" },
    { name = "Snapchat",    pkg = "com.snapchat.android" },
    { name = "Twitter / X", pkg = "com.twitter.android" },
    { name = "Spotify",     pkg = "com.spotify.music" },
    { name = "Netflix",     pkg = "com.netflix.mediaclient" },
    { name = "Roblox",      pkg = "com.roblox.client" },
}

local function is_installed(pkg)
    local out = exec("su -c \"pm list packages "..pkg.."\"")
    restore_tty()
    return out:match("package:"..pkg:gsub("%-","%%%-")) ~= nil
end

local function scan_by_keyword(keyword)
    local out = exec("su -c \"pm list packages "..keyword.."\"")
    restore_tty()
    local results = {}
    for pkg in out:gmatch("package:([%w%.%-%_]+)") do
        table.insert(results, pkg)
    end
    return results
end

local function do_uninstall(pkg, label)
    pr("  Menghapus "..B..label..NC.." ("..pkg..")... ")
    local out = exec("su -c \"pm uninstall "..pkg.."\"")
    restore_tty()
    if out:lower():match("success") or out:lower():match("delete") then
        p(G.."[✓] Berhasil"..NC); return true
    else
        local err = trim(out:match("[^\n]+$") or "")
        p(R.."[✗] Gagal"..(err ~= "" and (": "..err) or "")..NC)
        return false
    end
end

local function menu_uninstall()
    exec_code("clear 2>/dev/null")
    divider()
    p(B..R.."  🗑️   Uninstall Package"..NC)
    divider(); p("")

    p(Y.."  Scanning package yang terpasang..."..NC); p("")

    local installed = {}
    local seen_pkg  = {}

    -- Scan com.roblox* otomatis
    local roblox_pkgs = scan_by_keyword("com.roblox")
    for _, pkg in ipairs(roblox_pkgs) do
        if not seen_pkg[pkg] then
            local label = pkg:gsub("com%.roblox%.","Roblox ")
                             :gsub("^%l", string.upper)
                             :gsub("%."," ")
            table.insert(installed, { name = label, pkg = pkg })
            seen_pkg[pkg] = true
        end
    end

    -- Scan KNOWN_PACKAGES lainnya
    for _, entry in ipairs(KNOWN_PACKAGES) do
        if not seen_pkg[entry.pkg] and is_installed(entry.pkg) then
            table.insert(installed, entry)
            seen_pkg[entry.pkg] = true
        end
    end

    -- Tampilkan daftar
    divider()
    p(B.."  Package yang terdeteksi:"..NC); p("")

    if #installed == 0 then
        p(Y.."  Tidak ada package yang dikenali terpasang."..NC)
    else
        for i, entry in ipairs(installed) do
            p(string.format("  %s[%2d]%s %-24s %s(%s)%s",
                CY, i, NC, entry.name, Y, entry.pkg, NC))
        end
    end

    p("")
    p(CY.."  [S]"..NC.." Scan keyword lain  (mis: com.google)")
    p(CY.."  [M]"..NC.." Masukkan package ID manual")
    p(CY.."  [0]"..NC.." Kembali ke menu utama")
    p("")
    p("  Pilih yang ingin diuninstall:")
    p(Y.."  Contoh: 1  |  1,3  |  2-4  |  all  |  S  |  M  |  0"..NC)
    divider()
    pr(B.."  Pilihan: "..NC)
    local input = trim(read_line())
    p("")

    -- Kembali
    if input == "0" then return end

    -- Scan keyword lain
    if input:lower() == "s" then
        pr(B.."  Keyword (mis: com.google): "..NC)
        local kw = trim(read_line())
        if kw == "" then p(R.."  Keyword kosong, batal."..NC); return end
        local pkgs = scan_by_keyword(kw)
        if #pkgs == 0 then
            p(Y.."  Tidak ada package yang cocok dengan: "..kw..NC); p(""); return
        end
        divider()
        p(B.."  Hasil scan '"..kw.."':"..NC); p("")
        for i, pkg in ipairs(pkgs) do
            p(string.format("  %s[%2d]%s %s", CY, i, NC, pkg))
        end
        p("")
        p(Y.."  Contoh: 1  |  1,3  |  2-4  |  all"..NC)
        divider()
        pr(B.."  Pilihan: "..NC)
        local sel_input = trim(read_line()); p("")
        local sel = parse_selection(sel_input, #pkgs)
        if #sel == 0 then p(R.."  Pilihan tidak valid."..NC); return end
        divider()
        local ok_c, fail_c = 0, 0
        for _, i in ipairs(sel) do
            if do_uninstall(pkgs[i], pkgs[i]) then ok_c = ok_c+1 else fail_c = fail_c+1 end
        end
        p("")
        p(G.."  Berhasil : "..ok_c..NC)
        p(R.."  Gagal    : "..fail_c..NC)
        divider(); p(""); return
    end

    -- Manual input
    if input:lower() == "m" then
        pr(B.."  Package ID: "..NC)
        local pkg = trim(read_line())
        if pkg == "" then p(R.."  Package ID kosong, batal."..NC); return end
        divider()
        if not is_installed(pkg) then
            p(Y.."  [!] Package tidak terpasang: "..pkg..NC)
        else
            do_uninstall(pkg, pkg)
        end
        p(""); return
    end

    -- Pilih dari daftar
    if #installed == 0 then
        p(R.."  Tidak ada package untuk diuninstall."..NC); return
    end

    local sel
    if input:lower() == "all" or input == "" then
        sel = {}
        for i = 1, #installed do table.insert(sel, i) end
    else
        sel = parse_selection(input, #installed)
    end

    if #sel == 0 then p(R.."  Pilihan tidak valid."..NC); return end

    -- Konfirmasi
    divider()
    p(R..B.."  ⚠️  Akan diuninstall:"..NC); p("")
    for _, i in ipairs(sel) do
        p("  • "..installed[i].name.." ("..installed[i].pkg..")")
    end
    p("")
    pr(Y.."  Lanjutkan? (y/n): "..NC)
    local confirm = trim(read_line()):lower(); p("")
    if confirm ~= "y" then p(Y.."  Dibatalkan."..NC); return end

    -- Proses uninstall
    divider()
    local ok_count, fail_count = 0, 0
    local roblox_uninstalled = false
    for _, i in ipairs(sel) do
        local success = do_uninstall(installed[i].pkg, installed[i].name)
        if success then
            ok_count = ok_count + 1
            if installed[i].pkg:match("com%.roblox") then
                roblox_uninstalled = true
            end
        else
            fail_count = fail_count + 1
        end
    end

    p("")
    divider()
    p(B.."  📊 Ringkasan Uninstall:"..NC); p("")
    p(G.."  Berhasil : "..ok_count..NC)
    p(R.."  Gagal    : "..fail_count..NC)
    divider(); p("")

    if roblox_uninstalled then
        p(CY.."  ✅ Roblox berjaya diuninstall!"..NC)
        p(B.."  ⏳ Masuk ke menu Download & Install..."..NC); p("")
        pr(B.."  [Enter] untuk teruskan atau tunggu 3 saat..."..NC)
        os.execute("read -t 3 < /dev/tty 2>/dev/null || sleep 3")
        p("")
        menu_download()
        return
    end
end

-- ════════════════════════════════════════════════════════════
--   DOWNLOAD & INSTALL (DanzoInstall R2)
-- ════════════════════════════════════════════════════════════
local function parse_filelist(str, folder_id)
    local files = {}
    for obj in str:gmatch("{([^{}]+)}") do
        local name = obj:match('"name"%s*:%s*"([^"]+)"')
        if name and name ~= "" then
            local id    = obj:match('"id"%s*:%s*"([^"]+)"')
            local r2key = obj:match('"r2Key"%s*:%s*"([^"]+)"')
            local size  = obj:match('"size"%s*:%s*(%d+)')
            local szfmt = obj:match('"sizeFormatted"%s*:%s*"([^"]+)"')
            if r2key then r2key = r2key:gsub("\\/", "/") end
            -- Filter: hanya file yang r2key-nya mengandung folder_id
            if not folder_id or (r2key and r2key:find(folder_id, 1, true)) then
                table.insert(files, {
                    name    = name,
                    id      = id or "",
                    r2key   = r2key or "",
                    size    = tonumber(size) or 0,
                    sizefmt = szfmt or "",
                })
            end
        end
    end
    return files
end

local function list_files(folder_id)
    if not folder_id or folder_id == "" then return {} end
    p(B.."[~] Mengambil daftar file..."..NC)
    local resp = exec(string.format(
        'curl -s -L --max-time 15 "%s/api/files?folder=%s"', BASE_URL, folder_id
    ))
    if resp:find('"files"') then
        local files = parse_filelist(resp, folder_id)
        if #files > 0 then
            p(G.."[✓] Ditemukan "..#files.." file."..NC); p("")
            return files
        end
    end
    p(R.."[✗] Gagal ambil file list."..NC); p("")
    return {}
end

local function build_r2_url(r2key)
    return R2_URL.."/"..r2key:gsub(" ","%%20")
                             :gsub("%(","%%28"):gsub("%)","%%29")
end

local function download_file(file, num, total)
    local safe = file.name:gsub("[/\\:*?\"<>|]", "_")
    local dest = DEST.."/"..safe
    exec("rm -f '"..dest.."'")

    divider()
    p(string.format("  [%d/%d] 📥 "..B.."%s"..NC, num, total, trunc(file.name, 36)))
    p(CY.."        Ukuran : "..file.sizefmt..NC)
    p("")

    local url = build_r2_url(file.r2key)

    exec_code(string.format(
        'curl -L --progress-bar --max-time 600 -o "%s" "%s" 2>&1 | cat',
        dest, url
    ))
    restore_tty()
    p("")

    if file_exists(dest) then
        p(G.."        [✓] Selesai — "..file_size(dest)..NC)
        p(""); return dest
    else
        p(R.."        [✗] Download gagal!"..NC)
        p(""); return nil
    end
end

-- ── Cek file lokal di /sdcard/Download ──────────────────────
local function find_local_apk(filename)
    local safe = filename:gsub("[/\\:*?\"<>|]", "_")
    local path = DEST.."/"..safe
    if file_exists(path) then return path end
    return nil
end

-- ── Pilih Preset Folder ──────────────────────────────────────
local function select_preset_folder()
    exec_code("clear 2>/dev/null")
    divider()
    p(B..G.."  📥  Auto Download & Install APK"..NC)
    divider(); p("")
    p(B.."  Pilih Preset Folder:"..NC); p("")

    local colors = { G, CY, Y, R }
    for i, preset in ipairs(PRESET_FOLDERS) do
        local col = colors[i] or NC
        p(string.format("  %s[%d]%s  %s", col, i, NC, preset.name))
    end
    p("")
    p(string.format("  %s[0]%s  ← Kembali ke Menu Utama", B, NC))
    p("")
    divider()
    pr(B.."  Pilihan: "..NC)
    local c = trim(read_line()); p("")

    local idx = tonumber(c)
    if c == "0" then return nil end
    if idx and PRESET_FOLDERS[idx] then
        return PRESET_FOLDERS[idx]
    end
    p(R.."  [✗] Pilihan tidak valid."..NC); p("")
    return nil
end

menu_download = function()
    -- ── 1. Pilih preset folder ───────────────────────────────
    local preset = select_preset_folder()
    if not preset then return end

    local active_folder = preset.id

    divider()
    p(B.."  Folder: "..preset.name..NC); p("")

    -- ── 2. Ambil daftar file dari folder ────────────────────
    local files = list_files(active_folder)
    if #files == 0 then return end

    local apk_files = {}
    for _, f in ipairs(files) do
        if f.name:lower():find("%.apk") then table.insert(apk_files, f) end
    end

    if #apk_files == 0 then
        p(Y.."[!] Tidak ada APK. File tersedia:"..NC)
        for _, f in ipairs(files) do p("    - "..f.name.." ("..f.sizefmt..")") end
        p(""); return
    end

    -- Urutkan A-Z
    table.sort(apk_files, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    -- ── 3. Tampilkan daftar APK untuk dipilih ───────────────
    divider()
    p(B.."  APK tersedia di "..preset.name..":"..NC); p("")
    for i, f in ipairs(apk_files) do
        p(string.format("  %s[%2d]%s %-42s %s%s%s",
            CY, i, NC, trunc(f.name, 42), Y, f.sizefmt, NC))
    end
    p("")
    p("  Pilih APK yang ingin didownload & install:")
    p(Y.."  Contoh: 1  |  1,3  |  2-4  |  all"..NC)
    divider()
    pr(B.."  Pilihan: "..NC)
    local input = trim(read_line()); p("")
    input = input:gsub("\r", "")

    if input == "0" then return end
    if input == "" then return menu_download() end

    local sel = parse_selection(input, #apk_files)
    if #sel == 0 then
        p(R.."  Pilihan tidak valid."..NC); return
    end

    local to_process = {}
    for _, i in ipairs(sel) do table.insert(to_process, apk_files[i]) end

    -- ── 4. Deteksi file pilihan yang sudah ada di /sdcard/Download ──
    local already_local = {}
    for _, f in ipairs(to_process) do
        already_local[f.name] = find_local_apk(f.name)
    end

    -- ── 5. Download yang belum ada, skip yang sudah ada ─────
    p(""); divider()
    p(B.."  📥 Proses Download ("..#to_process.." file)..."..NC); p("")
    local dl_paths = {}
    local skip_count = 0
    for i, f in ipairs(to_process) do
        local lpath = already_local[f.name]
        if lpath then
            divider()
            p(string.format("  [%d/%d] "..B.."%s"..NC, i, #to_process, trunc(f.name, 36)))
            p(B.."        [✔] File sudah ada lokal — skip download"..NC); p("")
            table.insert(dl_paths, lpath)
            skip_count = skip_count + 1
        else
            local ff = {}
            for k, v in pairs(f) do ff[k] = v end
            if ff.r2key == "" then
                ff.r2key = "folders/"..active_folder.."/"..ff.id.."/"..ff.name
            end
            table.insert(dl_paths, download_file(ff, i, #to_process))
        end
    end

    -- ── 6. Install ───────────────────────────────────────────
    divider()
    p(B.."  📲 Install ("..#to_process.." file)..."..NC); p("")
    local ok_count, fail_count = 0, 0
    local statuses = {}
    for i = 1, #to_process do
        local ok = install_apk(dl_paths[i], i, #to_process)
        if ok then ok_count = ok_count+1; table.insert(statuses, "OK")
        else        fail_count = fail_count+1; table.insert(statuses, "GAGAL") end
    end

    -- ── 7. Hapus semua file setelah proses selesai ───────────
    for i, _ in ipairs(to_process) do
        if dl_paths[i] then os.remove(dl_paths[i]) end
    end

    -- ── 7. Ringkasan ─────────────────────────────────────────
    divider()
    p(B.."  📊 Ringkasan Install — "..preset.name..":"..NC); p("")
    for i, f in ipairs(to_process) do
        if statuses[i] == "OK" then
            p(B.."  [✓] "..NC..trunc(f.name, 38))
        else
            p(B.."  [✗] "..NC..trunc(f.name, 38))
        end
    end
    p("")
    p(B.."  Berhasil   : "..ok_count..NC)
    p(B.."  Gagal      : "..fail_count..NC)
    if skip_count > 0 then
        p(B.."  Lokal skip : "..skip_count..NC)
    end
    divider(); p("")
    os.exit(0)
end


-- ════════════════════════════════════════════════════════════
--   WEBHOOK
-- ════════════════════════════════════════════════════════════
local function load_webhook()
    local f = io.open(WEBHOOK_CFG, "r")
    if not f then return "" end
    local url = trim(f:read("*l") or ""); f:close()
    return url
end

local function save_webhook(url)
    local f = io.open(WEBHOOK_CFG, "w")
    if not f then return false end
    f:write(url.."\n"); f:close()
    return true
end

local function menu_webhook()
    exec_code("clear 2>/dev/null")
    divider()
    p(B.."  📤  Kirim Cookie ke Webhook"..NC)
    divider(); p("")

    local webhook_url = load_webhook()

    -- Tampilkan URL tersimpan
    if webhook_url ~= "" then
        p(B.."  Webhook aktif:"..NC)
        p("  "..trunc(webhook_url, 55)); p("")
    else
        p(B.."  [!] Belum ada webhook URL tersimpan."..NC); p("")
    end

    p(B.."  [1]"..NC.."  Kirim cookie.txt sekarang")
    p(B.."  [2]"..NC.."  Set / Ganti Webhook URL")
    p(B.."  [0]"..NC.."  Kembali")
    p(""); divider()
    pr(B.."  Pilihan: "..NC)
    local c = trim(read_line()); p("")

    if c == "2" then
        -- Setting webhook URL
        divider()
        p(B.."  Masukkan Webhook URL:"..NC); p("")
        pr(B.."  URL: "..NC)
        local new_url = trim(read_line()); p("")
        if new_url == "" then
            p(B.."  [!] URL kosong, batal."..NC)
        elseif not new_url:match("^https?://") then
            p(B.."  [✗] URL tidak valid."..NC)
        else
            if save_webhook(new_url) then
                p(B.."  [✓] Webhook URL berhasil disimpan."..NC)
            else
                p(B.."  [✗] Gagal menyimpan URL."..NC)
            end
        end
        p(""); pr(B.."  [Enter] lanjut..."..NC); read_line()
        return menu_webhook()

    elseif c == "1" then
        -- Kirim cookie.txt
        divider()
        if webhook_url == "" then
            p(B.."  [✗] Webhook URL belum diset. Pilih [1] dulu."..NC)
            p(""); pr(B.."  [Enter] lanjut..."..NC); read_line()
            return menu_webhook()
        end

        if not file_exists(COOKIE_FILE) then
            p(B.."  [✗] File tidak ditemukan: "..COOKIE_FILE..NC)
            p(""); pr(B.."  [Enter] lanjut..."..NC); read_line()
            return menu_webhook()
        end

        -- Baca isi cookie.txt per baris
        local lines = {}
        local f = io.open(COOKIE_FILE, "r")
        for line in f:lines() do
            line = trim(line)
            if line ~= "" then table.insert(lines, line) end
        end
        f:close()

        if #lines == 0 then
            p(B.."  [!] File cookie.txt kosong."..NC)
            p(""); pr(B.."  [Enter] lanjut..."..NC); read_line()
            return menu_webhook()
        end

        p(B.."[~] Mengirim "..#lines.." baris ke webhook..."..NC); p("")

        local ok_send = true
        local ok_count_w, fail_count_w = 0, 0
        local tmp_payload = TMP_DIR.."/wh_payload.json"

        for i, line in ipairs(lines) do
            local pf = io.open(tmp_payload, "w")
            if not pf then
                p(B.."  [✗] Gagal buat file temp."..NC)
                ok_send = false; break
            end
            local escaped = line:gsub('\\', '\\\\')
                                 :gsub('"',  '\\"')
                                 :gsub('\r', '')
                                 :gsub('\t', '\\t')
            pf:write('{"content":"```\\n'..escaped..'\\n```"}')
            pf:close()

            local out = exec(string.format(
                'curl -s -o /dev/null -w "%%{http_code}" -X POST -H "Content-Type: application/json" --data-binary @"%s" "%s"',
                tmp_payload, webhook_url
            ))
            local code = trim(out)
            if code == "200" or code == "204" then
                ok_count_w = ok_count_w + 1
            else
                fail_count_w = fail_count_w + 1
                ok_send = false
                p(B.."  [✗] Baris "..i.." gagal (HTTP "..code..")"..NC)
            end
        end

        os.remove(tmp_payload)

        if ok_send then
            p(B.."  [✓] Semua "..ok_count_w.." baris berhasil dikirim!"..NC)
        else
            p(B.."  Berhasil : "..ok_count_w..NC)
            p(B.."  Gagal    : "..fail_count_w..NC)
        end
        p(""); pr(B.."  [Enter] lanjut..."..NC); read_line()
        return menu_webhook()

    elseif c == "0" then
        return
    else
        p(B.."  [✗] Pilihan tidak valid."..NC)
        p(""); pr(B.."  [Enter] lanjut..."..NC); read_line()
        return menu_webhook()
    end
end

-- ════════════════════════════════════════════════════════════
--   MAIN MENU
-- ════════════════════════════════════════════════════════════
local function main()
    banner()
    p(G .."  [1]"..NC.." 📥  Download & Install APK")
    p(R  .."  [2]"..NC.." 🗑️   Uninstall Package")
    p(Y  .."  [3]"..NC.." 📋  Lihat Daftar File")
    p(B  .."  [4]"..NC.." 📤  Kirim Cookie ke Webhook")
    p(B  .."  [0]"..NC.."     Keluar")
    p("")
    divider()
    pr(B.."  Pilihan: "..NC)
    local c = trim(read_line())

    if     c == "1" then menu_download()
    elseif c == "2" then menu_uninstall()
    elseif c == "4" then menu_webhook()
    elseif c == "3" then
        divider()
        p(B.."  Pilih Preset untuk Lihat Daftar File:"..NC); p("")
        for i, preset in ipairs(PRESET_FOLDERS) do
            p(string.format("  %s[%d]%s  %s", B, i, NC, preset.name))
        end
        p(""); pr(B.."  Pilihan: "..NC)
        local pc = trim(read_line()); p("")
        local pidx = tonumber(pc)
        if pidx and PRESET_FOLDERS[pidx] then
            local files = list_files(PRESET_FOLDERS[pidx].id)
            if #files > 0 then
                table.sort(files, function(a, b) return a.name:lower() < b.name:lower() end)
                p(B.."  File di "..PRESET_FOLDERS[pidx].name..":"..NC); p("")
                for i, f in ipairs(files) do
                    p(string.format("  %s[%2d]%s %-42s %s%s%s",
                        B, i, NC, trunc(f.name, 42), B, f.sizefmt, NC))
                end
                p("")
            end
        else
            p(R.."  [✗] Pilihan tidak valid."..NC)
        end
    elseif c == "0" then
        p(Y.."\n  Sampai jumpa!\n"..NC); os.exit(0)
    else
        p(R.."  [✗] Pilihan tidak valid."..NC)
    end

    pr(B.."  [Enter] kembali ke menu..."..NC)
    read_line()
    main()
end

-- ── Entry ────────────────────────────────────────────────────
ensure_deps()
main()
