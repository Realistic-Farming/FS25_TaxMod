-- prelude.lua - minimal FS25 engine mock + tiny test framework for FS25_TaxMod.
-- Loaded first by run-tests.mjs, before main.lua and the test file. TaxMod's main.lua
-- is a monolithic entry point: it source()s sibling files and installs Mission00 /
-- FSBaseMission hooks at load time, so this prelude stubs exactly that load surface.
-- The real FS25TaxMod table (with .stats/.settings/.getLoanTaxProjection/._periodMonth)
-- is populated once main.lua loads against these stubs.

unpack = unpack or table.unpack

-- FS25 OO helper.
function Class(base)
  local mt = {}
  mt.__index = base or mt
  return mt
end

-- Mod directory latch: main.lua concatenates modDirectory .. "src/..." for source(),
-- so it must be a non-nil string even though source() is a no-op here.
g_currentModDirectory = "./"
g_currentModName = "FS25_TaxMod"
g_modsDirectory = "./"

-- source(): no-op. The sibling files (TaxHUD, bridges, RfEsc, ...) are not needed for
-- the pure producer logic under test; their globals stay nil and are guarded at load.
function source(_path) end

-- Lifecycle classes whose methods main.lua assigns via Utils hooks. Plain tables; the
-- hooks are never invoked in these offline tests.
Mission00 = Mission00 or {}
FSBaseMission = FSBaseMission or {}
FSCareerMissionInfo = FSCareerMissionInfo or {}

Utils = Utils or {}
function Utils.prependedFunction(_old, new) return new end
function Utils.appendedFunction(_old, new) return new end
function Utils.getNoNil(v, d) if v == nil then return d else return v end end

function addModEventListener(_l) end
function addConsoleCommand(_n, _d, _f, _t) end
function createFolder(_p) end

-- Engine globals the functions under test may touch at call time.
g_currentMission = nil  -- each test sets its own mission stub
MoneyType = { OTHER = 3, AI = 1, WORKER_WAGES = 2 }
FarmManager = { SPECTATOR_FARM_ID = 0, GUIDED_TOUR_FARM_ID = 14, INVALID_FARM_ID = 15 }

Logging = { info = function() end, warning = function() end, error = function() end }

-- i18n: getText echoes unique month labels; formatPeriod models the NORTHERN mapping
-- period -> ((period+1) % 12) + 1 (period 1 => month 3 = March), matching the engine's
-- real formatPeriod northern path. Tests that need the southern path override this.
g_i18n = {
  getText = function(_self, key) return key end,
  hasText = function(_self, key)
    if type(key) ~= "string" then return false end
    return key:sub(1, 8) == "ui_month"
  end,
  formatPeriod = function(_self, period, _short)
    if type(period) ~= "number" then return nil end
    local month = ((period + 1) % 12) + 1
    return "ui_month" .. month
  end,
  formatMoney = function(_self, amount) return "$" .. tostring(amount) end,
}

-- XML + misc globals (only reached if a test drives a save path; harmless stubs).
function createXMLFile() return 0 end
function loadXMLFile() return 0 end
function saveXMLFile() end
function fileExists() return false end
function delete() end
function setXMLInt() end
function setXMLFloat() end
function setXMLString() end
function setXMLBool() end
function getXMLInt() return nil end
function getXMLFloat() return nil end
function getXMLString() return nil end
function getXMLBool() return nil end

-- ── tiny test framework (same markers run-tests.mjs parses) ──
T = { _pass = 0, _fail = 0 }
local function _pass(name) T._pass = T._pass + 1; print("##TEST_PASS " .. name) end
local function _fail(name, msg) T._fail = T._fail + 1; print("##TEST_FAIL " .. name .. " :: " .. tostring(msg)) end
function T.ok(name, cond, msg) if cond then _pass(name) else _fail(name, msg or "expected truthy, got " .. tostring(cond)) end end
function T.eq(name, got, want) if got == want then _pass(name) else _fail(name, "got " .. tostring(got) .. " want " .. tostring(want)) end end
function T.near(name, got, want, tol)
  tol = tol or 1e-6
  if type(got) == "number" and math.abs(got - want) <= tol then _pass(name)
  else _fail(name, "got " .. tostring(got) .. " want ~" .. tostring(want) .. " (tol " .. tol .. ")") end
end
function T.summary() print("##TEST_SUMMARY " .. T._pass .. " " .. T._fail) end
