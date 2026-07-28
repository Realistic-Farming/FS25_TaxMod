-- =========================================================
-- FS25 Tax Mod - SettingsHub bridge
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Optional bridge to FS25_SettingsHub. Safe if SettingsHub is not
-- installed (register() just no-ops). Purpose: let the FarmTablet
-- System Settings app list Tax Mod's settings.
--
-- FS25TaxMod.settings (a plain table, persisted by the mod's own save
-- path) stays the source of truth. This mirrors current values into
-- SettingsHub for display; the tablet app is read-only for now, so
-- applyChange only sets the value back on that table.
-- =========================================================

TaxSettingsHubBridge = {}

local function applyChange(key, value)
    local tm = g_TaxManager
    if tm == nil or tm.settings == nil then return end
    tm.settings[key] = value
    if type(tm.saveSettings) == "function" then tm.saveSettings() end
end

function TaxSettingsHubBridge.register(tm)
    -- The reliable cross-mod handle is g_currentMission.settingsHub (the same one
    -- FarmTablet reads). The bare g_settingsHub global is only visible inside
    -- SettingsHub's own mod environment, so it reads back nil from here.
    local hub = (g_currentMission ~= nil and g_currentMission.settingsHub) or g_settingsHub
    if hub == nil then return end
    if tm == nil or tm.settings == nil then return end
    local s = tm.settings

    local defs = {
        { id = "enabled",          type = "bool",  default = s.enabled,          adminOnly = true,  label = "Tax Mod Enabled" },
        { id = "taxRate",          type = "enum",  default = s.taxRate,          adminOnly = true,  values = { "low", "medium", "high" }, label = "Tax Rate (low/medium/high)" },
        { id = "annualTaxRate",    type = "float", default = s.annualTaxRate,    adminOnly = true,  min = 0, max = 1, label = "Annual Tax Rate" },
        { id = "returnPercentage", type = "int",   default = s.returnPercentage, adminOnly = true,  min = 0, max = 100, label = "Return Percentage" },
        { id = "minimumBalance",   type = "int",   default = s.minimumBalance,   adminOnly = true,  min = 0, max = 100000000, label = "Minimum Balance" },
        { id = "showNotification", type = "bool",  default = s.showNotification, adminOnly = false, label = "Show Notifications" },
        { id = "showStatistics",   type = "bool",  default = s.showStatistics,   adminOnly = false, label = "Show Statistics" },
        { id = "showHUD",          type = "bool",  default = s.showHUD,          adminOnly = false, label = "Show HUD" },
        { id = "debugLevel",       type = "int",   default = s.debugLevel,       adminOnly = false, min = 0, max = 3, label = "Debug Level" },
    }

    local ok, err = pcall(function()
        hub:registerModule("TaxMod", {
            adminSettings = defs,
            onChange      = function(key, value, playerId) applyChange(key, value) end,
            -- We own our persistence (the mod's own save path writes FS25_TaxMod.xml) and
            -- load it before this registration runs, so the hub must mirror-for-display
            -- only: never restore its own stale copy and replay it back through onChange on
            -- load. Without this the hub can push a stale value over our real setting every
            -- load (the SoilFertilizer enabled=false reset-on-load bug class).
            selfPersisted = true,
        })
    end)

    if ok then
        Logging.info("Tax Mod: Registered with SettingsHub (%d setting(s))", #defs)
    else
        Logging.warning("Tax Mod: SettingsHub registration failed: %s", tostring(err))
    end
end
