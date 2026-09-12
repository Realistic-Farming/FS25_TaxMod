--!load: main.lua
-- RSF-F224 contract test, retargeted at the REAL repaired producer (FS25TaxMod).
-- The delivered draft was pure reference ("the actual owner functions are not
-- implemented"); per its instruction the scenarios are now bound to the real
-- FS25TaxMod._periodMonth (calendar adapter) and FS25TaxMod.getLoanTaxProjection
-- (pure cash-bill reader). Pure-arithmetic counterexamples that have no owner function
-- to bind to are retained as reference models and labelled REFERENCE.
-- Not proven here: native XML/save, real southern runtime labels, actual cash transfer,
-- Time Guard, GUI. Those are in-game observations.

T.ok("F224 setup: FS25TaxMod loaded", type(FS25TaxMod) == "table")
T.ok("F224 setup: real getLoanTaxProjection present", type(FS25TaxMod.getLoanTaxProjection) == "function")
T.ok("F224 setup: real _periodMonth present", type(FS25TaxMod._periodMonth) == "function")

-- Default settings already match the contract's terms: daily 0.02 (medium), annual 0.05,
-- minimum 1000. _spineScale is neutral (no SettingsHub), so the real rates are used.
local mission = {
    environment = { currentYear = 1, currentPeriod = 1, currentDay = 1,
        currentMonotonicDay = 1, currentDayInPeriod = 1, daysPerPeriod = 3, dayTime = 0,
        daylight = { latitude = 0.5 } },  -- northern
    getFarmId   = function() return nil end,   -- dedicated: no local-farm notify/HUD path
    getIsServer = function() return true end,
    addMoney    = function() end,
    missionInfo = {},                          -- no savegameDirectory => saveSettings no-ops
}
g_currentMission = mission

-- ── GROUP A: the REAL period -> calendar-month adapter ──────────────────────────
T.eq("F224 A1 REAL period 1 maps to March (3)",  FS25TaxMod._periodMonth(1),  3)
T.eq("F224 A2 REAL period 3 maps to May (5)",    FS25TaxMod._periodMonth(3),  5)
T.eq("F224 A3 REAL period 10 maps to December (12)", FS25TaxMod._periodMonth(10), 12)
T.eq("F224 A4 REAL period 11 wraps to January (1)", FS25TaxMod._periodMonth(11), 1)

-- Hemisphere change busts the cache; the adapter rebuilds from the new formatPeriod.
mission.environment.daylight.latitude = -0.5
g_i18n.formatPeriod = function(_self, period)
    if type(period) ~= "number" then return nil end
    return "ui_month" .. (((period + 7) % 12) + 1)  -- synthetic southern output
end
T.eq("F224 A5 REAL southern rebuild follows formatPeriod output", FS25TaxMod._periodMonth(1), 9)
-- Restore northern for the projection group.
mission.environment.daylight.latitude = 0.5
g_i18n.formatPeriod = function(_self, period)
    if type(period) ~= "number" then return nil end
    return "ui_month" .. (((period + 1) % 12) + 1)
end

-- REFERENCE: bijection rejection (ambiguous / unknown label). Models _buildPeriodMonthMap's
-- rejection logic, which has no standalone owner entry point to bind to.
local function monthMap(labels, monthNames)
    local result, used = {}, {}
    for period = 1, 12 do
        local found = nil
        for month = 1, 12 do
            if labels[period] == monthNames[month] then
                if found ~= nil then return nil end
                found = month
            end
        end
        if found == nil or used[found] then return nil end
        result[period], used[found] = found, true
    end
    return result
end
local names, north = {}, {}
for i = 1, 12 do names[i] = "month-key-" .. i end
for i = 1, 12 do north[i] = names[((i + 1) % 12) + 1] end
T.eq("F224 A6 REFERENCE northern bijection builds", monthMap(north, names)[1], 3)
local duplicate = {}; for i = 1, 12 do duplicate[i] = north[i] end; duplicate[2] = duplicate[1]
T.eq("F224 A7 REFERENCE ambiguous mapping refuses", monthMap(duplicate, names), nil)
local missing = {}; for i = 1, 12 do missing[i] = north[i] end; missing[2] = "unknown"
T.eq("F224 A8 REFERENCE unknown label refuses", monthMap(missing, names), nil)

-- ── GROUP B: the REAL pure cash-bill reader (getLoanTaxProjection) ───────────────
local function setFarm(acc, paidYear, imported)
    FS25TaxMod.stats.farmTax = FS25TaxMod.stats.farmTax or {}
    FS25TaxMod.stats.farmTax[7] = {
        taxesAccumulatedAnnual = acc, daysTaxed = 0, lastTaxYear = paidYear, imported = imported or {},
    }
end
-- Scenario samples carry the NATIVE period; the reader maps it to the named month.
local P_MARCH, P_APRIL = 1, 2  -- _periodMonth(1)=3 (March), _periodMonth(2)=4 (April)

setFarm(20000, 0)
local r1 = FS25TaxMod.getLoanTaxProjection(7, { { isFuture = false, period = P_MARCH, year = 1, balance = 500, monotonicDay = 100, timeOfDayMs = 0 } })
T.eq("F224 B1 accrued basis becomes the cash bill, not the raw accumulator", r1.cashEvents[1] and r1.cashEvents[1].amount, 1000)
T.eq("F224 B2 read does not reset the live accumulator", FS25TaxMod.stats.farmTax[7].taxesAccumulatedAnnual, 20000)
T.eq("F224 B3 read does not advance the live paid year", FS25TaxMod.stats.farmTax[7].lastTaxYear, 0)
T.eq("F224 B4 annual bill is not capped by current cash", (r1.cashEvents[1].amount > 500), true)
T.eq("F224 B5 read carries the due-day field", r1.cashEvents[1].dueDay, 100)
T.eq("F224 B6 read status OK", r1.status, "OK")

local same = FS25TaxMod.getLoanTaxProjection(7, { { isFuture = false, period = P_MARCH, year = 1, balance = 500, monotonicDay = 100, timeOfDayMs = 0 } })
T.eq("F224 B7 repeat read quotes the same bill without settling", same.cashEvents[1].amount, 1000)

local r2 = FS25TaxMod.getLoanTaxProjection(7, {
    { isFuture = true, period = P_MARCH, year = 1, balance = 100000, monotonicDay = 100, timeOfDayMs = 0 },
    { isFuture = true, period = P_MARCH, year = 1, balance = 100000, monotonicDay = 101, timeOfDayMs = 0 },
})
T.eq("F224 B8 daily accumulation precedes the annual price", r2.cashEvents[1].amount, 1100)
T.eq("F224 B9 one cash event for repeated March days", #r2.cashEvents, 1)
T.eq("F224 B10 future accrual is flagged", r2.futureAccrualIncluded, true)

setFarm(5000, 1)
local paid = FS25TaxMod.getLoanTaxProjection(7, { { isFuture = true, period = P_MARCH, year = 1, balance = 100000, monotonicDay = 100, timeOfDayMs = 0 } })
T.eq("F224 B11 a processed paid-year guard suppresses the bill", #paid.cashEvents, 0)

setFarm(20000, 0)
FS25TaxMod.settings.enabled = false
local off = FS25TaxMod.getLoanTaxProjection(7, { { isFuture = true, period = P_MARCH, year = 1, balance = 100000, monotonicDay = 100, timeOfDayMs = 0 } })
T.eq("F224 B12 disabled has no scheduled cash event", #off.cashEvents, 0)
T.eq("F224 B13 disabled retains the accumulated obligation", FS25TaxMod.stats.farmTax[7].taxesAccumulatedAnnual, 20000)
FS25TaxMod.settings.enabled = true

local skip = FS25TaxMod.getLoanTaxProjection(7, { { isFuture = true, period = P_APRIL, year = 4, balance = 0, monotonicDay = 200, timeOfDayMs = 0 } })
T.eq("F224 B14 a skip past March does not replay missed years", #skip.cashEvents, 0)
T.eq("F224 B15 skip retains the accrued state", FS25TaxMod.stats.farmTax[7].taxesAccumulatedAnnual, 20000)

local nextMar = FS25TaxMod.getLoanTaxProjection(7, { { isFuture = true, period = P_MARCH, year = 5, balance = 0, monotonicDay = 300, timeOfDayMs = 0 } })
T.eq("F224 B16 the next real March bills the accumulator once", nextMar.cashEvents[1].amount, 1000)
T.eq("F224 B17 no multiplication by missed years", #nextMar.cashEvents, 1)

-- Per-bucket flooring on the real reader (pooled MP->SP buckets): floor each, then sum.
setFarm(30, 1, { { acc = 30, paidYear = 1 } })
local frac = FS25TaxMod.getLoanTaxProjection(7, { { isFuture = false, period = P_MARCH, year = 2, balance = 500, monotonicDay = 101, timeOfDayMs = 0 } })
T.eq("F224 B18 each retained bucket is floored before summing (2, not 3)", frac.cashEvents[1].amount, 2)
T.eq("F224 B19 REFERENCE the combined-floor counterexample would overcharge", math.floor((30 + 30) * 0.05), 3)

-- DOT vs COLON call contract: a colon call passes the module table as farmId.
setFarm(20000, 0)
local scenario = { { isFuture = true, period = P_MARCH, year = 1, balance = 1000, monotonicDay = 100, timeOfDayMs = 0 } }
T.eq("F224 B20 dot call produces a real snapshot", FS25TaxMod.getLoanTaxProjection(7, scenario).status, "OK")
T.eq("F224 B21 colon call is the wrong contract -> UNAVAILABLE", FS25TaxMod:getLoanTaxProjection(7, scenario).status, "UNAVAILABLE")
T.eq("F224 B22 a non-number farm is UNAVAILABLE", FS25TaxMod.getLoanTaxProjection("x", scenario).status, "UNAVAILABLE")

-- "Owner finds March inside the full horizon; later samples cannot change the bill."
setFarm(20000, 0)
local full = {
    { isFuture = true, period = 12, year = 1, balance = 1000, monotonicDay = 98,  timeOfDayMs = 0 }, -- month 2
    { isFuture = true, period = P_MARCH, year = 1, balance = 1000, monotonicDay = 99, timeOfDayMs = 0 },
    { isFuture = true, period = P_APRIL, year = 1, balance = 999999, monotonicDay = 100, timeOfDayMs = 0 },
}
local quoted = FS25TaxMod.getLoanTaxProjection(7, full)
T.eq("F224 B23 owner finds March inside the full horizon", #quoted.cashEvents, 1)
T.eq("F224 B24 later samples cannot change the first bill", quoted.cashEvents[1].amount, 1002)

-- ── REFERENCE counterexamples (pure arithmetic; no owner function to bind) ───────
local cash, minCash = 500, 500
for _, delta in ipairs({ -1000, 2000 }) do cash = cash + delta; minCash = math.min(minCash, cash) end
T.eq("F224 C1 REFERENCE a known tax bill can precede a later receipt", minCash, -500)
T.eq("F224 C2 REFERENCE a positive endpoint does not erase the earlier shortage", cash, 1500)
do
    local buckets = { { id = "a", farm = 1, acc = 10000, paidYear = 7 }, { id = "b", farm = 2, acc = 20000, paidYear = 6 } }
    local map = { [2] = 1 }; for _, x in ipairs(buckets) do x.farm = map[x.farm] or x.farm end
    local c = 0
    for _, x in ipairs(buckets) do if x.paidYear < 7 then c = c + math.floor(x.acc * 0.05); x.acc = 0; x.paidYear = 7 end end
    T.eq("F224 C3 REFERENCE pool charges only the source bucket not yet paid this year", c, 1000)
    T.eq("F224 C4 REFERENCE the already-paid farm's later accumulator remains", buckets[1].acc, 10000)
end

T.summary()
