-- =====================================================================
-- CropStressIrrigationExpense.lua  (SCS-011)
-- Mirror SeasonalCropStress irrigation operating cost into the TaxMod
-- ledger as a deductible expense line, once per in-game day.
--
-- READ-ONLY over the SCS B3.2b companion facade (getIrrigationSystems /
-- getIrrigationCostsEnabled on g_currentMission.cropStressManager). It moves
-- NO money: recordExpense is bookkeeping only. SCS itself already deducts the
-- operating cost each active hour (FinanceIntegration), so this line reflects a
-- charge the player is already paying -- it never adds a second one, so there
-- is no double-charge (the CC-1 decision).
--
-- Run-time is DERIVED from each system's schedule (there is no runtime counter
-- in the snapshot), matching the same day-of-week + window logic SCS uses to
-- flip a system active (IrrigationManager:hourlyScheduleCheck). This is an
-- accepted approximation for a bookkeeping mirror: it does not see a system
-- that lost its water source or was placed mid-day. Gated on SCS's own
-- costsEnabled so it never reports a cost the player has switched off.
-- =====================================================================

CropStressIrrigationExpense = {}

-- Optional daily depreciation per scheduled system. 0 = off. A real schedule
-- needs a per-system capital value + useful life that the facade snapshot does
-- not carry, and the number is a balance-pass call, so it ships neutral (0)
-- and wired, not fabricated (brief OI-2 / OI-3).
CropStressIrrigationExpense.DAILY_DEPRECIATION_PER_SYSTEM = 0

-- Day-of-week index 1..7, matching SCS IrrigationManager:dayOfWeekIndex (F160),
-- so our accrual lands on the same days SCS actually runs a system. Derived from
-- the monotonic day modulo 7, never from env.currentDayInPeriod: the base game
-- computes currentDayInPeriod as (currentDay - 1) % daysPerPeriod + 1 and
-- daysPerPeriod defaults to 1, so on a default save it is always 1.
local function dayOfWeekIndex(env)
    if env == nil then return 1 end
    local currentDay = env.currentDay or env.currentMonotonicDay or 1
    if type(currentDay) ~= "number" or currentDay < 1 then currentDay = 1 end
    local dow = ((currentDay - 1) % 7) + 1
    if dow < 1 or dow > 7 then dow = 1 end
    return dow
end

-- Scheduled active hours for one system today, from its schedule window, using
-- the same wrap-around math as SCS. 0 when the system does not run today.
local function scheduledHoursToday(system, dow)
    local sched = system.schedule
    if sched == nil or sched.activeDays == nil then return 0 end
    if sched.activeDays[dow] ~= true then return 0 end
    local s = sched.startHour
    local e = sched.endHour
    if type(s) ~= "number" or type(e) ~= "number" then return 0 end
    if s <= e then return e - s end
    return (24 - s) + e   -- wrap-around (e.g. 23 -> 2)
end

local function resolveLabel(key, fallback)
    if g_i18n ~= nil then
        local t = g_i18n:getText(key)
        if t ~= nil and t ~= key then return t end
    end
    return fallback
end

-- Accrue one in-game day of irrigation operating cost into the TaxMod ledger.
-- Called once per day-change from main.lua's daily tick. Server-only, neutral
-- (records nothing) whenever SCS is absent, costs are off, or no system runs.
function CropStressIrrigationExpense.accrueDaily(taxManager)
    if taxManager == nil then return end
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end

    -- SCS facade handle (mission-bound; never the bare global as the primary).
    local csm = g_currentMission.cropStressManager or g_cropStressManager
    if csm == nil or type(csm.getIrrigationSystems) ~= "function" then return end

    -- Respect SCS's own irrigation-costs toggle: if the player disabled it, SCS
    -- charges nothing, so we must mirror nothing. Getter is optional (older SCS
    -- builds lack it); default to enabled when it is not present.
    if type(csm.getIrrigationCostsEnabled) == "function" then
        local ok, enabled = pcall(csm.getIrrigationCostsEnabled, csm)
        if ok and enabled == false then return end
    end

    local ok, systems = pcall(csm.getIrrigationSystems, csm)
    if not ok or type(systems) ~= "table" then return end

    local env = g_currentMission.environment
    local dow = dayOfWeekIndex(env)

    local operating = 0
    local scheduledSystems = 0
    for _, sys in ipairs(systems) do
        local hours = scheduledHoursToday(sys, dow)
        if hours > 0 then
            scheduledSystems = scheduledSystems + 1
            if type(sys.operationalCostPerHour) == "number" then
                operating = operating + sys.operationalCostPerHour * hours
            end
        end
    end

    if operating <= 0 and scheduledSystems == 0 then return end

    -- Attribute to the local player's farm -- the same farm SCS's
    -- FinanceIntegration charges (it deducts from the local player's owner farm),
    -- via TaxMod's own idiom so the mirror never disagrees with what SCS moved.
    local farmId = g_currentMission.getFarmId and g_currentMission:getFarmId()
    if type(farmId) ~= "number" or farmId <= 0 then return end

    if operating > 0 then
        taxManager.recordExpense(farmId, -operating,
            resolveLabel("tm_irrigation_operations", "Irrigation Operations"))
    end

    local depr = CropStressIrrigationExpense.DAILY_DEPRECIATION_PER_SYSTEM
    if depr > 0 and scheduledSystems > 0 then
        taxManager.recordExpense(farmId, -(depr * scheduledSystems),
            resolveLabel("tm_irrigation_assets", "Irrigation Assets"))
    end
end
