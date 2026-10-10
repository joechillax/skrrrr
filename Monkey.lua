pcall(function() game:GetService("GuiService"):SetGameplayPausedNotificationEnabled(false) end)

if not game:IsLoaded() then game.Loaded:Wait() end

local VERSION = 1.3
local env = getgenv()
if (env.MonkeyVersion or 0) > VERSION then return end
env.MonkeyVersion = VERSION
if env.MonkeyCleanup then pcall(env.MonkeyCleanup) end
env.MonkeyGen = (env.MonkeyGen or 0) + 1
local gen = env.MonkeyGen
local function alive() return env.MonkeyGen == gen end
local teardown = {}
local cleaning = false
local function cleanup()
    if cleaning then return end
    cleaning = true
    if alive() then env.MonkeyGen = env.MonkeyGen + 1 end
    for i = #teardown, 1, -1 do
        local ok = pcall(teardown[i])
        if ok then table.remove(teardown, i) end
    end
    cleaning = false
    if #teardown == 0 and env.MonkeyCleanup == cleanup then env.MonkeyCleanup = nil end
end
env.MonkeyCleanup = cleanup

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    LobbyPlace = 99409088950210,
    Map = "Cove",
    DeathSpot = Vector3.new(64, 5, 20),
    SourceFile = "MonkeyHorde/MonkeyHorde.lua",
}
local IN_LOBBY = game.PlaceId == CONFIG.LobbyPlace

local SAFE_SPOT = Vector3.new(66, 6, 53)
local SAFE_FALL_Y = 3.5
local OUT_OF_MAP_Y = -100
local STALL_TIMEOUT = 50
local STAIR_TRANSPARENCY = 0.7
local PLACEMENTS = { Barricade = true }
local RESUME_WINDOW = 600
local HEARTBEAT_SAVE = 30
local REPLAY_DELAY = 8
local NEWRUN_FALLBACK = 10

local S = {
    AutoKill = false, SafeSpot = false, AutoSkip = false, Upgrades = {}, Abilities = {},
    Autofarm = false, Difficulty = "Normal", StopWave = 20,
    Movement = "Ground pursuit",
}
local Rayfield, held, lastTargetId, abilityDropdown, autofarmToggle
local killToggle, safeToggle, skipToggle, movementDropdown
local uiReady = false
local conns = {}
teardown[#teardown + 1] = function()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    table.clear(conns)
end
local fireModes = setmetatable({}, { __mode = "k" })
local toolInfoCache = setmetatable({}, { __mode = "k" })

local suspended = false
local lastEquip = 0

local syncing = false
local function syncUI()
    local map = { AutoKill = killToggle, SafeSpot = safeToggle, AutoSkip = skipToggle }
    syncing = true
    for key, t in pairs(map) do
        if t then pcall(function() t:Set(S[key]) end) end
    end
    if movementDropdown then pcall(function() movementDropdown:Set({ S.Movement }) end) end
    syncing = false
end

local STATE_DIR, STATE_FILE = "MonkeyHorde", "MonkeyHorde/state.json"
local HAS_FILES = writefile ~= nil and readfile ~= nil and isfile ~= nil
local state = {}

local function loadState()
    if not HAS_FILES or not isfile(STATE_FILE) then return end
    local ok, t = pcall(function() return HttpService:JSONDecode(readfile(STATE_FILE)) end)
    if ok and type(t) == "table" then state = t end
end

local function saveState()
    if not writefile then return end
    pcall(function()
        if makefolder and isfolder and not isfolder(STATE_DIR) then makefolder(STATE_DIR) end
        writefile(STATE_FILE, HttpService:JSONEncode(state))
    end)
end

loadState()
if state.combatMovement == "Stay here" or state.combatMovement == "Safe spot (legacy)"
    or state.combatMovement == "Ground pursuit" then S.Movement = state.combatMovement end

local function persistAutofarm(on)
    state.autofarm = on
    state.autofarmAt = os.time()
    state.difficulty, state.stopWave, state.combatMovement = S.Difficulty, S.StopWave, S.Movement
    saveState()
end

local function resumeWanted()
    if not HAS_FILES then return env.MonkeyAutofarm == true end
    return state.autofarm == true
        and type(state.autofarmAt) == "number"
        and os.time() - state.autofarmAt < RESUME_WINDOW
end

if state.difficulty == "Normal" or state.difficulty == "Hardcore" then S.Difficulty = state.difficulty end
if type(state.stopWave) == "number" and state.stopWave >= 1 then S.StopWave = math.floor(state.stopWave) end
local RESUMING = resumeWanted()

if RESUMING and not IN_LOBBY and S.Movement == "Safe spot (legacy)" then
    S.SafeSpot = true
    task.spawn(function()
        local stop = os.clock() + 30
        while alive() and S.SafeSpot and os.clock() < stop do
            local ch = LocalPlayer.Character
            local root = ch and ch:FindFirstChild("HumanoidRootPart")
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            if root and hum and hum.Health > 0 and (root.Position - SAFE_SPOT).Magnitude > 10 then
                ch:PivotTo(CFrame.new(SAFE_SPOT))
                root.AssemblyLinearVelocity = Vector3.zero
            end
            task.wait(0.05)
        end
    end)
end

local function waitPath(root, timeout, ...)
    local node, deadline = root, os.clock() + timeout
    for _, name in ipairs({ ... }) do
        node = node:WaitForChild(name, math.max(0.1, deadline - os.clock()))
        if not node then return nil end
    end
    return node
end

local function findPath(root, ...)
    local node = root
    for _, name in ipairs({ ... }) do
        node = node and node:FindFirstChild(name)
    end
    return node
end

local function requireNode(node)
    if not node then return end
    local ok, m = pcall(require, node)
    if ok and type(m) == "table" then return m end
end

local function loadMod(...) return requireNode(waitPath(RS, 10, ...)) end

local GunRig, TargetWorld, UnitView, Ballistics
local Catalog, Progression, BulletProfiles, WeaponData, WeaponGeometry
if not IN_LOBBY then
    GunRig = loadMod("GunKit", "Controllers", "GunRigController")
    TargetWorld = loadMod("GunKit", "Shared", "Weapons", "TargetWorld")
    UnitView = requireNode(waitPath(LocalPlayer, 10, "PlayerScripts", "Client", "Controllers", "UnitViewController"))
    Ballistics = loadMod("GunKit", "Shared", "Weapons", "Ballistics")
    Catalog = loadMod("Shared", "Content", "Catalog")
    Progression = loadMod("Shared", "Content", "Progression")
    BulletProfiles = loadMod("GunKit", "Shared", "Weapons", "BulletVisualProfiles")
    WeaponGeometry = loadMod("GunKit", "Shared", "Weapons", "WeaponGeometry")
    WeaponData = requireNode(findPath(LocalPlayer, "PlayerScripts", "Client", "Controllers", "DataController"))
    local ch = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    ch:WaitForChild("HumanoidRootPart", 15)
end
if not alive() then return end
local PEN = (Ballistics and Ballistics.Penetration) or 10

local function getRoot()
    local ch = LocalPlayer.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local ch = LocalPlayer.Character
    return ch and ch:FindFirstChildOfClass("Humanoid")
end

local function currentTool()
    local ch = LocalPlayer.Character
    return ch and ch:FindFirstChildOfClass("Tool")
end

local function playerGui() return LocalPlayer:FindFirstChild("PlayerGui") end

local function notify(title, content)
    if not Rayfield then return end
    pcall(function()
        Rayfield:Notify({ Title = title, Content = content, Duration = 6 })
    end)
end

local lastLoopError
local function loop(interval, fn)
    task.spawn(function()
        while alive() do
            local ok, err = pcall(fn)
            if not ok then lastLoopError = tostring(err); task.wait(1) end
            task.wait(interval)
        end
    end)
end

local function toList(opt)
    if type(opt) == "table" then return opt end
    return { opt }
end

-- Reconcile rendered units at a bounded rate. The fast aim callback never scans the map.
local unitBuf, nearP, nearD = {}, {}, {}
local combat = {
    snapshots = setmetatable({}, { __mode = "k" }), records = {}, unitsAt = -math.huge,
    aimCalls = 0, activations = 0, lastError = nil, target = nil, confirmedKills = 0,
    targetAt = 0, targetTool = nil, speed = nil, lastAimAt = 0,
    status = "Idle", config = nil, tool = nil, candidates = {},
    crowd = { x = {}, y = {}, z = {}, r = {}, hp = {}, id = {}, d = {} },
}
local function validUnit(p)
    return p and p.live and p.hp > 0 and os.clock() - p.at < 0.65
end
local function collectUnits(out)
    local now = os.clock()
    if now - combat.unitsAt < 0.2 then return end
    combat.unitsAt = now
    table.clear(out)
    for _, record in pairs(combat.records) do record.live = false end
    local function update(id, pos, hp, radius, generation)
        local key = tostring(id) .. ":" .. tostring(generation or "native")
        local record = combat.records[key]
        if not record then record = { id = id, velocity = Vector3.zero }; combat.records[key] = record end
        local dt = record.at and now - record.at
        if dt and dt > 0.01 and dt < 1 then
            local velocity = (pos - record.Position) / dt
            record.velocity = velocity.Magnitude < 120 and velocity or Vector3.zero
        else record.velocity = Vector3.zero end
        record.Position, record.hp, record.radius = pos, hp or 100, radius or 2.5
        record.at, record.live = now, true
        out[#out + 1] = record
        combat.snapshots[record] = { velocity = record.velocity }
    end
    local root = getRoot()
    local world = TargetWorld and TargetWorld.current
    local crowd = world and world.crowd or UnitView and UnitView.crowd
    local usedNative = false
    if root and type(crowd) == "function" then
        local query = combat.crowd
        local ok, count = pcall(crowd, root.Position.X, root.Position.Z, 1200, math.huge, query)
        if ok and type(count) == "number" then
            usedNative = true
            for i = 1, count do
                if query.id[i] ~= nil and query.hp[i] and query.hp[i] > 0 then
                    update(query.id[i], Vector3.new(query.x[i], query.y[i], query.z[i]), query.hp[i], query.r[i])
                end
            end
        elseif not ok then combat.lastError = "Crowd: " .. tostring(count) end
    end
    if not usedNative then
        local views = workspace:FindFirstChild("UnitViews")
        local function scan(folder)
            for _, m in ipairs(folder:GetChildren()) do
                local p = m:IsA("Model") and m:FindFirstChild("Unit")
                if p and p:IsA("BasePart") and p:GetAttribute("UnitId") ~= nil and p.LocalTransparencyModifier < 1 then
                    update(p:GetAttribute("UnitId"), p.Position, 100, 2.5, p:GetAttribute("Generation"))
                end
            end
        end
        if views then
            scan(views)
            local flash = views:FindFirstChild("UnitFlash")
            if flash then scan(flash) end
        end
    end
    for key, record in pairs(combat.records) do
        if not record.live then combat.records[key] = nil end
    end
end
local function nearestUnits(pivot, k)
    collectUnits(unitBuf)
    table.clear(nearP)
    table.clear(nearD)
    for _, p in ipairs(unitBuf) do
        if validUnit(p) then
            local d = (p.Position - pivot).Magnitude
            local n = #nearP
            if n < k or d < nearD[n] then
                local j = math.min(n + 1, k)
                while j > 1 and nearD[j - 1] > d do
                    nearP[j], nearD[j] = nearP[j - 1], nearD[j - 1]
                    j = j - 1
                end
                nearP[j], nearD[j] = p, d
            end
        end
    end
    return nearP
end


local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
local penParams = RaycastParams.new()
penParams.FilterType = Enum.RaycastFilterType.Include
penParams.IgnoreWater = true

local ignoreList, ignoreAt = {}, 0
local function getIgnore()
    local now = os.clock()
    if now - ignoreAt < 1 and #ignoreList > 0 then return ignoreList end
    table.clear(ignoreList)
    local function add(x) if x then ignoreList[#ignoreList + 1] = x end end
    local world = TargetWorld and TargetWorld.current
    for _, object in ipairs(world and world.shotIgnore or {}) do add(object) end
    add(LocalPlayer.Character)
    add(workspace:FindFirstChild("UnitViews"))
    add(workspace:FindFirstChild("ClientBullets"))
    local map = workspace:FindFirstChild("Map")
    add(map and map:FindFirstChild("Blockers"))
    ignoreAt = now
    rayParams.FilterDescendantsInstances = ignoreList
    return ignoreList
end

local penFilter = {}
local function canReach(from, to, blast)
    local dir = to - from
    local total = dir.Magnitude
    if total < 0.1 then return true end
    local unit = dir.Unit
    getIgnore()
    local pos, travelled = from, 0
    for _ = 1, 8 do
        local rem = total - travelled
        if rem <= 0.05 then return true end
        local hit = workspace:Raycast(pos, unit * rem, rayParams)
        if not hit then return true end
        if blast then return false end
        local off = unit * PEN
        penFilter[1] = hit.Instance
        penParams.FilterDescendantsInstances = penFilter
        local exit = workspace:Raycast(hit.Position + off, -off, penParams)
        if not exit then return false end
        pos = exit.Position + unit * 0.05
        local nt = (pos - from):Dot(unit)
        if nt <= travelled then return false end
        travelled = nt
    end
    return false
end

local defaultInfo = { range = 300, blast = false, hold = false, mode = "unknown", speed = 0, gravity = 0 }
local function toolInfo(tool)
    if not tool then return defaultInfo end
    local cfg, now = tool:FindFirstChild("WeaponConfig"), os.clock()
    local cached = toolInfoCache[tool]
    local level = tool:GetAttribute("LoadoutLevel")
    if type(level) ~= "number" and WeaponData then
        local ok, loadout = pcall(WeaponData.Get, WeaponData, "Loadout")
        local item = ok and cached and loadout and loadout.Owned and loadout.Owned.Weapons[cached.id]
        level = item and item.Level
    end
    if cached and cached.module == cfg and cached.level == level and now - cached.at < 1 then return cached end
    local info = { range = 300, blast = false, hold = false, mode = "unknown", module = cfg,
        at = now, level = level, speed = 0, gravity = 0 }
    if cfg and cfg:IsA("ModuleScript") then
        local ok, c = pcall(require, cfg)
        if ok and type(c) == "table" and type(c.projectile) == "table" then
            info.raw, info.id = c, c.Id
            local p = c.projectile
            if type(level) ~= "number" and WeaponData then
                local got, loadout = pcall(WeaponData.Get, WeaponData, "Loadout")
                local item = got and loadout and loadout.Owned and loadout.Owned.Weapons[c.Id]
                level = item and item.Level
                info.level = level
            end
            local entry = Catalog and Catalog.Weapons.Get(c.Id)
            if entry and type(level) == "number" and Progression then
                local upgraded, projectile = pcall(Progression.Projectile, entry, level, p)
                if upgraded then p = projectile else combat.lastError = "Progression: " .. tostring(projectile) end
            end
            info.projectile = p
            if type(p.maxRange) == "number" and p.maxRange > 0 then info.range = p.maxRange end
            if type(p.speed) == "number" and p.speed > 0 then info.speed = p.speed end
            info.blast = type(p.blast) == "table"
            info.blastRadius = info.blast and p.blast.radius or 0
            info.blastDamage = info.blast and p.blast.damage or 0
            info.mode = tostring(p.fireMode or "unknown")
            -- Native Burst continues the burst after release and repeats while down; keep it held.
            info.hold = info.mode == "Automatic" or info.mode == "Burst"
            info.interval = type(p.roundsPerMinute) == "number" and p.roundsPerMinute > 0 and 60 / p.roundsPerMinute or 0.1
            local profile = BulletProfiles and c.visuals and BulletProfiles[c.visuals.profileId]
            info.gravity = profile and profile.gravity or 0
            toolInfoCache[tool] = info
        elseif not ok then combat.lastError = "WeaponConfig: " .. tostring(c) end
    end
    return info
end

local function tryCone(fn, self, ...)
    local ok, pos, id = pcall(fn, ...)
    if ok and typeof(pos) == "Vector3" then return pos, id end
    if self then
        ok, pos, id = pcall(fn, self, ...)
        if ok and typeof(pos) == "Vector3" then return pos, id end
    end
end

-- Check the same low launch arc used by the native controller, without adding aim compensation twice.
local function flight(from, to, info)
    local speed, gravity = info.speed, info.gravity
    local delta = to - from
    if speed <= 0 then return nil end
    if gravity <= 0 then return delta.Magnitude / speed, delta.Magnitude > 0.001 and delta.Unit or Vector3.yAxis end
    local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
    local s2 = speed * speed
    if s2 * s2 - gravity * (gravity * horizontal * horizontal + 2 * delta.Y * s2) < 0 then return nil end
    local direction = Ballistics.solve(from, to, speed, gravity)
    local flatSpeed = Vector3.new(direction.X, 0, direction.Z).Magnitude * speed
    if flatSpeed < 0.001 then return nil end
    return horizontal / flatSpeed, direction
end
local function reachable(pos, pivot, info)
    if (pos - pivot).Magnitude > info.range then return false end
    if info.gravity <= 0 then return canReach(pivot, pos, info.blast) end
    if not Ballistics or type(Ballistics.solve) ~= "function" then return false end
    local duration, direction = flight(pivot, pos, info)
    if not duration then return false end
    getIgnore()
    local last, distance = pivot, 0
    local segments = math.clamp(math.ceil(duration / 0.1), 4, 48)
    for i = 1, segments do
        local point = Ballistics.at(pivot, direction, info.speed, info.gravity, duration * i / segments)
        distance = distance + (point - last).Magnitude
        if distance > info.range then return false end
        local hit = workspace:Raycast(last, point - last, rayParams)
        if hit then
            -- An impact within the explosion radius is a useful landing point.
            local tolerance = info.blast and math.max(0, (info.blastRadius or 0) - 1) or 1
            return (hit.Position - pos).Magnitude <= tolerance
        end
        last = point
    end
    return true
end

local function predict(p, pivot, speed, info)
    local pos = p.Position
    speed = type(speed) == "number" and speed > 0 and speed or info.speed
    if speed <= 0 or speed == math.huge then return pos end
    local velocity = p.velocity or Vector3.zero
    local effective = table.clone(info)
    effective.speed = speed
    local aim = pos
    for _ = 1, 3 do
        local duration = flight(pivot, aim, effective)
        if not duration then return pos end
        -- Avoid extrapolating stale velocity over a long lob.
        aim = pos + velocity * math.min(duration, 2)
    end
    return aim
end


local function aimPivot(root, tool)
    local joint = root:FindFirstChild("RootJoint")
    local info = toolInfo(tool)
    if joint and WeaponGeometry and info.raw then
        local ok, pivot = pcall(WeaponGeometry.ResolveAimPivot, root, joint, info.raw.pose)
        if ok and typeof(pivot) == "Vector3" then return pivot end
    end
    return root.Position + Vector3.new(0, 1, 0)
end

local function chooseUnit(pivot, info)
    collectUnits(unitBuf)
    -- Spatial buckets keep density scoring linear in normal crowds.
    local radius = math.max(4, info.blast and info.blastRadius or 12)
    local grid = {}
    local function cell(x, z) return tostring(x) .. ":" .. tostring(z) end
    for _, p in ipairs(unitBuf) do
        if validUnit(p) then
            local x, z = math.floor(p.Position.X / radius), math.floor(p.Position.Z / radius)
            local key = cell(x, z)
            grid[key] = grid[key] or {}
            grid[key][#grid[key] + 1] = p
        end
    end
    local ranked = combat.candidates
    table.clear(ranked)
    local count = #unitBuf
    -- Evaluate a rotating sample across the whole map plus the nearest units.
    local pool, seen = {}, {}
    for _, p in ipairs(nearestUnits(pivot, 16)) do pool[#pool + 1], seen[p] = p, true end
    if count > 0 then
        local offset = math.floor(os.clock() * 5) % count
        for i = 1, math.min(count, 48) do
            local p = unitBuf[(offset + math.floor((i - 1) * count / math.min(count, 48))) % count + 1]
            if not seen[p] then pool[#pool + 1], seen[p] = p, true end
        end
    end
    for _, p in ipairs(pool) do
        if validUnit(p) then
            local d = (p.Position - pivot).Magnitude
            local neighbors = 0
            if info.blast then
                local x, z = math.floor(p.Position.X / radius), math.floor(p.Position.Z / radius)
                for dx = -1, 1 do
                    for dz = -1, 1 do
                        for _, q in ipairs(grid[cell(x + dx, z + dz)] or {}) do
                            if (q.Position - p.Position).Magnitude <= radius + q.radius then
                                local damage = math.max(1, info.blastDamage or 1)
                                neighbors = neighbors + math.min(damage / math.max(1, q.hp), 1)
                                    + 0.25 * math.min(q.hp, damage) / damage
                            end
                        end
                    end
                end
            end
            local score = (info.blast and neighbors * 25 or 0) - d * 0.12
            if p == combat.target then score = score + 4 end
            ranked[#ranked + 1] = { part = p, score = score, distance = d }
        end
    end
    table.sort(ranked, function(a, b) return a.score > b.score end)
    local movementTarget
    for _, candidate in ipairs(ranked) do
        if not combat.pathRejected or (combat.pathRejected[candidate.part.id] or 0) <= os.clock() then
            movementTarget = candidate.part
            break
        end
    end
    for i = 1, math.min(#ranked, 16) do
        local p = ranked[i].part
        local aim = predict(p, pivot, info.speed, info)
        if reachable(aim, pivot, info) then return p, movementTarget end
    end
    return nil, movementTarget
end

local scanPart, scanAt, emptyAt = nil, 0, 0
local function pickTarget(camPos, look, pivot, speed, tool)
    if typeof(pivot) ~= "Vector3" then return nil end
    local info, now = toolInfo(tool), os.clock()
    if combat.targetTool ~= tool or now - combat.targetAt >= 0.2 then
        combat.target, combat.pursuit = chooseUnit(pivot, info)
        combat.targetAt, combat.targetTool = now, tool
    end
    if validUnit(combat.target) then
        local p = combat.target
        local aim = predict(p, pivot, speed, info)
        local check = combat.reachCheck
        local can = check and check.target == p and check.tool == tool and check.info == info
            and now - check.at < 0.1 and (check.pivot - pivot).Magnitude < 1.5
            and (check.aim - aim).Magnitude < 1.5 and check.can
        if not can then
            can = reachable(aim, pivot, info)
            combat.reachCheck = { target = p, tool = tool, info = info, at = now, pivot = pivot, aim = aim, can = can }
        end
        if can then
            lastTargetId = p.id
            return aim
        end
        combat.target = nil
    end
    -- Native fallback retains game-specific targeting when rendered views are incomplete.
    local pos, id
    if UnitView and UnitView.coneTarget then
        pos, id = tryCone(UnitView.coneTarget, nil, camPos, look, lastTargetId, pivot, speed, -1)
    end
    local world = TargetWorld and TargetWorld.current
    if not pos and world and world.coneTarget then
        pos, id = tryCone(world.coneTarget, world, camPos, look, lastTargetId, pivot, speed, -1)
    end
    if pos and reachable(pos, pivot, info) then lastTargetId = id; return pos end
    lastTargetId = nil
    return nil
end

env.MonkeyAim = function(tool, camPos, look, pivot, speed)
    if not (alive() and S.AutoKill and not suspended) then return nil end
    combat.aimCalls = combat.aimCalls + 1
    combat.lastAimAt = os.clock()
    combat.speed = speed
    local ok, pos = pcall(pickTarget, camPos, look, pivot, speed, tool)
    if not ok then combat.lastError = "Aim: " .. tostring(pos) end
    return ok and pos or nil
end
teardown[#teardown + 1] = function() env.MonkeyAim = nil end
if GunRig and type(GunRig.AddAimOverride) == "function" and env.MonkeyAimOn ~= GunRig then
    local ok, err = pcall(GunRig.AddAimOverride, function(...)
        local fn = env.MonkeyAim
        if fn then return fn(...) end
    end)
    if ok then env.MonkeyAimOn = GunRig else combat.lastError = "Aim registration: " .. tostring(err) end
end


local pulseUntil = 0
local function release()
    pulseUntil = 0
    if held then
        pcall(function() held:Deactivate() end)
        held = nil
    end
end

teardown[#teardown + 1] = release

local function equipOnce()
    local hum, pack = getHumanoid(), LocalPlayer:FindFirstChildOfClass("Backpack")
    if not (hum and pack and hum.Health > 0) or currentTool() then return end
    for _, t in ipairs(pack:GetChildren()) do
        if t:IsA("Tool") and t:FindFirstChild("WeaponConfig") then
            hum:EquipTool(t)
            return
        end
    end
end

loop(0.03, function()
    if not (S.AutoKill and not suspended and GunRig) then combat.status = "Idle"; return release() end
    local hum, root = getHumanoid(), getRoot()
    if not (hum and root) or hum.Health <= 0 then return release() end
    local tool, cam = currentTool(), workspace.CurrentCamera
    if held and held ~= tool then release() end
    if not tool then
        local now = os.clock()
        if now - lastEquip > 0.75 then lastEquip = now; equipOnce() end
        combat.status = "Waiting for weapon"
        return release()
    end
    if not cam then return release() end
    local info, now = toolInfo(tool), os.clock()
    combat.tool, combat.config = tool.Name, info
    if not tool.Enabled then combat.status = "Weapon disabled / cooldown"; return release() end
    local pivot = aimPivot(root, tool)
    if not pickTarget(cam.CFrame.Position, cam.CFrame.LookVector, pivot, nil, tool) then
        combat.status = "No reachable target"
        return release()
    end
    combat.status = "Firing"
    if held and not info.hold then
        if now >= pulseUntil then release() end
        return
    end
    if held ~= tool and type(GunRig.PushAim) == "function" then
        local ok, err = pcall(GunRig.PushAim, GunRig)
        if not ok then combat.lastError = "PushAim: " .. tostring(err) end
    end
    if info.hold and held == tool then
        if now - (combat.retryAt or 0) >= 0.75 then
            combat.retryAt = now
            pcall(function() tool:Activate() end)
        end
        return
    end
    local ok, err = pcall(function() tool:Activate() end)
    if not ok then combat.lastError = "Activate: " .. tostring(err); return release() end
    held = tool
    combat.activations = combat.activations + 1
    combat.retryAt = now
    -- Native weapon cooldown/reload still controls accepted shots.
    -- Automatic and Burst stay held; Semi and unknown modes get release edges.
    pulseUntil = now + 0.035
end)


local safeActive, origin, noclipConn, partConn, trackedChar = false, nil, nil, nil, nil
local charParts = {}
local savedCollide = setmetatable({}, { __mode = "k" })
local stairOrig = setmetatable({}, { __mode = "k" })

local function trackCharacter(ch)
    table.clear(charParts)
    if partConn then
        partConn:Disconnect()
        partConn = nil
    end
    for _, p in ipairs(ch:GetDescendants()) do
        if p:IsA("BasePart") then charParts[#charParts + 1] = p end
    end
    partConn = ch.DescendantAdded:Connect(function(p)
        if p:IsA("BasePart") then charParts[#charParts + 1] = p end
    end)
end

local function noclipStep()
    local i = #charParts
    while i > 0 do
        local p = charParts[i]
        if p.Parent then
            if p.CanCollide then
                savedCollide[p] = true
                p.CanCollide = false
            end
        else
            charParts[i] = charParts[#charParts]
            charParts[#charParts] = nil
        end
        i = i - 1
    end
end

local function startNoclip(ch)
    trackCharacter(ch)
    if not noclipConn then
        noclipConn = RunService.Stepped:Connect(noclipStep)
    end
end

local function stopNoclip()
    if noclipConn then
        noclipConn:Disconnect()
        noclipConn = nil
    end
    if partConn then
        partConn:Disconnect()
        partConn = nil
    end
    for p in pairs(savedCollide) do
        if p.Parent then pcall(function() p.CanCollide = true end) end
    end
    table.clear(savedCollide)
    table.clear(charParts)
end

local function applyStairs()
    local stairs = findPath(workspace, "Map", "Ground", "BigStaircase")
    if not stairs then return end
    for _, p in ipairs(stairs:GetDescendants()) do
        if p:IsA("BasePart") and p.Name == "Stair" then
            if stairOrig[p] == nil then stairOrig[p] = p.Transparency end
            p.Transparency = STAIR_TRANSPARENCY
        end
    end
end

local function restoreStairs()
    for p, t in pairs(stairOrig) do
        if p.Parent then pcall(function() p.Transparency = t end) end
    end
    table.clear(stairOrig)
end

local function goSpot()
    local ch, root = LocalPlayer.Character, getRoot()
    if not (ch and root) then return end
    ch:PivotTo(CFrame.new(SAFE_SPOT))
    root.AssemblyLinearVelocity = Vector3.zero
end

local function setSafe(on)
    if on then
        if safeActive then return end
        local ch, root = LocalPlayer.Character, getRoot()
        if not (ch and root) then return end
        safeActive = true
        trackedChar = ch
        origin = root.Position.Y >= SAFE_FALL_Y and root.CFrame or nil
        applyStairs()
        startNoclip(ch)
        goSpot()
    else
        if not safeActive then return end
        safeActive = false
        trackedChar = nil
        local ch = LocalPlayer.Character
        if ch and origin then ch:PivotTo(origin) end
        origin = nil
        stopNoclip()
        restoreStairs()
    end
end

loop(0.1, function()
    if IN_LOBBY then return end
    local ch, hum, root = LocalPlayer.Character, getHumanoid(), getRoot()
    local want = S.SafeSpot and S.Movement == "Safe spot (legacy)" and not suspended

    if want and not safeActive then
        if hum and root and hum.Health > 0 then setSafe(true) end
        return
    elseif not want and safeActive then
        setSafe(false)
        return
    end
    if not safeActive then return end

    if ch and root and ch ~= trackedChar then
        trackedChar = ch
        startNoclip(ch)
        goSpot()
        return
    end
    if hum and root and hum.Health > 0
        and (root.Position.Y < SAFE_FALL_Y or (root.Position - SAFE_SPOT).Magnitude > 10) then
        goSpot()
    end
end)

conns[#conns + 1] = LocalPlayer.CharacterAdded:Connect(function(ch)
    if not alive() then return end
    ignoreAt = 0
    combat.target, combat.pursuit, combat.targetTool = nil, nil, nil
    combat.unitsAt = -math.huge
    release()
    ch:WaitForChild("HumanoidRootPart", 10)
    if not alive() then return end
    if S.SafeSpot and safeActive then
        trackedChar = ch
        startNoclip(ch)
        goSpot()
    end
    task.wait(1.5)
    if not alive() then return end
    if S.SafeSpot and safeActive then goSpot() end
    if S.AutoKill and not suspended then equipOnce() end
end)

-- Ground pursuit owns one path at a time and leaves normal movement physics intact.
local travel = { generation = 0, busy = false, points = nil, index = 1, goal = nil,
    lastPlan = -math.huge, lastPos = nil, progressAt = 0, hum = nil, status = "Idle", blocked = nil }
local function stopTravel()
    travel.generation = travel.generation + 1
    travel.points, travel.goal = nil, nil
    if travel.blocked then travel.blocked:Disconnect(); travel.blocked = nil end
    if travel.hum and travel.hum.Parent then travel.hum:Move(Vector3.zero) end
    travel.hum = nil
end
teardown[#teardown + 1] = stopTravel
loop(0.2, function()
    local hum, root = getHumanoid(), getRoot()
    if IN_LOBBY or not S.AutoKill or suspended or S.Movement ~= "Ground pursuit"
        or not hum or hum.Health <= 0 or not root then
        if travel.goal or travel.hum then stopTravel() end
        return
    end
    if safeActive then setSafe(false); return end
    local target = combat.pursuit
    if target and combat.pathRejected and (combat.pathRejected[target.id] or 0) > os.clock() then target = nil end
    if not validUnit(target) then
        collectUnits(unitBuf)
        local _, t = chooseUnit(root.Position + Vector3.new(0, 1, 0), toolInfo(currentTool()))
        target = t
    end
    if not validUnit(target) then stopTravel(); travel.status = "Waiting for targets"; return end
    local info, now = toolInfo(currentTool()), os.clock()
    local delta = root.Position - target.Position
    local distance = delta.Magnitude
    local stand = math.min(info.range * 0.65, info.blast and math.max(28, (info.blastRadius or 0) + 12) or 45)
    if distance <= stand + 6 and reachable(target.Position, root.Position + Vector3.new(0, 1, 0), info) then
        if travel.goal or travel.hum then stopTravel() end
        travel.status = "Holding firing position"
        return
    end
    if travel.hum and travel.hum ~= hum then stopTravel() end
    travel.hum = hum
    if hum.Sit then hum.Sit = false; hum.Jump = true; travel.status = "Leaving seat"; return end
    local horizontal = Vector3.new(delta.X, 0, delta.Z)
    local outward = horizontal.Magnitude > 0.1 and horizontal.Unit or Vector3.xAxis
    local destination = target.Position + outward * stand
    getIgnore()
    local floor = workspace:Raycast(destination + Vector3.new(0, 60, 0), Vector3.new(0, -160, 0), rayParams)
    if not floor or floor.Normal.Y < 0.55 then travel.status = "No walkable firing position"; stopTravel(); return end
    destination = floor.Position
    local needsPath = not travel.points or not travel.goal or (destination - travel.goal).Magnitude > 14
    if needsPath and not travel.busy and now - travel.lastPlan >= 1 then
        travel.lastPlan, travel.busy = now, true
        local token, character = travel.generation, LocalPlayer.Character
        task.spawn(function()
            local path
            local ok, err = pcall(function()
                path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
                path:ComputeAsync(root.Position, destination)
            end)
            travel.busy = false
            if not alive() or token ~= travel.generation or character ~= LocalPlayer.Character
                or not S.AutoKill or suspended or S.Movement ~= "Ground pursuit" then return end
            if ok and path.Status == Enum.PathStatus.Success then
                if travel.blocked then travel.blocked:Disconnect() end
                travel.points, travel.index, travel.goal = path:GetWaypoints(), 2, destination
                travel.lastPos, travel.progressAt = root.Position, os.clock()
                travel.blocked = path.Blocked:Connect(function(index)
                    if token == travel.generation and index >= travel.index then travel.points = nil end
                end)
                travel.status = "Walking to firing position"
            else
                travel.points = nil
                travel.status = "No path; selecting another group"
                combat.pathRejected = combat.pathRejected or {}
                combat.pathRejected[target.id] = os.clock() + 6
                combat.pursuit, combat.targetAt = nil, 0
                if not ok then combat.lastError = "Path: " .. tostring(err) end
            end
        end)
    end
    if not travel.points then return end
    local waypoint = travel.points[travel.index]
    if not waypoint then stopTravel(); return end
    if (root.Position - waypoint.Position).Magnitude < 4 then
        travel.index = travel.index + 1
        waypoint = travel.points[travel.index]
        if not waypoint then stopTravel(); return end
    end
    if travel.lastPos and (root.Position - travel.lastPos).Magnitude > 2 then
        travel.lastPos, travel.progressAt = root.Position, now
    elseif now - travel.progressAt > 3 then
        hum.Jump = true
        stopTravel()
        travel.status = "Stuck; replanning"
        return
    end
    if waypoint.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
    hum:MoveTo(waypoint.Position)
end)

local function setAutoSkip(on)
    local vote = findPath(RS, "Shared", "Waves", "Vote")
    if vote then pcall(function() vote:FireServer("Auto", on) end) end
end

loop(2, function()
    if S.AutoSkip and LocalPlayer:GetAttribute("AutoSkip") ~= true then setAutoSkip(true) end
end)

local SLOTS = {
    ["Ability 1"] = { motion = "Ability1MotionSlot", inner = "Ability1" },
    ["Ability 2"] = { motion = "Ability2MotionSlot", inner = "Ability2" },
    ["Ultimate"] = { motion = "UltimateMotionSlot", inner = "Ultimate", ultimate = true },
}
local SLOT_ORDER = { "Ability 1", "Ability 2", "Ultimate" }
local SKIP_LABELS = { Percentage = true, Cooldown = true, Key = true, Hotkey = true, Keybind = true }

local function slotRoot(slot)
    local gui = playerGui()
    return gui and findPath(gui, "Game", "RightMenu", slot.motion, slot.inner)
end

local function cleanName(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if #text < 3 or not text:match("^%a[%a ]*$") then return nil end
    if text == text:upper() then
        text = text:sub(1, 1) .. text:sub(2):lower()
    end
    return text
end

local function abilityName(slot)
    local idAttribute = slot.ultimate and "UltimateId" or slot.inner .. "Id"
    local id = LocalPlayer:GetAttribute(idAttribute)
    local entry = type(id) == "string" and Catalog and Catalog.Abilities.Get(id)
    if entry then return entry.Display and entry.Display.Name or id end
    local root = slotRoot(slot)
    if not root then return nil end
    local label
    if slot.ultimate then
        label = findPath(root, "Folder", "Label", "AbilityName")
    else
        local kid = root:GetChildren()[4]
        label = kid and kid:FindFirstChild("TextLabel")
    end
    local name = label and label:IsA("TextLabel") and cleanName(label.Text)
    if name then return name end
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") and not SKIP_LABELS[d.Name] then
            local n = cleanName(d.Text)
            if n then return n end
        end
    end
end

local function slotReady(slot)
    if slot.ultimate then
        local charge = LocalPlayer:GetAttribute("UltimateCharge")
        if type(charge) == "number" then return charge >= 1 end
    else
        local index = slot.inner == "Ability1" and 1 or 2
        local ready = LocalPlayer:GetAttribute("Ability" .. index .. "ReadyAt")
        local cost = LocalPlayer:GetAttribute("Ability" .. index .. "Cost")
        local cash = LocalPlayer:GetAttribute("Cash")
        if type(ready) == "number" then
            return workspace:GetServerTimeNow() >= ready
                and (type(cost) ~= "number" or type(cash) == "number" and cash >= cost)
        end
    end
    local root = slotRoot(slot)
    if not root then return false end
    if slot.ultimate then
        local pct = findPath(root, "MeterNumber", "Percentage")
        local n = pct and tonumber(tostring(pct.Text):match("%d+%.?%d*"))
        return n ~= nil and n >= 100
    end
    local overlay = findPath(root, "Frame", "CooldownOverlay")
    if not overlay then return false end
    return (not overlay.Visible) or overlay.AbsoluteSize.Y < 1
end

local function useAbility(name, slot)
    if PLACEMENTS[name] then
        local place = findPath(RS, "Shared", "Placements", "Place")
        if place then place:FireServer(name, 0) end
    else
        local use = findPath(RS, "Shared", "Abilities", "Use")
        local attribute = slot and (slot.ultimate and "UltimateId" or slot.inner .. "Id")
        local id = attribute and LocalPlayer:GetAttribute(attribute)
        if use then use:FireServer(type(id) == "string" and id or name) end
    end
end

local keyByName, lastSignature = {}, nil

local function refreshAbilityOptions()
    local options, map = {}, {}
    for _, key in ipairs(SLOT_ORDER) do
        local name = abilityName(SLOTS[key])
        if name and not map[name] then
            options[#options + 1] = name
            map[name] = key
        end
    end
    local signature = table.concat(options, "|")
    if signature == lastSignature then return options end
    lastSignature = signature
    keyByName = map
    if abilityDropdown then
        local keep = {}
        for name, key in pairs(map) do
            if S.Abilities[key] then keep[#keep + 1] = name end
        end
        abilityDropdown:Refresh(options)
        abilityDropdown:Set(keep)
    end
    return options
end

loop(2, refreshAbilityOptions)

local lastUse = {}

loop(0.4, function()
    if next(S.Abilities) == nil then return end
    local hum = getHumanoid()
    if not hum or hum.Health <= 0 then return end
    for _, key in ipairs(SLOT_ORDER) do
        if S.Abilities[key] then
            local slot = SLOTS[key]
            local now = os.clock()
            if now - (lastUse[key] or 0) > 1.5 and slotReady(slot) then
                local name = abilityName(slot)
                if name then
                    lastUse[key] = now
                    useAbility(name, slot)
                end
            end
        end
    end
end)

local MULT = { K = 1e3, M = 1e6, B = 1e9, T = 1e12 }

local function parseAmount(text)
    if type(text) ~= "string" then return nil end
    local num, suf = text:match("%$%s*([%d,%.]+)([KkMmBbTt]?)")
    if not num then num, suf = text:match("([%d,%.]+)([KkMmBbTt]?)") end
    if not num then return nil end
    local n = tonumber((num:gsub(",", "")))
    if not n then return nil end
    return n * (MULT[(suf or ""):upper()] or 1)
end

local function readAmount(path)
    local gui = playerGui()
    local label = gui and findPath(gui, table.unpack(path))
    return label and parseAmount(label.Text)
end

local CASH_PATH = { "Game", "CashContainer", "Background", "Amount" }
local COST_PATH = {
    Weapon = { "Game", "LeftMenu", "WeaponMotionSlot", "Weapon", "Frame", "Cost" },
    Health = { "Game", "LeftMenu", "HealthMotionSlot", "Health", "Frame", "Cost" },
}
local UPGRADE_KINDS = { "Weapon", "Health" }

local function readCash()
    local c = LocalPlayer:GetAttribute("Cash")
    if type(c) == "number" then return c end
    return readAmount(CASH_PATH)
end

loop(0.3, function()
    if next(S.Upgrades) == nil then return end
    local remote = findPath(RS, "Remotes", "UpgradeRequest")
    if not remote then return end
    for _, kind in ipairs(UPGRADE_KINDS) do
        if S.Upgrades[kind] then
            local have = readCash()
            local cost = LocalPlayer:GetAttribute(kind .. "UpgradeCost")
            if type(cost) ~= "number" then cost = readAmount(COST_PATH[kind]) end
            if LocalPlayer:GetAttribute(kind .. "UpgradeAvailable") == false then cost = nil end
            if have and cost and cost > 0 and have >= cost then
                remote:FireServer(kind)
                task.wait(0.5)
            end
        end
    end
end)

local queueWarned = false

local function queueReexec()
    if env.MonkeyQueuedJob == game.JobId .. ":" .. tostring(VERSION) then return end
    local queue = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
    if not queue then
        if not queueWarned then
            queueWarned = true
            notify("Autofarm", "Your executor has no queue_on_teleport, so Autofarm cannot restart itself after a teleport.")
        end
        return
    end
    if not HAS_FILES or not isfile(CONFIG.SourceFile) then
        if not queueWarned then
            queueWarned = true
            notify("Resume needs the updated file", "Save this script as " .. CONFIG.SourceFile .. " in your executor workspace for teleport resume.")
        end
        return
    end
    local okRead, src = pcall(readfile, CONFIG.SourceFile)
    if not okRead or type(src) ~= "string" or not src:find("local VERSION = 1.3", 1, true) then
        combat.lastError = "Resume file missing or outdated: " .. CONFIG.SourceFile
        return
    end
    local ok, err = pcall(queue, src)
    if ok then env.MonkeyQueuedJob = game.JobId .. ":" .. tostring(VERSION)
    else combat.lastError = "Queue: " .. tostring(err) end


end

local function clickButton(btn)
    for _, name in ipairs({ "Activated", "MouseButton1Click" }) do
        local sig = btn[name]
        if firesignal then
            pcall(firesignal, sig)
        elseif getconnections then
            for _, c in ipairs(getconnections(sig)) do pcall(function() c:Fire() end) end
        end
    end
end

local function lobbyHitbox(l)
    local hb = l:FindFirstChild("LobbyHitbox", true)
    return hb and hb:IsA("BasePart") and hb or nil
end

local function lobbyPos(l)
    local hb = lobbyHitbox(l)
    if hb then return hb.Position end
    if l:IsA("BasePart") then return l.Position end
    if l:IsA("Model") then return l:GetPivot().Position end
    local part = l:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position
end

local function emptyLobbies()
    local folder = workspace:FindFirstChild("Lobbies")
    local out = {}
    for _, l in ipairs(folder and folder:GetChildren() or {}) do
        local label = findPath(l, "Attachment", "BillboardGui", "Frame", "PlayerCount")
        local text = label and label:IsA("TextLabel") and label.Text
        if text and text:match("^%s*0%s*/") then out[#out + 1] = l end
    end
    table.sort(out, function(a, b) return a.Name < b.Name end)
    return out
end

local function enterLobby(lobby)
    local ch, root, pos = LocalPlayer.Character, getRoot(), lobbyPos(lobby)
    if not (ch and root and pos) then return end
    ch:PivotTo(CFrame.new(pos + Vector3.new(0, 1, 0)))
    root.AssemblyLinearVelocity = Vector3.zero
end

local function pokeLobby(lobby)
    local root = getRoot()
    if not root then return end
    local nodes = lobby:GetDescendants()
    nodes[#nodes + 1] = lobby
    for _, d in ipairs(nodes) do
        if fireproximityprompt and d:IsA("ProximityPrompt") then pcall(fireproximityprompt, d) end
        if firetouchinterest and d:IsA("BasePart") and d:FindFirstChildOfClass("TouchInterest") then
            pcall(firetouchinterest, root, d, 0)
        end
    end
end

local afStatus = "Autofarm off"

local function sendCreate(request, difficulty)
    request:FireServer("Create", {
        Map = CONFIG.Map, Difficulty = difficulty, Access = "Public", MaxPlayers = 1,
    })
end

local function startRun()
    local remotes = RS:WaitForChild("Remotes", 20)
    local request = remotes and remotes:WaitForChild("LobbyRequest", 10)
    local lobbyState = remotes and remotes:WaitForChild("LobbyState", 10)
    local lobbies = workspace:WaitForChild("Lobbies", 20)
    if not (request and lobbyState and lobbies and getRoot()) then
        afStatus = "Waiting for the lobby to load"
        return
    end

    local configuring
    local conn = lobbyState.OnClientEvent:Connect(function(kind, a)
        if kind == "HostConfiguring" then configuring = a end
    end)

    local function waitConfiguring(seconds)
        local t0 = os.clock()
        while not configuring and os.clock() - t0 < seconds do task.wait(0.1) end
        return configuring
    end

    local function tryCreate(difficulty)
        for _ = 1, 2 do
            if not (S.Autofarm and alive()) then return end
            sendCreate(request, difficulty)
            task.wait(5)
        end
    end

    pcall(function()
        local list = emptyLobbies()
        if #list == 0 then afStatus = "No empty lobby, waiting" end
        for _, lobby in ipairs(list) do
            if not (S.Autofarm and alive()) then break end
            afStatus = "Joining " .. lobby.Name
            configuring = nil
            enterLobby(lobby)
            if not waitConfiguring(3) then
                pokeLobby(lobby)
                waitConfiguring(3)
            end

            if configuring then
                afStatus = "Lobby open, creating"
                task.wait(1.2)
                local pos, root, hb = lobbyPos(lobby), getRoot(), lobbyHitbox(lobby)
                local reach = hb and (math.max(hb.Size.X, hb.Size.Z) / 2 + 4) or 12
                if pos and root and (root.Position - pos).Magnitude > reach then
                    enterLobby(lobby)
                    task.wait(0.5)
                end

                queueReexec()

                local want = S.Difficulty
                if want == "Hardcore" and state.hardcoreFailed then want = "Normal" end
                afStatus = "Creating (" .. want .. ")"
                tryCreate(want)
                if want == "Hardcore" and S.Autofarm and alive() then
                    state.hardcoreFailed = true
                    saveState()
                    afStatus = "Creating (Normal)"
                    tryCreate("Normal")
                end
            end
        end
    end)

    conn:Disconnect()
end

local function currentWave()
    local waves = findPath(RS, "Shared", "Waves")
    local n = waves and waves:GetAttribute("Number")
    if type(n) == "number" and n > 0 then return n end
    local gui = playerGui()
    local label = gui and findPath(gui, "Game", "Top", "NextWave", "Countdown", "TextLabel")
    local n = label and tostring(label.Text):upper():match("^%s*WAVE%s+(%d+)")
    return n and tonumber(n)
end

local finishing, ended, finishAt = false, false, 0
local endedAt, lastReplay, firstReplayAt = 0, 0, 0
local endedChar, endedWave, staleWave, lastWaveSeen = nil, nil, nil, nil
local deadAttrStale, skipAsserted = false, false
local stallAt, stallStage, lastCash, lastWave = os.clock(), 0, nil, nil
local noCharSince, lastRejoin = nil, -math.huge
local runCounter, appliedRun = 0, nil

local function resetWatch()
    stallAt, stallStage, lastCash, lastWave, noCharSince = os.clock(), 0, nil, nil, nil
end

local function rejoinLobby()
    local now = os.clock()
    if now - lastRejoin < 20 then return end
    lastRejoin = now
    afStatus = "Stuck, returning to the lobby"
    queueReexec()
    pcall(function() TeleportService:Teleport(CONFIG.LobbyPlace, LocalPlayer) end)
end

local function fireReplay(now)
    if now - lastReplay < 4 then return end
    lastReplay = now
    if firstReplayAt == 0 then firstReplayAt = now end
    local action = findPath(RS, "Remotes", "GameAction")
    if action then pcall(function() action:FireServer("Replay") end) end
end

local function finishRun()
    suspended = true
    release()
    stopTravel()
    pcall(setSafe, false)
    local ch = LocalPlayer.Character
    if ch then ch:PivotTo(CFrame.new(CONFIG.DeathSpot)) end
end

if UnitView and UnitView.Killed then
    conns[#conns + 1] = UnitView.Killed:Connect(function()
        combat.confirmedKills = combat.confirmedKills + 1
        combat.targetAt, combat.unitsAt = 0, -math.huge
    end)
end

local lastKills = 0
local function watchProgress(hum, wave, now)
    if not S.AutoKill then
        stallAt, stallStage = now, 0
        return
    end
    local cash = readCash()
    if cash == nil and wave == nil then
        stallAt, stallStage = now, 0
        return
    end
    if cash ~= lastCash or wave ~= lastWave or combat.confirmedKills ~= lastKills then
        lastKills = combat.confirmedKills
        lastCash, lastWave, stallAt, stallStage = cash, wave, now, 0
        return
    end
    local limit = stallStage == 0 and STALL_TIMEOUT or STALL_TIMEOUT / 2
    if now - stallAt < limit then return end
    if stallStage == 0 then
        stallStage, stallAt = 1, now
        afStatus = "Stalled, restarting the run"
        hum.Health = 0
    else
        rejoinLobby()
    end
end

local function gameOverRevealed(gui)
    local g = gui and findPath(gui, "End", "GameOver")
    if not g then return false end
    local ok, r = pcall(function()
        return g.Visible and g.GroupTransparency == 0 and g.Parent.Enabled
    end)
    return ok and r == true
end

local function gameOverShown(gui)
    local g = gui and findPath(gui, "End", "GameOver")
    if not g then return false end
    local ok, r = pcall(function()
        local screen = g.Parent
        if screen and screen:IsA("ScreenGui") and not screen.Enabled then return false end
        if g:IsA("GuiObject") and not g.Visible then return false end
        if g:IsA("CanvasGroup") and g.GroupTransparency >= 1 then return false end
        return true
    end)
    return ok and r == true
end

local function newRunSignal(hum, root, ch, wave, now, shown)
    if firstReplayAt == 0 then return nil end
    if not (hum and root and hum.Health > 0) then return nil end
    if shown then return nil end
    local novel = ch ~= endedChar
        or (wave ~= nil and endedWave ~= nil and wave < endedWave)
    if novel and LocalPlayer:GetAttribute("Dead") ~= true then return "signals" end
    if now - firstReplayAt >= NEWRUN_FALLBACK then return "timeout" end
    return nil
end

local function matchStep()
    local hum, root, gui = getHumanoid(), getRoot(), playerGui()
    local ch = LocalPlayer.Character
    local now = os.clock()
    local revealed = gameOverRevealed(gui)
    local shown = revealed or gameOverShown(gui)
    local deadAttr = LocalPlayer:GetAttribute("Dead") == true
    if not deadAttr then deadAttrStale = false end
    local isDead = (deadAttr and not deadAttrStale) or (hum ~= nil and hum.Health <= 0)
    local wave = currentWave()
    if wave and not ended then lastWaveSeen = wave end

    if not ended then
        if revealed or isDead then
            ended, endedAt, lastReplay, firstReplayAt = true, now, 0, 0
            endedChar, endedWave = ch, wave or lastWaveSeen
            suspended = true
            release()
        end
    else
        local via = newRunSignal(hum, root, ch, wave, now, shown)
        if via then
            ended, finishing, finishAt = false, false, 0
            suspended = false
            runCounter = runCounter + 1
            staleWave = endedWave
            deadAttrStale = deadAttr
            skipAsserted = false
            lastTargetId, scanPart, emptyAt = nil, nil, 0
            resetWatch()
        end
    end

    if ended then
        queueReexec()
        local waited = now - endedAt
        if waited < REPLAY_DELAY then
            afStatus = string.format("Run over, collecting rewards (%ds)", math.ceil(REPLAY_DELAY - waited))
        elseif not revealed and waited < REPLAY_DELAY + 7 then
            afStatus = "Waiting for the results screen"
        elseif waited > 60 then
            rejoinLobby()
        elseif waited > 30 then
            afStatus = "Replay failed, going back to the lobby"
            local action = findPath(RS, "Remotes", "GameAction")
            if action and now - lastReplay >= 4 then
                lastReplay = now
                action:FireServer("Return")
            end
        else
            afStatus = "Run over, replaying"
            fireReplay(now)
        end
        return
    end

    if not (hum and root) then
        noCharSince = noCharSince or now
        local gap = now - noCharSince
        if gap > 45 then
            rejoinLobby()
        elseif gap > 15 then
            afStatus = "No character, replaying"
            fireReplay(now)
        else
            afStatus = "Waiting for the character"
        end
        return
    end
    noCharSince = nil

    if root.Position.Y < OUT_OF_MAP_Y then
        afStatus = "Out of the map, restarting the run"
        hum.Health = 0
        return
    end

    local trusted = wave
    if wave and staleWave then
        if wave == staleWave then trusted = nil else staleWave = nil end
    end
    if trusted and not skipAsserted then
        skipAsserted = true
        if S.AutoSkip then setAutoSkip(true) end
    end

    if not finishing then
        afStatus = string.format("Wave %s / %d", wave and tostring(wave) or "?", S.StopWave)
        if trusted and trusted >= S.StopWave then
            finishing, finishAt = true, now
            finishRun()
            return
        end
        watchProgress(hum, wave, now)
        return
    end

    afStatus = "Reached wave " .. S.StopWave .. ", dying"
    if (root.Position - CONFIG.DeathSpot).Magnitude > 15 then
        LocalPlayer.Character:PivotTo(CFrame.new(CONFIG.DeathSpot))
    end
    if now - finishAt > 25 then hum.Health = 0 end
end

local starting, statusLabel, lastStatus = false, nil, nil

loop(1, function()
    if S.Autofarm then
        if os.time() - (state.autofarmAt or 0) >= HEARTBEAT_SAVE then persistAutofarm(true) end
        if IN_LOBBY then
            if not starting then
                starting = true
                task.spawn(function()
                    pcall(startRun)
                    task.wait(5)
                    starting = false
                end)
            end
        else
            matchStep()
        end
    else
        afStatus = "Autofarm off"
        ended, finishing, suspended = false, false, false
    end
    local text = afStatus
    if S.AutoKill and not IN_LOBBY and not suspended then
        text = text .. " | " .. combat.status
        if S.Movement == "Ground pursuit" then text = text .. " | " .. travel.status end
    end
    if statusLabel and text ~= lastStatus then
        lastStatus = text
        pcall(function() statusLabel:Set("Status: " .. text) end)
    end
end)

conns[#conns + 1] = LocalPlayer.Idled:Connect(function()
    local cam = workspace.CurrentCamera
    if not cam then return end
    pcall(function()
        VirtualUser:Button2Down(Vector2.new(0, 0), cam.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0), cam.CFrame)
    end)
end)

teardown[#teardown + 1] = function()
    S.AutoKill, S.AutoSkip, S.Autofarm, S.SafeSpot = false, false, false, false
    S.Upgrades, S.Abilities = {}, {}
    pcall(setAutoSkip, false)
    pcall(setSafe, false)
    pcall(stopNoclip)
    pcall(restoreStairs)
    table.clear(unitBuf)
    table.clear(nearP)
    table.clear(nearD)
    table.clear(ignoreList)
    table.clear(lastUse)
    if Rayfield then Rayfield:Destroy() end
end

local function applyAutofarmDefaults()
    S.AutoKill = true
    S.SafeSpot = S.Movement == "Safe spot (legacy)"
    S.AutoSkip = state.autoSkipOff ~= true
    if not IN_LOBBY then
        equipOnce()
        setAutoSkip(S.AutoSkip)
    end
end

local function runReady()
    if IN_LOBBY then return true end
    if ended or finishing or suspended then return false end
    local hum, root = getHumanoid(), getRoot()
    return hum ~= nil and root ~= nil and hum.Health > 0
end

local initFails = 0
loop(0.25, function()
    if not S.Autofarm then
        appliedRun, initFails = nil, 0
        return
    end
    if runCounter == appliedRun then return end
    if not runReady() then return end
    if not pcall(applyAutofarmDefaults) then
        initFails = initFails + 1
        if initFails < 20 then return end
    end
    appliedRun, initFails = runCounter, 0
    syncUI()
end)

if RESUMING then
    S.Autofarm = true
    env.MonkeyAutofarm = true
    applyAutofarmDefaults()
end

local function loadRayfield()
    for _ = 1, 3 do
        local ok, result = pcall(function()
            return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
        end)
        if ok and type(result) == "table" then return result end
        if not alive() then return nil end
        task.wait(2)
    end
end

local lib = loadRayfield()
if not lib then
    if alive() then
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = "Survive a Million Monkeys",
                Text = "Could not load the UI library. Autofarm still runs; re-run the script to get the menu back.",
                Duration = 8,
            })
        end)
    end
    return
end
Rayfield = lib

local initialOptions = refreshAbilityOptions()
if not IN_LOBBY then
    local deadline = os.clock() + 6
    while alive() and #initialOptions == 0 and os.clock() < deadline do
        task.wait(0.5)
        lastSignature = nil
        initialOptions = refreshAbilityOptions()
    end
end
if not alive() then
    pcall(function() Rayfield:Destroy() end)
    return
end
if #initialOptions == 0 then initialOptions = { "Waiting for abilities" } end

local Window = Rayfield:CreateWindow({
    Name = "Survive a Million Monkeys",
    LoadingTitle = "Survive a Million Monkeys",
    LoadingSubtitle = "youtube.com/@robloxvibecoder",
    ConfigurationSaving = { Enabled = true, FolderName = "MonkeyHorde", FileName = "Config" },
    KeySystem = false,
})

local Combat = Window:CreateTab("Combat", 4483362458)
killToggle = Combat:CreateToggle({
    Name = "Auto Kill Monkeys", CurrentValue = S.AutoKill,
    Callback = function(v)
        S.AutoKill = v
        if v then
            if not IN_LOBBY then equipOnce() end
        else
            release()
        end
    end,
})
movementDropdown = Combat:CreateDropdown({
    Name = "Combat movement", Options = { "Stay here", "Ground pursuit", "Safe spot (legacy)" },
    CurrentOption = { S.Movement }, MultipleOptions = false,
    Callback = function(opt)
        local value = toList(opt)[1]
        if value ~= "Stay here" and value ~= "Ground pursuit" and value ~= "Safe spot (legacy)" then return end
        S.Movement, S.SafeSpot = value, value == "Safe spot (legacy)"
        stopTravel()
        if uiReady and not syncing then state.combatMovement = value; saveState() end
    end,
})
skipToggle = Combat:CreateToggle({
    Name = "Auto Skip Wave", CurrentValue = S.AutoSkip,
    Callback = function(v)
        if uiReady and not syncing and S.Autofarm and v ~= S.AutoSkip then
            state.autoSkipOff = not v
            saveState()
        end
        S.AutoSkip = v
        if not IN_LOBBY then setAutoSkip(v) end
    end,
})
abilityDropdown = Combat:CreateDropdown({
    Name = "Auto Use Abilities",
    Options = initialOptions,
    CurrentOption = {},
    MultipleOptions = true,
    Flag = "AutoAbilities",
    Callback = function(opt)
        local set = {}
        for _, name in ipairs(toList(opt)) do
            local key = keyByName[name]
            if key then set[key] = true end
        end
        S.Abilities = set
    end,
})

local Upgrades = Window:CreateTab("Upgrades", 4483362458)
Upgrades:CreateDropdown({
    Name = "Auto Upgrade",
    Options = UPGRADE_KINDS,
    CurrentOption = {},
    MultipleOptions = true,
    Flag = "AutoUpgrade",
    Callback = function(opt)
        local set = {}
        for _, name in ipairs(toList(opt)) do set[name] = true end
        S.Upgrades = set
    end,
})

local Autofarm = Window:CreateTab("Autofarm", 4483362458)
autofarmToggle = Autofarm:CreateToggle({
    Name = "Start / Stop Autofarm", CurrentValue = S.Autofarm,
    Callback = function(v)
        S.Autofarm = v
        env.MonkeyAutofarm = v
        if uiReady or not v then persistAutofarm(v) end
        if not v then
            S.AutoKill, S.SafeSpot, S.AutoSkip = false, false, false
            release()
            stopTravel()
            pcall(setSafe, false)
            if not IN_LOBBY then setAutoSkip(false) end
            syncUI()
        end
        if v then
            resetWatch()
            queueReexec()
            if uiReady then
                applyAutofarmDefaults()
                syncUI()
            end
        end
    end,
})
Autofarm:CreateDropdown({
    Name = "Difficulty",
    Options = { "Normal", "Hardcore" },
    CurrentOption = { S.Difficulty },
    MultipleOptions = false,
    Flag = "AutofarmDifficulty",
    Callback = function(opt)
        local name = toList(opt)[1]
        if name ~= "Normal" and name ~= "Hardcore" then return end
        if uiReady and name ~= S.Difficulty and state.hardcoreFailed then
            state.hardcoreFailed = nil
            saveState()
        end
        S.Difficulty = name
    end,
})
Autofarm:CreateInput({
    Name = "Stop at wave",
    CurrentValue = tostring(S.StopWave),
    PlaceholderText = "Type a wave number",
    RemoveTextAfterFocusLost = false,
    Flag = "StopWaveInput",
    Callback = function(text)
        local n = tonumber(text)
        if n and n >= 1 then S.StopWave = math.floor(n) end
    end,
})
statusLabel = Autofarm:CreateLabel("Status: " .. afStatus)

local Misc = Window:CreateTab("Misc", 4483362458)
Misc:CreateButton({
    Name = "Print weapon diagnostics (console)",
    Callback = function()
        local tool = currentTool()
        local info = toolInfo(tool)
        print("MonkeyHorde v" .. VERSION, tool and tool.Name or "No tool", "mode=" .. info.mode,
            "range=" .. tostring(info.range), "blast=" .. tostring(info.blast),
            "blastRadius=" .. tostring(info.blastRadius), "gravity=" .. tostring(info.gravity),
            "speed=" .. tostring(info.speed), "kills=" .. tostring(combat.confirmedKills),
            "nativeSpeed=" .. tostring(combat.speed), "aimCalls=" .. combat.aimCalls,
            "activationAttempts=" .. combat.activations, combat.status, travel.status,
            combat.lastError or lastLoopError or "No captured error")
        local seen = {}
        local function dump(value, prefix, depth)
            if type(value) ~= "table" or depth > 4 or seen[value] then return end
            seen[value] = true
            for key, item in pairs(value) do
                local name = prefix .. "." .. tostring(key)
                if type(item) == "table" then dump(item, name, depth + 1)
                elseif type(item) ~= "function" then print(name, tostring(item)) end
            end
        end
        dump(info.raw, "WeaponConfig", 0)
    end,
})
Misc:CreateLabel("Script version: v" .. VERSION .. (RESUMING and " (quick hotfix)" or ""))
Misc:CreateButton({
    Name = "Unload Script",
    Callback = function()
        persistAutofarm(false)
        env.MonkeyAutofarm = false
        if env.MonkeyCleanup then env.MonkeyCleanup() end
    end,
})

pcall(function() Rayfield:LoadConfiguration() end)
task.delay(3, function()
    if not alive() then return end
    uiReady = true
    if RESUMING then
        notify("Autofarm resumed", "Auto Kill, " .. S.Movement .. (S.AutoSkip and ", Auto Skip" or "") .. " enabled")
    end
    if S.Autofarm then
        applyAutofarmDefaults()
        pcall(function() autofarmToggle:Set(true) end)
        syncUI()
    end
end)
