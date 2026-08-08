-- =========================================================
-- FS25 Tax Mod - TaxMasterHUDBridge
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Optional bridge to FS25_MasterHUD (bedrock). Strictly delegate-when-present,
-- mirroring SoilFertilizer / IncomeMod / WorkerCosts:
--   * MasterHUD installed -> the tax HUD overlay registers as a subscribe()
--     element so MasterHUD owns the single suspend-aware draw loop and cross-mod
--     ordering; the mod's own FSBaseMission.draw hook stands down when active.
--   * MasterHUD absent -> the mod's own draw hook runs the exact same body.
--
-- drawStack() is the single source of the draw body, shared with the fallback
-- hook so the two paths can never diverge. It reproduces the own hook's guard
-- (settings.showHUD) and then calls TaxHUD:draw(), which itself self-guards on
-- getIsClient / GUI-visible / large-map / visible, so calling it every frame is
-- a no-op when hidden.
--
-- Mouse routing stays on the mod's own addModEventListener handler (MasterHUD
-- owns draw ordering + suspend, not input). The settings UI injected into the
-- General Settings page is g_gui-managed and stays there.
--
-- The cross-mod handle is g_currentMission.masterHUD (published in Mission00.load).
-- =========================================================

TaxMasterHUDBridge = {}

TaxMasterHUDBridge.HUD_ID = "TaxMod_HUD"
TaxMasterHUDBridge.active = false   -- MasterHUD present and we registered

-- The tax HUD draw body. Resolves the manager from the canonical global so it
-- can be driven either by MasterHUD's loop or by the mod's own draw hook.
-- Reproduces the own hook's `taxHUD and settings.showHUD` guard.
function TaxMasterHUDBridge.drawStack()
    -- Suite hide: MasterHUD # key. No-op when MasterHUD absent.
    local mh = (g_currentMission ~= nil and g_currentMission.masterHUD) or g_masterHUD
    if mh ~= nil and mh.areHudsHidden ~= nil and mh:areHudsHidden() then return end
    local tm = g_TaxManager
    if tm ~= nil and tm.taxHUD ~= nil and tm.settings ~= nil and tm.settings.showHUD then
        tm.taxHUD:draw()
    end
end

-- Register with MasterHUD if present. Called from onMissionLoaded.
function TaxMasterHUDBridge.register(tm)
    TaxMasterHUDBridge.active = false

    local hud = (g_currentMission ~= nil and g_currentMission.masterHUD) or g_masterHUD
    if hud == nil then
        Logging.info("Tax Mod: MasterHUD not detected; tax HUD uses its own draw hook")
        return
    end

    local ok, err = pcall(function()
        hud:subscribe(TaxMasterHUDBridge.HUD_ID, {
            draw = TaxMasterHUDBridge.drawStack,
        })
    end)

    if ok then
        TaxMasterHUDBridge.active = true
        Logging.info("Tax Mod: Registered tax HUD with MasterHUD (single draw loop + menu-suspend)")
        if hud.registerEditListener ~= nil then
            hud:registerEditListener(TaxMasterHUDBridge.HUD_ID, {
                enter = function()
                    local th = tm ~= nil and tm.taxHUD or nil
                    if th ~= nil and th.enterEditMode ~= nil then th:enterEditMode() end
                end,
                exit = function()
                    local th = tm ~= nil and tm.taxHUD or nil
                    if th ~= nil and th.editMode and th.exitEditMode ~= nil then th:exitEditMode() end
                end,
            })
        end
    else
        Logging.warning("Tax Mod: MasterHUD registration failed: %s (using own draw hook)", tostring(err))
    end
end
