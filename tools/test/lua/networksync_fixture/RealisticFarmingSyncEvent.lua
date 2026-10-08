-- =========================================================
-- FS25_NetworkSync - network event classes (v2)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Three event classes carry the ecosystem's multiplayer sync:
--
--   RealisticFarmingSyncEvent         server -> client(s): a batch of per-module
--     frames. Used for the 1Hz dirty batch, syncNow, the join snapshot, and the
--     slow drift-floor full resync. v2 wraps each module's value array in a frame:
--
--       frame: modId (string), chunkIndex (int32), chunkCount (int32),
--              mode (UInt8: 0 FULL / 1 DELTA), subLength (int32), sub-values...
--
--     A module that fits one event is a single frame (chunkIndex 0, chunkCount 1),
--     so small and large modules use the exact same frame. A module larger than the
--     event budget is split into ordered chunks that reassemble on the client. The
--     value encoding inside a frame is byte-for-byte the v1 typed encoding below:
--     no new value types were introduced, so a module that never sends a delta and
--     never splits carries the same value bytes it did in v1.
--
--   RealisticFarmingSyncRequestEvent  client -> server: "send me a full snapshot"
--     on join. The server answers with a SyncEvent (FULL frames) to that connection.
--
--   RealisticFarmingActionEvent       client -> server: a validated request for a
--     server-authoritative action (Path 3). The server authorizes the requester
--     (master user, or the action's own gate) and applies it; the resulting state
--     change flags its module dirty and the normal sync path carries the result down.
--
-- Per-value type tagging (unchanged from v1): each value is a UInt8 tag then the
-- typed value. Integers that fit int32 are sent as int32 (exact); fractional or
-- out-of-range numbers fall back to float32; booleans and strings have their own tags.
-- =========================================================

RealisticFarmingSyncEvent = RealisticFarmingSyncEvent or {}
local RealisticFarmingSyncEvent_mt = Class(RealisticFarmingSyncEvent, Event)
InitEventClass(RealisticFarmingSyncEvent, "RealisticFarmingSyncEvent")

-- Value type tags (UInt8).
RealisticFarmingSyncEvent.T_BOOL   = 0
RealisticFarmingSyncEvent.T_INT    = 1
RealisticFarmingSyncEvent.T_FLOAT  = 2
RealisticFarmingSyncEvent.T_STRING = 3

local INT32_MIN = -2147483648
local INT32_MAX = 2147483647

-- Write a single tagged value (shared by sync frames and action args).
local function writeValue(streamId, v)
    local t = type(v)
    if t == "boolean" then
        streamWriteUInt8(streamId, RealisticFarmingSyncEvent.T_BOOL)
        streamWriteBool(streamId, v)
    elseif t == "number" then
        if v == v and v ~= math.huge and v ~= -math.huge
            and math.floor(v) == v and v >= INT32_MIN and v <= INT32_MAX then
            streamWriteUInt8(streamId, RealisticFarmingSyncEvent.T_INT)
            streamWriteInt32(streamId, v)
        else
            streamWriteUInt8(streamId, RealisticFarmingSyncEvent.T_FLOAT)
            streamWriteFloat32(streamId, (v == v) and v or 0)
        end
    elseif t == "string" then
        streamWriteUInt8(streamId, RealisticFarmingSyncEvent.T_STRING)
        streamWriteString(streamId, v)
    else
        NSLogger.warning("sync: unsupported value of type %s, sending 0", t)
        streamWriteUInt8(streamId, RealisticFarmingSyncEvent.T_FLOAT)
        streamWriteFloat32(streamId, 0)
    end
end

local function readValue(streamId)
    local tag = streamReadUInt8(streamId)
    if tag == RealisticFarmingSyncEvent.T_BOOL then
        return streamReadBool(streamId)
    elseif tag == RealisticFarmingSyncEvent.T_INT then
        return streamReadInt32(streamId)
    elseif tag == RealisticFarmingSyncEvent.T_STRING then
        return streamReadString(streamId)
    else
        return streamReadFloat32(streamId)
    end
end

-- Exposed so the core and tests can reuse the exact encoding.
RealisticFarmingSyncEvent.writeValue = writeValue
RealisticFarmingSyncEvent.readValue  = readValue

-- READ BOUNDS (MAINTENANCE row 118). The server reads every registered event a client
-- sends (network/Server.lua:436) BEFORE any guard in run, so a forged count in a
-- readStream loop is a hang vector on any host, dedicated included. Each count is held
-- to what the WRITER can produce, derived from the chunker in NetworkSync.lua: a frame's
-- values are split to fit EVENT_BUDGET_BYTES at no less than 2 estimated bytes each
-- (estimateValueBytes, a boolean), and an event's frames are batched to fit the same
-- budget at no less than 16 estimated bytes each (estimateFrameBytes with a one-char
-- module id and no values). A count outside that is a forged stream, refused the scoped
-- event's way (NetworkSyncScopedEvent.lua:125-130): the event marks itself malformed,
-- reads no further and never runs. Reading short costs nobody but the sender: the
-- server's event branch handles one message per packet with no loop (Server.lua
-- :413-448), and a sender puts each event on its own stream (netSendStream right after
-- writeStream, Connection.lua:99), so the unread rest is that one packet's and no
-- other. Note the engine's own bit check (Server.lua:438-446) runs only when the SENDER
-- wrote the debug flag (read at :427; written as g_networkDebug with the size word only
-- when set, Connection.lua:85-90): a forged stream writes false, so a refused event
-- leaves no error line. The action writer has no chunker of its own, so its
-- args take the same per-frame value ceiling (the fleet's largest sender passes three).
RealisticFarmingSyncEvent.MAX_EVENT_FRAMES = 512    -- EVENT_BUDGET_BYTES 8192 / 16
RealisticFarmingSyncEvent.MAX_FRAME_VALUES = 4096   -- EVENT_BUDGET_BYTES 8192 / 2

--- A count a writer could have written: a number from 0 to its bound (a nil is a
--- short stream on the bench's typed mock; the engine's stream never returns one).
local function countWithinBound(n, bound)
    return type(n) == "number" and n >= 0 and n <= bound
end
RealisticFarmingSyncEvent.countWithinBound = countWithinBound

function RealisticFarmingSyncEvent.emptyNew()
    return Event.new(RealisticFarmingSyncEvent_mt)
end

---@param frames table  array of { modId, chunkIndex, chunkCount, mode, values }
function RealisticFarmingSyncEvent.new(frames)
    local self = RealisticFarmingSyncEvent.emptyNew()
    self.frames = frames or {}
    return self
end

function RealisticFarmingSyncEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, #self.frames)
    for _, f in ipairs(self.frames) do
        streamWriteString(streamId, f.modId)
        streamWriteInt32(streamId, f.chunkIndex or 0)
        streamWriteInt32(streamId, f.chunkCount or 1)
        streamWriteUInt8(streamId, f.mode or 0)
        local values = f.values or {}
        local n = #values
        streamWriteInt32(streamId, n)
        for i = 1, n do
            writeValue(streamId, values[i])
        end
    end
end

function RealisticFarmingSyncEvent:readStream(streamId, connection)
    self.frames = {}
    -- Only a server sends sync frames, and the server never reads its own (broadcastEvent
    -- skips the local stream). A sync event arriving at a server is a client's forgery:
    -- read none of it (row 118; the early return in run at the end came after the reads).
    if g_currentMission ~= nil and g_currentMission:getIsServer() then
        self.malformed = "WRONG_SIDE"
        return
    end
    local count = streamReadInt32(streamId)
    if not countWithinBound(count, RealisticFarmingSyncEvent.MAX_EVENT_FRAMES) then
        self.malformed = "FRAME_COUNT_OUT_OF_RANGE"
        return
    end
    for _ = 1, count do
        local modId      = streamReadString(streamId)
        local chunkIndex = streamReadInt32(streamId)
        local chunkCount = streamReadInt32(streamId)
        local mode       = streamReadUInt8(streamId)
        local n          = streamReadInt32(streamId)
        if not countWithinBound(n, RealisticFarmingSyncEvent.MAX_FRAME_VALUES) then
            self.malformed = "VALUE_COUNT_OUT_OF_RANGE"
            return
        end
        local values = {}
        for i = 1, n do
            values[i] = readValue(streamId)
        end
        self.frames[#self.frames + 1] = {
            modId = modId, chunkIndex = chunkIndex, chunkCount = chunkCount,
            mode = mode, values = values,
        }
    end
    self:run(connection)
end

function RealisticFarmingSyncEvent:run(connection)
    -- Only a pure client applies received state. On a listen server (host)
    -- getIsServer() is true and the host already holds authoritative state.
    if g_currentMission ~= nil and g_currentMission:getIsServer() then
        return
    end
    if g_networkSync ~= nil then
        g_networkSync:receiveFrames(self.frames)
    end
end

-- =========================================================
-- Full-sync request (client -> server, on join)
-- =========================================================

RealisticFarmingSyncRequestEvent = RealisticFarmingSyncRequestEvent or {}
local RealisticFarmingSyncRequestEvent_mt = Class(RealisticFarmingSyncRequestEvent, Event)
InitEventClass(RealisticFarmingSyncRequestEvent, "RealisticFarmingSyncRequestEvent")

function RealisticFarmingSyncRequestEvent.emptyNew()
    return Event.new(RealisticFarmingSyncRequestEvent_mt)
end

function RealisticFarmingSyncRequestEvent.new()
    return RealisticFarmingSyncRequestEvent.emptyNew()
end

function RealisticFarmingSyncRequestEvent:writeStream(streamId, connection)
    -- no payload; the request itself is the signal
end

function RealisticFarmingSyncRequestEvent:readStream(streamId, connection)
    self:run(connection)
end

function RealisticFarmingSyncRequestEvent:run(connection)
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return
    end
    if g_networkSync ~= nil then
        g_networkSync:sendFullSnapshotTo(connection)
    end
end

-- =========================================================
-- Action channel (client -> server, validated) - Path 3
-- =========================================================
-- Modeled exactly on the request event above: a working client-to-server event
-- whose run(connection) guards on getIsServer. We add a typed-arg payload and route
-- to the server-side authorization + dispatch in NetworkSync:_applyAction, which
-- resolves the connection to its user and enforces the action's admin gate. A
-- rejected or unknown action applies nothing (a plain early return), matching the
-- request event's no-op-on-non-server pattern.

RealisticFarmingActionEvent = RealisticFarmingActionEvent or {}
local RealisticFarmingActionEvent_mt = Class(RealisticFarmingActionEvent, Event)
InitEventClass(RealisticFarmingActionEvent, "RealisticFarmingActionEvent")

function RealisticFarmingActionEvent.emptyNew()
    return Event.new(RealisticFarmingActionEvent_mt)
end

---@param actionId string  registered action id
---@param args table       typed arg array (int/float/bool/string), may be nil
function RealisticFarmingActionEvent.new(actionId, args)
    local self = RealisticFarmingActionEvent.emptyNew()
    self.actionId = actionId or ""
    self.args = args or {}
    return self
end

function RealisticFarmingActionEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.actionId)
    local n = #self.args
    streamWriteInt32(streamId, n)
    for i = 1, n do
        writeValue(streamId, self.args[i])
    end
end

RealisticFarmingActionEvent.MAX_ARGS = RealisticFarmingSyncEvent.MAX_FRAME_VALUES

function RealisticFarmingActionEvent:readStream(streamId, connection)
    self.actionId = streamReadString(streamId)
    local n = streamReadInt32(streamId)
    self.args = {}
    -- Row 118: a count past the value ceiling is a forged stream; read no further, never run.
    if not countWithinBound(n, RealisticFarmingActionEvent.MAX_ARGS) then
        self.malformed = "ARG_COUNT_OUT_OF_RANGE"
        return
    end
    for i = 1, n do
        self.args[i] = readValue(streamId)
    end
    self:run(connection)
end

function RealisticFarmingActionEvent:run(connection)
    -- Server-only, same guard as the request event. Authorization + dispatch lives
    -- in the core so it can resolve the connection to its user.
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return
    end
    if g_networkSync ~= nil then
        g_networkSync:_applyAction(self.actionId, self.args, connection)
    end
end
