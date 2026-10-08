-- MAINT-272-tax_record_to_clients_test.lua
--
-- MAINTENANCE row 272: TaxMod's server tax record reaches clients. TaxMod had no server-to-client path, so a
-- client's HUD, statistics and PDA page showed its own settings file's values (the last server it quit) or the
-- defaults, and a client kept its own shadow tax ticks. Bob's R-15 (Desk Office/Drafts/BOB-R15-MAINT272-TAXMOD-
-- SERVER-TO-CLIENT-2026-10-08.md) in the wider shape Desk dispatched, with Tyson's call (one public sync; other
-- farms' two ledger totals reach clients unlabelled and are not shown): one NetworkSync module carries the five admin
-- settings, the global scalars and every farm's record; a pure client applies it and mirrors its own farm; a synced
-- client's daily and annual ticks stand down; its notifications and HUD history come from the apply; every
-- server-side writer marks the module dirty. Without NetworkSync a client keeps its own ticks, as before.
--
-- THE ENTRY-POINT BAR: main.lua itself runs once per machine (loadfile, the chunk the engine runs), and each machine
-- enters through main.lua's own hooks: Mission00.load (onLoad) and Mission00.loadMission00Finished
-- (onMissionLoaded), which loads that machine's own settings file through the real loadSettings and registers the
-- bridges with that machine's NetworkSync and SettingsHub. Time moves through main.lua's own updateable (the
-- minute check, the day change, the period change). FS25_NetworkSync's own code (tools/test/lua/networksync_fixture,
-- verbatim at 63b390c) carries the record: the server's syncNow and 1 Hz batch, the real RealisticFarmingSyncEvent
-- written into a client's readStream, run, receiveFrames, the bridge's registered onReadState. The server's setting
-- changes through the hub's own applyChange; the ledger through the public recordExpense.
--
--   E0  each machine's onMissionLoaded registers the module with its own NetworkSync
--   C0  control: before any sync the client shows its own file's settings and record
--   J1  the join's FULL: the client takes the server's five admin settings and record, its own farm mirrored; the
--       stale farm its file held is gone; its four player-local keys stay its own
--       (and notifies nothing)
--   J2  another farm's ledger totals arrive, unlabelled (no entries)
--   H1  the server changes the daily rate through the hub's applyChange: the next batch carries it
--   D1  a daily tax on the server: the client's own farm's accrual, days taxed and HUD mirror match the server's
--   D2  the client's own tick, landing after the sync, does not add the day again
--   N3  the client's daily notification and HUD record come from the apply, exactly once
--   D4  a client tick landing before the sync still leaves one notification and one HUD record
--   R1  recordExpense on the server: the next batch carries the ledger totals, whole money
--   I1  every number the server's record carries is a whole number (NetworkSync sends a fraction as Float32)
--   U1  the client's HUD (its real drawPanel) shows the synced annual rate as "10%", and a rate read back
--       through a float shows "5%"
--   A4  the annual pass reaches the client with its own farm's charge, notified and recorded once
--   L5  the client's player-local keys are untouched throughout
--   G1  a record reaching the server's own onReadState changes nothing there (pure client only)
--   X6  without NetworkSync the client's own tick runs as before
--
--!load: tools/test/lua/networksync_fixture/engine_stubs.lua, tools/test/lua/networksync_fixture/Logger.lua, tools/test/lua/networksync_fixture/RealisticFarmingSyncEvent.lua, tools/test/lua/networksync_fixture/NetworkSync.lua, src/integrations/OptionScalingResolver.lua, src/settings/UIHelper.lua, src/settings/SettingsUI.lua, src/ui/TaxHUD.lua, src/settings/SettingsHubBridge.lua, src/integrations/TaxStateLedgerBridge.lua, src/integrations/TaxMasterHUDBridge.lua, src/integrations/CropStressIrrigationExpense.lua, src/integrations/TaxNetworkSyncBridge.lua

-- Engine-style hook chaining (main.lua hooks loadMission00Finished three times and FSBaseMission.delete twice).
function Utils.appendedFunction(old, new)
    if old == nil then return new end
    return function(...) old(...); return new(...) end
end
function Utils.prependedFunction(old, new)
    if old == nil then return new end
    return function(...) new(...); return old(...) end
end
getfenv = getfenv or function() return _G end
g_gui = { screenControllers = {} }
InGameMenu = InGameMenu or {}
NSLogger.warning = function() end
NSLogger.debug = function() end
NSLogger.error = function() end
NSLogger.info = function() end
local WARN = {}
Logging = { info = function() end, warning = function(f, ...) WARN[#WARN + 1] = tostring(f) end, error = function() end }

-- The engine's Float32 rounds to single precision; this harness's typed stream keeps the raw number, so the bench
-- rounds it here (a value that rides as Float32 arrives as the engine would deliver it).
local function f32(v) return (string.unpack("<f", string.pack("<f", v))) end
local rawWriteFloat32 = streamWriteFloat32
streamWriteFloat32 = function(s, v) rawWriteFloat32(s, type(v) == "number" and f32(v) or v) end
-- The HUD's render calls: text is recorded, the rest is inert.
local RENDERED = {}
RenderText = RenderText or { ALIGN_LEFT = 0, ALIGN_CENTER = 1, ALIGN_RIGHT = 2 }
function renderText(_, _, _, text) RENDERED[#RENDERED + 1] = tostring(text) end
function setTextAlignment() end
function setTextColor() end
function setTextBold() end
function getBaseGameRenderer() return nil end
function setOverlayColor() end
function renderOverlay() end

local function group(name, fn)
    local ok, err = pcall(fn)
    if not ok then T.ok(name .. " [group raised: " .. tostring(err) .. "]", false) end
end

-- The calendar: period p is calendar month ((p + 1) mod 12) + 1, so period 1 is March (the payment month).
g_i18n = {
    getText = function(_, key) local m = tostring(key):match("^ui_month(%d+)$"); return m and ("Month" .. m) or key end,
    hasText = function() return true end,
    formatPeriod = function(_, p) return "Month" .. (((p + 1) % 12) + 1) end,
    formatMoney = function(_, v) return tostring(v) end,
}

-- Two real farms; balances are the engine's, the same on every machine.
local FARMS = { { farmId = 1, money = 100000 }, { farmId = 2, money = 50000 } }
g_farmManager = {
    getFarms = function() return FARMS end,
    getFarmById = function(_, id) for _, f in ipairs(FARMS) do if f.farmId == id then return f end end end,
}

-- Each machine's own settings file, read and written by main.lua's real loadSettings/saveSettings.
local CUR = nil
-- No `a and b or nil` here: a stored false must read back as false.
local function xget(h, k)
    if CUR == nil or CUR.xml[h] == nil then return nil end
    return CUR.xml[h][k]
end
local function xset(h, k, v) if CUR ~= nil and CUR.xml[h] ~= nil then CUR.xml[h][k] = v end end
function fileExists(path) return CUR ~= nil and CUR.xml[path] ~= nil end
function loadXMLFile(_, path) return (CUR ~= nil and CUR.xml[path] ~= nil) and path or 0 end
function createXMLFile(_, path) if CUR ~= nil then CUR.xml[path] = CUR.xml[path] or {} end return path end
getXMLInt, getXMLFloat, getXMLString, getXMLBool = xget, xget, xget, xget
setXMLInt, setXMLFloat, setXMLString, setXMLBool = xset, xset, xset, xset

local MAIN = loadfile("main.lua") or loadfile("../../main.lua")

local W = {}
local function on(machine, fn)
    local saved = { g_currentMission, g_networkSync, g_server, g_client, FS25TaxMod, g_TaxManager, CUR }
    g_currentMission, g_networkSync, g_server, g_client = machine.mission, machine.ns, machine.server, machine.client
    FS25TaxMod, g_TaxManager, CUR = machine.mod, machine.mod, machine
    local res = table.pack(pcall(fn))
    g_currentMission, g_networkSync, g_server, g_client, FS25TaxMod, g_TaxManager, CUR =
        saved[1], saved[2], saved[3], saved[4], saved[5], saved[6], saved[7]
    if not res[1] then error(res[2], 0) end
    return table.unpack(res, 2, res.n)
end

local function newMission(name, isServer, farmId)
    local m = { _isServer = isServer, isMissionStarted = true, notes = {},
        getIsServer = function(self) return self._isServer end,
        getIsClient = function(self) return not self._isServer end,
        getFarmId = function() return farmId end,
        environment = { currentYear = 2, currentPeriod = 5, currentDay = 10, currentDayInPeriod = 1, daysPerPeriod = 1,
                        dayTime = 6 * 3600000, daylight = { latitude = 0.5 } },
        missionInfo = { savegameDirectory = "save_" .. name },
        addUpdateable = function(self, u) self.updateable = u end,
        removeUpdateable = function() end,
        addIngameNotification = function(self, _, text) self.notes[#self.notes + 1] = text end,
        addMoney = function(_, amount, farmId) for _, f in ipairs(FARMS) do if f.farmId == farmId then f.money = f.money + amount end end end,
    }
    return m
end
local function settingsFile(machine, values)
    local copy = {}
    for k, v in pairs(values) do copy[k] = v end   -- the machine's own file; saveSettings writes it
    machine.xml["save_" .. machine.name .. "/modSettings/FS25_TaxMod.xml"] = copy
end

--- A machine: its mission, NetworkSync, its own settings file, main.lua run for it and its two hooks called.
local function machine(name, isServer, farmId, withNS, file)
    local m = { name = name, mission = newMission(name, isServer, farmId), xml = {} }
    if withNS then m.ns = NetworkSync.new() end
    m.mission.networkSync = m.ns
    m.mission.settingsHub = { registerModule = function(_, _, spec) m.hubSpec = spec return true end }
    if isServer then m.server = { broadcastEvent = function(_, ev) W.sent[#W.sent + 1] = ev end }
    else m.client = { getServerConnection = function() return { sendEvent = function() end } end } end
    settingsFile(m, file)
    on(m, function()
        Mission00, FSBaseMission, FSCareerMissionInfo = {}, {}, {}
        FS25TaxMod = nil
        MAIN()
        m.mod = FS25TaxMod
        m.hooks = { load = Mission00.load, finished = Mission00.loadMission00Finished }
    end)
    on(m, function() m.hooks.load(m.mission) end)
    on(m, function() m.hooks.finished(m.mission, nil) end)
    return m
end

local SERVER_FILE = {
    ["settings.enabled"] = true, ["settings.taxRate"] = "high", ["settings.annualTaxRate"] = 0.10,
    ["settings.returnPercentage"] = 30, ["settings.minimumBalance"] = 2000,
    ["settings.showNotification"] = false, ["settings.showStatistics"] = true, ["settings.showHUD"] = true,
    ["settings.debugLevel"] = 0, ["settings.stats.totalTaxesPaid"] = 777, ["settings.stats.lastTaxYear"] = 1,
    ["settings.farmTax.farm(0)#farmId"] = 1, ["settings.farmTax.farm(0)#accumulated"] = 4000,
    ["settings.farmTax.farm(0)#daysTaxed"] = 2, ["settings.farmTax.farm(0)#lastTaxYear"] = 1,
    ["settings.farmTax.farm(1)#farmId"] = 2, ["settings.farmTax.farm(1)#accumulated"] = 3000,
    ["settings.farmTax.farm(1)#daysTaxed"] = 3, ["settings.farmTax.farm(1)#lastTaxYear"] = 1,
    ["settings.ledger.farm(0)#farmId"] = 1, ["settings.ledger.farm(0)#creditTotal"] = 120, ["settings.ledger.farm(0)#debitTotal"] = 30,
}
-- The client's file: the last server it quit, and its own player-local choices.
local CLIENT_FILE = {
    ["settings.enabled"] = true, ["settings.taxRate"] = "medium", ["settings.annualTaxRate"] = 0.05,
    ["settings.returnPercentage"] = 20, ["settings.minimumBalance"] = 1000,
    ["settings.showNotification"] = true, ["settings.showStatistics"] = false, ["settings.showHUD"] = false,
    ["settings.debugLevel"] = 2, ["settings.stats.totalTaxesPaid"] = 5, ["settings.stats.lastTaxYear"] = 0,
    ["settings.stats.taxesAccumulatedAnnual"] = 9, ["settings.stats.daysTaxed"] = 9,
    ["settings.farmTax.farm(0)#farmId"] = 2, ["settings.farmTax.farm(0)#accumulated"] = 9,
    ["settings.farmTax.farm(0)#daysTaxed"] = 9, ["settings.farmTax.farm(0)#lastTaxYear"] = 0,
    ["settings.ledger.farm(0)#farmId"] = 7, ["settings.ledger.farm(0)#creditTotal"] = 55, ["settings.ledger.farm(0)#debitTotal"] = 5,
}

local function world(withNS)
    W.sent = {}
    for _, f in ipairs(FARMS) do f.money = (f.farmId == 1) and 100000 or 50000 end
    W.server = machine("host", true, 1, withNS, SERVER_FILE)
    W.client = machine("client", false, 2, withNS, CLIENT_FILE)
    if withNS then
        -- The client's NetworkSync took the module at its own onMissionLoaded; nothing registered by hand.
        W.client.ns.needsFullSync = false
    end
    return W.server, W.client
end
--- The engine's delivery of every event the server sent since `from`: writeStream, then a fresh instance's
--- readStream on the client, which runs.
local function deliverSince(from)
    local n = 0
    for k = from + 1, #W.sent do
        local ev = W.sent[k]
        local s = NewTypedStream()
        on(W.server, function() ev:writeStream(s, nil) end)
        on(W.client, function() getmetatable(ev).__index.emptyNew():readStream(s, nil) end)
        n = n + 1
    end
    return n
end
local function batch()
    local from = #W.sent
    on(W.server, function() W.server.ns:update(1000) end)
    return deliverSince(from)
end
--- One step of main.lua's own updateable on a machine, after moving its clock.
local function tick(m, change)
    on(m, function()
        local env = m.mission.environment
        for k, v in pairs(change) do env[k] = v end
        env.dayTime = env.dayTime + 60000
        m.mission.updateable.update(16)
    end)
end
local function ownFarm(m, id)
    local ft = m.mod.stats.farmTax[id] or {}
    return tostring(ft.taxesAccumulatedAnnual) .. "/" .. tostring(ft.daysTaxed) .. "/" .. tostring(ft.lastTaxYear)
end
local function five(s)
    return table.concat({ tostring(s.enabled), tostring(s.taxRate), tostring(s.annualTaxRate), tostring(s.returnPercentage),
        tostring(s.minimumBalance) }, "/")
end
local function locals(s)
    return table.concat({ tostring(s.showNotification), tostring(s.showStatistics), tostring(s.showHUD), tostring(s.debugLevel) }, "/")
end
local function countNotes(m, pattern)
    local n = 0
    for _, t in ipairs(m.mission.notes) do if tostring(t):find(pattern, 1, true) then n = n + 1 end end
    return n
end

group("N", function()
    local server, client = world(true)
    T.ok("E0 [entry point] each machine's onMissionLoaded registers the FS25_TaxMod module with its own NetworkSync",
        server.ns.schemas[TaxNetworkSyncBridge.MODULE_ID] ~= nil and client.ns.schemas[TaxNetworkSyncBridge.MODULE_ID] ~= nil)
    local cs, ss = client.mod.settings, server.mod.settings
    T.eq("C0 control: before any sync the client shows its own file's settings and accrual", five(cs) .. " "
        .. tostring(client.mod.stats.taxesAccumulatedAnnual), "true/medium/0.05/20/1000 9")

    on(server, function() server.ns:syncNow(TaxNetworkSyncBridge.MODULE_ID) end)
    deliverSince(0)
    local ct = client.mod.stats
    T.eq("J1 [entry point] NAMED (row 272): the join's FULL gives the client the server's five admin settings, the annual rate exactly 0.10",
        tostring(cs.enabled) .. "/" .. cs.taxRate .. "/" .. tostring(cs.annualTaxRate == 0.10) .. "/"
        .. cs.returnPercentage .. "/" .. cs.minimumBalance, "true/high/true/30/2000")
    T.eq("J1 and the server's record: its own farm 2 mirrored, the global scalars, the stale farm 7 ledger gone",
        ownFarm(client, 2) .. " " .. ct.taxesAccumulatedAnnual .. "/" .. ct.daysTaxed .. " " .. ct.totalTaxesPaid .. "/"
        .. ct.lastTaxYear .. " " .. tostring(client.mod.ledger.farms[7]), "3000/3/1 3000/3 777/1 nil")
    T.eq("J1 the join notifies nothing and records no HUD history (there is no earlier record to compare)",
        #client.mission.notes .. " " .. #client.mod.taxHUD.taxHistory, "0 0")
    T.eq("J2 another farm's ledger totals arrive, unlabelled (no entries)",
        tostring((client.mod.ledger.farms[1] or {}).creditTotal) .. "/" .. tostring((client.mod.ledger.farms[1] or {}).debitTotal) .. "/"
        .. #((client.mod.ledger.farms[1] or {}).entries or {}),
        "120/30/0")

    -- H1: the server's daily rate changes through the hub's own applyChange; nothing else is dirty.
    on(server, function() server.hubSpec.onChange("taxRate", "low", nil) end)
    local sentH = batch()
    T.eq("H1 a server change through the hub's applyChange rides the next 1 Hz batch", sentH .. " " .. cs.taxRate, "1 low")

    -- D1, D2, N3: a day passes. The server ticks and its batch lands, then the client's own tick runs.
    local notes0, hist0 = #client.mission.notes, #client.mod.taxHUD.taxHistory
    tick(server, { currentDay = 11 })
    batch()
    local afterSync = ownFarm(client, 2)
    tick(client, { currentDay = 11 })
    T.eq("D1 a daily tax on the server: the client's own farm's accrual, days taxed and HUD mirror match the server's (low, 1%)",
        ownFarm(client, 2) .. " " .. ct.taxesAccumulatedAnnual .. "/" .. ct.daysTaxed .. " " .. ownFarm(server, 2),
        "3500/4/1 3500/4 3500/4/1")
    T.eq("D2 the client's own tick, landing after the sync, does not add the day again", afterSync .. " " .. ownFarm(client, 2),
        "3500/4/1 3500/4/1")
    T.eq("N3 the client's daily notification and HUD record come from the apply, exactly once",
        (#client.mission.notes - notes0) .. " " .. countNotes(client, "Daily tax accumulated: 500") .. " "
        .. (#client.mod.taxHUD.taxHistory - hist0) .. " " .. tostring((client.mod.taxHUD.taxHistory[1] or {}).amount) .. "/"
        .. tostring((client.mod.taxHUD.taxHistory[1] or {}).isReturn), "1 1 1 500/false")

    -- D4: the next day the client's own tick lands first, then the server's sync.
    local notes1, hist1 = #client.mission.notes, #client.mod.taxHUD.taxHistory
    tick(client, { currentDay = 12 })
    tick(server, { currentDay = 12 })
    batch()
    T.eq("D4 a client tick landing before the sync still leaves one notification and one HUD record, and the server's record",
        (#client.mission.notes - notes1) .. " " .. (#client.mod.taxHUD.taxHistory - hist1) .. " " .. ownFarm(client, 2),
        "1 1 4000/5/1")

    -- R1: the public recordExpense on the server; nothing else is dirty.
    local ok = on(server, function()
        return FS25TaxMod.recordExpense(2, 250.4, "Wages") and FS25TaxMod.recordExpense(1, -30.6, "Fuel")
    end)
    local sentR = batch()
    T.eq("R1 recordExpense on the server: the next batch carries the client's farm's ledger totals, without the label",
        tostring(ok) .. " " .. sentR .. " " .. tostring((client.mod.ledger.farms[2] or {}).creditTotal) .. "/"
        .. #((client.mod.ledger.farms[2] or {}).entries or {}) .. " " .. tostring((client.mod.ledger.farms[1] or {}).debitTotal),
        "true 1 250/0 61")
    local wire = on(server, function() return TaxNetworkSyncBridge._onWriteState() end)
    local fractions = {}
    for k, v in ipairs(wire) do
        if type(v) == "number" and math.floor(v) ~= v then fractions[#fractions + 1] = k .. "=" .. tostring(v) end
    end
    T.eq("I1 every number the server's record carries is a whole number (the host holds 250.4 and 60.6)",
        #wire > 20 and table.concat(fractions, ",") or "short record", "")

    -- A4: March. Both machines see the period change; the client's tick lands first.
    local notes2, hist2 = #client.mission.notes, #client.mod.taxHUD.taxHistory
    tick(client, { currentPeriod = 1 })
    tick(server, { currentPeriod = 1 })
    batch()
    local h = client.mod.taxHUD.taxHistory[1] or {}
    T.eq("A4 the annual pass reaches the client with its own farm's charge (4000 at 10%), notified and recorded once; its mirror reset",
        countNotes(client, "Annual tax deducted for 1: -400") .. " " .. (#client.mission.notes - notes2) .. " "
        .. (#client.mod.taxHUD.taxHistory - hist2) .. " " .. tostring(h.amount) .. "/" .. tostring(h.isReturn) .. " "
        .. ownFarm(client, 2) .. " " .. ct.taxesAccumulatedAnnual .. " " .. ct.totalTaxesPaid,
        "1 1 1 400/true 0/5/2 0 1777")
    T.eq("A4 (the server charged each farm its own: farm 1's 6000 and farm 2's 4000 at 10%)", tostring(server.mod.stats.farmTax[1].lastAnnualCharge) .. "/"
        .. tostring(server.mod.stats.farmTax[2].lastAnnualCharge), "600/400")

    -- showHUD follows the HUD's own saved visibility at load (onMissionLoaded), true with no layout file.
    T.eq("L5 the client's player-local keys are untouched throughout (its own)", locals(cs), "true/false/true/2")

    -- U1: the client's HUD, its real drawPanel.
    local function annualLine(m)
        RENDERED = {}
        on(m, function() m.mod.taxHUD:drawPanel() end)
        for _, t in ipairs(RENDERED) do if t:find("Annual Rate:", 1, true) then return t end end
        return "none"
    end
    T.eq("U1 the client's HUD (its real drawPanel) shows the synced annual rate", annualLine(client), "Annual Rate: 10%")
    local hostRate = ss.annualTaxRate
    ss.annualTaxRate = f32(0.05)   -- what the host reads back from its own save (getXMLFloat)
    T.eq("U1 and a rate read back through a float shows as a whole percentage, not 5.0000000745058%", annualLine(server), "Annual Rate: 5%")
    ss.annualTaxRate = hostRate

    -- G1: a record reaching the server's own onReadState (a listen host) changes nothing there.
    local before = five(ss) .. " " .. ownFarm(server, 2)
    on(server, function() TaxNetworkSyncBridge._onReadState({ 1, false, "medium", 5000, 1, 1, 12, 3, 9, 9, 0 }) end)
    T.eq("G1 the server's own onReadState never changes its settings or record (pure client only)", five(ss) .. " " .. ownFarm(server, 2), before)
end)

group("X", function()
    local server, client = world(false)
    T.ok("X6 (no NetworkSync: nothing registered)", not TaxNetworkSyncBridge.active)
    local notes0 = #client.mission.notes
    tick(client, { currentDay = 11 })
    T.eq("X6 without NetworkSync the client's own tick runs as before: its own farm accrues at its own file's rate (medium, 2%) and it notifies",
        ownFarm(client, 2) .. " " .. (#client.mission.notes - notes0) .. " " .. countNotes(client, "Daily tax accumulated: 1000"),
        "1009/10/0 1 1")
end)
