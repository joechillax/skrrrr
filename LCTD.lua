-- Last Contract Tower Defense: run this one file in lobby or in a fresh match.
-- Saves a local copy for teleport continuation; no remote loader or third-party UI.
local source = [========[-- Last Contract recorder/replayer. Protocol derived from the supplied 2026-10-03 dumps.
local function openCore(api)
    local C = {Mode = "Idle", Status = "Choose a macro or record a fresh round.", Running = true,
        Pending = {}, Bindings = {}, InstanceRefs = {}, Step = 0, Attempts = 0}
    local function status(s) C.Status = s end
    local function refFor(object)
        if C.InstanceRefs[object] then return C.InstanceRefs[object] end
        local d = api.describe(object)
        assert(d and d.Position, "Selected object has no stable world position")
        -- A fast click can reference a placement before the confirmation worker binds it.
        local nearest, closest = nil, 1.5
        for _, p in ipairs(C.Pending) do
            local dist = p.Name == d.Name and p.Position and api.purchaseDistance(p.Position, d.Position) or math.huge
            if p.Action == "Place" and dist < closest then nearest, closest = p, dist end
        end
        if nearest then
            C.InstanceRefs[object] = nearest.Ref
            C.Record.Refs[nearest.Ref].Position = d.Position
            return nearest.Ref
        end
        local id = tostring(#C.Record.Refs + 1)
        C.Record.Refs[tonumber(id)] = d
        C.InstanceRefs[object] = tonumber(id)
        return tonumber(id)
    end
    function C.Backup()
        if not C.Record then return end
        local ok, err = api.backup(C.Record)
        C.SaveError = not ok and tostring(err) or nil
    end
    function C.StartRecord(name, mission, difficulty)
        assert(C.Mode == "Idle", "Stop the current operation first")
        assert(api.fresh(), "Record in a fresh match before placing or installing towers")
        assert(api.canCapture(), "This executor needs hookmetamethod and getnamecallmethod for recording")
        local map = api.map()
        assert(map and map.Parts and #map.Parts > 0, "Map is still loading; wait before recording")
        C.Record = {Version = 1, Game = "LastContract", Name = name, Mission = mission,
            Difficulty = difficulty, Map = map, Loadout = api.loadout(), Refs = {}, Steps = {}, Complete = false}
        C.Pending, C.Bindings, C.InstanceRefs = {}, {}, {}
        C.Plan, C.Rejected, C.LastRejected, C.FinishStarted = nil, 0, nil, nil
        C.Started = api.now()
        C.Mode = "Record"
        C.Backup()
        status("Recording confirmed actions, including Hardpoint installs.")
    end
    function C.Capture(remote, args)
        if C.Mode ~= "Record" then return nil end
        if remote == "AbilityTowerActivate" then return nil end
        local s = {Time = api.now() - C.Started, Wave = api.wave(), Offset = api.waveAge(), Sent = api.now(), State = "Pending"}
        if remote == "TowerPlacement" then
            s.Action, s.Slot, s.Position = "Place", tostring(args[1]), api.vector(args[2])
            s.Name = api.slotName(s.Slot)
            assert(s.Name and s.Position, "Cannot resolve placement slot or position")
            s.Ref = #C.Record.Refs + 1
            C.Record.Refs[s.Ref] = {Name = s.Name, Position = s.Position, Kind = "Placed"}
            s.Before = api.identities()
        elseif remote == "HardpointTowerPlacement" then
            s.Action, s.Target, s.Name = "Install", refFor(args[1]), args[2]
            s.Position = api.describe(args[1]).Position
            s.Before = api.identities()
            s.Ref = #C.Record.Refs + 1
            C.Record.Refs[s.Ref] = {Name = s.Name, Position = s.Position, Kind = "Installed"}
        elseif remote == "TowerUpgrade" then
            s.Action, s.Target, s.Level = "Upgrade", refFor(args[1]), args[2]
            s.Previous = tostring(api.level(args[1]))
        elseif remote == "TowerSell" then
            s.Action, s.Target = "Sell", refFor(args[1])
        elseif remote == "ChangeTowerFiremode" then
            s.Action, s.Target, s.Value = "Targeting", refFor(args[2]), args[1]
        elseif remote == "AbilityTowerActivate" then
            s.Action, s.Target, s.Ability = "Ability", refFor(args[1]), args[2]
            s.Position = args[3] and api.cframe(args[3]) or nil
            s.Previous = api.activation(args[1]) or false
        elseif remote == "BaseUpgrade" then
            assert(args[1] == "HP" or args[1] == "Income", "Unknown base upgrade")
            s.Action, s.Value = "Base", args[1]
            s.Previous = api.baseLevel(s.Value)
            s.Level = s.Previous + 1
        elseif remote == "Reactor" then
            assert(args[1] == "install" or args[1] == "sell" or args[1] == "power" or args[1] == "overdrive", "Unknown reactor command")
            s.Action, s.Command, s.Element, s.Cell, s.Value = "Reactor", args[1], args[2], args[3], args[4]
            s.Previous = api.reactorSnapshot()
        else return nil end
        s.Object = args[1]
        if s.Action == "Targeting" then s.Object = args[2] end
        s.Cost = api.cost(s, C.Record, C.Bindings)
        table.insert(C.Pending, s)
        return s
    end
    function C.Returned(s, ok, result)
        if not s or s.State ~= "Pending" then return end
        if not ok then s.State = "Rejected"; s.Reason = tostring(result); return end
        if s.Action == "Upgrade" then
            if result[1] == true then
                s.Level = result[2] or s.Level
                s.State = "Confirmed"
            elseif result[1] == false then s.State = "Rejected"; s.Reason = "Server rejected upgrade" end
        end
    end
    local function cleanStep(s)
        local out = {}
        for _, k in ipairs({"Action", "Time", "Wave", "Offset", "Slot", "Position", "Name", "Ref", "Target", "Level", "Previous", "Value", "Ability", "Command", "Element", "Cell", "Cost"}) do
            if s[k] ~= nil and (k ~= "Previous" or s.Action ~= "Reactor") then out[k] = s[k] end
        end
        return out
    end
    function C.PollRecord()
        if C.Mode ~= "Record" and C.Mode ~= "Finishing" then return end
        for i = #C.Pending, 1, -1 do
            if C.Pending[i].Action == "Ability" then table.remove(C.Pending, i) end
        end
        for _, s in ipairs(C.Pending) do
            if s.State == "Confirmed" and s.Ref and s.ConfirmedObject then
                C.InstanceRefs[s.ConfirmedObject] = s.Ref
            end
            if s.State == "Pending" then
                local yes, object = api.confirm(s, s.Object, s.Before, s.Previous, C.InstanceRefs)
                if yes then
                    s.State = "Confirmed"
                    if s.Ref and object then
                        s.ConfirmedObject = object
                        C.InstanceRefs[object] = s.Ref
                        local d = api.describe(object)
                        C.Record.Refs[s.Ref].Position = d.Position
                        -- Keep the placement's ground point; the model pivot includes its offset.
                    end
                elseif api.now() - s.Sent > 20 then
                    -- Replication and queued spawns can arrive late. Keep the
                    -- request and its order instead of silently deleting it.
                    s.Delayed = true
                    if api.ended() and api.now() - (C.FinishStarted or api.now()) > 30 then
                        s.State = "Rejected"; s.Reason = "Unresolved at match end"
                        C.Record.Unresolved = (C.Record.Unresolved or 0) + 1
                    end
                end
            end
        end
        -- Flush in request order, even when acknowledgements arrive out of order.
        while C.Pending[1] and C.Pending[1].State ~= "Pending" do
            local s = table.remove(C.Pending, 1)
            if s.State == "Confirmed" then
                table.insert(C.Record.Steps, cleanStep(s))
                C.Backup()
            else
                C.Rejected = (C.Rejected or 0) + 1
                C.LastRejected = s.Action .. ": " .. (s.Reason or "not confirmed")
            end
        end
        local delayed = false
        for _, s in ipairs(C.Pending) do if s.Delayed then delayed = true end end
        status(string.format("%d actions backed up · %d awaiting confirmation%s", #C.Record.Steps, #C.Pending,
            C.SaveError and " · SAVE ERROR: " .. C.SaveError or (C.LastRejected and " · Ignored " .. C.LastRejected or "")))
        if delayed then C.Status = C.Status .. " · delayed acknowledgement; request retained" end
    end
    function C.Finish()
        if C.Mode ~= "Record" and C.Mode ~= "Finishing" then return false end
        C.Mode = "Finishing"
        C.FinishStarted = C.FinishStarted or api.now()
        C.PollRecord()
        -- Do not silently discard unresolved steps at the match boundary.
        if #C.Pending > 0 then return false end
        C.Record.Complete = #C.Record.Steps > 0 and not C.Record.Unresolved
        local ok, err = api.save(C.Record)
        C.Backup()
        C.Mode = "Idle"
        status(ok and ((C.Record.Complete and "Saved and verified: " or "Saved partial; unresolved actions: ") .. C.Record.Name .. " (" .. #C.Record.Steps .. " actions)") or "Save failed; draft retained: " .. tostring(err))
        return true
    end
    function C.StartReplay(record)
        assert(C.Mode == "Idle", "Stop the current operation first")
        assert(type(record) == "table" and record.Complete and type(record.Steps) == "table" and #record.Steps > 0, "Choose a completed recorded macro")
        local ok, why = api.validate(record)
        assert(ok, why)
        C.Plan, C.Bindings, C.Step, C.Attempts, C.Record = record, {}, 1, 0, nil
        C.Started, C.Inflight, C.NextAttempt = api.now(), nil, 0
        C.LastBefore, C.Preplaced, C.Preflight, C.UsedObjects = nil, {}, nil, {}
        C.Deferred = {}
        C.Mode = "Replay"
        status("Replay started")
    end
    function C.ObserveCash(before, after)
        if not before or not after or after >= before then return end
        local recent = C.LastCashRequest
        if recent and api.now() - recent.Sent <= 2 and recent.ExpectedCost
            and math.abs((before-after) - recent.ExpectedCost) < 0.01 then
            recent.CashDebited = true
            return
        end
        local function observed(f) if f and f.CashKnown then f.CashDebited = true end end
        observed(C.Inflight); observed(C.Preflight)
        for _, f in pairs(C.Deferred or {}) do observed(f) end
    end
    function C.Trace(kind, index, s, f, why)
        if api.report then pcall(api.report, {Event=kind, Step=index, Action=s.Action, Name=s.Name,
            Target=s.Target, Ref=s.Ref, Reason=why, Wave=api.wave(), Attempts=f.Tries, CashDebited=f.CashDebited,
            CashKnown=f.CashKnown, Position=s.Position}) end
    end
    function C.Depends(index, s)
        for earlier in pairs(C.Deferred or {}) do
            if earlier < index and api.related(C.Plan.Steps[earlier], s, C.Plan) then return true end
        end
        return false
    end
    function C.Defer(s, f, why)
        f = f or {Waiting=true, Tries=0}
        f.Index, f.Reason = C.Step, why
        C.Deferred[C.Step] = f
        C.Trace("Deferred", C.Step, s, f, why)
        C.Step, C.Attempts, C.Inflight, C.NextAttempt, C.LastBefore = C.Step + 1, 0, nil, 0, nil
    end
    function C.Dispatch(s, target, f, index)
        f.Index, f.Sent, f.SentWave, f.Busy, f.Error, f.Waiting, f.Dispatched = index, api.now(), api.wave(), true, nil, false, false
        f.Tries = (f.Tries or 0) + 1
        f.CashKnown = api.cashTracked() and api.cash() ~= nil
        f.CashDebited = false
        f.ExpectedCost = api.cost(s, C.Plan, C.Bindings)
        api.spawn(function()
            if C.Mode ~= "Replay" or (C.Inflight ~= f and C.Preflight ~= f and C.Deferred[index] ~= f) then f.Busy = false; return end
            f.Dispatched = true
            f.Sent = api.now()
            if f.ExpectedCost and f.ExpectedCost > 0 then C.LastCashRequest = f end
            local ok, a, b = pcall(api.send, s, target, C.Plan)
            f.Busy = false
            if not ok then f.Error = tostring(a)
            elseif s.Action == "Upgrade" and a == true then
                if tostring(b or s.Level) == tostring(s.Level) then f.Accepted = true
                else f.Error = "Server returned a different upgrade branch" end
            end
        end)
    end
    function C.PollDeferred()
        local indices = {}
        for index in pairs(C.Deferred) do table.insert(indices, index) end
        table.sort(indices)
        C.RecoveryStatus = #indices > 0 and (#indices .. " pending · step " .. indices[1] .. ": " .. tostring(C.Deferred[indices[1]].Reason)) or nil
        for _, index in ipairs(indices) do
            local s, f = C.Plan.Steps[index], C.Deferred[index]
            if not C.Depends(index, s) then
                local target = s.Target and api.resolve(C.Plan.Refs[s.Target], C.Bindings[s.Target]) or nil
                if s.Target and target then C.Bindings[s.Target] = target end
                local yes, object = api.confirm(s, target or f.Target, f.Before, f.Previous, C.UsedObjects)
                if f.Accepted or yes then
                    if s.Ref and object then C.Bindings[s.Ref], C.UsedObjects[object] = object, s.Ref end
                    C.Deferred[index] = nil
                    C.Trace("Recovered", index, s, f, "Confirmed by live state")
                elseif not f.Busy then
                    local ready, why = api.ready(s, C.Plan, target, C.Started)
                    if ready and (f.Waiting or api.recover(s, f)) then
                        f.Target = target
                        f.Before = f.Before or api.identities()
                        f.Previous = f.Previous or api.previous(s, target)
                        C.Trace("Retry", index, s, f, "Live state permits dispatch")
                        C.Dispatch(s, target, f, index)
                        return
                    else f.Reason = why or (f.CashDebited and "Paid; awaiting tower replication" or "Awaiting confirmation/retry") end
                end
            end
        end
    end
    function C.PollPrebuy()
        if C.Mode ~= "Replay" then return false end
        if C.Preflight then
            local f = C.Preflight
            local s = C.Plan.Steps[f.Index]
            local target = s.Target and api.resolve(C.Plan.Refs[s.Target], C.Bindings[s.Target]) or nil
            local yes, object = api.confirm(s, f.Target or target, f.Before, nil, C.UsedObjects)
            if yes then
                C.Preplaced[f.Index], C.Bindings[s.Ref], C.Preflight = true, object, nil
                if object then C.UsedObjects[object] = s.Ref end
            elseif f.Error then
                status("Pre-wave purchase blocked: " .. f.Error)
            elseif api.now() - f.Sent > 20 then
                -- An ambiguous placement must not trigger Start or duplicate purchases.
                status("Waiting for pre-wave purchase confirmation; match start held")
            end
            return true
        end
        if not api.prestart() then return false end
        -- Spend on recorded purchases only; stop at the first sell to avoid buying
        -- towers whose positions are deliberately reused later in the strategy.
        for i, s in ipairs(C.Plan.Steps) do
            if s.Action == "Sell" then break end
            if not C.Preplaced[i] and (s.Action == "Place" or s.Action == "Install") then
                local target = s.Target and api.resolve(C.Plan.Refs[s.Target], C.Bindings[s.Target]) or nil
                local ready, why, reason = api.ready(s, C.Plan, target, C.Started, true)
                if ready then
                    local f = {Index = i, Before = api.identities(), Sent = api.now(), SentWave=api.wave(), Target = target,
                        CashKnown=api.cashTracked() and api.cash() ~= nil, Tries=1, ExpectedCost=api.cost(s, C.Plan, C.Bindings)}
                    C.Preflight = f
                    status("Buying before wave 1: " .. s.Name)
                    api.spawn(function()
                        if C.Mode ~= "Replay" or C.Preflight ~= f then return end
                        f.Dispatched = true
                        f.Sent = api.now()
                        C.LastCashRequest = f
                        local ok, err = pcall(api.send, s, target, C.Plan)
                        if not ok then f.Error = tostring(err) end
                    end)
                    return true
                elseif reason ~= "Cash" and reason ~= "Limit" then
                    status("Match start held: " .. why); return true
                end
            end
        end
        -- All affordable recorded purchases have been confirmed before Start.
        local ok, why = api.startMatch()
        status(ok and "Pre-wave purchases complete; starting wave 1" or "Pre-wave purchases complete; " .. tostring(why))
        return true
    end
    function C.PollReplay()
        if C.Mode ~= "Replay" or api.ended() then return end
        C.Deferred = C.Deferred or {}
        C.PollDeferred()
        while C.Plan.Steps[C.Step] and (C.Preplaced[C.Step] or C.Plan.Steps[C.Step].Action == "Ability") do
            C.Step, C.Attempts, C.Inflight, C.NextAttempt, C.LastBefore = C.Step + 1, 0, nil, 0, nil
        end
        if C.PollPrebuy() then return end
        while C.Preplaced[C.Step] do C.Step = C.Step + 1 end
        local s = C.Plan.Steps[C.Step]
        if not s then status(C.RecoveryStatus and "Main sequence complete; resolving pending actions." or "All actions complete; waiting for match result."); return end
        if C.Depends(C.Step, s) then C.Defer(s, nil, "Waiting for earlier action on this target"); return end
        local target = s.Target and api.resolve(C.Plan.Refs[s.Target], C.Bindings[s.Target]) or nil
        if s.Target and target then C.Bindings[s.Target] = target end
        if C.Inflight then
            local f = C.Inflight
            local yes, object = api.confirm(s, f.Target or target, f.Before, f.Previous, C.UsedObjects)
            if f.Accepted then yes = true end
            if yes then
                if s.Ref and object then C.Bindings[s.Ref] = object; C.UsedObjects[object] = s.Ref end
                C.Step, C.Attempts, C.Inflight, C.NextAttempt, C.LastBefore = C.Step + 1, 0, nil, 0, nil
                return
            end
            if api.now() - f.Sent < 12 then return end
            if api.wave() > 0 then C.Defer(s, f, f.Error or "Awaiting purchase/state confirmation"); return end
            if f.Busy then return end
            -- One-shot actions must not be repeated if their outcome is ambiguous.
            if s.Action == "Place" or s.Action == "Install" or s.Action == "Ability" or (s.Action == "Reactor" and s.Command == "overdrive") then
                status("Step " .. C.Step .. ": waiting for confirmation; duplicate purchase/activation held")
                -- Keep polling live state for a delayed acknowledgement.
                return
            end
            C.Inflight = nil
            C.NextAttempt = api.now() + math.min(8, 1 + C.Attempts)
        end
        if api.now() < C.NextAttempt then return end
        -- Already-applied state permits late confirmations without another send.
        if s.Action ~= "Place" and s.Action ~= "Install" and s.Action ~= "Ability" and not (s.Action == "Reactor" and s.Command == "overdrive") then
            local done = s.Action == "Sell" and C.Bindings[s.Target] and C.Bindings[s.Target].Parent == nil
            if s.Action ~= "Sell" then done = api.confirm(s, target, nil, nil) end
            if done then C.Step, C.Attempts, C.LastBefore = C.Step + 1, 0, nil; return end
        end
        local ready, why, reason = api.ready(s, C.Plan, target, C.Started)
        if not ready then
            if api.wave() > 0 and (reason == "Target" or reason == "Branch" or reason == "Limit") then C.Defer(s, nil, why); return end
            status("Step " .. C.Step .. "/" .. #C.Plan.Steps .. ": " .. why); return
        end
        -- Scan before each retry for a placement accepted without a timely response.
        if s.Ref and C.LastBefore then
            local done, object = api.confirm(s, target, C.LastBefore, nil)
            if done then C.Bindings[s.Ref] = object; C.Step, C.Attempts, C.LastBefore = C.Step + 1, 0, nil; return end
        end
        local f = {Sent = api.now(), Before = C.LastBefore or api.identities(), Previous = api.previous(s, target), Busy = true, Target = target}
        C.Inflight, C.LastBefore = f, f.Before
        C.Attempts = C.Attempts + 1
        status("Step " .. C.Step .. "/" .. #C.Plan.Steps .. ": " .. s.Action .. " · attempt " .. C.Attempts)
        C.Dispatch(s, target, f, C.Step)
    end
    function C.Stop()
        if C.Record and (C.Mode == "Record" or C.Mode == "Finishing") then C.Backup() end
        C.Mode, C.Inflight, C.LastBefore, C.Preflight = "Idle", nil, nil, nil
        C.Deferred, C.RecoveryStatus = {}, nil
        status("Stopped. Drafts retained; visuals restored.")
    end
    return C
end

local env = (getgenv and getgenv()) or _G
local RUNTIME_VERSION = "2026-10-03-7"
-- The original release installed a global hook that changed namecall context
-- before forwarding. Repair it before even GetService/Stop can reach that hook.
if env.LastContractCaptureHook == true then
    assert(type(hookmetamethod) == "function" and type(getnamecallmethod) == "function", "Legacy hook repair requires the executor's hook APIs")
    local nativeDispatch = function(self, ...)
        local method = getnamecallmethod()
        local fn = self[method]
        return fn(self, ...)
    end
    hookmetamethod(game, "__namecall", newcclosure and newcclosure(nativeDispatch) or nativeDispatch)
    env.LastContractCaptureHook = nil
    env.LastContractHookRepaired = true
end
local previousWorker = env.LastContractFarm
local bootToken = {}
env.LastContractBootToken = bootToken
local startupSettingsText = env.LastContractReloadSettings
if not startupSettingsText and type(readfile) == "function" and type(isfile) == "function" then
    local ok, data = pcall(function()
        if isfile("Last Contract Tower Defense/settings.json") then return readfile("Last Contract Tower Defense/settings.json") end
    end)
    if ok then startupSettingsText = data end
end
local liveRecording, liveReplay
local sameSession = previousWorker and previousWorker.Running and (not previousWorker.SessionId or previousWorker.SessionId == tostring(game.PlaceId) .. ":" .. tostring(game.JobId))
local liveLifecycle = sameSession and previousWorker.GetLifecycle and previousWorker.GetLifecycle()
if sameSession then
    if previousWorker.Mode == "Record" or previousWorker.Mode == "Finishing" then
        liveRecording = {}
        for _, k in ipairs({"Mode", "Record", "Pending", "InstanceRefs", "Bindings", "Started", "Rejected", "LastRejected", "FinishStarted"}) do
            liveRecording[k] = previousWorker[k]
        end
    elseif previousWorker.Mode == "Replay" then
        liveReplay = {}
        for _, k in ipairs({"Mode", "Plan", "Bindings", "Step", "Attempts", "Started", "Inflight", "NextAttempt", "LastBefore", "Preplaced", "Preflight", "UsedObjects", "Deferred", "RecoveryStatus", "LastCashRequest"}) do
            liveReplay[k] = previousWorker[k]
        end
        if previousWorker.RuntimeVersion == RUNTIME_VERSION or previousWorker.RuntimeVersion == "2026-10-03-4" or previousWorker.RuntimeVersion == "2026-10-03-5" or previousWorker.RuntimeVersion == "2026-10-03-6" then
            for _, k in ipairs({"Inflight", "Preflight"}) do
                if liveReplay[k] and not liveReplay[k].Dispatched then liveReplay[k] = nil end
            end
        end
        for _, f in pairs(liveReplay.Deferred or {}) do
            if not f.Dispatched then
                if f.Busy then f.Tries = math.max(0, (f.Tries or 1) - 1) end
                f.Waiting, f.Busy = true, false
            end
        end
    end
end
local legacyReload = previousWorker and not previousWorker.Detach
if previousWorker then
    if legacyReload then
        -- Older Destroy called Stop and overwrote Armed=false. Preserve the
        -- pre-teardown preferences while migrating that already-running UI.
        env.LastContractReloadSettings = startupSettingsText
        if previousWorker.Destroy then previousWorker.Destroy() end
    else previousWorker.Detach() end
end
local resume = env.LastContractResume == true
env.LastContractResume = nil
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Run = game:GetService("RunService")
local Teleport = game:GetService("TeleportService")
local HTTP = game:GetService("HttpService")
local Input = game:GetService("UserInputService")
local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui", 30)
assert(gui, "PlayerGui did not load; run the script again")
if env.LastContractBootToken ~= bootToken then return env.LastContractFarm end
local ROOT = "Last Contract Tower Defense"
local hasFiles = type(readfile) == "function" and type(writefile) == "function" and type(makefolder) == "function" and type(isfile) == "function"
local queueTeleport = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
local connections, visualConnections, ownCallbacks = {}, {}, {}
local alive, busy, armed, requested, queueInstalled = true, false, false, nil, false
local storageError, sessionProfiles = nil, env.LastContractSessionProfiles or {}
env.LastContractSessionProfiles = sessionProfiles
local sessionOnlyProfiles = env.LastContractSessionOnlyProfiles or {}
env.LastContractSessionOnlyProfiles = sessionOnlyProfiles
local settings = {Version = 2, Mission = "FirstContact", Difficulty = "Mild", Selected = nil, Performance = true, Armed = false, StartRecoveries = 0,
    NameBoxText = "My macro", PanelMinimized = false, AutoAbilities = true, AbilitiesPaused = false}
local function connect(signal, fn)
    ownCallbacks[fn] = true
    local c = signal:Connect(fn); table.insert(connections, c); return c
end
local function folders()
    if not hasFiles then return false end
    for _, p in ipairs({ROOT, ROOT .. "/Profiles"}) do
        if not (isfolder and isfolder(p)) then pcall(makefolder, p) end
    end
    return true
end
local function readJSON(path)
    if not hasFiles or not isfile(path) then return nil end
    local ok, data = pcall(function() return HTTP:JSONDecode(readfile(path)) end)
    if ok and type(data) == "table" then return data end
    storageError = "Unreadable file preserved: " .. path
    return nil
end
local function writeJSON(path, data)
    if not folders() then return false, "File APIs unavailable; session only" end
    local ok, err = pcall(function()
        local encoded = HTTP:JSONEncode(data)
        writefile(path .. ".tmp", encoded)
        assert(readfile(path .. ".tmp") == encoded, "Temporary file verification failed")
        if isfile(path) then
            -- Do not overwrite the previous good backup with a corrupt main file.
            local old = readfile(path)
            local valid = pcall(function() HTTP:JSONDecode(old) end)
            if valid then writefile(path .. ".bak", old) end
        end
        writefile(path, encoded)
        assert(readfile(path) == encoded, "Read-back verification failed")
    end)
    if not ok then storageError = tostring(err) end
    return ok, err
end
local function saveSettings()
    settings.Version, settings.RuntimeVersion = 2, RUNTIME_VERSION
    settings.Armed, settings.Intent = armed, requested
    local ok, err = writeJSON(ROOT .. "/settings.json", settings)
    return ok, err
end
local saved = readJSON(ROOT .. "/settings.json")
if legacyReload and startupSettingsText then
    local ok, snapshot = pcall(function() return HTTP:JSONDecode(startupSettingsText) end)
    if ok and type(snapshot) == "table" then saved = snapshot end
end
if saved then
    -- Merge every preference, including fields absent from the defaults. An
    -- unrelated toggle must not erase Intent, RecordName, or map metadata.
    for k, v in pairs(saved) do settings[k] = v end
    settings.NameBoxText = saved.NameBoxText or saved.RecordName or "My macro"
end
armed = settings.Armed == true and (settings.Intent == "Replay" or settings.Intent == "Record")
requested = armed and settings.Intent or nil
if liveLifecycle then armed, requested = liveLifecycle.Armed, liveLifecycle.Intent end
resume = armed
local restoredSettingsError
if legacyReload then
    local ok, err = saveSettings()
    if not ok then restoredSettingsError = "Reload could not preserve saved farm state: " .. tostring(err) end
end
env.LastContractReloadSettings = nil
local function safeName(name)
    name = tostring(name or "My macro"):gsub('[<>:"/\\|?*%c]', "_"):gsub("[%.%s]+$", ""):sub(1, 80)
    if name == "" then name = "My macro" end
    if name:upper():match("^(CON)$") or name:upper():match("^(PRN)$") or name:upper():match("^(AUX)$") or name:upper():match("^(NUL)$")
        or name:upper():match("^COM%d$") or name:upper():match("^LPT%d$") then name = "Macro_" .. name end
    return name
end
local function profilePath(name) return ROOT .. "/Profiles/" .. safeName(name) .. ".json" end
local function loadProfile(name)
    if not name then return nil end
    if hasFiles then
        if isfile(profilePath(name)) then return readJSON(profilePath(name)) end
        if not sessionOnlyProfiles[name] then return nil end
    end
    return sessionProfiles[name]
end
local function profileNames()
    local names, seen = {}, {}
    if hasFiles and listfiles then
        local ok, files = pcall(listfiles, ROOT .. "/Profiles")
        if ok then
            for _, path in ipairs(files) do
                local name = path:match("([^/\\]+)%.json$")
                if name then seen[name] = true; table.insert(names, name) end
            end
        end
    end
    for name in pairs(sessionProfiles) do
        if not seen[name] and (not hasFiles or sessionOnlyProfiles[name]) then table.insert(names, name) end
    end
    table.sort(names); return names
end
local function unusedName(name)
    name = safeName(name)
    local base, i = name, 2
    while sessionProfiles[name] or (hasFiles and isfile(profilePath(name))) do
        name = base .. " (" .. i .. ")"; i = i + 1
    end
    return name
end
local function saveProfile(record)
    if not record or #record.Steps == 0 then return false, "No confirmed actions" end
    sessionProfiles[record.Name] = record
    local ok, err = writeJSON(profilePath(record.Name), record)
    sessionOnlyProfiles[record.Name] = not ok or nil
    settings.Selected = record.Name
    settings.Map, settings.Loadout = record.Map, record.Loadout
    saveSettings()
    return ok, err
end
local function findEvents()
    return RS:FindFirstChild("Events")
end
local function event(name)
    local events = findEvents()
    local r = events and events:FindFirstChild(name)
    assert(r, "Missing remote: " .. name)
    return r
end
local stage = game.PlaceId == 127750392812160 and "Lobby" or (game.PlaceId == 122908884019750 and "Match" or "Unsupported")
assert(stage ~= "Unsupported", "Run this in the supplied Last Contract lobby or match place")
local wave, waveStarted, ended, reactor, reactorVersion = 0, os.clock(), false, nil, 0
local matchCache = env.LastContractMatchCache
if type(matchCache) ~= "table" or matchCache.JobId ~= game.JobId or matchCache.PlaceId ~= game.PlaceId then
    matchCache = {JobId = game.JobId, PlaceId = game.PlaceId, Votes = {}, Closed = {}, Wave = 0}
    env.LastContractMatchCache = matchCache
end
wave = matchCache.Wave or 0
waveStarted = matchCache.WaveStarted or waveStarted
if liveLifecycle then reactor, reactorVersion = liveLifecycle.Reactor, liveLifecycle.ReactorVersion or 0 end
local startVote, voted, currentLobby, lobbySent, lobbyStartSent = nil, {}, nil, nil, nil
local lobbyAttempts, lobbyLeaving, lobbyUIAfter, startMissingSince = 0, false, 0, nil
local manualReturnPending = liveLifecycle and liveLifecycle.ManualReturnPending or false
if liveLifecycle then
    currentLobby, lobbySent, lobbyStartSent = liveLifecycle.Lobby, liveLifecycle.LobbySent, liveLifecycle.LobbyStartSent
    lobbyAttempts, lobbyLeaving = liveLifecycle.LobbyAttempts or 0, liveLifecycle.LobbyLeaving or false
end
local findStartVote
local prepareClient, repairStartUI, C
local runtimeStarted = os.clock()
local initialized = false
local nextReturn = 0
if liveLifecycle then nextReturn = liveLifecycle.NextReturn or 0 end
local Configs
local function config()
    if not Configs then
        local m = RS:FindFirstChild("Configs")
        if m then local ok, data = pcall(require, m); if ok then Configs = data end end
    end
    return Configs
end
local function value(parent, name)
    local x = parent and parent:FindFirstChild(name)
    return x and x.Value
end
local function cash()
    return tonumber(value(player:FindFirstChild("leaderstats"), "Cash"))
end
local function difficulty()
    return value(RS:FindFirstChild("GameState"), "Difficulty") or settings.Difficulty
end
local function vector(v)
    if typeof(v) == "Vector3" then return {v.X, v.Y, v.Z} end
    if typeof(v) == "CFrame" then local p = v.Position; return {p.X, p.Y, p.Z} end
    return nil
end
local function position(object)
    if not object then return nil end
    local ok, p = pcall(function()
        local hit = object:FindFirstChild("Hitbox")
        if hit and hit:IsA("BasePart") then return hit.Position end
        if object:IsA("BasePart") then return object.Position end
        if object:IsA("Model") then return object:GetPivot().Position end
    end)
    return ok and vector(p) or nil
end
local function distance(a, b)
    if not a or not b then return math.huge end
    return math.sqrt((a[1]-b[1])^2 + (a[2]-b[2])^2 + (a[3]-b[3])^2)
end
local function purchaseDistance(a, b)
    if not a or not b or math.abs(a[2]-b[2]) > 32 then return math.huge end
    return math.sqrt((a[1]-b[1])^2 + (a[3]-b[3])^2)
end
local function objectPath(object)
    local p = {}
    while object and object ~= workspace do
        table.insert(p, 1, object.Name); object = object.Parent
    end
    return object == workspace and p or nil
end
local function atPath(path)
    local o = workspace
    for _, name in ipairs(path or {}) do o = o and o:FindFirstChild(name) end
    return o
end
local function describe(object)
    if typeof(object) ~= "Instance" then return nil end
    return {Name = object:GetAttribute("Name") or object.Name, Position = position(object), Path = objectPath(object),
        Kind = object:GetAttribute("OwnerName") == player.Name and "Placed" or "Static"}
end
local function towers()
    local all = {}
    for _, n in ipairs({"Towers", "DisplayTowers"}) do
        local f = workspace:FindFirstChild(n)
        if f then for _, o in ipairs(f:GetChildren()) do table.insert(all, o) end end
    end
    return all
end
local staticObjects = {}
local function scanStatic()
    staticObjects = {}
    local cfg = config()
    for _, o in ipairs(workspace:GetDescendants()) do
        local name = o:GetAttribute("Name")
        if name and cfg and cfg.Towers[name] and position(o) then table.insert(staticObjects, o) end
    end
end
local function identities()
    local set = {}
    for _, o in ipairs(towers()) do set[o] = true end
    for _, o in ipairs(staticObjects) do set[o] = true end
    return set
end
local function owned(o) return o:GetAttribute("OwnerName") == player.Name end
local function slotName(slot)
    local f = player:FindFirstChild("Towers")
    local v = f and (f:FindFirstChild("Slot" .. tostring(slot):gsub("^Slot", "")) or f:FindFirstChild(tostring(slot)))
    return v and v.Value
end
local function loadout()
    local out = {}
    for i = 1, 5 do out[tostring(i)] = slotName(i) end
    return out
end
local function findSlot(name, recorded)
    if slotName(recorded) == name then return tostring(recorded):gsub("^Slot", "") end
    for i = 1, 5 do if slotName(i) == name then return tostring(i) end end
end
local function candidates()
    local out = towers()
    for _, o in ipairs(staticObjects) do if o.Parent then table.insert(out, o) end end
    return out
end
local function resolve(d, binding)
    if not d then return nil end
    local function matches(o)
        if not o or not o.Parent then return false end
        if (o:GetAttribute("Name") or o.Name) ~= d.Name then return false end
        if d.Kind ~= "Static" and not owned(o) then return false end
        if d.Kind == "Static" then return distance(position(o), d.Position) < 1 end
        return purchaseDistance(position(o), d.Position) < 1.5
    end
    if matches(binding) then return binding end
    -- Tower names contain server-local IDs and can be reused by a different
    -- nearby tower next round. Only static map paths identify a stable object.
    if d.Kind == "Static" and matches(atPath(d.Path)) then return atPath(d.Path) end
    local found, closest, ambiguous = nil, 1.5, false
    for _, o in ipairs(candidates()) do
        if matches(o) then
            local dist = purchaseDistance(position(o), d.Position)
            if dist < closest - 0.01 then found, closest, ambiguous = o, dist, false
            elseif found and found ~= o and math.abs(dist-closest) < 0.01 then ambiguous = true end
        end
    end
    return not ambiguous and found or nil
end
local function mapSignature(filter)
    filter = filter or 2
    local map = workspace:FindFirstChild("Map")
    local parts = {}
    if map then
        for _, o in ipairs(map:GetDescendants()) do
            if o:IsA("BasePart") and o.Anchored and not o:FindFirstAncestor("Misc") then
                local mutable, a = false, o
                local cfg = config()
                while a and a ~= map do
                    local n = a:GetAttribute("Name")
                    if filter == 2 and n and cfg and cfg.Towers[n] then mutable = true; break end
                    a = a.Parent
                end
                if not mutable then
                    local p, z = o.Position, o.Size
                    table.insert(parts, string.format("%s:%.1f,%.1f,%.1f:%.1f,%.1f,%.1f", o:GetFullName(), p.X,p.Y,p.Z,z.X,z.Y,z.Z))
                end
            end
        end
    end
    table.sort(parts)
    -- A deterministic sample tolerates irrelevant model IDs outside Map.
    local sample = {}
    for i = 1, math.min(24, #parts) do sample[i] = parts[math.floor((i-1) * #parts / math.min(24,#parts)) + 1] end
    return {Parts = sample, Count = #parts, Filter = filter}
end
local function level(o) return o and o:GetAttribute("Level") end
local function activation(o) return o and o:GetAttribute("TimeSinceLastActivation") end
local function baseLevel(kind)
    local state = RS:FindFirstChild("GameState")
    local hp = state and state:FindFirstChild("BaseHP")
    return hp and tonumber(hp:GetAttribute(kind == "HP" and "HPUpgrades" or "IncomeUpgrades")) or 0
end
local function componentAt(cell)
    for _, c in ipairs(reactor and reactor.Components or {}) do if tonumber(c.Cell) == tonumber(cell) then return c end end
end
local function elementMatches(c, name)
    local cfg = config()
    return c and (c.Name == name or c.Element == name or c.Type == name or (cfg and cfg.Elements[name] and c.Icon == cfg.Elements[name].Icon))
end
local function reactorSnapshot()
    return {Version = reactorVersion, Power = reactor and reactor.Power, Overdrive = reactor and reactor.Overdrive}
end
local function cost(s, plan, bindings)
    local cfg = config()
    if not cfg then return tonumber(s.Cost) end
    if s.Action == "Place" or s.Action == "Install" then
        local t = cfg.Towers[s.Name]; return t and t.Lvl0 and tonumber(t.Lvl0.Price)
    elseif s.Action == "Upgrade" then
        local d = plan.Refs[s.Target]; local t = d and cfg.Towers[d.Name]
        local l = t and t["Lvl" .. s.Level]; return l and tonumber(l.Price)
    elseif s.Action == "Base" then
        local b = cfg.Towers.Base
        if s.Value == "HP" then return b.HealthUpgradePrice + b.HealthUpgradePriceIncrease * baseLevel("HP") end
        -- This formula is the one displayed by the supplied match UI.
        return b.IncomeUpgradePrice * (1 + baseLevel("Income"))
    elseif s.Action == "Reactor" and s.Command == "install" then
        return cfg.Elements[s.Element] and tonumber(cfg.Elements[s.Element].Price)
    end
    return 0
end
local function confirm(s, target, before, previous, used)
    if s.Action == "Place" or s.Action == "Install" then
        if not before then return false end
        local found, best, ambiguous = nil, 1.5, false
        for _, o in ipairs(candidates()) do
            if (o:GetAttribute("Name") or o.Name) == s.Name and owned(o) and purchaseDistance(position(o), s.Position) < 1.5
                and (not used or not used[o] or used[o] == s.Ref or (s.Action == "Install" and o == target))
                and (not before[o] or (s.Action == "Install" and o == target)) then
                local dist = purchaseDistance(position(o), s.Position)
                if dist < best - 0.01 then found, best, ambiguous = o, dist, false
                elseif found and found ~= o and math.abs(dist-best) < 0.01 then ambiguous = true end
            end
        end
        return found ~= nil and not ambiguous, found
    elseif s.Action == "Upgrade" then return target and tostring(level(target)) == tostring(s.Level)
    elseif s.Action == "Sell" then return target ~= nil and target.Parent == nil
    elseif s.Action == "Targeting" then return target and target:GetAttribute("Firemode") == s.Value
    elseif s.Action == "Ability" then
        local a = activation(target)
        return a ~= nil and previous ~= nil and a ~= previous
    elseif s.Action == "Base" then return baseLevel(s.Value) >= s.Level
    elseif s.Action == "Reactor" then
        if not reactor then return false end
        if s.Command == "install" then return elementMatches(componentAt(s.Cell), s.Element)
        elseif s.Command == "sell" then return componentAt(s.Cell) == nil
        elseif s.Command == "power" then return reactor.Power == s.Value
        elseif s.Command == "overdrive" then return previous and reactorVersion > previous.Version and reactor.Overdrive ~= previous.Overdrive end
    end
    return false
end
local function previous(s, target)
    if s.Action == "Ability" then return activation(target) or false end
    if s.Action == "Reactor" then return reactorSnapshot() end
end
local function ready(s, plan, target, started, early)
    if C and C.ClientReady == false then return false, C.StartupStatus or "Waiting for the game's UI controller", "Startup" end
    if s.Target and not target then return false, "Waiting for " .. (plan.Refs[s.Target].Name or "target") .. " to spawn", "Target" end
    if s.Action == "Install" and target:GetAttribute("Name") ~= "Hardpoint" then return false, "Hardpoint already occupied", "Target" end
    if not early then
        if s.Wave and s.Wave > 0 then
            if wave < s.Wave then return false, "Waiting for wave " .. s.Wave, "Time" end
            if wave == s.Wave and os.clock() - waveStarted < (s.Offset or 0) then return false, "Waiting for recorded wave timing", "Time" end
        elseif wave == 0 and os.clock() - started < (s.Time or 0) then return false, "Waiting for recorded timing", "Time" end
    end
    if s.Action == "Place" then
        if not findSlot(s.Name, s.Slot) then return false, "Equip " .. s.Name .. " in your loadout", "Loadout" end
        local state = RS:FindFirstChild("GameState")
        local limit = tonumber(value(state, "CurrentTowerLimit"))
        local count, typeCount = 0, 0
        for _, o in ipairs(towers()) do if owned(o) then count = count + 1; if o:GetAttribute("Name") == s.Name then typeCount = typeCount + 1 end end end
        if limit and count >= limit then return false, "Tower limit reached", "Limit" end
        local cfg = config(); local t = cfg and cfg.Towers[s.Name]
        if t and t.TowerLimit and typeCount >= t.TowerLimit then return false, s.Name .. " limit reached", "Limit" end
    elseif s.Action == "Install" then
        local f, has = player:FindFirstChild("Emplacements"), false
        for _, o in ipairs(f and f:GetChildren() or {}) do if o.Value == s.Name then has = true end end
        if not has then return false, "Equip emplacement " .. s.Name, "Loadout" end
    elseif s.Action == "Upgrade" then
        local display = workspace:FindFirstChild("DisplayTowers")
        if display and target:IsDescendantOf(display) then
            return false, "Waiting for purchased tower to spawn at the next wave", "Target"
        end
        if s.Previous and tostring(level(target)) ~= tostring(s.Previous) then return false, "Upgrade branch does not match recorded level", "Branch" end
    elseif s.Action == "Ability" then
        local cfg = config(); local a = cfg and cfg.Abilites and cfg.Abilites[s.Ability]
        local last = activation(target)
        if a and last and os.time() - last < a.CD then return false, "Ability cooldown", "Cooldown" end
    elseif s.Action == "Reactor" then
        if not reactor then return false, "Waiting for reactor state", "Target" end
        if s.Command == "install" and reactor.GridLock then return false, "Reactor grid is locked", "Target" end
        if s.Command == "overdrive" and not reactor.OverdriveAvailable then return false, "Overdrive unavailable", "Cooldown" end
    end
    local price = cost(s, plan, {})
    if price == nil then return false, "Price unavailable; waiting for game configuration", "Config" end
    if price > 0 then
        local balance = cash()
        if balance == nil then return false, "Waiting for cash data", "Cash" end
        if balance < price then return false, string.format("Cash %s/%s", balance, price), "Cash" end
    end
    return true
end
local function startMatch(manual)
    if ended then return false, "Match already ended; use Return to lobby" end
    if wave > 0 then return false, "Match already started" end
    if prepareClient and not prepareClient() then return false, C.StartupStatus end
    if repairStartUI then repairStartUI() end
    if findStartVote then startVote = findStartVote() end
    if not startVote then return false, "No live Start vote found. Use Return to lobby for a fresh match if the game's vote was lost." end
    local last = voted[startVote]
    if last and os.clock() - last < (manual and 2 or 5) then return false, "Start vote sent; waiting for wave 1" end
    event("Vote"):FireServer(startVote, 1)
    voted[startVote] = os.clock()
    return true, "Start vote sent; waiting for wave 1"
end
local function send(s, target, plan)
    if s.Action == "Place" then return event("TowerPlacement"):FireServer(findSlot(s.Name, s.Slot), Vector3.new(table.unpack(s.Position)))
    elseif s.Action == "Install" then return event("HardpointTowerPlacement"):FireServer(target, s.Name)
    elseif s.Action == "Upgrade" then return event("TowerUpgrade"):InvokeServer(target, s.Level)
    elseif s.Action == "Sell" then return event("TowerSell"):FireServer(target)
    elseif s.Action == "Targeting" then return event("ChangeTowerFiremode"):FireServer(s.Value, target)
    elseif s.Action == "Ability" then
        return event("AbilityTowerActivate"):FireServer(target, s.Ability, s.Position and CFrame.new(table.unpack(s.Position)) or nil)
    elseif s.Action == "Base" then return event("BaseUpgrade"):FireServer(s.Value)
    elseif s.Action == "Reactor" then return event("Reactor"):FireServer(s.Command, s.Element, s.Cell, s.Value) end
    error("Unknown macro action: " .. tostring(s.Action))
end
local function validate(plan)
    if type(plan) ~= "table" then return false, "Profile is missing or unreadable" end
    if plan.Version ~= 1 or plan.Game ~= "LastContract" then return false, "Incompatible profile" end
    if type(plan.Steps) ~= "table" or type(plan.Refs) ~= "table" or type(plan.Map) ~= "table" or type(plan.Map.Parts) ~= "table" then return false, "Profile data is incomplete" end
    if plan.Difficulty ~= difficulty() then return false, "This macro uses " .. plan.Difficulty .. "; current match uses " .. difficulty() end
    local current = mapSignature(plan.Map.Filter or 1)
    if not plan.Map or #plan.Map.Parts == 0 or #current.Parts == 0 then return false, "Map is not ready; wait for Map to replicate" end
    if table.concat(plan.Map.Parts, "|") ~= table.concat(current.Parts, "|") then return false, "Map differs from recorded map; join the matching mission" end
    for _, s in ipairs(plan.Steps) do
        if type(s) ~= "table" or not ({Place=true,Install=true,Upgrade=true,Sell=true,Targeting=true,Ability=true,Base=true,Reactor=true})[s.Action] then return false, "Profile contains an unknown action" end
        if s.Action ~= "Ability" then
            if s.Target and (type(plan.Refs[s.Target]) ~= "table" or type(plan.Refs[s.Target].Position) ~= "table") then return false, "Profile contains a missing tower reference" end
            if s.Ref and type(plan.Refs[s.Ref]) ~= "table" then return false, "Profile contains a missing purchase reference" end
            if (s.Action == "Place" or s.Action == "Install") and (not s.Ref or type(s.Position) ~= "table" or #s.Position ~= 3 or type(s.Name) ~= "string") then return false, "Profile contains an invalid purchase" end
            if (s.Action == "Install" or s.Action == "Upgrade" or s.Action == "Sell" or s.Action == "Targeting") and not s.Target then return false, "Profile action has no target" end
            if s.Action == "Upgrade" and s.Level == nil then return false, "Profile upgrade has no level" end
            if s.Action == "Place" and not findSlot(s.Name, s.Slot) then return false, "Equip " .. s.Name .. " before replay" end
        end
    end
    return true
end
local selection = {Missions = {FirstContact=true, HospitalDefense=true, GroundZero=true},
    Difficulties = {Mild=true, Severe=true, Lethal=true, Terminal=true}, ConfirmedHere = false}
local function continuationPlan()
    if C.Mode == "Replay" then return C.Plan end
    if selection.CachedName ~= settings.Selected then
        selection.CachedName, selection.CachedProfile = settings.Selected, loadProfile(settings.Selected)
    end
    return selection.CachedProfile
end
-- The lobby controls are the user's destination. Profile selection, autosave,
-- recovery and Start farm must never silently replace that destination.
local function selectedPlan(plan, allowLabelRepair)
    if type(plan) ~= "table" or not plan.Complete then return false, "Select a completed saved macro" end
    if plan.Version ~= 1 or plan.Game ~= "LastContract" or type(plan.Steps) ~= "table" or type(plan.Refs) ~= "table"
        or type(plan.Map) ~= "table" or type(plan.Map.Parts) ~= "table" or #plan.Map.Parts == 0 then return false, "Profile data is incomplete or incompatible" end
    if not selection.Missions[settings.Mission] or not selection.Difficulties[settings.Difficulty] then return false, "Choose a valid mission and difficulty" end
    if not selection.Missions[plan.Mission] or not selection.Difficulties[plan.Difficulty] then return false, "Profile has an invalid mission or difficulty" end
    if plan.Difficulty ~= settings.Difficulty then
        return false, "Selected " .. settings.Difficulty .. "; macro uses " .. plan.Difficulty .. ". Choose a matching macro or difficulty."
    end
    if plan.Mission ~= settings.Mission and not allowLabelRepair then
        return false, "Macro label: " .. plan.Mission .. ". Selected: " .. settings.Mission .. ". For an old wrong label: in the actual match, choose its mission here, then Start farm to verify."
    end
    return true
end
local function verifyMissionLabel(plan)
    local ok, why = validate(plan)
    assert(ok, why)
    -- The dumps expose Difficulty but no mission identifier in GameState.
    -- Repair only on an explicit Start farm in the user-selected actual match,
    -- after the full recorded world fingerprint and difficulty are verified.
    if plan.Mission ~= settings.Mission then
        local copy = HTTP:JSONDecode(HTTP:JSONEncode(plan))
        copy.MissionLabelRepairedFrom, copy.Mission = plan.Mission, settings.Mission
        local stored, err = writeJSON(profilePath(copy.Name), copy)
        assert(stored, "Cannot save corrected mission label: " .. tostring(err))
        sessionProfiles[copy.Name], sessionOnlyProfiles[copy.Name] = copy, nil
        plan = copy
    end
    return plan
end
local api = {now = os.clock, spawn = task.spawn, describe = describe, distance = distance, purchaseDistance = purchaseDistance,
    cash = cash,
    vector = vector, cframe = function(v) return {v:GetComponents()} end,
    identities = identities, slotName = slotName, loadout = loadout, level = level,
    activation = activation, baseLevel = baseLevel, reactorSnapshot = reactorSnapshot,
    cost = cost, confirm = confirm, previous = previous, resolve = resolve, ready = ready, send = send,
    ended = function() return ended end, wave = function() return wave end,
    waveAge = function() return os.clock() - waveStarted end, map = mapSignature,
    prestart = function() return wave == 0 and not ended end, startMatch = startMatch,
    canCapture = function() return type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" end,
    fresh = function()
        for _, o in ipairs(candidates()) do
            local name = o:GetAttribute("Name")
            if owned(o) and name ~= "Base" and name ~= "Hardpoint" then return false end
        end
        return true
    end,
    backup = function(record)
        env.LastContractDraft = record
        return writeJSON(ROOT .. "/draft.json", record)
    end,
    save = saveProfile, validate = validate}
api.related = function(a, b, plan)
    if a.Action == "Reactor" and b.Action == "Reactor" then return true end
    if a.Action == "Base" and b.Action == "Base" then return a.Value == b.Value end
    local function same(x, y)
        if not x or not y then return false end
        if x == y then return true end
        local left, right = plan.Refs[x], plan.Refs[y]
        return left and right and left.Name == right.Name and purchaseDistance(left.Position, right.Position) < 0.35
    end
    if same(a.Ref or a.Target, b.Ref or b.Target) then return true end
    if a.Action == "Sell" and (b.Action == "Place" or b.Action == "Install") then
        local d = plan.Refs[a.Target]
        return d and purchaseDistance(d.Position, b.Position) < 1.5
    end
    if (a.Action == "Place" or a.Action == "Install") and (b.Action == "Place" or b.Action == "Install") then
        return purchaseDistance(a.Position, b.Position) < 1.5
    end
    return false
end
api.recover = function(s, f)
    if os.clock() - f.Sent < 12 or (f.Tries or 1) >= 3 then return false end
    if s.Action == "Reactor" and s.Command == "overdrive" then return false end
    if s.Action == "Place" or s.Action == "Install" then
        if not f.CashKnown or f.CashDebited then return false end
        if wave <= (f.SentWave or wave) then return false end
        for _, o in ipairs(candidates()) do
            if owned(o) and o:GetAttribute("Name") == s.Name and purchaseDistance(position(o), s.Position) < 1.5
                and (not f.Before[o] or purchaseDistance(position(o), s.Position) < 0.35) then return false end
        end
    end
    return true
end
api.report = function(entry)
    matchCache.RecoveryLog = matchCache.RecoveryLog or {}
    entry.Time, entry.Cash = os.time(), cash()
    table.insert(matchCache.RecoveryLog, entry)
    if #matchCache.RecoveryLog > 30 then table.remove(matchCache.RecoveryLog, 1) end
    writeJSON(ROOT .. "/replay-diagnostics.json", {Macro = C.Plan and C.Plan.Name, Events = matchCache.RecoveryLog})
end
api.cashTracked = function() return api.CashConnection ~= nil end
api.watchCash = function()
    if api.CashConnection then return end
    local stats = player:FindFirstChild("leaderstats")
    local balance = stats and stats:FindFirstChild("Cash")
    if balance then
        local lastBalance = tonumber(balance.Value)
        api.CashConnection = connect(balance:GetPropertyChangedSignal("Value"), function()
            local current = tonumber(balance.Value)
            C.ObserveCash(lastBalance, current)
            lastBalance = current
        end)
    end
end
C = openCore(api)
C.ClientReady = stage == "Lobby"
C.RuntimeVersion = RUNTIME_VERSION
C.Farming = armed and requested == "Replay"
C.SessionId = tostring(game.PlaceId) .. ":" .. tostring(game.JobId)
if liveRecording then
    for k, v in pairs(liveRecording) do C[k] = v end
    C.Status = "Recording restored in this match; pending requests retained"
end
if liveReplay then
    for k, v in pairs(liveReplay) do C[k] = v end
    C.UsedObjects = C.UsedObjects or {}
    C.Status = "Farming restored in this match; replay position retained"
    C.PerformancePending = settings.Performance == true
end
if restoredSettingsError then
    armed, requested, resume, C.Farming = false, nil, false, false
    C.Status = restoredSettingsError
end
env.LastContractFarm = C

-- One recording hook per session. Unrelated calls go straight to the original
-- namecall before any helper, lookup, or nested Instance method runs.
local allowed = {TowerPlacement = true, HardpointTowerPlacement = true, TowerUpgrade = true, TowerSell = true,
    ChangeTowerFiremode = true, AbilityTowerActivate = true, BaseUpgrade = true, Reactor = true}
local function installHook()
    if not api.canCapture() then return false end
    if type(env.LastContractCaptureHook) == "table" and env.LastContractCaptureHook.Version == 2 then return true end
    local events = findEvents()
    assert(events, "Game remotes are not loaded")
    local routes = {}
    for name in pairs(allowed) do
        local remote = events:FindFirstChild(name)
        if remote then
            -- Native dot calls do not depend on the thread's namecall method.
            routes[remote] = {Method = name == "TowerUpgrade" and "InvokeServer" or "FireServer",
                Call = name == "TowerUpgrade" and remote.InvokeServer or remote.FireServer, Name = name}
        end
    end
    local old
    local callback = function(self, ...)
        local method = getnamecallmethod()
        local worker = env.LastContractFarm
        if not worker or worker.Mode ~= "Record" or (method ~= "FireServer" and method ~= "InvokeServer") then
            return old(self, ...)
        end
        local route = routes[self]
        if not route or route.Method ~= method or (checkcaller and checkcaller()) then return old(self, ...) end
        local args, step = table.pack(...), nil
        local ok, captured = pcall(worker.Capture, route.Name, args)
        if ok then step = captured
        else
            worker.Backup(); worker.Mode = "Idle"
            worker.Status = "Recording stopped; draft retained: " .. tostring(captured)
        end
        -- Capture can call other Instance methods. Forward explicitly through
        -- the cached native method, never through the now-changed namecall.
        local result = table.pack(pcall(route.Call, self, table.unpack(args, 1, args.n)))
        if step then worker.Returned(step, result[1], {table.unpack(result, 2, result.n)}) end
        if not result[1] then error(result[2], 0) end
        return table.unpack(result, 2, result.n)
    end
    old = hookmetamethod(game, "__namecall", newcclosure and newcclosure(callback) or callback)
    env.LastContractCaptureHook = {Version = 2}
    return true
end
if liveRecording and C.Mode == "Record" then installHook() end

local autoAbilities = {LastPoll = -math.huge}
matchCache.AbilityAttempts = matchCache.AbilityAttempts or setmetatable({}, {__mode = "k"})
function autoAbilities.Aim(tower)
    local enemies = workspace:FindFirstChild("Enemies")
    local origin, best, nearest = position(tower), nil, math.huge
    for _, enemy in ipairs(enemies and enemies:GetChildren() or {}) do
        local health = tonumber(enemy:GetAttribute("Health"))
        local p = (not health or health > 0) and position(enemy) or nil
        local d = p and distance(origin, p) or math.huge
        if d < nearest then best, nearest = p, d end
    end
    return best and CFrame.new(table.unpack(best)) or nil
end
function autoAbilities.Poll()
    if not alive or stage ~= "Match" or not C.ClientReady or ended or manualReturnPending
        or wave == 0 or not settings.AutoAbilities or settings.AbilitiesPaused then return end
    if os.clock() - autoAbilities.LastPoll < 0.2 then return end
    autoAbilities.LastPoll = os.clock()
    local cfg, seen, available, sent = config(), {}, 0, 0
    if not cfg or type(cfg.Abilites) ~= "table" then C.AbilityStatus = "Ability configuration unavailable"; return end
    local queued = workspace:FindFirstChild("DisplayTowers")
    for _, tower in ipairs(candidates()) do
        if not seen[tower] and tower.Parent and owned(tower) and (not queued or not tower:IsDescendantOf(queued)) then
            seen[tower] = true
            local data = cfg.Towers[tower:GetAttribute("Name")]
            local upgrade = data and data["Lvl" .. tostring(level(tower))]
            local last = matchCache.AbilityAttempts[tower]
            local abilities = upgrade and upgrade.Abilities or {}
            for _, ability in ipairs(abilities) do if cfg.Abilites[ability] then available = available + 1 end end
            for offset = 1, #abilities do
                local i = ((last and last.Next or 1) + offset - 2) % #abilities + 1
                local ability = abilities[i]
                local definition = cfg.Abilites[ability]
                local cooldown = definition and tonumber(definition.CD)
                if cooldown then
                    if os.time() - (tonumber(activation(tower)) or 0) >= cooldown
                        and (not last or os.clock() - last.At >= 0.5) then
                        local aim = ability:find("MissileLaunch", 1, true) and autoAbilities.Aim(tower) or nil
                        if not ability:find("MissileLaunch", 1, true) or aim then
                            local nextIndex = i % #upgrade.Abilities + 1
                            matchCache.AbilityAttempts[tower] = {At = os.clock(), Next = nextIndex}
                            local ok, why = pcall(function()
                                if aim then event("AbilityTowerActivate"):FireServer(tower, ability, aim)
                                else event("AbilityTowerActivate"):FireServer(tower, ability) end
                            end)
                            if ok then sent = sent + 1; C.AbilityError = nil else C.AbilityError = tostring(why) end
                            break -- The game shares one activation timestamp per tower.
                        end
                    end
                end
            end
        end
    end
    C.AbilityStatus = tostring(available) .. " abilities detected · " .. (C.AbilityError or "activate when ready")
    C.AbilitySends = (C.AbilitySends or 0) + sent
end

-- Reversible replay visuals: models remain available for identification and confirmation.
local visualSaved, visualsActive, renderChanged = {}, false, false
local function changeVisual(o, property, forced, watch)
    local ok, before = pcall(function() return o[property] end)
    if not ok or before == nil then return end
    local entry = visualSaved[o]
    if not entry then entry = {}; visualSaved[o] = entry end
    if entry[property] then return end
    local v = {Before = before, Writing = true}; entry[property] = v
    pcall(function() o[property] = forced end); v.Writing = false
    if watch then
        table.insert(visualConnections, o:GetPropertyChangedSignal(property):Connect(function()
            if not visualsActive or v.Writing then return end
            local read, current = pcall(function() return o[property] end)
            if read and current ~= forced then
                v.Before, v.Writing = current, true
                pcall(function() o[property] = forced end); v.Writing = false
            end
        end))
    end
end
local function hideVisual(o)
    if o:IsA("BasePart") then changeVisual(o, "LocalTransparencyModifier", 1, false); changeVisual(o, "CastShadow", false, false)
    elseif o:IsA("ParticleEmitter") or o:IsA("Beam") or o:IsA("Trail") or o:IsA("Light")
        or o:IsA("Highlight") or o:IsA("BillboardGui") or o:IsA("SurfaceGui") then changeVisual(o, "Enabled", false, true)
    end
end
local function restoreVisuals()
    C.PerformancePending = false
    visualsActive = false
    for _, c in ipairs(visualConnections) do c:Disconnect() end
    visualConnections = {}
    local failed = {}
    for o, props in pairs(visualSaved) do
        for k, v in pairs(props) do
            local ok = pcall(function() o[k] = v.Before end)
            if not ok and o.Parent then failed[o] = failed[o] or {}; failed[o][k] = v end
        end
    end
    visualSaved = failed
    if renderChanged then
        local ok = pcall(function() Run:Set3dRenderingEnabled(true) end)
        renderChanged = not ok
    end
    C.VisualStatus = renderChanged and "Rendering restore failed; press Restore visuals again" or "Visuals restored"
end
local function performance()
    C.PerformancePending = false
    if visualsActive then return end
    visualsActive = true
    renderChanged = pcall(function() Run:Set3dRenderingEnabled(false) end)
    for _, o in ipairs(workspace:GetDescendants()) do hideVisual(o) end
    table.insert(visualConnections, workspace.DescendantAdded:Connect(function(o) if visualsActive then hideVisual(o) end end))
    C.VisualStatus = renderChanged and "3D rendering off" or "Effects hidden; 3D toggle unsupported"
end
C.RestoreVisuals = restoreVisuals

-- Use the real loading Skip callback. Hiding the overlay alone cannot stop PreloadAsync.
local skippedLoading, skipAttempts, loadingSeen, loadingActiveAt = {}, {}, {}, {}
local function skipLoading()
    local loading = gui:FindFirstChild("Loading")
    if not loading or skippedLoading[loading] then return end
    local frame = loading:FindFirstChild("LoadingFrame")
    local button = frame and frame:FindFirstChild("Skip")
    if not button then return end
    loadingSeen[loading] = loadingSeen[loading] or os.clock()
    local loadingText = frame:FindFirstChild("LoadingText")
    if loadingText and loadingText.Text == "Loaded" then
        skippedLoading[loading] = true; C.LoadingStatus = "Loading finished"; return
    end
    if button.Text == "SKIPPED" then
        skippedLoading[loading] = true; C.LoadingStatus = "Skip already requested; waiting for game cleanup"; return
    end
    if type(getconnections) ~= "function" then
        C.LoadingStatus = "Loading skip needs getconnections; use the game's Skip button"
        return
    end
    local status = loading:FindFirstChild("Status")
    local loader = status and status:FindFirstChild("LocalScript")
    if loader and not loader.Enabled then loadingActiveAt[loading] = nil; C.LoadingStatus = "Waiting for loading script"; return end
    loadingActiveAt[loading] = loadingActiveAt[loading] or os.clock()
    -- The real match loader enables Status after 4 seconds and reveals Skip
    -- another 2 seconds later. Let both stages initialize before invoking it.
    local elapsed = os.clock() - loadingSeen[loading]
    if elapsed < 7 or os.clock() - loadingActiveAt[loading] < 3 then
        C.LoadingStatus = "Loading skip waits for initialization (7 seconds minimum)"; return
    end
    if os.clock() - (skipAttempts[loading] or -math.huge) < 0.5 then return end
    skipAttempts[loading] = os.clock()
    local ok, list = pcall(getconnections, button.Activated)
    if ok then
        for _, c in ipairs(list) do
            if c.Enabled ~= false and c.Connected ~= false then
                if c.Function then pcall(c.Function)
                elseif c.Fire then pcall(function() c:Fire() end) end
            end
        end
    end
    if button.Text == "SKIPPED" then
        skippedLoading[loading] = true
        -- The game's preload coroutine must finish its current asset and run
        -- its own cleanup. Do not hide or disable the loading ScreenGui here.
        C.LoadingStatus = "Skip requested; waiting for game loading cleanup"
    end
end

local QUEUE_CODE = 'local e=(getgenv and getgenv()) or _G; if isfile and isfile("Last Contract Tower Defense/settings.json") then local h=game:GetService("HttpService"); local ok,s=pcall(function() return h:JSONDecode(readfile("Last Contract Tower Defense/settings.json")) end); if ok and s.Armed and isfile("Last Contract Tower Defense/runtime.lua") then local c=e.LastContractFarm; local session=tostring(game.PlaceId)..":"..tostring(game.JobId); if c and c.Running and c.SessionId==session and c.RuntimeVersion=="2026-10-03-7" then return end; e.LastContractResume=true; local f,err=loadstring(readfile("Last Contract Tower Defense/runtime.lua")); if f then f() else warn(err) end end end'
local function continuity()
    if not hasFiles or type(queueTeleport) ~= "function" or not isfile(ROOT .. "/runtime.lua") then
        return false, "Auto-join requires file APIs and queue_on_teleport; rerun manually after teleport"
    end
    if env.LastContractRuntimePersisted == false then return false, "Runtime could not be saved; auto-join disabled to avoid running an older script" end
    local readable, stored = pcall(readfile, ROOT .. "/runtime.lua")
    if not readable or not stored:find('local RUNTIME_VERSION = "' .. RUNTIME_VERSION .. '"', 1, true) then
        return false, "Saved runtime is outdated or unreadable; execute the current one-file script again"
    end
    if not queueInstalled then
        local ok, err = pcall(queueTeleport, QUEUE_CODE)
        if not ok then return false, "Teleport queue failed: " .. tostring(err) end
        queueInstalled = true
    end
    return true
end
local function arm(intent)
    settings.AbilitiesPaused = false
    settings.StartRecoveries = 0
    matchCache.RecoveryCounted = nil
    lobbyAttempts, lobbyLeaving = 0, false
    armed, requested = true, intent
    C.Farming = intent == "Replay"
    local ok, err = saveSettings()
    if not ok then armed, C.Farming = false, false; return false, "Cannot save continuation: " .. tostring(err) end
    local queued, why = continuity()
    if not queued then armed, C.Farming = false, false; saveSettings(); return false, why end
    return true
end
local rawStop = C.Stop
local flushPreferences
function C.Stop()
    settings.AbilitiesPaused = true
    armed, requested, busy, C.Farming = false, nil, false, false
    resume, initialized = false, true
    rawStop(); restoreVisuals()
    local ok, err = saveSettings()
    if not ok then C.Status = "Stopped locally; continuation settings could not be cleared: " .. tostring(err) end
    lobbySent, lobbyStartSent = nil, nil
    lobbyAttempts, lobbyLeaving, startMissingSince = 0, false, nil
    manualReturnPending = false
end
local function dispose(disarm)
    if not alive then return end
    if flushPreferences then flushPreferences() end
    if disarm then C.Stop() else rawStop(); restoreVisuals() end
    alive, C.Running = false, false
    for _, c in ipairs(connections) do c:Disconnect() end
    for _, c in ipairs(C.MenuConnections or {}) do c:Disconnect() end
    if C.Screen then C.Screen:Destroy() end
end
function C.Destroy() dispose(true) end
function C.Detach() dispose(false) end
local function attempt(fn)
    local ok, err = pcall(fn)
    if not ok then C.Status = tostring(err); return false end
    return true
end
local function beginRecord(name)
    if stage == "Lobby" then
        assert(C.Mode == "Idle" and not armed, "Stop before starting a new operation")
        settings.RecordName = unusedName(name)
        local ok, err = arm("Record"); assert(ok, err)
        C.Status = "Creating solo match; recording will begin after loading"
    else
        assert(not ended, "Match has ended; use Return to lobby before recording")
        installHook()
        C.StartRecord(unusedName(name), settings.Mission, difficulty())
        settings.AbilitiesPaused = false
        settings.RecordName = C.Record.Name
        settings.Difficulty = C.Record.Difficulty
        settings.Map, settings.Loadout = C.Record.Map, C.Record.Loadout
        armed, requested = false, nil; saveSettings()
    end
end
local function beginReplay()
    assert(C.Mode == "Idle" and not armed, "Stop before starting replay")
    local plan = loadProfile(settings.Selected)
    local canRepair = stage == "Match" and not ended and selection.ConfirmedHere
    local valid, why = selectedPlan(plan, canRepair)
    assert(valid, why)
    if stage == "Match" and not ended then
        assert(api.fresh(), "Start farming in a fresh match before purchasing towers")
        plan = verifyMissionLabel(plan)
        C.StartReplay(plan)
        if settings.Performance then if C.ClientReady then performance() else C.PerformancePending = true end end
    end
    selection.CachedName, selection.CachedProfile = settings.Selected, plan
    settings.Map, settings.Loadout = plan.Map, plan.Loadout
    local ok, err = arm("Replay")
    if not ok and stage == "Lobby" then error(err) end
    if not ok then C.Status = "Replaying this match only. " .. tostring(err) end
    if stage == "Lobby" then C.Status = "Creating solo match for " .. plan.Name end
end

local results = readJSON(ROOT .. "/results.json") or {Profiles = {}}
if type(results.Profiles) ~= "table" then results.Profiles = {} end
local reported, returning, resultAt = false, false, nil
if matchCache.Result then
    reported, ended, resultAt = true, true, os.clock()
    C.ResultStatus = matchCache.Result.Status
end
if liveLifecycle then returning, resultAt = liveLifecycle.Returning or false, liveLifecycle.ResultAt or resultAt end
function C.GetLifecycle()
    return {Armed = armed, Intent = requested, Lobby = currentLobby, LobbySent = lobbySent, LobbyStartSent = lobbyStartSent,
        LobbyAttempts = lobbyAttempts, LobbyLeaving = lobbyLeaving, Initialized = initialized, Returning = returning,
        ResultAt = resultAt, NextReturn = nextReturn, ManualReturnPending = manualReturnPending,
        Reactor = reactor, ReactorVersion = reactorVersion}
end
findStartVote = function()
    if wave > 0 or ended then return nil end
    if startVote and not matchCache.Closed[tostring(startVote)] then return startVote end
    for id, kind in pairs(matchCache.Votes) do
        if kind == "intermission" and not matchCache.Closed[tostring(id)] then return id end
    end
    -- The create event can precede script execution. Recover only actual
    -- intermission frames, including a hidden frame whose vote is still live.
    for _, name in ipairs({"Base", "BaseMobile"}) do
        local b = gui:FindFirstChild(name)
        local info = b and b:FindFirstChild("GameInfo")
        for _, o in ipairs(info and info:GetChildren() or {}) do
            local suffix = o.Name:match("^Vote(.+)$")
            local title = o:FindFirstChild("TextLabel")
            if suffix and title then
                local id = tonumber(suffix) or suffix
                local text = title.Text:upper()
                if not matchCache.Closed[tostring(id)] and (matchCache.Votes[id] == "intermission" or matchCache.Votes[suffix] == "intermission" or text:find("INTERMISSION",1,true)) then
                    matchCache.Votes[id] = "intermission"
                    return id
                end
            end
        end
    end
end
local function matchResult(lost, tokens, mode, xp)
    if reported then return end
    reported, ended, resultAt = true, true, os.clock()
    local kind = C.Mode == "Replay" and "Replay" or ((C.Mode == "Record" or C.Mode == "Finishing") and "Recording" or "Manual")
    local name = kind == "Replay" and C.Plan.Name or kind == "Recording" and C.Record.Name or "Manual"
    local key = kind .. ":" .. name .. ":" .. tostring(mode)
    local stats = results.Profiles[key] or {Wins = 0, Losses = 0}
    stats[lost and "Losses" or "Wins"] = stats[lost and "Losses" or "Wins"] + 1
    results.Profiles[key] = stats
    results.Last = {Result = lost and "LOSE" or "WIN", Kind = kind, Macro = name, Wave = wave, Tokens = tokens,
        XP = xp, Difficulty = mode, Step = C.Step, Total = C.Plan and #C.Plan.Steps or C.Record and #C.Record.Steps or 0,
        Wait = C.Status, Time = os.time()}
    writeJSON(ROOT .. "/results.json", results)
    C.ResultStatus = string.format("%s · %dW / %dL · %.1f%%", results.Last.Result, stats.Wins, stats.Losses, 100 * stats.Wins/(stats.Wins+stats.Losses))
    matchCache.Result = {Status = C.ResultStatus}
    restoreVisuals()
    if kind == "Recording" then C.Mode = "Finishing" end
end
local function attachEvents()
    local events = findEvents()
    if not events then return false end
    if stage == "Lobby" then
        local r = events:FindFirstChild("LobbyActions")
        if not r then return false end
        connect(r.OnClientEvent, function(lobbies)
            currentLobby = nil
            for _, l in pairs(lobbies) do
                if type(l) == "table" and table.find(l.Players or {}, player.Name) then currentLobby = l; break end
            end
            if lobbyLeaving and not currentLobby then lobbyLeaving = false; lobbySent = nil; lobbyUIAfter = os.clock() + 2 end
        end)
    else
        for _, name in ipairs({"MakeVote", "GameStats", "GameOver"}) do if not events:FindFirstChild(name) then return false end end
        connect(events.MakeVote.OnClientEvent, function(id, action, kind, required, votes)
            matchCache.VotePayloads = matchCache.VotePayloads or {}
            if action == "create" or action == "update" then
                matchCache.Closed[tostring(id)] = nil
                if kind then matchCache.Votes[id] = kind end
                if kind == "intermission" and required ~= nil then matchCache.VotePayloads[id] = {id, "create", kind, required, votes or 0} end
                if matchCache.Votes[id] == "intermission" and wave == 0 then startVote = id end
            elseif action == "close" then
                matchCache.Votes[id], matchCache.Closed[tostring(id)] = nil, true
                matchCache.VotePayloads[id] = nil
                if id == startVote then startVote = nil end
            end
        end)
        connect(events.GameStats.OnClientEvent, function(kind, text, numeric)
            if string.upper(tostring(kind)) == "WAVE" then
                local n = tonumber(numeric) or tonumber(tostring(text):match("%d+"))
                if n and n > wave then wave, waveStarted = n, os.clock(); matchCache.Wave, matchCache.WaveStarted = wave, waveStarted end
            end
        end)
        connect(events.GameOver.OnClientEvent, matchResult)
        api.watchCash()
        if events:FindFirstChild("Reactor") then
            connect(events.Reactor.OnClientEvent, function(data) reactor, reactorVersion = data, reactorVersion + 1 end)
        end
        -- Attach before waiting for the rest of the client to initialize.
        scanStatic()
        -- Recording installs its hook when Record round is pressed/resumed.
    end
    return true
end

local controllerStableAt, controllerMap, repairedControllers = nil, nil, {}
local deliveredVotes, nextVoteUIRepair = {}, 0
local function gameVoteListeners()
    local out = {}
    if type(getconnections) ~= "function" then return out, false end
    local events = findEvents(); local r = events and events:FindFirstChild("MakeVote")
    if not r then return out, false end
    local ok, list = pcall(getconnections, r.OnClientEvent)
    if not ok then return out, false end
    for _, c in ipairs(list) do
        if type(c.Function) == "function" and not ownCallbacks[c.Function] and c.Enabled ~= false and c.Connected ~= false then
            table.insert(out, c.Function)
        end
    end
    return out, true
end
prepareClient = function()
    if stage ~= "Match" then C.ClientReady = true; return true end
    local map = workspace:FindFirstChild("Map")
    local paths = map and map:FindFirstChild("Waypoints")
    local scripts = player:FindFirstChild("PlayerScripts")
    local uiController = scripts and scripts:FindFirstChild("PlayerGuiControllerNew")
    local worldController = scripts and scripts:FindFirstChild("PlayerController")
    local reason
    if not paths or #paths:GetChildren() == 0 then reason = "Waiting for map Waypoints"
    elseif not uiController or not worldController then reason = "Waiting for game controllers"
    else
        local disabled = not uiController.Enabled or not worldController.Enabled
        if disabled then
            local loader = scripts:FindFirstChild("Loader")
            local prerequisites = loader and loader.Enabled and gui:FindFirstChild("Base") and gui:FindFirstChild("BaseMobile")
                and gui:FindFirstChild("Reactor") and config() and workspace:FindFirstChild("Towers") and workspace:FindFirstChild("DisplayTowers")
            if not prerequisites then controllerStableAt = nil; reason = "Waiting for controller prerequisites"
            else
                if controllerMap ~= map then controllerMap, controllerStableAt = map, os.clock() end
                controllerStableAt = controllerStableAt or os.clock()
                reason = "Waiting for game UI loader (8-second grace)"
                if not ended and os.clock() - controllerStableAt >= 8 then
                    -- Supplied Loader waits for ChildAdded before checking
                    -- existing Waypoints. Recover only its two disabled scripts
                    -- after the map/UI are present; never restart enabled ones.
                    for _, scriptObject in ipairs({uiController, worldController}) do
                        if not scriptObject.Enabled and not repairedControllers[scriptObject] then
                            repairedControllers[scriptObject] = true
                            local ok, err = pcall(function() scriptObject.Enabled = true end)
                            if not ok then C.StartupError = "Controller recovery failed: " .. tostring(err) end
                        end
                    end
                    reason = "Controllers enabled; waiting for vote listener"
                end
            end
        else
            controllerStableAt = nil
            local listeners, inspectable = gameVoteListeners()
            if inspectable and #listeners == 0 then reason = "Waiting for game's Start-vote listener" end
        end
    end
    local loading = gui:FindFirstChild("Loading")
    if not reason and loading then
        local frame = loading:FindFirstChild("LoadingFrame")
        local text = frame and frame:FindFirstChild("LoadingText")
        if (text and text.Text ~= "Loaded") or (loading.Enabled and not text) then reason = "Waiting for game loading cleanup" end
    end
    C.ClientReady = not reason
    C.StartupStatus = C.StartupError or reason or (findStartVote() and "Game ready; Start vote available" or wave > 0 and "Match running" or "Game ready; Start vote not received")
    return C.ClientReady
end
repairStartUI = function()
    if stage ~= "Match" or ended or wave > 0 or os.clock() < nextVoteUIRepair then return end
    nextVoteUIRepair = os.clock() + 0.5
    local id = findStartVote()
    local payload = id and matchCache.VotePayloads and matchCache.VotePayloads[id]
    if not payload then return end
    for _, name in ipairs({"Base", "BaseMobile"}) do
        local b = gui:FindFirstChild(name); local info = b and b:FindFirstChild("GameInfo")
        if b and b.Enabled and info and info:FindFirstChild("Vote" .. tostring(id)) then return end
    end
    local listeners = gameVoteListeners()
    for _, fn in ipairs(listeners) do
        local last = deliveredVotes[fn]
        if not last or last.Id ~= id or (last.Attempts < 3 and os.clock() - last.At >= 5) then
            local attempts = last and last.Id == id and last.Attempts + 1 or 1
            deliveredVotes[fn] = {Id = id, At = os.clock(), Attempts = attempts}
            -- Deliver the captured server vote to the game's late listener.
            -- Exclude our callback to avoid recursion. Never fabricate an ID,
            -- fire a network vote, or replay skip-wave events.
            local ok, err = pcall(fn, table.unpack(payload, 1, 5))
            if not ok then C.StartupError = "Game Start-vote UI failed: " .. tostring(err)
            else C.StartupError = nil; C.StartupStatus = "Restored game's Start-vote UI" end
        end
    end
end

-- Listen before building the panel; a vote/result can arrive during UI startup.
local initialEventsReady = attachEvents()

-- UI: compact controls shared by both places.
local colors = {Bg = Color3.fromRGB(15,20,27), Panel = Color3.fromRGB(26,35,45), Text = Color3.fromRGB(233,240,245),
    Muted = Color3.fromRGB(157,175,190), Accent = Color3.fromRGB(78,209,166)}
local function make(class, parent, props)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent; return o
end
local function corner(o) make("UICorner", o, {CornerRadius = UDim.new(0,8)}) end
local screen = make("ScreenGui", gui, {Name = "LastContractFarm", ResetOnSpawn = false, DisplayOrder = 10000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
C.Screen = screen
local root = make("Frame", screen, {Size = UDim2.fromOffset(390,655), Position = UDim2.new(0,22,0.5,0), AnchorPoint = Vector2.new(0,0.5), BackgroundColor3 = colors.Bg, BorderSizePixel = 0})
if type(settings.PanelPosition) == "table" and type(settings.PanelPosition.X) == "number" and type(settings.PanelPosition.Y) == "number" then
    root.Position = UDim2.fromOffset(settings.PanelPosition.X, settings.PanelPosition.Y)
end
corner(root)
make("UIStroke", root, {Color = Color3.fromRGB(49,65,80), Thickness = 1})
local scale = make("UIScale", root, {Scale = 1})
local function fitPanel()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local view = camera.ViewportSize
    local width, height = 390 * scale.Scale, root.Size.Y.Offset * scale.Scale
    local left = root.Position.X.Scale * view.X + root.Position.X.Offset
    local center = root.Position.Y.Scale * view.Y + root.Position.Y.Offset
    left = math.max(8, math.min(left, math.max(8, view.X-width-8)))
    center = math.max(height/2+8, math.min(center, math.max(height/2+8, view.Y-height/2-8)))
    if root.Position.X.Scale ~= 0 or root.Position.Y.Scale ~= 0 or root.Position.X.Offset ~= left or root.Position.Y.Offset ~= center then
        root.Position = UDim2.fromOffset(left, center)
    end
end
local function label(parent, text, y, height, size)
    return make("TextLabel", parent, {Text = text, Position = UDim2.fromOffset(16,y), Size = UDim2.new(1,-32,0,height), BackgroundTransparency = 1,
        Font = Enum.Font.Gotham, TextSize = size or 12, TextColor3 = colors.Text, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true})
end
local header = make("Frame", root, {Size = UDim2.new(1,0,0,65), BackgroundTransparency = 1, Active = true})
label(header, "LAST CONTRACT", 10,25,19)
local subtitle = label(header, stage .. " · Record once, farm your strategy", 36,20,11); subtitle.TextColor3 = colors.Muted
local body = make("Frame", root, {Position = UDim2.fromOffset(0,65), Size = UDim2.new(1,0,1,-65), BackgroundTransparency = 1})
local function button(parent, text, x, y, w, h, accent, fn)
    local o = make("TextButton", parent, {Text = text, Position = UDim2.fromOffset(x,y), Size = UDim2.fromOffset(w,h), BackgroundColor3 = accent and colors.Accent or colors.Panel,
        BorderSizePixel = 0, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = accent and colors.Bg or colors.Text, AutoButtonColor = true})
    corner(o)
    if fn then connect(o.Activated, function() attempt(fn) end) end
    return o
end
local preferencesDirtyAt
local function dirtyPreferences() preferencesDirtyAt = os.clock() end
local minimized = settings.PanelMinimized == true
body.Visible = not minimized
root.Size = UDim2.fromOffset(390,minimized and 65 or 655)
button(header, "−", 309,13,27,27,false,function()
    minimized = not minimized; body.Visible = not minimized; root.Size = UDim2.fromOffset(390,minimized and 65 or 655)
    settings.PanelMinimized = minimized; dirtyPreferences()
end)
button(header, "×", 347,13,27,27,false,C.Destroy)
local missions = {"FirstContact", "HospitalDefense", "GroundZero"}
local modes = {"Mild", "Severe", "Lethal", "Terminal"}
local function idle() assert(C.Mode == "Idle" and not armed, "Stop before changing the profile or lobby") end
local missionButton, modeButton
missionButton = button(body, "Mission: " .. settings.Mission,16,8,225,34,false,function()
    idle(); local i = table.find(missions, settings.Mission) or 1; settings.Mission = missions[i % #missions + 1]; selection.ConfirmedHere = true; saveSettings()
end)
modeButton = button(body, settings.Difficulty,249,8,125,34,false,function()
    idle(); local i = table.find(modes, settings.Difficulty) or 1; settings.Difficulty = modes[i % #modes + 1]; saveSettings()
end)
label(body, "SAVED MACRO", 53,18,10).TextColor3 = colors.Muted
local profileMenu = make("ScrollingFrame", body, {Position = UDim2.fromOffset(16,109), Size = UDim2.fromOffset(358,155), CanvasSize = UDim2.fromOffset(0,0),
    ScrollBarThickness = 5, BackgroundColor3 = colors.Panel, BorderSizePixel = 0, Visible = false, ZIndex = 30})
corner(profileMenu)
local menuConnections = {}
C.MenuConnections = menuConnections
local profileButton
profileButton = button(body, settings.Selected or "Choose recorded macro ▾",16,74,358,34,false,function()
    idle()
    for _, c in ipairs(menuConnections) do c:Disconnect() end; menuConnections = {}; C.MenuConnections = menuConnections
    for _, o in ipairs(profileMenu:GetChildren()) do if o:IsA("TextButton") then o:Destroy() end end
    local names = profileNames()
    for i, name in ipairs(names) do
        local b = button(profileMenu, name,5,4+(i-1)*31,345,28,false,nil); b.ZIndex = 31
        table.insert(menuConnections, b.Activated:Connect(function()
            attempt(function()
                idle(); local p = loadProfile(name); assert(p, "Profile unreadable")
                settings.Selected = name
                settings.Map, settings.Loadout = p.Map, p.Loadout
                profileMenu.Visible = false; saveSettings(); C.Status = "Loaded " .. name .. " · " .. tostring(p.Mission) .. " / " .. tostring(p.Difficulty) .. " · destination kept"
            end)
        end))
    end
    profileMenu.CanvasSize = UDim2.fromOffset(0, #names*31+8)
    profileMenu.Visible = not profileMenu.Visible
    if #names == 0 then C.Status = "No saved profiles yet. Record a fresh round." end
end)
local nameBox = make("TextBox", body, {Text = settings.NameBoxText, PlaceholderText = "Name for your next recording", Position = UDim2.fromOffset(16,120), Size = UDim2.fromOffset(358,33),
    BackgroundColor3 = colors.Panel, BorderSizePixel = 0, TextColor3 = colors.Text, PlaceholderColor3 = colors.Muted, Font = Enum.Font.Gotham, TextSize = 12, ClearTextOnFocus = false})
corner(nameBox)
connect(nameBox:GetPropertyChangedSignal("Text"), function() settings.NameBoxText = nameBox.Text; dirtyPreferences() end)
connect(root:GetPropertyChangedSignal("Position"), function()
    if root.Position.X.Scale == 0 and root.Position.Y.Scale == 0 then
        settings.PanelPosition = {X = root.Position.X.Offset, Y = root.Position.Y.Offset}; dirtyPreferences()
    end
end)
flushPreferences = function()
    if not preferencesDirtyAt then return true end
    local ok, err = saveSettings()
    if ok then preferencesDirtyAt = nil else C.PreferenceError = "Settings save failed: " .. tostring(err) end
    return ok, err
end
button(body, "Record round",16,166,175,37,false,function() beginRecord(nameBox.Text) end)
button(body, "Recover draft",199,166,175,37,false,function()
    idle(); local d = env.LastContractDraft or readJSON(ROOT .. "/draft.json") or readJSON(ROOT .. "/draft.json.bak")
    assert(d and d.Game == "LastContract" and type(d.Steps) == "table" and #d.Steps > 0, "No recoverable draft")
    local copy = HTTP:JSONDecode(HTTP:JSONEncode(d)); copy.Name = unusedName(d.Name .. " recovered")
    -- Partial drafts stay partial; do not claim they are a complete round strategy.
    local ok, err = saveProfile(copy)
    C.Status = ok and (copy.Complete and "Recovered completed macro" or "Recovered partial draft; not eligible for farming") or "Recovery retained in session: " .. tostring(err)
end)
local farmButton = button(body, "Start farm",16,214,175,40,true,beginReplay)
button(body, "Stop · F8",199,214,175,40,false,C.Stop)
button(body, "Restore visuals",16,267,175,33,false,restoreVisuals)
local perfButton = button(body, "Replay low graphics: ON",199,267,175,33,false,function()
    settings.Performance = not settings.Performance
    if C.Mode == "Replay" and settings.Performance then performance() else restoreVisuals() end
    saveSettings()
end)
button(body, "Start match",16,313,175,34,false,function()
    assert(stage == "Match", "Use Start farm or Record round to create a lobby match")
    if C.Mode == "Replay" then
        C.PollPrebuy()
        C.Status = "Preparing recorded purchases before Start; " .. C.Status
        return
    end
    assert(#C.Pending == 0, "Wait for pending purchases to confirm before starting")
    local ok, message = startMatch(true)
    C.Status = message
end)
button(body, "Return to lobby",199,313,175,34,false,function()
    assert(stage == "Match", "Already in the lobby")
    if armed and requested == "Replay" then
        -- Abandon this round while preserving the user's continuous farm.
        rawStop(); restoreVisuals()
        manualReturnPending, returning, nextReturn = true, false, os.clock()
        local ok, err = saveSettings(); assert(ok, err)
        C.Status = "Returning to lobby; farming remains ON for the next match"
        return
    end
    C.Stop() -- retains any draft before leaving the current match
    C.Status = "Returning to lobby; draft retained"
    Teleport:Teleport(127750392812160, player)
end)
autoAbilities.Button = button(body, "Auto abilities: ON",16,358,358,30,false,function()
    settings.AutoAbilities = not (settings.AutoAbilities and not settings.AbilitiesPaused)
    settings.AbilitiesPaused = false
    local ok, why = saveSettings()
    C.Status = ok and (settings.AutoAbilities and "Auto abilities enabled; recorded ability steps stay ignored" or "Auto abilities disabled; recorded ability steps stay ignored") or "Ability setting save failed: " .. tostring(why)
end)
local statusCard = make("Frame", body, {Position = UDim2.fromOffset(16,397), Size = UDim2.fromOffset(358,79), BackgroundColor3 = colors.Panel, BorderSizePixel = 0})
corner(statusCard)
local statusLabel = label(statusCard, C.Status,5,69,12)
local progressLabel = label(body, "Idle",486,25,11)
local resultLabel = label(body, "No results this session",513,24,11)
local helpLabel = label(body, "Solo lobbies · loading skip · buys before wave 1 · no auto-skip",543,31,10); helpLabel.TextColor3 = colors.Muted
local drag, origin, offset
connect(header.InputBegan, function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        drag, origin, offset = i, i.Position, root.Position
        local endConnection
        endConnection = i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then drag = nil; endConnection:Disconnect() end end)
        table.insert(connections, endConnection)
    end
end)
connect(Input.InputChanged, function(i)
    if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i == drag) then
        local d = i.Position-origin
        root.Position = UDim2.new(offset.X.Scale,offset.X.Offset+d.X,offset.Y.Scale,offset.Y.Offset+d.Y)
        fitPanel()
    end
end)
connect(Input.InputBegan, function(i) if i.KeyCode == Enum.KeyCode.F8 then C.Stop() end end)
connect(player.OnTeleport, function(state)
    if state == Enum.TeleportState.Started and armed then
        if flushPreferences then flushPreferences() end
        local ok, err = saveSettings()
        if not ok then C.Status = "Could not save farm state before teleport: " .. tostring(err) end
        if C.Mode == "Record" or C.Mode == "Finishing" then C.Backup() end
        restoreVisuals(); continuity()
    elseif state == Enum.TeleportState.Failed then
        lobbyStartSent, returning = nil, false
        nextReturn = os.clock() + 10
        C.Status = "Teleport failed; retrying while farm remains active"
    end
end)
connect(Teleport.TeleportInitFailed, function(p, result, message)
    if p == player then returning, lobbyStartSent = false, nil; nextReturn = os.clock() + 10; C.Status = "Teleport failed: " .. tostring(message) end
end)

local readyEvents, lastStatic, lastUI, autoBeginAt = initialEventsReady, 0, 0, os.clock()
initialized = liveRecording ~= nil or liveReplay ~= nil or restoredSettingsError ~= nil
    or (liveLifecycle and liveLifecycle.Initialized == true)
local function currentWaveFromUI()
    for _, name in ipairs({"Base", "BaseMobile"}) do
        local b = gui:FindFirstChild(name)
        local h = b and b.Enabled and b:FindFirstChild("BaseHealth")
        local stats = h and h:FindFirstChild("Stats")
        local w = stats and stats:FindFirstChild("WAVE")
        local n = w and w.Text:upper():find("WAVE",1,true) and tonumber(w.Text:match("%d+"))
        if n and n > wave then wave, waveStarted = n, os.clock(); matchCache.Wave, matchCache.WaveStarted = wave, waveStarted end
    end
    -- Template victory text is not evidence of a finished round. Results are
    -- accepted from the GameOver event only.
    if wave == 0 then startVote = findStartVote() end
end
local function tickLobby()
    if not armed then return end
    if requested == "Replay" then
        local ok, why = selectedPlan(continuationPlan())
        if not ok then C.Stop(); C.Status = why; return end
    end
    -- Recover a lobby already visible before this script attached its listener.
    if not currentLobby and not lobbyLeaving and os.clock() >= lobbyUIAfter then
        local b = gui:FindFirstChild("BaseUI")
        local play = b and b:FindFirstChild("PLAY")
        local l = play and play:FindFirstChild("LobbyPlayers")
        local stats = l and l:FindFirstChild("txtLobbyStats")
        local start = l and l:FindFirstChild("btnStartGame")
        if l and l.Visible and stats and start then
            local m = stats.Text:match("MISSION:%s*([^%s]+)")
            local d = stats.Text:match("DIFFICULTY:%s*([^%s]+)")
            if m and d then
                for _, mission in ipairs(missions) do if mission:upper() == m:upper() then m = mission end end
                for _, mode in ipairs(modes) do if mode:upper() == d:upper() then d = mode end end
                currentLobby = {Owner = start.Visible and player.Name or "Another player", Mission = m, Difficulty = d,
                    MaxPlayers = stats.Text:match("MAX PLAYERS:%s*(%d+)"), Privacy = stats.Text:match("PRIVACY:%s*([^%s]+)")}
            end
        end
    end
    if lobbyLeaving then C.Status = "Waiting to leave previous lobby"; return end
    if currentLobby then
        if currentLobby.Owner ~= player.Name or currentLobby.Mission ~= settings.Mission or currentLobby.Difficulty ~= settings.Difficulty
            or (currentLobby.MaxPlayers and tonumber(currentLobby.MaxPlayers) ~= 1)
            or (currentLobby.Privacy and currentLobby.Privacy:upper() ~= "PRIVATE") then
            lobbyLeaving, lobbyUIAfter = true, os.clock() + 5
            event("LobbyActions"):FireServer("Leave")
            C.Status = "Leaving previous lobby to create the selected solo match"; return
        end
        if os.clock() >= nextReturn and (not lobbyStartSent or os.clock() - lobbyStartSent > 30) then
            event("LobbyActions"):FireServer("Start"); lobbyStartSent = os.clock()
            C.Status = "Joining " .. settings.Mission .. " · " .. settings.Difficulty
        end
    elseif not lobbySent or (os.clock() - lobbySent > 20 and lobbyAttempts < 3) then
        lobbyAttempts = lobbyAttempts + 1
        event("LobbyActions"):FireServer("Create", {Privacy = "Private", MaxPlayers = "1", Difficulty = settings.Difficulty, Mission = settings.Mission, TestPlace = false})
        lobbySent = os.clock(); C.Status = "Creating private solo lobby"
    elseif os.clock() - lobbySent > 20 then
        C.Stop(); C.Status = "No lobby confirmation after 3 attempts; check the game's lobby connection"
    end
end
local function autoBegin()
    if not resume or initialized then return end
    local s = readJSON(ROOT .. "/settings.json")
    if not s or not s.Armed then initialized = true; return end
    if s.Intent == "Replay" then
        local valid, why = selectedPlan(continuationPlan())
        if not valid then C.Stop(); C.Status = why; initialized = true; return end
    end
    if manualReturnPending then initialized = true; C.Status = "Restoring farm return to lobby"; return end
    if stage == "Lobby" then
        requested, armed = s.Intent, true
        C.Farming = requested == "Replay"
        local ok, why = continuity()
        if not ok then C.Stop(); C.Status = why else C.Status = "Saved farm state restored; creating next match" end
        initialized = true; return
    end
    if not C.ClientReady then
        C.Status = C.StartupStatus or "Waiting for game initialization"
        if os.clock() - autoBeginAt > 60 then initialized = true; C.Stop(); C.Status = "Game initialization timed out: " .. tostring(C.StartupStatus) end
        return
    end
    if not cash() or not workspace:FindFirstChild("Map") or #mapSignature().Parts == 0 then return end
    -- Allow the world and loadout to settle before fingerprinting or buying.
    if os.clock() - autoBeginAt < 3 then return end
    local ok, err = pcall(function()
        if s.Intent == "Record" then
            installHook(); C.StartRecord(s.RecordName or unusedName("My macro"), s.Mission, difficulty())
            settings.Map, settings.Loadout = C.Record.Map, C.Record.Loadout
            settings.Difficulty = C.Record.Difficulty
            armed, requested = false, nil; saveSettings()
        elseif s.Intent == "Replay" then
            local plan = loadProfile(s.Selected)
            local valid, why = selectedPlan(plan)
            assert(valid, why)
            if ended then
                armed, requested, C.Farming = true, "Replay", true
                local ok, why = continuity(); assert(ok, why)
                C.Status = "Farm restored after result; returning to lobby"
                return
            end
            C.StartReplay(plan); armed, requested = true, "Replay"; continuity()
            C.Farming = true
            if settings.Performance then performance() end
        end
    end)
    if ok then initialized = true
    elseif os.clock() - autoBeginAt > 45 then initialized = true; C.Stop(); C.Status = "Auto-start stopped: " .. tostring(err)
    else C.Status = "Waiting to resume: " .. tostring(err) end
end
local function tickMatch()
    api.watchCash()
    if os.clock()-lastStatic > 2 then scanStatic(); lastStatic = os.clock(); currentWaveFromUI() end
    autoBegin()
    if armed and requested == "Replay" then
        local valid, why = selectedPlan(continuationPlan())
        if not valid then C.Stop(); C.Status = why; return end
    end
    if C.Mode == "Replay" and C.PerformancePending and C.ClientReady and settings.Performance then performance() end
    if C.Mode == "Record" then
        C.PollRecord()
        -- Manual recording keeps buying under the player's control. Only vote
        -- Start once no equipped tower/emplacement can be afforded.
        if C.ClientReady and wave == 0 and #C.Pending == 0 and startVote then
            local cfg, balance, cheapest = config(), cash(), math.huge
            for i = 1, 5 do
                local name = slotName(i); local t = cfg and cfg.Towers[name]
                if t and t.Lvl0 then cheapest = math.min(cheapest, tonumber(t.Lvl0.Price) or math.huge) end
            end
            local hasHardpoint = false
            for _, o in ipairs(staticObjects) do if o:GetAttribute("Name") == "Hardpoint" then hasHardpoint = true end end
            if hasHardpoint then
                local f = player:FindFirstChild("Emplacements")
                for _, o in ipairs(f and f:GetChildren() or {}) do
                    local t = cfg and cfg.Towers[o.Value]
                    if t and t.Lvl0 then cheapest = math.min(cheapest, tonumber(t.Lvl0.Price) or math.huge) end
                end
            end
            if balance and cheapest < math.huge and balance < cheapest then startMatch() end
        end
    elseif C.Mode == "Finishing" then C.Finish()
    elseif C.Mode == "Replay" then C.PollReplay() end
    autoAbilities.Poll()
    if C.Mode == "Replay" and armed and not ended and wave == 0 and C.ClientReady then
        local purchaseStalled = C.Preflight and os.clock() - C.Preflight.Sent > 60
        if not findStartVote() and not C.Preflight then startMissingSince = startMissingSince or os.clock() else startMissingSince = nil end
        if (purchaseStalled or (startMissingSince and os.clock() - startMissingSince > 30)) and not returning and os.clock() >= nextReturn then
            if not matchCache.RecoveryCounted then
                settings.StartRecoveries = (tonumber(settings.StartRecoveries) or 0) + 1
                matchCache.RecoveryCounted = true
            end
            if settings.StartRecoveries > 2 then
                C.Stop(); C.Status = "Opening failed in 3 matches; farming stopped. Check game loading or recorded placement positions."
            else
                saveSettings()
                returning = true
                C.Status = (purchaseStalled and "Opening purchase unconfirmed" or "Start vote missing") .. "; returning to create a fresh match"
                local ok, why = pcall(function() Teleport:Teleport(127750392812160, player) end)
                if not ok then returning = false; nextReturn = os.clock()+10; C.Status = "Start recovery teleport failed: " .. tostring(why) end
            end
        end
    elseif wave > 0 then
        startMissingSince = nil
        if settings.StartRecoveries and settings.StartRecoveries ~= 0 then settings.StartRecoveries = 0; saveSettings() end
    end
    if (ended or manualReturnPending) and armed and requested == "Replay" and not returning
        and (manualReturnPending or os.clock() - resultAt >= 4) and os.clock() >= nextReturn then
        local ok, err = continuity()
        if not ok then armed = false; saveSettings(); C.Status = err; return end
        returning = true
        local success, why = pcall(function() Teleport:Teleport(127750392812160, player) end)
        if not success then returning = false; nextReturn = os.clock() + 10; C.Status = "Return to lobby failed: " .. tostring(why) end
    end
end
local accumulator = 0
connect(Run.Heartbeat, function(dt)
    if not alive or busy then return end
    accumulator = accumulator + dt
    if accumulator < 0.15 then return end
    accumulator = 0; busy = true
    local ok, err = pcall(function()
        if not readyEvents then readyEvents = attachEvents() end
        if stage == "Match" then prepareClient(); repairStartUI() end
        skipLoading()
        if preferencesDirtyAt and os.clock() - preferencesDirtyAt >= 0.75 then flushPreferences() end
        if readyEvents then if stage == "Lobby" then autoBegin(); tickLobby() else tickMatch() end end
        if os.clock() - lastUI > 0.25 then
            lastUI = os.clock()
            statusLabel.Text = C.Status .. (C.RecoveryStatus and ("\n" .. C.RecoveryStatus) or "")
            missionButton.Text, modeButton.Text = "Mission: " .. settings.Mission, settings.Difficulty
            profileButton.Text = settings.Selected or "Choose recorded macro ▾"
            subtitle.Text = stage .. " · " .. (C.StartupStatus or "Record once, farm your strategy")
            perfButton.Text = "Replay low graphics: " .. (settings.Performance and "ON" or "OFF")
            C.Farming = armed and requested == "Replay"
            farmButton.Text = C.Farming and "Farming: ON" or "Start farm"
            autoAbilities.Button.Text = "Auto abilities: " .. ((settings.AutoAbilities and not settings.AbilitiesPaused) and "ON" or "OFF")
            progressLabel.Text = string.format("%s · wave %s · cash %s · %s", C.Mode, wave, cash() or "—", C.VisualStatus or "Visuals normal")
            resultLabel.Text = C.ResultStatus or C.AbilityStatus or C.LoadingStatus or (storageError or "Profiles: " .. ROOT)
            local camera = workspace.CurrentCamera
            if camera then scale.Scale = math.min(1,camera.ViewportSize.X/420,camera.ViewportSize.Y/695); fitPanel() end
        end
    end)
    busy = false
    if not ok then C.Status = "Error (draft retained): " .. tostring(err) end
end)
for _, c in ipairs(menuConnections) do table.insert(connections, c) end
return C
]========]
local persisted, persistenceError = pcall(function()
    if not (writefile and makefolder and isfile and readfile) then error("File APIs unavailable") end
    if not (isfolder and isfolder("Last Contract Tower Defense")) then pcall(makefolder, "Last Contract Tower Defense") end
    writefile("Last Contract Tower Defense/runtime.lua", source)
    assert(readfile("Last Contract Tower Defense/runtime.lua") == source, "Runtime save verification failed")
end)
if not persisted then warn("Teleport continuation unavailable: " .. tostring(persistenceError)) end
local env = (getgenv and getgenv()) or _G
env.LastContractRuntimePersisted = persisted
local run, err = loadstring(source, "LastContractFarm")
assert(run, err)
return run()
