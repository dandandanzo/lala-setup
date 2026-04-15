#!/data/data/com.termux/files/usr/bin/lua

local VERSION      = "3.1"
local BASE_URL     = "https://ipantompal.anistioj.workers.dev"
local TMP_DIR      = os.getenv("HOME") .. "/ipantompal_tmp"
local DEST         = "/storage/emulated/0/Download"

local CACHED_TREE  = nil  -- all folders flat list (from tree=1)

-- ── Colors ──────────────────────────────────────────────────
local B  = "\27[1m"
local DIM= "\27[2m"
local NC = "\27[0m"
local GR = "\27[32m"
local RD = "\27[31m"
local YL = "\27[33m"
local CY = "\27[36m"
local MG = "\27[35m"

-- ── Helpers ─────────────────────────────────────────────────
local function p(s)  io.write((s or "").."\n"); io.stdout:flush() end
local function pr(s) io.write(s or "");         io.stdout:flush() end
local function divider() p(B.."  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"..NC) end
local function trunc(s, max) s=s or "?"; if #s>max then return s:sub(1,max-3).."..." end; return s end
local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end

local function read_line()
    io.stdout:flush()
    local tty = io.open("/dev/tty", "r")
    if tty then local l = tty:read("*l") or ""; tty:close(); return l end
    return io.read("*l") or ""
end

local function exec(cmd)
    local h = io.popen(cmd.." 2>&1 </dev/null"); local r = h:read("*a"); h:close(); return r or ""
end
local function exec_code(cmd) return os.execute(cmd) end
local function check_cmd(n) return trim(exec("command -v "..n)) ~= "" end
local function restore_tty() os.execute("stty sane </dev/tty 2>/dev/null") end

local function file_exists(path)
    if not path then return false end
    local f = io.open(path, "r"); if f then f:close(); return true end; return false
end
local function file_size(path)
    local h = io.popen("du -h '"..path.."' | cut -f1"); local s = h:read("*l"); h:close(); return s or "?"
end
local function file_size_bytes(path)
    local h = io.popen("stat -c%s '"..path.."' 2>/dev/null || wc -c < '"..path.."' 2>/dev/null")
    local s = h:read("*l"); h:close(); return tonumber(trim(s)) or 0
end
local function shell_quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- ── Expiry badge (colored) ──────────────────────────────────
local function expiry_tag(days, pinned)
    if pinned then return MG.."[pinned]"..NC end
    if not days then return "" end
    local n = tonumber(days)
    if not n then return "" end
    if n <= 3 then return RD.."["..n.."d left]"..NC
    elseif n <= 7 then return YL.."["..n.."d left]"..NC
    else return GR.."["..n.."d left]"..NC end
end

-- ── Banner ───────────────────────────────────────────────────
local function banner()
    exec_code("clear 2>/dev/null")
    divider()
    local t = "IPANTOOLS v"..VERSION; local w = 44
    p(B..string.rep(" ", math.floor((w-#t)/2))..t..NC)
    divider()
end

-- ── Deps ─────────────────────────────────────────────────────
local HAS_ROOT = false

local function ensure_deps()
    p(B.."[~] Checking dependencies..."..NC)
    if not check_cmd("curl") then p(RD.."  [!] curl not found! Run: pkg install curl"..NC); os.exit(1) end
    p(GR.."  [+] curl"..NC)
    if exec("su -c 'id' 2>/dev/null"):find("uid=0") then
        HAS_ROOT = true; p(GR.."  [+] Root available"..NC)
    else p(YL.."  [-] Root not detected"..NC) end
    exec_code("mkdir -p '"..TMP_DIR.."'"); exec_code("mkdir -p '"..DEST.."'"); p("")
end

-- ══════════════════════════════════════════════════════════════
--   PARSE SELECTION
-- ══════════════════════════════════════════════════════════════
local function parse_selection(input, max)
    input = trim(input):lower()
    if input == "all" then local s={}; for i=1,max do s[#s+1]=i end; return s end
    if input == "" then return {} end
    local sel, seen = {}, {}
    for part in (input..","):gmatch("([^,]+),") do
        part = trim(part)
        local a, b = part:match("^(%d+)%-(%d+)$")
        if a and b then
            a,b = tonumber(a),tonumber(b); if a>b then a,b=b,a end
            for i=a,math.min(b,max) do if not seen[i] then sel[#sel+1]=i; seen[i]=true end end
        else
            local n = tonumber(part)
            if n and n>=1 and n<=max and not seen[n] then sel[#sel+1]=n; seen[n]=true end
        end
    end
    table.sort(sel); return sel
end

-- ══════════════════════════════════════════════════════════════
--   API
-- ══════════════════════════════════════════════════════════════
local function parse_filelist(str)
    local files = {}
    for obj in str:gmatch("{([^{}]+)}") do
        local name = obj:match('"name"%s*:%s*"([^"]+)"')
        if name and name ~= "" then
            local id   = obj:match('"id"%s*:%s*"([^"]+)"')
            local size = obj:match('"size"%s*:%s*(%d+)')
            local szf  = obj:match('"sizeFormatted"%s*:%s*"([^"]+)"')
            local tags = obj:match('"tags"%s*:%s*"([^"]*)"')
            local desc = obj:match('"description"%s*:%s*"([^"]*)"')
            local expd = obj:match('"expiryDays"%s*:%s*(%d+)')
            local pinn = obj:match('"isPinned"%s*:%s*(%a+)')
            files[#files+1] = {
                name = name, id = id or "", size = tonumber(size) or 0,
                sizefmt = szf or "", tags = tags or "", description = desc or "",
                expiryDays = expd and tonumber(expd) or nil,
                isPinned = (pinn == "true"),
            }
        end
    end
    return files
end

local function list_files(folder_id)
    if not folder_id or folder_id == "" then return {} end
    p(B.."[~] Fetching file list..."..NC)
    local resp = exec(string.format('curl -s -L --max-time 15 "%s/api/files?folderId=%s&limit=100"', BASE_URL, folder_id))
    if not resp or resp == "" then
        p(RD.."  [!] No response from server."..NC); p(""); return {}
    end
    local err = resp:match('"error"%s*:%s*"([^"]+)"')
    if err then
        p(RD.."  [!] API error: "..err..NC); p(""); return {}
    end
    if resp:find('"files"') then
        local files = parse_filelist(resp)
        if #files > 0 then p(GR.."  [+] Found "..#files.." files."..NC); p(""); return files end
    end
    p(RD.."  [!] Failed to fetch file list."..NC)
    p(DIM.."      Response: "..trunc(resp, 200)..NC)
    p(""); return {}
end

local function get_download_url(file)
    if file.id and file.id ~= "" and file.name then
        local safe = file.name:gsub("[^%w%.%-_]", function(c) return string.format("%%%02X", string.byte(c)) end)
        return BASE_URL.."/dl/"..file.id.."/"..safe
    end
    return nil
end

-- ── Folder tree (single request) ─────────────────────────────
local function fetch_folder_tree(force)
    if CACHED_TREE and not force then return CACHED_TREE end
    p(B.."[~] Fetching folder tree..."..NC)
    local resp = exec(string.format('curl -s -L --max-time 15 "%s/api/folders?tree=1"', BASE_URL))
    if not resp or resp == "" then
        p(RD.."  [!] No response from server."..NC); p(""); return {}
    end
    local folders = {}
    for obj in resp:gmatch("{([^{}]+)}") do
        local name = obj:match('"name"%s*:%s*"([^"]+)"')
        local fid  = obj:match('"id"%s*:%s*"([^"]+)"')
        local pid  = obj:match('"parentId"%s*:%s*"([^"]*)"')
        local cnt  = obj:match('"fileCount"%s*:%s*(%d+)')
        local szf  = obj:match('"totalSizeFormatted"%s*:%s*"([^"]*)"')
        if name and fid then
            -- Normalize parentId: treat "", "null", nil as nil
            local parent = pid
            if not parent or parent == "" or parent == "null" then parent = nil end
            folders[#folders+1] = {
                name=name, id=fid, parentId=parent,
                count=tonumber(cnt) or 0, sizefmt=szf or ""
            }
        end
    end
    if #folders > 0 then
        p(GR.."  [+] Found "..#folders.." folders."..NC); p("")
        CACHED_TREE = folders; return folders
    end
    p(RD.."  [!] Failed to fetch folder list."..NC)
    p(DIM.."      Response: "..trunc(resp, 200)..NC)
    p(""); return {}
end

-- Get children of a parent folder (nil = root)
local function get_children(all_folders, parent_id)
    local children = {}
    for _, f in ipairs(all_folders) do
        if f.parentId == parent_id then
            children[#children+1] = f
        end
    end
    table.sort(children, function(a,b) return a.name:lower() < b.name:lower() end)
    return children
end

-- Count subfolders for a given folder
local function count_subfolders(all_folders, folder_id)
    local n = 0
    for _, f in ipairs(all_folders) do
        if f.parentId == folder_id then n = n + 1 end
    end
    return n
end

-- Build breadcrumb path string
local function build_breadcrumb(all_folders, folder_id)
    local parts = {}
    local cur = folder_id
    while cur do
        local found = false
        for _, f in ipairs(all_folders) do
            if f.id == cur then
                table.insert(parts, 1, f.name)
                cur = f.parentId
                found = true
                break
            end
        end
        if not found then break end
    end
    if #parts == 0 then return "Root" end
    return "Root > " .. table.concat(parts, " > ")
end

-- ══════════════════════════════════════════════════════════════
--   DOWNLOAD
-- ══════════════════════════════════════════════════════════════
local function download_file(file, num, total)
    local safe = file.name:gsub("[/\\:*?\"<>|']", "_")
    local dest = DEST.."/"..safe

    divider()
    p(string.format("  [%d/%d] "..B.."%s"..NC, num, total, trunc(file.name, 36)))
    p(CY.."        Size : "..file.sizefmt..NC)
    if file.description ~= "" then p(DIM.."        Note : "..trunc(file.description, 40)..NC) end
    local et = expiry_tag(file.expiryDays, file.isPinned)
    if et ~= "" then p("        Expiry: "..et) end
    p("")

    local url = get_download_url(file)
    if not url then
        p(RD.."        [!] No download URL available"..NC); p(""); return nil
    end

    exec("rm -f "..shell_quote(dest))
    exec_code(string.format('curl -L --progress-bar --max-time 600 -o %s %s 2>&1 | cat',
        shell_quote(dest), shell_quote(url)))
    restore_tty(); p("")

    if file_exists(dest) and file_size_bytes(dest) > 0 then
        p(GR.."        [+] Done — "..file_size(dest)..NC); p(""); return dest
    end
    exec("rm -f "..shell_quote(dest))
    p(RD.."        [!] Download failed!"..NC); p(""); return nil
end

-- ══════════════════════════════════════════════════════════════
--   INSTALL
-- ══════════════════════════════════════════════════════════════
local function install_apk(filepath, num, total)
    divider()
    if not filepath or not file_exists(filepath) then
        p(string.format("  [%d/%d] "..RD.."[!] Skipped (download failed)"..NC, num, total)); p(""); return false
    end
    if not HAS_ROOT then
        p(string.format("  [%d/%d] "..YL.."[!] Cannot install — root required"..NC, num, total)); p(""); return false
    end
    local name = filepath:match("([^/]+)$")
    p(string.format("  [%d/%d] Install "..B.."%s"..NC, num, total, trunc(name, 36)))
    local sq = shell_quote(filepath)
    local out = exec("su -c \"pm install -r "..sq.."\""); restore_tty()
    if out:lower():match("success") then p(GR.."        [+] Success"..NC); p(""); return true end
    out = exec("su -c \"pm install -r -d "..sq.."\""); restore_tty()
    if out:lower():match("success") then p(GR.."        [+] Success"..NC); p(""); return true end
    p(RD.."        [!] Failed: "..(out:match("[^\n]+$") or "?")..NC); p(""); return false
end

-- ══════════════════════════════════════════════════════════════
--   UNINSTALL
-- ══════════════════════════════════════════════════════════════
local KNOWN_PACKAGES = {
    { name="WhatsApp",    pkg="com.whatsapp" },
    { name="Instagram",   pkg="com.instagram.android" },
    { name="TikTok",      pkg="com.zhiliaoapp.musically" },
    { name="Telegram",    pkg="org.telegram.messenger" },
    { name="YouTube",     pkg="com.google.android.youtube" },
    { name="Facebook",    pkg="com.facebook.katana" },
    { name="Snapchat",    pkg="com.snapchat.android" },
    { name="Twitter / X", pkg="com.twitter.android" },
    { name="Spotify",     pkg="com.spotify.music" },
    { name="Netflix",     pkg="com.netflix.mediaclient" },
    { name="Roblox",      pkg="com.roblox.client" },
}

local function is_installed(pkg) local o=exec("su -c \"pm list packages "..pkg.."\""); restore_tty(); return o:match("package:"..pkg:gsub("%-","%%%-")) ~= nil end
local function scan_by_keyword(kw) local o=exec("su -c \"pm list packages "..kw.."\""); restore_tty(); local r={}; for pk in o:gmatch("package:([%w%.%-%_]+)") do r[#r+1]=pk end; return r end

local function do_uninstall(pkg, label)
    pr("  Removing "..B..label..NC.." ("..pkg..")... ")
    local o=exec("su -c \"pm uninstall "..pkg.."\""); restore_tty()
    if o:lower():match("success") or o:lower():match("delete") then p(GR.."[+] Done"..NC); return true
    else p(RD.."[!] Failed"..NC); return false end
end

-- Forward declaration
local menu_download

local function menu_uninstall()
    if not HAS_ROOT then
        divider(); p(RD.."  [!] Root required for uninstall."..NC); divider(); return
    end
    exec_code("clear 2>/dev/null"); divider(); p(B.."  Uninstall Package"..NC); divider(); p("")
    p(YL.."  Scanning installed packages..."..NC); p("")
    local installed, seen = {}, {}
    for _,pkg in ipairs(scan_by_keyword("com.roblox")) do
        if not seen[pkg] then
            installed[#installed+1] = { name=pkg:gsub("com%.roblox%.","Roblox "):gsub("^%l",string.upper):gsub("%."," "), pkg=pkg }; seen[pkg]=true
        end
    end
    for _,e in ipairs(KNOWN_PACKAGES) do if not seen[e.pkg] and is_installed(e.pkg) then installed[#installed+1]=e; seen[e.pkg]=true end end

    divider(); p(B.."  Detected packages:"..NC); p("")
    if #installed==0 then p(YL.."  No recognized packages found."..NC)
    else for i,e in ipairs(installed) do p(string.format("  "..CY.."[%2d]"..NC.." %-24s "..DIM.."(%s)"..NC, i, e.name, e.pkg)) end end
    p(""); p("  "..CY.."[S]"..NC.." Scan by keyword"); p("  "..CY.."[M]"..NC.." Enter package ID"); p("  "..CY.."[0]"..NC.." Back")
    p(""); p("  Example: 1 | 1,3 | 2-4 | all"); divider(); pr(B.."  Choice: "..NC)
    local input = trim(read_line()); p("")
    if input=="0" then return end
    if input:lower()=="s" then
        pr(B.."  Keyword: "..NC); local kw=trim(read_line()); if kw=="" then p(RD.."  Empty, cancelled."..NC); return end
        local pkgs=scan_by_keyword(kw); if #pkgs==0 then p(YL.."  No match for: "..kw..NC); return end
        divider(); p(B.."  Results for '"..kw.."':"..NC); p("")
        for i,pk in ipairs(pkgs) do p(string.format("  "..CY.."[%2d]"..NC.." %s",i,pk)) end
        p(""); pr(B.."  Choice: "..NC); local si=trim(read_line()); p(""); local sl=parse_selection(si,#pkgs)
        if #sl==0 then p(RD.."  Invalid."..NC); return end; divider()
        local ok,fl=0,0; for _,i in ipairs(sl) do if do_uninstall(pkgs[i],pkgs[i]) then ok=ok+1 else fl=fl+1 end end
        p(""); p("  Success: "..ok.."  Failed: "..fl); divider()
        p(""); p(B.."  Entering Download & Install..."..NC); p("")
        menu_download(); return
    end
    if input:lower()=="m" then
        pr(B.."  Package ID: "..NC); local pk=trim(read_line()); if pk=="" then return end
        if not is_installed(pk) then p(YL.."  Not installed: "..pk..NC); return end
        do_uninstall(pk,pk)
        p(""); p(B.."  Entering Download & Install..."..NC); p("")
        menu_download(); return
    end
    if #installed==0 then p(RD.."  Nothing to uninstall."..NC); return end
    local sel=parse_selection(input,#installed); if #sel==0 then p(RD.."  Invalid."..NC); return end
    divider(); p(RD..B.."  Will uninstall:"..NC); p("")
    for _,i in ipairs(sel) do p("  - "..installed[i].name.." ("..installed[i].pkg..")") end
    p(""); pr(YL.."  Continue? (y/n): "..NC); if trim(read_line()):lower()~="y" then p(YL.."  Cancelled."..NC); return end
    divider(); local ok,fl=0,0
    for _,i in ipairs(sel) do if do_uninstall(installed[i].pkg,installed[i].name) then ok=ok+1 else fl=fl+1 end end
    p(""); p("  Success: "..ok.."  Failed: "..fl); divider()
    p(""); p(B.."  Entering Download & Install..."..NC); p("")
    menu_download()
end

-- ══════════════════════════════════════════════════════════════
--   FOLDER BROWSER (supports subfolders)
-- ══════════════════════════════════════════════════════════════
local function browse_folders(purpose)
    -- purpose: "download" or "view"
    local all_folders = fetch_folder_tree()
    if #all_folders == 0 then p(RD.."  No folders available."..NC); return nil end

    local current_parent = nil  -- nil = root level

    while true do
        local crumb = build_breadcrumb(all_folders, current_parent)
        local children = get_children(all_folders, current_parent)

        exec_code("clear 2>/dev/null"); divider()
        p(B.."  "..(purpose=="download" and "Download & Install APK" or "View File List")..NC)
        divider()
        p(DIM.."  "..crumb..NC); p("")

        if #children == 0 and current_parent then
            -- No subfolders in this folder — return this folder for file listing
            return current_parent
        end

        p(B.."  Select Folder:"..NC); p("")
        for i, f in ipairs(children) do
            local info_parts = {}
            if f.count > 0 then info_parts[#info_parts+1] = f.count.." files" end
            if f.sizefmt ~= "" and f.sizefmt ~= "0 B" then info_parts[#info_parts+1] = f.sizefmt end
            local subs = count_subfolders(all_folders, f.id)
            if subs > 0 then info_parts[#info_parts+1] = subs.." subfolder" end
            local info = #info_parts > 0 and (DIM.." ("..table.concat(info_parts, " / ")..")"..NC) or ""
            local arrow = subs > 0 and (CY.." >"..NC) or ""
            p(string.format("  "..CY.."[%d]"..NC.."  %s%s%s", i, f.name, info, arrow))
        end

        p("")
        if current_parent then
            p("  "..CY.."[B]"..NC.."  Back to parent")
        end
        p("  "..CY.."[R]"..NC.."  Refresh")
        p("  "..CY.."[0]"..NC.."  Cancel")
        p(""); divider(); pr(B.."  Choice: "..NC)
        local c = trim(read_line()); p("")

        if c == "0" then return nil end
        if c:lower() == "r" then CACHED_TREE = nil; all_folders = fetch_folder_tree()
        elseif c:lower() == "b" and current_parent then
            -- Go back to parent
            for _, f in ipairs(all_folders) do
                if f.id == current_parent then
                    current_parent = f.parentId
                    break
                end
            end
        else
            local idx = tonumber(c)
            if idx and children[idx] then
                local selected = children[idx]
                local subs = count_subfolders(all_folders, selected.id)
                if subs > 0 then
                    -- Has subfolders — dive into it, but also offer "files in this folder"
                    exec_code("clear 2>/dev/null"); divider()
                    p(B.."  "..selected.name..NC)
                    divider(); p("")
                    p("  "..CY.."[1]"..NC.."  Browse subfolders ("..subs..")")
                    if selected.count > 0 then
                        p("  "..CY.."[2]"..NC.."  Show files in this folder ("..selected.count..")")
                    end
                    p("  "..CY.."[0]"..NC.."  Back")
                    p(""); pr(B.."  Choice: "..NC)
                    local sc = trim(read_line()); p("")
                    if sc == "1" then
                        current_parent = selected.id
                    elseif sc == "2" and selected.count > 0 then
                        return selected.id
                    end
                else
                    -- Leaf folder — return directly
                    return selected.id
                end
            else
                p(RD.."  Invalid choice."..NC)
                pr(B.."  [Enter]..."..NC); read_line()
            end
        end
    end
end

-- Get folder name by id
local function folder_name_by_id(folder_id)
    if not CACHED_TREE then return folder_id end
    for _, f in ipairs(CACHED_TREE) do
        if f.id == folder_id then return f.name end
    end
    return folder_id
end

-- ══════════════════════════════════════════════════════════════
--   DOWNLOAD & INSTALL MENU
-- ══════════════════════════════════════════════════════════════

menu_download = function()
    local folder_id = browse_folders("download")
    if not folder_id then return end

    local folder_name = folder_name_by_id(folder_id)
    local files = list_files(folder_id)
    if #files == 0 then return end

    -- Check for expiring files and warn
    local expiring = 0
    for _, f in ipairs(files) do
        if f.expiryDays and f.expiryDays <= 3 and not f.isPinned then expiring = expiring + 1 end
    end
    if expiring > 0 then
        p(RD..B.."  ⚠ "..expiring.." file akan expire dalam 3 hari!"..NC); p("")
    end

    local apk_files = {}
    for _, f in ipairs(files) do
        if f.name:lower():find("%.apk") then apk_files[#apk_files+1] = f end
    end
    if #apk_files == 0 then
        p(YL.."  No APK files. Available:"..NC)
        for _, f in ipairs(files) do
            local et = expiry_tag(f.expiryDays, f.isPinned)
            p("    - "..f.name.." ("..f.sizefmt..") "..et)
        end
        return
    end
    table.sort(apk_files, function(a,b) return a.name:lower()<b.name:lower() end)

    divider(); p(B.."  APK in "..folder_name..":"..NC); p("")
    for i, f in ipairs(apk_files) do
        local et = expiry_tag(f.expiryDays, f.isPinned)
        local note = (f.description~="" and ("\n        "..DIM..trunc(f.description,50)..NC) or "")
        p(string.format("  "..CY.."[%2d]"..NC.." %-32s %6s %s%s", i, trunc(f.name,32), f.sizefmt, et, note))
    end
    p(""); p("  Select APK:  Example: 1 | 1,3 | 2-4 | all")
    divider(); pr(B.."  Choice: "..NC)
    local input=trim(read_line()):gsub("\r",""); p("")

    if input=="0" or input=="" then return end

    local to_process = {}
    local sel=parse_selection(input,#apk_files)
    if #sel==0 then p(RD.."  Invalid."..NC); return end
    for _,i in ipairs(sel) do to_process[#to_process+1]=apk_files[i] end

    -- Warn if any selected file is about to expire
    local warn_files = {}
    for _, f in ipairs(to_process) do
        if f.expiryDays and f.expiryDays <= 3 and not f.isPinned then
            warn_files[#warn_files+1] = f.name.." ("..f.expiryDays.."d left)"
        end
    end
    if #warn_files > 0 then
        p(YL.."  ⚠ File berikut hampir expire:"..NC)
        for _, w in ipairs(warn_files) do p(RD.."    - "..w..NC) end
        p(YL.."  Download akan reset timer expiry."..NC); p("")
    end

    -- Download
    p(""); divider(); p(B.."  Downloading "..#to_process.." files..."..NC); p("")
    local dl_paths = {}
    for i,f in ipairs(to_process) do
        dl_paths[i] = download_file(f, i, #to_process)
    end

    -- Retry failed downloads once
    local failed = {}
    for i=1,#to_process do
        if not dl_paths[i] then failed[#failed+1] = i end
    end
    if #failed > 0 then
        divider(); p(YL.."  Retrying "..#failed.." failed downloads..."..NC); p("")
        for _,i in ipairs(failed) do
            dl_paths[i] = download_file(to_process[i], i, #to_process)
        end
    end

    -- Install
    if HAS_ROOT then
        divider(); p(B.."  Installing "..#to_process.." files..."..NC); p("")
        local ok_n, fail_inst = 0, 0
        local inst_st = {}
        for i=1,#to_process do
            if install_apk(dl_paths[i],i,#to_process) then
                ok_n=ok_n+1; inst_st[i]="OK"
            else
                fail_inst=fail_inst+1; inst_st[i]="FAIL"
            end
        end
        divider(); p(B.."  Summary — "..folder_name..":"..NC); p("")
        for i,f in ipairs(to_process) do
            local icon = inst_st[i]=="OK" and (GR.."[+]"..NC) or (RD.."[!]"..NC)
            p("  "..icon.." "..trunc(f.name,38))
        end
        p(""); p("  Installed : "..ok_n); p("  Failed    : "..fail_inst)
    else
        p(GR.."  [+] "..#to_process.." files downloaded to "..DEST..NC)
        p(YL.."  [!] Manual install required (no root)"..NC)
    end
    divider(); p("")
    p(GR..B.."  Done! Script terminated."..NC); p("")
    os.exit(0)
end

-- ══════════════════════════════════════════════════════════════
--   VIEW FILES
-- ══════════════════════════════════════════════════════════════
local function menu_view_files()
    local folder_id = browse_folders("view")
    if not folder_id then return end

    local folder_name = folder_name_by_id(folder_id)
    local files = list_files(folder_id)
    if #files == 0 then return end

    table.sort(files, function(a,b) return a.name:lower()<b.name:lower() end)

    -- Count expiring
    local expiring = 0
    for _, f in ipairs(files) do
        if f.expiryDays and f.expiryDays <= 7 and not f.isPinned then expiring = expiring + 1 end
    end

    divider(); p(B.."  Files in "..folder_name..":"..NC); p("")
    if expiring > 0 then
        p(YL.."  ⚠ "..expiring.." file akan expire dalam 7 hari"..NC); p("")
    end
    for i, f in ipairs(files) do
        local tag = (f.tags~="" and " ["..f.tags.."]" or "")
        local et = expiry_tag(f.expiryDays, f.isPinned)
        local note = (f.description~="" and ("\n        "..DIM..trunc(f.description,50)..NC) or "")
        p(string.format("  "..CY.."[%2d]"..NC.." %-32s %6s %s%s%s", i, trunc(f.name,32), f.sizefmt, et, tag, note))
    end; p("")
end

-- ══════════════════════════════════════════════════════════════
--   MAIN
-- ══════════════════════════════════════════════════════════════
local function main()
    while true do
        banner()
        p("  "..CY.."[1]"..NC.."  Download & Install APK")
        p("  "..CY.."[2]"..NC.."  Uninstall Package")
        p("  "..CY.."[3]"..NC.."  View File List")
        p("  "..CY.."[0]"..NC.."  Exit")
        p(""); divider(); pr(B.."  Choice: "..NC)
        local c = trim(read_line())
        if     c=="1" then menu_download()
        elseif c=="2" then menu_uninstall()
        elseif c=="3" then menu_view_files()
        elseif c=="0" then p("\n  Goodbye!\n"); os.exit(0)
        else p(RD.."  Invalid."..NC) end
        pr(B.."  [Enter] back to menu..."..NC); read_line()
    end
end

ensure_deps()
main()
