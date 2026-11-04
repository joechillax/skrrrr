-- Quick Match automation for the supplied 80007766855741 game export.
-- Execute in the live game after the lobby loads. No external downloads.
-- F6: pause/resume; F7: auto join on/off; F8: unload; F9: Quick Match/Ranked.
-- Auto-unlocks Awakening for every owned eligible fighter (gem reserve defaults to 0).
-- This uses the game's networked input path, never edits simulated HP/cooldowns.

local env = getgenv and getgenv() or _G
local previousBot = env.QuickMatchAuto
local previousAutoJoin = previousBot and previousBot.AutoJoin
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
assert(player, "Run this in the game client")
local scripts = player:WaitForChild("PlayerScripts", 20)
assert(scripts, "PlayerScripts unavailable; wait for the lobby")
-- Prefer already-running module tables; requiring in an executor environment
-- alone does not establish that the game's own module cache is being edited.
local liveModules = {}
local profileCandidateScore, profileCandidateFreshness = -1, -1
local function profileScore(value)
    local score, freshness = 0, 0
    if type(rawget(value, "view")) == "function" then
        local ok, view = pcall(value.view)
        if ok and type(view) == "table" then
            score = 100
            if type(view.owned) == "table" then score = score + math.min(100, #view.owned) end
            if type(view.rewards) == "table" then freshness = tonumber(view.rewards.at) or 0 end
        end
    end
    for _, name in ipairs({"owns", "unlockMove", "onUnlocked"}) do if type(rawget(value, name)) == "function" then score = score + 1 end end
    return score, freshness
end
if type(getgc) == "function" then
    local ok, values = pcall(getgc, true)
    if ok then
        for _, v in pairs(values) do
            if type(v) == "table" then
                if type(rawget(v, "sample")) == "function" and type(rawget(v, "sampler")) == "function"
                    and type(rawget(v, "PRESS")) == "table" and type(rawget(v, "hold")) == "function" then liveModules.PlayerInput = v end
                if type(rawget(v, "bind")) == "function" and type(rawget(v, "queue")) == "function"
                    and type(rawget(v, "lobby")) == "function" and type(rawget(v, "hover")) == "function" then liveModules.OnlineClient = v end
                if type(rawget(v, "arrivedForMatch")) == "function" and type(rawget(v, "queue")) == "function"
                    and type(rawget(v, "connected")) == "function" and type(rawget(v, "back")) == "function" then liveModules.RankedClient = v end
                if type(rawget(v, "card")) == "function" and type(rawget(v, "keyUnlocked")) == "function"
                    and type(rawget(v, "gems")) == "function" then
                    local score, freshness = profileScore(v)
                    if score > profileCandidateScore or (score == profileCandidateScore and freshness > profileCandidateFreshness) then
                        liveModules.ProfileClient = v; profileCandidateScore, profileCandidateFreshness = score, freshness
                    end
                end
                if type(rawget(v, "list")) == "table" and type(rawget(v, "isPlayable")) == "function"
                    and type(rawget(v, "main")) == "table" then
                    local old = liveModules.Fighters
                    if not old or #v.main > #old.main then liveModules.Fighters = v end
                end
                if type(rawget(v, "canUnlock")) == "function" and type(rawget(v, "hasSlot")) == "function"
                    and type(rawget(v, "slotOf")) == "function" and type(rawget(v, "isUnlocked")) == "function"
                    and type(rawget(v, "AWAKEN_PRICE")) == "table" then liveModules.Gems = v end
                if type(rawget(v, "onPauseLeave")) == "function" and type(rawget(v, "ownsRenderer")) == "function"
                    and type(rawget(v, "isPvp")) == "function" and type(rawget(v, "resume")) == "function"
                    and type(rawget(v, "active")) == "boolean" then
                    if not liveModules.MatchController or v.active then liveModules.MatchController = v end
                end
            end
        end
    end
end
local function load(root, name, required)
    if liveModules[name] then return liveModules[name] end
    local obj = root:FindFirstChild(name, true)
    if obj and obj:IsA("ModuleScript") then
        local ok, result = pcall(require, obj)
        if ok then return result end
        if required then error(name .. ": " .. tostring(result)) end
    end
    if required then error("Missing module: " .. name) end
end
local Shared = RS:WaitForChild("Shared", 20)
assert(Shared, "Shared modules unavailable")
local Input = load(scripts, "PlayerInput", true)
local Online = load(scripts, "OnlineClient", true)
local Ranked = load(scripts, "RankedClient", false)
local RankConfig = load(Shared, "RankConfig", false)
local Flags = load(Shared, "Flags", false)
local Rarity = load(Shared, "Rarity", true)
local Kind = load(Shared, "MoveKind", true)
local Profile = load(scripts, "ProfileClient", false)
local Rewards = load(Shared, "Rewards", false)
local Gems = load(Shared, "Gems", false)
local Fighters = load(Shared, "Fighters", false)
local Combat = load(Shared, "Combat", false)
local CombatRules = load(Shared, "CombatRules", false)
local GroundRules = CombatRules and CombatRules.C or {}
local Http = game:GetService("HttpService")
local Bot = {
    Enabled = true,
    AutoJoin = previousAutoJoin ~= false, -- default on; retain F7 choice across re-execution
    MatchMode = "quick",
    Movement = "custom", -- "manual" lets you steer; both use full CONTROL mode
    HealBelow = 0.78,
    SkillGap = 0.22,
    ManualGrace = 1.5,
    RangedFallback = 12, -- heuristic only when projectile data has no usable reach
    ReserveDashCharges = 1,
    ReserveDashFraction = 0.5, -- round up: keep two when the fighter has three
    OffensiveDashGap = 1.3, -- actual recharge duration can increase this gap
    MaxApproachDashDistance = 12,
    ReserveBreaker = true,
    AvoidLostOpponents = false,
    AcceptRematches = true,
    SkipPopups = true,
    MaxBasicRange = 2.6, -- conservative entry distance; skills retain their own reach
    AutoLogs = true,
    ClearOldVersionLogs = true,
    AutoClaimPlaytime = true,
    AutoAwakenAll = true,
    PrioritizeUltimate = true,
    AwakenGemReserve = 0,
    AwakenStatus = "initializing",
    PredictBlock = true,
    CloseDashOpener = true,
    RecoveryGuard = true,
    ProtectedSpacing = 3.4,
    -- Internal fighter IDs; priorities apply only among offered cards of a tier.
    DraftPriorities = {[12] = {Hakari = 100}, [10] = {Nanami = 100}},
    MinGuardToBlock = 30,
    LogSlots = 200,
    LogMaxBytes = 8 * 1024 * 1024, -- longer PvP sets previously lost their last rounds at 4 MiB
    LogInterval = 0.1,
    LogStatus = "initializing",
    RewardStatus = "idle",
    Status = "Starting",
    LastError = nil,
    Version = "4.28-ranked-update",
    AwakenDiagnostics = {},
    RecoveryStatus = "watching",
    RecoveryCount = 0,
    LobbyRecoveryDelay = 15,
    AwayWarnings = 0,
    AwayLimit = 3,
    InputCalls = 0,
    LiveInputFound = liveModules.PlayerInput ~= nil,
    LiveOnlineFound = liveModules.OnlineClient ~= nil,
    ControlState = "unknown",
}
-- Keep script configuration/macros across replacement; runtime sessions and
-- pending input are rebuilt. The old awakening option is an alias for the new
-- all-owned scope, so existing enable/disable macros continue to work.
do
    local keys = {"Enabled", "AutoJoin", "MatchMode", "AutoAwakenAll", "Movement", "HealBelow", "SkillGap",
        "ManualGrace", "RangedFallback", "ReserveDashCharges",
        "ReserveDashFraction", "OffensiveDashGap", "MaxApproachDashDistance", "ReserveBreaker", "AvoidLostOpponents",
        "AcceptRematches", "SkipPopups", "MaxBasicRange", "AutoLogs", "ClearOldVersionLogs", "AutoClaimPlaytime",
        "AwakenGemReserve", "PredictBlock", "CloseDashOpener", "RecoveryGuard", "ProtectedSpacing", "DraftPriorities",
        "MinGuardToBlock", "LogSlots", "LogMaxBytes", "LogInterval", "LobbyRecoveryDelay", "PrioritizeUltimate"}
    local path = "QuickMatchAutoSettings_" .. tostring(player.UserId) .. ".json"
    local saved
    local function restore(source)
        if type(source) ~= "table" then return end
        for _, key in ipairs(keys) do
            local value = source[key]
            if key == "DraftPriorities" and type(value) == "table" then
                local tiers = {}
                for tier, priorities in pairs(value) do
                    local index = tonumber(tier)
                    if index and type(priorities) == "table" then tiers[index] = priorities end
                end
                Bot[key] = tiers
            elseif key == "MatchMode" then
                if value == "quick" or value == "ranked" then Bot[key] = value end
            elseif key == "Movement" then
                if value == "manual" or value == "custom" then Bot[key] = value end
            elseif type(value) == type(Bot[key]) and key ~= "DraftPriorities"
                and not (key == "Enabled" and source.Status == "Unloaded") then Bot[key] = value end
        end
    end
    if type(readfile) == "function" and type(Http.JSONDecode) == "function" then
        local ok, value = pcall(function() return Http:JSONDecode(readfile(path)) end)
        if ok then restore(value) end
    end
    restore(previousBot)
    if type(previousBot) == "table" and previousBot.AutoAwakenAll == nil
        and type(previousBot.AutoAwakenMythicPlus) == "boolean" then Bot.AutoAwakenAll = previousBot.AutoAwakenMythicPlus end
    function Bot.SaveSettings()
        if type(writefile) ~= "function" or type(readfile) ~= "function"
            or type(Http.JSONEncode) ~= "function" or type(Http.JSONDecode) ~= "function" then return false end
        local ok, err = pcall(function()
            local data, tiers = {}, {}
            for _, key in ipairs(keys) do data[key] = Bot[key] end
            for tier, priorities in pairs(Bot.DraftPriorities) do tiers[tostring(tier)] = priorities end
            data.DraftPriorities = tiers
            local encoded = Http:JSONEncode(data)
            if encoded ~= saved then writefile(path, encoded); saved = encoded end
        end)
        Bot.SettingsError = not ok and tostring(err) or nil
        return ok
    end
end
setmetatable(Bot, {__index = function(self, key)
    if key == "AutoAwakenMythicPlus" then return rawget(self, "AutoAwakenAll") end
end, __newindex = function(self, key, value)
    if key == "AutoAwakenMythicPlus" then rawset(self, "AutoAwakenAll", value)
    else rawset(self, key, value) end
end})
-- Required modules are available before replacing the working instance.
if previousBot and type(previousBot.Stop) == "function" then
    local ok, err = pcall(previousBot.Stop)
    if not ok then Bot.PreviousStopError = tostring(err); warn("[QuickMatchAuto] Previous cleanup: " .. tostring(err)) end
end
-- Survives script re-execution in this executor, not reconnects or teleports.
if type(env.QuickMatchMemory) ~= "table" then env.QuickMatchMemory = {} end
local memoryKey = tostring(game.PlaceId or "unknown")
if type(env.QuickMatchMemory[memoryKey]) ~= "table" then
    env.QuickMatchMemory[memoryKey] = {lost = {}, wins = 0, losses = 0, defenseMargin = 0}
end
local memory = env.QuickMatchMemory[memoryKey]
Bot.Memory = memory
env.QuickMatchAuto = Bot
local alive, connections, session = true, {}, nil
local ranked = {state = "off", retryAt = 0, returnAt = 0}
if Ranked and type(Ranked.arrivedForMatch) == "function" then
    local ok, value = pcall(Ranked.arrivedForMatch)
    ranked.arena = ok and value == true
end
local originalSample, originalBind = Input.sample, Online.bind
local sampleWrapper, bindWrapper
local lastManual, lastScan, lastQueue = -100, -100, -100
local nextSkill, nextDodge, nextJump, nextSwitch, nextLight = 0, 0, 0, 0, 0
local nextUltimate = 0
local pendingJump, busy, queued, dealGeneration = nil, false, false, 0
local queueRequested = false
local lastDeal, drafting, ending, matchId = nil, false, false, nil
local matchNumber = nil
local lastGoodSample = os.clock()
local previousHp, previousSelf, nextEscape, lastLightSeq = nil, nil, 0, nil
local opponentId, blockedMatch, outcomeRecorded, mySide = nil, false, false, nil
local rematchAnswered, rematchWaitUntil = false, 0
local rematchAutoAccepted = false
local defenseUntil = 0
local dashOpener, nextCloseDash = nil, 0
local recoveryGuardUntil = 0
local pendingDash, nextOffensiveDash = nil, 0
local pendingAttack, defenseKind = nil, nil
local opponentCPU = nil
local matchController = liveModules.MatchController
local skipState, lastControllerScan = nil, -100
if type(memory.ignoredSessions) ~= "table" then memory.ignoredSessions = setmetatable({}, {__mode = "k"}) end
if type(memory.sessionMatches) ~= "table" then memory.sessionMatches = setmetatable({}, {__mode = "k"}) end
local ignoredSessions, sessionMatches = memory.ignoredSessions, memory.sessionMatches
memory.retiredMatches, memory.retiredOrder = memory.retiredMatches or {}, memory.retiredOrder or {}
local retiredMatches, retiredOrder = memory.retiredMatches, memory.retiredOrder
local lobbyUpdatedAt = -100
local matchEventAt = os.clock()
local function status(s) Bot.Status = s end
local function resetCombat()
    nextSkill, nextDodge, nextJump, nextSwitch, nextLight = 0, 0, 0, 0, 0
    nextUltimate = 0
    pendingJump = nil
    previousHp, previousSelf, nextEscape, lastLightSeq = nil, nil, 0, nil
    defenseUntil = 0
    dashOpener, nextCloseDash = nil, 0
    recoveryGuardUntil = 0
    pendingDash, nextOffensiveDash = nil, 0
    pendingAttack, defenseKind = nil, nil
    Bot.Snapshot = nil
end
local function validSession(v)
    return type(v) == "table" and not ignoredSessions[v] and rawget(v, "dead") == false
        and not retiredMatches[sessionMatches[v]]
        and type(rawget(v, "r")) == "table" and type(rawget(v, "side")) == "number"
        and type(rawget(v, "nc")) == "table" and type(v.r.sim) == "table"
end
local function retireMatch(id, current, sweepUnknown)
    if id and not retiredMatches[id] then
        retiredMatches[id] = true; retiredOrder[#retiredOrder + 1] = id
        if #retiredOrder > 400 then retiredMatches[table.remove(retiredOrder, 1)] = nil end
    end
    if current and (not sessionMatches[current] or sessionMatches[current] == id) then ignoredSessions[current] = true end
    for value, owner in pairs(sessionMatches) do if owner == id then ignoredSessions[value] = true end end
    if sweepUnknown and type(getgc) == "function" then
        local ok, values = pcall(getgc, true)
        if ok then
            for _, value in pairs(values) do
                if validSession(value) and (not sessionMatches[value] or sessionMatches[value] == id) then ignoredSessions[value] = true end
            end
        end
    end
end
local function discover()
    if session and validSession(session) then return session end
    session = nil
    if os.clock() - lastScan < 5 then return end
    lastScan = os.clock()
    -- Existing matches can be attached without changing any simulation state.
    if type(getgc) == "function" then
        local ok, values = pcall(getgc, true)
        if ok then
            local bestScore = -math.huge
            for _, value in pairs(values) do
                if validSession(value) and (not matchId or not sessionMatches[value] or sessionMatches[value] == matchId) then
                    local score = tonumber(value.lastStepT) or 0
                    if matchController and type(matchController.ownsRenderer) == "function" then
                        local owned, result = pcall(matchController.ownsRenderer, matchController, value.r)
                        if owned and result then score = score + 1e9 end
                    end
                    if score > bestScore then session, bestScore = value, score end
                end
            end
            if session then resetCombat() end
        end
    end
    return session
end
bindWrapper = function(...)
    local result = originalBind(...)
    local info = select(2, ...)
    local id = type(info) == "table" and (info.matchId or (type(info.match) == "table" and info.match.matchId)) or matchId
    if alive and type(result) == "table" then
        sessionMatches[result] = id
        if retiredMatches[id] then ignoredSessions[result] = true
        elseif validSession(result) then session = result; resetCombat() end
    end
    return result
end
Online.bind = bindWrapper

-- Per-match rolling logs. File IO is flushed outside the input callback.
local logger = {folder = "QuickMatchAutoLogs", buffer = {}, bytes = 0, active = false,
    lastSample = -100, lastFlush = -100, serial = 0}
logger.available = type(writefile) == "function" and type(appendfile) == "function"
    and type(Http.JSONEncode) == "function"
Bot.LogStatus = logger.available and "ready" or "unavailable (file/JSON APIs)"
function logger:cleanupVersions()
    if not Bot.ClearOldVersionLogs then Bot.LogCleanupStatus = "off"; return end
    if type(listfiles) ~= "function" or type(readfile) ~= "function" or type(delfile) ~= "function"
        or type(Http.JSONDecode) ~= "function" then
        Bot.LogCleanupStatus = "unavailable (file/JSON APIs)"; return
    end
    if type(isfolder) == "function" and not isfolder(self.folder) then
        Bot.LogCleanupStatus = "no old logs"; return
    end
    local ok, paths = pcall(listfiles, self.folder)
    if not ok or type(paths) ~= "table" then
        Bot.LogCleanupStatus = "error"; Bot.LogCleanupError = tostring(paths); return
    end
    local files, versions, readable = {}, {}, {}
    -- Never delete a returned absolute path. Only recognized direct children are
    -- mapped to canonical paths inside this script's own log directory.
    for _, listed in pairs(paths) do
        if type(listed) == "string" then
            local normalized = listed:gsub("\\", "/"):gsub("^%./", "")
            local leaf = normalized:match("^QuickMatchAutoLogs/([^/]+)$")
                or normalized:match("/QuickMatchAutoLogs/([^/]+)$")
            if leaf and not normalized:find("..", 1, true) and (leaf == "latest.json"
                or leaf:match("^match_%d+%.jsonl$") or leaf:match("^match_%d+%.summary%.json$")) then
                files[leaf] = self.folder .. "/" .. leaf
            end
        end
    end
    local errors, removed = 0, 0
    for leaf, path in pairs(files) do
        local read, data = pcall(readfile, path)
        if read and type(data) == "string" then
            readable[leaf] = true
            if leaf:match("%.jsonl$") then data = data:match("([^\r\n]+)") or "" end
            local decoded, row = pcall(Http.JSONDecode, Http, data)
            if decoded and type(row) == "table" and type(row.version) == "string" then versions[leaf] = row.version end
        else errors = errors + 1 end
    end
    for leaf, path in pairs(files) do
        if readable[leaf] then
            local version = versions[leaf]
            -- A current companion identifies a crash-truncated file that has no
            -- readable version of its own. Explicitly old versions still go.
            if not version then
                local companion = leaf:match("%.jsonl$") and leaf:gsub("%.jsonl$", ".summary.json")
                    or (leaf:match("%.summary%.json$") and leaf:gsub("%.summary%.json$", ".jsonl"))
                version = companion and versions[companion] or nil
            end
            if version ~= Bot.Version then
                local deleted, err = pcall(delfile, path)
                if deleted then removed = removed + 1 else errors = errors + 1; Bot.LogCleanupError = tostring(err) end
            end
        end
    end
    Bot.LogCleanupRemoved = removed
    Bot.LogCleanupStatus = errors > 0 and ("partial (" .. errors .. " errors)") or ("cleared " .. removed .. " old files")
end
local cleanupOk, cleanupError = pcall(logger.cleanupVersions, logger)
if not cleanupOk then Bot.LogCleanupStatus = "error"; Bot.LogCleanupError = tostring(cleanupError) end
if memory.logVersion ~= Bot.Version then
    memory.logCursor, memory.logSequence, memory.logSlots = 0, 0, Bot.LogSlots
    memory.logVersion = Bot.Version
end
function logger:restoreCursor()
    if self.restored then return end
    self.restored = true
    if type(readfile) ~= "function" or type(Http.JSONDecode) ~= "function" then return end
    local ok, data = pcall(function() return Http:JSONDecode(readfile(self.folder .. "/latest.json")) end)
    if not ok or type(data) ~= "table" or data.version ~= Bot.Version then return end
    local slot = tonumber(data.slot) or (type(data.file) == "string" and tonumber(data.file:match("match_(%d+)%.jsonl$")))
    local sequence = tonumber(data.sequence) or slot
    local slots = tonumber(data.slots)
    if slot and slot >= 1 and slot < 1e6 and slot % 1 == 0 and sequence and sequence >= slot and sequence < 1e12
        and sequence % 1 == 0 and sequence >= (tonumber(memory.logSequence) or 0) then
        memory.logCursor, memory.logSequence = slot, sequence
        if slots and slots >= 1 and slots < 1e6 and slots % 1 == 0 then memory.logSlots = slots end
    end
end
local function flat(source, keys)
    local result = {}
    if type(source) ~= "table" then return result end
    for _, key in ipairs(keys) do
        local value = source[key]
        if type(value) == "string" or type(value) == "boolean"
            or (type(value) == "number" and value == value and math.abs(value) < 1e9) then result[key] = value end
    end
    return result
end
local actorKeys = {"name", "idx", "state", "moveBase", "moveSeq", "key", "kt", "keyDur", "hp", "maxHp",
    "x", "y", "vx", "vy", "grounded", "facing", "human", "cmdMine", "chainN", "chainCanT", "chainCanSeq",
    "chainEnd", "moveHit", "moveBlocked", "hbuf", "hbufT", "invuln", "invis", "kdT", "cbInvT",
    "evInvT", "dashT", "dashN", "dashMax", "dashCd", "dashCdLen", "dashAt", "dashFwd", "dashHit", "stunT",
    "airJumps", "airDashes", "guard", "guardMax", "guardLockT", "blockStunT",
    "dashInvT", "keyHold", "botSeat", "dummy", "tutorBot", "switchable", "form", "lifeLost",
    "downT", "kdGetup", "otgT0", "otgWin", "otgN", "otgOff", "otgFlBy", "otgFlCls",
    "dcStr", "dcLoop", "dcCap", "dcBy", "dcHoldTo", "reviveInvT", "cl", "clHitSeq", "clHitT",
    "clSkSeq", "clSkT", "clKdLockT", "clNoStunT", "clRag", "clTechT", "clEscCd",
    "cdN", "cdP", "cdT", "cdKey", "combo", "l3Vic", "l3Seq", "hitCls", "ult"}
local function controlMode(actor)
    if actor.botSeat or actor.dummy or actor.tutorBot then return "bot" end
    if actor.human then return "full" end
    if actor.cmdMine then return "command" end
    return "ai"
end
local function attackMove(sim, me)
    -- DashPunch plays a hitless recovery animation after its separately resolved
    -- contact. Get-up, buff and counter stance animations need not deal damage.
    if me.moveBase == "DashPunch" or me.moveBase == "GetUp" or me.moveBase == "GetUpKD" then return false end
    local move = me.move
    if not move and type(sim._moveDef) == "function" then move = sim:_moveDef(me, me.moveBase) end
    if type(move) == "table" then
        for _, key in ipairs(move.keys or {}) do
            if key.hit or key.grab then return true end
            for _, fx in ipairs(key.fx or {}) do
                if fx[1] == "proj" or fx[1] == "strike" or fx[1] == "whip" or fx[1] == "release" then return true end
            end
        end
        return false
    end
    return type(me.moveBase) == "string" and me.moveBase:match("^L[1-4]$") ~= nil
end
local function actorLog(actor)
    local row = flat(actor, actorKeys)
    row.fighterId = actor.def and actor.def.name or nil
    row.movement = actor.mvt
    row.controlMode = controlMode(actor)
    if type(actor.clC) == "table" then row.comboState = flat(actor.clC, {"by", "t0", "f0", "dmg", "hits", "hold", "sks", "chase", "vanish"}) end
    return row
end
function logger:fail(err)
    self.available = false
    Bot.LogStatus = "error"
    Bot.LogError = tostring(err)
end
function logger:line(kind, data)
    if not self.available or not Bot.AutoLogs or not self.path or self.full then return end
    local row = data or {}
    row.type = kind; row.clock = os.clock()
    local ok, encoded = pcall(Http.JSONEncode, Http, row)
    if not ok then self:fail(encoded); return end
    encoded = encoded .. "\n"
    if self.bytes + #encoded > Bot.LogMaxBytes then
        self.full = true; Bot.LogStatus = "match log capped"
        return
    end
    self.bytes = self.bytes + #encoded
    self.buffer[#self.buffer + 1] = encoded
end
function logger:index()
    if not self.available or not self.path then return end
    local ok, err = pcall(function()
        local encoded = Http:JSONEncode({version = Bot.Version,
            file = self.path, active = self.active, matchId = self.id, summary = self.stats,
            capped = self.full == true, bytes = self.bytes, slots = Bot.LogSlots,
            awakening = {status = Bot.AwakenStatus, diagnostics = Bot.AwakenDiagnostics, error = Bot.AwakenError},
            popup = Bot.LastPopup,
            recovery = {status = Bot.RecoveryStatus, count = Bot.RecoveryCount, state = Bot.SessionState},
            slot = self.slot, sequence = self.sequence})
        writefile(self.folder .. "/latest.json", encoded)
        writefile(self.path:gsub("%.jsonl$", ".summary.json"), encoded)
    end)
    if not ok then self:fail(err) end
end
function logger:flush(force)
    if not self.available or not self.path then return end
    if not force and os.clock() - self.lastFlush < 1 then return end
    self.lastFlush = os.clock()
    if #self.buffer > 0 then
        local ok, err = pcall(appendfile, self.path, table.concat(self.buffer))
        if not ok then self:fail(err); return end
        table.clear(self.buffer)
    end
    self:index()
end
function logger:endMove(reason)
    local m = self.move
    if not m then return end
    self:line("move_end", {move = m.name, seq = m.seq, hit = m.hit, blocked = m.blocked,
        attack = m.attack, sawStart = m.sawStart, reason = reason})
    if m.hit then self.stats.movesWithHit = self.stats.movesWithHit + 1
    elseif m.blocked then self.stats.movesBlocked = self.stats.movesBlocked + 1
    elseif m.attack and m.sawStart and reason == "neutral" then self.stats.observedNoHit = self.stats.observedNoHit + 1 end
    self.move = nil
end
function logger:finish(reason)
    if not self.active then return end
    self:endMove(reason)
    self.active = false
    self.finishedSession = session
    self:line("match_end", {reason = reason, summary = self.stats})
    self:flush(true)
    if self.available then Bot.LogStatus = self.full and "saved (capped)" or "saved" end
end
function logger:start(id)
    if not Bot.AutoLogs or not self.available then return end
    if self.active then self:finish("next match") end
    local ok, err = pcall(function()
        if type(isfolder) ~= "function" or not isfolder(self.folder) then
            if type(makefolder) == "function" then makefolder(self.folder) end
        end
    end)
    -- Some executors report an error for an existing directory; writefile below
    -- is the final capability check, without deleting any existing log files.
    self:restoreCursor()
    local slots = math.max(1, math.floor(Bot.LogSlots))
    local cursor = tonumber(memory.logCursor) or 0
    if memory.logSlots and memory.logSlots < slots then cursor = math.max(cursor, memory.logSlots) end
    memory.logCursor = (cursor % slots) + 1
    memory.logSequence = math.max(tonumber(memory.logSequence) or 0, cursor) + 1
    memory.logSlots = slots
    self.slot, self.sequence = memory.logCursor, memory.logSequence
    self.path = self.folder .. string.format("/match_%02d.jsonl", memory.logCursor)
    ok, err = pcall(writefile, self.path, "")
    if not ok then self:fail(err); return end
    self.id = id or "attached"
    self.buffer = {}; self.bytes = 0; self.full = false; self.active = true
    self.move = nil; self.lastMe = nil; self.lastFoe = nil; self.lastSim = nil; self.lastSample = -100
    self.lastUltimateCast = 0
    self.stats = {samples = 0, inputs = {}, damageTaken = 0, damageDealt = 0,
        selfHpCost = 0, opponentSelfHpCost = 0, combatDamageTaken = 0, combatDamageDealt = 0,
        movesWithHit = 0, movesBlocked = 0, observedNoHit = 0, ultimateStarts = 0, outcome = "unknown", rounds = {},
        opponentCPU = opponentCPU, opponentControlSamples = {}, matchMode = ranked.arena and "ranked" or "quick"}
    self.roundSeen = {}; self.roundNumber = nil
    self.roundBaseTaken, self.roundBaseDealt = 0, 0
    self.roundBaseSelfCost, self.roundBaseOpponentCost = 0, 0
    Bot.LogFile = self.path; Bot.LogStatus = "recording"
    self:line("match_start", {version = Bot.Version, matchId = self.id, opponentId = opponentId, opponentCPU = opponentCPU,
        slot = self.slot, sequence = self.sequence, matchMode = self.stats.matchMode})
    self:flush(true)
end
local function estimatedHpCost(actor, beforeHp, beforeLifeLost, beforeSeq, beforeKey, drop)
    local cost = 0
    if (actor.lifeLost or 0) > (beforeLifeLost or 0) then
        cost = math.max(0, beforeHp - math.max(1, (actor.maxHp or beforeHp) - actor.lifeLost))
    end
    if actor.moveSeq ~= beforeSeq or actor.key ~= beforeKey then
        local key = actor.move and actor.move.keys and actor.move.keys[actor.key or 1]
        if key then cost = cost + math.max(0, tonumber(key.selfDmg) or 0) end
    end
    return math.min(drop, cost)
end
function logger:sample(out)
    if not Bot.AutoLogs or not self.available or blockedMatch then return end
    local current = session
    local sim = current and not current.dead and current.r.sim
    local me = sim and sim.fighters[current.side]
    local foe = me and sim:other(me)
    if not me or not foe then return end
    if not self.active then
        if sim.phase == "fight" and self.finishedSession ~= current then self:start(matchId) else return end
    end
    if not self.active then return end
    local pressed = false
    for key, value in pairs(out or {}) do
        if value == true and key ~= "block" and key ~= "down" then
            pressed = true; self.stats.inputs[key] = (self.stats.inputs[key] or 0) + 1
        end
    end
    local sameRound = self.lastSim == sim and self.lastMe == me and self.lastFoe == foe
        and (sim.t or 0) >= (self.lastTime or 0)
    local changed = not sameRound or (me.moveSeq ~= self.lastSeq) or me.state ~= self.lastState or sim.phase ~= self.lastPhase
        or Bot.InputMode ~= self.lastInputMode
    if sameRound then
        local taken = math.max(0, (self.lastHp or me.hp) - me.hp)
        local dealt = math.max(0, (self.lastFoeHp or foe.hp) - foe.hp)
        self.stats.damageTaken = self.stats.damageTaken + taken
        self.stats.damageDealt = self.stats.damageDealt + dealt
        local selfCost = estimatedHpCost(me, self.lastHp or me.hp, self.lastLifeLost, self.lastSeq, self.lastKey, taken)
        local opponentCost = estimatedHpCost(foe, self.lastFoeHp or foe.hp, self.lastFoeLifeLost, self.lastFoeSeq, self.lastFoeKey, dealt)
        self.stats.selfHpCost = self.stats.selfHpCost + selfCost
        self.stats.opponentSelfHpCost = self.stats.opponentSelfHpCost + opponentCost
        self.stats.combatDamageTaken = self.stats.damageTaken - self.stats.selfHpCost
        self.stats.combatDamageDealt = self.stats.damageDealt - self.stats.opponentSelfHpCost
        if selfCost > 0 or opponentCost > 0 then self:line("hp_cost", {simTime = sim.t, selfCost = selfCost,
            opponentCost = opponentCost, attribution = "lifeLost/key selfDmg estimate"}) end
        if taken > 0 or dealt > 0 then changed = true end
    elseif self.move then self:endMove("round changed") end
    if self.move and (me.state ~= "move" or me.moveSeq ~= self.move.seq) then self:endMove(me.state) end
    if me.state == "move" then
        if not self.move then self.move = {name = me.moveBase, seq = me.moveSeq, hit = false, blocked = false,
            attack = attackMove(sim, me),
            sawStart = sameRound and me.moveSeq ~= self.lastSeq and me.key == 1} end
        self.move.hit = self.move.hit or me.moveHit == true
        self.move.blocked = self.move.blocked or me.moveBlocked == true
    end
    if self.lastSim ~= sim or self.lastMe ~= me then self.lastUltimateCast = 0 end
    local cast = me.ultCast
    if me.state == "move" and me.move and me.move.ultimate and cast
        and type(cast.id) == "number" and cast.id > self.lastUltimateCast then
        self.lastUltimateCast = cast.id
        self.stats.ultimateStarts = self.stats.ultimateStarts + 1
        self:line("ultimate_start", {move = cast.move or me.moveBase, castId = cast.id, simTime = sim.t})
    end
    self.lastSim, self.lastMe, self.lastFoe = sim, me, foe
    self.lastTime, self.lastHp, self.lastFoeHp = sim.t, me.hp, foe.hp
    self.lastSeq, self.lastState = me.moveSeq, me.state
    self.lastKey, self.lastLifeLost = me.key, me.lifeLost
    self.lastFoeKey, self.lastFoeSeq, self.lastFoeLifeLost = foe.key, foe.moveSeq, foe.lifeLost
    self.lastPhase = sim.phase
    self.lastInputMode = Bot.InputMode
    if not pressed and not changed and os.clock() - self.lastSample < Bot.LogInterval then return end
    self.lastSample = os.clock(); self.stats.samples = self.stats.samples + 1
    local mode = controlMode(foe)
    local modes = self.stats.opponentControlSamples
    if sim.phase == "fight" then modes[mode] = (modes[mode] or 0) + 1 end
    local queries = {}
    for _, key in ipairs({"x1", "x2", "x3", "ult", "form"}) do
        local success, ready, reason = pcall(sim.canUseMove, sim, me, key)
        if success then queries[key] = {ready = ready == true, reason = type(reason) == "string" and reason or nil} end
    end
    self:line("sample", {phase = sim.phase, frame = sim.frame, simTime = sim.t, delay = current.nc.delay, halfW = sim.halfW,
        me = actorLog(me), foe = actorLog(foe), input = out, queries = queries,
        decision = Bot.Snapshot, status = Bot.Status, enabled = Bot.Enabled, inputMode = Bot.InputMode,
        network = {lp = current.nc.lp == true, acked = current.nc.acked, fillTo = current.nc.fillTo,
            ownKnown = current.nc.known and current.nc.known[current.side], stalls = current.stalls, desync = current.desync},
        manualGraceRemaining = math.max(0, Bot.ManualGrace - (os.clock() - lastManual))})
end

local function copyFields(value)
    local result = {}; for k, v in pairs(value or {}) do result[k] = v end; return result
end
local function comboCutQuery(sim, me, key)
    if type(sim._clSkillCut) ~= "function" then return false end
    local foe = sim:other(me)
    if not foe then return false end
    local own, target = copyFields(me), copyFields(foe)
    own.clC, target.clC = me.clC and copyFields(me.clC), foe.clC and copyFields(foe.clC)
    local fighters = copyFields(sim.fighters); fighters[me.idx], fighters[foe.idx] = own, target
    local query = setmetatable({fighters = fighters, other = function(_, actor)
        return actor.idx == own.idx and target or own
    end}, {__index = sim})
    -- _clSkillCut consumes combo flags and can extend stun. Only run it on
    -- isolated fighter/combo copies; native input performs any real cancel.
    local ok, ready = pcall(sim._clSkillCut, query, own, key)
    return ok and ready == true, target.stunT
end
local function canUse(sim, me, key)
    if me.locks and me.locks[key] then return false end
    local ok, result, reason = pcall(sim.canUseMove, sim, me, key)
    if ok and not result and me.state == "move" and me.cl ~= nil then
        local ready, hold = comboCutQuery(sim, me, key)
        if ready then return true, "combo-chain", hold end
    elseif ok and not result and me.state == "move" and type(sim._skillCutOk) == "function" then
        local chainOk, chain = pcall(sim._skillCutOk, sim, me, key)
        if chainOk and chain == true then return true, "chain" end
    end
    return ok and result == true, reason
end
local function checkMethod(sim, name, ...)
    if type(sim[name]) ~= "function" then return false end
    local ok, value = pcall(sim[name], sim, ...)
    return ok and value == true
end
local function escapeKind(sim, me, key)
    local ready, reason = canUse(sim, me, key)
    if not ready then return end
    local checked = false
    for _, entry in ipairs({{"_tfReady", "transform"}, {"_evReady", "evade"}}) do
        if type(sim[entry[1]]) == "function" then
            checked = true
            local ok, id = pcall(sim[entry[1]], sim, me, key)
            if ok and type(id) == "string" then return entry[2] end
        end
    end
    local id = sim:_pressMove(me, key)
    if type(sim._breakerMove) == "function" then id = sim:_breakerMove(me, key) or id end
    if type(sim._breakerOk) == "function" then
        checked = true
        if id and checkMethod(sim, "_breakerOk", me, id, sim:other(me)) then return "breaker" end
    end
    if checked then return end
    -- Older environments may lack the specific queries. A generic "breaker"
    -- reason is insufficient during GetUp: moveBlackout opens every input then.
    local def = id and sim:_moveDef(me, id)
    local rising = me.state == "move" and (me.moveBase == "GetUp" or me.moveBase == "GetUpKD")
    if def and def.comboBreaker then return "breaker" end
    if not rising and (reason == "breaker" or reason == "transform") then return reason end
end
local function protectedTarget(sim, foe, floorMelee)
    local gettingUp = foe.state == "move" and (foe.moveBase == "GetUpKD" or foe.moveBase == "GetUp")
    return foe.ko or (foe.hp and foe.hp <= 0) or (foe.invuln and not (floorMelee and gettingUp))
        or foe.invis or foe.clash or foe.state == "ko"
        or (tonumber(foe.cbInvT) or 0) > (sim.t or 0)
        or (tonumber(foe.evInvT) or 0) > (sim.t or 0)
        or (tonumber(foe.reviveInvT) or 0) > (sim.t or 0)
        or ((foe.dashT or 0) > 0 and (foe.dashInvT or 0) > (sim.t or 0))
        or (gettingUp and not floorMelee)
end
local function hittable(sim, foe)
    return not (protectedTarget(sim, foe) or foe.state == "down"
        or (tonumber(foe.kdT) or 0) > (sim.t or 0)
        or (foe.grounded and foe.state == "tumble")
        )
end
local function lockedState(me)
    return me.state == "stun" or me.state == "tumble" or me.state == "down"
        or me.state == "held" or me.state == "splat" or me.clash or me.state == "clash" or (me.state == "move"
            and (me.moveBase == "GetUp" or me.moveBase == "GetUpKD"))
end
local function guardReady(sim, me, foe, kind, horizon)
    if type(sim.comboGuardWait) ~= "function" then return true end
    local ok, waitTime = pcall(sim.comboGuardWait, sim, me, foe, kind)
    return ok and type(waitTime) == "number" and waitTime <= horizon
end
local infoCache = setmetatable({}, {__mode = "k"})
local function moveRemaining(me)
    if me.state ~= "move" or not me.move then return 0 end
    local tempo = me.move.fixedTime and 1 or tonumber(me.def and me.def.tempo) or 1
    local left = math.max(0, (me.keyDur or 0) + (me.keyHold or 0) - (me.kt or 0))
    for i = (me.key or 1) + 1, #(me.move.keys or {}) do
        local k = me.move.keys[i]
        left = left + ((tonumber(k.dur) or 0) + (tonumber(k.hold) or 0)) * tempo
    end
    return left
end
local function moveInfo(sim, me, id, key)
    if not id then return end
    local def = sim:_moveDef(me, id)
    if not def then return end
    -- _airKit can return the base ID; startMove resolves its optional ifAir branch.
    if not me.grounded and key ~= "form" and key ~= "ult" and type(def.ifAir) == "string" then
        id = def.ifAir
        def = sim:_moveDef(me, id)
        if not def then return end
    end
    local projectileReach = 0
    local function proj(name)
        local p = sim:_projDef(me, name)
        if type(p) == "table" then
            local r = type(p.range) == "number" and p.range or 0
            local speed = tonumber(p.speed) or (type(p.vx) == "number" and math.abs(p.vx)) or 0
            local life = tonumber(p.life) or tonumber(p.lifetime) or 0
            projectileReach = math.max(projectileReach, r, speed * life)
        end
        return p
    end
    local cacheKey = key == "ult" and "V" or (key == "form" and "C" or "skill")
    local ownerCache = infoCache[me]
    if not ownerCache or ownerCache.ownProj ~= me.ownProj or ownerCache.form ~= me.form or ownerCache.def ~= me.def then
        ownerCache = {ownProj = me.ownProj, form = me.form, def = me.def, definitions = setmetatable({}, {__mode = "k"})}
        infoCache[me] = ownerCache
    end
    local cache = ownerCache.definitions[def]
    if not cache then cache = {}; ownerCache.definitions[def] = cache end
    local entry = cache[cacheKey]
    if not entry then
        entry = {features = Kind.features(def, proj),
            cat = Kind.classify(sim:_moveName(me, id), "", "", def, proj,
                cacheKey ~= "skill" and cacheKey or nil)}
        entry.projectileReach = projectileReach
        local startup, duration, activeSeen, targetTeleport, approachSpeed, armoredApproach = 0, 0, false, false, 0, false
        local groundDamage, firstActiveDuration, approachTo, firstProjectileSpeed, firstHitDelay, firstDirectHit, hasShot = false, 0, nil, 0, 0, nil, false
        local openingBeatsGuard = def.unblockable == true
        local openingPulseRadius
        local jumpsBeforeHit = false
        for index, k in ipairs(def.keys or {}) do
            local active = k.hit or k.grab
            if k.hit then groundDamage = true end
            if k.hit and not k.hit.shot and not activeSeen then firstDirectHit = k.hit end
            if not activeSeen and (k.grab or (k.hit and (k.hit.unblockable or k.hit.grab))) then openingBeatsGuard = true end
            if k.hit and type(k.hit.shot) == "string" then
                hasShot = true
                local projectile = proj(k.hit.shot)
                if not activeSeen and type(projectile) == "table" and not projectile.beam then firstProjectileSpeed = tonumber(projectile.speed) or 0 end
                if not activeSeen and type(projectile) == "table" and projectile.unblockable then openingBeatsGuard = true end
                if not activeSeen and type(projectile) == "table" then entry.shotNoStun = projectile.shotNoStun == true end
            end
            for _, fx in pairs(k.fx or {}) do
                local pulse = fx[1] == "pulse" and type(fx[2]) == "table" and not fx[2].statusOnly
                    and (tonumber(fx[2].dmg) or 0) > 0
                if fx[1] == "proj" or fx[1] == "strike" or fx[1] == "whip" or fx[1] == "release" or pulse then active = true end
                if pulse and not activeSeen and (fx[2].guardBreak or fx[2].unblockable) then openingBeatsGuard = true end
                if pulse and not activeSeen then
                    openingPulseRadius = math.max(openingPulseRadius or 0, tonumber(fx[2].r) or 4)
                end
                if fx[1] == "proj" or fx[1] == "strike" or fx[1] == "whip" then groundDamage = true end
                if (fx[1] == "zone" or fx[1] == "sprout") and type(fx[2]) == "table" and fx[2].hit then
                    active = true
                    if def.otg == true or def.hitDown == true then groundDamage = true end
                    if not activeSeen then firstHitDelay = math.max(firstHitDelay, tonumber(fx[2].delay) or (fx[1] == "sprout" and 0.3 or 0)) end
                end
                if not activeSeen and fx[1] == "sprout" and type(fx[2]) == "table"
                    and (not fx[2].at or fx[2].at == "target") and fx[2].hit and fx[2].hit.grab
                    and not fx[2].follow then
                    entry.targetTrap = {delay = tonumber(fx[2].delay) or 0.3, radius = tonumber(fx[2].r) or 0.9}
                end
                if not activeSeen and fx[1] == "proj" and type(fx[2]) == "string" then
                    local projectile = sim:_projDef(me, fx[2])
                    if type(projectile) == "table" and not projectile.beam then firstProjectileSpeed = tonumber(projectile.speed) or 0 end
                    if type(projectile) == "table" and projectile.unblockable then openingBeatsGuard = true end
                elseif not activeSeen and (fx[1] == "strike" or fx[1] == "whip") and type(fx[2]) == "table" then
                    firstHitDelay = math.max(firstHitDelay, tonumber(fx[2].delay) or 0)
                    if fx[2].unblockable or fx[2].grab then openingBeatsGuard = true end
                end
                if fx[1] == "teleport" and (fx[2] == "around" or fx[2] == "behind" or fx[2] == "target") then targetTeleport = true end
            end
            local time = (tonumber(k.dur) or tonumber(k.t) or 0.05) + (tonumber(k.hold) or 0)
            if not activeSeen and not active and k.untilLand then
                jumpsBeforeHit = true
                time = math.max(time, tonumber(k.maxT) or time)
            end
            if not activeSeen and type(k.vel) == "table" and (tonumber(k.vel[1]) or 0) >= 10 then
                approachSpeed = math.max(approachSpeed, k.vel[1])
                if type(k.untilClose) == "number" then approachTo = k.untilClose end
                if (tonumber(k.armor) or 0) > 0 then armoredApproach = true end
            end
            if active and not activeSeen then
                firstActiveDuration = tonumber(k.dur) or 0.05
                entry.firstActiveProtected = k.invuln == true
            end
            if active then activeSeen = true; entry.lastActiveKey = index end
            if not activeSeen then startup = startup + time end
            duration = duration + time
        end
        entry.startup = startup
        entry.duration = duration
        entry.needsTarget = activeSeen
        entry.targetTeleport = targetTeleport and activeSeen
        entry.approachSpeed, entry.armoredApproach = approachSpeed, armoredApproach and activeSeen
        entry.groundDamage, entry.firstActiveDuration, entry.approachTo = groundDamage, firstActiveDuration, approachTo
        entry.firstProjectileSpeed, entry.firstHitDelay = firstProjectileSpeed, firstHitDelay
        entry.firstDirectHit = firstDirectHit
        entry.shot, entry.projectileReach = hasShot, projectileReach
        entry.openingBeatsGuard = openingBeatsGuard
        entry.openingPulseRadius = openingPulseRadius
        entry.jumpsBeforeHit = jumpsBeforeHit
        cache[cacheKey] = entry
    end
    local range = def.range or {0, 4}
    local opening = def.keys and def.keys[1]
    local hi = math.max(range[2] or 4, 1.5)
    local ranged = (entry.features.proj or 0) > 0 or entry.features.beam or entry.shot
    if ranged and (not entry.jumpsBeforeHit or entry.shot) then
        hi = math.max(hi, math.min(30, entry.projectileReach or 0))
        if hi <= 4 then hi = Bot.RangedFallback end
    end
    if entry.shot and type(me.def and me.def.shotFar) == "number" then hi = math.min(hi, me.def.shotFar) end
    return {def = def, features = entry.features, cat = entry.cat,
        lo = entry.approachTo and 0 or (range[1] or 0), hi = hi, startup = entry.startup, duration = entry.duration,
        protectedStartup = def.keys and def.keys[1] and def.keys[1].invuln == true,
        stopsOnCast = opening and opening.vel and opening.vel[1] == 0 and not opening.keepVel,
        targetTeleport = entry.targetTeleport, approachSpeed = entry.approachSpeed,
        armoredApproach = entry.armoredApproach, ranged = ranged, groundDamage = entry.groundDamage,
        needsTarget = entry.needsTarget,
        shot = entry.shot, shotNoStun = entry.shotNoStun,
        openingBeatsGuard = entry.openingBeatsGuard,
        openingPulseRadius = entry.openingPulseRadius,
        firstActiveDuration = entry.firstActiveDuration, firstActiveProtected = entry.firstActiveProtected,
        approachTo = entry.approachTo,
        firstDirectHit = entry.firstDirectHit,
        firstProjectileSpeed = entry.firstProjectileSpeed, firstHitDelay = entry.firstHitDelay,
        targetTrap = entry.targetTrap, lastActiveKey = entry.lastActiveKey}
end
local function arenaWideUltimate(sim, id, info)
    if Combat and Combat.ULT_ANYWHERE and Combat.ULT_ANYWHERE[id] then return true end
    local halfW = tonumber(sim.halfW)
    -- The engine scales the cast range separately from the damage radius.
    -- Check cast legality with _ultReach, even for a pulse that spans the arena.
    return halfW and halfW > 0 and info.openingPulseRadius ~= nil and info.openingPulseRadius >= 2 * halfW or false
end
local function ultimateOpportunity(sim, me, foe, id, info, lead, eta, foeCounter, arenaWide)
    if not hittable(sim, foe) or foe.state == "held" then return false, "target protected" end
    if foeCounter then return false, "opponent counter" end
    if foe.state == "block" and not info.openingBeatsGuard then return false, "opponent guarding" end
    if (me.dashT or 0) > 0 then return false, "finishing movement" end
    if type(sim._ultReach) ~= "function" then return false, "reach query unavailable" end
    if checkMethod(sim, "_ultBlocked", foe) then return false, "native target restriction" end
    local ok, reach = pcall(sim._ultReach, sim, me, id, foe)
    if not ok or reach ~= "in" then return false, "outside cast range", reach end
    local tempo = info.def.fixedTime and 1 or tonumber(me.def and me.def.tempo) or 1
    local startup = info.startup * tempo
    local function predictedReach(after, impact)
        local own, target = copyFields(me), copyFields(foe)
        local drift = info.stopsOnCast and math.min(after, lead) or after
        own.x, own.y = me.x + (me.vx or 0) * drift, me.y + (me.vy or 0) * drift
        target.x, target.y = foe.x + (foe.vx or 0) * after, foe.y + (foe.vy or 0) * after
        local halfW = tonumber(sim.halfW)
        if halfW and halfW > 0 then
            own.x = math.max(-halfW, math.min(halfW, own.x))
            target.x = math.max(-halfW, math.min(halfW, target.x))
        end
        if impact and arenaWide and info.openingPulseRadius then
            return (target.x - own.x) ^ 2 + (target.y - own.y) ^ 2 <= info.openingPulseRadius ^ 2
        end
        local success, value = pcall(sim._ultReach, sim, own, id, target)
        return success and value == "in"
    end
    -- A protected cinematic that stops the caster invalidates the current movement forecast.
    local predictionWindow = info.protectedStartup and info.stopsOnCast and math.min(startup, 0.35) or startup
    if not predictedReach(lead) or not predictedReach(lead + predictionWindow, true) then
        return false, "target leaving cast range", reach
    end
    local confirmed = foe.state == "stun" and (foe.stunT or 0) >= lead + startup + 1 / 60
    if eta < lead + 0.1 and not confirmed and not info.protectedStartup then return false, "defend before casting", reach end
    return true, "ready in confirmed range", reach
end
local function groundFollowup(sim, me, foe, info, key, lead, distance)
    local gettingUp = foe.state == "move" and (foe.moveBase == "GetUpKD" or foe.moveBase == "GetUp")
    local floorMelee = info.firstDirectHit and not info.def.ultimate
        and checkMethod(sim, "_floorMelee", me, foe, info.firstDirectHit, "move")
    if key == "ult" or key == "form" or info.def.ultimate or (foe.state ~= "down" and not gettingUp
        and not (foe.state == "tumble" and info.def.hitDown == true)) or protectedTarget(sim, foe, floorMelee)
        or not info.groundDamage or info.features.grab or info.def.basic then return false, "protected/unsupported" end
    if not me.grounded and not (info.def.otg == true and not info.ranged) then return false, "air geometry" end
    local tempo = info.def.fixedTime and 1 or tonumber(me.def and me.def.tempo) or 1
    local startup = info.startup * tempo
    if info.approachTo and info.approachSpeed > 0 then
        startup = math.max(startup, math.max(0, distance - info.approachTo) / info.approachSpeed)
    end
    local impact = lead + startup + (info.firstActiveDuration or 0) * tempo + (info.firstHitDelay or 0)
    if (info.firstProjectileSpeed or 0) > 0 then impact = impact + math.max(0, distance - 1) / info.firstProjectileSpeed end
    -- Runtime read-only predicates decide ownership/caps; a proxy clock checks
    -- arrival/impact without advancing the live simulation or its fighter state.
    local function query(name, after, ...)
        if type(sim[name]) ~= "function" then return false end
        local future = setmetatable({t = (sim.t or 0) + after}, {__index = sim})
        local ok, result = pcall(sim[name], future, ...)
        return ok and result == true
    end
    local arrival = lead + 1 / 60
    local downLeft = tonumber(foe.downT)
    local activeOTG = query("_otgDown", 0, foe)
    if floorMelee and not activeOTG then
        local hold = gettingUp and moveRemaining(foe) or downLeft
        if hold and hold > impact then return true, "native floor melee" end
        return false, "floor melee too late"
    end
    if info.def.hitDown == true and not activeOTG and not gettingUp then
        local hold = foe.state == "down" and downLeft or math.max(0, (foe.hdHoldTo or 0) - (sim.t or 0))
        if info.def.otg == true then hold = math.max(hold or 0, GroundRules.OTG_SKILL_EXT or 0.8) end
        if hold and hold > impact then return true, "native hitDown skill" end
        return false, "hitDown hold too short"
    end
    if foe.kdGetup or (tonumber(foe.kdT) or 0) > (sim.t or 0) then return false, "knockdown protection" end
    if not downLeft or downLeft <= arrival then return false, "standing before input arrives" end
    if query("_otgDown", arrival, foe) then
        if not query("_otgOk", arrival, me, foe, "move", nil) then return false, "ground cap/window closed" end
        -- Tagged OTG moves ask the game to extend its floor hold on start. Other
        -- attacks must fit the existing hold/window through their first hit.
        if info.def.otg ~= true and (downLeft <= impact or not query("_otgOk", impact, me, foe, "move", nil)) then
            return false, "ground window too short"
        end
        if info.def.otg == true and (sim.t or 0) + impact > (foe.otgT0 or 0)
            + (foe.otgWin or GroundRules.OTG_WIN or 1.25) + (GroundRules.OTG_SKILL_EXT or 0.8) then
            return false, "OTG extension too short"
        end
        return true, info.def.otg == true and "native OTG hold" or "native ground window"
    end
    if query("_dcDown", arrival, foe) and foe.dcBy == me.idx and not foe.dcCap
        and downLeft > impact then return true, "owned down combo" end
    return false, "ground window closed"
end
local function minorZoneHit(hit, tick, arg)
    if type(hit) ~= "table" or hit.noStun ~= true or hit.grab or hit.unblockable
        or (tonumber(hit.stun) or 0) > 0 or (tonumber(hit.dmg) or 0) > 2 then return false end
    if type(tick) == "number" and (tick <= 0 or (tonumber(hit.dmg) or 0) / tick > 4) then return false end
    if type(arg) == "table" and (arg.autoFire ~= nil or arg.pinFire ~= nil or arg.pull or arg.sink) then return false end
    if type(hit.kb) == "table" and (math.abs(tonumber(hit.kb[1]) or 0) > 0 or math.abs(tonumber(hit.kb[2]) or 0) > 0) then return false end
    for _, name in ipairs({"root", "stun", "freeze", "seal", "noBlock", "sleep"}) do
        if hit.status and hit.status[name] then return false end
    end
    return true
end
local function defenseKeyAt(info, me, afterInput)
    if afterInput < 0 then return nil end
    local tempo = info.def.fixedTime and 1 or tonumber(me.def and me.def.tempo) or 1
    for _, key in ipairs(info.def.keys or {}) do
        local duration = ((tonumber(key.dur) or 0.05) + (tonumber(key.hold) or 0)) * tempo
        if afterInput < duration then return key end
        afterInput = afterInput - duration
    end
end
local function guardCounterCovers(counters, distance, hit)
    if not counters or (hit and hit.noCounter) then return false end
    for _, counter in ipairs(counters) do
        if distance <= (tonumber(counter.counterNear) or math.huge)
            and not (counter.counterBypass and hit and (hit.grab or hit.unblockable)) then
            return true
        end
    end
    return false
end
local function threat(sim, me)
    local soon, projectile, unblockable, blockDir, source = math.huge, false, false, nil, nil
    local minorZone, targetedUltimate
    local function consider(eta, ranged, cannotBlock, direction, kind, isTargetedUltimate)
        if eta < soon or (cannotBlock == true and not unblockable and eta <= soon + 1 / 60) then
            soon, projectile, unblockable, blockDir, source = math.max(0, eta), ranged == true,
                cannotBlock == true, direction, kind
            targetedUltimate = isTargetedUltimate
        end
    end
    for _, foe in pairs(sim.fighters) do
        -- Ordinary forward Q resolves contact separately from move keys. It is
        -- already a threat while the attacker is still in the neutral state.
        if foe.team ~= me.team and not foe.ko and foe.state == "neutral" and foe.dashFwd
            and not foe.dashHit and (foe.dashT or 0) > 0 then
            local facing = foe.facing or 1
            local gap = (me.x - foe.x) * facing
            local scale = ((me.def and me.def.scale or 1) + (foe.def and foe.def.scale or 1)) * 0.5
            local closing = ((foe.vx or 0) - (me.vx or 0)) * facing
            local eta = gap <= 2.5 * scale and 0 or (closing > 0 and (gap - 2.5 * scale) / closing or math.huge)
            if gap >= -0.5 and eta <= (foe.dashT or 0) and math.abs(foe.y - me.y) <= 2.2 * scale then
                consider(eta, false, false, -facing, "dash contact")
            end
        end
        if foe.team ~= me.team and not foe.ko and foe.state == "move" and foe.move then
            local move, eta = foe.move, -(foe.kt or 0)
            local dist = math.abs(foe.x - me.x)
            local range = move.range or {0, 4}
            local closing = math.max(0, ((foe.vx or 0) - (me.vx or 0)) * (me.x >= foe.x and 1 or -1))
            local targetWarp, remoteStrike, ultimatePulse = false, false, false
            for i = foe.key or 1, #move.keys do
                for _, fx in ipairs(move.keys[i].fx or {}) do
                    if fx[1] == "teleport" and (fx[2] == "around" or fx[2] == "behind" or fx[2] == "through") then targetWarp = true end
                    if fx[1] == "strike" and type(fx[2]) == "table" and fx[2].ignoreDist then remoteStrike = true end
                    if move.ultimate and fx[1] == "pulse" and i > (foe.key or 1) and type(fx[2]) == "table"
                        and not fx[2].statusOnly and (tonumber(fx[2].dmg) or 0) > 0 then ultimatePulse = true end
                end
            end
            local attackX, relocated = foe.x, false
            local nearby = targetWarp or (dist <= (range[2] or 4) + 1.4 + closing * 0.35 and math.abs(foe.y - me.y) < 4)
            if nearby or remoteStrike or ultimatePulse then
                for i = foe.key or 1, #move.keys do
                    local k = move.keys[i]
                    local active, ranged, flight = k.hit or k.grab or k.needsGrab, false, 0
                    local cannotBlock = move.unblockable or k.grab or k.needsGrab or (type(k.hit) == "table"
                        and (k.hit.grab or k.hit.unblockable))
                    for _, fx in pairs(k.fx or {}) do
                        if fx[1] == "teleport" and i > (foe.key or 1) then
                            local offset
                            if fx[2] == "around" then offset = tonumber(fx[3]) or 0
                            elseif fx[2] == "behind" then offset = -(me.facing or 1) * (tonumber(fx.dist) or 2)
                            elseif fx[2] == "through" then offset = (me.x >= attackX and 1 or -1) * (tonumber(fx.dist) or 2.6) end
                            if offset then
                                if sim.halfW and math.abs(me.x + offset) > sim.halfW - 1 then offset = -offset end
                                attackX, relocated = me.x + offset, true
                            end
                        elseif fx[1] == "proj" then
                            active, ranged = true, true
                            if type(fx[2]) == "string" then
                                local p = sim:_projDef(foe, fx[2])
                                if type(p) == "table" and not p.beam and (tonumber(p.speed) or 0) > 0 then
                                    flight = math.max(0, dist - 1) / p.speed
                                end
                            end
                        elseif fx[1] == "strike" and type(fx[2]) == "table" and fx[2].ignoreDist then
                            local hit = fx[2]
                            if i > (foe.key or 1) and not k.needsGrab and not hit.zone
                                and (not hit.near or dist <= hit.near) then
                                consider(eta + (tonumber(hit.delay) or 0), false,
                                    cannotBlock or hit.grab or hit.unblockable, -(foe.facing or 1), "targeted strike",
                                    hit.ult == true or move.ultimate == true)
                            end
                        elseif fx[1] == "strike" or fx[1] == "whip" or fx[1] == "release" then
                            active = true
                            local h = type(fx[2]) == "table" and fx[2] or {}
                            cannotBlock = cannotBlock or h.grab or h.unblockable
                                or (fx[1] == "whip" and h.unblockable ~= false)
                        elseif ultimatePulse and fx[1] == "pulse" and i > (foe.key or 1) and type(fx[2]) == "table" then
                            local hit = fx[2]
                            local radius = tonumber(hit.r) or 4
                            if not hit.statusOnly and (tonumber(hit.dmg) or 0) > 0
                                and (me.x - attackX) ^ 2 + (me.y - foe.y) ^ 2 <= radius ^ 2 then
                                consider(eta, false, hit.unblockable or hit.grab, attackX >= me.x and 1 or -1, "ultimate pulse")
                            end
                        elseif nearby and (fx[1] == "sprout" or fx[1] == "zone") and type(fx[2]) == "table" then
                            local z = fx[2]
                            if type(z.hit) == "table" then
                                local at = z.at or (fx[1] == "sprout" and "target" or "self")
                                local center = (at == "self" and foe.x or me.x) + (z.dx or 0) * (foe.facing or 1)
                                local wait = math.max(0, eta) + (tonumber(z.delay) or (fx[1] == "sprout" and 0.3 or 0))
                                if (at == "self" or at == "target" or at == "targetBody")
                                    and math.abs(me.x + (me.vx or 0) * wait - center) <= (z.r or 0.9) + 1.2 then
                                    if not minorZoneHit(z.hit, z.tick, z) then
                                        consider(wait, false, z.hit.grab or z.hit.unblockable or false,
                                            center >= me.x and 1 or -1, "delayed effect")
                                    end
                                end
                            end
                        end
                    end
                    if nearby and active then
                        consider(eta + flight, ranged, cannotBlock and true or false,
                            attackX >= me.x and 1 or -1, relocated and "teleport attack" or "move")
                        break
                    end
                    local duration = (tonumber(k.dur) or tonumber(k.t) or 0.1) + (tonumber(k.hold) or 0)
                    local currentKey = move.keys[foe.key or 1]
                    local base = currentKey and (tonumber(currentKey.dur) or tonumber(currentKey.t))
                    local scale = base and base > 0 and (foe.keyDur or base) / base or 1
                    if i == (foe.key or 1) then
                        eta = eta + (foe.keyDur or duration * scale) + (foe.keyHold or (tonumber(k.hold) or 0) * scale)
                    else eta = eta + duration * scale end
                end
            end
        end
    end
    for _, p in pairs(sim.projectiles or {}) do
        local owner = sim.fighters[p.owner]
        if owner and owner.team ~= me.team and not p.dead and type(p.vx) == "number" then
            local dx = me.x - p.x
            local relativeVx = p.vx - (me.vx or 0)
            if dx * relativeVx > 0 then
                local eta = dx / relativeVx
                local impactY = p.y + (p.vy or 0) * eta
                local targetY = me.y + (me.vy or 0) * eta
                if eta < soon and math.abs(impactY - targetY) < 3 then
                    consider(eta, true, type(p.def) == "table" and (p.def.unblockable or p.def.grab) or false,
                        p.x >= me.x and 1 or -1, "projectile")
                end
            end
        end
    end
    for _, z in pairs(sim.zones or {}) do
        local owner = sim.fighters[z.owner]
        local lastHit = z.hits and z.hits[me.idx]
        local repeatable = type(z.tick) == "number"
        if owner and owner.team ~= me.team and not z.dead and type(z.hit) == "table"
            and not (lastHit ~= nil and (z.once or not repeatable)) then
            local wait = math.max(0, (tonumber(z.delay) or 0) - (tonumber(z.t) or 0))
            if type(lastHit) == "number" and repeatable then wait = math.max(wait, lastHit + z.tick - (sim.t or 0)) end
            local aliveAtImpact = type(z.life) ~= "number" or (tonumber(z.t) or 0) + wait < z.life or z.armed == false
            local x, y = me.x + (me.vx or 0) * wait, me.y + (me.vy or 0) * wait
            local a, b = z.p0, z.p1
            local zx, zy = tonumber(z.x) or 0, tonumber(z.y) or 0
            if a and b then
                local vx, vy = b.X - a.X, b.Y - a.Y
                local len = vx * vx + vy * vy
                local t = len > 0 and math.max(0, math.min(1, ((x - a.X) * vx + (y - a.Y) * vy) / len)) or 0
                zx, zy = a.X + vx * t, a.Y + vy * t
            end
            local r = (tonumber(z.cr) or tonumber(z.r) or 0.9) + 1.2
            if aliveAtImpact and (x - zx) ^ 2 + (y - zy) ^ 2 <= r ^ 2 then
                if minorZoneHit(z.hit, z.tick, z.arg or z) then
                    minorZone = {kind = z.kind, eta = wait, damage = z.hit.dmg, tick = z.tick}
                else
                    consider(wait, false, z.hit.unblockable or z.hit.grab or false, zx >= me.x and 1 or -1, "zone")
                end
            end
        end
    end
    return soon, projectile, unblockable, blockDir, source, minorZone, targetedUltimate
end
local function closeDashReach(me, foe, dir, lead, sim)
    if type(me.def) ~= "table" or type(foe.def) ~= "table"
        or type(me.def.scale) ~= "number" or type(foe.def.scale) ~= "number"
        or me.mvt == "blink" or me.def.dashSkill ~= nil
        or (me.statusOn and me.status and me.status.root ~= nil) or me.hbuf then return false end
    local scale = (me.def.scale + foe.def.scale) * 0.5
    local reach = 2.5 * scale
    local gap = (foe.x - me.x + ((foe.vx or 0) - (me.vx or 0)) * lead) * dir
    if gap < 0.65 or gap > math.min(4.5, reach + 1.5) or math.abs(foe.y - me.y) > 2.2 * scale then return false end
    local mul = me.mvt == "dash" and 1.4 or 1
    local cls = me.cls or {}
    local duration = mul * 0.225 * (cls.dashTime or 1)
    local speed = math.max(15.923076923076923 * mul * (cls.dashDist or 1) / (cls.dashTime or 1),
        1.2 * (me.spd or 0)) * (sim and type(sim._dashFinish) == "function" and 1.2 or 1)
    local closing = speed - (foe.vx or 0) * dir
    return closing > 0 and math.max(0, gap - reach) / closing <= math.min(0.16, duration * 0.7)
end
local function dashRechargeLength(sim, me)
    if type(sim._dashCdLen) == "function" then
        local ok, value = pcall(sim._dashCdLen, sim, me)
        if ok and type(value) == "number" and value > 0 then return value end
    end
    return tonumber(me.dashCdLen) or 2
end
local function dashBudget(me, t)
    local charges = math.max(0, math.floor(tonumber(me.dashN) or 0))
    if pendingDash and (pendingDash.me ~= me or t < pendingDash.at or t > pendingDash.untilT
        or (me.dashAt or -100) > pendingDash.previousAt or charges < pendingDash.before) then pendingDash = nil end
    local available = math.max(0, charges - (pendingDash and 1 or 0))
    local maximum = math.max(1, tonumber(me.dashMax) or math.max(2, charges))
    local reserve = math.max(Bot.ReserveDashCharges, math.ceil(maximum * Bot.ReserveDashFraction))
    local rooted = me.statusOn and me.status and me.status.root ~= nil
    local airReady = me.grounded or (me.airDashes or 0) < (me.mvt == "swing" and 2 or 1)
    local ready = available > 0 and not pendingDash and not rooted and airReady
        and (me.dashT or 0) <= 0 and t >= (me.dashAt or -10) + 0.2 - 1e-6
    local rechargeIn = charges < maximum and math.max(0, (tonumber(me.dashCd) or t) - t) or 0
    return ready, available, reserve, rechargeIn
end
local function decide(manual)
    local current = discover()
    if not current then status("Waiting for fight session"); return end
    local sim = current.r.sim
    local me = sim.fighters and sim.fighters[current.side]
    if not me or me.ko or sim.phase ~= "fight" or current.r.paused then
        status("Waiting for round"); return
    end
    local now = os.clock()
    local out = {x = 0, block = false, down = false}
    if blockedMatch then status("Skipping opponent previously lost to"); return out end
    Bot.ControlState = me.human and "full" or (me.cmdMine and "auto" or "cpu")
    if not me.human then
        if not me.switchable then status("Full CONTROL unavailable; automation waiting"); return end
        if now >= nextSwitch then out.switch = true; nextSwitch = now + 0.8 end
        status("Switching to full CONTROL")
        return out
    end
    local foe = sim:other(me)
    if not foe or foe.ko then return out end
    local dx = foe.x - me.x
    local dir = dx >= 0 and 1 or -1
    local distance = math.abs(dx)
    local nc = current.nc
    local inputFrame = type(sim.frame) == "number" and sim.frame + (tonumber(nc.delay) or 6)
    local ownKnown = nc.known and nc.known[nc.side or current.side]
    if inputFrame and type(ownKnown) == "number" and inputFrame <= ownKnown then
        -- Netplay can only carry presses across these frames. Re-evaluate before
        -- committing an action at the first frame that can accept fresh input.
        Bot.Snapshot = {action = "input frame already filled", selfState = me.state, foeState = foe.state,
            distance = distance, threatETA = -1, inputFrame = inputFrame, ownKnown = ownKnown,
            ultimate = {ready = false, reason = "input frame already filled"}}
        status("Waiting for fresh input frame")
        return Bot.Movement == "manual" and manual or out
    end
    local targetHittable = hittable(sim, foe)
    local trapped = lockedState(me)
    if previousSelf == me and previousHp and me.hp < previousHp and trapped then
        memory.defenseMargin = math.min(0.12, (memory.defenseMargin or 0) + 0.015)
    end
    previousSelf, previousHp = me, me.hp
    local eta, isProjectile, unblockable, blockDir, threatSource, minorZone, targetedUltimate = threat(sim, me)
    local targetedStrike = threatSource == "targeted strike"
    blockDir = blockDir or dir
    local lead = math.min(0.35, math.max(0, tonumber(current.nc.delay) or 6) / 60 + 1 / 60)
    local combatClock = type(sim.t) == "number" and sim.t or now
    if pendingAttack and (pendingAttack.me ~= me or trapped or combatClock < pendingAttack.at
        or me.moveSeq ~= pendingAttack.seq or combatClock > pendingAttack.untilT) then pendingAttack = nil end
    -- Arrival commitments prevent unrelated offense from replacing an earlier
    -- buffered press. A newly observed threat still gets defensive priority.
    local attackPending = pendingAttack ~= nil
    local dashReady, dashAvailable, dashReserve, dashRechargeIn = dashBudget(me, combatClock)
    local offensiveDashReady = dashReady and dashAvailable > dashReserve and combatClock >= nextOffensiveDash
    local blockAllowed = not checkMethod(sim, "_statusHas", me, "noBlock")
        and not (me.statusOn and me.status and me.status.noBlock)
        and (me.clKdLockT or 0) <= combatClock
    local guardRequired = Bot.MinGuardToBlock
    if me.cls and type(me.cls.blockPunches) == "number" and type(me.guardMax) == "number" then
        guardRequired = math.max(math.min(guardRequired, me.guardMax * 0.3), me.guardMax / (me.cls.blockPunches + 0.5) + 0.5)
    end
    local guardSafe = blockAllowed and type(me.guard) == "number" and me.guard >= guardRequired
        and (me.guardLockT == nil or me.guardLockT <= combatClock)
    if Bot.RecoveryGuard and trapped and me.grounded and guardSafe and distance <= 4.2 and not unblockable then
        recoveryGuardUntil = combatClock + lead + 0.18
    end
    local recoveryGuard = Bot.RecoveryGuard and guardSafe and me.grounded and not unblockable
        and combatClock < recoveryGuardUntil and distance <= 4.2
    if dashOpener then
        if not Bot.CloseDashOpener or Bot.Movement == "manual" or dashOpener.me ~= me or dashOpener.foe ~= foe or trapped or not targetHittable
            or combatClock < dashOpener.at or combatClock - dashOpener.at > 1.2 then dashOpener = nil
        elseif not dashOpener.confirmed and (me.dashAt or -100) <= dashOpener.previousDashAt
            and combatClock > dashOpener.at + lead + 0.25 then dashOpener = nil
        elseif dashOpener.followAt then
            if (me.state == "move" and me.move and me.move.basic == "light" and me.moveSeq ~= dashOpener.followSeq)
                or combatClock > dashOpener.followAt + lead + 0.12 then dashOpener = nil end
        elseif (me.dashAt or -100) > dashOpener.previousDashAt and me.dashHit then
            if foe.state == "stun" and foe.hp < dashOpener.hp then
                if not dashOpener.confirmed then
                    dashOpener.confirmed = true
                    defenseUntil = math.min(defenseUntil, combatClock)
                    logger:line("dash_opener_hit", {simTime = combatClock, hp = foe.hp})
                end
            else dashOpener = nil end -- block, armor or unconfirmed contact: no forced follow-up
        end
    end
    local dashWaiting = dashOpener and (not dashOpener.confirmed or dashOpener.followAt ~= nil)
    local defensePending = combatClock < defenseUntil
    local danger = eta < 0.28 + lead + (memory.defenseMargin or 0)
    local imminent = eta < 0.10 + lead + (memory.defenseMargin or 0)
    if danger and defenseKind == "approach" then
        defensePending = false; defenseUntil = combatClock; dashOpener = nil; dashWaiting = false
    end
    local kit = sim:commandKit(me)
    local controls = sim:controls(me)
    local slots = {ult = sim.kitKeys and (kit.ult or controls.ult) or controls.ult,
        form = sim.kitKeys and kit.awaken or nil}
    for _, key in ipairs({"x1", "x2", "x3"}) do slots[key] = sim:_pressMove(me, key) end
    if me.formPending ~= nil and type(sim._pendingMove) == "function" then slots.form = sim:_pendingMove(me) or slots.form end
    Bot.Snapshot = {selfState = me.state, foeState = foe.state, distance = distance,
        hp = me.hp, targetHittable = targetHittable, threatETA = eta < 100 and eta or -1,
        dashCharges = me.dashN or 0, opponentId = opponentId, defenseMargin = memory.defenseMargin or 0}
    Bot.Snapshot.dashAvailable = dashAvailable
    Bot.Snapshot.dashReserve = dashReserve
    Bot.Snapshot.dashRechargeIn = dashRechargeIn
    Bot.Snapshot.dashInputPending = pendingDash ~= nil
    Bot.Snapshot.attackInputPending = attackPending
    Bot.Snapshot.threatSource = threatSource
    Bot.Snapshot.threatBypassesDash = targetedUltimate or nil
    Bot.Snapshot.minorZone = minorZone
    Bot.Snapshot.blockDirection = blockDir
    Bot.Snapshot.threatUnblockable = unblockable
    Bot.Snapshot.foeControl = controlMode(foe)
    Bot.Snapshot.dashOpener = dashOpener and (dashOpener.followAt and "J queued" or (dashOpener.confirmed and "hit confirmed" or "Q queued")) or nil
    Bot.Snapshot.blockAllowed, Bot.Snapshot.guardRequired = blockAllowed, guardRequired
    Bot.Snapshot.comboStyle, Bot.Snapshot.comboDamageTier = me.cl, foe.cdN
    Bot.Snapshot.networkLP = current.nc.lp == true
    Bot.Snapshot.dashSpeedMultiplier = type(sim._dashFinish) == "function" and 1.2 or 1
    -- Dashes/jumps cannot get you out of ordinary hitstun. Use a legal escape
    -- according to the live readiness API; never force a cooldown or state change.
    if trapped then
        if sim.clOn ~= nil and combatClock >= nextEscape then
            if me.clRag ~= nil and (me.state == "tumble" or me.state == "down") and checkMethod(sim, "_clEscOk", me) then
                out.dash = true; out.x = -dir; nextEscape = combatClock + math.max(0.15, lead + 0.04)
                Bot.Snapshot.action = "native ragdoll escape"; status("Ragdoll escape / Q")
                return out
            elseif me.clTechT ~= nil and me.state == "tumble" and not me.grounded and combatClock >= me.clTechT then
                out.jump = true; out.x = -dir; nextEscape = combatClock + math.max(0.15, lead + 0.04)
                Bot.Snapshot.action = "native air tech"; status("Air recovery / jump")
                return out
            end
        end
        local escapeKey, escapeScore = nil, 0
        local rising = me.state == "move" and (me.moveBase == "GetUp" or me.moveBase == "GetUpKD")
        local incomingHit
        if rising and foe.state == "move" and foe.hitCls == "move" and foe.move and not foe.move.ultimate then
            for i = foe.key or 1, #(foe.move.keys or {}) do
                if foe.move.keys[i].hit and not foe.move.keys[i].hit.shot then incomingHit = foe.move.keys[i].hit; break end
            end
        end
        local getupMelee = incomingHit and checkMethod(sim, "_floorMelee", foe, me, incomingHit, "move")
        Bot.Snapshot.getupMeleeThreat = getupMelee and true or false
        local needsEscape = not rising or ((not me.invuln or getupMelee) and (me.cbInvT or 0) <= combatClock and danger)
        if needsEscape then
            for _, key in ipairs({"x1", "x2", "x3", "form", "ult"}) do
                local kind = escapeKind(sim, me, key)
                if kind then
                    local score = kind == "breaker" and 3 or (kind == "evade" and 2 or 1)
                    if score > escapeScore then escapeKey, escapeScore = key, score end
                end
            end
        end
        if escapeKey and combatClock >= nextEscape then
            out[escapeKey] = true; nextEscape = combatClock + math.max(0.12, lead + 0.04)
            Bot.Snapshot.action = "escape:" .. escapeKey
            status("Breaking combo / " .. escapeKey)
        elseif recoveryGuard and not escapeKey then
            out.block = true; out.x = dir
            Bot.Snapshot.action = "recovery guard"; Bot.Snapshot.recoveryGuard = true
            status("Recovery / holding guard for release")
        else status("Hitstun / waiting for a legal escape") end
        return out
    end
    local reservedKey
    if Bot.ReserveBreaker then
        local cheapest = math.huge
        for _, key in ipairs({"x1", "x2", "x3"}) do
            local id = slots[key]
            if type(sim._breakerMove) == "function" then id = sim:_breakerMove(me, key) or id end
            local def = id and sim:_moveDef(me, id)
            if def and def.comboBreaker and canUse(sim, me, key) then
                local info = moveInfo(sim, me, slots[key], key)
                local cost = info and (info.features.dmg or 0) or 0
                if cost < cheapest then cheapest, reservedKey = cost, key end
            end
        end
    end
    local bestKey, bestScore, desired = nil, 0, 1.8
    local bestPriority, bestPunish, ultimateGoal = 0, nil, nil
    local arenaUlt = false
    local hasRangedKit, rangedOpportunity = false, false
    local spacingReason = "melee"
    local groundOptions = {}
    Bot.Snapshot.groundFollowups = {}
    Bot.Snapshot.skillReadiness = {}
    local fullOpponent = foe.human == true and not (foe.botSeat or foe.dummy or foe.tutorBot)
    local foeRecovery = fullOpponent and foe.state == "move" and eta == math.huge and moveRemaining(foe) or nil
    local foeTeleportETA, foeApproaches, guardCounters = math.huge, {}, nil
    if fullOpponent and (foe.state == "neutral" or foe.state == "block") then
        for _, key in ipairs({"x1", "x2", "x3"}) do
            local id = sim:_pressMove(foe, key)
            local info = moveInfo(sim, foe, id, key)
            if info and info.targetTeleport and canUse(sim, foe, key) then
                local tempo = info.def.fixedTime and 1 or tonumber(foe.def and foe.def.tempo) or 1
                foeTeleportETA = math.min(foeTeleportETA, info.startup * tempo)
            end
            if info and info.armoredApproach and canUse(sim, foe, key) then
                local tempo = info.def.fixedTime and 1 or tonumber(foe.def and foe.def.tempo) or 1
                foeApproaches[#foeApproaches + 1] = {startup = info.startup * tempo, speed = info.approachSpeed}
            end
            local opening = info and info.def.keys and info.def.keys[1]
            if distance <= 6 and foe.state == "block" and opening and opening.counter and (opening.onCounter or info.def.onCounter)
                and canUse(sim, foe, key) then
                guardCounters = guardCounters or {}
                guardCounters[#guardCounters + 1] = opening
            end
        end
    end
    local hp = me.hp / math.max(1, me.maxHp)
    local foeCounter = false
    if foe.move and foe.state == "move" then
        local k = foe.move.keys[foe.key or 1]
        foeCounter = k and (k.counter or k.reflect) and true or false
    end
    local recoveryWindow = 0
    if fullOpponent and targetHittable and not foeCounter and eta == math.huge and distance <= 6
        and foe.state == "move" and foe.move and not foe.moveHit and not foe.moveBlocked
        and not checkMethod(sim, "_cancelOk", foe) then
        local info = moveInfo(sim, foe, foe.moveBase, "skill")
        local frame = foe.move.keys and foe.move.keys[foe.key or 1]
        if info and info.def == foe.move and info.lastActiveKey and (foe.key or 1) > info.lastActiveKey
            and frame and not frame.armor and not frame.invuln then
            -- Only count the observed key's remaining time. Later keys may allow a cancel.
            recoveryWindow = math.max(0, (foe.keyDur or 0) + (foe.keyHold or 0) - (foe.kt or 0))
        end
    end
    Bot.Snapshot.punishWindow = recoveryWindow > 0 and recoveryWindow or nil
    Bot.Snapshot.openingBlocked = {}
    for _, key in ipairs({"x1", "x2", "x3", "ult", "form"}) do
        -- A ranged move on cooldown does not set the spacing for the whole kit.
        local kitInfo = key ~= "ult" and key ~= "form" and moveInfo(sim, me, slots[key], key)
        if kitInfo and kitInfo.ranged then
            hasRangedKit = true
        end
        local ready, readyReason, comboHold = canUse(sim, me, key)
        if key == "ult" and combatClock < nextUltimate then ready, readyReason = false, "awaiting ultimate result" end
        if key == "ult" then
            Bot.Snapshot.ultimate = {ready = ready, reason = readyReason or "checking opportunity", move = slots.ult}
            if Bot.PrioritizeUltimate and (ready or readyReason == "awaiting ultimate result") then
                local info = moveInfo(sim, me, slots.ult, key)
                arenaUlt = info and arenaWideUltimate(sim, slots.ult, info) or false
            end
        end
        if key ~= reservedKey and ready then
            Bot.Snapshot.skillReadiness[key] = readyReason or "ready"
            local info = moveInfo(sim, me, slots[key], key)
            if info then
                local f, cat, score = info.features, info.cat, 0
                local ranged = info.ranged
                local tempo = info.def.fixedTime and 1 or tonumber(me.def and me.def.tempo) or 1
                local startup = info.startup * tempo
                if info.approachTo and info.approachSpeed > 0 then
                    startup = math.max(startup, math.max(0, distance - info.approachTo) / info.approachSpeed)
                end
                local horizon = lead + startup
                local impact = horizon + (info.firstHitDelay or 0)
                if (info.firstProjectileSpeed or 0) > 0 and (not info.firstDirectHit or distance > 4) then
                    impact = impact + math.max(0, distance - 1) / info.firstProjectileSpeed
                end
                local groundOpening, groundReason = false, nil
                if not targetHittable then groundOpening, groundReason = groundFollowup(sim, me, foe, info, key, lead, distance) end
                groundOptions[key] = groundOpening
                if not targetHittable then Bot.Snapshot.groundFollowups[key] = {eligible = groundOpening, reason = groundReason} end
                local stunOpening = groundOpening or (foe.state == "stun" and (foe.clNoStunT or 0) <= combatClock
                    and math.max(tonumber(foe.stunT) or 0, tonumber(comboHold) or 0) >= horizon + 1 / 60)
                local ownDrift = info.stopsOnCast and lead or horizon
                local predictedDistance = math.abs(dx + (foe.vx or 0) * horizon - (me.vx or 0) * ownDrift)
                local inRange = predictedDistance >= info.lo and predictedDistance <= info.hi
                    and math.abs(foe.y - me.y) < (ranged and 4 or 3)
                if f.heal and hp >= Bot.HealBelow then
                    score = 0
                elseif key == "form" and me.formPending ~= nil then
                    score = 8
                elseif cat == "heal" then
                    if hp < Bot.HealBelow and eta > horizon + 0.12 then score = 5 + (1 - hp) * 5 end
                elseif cat == "counter" then
                    local frame = danger and defenseKeyAt(info, me, eta - lead)
                    if frame and not (unblockable and frame.counterBypass) then
                        if isProjectile then
                            if frame.reflect or frame.blockProj or (frame.counterProj and info.def.onCounterProj) then
                                score = 12 - eta * 3
                            end
                        elseif frame.counter and (frame.onCounter or info.def.onCounter)
                            and not (targetedStrike and frame.counterMelee)
                            and (not frame.counterNear or distance <= frame.counterNear) then
                            score = 12 - eta * 3
                        end
                    end
                elseif cat == "evade" then
                    local frame = danger and defenseKeyAt(info, me, eta - lead)
                    if frame and frame.invuln == true then score = 9 end
                elseif key == "form" or cat == "buff" or cat == "summon" then
                    if not danger and (foe.hp or 0) > 10 and (key == "form" or not info.needsTarget
                        or targetHittable or groundOpening) then score = key == "form" and 6 or 2 end
                elseif (inRange or key == "ult") and (targetHittable or groundOpening) and not foeCounter
                    and guardReady(sim, me, foe, key == "ult" and "ult" or "move", key == "ult" and lead or horizon) then
                    score = 2 + math.min(2, (f.dmg or 0) / 30)
                    if stunOpening then score = score + 2 end
                    score = score - (key == "ult" and math.min(startup * 1.5, 2) or startup * 1.5)
                    if foe.state == "block" and not info.def.unblockable and not f.grab then score = score * 0.35 end
                    if key == "ult" then score = score + 3 end
                    if danger and not f.invuln then score = score * 0.3 end
                end
                if attackPending and (score < 9 or key == "ult") then score = 0 end
                -- A long startup at point blank range gives neutral opponents
                -- an unforced punish. Keep such casts for range or confirmed stun.
                local protectedCast = key == "ult" and info.protectedStartup or (key ~= "ult" and f.invuln)
                if cat ~= "counter" and cat ~= "evade" and key ~= "form" and not protectedCast
                    and distance < 4 and not stunOpening and startup > lead + 0.3 then score = 0 end
                local offensive = cat ~= "counter" and cat ~= "evade" and cat ~= "heal" and key ~= "form" and key ~= "ult"
                if score > 0 and offensive and not ranged and info.firstDirectHit
                    and guardCounterCovers(guardCounters, predictedDistance, info.firstDirectHit) then
                    score = 0
                    Bot.Snapshot.openingBlocked[key] = "guarded melee counter ready"
                end
                local trap = info.targetTrap
                if score > 0 and fullOpponent and offensive and trap and not groundOpening
                    and not (foe.state == "stun" and (foe.stunT or 0) >= horizon + trap.delay + 1 / 60)
                    and (not foe.grounded or math.abs(foe.vx or 0) * trap.delay > trap.radius) then
                    score = 0
                    Bot.Snapshot.openingBlocked[key] = "target moving out of trap"
                end
                local commitment = lead + (info.duration or startup)
                local walkSpeed = math.max(8, tonumber(foe.spd) or 10)
                local dashReach = (foe.dashN or 0) > 0 and 3.5 or 0
                if score > 0 and offensive and not stunOpening and foeRecovery and ranged
                    and not info.firstActiveProtected and not info.openingBeatsGuard
                    and (info.duration or 0) > 0.65 and impact >= foeRecovery
                    and distance < 3 + walkSpeed * 1.1 * (commitment - foeRecovery) + dashReach then
                    score = 0
                    Bot.Snapshot.openingBlocked[key] = "opponent recovers before attack"
                end
                if score > 0 and offensive and not info.protectedStartup and not stunOpening then
                    local walkReach = 3 + walkSpeed * 1.1 * commitment + dashReach
                    if fullOpponent and foe.state == "neutral" and foe.dashFwd and (foe.dashT or 0) > 0 then
                        local dashTime = math.min(foe.dashT, impact)
                        local closing = math.max(0, -(foe.vx or 0) * dir)
                        local contactReach = 3 + closing * dashTime + walkSpeed * (impact - dashTime + 1 / 60)
                            + dashReach
                        if closing > 0 and impact > lead + 0.25 and distance <= contactReach then
                            score = 0
                            Bot.Snapshot.openingBlocked[key] = "dash can reach before attack"
                        end
                    end
                    local armoredPunish = false
                    for _, approach in ipairs(foeApproaches) do
                        local reachTime = math.max(0, distance - 3) / math.max(1, approach.speed + (info.approachSpeed or 0))
                        if math.max(approach.startup, reachTime) <= commitment then armoredPunish = true; break end
                    end
                    if eta <= horizon + 0.06 or (fullOpponent and (foe.state == "neutral" or foe.state == "block")
                        and (armoredPunish or (foeTeleportETA < commitment) or ((info.duration or 0) > 0.65 and distance < walkReach))) then score = 0 end
                end
                if key == "ult" then
                    local eligible, reason, reach = ultimateOpportunity(sim, me, foe, slots[key], info, lead, eta, foeCounter, arenaUlt)
                    Bot.Snapshot.ultimate = {ready = true, eligible = eligible and score > 0, reason = reason,
                        reach = reach, move = slots.ult, arenaWide = arenaUlt}
                    if eligible and score <= 0 then Bot.Snapshot.ultimate.reason = "waiting for a safe skill window" end
                    if not eligible then score = 0 end
                    if Bot.PrioritizeUltimate and reason == "outside cast range" and reach == "approach"
                        and targetHittable and not danger and not foeCounter and me.state == "neutral"
                        and (not f.heal or hp < Bot.HealBelow) then
                        ultimateGoal = math.max(0.65, (info.def.range and tonumber(info.def.range[2]) or 4) - 0.35)
                    end
                end
                local priority = score > 0 and 1 or 0
                if score > 0 and ranged and key ~= "ult" and key ~= "form"
                    and cat ~= "counter" and cat ~= "evade" and cat ~= "heal" and cat ~= "buff" and cat ~= "summon" then
                    rangedOpportunity = true
                    desired = math.max(desired, math.min(8, info.hi * 0.62))
                end
                if Bot.PrioritizeUltimate and score > 0 then
                    if key == "ult" then priority = 2
                    elseif score >= 9 or (f.heal and hp < 0.35) then priority = 3 end
                end
                local punish = priority == 1 and offensive and info.needsTarget and impact + 1 / 60 < recoveryWindow and impact or nil
                if priority > bestPriority or (priority == bestPriority and
                    ((punish and (not bestPunish or punish < bestPunish))
                        or (punish == bestPunish and score > bestScore))) then
                    bestPriority, bestScore, bestKey, bestPunish = priority, score, key, punish
                end
            end
        end
    end
    local foeKey = foe.move and foe.move.keys and foe.move.keys[foe.key or 1]
    local whiffOpening = targetHittable and foe.state == "move" and eta == math.huge
        and moveRemaining(foe) > lead + 0.15 and distance <= 6 and not foeCounter
        and not (foeKey and (foeKey.armor or foeKey.invuln))
    local chainPressure = me.state == "move" and me.move and me.move.basic == "light" and me.moveHit and foe.state == "stun"
    if rangedOpportunity then spacingReason = "ranged opening"
    elseif hasRangedKit then
        spacingReason = "melee reengage"
    end
    if whiffOpening or chainPressure or (foe.state == "stun" and (foe.stunT or 0) > lead + 0.2) then
        desired = 1.8; spacingReason = "confirmed pressure"
    end
    if ultimateGoal and Bot.Movement ~= "manual" then desired = ultimateGoal; spacingReason = "ultimate approach" end
    if guardCounters and not bestKey and not ultimateGoal then
        desired = math.max(desired, 2.6); spacingReason = "guarded counter"
    end
    local counterGap
    if foeCounter then
        counterGap = math.max(3.4, math.min(6, (tonumber(foe.move.range and foe.move.range[2]) or 4) + 0.6))
        desired = counterGap; spacingReason = "counter wait"
    end
    Bot.Snapshot.ultimateApproach = ultimateGoal
    Bot.Snapshot.whiffOpening = whiffOpening and true or false
    Bot.Snapshot.foeTeleportReady = foeTeleportETA < math.huge
    Bot.Snapshot.foeArmoredApproachReady = #foeApproaches > 0
    local closeDash, dashFollow = false, false
    local holdArenaRange = arenaUlt and not danger and not foeCounter and distance > 3
        and (bestKey == "ult" or (not bestKey and Bot.Snapshot.ultimate.reason == "awaiting ultimate result"))
        and (me.state == "neutral" or me.state == "block")
    if holdArenaRange then
        local ok, reach = pcall(sim._ultReach, sim, me, slots.ult, foe)
        holdArenaRange = ok and reach == "in"
    end
    local groundChoice = bestKey and groundOptions[bestKey]
    if groundChoice then
        local info = moveInfo(sim, me, slots[bestKey], bestKey)
        desired = math.max(1.6, math.min(3, info.hi * 0.6))
        Bot.Snapshot.groundFollowupKey = bestKey
    end
    if Bot.Movement == "manual" then
        for _, key in ipairs({"x", "down", "jump", "dash", "block", "light"}) do out[key] = manual and manual[key] or out[key] end
    else
        if not targetHittable and not groundChoice then desired = Bot.ProtectedSpacing; spacingReason = "protected target" end
        local halfW = tonumber(sim.halfW)
        local nearWall = halfW and math.abs(me.x) >= halfW - 2.5
        local centerDir = me.x >= 0 and -1 or 1
        local leaveCorner = nearWall and targetHittable and not danger and not foeCounter and not defensePending
            and (me.state == "neutral" or me.state == "block")
        if leaveCorner and not (arenaUlt and ultimateGoal) then desired = math.min(desired, 1.8); spacingReason = "leave corner" end
        local projectedGap = (dx + ((foe.vx or 0) - (me.vx or 0)) * lead) * dir
        Bot.Snapshot.spacingProjectedGap = projectedGap
        Bot.Snapshot.spacingDesired = desired
        Bot.Snapshot.spacingReason = spacingReason
        Bot.Snapshot.counterGap = counterGap
        if danger and not targetedStrike then out.x = -dir
        elseif distance > desired + 0.35 and projectedGap > desired + 0.15 then out.x = dir
        elseif distance < desired - 0.45 and projectedGap < desired - 0.15 then out.x = -dir end
        if leaveCorner and distance > 2.8 and not attackPending then out.x = centerDir end
        if dashOpener and not danger then out.x = dir end
        if holdArenaRange then
            out.x = 0
            Bot.Snapshot.spacingDesired = distance
            Bot.Snapshot.spacingReason = "hold ultimate range"
        end
        if not holdArenaRange and me.state == "neutral" and me.grounded and foe.y - me.y > 3 and now >= nextJump then
            out.jump = true; nextJump = now + 0.65
        end
        if me.state == "wall" and now >= nextJump then
            out.jump = true; out.x = -(me.wallSide or dir); nextJump = now + 0.5
        end
        local basicId = me.grounded and controls.ground.light or controls.air.light
        if me.grounded and type(sim._basicFor) == "function" then basicId = sim:_basicFor(me, "light", controls.ground) or basicId end
        local lightMove = me.state == "move" and me.move and me.move.basic == "light"
        -- A confirmed hit exposes the upcoming window before it opens. Queue J
        -- early enough to arrive through Netplay's input delay at that window.
        local earlyChain = lightMove and me.grounded and (me.chainN or 0) >= 1 and (me.chainN or 0) < 4
            and me.moveHit and me.chainCanSeq == me.moveSeq and type(me.chainCanT) == "number"
            and me.chainCanT > combatClock and me.chainCanT <= combatClock + lead
            and not me.thenMove and not me.grabWait
        local comboWindow = me.state == "move" and checkMethod(sim, "_chainCancelOk", me)
        if me.grounded and (comboWindow or earlyChain) and type(me.chainN) == "number" then
            local nextId = "L" .. tostring(me.chainN + 1)
            if sim:_moveDef(me, nextId) then basicId = nextId end
        end
        local basicDef = basicId and sim:_moveDef(me, basicId)
        local basicReach = basicDef and basicDef.range and basicDef.range[2] or 2.6
        local basicInfo = basicDef and moveInfo(sim, me, basicId, "light")
        local startup = basicInfo and basicInfo.startup or 0.06
        local tempo = basicDef and basicDef.fixedTime and 1 or tonumber(me.def and me.def.tempo) or 1
        local basicHorizon = lead + startup * tempo
        local shotWithoutStun = basicInfo and basicInfo.shotNoStun
        local futureDx = dx + (foe.vx or 0) * basicHorizon - (me.vx or 0) * lead
        local safeReach = math.max(0.5, math.min(basicReach - 0.1,
            basicInfo and basicInfo.shot and basicInfo.hi - 0.1 or Bot.MaxBasicRange))
        local chainOpportunity = comboWindow or earlyChain
        local recoveryLeft = moveRemaining(me)
        local confirmedRecovery = me.state == "move" and me.grounded and not lightMove
            and (me.moveHit or (me.moveBase == "DashPunch" and me.dashHit))
            and not (me.move and me.move.ultimate) and not me.thenMove and not me.grabWait
        local recoveryBuffer = confirmedRecovery and recoveryLeft <= lead + 0.16
            and foe.state == "stun" and (foe.stunT or 0) > math.max(lead, recoveryLeft) + startup * tempo + 1 / 60
        local freeToPunch = me.state == "neutral" or me.state == "block" or chainOpportunity or recoveryBuffer
        local stunFits = foe.state ~= "stun" or chainOpportunity
            or (foe.stunT or 0) > math.max(lead, recoveryBuffer and recoveryLeft or 0) + startup * tempo + 1 / 60
        local freshChain = chainOpportunity and me.moveSeq ~= nil and me.moveSeq ~= lastLightSeq
        local neutralPress = not chainOpportunity and now >= nextLight
        local counterThreat = not (basicInfo and basicInfo.shot)
            and guardCounterCovers(guardCounters, math.abs(futureDx), basicInfo and basicInfo.firstDirectHit)
        Bot.Snapshot.guardCounterReady = counterThreat or nil
        if not danger and not attackPending and not dashWaiting and not defensePending and targetHittable and distance < basicReach and math.abs(futureDx) < safeReach
            and math.abs(me.y - foe.y) < 3
            and guardReady(sim, me, foe, "punch", lead)
            and not foeCounter and not counterThreat and freeToPunch and stunFits
            and (freshChain or neutralPress) then
            out.light = true; nextLight = now + math.max(0.09, lead + 0.03)
            lastLightSeq = me.moveSeq
            if not (shotWithoutStun and bestKey) and bestPriority <= 1 and bestKey ~= "ult" and bestScore < 9
                and basicHorizon + 1 / 60 < recoveryWindow
                and (not bestPunish or basicHorizon < bestPunish) then
                bestKey = nil
                Bot.Snapshot.punishKey = "J"
            end
            dashFollow = dashOpener and dashOpener.confirmed and not dashOpener.followAt
                and foe.state == "stun" and type(foe.stunT) == "number" and foe.stunT > basicHorizon + 1 / 60
        end
        Bot.Snapshot.basicPredictedDistance = math.abs(futureDx)
        Bot.Snapshot.basicSafeReach = safeReach
        Bot.Snapshot.earlyChain = earlyChain and true or false
        Bot.Snapshot.recoveryBuffer = recoveryBuffer and true or false
        Bot.Snapshot.recoveryLeft = recoveryLeft
        local bestInfo = bestKey and moveInfo(sim, me, slots[bestKey], bestKey)
        local meleeChoice = not bestKey or (bestInfo and not bestInfo.ranged and bestInfo.cat == "punch" and bestScore < 5)
        if Bot.CloseDashOpener and not holdArenaRange and not attackPending and not dashOpener
            and not danger and not foeCounter and not defensePending
            and targetHittable and me.state == "neutral" and me.grounded and foe.grounded
            and foe.state == "neutral" and (foe.dashT or 0) <= 0
            and (me.dashT or 0) <= 0 and me.facing == dir
            and offensiveDashReady and now >= nextDodge and combatClock >= nextCloseDash
            and combatClock >= (me.dashAt or -10) + 0.2
            and meleeChoice and closeDashReach(me, foe, dir, lead, sim)
            and guardReady(sim, me, foe, "punch", lead) then
            out.dash = true; out.x = dir; closeDash = true
        end
        -- Chase only when no attack is ready to land; preserve an escape charge.
        if targetHittable and not danger and not foeCounter and not holdArenaRange and me.state == "neutral"
            and distance > math.max(6, desired + 3) and distance <= Bot.MaxApproachDashDistance and now >= nextDodge
            and offensiveDashReady and not attackPending
            and (me.grounded or (me.airDashes or 0) < 1) and bestKey == nil and not out.light
            and not defensePending and not dashOpener then
            out.dash = true; out.x = dir; nextDodge = now + 0.5
        end
    end
    local ultimateMayPost = bestKey == "ult" and not pendingDash and not attackPending
    if bestKey and not defensePending and (not dashWaiting and not dashFollow or bestScore >= 9 or ultimateMayPost)
        and (now >= nextSkill or bestScore >= 9 or ultimateMayPost) then
        out[bestKey] = true
        out.light = nil
        -- Defensive skills must not be cancelled by movement on the same frame.
        out.jump = nil
    end
    local postedDefense = bestKey and bestKey ~= "ult" and out[bestKey] and bestScore >= 9
    if postedDefense then defenseUntil = combatClock + lead + 0.06; defenseKind = "skill" end
    local usingDefense = postedDefense or defensePending
    if usingDefense then out.jump = nil; out.light = nil end
    local canCancel = me.state ~= "move" or checkMethod(sim, "_cancelOk", me)
    local protectedSelf = me.invuln or (me.cbInvT or 0) > combatClock or (me.evInvT or 0) > combatClock
        or ((me.dashT or 0) > 0 and (me.dashInvT or 0) > combatClock)
    local closingSpeed = ((me.vx or 0) - (foe.vx or 0)) * dir
    -- A full-control opponent can Q into contact faster than a delayed F can
    -- arrive. Guard an observed fast approach before a contact animation exists.
    -- This is a pressure prediction, not a claim to know their next input.
    local approachPressure = foe.human == true and targetHittable and foe.state == "neutral" and foe.grounded
        and foe.facing == -dir and -(foe.vx or 0) * dir > 5 and closingSpeed > 5 and distance <= 6
        and distance - closingSpeed * (lead + 0.1) < 3
    local fallbackGuardSafe = blockAllowed and (me.guard == nil or guardSafe) and me.guardLockT == nil
    local predictBlock = Bot.PredictBlock and guardSafe and me.grounded
        and (me.state == "neutral" or (me.state == "block" and me.facing == blockDir))
        and not unblockable and ((eta >= 0 and eta < lead + 0.24 + (memory.defenseMargin or 0)) or approachPressure)
        and not usingDefense and not protectedSelf
    local holdRecovery = recoveryGuard and (me.state == "neutral" or (me.state == "block" and me.facing == blockDir))
        and not usingDefense and not protectedSelf
    local turnGuard = Bot.PredictBlock and guardSafe and me.grounded and me.state == "block"
        and me.facing ~= blockDir and not unblockable and eta < lead + 0.45 and not usingDefense and not protectedSelf
    if turnGuard then
        out.block = false; out.x = blockDir; out.dash = nil; out.jump = nil
        for _, key in ipairs({"x1", "x2", "x3", "ult", "form", "light"}) do out[key] = nil end
    end
    if predictBlock or holdRecovery then
        out.block = true; out.x = blockDir; out.dash = nil; out.jump = nil; out.light = nil
        usingDefense = true
    end
    Bot.Snapshot.predictBlock = predictBlock and true or false
    Bot.Snapshot.approachPressure = approachPressure and true or false
    Bot.Snapshot.recoveryGuard = holdRecovery and true or false
    Bot.Snapshot.turnGuard = turnGuard and true or false
    local dashCoversStrike = not targetedStrike or (not targetedUltimate and eta >= lead and eta - lead < 0.14
        and (me.mvt == "blink" or (me.cls and me.cls.dashInv) or (me.def and me.def.dashInv)))
    if imminent and not usingDefense and canCancel and not protectedSelf then
        if now >= nextDodge and dashReady
            and dashCoversStrike
            and (me.grounded or (me.airDashes or 0) < (me.mvt == "swing" and 2 or 1)) then
            out.dash = true
            out.x = (threatSource == "zone" or threatSource == "delayed effect" or threatSource == "teleport attack") and -blockDir or -dir
            nextDodge = now + 0.55
        elseif not targetedStrike and now >= nextJump and (me.grounded or (me.airJumps or 0) < 1) then
            out.jump = true; nextJump = now + 0.3
            if me.grounded then pendingJump = now + 0.24 end
        elseif not unblockable and me.grounded and fallbackGuardSafe
            and (me.state ~= "block" or me.facing == blockDir) then out.block = true; out.x = blockDir end
    end
    if pendingJump and now >= pendingJump and not usingDefense and canCancel and not protectedSelf then
        if not targetedStrike and not me.grounded and danger then out.jump = true end
        pendingJump = nil
    end
    -- Keep a retreat/dash from driving straight into the arena wall.
    local halfW = tonumber(sim.halfW)
    if halfW and not out.block and math.abs(me.x) > halfW - 2 and out.x * me.x > 0 then
        out.x = 0
        out.dash = nil
        if imminent and not targetedStrike and not usingDefense and now >= nextJump
            and (me.grounded or (me.airJumps or 0) < 1) then
            out.jump = true; nextJump = now + 0.3
        end
    end
    -- Only one action family per frame; jumps/dashes can cancel a move in Sim.
    if out.dash or out.jump or out.block then
        for _, key in ipairs({"x1", "x2", "x3", "ult", "form", "light"}) do out[key] = nil end
        if out.dash then out.jump = nil; pendingJump = nil end
        -- The live trace exposed dash -> jump -> block queued before the dash
        -- arrived. Commit physical evasions through their input-delay interval.
        if out.dash or out.jump then
            defenseUntil = math.max(defenseUntil, combatClock + lead + 0.12)
            defenseKind = out.dash and out.x == dir and not imminent and "approach" or "physical"
        end
    elseif bestKey and out[bestKey] then
        -- Full-control skills can use facing for aim; don't cast while facing away.
        if (bestScore < 9 or bestKey == "ult") and Bot.Movement ~= "manual" then
            out.x = bestKey == "ult" and arenaUlt and 0 or dir
        end
        if bestKey == "ult" then nextUltimate = combatClock + math.max(0.35, lead + 0.2) end
        nextSkill = now + Bot.SkillGap
    end
    if out.light and Bot.Movement ~= "manual" then out.x = dir end
    if Bot.Movement ~= "manual" then
        local press = out.light and "light" or (bestKey and out[bestKey] and bestKey)
        if press then pendingAttack = {me = me, seq = me.moveSeq, at = combatClock,
            untilT = combatClock + math.max(lead, out.light and moveRemaining(me) or 0) + 0.12, key = press} end
    end
    if out.dash and Bot.Movement ~= "manual" then
        pendingDash = {me = me, at = combatClock, untilT = combatClock + lead + 0.3,
            previousAt = me.dashAt or -100, before = tonumber(me.dashN) or 0}
        if closeDash or out.x == dir then
            nextOffensiveDash = combatClock + math.max(Bot.OffensiveDashGap, dashRechargeLength(sim, me))
        end
    end
    if closeDash and out.dash and out.x == dir then
        dashOpener = {me = me, foe = foe, hp = foe.hp, at = combatClock, previousDashAt = me.dashAt or -100}
        nextCloseDash = combatClock + 1.3; nextDodge = now + 0.5
        logger:line("dash_opener", {simTime = combatClock, distance = distance})
    elseif dashFollow and out.light and dashOpener then
        dashOpener.followAt, dashOpener.followSeq = combatClock, me.moveSeq
    elseif dashOpener and (postedDefense or out.dash or out.jump or out.block) then dashOpener = nil end
    Bot.Snapshot.action = out.dash and (closeDash and "dash opener" or (out.x == dir and "approach dash" or "evade dash"))
        or (out.light and "J") or (bestKey and out[bestKey] and bestKey)
        or (holdRecovery and "recovery guard") or (predictBlock and "predictive block") or (out.block and "block") or (turnGuard and "turn guard") or "position"
    if Bot.Snapshot.ultimate.eligible then Bot.Snapshot.ultimate.posted = out.ult == true end
    if Bot.Snapshot.punishKey == "J" and not out.light then Bot.Snapshot.punishKey = nil end
    if bestPunish and bestKey and out[bestKey] then Bot.Snapshot.punishKey = bestKey end
    status("Fighting / " .. Bot.Movement .. (out[bestKey or ""] and (" / " .. bestKey) or ""))
    return out
end
sampleWrapper = function(...)
    local manual = originalSample(...)
    local out = manual
    Bot.Snapshot = nil
    lastGoodSample = os.clock()
    Bot.InputCalls = Bot.InputCalls + 1
    Bot.InputMode = not Bot.Enabled and "paused" or (UIS:GetFocusedTextBox() and "typing"
        or (os.clock() - lastManual < Bot.ManualGrace and "manual" or "autoplay"))
    if alive and Bot.Enabled and not UIS:GetFocusedTextBox() and os.clock() - lastManual >= Bot.ManualGrace then
        local ok, result = pcall(decide, manual)
        if not ok then
            Bot.InputMode = "error"
            if Bot.LastError ~= tostring(result) then warn("[QuickMatchAuto] " .. tostring(result)) end
            Bot.LastError = tostring(result)
            status("Error; check QuickMatchAuto.LastError")
        else out = result or manual end
    elseif alive and Bot.Enabled then
        status(Bot.InputMode == "typing" and "Typing / normal input" or "Manual combat input / temporary override")
    end
    if alive then
        local ok, err = pcall(logger.sample, logger, out)
        if not ok then logger:fail(err) end
    end
    return out
end
Input.sample = sampleWrapper

local function awakened(id)
    if not Profile or type(Profile.card) ~= "function" then return false end
    local ok, card = pcall(Profile.card, id)
    return ok and card and card.u and card.u.form == true
end
local function eventMatchId(info)
    if type(info) ~= "table" then return nil end
    return info.matchId or (type(info.match) == "table" and info.match.matchId or nil)
end
local function staleEvent(info)
    local id = eventMatchId(info)
    return id ~= nil and (retiredMatches[id] == true or (matchId ~= nil and id ~= matchId))
end
local function controllerForSkip()
    if matchController and matchController.active == true then return matchController end
    if type(getgc) ~= "function" or os.clock() - lastControllerScan < 3 then return matchController end
    lastControllerScan = os.clock()
    local ok, values = pcall(getgc, true)
    if ok then
        for _, value in pairs(values) do
            if type(value) == "table" and type(rawget(value, "onPauseLeave")) == "function"
                and type(rawget(value, "ownsRenderer")) == "function" and type(rawget(value, "isPvp")) == "function"
                and type(rawget(value, "resume")) == "function" and type(rawget(value, "active")) == "boolean" then
                if not matchController or value.active then matchController = value end
                if value.active then break end
            end
        end
    end
    return matchController
end
local function selfLobbyStatus()
    local ok, rows = pcall(Online.lobby)
    if ok and type(rows) == "table" then
        for _, row in pairs(rows) do
            if type(row) == "table" and tonumber(row.id) == player.UserId then return row.status end
        end
    end
end
local function leaveExcluded()
    if not skipState or skipState.id ~= matchId or not blockedMatch then return end
    local state = skipState
    local controller = controllerForSkip()
    local usedClient = false
    if controller and controller.active then
        local ok, pvp = pcall(controller.isPvp, controller)
        if ok and pvp then
            local left, err = pcall(controller.onPauseLeave, controller)
            if skipState ~= state or matchId ~= state.id then return end
            if left then usedClient = true; state.controller = controller
            else Bot.LastError = tostring(err) end
        end
    end
    if not usedClient then pcall(Online.leave, matchId) end
    skipState.tries = skipState.tries + 1
    skipState.retryAt = os.clock() + 4
end
local function finishSkip(reason, current)
    local id = matchId
    retireMatch(id, current, true)
    if current then ignoredSessions[current] = true end
    if session then ignoredSessions[session] = true end
    logger:line("skip_recovered", {matchId = id, reason = reason})
    logger:flush(true)
    busy, queued, ending, drafting = false, false, false, false
    queueRequested = false
    blockedMatch, opponentId, mySide, rematchAnswered = false, nil, nil, false
    rematchWaitUntil = 0; rematchAutoAccepted = false
    matchId, matchNumber, lastDeal, session, skipState = nil, nil, nil, nil, nil
    dealGeneration = dealGeneration + 1; lastQueue = os.clock(); resetCombat()
    Bot.ControlState = "lobby"
    status("Skipped opponent; returning to Quick Match")
end
local function skipTick(current)
    if not blockedMatch or not skipState then
        -- Re-injection in the hub must not attach an orphaned old renderer and
        -- wait forever for its phase to become done.
        local controller = matchController
        if not matchId and current and controller and controller.active == false and not controller.trainingActive
            and selfLobbyStatus() == "free" then
            ignoredSessions[current] = true; session = nil; busy = false
            status(Bot.AutoJoin and "Lobby confirmed; joining Quick Match" or "Lobby confirmed; auto join off")
            return nil
        end
        return current
    end
    if os.clock() - skipState.since < 1.5 then return current end
    local controller = skipState.controller
    local clientReturned = controller and controller.active == false and not controller.trainingActive
    local freshServerReturn = lobbyUpdatedAt >= skipState.since and selfLobbyStatus() == "free"
        and (not current or current.dead or current.r.sim.phase == "done")
    if clientReturned or freshServerReturn then
        finishSkip(clientReturned and "client returned to lobby" or "server lobby free", current)
        return nil
    end
    if os.clock() >= skipState.retryAt and skipState.tries < 3 then leaveExcluded() end
    status(skipState.tries >= 3 and "Waiting for skipped match to return to lobby" or "Leaving skipped opponent; checking lobby")
    return current
end
local lobbyWatch = {nextPoll = 0, progressAt = os.clock()}
local function lobbyRecoveryTick(current, uiBlocked)
    local now = os.clock()
    local sim = current and current.r.sim
    if current ~= lobbyWatch.current or (sim and (sim.frame ~= lobbyWatch.frame or sim.t ~= lobbyWatch.simTime)) then
        lobbyWatch.current, lobbyWatch.frame, lobbyWatch.simTime = current, sim and sim.frame, sim and sim.t
        lobbyWatch.progressAt = now
    end
    if now < lobbyWatch.nextPoll then return current end
    lobbyWatch.nextPoll = now + 2
    local serverState = selfLobbyStatus()
    local controller = controllerForSkip()
    local freshLobby = lobbyUpdatedAt >= matchEventAt and now - lobbyUpdatedAt <= 10
    local recentInput = now - lastGoodSample < 4
    local progressing = sim and now - lobbyWatch.progressAt < 4
    Bot.SessionState = {matchId = matchId, busy = busy, queued = queued, phase = sim and sim.phase,
        server = serverState, lobbyFresh = freshLobby, controllerActive = controller and controller.active,
        inputAge = now - lastGoodSample, progressAge = now - lobbyWatch.progressAt, matchEventAge = now - matchEventAt}
    if blockedMatch or uiBlocked or (controller and controller.trainingActive) or (current and current.r.paused)
        or (sim and sim.phase == "fight" and progressing and recentInput) then return current end
    if not busy and not current then return current end
    local delay = math.max(5, tonumber(Bot.LobbyRecoveryDelay) or 15)
    if serverState == "free" and freshLobby and now - matchEventAt >= delay
        and ((controller and controller.active == false) or (not progressing and not recentInput)) then
        local oldId = matchId
        logger:line("lobby_recovered", {matchId = oldId, phase = sim and sim.phase, server = serverState,
            reason = "fresh server-free lobby and inactive renderer/input"})
        logger:finish("confirmed lobby recovery")
        retireMatch(oldId, current, true)
        busy, queued, queueRequested, ending, drafting = false, false, false, false, false
        matchId, matchNumber, lastDeal, session = nil, nil, nil, nil
        opponentId, opponentCPU, mySide, outcomeRecorded = nil, nil, nil, false
        rematchAnswered, rematchWaitUntil, rematchAutoAccepted = false, 0, false
        dealGeneration = dealGeneration + 1; lastQueue = now; matchEventAt = now; resetCombat()
        Bot.RecoveryCount = Bot.RecoveryCount + 1; Bot.RecoveryStatus = "recovered confirmed lobby"
        status(Bot.AutoJoin and "Lobby recovered; waiting for Quick Match" or "Lobby recovered; auto join off")
        return nil
    end
    if busy and not current and now - matchEventAt >= delay then
        Bot.RecoveryStatus = "waiting for fresh lobby confirmation"
        status("Waiting for renderer / checking lobby")
    end
    return current
end
local function observeOpponent(info)
    if type(info) ~= "table" then return end
    if type(info.side) == "number" then mySide = info.side end
    local opp = info.opp
    if type(opp) == "table" and type(opp.cpu) == "boolean" then
        opponentCPU = opp.cpu
        if logger.active and logger.stats then logger.stats.opponentCPU = opponentCPU end
    end
    if type(opp) == "table" and opp.cpu ~= true and tonumber(opp.id) and tonumber(opp.id) > 0 then opponentId = tonumber(opp.id) end
    if Bot.Enabled and not ranked.arena and Bot.AvoidLostOpponents and opponentId and memory.lost[tostring(opponentId)] then
        if not blockedMatch then
            blockedMatch = true; dealGeneration = dealGeneration + 1
            skipState = {id = matchId, since = os.clock(), tries = 0, retryAt = 0}
            leaveExcluded()
            if logger.active and logger.id == matchId then
                logger.stats.outcome = "skipped"
                logger:line("excluded_opponent", {opponentId = opponentId})
                logger:finish("excluded opponent")
            end
        end
        status("Skipping opponent previously lost to / " .. tostring(opponentId))
    end
end
local function recordOutcome(info)
    if outcomeRecorded or blockedMatch or type(info) ~= "table" then return end
    if logger.stats then logger.stats.terminal = flat(info, {"winner", "result", "outcome", "reason", "forfeit", "kind", "code", "detail"}) end
    local rounds = logger.stats and logger.stats.rounds
    local lastRound = rounds and rounds[#rounds]
    local forfeit = info.forfeit == true or info.result == "forfeit" or info.reason == "forfeit"
        or (lastRound and lastRound.result == "forfeit") or false
    if logger.stats then logger.stats.forfeit = forfeit end
    local loss, win = false, false
    if mySide and type(info.winner) == "number" then
        if info.winner == 0 then
            outcomeRecorded = true
            if logger.stats then logger.stats.outcome = "draw" end
            logger:line("outcome", {outcome = "draw", opponentId = opponentId})
            return
        end
        win = info.winner == mySide; loss = not win
    else
        local result = info.outcome or info.result
        loss = result == "lose" or result == "loss" or result == "defeat"
        win = result == "win" or result == "victory"
    end
    if not loss and not win then return end
    outcomeRecorded = true
    if logger.stats then logger.stats.outcome = loss and "loss" or "win" end
    logger:line("outcome", {outcome = loss and "loss" or "win", opponentId = opponentId})
    if loss then
        memory.losses = (memory.losses or 0) + 1
        if not forfeit then memory.defenseMargin = math.min(0.12, (memory.defenseMargin or 0) + 0.02) end
        if opponentId then memory.lost[tostring(opponentId)] = true end
    else
        memory.wins = (memory.wins or 0) + 1
        if not forfeit and logger.stats and logger.stats.opponentControlSamples and (logger.stats.opponentControlSamples.full or 0) > 0 then
            memory.defenseMargin = math.max(0, (memory.defenseMargin or 0) - 0.005)
        end
    end
end
local function deal(info)
    if not alive or type(info) ~= "table" or type(info.hand) ~= "table" then return end
    if staleEvent(info) then return end
    observeOpponent(info)
    if blockedMatch or staleEvent(info) then return end
    lastDeal, drafting = info, true
    matchEventAt = os.clock()
    Bot.RecoveryStatus = "watching"
    rematchWaitUntil = 0; rematchAutoAccepted = false
    logger:line("draft", {round = info.round, handSize = #info.hand})
    ending = false
    busy, queued = true, false
    if not Bot.Enabled then return end
    dealGeneration = dealGeneration + 1
    local generation = dealGeneration
    local hand = {}
    for _, id in ipairs(info.hand) do if type(id) == "string" then hand[#hand + 1] = id end end
    table.sort(hand, function(a, b)
        local ar, br = Rarity.tierOf(a), Rarity.tierOf(b)
        if ar ~= br then return ar > br end
        local priorities = Bot.DraftPriorities and Bot.DraftPriorities[ar] or {}
        local ap, bp = tonumber(priorities[a]) or 0, tonumber(priorities[b]) or 0
        if ap ~= bp then return ap > bp end
        local aa, ba = awakened(a), awakened(b)
        if aa ~= ba then return aa end
        return a < b
    end)
    if #hand == 0 then return end
    local pick = info.picks == 2 and #hand >= 2 and {hand[1], hand[2]} or hand[1]
    status("Picking " .. hand[1])
    local delay = math.max(0.4, tonumber(info.grace) or 3.6) + 0.2
    if type(info.deadline) == "number" then
        delay = math.max(0.05, math.min(delay, info.deadline - workspace:GetServerTimeNow() - 0.4))
    end
    task.delay(delay, function()
        if alive and Bot.Enabled and generation == dealGeneration then
            Online.ready(pick)
            logger:line("pick", {pick = pick})
            status("Character locked: " .. hand[1])
        end
    end)
end
if type(memory.onlineDispatch) ~= "table" then memory.onlineDispatch = setmetatable({}, {__mode = "k"}) end
local onlineSlots = memory.onlineDispatch[Online]
if type(onlineSlots) ~= "table" then onlineSlots = {}; memory.onlineDispatch[Online] = onlineSlots end
local ownedOnlineSlots = {}
local function on(event, callback)
    local slot = onlineSlots[event]
    if not slot then
        slot = {}; onlineSlots[event] = slot
        Online.on(event, function(...) if slot.callback then slot.callback(...) end end)
    end
    local wrapper = function(...) if alive then callback(...) end end
    slot.callback = wrapper; ownedOnlineSlots[event] = wrapper
end
on("queue", function(value) queued = value == true; if not queued then queueRequested = false end end)
if Ranked and type(Ranked.on) == "function" then
    memory.rankedDispatch = memory.rankedDispatch or setmetatable({}, {__mode = "k"})
    local slots = memory.rankedDispatch[Ranked] or {}
    memory.rankedDispatch[Ranked] = slots
    ranked.handlers = slots
    local function onRanked(event, callback)
        if not slots[event] then
            local slot = {}
            slots[event] = slot
            Ranked.on(event, function(info) if slot.callback then slot.callback(info) end end)
        end
        slots[event].callback = function(info) if alive then callback(info) end end
    end
    onRanked("q", function(info)
        if type(info) ~= "table" then return end
        if info.state == "off" then
            ranked.state = "off"
            ranked.retryAt = os.clock() + math.max(8, tonumber(info.seconds) or 0)
            if Bot.MatchMode == "ranked" and not ranked.arena then
                status("Ranked queue idle" .. (type(info.reason) == "string" and " / " .. info.reason or ""))
            end
        elseif ranked.state ~= "cancelling" and (info.state == "searching" or info.state == "found"
            or info.state == "retrying" or info.state == "teleporting") then
            ranked.state = info.state
            if info.state == "teleporting" then Bot.SaveSettings() end
            if Bot.MatchMode == "ranked" then status("Ranked / " .. info.state) end
        end
    end)
    onRanked("arena", function(info)
        if type(info) ~= "table" then return end
        if info.phase == "waiting" or info.phase == "live" then
            ranked.arena, ranked.state, ranked.finishedAt, ranked.returnAt = true, "off", nil, 0
            if info.phase == "waiting" then status("Ranked arena / waiting for opponent") end
        elseif info.phase == "over" then
            ranked.arena, ranked.finishedAt = true, ranked.finishedAt or os.clock()
        end
    end)
    onRanked("cancelled", function()
        ranked.state = "off"
        if ranked.arena then ranked.finishedAt = ranked.finishedAt or os.clock() end
    end)
    onRanked("return", function(info)
        if type(info) == "table" and info.mode == "local" then
            if not ranked.arena or (info.matchId and matchId and info.matchId ~= matchId) then return end
            logger:finish("ranked local return")
            retireMatch(matchId, session, true)
            busy, queued, queueRequested, ending, drafting = false, false, false, false, false
            matchId, matchNumber, lastDeal, session = nil, nil, nil, nil
            dealGeneration = dealGeneration + 1
            resetCombat()
            ranked.arena, ranked.finishedAt, ranked.state = false, nil, "off"
            ranked.retryAt = os.clock() + 8
        end
    end)
end
on("lobby", function() lobbyUpdatedAt = os.clock() end)
on("away", function(count, limit)
    Bot.AwayWarnings = tonumber(count) or 1; Bot.AwayLimit = tonumber(limit) or 3
    logger:line("away_warning", {count = Bot.AwayWarnings, limit = Bot.AwayLimit})
    if logger.active and logger.stats then logger.stats.awayWarnings = Bot.AwayWarnings; logger.stats.awayLimit = Bot.AwayLimit end
end)
on("match", function(info)
    if retiredMatches[eventMatchId(info)] then return end
    if type(info) == "table" and info.ranked == true then
        ranked.arena, ranked.finishedAt, ranked.state, ranked.returnAt = true, nil, "off", 0
    end
    if eventMatchId(info) ~= nil and eventMatchId(info) == matchId and busy then
        observeOpponent(info); return
    end
    if logger.active then logger:finish("next match announcement") end
    if matchId ~= eventMatchId(info) then retireMatch(matchId, session, false); session = nil end
    matchEventAt = os.clock()
    Bot.RecoveryStatus = "watching"
    Bot.AwayWarnings = 0
    busy = true; queued = false; ending = false
    queueRequested = false
    skipState = nil
    opponentId, blockedMatch, outcomeRecorded, mySide = nil, false, false, nil
    opponentCPU = nil
    rematchAnswered, rematchWaitUntil, rematchAutoAccepted = false, 0, false
    matchId = eventMatchId(info)
    matchNumber = type(info) == "table" and type(info.id) == "number" and info.id or nil
    observeOpponent(info)
    if not busy or matchId ~= eventMatchId(info) then return end
    logger:start(matchId)
    if blockedMatch then
        if logger.stats then logger.stats.outcome = "skipped" end
        logger:line("excluded_opponent", {opponentId = opponentId})
        logger:finish("excluded opponent")
    end
    dealGeneration = dealGeneration + 1
    if type(info) == "table" and info.hand then deal(info) end
end)
on("deal", deal)
on("start", function(info)
    if staleEvent(info) then return end
    observeOpponent(info)
    if staleEvent(info) then return end
    busy = true; queued = false; drafting = false; dealGeneration = dealGeneration + 1
    matchEventAt = os.clock()
    rematchWaitUntil = 0; rematchAutoAccepted = false
    resetCombat(); status(blockedMatch and "Skipping previous loss" or "Round starting")
    logger.roundNumber = type(info) == "table" and info.round or nil
    logger.roundBaseTaken = logger.stats and logger.stats.damageTaken or 0
    logger.roundBaseDealt = logger.stats and logger.stats.damageDealt or 0
    logger.roundBaseSelfCost = logger.stats and logger.stats.selfHpCost or 0
    logger.roundBaseOpponentCost = logger.stats and logger.stats.opponentSelfHpCost or 0
    logger:line("round_start", flat(info, {"round", "side", "seat", "matchId"}))
end)
on("end", function(info)
    if staleEvent(info) or type(info) ~= "table" or not logger.active or not logger.stats then return end
    if logger.roundNumber and info.round and info.round ~= logger.roundNumber then return end
    local key = tostring(info.round or logger.roundNumber or "unknown") .. ":" .. tostring(info.attempt or 0)
    if logger.roundSeen[key] then return end
    logger.roundSeen[key] = true
    local current = session
    local sim = current and not current.dead and current.r.sim
    local me = sim and sim.fighters[current.side] or logger.lastMe
    local foe = me and sim and sim:other(me) or logger.lastFoe
    local side = mySide or (current and current.side)
    local outcome = type(info.winner) == "number" and side
        and (info.winner == 0 and "draw" or (info.winner == side and "win" or "loss")) or "unknown"
    local row = {round = info.round or logger.roundNumber, attempt = info.attempt, winner = info.winner,
        result = info.result, outcome = outcome, opponentId = opponentId,
        opponentCPU = opponentCPU, opponentControl = foe and controlMode(foe),
        fighter = me and me.def and me.def.name, opponentFighter = foe and foe.def and foe.def.name,
        hp = me and me.hp, maxHp = me and me.maxHp, opponentHp = foe and foe.hp, opponentMaxHp = foe and foe.maxHp,
        damageTaken = math.max(0, logger.stats.damageTaken - logger.roundBaseTaken),
        damageDealt = math.max(0, logger.stats.damageDealt - logger.roundBaseDealt)}
    row.selfHpCost = math.max(0, logger.stats.selfHpCost - logger.roundBaseSelfCost)
    row.opponentSelfHpCost = math.max(0, logger.stats.opponentSelfHpCost - logger.roundBaseOpponentCost)
    row.combatDamageTaken = math.max(0, row.damageTaken - row.selfHpCost)
    row.combatDamageDealt = math.max(0, row.damageDealt - row.opponentSelfHpCost)
    logger.stats.rounds[#logger.stats.rounds + 1] = row
    if #logger.stats.rounds > 32 then table.remove(logger.stats.rounds, 1) end
    logger:line("round_result", row); logger:flush(true)
end)
on("closed", function(id)
    if retiredMatches[id] then return end
    if type(id) == "string" and matchId and id ~= matchId then return end
    if type(id) == "number" and matchNumber and id ~= matchNumber then return end
    if blockedMatch then finishSkip("closed acknowledgement", session); return end
    logger:line("closed_event", {matchId = matchId, eventId = (type(id) == "string" or type(id) == "number") and id or nil})
    logger:finish("closed")
    retireMatch(matchId or id, session, true)
    busy = false; queued = false; ending = false; drafting = false
    queueRequested = false
    matchId = nil; matchNumber = nil; lastDeal = nil; session = nil
    blockedMatch, opponentId, skipState = false, nil, nil
    rematchAnswered, rematchWaitUntil, rematchAutoAccepted = false, 0, false
    dealGeneration = dealGeneration + 1; lastQueue = os.clock()
    matchEventAt = os.clock(); resetCombat()
    Bot.RecoveryStatus = "closed session retired"
    status(Bot.AutoJoin and "Match closed; waiting for Quick Match" or "Match closed; auto join off")
end)
on("rematch", function(mine, theirs)
    if not mine and not theirs then rematchAnswered = false; rematchWaitUntil = 0; rematchAutoAccepted = false; return end
    if Bot.Enabled and Bot.AutoJoin and Bot.MatchMode == "quick" and not ranked.arena
        and not rematchAnswered and type(Online.rematch) == "function" then
        if Bot.AcceptRematches and theirs then
            rematchAutoAccepted = true
            rematchAnswered = true; rematchWaitUntil = os.clock() + 15
            Online.rematch(true); status("Rematch accepted; waiting for draft")
        elseif not Bot.AcceptRematches then
            rematchAnswered = true; Online.rematch(false)
        elseif mine then rematchAnswered = true; rematchWaitUntil = os.clock() + 15 end
    end
end)
on("matchOver", function(info)
    if staleEvent(info) then return end
    if ranked.arena then ranked.finishedAt = ranked.finishedAt or os.clock() end
    recordOutcome(info)
    logger:finish("results")
    dealGeneration = dealGeneration + 1
    drafting, lastDeal = false, nil
    ending = true
    status("Match finished")
end)
-- Use the same free, server-validated claim path as RewardsPanel.claimAll.
local rewardClaim = {nextPoll = 0, retryAt = 0, confirmed = {}}
local function rewardAck(info)
    if not alive or type(info) ~= "table" or info.claim ~= "play" then return end
    if info.failed then
        rewardClaim.pending = nil; rewardClaim.retryAt = os.clock() + 10
        Bot.RewardStatus = "retry: " .. tostring(info.reason or "server rejected")
        logger:line("reward_failed", {reason = tostring(info.reason or "unknown")})
        return
    end
    local ids = type(info.ids) == "table" and info.ids or {info.id}
    for _, id in ipairs(ids) do
        if type(id) == "string" and id ~= (Rewards and Rewards.PLAY_ALL) then rewardClaim.confirmed[id] = true end
    end
    rewardClaim.pending = nil; rewardClaim.retryAt = os.clock() + 2
    Bot.RewardStatus = "claimed"
    logger:line("reward_claimed", {ids = ids})
end
if Profile and type(Profile.onClaim) == "function" then
    local ok, conn = pcall(Profile.onClaim, rewardAck)
    if ok and conn and type(conn.Disconnect) == "function" then connections[#connections + 1] = conn end
end
local function rewardsTick()
    if not Bot.AutoClaimPlaytime then Bot.RewardStatus = "off"; return end
    local now = os.clock()
    if now < rewardClaim.nextPoll then return end
    rewardClaim.nextPoll = now + 2
    if not Profile or not Rewards or type(Profile.rewards) ~= "function"
        or type(Profile.claim) ~= "function" or type(Rewards.playStatus) ~= "function" then
        Bot.RewardStatus = "unavailable"; return
    end
    local state = Profile.rewards()
    if type(state) ~= "table" or state.syncing or type(state.play) ~= "table" then
        Bot.RewardStatus = "syncing"; return
    end
    local claimed = type(state.play.claimed) == "table" and state.play.claimed or {}
    if rewardClaim.pending then
        local synced = true
        for _, id in ipairs(rewardClaim.pending.ids) do if not claimed[id] then synced = false end end
        if synced then rewardClaim.pending = nil; Bot.RewardStatus = "claimed (synced)"
        elseif now - rewardClaim.pending.at < 15 then Bot.RewardStatus = "claim pending"; return
        else
            rewardClaim.pending = nil; rewardClaim.retryAt = now + 10
            Bot.RewardStatus = "claim timeout; retrying"; return
        end
    end
    if now < rewardClaim.retryAt then return end
    local elapsed = (tonumber(state.play.elapsed) or 0) + math.max(0, now - (tonumber(state.at) or now))
    local rows = Rewards.playStatus(elapsed, claimed)
    local ids = {}
    for _, row in ipairs(rows or {}) do
        if row.state == "ready" and not rewardClaim.confirmed[row.id] then ids[#ids + 1] = row.id end
    end
    if #ids == 0 then Bot.RewardStatus = "waiting for next reward"; return end
    rewardClaim.pending = {ids = ids, at = now} -- set before sending, including synchronous acknowledgements
    Bot.RewardStatus = "claim pending"
    local ok, err = pcall(Profile.claim, "play", Rewards.PLAY_ALL or "all")
    if not ok then
        rewardClaim.pending = nil; rewardClaim.retryAt = now + 10
        Bot.RewardStatus = "claim error"; Bot.RewardError = tostring(err)
    end
    logger:line("reward_request", {ids = ids, sent = ok})
end
-- Permanent Awakening unlocks, explicitly requested by the user. One server
-- request at a time; wait for the profile to reflect it before spending again.
local unlocker = {nextPoll = 0, retryAt = 0}
if Profile and type(Profile.onChange) == "function" then
    local ok, conn = pcall(Profile.onChange, function()
        if alive then unlocker.nextPoll = 0 end
    end)
    if ok and conn and type(conn.Disconnect) == "function" then connections[#connections + 1] = conn end
end
if Profile and type(Profile.onUnlocked) == "function" then
    local ok, conn = pcall(Profile.onUnlocked, function(info)
        local pending = unlocker.pending
        if not alive or not pending or type(info) ~= "table" or info.name ~= pending.id then return end
        if info.key and Gems and Gems.slotOf(info.key) ~= "awaken" then return end
        if info.ok then
            pending.ack = true; Bot.AwakenStatus = "unlocked " .. pending.id .. "; syncing"
            unlocker.nextPoll = 0
        else
            unlocker.pending = nil; unlocker.retryAt = os.clock() + 10
            Bot.AwakenStatus = "retry: " .. tostring(info.reason or "server rejected")
        end
        logger:line("awakening_ack", {fighter = pending.id, ok = info.ok == true, reason = info.reason, cost = pending.cost})
    end)
    if ok and conn and type(conn.Disconnect) == "function" then connections[#connections + 1] = conn end
end
local function awakenTick()
    if not Bot.AutoAwakenAll then Bot.AwakenStatus = "off"; return end
    local now = os.clock()
    if now < unlocker.nextPoll then return end
    unlocker.nextPoll = now + 2
    if not Profile or not Gems or not Fighters or type(Fighters.list) ~= "table"
        or type(Profile.view) ~= "function"
        or type(Profile.unlockMove) ~= "function" or type(Profile.gems) ~= "function"
        or type(Gems.canUnlock) ~= "function" or type(Gems.isUnlocked) ~= "function" or type(Gems.slotOf) ~= "function" then
        Bot.AwakenStatus = "unavailable"; return
    end
    local view = Profile.view()
    if type(view) ~= "table" or view.syncing then Bot.AwakenStatus = "waiting for profile"; return end
    if unlocker.pending then
        local pending = unlocker.pending
        if Gems.isUnlocked(view.abilities, pending.id, "awaken", view.passives) then
            logger:line("awakening_confirmed", {fighter = pending.id, cost = pending.cost})
            unlocker.pending = nil; Bot.AwakenStatus = "unlocked " .. pending.id
        elseif now - pending.at < 15 then Bot.AwakenStatus = "pending " .. pending.id; return
        else
            unlocker.pending = nil; unlocker.retryAt = now + 10
            Bot.AwakenStatus = "unlock timeout; retrying"; return
        end
    end
    if now < unlocker.retryAt then return end
    local gems = tonumber(Profile.gems()) or 0
    local available = math.max(0, gems - math.max(0, tonumber(Bot.AwakenGemReserve) or 0))
    local candidates, needsGems, ids, collection = {}, false, {}, {}
    for _, id in pairs(type(view.owned) == "table" and view.owned or {}) do
        if type(id) == "string" then collection[id] = true; ids[id] = true end
    end
    for id, def in pairs(Fighters.list) do
        if type(id) == "string" then ids[id] = true
        elseif type(def) == "table" and type(def.name) == "string" then ids[def.name] = true end
    end
    local diagnostics = {gems = gems, available = available, ownedCount = 0, ownedMythicPlus = 0, scope = "all owned", unlocked = 0,
        noAwakening = 0, affordable = 0, needsGems = 0, errors = 0, ownershipFallbacks = 0, checks = {},
        sources = {profile = liveModules.ProfileClient and "live" or "require",
            gems = liveModules.Gems and "live" or "require", fighters = liveModules.Fighters and "live" or "require"}}
    Bot.AwakenDiagnostics = diagnostics
    for id in pairs(ids) do
        local ownedOk, owned = false, false
        if type(Profile.owns) == "function" then ownedOk, owned = pcall(Profile.owns, id) end
        local isOwned = type(view.owned) == "table" and collection[id]
            or (type(view.owned) ~= "table" and ownedOk and owned == true)
        if isOwned then
            diagnostics.ownedCount = diagnostics.ownedCount + 1
            if Rarity.tierOf(id) >= 10 then diagnostics.ownedMythicPlus = diagnostics.ownedMythicPlus + 1 end
            if not (ownedOk and owned == true) then diagnostics.ownershipFallbacks = diagnostics.ownershipFallbacks + 1 end
            local def = Fighters.list[id]
            local success, ready, reason, cost = pcall(Gems.canUnlock, view.abilities, available, id, "awaken", def, view.passives)
            -- The collection view is authoritative ownership data. If a second
            -- module cache has only base definitions, resolve this owned ID from
            -- FighterDefs before deciding that it has no Awakening.
            if not success or reason == "fighter" or reason == "none" then
                local root = Shared:FindFirstChild("FighterDefs")
                local actual = root and load(root, id, false)
                if type(actual) == "table" then
                    success, ready, reason, cost = pcall(Gems.canUnlock, view.abilities, available, id, "awaken", actual, view.passives)
                end
            end
            diagnostics.checks[id] = {reason = success and (reason or (ready and "ready" or "unknown")) or "error",
                cost = type(cost) == "number" and cost or nil, ownership = collection[id] and "profile collection" or "owns helper"}
            if not success then
                diagnostics.errors = diagnostics.errors + 1
                diagnostics.checks[id].error = tostring(ready)
                ready, reason = false, "error"
            end
            if ready and type(cost) == "number" and cost >= 0 and cost <= available then
                candidates[#candidates + 1] = {id = id, cost = cost}
                diagnostics.affordable = diagnostics.affordable + 1
            elseif reason == "gems" then needsGems = true; diagnostics.needsGems = diagnostics.needsGems + 1
            elseif reason == "done" then diagnostics.unlocked = diagnostics.unlocked + 1
            elseif reason == "none" or reason == "fighter" then diagnostics.noAwakening = diagnostics.noAwakening + 1 end
        end
    end
    table.sort(candidates, function(a, b)
        local ar, br = Rarity.tierOf(a.id), Rarity.tierOf(b.id)
        if ar ~= br then return ar > br end
        local priorities = Bot.DraftPriorities and Bot.DraftPriorities[ar] or {}
        local ap, bp = tonumber(priorities[a.id]) or 0, tonumber(priorities[b.id]) or 0
        if ap ~= bp then return ap > bp end
        return a.id < b.id
    end)
    local chosen = candidates[1]
    if not chosen then
        if needsGems then Bot.AwakenStatus = "waiting for gems / " .. tostring(gems)
        elseif diagnostics.ownedCount == 0 then Bot.AwakenStatus = "no owned fighters in profile"
        elseif diagnostics.errors > 0 then Bot.AwakenStatus = "eligibility error; see awakening logs"
        else Bot.AwakenStatus = tostring(diagnostics.ownedCount) .. " owned / " .. tostring(diagnostics.unlocked)
            .. " unlocked / " .. tostring(diagnostics.noAwakening) .. " without Awakening" end
        return
    end
    unlocker.pending = {id = chosen.id, cost = chosen.cost, at = now}
    Bot.AwakenStatus = "unlocking " .. chosen.id .. " / " .. chosen.cost .. " gems"
    local ok, err = pcall(Profile.unlockMove, chosen.id, "form")
    if not ok then
        unlocker.pending = nil; unlocker.retryAt = now + 10
        Bot.AwakenStatus = "unlock error"; Bot.AwakenError = tostring(err)
    end
    logger:line("awakening_request", {fighter = chosen.id, cost = chosen.cost, sent = ok})
end
-- A server leave request alone does not run MatchFlow.leave/toHub cleanup.
-- Activate the actual Results button, including when injected on that screen.
local playerGui = player:WaitForChild("PlayerGui")
local resultSeen, resultAttempt, resultPending = nil, -100, false
local function visible(obj)
    while obj and obj ~= playerGui do
        if obj:IsA("ScreenGui") and not obj.Enabled then return false end
        if obj:IsA("GuiObject") and not obj.Visible then return false end
        obj = obj.Parent
    end
    return obj == playerGui
end
local function resultButton()
    local screen = playerGui:FindFirstChild("Results")
    if not screen or not visible(screen) then return end
    -- Returning through Lobby leaves all automatic queue requests behind F7's
    -- gate; New Opponent also schedules a queue inside the game's own callback.
    local button = screen:FindFirstChild("Btn_lobby", true) or screen:FindFirstChild("Btn_newOpponent", true)
    if button and visible(button) then return button end
end
local function fireButton(button, allowResultsFallback)
    local targets = {button}
    for _, child in ipairs(button:GetDescendants()) do
        if child:IsA("GuiButton") then targets[#targets + 1] = child end
    end
    if type(getconnections) == "function" then
        for _, target in ipairs(targets) do
            if target:IsA("GuiButton") then
                for _, signalName in ipairs({"Activated", "MouseButton1Click"}) do
                    local ok, list = pcall(getconnections, target[signalName])
                    if ok then
                        local fired = false
                        for _, conn in ipairs(list) do
                            if conn.Enabled ~= false then
                                local success = pcall(function() conn:Fire() end)
                                fired = success or fired
                            end
                        end
                        if fired then return true end
                    end
                end
            end
        end
    end
    -- Exact exported match-result callback; its own ownership guard rejects stale screens.
    if allowResultsFallback ~= false and type(getgc) == "function" then
        local ok, list = pcall(getgc, true)
        if ok then
            for _, value in pairs(list) do
                if type(value) == "table" and type(rawget(value, "onNewOpponent")) == "function"
                    and type(rawget(value, "onLobby")) == "function"
                    and (not matchId or rawget(value, "matchId") == matchId) then
                    local callback = button.Name == "Btn_lobby" and value.onLobby or value.onNewOpponent
                    pcall(callback)
                    if not resultButton() then return true end
                end
            end
        end
    end
    return false
end
local popupAttempts = setmetatable({}, {__mode = "k"})
local popupProtected = {Results = true, Draft = true, Select = true, Versus = true,
    Hud = true, HUD = true, HudV2 = true, ControlSwitch = true, QuickMatchAutoStatus = true}
local dismissNames = {Close = 4, CLOSE = 4, Dismiss = 4, Skip = 3,
    CelebrateClose = 7}
local function popupsTick()
    if not Bot.SkipPopups or os.clock() - lastManual < Bot.ManualGrace then return false end
    local selected, best, blocking = nil, -math.huge, false
    for _, screen in ipairs(playerGui:GetChildren()) do
        if screen:IsA("ScreenGui") and visible(screen) and not popupProtected[screen.Name] then
            local reveal = screen.Name == "Roll" or string.sub(screen.Name, 1, 8) == "Rewards_"
            for _, obj in ipairs(screen:GetDescendants()) do
                if obj:IsA("GuiButton") and visible(obj) then
                    local rank = dismissNames[obj.Name]
                    if reveal and obj.Name == "SkipTap" then rank = 10 end
                    if reveal and obj.Name == "Tap" then rank = 9 end
                    if reveal and obj.Name == "Continue" then rank = 3 end
                    if reveal and obj.Name == "Done" then rank = 12 end
                    if reveal and obj.Name == "Veil" then rank = 8 end
                    if reveal and obj.Name == "OpenPackHit" then rank = 8 end
                    local enabled = type(obj.GetAttribute) ~= "function" or obj:GetAttribute("Enabled") ~= false
                    if rank and enabled then
                        blocking = true
                        if os.clock() - (popupAttempts[obj] or -100) >= 0.8 then
                            local score = (screen.DisplayOrder or 0) * 1000 + (obj.ZIndex or 0) * 10 + rank
                            if score > best then selected, best = obj, score end
                        end
                    end
                end
            end
        end
    end
    if selected then
        popupAttempts[selected] = os.clock()
        local screen = selected
        while screen.Parent ~= playerGui and screen.Parent do screen = screen.Parent end
        local activated = fireButton(selected, false)
        Bot.LastPopup = {screen = screen.Name, button = selected.Name, activated = activated, at = os.clock()}
        logger:line("popup_dismiss", Bot.LastPopup)
        if activated then
            status("Dismissing popup / " .. selected.Name)
            return true
        end
        Bot.LastError = "Popup handler unavailable: " .. selected.Name
        status(Bot.LastError)
        return true
    end
    return blocking
end
local function resultsTick()
    if ranked.arena then return ranked.finishedAt ~= nil end
    local button = resultButton()
    if not button then
        if resultPending then
            resultPending = false; ending = false; busy = false
            session = nil; lastQueue = os.clock()
            status("Results closed; waiting for next queue")
        end
        resultSeen = nil
        return false
    end
    busy = true
    if not outcomeRecorded then
        local screen = playerGui:FindFirstChild("Results")
        for _, obj in ipairs(screen and screen:GetDescendants() or {}) do
            if obj:IsA("TextLabel") and visible(obj) then
                local text = string.upper(obj.Text)
                if text == "DEFEAT" then recordOutcome({outcome = "defeat"})
                elseif text == "VICTORY" then recordOutcome({outcome = "victory"}) end
            end
        end
    end
    if not Bot.AutoJoin then
        resultSeen = nil
        status("Auto join off; choose next match manually")
        return true
    end
    if Bot.MatchMode == "ranked" and button.Name ~= "Btn_lobby" then
        status("Choose Lobby to switch to Ranked")
        return true
    end
    if os.clock() < rematchWaitUntil then status("Rematch accepted; waiting for draft"); return true end
    if not resultSeen then resultSeen = os.clock() end
    if os.clock() - resultSeen >= 2 and os.clock() - resultAttempt >= 3 then
        resultAttempt = os.clock()
        if fireButton(button) then resultPending = true; status("Results navigation selected; checking transition")
        else status("Results handler unavailable; check LastError"); Bot.LastError = "Cannot activate Results button: getconnections/getgc callback unavailable" end
    end
    return true
end
local gui = Instance.new("ScreenGui")
gui.Name = "QuickMatchAutoStatus"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100000
local label = Instance.new("TextLabel")
label.Size = UDim2.fromOffset(470, 110)
label.Position = UDim2.fromOffset(12, 80)
label.BackgroundColor3 = Color3.fromRGB(21, 25, 35)
label.BackgroundTransparency = 0.12
label.TextColor3 = Color3.new(1, 1, 1)
label.Font = Enum.Font.Code
label.TextSize = 14
label.TextWrapped = true
label.Parent = gui
gui.Parent = playerGui
function ranked.cancel()
    if not Ranked or ranked.state == "off" or ranked.state == "cancelling" or ranked.arena then return end
    local ok, err = pcall(Ranked.queue, false)
    if ok then ranked.state, ranked.requestAt = "cancelling", os.clock()
    else Bot.LastError = tostring(err) end
end
local function cancelMatchmaking()
    if queued or queueRequested then
        local ok, err = pcall(Online.queue, false, "classic")
        if not ok then Bot.LastError = tostring(err) end
        queued, queueRequested = false, false
    end
    ranked.cancel()
end
function Bot.SetMatchMode(mode)
    if mode ~= "quick" and mode ~= "ranked" then return false end
    if Bot.MatchMode ~= mode then
        cancelMatchmaking()
        Bot.MatchMode = mode
        resultSeen = nil
        if rematchAutoAccepted then
            rematchAutoAccepted, rematchAnswered, rematchWaitUntil = false, false, 0
            pcall(Online.rematch, false)
        end
    end
    local saved = Bot.SaveSettings()
    status((mode == "ranked" and "Ranked selected" or "Quick Match selected") .. (saved and "" or " / settings storage unavailable"))
    return saved
end
function ranked.tick(blocked)
    if ranked.arena then
        if Bot.AutoJoin and Ranked and ranked.finishedAt and os.clock() >= ranked.finishedAt + 3
            and os.clock() >= ranked.returnAt and Bot.SaveSettings() then
            ranked.returnAt = os.clock() + 12
            local ok, err = pcall(Ranked.back)
            if ok then status("Returning from Ranked") else Bot.LastError = tostring(err) end
        end
        return true
    end
    if (ranked.state == "request" or ranked.state == "cancelling") and os.clock() - ranked.requestAt >= 12 then
        ranked.state = "off"
    end
    if Bot.MatchMode ~= "ranked" then return ranked.state ~= "off" end
    if not Bot.AutoJoin or blocked or ranked.state ~= "off" or os.clock() < ranked.retryAt then return true end
    ranked.retryAt = os.clock() + 8
    if not Ranked or not ranked.handlers or not RankConfig or RankConfig.ENABLED ~= true or (Flags and Flags.MATCH_V2 ~= true) then
        status("Ranked unavailable in this game build")
    elseif type(Ranked.connected) ~= "function" or not Ranked.connected() then
        status("Waiting for Ranked connection")
    elseif not Bot.SaveSettings() then
        status("Ranked waiting / settings storage unavailable")
    else
        ranked.state, ranked.requestAt = "request", os.clock()
        local ok, err = pcall(Ranked.queue, true)
        if ok then status("Joining Ranked")
        else ranked.state = "off"; Bot.LastError = tostring(err); status("Ranked queue error") end
    end
    return true
end
function Bot.Stop()
    if not alive then return end
    Bot.SaveSettings()
    alive = false; Bot.Enabled = false; dealGeneration = dealGeneration + 1
    local cancelQueue = (queued or queueRequested) and Bot.AutoJoin
    queued, queueRequested = false, false; resetCombat()
    Bot.StopErrors = {}
    local function cleanup(name, action)
        local ok, err = pcall(action)
        if not ok then Bot.StopErrors[#Bot.StopErrors + 1] = name .. ": " .. tostring(err) end
    end
    cleanup("log finish", function() logger:finish("unload") end)
    cleanup("log flush", function() logger:flush(true) end)
    cleanup("input restore", function() if Input.sample == sampleWrapper then Input.sample = originalSample end end)
    cleanup("bind restore", function() if Online.bind == bindWrapper then Online.bind = originalBind end end)
    cleanup("event detach", function()
        for event, wrapper in pairs(ownedOnlineSlots) do
            local slot = onlineSlots[event]
            if slot and slot.callback == wrapper then slot.callback = nil end
        end
        for _, slot in pairs(ranked.handlers or {}) do slot.callback = nil end
    end)
    for _, conn in ipairs(connections) do cleanup("disconnect", function() conn:Disconnect() end) end
    if cancelQueue then cleanup("queue cancel", function() Online.queue(false, "classic") end) end
    cleanup("ranked cancel", ranked.cancel)
    cleanup("UI destroy", function() gui:Destroy() end)
    status("Unloaded")
end
local function combatInput(input)
    local code = input.KeyCode
    if Input.PRESS and Input.PRESS[code] or Input.PAD and Input.PAD[code] then return true end
    for _, map in ipairs({Input.KB_HOLD or {}, Input.PAD_HOLD or {}}) do
        for _, codes in pairs(map) do
            for _, value in ipairs(codes) do if code == value then return true end end
        end
    end
    -- Compatibility fallback for environments that expose only sampler/hold.
    if Input.KB_HOLD == nil then
        for _, name in ipairs({"A", "D", "S", "F", "W", "Space", "Up", "Down", "Left", "Right", "Q", "J", "V", "C", "X", "One", "Two", "Three"}) do
            if code == Enum.KeyCode[name] then return true end
        end
    end
    return false
end
connections[#connections + 1] = UIS.InputBegan:Connect(function(input, processed)
    if not alive or UIS:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.F6 then
        Bot.Enabled = not Bot.Enabled
        dealGeneration = dealGeneration + 1
        if not Bot.Enabled and Bot.AutoJoin then cancelMatchmaking() end
        Bot.SaveSettings()
        if Bot.Enabled then observeOpponent({}) end
        if Bot.Enabled and drafting and lastDeal then deal(lastDeal) end
    elseif input.KeyCode == Enum.KeyCode.F7 then
        Bot.AutoJoin = not Bot.AutoJoin
        if not Bot.AutoJoin then cancelMatchmaking() end
        Bot.SaveSettings()
        if not Bot.AutoJoin and rematchAutoAccepted then
            rematchAutoAccepted = false; rematchAnswered = false; rematchWaitUntil = 0
            local ok, err = pcall(Online.rematch, false)
            if not ok then Bot.LastError = tostring(err) end
        end
        if not Bot.AutoJoin then resultSeen = nil end
        status(Bot.AutoJoin and "Automatic matchmaking enabled" or "Auto join off; join matches manually")
    elseif input.KeyCode == Enum.KeyCode.F8 then Bot.Stop()
    elseif input.KeyCode == Enum.KeyCode.F9 then Bot.SetMatchMode(Bot.MatchMode == "ranked" and "quick" or "ranked")
    elseif not processed and combatInput(input) then
        lastManual = os.clock()
    end
end)
if player.OnTeleport then
    connections[#connections + 1] = player.OnTeleport:Connect(function()
        if alive then Bot.SaveSettings(); pcall(logger.flush, logger, true) end
    end)
end
task.spawn(function()
    while alive do
        Bot.SaveSettings()
        if Bot.Enabled then
            local okAwaken, awakenError = pcall(awakenTick)
            if not okAwaken then
                Bot.AwakenStatus = "error"; Bot.AwakenError = tostring(awakenError)
                unlocker.retryAt = os.clock() + 10
            end
            local okReward, rewardError = pcall(rewardsTick)
            if not okReward then
                Bot.RewardStatus = "error"; Bot.RewardError = tostring(rewardError)
                rewardClaim.retryAt = os.clock() + 10
            end
            local okPopup, inPopup = pcall(popupsTick)
            if not okPopup then Bot.LastError = tostring(inPopup); inPopup = true end
            local okResults, inResults = true, false
            if not inPopup then okResults, inResults = pcall(resultsTick) end
            if not okResults then
                Bot.LastError = tostring(inResults)
                status("Results check failed: " .. Bot.LastError)
                inResults = true
            end
            local current = skipTick(discover())
            if not ranked.arena then current = lobbyRecoveryTick(current, inPopup or inResults) end
            if current and current.r.sim.phase ~= "done" then busy = true end
            local blocked = inPopup or inResults or busy or queued or queueRequested
            local handledRanked = ranked.tick(blocked)
            if not handledRanked and Bot.AutoJoin and not inPopup and not inResults and not busy and not queued and os.clock() - lastQueue >= 8 then
                lastQueue = os.clock()
                queueRequested = true
                local ok, err = pcall(function()
                    Online.queue(true, "classic")
                end)
                if not ok then queueRequested = false; Bot.LastError = tostring(err); status("Queue error: " .. tostring(err))
                else status("Joining Quick Match") end
            end
            if current and current.r.sim.phase == "fight" and os.clock() - lastGoodSample > 5 then
                status("Input hook inactive; executor may use a separate module environment")
            end
        end
        local okLog, logError = pcall(logger.flush, logger)
        if not okLog then logger:fail(logError) end
        label.Text = "v4.28 " .. (Bot.Enabled and "ON" or "PAUSED") .. " | " .. Bot.Status
            .. "\nF6 pause | F7 auto join: " .. (Bot.AutoJoin and "ON" or "OFF") .. " | F8 unload"
            .. "\nF9 mode: " .. (Bot.MatchMode == "ranked" and "Ranked" or "Quick Match")
            .. "\nLogs: " .. Bot.LogStatus .. " | Rewards: " .. Bot.RewardStatus
            .. "\nAwaken: " .. Bot.AwakenStatus
            .. (Bot.AwayWarnings > 0 and ("\nAway: " .. Bot.AwayWarnings .. "/" .. Bot.AwayLimit .. " / keep Roblox focused") or "")
        task.wait(0.5)
    end
end)
warn("[QuickMatchAuto v4.28] Full CONTROL. F6 autoplay, F7 automatic matchmaking, F8 unload; F9 mode.")
