--// ═══════════════════════════════════════════
--//   Auto Mail — Diamonds + Huge Pets v4
--// ═══════════════════════════════════════════

if not game:IsLoaded() then game.Loaded:Wait() end

--// CONFIG
getgenv().MailConfig = {
    Enabled         = true,
    Target          = "jrdntio",

    -- Diamonds
    SendDiamonds    = true,
    SendPercent     = 0.5,
    MinDiamonds     = 2000000,
    KeepDiamonds    = 500000,
    MaxSendAmount   = 50000000,

    -- Pets
    SendHugePets    = true,
    PetFilters      = {"Huge", "Titanic"},  -- kirim pet yang mengandung nama ini
    KeepEquipped    = true,
    KeepFavorited   = true,
    KeepLocked      = true,
    KeepGolden      = true,                 -- jangan kirim Golden variant
    KeepRainbow     = true,                 -- jangan kirim Rainbow variant
    KeepShiny       = true,                 -- jangan kirim Shiny variant
    MaxPetsPerCycle = 10,
    PetSendDelay    = 1.5,
    PetMessage      = "",                   -- message saat kirim pet

    -- Timing
    Interval        = 43200,
    PetCheckInterval = 60,
    CheckDelay      = 30,
    RetryDelay      = 60,
    MaxRetries      = 3,
    LogHistory      = true,
}

local SAVE_FILE = "ps99_mail_timer.txt"
local LOG_FILE  = "ps99_mail_log.txt"

--// SERVICES
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local Network = RS:WaitForChild("Network", 30)
local Library = RS:WaitForChild("Library", 30)

--// REMOTES
local mailRemote = Network and Network:FindFirstChild("Mailbox: Send")
local petsGetEquipped = Network and Network:FindFirstChild("Pets_GetEquipped")

--// MODULES
local CurrencyCmds, Save, PetCmds, InventoryCmds, PetsDir

pcall(function() CurrencyCmds = require(Library.Client.CurrencyCmds) end)
pcall(function() Save = require(Library.Client.Save) end)
pcall(function() PetCmds = require(Library.Client.PetCmds) end)
pcall(function() InventoryCmds = require(Library.Client.InventoryCmds) end)
pcall(function() PetsDir = require(Library.Directory.Pets) end)

--// STATE
local state = {
    lastSend = 0, totalSent = 0, sendCount = 0,
    petsSent = 0, failCount = 0, startTime = os.clock(),
}

local function mcfg() return getgenv().MailConfig end

--// ═══════════════════════════════════════════
--//       FILE SYSTEM
--// ═══════════════════════════════════════════

local function fileExists(p) local ok, r = pcall(isfile, p); return ok and r end
local function loadLastSend()
    if fileExists(SAVE_FILE) then
        local ok, d = pcall(readfile, SAVE_FILE); if ok then return tonumber(d) or 0 end
    end; return 0
end
local function saveLastSend(t) pcall(writefile, SAVE_FILE, tostring(t)) end
local function appendLog(msg)
    if not mcfg().LogHistory then return end
    pcall(function()
        local e = fileExists(LOG_FILE) and readfile(LOG_FILE) or ""
        writefile(LOG_FILE, e .. string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), msg))
    end)
end

state.lastSend = loadLastSend()

--// ═══════════════════════════════════════════
--//       UTILITY
--// ═══════════════════════════════════════════

local function formatNum(n)
    if n >= 1e12 then return string.format("%.2fT", n/1e12)
    elseif n >= 1e9 then return string.format("%.2fB", n/1e9)
    elseif n >= 1e6 then return string.format("%.2fM", n/1e6)
    elseif n >= 1e3 then return string.format("%.1fK", n/1e3)
    else return tostring(math.floor(n)) end
end

local function formatTime(s)
    if s <= 0 then return "ready" end
    local h, m = math.floor(s/3600), math.floor((s%3600)/60)
    if h > 0 then return string.format("%dh %dm", h, m)
    elseif m > 0 then return string.format("%dm %ds", m, s%60)
    else return string.format("%ds", s) end
end

local function parseNumber(text)
    if not text then return 0 end
    text = tostring(text):lower():gsub("[, ]", "")
    local num = tonumber(text:match("[%d%.]+"))
    if not num then return 0 end
    if text:find("t") then return num*1e12 elseif text:find("b") then return num*1e9
    elseif text:find("m") then return num*1e6 elseif text:find("k") then return num*1e3
    else return num end
end

local function getToken()
    return player:GetAttribute("SessionToken")
end

local function getTimeRemaining()
    return math.max(mcfg().Interval - (os.time() - state.lastSend), 0)
end

--// ═══════════════════════════════════════════
--//       GET DIAMONDS
--// ═══════════════════════════════════════════

local function getDiamonds()
    if CurrencyCmds and CurrencyCmds.Get then
        local ok, r = pcall(CurrencyCmds.Get, "Diamonds")
        if ok and type(r) == "number" and r > 0 then return r end
    end
    local ls = player:FindFirstChild("leaderstats")
    if ls then local d = ls:FindFirstChild("💎 Diamonds"); if d then return d.Value end end
    local gui = player:FindFirstChild("PlayerGui")
    if gui then
        local ok, v = pcall(function() return gui.MainLeft.Left.Currency.Diamonds.Diamonds.Amount.Text end)
        if ok then return parseNumber(v) end
    end
    return 0
end

--// ═══════════════════════════════════════════
--//       PET SYSTEM — GET ALL PETS
--// ═══════════════════════════════════════════

-- Dapet SEMUA pet dari inventory (multiple methods)
local function getAllPets()
    local pets = {}

    -- Method 1: Save.Get() → paling lengkap, ada UID sebagai key
    if Save and Save.Get then
        pcall(function()
            local saves = Save.Get()
            if type(saves) == "table" then
                -- Cari pet table
                local petTable = saves.Pets or saves.pets or saves.PetInventory
                if type(petTable) == "table" then
                    for uid, data in pairs(petTable) do
                        if type(data) == "table" then
                            table.insert(pets, {
                                UID = tostring(uid),
                                Id = data.id or data.Id or data.ID or "",
                                Locked = data.locked or data.Locked or false,
                                Favorited = data.fav or data.Favorited or data.favorited or false,
                                Shiny = data.sh or data.Shiny or data.shiny or false,
                                Golden = data.pt or data.Golden or data.golden or 0,
                                _raw = data,
                            })
                        end
                    end
                end
            end
        end)
    end

    if #pets > 0 then
        print(string.format("[PetScan] Found %d pets via Save", #pets))
        return pets
    end

    -- Method 2: PetCmds.GetSortedPets()
    if PetCmds then
        pcall(function()
            local fn = PetCmds.GetSortedPets or PetCmds.GetDamageSortedPets
            if fn then
                local sorted = fn()
                if type(sorted) == "table" then
                    for _, petData in ipairs(sorted) do
                        if type(petData) == "table" then
                            local uid = petData.uid or petData.UID or petData.uniqueId
                            local id = petData.id or petData.Id
                            if uid then
                                table.insert(pets, {
                                    UID = tostring(uid),
                                    Id = id or "",
                                    Locked = petData.locked or false,
                                    Favorited = petData.fav or petData.favorited or false,
                                    Shiny = petData.sh or petData.shiny or false,
                                    Golden = petData.pt or petData.golden or 0,
                                    _raw = petData,
                                })
                            end
                        end
                    end
                end
            end
        end)
    end

    if #pets > 0 then
        print(string.format("[PetScan] Found %d pets via PetCmds", #pets))
        return pets
    end

    -- Method 3: InventoryCmds.Container("Pet")
    if InventoryCmds and InventoryCmds.Container then
        pcall(function()
            local container = InventoryCmds.Container("Pet")
            if container then
                -- Coba GetAll, All, Items, dll
                local items = nil
                if type(container) == "table" then
                    if container.GetAll then items = container:GetAll()
                    elseif container.All then items = container:All()
                    elseif container.Items then items = container.Items
                    else items = container end
                end

                if type(items) == "table" then
                    for uid, data in pairs(items) do
                        if type(data) == "table" then
                            table.insert(pets, {
                                UID = tostring(uid),
                                Id = data.id or data.Id or "",
                                Locked = data.locked or false,
                                Favorited = data.fav or false,
                                Shiny = data.sh or data.shiny or false,
                                Golden = data.pt or data.golden or 0,
                                _raw = data,
                            })
                        end
                    end
                end
            end
        end)
    end

    if #pets > 0 then
        print(string.format("[PetScan] Found %d pets via InventoryCmds", #pets))
    else
        warn("[PetScan] Could not find pets from any method!")
    end

    return pets
end

-- Dapet equipped pet UIDs
local function getEquippedUIDs()
    local equipped = {}

    -- Method 1: PetCmds.GetEquipped()
    if PetCmds and PetCmds.GetEquipped then
        pcall(function()
            local result = PetCmds.GetEquipped()
            if type(result) == "table" then
                for uid, _ in pairs(result) do
                    equipped[tostring(uid)] = true
                end
            end
        end)
    end

    -- Method 2: Remote
    if not next(equipped) and petsGetEquipped then
        pcall(function()
            local result = petsGetEquipped:InvokeServer()
            if type(result) == "table" then
                for uid, _ in pairs(result) do
                    equipped[tostring(uid)] = true
                end
            end
        end)
    end

    return equipped
end

-- Dapet pet display name dari Directory
local function getPetName(petId)
    if not petId or petId == "" then return "Unknown" end
    if PetsDir then
        local data = PetsDir[petId]
        if data then return data.Name or petId end
    end
    return petId
end

-- Cek apakah pet name match salah satu filter
local function matchesFilter(petName)
    if not petName then return false end
    local lower = petName:lower()
    for _, filter in ipairs(mcfg().PetFilters) do
        if lower:find(filter:lower()) then
            return true
        end
    end
    return false
end

-- Helper: detect variant type
local function getVariant(pet)
    -- pt = 1 → Golden, pt = 2 → Rainbow
    -- sh = true → Shiny
    -- Combination: Golden + Shiny, Rainbow + Shiny, etc.
    local golden = (pet.Golden == 1) or (pet.Golden == true)
    local rainbow = (pet.Golden == 2)
    local shiny = (pet.Shiny == true) or (pet.Shiny == 1)
    return golden, rainbow, shiny
end

local function getVariantTag(pet)
    local golden, rainbow, shiny = getVariant(pet)
    local tags = {}
    if rainbow then table.insert(tags, "RAINBOW") end
    if golden then table.insert(tags, "GOLDEN") end
    if shiny then table.insert(tags, "SHINY") end
    if #tags == 0 then return "NORMAL" end
    return table.concat(tags, "+")
end

-- MAIN: dapet huge/titanic pets yang TIDAK di-equip dan bukan variant yang dilindungi
local function getSendablePets()
    local allPets = getAllPets()
    local equipped = getEquippedUIDs()

    local sendable = {}

    for _, pet in ipairs(allPets) do
        local name = getPetName(pet.Id)

        if matchesFilter(name) then
            local skip = false
            local reason = nil

            -- Status protection
            if mcfg().KeepEquipped and equipped[pet.UID] then skip = true; reason = "equipped" end
            if mcfg().KeepFavorited and pet.Favorited then skip = true; reason = "favorited" end
            if mcfg().KeepLocked and pet.Locked then skip = true; reason = "locked" end

            -- Variant protection
            local golden, rainbow, shiny = getVariant(pet)
            if mcfg().KeepGolden and golden then skip = true; reason = "golden" end
            if mcfg().KeepRainbow and rainbow then skip = true; reason = "rainbow" end
            if mcfg().KeepShiny and shiny then skip = true; reason = "shiny" end

            if not skip then
                table.insert(sendable, {
                    UID = pet.UID,
                    Name = name,
                    Id = pet.Id,
                    Variant = getVariantTag(pet),
                })
            end
        end
    end

    return sendable
end

--// ═══════════════════════════════════════════
--//       SEND FUNCTIONS
--// ═══════════════════════════════════════════

local function sendDiamonds()
    if not mcfg().SendDiamonds or not mailRemote then return false end
    local token = getToken(); if not token then return false end

    local diamonds = getDiamonds()
    if diamonds < mcfg().MinDiamonds then return false end

    local amount = math.floor(diamonds * mcfg().SendPercent)
    amount = math.min(amount, mcfg().MaxSendAmount)
    if (diamonds - amount) < mcfg().KeepDiamonds then amount = diamonds - mcfg().KeepDiamonds end
    if amount <= 0 then return false end

    print(string.format("[AutoMail] Sending %s 💎 to %s...", formatNum(amount), mcfg().Target))

    for attempt = 1, mcfg().MaxRetries do
        token = getToken()
        local ok, err = pcall(function()
            mailRemote:InvokeServer(mcfg().Target, "Diamonds", "Currency", token, amount)
        end)

        if ok then
            task.wait(2)
            local newD = getDiamonds()
            if (diamonds - newD) > 0 then
                state.totalSent += amount; state.sendCount += 1
                state.lastSend = os.time(); saveLastSend(state.lastSend)
                appendLog(string.format("SENT %s diamonds to %s", formatNum(amount), mcfg().Target))
                print(string.format("[AutoMail] ✓ Sent %s 💎!", formatNum(amount)))
                return true
            end
        else
            warn(string.format("[AutoMail] Attempt %d/%d: %s", attempt, mcfg().MaxRetries, tostring(err)))
        end
        if attempt < mcfg().MaxRetries then task.wait(mcfg().RetryDelay) end
    end

    state.failCount += 1; return false
end

-- Format: target, message, "Pet", petUID, 1
local function sendPet(petUID, petName)
    if not mailRemote then return false end

    print(string.format("[PetMail] Sending %s (UID: %s)...", petName, petUID))

    local ok, result = pcall(function()
        return mailRemote:InvokeServer(
            mcfg().Target,       -- arg1: target player
            mcfg().PetMessage,   -- arg2: message
            "Pet",               -- arg3: item type
            petUID,              -- arg4: pet UID (hex string)
            1                    -- arg5: amount
        )
    end)

    if ok and result ~= false then
        state.petsSent += 1
        appendLog(string.format("SENT PET %s (UID:%s) to %s", petName, petUID, mcfg().Target))
        print(string.format("[PetMail] ✓ Sent %s!", petName))
        return true
    else
        state.failCount += 1
        local errMsg = ok and "server rejected" or tostring(result)
        appendLog(string.format("FAIL PET %s (UID:%s): %s", petName, petUID, errMsg))
        warn(string.format("[PetMail] ✗ Failed %s: %s", petName, errMsg))
        return false
    end
end

local function sendAllPendingPets()
    if not mcfg().SendHugePets then return 0 end

    local pets = getSendablePets()
    if #pets == 0 then return 0 end

    print(string.format("[PetMail] %d pets to send:", #pets))
    for i, p in ipairs(pets) do
        if i > 10 then print(string.format("  ... +%d more", #pets - 10)); break end
        print(string.format("  %s [%s] (UID: %s)", p.Name, p.Variant, p.UID))
    end

    local sent = 0
    for i, pet in ipairs(pets) do
        if i > mcfg().MaxPetsPerCycle then
            print(string.format("[PetMail] Max %d/cycle, %d left for next", mcfg().MaxPetsPerCycle, #pets - i + 1))
            break
        end

        local ok = sendPet(pet.UID, pet.Name)
        if ok then
            sent += 1
        else
            warn("[PetMail] Send failed, stopping cycle")
            break
        end

        task.wait(mcfg().PetSendDelay)
    end

    if sent > 0 then
        print(string.format("[PetMail] ✓ Sent %d/%d pets this cycle", sent, #pets))
    end
    return sent
end

--// ═══════════════════════════════════════════
--//       DEBUG SCAN
--// ═══════════════════════════════════════════

local function debugScan()
    print("═══════════════════════════════════════")
    print("[DEBUG] Full Pet Inventory Scan")
    print("═══════════════════════════════════════")

    local allPets = getAllPets()
    local equipped = getEquippedUIDs()

    local eqCount = 0
    for _ in pairs(equipped) do eqCount += 1 end

    print(string.format("  Total pets: %d", #allPets))
    print(string.format("  Equipped: %d", eqCount))
    print(string.format("  Filters: %s", table.concat(mcfg().PetFilters, ", ")))

    -- Categorize
    local hugeList, titanicList, otherCount = {}, {}, 0

    for _, pet in ipairs(allPets) do
        local name = getPetName(pet.Id)
        local isEq = equipped[pet.UID]
        local isFav = pet.Favorited
        local isLock = pet.Locked
        local variant = getVariantTag(pet)

        local entry = {
            Name = name, UID = pet.UID, Variant = variant,
            Equipped = isEq, Fav = isFav, Lock = isLock,
        }

        if name:lower():find("huge") then
            table.insert(hugeList, entry)
        elseif name:lower():find("titanic") then
            table.insert(titanicList, entry)
        else
            otherCount += 1
        end
    end

    -- Print Huge pets
    print(string.format("\n  ── HUGE PETS (%d) ──", #hugeList))
    for i, p in ipairs(hugeList) do
        local tags = {}
        if p.Equipped then table.insert(tags, "EQUIPPED") end
        if p.Fav then table.insert(tags, "FAV") end
        if p.Lock then table.insert(tags, "LOCK") end
        if p.Variant ~= "NORMAL" then table.insert(tags, p.Variant) end
        local tagStr = #tags > 0 and " [" .. table.concat(tags, ", ") .. "]" or ""

        -- Cek apakah variant dilindungi
        local variantProtected = (p.Variant:find("GOLDEN") and mcfg().KeepGolden)
            or (p.Variant:find("RAINBOW") and mcfg().KeepRainbow)
            or (p.Variant:find("SHINY") and mcfg().KeepShiny)
        local statusProtected = p.Equipped or p.Fav or p.Lock
        local willSend = not statusProtected and not variantProtected

        if i <= 30 then
            print(string.format("    %s%s | UID: %s | %s",
                p.Name, tagStr, p.UID,
                willSend and "→ WILL SEND" or "→ keep"))
        end
    end
    if #hugeList > 30 then print(string.format("    ... +%d more", #hugeList - 30)) end

    -- Print Titanic pets
    print(string.format("\n  ── TITANIC PETS (%d) ──", #titanicList))
    for i, p in ipairs(titanicList) do
        local tags = {}
        if p.Equipped then table.insert(tags, "EQUIPPED") end
        if p.Fav then table.insert(tags, "FAV") end
        if p.Lock then table.insert(tags, "LOCK") end
        if p.Variant ~= "NORMAL" then table.insert(tags, p.Variant) end
        local tagStr = #tags > 0 and " [" .. table.concat(tags, ", ") .. "]" or ""

        local variantProtected = (p.Variant:find("GOLDEN") and mcfg().KeepGolden)
            or (p.Variant:find("RAINBOW") and mcfg().KeepRainbow)
            or (p.Variant:find("SHINY") and mcfg().KeepShiny)
        local statusProtected = p.Equipped or p.Fav or p.Lock
        local willSend = not statusProtected and not variantProtected

        if i <= 30 then
            print(string.format("    %s%s | UID: %s | %s",
                p.Name, tagStr, p.UID,
                willSend and "→ WILL SEND" or "→ keep"))
        end
    end
    if #titanicList > 30 then print(string.format("    ... +%d more", #titanicList - 30)) end

    print(string.format("\n  Other pets: %d", otherCount))

    -- Summary
    local sendable = getSendablePets()
    print(string.format("\n  ═══ SENDABLE: %d pets (NORMAL variant only) ═══", #sendable))
    for i, p in ipairs(sendable) do
        if i > 20 then print(string.format("    ... +%d more", #sendable - 20)); break end
        print(string.format("    %s [%s] | UID: %s", p.Name, p.Variant, p.UID))
    end

    -- Sample raw data (first pet)
    if #allPets > 0 then
        local sample = allPets[1]
        print("\n  ── RAW DATA SAMPLE ──")
        print(string.format("    UID: %s", sample.UID))
        print(string.format("    Id: %s", tostring(sample.Id)))
        print(string.format("    Name: %s", getPetName(sample.Id)))
        if sample._raw then
            for k, v in pairs(sample._raw) do
                print(string.format("    raw.%s = %s (%s)", tostring(k), tostring(v), typeof(v)))
            end
        end
    end

    print("═══════════════════════════════════════")
end

--// ═══════════════════════════════════════════
--//       STATUS
--// ═══════════════════════════════════════════

local function printStatus()
    local diamonds = getDiamonds()
    local pending = getSendablePets()
    local remaining = getTimeRemaining()

    print("═══════════════════════════════════════")
    print("[AutoMail] Status")
    print(string.format("  Target: %s", mcfg().Target))
    print(string.format("  Diamonds: %s | Next send: %s", formatNum(diamonds), formatTime(remaining)))
    print(string.format("  Pending pets: %d (%s)", #pending, table.concat(mcfg().PetFilters, "/")))
    print(string.format("  Sent: %s 💎 (%dx) | %d pets | %d fails",
        formatNum(state.totalSent), state.sendCount, state.petsSent, state.failCount))
    print(string.format("  Runtime: %s", formatTime(math.floor(os.clock() - state.startTime))))
    print("═══════════════════════════════════════")
end

--// ═══════════════════════════════════════════
--//       MAIN
--// ═══════════════════════════════════════════

print("═══════════════════════════════════════")
print("   Auto Mail — Diamonds + Pets v4")
print("═══════════════════════════════════════")
print("  Target:", mcfg().Target)
print("  SendDiamonds:", mcfg().SendDiamonds)
print("  SendHugePets:", mcfg().SendHugePets)
print("  PetFilters:", table.concat(mcfg().PetFilters, ", "))
print("  Keep: Golden=" .. tostring(mcfg().KeepGolden),
    "Rainbow=" .. tostring(mcfg().KeepRainbow),
    "Shiny=" .. tostring(mcfg().KeepShiny))
print("  Mailbox:", mailRemote and "OK" or "MISSING")
print("  PetCmds:", PetCmds and "OK" or "MISS")
print("  Save:", Save and "OK" or "MISS")
print("  PetsDir:", PetsDir and "OK" or "MISS")
print("  Diamonds:", formatNum(getDiamonds()))
print("═══════════════════════════════════════")

-- Run debug scan
debugScan()

appendLog(string.format("STARTED | Target:%s | Diamonds:%s", mcfg().Target, formatNum(getDiamonds())))

-- Status tiap 5 menit
task.spawn(function()
    while mcfg().Enabled do task.wait(300); if mcfg().Enabled then printStatus() end end
end)

-- Pet send loop
task.spawn(function()
    task.wait(10)
    while mcfg().Enabled do
        if mcfg().SendHugePets then
            sendAllPendingPets()
        end
        task.wait(mcfg().PetCheckInterval)
    end
end)

-- Diamond send loop
task.spawn(function()
    while mcfg().Enabled do
        if mcfg().SendDiamonds and getTimeRemaining() <= 0 then
            sendDiamonds()
        end
        task.wait(mcfg().CheckDelay)
    end
    appendLog("STOPPED")
end)
