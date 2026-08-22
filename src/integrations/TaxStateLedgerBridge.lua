-- =========================================================
-- FS25 Tax Mod - TaxStateLedgerBridge
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Optional bridge to FS25_StateLedger (bedrock). Strictly
-- delegate-when-present, mirroring SoilFertilizer / IncomeMod / WorkerCosts:
--
--   * StateLedger installed -> the shared master save file is the LOAD source
--     of truth for the Tax Mod STATE: the running stats (totals, days taxed,
--     the annual accumulator + last-paid year) and the companion recordExpense
--     ledger (per-farm credit/debit + recent entries). The mod's own
--     modSettings/FS25_TaxMod.xml is still written every save as the standalone
--     safety copy, so removing the ledger later never loses data.
--   * StateLedger absent -> nothing changes; the own XML is primary.
--
-- ONE module: TaxMod_Data. Settings are NOT a StateLedger module here.
-- Settings persistence + MP sync are SettingsHub's domain, and the mod keeps
-- its own XML as the settings fallback; a third settings copy in a per-mod
-- ledger module would just be a conflicting duplicate. This matches
-- SoilFertilizer / IncomeMod, whose ledger modules carry state, not settings.
--
-- Timing note (same as IncomeMod / WorkerCosts): the mod loads its state in
-- onMissionLoaded (= loadMission00Finished), the same phase StateLedger parses
-- its file in. So register() force-triggers the idempotent parseFile after
-- registering, guaranteeing deserialize has delivered before the caller reads
-- hasState(), independent of mod load order.
--
-- The cross-mod handle is g_currentMission.stateLedger (published in Mission00.load).
-- =========================================================

TaxStateLedgerBridge = TaxStateLedgerBridge or {}

-- LOCKED persistence key. Never renamed after first persist.
TaxStateLedgerBridge.MODULE_ID = "TaxMod_Data"

TaxStateLedgerBridge.active       = false   -- ledger present and we registered
TaxStateLedgerBridge.delivered    = false   -- deserialize has fired (once)
TaxStateLedgerBridge.pendingState = nil     -- cached table (nil = new save / no block)

-- True when the ledger is the state load source of truth this session.
function TaxStateLedgerBridge.hasState()
    return TaxStateLedgerBridge.active
        and TaxStateLedgerBridge.delivered
        and TaxStateLedgerBridge.pendingState ~= nil
end

-- Apply the cached state block into the tax mod. Returns true on apply.
function TaxStateLedgerBridge.applyState(tm)
    if tm == nil or type(tm.applyState) ~= "function" then return false end
    if type(TaxStateLedgerBridge.pendingState) ~= "table" then return false end
    return tm.applyState(TaxStateLedgerBridge.pendingState)
end

-- Register with StateLedger if present. Called from onMissionLoaded, after
-- loadSettings() has imported the own-XML safety copy.
function TaxStateLedgerBridge.register(tm)
    TaxStateLedgerBridge.active       = false
    TaxStateLedgerBridge.delivered    = false
    TaxStateLedgerBridge.pendingState = nil

    local ledger = (g_currentMission ~= nil and g_currentMission.stateLedger) or g_stateLedger
    if ledger == nil then
        Logging.info("Tax Mod: StateLedger not detected; state uses its own FS25_TaxMod.xml")
        return
    end
    if tm == nil or type(tm.serializeState) ~= "function" then return end

    local ok, err = pcall(function()
        ledger:registerModule(TaxStateLedgerBridge.MODULE_ID, {
            serialize = function()
                return tm.serializeState()
            end,
            deserialize = function(data)
                TaxStateLedgerBridge.delivered    = true
                TaxStateLedgerBridge.pendingState = data   -- nil on a brand-new save
            end,
        })
    end)

    if not ok then
        Logging.warning("Tax Mod: StateLedger registration failed: %s (falling back to own XML)", tostring(err))
        return
    end

    TaxStateLedgerBridge.active = true

    -- Force the (idempotent) parse now so deserialize has delivered before the
    -- caller checks hasState() a few lines later, independent of which mod's
    -- loadMission00Finished handler ran first. A no-op if StateLedger already
    -- parsed (it loaded first).
    if ledger.parseFile ~= nil then
        pcall(function() ledger:parseFile() end)
    end

    Logging.info("Tax Mod: Registered with StateLedger as '%s' (FS25_TaxMod.xml kept as safety copy)",
        TaxStateLedgerBridge.MODULE_ID)
end
