#!/data/data/com.termux/files/usr/bin/lua

local VERSION      = "3.0"
local BASE_URL     = "https://ipantompal.anistioj.workers.dev"
local TMP_DIR      = os.getenv("HOME") .. "/ipantompal_tmp"
local DEST         = "/storage/emulated/0/Download"

local CACHED_FOLDERS = nil

-- ── Colors ──────────────────────────────────────────────────
local B  = "\27[1m"
local DIM= "\27[2m"
local NC = "\27[0m"
local GR = "\27[32m"
local RD = "\27[31m"
local YL = "\27[33m"
local CY = "\27[36m"

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
-- Shell-safe quoting: wraps in single quotes, escapes existing single quotes
local function shell_quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
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
            files[#files+1] = {
                name = name, id = id or "", size = tonumber(size) or 0,
                sizefmt = szf or "", tags = tags or "", description = desc or "",
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
    -- Check for error response
    local err = resp:match('"error"%s*:%s*"([^"]+)"')
    if err then
        p(RD.."  [!] API error: "..err..NC); p(""); return {}
    end
    if resp:find('"files"') then
        local files = parse_filelist(resp)
        if #files > 0 then p(GR.."  [+] Found "..#files.." files."..NC); p(""); return files end
    end
    -- Debug: show first 200 chars of response
    p(RD.."  [!] Failed to fetch file list."..NC)
    p(DIM.."      Response: "..trunc(resp, 200)..NC)
    p(""); return {}
end

local function get_download_url(file)
    if file.id and file.id ~= "" then return BASE_URL.."/dl/"..file.id.."?stream=1" end
    return nil -- no valid download URL
end

local function fetch_folders(force)
    if CACHED_FOLDERS and not force then return CACHED_FOLDERS end
    p(B.."[~] Fetching folder list..."..NC)
    local resp = exec(string.format('curl -s -L --max-time 15 "%s/api/folders?limit=100&sort=name&order=asc"', BASE_URL))
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
        if name and fid and (not pid or pid=="" or pid=="null") then
            folders[#folders+1] = { name=name, id=fid, count=tonumber(cnt) or 0, sizefmt=szf or "" }
        end
    end
    if #folders > 0 then p(GR.."  [+] Found "..#folders.." folders."..NC); p(""); CACHED_FOLDERS=folders; return folders end
    p(RD.."  [!] Failed to fetch folder list."..NC)
    p(DIM.."      Response: "..trunc(resp, 200)..NC)
    p(""); return {}
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
    p("")

    local url = get_download_url(file)
    if not url then
        p(RD.."        [!] No download URL available"..NC); p(""); return nil
    end

    exec("rm -f "..shell_quote(dest))
    exec_code(string.format('curl -L --progress-bar --max-time 600 -o %s %s 2>&1 | cat',
        shell_quote(dest), shell_quote(url)))
    restore_tty(); p("")

    -- Check file exists AND has content (> 0 bytes)
    if file_exists(dest) and file_size_bytes(dest) > 0 then
        p(GR.."        [+] Done — "..file_size(dest)..NC); p(""); return dest
    end
    -- Clean up 0-byte or partial file
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
local function scan_by_keyword(kw) local o=exec("su -c \"pm list packages "..kw.."\""); restore_tty(); local r={}; for p in o:gmatch("package:([%w%.%-%_]+)") do r[#r+1]=p end; return r end

local function do_uninstall(pkg, label)
    pr("  Removing "..B..label..NC.." ("..pkg..")... ")
    local o=exec("su -c \"pm uninstall "..pkg.."\""); restore_tty()
    if o:lower():match("success") or o:lower():match("delete") then p(GR.."[+] Done"..NC); return true
    else p(RD.."[!] Failed"..NC); return false end
end

-- Forward declaration (needed so menu_uninstall can call menu_download)
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
--   DOWNLOAD & INSTALL MENU
-- ══════════════════════════════════════════════════════════════

menu_download = function()
  while true do
    exec_code("clear 2>/dev/null"); divider(); p(B.."  Download & Install APK"..NC); divider(); p("")
    local folders = fetch_folders()
    if #folders==0 then p(RD.."  No folders available."..NC); return end

    p(B.."  Select Folder:"..NC); p("")
    for i,f in ipairs(folders) do
        local info = f.count>0 and (DIM.." ("..f.count.." files"..(f.sizefmt~="" and " / "..f.sizefmt or "")..")"..NC) or ""
        p(string.format("  "..CY.."[%d]"..NC.."  %s%s", i, f.name, info))
    end
    p(""); p("  "..CY.."[R]"..NC.."  Refresh"); p("  "..CY.."[0]"..NC.."  Back"); p(""); divider()
    pr(B.."  Choice: "..NC); local c=trim(read_line()); p("")

    if c=="0" then return end
    if c:lower()=="r" then CACHED_FOLDERS=nil -- continues while loop
    else
        local idx=tonumber(c)
        if not idx or not folders[idx] then p(RD.."  Invalid."..NC); return end
        local preset = folders[idx]
        local files = list_files(preset.id)
        if #files==0 then return end

        local apk_files = {}
        for _,f in ipairs(files) do
            if f.name:lower():find("%.apk") then apk_files[#apk_files+1]=f end
        end
        if #apk_files==0 then
            p(YL.."  No APK files. Available:"..NC)
            for _,f in ipairs(files) do p("    - "..f.name.." ("..f.sizefmt..")") end
            return
        end
        table.sort(apk_files, function(a,b) return a.name:lower()<b.name:lower() end)

        divider(); p(B.."  APK in "..preset.name..":"..NC); p("")
        for i,f in ipairs(apk_files) do
            local note = (f.description~="" and ("\n        "..DIM..trunc(f.description,50)..NC) or "")
            p(string.format("  "..CY.."[%2d]"..NC.." %-36s %s%s", i, trunc(f.name,36), f.sizefmt, note))
        end
        p(""); p("  Select APK:  Example: 1 | 1,3 | 2-4 | all")
        divider(); pr(B.."  Choice: "..NC)
        local input=trim(read_line()):gsub("\r",""); p("")

        if input=="0" or input=="" then return end

        local to_process = {}
        local sel=parse_selection(input,#apk_files)
        if #sel==0 then p(RD.."  Invalid."..NC); return end
        for _,i in ipairs(sel) do to_process[#to_process+1]=apk_files[i] end

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
            divider(); p(B.."  Summary — "..preset.name..":"..NC); p("")
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
        os.exit(0)
    end -- else (not refresh)
  end -- while
end

-- ══════════════════════════════════════════════════════════════
--   VIEW FILES
-- ══════════════════════════════════════════════════════════════
local function menu_view_files()
    exec_code("clear 2>/dev/null"); divider(); p(B.."  View File List"..NC); divider(); p("")
    local folders=fetch_folders(); if #folders==0 then p(RD.."  No folders."..NC); return end
    for i,f in ipairs(folders) do p(string.format("  "..CY.."[%d]"..NC.."  %s",i,f.name)) end
    p("  "..CY.."[0]"..NC.."  Back"); p(""); pr(B.."  Choice: "..NC)
    local pc=trim(read_line()); p(""); if pc=="0" then return end
    local pidx=tonumber(pc); if not pidx or not folders[pidx] then p(RD.."  Invalid."..NC); return end
    local files=list_files(folders[pidx].id); if #files==0 then return end
    table.sort(files, function(a,b) return a.name:lower()<b.name:lower() end)
    divider(); p(B.."  Files in "..folders[pidx].name..":"..NC); p("")
    for i,f in ipairs(files) do
        local tag = (f.tags~="" and " ["..f.tags.."]" or "")
        local note = (f.description~="" and ("\n        "..DIM..trunc(f.description,50)..NC) or "")
        p(string.format("  "..CY.."[%2d]"..NC.." %-36s %s%s%s", i, trunc(f.name,36), f.sizefmt, tag, note))
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
