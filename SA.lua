-- Arcade/Beginner: entity-aware Linoria combat tools.
-- Requires client execution, HTTP/loadstring, debug.getupvalues and debug.setupvalue.
-- Built against the supplied dump. Live server acceptance has not been tested.
-- Silent aim targets the standard gun component; launcher middleware is excluded.

local env = getgenv()
if env.ArcadeLinoria and env.ArcadeLinoria.Unload then
    env.ArcadeLinoria.Unload()
end

local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local UIS = game:GetService('UserInputService')
local LocalPlayer = Players.LocalPlayer
local function module(path)
    local instance = RS
    for name in path:gmatch('[^.]+') do
        instance = instance:WaitForChild(name, 15)
        assert(instance, 'Missing module: ' .. path)
    end
    return require(instance)
end
local EntityService = module('Remote.EntityService')
local HumanoidEntity = module('Remote.EntityService.Entity.HumanoidEntity')
local GameService = module('Remote.GameService')
local CameraController = module('Client.CameraController')
local CombatController = module('Client.CombatController')
local EntityController = module('Client.EntityController')
local WatchingHelper = module('Client.WatchingHelper')
local Components = module('Common.CombatService.Components')
local Shootable = module('Client.CombatController.ClientComponent.ClientShootableComponent')

local repo = 'https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/'
local Library = loadstring(game:HttpGet(repo .. 'Library.lua'))()
local Window = Library:CreateWindow({Title = 'Arcade | Players + Bots', Center = true, AutoShow = true})
local Main = Window:AddTab('Combat')
local Visuals = Window:AddTab('Visuals')
local UI = Window:AddTab('Settings')
local Aim = Main:AddLeftGroupbox('Silent aim')
local Trigger = Main:AddRightGroupbox('Triggerbot')
local Filters = Visuals:AddLeftGroupbox('Target filters')
local ESP = Visuals:AddRightGroupbox('ESP')
local Settings = UI:AddLeftGroupbox('Menu / diagnostics')

Aim:AddToggle('ASilent', {Text = 'Enable silent aim', Default = true})
Aim:AddLabel('Activation'):AddKeyPicker('AAimKey', {Default = 'MB2', Mode = 'Always', Text = 'Silent aim'})
Aim:AddSlider('AFOV', {Text = 'FOV radius (pixels)', Default = 30, Min = 10, Max = 700, Rounding = 0})
Aim:AddSlider('AChance', {Text = 'Hit chance (%)', Default = 100, Min = 0, Max = 100, Rounding = 0})
Aim:AddDropdown('APart', {Text = 'Aim part', Values = {'Head', 'Body'}, Default = 1})
Aim:AddToggle('AHealthAim', {Text = 'HP-based head / torso selection', Default = true})
Aim:AddLabel('Per shot: HP <= 100: 30% head / 70% torso. HP > 100: always head. Overrides Aim part.', true)
Aim:AddToggle('AWalls', {Text = 'Visibility check', Default = true})
Aim:AddToggle('ACircle', {Text = 'Show FOV circle', Default = true})
Aim:AddLabel('Standard guns only; launchers are excluded.', true)

Trigger:AddToggle('ATrigger', {Text = 'Enable triggerbot', Default = true})
Trigger:AddLabel('Activation'):AddKeyPicker('ATriggerKey', {Default = 'MB2', Mode = 'Always', Text = 'Triggerbot'})
Trigger:AddSlider('ADelay', {Text = 'Reaction delay (ms)', Default = 0, Min = 0, Max = 500, Rounding = 0})
Trigger:AddToggle('AUseSilent', {Text = 'Fire at silent-aim target', Default = true})
Trigger:AddLabel('Automatically fires at eligible enemies inside the FOV. Activation defaults to Always.', true)

Filters:AddToggle('APlayers', {Text = 'Target players', Default = true})
Filters:AddToggle('ABots', {Text = 'Target replacement bots', Default = true})
Filters:AddToggle('ATeam', {Text = 'Team check', Default = true})
Filters:AddSlider('ADistance', {Text = 'Max distance (studs)', Default = 1000, Min = 25, Max = 3000, Rounding = 0})
ESP:AddToggle('AESP', {Text = 'Enable ESP (real players only)', Default = true})
ESP:AddToggle('AHighlight', {Text = 'Highlights', Default = true})
ESP:AddToggle('ANames', {Text = 'Player names', Default = true})
ESP:AddToggle('AHealth', {Text = 'Health', Default = true})
ESP:AddToggle('AESPDistance', {Text = 'Distance', Default = true})
ESP:AddLabel('Player color'):AddColorPicker('APlayerColor', {Default = Color3.fromRGB(255, 100, 100)})

local Toggles, Options = env.Toggles, env.Options
Settings:AddLabel('Menu key'):AddKeyPicker('AMenuKey', {Default = 'RightControl', NoUI = true, Text = 'Menu'})
Library.ToggleKeybind = Options.AMenuKey
local Status = Settings:AddLabel('Initializing...')

local state = {alive = true, esp = {}, connections = {}, restores = {}, context = setmetatable({}, {__mode = 'k'})}
local inputTag = 'ArcadeLinoriaTrigger'
local triggerWeapon, triggerEntity, triggerSince, requestedTriggerWeapon
local originalLocalShoot = Shootable.LocalShoot
local originalOriginGetter = CameraController.GetCombatOriginFn()
local silentAvailable = false
local lastErrorAt, lastErrorMessage = -math.huge, nil

local function report(message)
    message = tostring(message)
    local now = os.clock()
    if message == lastErrorMessage and now - lastErrorAt < 5 then return end
    lastErrorAt, lastErrorMessage = now, message
    warn('[ArcadeLinoria] ' .. message)
    Library:Notify(message, 5)
end
local function localEntity()
    return EntityService.GetLocalEntity()
end
local function worldEntities(world)
    local registry = world and world.Entities
    if type(registry) ~= 'table' then return {} end
    -- TableUtils.NewDict has __iter, but pairs() exposes its raw metadata.
    local items = rawget(registry, '_items')
    return type(items) == 'table' and items or registry
end
local function canFight()
    local me = localEntity()
    return state.alive and me and me.World and me:IsAlive() and me:CanAttack()
        and GameService.IsJoined() and not GameService.IsPaused()
        and not CombatController.IsPaused() and WatchingHelper.Watching == LocalPlayer
        and not UIS:GetFocusedTextBox() and not Library.Unloaded
end

-- Enumerate the game's world registry, not Players:GetPlayers(): bots are Models.
local function aimPart(entity, model, mode)
    local part
    if mode == 'Head' then
        part = entity:GetHeadPart() or model:FindFirstChild('Head', true)
    else
        -- Prefer torso parts over GetBodyPart's root-part fallback.
        part = model:FindFirstChild('BodyPart', true) or model:FindFirstChild('UpperTorso', true)
            or model:FindFirstChild('Torso', true) or entity:GetBodyPart()
    end
    if not part or not part:IsA('BasePart') then part = entity:GetRootPart() end
    if part and part:IsA('BasePart') then return part end
end
local function record(entity)
    if type(entity) ~= 'table' or not HumanoidEntity:is(entity) then return end
    local me = localEntity()
    if not me or entity == me or entity.Destroyed or entity.World ~= me.World then return end
    if not entity:IsAlive() then return end
    local instance = entity.Instance
    if not instance or not instance.Parent then return end
    local bot = GameService.IsBot(instance) == true
    if instance:IsA('Player') then
        if not Toggles.APlayers.Value then return end
    elseif bot then
        if not Toggles.ABots.Value then return end
    else
        return -- Excludes props, pets, noncombat NPCs, and dead-body entities.
    end
    if Toggles.ATeam.Value and me:IsFriendly(entity) then return end
    local model = entity:GetWorkspaceRoot()
    local pivot = entity:GetPivot(true)
    local camera = workspace.CurrentCamera
    if not camera or not model or not model:IsDescendantOf(workspace) or not pivot then return end
    local distance = (pivot.Position - camera.CFrame.Position).Magnitude
    if distance > Options.ADistance.Value then return end
    local part = aimPart(entity, model, Options.APart.Value)
    if not part then return end
    return {entity = entity, model = model, part = part, position = part.Position, distance = distance, bot = bot}
end
local function espRecord(entity)
    local target = record(entity)
    if target and not target.bot and target.entity.Instance:IsA('Player') then return target end
end
local function chooseShotTarget(target)
    local mode = Options.APart.Value
    if Toggles.AHealthAim.Value then
        local health = tonumber(target.entity.Health)
        if not health then
            local humanoid = target.entity:GetHumanoid()
            health = humanoid and tonumber(humanoid.Health)
        end
        if health then
            mode = health > 100 and 'Head' or (math.random(1, 100) <= 30 and 'Head' or 'Body')
        end
    end
    local part = aimPart(target.entity, target.model, mode)
    if not part then return end
    local shotTarget = table.clone(target)
    shotTarget.part, shotTarget.position = part, part.Position
    return shotTarget
end
local function passthroughShot(component, ...)
    -- Auto-fire must not degrade to an unredirected crosshair shot.
    if Toggles.AUseSilent.Value and (component.Holder == triggerWeapon
        or component.Holder == requestedTriggerWeapon) then return false end
    return originalLocalShoot(component, ...)
end
local function visible(target, origin)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local exclusions = {target.model}
    local me = localEntity()
    local model = me and me:GetWorkspaceRoot()
    if model then table.insert(exclusions, model) end
    local camera = workspace.CurrentCamera
    if camera then table.insert(exclusions, camera) end
    params.FilterDescendantsInstances = exclusions
    params.IgnoreWater = true
    params.RespectCanCollide = false
    params.CollisionGroup = 'CanCollide' -- Same world-geometry group used by the game's AutoAim.
    local direction = target.position - origin
    return direction.Magnitude > 0.001 and workspace:Raycast(origin, direction, params) == nil
end
local function partFOVScore(part, camera, center)
    -- Test projected hitbox overlap, rather than requiring its center inside FOV.
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local half = part.Size / 2
    for _, x in ipairs({-1, 1}) do
        for _, y in ipairs({-1, 1}) do
            for _, z in ipairs({-1, 1}) do
                local point = part.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
                local screen = camera:WorldToViewportPoint(point)
                if screen.Z > 0 then
                    minX, minY = math.min(minX, screen.X), math.min(minY, screen.Y)
                    maxX, maxY = math.max(maxX, screen.X), math.max(maxY, screen.Y)
                end
            end
        end
    end
    minX, minY = math.max(minX, 0), math.max(minY, 0)
    maxX, maxY = math.min(maxX, camera.ViewportSize.X), math.min(maxY, camera.ViewportSize.Y)
    if minX > maxX or minY > maxY then return end
    local closest = Vector2.new(math.clamp(center.X, minX, maxX), math.clamp(center.Y, minY, maxY))
    return (closest - center).Magnitude
end
local function scanTarget(target, camera, center, origin)
    local parts = {target.part}
    -- A nearby torso can fill the FOV while the head's center is far above it.
    local torso = aimPart(target.entity, target.model, 'Body')
    if torso and torso ~= target.part then table.insert(parts, torso) end
    local best, score = nil, math.huge
    for _, part in ipairs(parts) do
        local distance = partFOVScore(part, camera, center)
        if distance and distance <= Options.AFOV.Value and distance < score then
            local candidate = table.clone(target)
            candidate.part, candidate.position = part, part.Position
            if not Toggles.AWalls.Value or visible(candidate, origin) then
                best, score = candidate, distance
            end
        end
    end
    return best, score
end
local function selectTarget()
    if not canFight() then return end
    local camera = workspace.CurrentCamera
    local center = camera.ViewportSize / 2
    local best, bestScore = nil, math.huge
    local origin = originalOriginGetter()
    for _, entity in pairs(worldEntities(localEntity().World)) do
        local target = record(entity)
        if target then
            local controller = EntityController.GetController(entity)
            local vc = controller and controller.VisibleController
            local displayed = vc and vc.CurrentVisible and vc.CurrentTransparency ~= 1
            if displayed then
                local candidate, score = scanTarget(target, camera, center, origin.Position)
                if candidate and score < bestScore then best, bestScore = candidate, score end
            end
        end
    end
    return best
end

-- Discover cached closures by shared upvalue identity, without fixed numeric indices.
local function installSilent()
    assert(debug and type(debug.getupvalues) == 'function' and type(debug.setupvalue) == 'function',
        'Silent aim needs debug.getupvalues and debug.setupvalue in this executor.')
    local function upvalues(fn)
        local ok, result = pcall(debug.getupvalues, fn)
        return ok and type(result) == 'table' and result or {}
    end
    local originState
    for _, value in pairs(upvalues(CameraController.GetCombatOriginFn)) do
        if type(value) == 'table' and type(value.Get) == 'function' and type(value.TempParams) == 'table' then
            originState = value
            break
        end
    end
    assert(originState, 'Combat origin layout differs from the supplied dump.')
    local targetingInternal
    for _, value in pairs(upvalues(CameraController.GetTargetingFn)) do
        if type(value) == 'function' then targetingInternal = value; break end
    end
    assert(targetingInternal, 'Targeting closure was not found.')
    local targetIndex, oldTargetFn
    for index, value in pairs(upvalues(originalLocalShoot)) do
        if type(value) == 'function' then
            for _, nested in pairs(upvalues(value)) do
                if nested == targetingInternal then targetIndex, oldTargetFn = index, value end
            end
        end
    end
    assert(type(targetIndex) == 'number' and oldTargetFn, 'Cached shot targeting closure was not found.')
    local oldGet = originState.Get
    local function originWrapper(...)
        local results = table.pack(oldGet(...))
        local target = state.context[coroutine.running()]
        if state.alive and target and typeof(results[1]) == 'CFrame' then
            local origin = results[1].Position
            if (target.position - origin).Magnitude > 0.001 then
                results[1] = CFrame.lookAt(origin, target.position)
            end
        end
        return table.unpack(results, 1, results.n)
    end
    local function targetWrapper(...)
        local target = state.context[coroutine.running()]
        if state.alive and target then return target.position, target.part end
        return oldTargetFn(...)
    end
    local function shootWrapper(component, ...)
        if not state.alive or not Toggles.ASilent.Value or not Options.AAimKey:GetState()
            or Components.Launcher:from(component.Holder) then
            return passthroughShot(component, ...)
        end
        local target = selectTarget()
        if not target or math.random() * 100 >= Options.AChance.Value then
            return passthroughShot(component, ...)
        end
        -- Roll once per actual shot, keeping target scanning / trigger timing stable.
        target = chooseShotTarget(target)
        if not target then return passthroughShot(component, ...) end
        local origin = originalOriginGetter()
        if Toggles.AWalls.Value and not visible(target, origin.Position) then
            return passthroughShot(component, ...)
        end
        local thread = coroutine.running()
        local previous = state.context[thread]
        state.context[thread] = target
        local results = table.pack(pcall(originalLocalShoot, component, ...))
        state.context[thread] = previous
        if not results[1] then error(results[2], 0) end
        return table.unpack(results, 2, results.n)
    end
    -- Register each rollback before making the corresponding mutation.
    table.insert(state.restores, function()
        if originState.Get == originWrapper then originState.Get = oldGet end
    end)
    originState.Get = originWrapper
    table.insert(state.restores, function() debug.setupvalue(originalLocalShoot, targetIndex, oldTargetFn) end)
    debug.setupvalue(originalLocalShoot, targetIndex, targetWrapper)
    assert(upvalues(originalLocalShoot)[targetIndex] == targetWrapper, 'Executor could not replace the targeting upvalue.')
    table.insert(state.restores, function()
        if Shootable.LocalShoot == shootWrapper then Shootable.LocalShoot = originalLocalShoot end
    end)
    Shootable.LocalShoot = shootWrapper
end
local function restoreSilent()
    local remaining = {}
    for i = #state.restores, 1, -1 do
        local ok, err = pcall(state.restores[i])
        if not ok then table.insert(remaining, 1, state.restores[i]); warn('[ArcadeLinoria] Restore failed: ' .. tostring(err)) end
    end
    state.restores = remaining
end
local installed, hookError = pcall(installSilent)
if installed then
    silentAvailable = true
    Status:SetText('Entity adapter ready. Silent aim hooks installed.')
else
    restoreSilent()
    Status:SetText('ESP / trigger ready. Silent aim unavailable (see console).')
    report(hookError)
end
Toggles.ASilent:OnChanged(function()
    if Toggles.ASilent.Value and not silentAvailable then
        Toggles.ASilent:SetValue(false)
        Library:Notify('Silent aim unavailable: ' .. tostring(hookError), 7)
    end
end)
if not silentAvailable then Toggles.ASilent:SetValue(false) end

local overlay = Instance.new('ScreenGui')
overlay.Name = 'ArcadeLinoriaOverlay'
overlay.IgnoreGuiInset = true
overlay.ResetOnSpawn = false
overlay.DisplayOrder = 1
overlay.Parent = LocalPlayer:WaitForChild('PlayerGui')
local circle = Instance.new('Frame')
circle.Name = 'FOV'
circle.AnchorPoint = Vector2.new(0.5, 0.5)
circle.Position = UDim2.fromScale(0.5, 0.5)
circle.BackgroundTransparency = 1
circle.Visible = false
circle.Parent = overlay
local round = Instance.new('UICorner')
round.CornerRadius = UDim.new(1, 0)
round.Parent = circle
local stroke = Instance.new('UIStroke')
stroke.Color = Color3.fromRGB(230, 230, 230)
stroke.Transparency = 0.3
stroke.Thickness = 1
stroke.Parent = circle

local function destroyESP(entity)
    local item = state.esp[entity]
    if item then item.highlight:Destroy(); item.billboard:Destroy(); state.esp[entity] = nil end
end
local function updateESP()
    local seen = {}
    local me = localEntity()
    if Toggles.AESP.Value and me and me.World then
        for _, entity in pairs(worldEntities(me.World)) do
            local target = espRecord(entity)
            if target then
                seen[entity] = true
                local item = state.esp[entity]
                if item and item.model ~= target.model then destroyESP(entity); item = nil end
                if not item then
                    local highlight = Instance.new('Highlight')
                    highlight.Adornee = target.model
                    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    highlight.FillTransparency = 0.8
                    highlight.OutlineTransparency = 0
                    highlight.Parent = overlay
                    local billboard = Instance.new('BillboardGui')
                    billboard.Size = UDim2.fromOffset(240, 55)
                    billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
                    billboard.AlwaysOnTop = true
                    billboard.Parent = overlay
                    local label = Instance.new('TextLabel')
                    label.Size = UDim2.fromScale(1, 1)
                    label.BackgroundTransparency = 1
                    label.Font = Enum.Font.GothamMedium
                    label.TextSize = 13
                    label.TextStrokeTransparency = 0.3
                    label.Parent = billboard
                    item = {model = target.model, highlight = highlight, billboard = billboard, label = label}
                    state.esp[entity] = item
                end
                local color = Options.APlayerColor.Value
                item.highlight.Enabled = Toggles.AHighlight.Value
                item.highlight.FillColor = color
                item.highlight.OutlineColor = color
                item.label.TextColor3 = color
                item.billboard.Adornee = target.model:FindFirstChild('Head', true) or target.part
                local lines = {}
                if Toggles.ANames.Value then
                    table.insert(lines, GameService.GetDisplayName(entity.Instance))
                end
                local details = {}
                if Toggles.AHealth.Value then
                    table.insert(details, string.format('%d / %d HP', math.floor(entity.Health or 0), math.floor(entity.MaxHealth or 0)))
                end
                if Toggles.AESPDistance.Value then table.insert(details, string.format('%d studs', target.distance)) end
                if #details > 0 then table.insert(lines, table.concat(details, ' | ')) end
                item.label.Text = table.concat(lines, '\n')
                item.billboard.Enabled = #lines > 0
            end
        end
    end
    for entity in pairs(state.esp) do if not seen[entity] then destroyESP(entity) end end
end

local function releaseTrigger()
    local weapon = triggerWeapon
    triggerWeapon = nil
    if weapon then
        -- Release the original weapon even when the current slot has changed.
        pcall(function() weapon:OnPrimaryAction({End = true, Input = inputTag}) end)
    end
end
local function resetTrigger()
    releaseTrigger()
    triggerEntity, triggerSince, requestedTriggerWeapon = nil, nil, nil
end
local function updateTrigger()
    if not Toggles.ATrigger.Value or not Options.ATriggerKey:GetState() or not canFight() then
        resetTrigger(); return
    end
    local weapon = CombatController.GetWeapon()
    local shootable = weapon and Components.Shootable:from(weapon)
    if not shootable or Components.Launcher:from(weapon) then resetTrigger(); return end
    if triggerWeapon and triggerWeapon ~= weapon then resetTrigger() end
    local target
    if Toggles.AUseSilent.Value then
        if not silentAvailable or not Toggles.ASilent.Value or not Options.AAimKey:GetState() then
            resetTrigger(); return
        end
        target = selectTarget()
    else
        local entity, part = CameraController.GetTargetingEntity()
        target = entity and record(entity)
        if target and part and part:IsA('BasePart') then target.position = part.Position end
    end
    local origin = originalOriginGetter()
    if not target or not visible(target, origin.Position) then resetTrigger(); return end
    local ammo = Components.Ammo:from(weapon)
    local reload = Components.Reloadable:from(weapon)
    local charge = Components.Chargeable:from(weapon)
    if (ammo and not ammo:HasAmmoInClip()) or (reload and reload:IsReloading())
        or (charge and charge:IsCharging()) then resetTrigger(); return end
    if triggerEntity ~= target.entity then
        releaseTrigger()
        triggerEntity, triggerSince = target.entity, os.clock()
    end
    if os.clock() - triggerSince < Options.ADelay.Value / 1000 then return end
    if triggerWeapon then return end
    if not weapon:CanActionNow(Components.Shootable.Action.Shoot) then return end
    -- Uses the normal action path so weapon timers, ammo and fire rates still apply.
    requestedTriggerWeapon = weapon
    local started = CombatController.PrimaryAction.Begin(inputTag)
    requestedTriggerWeapon = nil
    if started then
        if shootable:IsFullAuto() then
            triggerWeapon = weapon
        else
            weapon:OnPrimaryAction({End = true, Input = inputTag})
            triggerSince = os.clock()
        end
    end
end

local function cleanup()
    if not state.alive then return end
    state.alive = false
    resetTrigger()
    for _, connection in ipairs(state.connections) do connection:Disconnect() end
    restoreSilent()
    for entity in pairs(state.esp) do destroyESP(entity) end
    overlay:Destroy()
    if env.ArcadeLinoria == state then env.ArcadeLinoria = nil end
end
Library:OnUnload(cleanup)
state.Unload = function() cleanup(); if not Library.Unloaded then Library:Unload() end end
env.ArcadeLinoria = state
Settings:AddButton({Text = 'Unload and restore', Func = state.Unload})
Settings:AddButton({Text = 'Print entity counts', Func = function()
    local me = localEntity()
    local players, bots, eligible = 0, 0, 0
    if me and me.World then
        for _, entity in pairs(worldEntities(me.World)) do
            if type(entity) == 'table' and typeof(entity.Instance) == 'Instance' then
                if entity.Instance:IsA('Player') then players = players + 1
                elseif GameService.IsBot(entity.Instance) then bots = bots + 1 end
                if record(entity) then eligible = eligible + 1 end
            end
        end
    end
    Library:Notify(string.format('World: %d players, %d bots; %d eligible targets', players, bots, eligible), 6)
end})
Toggles.ATrigger:OnChanged(resetTrigger)

local espElapsed = 0
table.insert(state.connections, RunService.Heartbeat:Connect(function(dt)
    if not state.alive then return end
    circle.Visible = Toggles.ACircle.Value
    circle.Size = UDim2.fromOffset(Options.AFOV.Value * 2, Options.AFOV.Value * 2)
    espElapsed = espElapsed + dt
    if espElapsed >= 0.1 then
        espElapsed = 0
        local ok, err = pcall(updateESP)
        if not ok then report(err) end
    end
    local ok, err = pcall(updateTrigger)
    if not ok then resetTrigger(); report(err) end
end))
Library:Notify('Ready. FOV auto-fire enabled. Right Ctrl toggles the menu.', 5)
