--!load: tools/test/lua/f201_model_binding.lua, tools/test/lua/f201_boot.lua, main.lua
-- RSF-F201 (detail 7), TaxMod PLAYER-lifetime companion, run against the REAL
-- production main.lua: onLoad installs the PlayerInputComponent wrapper once per
-- loaded script environment, onUnload switches registration off and no longer
-- restores the predecessor, a second onLoad re-arms the same wrapper.
-- The binding is the F201 model, not the native InputBinding; native key
-- delivery, save, MP and GUI are in-game observations (TESTING.md).

local noop = function() end
getfenv = getfenv or function() return _G end
GS_PRIO_NORMAL = GS_PRIO_NORMAL or 1

local b = F201Model.installEngine({ "TM_TOGGLE_HUD", "TM_HUD_DRAG" })
local native = PlayerInputComponent.registerActionEvents
local nativeCalls = 0
PlayerInputComponent.registerActionEvents = function(...) nativeCalls = nativeCalls + 1 end
native = PlayerInputComponent.registerActionEvents

local activeDuringHudDelete = "unset"
local hudsCreated = 0
TaxHUD = { new = function()
    hudsCreated = hudsCreated + 1
    return { visible = true, editMode = false, saveLayout = noop, loadLayout = noop, toggleVisibility = noop,
             exitEditMode = noop, enterEditMode = noop,
             delete = function() activeDuringHudDelete = FS25TaxMod._inputActive end }
end }
TaxSettingsUI = { new = function() return { inject = noop } end }

local mission = {
    getIsClient = function() return true end,
    getIsServer = function() return true end,
    missionInfo = {},
    environment = { currentDay = 1, currentPeriod = 1, dayTime = 0, daylight = { latitude = 0.5 } },
    addUpdateable = noop, removeUpdateable = noop,
}
g_currentMission = mission

-- prelude Utils.prependedFunction returns the new function, so Mission00.load IS onLoad
-- and FSBaseMission.delete IS onUnload.
T.ok("F201 Tax setup: FS25TaxMod loaded", type(FS25TaxMod) == "table")

-- GROUP A: first load installs one wrapper and arms it
Mission00.load(mission)
local w1 = PlayerInputComponent.registerActionEvents
T.ok("F201 Tax A1 onLoad wraps registerActionEvents", w1 ~= native)
T.eq("F201 Tax A2 install latch set", FS25TaxMod._inputHookInstalled, true)
T.eq("F201 Tax A3 predecessor held on the module table", FS25TaxMod._inputHookOriginal, native)
T.eq("F201 Tax A4 registration armed", FS25TaxMod._inputActive, true)
T.eq("F201 Tax A5 one HUD created", hudsCreated, 1)

-- GROUP B: the owning player callback registers both actions once
local ic = { player = { isOwner = true } }
w1(ic)
T.eq("F201 Tax B1 predecessor called", nativeCalls, 1)
T.eq("F201 Tax B2 two registrations", b.attempts, 2)
T.ok("F201 Tax B3 toggle handle stored", FS25TaxMod.toggleHUDEventId ~= nil)
T.ok("F201 Tax B4 drag handle stored", FS25TaxMod.hudDragEventId ~= nil)
T.eq("F201 Tax B5 drag label set", b.events[FS25TaxMod.hudDragEventId].text, "input_TM_HUD_DRAG")
w1(ic)
T.eq("F201 Tax B6 second callback trips the existing guard, no re-registration", b.attempts, 2)
w1({ player = { isOwner = false } })
T.eq("F201 Tax B7 a non-owning player registers nothing", b.attempts, 2)

-- GROUP C: unload switches off first, cleans up, restores nothing
FSBaseMission.delete()
T.eq("F201 Tax C1 registration inactive while the HUD was deleted", activeDuringHudDelete, false)
T.eq("F201 Tax C2 toggle handle cleared", FS25TaxMod.toggleHUDEventId, nil)
T.eq("F201 Tax C3 drag handle cleared", FS25TaxMod.hudDragEventId, nil)
T.eq("F201 Tax C4 both events removed from the binding", b:totalIn("PLAYER"), 0)
T.eq("F201 Tax C5 the wrapper is NOT restored", PlayerInputComponent.registerActionEvents, w1)
T.eq("F201 Tax C6 the predecessor is still held", FS25TaxMod._inputHookOriginal, native)
w1(ic)
T.eq("F201 Tax C7 predecessor still called while inactive", nativeCalls, 4)
T.eq("F201 Tax C8 inactive wrapper registers nothing", b.attempts, 2)

-- GROUP D: second load re-arms the same wrapper, no stacking
Mission00.load(mission)
T.eq("F201 Tax D1 no second wrapper", PlayerInputComponent.registerActionEvents, w1)
T.eq("F201 Tax D2 re-armed", FS25TaxMod._inputActive, true)
T.eq("F201 Tax D3 HUD recreated", hudsCreated, 2)
w1(ic)
T.eq("F201 Tax D4 keys registered on the second load", b.attempts, 4)
T.ok("F201 Tax D5 toggle handle stored again", FS25TaxMod.toggleHUDEventId ~= nil)
T.eq("F201 Tax D6 both events resident", b:totalIn("PLAYER"), 2)

-- GROUP E: the wrapper reads the module field, not a file-local upvalue
FS25TaxMod.taxHUD = nil
FS25TaxMod.toggleHUDEventId = nil
w1(ic)
T.eq("F201 Tax E1 no HUD on the module table means no registration", b.attempts, 4)
