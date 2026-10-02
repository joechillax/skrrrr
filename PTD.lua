-- Periastron farm: one-file UI, recorder, and replay. Run in the main-game client.
-- Auto skip follows its toggle while the panel is open. F8 stops recording/replay.

local function launchReplay()
-- Periastron TD client macro, based on the supplied 2026-10-02 dump.
-- Run once in the main-game client after loading. F8 stops; rerunning replaces it.
-- Plays completed recordings only. Coordinates and action order come from them.
local CONFIG = {
    Difficulty = "Medium",
    SpeedIndex = 3, -- In this dump: 1 = 1x, 2 = 1.5x, 3 = 2x (Speed pass)
    AutoRetry = true,
    AutoReady = true,
    AutoSkip = true,
    Tick = 0.2,
    ActionInterval = 2,
    PlacementTimeout = 4,
    AttemptsPerPosition = 2,
    InitialPlacementWait = 5, -- ready anyway if money/cards/positions block placement
    RetryDelay = 4,
    RetryInterval = 5,
}

local env = (getgenv and getgenv()) or _G
if env.PeriastronAutofarm and env.PeriastronAutofarm.Stop then
    env.PeriastronAutofarm.Stop()
end
local Players = game:GetService("Players")
local player = Players.LocalPlayer
assert(player, "Run this in the game client")
local RS = game:GetService("ReplicatedStorage")
local shared = RS:WaitForChild("Shared", 30)
assert(shared, "Shared folder missing; run in the main game")
local Me = require(shared.Vendor.Me).new()
local SharedConfig = require(shared.Config.SharedConfig)
local reliable = shared.Vendor.Warp.Index.Event.Reliable
-- Warp.Client does a nested require from a game ModuleScript. Some scripting
-- environments reject that after loading the client factory themselves. Keep
-- the require in this script, reuse the game's cache, and call events directly.
local createClientEvent
local function eventFor(name)
    assert(reliable:GetAttribute(name), "Missing event: " .. name)
    local event = Me.Events[name]
    if not event then
        if not createClientEvent then
            createClientEvent = require(shared.Vendor.Warp.Index.Client.Index)
            assert(type(createClientEvent) == "function", "Warp client factory unavailable")
        end
        event = createClientEvent(name)
        Me.Events[name] = event
    end
    return event
end
local gui = player:WaitForChild("PlayerGui", 30)
local macro = {Running = true, Status = "Loading", Placed = 0, Rounds = 0}
env.PeriastronAutofarm = macro
function macro.SetOptions(options)
    if options.Difficulty ~= nil then
        assert(type(options.Difficulty) == "string", "Invalid mode")
        CONFIG.Difficulty = options.Difficulty
    end
    if options.SpeedIndex ~= nil then
        assert(SharedConfig.SpeedConfig.IsValid(options.SpeedIndex), "Invalid speed option")
        CONFIG.SpeedIndex = options.SpeedIndex
    end
    if options.AutoRetry ~= nil then CONFIG.AutoRetry = options.AutoRetry == true end
    if options.AutoReady ~= nil then CONFIG.AutoReady = options.AutoReady == true end
    if options.AutoSkip ~= nil then CONFIG.AutoSkip = options.AutoSkip == true end
end
if type(env.PeriastronUIOptions) == "table" then macro.SetOptions(env.PeriastronUIOptions) end
local subscriptions, nativeConnections = {}, {}
function macro.Stop()
    macro.Running = false
    macro.Status = "Stopped"
    -- Warp Connect returns a string key, not an RBXScriptConnection.
    for _, subscription in ipairs(subscriptions) do
        pcall(function() subscription.event:Disconnect(subscription.key) end)
    end
    for _, connection in ipairs(nativeConnections) do connection:Disconnect() end
    subscriptions, nativeConnections = {}, {}
end
local function status(message)
    if macro.Status ~= message then
        macro.Status = message
        print("[PeriastronAutofarm] " .. message)
    end
end
local function controller(name) return Me:Get(name) end
local function listen(name, callback)
    local event = eventFor(name)
    local key = event:Connect(function(...)
        if macro.Running then callback(...) end
    end)
    table.insert(subscriptions, {event = event, key = key})
end
local function fire(name, ...)
    if not macro.Running then return end
    eventFor(name):Fire(true, ...)
end
local function visible(object)
    if not object then return false end
    local current = object
    while current and current ~= gui do
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("ScreenGui") and not current.Enabled then return false end
        current = current.Parent
    end
    return current == gui
end

local cash, pending, roundStartedAt, endedAt, intermission
local retryState, retryAttempts = nil, 0
local previousResultShowing = false
local skipState, lastSkipToken, skipVoted = nil, nil, false
local uiSkip = env.PeriastronFarmUI and env.PeriastronFarmUI.AutoSkip
local ownsSkip = not (uiSkip and uiSkip.Running)
macro.SkipVotes = 0
macro.SkipSupported = reliable:GetAttribute("VoteSkip") ~= nil and reliable:GetAttribute("SkipState") ~= nil
    and reliable:GetAttribute("RequestSkipState") ~= nil
local positionIndex, actionIndex, attempts, generation = 1, 1, 0, 0
local placedByIndex, upgradesById = {}, {}
local placements, replaySteps = {}, {}
local function loadRecording()
    local recording = env.PeriastronReplay
    if not recording and isfile and readfile and isfile("periastron-replay.json") then
        local ok, value = pcall(function()
            return game:GetService("HttpService"):JSONDecode(readfile("periastron-replay.json"))
        end)
        assert(ok, "Could not read periastron-replay.json: " .. tostring(value))
        recording = value
    end
    assert(type(recording) == "table", "No recorded macro loaded; select a saved macro or record and save a round first")
    assert(recording.Version == 1 and recording.Complete == true, "Recording is not complete; finish and save a manual round first")
    assert(type(recording.Placements) == "table" and #recording.Placements > 0, "Recording has no placements")
    assert(type(recording.Steps) == "table" and #recording.Steps > 0, "Recording has no steps")
    local loadedPlacements = {}
    for index, item in ipairs(recording.Placements) do
        assert(SharedConfig.UnitStats[item.Unit] and type(item.CFrame) == "table" and #item.CFrame == 12, "Invalid recorded placement")
        loadedPlacements[index] = {Unit = item.Unit, CF = CFrame.new(table.unpack(item.CFrame))}
    end
    local seen = {}
    for _, step in ipairs(recording.Steps) do
        assert(step.Kind == "Place" or step.Kind == "Upgrade", "Invalid recorded action")
        assert(loadedPlacements[step.Placement], "Invalid recorded target")
        if step.Kind == "Place" then
            assert(not seen[step.Placement], "Duplicate recorded placement")
            seen[step.Placement] = true
        else
            assert(seen[step.Placement] and type(step.Level) == "number" and step.Level >= 1
                and step.Level <= SharedConfig.UnitUpgradeConfig.MaxUpgrades, "Invalid recorded upgrade")
        end
    end
    placements, replaySteps = loadedPlacements, recording.Steps
    print("[PeriastronAutofarm] Using recorded macro: " .. #replaySteps .. " actions")
end
local last = {}
local function due(name, interval)
    local now = os.clock()
    if last[name] and now - last[name] < interval then return false end
    last[name] = now
    return true
end
local function reset()
    generation = generation + 1
    cash, pending, roundStartedAt, endedAt, intermission = nil, nil, nil, nil, nil
    positionIndex, actionIndex, attempts, macro.Placed, last = 1, 1, 0, 0, {}
    placedByIndex, upgradesById = {}, {}
    macro.Cash, macro.Step = nil, 1
    retryState, retryAttempts = nil, 0
    macro.RetryAttempts = 0
    skipState, lastSkipToken, skipVoted = nil, nil, false
    fire("RequestCash")
    fire("RequestCardCounts")
    fire("RequestGameSpeed")
    if ownsSkip and macro.SkipSupported then fire("RequestSkipState") end
end
local function ended()
    if not endedAt then macro.Rounds = macro.Rounds + 1 end
    endedAt = endedAt or os.clock()
    pending = nil
end
local function seedExistingPositions()
    for _, model in ipairs(workspace:GetChildren()) do
        local id = model:GetAttribute("UnitID")
        if model:IsA("Model") and model:GetAttribute("Owned") == true and id then
            local nearest, distance = nil, 0.75
            for index, placement in ipairs(placements) do
                local delta = (model:GetPivot().Position - placement.CF.Position).Magnitude
                if model.Name == placement.Unit and delta < distance then
                    nearest, distance = index, delta
                end
            end
            if nearest then
                placedByIndex[nearest] = id
                upgradesById[id] = model:GetAttribute("Upgrades") or 0
            end
        end
    end
end
local function playUpgrade(step)
    local target = step.Placement
    local id = placedByIndex[target]
    assert(id, "Upgrade target placement missing: " .. tostring(target))
    local name = placements[target].Unit
    local desired = step.Level
    local level = upgradesById[id] or 0
    if level >= desired then actionIndex = actionIndex + 1; return end
    assert(not SharedConfig.UnitUpgradeConfig:IsMaxed(level), "Upgrade target is already maxed")
    local cost = SharedConfig.UnitUpgradeConfig:GetCost(name, level)
    if type(cash) ~= "number" or cash < cost then
        status("Waiting for upgrade cash: " .. name .. " costs " .. tostring(cost)); return
    end
    if not due("upgrade", CONFIG.ActionInterval) then return end
    pending = {kind = "upgrade", id = id, desired = desired, sentAt = os.clock(), generation = generation}
    status("Upgrading " .. name .. " at placement " .. target)
    fire("UpgradeUnit", id)
end
local function tick()
    macro.Cash, macro.Step, macro.TotalSteps = cash, actionIndex, #replaySteps
    local result = controller("ResultController")
    local resultShowing = result and result.showing == true or false
    -- RoundRestarted and the game's Hide callback are delivered separately.
    -- A still-visible result panel must not mark the new round ended again.
    if resultShowing and not previousResultShowing then ended() end
    previousResultShowing = resultShowing
    if endedAt then
        if not CONFIG.AutoRetry then status("Round ended; auto replay is off"); return end
        local tutorial = controller("TutorialStepController")
        if tutorial and tutorial.IsTutorial and tutorial:IsTutorial() then
            status("Replay is unavailable during the tutorial"); return
        end
        local remaining = CONFIG.RetryDelay - (os.clock() - endedAt)
        if remaining > 0 then
            status("Round ended; retry in " .. math.ceil(remaining) .. "s"); return
        end
        local votes = retryState or (result and result.playAgainState)
        if votes and type(votes.votes) == "number" and type(votes.total) == "number"
            and votes.total > 0 and votes.votes >= votes.total then
            status("All retry votes ready; waiting for round restart"); return
        end
        -- VotePlayAgain is the same action used by the game's click handler.
        -- Send it after a confirmed round end; animated GUI state is not a gate.
        if due("retry", CONFIG.RetryInterval) then
            retryAttempts = retryAttempts + 1
            macro.RetryAttempts = retryAttempts
            status("Retry requested (attempt " .. retryAttempts .. "); waiting for server")
            fire("VotePlayAgain")
        end
        return
    end

    local difficulty = controller("DifficultyController")
    if difficulty and visible(difficulty.board) then
        local modeButton = difficulty.Buttons and difficulty.Buttons[CONFIG.Difficulty]
        if difficulty.Buttons and not modeButton then
            status("Selected mode is unavailable: " .. CONFIG.Difficulty); return
        end
        if SharedConfig.DifficultyUnlockConfig and difficulty.stats then
            if not SharedConfig.DifficultyUnlockConfig.isUnlocked(CONFIG.Difficulty, difficulty:stats()) then
                status("Selected mode is locked: " .. CONFIG.Difficulty); return
            end
        end
        status("Selecting " .. CONFIG.Difficulty)
        if due("difficulty", CONFIG.ActionInterval) then
            fire("SelectDifficulty", CONFIG.Difficulty)
        end
        return
    end
    if not difficulty or not difficulty.HotbarWanted then
        status("Waiting for difficulty selection")
        return
    end
    if ownsSkip then
        local skipController = controller("SkipPromptController")
        local offer = skipState or (skipController and skipController.State)
        if not offer or offer.active ~= true then
            skipVoted, lastSkipToken = false, nil
            macro.SkipStatus = "Waiting for skip offer"
        elseif CONFIG.AutoSkip and macro.SkipSupported then
            if not skipVoted or offer.token ~= lastSkipToken then
                skipVoted, lastSkipToken = true, offer.token
                macro.SkipVotes = macro.SkipVotes + 1
                macro.SkipStatus = "Voted to skip"
                fire("VoteSkip", true)
            end
        end
    else
        macro.SkipStatus, macro.SkipVotes, macro.SkipSupported = uiSkip.Status, uiSkip.Votes, uiSkip.Supported
    end
    roundStartedAt = roundStartedAt or os.clock()
    local speed = controller("SpeedController")
    if speed and due("speed", CONFIG.ActionInterval) then
        local index = CONFIG.SpeedIndex
        while index > 1 and not speed:isUnlocked(index) do index = index - 1 end
        if speed.Index ~= index then fire("SetGameSpeed", index) end
        macro.SpeedIndex = index
    end

    local ready = controller("ReadyController")
    local readyActive = intermission and intermission.active == true
    if intermission == nil then readyActive = ready and visible(ready.button) end
    if CONFIG.AutoReady and readyActive and not (intermission and intermission.isReady) then
        if macro.Placed > 0 or os.clock() - roundStartedAt >= CONFIG.InitialPlacementWait then
            if due("ready", CONFIG.ActionInterval) then fire("ReadyWave") end
        end
    end

    if pending then
        if os.clock() - pending.sentAt < CONFIG.PlacementTimeout then
            status(pending.kind == "upgrade" and "Waiting for upgrade confirmation" or "Waiting for placement confirmation")
            return
        end
        local kind = pending.kind
        pending = nil
        attempts = attempts + 1
        -- Refresh after timeout; never assume a cash deduction means placement succeeded.
        cash = nil
        fire("RequestCash")
        fire("RequestCardCounts")
        assert(attempts < CONFIG.AttemptsPerPosition,
            kind .. " not confirmed after " .. attempts .. " attempts at placement " .. positionIndex)
        return
    end
    local step = replaySteps[actionIndex]
    if not step then status("Recording complete; waiting for round end"); return end
    if step.Kind == "Upgrade" then playUpgrade(step); return end
    positionIndex = step.Placement
    if placedByIndex[positionIndex] then actionIndex = actionIndex + 1; return end
    local placement = placements[positionIndex]
    local selectedUnit = placement.Unit
    assert(SharedConfig.UnitStats[selectedUnit], "Unknown tower: " .. tostring(selectedUnit))
    local card = controller("CardController")
    local count = card and card.CardCounts and card.CardCounts[selectedUnit]
    if type(count) ~= "number" or count <= 0 then status("Waiting for " .. selectedUnit .. " cards"); return end
    if type(cash) ~= "number" then status("Waiting for cash update"); return end
    local weather = controller("WeatherController")
    local cost = SharedConfig.UnitUpgradeConfig:GetPlaceCost(selectedUnit, weather and weather:GetCurrent() or nil)
    if cash < cost then status("Waiting for cash: " .. tostring(cash) .. "/" .. tostring(cost)); return end
    if not due("place", CONFIG.ActionInterval) then return end
    pending = {kind = "place", unit = selectedUnit, cf = placement.CF, sentAt = os.clock(), generation = generation}
    status("Placing " .. selectedUnit .. " at position " .. positionIndex)
    fire("PlaceUnit", selectedUnit, pending.cf)
end

local function run()
    if not macro.Running then return end
    assert(SharedConfig.SpeedConfig.IsValid(CONFIG.SpeedIndex), "Invalid speed index")
    loadRecording()
    local deadline = os.clock() + 30
    while macro.Running and os.clock() < deadline do
        if controller("CardController") and controller("SpeedController") and controller("DifficultyController") then break end
        task.wait(CONFIG.Tick)
    end
    if not macro.Running then return end
    assert(controller("CardController") and controller("SpeedController") and controller("DifficultyController"), "Game controllers did not load")
    listen("UpdateCash", function(value) if type(value) == "number" then cash, macro.Cash = value, value end end)
    listen("WaveIntermission", function(state) intermission = state end)
    listen("GameOver", ended)
    listen("Win", ended)
    listen("RoundReward", ended)
    listen("PlayAgainState", function(state)
        if type(state) == "table" then retryState = state end
    end)
    if ownsSkip and macro.SkipSupported then
        listen("SkipState", function(state) if type(state) == "table" then skipState = state end end)
    end
    listen("RoundRestarted", function()
        reset()
    end)
    listen("ReplicateUnit", function(name, cf, owner, id, level)
        if not pending or pending.kind ~= "place" or pending.generation ~= generation or endedAt then return end
        if owner ~= player.UserId or name ~= pending.unit or not id or typeof(cf) ~= "CFrame" then return end
        if (cf.Position - pending.cf.Position).Magnitude > 0.3 then return end
        placedByIndex[positionIndex] = id
        upgradesById[id] = level or 0
        macro.Placed = macro.Placed + 1
        actionIndex, attempts, pending = actionIndex + 1, 0, nil
        -- Obtain a fresh balance before the next placement, independent of event order.
        cash = nil
        fire("RequestCash")
        fire("RequestCardCounts")
    end)
    listen("UnitUpgraded", function(id, level)
        upgradesById[id] = level
        if pending and pending.kind == "upgrade" and pending.generation == generation and pending.id == id then
            if level >= pending.desired then
                pending, attempts, cash = nil, 0, nil
                actionIndex = actionIndex + 1
                fire("RequestCash")
            end
        end
    end)
    local input = game:GetService("UserInputService")
    table.insert(nativeConnections, input.InputBegan:Connect(function(key, processed)
        if not processed and key.KeyCode == Enum.KeyCode.F8 then macro.Stop() end
    end))
    reset()
    seedExistingPositions()
    while macro.Running do tick(); task.wait(CONFIG.Tick) end
end
task.spawn(function()
    local ok, message = xpcall(run, debug.traceback)
    if not ok then
        macro.Stop()
        macro.Status = "Error: " .. tostring(message)
        warn("[PeriastronAutofarm] " .. macro.Status)
    end
end)

return env.PeriastronAutofarm
end

local function launchRecorder()
-- Run BEFORE placing the first tower in a fresh round, then play one round manually.
-- Saves reusable placement/upgrade targets. F7 finishes early; F8 cancels capture.
local env = (getgenv and getgenv()) or _G
if env.PeriastronAutofarm and env.PeriastronAutofarm.Stop then env.PeriastronAutofarm.Stop() end
if env.PeriastronRecorder and env.PeriastronRecorder.Stop then env.PeriastronRecorder.Stop() end
local player = game:GetService("Players").LocalPlayer
assert(player, "Run the recorder in the game client")
local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared", 30)
assert(shared, "Run in the main game")
local Me = require(shared.Vendor.Me).new()
local reliable = shared.Vendor.Warp.Index.Event.Reliable
-- Require from this script rather than Warp.Client's game ModuleScript context.
-- Reuse cached events so the recorder shares the game's existing network state.
local createClientEvent
local function eventFor(name)
    assert(reliable:GetAttribute(name), "Missing event: " .. name)
    local event = Me.Events[name]
    if not event then
        if not createClientEvent then
            createClientEvent = require(shared.Vendor.Warp.Index.Client.Index)
            assert(type(createClientEvent) == "function", "Warp client factory unavailable")
        end
        event = createClientEvent(name)
        Me.Events[name] = event
    end
    return event
end
local recorder = {Running = true, Status = "Recording"}
env.PeriastronRecorder = recorder
local profileName = env.PeriastronRecordingName
local profileOptions = {}
for key, value in pairs(env.PeriastronUIOptions or {}) do profileOptions[key] = value end
local subscriptions, inputConnection, heartbeatConnection = {}, nil, nil
local recording, byID, levels, accepting
local finish, suppressOldResult, backupSlot = nil, false, 0
local http = game:GetService("HttpService")
local function resultShowing()
    local result = Me:Get("ResultController")
    if result and type(result.showing) == "boolean" then return result.showing end
    local screen = player:WaitForChild("PlayerGui"):FindFirstChild("ResultScreen")
    return screen and screen.Enabled == true or false
end
local function preserve()
    if not recording then return end
    recorder.Recording = recording
    env.PeriastronRecoveryDraft = recording
    env.PeriastronRecordingBackups = env.PeriastronRecordingBackups or {}
    env.PeriastronRecordingBackups[recording.CaptureID] = recording
end
local function checkpoint()
    preserve()
    if not recording or #recording.Steps == 0 then return end
    local ok, err = pcall(function()
        assert(writefile and readfile and makefolder and isfolder, "Recording file APIs unavailable")
        if not isfolder("Periastron Tower Defense") then makefolder("Periastron Tower Defense") end
        if not isfolder("Periastron Tower Defense/Recovery") then makefolder("Periastron Tower Defense/Recovery") end
        local nextSlot = 1 - backupSlot
        local path = "Periastron Tower Defense/Recovery/" .. recording.CaptureID .. (nextSlot == 0 and "-a.json" or "-b.json")
        local encoded = http:JSONEncode({Version = 1, Name = profileName or "Recorded macro", SavedAt = os.time(),
            Recording = recording, Options = env.PeriastronUIOptions or profileOptions})
        writefile(path, encoded)
        assert(readfile(path) == encoded, "Recording backup read-back failed")
        -- Keep retrying the failed slot; never overwrite the last verified slot.
        backupSlot = nextSlot
        recorder.BackupPath = path
    end)
    recorder.BackupError = not ok and tostring(err) or nil
    return ok
end
function recorder.Snapshot() return recording end
local function begin()
    -- A retry is evidence that the preceding round ended, not a reason to erase it.
    if recording and accepting and #recording.Steps > 0 then finish(); return end
    env.PeriastronCaptureSerial = (env.PeriastronCaptureSerial or 0) + 1
    recording = {Version = 1, Complete = false, Placements = {}, Steps = {}, ProfileName = profileName,
        RecordedAt = os.time(), CaptureSerial = env.PeriastronCaptureSerial,
        CaptureID = tostring(os.time()) .. "-" .. env.PeriastronCaptureSerial .. "-" .. math.random(100000, 999999)}
    byID, levels, accepting = {}, {}, true
    env.PeriastronReplay = recording
    preserve()
    suppressOldResult = resultShowing()
    recorder.Status = "Recording manual placements and upgrades"
    print("[PeriastronRecorder] Recording. Play your round manually; F7 saves early.")
end
function recorder.Stop()
    checkpoint()
    recorder.Running = false
    for _, item in ipairs(subscriptions) do pcall(function() item.event:Disconnect(item.key) end) end
    subscriptions = {}
    if inputConnection then inputConnection:Disconnect(); inputConnection = nil end
    if heartbeatConnection then heartbeatConnection:Disconnect(); heartbeatConnection = nil end
end
finish = function()
    if not accepting or recorder.DiskSaved then return end
    if #recording.Placements == 0 then
        warn("[PeriastronRecorder] No placements captured; nothing saved")
        return
    end
    recording.Complete = true
    checkpoint()
    env.PeriastronReplay = recording
    local savedProfile, saveLocation
    if profileName and type(env.PeriastronProfileSaver) == "function" then
        local ok, name, location, diskSaved = pcall(env.PeriastronProfileSaver, profileName, recording, env.PeriastronUIOptions or profileOptions)
        if ok then
            savedProfile, saveLocation = name, location
            recording.ProfileName = name
            recorder.DiskSaved = diskSaved == true
            if env.PeriastronReplay and env.PeriastronReplay.CaptureID == recording.CaptureID then recording = env.PeriastronReplay end
        else saveLocation = "save failed; recording kept in memory: " .. tostring(name) end
    end
    local json = http:JSONEncode(recording)
    if not profileName and writefile then
        local ok, err = pcall(function()
            writefile("periastron-replay.json", json)
            assert(readfile and readfile("periastron-replay.json") == json, "Save read-back failed")
        end)
        recorder.DiskSaved = ok
        if ok then print("[PeriastronRecorder] Saved and verified periastron-replay.json")
        else warn("[PeriastronRecorder] File save failed: " .. tostring(err)) end
    end
    if recorder.DiskSaved then recorder.Status = "Saved and verified " .. #recording.Steps .. " actions: " .. (savedProfile or "periastron-replay.json")
    elseif savedProfile then recorder.Status = "NOT saved to profile file: " .. tostring(saveLocation) .. ". " .. #recording.Steps .. " actions retained; use Recover draft."
    elseif profileName then recorder.Status = saveLocation or "Recording complete; save it as a profile in the UI"
    else recorder.Status = "NOT saved to file; " .. #recording.Steps .. " actions retained in memory" end
    print("[PeriastronRecorder] " .. recorder.Status)
    recorder.Stop()
end
recorder.Finish = finish
local function listen(name, callback)
    local event = eventFor(name)
    local key = event:Connect(function(...)
        if not recorder.Running then return end
        local ok, err = xpcall(callback, debug.traceback, ...)
        if not ok then
            recorder.Status = "Error: " .. tostring(err)
            warn("[PeriastronRecorder] " .. recorder.Status)
            recorder.Stop()
        end
    end)
    table.insert(subscriptions, {event = event, key = key})
end
begin()
for _, model in ipairs(workspace:GetChildren()) do
    if model:IsA("Model") and model:GetAttribute("Owned") == true and model:GetAttribute("UnitID") then
        accepting = false
        recorder.Status = "Waiting for a fresh round; current round already has towers"
        print("[PeriastronRecorder] " .. recorder.Status)
        break
    end
end
listen("RoundRestarted", begin)
listen("ReplicateUnit", function(name, cf, owner, id, level)
    if not accepting or recording.Complete or owner ~= player.UserId or not id or byID[id] then return end
    assert(typeof(cf) == "CFrame", "Placement response did not contain a CFrame")
    local index = #recording.Placements + 1
    byID[id], levels[id] = index, level or 0
    table.insert(recording.Placements, {Unit = name, CFrame = {cf:GetComponents()}})
    table.insert(recording.Steps, {Kind = "Place", Placement = index})
    -- Ordinarily newly placed towers are level zero; preserve a nonzero level if supplied.
    for upgrade = 1, level or 0 do table.insert(recording.Steps, {Kind = "Upgrade", Placement = index, Level = upgrade}) end
    checkpoint()
    recorder.Status = "Recording " .. #recording.Steps .. " actions; " .. (recorder.BackupError and "backup failed: " .. recorder.BackupError or "draft backed up")
    print("[PeriastronRecorder] Placement " .. index .. ": " .. name)
end)
listen("UnitUpgraded", function(id, level)
    if not accepting or recording.Complete or not byID[id] or type(level) ~= "number" then return end
    for upgrade = (levels[id] or 0) + 1, level do
        table.insert(recording.Steps, {Kind = "Upgrade", Placement = byID[id], Level = upgrade})
    end
    levels[id] = math.max(levels[id] or 0, level)
    checkpoint()
    recorder.Status = "Recording " .. #recording.Steps .. " actions; " .. (recorder.BackupError and "backup failed: " .. recorder.BackupError or "draft backed up")
    print("[PeriastronRecorder] Upgrade placement " .. byID[id] .. " to level " .. level)
end)
-- RemoveUnit also occurs during round cleanup. Never erase/stop a draft on it.
listen("RemoveUnit", function(id)
    if accepting and byID[id] and not recording.Complete then
        recording.RemovalObserved = true
        checkpoint()
        recorder.Status = "Tower removed; draft retained while waiting for the match result"
    end
end)
listen("RoundReward", finish)
for _, name in ipairs({"Win", "GameOver"}) do
    if reliable:GetAttribute(name) then listen(name, function() finish() end) end
end
local runService = game:GetService("RunService")
if runService and runService.Heartbeat then
    heartbeatConnection = runService.Heartbeat:Connect(function()
        if not recorder.Running or not accepting then return end
        local showing = resultShowing()
        if not showing then suppressOldResult = false end
        if showing and not suppressOldResult and #recording.Steps > 0 then
            local ok, err = pcall(finish)
            if not ok then preserve(); recorder.Status = "Auto-save failed; draft retained: " .. tostring(err) end
        end
    end)
end
inputConnection = game:GetService("UserInputService").InputBegan:Connect(function(key, processed)
    if processed then return end
    if key.KeyCode == Enum.KeyCode.F7 then finish()
    elseif key.KeyCode == Enum.KeyCode.F8 then recorder.Status = "Cancelled"; recorder.Stop() end
end)

return env.PeriastronRecorder
end

-- Individual files keep profile deletion independent of settings and other macros.
local function openProfileStore(env)
    local root = "Periastron Tower Defense"
    local directory = root .. "/Profiles"
    local settingsPath, markerPath = root .. "/settings.json", root .. "/legacy-imported.json"
    local http = game:GetService("HttpService")
    local oldMemory, initialSelected = env.PeriastronProfiles, env.PeriastronCurrentProfile
    local store = {Error = nil, SettingsBlocked = false, Files = {}, Text = {}, Session = {}}
    store.Session = env.PeriastronSessionProfileNames or {}
    env.PeriastronSessionProfileNames = store.Session
    local optionKeys = {"Difficulty", "SpeedIndex", "AutoRetry", "AutoReady", "AutoSkip"}
    local defaults = {Difficulty = "Medium", SpeedIndex = 3, AutoRetry = true, AutoReady = true, AutoSkip = true}
    local disk = isfile and readfile and writefile and isfolder and makefolder and listfiles
    local function note(message) store.Error = (store.Error and store.Error .. "; " or "") .. message end
    local function copy(value)
        if type(value) ~= "table" then return value end
        local clone = {}
        for key, item in pairs(value) do clone[key] = copy(item) end
        return clone
    end
    local function options(value, base)
        local result = copy(base or defaults)
        if type(value) ~= "table" then return result end
        for _, key in ipairs(optionKeys) do
            local item = value[key]
            if key == "Difficulty" then
                if type(item) == "string" and #item > 0 and #item <= 60 then result[key] = item end
            elseif key == "SpeedIndex" then
                if type(item) == "number" and item % 1 == 0 and item >= 1 and item <= 3 then result[key] = item end
            elseif type(item) == "boolean" then result[key] = item end
        end
        return result
    end
    local function validRecording(value)
        return type(value) == "table" and value.Version == 1 and value.Complete == true
            and type(value.Placements) == "table" and #value.Placements > 0
            and type(value.Steps) == "table" and #value.Steps > 0
    end
    local function readJSON(path) return http:JSONDecode(readfile(path)) end
    if disk then
        local ok, err = pcall(function()
            if not isfolder(root) then makefolder(root) end
            if not isfolder(directory) then makefolder(directory) end
        end)
        if not ok then disk = false; note("Save folder unavailable: " .. tostring(err)) end
    end
    store.DiskAvailable = disk and true or false
    store.Settings = {Version = 1, Options = copy(defaults)}
    if disk and isfile(settingsPath) then
        local ok, value = pcall(function()
            local decoded = readJSON(settingsPath)
            assert(type(decoded) == "table" and decoded.Version == 1 and type(decoded.Options) == "table", "Invalid settings file")
            return {Version = 1, Options = options(decoded.Options), SelectedProfile = decoded.SelectedProfile}
        end)
        if ok then store.Settings = value; store.HasSavedSettings = true
        else store.SettingsBlocked = true; note("Settings could not be loaded: " .. tostring(value)) end
    end
    store.Data = {Version = 1, Profiles = {}}
    if type(oldMemory) == "table" and type(oldMemory.Profiles) == "table" then
        for name in pairs(store.Session) do store.Data.Profiles[name] = oldMemory.Profiles[name] end
    end
    if not disk and type(oldMemory) == "table" and type(oldMemory.Profiles) == "table" then
        store.Data = oldMemory
        for name in pairs(store.Data.Profiles) do store.Session[name] = true end
    end
    env.PeriastronProfiles = store.Data
    function store.LoadSettings(current)
        return options(current, store.Settings.Options), store.Settings.SelectedProfile
    end
    function store.SaveSettings(value, selected)
        store.SettingsSaved = false
        store.Settings = {Version = 1, Options = options(value), SelectedProfile = selected}
        if store.SettingsBlocked then return false, "session only; existing settings file needs repair" end
        if not disk then return false, "session only; folder/file APIs unavailable" end
        local ok, err = pcall(function()
            local encoded = http:JSONEncode(store.Settings)
            writefile(settingsPath, encoded)
            assert(readfile(settingsPath) == encoded, "Settings save read-back failed")
        end)
        store.SettingsSaved = ok
        return ok, ok and "saved to disk" or "session only; settings save failed: " .. tostring(err)
    end
    function store.Refresh()
        if not disk then return end
        local ok, paths = pcall(listfiles, directory)
        if not ok then return false, "Could not read profile folder: " .. tostring(paths) end
        local profiles, files, texts = {}, {}, {}
        for _, listed in ipairs(paths) do
            local filename = listed:gsub("\\", "/"):match("([^/]+)$")
            if filename and filename:lower():sub(-5) == ".json" then
                local path = directory .. "/" .. filename
                local loaded, profile, content = pcall(function()
                    local text = readfile(path)
                    local value = http:JSONDecode(text)
                    assert(type(value) == "table" and value.Version == 1 and type(value.Name) == "string"
                        and #value.Name > 0 and validRecording(value.Recording), "Invalid profile file")
                    assert(not profiles[value.Name], "Duplicate profile name")
                    value.Options = options(value.Options)
                    value.Recording.ProfileName = value.Name
                    return value, text
                end)
                if loaded then
                    local name = profile.Name
                    if store.Text[path] == content and store.Data.Profiles[name] then profile = store.Data.Profiles[name] end
                    profiles[name], files[name], texts[path] = profile, path, content
                else note("Skipped " .. filename .. ": " .. tostring(profile)) end
            end
        end
        for name in pairs(store.Session) do
            if store.Data.Profiles[name] then profiles[name] = store.Data.Profiles[name] end
        end
        store.Data.Profiles, store.Files, store.Text = profiles, files, texts
        local selected = env.PeriastronCurrentProfile
        if selected and not profiles[selected] then env.PeriastronCurrentProfile, env.PeriastronReplay = nil, nil end
        return true
    end
    function store.Names()
        local names = {}
        for name in pairs(store.Data.Profiles) do table.insert(names, name) end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        return names
    end
    local function fileFor(name)
        if store.Files[name] then return store.Files[name] end
        local stem = name:gsub('[<>:"/\\|?*%c]', "_"):gsub("[%. ]+$", "")
        if #stem == 0 then stem = "Macro" end
        local device = stem:match("^([^.]+)"):upper()
        if device == "CON" or device == "PRN" or device == "AUX" or device == "NUL"
            or device:match("^COM[1-9]$") or device:match("^LPT[1-9]$") then stem = "_" .. stem end
        local candidate, suffix = directory .. "/" .. stem .. ".json", 2
        local function occupied(path)
            if isfile and isfile(path) then return true end
            for _, existing in pairs(store.Files) do if existing:lower() == path:lower() then return true end end
            return false
        end
        while occupied(candidate) do
            candidate = directory .. "/" .. stem .. " (" .. suffix .. ").json"; suffix = suffix + 1
        end
        return candidate
    end
    function store.Save(name, recording, value, migrating)
        assert(validRecording(recording), "Finish recording before saving a profile")
        assert(type(name) == "string", "Enter a macro name")
        name = name:match("^%s*(.-)%s*$")
        assert(#name > 0 and #name <= 60, "Use a macro name between 1 and 60 characters")
        local original, suffix = name, 2
        while store.Data.Profiles[name] and store.Data.Profiles[name].Recording ~= recording do
            name = original .. " (" .. suffix .. ")"; suffix = suffix + 1
        end
        local saved = {Version = 1, Name = name, Recording = copy(recording), Options = options(value)}
        saved.Recording.ProfileName = name
        local encoded = http:JSONEncode(saved)
        local path = fileFor(name)
        store.Data.Profiles[name], store.Session[name] = saved, true
        env.PeriastronReplay, env.PeriastronCurrentProfile = saved.Recording, name
        local location = "session only; folder/file APIs unavailable"
        if disk then
            local ok, err = pcall(function()
                writefile(path, encoded)
                assert(readfile(path) == encoded, "Profile save read-back failed")
            end)
            if ok then
                store.Files[name], store.Text[path], store.Session[name] = path, encoded, nil
                location = "saved to " .. path
            else location = "session only; profile save failed: " .. tostring(err) end
        end
        if not migrating then store.SaveSettings(env.PeriastronUIOptions or value, name) end
        return name, location, store.Session[name] == nil
    end
    function store.Load(name)
        local profile = store.Data.Profiles[name]
        assert(profile and validRecording(profile.Recording), "Saved macro not found")
        env.PeriastronReplay, env.PeriastronCurrentProfile = profile.Recording, name
        return profile.Recording, profile.Options or {}
    end
    function store.ImportLegacy(current, value)
        local recording = current
        if not validRecording(recording) and isfile and readfile and isfile("periastron-replay.json") then
            local ok, decoded = pcall(readJSON, "periastron-replay.json")
            if ok and validRecording(decoded) then recording = decoded end
        end
        assert(validRecording(recording), "No complete old recording found")
        for name, profile in pairs(store.Data.Profiles) do
            if profile.Recording == recording then return name, "already saved" end
        end
        return store.Save("Imported recording", recording, value)
    end
    function store.CheckRecordingPersistence()
        if not disk then return false, "Recording needs working folder, read, write, and list APIs" end
        local ok, err = pcall(function()
            local recovery = root .. "/Recovery"
            if not isfolder(recovery) then makefolder(recovery) end
            local path = recovery .. "/_write-check.json"
            local encoded = http:JSONEncode({Version = 1, Probe = true})
            writefile(path, encoded)
            assert(readfile(path) == encoded, "Recording backup read-back failed")
            if delfile then pcall(delfile, path) end
        end)
        return ok, not ok and tostring(err) or nil
    end
    function store.LoadDraft()
        local best, stamp, serial = nil, -1, -1
        local function consider(value)
            if type(value) ~= "table" or value.Version ~= 1 or value.Invalid
                or type(value.Placements) ~= "table" or #value.Placements == 0
                or type(value.Steps) ~= "table" or #value.Steps == 0 then return end
            local time, order = value.RecordedAt or 0, value.CaptureSerial or 0
            if not best or time > stamp or (time == stamp and order > serial)
                or (time == stamp and order == serial and #value.Steps > #best.Steps) then
                best, stamp, serial = value, time, order
            end
        end
        consider(env.PeriastronRecoveryDraft)
        consider(env.PeriastronRecoveredRecording)
        if env.PeriastronRecorder then consider(env.PeriastronRecorder.Recording) end
        for _, value in pairs(env.PeriastronRecordingBackups or {}) do consider(value) end
        if disk then
            local ok, paths = pcall(listfiles, root .. "/Recovery")
            if ok then
                for _, listed in ipairs(paths) do
                    local filename = listed:gsub("\\", "/"):match("([^/]+)$")
                    if filename and filename:lower():sub(-5) == ".json" then
                        local read, value = pcall(readJSON, root .. "/Recovery/" .. filename)
                        if read and type(value) == "table" then consider(value.Recording) end
                    end
                end
            end
        end
        assert(best, "No retained recording draft found")
        local draft = copy(best)
        draft.Complete = true
        return draft
    end
    store.Refresh()
    store.LegacyImported = disk and isfile(markerPath) or false
    if disk and not store.LegacyImported then
        local successful = true
        local previous = initialSelected or store.Settings.SelectedProfile
        local legacy = oldMemory
        if isfile("periastron-profiles.json") then
            local ok, value = pcall(readJSON, "periastron-profiles.json")
            if ok and type(value) == "table" and type(value.Profiles) == "table" then legacy = value
            else note("Old profile library could not be imported; original file retained") end
        end
        local function migrate(name, recording, value)
            if store.Data.Profiles[name] then return end
            local ok, savedName = pcall(store.Save, name, recording, value, true)
            if not ok or store.Session[savedName] then successful = false; note("Could not migrate " .. tostring(name)) end
        end
        if type(legacy) == "table" and type(legacy.Profiles) == "table" then
            for name, profile in pairs(legacy.Profiles) do
                if type(profile) == "table" and validRecording(profile.Recording) then migrate(name, profile.Recording, profile.Options) end
            end
        end
        if isfile("periastron-replay.json") and not store.Data.Profiles["Imported recording"] then
            local ok, recording = pcall(readJSON, "periastron-replay.json")
            if ok and validRecording(recording) then migrate("Imported recording", recording, env.PeriastronUIOptions)
            else note("Old recording could not be imported; original file retained") end
        end
        env.PeriastronCurrentProfile = previous
        if previous and store.Data.Profiles[previous] then env.PeriastronReplay = store.Data.Profiles[previous].Recording end
        if successful then
            local ok = pcall(writefile, markerPath, http:JSONEncode({Version = 1}))
            store.LegacyImported = ok
        end
    end
    return store
end

-- Auto skip belongs to the panel session, independently of recording/playback.
local function openAlwaysSkip(settings, getFramework)
    local service = {Running = true, Supported = nil, Votes = 0, Status = "Waiting for game"}
    local subscriptions, framework, reliable, createEvent, clientModule = {}, nil, nil, nil, nil
    local initialized, enabled, state, voted, lastToken = false, false, nil, false, nil
    local retryAt = 0
    local function eventFor(name)
        local event = framework.Events[name]
        if not event then
            createEvent = createEvent or require(clientModule)
            event = createEvent(name)
            framework.Events[name] = event
        end
        return event
    end
    local function disconnect()
        for _, item in ipairs(subscriptions) do pcall(function() item.event:Disconnect(item.key) end) end
        subscriptions = {}
    end
    local function listen(name, callback)
        local event = eventFor(name)
        table.insert(subscriptions, {event = event, key = event:Connect(callback)})
    end
    local function receive(value)
        if type(value) ~= "table" then return end
        state = value
        if state.active ~= true then voted, lastToken = false, nil end
        service.Update()
    end
    local function update()
        if not initialized then
            framework = getFramework()
            if not framework then service.Status = "Waiting for game"; return end
            local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
            reliable = shared.Vendor.Warp.Index.Event.Reliable
            clientModule = shared.Vendor.Warp.Index.Client.Index
            service.Supported = reliable:GetAttribute("VoteSkip") ~= nil
                and reliable:GetAttribute("SkipState") ~= nil and reliable:GetAttribute("RequestSkipState") ~= nil
            if not service.Supported then service.Status = "Unavailable"; return end
            disconnect()
            listen("SkipState", receive)
            if reliable:GetAttribute("RoundRestarted") then
                listen("RoundRestarted", function()
                    -- The controller may briefly retain the previous round's offer.
                    state, voted, lastToken, enabled = {active = false}, false, nil, false
                    service.Update()
                end)
            end
            initialized = true
        end
        local wasEnabled = enabled
        enabled = settings.AutoSkip == true
        if enabled and not wasEnabled then eventFor("RequestSkipState"):Fire(true) end
        local skipController = framework:Get("SkipPromptController")
        local offer = state or (skipController and skipController.State)
        if not offer or offer.active ~= true then
            voted, lastToken = false, nil
            service.Status = enabled and "Waiting for skip offer" or "Off"
        elseif not enabled then
            service.Status = "Off"
        elseif voted and offer.token == lastToken then
            service.Status = "Voted to skip"
        else
            -- Mark before firing: server acknowledgements may arrive immediately.
            voted, lastToken = true, offer.token
            eventFor("VoteSkip"):Fire(true, true)
            service.Votes = service.Votes + 1
            service.Status = "Voted to skip"
        end
    end
    function service.Update()
        if not service.Running or os.clock() < retryAt then return end
        local ok, err = pcall(update)
        if not ok then
            service.Error = tostring(err)
            service.Status = "Error: " .. service.Error
            retryAt = os.clock() + 5
        else service.Error = nil end
    end
    function service.Stop()
        service.Running = false
        disconnect()
    end
    return service
end

-- Fixed destination. Results and delivery retries are independent of macro workers.
local function openResultReporter(env, settings, getFramework, getContext)
    local WEBHOOK = "https://discord.com/api/webhooks/1551830162650435584/V_EItPsWyCQDQgEvZlAGjaH4XoKXchAD6UbPwEiiJ6mPUmiU-2cOlioFzvPW79KlZGgu?wait=true"
    local ROOT = "Periastron Tower Defense"
    local executorHttp = http
    local http = game:GetService("HttpService")
    local service = {Running = true, Status = "Discord: waiting for a result"}
    local state = env.PeriastronResultState
    local slot, sequence, diskError, blockSave = 0, 0, false, false
    if not state then
        local best
        for index, suffix in ipairs({"a", "b"}) do
            local path = ROOT .. "/results-" .. suffix .. ".json"
            if isfile and readfile then
                local ok, data = pcall(function()
                    if not isfile(path) then return end
                    local value = http:JSONDecode(readfile(path))
                    assert(type(value) == "table" and value.Version == 1 and type(value.Stats) == "table"
                        and type(value.Outbox) == "table" and type(value.Sequence) == "number", "Invalid results file")
                    return value
                end)
                if ok and data and (not best or data.Sequence > best.Sequence) then best, slot = data, index - 1
                elseif not ok then diskError = true end
            end
        end
        blockSave = diskError and not best
        state = best or {Version = 1, Sequence = 0, Serial = 0, Stats = {}, Outbox = {}}
        sequence = state.Sequence
        -- Retry unsent transient failures after a fresh script session.
        for _, item in ipairs(state.Outbox) do item.RetryAt = 0 end
        env.PeriastronResultState = state
    else slot, sequence, blockSave = state.Slot or 0, state.Sequence or 0, state.BlockSave == true end
    state.BlockSave = blockSave
    state.Slot = slot
    local subscriptions, framework, factory, initialized = {}, nil, nil, false
    local round = state.Round
    local function persist()
        local ok = pcall(function()
            assert(not blockSave, "Existing results files are damaged; preserving them")
            assert(writefile and readfile and isfolder and makefolder, "File APIs unavailable")
            if not isfolder(ROOT) then makefolder(ROOT) end
            slot, sequence = state.Slot or slot, state.Sequence or sequence
            local nextSlot = 1 - slot
            local path = ROOT .. (nextSlot == 0 and "/results-a.json" or "/results-b.json")
            local data = {Version = 1, Sequence = sequence + 1, Serial = state.Serial, Stats = state.Stats, Outbox = state.Outbox}
            local encoded = http:JSONEncode(data)
            writefile(path, encoded)
            assert(readfile(path) == encoded, "Results read-back failed")
            slot, sequence = nextSlot, sequence + 1
            state.Slot, state.Sequence = slot, sequence
        end)
        service.DiskSaved = ok
        diskError = not ok
        state.StorageError = diskError
    end
    local function clock() return os.clock() end
    local function context(kind, recording)
        local value = getContext() or {}
        local difficulty = framework and framework:Get("DifficultyController")
        local mode = difficulty and type(difficulty.Locked) == "string" and difficulty.Locked or settings.Difficulty
        return {Kind = kind or value.Kind or "Manual", Recording = recording or value.Recording,
            Recorder = env.PeriastronRecorder,
            Name = value.Name, Mode = mode,
            AutoSkip = settings.AutoSkip == true}
    end
    function service.Begin(kind, recording)
        if round and round.Won ~= nil then service.Flush() end
        local value = context(kind, recording)
        if round and not round.Closed then
            -- Starting another strategy halfway through a match cannot be a clean macro trial.
            if round.Kind ~= value.Kind or round.Recording ~= value.Recording then round.Kind = "Mixed / manual finish" end
            round.Recording, round.Name = value.Recording, value.Name
            return
        end
        value.Started, value.Wave = clock(), 0
        round, state.Round = value, value
    end
    function service.MarkStopped()
        if round and not round.Closed and round.Won == nil and round.Kind == "Replay" then round.Kind = "Replay stopped / manual finish" end
    end
    local function waveFallback()
        local ok, value = pcall(function()
            local gui = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
            local interface = gui and gui:FindFirstChild("Interface")
            local counter = interface and interface:FindFirstChild("WaveCounter")
            local number = counter and counter:FindFirstChild("Number")
            return number and tonumber(number.Text)
        end)
        return ok and value or nil
    end
    local function speed()
        local controller = framework and framework:Get("SpeedController")
        return ({"1x", "1.5x", "2x"})[controller and controller.Index] or "Unknown"
    end
    local function result(won, payload)
        if round and round.Closed then return end
        if not round then service.Begin("Manual") end
        if type(won) ~= "boolean" then return end
        if round.Won == nil then
            round.Won, round.Ended, round.FlushAt = won, clock(), clock() + 0.75
            round.Wave = math.max(round.Wave or 0, waveFallback() or 0)
            round.Speed = speed()
            local worker = env.PeriastronAutofarm
            if round.Kind == "Replay" and worker then
                if not worker.Running then round.Kind = "Replay stopped / manual finish" end
                round.Actions = math.min(math.max(0, (worker.Step or 1) - 1), worker.TotalSteps or 0)
                round.TotalActions = worker.TotalSteps
            end
        end
        -- RoundReward is authoritative and supplies rewards after Win/GameOver.
        if payload then round.Won, round.Rewards = won, payload.rewards end
    end
    local function truncate(value) return tostring(value or "Unknown"):sub(1, 900) end
    function service.Flush()
        if not round or round.Closed or round.Won == nil then return end
        round.Closed = true -- Mark first: no duplicate result from another event/retry.
        local recording = round.Recording
        if round.Kind == "Recording" and round.Recorder and round.Recorder.Snapshot then
            recording = round.Recorder.Snapshot() or recording
        end
        local name = recording and recording.ProfileName or round.Name or "No macro (manual)"
        local duration = math.max(0, math.floor((round.Ended or clock()) - round.Started))
        local kind, mode = round.Kind, round.Mode or "Unknown"
        local key = http:JSONEncode({name, mode, kind, round.Speed, round.AutoSkip})
        local stats = state.Stats[key]
        if type(stats) ~= "table" or type(stats.Wins) ~= "number" or type(stats.Losses) ~= "number" then
            stats = {Macro = name, Mode = mode, Kind = kind, Speed = round.Speed, AutoSkip = round.AutoSkip, Wins = 0, Losses = 0}
            state.Stats[key] = stats
        end
        if round.Won then stats.Wins = stats.Wins + 1 else stats.Losses = stats.Losses + 1 end
        local total = stats.Wins + stats.Losses
        local fields = {}
        local function field(title, value, inline)
            table.insert(fields, {name = title, value = truncate(value), inline = inline ~= false})
        end
        field("Macro", name, false)
        field("Mode", mode); field("Run type", kind)
        if not round.Won then field("Lose at wave", (round.Wave or 0) > 0 and round.Wave or "Unknown") end
        field("Duration", string.format("%d:%02d", math.floor(duration / 60), duration % 60))
        field("Speed", round.Speed); field("Auto skip", round.AutoSkip and "ON" or "OFF")
        field("Win rate", string.format("%.1f%% | %d wins / %d losses | %d matches", stats.Wins / total * 100, stats.Wins, stats.Losses, total), false)
        if round.TotalActions then field("Macro actions completed", tostring(round.Actions) .. " / " .. round.TotalActions) end
        if type(round.Rewards) == "table" then
            local parts = {}
            for _, entry in ipairs({{"coins", "coins"}, {"shards", "shards"}, {"xp", "XP"}}) do
                local amount = round.Rewards[entry[1]]
                if type(amount) == "number" then table.insert(parts, tostring(amount) .. " " .. entry[2]) end
            end
            if #parts > 0 then field("Rewards", table.concat(parts, " | "), false) end
        end
        state.Serial = (state.Serial or 0) + 1
        local id = tostring(os.time()) .. "-" .. state.Serial .. "-" .. math.random(100000, 999999)
        local item = {ID = id, Attempts = 0, RetryAt = 0, Payload = {
            username = "Periastron results", allowed_mentions = {parse = {}},
            embeds = {{title = round.Won and "WIN" or "LOSE", color = round.Won and 4511146 or 15885444,
                fields = fields, timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                footer = {text = "Win rate: same macro, mode, run type, speed & skip | Report " .. id}}},
        }}
        table.insert(state.Outbox, item)
        service.LastResult = {Won = round.Won, Macro = name, Wave = round.Wave, WinRate = stats.Wins / total * 100}
        service.Status = "Discord: result queued"
        persist()
    end
    local function requestFunction()
        return request or http_request or (syn and syn.request) or (type(executorHttp) == "table" and executorHttp.request)
            or env.request or (type(env.http) == "table" and env.http.request)
    end
    local function deliver()
        if state.Sending or clock() < (state.NextSendAt or 0) then return end
        local send = requestFunction()
        local chosen
        for _, item in ipairs(state.Outbox) do
            if not item.Failed and clock() >= (item.RetryAt or 0) then chosen = item; break end
        end
        if not chosen then
            for _, item in ipairs(state.Outbox) do
                if item.Failed then service.Status = "Discord: rejected report kept locally"; break end
            end
            return
        end
        if type(send) ~= "function" then service.Status = "Discord: queued (HTTP request API unavailable)"; return end
        state.Sending = chosen.ID
        -- Network work runs separately; it never waits in recording/replay or event callbacks.
        task.spawn(function()
            chosen.Attempts = (chosen.Attempts or 0) + 1
            local ok, response = pcall(function()
                return send({Url = WEBHOOK, Method = "POST", Headers = {["Content-Type"] = "application/json"},
                    Body = http:JSONEncode(chosen.Payload)})
            end)
            local code = ok and type(response) == "table" and tonumber(response.StatusCode or response.Status)
            if code and code >= 200 and code < 300 then
                for index, item in ipairs(state.Outbox) do if item == chosen then table.remove(state.Outbox, index); break end end
                service.Status = "Discord: result sent"
            elseif code == 429 then
                local retry = 5
                pcall(function() retry = tonumber(http:JSONDecode(response.Body or "{}").retry_after) or retry end)
                local headers = response.Headers or {}
                retry = tonumber(headers["Retry-After"] or headers["retry-after"]) or retry
                chosen.RetryAt = clock() + math.max(1, retry)
                state.NextSendAt = chosen.RetryAt
                service.Status = "Discord: rate limited; retry queued"
            elseif code and code >= 400 and code < 500 then
                chosen.Failed = true
                service.Status = "Discord: rejected (HTTP " .. code .. "); result kept locally"
            else
                chosen.RetryAt = clock() + math.min(300, 5 * 2 ^ math.min(chosen.Attempts - 1, 6))
                service.Status = "Discord: network/server error; retry queued"
            end
            persist()
            state.Sending = nil
        end)
    end
    local function listen(name, callback, reliable, module)
        if not reliable:GetAttribute(name) then return end
        local event = framework.Events[name]
        if not event then factory = factory or require(module); event = factory(name); framework.Events[name] = event end
        table.insert(subscriptions, {Event = event, Key = event:Connect(function(...)
            local ok = pcall(callback, ...)
            if not ok then service.Status = "Discord: reporter error; macro continues" end
        end)})
    end
    local function initialize()
        framework = getFramework()
        if not framework then return end
        -- A missing module during startup must not multiply successful earlier subscriptions.
        for _, item in ipairs(subscriptions) do pcall(function() item.Event:Disconnect(item.Key) end) end
        subscriptions = {}
        local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
        local reliable, module = shared.Vendor.Warp.Index.Event.Reliable, shared.Vendor.Warp.Index.Client.Index
        listen("SetWave", function(number)
            if type(number) ~= "number" or number <= 0 then return end
            if round and round.Closed then return end -- Only RoundRestarted opens the next match.
            if not round then service.Begin() end
            round.Wave = math.max(round.Wave or 0, number)
        end, reliable, module)
        listen("DifficultyLocked", function(value)
            if round and not round.Closed and type(value) == "string" then round.Mode = value end
        end, reliable, module)
        listen("Win", function() result(true) end, reliable, module)
        listen("GameOver", function() result(false) end, reliable, module)
        listen("RoundReward", function(payload)
            if type(payload) == "table" then result(payload.won, payload) end
        end, reliable, module)
        listen("RoundRestarted", function()
            service.Flush()
            round, state.Round = nil, nil
            service.Begin()
        end, reliable, module)
        initialized = true
    end
    function service.Update()
        if not service.Running then return end
        local ok = pcall(function()
            if not initialized then initialize() end
            if round and round.Won ~= nil and not round.Closed and clock() >= round.FlushAt then service.Flush() end
            deliver()
        end)
        if not ok then service.Status = "Discord: reporter error; macro continues" end
        service.StorageWarning = (diskError or state.StorageError) and " | results session only" or ""
    end
    function service.Stop()
        -- Report a confirmed result even if the panel closes during the reward animation.
        service.Flush()
        service.Running = false
        for _, item in ipairs(subscriptions) do pcall(function() item.Event:Disconnect(item.Key) end) end
        subscriptions = {}
    end
    service.Update()
    return service
end

-- Native in-game controls; the replay and recorder are embedded above this panel.
local env = (getgenv and getgenv()) or _G
if env.PeriastronFarmUI and env.PeriastronFarmUI.Destroy then env.PeriastronFarmUI.Destroy() end
if env.PeriastronAutofarm and env.PeriastronAutofarm.Stop then env.PeriastronAutofarm.Stop() end
if env.PeriastronRecorder and env.PeriastronRecorder.Stop then env.PeriastronRecorder.Stop() end
local player = game:GetService("Players").LocalPlayer
assert(player, "Open this UI in the main-game client")
local playerGui = player:WaitForChild("PlayerGui", 30)
local input = game:GetService("UserInputService")
local runService = game:GetService("RunService")
local hadSettings = env.PeriastronUIOptions ~= nil
local store = openProfileStore(env)
local settings, savedProfile = store.LoadSettings(env.PeriastronUIOptions)
env.PeriastronUIOptions = settings
env.PeriastronProfileSaver = store.Save
local currentProfile = env.PeriastronCurrentProfile or savedProfile
if currentProfile and not store.Data.Profiles[currentProfile] then
    if env.PeriastronReplay and env.PeriastronReplay.ProfileName == currentProfile then env.PeriastronReplay = nil end
    currentProfile, env.PeriastronCurrentProfile = nil, nil
end
local UI = {Running = true, Status = "Choose Record round to capture your strategy, or load a saved recording."}
env.PeriastronFarmUI = UI
local connections, active, minimized = {}, nil, false
local framework, config
local function gameModules()
    if framework then return true end
    local ok = pcall(function()
        local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
        assert(shared, "Main-game modules are not loaded")
        framework = require(shared.Vendor.Me).new()
        config = require(shared.Config.SharedConfig)
    end)
    return ok
end
local function controller(name)
    if not gameModules() then return nil end
    return framework:Get(name)
end
local autoSkip = openAlwaysSkip(settings, function()
    if gameModules() then return framework end
end)
UI.AutoSkip = autoSkip
local results = openResultReporter(env, settings, function()
    if gameModules() then return framework end
end, function()
    local replay = env.PeriastronAutofarm
    local recorder = env.PeriastronRecorder
    if replay and replay.Running then
        return {Kind = "Replay", Recording = env.PeriastronReplay, Name = currentProfile}
    elseif recorder and recorder.Running then
        return {Kind = "Recording", Recording = recorder.Snapshot(), Name = env.PeriastronRecordingName}
    end
    return {Kind = "Manual", Name = "No macro (manual)"}
end)
UI.Results = results
local colors = {
    Background = Color3.fromRGB(15, 20, 31), Panel = Color3.fromRGB(24, 32, 46),
    Border = Color3.fromRGB(48, 61, 80), Text = Color3.fromRGB(237, 242, 249),
    Muted = Color3.fromRGB(151, 168, 191), Accent = Color3.fromRGB(68, 213, 170),
    Ink = Color3.fromRGB(9, 32, 26), Red = Color3.fromRGB(242, 130, 132),
}
local function make(class, parent, props)
    local item = Instance.new(class)
    for key, value in pairs(props or {}) do item[key] = value end
    item.Parent = parent
    return item
end
local function corner(item, radius) make("UICorner", item, {CornerRadius = UDim.new(0, radius or 8)}) end
local function connect(signal, callback)
    table.insert(connections, signal:Connect(callback))
end
local old = playerGui:FindFirstChild("PeriastronFarmPanel")
if old then old:Destroy() end
local screen = make("ScreenGui", playerGui, {
    Name = "PeriastronFarmPanel", ResetOnSpawn = false, DisplayOrder = 10000,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local root = make("Frame", screen, {
    Name = "Panel", Size = UDim2.fromOffset(390, 748), Position = UDim2.new(0, 24, 0.5, 0),
    AnchorPoint = Vector2.new(0, 0.5),
    BackgroundColor3 = colors.Background, BorderSizePixel = 0,
})
corner(root, 14)
make("UIStroke", root, {Color = colors.Border, Thickness = 1})
local scale = make("UIScale", root, {Scale = 1})
local header = make("Frame", root, {Name = "DragHeader", Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1, Active = true})
local function label(parent, name, text, x, y, w, h, size, color)
    return make("TextLabel", parent, {
        Name = name, Text = text, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = size or 13,
        TextColor3 = color or colors.Text, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
end
label(header, "Title", "Periastron farm", 18, 12, 270, 25, 20)
label(header, "Subtitle", "Record once. Replay each round.", 18, 39, 310, 18, 12, colors.Muted)
local body = make("Frame", root, {Name = "Controls", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 1, -64), BackgroundTransparency = 1})
local function button(parent, name, text, x, y, w, h, accent)
    local item = make("TextButton", parent, {
        Name = name, Text = text, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = accent and colors.Accent or colors.Panel, BorderSizePixel = 0,
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = accent and colors.Ink or colors.Text,
        AutoButtonColor = true,
    })
    corner(item, 8)
    return item
end
local minimize = button(header, "Minimize", "-", 312, 13, 26, 26)
local close = button(header, "Close", "x", 346, 13, 26, 26)
label(body, "ModeLabel", "MODE", 16, 14, 200, 18, 11, colors.Muted)
local modeButton = button(body, "ModeSelect", "Medium  v", 16, 37, 358, 34)
label(body, "SpeedLabel", "SPEED BOOST", 16, 85, 200, 18, 11, colors.Muted)
local speedButtons = {}
local speedNames = {"1x", "1.5x", "2x"}
for index, name in ipairs(speedNames) do
    speedButtons[index] = button(body, "Speed" .. index, name, 16 + (index - 1) * 122, 108, 114, 34)
end
local retryButton = button(body, "AutoReplay", "Auto replay: ON", 16, 158, 175, 30)
local readyButton = button(body, "AutoReady", "Ready waves: ON", 199, 158, 175, 30)
local skipButton = button(body, "AutoSkip", "Auto skip: ON", 16, 194, 358, 30)
label(body, "ProfileLabel", "SAVED MACRO FOR THIS MAP", 16, 233, 358, 18, 11, colors.Muted)
local profileButton = button(body, "ProfileSelect", "Choose saved macro  v", 16, 255, 358, 32)
local nameBox = make("TextBox", body, {
    Name = "ProfileName", Text = currentProfile or "My macro", PlaceholderText = "Macro name, e.g. Forest Medium",
    Position = UDim2.fromOffset(16, 297), Size = UDim2.fromOffset(240, 32),
    BackgroundColor3 = colors.Panel, BorderSizePixel = 0, TextColor3 = colors.Text,
    PlaceholderColor3 = colors.Muted, Font = Enum.Font.Gotham, TextSize = 12, ClearTextOnFocus = false,
})
corner(nameBox)
local saveProfileButton = button(body, "SaveProfile", "Save as", 264, 297, 110, 32)
local planCard = make("Frame", body, {
    Name = "RecordingCard", Position = UDim2.fromOffset(16, 342), Size = UDim2.fromOffset(358, 68),
    BackgroundColor3 = colors.Panel, BorderSizePixel = 0,
})
corner(planCard)
local planLabel = label(planCard, "RecordingTitle", "No recorded macro", 12, 9, 235, 22, 13)
local planHelp = label(planCard, "RecordingHelp", "Select a saved macro or record a round.", 12, 35, 334, 24, 11, colors.Muted)
planHelp.TextWrapped = true
local loadButton = button(planCard, "LoadSaved", "Import old", 253, 8, 94, 25)
loadButton.TextSize = 11
planHelp.Size = UDim2.fromOffset(235, 24)
local recoverButton = button(planCard, "RecoverDraft", "Recover draft", 253, 35, 94, 25)
recoverButton.TextSize = 11
local recordButton = button(body, "RecordRound", "Record round", 16, 422, 175, 36)
local saveButton = button(body, "SaveRecording", "Finish & save", 199, 422, 175, 36)
local startButton = button(body, "StartReplay", "Start replay", 16, 468, 175, 40, true)
local stopButton = button(body, "Stop", "Stop", 199, 468, 175, 40)
stopButton.TextColor3 = colors.Red
local statusCard = make("Frame", body, {
    Name = "StatusCard", Position = UDim2.fromOffset(16, 526), Size = UDim2.fromOffset(358, 54),
    BackgroundColor3 = colors.Panel, BorderSizePixel = 0,
})
corner(statusCard)
local statusLabel = label(statusCard, "Status", UI.Status, 12, 5, 334, 44, 12)
statusLabel.TextWrapped = true
local statsLabel = label(body, "Progress", "Idle", 16, 586, 358, 20, 11, colors.Muted)
local actualSpeed = label(body, "ActiveSpeed", "Speed: waiting for game", 16, 608, 358, 20, 11, colors.Muted)
local storageLabel = label(body, "Help", "Files: Periastron Tower Defense", 16, 631, 358, 18, 10, colors.Muted)
local resultLabel = label(body, "ResultStatus", results.Status, 16, 652, 358, 28, 10, colors.Muted)
resultLabel.TextWrapped = true
local profileMenu = make("ScrollingFrame", body, {
    Name = "ProfileMenu", Position = UDim2.fromOffset(16, 291), Size = UDim2.fromOffset(358, 40),
    CanvasSize = UDim2.fromOffset(0, 0), ScrollBarThickness = 4, BackgroundColor3 = colors.Panel,
    BorderSizePixel = 0, Visible = false, ZIndex = 30,
})
corner(profileMenu)
local menu = make("Frame", body, {
    Name = "ModeMenu", Position = UDim2.fromOffset(16, 76), Size = UDim2.fromOffset(358, 160),
    BackgroundColor3 = colors.Panel, BorderSizePixel = 0, Visible = false, ZIndex = 20,
})
corner(menu)
make("UIStroke", menu, {Color = colors.Border, Thickness = 1})
local modeConnections = {}
local profileConnections = {}
local function persistSettings()
    local saved = store.SaveSettings(settings, currentProfile)
    storageLabel.Text = "Files: Periastron Tower Defense" .. (saved and "" or " | settings session only")
end
local function applySettings()
    if env.PeriastronAutofarm and env.PeriastronAutofarm.Running then
        env.PeriastronAutofarm.SetOptions(settings)
    end
    autoSkip.Update()
    persistSettings()
end
local function setMessage(text) UI.Status = text; statusLabel.Text = text end
local function stopWorkers()
    results.MarkStopped()
    if env.PeriastronAutofarm and env.PeriastronAutofarm.Stop then env.PeriastronAutofarm.Stop() end
    if env.PeriastronRecorder and env.PeriastronRecorder.Stop then env.PeriastronRecorder.Stop() end
    active = nil
end
function UI.Destroy()
    currentProfile = env.PeriastronCurrentProfile
    persistSettings()
    UI.Running = false
    autoSkip.Stop()
    results.Stop()
    stopWorkers()
    for _, item in ipairs(connections) do item:Disconnect() end
    for _, item in ipairs(modeConnections) do item:Disconnect() end
    for _, item in ipairs(profileConnections) do item:Disconnect() end
    screen:Destroy()
end
local function busy()
    return (env.PeriastronAutofarm and env.PeriastronAutofarm.Running)
        or (env.PeriastronRecorder and env.PeriastronRecorder.Running)
end
local function selectProfile(name, restoreOptions)
    local _, options = store.Load(name)
    currentProfile = name
    nameBox.Text = name
    if restoreOptions ~= false then
        for _, key in ipairs({"Difficulty", "SpeedIndex", "AutoRetry", "AutoReady", "AutoSkip"}) do
            if options[key] ~= nil then settings[key] = options[key] end
        end
    end
    autoSkip.Update()
    persistSettings()
    profileMenu.Visible = false
    setMessage("Loaded " .. name .. ". Use it on the matching map, then Start replay.")
end
local function importOld(quiet)
    local ok, name, location = pcall(store.ImportLegacy, quiet and env.PeriastronReplay or nil, settings)
    if ok then selectProfile(name); if not quiet then setMessage("Imported " .. name .. " (" .. location .. ")") end
    elseif not quiet then setMessage(tostring(name)) end
    return ok
end
local function rebuildProfiles()
    local refreshed, err = store.Refresh()
    if refreshed == false then setMessage(err) end
    for _, item in ipairs(profileConnections) do item:Disconnect() end
    profileConnections = {}
    for _, item in ipairs(profileMenu:GetChildren()) do if item:IsA("TextButton") then item:Destroy() end end
    local names = store.Names()
    profileMenu.Size = UDim2.fromOffset(358, math.min(224, math.max(39, #names * 31 + 8)))
    profileMenu.CanvasSize = UDim2.fromOffset(0, #names * 31 + 8)
    if #names == 0 then
        local item = button(profileMenu, "NoProfiles", "No saved macros yet", 6, 4, 346, 29)
        item.ZIndex = 31
    end
    for index, name in ipairs(names) do
        local item = button(profileMenu, "Profile_" .. name, name, 6, 4 + (index - 1) * 31, 346, 29)
        item.ZIndex = 31
        table.insert(profileConnections, item.Activated:Connect(function()
            if busy() then setMessage("Stop replay or finish recording before changing macros."); return end
            local ok, err = pcall(selectProfile, name)
            if not ok then setMessage(tostring(err)) end
        end))
    end
end
local function rebuildModes()
    for _, item in ipairs(modeConnections) do item:Disconnect() end
    modeConnections = {}
    for _, item in ipairs(menu:GetChildren()) do if item:IsA("TextButton") then item:Destroy() end end
    local difficulty = controller("DifficultyController")
    local names = {}
    local preferred = {"Medium", "Easy", "Hard", "Impossible", "Nightmare"}
    if difficulty and difficulty.Buttons and next(difficulty.Buttons) then
        for _, name in ipairs(preferred) do if difficulty.Buttons[name] then table.insert(names, name) end end
        for name in pairs(difficulty.Buttons) do if not table.find(names, name) then table.insert(names, name) end end
    else names = {"Medium", "Hard", "Impossible", "Nightmare"} end
    menu.Size = UDim2.fromOffset(358, 8 + #names * 31)
    for index, name in ipairs(names) do
        local locked = config and config.DifficultyUnlockConfig and difficulty and difficulty.stats
            and not config.DifficultyUnlockConfig.isUnlocked(name, difficulty:stats())
        local option = button(menu, "Mode_" .. name, name .. (locked and " (locked)" or ""), 6, 4 + (index - 1) * 31, 346, 29)
        option.ZIndex = 21
        if locked then option.TextColor3 = colors.Muted end
        table.insert(modeConnections, option.Activated:Connect(function()
            if locked then setMessage("That mode is locked. Choose an unlocked mode."); return end
            settings.Difficulty = name
            menu.Visible = false
            applySettings()
        end))
    end
end
connect(modeButton.Activated, function() profileMenu.Visible = false; rebuildModes(); menu.Visible = not menu.Visible end)
connect(profileButton.Activated, function() menu.Visible = false; rebuildProfiles(); profileMenu.Visible = not profileMenu.Visible end)
for index, item in ipairs(speedButtons) do
    connect(item.Activated, function() settings.SpeedIndex = index; applySettings() end)
end
connect(retryButton.Activated, function() settings.AutoRetry = not settings.AutoRetry; applySettings() end)
connect(readyButton.Activated, function() settings.AutoReady = not settings.AutoReady; applySettings() end)
connect(skipButton.Activated, function() settings.AutoSkip = not settings.AutoSkip; applySettings() end)
connect(loadButton.Activated, function()
    if busy() then setMessage("Stop recording or replay before importing."); return end
    importOld(false)
end)
connect(saveProfileButton.Activated, function()
    if busy() then setMessage("Stop replay or finish recording before using Save as."); return end
    local ok, name, location, verified = pcall(store.Save, nameBox.Text, env.PeriastronReplay, settings)
    if ok then currentProfile = name; nameBox.Text = name; setMessage((verified and "Saved and verified " or "NOT saved to disk: ") .. name .. " (" .. location .. ")")
    else setMessage(tostring(name)) end
end)
connect(recordButton.Activated, function()
    local name = nameBox.Text:match("^%s*(.-)%s*$")
    if #name == 0 or #name > 60 then setMessage("Enter a macro name between 1 and 60 characters."); return end
    local writable, reason = store.CheckRecordingPersistence()
    if not writable then setMessage("Recording not started: " .. tostring(reason)); return end
    stopWorkers()
    menu.Visible, profileMenu.Visible = false, false
    env.PeriastronRecordingName = name
    local ok, err = pcall(launchRecorder)
    if ok then
        active = "record"
        results.Begin("Recording", env.PeriastronRecorder.Snapshot())
        setMessage("Recording " .. name .. ". Play manually, then Finish & save.")
    else stopWorkers(); setMessage("Could not start recorder: " .. tostring(err)) end
end)
connect(saveButton.Activated, function()
    local recorder = env.PeriastronRecorder
    if not recorder or (not recorder.Running and (not recorder.Snapshot or not recorder.Snapshot())) then
        setMessage("Start Record round first, or use Recover draft for a retained recording."); return
    end
    local ok, err = pcall(recorder.Finish)
    if not ok then setMessage("Could not save; draft retained: " .. tostring(err))
    else setMessage(recorder.Status) end
end)
connect(recoverButton.Activated, function()
    if busy() then setMessage("Finish or stop the macro before recovering a draft."); return end
    local ok, draft = pcall(store.LoadDraft)
    if not ok then setMessage(tostring(draft)); return end
    local saved, name, location, verified = pcall(store.Save, draft.ProfileName or "Recovered macro", draft, settings)
    if saved then
        currentProfile, nameBox.Text = name, name
        setMessage((verified and "Recovered and verified " or "Recovered in memory; NOT saved to disk: ")
            .. #draft.Steps .. " actions (" .. tostring(location) .. ")")
    else setMessage("Recovery file save failed: " .. tostring(name)) end
end)
connect(startButton.Activated, function()
    local recorder = env.PeriastronRecorder
    if recorder and recorder.Running then setMessage("Save your recording before starting replay."); return end
    store.Refresh()
    local recording = env.PeriastronReplay
    if type(recording) ~= "table" or recording.Complete ~= true then
        setMessage("Select a saved macro or record and save a round first."); return
    end
    stopWorkers()
    menu.Visible, profileMenu.Visible = false, false
    local ok, err = pcall(launchReplay)
    if ok then
        active = "replay"
        results.Begin("Replay", recording)
        setMessage("Starting replay...")
    else stopWorkers(); setMessage("Could not start replay: " .. tostring(err)) end
end)
connect(stopButton.Activated, function() stopWorkers(); setMessage("Macro stopped. Auto skip still follows its toggle.") end)
connect(close.Activated, UI.Destroy)
connect(minimize.Activated, function()
    minimized = not minimized
    body.Visible = not minimized
    menu.Visible, profileMenu.Visible = false, false
    root.Size = UDim2.fromOffset(390, minimized and 64 or 748)
    minimize.Text = minimized and "+" or "-"
end)
local dragging, startPointer, startPosition, touchInput
connect(header.InputBegan, function(key)
    if key.UserInputType == Enum.UserInputType.MouseButton1 or key.UserInputType == Enum.UserInputType.Touch then
        dragging, startPointer, startPosition = true, key.Position, root.Position
        touchInput = key.UserInputType == Enum.UserInputType.Touch and key or nil
    end
end)
connect(input.InputChanged, function(key)
    if dragging and (key.UserInputType == Enum.UserInputType.MouseMovement or key == touchInput) then
        local delta = key.Position - startPointer
        root.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X,
            startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
    end
end)
connect(input.InputEnded, function(key)
    if key.UserInputType == Enum.UserInputType.MouseButton1 or key == touchInput then dragging = false end
end)
connect(input.InputBegan, function(key, processed)
    if not processed and key.KeyCode == Enum.KeyCode.F8 then stopWorkers(); setMessage("Macro stopped with F8. Auto skip follows its toggle.") end
end)
local elapsed = 1
local function refresh()
    autoSkip.Update()
    results.Update()
    resultLabel.Text = results.Status .. (results.StorageWarning or "")
    storageLabel.Text = "Files: Periastron Tower Defense" .. (store.SettingsSaved and "" or " | settings session only")
    modeButton.Text = settings.Difficulty .. "  v"
    for index, item in ipairs(speedButtons) do
        item.BackgroundColor3 = settings.SpeedIndex == index and colors.Accent or colors.Panel
        item.TextColor3 = settings.SpeedIndex == index and colors.Ink or colors.Text
    end
    retryButton.Text = "Auto replay: " .. (settings.AutoRetry and "ON" or "OFF")
    readyButton.Text = "Ready waves: " .. (settings.AutoReady and "ON" or "OFF")
    skipButton.Text = "Auto skip: " .. (settings.AutoSkip and "ON" or "OFF")
    if settings.AutoSkip then
        if autoSkip.Error then skipButton.Text = "Auto skip: error"
        elseif autoSkip.Supported == false then skipButton.Text = "Auto skip: unavailable"
        elseif autoSkip.Status == "Voted to skip" then skipButton.Text = "Auto skip: ON - vote sent" end
    end
    if env.PeriastronCurrentProfile ~= currentProfile then
        currentProfile = env.PeriastronCurrentProfile
        if currentProfile then nameBox.Text = currentProfile end
    end
    profileButton.Text = (currentProfile or "Choose saved macro") .. "  v"
    local recording = env.PeriastronReplay
    if recording and recording.Complete then
        local profile = currentProfile and store.Data.Profiles[currentProfile]
        local verified = profile and profile.Recording == recording and store.Files[currentProfile] and not store.Session[currentProfile]
        planLabel.Text = (verified and "Saved: " or "Recorded: ") .. #recording.Placements .. " towers / " .. #recording.Steps .. " actions"
        planHelp.Text = verified and "Ready to replay. Use the same map and deck." or "Kept in memory. Save as or Recover draft to save a file."
    elseif recording then
        planLabel.Text = "Captured: " .. #(recording.Steps or {}) .. " actions"
        planHelp.Text = "Finish a manual round, or press Finish & save."
    else
        planLabel.Text = "No recorded macro"
        planHelp.Text = "Select a saved macro or record a round."
    end
    local worker = active == "record" and env.PeriastronRecorder or active == "replay" and env.PeriastronAutofarm
    if worker then
        statusLabel.Text = worker.Status
        if active == "replay" then
            statsLabel.Text = string.format("Cash: %s   Step: %d/%d   Rounds: %d", tostring(worker.Cash or "--"),
                math.min(worker.Step or 0, worker.TotalSteps or 0), worker.TotalSteps or 0, worker.Rounds or 0)
        else statsLabel.Text = "Play manually while recording. F7 saves early." end
        if not worker.Running then UI.Status = worker.Status; active = nil end
    else statusLabel.Text = UI.Status; statsLabel.Text = "Idle - no replay or recording is running" end
    local speed = controller("SpeedController")
    if speed then
        local passLocked = settings.SpeedIndex == 3 and not speed:isUnlocked(3)
        actualSpeed.Text = "Speed: " .. (speedNames[speed.Index] or "--") .. " active / " .. speedNames[settings.SpeedIndex]
            .. (passLocked and " requested (Speed pass required)" or " selected")
    end
    local camera = workspace.CurrentCamera
    if camera then
        local viewport = camera.ViewportSize
        scale.Scale = math.max(0.35, math.min(1, (viewport.X - 48) / 390, (viewport.Y - 48) / (minimized and 64 or 748)))
    end
end
connect(runService.Heartbeat, function(dt)
    if not UI.Running then return end
    elapsed = elapsed + dt
    if elapsed >= 0.25 then elapsed = 0; refresh() end
end)
local names = store.Names()
local restoreInitialOptions = not (store.HasSavedSettings or hadSettings)
if currentProfile and store.Data.Profiles[currentProfile] then selectProfile(currentProfile, restoreInitialOptions)
elseif #names > 0 then selectProfile(names[1], restoreInitialOptions)
elseif not store.LegacyImported then importOld(true) end
persistSettings()
if store.Error then setMessage(store.Error .. "; existing file will not be overwritten.") end
refresh()
