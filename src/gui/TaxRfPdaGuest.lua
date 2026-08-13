-- =========================================================
-- TaxRfPdaGuest - Esc RF PDA Tax framework (Status shell)
-- Soft-detect: mission.taxManager -> g_TaxManager -> FS25TaxMod.
-- Read-only; no tax settle / money writes.
-- =========================================================

TaxRfPdaGuest = {}

local MOD_DIR = g_currentModDirectory
local MOD_NAME = g_currentModName
local PANEL_ID = "tax"
local PANEL_ORDER = 60
local _registered = false

local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[MOD_NAME]
    local i18n = (modEnv and modEnv.i18n) or g_i18n
    if i18n then
        local ok, text = pcall(function() return i18n:getText(key) end)
        if ok and type(text) == "string" and text ~= "" then
            local lower = text:lower()
            if lower ~= tostring(key):lower()
                and text ~= ("$l10n_" .. key)
                and not lower:find("^missing%s")
                and not lower:find("^missing_")
            then
                return text
            end
        end
    end
    return fallback or key
end

local function getHost()
    if g_currentMission ~= nil and g_currentMission.rfEscModules ~= nil then
        return g_currentMission.rfEscModules
    end
    local env = getfenv(0)
    if env ~= nil and env.g_rfEscModules ~= nil then
        return env.g_rfEscModules
    end
    if RfEscModules ~= nil then
        return RfEscModules.getOrCreate()
    end
    return nil
end

local function getHostPage()
    if g_inGameMenu == nil then return nil end
    return g_inGameMenu.menuRealisticFarming
end

local function findDescendant(root, id)
    if root == nil or id == nil then return nil end
    if root.getDescendantById then
        local el = root:getDescendantById(id)
        if el ~= nil then return el end
    end
    local page = getHostPage()
    if page and page.getDescendantById then
        return page:getDescendantById(id)
    end
    return nil
end

local function setText(el, text)
    if el ~= nil and type(el.setText) == "function" then el:setText(text or "") end
end

local function setVis(el, visible)
    if el ~= nil and type(el.setVisible) == "function" then el:setVisible(visible) end
end

local function formatMoney(amount)
    if amount == nil then return "--" end
    if g_i18n and g_i18n.formatMoney then return g_i18n:formatMoney(amount, 0, true, true) end
    return string.format("%.0f", amount)
end

local function paintSide(container, key, fallback)
    setVis(findDescendant(container, "wcSideInfoShell"), false)
    setVis(findDescendant(container, "mdSideInfoShell"), false)
    local shell = findDescendant(container, "rfSideInfoShell")
    local body = findDescendant(container, "rfSideInfoBody")
    setVis(shell, true)
    setText(body, tr(key, fallback))
end


local function refreshFwAbs(container)
    local page = getHostPage()
    local host = findDescendant(container, "rfHostPlaceholder") or (page and page.rfHostPlaceholder)
    local shell = findDescendant(container, "rfFrameworkGlanceShell")
    local status = findDescendant(container, "rfFwStatusBlock")
    local tableBlock = findDescendant(container, "rfFwTableBlock")
    for _, el in ipairs({ host, shell, status, tableBlock }) do
        if el ~= nil and type(el.updateAbsolutePosition) == "function" then
            el:updateAbsolutePosition()
        end
    end
end

local function clearHostDupes(container)
    setText(findDescendant(container, "rfHostBody"), "")
    setText(findDescendant(container, "rfHostTitle"), "")
    setText(findDescendant(container, "rfHostBlurb"), "")
    setVis(findDescendant(container, "rfHostTitle"), false)
    setVis(findDescendant(container, "rfHostBlurb"), false)
end

local function showStatusMode(container)
    setVis(findDescendant(container, "rfFrameworkGlanceShell"), true)
    setVis(findDescendant(container, "rfFwStatusBlock"), true)
    setVis(findDescendant(container, "rfFwTableBlock"), false)
    refreshFwAbs(container)
end

local function showTableMode(container)
    setVis(findDescendant(container, "rfFrameworkGlanceShell"), true)
    setVis(findDescendant(container, "rfFwStatusBlock"), false)
    setVis(findDescendant(container, "rfFwTableBlock"), true)
    refreshFwAbs(container)
end

local function labeled(label, value)
    local lbl = tostring(label or ""):gsub(":%s*$", "")
    return string.format("%s: %s", lbl, tostring(value or "--"))
end

-- Daily taxRate map (same as HUD / main.lua TAX_RATE_VALUES). March annualTaxRate is separate.
local TAX_RATE_VALUES = { low = 0.01, medium = 0.02, high = 0.03 }

local function getTax()
    if g_currentMission ~= nil and g_currentMission.taxManager ~= nil then
        return g_currentMission.taxManager
    end
    if g_TaxManager ~= nil then
        return g_TaxManager
    end
    local env = getfenv(0)
    if env ~= nil and env.g_TaxManager ~= nil then
        return env.g_TaxManager
    end
    -- Temporary deepest fallback (named): global table FS25TaxMod
    if FS25TaxMod ~= nil then
        return FS25TaxMod
    end
    return nil
end

local function monthsUntil(target, current)
    local d = (tonumber(target) or 1) - (tonumber(current) or 1)
    if d <= 0 then d = d + 12 end
    return d
end

local _baseline = nil   -- the XML baseline, captured on the first show, re-asserted after

-- BUILD 16:32. The densify that used to live here moved rfFwLine1..8 to -280..-480 with
-- 26px type and X reset to 0. That was written for an unframed 580-tall status block,
-- where the lower band really was empty space. BUILD 15:35 put a 340-tall white stroke
-- round that block, so the same move now drops the whole status band under the bottom
-- rule and leaves an empty white box above it: the FAIL Wizard saw.
--
-- It is gone rather than re-tuned. The guest had the shell geometry copied into Lua, so
-- the moment the shared XML changed underneath it the two disagreed and the guest won.
-- The XML is the one place that says where status text lives; this file's job is only to
-- put it back there if anything moved it.

--- Remember where the shared Status shell started, once. Nothing here moves it any more,
--- so on the first show this IS the XML baseline, and it is what every later show restores.
local function captureBaseline(container)
    if _baseline ~= nil then return end
    _baseline = {}
    for i = 1, 8 do
        local el = findDescendant(container, "rfFwLine" .. i)
        if el ~= nil then
            _baseline["rfFwLine" .. i] = { x = el.position and el.position[1], y = el.position and el.position[2],
                                           textSize = el.textSize }
        end
    end
    local h = findDescendant(container, "rfFwHint")
    if h ~= nil then
        _baseline.rfFwHint = { x = h.position and h.position[1], y = h.position and h.position[2], textSize = h.textSize }
    end
end

--- Put the shared Status shell back on the XML baseline captured before anything moved.
--- Position and textSize are stored already normalised, straight off the element, so this
--- needs no GuiUtils and cannot mis-convert. If nothing was ever captured it does nothing,
--- which leaves the XML standing - the right failure direction.
---
--- ONE definition, called from both onShow and onHide. The old pair was a densify here and
--- a restore there: two descriptions of the same layout, free to drift apart. They did.
local function restoreStatusBand(container)
    if container == nil or _baseline == nil then return end
    local function restore(id)
        local b = _baseline[id]
        local el = findDescendant(container, id)
        if b == nil or el == nil then return end
        if b.x ~= nil and b.y ~= nil and type(el.setPosition) == "function" then el:setPosition(b.x, b.y) end
        if b.textSize ~= nil and type(el.setTextSize) == "function" then el:setTextSize(b.textSize) end
        if type(el.updateAbsolutePosition) == "function" then el:updateAbsolutePosition() end
    end
    for i = 1, 8 do restore("rfFwLine" .. i) end
    restore("rfFwHint")
end

function TaxRfPdaGuest.onShow(container, lightOnly)
    clearHostDupes(container)
    showStatusMode(container)
    -- Capture first (this is the XML baseline on the first show), then re-assert it every
    -- show, so a stale move from any earlier session cannot survive into this one.
    captureBaseline(container)
    restoreStatusBand(container)
    paintSide(container, "rf_pda_side_info_tax",
        "Tax posture: on/off, year bill, March estimate, balance share, countdown.\n"
        .. "Daily rate and March rate differ. Esc never pays tax - use Tax HUD / Settings.")
    setText(findDescendant(container, "rfFwStatusTitle"), "")
    setVis(findDescendant(container, "rfFwStatusTitle"), false)

    local tax = getTax()
    local settings = tax and tax.settings
    local stats = tax and tax.stats
    if tax == nil or settings == nil or stats == nil then
        setText(findDescendant(container, "rfFwLine1"), tr("tax_rf_pda_waiting", "Tax manager not ready"))
        for i = 2, 8 do setText(findDescendant(container, "rfFwLine" .. i), "") end
        setText(findDescendant(container, "rfFwHint"), "")
        return
    end

    local onOff = settings.enabled and tr("tax_rf_pda_on", "On") or tr("tax_rf_pda_off", "Off")
    setText(findDescendant(container, "rfFwLine1"), labeled(tr("tax_rf_pda_lbl_enabled", "Tax"), onOff))

    local accum = tonumber(stats.taxesAccumulatedAnnual) or 0
    setText(findDescendant(container, "rfFwLine2"), labeled(tr("tax_rf_pda_lbl_accum", "Accumulated bill"), formatMoney(accum)))

    local annualRate = tonumber(settings.annualTaxRate) or 0.05
    local projected = math.floor(accum * annualRate)
    setText(findDescendant(container, "rfFwLine3"), labeled(tr("tax_rf_pda_lbl_projected", "Projected March payment"), formatMoney(projected)))

    local balance = 0
    local farmId = nil
    if g_farmManager ~= nil and g_currentMission ~= nil and type(g_currentMission.getFarmId) == "function" then
        farmId = g_currentMission:getFarmId()
        local farm = g_farmManager:getFarmById(farmId)
        balance = farm and farm.money or 0
    end
    local pct = balance > 0 and math.floor((projected / balance) * 100) or 0
    setText(findDescendant(container, "rfFwLine4"), labeled(tr("tax_rf_pda_lbl_pct", "Percent of balance"), string.format("%d%%", pct)))

    local env = g_currentMission and g_currentMission.environment
    local currentMonth = env and env.currentMonth or 1
    local advisoryMonth = stats.taxAdvisoryMonth or 12
    local returnMonth = stats.taxReturnMonth or 3
    local mToAdvisory = monthsUntil(advisoryMonth, currentMonth)
    local mToPayment = monthsUntil(returnMonth, currentMonth)
    local nextLine
    if mToPayment <= mToAdvisory then
        local when = mToPayment == 1 and tr("tax_rf_pda_next_month", "Next month!") or string.format("%d months", mToPayment)
        nextLine = labeled(tr("tax_rf_pda_next_pay", "Next: Tax payment"), when)
    else
        local when = mToAdvisory == 1 and tr("tax_rf_pda_next_month", "Next month!") or string.format("%d months", mToAdvisory)
        nextLine = labeled(tr("tax_rf_pda_next_adv", "Next: Advisory"), when)
    end
    setText(findDescendant(container, "rfFwLine5"), nextLine)

    -- Lifetime paid only. Never paint the returned-taxes total (no live writer).
    local paid = tonumber(stats.totalTaxesPaid) or 0
    setText(findDescendant(container, "rfFwLine6"), labeled(tr("tax_rf_pda_lbl_paid", "Lifetime paid"), formatMoney(paid)))

    -- Line 7: companion ledger credit/debit summary for current farm (honest empty if farm absent).
    local ledgerLbl = tr("tax_rf_pda_lbl_ledger", "Companion ledger")
    local farmLedger = nil
    local ledgerFarms = tax.ledger and tax.ledger.farms
    if ledgerFarms ~= nil and farmId ~= nil then
        farmLedger = ledgerFarms[farmId]
    end
    if farmLedger == nil then
        setText(findDescendant(container, "rfFwLine7"),
            labeled(ledgerLbl, tr("tax_rf_pda_ledger_none", "none yet")))
    else
        local credit = tonumber(farmLedger.creditTotal) or 0
        local debit = tonumber(farmLedger.debitTotal) or 0
        local pair = string.format("+%s / -%s", formatMoney(credit), formatMoney(debit))
        setText(findDescendant(container, "rfFwLine7"), labeled(ledgerLbl, pair))
    end

    -- Line 8: days taxed (0 is honest empty, not an error).
    local daysTaxed = tonumber(stats.daysTaxed) or 0
    setText(findDescendant(container, "rfFwLine8"),
        labeled(tr("tax_rf_pda_lbl_days", "Days taxed"), tostring(daysTaxed)))

    -- Hint: daily rate · March rate · min balance (distinct labels; never conflate).
    local rateKey = tostring(settings.taxRate or "medium")
    local dailyPct = (TAX_RATE_VALUES[rateKey] or 0.02) * 100
    local marchPct = annualRate * 100
    local minBal = tonumber(settings.minimumBalance) or 0
    local hint = string.format("%s: %s (%.0f%%) · %s: %.0f%% · %s: %s",
        tr("tax_rf_pda_lbl_daily_rate", "Daily rate"), rateKey, dailyPct,
        tr("tax_rf_pda_lbl_annual_rate", "March rate"), marchPct,
        tr("tax_rf_pda_lbl_min_balance", "Min balance"), formatMoney(minBal))
    setText(findDescendant(container, "rfFwHint"), hint)
end

--- Hand the Status shell back on the XML baseline. Status is tax-only today (host maps
--- isFwStatus = "tax") and no host calls onHide, so this is correct-when-wired rather than
--- live; it stays because the day status is shared is the day it matters, and onShow now
--- re-asserts the same baseline anyway.
function TaxRfPdaGuest.onHide(container)
    restoreStatusBand(container)
end

function TaxRfPdaGuest.tryRegister()
    if RfEscBootstrap ~= nil then
        if MOD_DIR == nil then
            print("[Tax] TaxRfPdaGuest: WARNING MOD_DIR nil - cannot ensureDoor")
        else
            local doorOk = RfEscBootstrap.ensureDoor(MOD_DIR, {
                profilesXml = MOD_DIR .. "xml/gui/rfEscProfiles.xml",
                iconPath = "textures/ui/menuIcon.dds",
            })
            if not doorOk then print("[Tax] TaxRfPdaGuest: WARNING ensureDoor failed (will retry)") end
        end
    end
    local host = getHost()
    local registerFn = host and (host.registerModule or host.registerPanel)
    if host == nil or registerFn == nil then return false end
    if not _registered then
        local ok = registerFn(host, {
            id = PANEL_ID,
            title = tr("tax_rf_pda_module_title", "Tax"),
            blurb = tr("tax_rf_pda_blurb", "Tax posture glance: on/off, bill, March, balance share, countdown, lifetime paid, ledger summary."),
            order = PANEL_ORDER,
            isAvailable = function() return getTax() ~= nil end,
            onShow = TaxRfPdaGuest.onShow,
            onHide = TaxRfPdaGuest.onHide,
        })
        if ok then
            _registered = true
            print("[Tax] TaxRfPdaGuest: registered module tax on rfEscModules")
        else
            return false
        end
    end
    return _registered and g_inGameMenu ~= nil and g_inGameMenu.menuRealisticFarming ~= nil
end

function TaxRfPdaGuest.isRegistered() return _registered end
function TaxRfPdaGuest.reset() _registered = false end
