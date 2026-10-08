-- =========================================================
-- FS25 Tax Mod - NetworkSync bridge (MAINTENANCE row 272)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- TaxMod had no server-to-client path, so a client's HUD, statistics and PDA page
-- showed the values its own settings file held (the last server it quit) or the
-- defaults, and a client ran its own shadow tax ticks. With FS25_NetworkSync installed
-- (delegate-when-present), one public module carries the server's tax record:
--   * the five admin settings (SettingsHubBridge's adminOnly keys);
--   * the global scalars taxAdvisoryMonth, taxReturnMonth, lastTaxYear, totalTaxesPaid;
--   * every farm's active accrual, days taxed, last tax year, the ledger's credit and
--     debit totals (whole money), and its last annual charge. The labelled ledger entries and the
--     imported (MP->SP) buckets are not carried: no client screen shows them.
-- A pure client applies it: the settings raw (no save), the record replaced, its own
-- farm mirrored into stats.taxesAccumulatedAnnual / stats.daysTaxed as the host's daily
-- tick mirrors its local farm. While the module is registered a client's own daily and
-- annual ticks stand down (main.lua's applyDailyTax / applyAnnualTax), so the record has
-- one writer, and the client's daily and annual notifications and HUD history come from
-- the apply instead. Without NetworkSync nothing here runs and a client keeps its own
-- ticks, as before. The player-local keys (showNotification, showStatistics, showHUD,
-- debugLevel) never ride. Every number rides as an integer (NetworkSync sends a fraction as
-- Float32): the annual rate in ten-thousandths, the ledger totals rounded to whole money.
-- =========================================================

TaxNetworkSyncBridge = TaxNetworkSyncBridge or {}

TaxNetworkSyncBridge.MODULE_ID = "FS25_TaxMod"
TaxNetworkSyncBridge.CHANNEL   = "FS25_TaxMod"
TaxNetworkSyncBridge.VERSION   = 1
TaxNetworkSyncBridge.FARM_FIELDS = 7   -- farmId, accrual, days taxed, last tax year, credits, debits, last annual charge
TaxNetworkSyncBridge.RATE_SCALE  = 10000   -- the annual rate rides as an integer number of ten-thousandths

TaxNetworkSyncBridge.active   = false   -- NetworkSync present and we registered
TaxNetworkSyncBridge._ownSeen = nil     -- client: the own farm's last applied { farmId, acc, year }

local function isServer()
    return g_currentMission ~= nil and g_currentMission.getIsServer ~= nil and g_currentMission:getIsServer() == true
end

local function getNetworkSync()
    return (g_currentMission ~= nil and g_currentMission.networkSync) or g_networkSync
end

local function whole(v)
    return math.floor((tonumber(v) or 0) + 0.5)
end

local function formatMoney(amount)
    if g_i18n and g_i18n.formatMoney then
        return g_i18n:formatMoney(amount, 0, true, true)
    end
    return "$" .. tostring(amount)
end

--- True on a pure client while the module is registered: the server's record is the one
--- source, so the client's own daily and annual ticks stand down.
function TaxNetworkSyncBridge.clientStandsDown()
    return TaxNetworkSyncBridge.active and g_currentMission ~= nil and not isServer()
end

--- SERVER: flag the module so NetworkSync's next 1 Hz batch sends the record. Called from
--- every server-side writer (main.lua: saveSettings, which every settings writer and the
--- annual pass end in; applyDailyTax; recordExpense, which the SCS irrigation expense uses).
function TaxNetworkSyncBridge.markDirty()
    if not TaxNetworkSyncBridge.active or not isServer() then return false end
    local ns = getNetworkSync()
    if ns == nil then return false end
    ns:markDirty(TaxNetworkSyncBridge.MODULE_ID)
    return true
end

-- ---------------------------------------------------------
-- Wire: one flat array, read in the same order
-- ---------------------------------------------------------

function TaxNetworkSyncBridge._onWriteState()
    local tm = FS25TaxMod
    if tm == nil or tm.settings == nil or tm.stats == nil then return {} end
    local s, st = tm.settings, tm.stats
    local ledgerFarms = (tm.ledger ~= nil and tm.ledger.farms) or {}

    local arr = { TaxNetworkSyncBridge.VERSION }
    arr[#arr + 1] = s.enabled ~= false
    arr[#arr + 1] = tostring(s.taxRate or "medium")
    arr[#arr + 1] = whole((tonumber(s.annualTaxRate) or 0.05) * TaxNetworkSyncBridge.RATE_SCALE)
    arr[#arr + 1] = whole(s.returnPercentage)
    arr[#arr + 1] = whole(s.minimumBalance)
    arr[#arr + 1] = whole(st.taxAdvisoryMonth or 12)
    arr[#arr + 1] = whole(st.taxReturnMonth or 3)
    arr[#arr + 1] = whole(st.lastTaxYear)
    arr[#arr + 1] = whole(st.totalTaxesPaid)

    -- Every farm with a tax record or a ledger, in a stable order.
    local ids, seen = {}, {}
    for farmId in pairs(st.farmTax or {}) do
        if type(farmId) == "number" and not seen[farmId] then seen[farmId] = true; ids[#ids + 1] = farmId end
    end
    for farmId in pairs(ledgerFarms) do
        if type(farmId) == "number" and not seen[farmId] then seen[farmId] = true; ids[#ids + 1] = farmId end
    end
    table.sort(ids)

    arr[#arr + 1] = #ids
    for _, farmId in ipairs(ids) do
        local ft = (st.farmTax or {})[farmId] or {}
        local fl = ledgerFarms[farmId] or {}
        arr[#arr + 1] = farmId
        arr[#arr + 1] = whole(ft.taxesAccumulatedAnnual)
        arr[#arr + 1] = whole(ft.daysTaxed)
        arr[#arr + 1] = whole(ft.lastTaxYear)
        arr[#arr + 1] = whole(fl.creditTotal)
        arr[#arr + 1] = whole(fl.debitTotal)
        arr[#arr + 1] = whole(ft.lastAnnualCharge)
    end
    return arr
end

--- CLIENT: the own farm's daily and annual notifications and HUD records, from the change
--- since the last apply (the host raises the same ones from its tick, main.lua's
--- applyDailyTax and applyAnnualTax). Nothing on the first apply after a join.
local function notifyOwnFarm(tm, ownId, ft)
    local acc, year = ft.taxesAccumulatedAnnual or 0, ft.lastTaxYear or 0
    local seen = TaxNetworkSyncBridge._ownSeen
    TaxNetworkSyncBridge._ownSeen = { farmId = ownId, acc = acc, year = year }
    if seen == nil or seen.farmId ~= ownId then return end

    local hud = tm.taxHUD
    local showNotification = tm.settings ~= nil and tm.settings.showNotification
    if year > seen.year then
        local charge = ft.lastAnnualCharge or 0
        if charge > 0 then
            if hud ~= nil then hud:recordTax(charge, 1, tm.stats.taxReturnMonth, true) end
            if showNotification then
                g_currentMission:addIngameNotification({1.0, 0.0, 0.0, 1.0},
                    string.format("Annual tax deducted for %d: -%s", year - 1, formatMoney(charge)))
            end
        end
    elseif acc > seen.acc then
        local delta = acc - seen.acc
        if hud ~= nil then
            local env = g_currentMission.environment
            hud:recordTax(delta, env and env.currentDay or 0, env and env.currentMonth or 0, false)
        end
        if showNotification then
            g_currentMission:addIngameNotification({1.0, 0.5, 0.0, 1.0},
                string.format("Daily tax accumulated: %s", formatMoney(delta)))
        end
    end
end

function TaxNetworkSyncBridge._onReadState(arr)
    if isServer() then return end   -- pure client only: the server's record is the source
    local tm = FS25TaxMod
    if tm == nil or tm.settings == nil or tm.stats == nil then return end
    if type(arr) ~= "table" or arr[1] ~= TaxNetworkSyncBridge.VERSION then return end

    local s, st = tm.settings, tm.stats
    s.enabled          = arr[2] == true
    s.taxRate          = tostring(arr[3] or "medium")
    local rate = tonumber(arr[4])
    if rate ~= nil then s.annualTaxRate = rate / TaxNetworkSyncBridge.RATE_SCALE end
    s.returnPercentage = tonumber(arr[5]) or s.returnPercentage
    s.minimumBalance   = tonumber(arr[6]) or s.minimumBalance
    st.taxAdvisoryMonth = tonumber(arr[7]) or st.taxAdvisoryMonth
    st.taxReturnMonth   = tonumber(arr[8]) or st.taxReturnMonth
    st.lastTaxYear      = tonumber(arr[9]) or 0
    st.totalTaxesPaid   = tonumber(arr[10]) or 0

    -- The record is replaced. ledger.farms is rebuilt IN PLACE (the HUD holds the table) and
    -- keeps each farm's local entries list, which the wire does not carry.
    local farms = tm.ledger ~= nil and tm.ledger.farms or nil
    local oldEntries = {}
    if farms ~= nil then
        for farmId, fl in pairs(farms) do oldEntries[farmId] = fl.entries end
        for farmId in pairs(farms) do farms[farmId] = nil end
    end
    st.farmTax = {}
    local n = tonumber(arr[11]) or 0
    local i = 12
    for _ = 1, n do
        local farmId = tonumber(arr[i])
        if farmId ~= nil then
            st.farmTax[farmId] = {
                taxesAccumulatedAnnual = tonumber(arr[i + 1]) or 0,
                daysTaxed              = tonumber(arr[i + 2]) or 0,
                lastTaxYear            = tonumber(arr[i + 3]) or 0,
                imported               = {},
                lastAnnualCharge       = tonumber(arr[i + 6]) or 0,
            }
            if farms ~= nil then
                farms[farmId] = {
                    creditTotal = tonumber(arr[i + 4]) or 0,
                    debitTotal  = tonumber(arr[i + 5]) or 0,
                    entries     = oldEntries[farmId] or {},
                }
            end
        end
        i = i + TaxNetworkSyncBridge.FARM_FIELDS
    end

    -- Mirror the client's own farm into the global stats every HUD surface reads.
    local ownId = nil
    pcall(function() ownId = g_currentMission:getFarmId() end)
    local own = ownId ~= nil and st.farmTax[ownId] or nil
    if own ~= nil then
        st.taxesAccumulatedAnnual = own.taxesAccumulatedAnnual
        st.daysTaxed = own.daysTaxed
        notifyOwnFarm(tm, ownId, own)
    else
        st.taxesAccumulatedAnnual = 0
        st.daysTaxed = 0
    end
end

-- ---------------------------------------------------------
-- Registration (loadMission00Finished, server and client)
-- ---------------------------------------------------------

function TaxNetworkSyncBridge.register(tm)
    TaxNetworkSyncBridge.active   = false
    TaxNetworkSyncBridge._ownSeen = nil

    local ns = getNetworkSync()
    if ns == nil then
        Logging.info("Tax Mod: NetworkSync not detected; a client keeps its own tax record")
        return
    end
    if tm == nil then return end

    local registered = false
    local ok, err = pcall(function()
        registered = ns:registerModule(TaxNetworkSyncBridge.MODULE_ID, {
            channel      = TaxNetworkSyncBridge.CHANNEL,
            onWriteState = TaxNetworkSyncBridge._onWriteState,
            onReadState  = TaxNetworkSyncBridge._onReadState,
        }) ~= false
    end)

    if ok and registered then
        TaxNetworkSyncBridge.active = true
        Logging.info("Tax Mod: Registered with NetworkSync as '%s' (server tax record to clients)",
            TaxNetworkSyncBridge.MODULE_ID)
    else
        Logging.warning("Tax Mod: NetworkSync registration failed: %s (a client keeps its own tax record)",
            tostring(err or "refused"))
    end
end
