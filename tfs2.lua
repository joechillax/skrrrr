local runtime = {active = true, connections = {}}
runtime.environment = type(getgenv) == "function" and getgenv() or _G
runtime.slot = runtime.environment.__CombatAssistantLifecycleV1
if not runtime.slot then
    runtime.slot = {}
    runtime.environment.__CombatAssistantLifecycleV1 = runtime.slot
end
if runtime.slot.current then
    assert(type(runtime.slot.current.unload) == "function", "Previous Combat Assistant is still initializing. Rejoin before retrying.")
    assert(runtime.slot.current.unload() == true, "Previous Combat Assistant could not release input. Close menus/console and unload it before retrying.")
end
runtime.slot.damageHistory = nil -- Release history retained by the previous diagnostic build.
runtime.slot.current = runtime
local function connect(signal, callback)
    local connection = signal:Connect(function(...)
        if runtime.active then return callback(...) end
    end)
    table.insert(runtime.connections, connection)
    return connection
end
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local zombiesFolder = Workspace:WaitForChild("Zombies")
local Linoria = loadstring(game:HttpGet("https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"))()
-- Fit tab scrolling columns to the available panel height instead of 509px.
do
    local create=Linoria.Create
    function Linoria:Create(class,properties)
        if class=="ScrollingFrame" and properties and properties.Parent and properties.Parent.Name=="TabFrame" then
            local size=properties.Size
            properties.Size=UDim2.new(size.X.Scale,size.X.Offset,1,-14)
        end
        return create(self,class,properties)
    end
end
local Window
local function setMenuVisible(visible)
    if runtime.active and Window and Window.Holder and Window.Holder.Visible ~= visible then Linoria:Toggle() end
end
function runtime.label(group,text)
    local label=group:AddLabel("",true)
    local rendered,retryAt=false,0
    function label:SetText(value)
        value=tostring(value)
        if rendered==value then return true end
        if os.clock()<retryAt then return false end
        local ok,err=pcall(function()
        local lines={}
        for paragraph in (tostring(value).."\n"):gmatch("(.-)\n") do
            local line=""
            for word in paragraph:gmatch("%S+") do
                while #word>30 do
                    if #line>0 then table.insert(lines,line);line="" end
                    table.insert(lines,word:sub(1,30));word=word:sub(31)
                end
                if #line+#word+1>30 and #line>0 then table.insert(lines,line);line="" end
                line=line=="" and word or line.." "..word
            end
            table.insert(lines,line)
        end
        if self.TextLabel then
            self.TextLabel.Text=table.concat(lines,"\n")
            self.TextLabel.TextWrapped=true
            self.TextLabel.Size=UDim2.new(1,-4,0,math.max(1,#lines)*18)
            if group.Resize then group:Resize() end
        else error("Status TextLabel unavailable") end
        end)
        if ok then rendered=value;self.renderError=nil else
            retryAt=os.clock()+2;self.renderError=tostring(err)
            if not runtime.uiWarning then runtime.uiWarning=true;warn("[Combat Assistant] Status update unavailable; retrying quietly every two seconds.") end
        end
        return ok
    end
    label:SetText(text)
    return label
end

local function addControl(group, kind, id, options)
    group:AddBlank(5)
    return group["Add" .. kind](group, id, options)
end
local function toSet(names)
    local set = {}
    for _, name in ipairs(names) do set[name] = true end
    return set
end
local config = {
    HeadshotConversion = false,
    NoSpread = false,
    NoRecoil = false,
    SilentAim = false,
    Triggerbot = false,
    VisibleCheck = false, -- Optional camera visibility check.
    BodyFallback = true,
    IgnoreInvisibleParts = false,
    WeaponClearance = true, -- Match the supplied GunScript head/camera origin.
    AutoFireMode = true,
    RangeCheck = true,
    RangeMode = "Automatic",
    ManualRange = 500,
    FOVRadius = 150,
    ShowFOV = false,
    FOVColor = Color3.fromRGB(0, 255, 140),
    CursorMode = "Follow mouse",
    TriggerIntervalMs = 130, -- Requested time between click starts.
    TargetMode = "Closest to Crosshair",
    SuperPriorityList = {},
    PriorityList = {},
    IgnoreList = {}
}
-- Optional extensions: every automatic or resource-using feature starts disabled.
runtime.extraSpecs = {
    Autofarm={false}, AutoC96={false}, AutoLeaveSpawn={false}, AutoNightDrinks={false},
    AutoEquip={false}, EquipWeapon={""}, FireModeOverride={false}, FireMode={"FullAuto",{"Single","Burst","FullAuto"}},
    OverheatManagement={false}, ClosePriority={false}, CloseDistance={60,20,200}, SkipCloaked={false},
    MeleeAura={false}, UseKnife={true}, ThrowMode={"Most crowded",{"Most crowded","Nearest safe group","Cursor position"}}, LureMode={"Most crowded",{"Most crowded","Nearest safe group","Cursor position","Boss–Enemy Spawn"}},
    AutoDonate={false}, DonatePlayer={""}, DonateAmount={100,1,10000}, DonateInterval={10,1,60},
    IgnoreEquippingTool={false}, AutoRefillAmmo={false}, ExperimentalFire={false}, AutoVote={false}, VoteMap={""}, AutoSkip={false}, 
    HipFireADS={false}, AutoShopMoney={false}, AutoPurchase={false}, Purchases={{}}, AutoRepair={false}, Repairs={{}},
    AutoReplenish={false}, Replenish={{}}, ActionInterval={3,.2,30}, MoneyReserve={0,0,100000},
    ZombieHighlights={false}, HighlightMode={"All",{"All","Priority only","Super priority only","Selected type"}},
    HighlightType={""}, HighlightDistance={1000,25,5000}, HighlightLimit={24,1,30}, ThroughWalls={false},
    TargetMarker={false}, TargetTracer={false}, ScavengerHighlights={false},

}
runtime.opDefinitions={{2,"Armour-Aware Aim Points"},{3,"Hot Harmony Heat Optimization"},{5,"Smarter Manual Throwable Placement","Predict throwable targets"},{6,"Hotkey Explosive-Can Detonation","Detonate owned can [J]"},{17,"Projectile Trajectory Override","Projectile velocity multiplier"}}
for _,entry in ipairs(runtime.opDefinitions) do runtime.extraSpecs["OP"..entry[1]]={false} end
runtime.extraSpecs.OPPredictionSeconds={1,0,3}
runtime.extraSpecs.ProjectileMultiplier={1.5,1,3}
runtime.extraSpecs.AssassinShotGuard={false}
runtime.extraSpecs.QuietReload={false}
runtime.extraSpecs.QuietReloadPercent={40,10,90}
runtime.extraSpecs.ReloadClearance={100,20,200}
runtime.extraSpecs.OPCanKey={"J"}
runtime.throwDefinitions={{"Grenade","T","Damage","1"},{"Molotov","Y","Damage","2"},{"Zombie Bait","F","Luring","3"},{"Pipe Bomb","G","Luring","4"}}
runtime.throwSupported={Grenade=true,Molotov=true,["Zombie Bait"]=true,["Pipe Bomb"]=true,Dynamite=true,
    ["Gas Grenade"]=true,Cryonade=true,["Nail Bomb"]=true,["Stun Grenade"]=true,Kunai=true,Shuriken=true,
    Snowball=true,Superball=true,Timebomb=true,["Time Bomb"]=true}
function runtime.throwSuffix(index) return runtime.throwDefinitions[index][4] end
function runtime.discoverThrowables()
    local storage=game:GetService("ReplicatedStorage")
    local containers={storage:FindFirstChild("Tools"),LocalPlayer:FindFirstChild("Backpack"),LocalPlayer.Character}
    local known,found={},{}
    for _,item in ipairs(runtime.throwDefinitions) do known[item[1]]=true end
    for _,container in pairs(containers) do
        if container then for _,tool in ipairs(container:GetChildren()) do
            if runtime.throwSupported[tool.Name] and not known[tool.Name] and tool:FindFirstChild("GrenadeScript") then
                known[tool.Name]=true;table.insert(found,tool.Name)
            end
        end end
    end
    table.sort(found)
    for _,name in ipairs(found) do
        local suffix="_"..name:gsub(".",function(c) return string.format("%02x",string.byte(c)) end)
        table.insert(runtime.throwDefinitions,{name,"None","Damage",suffix})
    end
end
runtime.discoverThrowables()

for index,item in ipairs(runtime.throwDefinitions) do
    runtime.extraSpecs["ThrowEnabled"..runtime.throwSuffix(index)]={false}
    runtime.extraSpecs["ThrowKey"..runtime.throwSuffix(index)]={item[2]}
end
for name in pairs(runtime.throwSupported) do
    if name~="Grenade" and name~="Molotov" and name~="Zombie Bait" and name~="Pipe Bomb" then
        local suffix="_"..name:gsub(".",function(c) return string.format("%02x",string.byte(c)) end)
        runtime.extraSpecs["ThrowEnabled"..suffix]={false}
        runtime.extraSpecs["ThrowKey"..suffix]={"None"}
    end
end
runtime.consumableDefinitions = {
    {"Speed Drink","Z"},{"Energy Drink","Z"},{"Deadeye Drink","X"},{"Experimental Drink","X"},
    {"Bandage","C"},{"Booster Kit","V"},{"First Aid Kit","B"}
}
for index,item in ipairs(runtime.consumableDefinitions) do
    runtime.extraSpecs["UseItem"..index]={false}
    runtime.extraSpecs["ItemKey"..index]={item[2]}
end
for index=1,3 do
    runtime.extraSpecs["Tool"..index]={""}
    runtime.extraSpecs["Upgrades"..index]={{}}
    runtime.extraSpecs["AutoUpgrade"..index]={false}
end
runtime.healDefinitions={
    {name="Bandage",key="AutoBandage",threshold="BandageHP"},
    {name="First Aid Kit",key="AutoFirstAid",threshold="FirstAidHP"},
    {name="Booster Kit",key="AutoBooster",threshold="BoosterHP"}
}
for _,entry in ipairs(runtime.healDefinitions) do
    runtime.extraSpecs[entry.key]={false};runtime.extraSpecs[entry.threshold]={50,10,90}
end
runtime.extra, runtime.extraUI = {}, {}
for key,spec in pairs(runtime.extraSpecs) do runtime.extra[key]=spec[1] end
function runtime.validateExtras(source)
    assert(source==nil or type(source)=="table","Invalid extension settings.")
    local clean={}
    for key,spec in pairs(runtime.extraSpecs) do
        local value=source and source[key]
        if key=="ThrowMode" and value=="Largest group" then value="Most crowded" end
        if value==nil then value=spec[1] end
        assert(type(value)==type(spec[1]),"Invalid setting: "..key)
        if type(value)=="number" then assert(value==value and value>=spec[2] and value<=spec[3],"Out of range: "..key) end
        if type(value)=="string" then
            assert(#value<=100 and not value:find("%c"),"Invalid text: "..key)
            if type(spec[2])=="table" then assert(table.find(spec[2],value),"Invalid choice: "..key) end
        end
        if type(value)=="table" then
            local copy,count={},0
            for name,selected in pairs(value) do
                count=count+1
                assert(count<=300 and type(name)=="string" and #name<=100 and type(selected)=="boolean","Invalid selection: "..key)
                if selected then copy[name]=true end
            end
            value=copy
        end
        clean[key]=value
    end
    return clean
end

local fileName = "LearnedZombies.json"
local knownZombies = {"ArmouredZombie","HeadlessZombie","GuardianZombie","Assassin","Berserker","Boomer","Boss","Crawler","Destroyer","ElectricZombie","Flamer","HeavyArmourZombie","HelmetZombie","Hunter","LongArm","LongerArm","MinerZombie","RadioactiveZombie","RiotZombie","Slasher","SniperZombie","Spitter","ToxicZombie","Wraith","Zombie","DrenchWraith","Sponger"}

local function loadZombies()
    if isfile and isfile(fileName) then
        local success, result = pcall(function()
            return HttpService:JSONDecode(readfile(fileName))
        end)
        if success and type(result) == "table" then
            for _, zombieName in ipairs(result) do
                if not table.find(knownZombies, zombieName) then
                    table.insert(knownZombies, zombieName)
                end
            end
        end
    end
end

local function saveZombies()
    if writefile then
        writefile(fileName, HttpService:JSONEncode(knownZombies))
    end
end
loadZombies()
local pointState = {focused = true, last = nil, fixed = nil, picking = false,
    pickAfter = 0, savedBehavior = nil, savedIcon = nil}
local cachedTarget, cachedPosition, cachedAt = nil, nil, 0
local nextScan = 0
local scanWarned = false
local function invalidateTarget()
    cachedTarget, cachedPosition, cachedAt = nil, nil, 0
    nextScan = 0
    if runtime.clearFacingPose then runtime.clearFacingPose() end
end
local function validPoint(point)
    local camera = Workspace.CurrentCamera
    if not camera or not point then return false end
    local size = camera.ViewportSize
    return point.X >= 0 and point.Y >= 0 and point.X < size.X and point.Y < size.Y
end
local function getAimPoint()
    local camera = Workspace.CurrentCamera
    if not camera then return nil end
    if config.CursorMode == "Fixed position" and not pointState.picking then
        return validPoint(pointState.fixed) and pointState.fixed or nil
    end
    if config.CursorMode == "Screen center" and not pointState.picking then
        return camera.ViewportSize / 2
    end
    if pointState.focused then
        local point = UIS:GetMouseLocation()
        if validPoint(point) then pointState.last = point else return nil end
    end
    return validPoint(pointState.last) and pointState.last or nil
end
local function menuVisible()
    local ok, visible = pcall(function() return Window == nil or Window.Holder == nil or Window.Holder.Visible end)
    return not ok or visible -- Pause when menu visibility cannot be determined.
end
local pickerArrow = Drawing.new("Triangle")
pickerArrow.Filled = true
pickerArrow.Color = Color3.fromRGB(255, 255, 255)
pickerArrow.Visible = false
pickerArrow.ZIndex = 1000
local pickerOutline = Drawing.new("Triangle")
pickerOutline.Filled = false
pickerOutline.Thickness = 2
pickerOutline.Color = Color3.fromRGB(0, 0, 0)
pickerOutline.Visible = false
pickerOutline.ZIndex = 1001
local restoreIconUntil = 0
local restoreIconValue = true
local function finishPick()
    pointState.picking = false
    pickerArrow.Visible, pickerOutline.Visible = false, false
    restoreIconValue = pointState.savedIcon ~= false
    restoreIconUntil = os.clock() + 0.25
    if pointState.savedBehavior then UIS.MouseBehavior = pointState.savedBehavior end
    if pointState.savedIcon ~= nil then UIS.MouseIconEnabled = pointState.savedIcon end
    pointState.savedBehavior, pointState.savedIcon = nil, nil
end
connect(UIS.WindowFocusReleased, function()
    pointState.focused = false
    pointState.recoverHold = true
    if pointState.picking then finishPick() end
end)
connect(UIS.WindowFocused, function() pointState.focused = true; pointState.recoverHold = true end)
local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 1.5
fovCircle.NumSides = 64
fovCircle.Filled = false
fovCircle.Transparency = 1
fovCircle.Visible = false
connect(RunService.RenderStepped, function()
    Camera = Workspace.CurrentCamera
    local point = getAimPoint()
    fovCircle.Visible = point ~= nil and (config.ShowFOV or pointState.picking)
    if point then fovCircle.Position = point end
    fovCircle.Radius = config.FOVRadius
    fovCircle.Color = config.FOVColor
end)

local function equippedGun()
    local character = LocalPlayer.Character
    return character and character:FindFirstChildOfClass("Tool")
end
local function readValue(parent, name)
    local item = parent and parent:FindFirstChild(name)
    return item and item.Value
end
local function gunProfile()
    local tool = equippedGun()
    if not tool then return nil end
    local current = tool:FindFirstChild("CurrentValues")
    local other = tool:FindFirstChild("OtherValues")
    local mode = readValue(current, "FireType")
    local kind = string.lower(tostring(readValue(other, "Type") or ""))
    if not tool:FindFirstChild("GunScript") or not current then return nil end
    if kind == "melee" or kind == "launcher" or kind == "flamethrower"
        or kind == "utility" or kind == "throwable" or kind == "grenade" then return nil end
    if current:FindFirstChild("ProjectileSpeed") or readValue(other, "ToggledAltValue") == true then return nil end
    if mode ~= "Single" and mode ~= "Burst" and mode ~= "FullAuto" and mode ~= "Continuous" then return nil end
    return tool, mode, current
end
-- Use the gun range formula; unavailable modules leave the base range.
function runtime.armouredPart(part)
    local name=string.lower(part.Name)
    return name:find("armour",1,true)~=nil or name:find("armor",1,true)~=nil
        or name:find("shield",1,true)~=nil or name:find("helmet",1,true)~=nil or name=="stonearm"
end
function runtime.headForHit(hit)
    if not hit or not hit:IsA("BasePart") then return end
    local model=hit.Parent
    if not model or model.Parent~=zombiesFolder or not model:FindFirstChildOfClass("Humanoid") then return end
    local head=model:FindFirstChild("Head")
    if head and head:IsA("BasePart") then return head end
end
function runtime.restoreRecoil()
    local patch=runtime.recoilPatch
    if patch and patch.module.AddRecoil==patch.wrapper then patch.module.AddRecoil=patch.original end
    runtime.recoilPatch=nil
end
function runtime.updateRecoil()
    if not config.NoRecoil then runtime.restoreRecoil() return end
    if runtime.recoilPatch then return end
    local scripts=LocalPlayer:FindFirstChild("PlayerScripts")
    local gui=scripts and scripts:FindFirstChild("GuiManager")
    local main=gui and gui:FindFirstChild("MainGui")
    local object=main and main:FindFirstChild("CharGui")
    if not object then runtime.modifierStatus="No recoil: CharGui unavailable" return end
    local ok,module=pcall(require,object)
    if not ok or type(module)~="table" or type(module.AddRecoil)~="function" then
        runtime.modifierStatus="No recoil: AddRecoil unavailable";return
    end
    local original=module.AddRecoil
    local wrapper=function(...)
        if runtime.active and config.NoRecoil then return end
        return original(...)
    end
    runtime.recoilPatch={module=module,original=original,wrapper=wrapper}
    module.AddRecoil=wrapper
    runtime.modifierStatus="No recoil: recoil callback installed"
end
connect(RunService.Heartbeat,function()
    if os.clock()<(runtime.modifierNext or 0) then return end
    runtime.modifierNext=os.clock()+1
    if config.NoRecoil then runtime.updateRecoil() end
end)

local rangeManager, rangeMods
pcall(function()
    local modules = game:GetService("ReplicatedStorage"):FindFirstChild("ModuleScripts")
    if modules then
        rangeManager = require(modules:FindFirstChild("CharacterManager"))
        rangeMods = require(modules:FindFirstChild("ModOperations"))
    end
end)
local rangeCache = {tool = nil, nextUpdate = 0, value = nil, source = "No gun equipped"}
local rangeLabel
local function validRange(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
end
local function detectedRange(tool, current)
    if tool == rangeCache.tool and os.clock() < rangeCache.nextUpdate then return rangeCache.value end
    rangeCache.tool, rangeCache.nextUpdate = tool, os.clock() + 0.25
    local base = readValue(current, "Range")
    rangeCache.value = validRange(base) and base or nil
    rangeCache.source = rangeCache.value and "Base range" or "Range unavailable"
    if rangeCache.value and rangeManager and rangeMods then
        local ok, effective = pcall(function()
            local mods = {}
            local saved = _G.ClientPlayerMods and _G.ClientPlayerMods[tool.Name]
            if saved then mods = rangeMods:GetModStats(saved) end
            local context = {Tool = tool, ModStats = mods, IsFlamethrower = false}
            local added = rangeManager:GetAdded("Range", LocalPlayer, context)
            local multiplier = rangeManager:GetMulti("Range", LocalPlayer, context)
            return (base + added) * multiplier
        end)
        if ok and validRange(effective) then
            rangeCache.value, rangeCache.source = effective, "Effective range"
        end
    end
    return rangeCache.value
end
local function rangeLimit(tool, current)
    if not config.RangeCheck then return math.huge end
    if config.RangeMode == "Manual" then return config.ManualRange end
    return detectedRange(tool, current)
end
local function withinRange(origin, point, limit)
    return limit ~= nil and (limit == math.huge or (origin and (point - origin).Magnitude <= limit))
end

local function gunReady(tool, current)
    if tool.Enabled == false then return false end
    if readValue(tool, "Reloading") == true then return false end
    local clip = readValue(current, "Clip")
    return type(clip) ~= "number" or clip ~= 0
end
local function getWeaponOrigin()
    local character = LocalPlayer.Character
    local head = character and character:FindFirstChild("Head")
    local camera = Workspace.CurrentCamera
    if not head or not camera then return nil end
    if (camera.CFrame.Position - head.Position).Magnitude <= 2 then
        return camera.CFrame.Position
    end
    return head.Position
end

local function updatePickerCursor()
    if not runtime.active then return end
    local selecting = pointState.picking and pointState.focused
    pickerArrow.Visible, pickerOutline.Visible = selecting, selecting
    if selecting then
        UIS.MouseBehavior = Enum.MouseBehavior.Default
        UIS.MouseIconEnabled = false -- A single clear cursor, independent of the game's icon.
        local point = UIS:GetMouseLocation()
        pickerArrow.PointA = point
        pickerArrow.PointB = point + Vector2.new(16, 6)
        pickerArrow.PointC = point + Vector2.new(6, 16)
        pickerOutline.PointA, pickerOutline.PointB, pickerOutline.PointC = pickerArrow.PointA, pickerArrow.PointB, pickerArrow.PointC
    elseif os.clock() < restoreIconUntil and pointState.focused and not menuVisible() then
        UIS.MouseIconEnabled = restoreIconValue
    end
end
RunService:BindToRenderStep("CombatAssistantPickerCursor", Enum.RenderPriority.Last.Value + 1, updatePickerCursor)
local visibilityParams = RaycastParams.new()
visibilityParams.FilterType = Enum.RaycastFilterType.Exclude
function runtime.zombiePart(part)
    local parent=part and part.Parent
    for _=1,8 do
        if not parent then return false end
        if parent.Parent==zombiesFolder then return true end
        parent=parent.Parent
    end
    return false
end
function runtime.traceVisible(origin, direction, ignored, ignoreWater)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = ignoreWater == true
    local excluded = {}
    for _, instance in ipairs(ignored) do table.insert(excluded, instance) end
    local result
    for _ = 1, 32 do
        params.FilterDescendantsInstances = excluded
        result = Workspace:Raycast(origin, direction, params)
        local part = result and result.Instance
        if not part or not part:IsA("BasePart") or part.Transparency ~= 1 or runtime.zombiePart(part) then return result, excluded end
        -- Bound the work and leave the final hit blocking if the limit is reached.
        if table.find(excluded, part) then return result, excluded end
        if #excluded >= #ignored + 31 then return result, excluded end
        table.insert(excluded, part)
    end
    return result, excluded
end
local function clearPath(origin, point, model)
    local offset = point - origin
    if offset.Magnitude < 0.001 then return true end
    local result
    if config.IgnoreInvisibleParts then
        result = runtime.traceVisible(origin, offset, visibilityParams.FilterDescendantsInstances, false)
    else
        result = Workspace:Raycast(origin, offset, visibilityParams)
    end
    return result == nil or result.Instance:IsDescendantOf(model),result
end

function runtime.targetPoints(part,origin,expanded)
    local points={part.Position}
    if not expanded or not part.Size or not part.CFrame then return points end
    local frame,size=part.CFrame,part.Size
    local up,right=frame.UpVector*(size.Y*.4),frame.RightVector*(size.X*.4)
    table.insert(points,part.Position+up)
    table.insert(points,part.Position+right)
    table.insert(points,part.Position-right)
    table.insert(points,part.Position-up)
    if frame.LookVector then
        local forward=frame.LookVector*(size.Z*.4)
        table.insert(points,part.Position+forward)
        table.insert(points,part.Position-forward)
        local delta=origin and origin-part.Position
        if delta then
            local function side(axis) return delta.X*axis.X+delta.Y*axis.Y+delta.Z*axis.Z>=0 and 1 or -1 end
            table.insert(points,part.Position+up*side(frame.UpVector)+right*side(frame.RightVector)+forward*side(frame.LookVector))
        end
    end
    return points
end
function runtime.immediateThreat(model,root)
    if not config.Triggerbot or not root then return false end
    local body=model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso") or model:FindFirstChild("Head")
    return body and (body.Position-root.Position).Magnitude<=20
        and (model.Name=="Assassin" or body.Position.Y<root.Position.Y-3) or false
end
local function exposedPoint(candidate, origin, center, limit)
    local model = candidate.model
    local root=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local body=model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
    local contact=config.Triggerbot and root and body and (root.Position-body.Position).Magnitude<=6
    local ignoreFOV=config.Triggerbot
    if contact and not origin then origin=Camera.CFrame.Position end
    local parts = {}
    local head = model:FindFirstChild("Head")
    if head and head:IsA("BasePart") then table.insert(parts, head) end
    if config.BodyFallback or runtime.extra.OP2 or contact or runtime.immediateThreat(model,root) then
        for _, name in ipairs({
            "UpperTorso", "Torso", "LowerTorso",
            "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
            "LeftHand", "RightHand", "Left Arm", "Right Arm",
            "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg",
            "LeftFoot", "RightFoot", "Left Leg", "Right Leg"
        }) do
            local part = model:FindFirstChild(name)
            if part and part:IsA("BasePart") then table.insert(parts, part) end
        end
    end
    local bestPart,bestPoint,bestDamage,fallbackPart,fallbackPoint
    local damageCache={};local reason="No aimable body parts";local reachedRange=false
    for _, part in ipairs(parts) do
        local points = runtime.targetPoints(part,origin,config.WeaponClearance or ignoreFOV or contact)
        for _, point in ipairs(points) do
            local screen, onScreen = Camera:WorldToViewportPoint(point)
            local eligible=ignoreFOV or (onScreen and (Vector2.new(screen.X, screen.Y) - center).Magnitude <= config.FOVRadius)
            local hit
            if not eligible then reason="Outside manual aim FOV"
            elseif not withinRange(origin,point,limit) then if not reachedRange then reason="Outside gun range" end;eligible=false
            else
                reachedRange=true
                if config.WeaponClearance or ignoreFOV then
                    local clear;clear,hit=clearPath(origin,point,model)
                    if not clear then reason="Shot path blocked: "..tostring(hit and hit.Instance and hit.Instance.Name or "geometry");eligible=false end
                end
                if eligible and not ignoreFOV and config.VisibleCheck and not clearPath(Camera.CFrame.Position,point,model) then
                    reason="Camera visibility blocked";eligible=false
                end
            end
            if eligible and (not contact or (point-origin).Magnitude>=.001) then
                if not runtime.extra.OP2 then return part, point end
                local actual=part
                local start=origin or Camera.CFrame.Position
                if not (config.WeaponClearance or ignoreFOV) then
                    if config.IgnoreInvisibleParts then hit=runtime.traceVisible(start,point-start,visibilityParams.FilterDescendantsInstances,false) else hit=Workspace:Raycast(start,point-start,visibilityParams) end
                end
                if hit and hit.Instance and hit.Instance:IsDescendantOf(model) then actual=hit.Instance
                elseif hit then actual=nil end
                if actual and not runtime.armouredPart(actual) then
                    if config.HeadshotConversion then return actual,hit and hit.Position or point end
                    local damage=damageCache[actual]
                    if damage==nil then
                        local ok,value=pcall(function() return rangeManager:GetDamage(LocalPlayer,actual,equippedGun(),{}) end)
                        damage=ok and validRange(value) and value or false;damageCache[actual]=damage
                    end
                    if damage==false then
                        -- Missing client damage estimates must not disable an otherwise clear shot.
                        runtime.damageEstimateUnavailable=true
                        if not fallbackPart then fallbackPart,fallbackPoint=actual,hit and hit.Position or point end
                    elseif damage>0 and (not bestDamage or damage>bestDamage) then bestDamage,bestPart,bestPoint=damage,actual,hit and hit.Position or point
                    elseif damage==0 then reason="Estimated damage is zero" end
                else reason="Armour or shield blocks exposed points" end
            end
        end
    end
    return bestPart or fallbackPart,bestPoint or fallbackPoint,reason
end

local function protectedZombie(model)
    if model:FindFirstChildOfClass("ForceField") then return true,"ForceField" end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.MaxHealth==math.huge then return true,"Invulnerable (infinite MaxHealth)" end
    if runtime.extra.SkipCloaked and model.Name=="Assassin" then
        -- Visibility proxy: the extracted client does not expose its server vulnerability flag.
        local body=model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso") or model:FindFirstChild("Head")
        if body and body:IsA("BasePart") and body.Transparency>=.95 then return true,"Skip cloaked Assassins is enabled (appearance check)" end
    end
    return false
end
function runtime.closeZombie(model,root)
    local part=model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("Head")
    return runtime.extra.ClosePriority and root and part and (part.Position-root.Position).Magnitude<=runtime.extra.CloseDistance or false
end
local function getTargetHead()
    runtime.targetName, runtime.targetTier = nil, nil
    runtime.targetBlocked=nil;runtime.damageEstimateUnavailable=nil
    runtime.superSeen = 0
    Camera = Workspace.CurrentCamera
    local center = getAimPoint()
    if not Camera or not center then return nil end
    local tool, _, current = gunProfile()
    if not tool then return nil end
    local ignoreFOV=config.Triggerbot
    local limit
    if ignoreFOV then limit=config.RangeMode=="Manual" and config.ManualRange or detectedRange(tool,current)
    else limit=rangeLimit(tool,current) end
    local origin = (ignoreFOV or config.WeaponClearance or config.RangeCheck) and getWeaponOrigin() or nil
    if limit == nil or ((ignoreFOV or config.WeaponClearance or config.RangeCheck) and not origin) then return nil end
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local ignored = {Camera}
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then table.insert(ignored, player.Character) end
    end
    visibilityParams.FilterDescendantsInstances = ignored
    local candidate
    for _, zombie in ipairs(zombiesFolder:GetChildren()) do
        if config.SuperPriorityList[zombie.Name] then runtime.superSeen = runtime.superSeen + 1 end
        local protected,blockReason=protectedZombie(zombie)
        if config.IgnoreList[zombie.Name] then blockReason=blockReason or "Ignore list" end
        if zombie:IsA("Model") and not protected and (not config.IgnoreList[zombie.Name] or runtime.closeZombie(zombie,root)) then
            local humanoid = zombie:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                local part, point,reason = exposedPoint({model = zombie}, origin, center, limit)
                if not part then blockReason=reason end
                if part then
                    blockReason=nil
                    local projected = Camera:WorldToViewportPoint(point)
                    local score = (Vector2.new(projected.X, projected.Y) - center).Magnitude
                    if (ignoreFOV or config.TargetMode == "Closest to Player") and root then score = (point - root.Position).Magnitude end
                    local found = {part = part, point = point, model = zombie, score = score,
                        priority = runtime.immediateThreat(zombie,root) and 4 or runtime.closeZombie(zombie,root) and 3 or (config.SuperPriorityList[zombie.Name] and 2 or (config.PriorityList[zombie.Name] and 1 or 0))}
                    if not candidate or found.priority>candidate.priority or (found.priority==candidate.priority and found.score<candidate.score) then candidate=found end
                end
            end
        end
        if blockReason and root then
            local body=zombie:FindFirstChild("HumanoidRootPart") or zombie:FindFirstChild("Torso") or zombie:FindFirstChild("UpperTorso") or zombie:FindFirstChild("Head")
            local distance=body and (body.Position-root.Position).Magnitude
            if distance and distance<=30 and (not runtime.targetBlocked or distance<runtime.targetBlocked.distance) then
                runtime.targetBlocked={name=zombie.Name,reason=blockReason,distance=distance}
            end
        end
    end
    if candidate then
        runtime.targetName = candidate.model.Name
        runtime.targetTier = candidate.priority == 4 and "Threat" or candidate.priority == 3 and "Close" or candidate.priority == 2 and "Super" or (candidate.priority == 1 and "Priority" or "Normal")
        return candidate.part, candidate.point
    end
end
connect(RunService.Heartbeat, function()
    if pointState.picking or not (config.SilentAim or config.Triggerbot) then
        invalidateTarget()
        return
    end
    local now = os.clock()
    if now < nextScan then return end
    nextScan = now + 1 / 30
    local ok, head, point = pcall(getTargetHead)
    cachedTarget = ok and head or nil
    cachedPosition = cachedTarget and point or nil
    cachedAt = now
    if not ok then
        nextScan = now + 1
        if not scanWarned then
            scanWarned = true
            warn("[Combat Assistant] Target scan paused; retrying: " .. tostring(head))
        end
    else
        scanWarned = false
    end
end)

-- Share the selected shot point with the game's normal arm-aim data. The
-- native LookPos rays and camera stay intact; no extra packet sender is added.
runtime.facing={status="Waiting for target",available=false}
function runtime.releaseFacing()
    local a=runtime.facing
    if a.humanoid and a.humanoid.AutoRotate==false then
        pcall(function() a.humanoid.AutoRotate=a.autoRotate end)
    end
    a.humanoid=nil;a.autoRotate=nil
end
function runtime.clearFacingPose()
    runtime.releaseFacing()
    local a=runtime.facing
    a.pose=nil;a.poseCharacter=nil;a.poseTool=nil;a.poseRoot=nil;a.neutralPose=nil
end
function runtime.automaticFacing()
    return config.Triggerbot or (runtime.extra and runtime.extra.Autofarm==true) or false
end
function runtime.facingADSActive()
    local character=LocalPlayer.Character
    local tool=character and character:FindFirstChildOfClass("Tool")
    local current=tool and tool:FindFirstChild("CurrentValues")
    local hold=current and current:FindFirstChild("HoldType")
    -- Dual guns cannot ADS in the native GunScript. Do not accept a lingering
    -- ADS value from the previously equipped weapon, or a toggle that failed.
    if not hold or hold.Value=="Dual" then return false end
    local data=runtime.facing.network:GetPlayerNetworkData(LocalPlayer)
    return data and data.Adsing==true or false
end
function runtime.facingContext()
    local a=runtime.facing
    local automatic=runtime.automaticFacing()
    if not runtime.active or not a.available or (pointState.picking and not automatic) or not (config.SilentAim or automatic) then
        runtime.clearFacingPose();return
    end
    local character=LocalPlayer.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    local root=character and character:FindFirstChild("HumanoidRootPart")
    local tool=character and character:FindFirstChildOfClass("Tool")
    if not humanoid or humanoid.Health<=0 or not root or not tool or not tool:FindFirstChild("GunScript") then
        runtime.clearFacingPose();return
    end
    if a.pose and (a.poseCharacter~=character or a.poseTool~=tool or a.poseRoot~=root) then runtime.clearFacingPose() end
    local other=tool:FindFirstChild("OtherValues")
    local mounted=other and other:FindFirstChild("MountedWeapon")
    if mounted and mounted.Value then runtime.clearFacingPose();return end -- Retain native mounted angle limits.
    if not automatic and (runtime.action or runtime.refillBusy or runtime.consumableBusy) then return end
    if not pointState.picking and cachedTarget and cachedTarget.Parent and os.clock()-cachedAt<=.15 and typeof(cachedPosition)=="Vector3" then
        local point=cachedPosition;local valid=true
        for _,n in ipairs({point.X,point.Y,point.Z}) do if n~=n or math.abs(n)==math.huge then valid=false;break end end
        if valid then
            -- Store character-relative aim, without retaining the killed zombie.
            a.pose=root.CFrame:VectorToObjectSpace(point-root.Position)
            a.poseCharacter=character;a.poseTool=tool;a.poseRoot=root
            a.neutralPose=nil
            return point,humanoid,root,false
        end
    end
    if automatic and not a.pose then
        -- Automatic modes never initialize their idle gun pose from mouse aim.
        -- Recreate a level forward pose after equip or respawn, until a target appears.
        a.pose=Vector3.new(0,1.5,-100);a.neutralPose=true
        a.poseCharacter=character;a.poseTool=tool;a.poseRoot=root
    end
    if a.pose then return root.Position+root.CFrame:VectorToWorldSpace(a.pose),humanoid,root,true end
end
function runtime.facingFailure(reason)
    runtime.clearFacingPose();runtime.facing.available=false
    runtime.facing.status="Unavailable: "..tostring(reason)
end
function runtime.installFacing()
    local a=runtime.facing
    local ok,err=pcall(function()
        local scripts=LocalPlayer:FindFirstChild("PlayerScripts")
        local manager=scripts and scripts:FindFirstChild("LocalManager")
        assert(manager,"LocalManager missing; reload after the game loads")
        -- Require once in the executor initialization context, never inside a
        -- Roblox render callback, and never call the modules' Init a second time.
        a.look=require(assert(manager:FindFirstChild("LookPosManager"),"LookPosManager missing"))
        a.rotation=require(assert(manager:FindFirstChild("RotationManager"),"RotationManager missing"))
        a.network=require(assert(manager:FindFirstChild("NetworkManager"),"NetworkManager missing"))
        assert(type(a.look.UpdateLocalLookPos)=="function" and type(a.rotation.RenderStepped)=="function"
            and type(a.network.PassDataA)=="function" and type(a.network.GetPlayerNetworkData)=="function","Unsupported native aim modules")
        a.originalLook=a.look.UpdateLocalLookPos;a.originalRotation=a.rotation.RenderStepped
        a.lookWrapper=function(self,...)
            local result=table.pack(a.originalLook(self,...))
            local data=a.network:GetPlayerNetworkData(LocalPlayer)
            a.nativePoint=data and data.LookPos
            local success,point=pcall(runtime.facingContext)
            if not success then runtime.facingFailure(point)
            elseif point then
                local passed,reason=pcall(a.network.PassDataA,a.network,"LookPos",point)
                if not passed then runtime.facingFailure(reason) end
            end
            return table.unpack(result,1,result.n)
        end
        a.rotationWrapper=function(self,dt,...)
            local success,point,humanoid,root,holding=pcall(runtime.facingContext)
            if not success then runtime.facingFailure(point);point=nil end
            local ads,movement=false,false
            if point then
                local ok,value=pcall(runtime.facingADSActive)
                if not ok then runtime.facingFailure(value);point=nil else ads=value end
            end
            if point and ads and not holding then
                local state=humanoid:GetState()
                local types=Enum.HumanoidStateType
                local farm=runtime.extensions and runtime.extensions.farm
                movement=humanoid.Sit or (types and (state==types.Climbing or state==types.Swimming or state==types.Physics
                    or state==types.PlatformStanding)) or (farm and (farm.moving or farm.walkPoint or farm.climbDirection
                    or farm.exitWalking or farm.exitTransit)) or humanoid.FloorMaterial==Enum.Material.Air
            end
            if point and (holding or not ads or movement) then
                runtime.releaseFacing()
                -- Arms see the zombie (or retained pose), while normal body/camera
                -- rotation sees mouse aim. Target-driven body turning requires ADS.
                local data=a.network:GetPlayerNetworkData(LocalPlayer)
                local saved=data and data.LookPos
                if data then data.LookPos=a.nativePoint or saved end
                local result=table.pack(pcall(a.originalRotation,self,dt,...))
                if data then data.LookPos=saved end
                if not result[1] then error(result[2],0) end
                local valid,held,_,_,stillHolding=pcall(runtime.facingContext)
                if not valid then runtime.facingFailure(held)
                elseif held then
                    local updated,reason=pcall(a.network.PassDataA,a.network,"LookPos",held)
                    if not updated then runtime.facingFailure(reason)
                    else a.status=stillHolding and (a.neutralPose and "Mouse-independent idle pose" or "Holding last aim pose")
                        or (movement and "Arms aiming; movement controls facing" or "Arms tracking target; body follows movement") end
                end
                return table.unpack(result,2,result.n)
            end
            if point then
                local rotated,reason=pcall(function()
                    if a.humanoid~=humanoid then runtime.releaseFacing();a.humanoid=humanoid;a.autoRotate=humanoid.AutoRotate end
                    local delta=Vector3.new(point.X-root.Position.X,0,point.Z-root.Position.Z)
                    if delta.Magnitude>.05 then
                        local look=root.CFrame.LookVector
                        local angle=math.atan2(delta.X,delta.Z)-math.atan2(look.X,look.Z)
                        angle=(angle+math.pi)%(2*math.pi)-math.pi
                        local step=type(dt)=="number" and dt==dt and dt>=0 and math.min(dt,.05) or 0
                        local turn=math.max(-4*math.pi*step,math.min(4*math.pi*step,angle))
                        humanoid.AutoRotate=false
                        root.CFrame=root.CFrame*CFrame.Angles(0,turn,0)
                    end
                    a.pose=root.CFrame:VectorToObjectSpace(point-root.Position)
                    a.status="ADS: body and arms tracking target"
                end)
                if rotated then return end
                runtime.facingFailure(reason)
            end
            runtime.releaseFacing()
            if a.available then a.status="Waiting for target" end
            return a.originalRotation(self,dt,...)
        end
        a.look.UpdateLocalLookPos=a.lookWrapper;a.rotation.RenderStepped=a.rotationWrapper
        a.available=true;a.status="Waiting for target"
    end)
    if not ok then runtime.facingFailure(err) end
end
function runtime.restoreFacing()
    local a=runtime.facing;runtime.clearFacingPose();a.available=false
    if a.look and a.look.UpdateLocalLookPos==a.lookWrapper then a.look.UpdateLocalLookPos=a.originalLook end
    if a.rotation and a.rotation.RenderStepped==a.rotationWrapper then a.rotation.RenderStepped=a.originalRotation end
end
runtime.installFacing()
table.insert(runtime.connections,{Disconnect=runtime.restoreFacing})

-- LookPosManager and camera modules use this ray API too. Only redirect
-- calls from the equipped weapon's GunScript; never change their rays.
runtime.callerLookup = getcallingscript
runtime.callerWarning = false
function runtime.isEquippedGunCaller()
    if type(runtime.callerLookup) ~= "function" then
        if not runtime.callerWarning then
            runtime.callerWarning = true
            warn("[Combat Assistant] Silent Aim needs getcallingscript; ray redirection is disabled.")
        end
        return false
    end
    local ok, caller = pcall(runtime.callerLookup)
    if not ok or not caller then return false end
    local character = LocalPlayer.Character
    local tool = character and character:FindFirstChildOfClass("Tool")
    return tool ~= nil and caller == tool:FindFirstChild("GunScript")
end
-- One shared dispatcher survives reloads without retaining unloaded runtimes.
if not runtime.slot.original then
    local slot = runtime.slot
    slot.original = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if slot.handler then return slot.handler(self, ...) end
        return slot.original(self, ...)
    end))
end
runtime.penetrationRays=setmetatable({}, {__mode="k"})
function runtime.singleHitEnabled()
    if not runtime.extra.AssassinShotGuard or not (config.SilentAim or config.Triggerbot) then return false end
    local tool,mode,current=gunProfile()
    if not tool or mode=="Continuous" or (readValue(current,"RayRadius") or 0)>0 then return false end
    return true
end
function runtime.penetrationDirection(ray,ignored)
    if type(ignored)~="table" then return end
    local previous=runtime.penetrationRays[ignored]
    if not previous then return end
    -- GunScript reuses this list, adds the previous victim and advances to its impact.
    if os.clock()-previous.at<=.25 and table.find(ignored,previous.model)
        and (ray.Origin-previous.point).Magnitude<=.01
        and ray.Direction.Magnitude<=previous.length+.01
        and (ray.Direction.Unit-previous.originalUnit).Magnitude<=.0001 then
        return previous.direction
    end
    runtime.penetrationRays[ignored]=nil
end
function runtime.rememberPenetration(original,args,result)
    local ignored=original[2]
    if type(ignored)~="table" then return end
    runtime.penetrationRays[ignored]=nil
    local part,point=result[1],result[2]
    if not part or typeof(point)~="Vector3" then return end
    local model=part.Parent
    for _=1,5 do
        if not model or model.Parent==zombiesFolder then break end
        model=model.Parent
    end
    if not model or model.Parent~=zombiesFolder then return end
    runtime.penetrationRays[ignored]={model=model,point=point,at=os.clock(),
        originalUnit=original[1].Direction.Unit,direction=args[1].Direction.Unit,length=args[1].Direction.Magnitude}
end

local oldNamecall = runtime.slot.original
runtime.slot.handler = function(self, ...)
    local method = getnamecallmethod()
    if runtime.active and runtime.op and (runtime.op.any or config.HeadshotConversion or runtime.extra.MeleeAura) and not runtime.op.busy and method=="FireServer" and type(setnamecallmethod)=="function" then
        runtime.op.busy=true
        local ok,result=pcall(runtime.op.namecall,self,method,table.pack(...))
        runtime.op.busy=false;setnamecallmethod(method)
        if not ok then runtime.op.last="Experimental request transform failed: "..tostring(result)
        elseif result then
            if result.blocked then return end
            return oldNamecall(self,table.unpack(result,1,result.n))
        end
    end
    -- Never inspect characters or reset method state for unrelated game calls.
    if not runtime.active or not (config.SilentAim or config.Triggerbot or config.NoSpread or config.HeadshotConversion or runtime.actionAim) or self ~= Workspace
        or (method ~= "FindPartOnRayWithIgnoreList" and method ~= "findPartOnRayWithIgnoreList")
        or (checkcaller() and not runtime.actionAim) then return oldNamecall(self, ...) end
    if type(setnamecallmethod) ~= "function" then
        if not runtime.methodWarning then
            runtime.methodWarning = true
            warn("[Combat Assistant] Silent Aim paused: setnamecallmethod is unavailable.")
        end
        return oldNamecall(self, ...)
    end
    local original = table.pack(...)
    if runtime.actionAim and os.clock()<runtime.actionAim.untilAt then
        local action=runtime.actionAim
        local ok,caller=pcall(runtime.callerLookup)
        local ray=original[1]
        if ok and caller==action.script and typeof(ray)=="Ray" and ray.Direction.Magnitude>500 and action.part.Parent then
            local delta=action.part.Position-ray.Origin
            if delta.Magnitude>.001 then original[1]=Ray.new(ray.Origin,delta.Unit*ray.Direction.Magnitude) end
            setnamecallmethod(method)
            return oldNamecall(self,table.unpack(original,1,original.n))
        end
    end
    local ok, redirected = pcall(function()
        if not runtime.isEquippedGunCaller() then return end
        local ray = original[1]
        if typeof(ray) ~= "Ray" or ray.Direction.Magnitude<=0.001 then return end
        local continuation=runtime.penetrationDirection(ray,original[2])
        if continuation and runtime.singleHitEnabled() then
            -- Native GunScript subtracts this segment length and ends the loop on zero range.
            -- Keep the real first hit; do not query or manufacture a subsequent damage target.
            return {singleHitEnd=ray.Origin+continuation.Unit*ray.Direction.Magnitude}
        end
        local targetPosition = (config.SilentAim or config.Triggerbot) and os.clock()-cachedAt<=0.15 and cachedPosition or nil
        if not continuation and not targetPosition and config.NoSpread then
            -- Match GunScript's Mouse coordinates, not UIS screen coordinates or a saved FOV point.
            local camera,mouse=Workspace.CurrentCamera,LocalPlayer:GetMouse()
            if camera and mouse and _G.ActiveInput~="Touch" then
                local aimRay=camera:ScreenPointToRay(mouse.X,mouse.Y,0.5)
                targetPosition=aimRay.Origin+aimRay.Direction*999
            end
        end
        if not continuation and not targetPosition then return end
        local offset = continuation or (targetPosition-ray.Origin)
        if offset.Magnitude<=0 then return end
        local args = table.pack(table.unpack(original,1,original.n))
        args[1] = Ray.new(ray.Origin,offset.Unit*ray.Direction.Magnitude)
        if type(args[2]) == "table" then
            local ignored = {}
            for _, instance in ipairs(args[2]) do table.insert(ignored, instance) end
            local changed = false
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character then
                    table.insert(ignored, player.Character)
                    changed = true
                end
            end
            if config.IgnoreInvisibleParts then
                local _, filtered = runtime.traceVisible(ray.Origin, args[1].Direction, ignored, args[4])
                ignored, changed = filtered, true
            end
            if changed then args[2] = ignored end
        end
        return args
    end)
    -- Nested engine queries may change method state, even when they fail.
    setnamecallmethod(method)
    if not ok then
        if not runtime.rayWarning then
            runtime.rayWarning = true
            warn("[Combat Assistant] Aim calculation failed; forwarding original shot: " .. tostring(redirected))
        end
        return oldNamecall(self, table.unpack(original, 1, original.n))
    end
    if redirected and redirected.singleHitEnd then
        runtime.penetrationRays[original[2]]=nil
        return nil,redirected.singleHitEnd,Vector3.new(0,0,0),Enum.Material.Air
    end
    local args = redirected or original
    if redirected then runtime.rayWarning=false;runtime.lastRedirect=os.clock() end
    local result=table.pack(oldNamecall(self,table.unpack(args,1,args.n)))
    if redirected then
        pcall(runtime.rememberPenetration,original,args,result)
        setnamecallmethod(method)
    end
    -- Hit override is applied to damage packets, not physical ray results.
    return table.unpack(result,1,result.n)
end

-- Roblox-local input, extracted from the supplied auto-clicker.
local virtualInput, legacyInput
local inputOK, inputResult = pcall(function()
    return UIS:CreateVirtualInput()
end)
if inputOK then virtualInput = inputResult end
if not virtualInput then
    local ok, result = pcall(function()
        local service = game:GetService("VirtualInputManager")
        assert(type(service.SendMouseButtonEvent) == "function", "No virtual mouse API")
        return service
    end)
    if ok then legacyInput = result end
end
local inputSupported = virtualInput ~= nil or legacyInput ~= nil
local backendName = virtualInput and "VirtualInput" or (legacyInput and "VirtualInputManager" or "unavailable")
local triggerToggle, cursorDropdown
local guiService = game:GetService("GuiService")
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local coreGui
pcall(function() coreGui = game:GetService("CoreGui") end)
local clickState = {held = false, point = nil, releaseAt = 0, nextClick = 0,
    retryReleaseAt = 0, retryAt = 0, failures = 0, errorWarned = false}

local function notifyTrigger(text)
    warn("[Combat Assistant] " .. text)
    pcall(function()
        Linoria:Notify("Triggerbot: " .. text, 6)
    end)
end

-- Invoke only callbacks belonging to the equipped GunScript. Never fire a whole UI signal.
function runtime.gunCallbacks()
    local tool=equippedGun()
    if not tool or type(getconnections)~="function" or type(getfenv)~="function" then return end
    local gun=tool:FindFirstChild("GunScript")
    if not gun then return end
    local now=os.clock()
    if runtime.callbackTool==tool and runtime.callbackExperimental==runtime.extra.ExperimentalFire and now<(runtime.callbackUntil or 0) then return runtime.callbacks end
    runtime.callbackExperimental=runtime.extra.ExperimentalFire
    runtime.callbackTool,runtime.callbackUntil,runtime.callbacks=tool,now+.5,nil
    local function find(signal)
        if not signal then return end
        local ok,connections=pcall(getconnections,signal)
        if not ok then return end
        for index=#connections,1,-1 do
            local connection=connections[index]
            local found,fn=pcall(function() return connection.Enabled~=false and connection.Function end)
            if found and type(fn)=="function" then
                local success,environment=pcall(getfenv,fn)
                if success and type(environment)=="table" and environment.script==gun then return fn end
            end
        end
    end
    if runtime.extra.ExperimentalFire then
        local playerGui=LocalPlayer:FindFirstChild("PlayerGui")
        local screen=playerGui and playerGui:FindFirstChild("ScreenGui")
        local touch=screen and screen:FindFirstChild("TouchControls")
        local side=touch and touch:FindFirstChild("RightSide")
        local attack=side and side:FindFirstChild("AttackButton")
        local down=attack and find(attack.MouseButton1Down)
        local up=attack and find(attack.InputEnded)
        if down and up then
            runtime.callbacks={down=down,up=up,reload=find(UIS.InputBegan),backend="Attack-button callbacks (experimental)"}
            return runtime.callbacks
        end
    end
    local ok,mouse=pcall(function() return LocalPlayer:GetMouse() end)
    if not ok then return end
    local down,up=find(mouse.Button1Down),find(mouse.Button1Up)
    if down and up then runtime.callbacks={down=down,up=up,reload=find(UIS.InputBegan),backend="Gun mouse callbacks"} end
    return runtime.callbacks
end

local function sendButton(point, down)
    if down then
        local callbacks=runtime.gunCallbacks()
        if callbacks then
            runtime.directHeld=callbacks
            local ok,err=pcall(callbacks.down)
            if not ok then pcall(callbacks.up);runtime.directHeld=nil;error(err) end
            return
        end
    elseif runtime.directHeld then
        local callbacks=runtime.directHeld
        callbacks.up();runtime.directHeld=nil;return
    end
    if virtualInput then
        virtualInput:SendMouseButton(point, Enum.UserInputType.MouseButton1, down, 0)
    elseif legacyInput then
        legacyInput:SendMouseButtonEvent(point.X, point.Y, 0, down, game, 0)
    else
        error("Roblox virtual input is unavailable in this client/executor.")
    end
end

local function duplicateButtonState(err)
    local text = string.lower(tostring(err))
    return string.find(text, "duplicate", 1, true)
        and string.find(text, "button", 1, true)
        and string.find(text, "state", 1, true)
end

local function retryInput(err)
    runtime.lastInputError = tostring(err)
    clickState.failures = math.min(clickState.failures + 1, 4)
    local delay = math.min(2, 0.25 * 2 ^ (clickState.failures - 1))
    clickState.retryAt = os.clock() + delay
    clickState.retryReleaseAt = clickState.retryAt
    if not clickState.errorWarned then
        clickState.errorWarned = true
        -- No popup: a notification can itself obstruct the selected point.
        warn("[Combat Assistant] Input paused; Triggerbot stays enabled and retries automatically: " .. tostring(err))
    end
end

local function releaseHeld()
    if not clickState.held then return true end
    local ok, err = pcall(sendButton, clickState.point, false)
    -- Duplicate UP means the button is already released; recovery is complete.
    if ok or duplicateButtonState(err) then
        clickState.held = false
        clickState.autoHeld = false
        clickState.tool, clickState.mode = nil, nil
        clickState.point = nil
        clickState.failures = 0
        clickState.errorWarned = false
        clickState.retryAt = 0
        clickState.retryReleaseAt = 0
        -- Leave at least one heartbeat between release and the next press.
        clickState.nextClick = math.max(clickState.nextClick, os.clock() + 0.01)
        return true
    end
    retryInput(err)
    return false
end

local function setTriggerEnabled(value)
    if value and pointState.picking then finishPick() end
    config.Triggerbot = value
    clickState.nextClick = os.clock() + 0.25
    if not value then
        releaseHeld()
    elseif not inputSupported and not runtime.gunCallbacks() then
        retryInput("Virtual input is unavailable in this client. Waiting without disabling the toggle.")
    elseif config.CursorMode == "Fixed position" and not validPoint(pointState.fixed) then
        retryInput("Waiting for a valid cursor position.")
    end
end

local function stopTrigger(reason)
    setTriggerEnabled(false)
    if triggerToggle then triggerToggle:SetValue(false) end
    if reason then notifyTrigger(reason) end
end

-- Native input errors also cover executors without CoreGui access.
local function pointBlocked(point)
    if not pointState.picking and runtime.gunCallbacks() then return false end
    if UIS:GetFocusedTextBox() or guiService.MenuIsOpen then return true end
    for _, container in ipairs({playerGui, coreGui}) do
        local ok, objects = pcall(function()
            return container:GetGuiObjectsAtPosition(point.X, point.Y)
        end)
        if ok then
            for _, object in ipairs(objects) do
                if object.Visible and (object.Active or object:IsA("GuiButton") or object:IsA("TextBox")) then
                    return true
                end
            end
        end
    end
    return false
end

-- Empty magazines need a reload request, not just a released fire button.
local reloadState = {tool = nil, key = nil, releaseAt = 0, retryAt = 0, nextAttempt = 0, warned = false}
local function sendReloadKey(key, down)
    if not down and runtime.directReload then runtime.directReload=false;return end
    if down then
        local callbacks=runtime.gunCallbacks()
        if callbacks and callbacks.reload then
            runtime.directReload=true
            task.spawn(function()
                if not runtime.active then return end
                local ok,err=pcall(callbacks.reload,{KeyCode=key,UserInputType=Enum.UserInputType.Keyboard},false)
                if not ok then runtime.lastInputError="Reload callback: "..tostring(err) end
            end)
            return
        end
    end
    if virtualInput then virtualInput:SendKey(down, key, false)
    elseif legacyInput then legacyInput:SendKeyEvent(down, key, false, game)
    else error("Virtual keyboard input is unavailable.") end
end
local function reloadWarning(err)
    if not reloadState.warned then
        reloadState.warned = true
        warn("[Combat Assistant] Reload input paused; retrying: " .. tostring(err))
    end
end
local function configuredReloadKey()
    local data = _G.LocalReplicatedDataStore
    local key = data and data.KeyBinds and data.KeyBinds.Reload
    if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then return key end
    if type(key) == "string" then
        local ok, value = pcall(function() return Enum.KeyCode[key] end)
        if ok and value then return value end
    end
    return Enum.KeyCode.R
end
local function finishReloadKey(now)
    if not reloadState.key then return false end
    if now >= reloadState.releaseAt and now >= reloadState.retryAt then
        local ok, err = pcall(sendReloadKey, reloadState.key, false)
        if ok then
            reloadState.key, reloadState.warned = nil, false
        else
            reloadState.retryAt = now + 0.5
            reloadWarning(err)
        end
    end
    return true
end
runtime.heatStates=setmetatable({}, {__mode="k"})
function runtime.heatBlocked(tool,current,now)
    local harmony=runtime.extra.OP3 and LocalPlayer:FindFirstChild("PlayerPerks") and LocalPlayer.PlayerPerks:FindFirstChild("HeatHighLow")
    if not (runtime.extra.OverheatManagement or harmony) or not tool then return false end
    local heat=readValue(current,"HeatClient")
    if heat==nil then return false end
    if not validRange(heat) then return true end
    local state=runtime.heatStates[tool]
    if not state then state={nextUpdate=0};runtime.heatStates[tool]=state end
    if now>=state.nextUpdate then
        state.nextUpdate=now+.25
        state.maximum,state.increase=nil,nil
        local ok,maximum,increase=pcall(function()
            assert(rangeManager and rangeMods,"Heat modifiers unavailable")
            local saved=_G.ClientPlayerMods and _G.ClientPlayerMods[tool.Name]
            local mods=saved and rangeMods:GetModStats(saved) or {}
            local context={Tool=tool,ModStats=mods}
            return readValue(current,"HeatMax")*rangeManager:GetMulti("HeatMax",LocalPlayer,context),
                readValue(current,"HeatIncrease")*rangeManager:GetMulti("HeatIncrease",LocalPlayer,context)
        end)
        if ok and validRange(maximum) and maximum>0 and validRange(increase) then
            state.maximum,state.increase=maximum,increase
        end
    end
    local maximum,increase=state.maximum,state.increase
    if not maximum then return true end
    if heat>=maximum then state.overheated=true end
    if state.overheated then
        if heat>0 then return true end
        state.overheated=false;state.paused=false
    end
    -- Leave at least two shots of headroom; a shot that itself reaches the cap is unsafe.
    local stop=math.max(0,math.min(maximum*.9,maximum-2*increase))
    if heat+increase>=maximum then state.paused=true;return true end
    if state.paused then
        if heat>math.min(maximum*(harmony and .55 or .4),stop*(harmony and .8 or .5)) then return true end
        state.paused=false
    end
    if heat>0 and heat>=stop then state.paused=true;return true end
    return false
end

function runtime.challengeReloadReady(tool,current,now)
    if not runtime.extra.QuietReload or not tool or not current then runtime.quietSince=nil;return false end
    if now<(runtime.quietScanAt or 0) then return false end
    runtime.quietScanAt=now+.2
    local root=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then runtime.quietSince=nil;return false end
    for _,model in ipairs(zombiesFolder:GetChildren()) do
        local humanoid=model:FindFirstChildOfClass("Humanoid")
        local part=model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("Head")
        if humanoid and humanoid.Health>0 and part and (part.Position-root.Position).Magnitude<=runtime.extra.ReloadClearance then runtime.quietSince=nil;return false end
    end
    runtime.quietSince=runtime.quietSince or now
    local clip,maxClip=readValue(current,"Clip"),readValue(current,"MaxClip")
    if type(clip)~="number" or type(maxClip)~="number" or maxClip<=0 or clip<=0 or clip>=maxClip then return false end
    if readValue(current,"FeedType")=="None" or readValue(current,"Ammo")==0 or readValue(tool,"Reloading")==true then return false end
    if now-runtime.quietSince<1.5 or now<(runtime.quietReloadAt or 0) or clip/maxClip*100>runtime.extra.QuietReloadPercent then return false end
    runtime.quietReloadAt=now+3;return true
end




local function requestEmptyReload(tool, current, now)
    if now < reloadState.nextAttempt or tool.Enabled == false or readValue(tool, "Reloading") == true then return end
    if readValue(current, "FeedType") == "None" or readValue(current, "Ammo") == 0 then return end
    if not runtime.gunCallbacks() and (UIS:GetFocusedTextBox() or guiService.MenuIsOpen) then return end
    reloadState.nextAttempt = now + 0.2
    local key = configuredReloadKey()
    local ok, err = pcall(sendReloadKey, key, true)
    if ok then
        reloadState.key, reloadState.releaseAt, reloadState.retryAt = key, now + 0.05, 0
    else
        reloadState.nextAttempt = now + 1.5 -- Back off only when input delivery fails.
        reloadWarning(err)
    end
end
connect(RunService.Heartbeat, function()
    local now = os.clock()
    if finishReloadKey(now) then return end
    if runtime.extra.Autofarm and runtime.extensions and runtime.extensions.farm and runtime.extensions.farm.stage<3 then releaseHeld();return end
    if runtime.consumableBusy or runtime.refillBusy then return end
    if config.Triggerbot and (type(runtime.callerLookup)~="function" or type(setnamecallmethod)~="function") then
        runtime.lastInputError="Triggerbot needs supported silent-aim hooks."
        if clickState.held then releaseHeld() end
        return
    end
    if pointState.recoverHold then
        pointState.recoverHold = false
        if clickState.held then releaseHeld() return end
    end
    local activeTool, _, activeValues = gunProfile()
    if activeTool ~= reloadState.tool or (activeValues and readValue(activeValues, "Clip") ~= 0) then
        reloadState.tool, reloadState.nextAttempt = activeTool, 0
    end
    if config.Triggerbot and runtime.challengeReloadReady(activeTool,activeValues,now) then
        if clickState.held and not releaseHeld() then return end
        requestEmptyReload(activeTool,activeValues,now);return
    end
    if config.Triggerbot and runtime.heatBlocked(activeTool, activeValues, now) then
        if clickState.held and now>=clickState.retryReleaseAt then releaseHeld() end
        return
    end
    if config.Triggerbot and not pointState.picking and (inputSupported or runtime.gunCallbacks())
        and activeTool and readValue(activeValues, "Clip") == 0 then
        if clickState.held then
            if now < clickState.retryReleaseAt or not releaseHeld() then return end
        end
        requestEmptyReload(activeTool, activeValues, now)
        return
    end
    if clickState.held then
        local tool, mode, current = gunProfile()
        local point = getAimPoint()
        local ammo = current and readValue(current, "Clip")
        if ammo ~= clickState.observedAmmo then
            clickState.observedAmmo, clickState.progressAt = ammo, now
        end
        local stalled = type(ammo) == "number" and now - (clickState.progressAt or now) >= 2
        local canKeepHolding = clickState.autoHeld and config.AutoFireMode and not stalled
            and config.Triggerbot and tool == clickState.tool and mode == clickState.mode
            and tool ~= nil and gunReady(tool, current)
            and cachedTarget and cachedTarget.Parent and now - cachedAt <= 0.15
            and not pointState.picking and point and not pointBlocked(point)
            and (runtime.directHeld or (point - clickState.point).Magnitude < 1)
        if not canKeepHolding and (not config.Triggerbot or now >= clickState.releaseAt) and now >= clickState.retryReleaseAt then
            releaseHeld()
        end
        return
    end
    if not config.Triggerbot or pointState.picking or now < clickState.retryAt then return end
    if not inputSupported and not runtime.gunCallbacks() then return end
    local tool, mode, current = gunProfile()
    if not tool then return end
    if not gunReady(tool, current) then return end
    if now < clickState.nextClick then return end
    if not cachedTarget or not cachedTarget.Parent or now - cachedAt > 0.15 then return end
    local point = getAimPoint()
    if not point or pointBlocked(point) then return end
    if not runtime.gunCallbacks() and pointState.focused and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then return end
    local interval = config.TriggerIntervalMs / 1000
    clickState.nextClick = now + interval -- Never send catch-up bursts.
    local inputStage = "move"
    local sent, err = pcall(function()
        if not runtime.gunCallbacks() and config.CursorMode == "Fixed position" and UIS.MouseBehavior == Enum.MouseBehavior.Default then
            if virtualInput then virtualInput:SendMousePosition(point)
            else legacyInput:SendMouseMoveEvent(point.X, point.Y, game) end
        end
        inputStage = "press"
        sendButton(point, true)
    end)
    if sent then
        runtime.lastInputError = nil
        -- A rejected press never creates a held state or a bogus release.
        clickState.point = point
        clickState.held = true
        clickState.tool, clickState.mode = tool, mode
        clickState.observedAmmo, clickState.progressAt = readValue(current, "Clip"), now
        clickState.autoHeld = config.AutoFireMode and (mode == "FullAuto" or mode == "Continuous")
        clickState.releaseAt = now + math.min(0.03, interval / 2)
        clickState.retryReleaseAt = 0
    else
        if inputStage == "press" and duplicateButtonState(err) then
            -- Recover a rejected duplicate press by releasing first.
            clickState.point = point
            clickState.autoHeld = false
            clickState.held = true
            clickState.releaseAt = now
        end
        retryInput(err)
    end
end)

runtime.refill={next=0,message="Day: top up ammo. Night: refill only at 0/0."}
function runtime.ammoCounts(tool)
    if not tool or not tool:FindFirstChild("GunScript") then return false end
    local current=tool:FindFirstChild("CurrentValues")
    local other=tool:FindFirstChild("OtherValues")
    local prefix=readValue(other,"ToggledAltValue")==true and "Alt" or ""
    local clip,reserve=readValue(current,prefix.."Clip"),readValue(current,prefix.."Ammo")
    local maxClip,maxAmmo=readValue(current,prefix.."MaxClip"),readValue(current,prefix.."MaxAmmo")
    if type(clip)~="number" or clip<0 or clip>=math.huge or clip~=clip
        or type(reserve)~="number" or reserve<0 or reserve>=math.huge or reserve~=reserve
        or type(maxClip)~="number" or maxClip<=0 or maxClip>=math.huge or maxClip~=maxClip
        or type(maxAmmo)~="number" or maxAmmo<=0 or maxAmmo>=math.huge or maxAmmo~=maxAmmo then return end
    return clip,reserve
end
function runtime.refillNeeded(tool)
    local clip,reserve=runtime.ammoCounts(tool)
    if type(clip)~="number" then return false end
    local minutes=game:GetService("Lighting"):GetMinutesAfterMidnight()
    return (minutes>=360 and minutes<1080) or (clip==0 and reserve==0)
end
function runtime.refillSourceAllowed(source,tool,root)
    if not source or not source.Parent or not source.PrimaryPart or not source.PrimaryPart.Parent then return end
    if (source.PrimaryPart.Position-root.Position).Magnitude>=8 then return end
    if readValue(source,"CreatorOnly")==true and readValue(source,"Creator")~=LocalPlayer then return end
    local time=readValue(source,"Time")
    if type(time)~="number" or time<0 or time>=math.huge or time~=time then return end
    local name=source.Name
    local perks=LocalPlayer:FindFirstChild("PlayerPerks")
    local minutes=game:GetService("Lighting"):GetMinutesAfterMidnight()
    if perks and perks:FindFirstChild("SupplyNone") and name~="HeavySentry" and (minutes<360 or minutes>=1080) then return end
    if name=="HeavySentry" then
        if readValue(source,"Refill")~=true or (readValue(tool:FindFirstChild("CurrentValues"),"Consume") or 0)<=0 then return end
        return "RemoteRefillSentry",time
    elseif name=="GasCan" then
        local kind=readValue(tool:FindFirstChild("OtherValues"),"Type")
        if readValue(source,"Refill")~=true or not (kind=="Flamethrower" or tool.Name=="Chainsaw" or tool.Name=="Freezethrower" or tool.Name=="AK-74") then return end
        return "RemoteRefillFuel",time
    elseif name=="AmmoBox" or name=="RoofAmmo" or name=="DeployableAmmo" or name=="SupplyCrate" then
        local ammo=readValue(source,"Ammo")
        if type(ammo)=="number" and ammo>0 and source:FindFirstChild("MaxAmmo") then return "RemoteRefillAmmo",time end
    end
end
function runtime.findRefillSource(tool,root)
    local sources={}
    local map=Workspace:FindFirstChild("Map")
    local upgrades=map and map:FindFirstChild("Upgrades")
    if upgrades then for _,name in ipairs({"AmmoBox","RoofAmmo"}) do
        local source=upgrades:FindFirstChild(name);if source then table.insert(sources,source) end
    end end
    local deployables=Workspace:FindFirstChild("Deployables")
    if deployables then for _,source in ipairs(deployables:GetDescendants()) do
        if source:IsA("Model") and (source.Name=="DeployableAmmo" or source.Name=="SupplyCrate" or source.Name=="GasCan" or source.Name=="HeavySentry") then table.insert(sources,source) end
    end end
    local best,distance,method,duration
    for _,source in ipairs(sources) do
        local candidate,seconds=runtime.refillSourceAllowed(source,tool,root)
        local range=candidate and (source.PrimaryPart.Position-root.Position).Magnitude
        if range and (not distance or range<distance) then best,distance,method,duration=source,range,candidate,seconds end
    end
    return best,method,duration
end
function runtime.cancelRefill()
    local job=runtime.refill.job
    if job and not job.cancelled then
        job.cancelled=true
        if job.tool and job.tool.Parent and job.tool.Enabled==false then job.tool.Enabled=job.enabled end
    end
end
function runtime.refillStep()
    local state=runtime.refill
    if not runtime.extra.AutoRefillAmmo then runtime.cancelRefill();return end
    if runtime.refillBusy or runtime.consumableBusy or os.clock()<state.next then return end
    state.next=os.clock()+.5
    local character=LocalPlayer.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    local root=character and character:FindFirstChild("HumanoidRootPart")
    local tool=equippedGun()
    if not humanoid or humanoid.Health<=0 or not root or not runtime.refillNeeded(tool) then return end
    if tool.Enabled==false or readValue(tool,"Reloading")==true or reloadState.key then return end
    local playerGui=LocalPlayer:FindFirstChild("PlayerGui")
    if playerGui and playerGui:FindFirstChild("MenuGui") then return end
    local source,method,seconds=runtime.findRefillSource(tool,root)
    if not source then state.message="Waiting for an available ammo source within 8 studs.";return end
    local modules=game:GetService("ReplicatedStorage"):FindFirstChild("ModuleScripts")
    local manager=modules and modules:FindFirstChild("CharacterManager")
    local ok,speed=pcall(function() return require(manager):GetMulti("InteractionSpeed",LocalPlayer,{IgnoreTool=true}) end)
    if not ok or type(speed)~="number" or speed<=0 or speed>=math.huge or speed~=speed then state.message="Refill waiting: interaction speed unavailable.";return end
    local minutes=game:GetService("Lighting"):GetMinutesAfterMidnight()
    local duration=seconds/speed/(minutes>=360 and minutes<1080 and 5 or 1)
    if not releaseHeld() then return end
    local job={tool=tool,enabled=tool.Enabled,cancelled=false}
    state.job=job;runtime.refillBusy=true
    local function valid()
        return runtime.active and not job.cancelled and runtime.extra.AutoRefillAmmo and LocalPlayer.Character==character
            and humanoid.Health>0 and tool.Parent==character and runtime.refillNeeded(tool)
            and readValue(tool,"Reloading")~=true and runtime.refillSourceAllowed(source,tool,root)==method
            and not (playerGui and playerGui:FindFirstChild("MenuGui"))
    end
    task.spawn(function()
        local completed=false
        local success,err=pcall(function()
            if not valid() then return end
            local storage=game:GetService("ReplicatedStorage")
            local events,functions=storage:FindFirstChild("RemoteEvents"),storage:FindFirstChild("RemoteFunctions")
            local start=events and events:FindFirstChild("RemoteStartRefill")
            local finish=functions and functions:FindFirstChild(method)
            assert(start and start:IsA("RemoteEvent") and finish and finish:IsA("RemoteFunction"),"Refill remotes unavailable")
            tool.Enabled=false;state.message="Refilling from "..source.Name.."..."
            start:FireServer(tool.Name,source)
            local deadline=os.clock()+duration
            repeat
                if not valid() then state.message="Refill cancelled: range, weapon, or character changed.";return end
                if os.clock()>=deadline then break end
                task.wait(math.min(.05,deadline-os.clock()))
            until false
            local clip,ammo,altClip,altAmmo,premium,kind=finish:InvokeServer(tool,source)
            if not runtime.active or job.cancelled or tool.Parent~=character or LocalPlayer.Character~=character then return end
            if type(clip)~="number" or type(ammo)~="number" then state.message="Refill returned no ammo values; retrying later.";return end
            local values=tool:FindFirstChild("CurrentValues")
            values.Clip.Value=clip;values.Ammo.Value=ammo
            for key,value in pairs({AltClip=altClip,AltAmmo=altAmmo}) do
                local field=values:FindFirstChild(key);if field and type(value)=="number" then field.Value=value end
            end
            if type(premium)=="number" and premium>0 and kind=="Premium" then
                local other=tool:FindFirstChild("OtherValues")
                local field=other:FindFirstChild("PremiumAmmo")
                if not field then field=Instance.new("IntValue");field.Name="PremiumAmmo";field.Parent=other end
                field.Value=field.Value+premium
            end
            local update=tool:FindFirstChild("UpdateAmmoGui");if update then update:Fire() end
            completed=true
            state.message="Refill returned "..tostring(clip).."/"..tostring(ammo).."."
        end)
        if not job.cancelled and tool.Parent and tool.Enabled==false then tool.Enabled=job.enabled end
        if not success and runtime.active then state.message="Refill: "..tostring(err) end
        if state.job==job then state.job=nil;runtime.refillBusy=false;state.next=os.clock()+(completed and .25 or 3) end
    end)
end

local function beginPick()
    stopTrigger()
    invalidateTarget()
    if pointState.picking then finishPick() end
    pointState.savedBehavior = UIS.MouseBehavior
    pointState.savedIcon = menuVisible() or UIS.MouseIconEnabled
    pointState.picking = true
    pointState.pickAfter = os.clock() + 0.35
    setMenuVisible(false)
    notifyTrigger("Click a clear game position. Escape cancels. Right Ctrl reopens the menu; Delete starts clicking.")
end
connect(UIS.InputBegan, function(input, processed)
    if not pointState.picking then return end
    if input.KeyCode == Enum.KeyCode.Escape then finishPick() return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 or processed or os.clock() < pointState.pickAfter then return end
    local point = UIS:GetMouseLocation()
    if not validPoint(point) or pointBlocked(point) then return end
    pointState.fixed, pointState.last = point, point
    config.CursorMode = "Fixed position"
    finishPick()
    invalidateTarget()
    if cursorDropdown then cursorDropdown:SetValue("Fixed position") end
    notifyTrigger(string.format("Position saved: X %.0f, Y %.0f. Delete starts/stops; Right Ctrl opens the menu.", point.X, point.Y))
end)
connect(LocalPlayer.CharacterRemoving, function()
    releaseHeld()
end)
connect(UIS.InputBegan, function(input, processed)
    if input.KeyCode ~= Enum.KeyCode.Delete then return end
    if config.Triggerbot then
        stopTrigger()
    elseif not processed and not UIS:GetFocusedTextBox() then
        if triggerToggle then triggerToggle:SetValue(true) else setTriggerEnabled(true) end
    end
end)
print("[Combat Assistant] Gun callbacks preferred; " .. backendName .. " fallback. Input status is shown under Weapons.")
Linoria.ToggleKeybind = {Type = "KeyPicker", Value = "RightControl"}
Window = Linoria:CreateWindow({
    Title = "Combat Assistant", Center = true, AutoShow = true,
    Size = UDim2.fromOffset(840, 740), TabPadding = 8, MenuFadeTime = 0,
})
local CombatTab = Window:AddTab("Combat")
runtime.extensionTabs = {
    Weapons=Window:AddTab("Weapons"), Automation=Window:AddTab("Automation"),
    Visuals=Window:AddTab("Visuals"), Items=Window:AddTab("Items")
}
runtime.weaponGroup=runtime.extensionTabs.Weapons:AddLeftGroupbox("Weapon controls & range")
local firing = CombatTab:AddLeftGroupbox("Firing & Filters")
local targeting = CombatTab:AddRightGroupbox("Targeting & FOV")
local settingsUI = {}
local function toggle(group, key, text, flag, callback)
    settingsUI[key] = addControl(group, "Toggle", flag, {
        Text = text, Default = config[key], Callback = callback or function(value)
            config[key] = value
            invalidateTarget()
        end,
    })
    return settingsUI[key]
end
local function slider(group, key, text, flag, minimum, maximum, suffix)
    settingsUI[key] = addControl(group, "Slider", flag, {
        Text = text, Default = config[key], Min = minimum, Max = maximum, Rounding = 0, Suffix = suffix,
        Callback = function(value)
            config[key] = value
            invalidateTarget()
            if key == "TriggerIntervalMs" then clickState.nextClick = os.clock() + value / 1000 end
        end,
    })
end
local function dropdown(group, key, text, flag, values)
    settingsUI[key] = addControl(group, "Dropdown", flag, {
        Text = text, Values = values, Default = config[key], Multi = false, AllowNull = false,
        Callback = function(value) config[key] = value invalidateTarget() end,
    })
    return settingsUI[key]
end
toggle(firing, "SilentAim", "Manual-fire silent aim", "SilentAimToggle")
runtime.label(firing,"Triggerbot includes silent aim while enabled. Manual-fire silent aim is independent.")
triggerToggle = toggle(firing, "Triggerbot", "Triggerbot", "TriggerbotToggle", setTriggerEnabled)
slider(firing, "TriggerIntervalMs", "Click interval", "TriggerIntervalSlider", 10, 2000, "ms")
toggle(firing, "AutoFireMode", "Hold automatic fire", "AutoFireModeToggle")
cursorDropdown = dropdown(targeting, "CursorMode", "Cursor / FOV position", "CursorModeDropdown",
    {"Follow mouse", "Fixed position", "Screen center"})
targeting:AddBlank(5)
targeting:AddButton({Text = "Choose cursor position", Func = beginPick})
toggle(runtime.weaponGroup, "HeadshotConversion", "Hit Override: head request", "HeadshotConversionToggle", function(value)
    config.HeadshotConversion = value
end)
toggle(runtime.weaponGroup, "NoSpread", "No spread (hitscan)", "NoSpreadToggle", function(value)
    config.NoSpread = value
end)
toggle(runtime.weaponGroup, "NoRecoil", "No recoil", "NoRecoilToggle", function(value)
    config.NoRecoil = value
    runtime.updateRecoil()
end)
toggle(targeting, "IgnoreInvisibleParts", "Ignore transparent barriers", "IgnoreInvisiblePartsToggle")
toggle(targeting, "BodyFallback", "Allow body / limb targets", "BodyFallbackToggle")
toggle(targeting, "WeaponClearance", "Check shot-path clearance", "WeaponClearanceToggle")
toggle(targeting, "VisibleCheck", "Visible Check", "VisibleCheckToggle")
dropdown(targeting, "TargetMode", "Targeting Mode", "TargetModeDropdown", {"Closest to Crosshair", "Closest to Player"})
toggle(targeting, "ShowFOV", "Show FOV Circle", "ShowFOVToggle")
slider(targeting, "FOVRadius", "Manual silent aim FOV", "FOVRangeSlider", 10, 1000, "px")
targeting:AddBlank(8)
runtime.targetLabel = runtime.label(targeting,"Target: waiting", true)
runtime.nextTargetLabel = 0
connect(RunService.Heartbeat, function()
    if os.clock() < runtime.nextTargetLabel then return end
    runtime.nextTargetLabel = os.clock() + 0.25
    local target = runtime.targetName and (runtime.targetName .. " [" .. runtime.targetTier .. "]") or "none eligible"
    if pointState.picking then target = "paused (cursor selection)" end
    local aim = not (config.SilentAim or config.Triggerbot) and "OFF - shots follow normal aim" or
        (not runtime.callerLookup and "unavailable (caller API)" or
        (runtime.lastRedirect and os.clock() - runtime.lastRedirect < 2 and "redirecting shots" or "ON - no recent redirected shot"))
    local input = runtime.lastInputError and "Input: rejected; close menus/console" or "Input: no recorded rejection"
    local super = (runtime.superSeen or 0) > 0 and not runtime.targetName and "\nSuper zombies present but filtered out" or ""
    local rejected=runtime.targetBlocked
    local detail=rejected and ("\nNearby "..rejected.name..": "..rejected.reason) or ""
    if runtime.damageEstimateUnavailable then detail=detail.."\nDamage estimate unavailable; using exposed aim points" end
    runtime.targetLabel:SetText("Target: " .. target .. "\nSilent Aim: " .. aim .. "\n" .. input .. "\nFacing: " .. tostring(runtime.facing and runtime.facing.status or "Unavailable") .. super .. detail)
end)
local function zombieFilter(key, text, flag)
    return addControl(firing, "Dropdown", flag, {
        Text = text, Values = knownZombies, Default = {}, Multi = true, AllowNull = true,
        Callback = function(selected)
            config[key] = {}
            for name, enabled in pairs(selected) do if enabled then config[key][name] = true end end
            invalidateTarget()
        end,
    })
end
toggle(runtime.weaponGroup, "RangeCheck", "Check gun range", "RangeCheckToggle")
dropdown(runtime.weaponGroup, "RangeMode", "Range mode", "RangeModeDropdown", {"Automatic", "Manual"})
slider(runtime.weaponGroup, "ManualRange", "Manual range", "ManualRangeSlider", 10, 5000, "studs")
firing:AddBlank(5)
rangeLabel = runtime.label(runtime.weaponGroup,"Gun: waiting for equipped gun", true)
local nextRangeLabel, lastRangeText = 0, nil
connect(RunService.Heartbeat, function()
    if os.clock() < nextRangeLabel then return end
    nextRangeLabel = os.clock() + 0.25
    local tool, _, current = gunProfile()
    local value = tool and detectedRange(tool, current)
    local base = tool and readValue(current, "Range")
    local function displayRange(number)
        return validRange(number) and string.format("%.2f studs", number) or "unavailable"
    end
    local detected = value and (rangeCache.source .. ": " .. displayRange(value)) or "Detected range: unavailable"
    local limit = not config.RangeCheck and "off" or
        (config.RangeMode == "Manual" and (displayRange(config.ManualRange) .. " (manual)") or
        (value and (displayRange(value) .. " (auto)") or "unknown - waiting"))
    local text = "Gun: " .. (tool and tool.Name or "no supported gun") ..
        "\nCurrentValues.Range: " .. displayRange(base) ..
        "\n" .. detected .. "\nActive limit: " .. limit
    if text ~= lastRangeText then
        rangeLabel:SetText(text)
        lastRangeText = text
    end
end)
settingsUI.SuperPriorityList = zombieFilter("SuperPriorityList", "Super prioritize", "SuperPriorityDropdown")
local PriorityDropdown = zombieFilter("PriorityList", "Prioritize Zombies", "PriorityDropdown")
local IgnoreDropdown = zombieFilter("IgnoreList", "Ignore Zombies", "IgnoreDropdown")

function runtime.refreshZombieChoices()
    for _, dropdown in ipairs({settingsUI.SuperPriorityList, PriorityDropdown, IgnoreDropdown}) do
        dropdown:SetValues(knownZombies)
    end
end
local function updateDropdowns(zombieName)
    if not table.find(knownZombies, zombieName) then
        table.insert(knownZombies, zombieName)
        runtime.refreshZombieChoices()
        pcall(saveZombies)
    end
end
for _, zombie in ipairs(zombiesFolder:GetChildren()) do
    if zombie:IsA("Model") then updateDropdowns(zombie.Name) end
end
connect(zombiesFolder.ChildAdded, function(zombie)
    if zombie:IsA("Model") then updateDropdowns(zombie.Name) end
end)
firing:AddBlank(5)
firing:AddButton({Text = "Refresh zombie list", Func = function()
    for _, zombie in ipairs(zombiesFolder:GetChildren()) do
        if zombie:IsA("Model") and not table.find(knownZombies, zombie.Name) then
            table.insert(knownZombies, zombie.Name)
        end
    end
    table.sort(knownZombies)
    runtime.refreshZombieChoices()
    pcall(saveZombies)
end})
local SettingsTab = Window:AddTab("Settings")
local menuGroup = SettingsTab:AddLeftGroupbox("Menu")
local configGroup = SettingsTab:AddRightGroupbox("Configurations")

runtime.consumables = {nextRefresh=0,message="Enable an item and press its hotkey."}
function runtime.consumableContext(name)
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    assert(humanoid and humanoid.Health > 0, "Your character is not alive.")
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local tool = character:FindFirstChild(name) or (backpack and backpack:FindFirstChild(name))
    assert(tool and tool:IsA("Tool") and tool:FindFirstChild("ConsumableScript"), "Selected consumable is not in your inventory.")
    local charges = LocalPlayer:FindFirstChild("Charges")
    local entry = charges and charges:FindFirstChild(name)
    local amount = readValue(entry, "Amount")
    assert(type(amount)=="number" and amount>0, "No consumable charges remaining.")
    local target = LocalPlayer
    local targetCharacter = target and target.Character
    local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
    assert(targetHumanoid and targetHumanoid.Health>0, "Target player is not alive.")
    local current = tool:FindFirstChild("CurrentValues")
    local duration = readValue(current, "AnimationDuration")
    if type(duration)~="number" or duration<=0 or duration>=math.huge then duration=1 end
    if rangeManager then
        local ok, speed = pcall(function()
            return rangeManager:GetMulti("UseSpeed",LocalPlayer,{Tool=tool})
        end)
        if ok and type(speed)=="number" and speed>0 and speed<math.huge then duration=duration/speed end
    end
    local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
    local actions = scripts and scripts:FindFirstChild("PlayerActions")
    assert(readValue(actions,"Meleeing")~=true and readValue(tool,"Consuming")~=true, "Already using an item or meleeing.")
    return tool, target, duration, amount, character, humanoid
end
function runtime.consumableResult(entry,status,reason)
    runtime.consumables.message=entry.name..": "..(status=="consumed" and "charge used." or (reason or "Use unconfirmed."))
end
function runtime.useDrinkBatch(indices)
    local c=runtime.consumables
    if runtime.refillBusy or os.clock()<(c.drinkAt or 0) then return end
    local entries={}
    for _,index in ipairs(indices) do
        if index>=1 and index<=4 and runtime.extra["UseItem"..index] then
            table.insert(entries,{name=runtime.consumableDefinitions[index][1],index=index})
        end
    end
    if #entries==0 then return end
    local started=runtime.instantConsumableBatch(entries,function(entry)
        return runtime.extra["UseItem"..entry.index]==true
    end,runtime.consumableResult,"manual")
    if started then c.drinkAt=os.clock()+1;c.message="Immediate backpack requests for selected drinks." end
    return started
end
function runtime.useConsumable(name,automatic)
    if runtime.refillBusy then return end
    local character=LocalPlayer.Character
    local function eligible()
        if not automatic then return true end
        local health=character and character:FindFirstChildOfClass("Humanoid")
        return runtime.extra[automatic.key]==true and LocalPlayer.Character==character
            and health and health.Health>0 and health.MaxHealth>0 and health.MaxHealth<math.huge
            and health.Health<=health.MaxHealth*runtime.extra[automatic.threshold]/100
    end
    if not eligible() then return end
    return runtime.instantConsumableBatch({{name=name}},eligible,runtime.consumableResult,automatic and "healing" or "manual")
end

runtime.label(menuGroup,"Show / hide: Right Ctrl", true)
runtime.label(menuGroup,"Triggerbot: Delete", true)
local function unloadAssistant()
    if not runtime.active then return true end
    if runtime.cancelInstantConsumables and not runtime.cancelInstantConsumables() then
        return false
    end
    runtime.cancelRefill()
    if runtime.cancelAction then runtime.cancelAction() end
    config.HeadshotConversion = false
    config.NoSpread, config.NoRecoil = false, false
    runtime.restoreRecoil()
    config.Triggerbot, config.SilentAim, config.ShowFOV = false, false, false
    invalidateTarget()
    -- Do not abandon a held synthetic key if Roblox rejects its release.
    if not releaseHeld() then
        notifyTrigger("Unload waiting: close Roblox menus/console, then try Unload again.")
        return false
    end
    if reloadState.key then
        local ok = pcall(sendReloadKey, reloadState.key, false)
        if not ok then
            notifyTrigger("Unload waiting for reload-key release. Try Unload again.")
            return false
        end
        reloadState.key = nil
    end
    if pointState.picking then finishPick() end
    runtime.active = false
    if runtime.extensions then runtime.extensions.cleanup() end
    if runtime.slot.current == runtime then
        runtime.slot.handler, runtime.slot.current = nil, nil
    end
    for _, connection in ipairs(runtime.connections) do pcall(function() connection:Disconnect() end) end
    table.clear(runtime.connections)
    pcall(function() RunService:UnbindFromRenderStep("CombatAssistantPickerCursor") end)
    for _, drawing in ipairs({fovCircle, pickerArrow, pickerOutline}) do
        pcall(function() drawing.Visible = false; drawing:Remove() end)
    end
    pcall(function() Linoria:Unload() end)
    UIS.MouseIconEnabled = true
    -- Dispatcher has no reference to this runtime after unload.
    return true
end
runtime.unload = unloadAssistant
menuGroup:AddButton({Text = "Unload Combat Assistant", Func = unloadAssistant})
local profileFolder = "CombatAssistantConfigs"
local autoloadPath = profileFolder .. "/autoload.json"
local typedProfile, selectedProfile = "Default", nil
local profileDropdown, autoloadLabel
local hideOnAutoload = true
local booleanKeys = {"SilentAim", "Triggerbot", "VisibleCheck", "WeaponClearance", "AutoFireMode", "ShowFOV"}
local cursorModes = {"Follow mouse", "Fixed position", "Screen center"}
local targetModes = {"Closest to Crosshair", "Closest to Player"}

local function profileNotice(message)
    Linoria:Notify("Configuration: " .. message, 6)
end
local function profileAction(action)
    local ok, result = pcall(action)
    if not ok then
        warn("[Combat Assistant Config] " .. tostring(result))
        profileNotice("Failed: " .. tostring(result))
    end
    return ok, result
end
local function cleanName(name)
    assert(type(name) == "string", "Enter a profile name.")
    name = name:match("^%s*(.-)%s*$")
    assert(#name > 0 and #name <= 48 and name:match("^[%w _%-]+$"), "Use 1-48 letters, numbers, spaces, underscores or hyphens.")
    local lower = string.lower(name)
    assert(lower ~= "autoload" and lower ~= "con" and lower ~= "prn" and lower ~= "aux" and lower ~= "nul"
        and not lower:match("^com%d$") and not lower:match("^lpt%d$"), "That profile name is reserved.")
    return name
end
local function diskReady()
    assert(type(readfile) == "function" and type(writefile) == "function" and type(isfile) == "function",
        "This executor needs readfile, writefile and isfile for profiles.")
    if type(isfolder) == "function" and isfolder(profileFolder) then return end
    assert(type(makefolder) == "function", "This executor cannot create the profile folder.")
    local ok, err = pcall(makefolder, profileFolder)
    assert(ok or (type(isfolder) == "function" and isfolder(profileFolder)), tostring(err))
end
local function profilePath(name) return profileFolder .. "/" .. cleanName(name) .. ".json" end
local function writeJSON(path, data)
    diskReady()
    local encoded = HttpService:JSONEncode(data)
    writefile(path, encoded)
    assert(isfile(path) and readfile(path) == encoded, "File verification failed; configuration was not confirmed saved.")
end
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function namesFromSet(set)
    local names = {}
    for name, enabled in pairs(set) do if enabled then table.insert(names, name) end end
    table.sort(names)
    return names
end
local function serializePoint(point)
    if not point then return nil end
    local camera = Workspace.CurrentCamera
    local size = camera and camera.ViewportSize
    return {X = point.X, Y = point.Y, Width = size and size.X, Height = size and size.Y}
end
local function snapshotProfile()
    local settings = {}
    for _, key in ipairs(booleanKeys) do settings[key] = config[key] end
    settings.RangeCheck, settings.RangeMode, settings.ManualRange = config.RangeCheck, config.RangeMode, config.ManualRange
    settings.FOVRadius = config.FOVRadius
    settings.TriggerIntervalMs = config.TriggerIntervalMs
    settings.CursorMode = config.CursorMode
    settings.TargetMode = config.TargetMode
    settings.FOVColor = {R = config.FOVColor.R, G = config.FOVColor.G, B = config.FOVColor.B}
    settings.IgnoreInvisibleParts = config.IgnoreInvisibleParts
    settings.Extras = {}
    for key,value in pairs(runtime.extra) do settings.Extras[key]=value end
    settings.HeadshotConversion = config.HeadshotConversion
    settings.NoSpread, settings.NoRecoil = config.NoSpread, config.NoRecoil
    settings.BodyFallback = config.BodyFallback
    settings.SuperPriorityList = namesFromSet(config.SuperPriorityList)
    settings.PriorityList = namesFromSet(config.PriorityList)
    settings.IgnoreList = namesFromSet(config.IgnoreList)
    settings.FixedPoint = serializePoint(pointState.fixed)
    settings.LastPoint = serializePoint(pointState.last)
    local learned = {}
    for _, name in ipairs(knownZombies) do table.insert(learned, name) end
    return {Version = 1, Settings = settings, LearnedZombies = learned}
end
local function validateNames(list)
    assert(type(list) == "table" and #list <= 2000, "Invalid zombie list.")
    local result, seen = {}, {}
    for key, name in pairs(list) do
        assert(type(key) == "number" and key % 1 == 0 and key >= 1 and key <= #list, "Invalid list index.")
        assert(type(name) == "string" and #name > 0 and #name <= 200, "Invalid zombie name.")
        if not seen[name] then seen[name] = true table.insert(result, name) end
    end
    return result
end
local function validatePoint(point)
    if point == nil then return nil end
    assert(type(point) == "table" and finite(point.X) and finite(point.Y) and point.X >= 0 and point.Y >= 0,
        "Invalid saved cursor position.")
    local x, y = point.X, point.Y
    if point.Width ~= nil or point.Height ~= nil then
        assert(finite(point.Width) and finite(point.Height) and point.Width > 0 and point.Height > 0
            and x < point.Width and y < point.Height, "Invalid saved viewport dimensions.")
        local camera = Workspace.CurrentCamera
        if camera and camera.ViewportSize.X > 0 and camera.ViewportSize.Y > 0 then
            x, y = x / point.Width * camera.ViewportSize.X, y / point.Height * camera.ViewportSize.Y
        end
    end
    return Vector2.new(x, y)
end
local function validateProfile(data, allowIncomplete)
    assert(type(data) == "table" and data.Version == 1 and type(data.Settings) == "table", "Unsupported or invalid profile format.")
    local source, clean = data.Settings, {}
    clean.Extras = runtime.validateExtras(source.Extras)
    clean.IgnoreInvisibleParts = source.IgnoreInvisibleParts
    if clean.IgnoreInvisibleParts == nil then clean.IgnoreInvisibleParts = false end
    assert(type(clean.IgnoreInvisibleParts) == "boolean", "Invalid invisible-parts option.")
    for _, key in ipairs({"HeadshotConversion", "NoSpread", "NoRecoil"}) do
        clean[key] = source[key]
        if clean[key] == nil then clean[key] = false end
        assert(type(clean[key]) == "boolean", "Invalid " .. key)
    end
    clean.BodyFallback = source.BodyFallback
    if clean.BodyFallback == nil then clean.BodyFallback = true end
    assert(type(clean.BodyFallback) == "boolean", "Invalid body fallback.")
    clean.RangeCheck = source.RangeCheck
    if clean.RangeCheck == nil then clean.RangeCheck = true end
    clean.RangeMode = source.RangeMode
    if clean.RangeMode == nil then clean.RangeMode = "Automatic" end
    clean.ManualRange = source.ManualRange
    if clean.ManualRange == nil then clean.ManualRange = 500 end
    assert(type(clean.RangeCheck) == "boolean", "Invalid range check.")
    assert(clean.RangeMode == "Automatic" or clean.RangeMode == "Manual", "Invalid range mode.")
    assert(finite(clean.ManualRange) and clean.ManualRange >= 10 and clean.ManualRange <= 5000, "Invalid manual range.")
    for _, key in ipairs(booleanKeys) do
        assert(type(source[key]) == "boolean", "Invalid setting: " .. key)
        clean[key] = source[key]
    end
    assert(finite(source.FOVRadius) and source.FOVRadius >= 10 and source.FOVRadius <= 1000, "Invalid FOV radius.")
    assert(finite(source.TriggerIntervalMs) and source.TriggerIntervalMs >= 10 and source.TriggerIntervalMs <= 2000, "Invalid click interval.")
    assert(table.find(cursorModes, source.CursorMode), "Invalid cursor mode.")
    assert(table.find(targetModes, source.TargetMode), "Invalid targeting mode.")
    clean.FOVRadius, clean.TriggerIntervalMs = source.FOVRadius, source.TriggerIntervalMs
    clean.CursorMode, clean.TargetMode = source.CursorMode, source.TargetMode
    local color = source.FOVColor
    assert(type(color) == "table", "Missing FOV color.")
    for _, key in ipairs({"R", "G", "B"}) do
        assert(finite(color[key]) and color[key] >= 0 and color[key] <= 1, "Invalid FOV color.")
    end
    clean.FOVColor = Color3.new(color.R, color.G, color.B)
    clean.SuperPriorityList = validateNames(source.SuperPriorityList == nil and {} or source.SuperPriorityList)
    clean.PriorityList, clean.IgnoreList = validateNames(source.PriorityList), validateNames(source.IgnoreList)
    clean.FixedPoint, clean.LastPoint = validatePoint(source.FixedPoint), validatePoint(source.LastPoint)
    clean.LearnedZombies = validateNames(data.LearnedZombies)
    assert(allowIncomplete or clean.CursorMode ~= "Fixed position" or clean.FixedPoint, "Fixed-position mode needs a saved point.")
    return clean
end
local function applyProfile(clean)
    assert(not (runtime.consumableBusy or runtime.refillBusy),"Wait for consumable use to finish before loading a profile.")
    -- Validate first; release input and restore Triggerbot last.
    assert(releaseHeld(), "Input release is pending. Retry loading after the blocked UI clears.")
    config.Triggerbot, config.SilentAim = false, false
    if pointState.picking then finishPick() end
    pointState.fixed, pointState.last = clean.FixedPoint, clean.LastPoint
    for _, list in ipairs({clean.LearnedZombies, clean.SuperPriorityList, clean.PriorityList, clean.IgnoreList}) do
        for _, name in ipairs(list) do
            if not table.find(knownZombies, name) then table.insert(knownZombies, name) end
        end
    end
    runtime.refreshZombieChoices()
    for _, key in ipairs({"HeadshotConversion", "NoSpread", "NoRecoil", "IgnoreInvisibleParts", "BodyFallback", "FOVRadius", "TriggerIntervalMs", "VisibleCheck", "WeaponClearance", "AutoFireMode", "ShowFOV"}) do
        settingsUI[key]:SetValue(clean[key])
    end
    for _, key in ipairs({"RangeCheck", "RangeMode", "ManualRange"}) do settingsUI[key]:SetValue(clean[key]) end
    rangeCache.nextUpdate = 0
    cursorDropdown:SetValue(clean.CursorMode)
    settingsUI.TargetMode:SetValue(clean.TargetMode)
    settingsUI.SuperPriorityList:SetValue(toSet(clean.SuperPriorityList))
    PriorityDropdown:SetValue(toSet(clean.PriorityList))
    IgnoreDropdown:SetValue(toSet(clean.IgnoreList))
    runtime.consumables.playerKey = nil
    runtime.loadingProfile=true
    for key,value in pairs(clean.Extras) do
        if runtime.extraUI[key] then runtime.extraUI[key]:SetValue((key:match("^ItemKey") or key:match("^ThrowKey") or key=="OPCanKey") and {value,"Toggle"} or value) end
        runtime.extra[key]=value
    end
    runtime.loadingProfile=false
    if runtime.extensions then runtime.extensions.refresh() end
    config.FOVColor = clean.FOVColor
    invalidateTarget()
    settingsUI.SilentAim:SetValue(clean.SilentAim)
    triggerToggle:SetValue(clean.Triggerbot)
end
local function readProfile(name)
    diskReady()
    local path = profilePath(name)
    assert(isfile(path), "Profile not found: " .. name)
    return validateProfile(HttpService:JSONDecode(readfile(path)))
end
local function loadProfile(name)
    local clean = readProfile(name)
    local previous = validateProfile(snapshotProfile(), true)
    local ok, err = pcall(applyProfile, clean)
    if not ok then
        local restored = pcall(applyProfile, previous)
        error(tostring(err) .. (restored and " Previous settings restored." or " Settings could not be fully restored; input remains paused."))
    end
    return true
end
local function refreshProfiles(preferred)
    diskReady()
    assert(type(listfiles) == "function", "This executor needs listfiles to list saved profiles.")
    local names, seen = {}, {}
    for _, path in ipairs(listfiles(profileFolder)) do
        local name = path:match("([^/\\]+)%.json$")
        if name and string.lower(name) ~= "autoload" then
            local ok = pcall(cleanName, name)
            if ok and not seen[name] then seen[name] = true table.insert(names, name) end
        end
    end
    table.sort(names)
    selectedProfile = seen[preferred or ""] and preferred or (seen[selectedProfile or ""] and selectedProfile or names[1])
    local key=table.concat(names,"\n").."\nselected="..tostring(selectedProfile)
    if runtime.profileListKey~=key then
        runtime.profileListKey=key
        profileDropdown:SetValues(#names > 0 and names or {"(no saved profiles)"})
        profileDropdown:SetValue(selectedProfile)
    end
end
connect(RunService.Heartbeat,function()
    if os.clock()<(runtime.profileRefreshAt or 0) then return end
    runtime.profileRefreshAt=os.clock()+5
    if not runtime.loadingProfile and type(listfiles)=="function" and type(isfolder)=="function" and isfolder(profileFolder) then pcall(refreshProfiles) end
end)
local function selectedName()
    assert(selectedProfile, "Select a saved profile first.")
    return cleanName(selectedProfile)
end
local function saveProfile(name, overwrite)
    name = cleanName(name)
    diskReady()
    local path = profilePath(name)
    assert(overwrite or not isfile(path), "Profile already exists. Use Overwrite selected profile.")
    local data = snapshotProfile()
    validateProfile(data)
    writeJSON(path, data)
    selectedProfile = name
    profileNotice("Saved: " .. name)
    profileAction(function() refreshProfiles(name) end)
end
addControl(configGroup, "Input", "ProfileName", {Text = "Config name", Default = "Default", Finished = false,
    Callback = function(text) typedProfile = text end})
profileDropdown = addControl(configGroup, "Dropdown", "ProfileSelection", {
    Text = "Config list", Values = {"(no saved profiles)"}, Multi = false, AllowNull = true,
    Callback = function(name)
        if name and name ~= "(no saved profiles)" then selectedProfile = name end
    end,
})
local function configButton(text, action, parentButton)
    if not parentButton then configGroup:AddBlank(5) end
    return (parentButton or configGroup):AddButton({Text = text, Func = function() profileAction(action) end})
end
local createButton = configButton("Create config", function() saveProfile(typedProfile, false) end)
configButton("Load config", function()
    local name = selectedName() loadProfile(name) profileNotice("Loaded: " .. name)
end, createButton)
configButton("Overwrite config", function() saveProfile(selectedName(), true) end)
local hideAutoloadToggle = addControl(menuGroup, "Toggle", "HideMenuAutoload", {
    Text = "Hide UI after autoload", Default = true, Callback = function(value) hideOnAutoload = value end,
})
local function setAutoloadLabel(name)
    autoloadLabel:SetText("Current autoload config: " .. (name or "none"))
end
configButton("Set as autoload", function()
    local name = selectedName()
    readProfile(name)
    writeJSON(autoloadPath, {Version = 1, Enabled = true, Name = name, HideMenu = hideOnAutoload})
    setAutoloadLabel(name)
    profileNotice("Autoload set: " .. name .. ". Runs the next time you execute this script.")
end)
configButton("Disable autoload", function()
    writeJSON(autoloadPath, {Version = 1, Enabled = false})
    setAutoloadLabel()
    profileNotice("Autoload disabled.")
end)
configGroup:AddBlank(5)
autoloadLabel = runtime.label(configGroup,"Current autoload config: none", true)
runtime.initializeExtensions = function()
local e, ui = runtime.extra, runtime.extraUI
local state = {next=0, catalogAt=0, highlights={}, scavengers={}, jobs={}, cooldowns={}, message="Ready"}
runtime.extensions = state
local function child(parent,name) return parent and parent:FindFirstChild(name) end
local function storage() return game:GetService("ReplicatedStorage") end
local function alive()
    local character=LocalPlayer.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    return character, humanoid and humanoid.Health>0 and humanoid or nil
end
local function notice(message) state.message=tostring(message) end
local function job(key,seconds,fn)
    if not runtime.active or state.jobs[key] or os.clock()<(state.cooldowns[key] or 0) then return end
    state.jobs[key]=true;state.cooldowns[key]=os.clock()+seconds
    local epoch=state.epoch or 0
    task.spawn(function()
        if runtime.active and (state.epoch or 0)==epoch then
            local ok,err=pcall(fn)
            if not ok and runtime.active then notice(key..": "..tostring(err)) end
        end
        state.jobs[key]=nil
    end)
end
local function control(group,key,text,choices)
    local spec=runtime.extraSpecs[key]
    local selection
    local options={Text=text,Default=e[key],Callback=function(value)
        e[key]=value==nil and spec[1] or value
        if key=="Autofarm" and not e[key] and state.farm then state.farm.stop() end
        if key=="AutoNightDrinks" and not e[key] and not e.Autofarm and runtime.cancelInstantConsumables then runtime.cancelInstantConsumables("standalone") end
        if key=="AutoLeaveSpawn" and not e[key] and state.farm and not e.Autofarm then state.farm.cancelWalk() end
        if selection then selection:SetText(table.concat(namesFromSet(e[key]),", ")) end
    end}
    for _,entry in ipairs(runtime.opDefinitions) do if key=="OP"..entry[1] then options.Tooltip=entry[2]..". Check the release notes for requirements and verification limits.";break end end
    local kind
    if type(spec[1])=="boolean" then kind="Toggle"
    elseif type(spec[1])=="number" then kind="Slider";options.Min=spec[2];options.Max=spec[3];options.Rounding=(key=="ActionInterval" or key=="OPPredictionSeconds" or key:find("Multiplier",1,true)) and 1 or 0
    elseif type(spec[1])=="table" then kind="Dropdown";options.Values=choices or {};options.Multi=true
    elseif choices or type(spec[2])=="table" then kind="Dropdown";options.Values=choices or spec[2];options.AllowNull=true
    else kind="Input";options.Finished=true end
    ui[key]=addControl(group,kind,"Extra_"..key,options)
    if options.Multi then selection=runtime.label(group,table.concat(namesFromSet(e[key]),", ")) end
    return ui[key]
end
local function remote(folder,name,method,...)
    local object=child(child(storage(),folder),name)
    assert(object and object:IsA(method=="InvokeServer" and "RemoteFunction" or "RemoteEvent"),name.." is unavailable")
    return object[method](object,...)
end
local function ownedWeapons()
    local names,seen={},{}
    for _,folder in ipairs({child(LocalPlayer,"Backpack") or false,LocalPlayer.Character or false}) do
        if folder then for _,tool in ipairs(folder:GetChildren()) do
            if tool:IsA("Tool") and child(tool,"GunScript") and not seen[tool.Name] then
                seen[tool.Name]=true;table.insert(names,tool.Name)
            end
        end end
    end
    table.sort(names);return names
end
local function refreshChoices(key,values)
    if not ui[key] then return end
    local fingerprint=table.concat(values,"\n")
    if state[key.."Choices"]~=fingerprint then
        ui[key]:SetValues(values)
        -- Keep a saved preference even when that item is temporarily unavailable.
        local preference=e[key]
        ui[key]:SetValue(type(preference)=="table" and preference or (table.find(values,preference) and preference or nil))
        e[key]=preference
        state[key.."Choices"]=fingerprint
    end
end
local function ballotChoices()
    local maps={}
    for name in tostring(readValue(child(storage(),"Values"),"VotingMaps") or ""):gmatch("([^,]+)") do
        name=name:match("^%s*(.-)%s*$")
        table.insert(maps,name)
    end
    return maps
end
function state.refresh()
    refreshChoices("EquipWeapon",ownedWeapons())
    local maps,seen=ballotChoices(),{}
    for _,name in ipairs(maps) do seen[name]=true end
    local module=child(child(storage(),"ModuleScripts"),"AtlasManager")
    if module then
        local ok,atlas=pcall(require,module)
        if ok and type(atlas.MapAtlas)=="table" then
            for name in pairs(atlas.MapAtlas) do if type(name)=="string" and not seen[name] then table.insert(maps,name);seen[name]=true end end
        end
    end
    table.sort(maps);refreshChoices("VoteMap",maps)
    refreshChoices("HighlightType",knownZombies)
    local upgrades,names=child(storage(),"Upgrades"),{}
    if upgrades then for _,item in ipairs(upgrades:GetChildren()) do
        if child(item,"UStructure") then table.insert(names,item.Name) end
    end end
    table.sort(names);refreshChoices("Purchases",names)
    if state.refreshTools then state.refreshTools() end
end
function state.equip()
    assert(not (runtime.consumableBusy or runtime.refillBusy),"A consumable is in use")
    local character,humanoid=alive();assert(humanoid,"Character is not alive")
    local backpack=child(LocalPlayer,"Backpack")
    local tool=child(character,e.EquipWeapon) or child(backpack,e.EquipWeapon)
    assert(tool and tool:IsA("Tool") and child(tool,"GunScript"),"Selected gun is not owned")
    assert(not reloadState.key and releaseHeld(),"Input release is pending")
    humanoid:EquipTool(tool);notice("Equipped "..tool.Name)
end
local function restoreFireMode()
    if state.fireValue then
        pcall(function() if state.fireValue.Value==state.fireWritten then state.fireValue.Value=state.fireOriginal end end)
    end
    state.fireValue,state.fireOriginal,state.fireWritten=nil,nil,nil
end
-- Native ADS state with the gun's ADS presentation step kept in hip-fire state.
-- Critical Aim acceptance is not confirmed by this client-side status.
state.hipADS={}
function state.restoreHipADS()
    local a=state.hipADS
    state.hipADS={}
    if not a.tool then return end
    if a.environment and a.environment.ADSStep==a.wrapper then a.environment.ADSStep=a.originalStep end
    if a.set and a.callback then pcall(a.set,a.callback,a.flag,false) end
    if a.network then pcall(a.network.PassDataA,a.network,"Adsing",false) end
end
function state.hipADSStep()
    local tool=equippedGun()
    local _,humanoid=alive()
    if not humanoid or humanoid.Health<=0 then tool=nil end
    local a=state.hipADS
    if not e.HipFireADS or not runtime.active or not tool or tool~=a.tool then
        if a.tool then state.restoreHipADS();a=state.hipADS end
        if not e.HipFireADS or not runtime.active or not tool then a.failedTool=nil;return end
    end
    if a.failedTool and a.failedTool~=tool then a.failedTool=nil end
    if a.failedTool==tool then return end
    if os.clock()<(a.nextCheck or 0) then return end
    a.nextCheck=os.clock()+.25
    local function fail(reason)
        state.restoreHipADS();state.hipADS.failedTool=tool
        notice("Hip-fire ADS inactive: "..reason..". Toggle off/on or re-equip to retry.")
    end
    if readValue(tool,"Reloading")==true or readValue(tool,"Meleeing")==true then
        if a.tool then state.restoreHipADS() end
        return
    end
    if not a.tool then
        local cv=child(tool,"CurrentValues")
        local mode=readValue(cv,"ADSType")
        if (mode~="IronSights" and mode~="Scope") or readValue(cv,"HoldType")=="Dual" then fail("unsupported sights / dual wield");return end
        local perks=child(LocalPlayer,"PlayerPerks")
        if child(perks,"DisableADS1") then fail("Confident Handling disables ADS");return end
        local owner=child(tool,"GunScript")
        local bind=child(tool,"BindableADS")
        if not owner or not bind then return end -- The gun may still be initializing.
        local callback=state.nativeCallback(bind.Event,owner)
        local get=type(getupvalues)=="function" and getupvalues or (debug and debug.getupvalues)
        local set=type(setupvalue)=="function" and setupvalue or (debug and debug.setupvalue)
        if not callback or type(get)~="function" or type(set)~="function" then fail("native callback/upvalue APIs unavailable");return end
        local ok,up=pcall(get,callback)
        if not ok or type(up)~="table" then fail("cannot inspect native ADS callback");return end
        local flag,network
        local flags,functions,networks=0,0,0
        for index,v in pairs(up) do
            if type(index)=="number" then
                if type(v)=="boolean" then flag=index;flags=flags+1
                elseif type(v)=="function" then functions=functions+1
                elseif type(v)=="table" and type(v.PassDataA)=="function" then network=v;networks=networks+1 end
            end
        end
        if flags~=1 or functions~=1 or networks~=1 then fail("unrecognized ADS callback layout");return end
        local okEnv,environment=pcall(getfenv,callback)
        if not okEnv or environment.script~=owner or type(environment.ADSStep)~="function" then fail("native ADS presentation unavailable");return end
        if up[flag] then return end -- Wait for manual ADS to end before taking ownership.
        a.tool=tool;a.environment=environment;a.originalStep=environment.ADSStep;a.network=network
        a.callback=callback;a.flag=flag;a.get=get;a.set=set
        a.wrapper=function(...)
            if state.hipADS~=a then return a.originalStep(...) end
            if not e.HipFireADS or not runtime.active or tool.Parent~=LocalPlayer.Character then
                state.restoreHipADS()
                return a.originalStep(...)
            end
            local was
            local result=table.pack(pcall(function(...)
                local values=a.get(a.callback)
                was=values[a.flag]
                assert(type(was)=="boolean","ADS flag layout changed")
                a.set(a.callback,a.flag,false)
                return a.originalStep(...)
            end,...))
            local restored=true
            if type(was)=="boolean" then restored=pcall(a.set,a.callback,a.flag,was) end
            if not result[1] or not restored then
                fail("native ADS presentation failed")
                return
            end
            return table.unpack(result,2,result.n)
        end
        environment.ADSStep=a.wrapper
    end
    local ok,err=pcall(function()
        if tool.Parent~=LocalPlayer.Character then return end
        -- SetADS clamps camera distance even if immediately restored. Never call it here.
        local values=a.get(a.callback)
        assert(type(values[a.flag])=="boolean","ADS flag layout changed")
        if values[a.flag]~=true or not a.notified then
            a.set(a.callback,a.flag,true)
            assert(a.get(a.callback)[a.flag]==true,"ADS state update rejected")
            a.network:PassDataA("Adsing",true)
            a.notified=true
        end
    end)
    if not ok then fail(tostring(err));return end
    if not a.reported then
        a.reported=true
        notice("Hip-fire ADS active locally; server Critical Aim bonus unverified.")
    end
end

function state.fireMode()
    local tool=equippedGun()
    local value=tool and child(tool,"GunScript") and child(child(tool,"CurrentValues"),"FireType")
    if value~=state.fireValue or not e.FireModeOverride then restoreFireMode() end
    if not e.FireModeOverride or not value or not table.find({"Single","Burst","FullAuto"},value.Value) then return end
    if not state.fireValue then state.fireValue,state.fireOriginal=value,value.Value
    elseif value.Value~=state.fireWritten then state.fireOriginal=value.Value end
    state.fireWritten=e.FireMode;value.Value=e.FireMode
end
function state.vote()
    local values=child(storage(),"Values")
    assert((readValue(values,"VotingTime") or 0)>0,"Map voting is closed")
    local index=table.find(ballotChoices(),e.VoteMap);assert(index,"Preferred map is not on this ballot")
    if readValue(LocalPlayer,"VotedMap")==index then return end
    remote("RemoteEvents","RemoteMapVote","FireServer",index)
    notice("Map vote requested: "..e.VoteMap)
end
function state.skip()
    if e.Autofarm and state.farm and state.farm.wave30VoteHeld and state.farm.wave30VoteHeld() then return false end
    local values=child(storage(),"Values")
    assert(readValue(values,"Vote")==true,"Skip voting is closed by the game")
    assert(readValue(LocalPlayer,"Voted")==false,"Already voted or vote state unavailable")
    if state.skipBusy then return end
    local wave=readValue(values,"LocalWave")
    local character=LocalPlayer.Character;local map=child(Workspace,"Map");local epoch=state.epoch
    local voteCycle=state.skipCycle
    state.skipBusy=true;state.skipStartedAt=os.clock()
    state.skipLastAttempt=os.clock();state.skipLastWave=wave;state.skipLastError=nil;state.skipLastResult=nil
    local ok,result=pcall(remote,"RemoteFunctions","VoteSkip","InvokeServer")
    state.skipBusy=false;state.skipStartedAt=nil
    if not ok then state.skipLastError=tostring(result);error(result) end
    state.skipLastResult=result==true and "acknowledged" or "not acknowledged"
    if not runtime.active or state.epoch~=epoch or state.skipCycle~=voteCycle or LocalPlayer.Character~=character or child(Workspace,"Map")~=map
        or readValue(values,"LocalWave")~=wave or readValue(values,"Vote")~=true then return end
    if type(result)=="boolean" then
        local voted=child(LocalPlayer,"Voted");if voted then voted.Value=result end
    end
    notice(result==true and "Ready vote acknowledged; waiting for other players." or "Ready vote not acknowledged; will retry.")
end
local function shop()
    local scripts=child(LocalPlayer,"PlayerScripts")
    local module=child(child(child(child(scripts,"GuiManager"),"MainGui"),"ShopGui"),"ShopPurchase")
    assert(module,"ShopPurchase module is unavailable")
    local cached=runtime.gameModules and runtime.gameModules.ShopPurchase
    assert(cached and cached.module==module and cached.value,"ShopPurchase initialization unavailable; reload after game loads. "..tostring(cached and cached.error or "module changed"))
    return cached.value
end
function state.stop()
    state.restoreHipADS()
    if state.farm then state.farm.stop() end
    if runtime.cancelInstantConsumables then runtime.cancelInstantConsumables() end
    for _,definition in ipairs(runtime.opDefinitions) do local key="OP"..definition[1];e[key]=false;if ui[key] then ui[key]:SetValue(false) end end
    if runtime.op then runtime.op.cleanup() end
    if runtime.cancelAction then runtime.cancelAction() end
    runtime.cancelRefill()
    state.epoch=(state.epoch or 0)+1
    runtime.consumableEpoch=(runtime.consumableEpoch or 0)+1
    for key,value in pairs(e) do if type(value)=="boolean" then e[key]=false;if ui[key] then ui[key]:SetValue(false) end end end
    config.SilentAim,config.Triggerbot,config.NoSpread,config.NoRecoil,config.HeadshotConversion=false,false,false,false,false
    settingsUI.SilentAim:SetValue(false);triggerToggle:SetValue(false)
    settingsUI.NoSpread:SetValue(false);settingsUI.NoRecoil:SetValue(false);settingsUI.HeadshotConversion:SetValue(false)
    restoreFireMode();runtime.restoreRecoil()
    invalidateTarget();notice("Stopped automatic features; pending remote calls cannot be recalled")
end
local function destroy(object) pcall(function() object:Destroy() end) end
local function removeDrawing(object) pcall(function() object.Visible=false;object:Remove() end) end
local function clearVisuals()
    for model,object in pairs(state.highlights) do destroy(object);state.highlights[model]=nil end
    for model,object in pairs(state.scavengers) do destroy(object);state.scavengers[model]=nil end
    for _,key in ipairs({"marker","tracer"}) do if state[key] then removeDrawing(state[key]);state[key]=nil end end
end
local function color(model)
    if config.SuperPriorityList[model.Name] then return Color3.fromRGB(255,70,70) end
    if config.PriorityList[model.Name] then return Color3.fromRGB(255,190,60) end
    return Color3.fromRGB(80,180,255)
end
local function highlight(model,collection,tint)
    local body=child(model,"Torso") or child(model,"UpperTorso") or child(model,"Head")
    local cloak=model.Name=="Assassin" and body and body.Transparency>=.95
    local kind=cloak and "SelectionBox" or "Highlight"
    local object=collection[model]
    if object and not object:IsA(kind) then destroy(object);collection[model]=nil;object=nil end
    if cloak then
        if not object then object=Instance.new("SelectionBox");object.Name="CombatAssistantCloakBox";object.Parent=model;collection[model]=object end
        object.Adornee=body;object.Color3=tint;object.LineThickness=.04;object.SurfaceTransparency=1
        return
    end
    if not object then object=Instance.new("Highlight");object.Name="CombatAssistantHighlight";object.Adornee=model;object.Parent=model;collection[model]=object end
    object.FillColor=tint;object.OutlineColor=tint;object.FillTransparency=.75;object.OutlineTransparency=.1
    object.DepthMode=e.ThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
end
function state.visuals()
    if os.clock()<(state.visualAt or 0) then return end
    state.visualAt=os.clock()+.25
    local character=LocalPlayer.Character
    local root=child(character,"HumanoidRootPart")
    local keep={};local count=0
    if e.ZombieHighlights and root then
        local candidates={}
        for _,model in ipairs(zombiesFolder:GetChildren()) do
            local humanoid=model:FindFirstChildOfClass("Humanoid")
            local part=child(model,"Head") or child(model,"Torso") or child(model,"HumanoidRootPart")
            local matches=e.HighlightMode=="All" or (e.HighlightMode=="Priority only" and (config.PriorityList[model.Name] or config.SuperPriorityList[model.Name]))
                or (e.HighlightMode=="Super priority only" and config.SuperPriorityList[model.Name]) or (e.HighlightMode=="Selected type" and model.Name==e.HighlightType)
            if humanoid and humanoid.Health>0 and part and matches then
                local distance=(part.Position-root.Position).Magnitude
                if distance<=e.HighlightDistance then table.insert(candidates,{model=model,distance=distance}) end
            end
        end
        table.sort(candidates,function(a,b) return a.distance<b.distance end)
        for _,item in ipairs(candidates) do
            if count>=e.HighlightLimit then break end
            count=count+1;keep[item.model]=true
            highlight(item.model,state.highlights,color(item.model))
        end
    end
    for model,object in pairs(state.highlights) do if not keep[model] then destroy(object);state.highlights[model]=nil end end
    if not e.ScavengerHighlights then
        for model,object in pairs(state.scavengers) do destroy(object);state.scavengers[model]=nil end
    elseif os.clock()>=(state.scavengerAt or 0) then
        state.scavengerAt=os.clock()+5
        local found={};local count=0
        for _,object in ipairs(Workspace:GetDescendants()) do
            if object.Name=="ScavengerPackage" and (object:IsA("Model") or object:IsA("BasePart")) and count<6 then
                found[object]=true;count=count+1;highlight(object,state.scavengers,Color3.fromRGB(80,255,140))
            end
        end
        for model,object in pairs(state.scavengers) do if not found[model] then destroy(object);state.scavengers[model]=nil end end
    end
end
connect(RunService.RenderStepped,function()
    local position=cachedPosition
    local camera=Workspace.CurrentCamera
    local screen,onScreen
    if position and camera and os.clock()-cachedAt<=.15 then screen,onScreen=camera:WorldToViewportPoint(position) end
    if e.TargetMarker and not state.marker then state.marker=Drawing.new("Circle");state.marker.Radius=6;state.marker.Thickness=2;state.marker.Color=Color3.fromRGB(255,90,90);state.marker.Filled=false end
    if e.TargetTracer and not state.tracer then state.tracer=Drawing.new("Line");state.tracer.Thickness=1;state.tracer.Color=Color3.fromRGB(255,190,60) end
    if state.marker then state.marker.Visible=e.TargetMarker and onScreen==true;if onScreen then state.marker.Position=Vector2.new(screen.X,screen.Y) end end
    if state.tracer then state.tracer.Visible=e.TargetTracer and onScreen==true;if onScreen then state.tracer.From=getAimPoint() or camera.ViewportSize/2;state.tracer.To=Vector2.new(screen.X,screen.Y) end end
end)
function state.automation()
    if state.farm and (e.Autofarm or state.farm.active) then
        local ok,err=pcall(state.farm.step)
        if not ok then state.farm.lastError=tostring(err);state.farm.status("Autofarm error: "..tostring(err)) else state.farm.lastError=nil end
        local drinksOK,drinksError=pcall(state.farm.drinkTick)
        if not drinksOK then state.farm.drinkMessage="Drink scheduler: "..tostring(drinksError) end
        state.farm.showDrinks()
        if e.Autofarm and state.farm.supported() and state.farm.stage>=3 and not state.farm.inFlight and not runtime.action and not state.farm.moving then
            runtime.refillStep()
            if state.farm.unlimitedOwned() then state.spending(true) end
        end
        return
    end
    if e.AutoLeaveSpawn and state.farm then state.farm.leave(1) end
    runtime.refillStep()
    if state.actions then state.actions() end
    if state.spending then state.spending() end
    local character,humanoid=alive()
    if e.AutoEquip and humanoid and not (runtime.consumableBusy or runtime.refillBusy) and not character:FindFirstChildOfClass("Tool") and e.EquipWeapon~="" then job("Equip",2,state.equip) end
    if e.AutoVote or e.AutoSkip then
        local values=child(storage(),"Values")
        local time=readValue(values,"VotingTime") or 0
        if e.AutoVote and time>0 and table.find(ballotChoices(),e.VoteMap) and readValue(LocalPlayer,"VotedMap")~=table.find(ballotChoices(),e.VoteMap) then
            job("Map vote",2,state.vote)
        end
        local vote=readValue(values,"Vote")
        if e.AutoSkip and vote==true and readValue(LocalPlayer,"Voted")==false then
            job("Skip vote",3,state.skip)
        end
    end
end
local automation=runtime.extensionTabs.Automation
local equipment=automation:AddLeftGroupbox("Equipment")
control(equipment,"EquipWeapon","Owned gun",ownedWeapons())
control(equipment,"AutoEquip","Auto equip when unarmed")
equipment:AddButton({Text="Equip selected now",Func=function() job("Equip",1,state.equip) end})
local refill=automation:AddLeftGroupbox("Ammo refill")
control(refill,"AutoRefillAmmo","Auto refill ammo")
runtime.label(refill,"06:00–17:59: repeat refills. Night: only 0/0. Finite ammo, within 8 studs.",true)
local refillStatus=runtime.label(refill,runtime.refill.message,true)
connect(RunService.Heartbeat,function()
    if os.clock()<(runtime.refill.labelAt or 0) then return end
    runtime.refill.labelAt=os.clock()+.5
    if runtime.refill.displayed~=runtime.refill.message then
        runtime.refill.displayed=runtime.refill.message;refillStatus:SetText(runtime.refill.message)
    end
end)
local voting=automation:AddRightGroupbox("Voting")
control(voting,"VoteMap","Preferred map",{})
control(voting,"AutoVote","Auto vote preferred map")
voting:AddButton({Text="Vote selected map now",Func=function() job("Map vote",2,state.vote) end})
control(voting,"AutoSkip","Auto vote to skip")
voting:AddButton({Text="Vote skip now",Func=function() job("Skip vote",3,state.skip) end})
state.status=runtime.label(voting,"Ready",true)
state.readyStatus=runtime.label(voting,"Ready-up waits for the game voting phase and the required player votes.",true)
voting:AddButton({Text="Emergency stop (End)",Func=state.stop})
local weapons=runtime.extensionTabs.Weapons:AddLeftGroupbox("Fire mode & input")
control(weapons,"HipFireADS","ADS state without zoom (experimental)")
runtime.label(weapons,"Sets ADS state without changing the camera or zoom. Requires executor upvalue APIs and supported sights. Critical Aim upgrade must be owned; server bonus unverified. ADS restrictions may remain; scope charging is suppressed. Release manual ADS before enabling.",true)
control(weapons,"OverheatManagement","Manage triggerbot heat")
runtime.label(weapons,"Pauses before overheating; resumes after cooling. Applies to triggerbot only. Unsupported heat data pauses firing while enabled.",true)
control(weapons,"ExperimentalFire","Attack-button firing (test)")
runtime.label(weapons,"Uses the equipped gun's native callback; falls back if unavailable.",true)
control(weapons,"FireModeOverride","Override fire mode")
control(weapons,"FireMode","Mode")
runtime.label(weapons,"Re-equip after changing; charge/continuous modes excluded.",true)
runtime.modifierLabel=runtime.label(runtime.weaponGroup,"Checking weapon support...",true)
connect(RunService.Heartbeat,function()
    if os.clock()<(runtime.diagnosticAt or 0) then return end
    runtime.diagnosticAt=os.clock()+1
    local callbacks=runtime.gunCallbacks()
    local input=callbacks and callbacks.backend or "Virtual input fallback (GUI can block)"
    local rays=type(runtime.callerLookup)=="function" and type(setnamecallmethod)=="function"
    local recoil=not config.NoRecoil and "Off" or (runtime.recoilPatch and runtime.recoilPatch.module.AddRecoil==runtime.recoilPatch.wrapper and "Installed" or "Unavailable / replaced")
    runtime.modifierLabel:SetText("Input: "..input.."\nRay modifiers: "..(rays and "Available (hitscan)" or "Unsupported executor").."\nRecoil: "..recoil.."\nLast converted hit: "..(runtime.lastHeadshot and string.format("%.0fs ago",os.clock()-runtime.lastHeadshot) or "none"))
end)
local visuals=runtime.extensionTabs.Visuals
local targets=visuals:AddLeftGroupbox("Zombie visuals")
control(targets,"ZombieHighlights","Highlight zombies")
control(targets,"HighlightMode","Which zombies")
control(targets,"HighlightType","Selected zombie type",knownZombies)
control(targets,"HighlightDistance","Highlight range (studs)")
control(targets,"HighlightLimit","Highlight limit")
control(targets,"ThroughWalls","Show visuals through walls")
control(targets,"ScavengerHighlights","Highlight scavengers")
local scene=visuals:AddRightGroupbox("View")
control(scene,"TargetMarker","Mark selected aim point")
control(scene,"TargetTracer","Line to selected aim point")
runtime.label(scene,"Red: super priority; gold: priority; blue: normal.",true)
local priority=CombatTab:AddLeftGroupbox("Priority & protection")
control(priority,"ClosePriority","Close Range Prioritize")
control(priority,"CloseDistance","Close distance (studs)")
control(priority,"SkipCloaked","Skip cloaked Assassins")
runtime.label(priority,"Optional appearance filter: skips highly transparent Assassins. Transparency alone does not prove immunity. Off by default; saved profiles retain their setting.",true)
control(priority,"AssassinShotGuard","Assassin protection: single-hit hitscan")
runtime.label(priority,"Silent aim / triggerbot: each hitscan pellet stops after its first zombie hit; no fire pause. Overrides penetration while enabled. Does not protect against an Assassin in front, separate pellets, projectiles or splash.",true)
control(priority,"QuietReload","Reload early during quiet periods")
control(priority,"QuietReloadPercent","Reload at magazine % or below")
control(priority,"ReloadClearance","No enemies within (studs)")
runtime.label(priority,"Requires 1.5 seconds clear of all nearby zombies, including cloaked / ignored ones. Cannot cancel a reload or guarantee a damage-free challenge.",true)
runtime.label(priority,"Threat > Close > Super > Priority > Normal. Triggerbot prioritizes nearby Assassins and zombies below you within 20 studs. Close overrides Ignore. Cloaked / protected zombies stay excluded.",true)
runtime.label(priority,"Triggerbot always ignores FOV and uses built-in aim. Range, obstacles and priorities still apply. FOV only limits manual silent aim. Off-screen server acceptance remains unverified.",true)
local actions=CombatTab:AddRightGroupbox("Melee")
control(actions,"MeleeAura","Melee aura")
control(actions,"UseKnife","Use knife with guns")
runtime.label(actions,"Direct 360-degree requests within native range. Ignores gun target lists. Knife is a fallback, not a simultaneous second attack.",true)
local donation=automation:AddLeftGroupbox("Donations")
control(donation,"AutoDonate","Auto donate")
control(donation,"DonatePlayer","Recipient",{})
control(donation,"DonateAmount","Amount per donation")
control(donation,"DonateInterval","Donation interval (seconds)")
runtime.label(donation,"Respects debt and the money reserve under Shop & supplies. Repeats until disabled.",true)
local damage=runtime.extensionTabs.Items:AddRightGroupbox("Explosive / Damage")
local luring=runtime.extensionTabs.Items:AddRightGroupbox("Luring")
function runtime.refreshThrowables()
    runtime.discoverThrowables()
    for index,item in ipairs(runtime.throwDefinitions) do
        local suffix=runtime.throwSuffix(index)
        local enabled,key="ThrowEnabled"..suffix,"ThrowKey"..suffix
        if not ui[enabled] then
            runtime.extraSpecs[enabled]={false};runtime.extraSpecs[key]={item[2]}
            if e[enabled]==nil then e[enabled]=false end
            if e[key]==nil then e[key]=item[2] end
            local group=item[3]=="Luring" and luring or damage
            local toggle=control(group,enabled,item[1])
            toggle:AddKeyPicker("ThrowableKey"..suffix,{
                Default=e[key],Mode="Toggle",Modes={"Toggle"},SyncToggleState=false,NoUI=true,Text=item[1],
                ChangedCallback=function() if ui[key] then e[key]=ui[key].Value end end
            })
            ui[key]=toggle.Addons[#toggle.Addons]
        end
    end
end
runtime.refreshThrowables()
damage:AddDivider();control(damage,"ThrowMode","Damage throw mode")
luring:AddDivider();control(luring,"LureMode","Luring throw mode")
runtime.label(luring,"Boss–Enemy Spawn: 25 studs toward a detected enemy spawn, away from the shop. Missing or ambiguous map markers cancel placement.")
local throwInfo=runtime.extensionTabs.Items:AddRightGroupbox("Throwable status")
runtime.label(throwInfo,"Manual keys only. No distance cap. Fixed 50-stud exclusion around your character. Server restrictions still apply.")
state.throwStatus=runtime.label(throwInfo,"Enable an item and assign its key. Newly discovered items default off with no key.")
function runtime.throwKeyMatches(input)
    for index in ipairs(runtime.throwDefinitions) do
        local suffix=runtime.throwSuffix(index);local key=e["ThrowKey"..suffix]
        if e["ThrowEnabled"..suffix] and key~="None" and (input.KeyCode.Name==key
            or key=="MB1" and input.UserInputType==Enum.UserInputType.MouseButton1
            or key=="MB2" and input.UserInputType==Enum.UserInputType.MouseButton2) then return index end
    end
end
connect(UIS.InputBegan,function(input,processed)
    if processed or UIS:GetFocusedTextBox() then return end
    local index=runtime.throwKeyMatches(input)
    if index and state.throw then
        local ok,err=pcall(state.throw,index)
        if not ok then state.throwStatus:SetText("Placement paused: "..tostring(err)) end
    end
end)

local items=runtime.extensionTabs.Items
local itemOptions=items:AddLeftGroupbox("Item activation")
control(itemOptions,"IgnoreEquippingTool","ignore equipping tool")
runtime.label(itemOptions,"All drinks and healing items always use immediate backpack requests, regardless of this toggle. Throwables equip and restore your previous tool.")
local use=items:AddLeftGroupbox("Use consumables")
for index,item in ipairs(runtime.consumableDefinitions) do
    if index==5 then use:AddDivider() end
    local key="ItemKey"..index
    local toggle=control(use,"UseItem"..index,item[1])
    toggle:AddKeyPicker("ConsumableKey"..index,{
        Default=e[key],Mode="Toggle",Modes={"Toggle"},SyncToggleState=false,NoUI=true,
        Text=item[1],ChangedCallback=function() if ui[key] then e[key]=ui[key].Value end end
    })
    ui[key]=toggle.Addons[#toggle.Addons]
end
use:AddDivider()
runtime.consumables.label=runtime.label(use,runtime.consumables.message,true)
runtime.label(use,"Shared drink key sends every enabled drink immediately from your backpack. No equip or animation wait. Charges still apply.",true)
connect(UIS.InputBegan,function(input,processed)
    if processed or UIS:GetFocusedTextBox() or runtime.consumableBusy or runtime.refillBusy or runtime.throwKeyMatches(input) then return end
    local drinks={}
    for index,item in ipairs(runtime.consumableDefinitions) do
        local key=e["ItemKey"..index]
        local matches=input.KeyCode.Name==key or (key=="MB1" and input.UserInputType==Enum.UserInputType.MouseButton1)
            or (key=="MB2" and input.UserInputType==Enum.UserInputType.MouseButton2)
        if e["UseItem"..index] and matches then
            if index<=4 then table.insert(drinks,index)
            elseif #drinks==0 then runtime.useConsumable(item[1]);return end
        end
    end
    if #drinks>0 then runtime.useDrinkBatch(drinks) end
end)
connect(RunService.Heartbeat,function()
    local c=runtime.consumables
    if os.clock()<c.nextRefresh then return end
    c.nextRefresh=os.clock()+2
    if c.displayed~=c.message then c.displayed=c.message;c.label:SetText(c.message) end
end)

local healing=automation:AddLeftGroupbox("Automatic consumables")
for _,entry in ipairs(runtime.healDefinitions) do
    control(healing,entry.key,"Auto-Use "..entry.name)
    control(healing,entry.threshold,entry.name.." HP threshold (%)")
end
runtime.label(healing,"Heals yourself at or below each HP threshold. Backpack requests; no equip or animation wait. Charges still apply.",true)
function runtime.autoHealStep()
    local c=runtime.consumables
    if not runtime.active or runtime.consumableBusy or runtime.refillBusy or runtime.action or os.clock()<(c.healScanAt or 0) then return end
    c.healScanAt=os.clock()+.1
    for offset=1,#runtime.healDefinitions do
        local index=((c.healIndex or 0)+offset-1)%#runtime.healDefinitions+1
        local entry=runtime.healDefinitions[index]
        if e[entry.key] and runtime.useConsumable(entry.name,entry) then c.healIndex=index;return end
    end
end
connect(RunService.Heartbeat,function()
    local ok,err=pcall(runtime.autoHealStep)
    if not ok then runtime.consumables.message="Auto-heal paused: "..tostring(err) end
end)

local purchasing=automation:AddLeftGroupbox("Shop & supplies")
control(purchasing,"AutoShopMoney","Auto upgrade Shop Money only")
runtime.label(purchasing,"Only MoneyUpgrade; respects money reserve and upgrade delay. Autofarm manages this in its own sequence.",true)
control(purchasing,"AutoPurchase","Auto buy / upgrade")
control(purchasing,"Purchases","Shop items (buy + upgrade)",{})
control(purchasing,"AutoRepair","Auto repair")
control(purchasing,"Repairs","Repair",{"Shop","Barricade"})
control(purchasing,"AutoReplenish","Auto replenish")
control(purchasing,"Replenish","Replenish",{"AmmoBox","Ladders","Armour"})
control(purchasing,"ActionInterval","Upgrade / shop delay (s)")
control(purchasing,"MoneyReserve","Keep this much money")
runtime.label(purchasing,"AmmoBox / Ladders replenish shared ammo supplies. Normal game restrictions apply.",true)

state.toolUI={}
local function ownedTools()
    local names,tools={},{}
    for _,folder in ipairs({child(LocalPlayer,"Backpack") or false,LocalPlayer.Character or false}) do
        if folder then for _,tool in ipairs(folder:GetChildren()) do
            if tool:IsA("Tool") and not tools[tool.Name] then tools[tool.Name]=tool;table.insert(names,tool.Name) end
        end end
    end
    table.sort(names);return names,tools
end
local function toolUpgrades(name)
    return child(child(child(LocalPlayer,"Upgrades"),"GunUpgrades"),name)
end
function state.refreshTools()
    if state.refreshingTools then return end
    state.refreshingTools=true
    local ok,err=pcall(function()
    local names=ownedTools()
    for index=1,3 do
        local slot=state.toolUI[index]
        refreshChoices("Tool"..index,names)
        local folder=toolUpgrades(e["Tool"..index])
        local choices,details={},{}
        if folder then for _,upgrade in ipairs(folder:GetChildren()) do
            if child(upgrade,"EffectType") and child(upgrade,"Cost") then
                table.insert(choices,upgrade.Name)
                table.insert(details,string.format("%s: %s/%s",tostring(readValue(upgrade,"UName") or upgrade.Name),tostring(upgrade.Value),tostring(upgrade.MaxValue)))
            end
        end end
        table.sort(choices);table.sort(details)
        refreshChoices("Upgrades"..index,choices)
        if slot then
            slot.selected=e["Tool"..index]
            slot.status:SetText(#details>0 and table.concat(details,"\n") or "No upgrades found for this tool.")
        end
    end
    end)
    state.refreshingTools=false
    if not ok then error(err,0) end
end
local group=automation:AddRightGroupbox("Auto-upgrade tools")
control(group,"AutoC96","Auto Upgrade C96: Unlimited Ammo first")
runtime.label(group,"Reserves spending for Unlimited Ammo before buying any other C96 upgrade. Uses all available C96 upgrades automatically.",true)
for index=1,3 do
    if index>1 then group:AddDivider() end
    runtime.label(group,"Tool "..index)
    control(group,"Tool"..index,"Current tool",{})
    control(group,"Upgrades"..index,"Upgrades to apply",{})
    control(group,"AutoUpgrade"..index,"Automatically buy selected upgrades")
    state.toolUI[index]={status=runtime.label(group,"Select a current tool.",true)}
    ui["Tool"..index]:OnChanged(function()
        if state.refreshingTools or runtime.loadingProfile then return end
        local selected=e["Tool"..index]
        if state.toolUI[index].selected==selected then return end
        state.toolUI[index].selected=selected
        -- Choices belong to a specific tool; do not carry old selections to a new one.
        e["Upgrades"..index]={};ui["Upgrades"..index]:SetValue({})
        state.refreshTools()
    end)
end
-- Resolve dependencies in the script's initialization context, before Heartbeat
-- callbacks. Requiring them from an engine callback fails in some executors.
runtime.gameModules={}
for _,name in ipairs({"Utility","CharacterManager","ShopModule"}) do
    local module=child(child(storage(),"ModuleScripts"),name)
    local ok,value=pcall(function() assert(module,name.." unavailable");return require(module) end)
    runtime.gameModules[name]={module=module,value=ok and value or nil,error=not ok and tostring(value) or nil}
end
do
    local scripts=child(LocalPlayer,"PlayerScripts")
    local module=child(child(child(child(scripts,"GuiManager"),"MainGui"),"ShopGui"),"ShopPurchase")
    local ok,value=pcall(function() assert(module,"ShopPurchase unavailable");return require(module) end)
    runtime.gameModules.ShopPurchase={module=module,value=ok and value or nil,error=not ok and tostring(value) or nil}
end
local function gameModule(name)
    local module=child(child(storage(),"ModuleScripts"),name)
    local cached=runtime.gameModules[name]
    assert(cached and cached.module==module and cached.value,name.." initialization failed; reload after game loads. "..tostring(cached and cached.error or "module changed"))
    return cached.value
end
function state.upgradeCost(tool,upgrade)
    local level,minimum=upgrade.Value,upgrade.MinValue
    local cost,increase=readValue(upgrade,"Cost"),readValue(upgrade,"CostIncrease")
    local operator=readValue(upgrade,"CostOperator")
    assert(type(cost)=="number" and type(increase)=="number","Upgrade price unavailable")
    if operator=="+" then cost=cost+(level-minimum)*increase
    elseif operator=="~" then cost=cost+cost*(level-minimum)*(increase-1)
    elseif operator=="*" then cost=cost*increase^(level-minimum)
    else error("Unsupported upgrade price operator") end
    local perks,other=child(LocalPlayer,"PlayerPerks"),child(tool,"OtherValues")
    local multiplier=1+(readValue(perks,"WeaponUpgradePrice") or 0)
    if child(perks,"SecondaryPrice") and child(other,"SecondaryPrice") then multiplier=multiplier*(1-(readValue(perks,"SecondaryPrice")*.05+.45)) end
    if perks and child(other,"DamagePrice") then multiplier=multiplier*1.5 end
    cost=math.floor(cost*multiplier+.5)
    if readValue(child(storage(),"Values"),"Difficulty")==5 then
        local utility=gameModule("Utility")
        cost=utility:RoundPrice(cost*utility:CareerMulti(readValue(other,"PriceBuy")),"Upgrade")
    end
    assert(type(cost)=="number" and cost==cost and cost>=0 and cost<math.huge,"Invalid upgrade cost")
    return cost
end
function state.upgradeAllowed(folder,upgrade,shopUpgrade)
    local requirement=readValue(upgrade,"UpgradeReq")
    if requirement and requirement~="" and (readValue(folder,requirement) or 0)<=0 then return false end
    local locks=readValue(upgrade,"UpgradeLock")
    if locks and not (shopUpgrade and readValue(child(storage(),"Values"),"Difficulty")==5) then
        for name in tostring(locks):gmatch("([^,]+)") do
            if (readValue(folder,name) or 0)>0 then return false end
        end
    end
    local data=_G.LocalReplicatedDataStore
    if type(getrenv)=="function" then
        local ok,env=pcall(getrenv)
        if ok and env and env._G and env._G.LocalReplicatedDataStore then data=env._G.LocalReplicatedDataStore end
    end
    data=data or {}
    local achievement=readValue(upgrade,"Achievement")
    if achievement and achievement~="" and not (data.Achievements and data.Achievements[achievement]) then return false end
    local perk=readValue(upgrade,"Perk")
    if perk and perk~="" then
        local name,level=tostring(perk):match("^([^:]+):(%d+)$")
        local levels=name and data.PerkLevels and data.PerkLevels[name]
        if not name then return false,"Unrecognized perk requirement: "..tostring(perk) end
        if not child(child(LocalPlayer,"PlayerPerks"),name) then return false,"Equip required perk: "..name end
        if not levels then return false,"Perk level data unavailable: "..name.." (requires "..level..")" end
        if (tonumber(levels[1]) or 0)<tonumber(level) then return false,name.." requires level "..level.."; stored level "..tostring(levels[1]) end
    end
    return true
end
function state.shopUpgradeCost(upgrade,structure)
    local base,increase=readValue(upgrade,"Cost"),readValue(upgrade,"CostIncrease")
    local level=upgrade.Value-upgrade.MinValue
    local operator=readValue(upgrade,"CostOperator")
    assert(type(base)=="number" and type(increase)=="number","Upgrade price unavailable")
    local cost
    if operator=="+" then cost=base+level*increase
    elseif operator=="~" then cost=base+base*level*(increase-1)
    elseif operator=="*" then cost=base*increase^level
    else error("Unsupported upgrade price operator") end
    local values=child(storage(),"Values")
    if structure then cost=cost*(readValue(values,"ShopPriceMulti") or 1) end
    cost=math.floor(cost+.5)
    if readValue(values,"Difficulty")==5 then
        local utility=gameModule("Utility")
        cost=utility:RoundPrice(cost*(structure and utility:CareerStructureMulti() or utility:CareerPlayerMulti()),"Upgrade")
    end
    assert(type(cost)=="number" and cost==cost and cost>=0 and cost<math.huge,"Invalid shop upgrade cost")
    return cost
end
function state.upgradeShop(name,structure,owned,budget,selected)
    if state.shopUpgradeFaults and state.shopUpgradeFaults[name] then return false end
    local folder=child(owned,"Upgrades")
    if not folder then return false end
    local upgrades=folder:GetChildren()
    table.sort(upgrades,function(a,b) return a.Name<b.Name end)
    for _,upgrade in ipairs(upgrades) do
        if (not selected or selected[upgrade.Name]) and child(upgrade,"Cost") and child(upgrade,"EffectType") and upgrade.Value<upgrade.MaxValue and state.upgradeAllowed(folder,upgrade,true) then
            local cost=state.shopUpgradeCost(upgrade,structure)
            if cost<=budget then
                local event=child(child(storage(),"RemoteEvents"),"UpgradeStructurePlayer")
                assert(event and event:IsA("RemoteEvent"),"UpgradeStructurePlayer unavailable")
                local module=gameModule("ShopModule")
                local epoch=state.epoch or 0
                -- ShopGui increments this before updating effects; both structure and player upgrades use this remote.
                upgrade.Value=upgrade.Value+1
                local ok,err=pcall(module.UpgradeStructurePlayer,module,LocalPlayer,name,upgrade,cost)
                if not ok then
                    -- The native function may have changed some local effects before failing. Do not repeat it.
                    state.shopUpgradeFaults=state.shopUpgradeFaults or {};state.shopUpgradeFaults[name]=true
                    notice("Shop upgrades stopped for "..name..": "..tostring(err))
                    warn("[Combat Assistant] "..state.message)
                    return false
                end
                if not runtime.active or (state.epoch or 0)~=epoch then return false end
                LocalPlayer.ReplicatedMoney.Value=LocalPlayer.ReplicatedMoney.Value-cost
                event:FireServer(name,upgrade.Name)
                notice("Shop upgrade requested: "..name.." / "..upgrade.Name)
                return true
            end
        end
    end
    return false
end

function state.nativeCallback(signal,owner)
    if not signal or not owner or type(getconnections)~="function" or type(getfenv)~="function" then return end
    local ok,list=pcall(getconnections,signal)
    if not ok then return end
    for index=#list,1,-1 do
        local connection=list[index]
        local okFn,fn=pcall(function() return connection.Enabled~=false and connection.Function end)
        if okFn and type(fn)=="function" then
            local okEnv,environment=pcall(getfenv,fn)
            if okEnv and type(environment)=="table" and environment.script==owner then return fn end
        end
    end
end
function state.actionTargets(origin,range,melee)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={LocalPlayer.Character,Workspace.CurrentCamera}
    local list={}
    for _,model in ipairs(zombiesFolder:GetChildren()) do
        local humanoid=model:FindFirstChildOfClass("Humanoid")
        local part=child(model,"Torso") or child(model,"UpperTorso") or child(model,"Head")
        if humanoid and humanoid.Health>0 and part and part:IsA("BasePart") and not protectedZombie(model) and (melee or not config.IgnoreList[model.Name]) then
            local delta=part.Position-origin
            if delta.Magnitude<=range then
                local hit=Workspace:Raycast(origin,delta,params)
                if not hit or hit.Instance:IsDescendantOf(model) then table.insert(list,{model=model,part=part,distance=delta.Magnitude}) end
            end
        end
    end
    return list
end
function runtime.cancelAction()
    local action=runtime.action
    if action then
        action.cancelled=true
        if action.release then pcall(action.release);action.release=nil end
        if not action.ignoreEquip and action.previous and action.humanoid and action.humanoid.Health>0 and LocalPlayer.Character==action.character
            and action.previous.Parent==child(LocalPlayer,"Backpack") and action.character:FindFirstChildOfClass("Tool")==action.tool then
            pcall(function() action.humanoid:EquipTool(action.previous) end)
        end
    end
    runtime.actionAim=nil
end
function state.runAction(tool,enabled,fn)
    if runtime.consumableBusy or runtime.refillBusy or runtime.action or not releaseHeld() then return end
    local character,humanoid=alive()
    if not humanoid then return end
    local previous=character:FindFirstChildOfClass("Tool")
    local ignoreEquip=false -- Item actions here are melee/throwables; native throwables prepare while equipped.
    local action={character=character,tool=tool,previous=previous,humanoid=humanoid,ignoreEquip=ignoreEquip}
    runtime.action=action;runtime.consumableBusy=true
    local function valid()
        return runtime.active and not action.cancelled and e[enabled] and LocalPlayer.Character==character and humanoid.Health>0
            and (not tool or tool.Parent==character or (ignoreEquip and tool.Parent==child(LocalPlayer,"Backpack")))
    end
    task.spawn(function()
        local ok,err=pcall(function()
            if not runtime.active or action.cancelled or not e[enabled] then return end
            if not ignoreEquip and tool and tool~=previous then humanoid:EquipTool(tool);task.wait(.15) end
            if valid() then fn(action,valid) end
        end)
        if action.release then pcall(action.release) end
        runtime.actionAim=nil
        if not ignoreEquip and runtime.active and LocalPlayer.Character==character and humanoid.Health>0 and tool and previous and previous~=tool
            and previous.Parent==child(LocalPlayer,"Backpack") and (character:FindFirstChildOfClass("Tool")==tool or not character:FindFirstChildOfClass("Tool")) then
            pcall(function() humanoid:EquipTool(previous) end)
        end
        if runtime.action==action then runtime.action=nil;runtime.consumableBusy=false end
        if not ok and runtime.active then notice("Action paused: "..tostring(err)) end
    end)
end
function state.directMelee()
    if not runtime.active or not e.MeleeAura or runtime.action or runtime.consumableBusy or runtime.refillBusy then return end
    local character,humanoid=alive();local root=child(character,"HumanoidRootPart")
    if not humanoid or not root or child(child(LocalPlayer,"PlayerGui"),"MenuGui") then return end
    local tool=character:FindFirstChildOfClass("Tool")
    local melee=child(tool,"MeleeScript")
    if not melee and (not e.UseKnife or not child(character,"MeleeWeapon")) then return end
    local playerActions=child(child(LocalPlayer,"PlayerScripts"),"PlayerActions")
    if readValue(playerActions,"Meleeing")==true or readValue(tool,"Attacking")==true
        or readValue(tool,"Reloading")==true or readValue(tool,"Consuming")==true then return end
    if not melee and child(child(tool,"OtherValues"),"MountedWeapon") then return end
    local manager=gameModule("CharacterManager")
    local range,speed
    if melee then
        local values=child(tool,"CurrentValues")
        local base=readValue(values,"Range");local rate=readValue(values,"AttackSpeed")
        if not finite(base) or not finite(rate) then return end
        local saved=_G.ClientPlayerMods and _G.ClientPlayerMods[tool.Name]
        local context={Tool=tool,ModStats=saved and rangeMods and rangeMods:GetModStats(saved) or {}}
        range=(base+manager:GetAdded("Range",LocalPlayer,context))*manager:GetMulti("Range",LocalPlayer,context)
        speed=rate*manager:GetMulti("AttackSpeed",LocalPlayer,context)
    else
        range=manager:GetValue("MeleeRange",LocalPlayer)
        speed=manager:GetValue("MeleeAttackSpeed",LocalPlayer)
    end
    if not finite(range) or range<=0 or not finite(speed) or speed<=0 then return end
    local now=os.clock()
    if now<(state.directMeleeAt or 0) then return end
    local targets=state.actionTargets(root.Position,range,true)
    table.sort(targets,function(a,b) return a.distance<b.distance end)
    local hits,seen={},{}
    for _,target in ipairs(targets) do
        if #hits>=20 then break end
        if not seen[target.model] then
            seen[target.model]=true;hits[#hits+1]={target.part,{}}
        end
    end
    if #hits==0 or not releaseHeld() then return end
    -- Native rate, no range multiplier, no claimed critical/overhead/combo state.
    -- This intentionally skips native animation callbacks; server acceptance requires live testing.
    state.directMeleeAt=now+math.max(.1,60/speed)
    remote("RemoteEvents","RemoteFireMelee","FireServer",melee and tool or "Melee",hits,{})
    notice("Direct melee: "..#hits.." hits requested; server damage unverified.")
end

function state.melee() return state.directMelee() end
function state.refreshActions()
    local names={}
    for _,player in ipairs(Players:GetPlayers()) do if player~=LocalPlayer then table.insert(names,player.Name) end end
    table.sort(names);refreshChoices("DonatePlayer",names)
end
function state.donate()
    if not e.AutoDonate or state.spendingBusy then return end
    local recipient=child(Players,e.DonatePlayer)
    if not recipient or recipient==LocalPlayer then return end
    local perks=child(recipient,"PlayerPerks")
    if not perks or child(perks,"Investor") or child(perks,"DonateMoney") or child(perks,"CashBack") then
        notice("Donation recipient is ineligible.");return
    end
    local money=readValue(LocalPlayer,"ReplicatedMoney")
    local debt=readValue(LocalPlayer,"Debt")
    if type(money)~="number" or type(debt)~="number" then return end
    local amount=math.floor(math.min(e.DonateAmount,money-debt-e.MoneyReserve))
    if amount<=0 then return end
    state.spendingBusy=true
    local ok,result=pcall(remote,"RemoteFunctions","TransferMoney","InvokeServer",recipient,amount)
    state.spendingBusy=false
    notice(ok and result~="FAIL" and result~=false and "Donation submitted: "..recipient.Name or "Donation rejected; retrying later.")
end
function state.bossLurePoint(root)
    local map=child(Workspace,"Map");local shop=child(map,"Shop")
    local function position(object)
        if not object then return end
        if object:IsA("BasePart") then return object.Position end
        if object:IsA("Model") then
            if object.PrimaryPart then return object.PrimaryPart.Position end
            return object:GetPivot().Position
        end
    end
    local shopPoint=position(shop)
    if not shopPoint then return nil,"Shop position unavailable" end
    local boss,bossDistance
    for _,model in ipairs(zombiesFolder:GetChildren()) do
        local humanoid=model:FindFirstChildOfClass("Humanoid")
        local part=child(model,"HumanoidRootPart") or child(model,"Torso") or child(model,"Head")
        if model.Name=="Boss" and humanoid and humanoid.Health>0 and part and part:IsA("BasePart") then
            local distance=(part.Position-root.Position).Magnitude
            if not bossDistance or distance<bossDistance then boss=part;bossDistance=distance end
        end
    end
    if not boss then return nil,"No identified living boss" end
    local best,score
    local entrances=child(child(map,"Border"),"ZombieEntrances")
    local markers={}
    local function collect(container)
        for _,object in ipairs(container:GetChildren()) do
            -- Each entrance Model supplies one pivot; its decorative parts are not separate entrances.
            if object:IsA("Model") or object:IsA("BasePart") then
                table.insert(markers,object)
            elseif object:IsA("Folder") then collect(object) end
        end
    end
    if entrances then collect(entrances) end
    -- Use the confirmed container regardless of individual entrance names. Legacy maps retain explicit markers only.
    for _,object in ipairs(entrances and markers or map:GetDescendants()) do
        local name=object.Name:lower():gsub("[%s_]","")
        local parentName=object.Parent and object.Parent.Name:lower():gsub("[%s_]","") or ""
        local tagged=entrances~=nil or name=="enemyspawn" or name=="zombiespawn" or name=="bossspawn"
            or parentName=="enemyspawns" or parentName=="zombiespawns" or parentName=="bossspawns"
        local spawnPoint=tagged and position(object)
        if spawnPoint then
            local delta=Vector3.new(spawnPoint.X-boss.Position.X,0,spawnPoint.Z-boss.Position.Z)
            if delta.Magnitude>=25 then
                local candidate=boss.Position+delta.Unit*25
                if (candidate+Vector3.new(0,2,0)-root.Position).Magnitude>50
                    and (candidate-shopPoint).Magnitude>(boss.Position-shopPoint).Magnitude and (candidate-spawnPoint).Magnitude<(boss.Position-spawnPoint).Magnitude then
                    if not score or delta.Magnitude<score then best=candidate;score=delta.Magnitude end
                end
            end
        end
    end
    if not best then return nil,"No enemy spawn direction away from shop" end
    return best+Vector3.new(0,2,0)
end

function state.throwPlan(tool,root,destination)
    local radius=readValue(child(tool,"CurrentValues"),"Radius")
    if not finite(radius) or radius<0 then return nil,"Item radius unavailable" end
    local manager=gameModule("CharacterManager")
    radius=radius*manager:GetMulti("Radius",LocalPlayer,{Tool=tool})
    if not finite(radius) or radius<0 then return nil,"Invalid item radius" end
    radius=math.max(radius,20)
    local safety=math.max(50,radius+5)
    local lure=tool.Name=="Pipe Bomb" or tool.Name=="Zombie Bait"
    local mode=lure and e.LureMode or e.ThrowMode
    local point=mode~="Boss–Enemy Spawn" and destination or nil
    if not point and mode=="Boss–Enemy Spawn" then
        local reason;point,reason=state.bossLurePoint(root)
        if not point then return nil,reason end
    elseif not point and mode=="Cursor position" then
        local mouse=LocalPlayer:GetMouse()
        if not mouse.Target then return nil,"Point at a world surface" end
        point=mouse.Hit.Position+Vector3.new(0,2,0)
    elseif not point then
        local list=state.actionTargets(root.Position,math.huge)
        local best,count
        local function predicted(candidate)
            local point=candidate.part.Position
            if e.OP5 then
                local velocity=candidate.part.AssemblyLinearVelocity
                if typeof(velocity)=="Vector3" and finite(velocity.Magnitude) and velocity.Magnitude<=100 then point=point+velocity*e.OPPredictionSeconds end
            end
            return point
        end
        for _,candidate in ipairs(list) do
            if candidate.distance>safety then
                local nearby=0
                for _,other in ipairs(list) do if (predicted(other)-predicted(candidate)).Magnitude<=radius then nearby=nearby+1 end end
                if (not best or (mode=="Nearest safe group" and candidate.distance<best.distance)
                    or (mode=="Most crowded" and (nearby>count or nearby==count and candidate.distance<best.distance))) then
                    best,count=candidate,nearby
                end
            end
        end
        if not best then return nil,"No safe zombie group" end
        point=predicted(best)+Vector3.new(0,2,0)
    end
    local offset=point-root.Position
    if not finite(offset.Magnitude) or offset.Magnitude<=safety then
        return nil,"Destination violates the 50-stud minimum or blast margin"
    end
    for _,player in ipairs(Players:GetPlayers()) do
        local part=child(player.Character,"HumanoidRootPart")
        if part and (part.Position-point).Magnitude<=safety then return nil,"Player inside explosive safety margin" end
    end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={LocalPlayer.Character,Workspace.CurrentCamera,zombiesFolder}
    local head=child(LocalPlayer.Character,"Head") or root
    local hit=Workspace:Raycast(head.Position,point-head.Position,params)
    if hit then return nil,"Destination blocked by an obstacle" end
    -- CreateProjectile accepts a spawn frame and charge velocity. Zero velocity is a native uncharged release.
    -- Only the requested projectile origin changes; no character, tool, or world instance is moved locally.
    return {position=point,frame=CFrame.new(point),direction=offset.Unit,speed=0,safety=safety}
end
function state.throw(index)
    local item=runtime.throwDefinitions[index]
    local suffix=item and runtime.throwSuffix(index)
    if not item or not e["ThrowEnabled"..suffix] then return end
    local function report(message) state.throwStatus:SetText(message) end
    if runtime.action or runtime.consumableBusy or runtime.refillBusy then report("Wait for the current item action.");return end
    local character,humanoid=alive();local root=child(character,"HumanoidRootPart")
    if not humanoid or not root or child(child(LocalPlayer,"PlayerGui"),"MenuGui") then report("Close the game menu and try again.");return end
    local name=item[1];local _,owned=ownedTools();local tool=owned[name]
    local charge=child(child(LocalPlayer,"Charges"),name)
    if not tool or not child(tool,"GrenadeScript") or (readValue(charge,"Amount") or 0)<=0 then report(name..": not owned or no charges.");return end
    if os.clock()<(state["throwAt_"..name] or 0) then report(name..": cooling down.");return end
    local plan,why=state.throwPlan(tool,root)
    if not plan then report(why or "No safe destination");return end
    local current=child(tool,"CurrentValues")
    local cooldown=readValue(current,"Cooldown");local duration=readValue(current,"ThrowTime")
    if not finite(cooldown) or cooldown<0 or not finite(duration) or duration<=0 or duration>10 then report("Throw timing unavailable.");return end
    state["throwAt_"..name]=os.clock()+cooldown+duration
    state.runAction(tool,"ThrowEnabled"..suffix,function(action,valid)
        local manager=gameModule("CharacterManager")
        local waitFor=duration*manager:GetMulti("ThrowTime",LocalPlayer,{Tool=tool})
        assert(finite(waitFor) and waitFor>0 and waitFor<=15,"Invalid throw time")
        report("Preparing "..name.."...")
        local deadline=os.clock()+waitFor
        repeat if not valid() then report("Placement cancelled.");return end;task.wait(.05) until os.clock()>=deadline
        -- Keep the keypress destination, but recheck current player positions, blast radius, range and walls.
        local fresh,reason=state.throwPlan(tool,root,not e.OP5 and plan.position or nil)
        if not fresh then report(reason or "Destination no longer safe");return end
        if (readValue(charge,"Amount") or 0)<=0 or not valid() then report("Placement cancelled.");return end
        local backgear=child(child(LocalPlayer,"Backgear"),name)
        if not backgear then report("Backgear entry unavailable.");return end
        local before=readValue(charge,"Amount")
        remote("RemoteEvents","CreateProjectile","FireServer",tool,backgear,fresh.frame,fresh.direction,fresh.speed)
        -- Keep the throwable equipped while the server processes the request, then restore in runAction.
        local responseUntil=os.clock()+1.5
        while valid() and os.clock()<responseUntil and readValue(charge,"Amount")==before do task.wait(.05) end
        local after=readValue(charge,"Amount")
        state["throwAt_"..name]=os.clock()+cooldown
        report(name..(type(after)=="number" and after<before and ": charge deducted; placement still unverified." or ": no charge confirmation; server may have rejected placement."))
    end)
end

function state.actions()
    if os.clock()>=(state.playersAt or 0) then
        state.playersAt=os.clock()+3;state.refreshActions();runtime.refreshThrowables()
        local values=child(storage(),"Values")
        local loaded=0
        for _,player in ipairs(Players:GetPlayers()) do if child(player,"Loaded") then loaded=loaded+1 end end
        local message=readValue(values,"Vote")==true and ("Ready: "..tostring(readValue(values,"Voted") or "?").."/"..math.ceil(loaded/2).." votes. Your vote: "..(readValue(LocalPlayer,"Voted")==true and "confirmed" or "pending"))
            or ("Wave "..tostring(readValue(values,"LocalWave") or "?")..": ready-up closed by the game.")
        if not e.Autofarm and state.readyText~=message then state.readyText=message;state.readyStatus:SetText(message) end
    end
    if e.AutoDonate and not (e.AutoC96 and state.farm and not state.farm.unlimitedOwned()) then job("Donate",e.DonateInterval,state.donate) end
    if e.MeleeAura and os.clock()>=(state.meleeAt or 0) then state.meleeAt=os.clock()+.05;state.melee() end
end

function state.purchaseReserve(maintenance)
    local reserve=e.MoneyReserve
    if e.Autofarm and not maintenance then
        local wave=readValue(child(storage(),"Values"),"LocalWave") or 0
        local floor=wave>=30 and 40000 or (wave>=25 and 35000 or (wave>=20 and 20000 or 0))
        reserve=math.max(reserve,floor)
    end
    return reserve
end
local function availableMoney(maintenance)
    return math.max(0,(readValue(LocalPlayer,"ReplicatedMoney") or 0)-state.purchaseReserve(maintenance))
end
function state.upgradeTool(name,upgradeName,farmOwned)
    if not farmOwned and (e.Autofarm or (e.AutoC96 and name=="C96")) then return false end
    local _,tools=ownedTools();local tool=tools[name]
    local upgrade=child(toolUpgrades(name),upgradeName)
    if not tool or not upgrade or upgrade.Value>=upgrade.MaxValue or not state.upgradeAllowed(toolUpgrades(name),upgrade) then return false end
    local backgear=child(child(LocalPlayer,"Backgear"),name)
    if not backgear then notice("Waiting for backgear: "..name);return false end
    local cost=state.upgradeCost(tool,upgrade)
    if cost>availableMoney() then return false end
    local character,humanoid=alive()
    if not humanoid or runtime.consumableBusy or runtime.refillBusy or reloadState.key or readValue(tool,"Reloading")==true then return false end
    if not releaseHeld() then return false end
    local shopModule=gameModule("ShopModule")
    local effect=shopModule:GetTrueEffectType(readValue(upgrade,"EffectType"),name)
    if readValue(upgrade,"AltUpgrade")==true then effect="Alt"..effect end
    local event=child(child(storage(),"RemoteEvents"),"UpgradeWeapon")
    assert(event and event:IsA("RemoteEvent"),"UpgradeWeapon unavailable")
    -- Match ShopGui.BuyUpgrade, including its local cache and upgrade level updates.
    shopModule:UpgradeTool(LocalPlayer,tool,backgear,upgrade,effect)
    LocalPlayer.ReplicatedMoney.Value=LocalPlayer.ReplicatedMoney.Value-cost
    event:FireServer(name,upgradeName)
    local wasEquipped=tool.Parent==character
    if wasEquipped then humanoid:UnequipTools() end
    upgrade.Value=upgrade.Value+1
    local price=child(child(tool,"OtherValues"),"PriceValue")
    local backPrice=child(child(backgear,"OtherValues"),"PriceValue")
    if price and backPrice and price.Value>=0 then price.Value=price.Value+cost;backPrice.Value=backPrice.Value+cost end
    if wasEquipped and runtime.active and LocalPlayer.Character==character and not character:FindFirstChildOfClass("Tool") then humanoid:EquipTool(tool) end
    notice("Upgrade requested: "..name.." / "..upgradeName)
    return true
end
function state.purchase(name,farmOwned,buyOnly)
    if not farmOwned and (e.Autofarm or (e.AutoC96 and state.farm and not state.farm.unlimitedOwned())) then return false end
    if name=="Armour" and readValue(LocalPlayer,"InsideShop")~=true then return false end
    local upgrade=child(child(storage(),"Upgrades"),name)
    if not upgrade then return false end
    local structure=readValue(upgrade,"UStructure")==true
    local owned=structure and upgrade or child(child(child(LocalPlayer,"Upgrades"),"PlayerUpgrades"),name)
    if structure and readValue(LocalPlayer,"FirstWave")==true then return false end
    if readValue(owned,"UPurchased")==true then
        return not buyOnly and state.upgradeShop(name,structure,owned,availableMoney())
    end
    if readValue(owned,"UPurchased")~=false then return false end
    local values=child(storage(),"Values")
    if name=="MortarSquad" and table.find({"Underground","Subway"},readValue(values,"MapName")) then return false end
    local cost=readValue(upgrade,"UCost")
    if type(cost)~="number" then return false end
    if readValue(values,"Difficulty")==5 then
        local utility=gameModule("Utility")
        cost=utility:RoundPrice(cost*(structure and utility:CareerStructureMulti() or utility:CareerPlayerMulti()),"Structure")
    end
    if structure then cost=cost*(readValue(values,"ShopPriceMulti") or 1) end
    if cost>availableMoney() then return false end
    if name=="Armour" and not farmOwned then
        if os.clock()<(state.armourBuyAt or 0) then return false end
        state.armourBuyAt=os.clock()+5
        remote("RemoteEvents","BuyPlayerUpgrade","FireServer",name)
        notice("Armour purchase requested; awaiting game update.")
    else shop():BuyStructure(name);notice("Shop purchase checked: "..name) end
    return true
end
function state.repair(name)
    if (e.Autofarm or e.AutoC96) and state.farm and not state.farm.unlimitedOwned() then return false end
    if readValue(LocalPlayer,"InsideShop")~=true then return false end
    local upgrade=child(child(storage(),"Upgrades"),name)
    if not upgrade or (readValue(upgrade,"UStructure")==true and readValue(LocalPlayer,"FirstWave")==true) then return false end
    local cost
    if name=="Armour" then
        local playerValues=child(LocalPlayer,"PlayerValues")
        local maximum=gameModule("CharacterManager"):GetValue("MaxArmour",LocalPlayer)
        local current=readValue(playerValues,"ArmourCurrent")
        if type(maximum)~="number" or maximum<=0 or type(current)~="number" or current>=maximum then return false end
        cost=math.ceil((maximum-current)/maximum*100)*10
    else
        local time=game:GetService("Lighting"):GetMinutesAfterMidnight()
        if time<360 or time>=1080 then return false end
        local amount
        amount,cost=gameModule("Utility"):GetStructureRepairInfo(name,availableMoney(true))
        if type(amount)~="number" or amount<=0 then return false end
    end
    if type(cost)~="number" or cost>availableMoney(true) then return false end
    -- RepairStructure computes against the full balance. Do not let a partial repair cross the reserve.
    if name~="Armour" then
        local _,fullCost=gameModule("Utility"):GetStructureRepairInfo(name,readValue(LocalPlayer,"ReplicatedMoney") or 0)
        if type(fullCost)~="number" or fullCost>availableMoney(true) then return false end
    end
    if name=="Armour" then
        if os.clock()<(state.armourRetryAt or 0) then return false end
        state.armourRetryAt=os.clock()+5
        remote("RemoteEvents","SellRepair","FireServer","Armour")
        notice("Armour repair requested inside shop; awaiting game update.")
    else shop():RepairStructure(name);notice("Repair / replenish checked: "..name) end
    return true
end
-- Uses the same client bookkeeping as ShopGui; local levels are not server acknowledgements.
state.farm={stage=1,message="Off",next=0,epoch=0}
local farm=state.farm
farm.healingItems={
    {name="Bandage",excluded={HealOverTime=true}},
    {name="First Aid Kit",excluded={Range=true,StaminaHeal=true}},
    {name="Booster Kit",excluded={}}
}
farm.drinkItems={
    {name="Energy Drink",excluded={AnimationDuration=true,Stamina=true,StaminaDuration=true}},
    {name="Experimental Drink",excluded={AnimationDuration=true,DrinkLifesteal=true}},
    {name="Speed Drink",excluded={DrinkMovementSpeed=true,TimeFreeze=true,AnimationDuration=true}},
    {name="Deadeye Drink",excluded={DrinkAutoReload=true,DrinkCritChance=true}}
}
function farm.drinkItem(name)
    for _,item in ipairs(farm.drinkItems) do if item.name==name then return item end end
end
function farm.nightVisionAndDrinks()
    if not farm.upgrades("NightVision",{CriticalChance=true}) then return false end
    return farm.itemSequence(farm.drinkItems,"Drinks")
end
function farm.healingDue()
    return e.Autofarm and not farm.healingDone and farm.stage==12
end
function farm.healthDue()
    local wave=readValue(child(storage(),"Values"),"LocalWave")
    return e.Autofarm and not farm.healthDone and type(wave)=="number" and wave>=28
end
function farm.healthPriority()
    if not farm.healthDue() then return true end
    if not farm.upgrades("Health",{Health=true,HealthRegen=true}) then return false end
    farm.healthDone=true
    farm.status("Wave 28 Max Health and Health Regen complete; resuming interrupted progression.")
    return true
end
function farm.sniperAndHandling()
    if not farm.upgrades("Sniper") then return false end
    return farm.upgrades("Health",{Handling=true})
end
function farm.healingItem(name)
    for _,item in ipairs(farm.healingItems) do if item.name==name then return item end end
end
-- Match BuyTool's stock, price and weight checks without its selected-GUI dependencies.
function farm.healingPrice(template,utility,manager)
    -- Utility.ToolBuyPrice requires CharacterManager inside each invocation.
    -- Use its saved formula with the already initialized manager instead.
    local base=readValue(child(template,"OtherValues"),"PriceBuy")
    if not finite(base) then return nil end
    local perks=child(LocalPlayer,"PlayerPerks")
    local multiplier=1
    local secondary=readValue(perks,"SecondaryPrice")
    if secondary~=nil and utility:CheckArmsDealDiscount(LocalPlayer,template) then multiplier=1+(-.875+secondary*-.025) end
    if child(perks,"DamagePrice") and not manager:IsEquipment(template) and base>0 then multiplier=multiplier*1.5 end
    local sell=readValue(perks,"SellValue")
    if sell~=nil then multiplier=multiplier*(1-(sell*.05+.1)) end
    local price=math.abs(math.ceil(base*multiplier-.001))
    if readValue(child(storage(),"Values"),"Difficulty")==5 then price=utility:RoundPrice(price*utility:CareerMulti(price),"Tool") end
    return price
end
function farm.healingBuyInfo(name)
    local template=child(child(storage(),"Tools"),name)
    local playerValues=child(LocalPlayer,"PlayerValues")
    if not (farm.healingItem(name) or farm.drinkItem(name)) or not template or not child(playerValues,"PerkValues") then return nil,"waiting for item/player data" end
    local utility,manager=gameModule("Utility"),gameModule("CharacterManager")
    if not utility:IsWeaponInStock(name,LocalPlayer) then return nil,"item not in stock" end
    local price=farm.healingPrice(template,utility,manager)
    local weight=manager:GetValue("WeightTool",LocalPlayer,{Tool=template})
    local maximum=manager:GetValue("MaxWeight")
    local current=readValue(playerValues,"WeightCurrent")
    if not finite(price) or price<0 or not finite(weight) or not finite(maximum) or not finite(current) then return nil,"price/weight unavailable" end
    if child(child(LocalPlayer,"PlayerPerks"),"SecondaryPrice") and not manager:IsEquipment(template) then
        local backgear=child(LocalPlayer,"Backgear");if not backgear then return nil,"backgear unavailable" end
        local largest=0
        for _,tool in ipairs(backgear:GetChildren()) do
            if not manager:IsEquipment(tool) then largest=math.max(largest,readValue(child(tool,"CurrentValues"),"Weight") or 0) end
        end
        weight=weight<=largest and math.min(1,weight) or weight-largest+1
    end
    if weight>maximum-current then return nil,"insufficient carrying capacity" end
    return price
end
function farm.purchaseHealing(name)
    local _,tools=ownedTools()
    if tools[name] or child(child(LocalPlayer,"Backgear"),name) then return false end
    local price,reason=farm.healingBuyInfo(name)
    if not price or price>availableMoney() then farm.waitStatus(name..": "..(reason or "purchase budget changed"));return false end
    remote("RemoteEvents","BuyWeapon","FireServer",name)
    -- Ownership is only accepted when the actual tool arrives; never fabricate it.
    return true
end
function farm.itemSequence(items,label)
    if not farm.confirmed() then return false end
    local _,tools=ownedTools()
    for _,item in ipairs(items) do
        if not tools[item.name] then
            if child(child(LocalPlayer,"Backgear"),item.name) then farm.waitStatus(item.name.." tool replication");return false end
            local price,reason=farm.healingBuyInfo(item.name)
            if not price then farm.waitStatus(label..": "..item.name.." — "..reason);return false end
            if os.clock()<(farm.healingBuyAt or 0) then farm.waitStatus(label..": "..item.name.." ownership confirmation");return false end
            return farm.request({Name=item.name},price,"BuyHealing",item.name)
        end
    end
    -- Finish buying the whole item group before spending on its upgrades.
    for _,item in ipairs(items) do
        local folder=toolUpgrades(item.name)
        if not folder then farm.waitStatus(label..": "..item.name.." upgrade data");return false end
        local list=folder:GetChildren();table.sort(list,function(a,b) return a.Name<b.Name end)
        local count,blocked=0,nil
        for _,u in ipairs(list) do
            if child(u,"Cost") and not item.excluded[u.Name] then
                count=count+1
                if not finite(u.Value) or not finite(u.MaxValue) then farm.waitStatus(item.name.." / "..u.Name.." level data");return false end
                if u.Value<u.MaxValue then
                    local allowed,reason=state.upgradeAllowed(folder,u)
                    if allowed then return farm.request(u,state.upgradeCost(tools[item.name],u),"UpgradeWeapon",item.name,u.Name) end
                    blocked=blocked or item.name.." / "..u.Name..": "..(reason or "upgrade prerequisite or path lock")
                end
            end
        end
        if count==0 then farm.waitStatus(label..": no allowed upgrade data for "..item.name);return false end
        if blocked then farm.waitStatus(label..": "..blocked);return false end
    end

    return true
end
function farm.healingPriority()
    if not farm.healingDue() then return true end
    if not farm.itemSequence(farm.healingItems,"Post-Handling") then return false end
    farm.healingDone=true
    farm.status("Healing upgrades complete; continuing after stage "..tostring(farm.stage))
    return true
end
function farm.mapName() return readValue(child(storage(),"Values"),"MapName") end
function farm.supported() local name=farm.mapName();return name=="Default" or name=="Winter" or name=="Lakeside" end
function farm.voteMap()
    local values=child(storage(),"Values")
    if (readValue(values,"VotingTime") or 0)<=0 then return false end
    local ballot=ballotChoices();local index=table.find(ballot,"Default") or table.find(ballot,"Winter") or table.find(ballot,"Lakeside")
    if not index then farm.status("Forest, Arctic and Lakeside absent from ballot; waiting for next run.");return true end
    if readValue(LocalPlayer,"VotedMap")~=index and os.clock()>=(farm.mapVoteAt or 0) then
        farm.mapVoteAt=os.clock()+3;remote("RemoteEvents","RemoteMapVote","FireServer",index)
    end
    farm.status((ballot[index]=="Default" and "Forest" or (ballot[index]=="Winter" and "Arctic" or "Lakeside")).." vote submitted; waiting for map result.");return true
end
function farm.status(message)
    farm.message=message
    if farm.displayed==message or not farm.label or os.clock()<(farm.displayRetryAt or 0) then return end
    farm.displayRetryAt=os.clock()+.5
    local ok,result=pcall(function() return farm.label:SetText(message) end)
    if ok and result~=false then farm.displayed=message;farm.displayError=nil
    else farm.displayError=tostring(farm.label.renderError or result) end
end
function farm.waitStatus(reason)
    if farm.waitReason~=reason then farm.waitReason=reason;farm.waitSince=os.clock() end
    farm.status("Waiting: "..reason.." ("..math.floor(os.clock()-(farm.waitSince or os.clock())).."s). Stage "..tostring(farm.stage)..", live wave "..tostring(readValue(child(storage(),"Values"),"LocalWave")))
end
function farm.unlimited()
    local folder=toolUpgrades("C96")
    if not folder then return nil end
    for _,u in ipairs(folder:GetChildren()) do
        if u.Name=="UnlimitedAmmo" or readValue(u,"EffectType")=="Unlimited Ammo" then return u end
    end
end
function farm.unlimitedOwned()
    local u=farm.unlimited();return u and type(u.Value)=="number" and u.Value>(u.MinValue or 0) or false
end
function farm.confirmed()
    if farm.fault then farm.status(farm.fault);return false end
    if farm.inFlight then farm.waitStatus("native farm purchase response");return false end
    return true
end
function farm.request(object,cost,event,...)
    if state.spendingBusy then farm.waitStatus("support purchase/repair response");return false end
    if not farm.confirmed() or os.clock()<(farm.requestAt or 0) then return false end
    if type(cost)~="number" or cost<0 or cost>=math.huge or cost~=cost then farm.status("Unknown price; purchase withheld.");return false end
    local cash=readValue(LocalPlayer,"ReplicatedMoney")
    if not finite(cash) then farm.status("Waiting for numeric ReplicatedMoney; balance unavailable.");return false end
    local budget=availableMoney()
    local reserve=state.purchaseReserve()
    farm.purchaseBudget={item=object.Name,cost=cost,cash=cash,reserve=reserve,available=budget,at=os.clock()}
    if cost>budget then
        farm.status("Saving for "..object.Name..": cost "..math.ceil(cost)..", cash "..math.floor(cash)..", reserve "..tostring(reserve)..", available "..math.floor(budget));return false
    end
    local _,humanoid=alive()
    if not humanoid then farm.waitStatus("living character before purchase");return false end
    if runtime.consumableBusy or runtime.refillBusy or reloadState.key then
        farm.waitStatus("item use/refill/reload before "..object.Name.." purchase (available "..math.floor(budget)..", cost "..math.ceil(cost)..")");return false
    end
    local args={...};local character=LocalPlayer.Character;local run=farm.runId
    farm.purchaseObservation={object=object,before=object.Value,event=event,item=args[1],name=object.Name,state="Queued"}
    local observation=farm.purchaseObservation
    farm.inFlight=true;farm.requestAt=os.clock()+math.max(.5,e.ActionInterval)
    task.spawn(function()
        if not runtime.active or LocalPlayer.Character~=character or farm.runId~=run or not (e.Autofarm or e.AutoC96) then farm.inFlight=false;return end
        if farm.healthDue() then
            if not (args[1]=="Health" and (event=="BuyPlayerUpgrade" or (event=="UpgradeStructurePlayer" and (args[2]=="Health" or args[2]=="HealthRegen")))) then farm.inFlight=false;return end
        elseif farm.healingDue() and not ((event=="UpgradeWeapon" or event=="BuyHealing") and farm.healingItem(args[1])) then farm.inFlight=false;return end
        -- A queued job must respect a newly reached wave floor or maintenance spending.
        if cost>availableMoney() then
            observation.state="Waiting for purchase budget";farm.inFlight=false
            farm.status("Purchase held: "..object.Name.."; reserve "..tostring(state.purchaseReserve()))
            return
        end
        local ok,result=pcall(function()
            if event=="BuyHealing" then
                farm.healingBuyAt=os.clock()+3
                return farm.purchaseHealing(args[1])
            end
            if event=="UpgradeWeapon" then return state.upgradeTool(args[1],args[2],true) end
            if event=="UpgradeStructurePlayer" then
                local _,owned,structure=farm.shopData(args[1])
                return state.upgradeShop(args[1],structure,owned,availableMoney(),{[args[2]]=true})
            end
            return state.purchase(args[1],true,true)
        end)
        farm.inFlight=false
        if farm.runId~=run or LocalPlayer.Character~=character then return end
        if not ok then observation.state="Native request failed";farm.fault="Native purchase failed: "..tostring(result);farm.status(farm.fault)
        elseif result then observation.state="Request sent";farm.status("Native purchase sent: "..object.Name..". Waiting for observed ownership/level change.")
        else observation.state="Blocked by native prerequisites";farm.status("Purchase waiting for native prerequisites: "..object.Name) end
    end)
    return false
end
function farm.upgradeC96(onlyUnlimited)
    if not farm.confirmed() then return false end
    local folder=toolUpgrades("C96");local _,tools=ownedTools();local tool=tools.C96
    local first=farm.unlimited()
    if not tool or not folder or not first then farm.status("Waiting for owned C96 and Unlimited Ammo upgrade data.");return false end
    local chosen
    if not farm.unlimitedOwned() then chosen=first
    elseif onlyUnlimited then return true
    else
        local list=folder:GetChildren();table.sort(list,function(a,b) return a.Name<b.Name end)
        for _,u in ipairs(list) do
            if child(u,"Cost") and type(u.Value)=="number" and u.Value<u.MaxValue and state.upgradeAllowed(folder,u) then chosen=u;break end
        end
        if not chosen then return true end
    end
    local allowed,reason=state.upgradeAllowed(folder,chosen)
    if not allowed then farm.status("C96 "..chosen.Name..": "..(reason or "upgrade prerequisite not met"));return false end
    return farm.request(chosen,state.upgradeCost(tool,chosen),"UpgradeWeapon","C96",chosen.Name)
end
function farm.shopData(name)
    local template=child(child(storage(),"Upgrades"),name)
    if not template then return nil end
    local structure=readValue(template,"UStructure")==true
    local owned=structure and template or child(child(child(LocalPlayer,"Upgrades"),"PlayerUpgrades"),name)
    return template,owned,structure
end
function farm.buy(name)
    local template,owned,structure=farm.shopData(name)
    if not template or not owned then farm.status("Missing shop data: "..name);return false end
    if readValue(owned,"UPurchased")==true then return true end
    if structure and readValue(LocalPlayer,"FirstWave")==true then farm.status("Structures locked until the first night is survived.");return false end
    if name=="MortarSquad" and table.find({"Underground","Subway"},readValue(child(storage(),"Values"),"MapName")) then farm.status("This map does not allow Mortar Squad.");return false end
    if name=="Armour" and readValue(LocalPlayer,"InsideShop")~=true then
        local region=child(child(storage(),"ShopRegions"),"MainShopRegion")
        if region then farm.walk(region.Position,"Entering shop for armour") end
        return false
    end
    local flag=child(owned,"UPurchased");if not flag or flag.Value~=false then farm.status("Purchase state unavailable: "..name);return false end
    local cost=readValue(template,"UCost");if type(cost)~="number" then return false end
    local values=child(storage(),"Values")
    if readValue(values,"Difficulty")==5 then
        local utility=gameModule("Utility");cost=utility:RoundPrice(cost*(structure and utility:CareerStructureMulti() or utility:CareerPlayerMulti()),"Structure")
    end
    if structure then cost=cost*(readValue(values,"ShopPriceMulti") or 1) end
    return farm.request(flag,cost,structure and "BuyStructure" or "BuyPlayerUpgrade",name)
end
function farm.upgrades(name,selected,firstLevelOnly)
    if state.shopUpgradeFaults and state.shopUpgradeFaults[name] then
        farm.status("Native upgrade failed for "..name.."; purchase paused to avoid repeating partial changes. Movement and ready-up continue.");return false
    end
    if not farm.confirmed() or not farm.buy(name) then return false end
    local _,owned,structure=farm.shopData(name);local folder=child(owned,"Upgrades")
    if not folder then farm.status("Upgrade list unavailable: "..name);return false end
    local list=folder:GetChildren();table.sort(list,function(a,b) return a.Name<b.Name end)
    local found={}
    for _,u in ipairs(list) do
        if child(u,"Cost") and type(u.Value)=="number" and (not selected or selected[u.Name]) then
            found[u.Name]=true
            local maximum=firstLevelOnly and math.min(u.MaxValue,(u.MinValue or 0)+1) or u.MaxValue
            if u.Value<maximum then
                if state.upgradeAllowed(folder,u,true) then return farm.request(u,state.shopUpgradeCost(u,structure),"UpgradeStructurePlayer",name,u.Name)
                elseif selected then farm.status("Required upgrade is locked: "..name.." / "..u.Name);return false end
            end
        end
    end
    if selected then for key in pairs(selected) do if not found[key] then farm.status("Missing required upgrade: "..name.." / "..key);return false end end end
    return true
end
function farm.inRegion(root,region)
    if not root or not region then return false end
    local p=region.CFrame:PointToObjectSpace(root.Position);local s=region.Size/2
    return math.abs(p.X)<=s.X and math.abs(p.Y)<=s.Y and math.abs(p.Z)<=s.Z
end
function farm.cancelWalk()
    if farm.stopSprint then farm.stopSprint() end
    farm.retreat=nil;farm.sprintClear=false;farm.clearAt=0;farm.clearPoint=nil;farm.lastGroundAt=nil
    if farm.route and farm.route.blocked then farm.route.blocked:Disconnect() end
    if farm.route and farm.route.path then pcall(function() farm.route.path:Destroy() end) end
    farm.epoch=farm.epoch+1;farm.route=nil;farm.pathBusy=false;farm.climbDirection=nil
    farm.walkPoint=nil;farm.jumpUntil=nil
    local character,humanoid=alive();local root=child(character,"HumanoidRootPart")
    if humanoid and root and farm.moving then humanoid:MoveTo(root.Position) end
    farm.moving=false
end
function farm.walk(goal,message,tolerance)
    local character,humanoid=alive();local root=child(character,"HumanoidRootPart")
    if not root or not humanoid then return false end
    local function distance(a,b) return Vector3.new(a.X-b.X,0,a.Z-b.Z).Magnitude end
    if distance(root.Position,goal)<(tolerance or 1.5) and math.abs(root.Position.Y-goal.Y)<4 and farm.grounded(humanoid,root) then farm.cancelWalk();return true end
    if farm.retreat then
        if (farm.retreat.goal-goal).Magnitude>4 or os.clock()>=farm.retreat.untilAt then farm.cancelWalk();farm.pathAt=0
        else farm.walkPoint=farm.retreat.point;farm.status("Backing up before recalculating route");return false end
    end
    farm.status(message);farm.moving=true
    local route=farm.route
    if route and (route.goal-goal).Magnitude>4 then farm.cancelWalk();route=nil end
    if route then
        local point=farm.steerRoute(humanoid,root)
        if not point then farm.cancelWalk();farm.pathAt=0;return false end
        if route.obstructed or os.clock()-route.progressAt>2 then
            if route.direct then farm.forcePathUntil=os.clock()+3 end
            farm.cancelWalk();farm.pathAt=os.clock()+.25
            farm.backoff(root,point.Position,goal)
            farm.status("Route obstructed or stalled; recalculating around obstacles.");return false
        end
        return false
    end
    if farm.pathBusy or os.clock()<(farm.pathAt or 0) then return false end
    -- Start immediately when the whole ground corridor is clear. Paths remain
    -- the fallback for doors, corners, uneven terrain and jump approaches.
    if not farm.exitWalking and not farm.retreat and os.clock()>=(farm.forcePathUntil or 0)
        and farm.grounded(humanoid,root) and farm.clearGroundSegment(root,goal) then
        farm.route={points={{Position=goal,Action=Enum.PathWaypointAction.Walk}},index=1,goal=goal,progressAt=os.clock(),direct=true}
        farm.steerRoute(humanoid,root)
        return false
    end
    farm.pathBusy=true;farm.pathAt=os.clock()+3;local epoch=farm.epoch
    task.spawn(function()
        local created
        local ok,path=pcall(function()
            local p=game:GetService("PathfindingService"):CreatePath({AgentRadius=2.5,AgentHeight=5,AgentCanJump=true,AgentCanClimb=true,WaypointSpacing=2})
            created=p
            p:ComputeAsync(root.Position,goal);return p
        end)
        local function dispose() if created then pcall(function() created:Destroy() end) end end
        if epoch~=farm.epoch or LocalPlayer.Character~=character or not runtime.active then dispose();return end
        farm.pathBusy=false
        if ok and path.Status==Enum.PathStatus.Success then
            local route={path=path,points=path:GetWaypoints(),index=1,goal=goal,progressAt=os.clock()};farm.route=route
            if path.Blocked then route.blocked=path.Blocked:Connect(function(index)
                if farm.route==route and index>=route.index then route.obstructed=true end
            end) end
            farm.steerRoute(humanoid,root)
        else dispose();farm.status("No walkable path: "..message..". Waiting; no teleport fallback.") end
    end)
    return false
end
function farm.leave(which)
    local time=game:GetService("Lighting"):GetMinutesAfterMidnight()
    local daytime=time>=360 and time<1080
    local character,humanoid=alive();local root=child(character,"HumanoidRootPart")
    if not root or not humanoid then return false end
    local regions=child(storage(),"ShopRegions");local region=child(regions,which==1 and "SpawnExit" or "ShopExit")
    if not region then farm.status("Exit region unavailable.");return false end
    local inside=farm.inRegion(root,region)
    local function finish()
        -- An already-completed exit check must not cancel a positioning route.
        if farm.exitWalking==which then farm.cancelWalk();farm.exitWalking=nil;farm.pathAt=0 end
        if farm.exitTransit and farm.exitTransit.which==which then farm.exitTransit=nil end
        return true
    end
    -- Both native exit transitions move along world +Z. Being away from the
    -- small interaction volume does NOT mean the player has left the room.
    local beyondDoor=root.Position.Z>region.Position.Z+region.Size.Z/2+.5
    local transit=farm.exitTransit
    if transit and (transit.character~=character or transit.region~=region) then farm.exitTransit=nil;transit=nil end
    if transit and transit.which==which then
        if not inside and beyondDoor then return finish() end
        if inside and os.clock()-(transit.startedAt or os.clock())>=5 then
            -- A rejected transition or return to the same doorway must not
            -- leave the route permanently stuck in its clearing phase.
            farm.cancelWalk();farm.exitTransit=nil;farm.pathAt=0
        else
            farm.exitWalking=which
            farm.walk(transit.goal,"Clearing "..(which==1 and "spawn" or "shop").." doorway",.6)
            return false
        end
    end
    local shopRoom=child(regions,"MainShopRegion")
    local inShop=which==2 and shopRoom and farm.inRegion(root,shopRoom)
    if not inside and not inShop and beyondDoor then return finish() end
    if not inside then farm.exitWalking=which;farm.walk(region.Position,which==1 and "Walking to spawn door" or "Walking to shop door",.6);return false end
    if which==1 and readValue(LocalPlayer,"CanExitSpawn")~=true then farm.status("At spawn door; waiting for CanExitSpawn.");return false end
    if (which==1 and not daytime) or (which==2 and daytime) then
        farm.cancelWalk();farm.exitWalking=which;farm.pathAt=0
        farm.exitTransit={which=which,character=character,region=region,startedAt=os.clock(),goal=Vector3.new(root.Position.X,root.Position.Y,region.Position.Z+region.Size.Z/2+4)}
        farm.walk(farm.exitTransit.goal,"Walking through open door",.6);return false
    end
    if os.clock()>=(farm.exitAt or 0) then
        farm.exitAt=os.clock()+3
        farm.cancelWalk();farm.exitWalking=which;farm.pathAt=0
        remote("RemoteEvents","PlayerTeleport","FireServer",root.Position,which)
        -- This small transition is part of MainGui.ExitRoom, after the region-checked request.
        character:TranslateBy(Vector3.new(0,.2,8))
        farm.exitTransit={which=which,character=character,region=region,startedAt=os.clock(),goal=Vector3.new(root.Position.X,root.Position.Y,region.Position.Z+region.Size.Z/2+4)}
        farm.status("Native exit performed; clearing doorway before continuing.")
    end
    return false
end
function farm.forwardPosition()
    local goals={Default=Vector3.new(-5,4,79),Winter=Vector3.new(1,-25,-8),Lakeside=Vector3.new(28,3,176)}
    local goal=goals[farm.mapName()]
    if not goal then farm.status("No firing position configured for this map.");return false end
    return farm.walk(goal,"Walking to map firing position",1.5)
end
function farm.priorityUpgrades()
    if not farm.upgradeC96(false) then return false end
    return farm.upgrades("Shop",{MoneyUpgrade=true})
end
function farm.earlyWaves()
    local values=child(storage(),"Values")
    local wave=readValue(values,"LocalWave")
    if type(wave)~="number" or wave<1 then farm.status("Waiting for valid wave state before early-wave voting.");return false end
    local time=game:GetService("Lighting"):GetMinutesAfterMidnight()
    local daytime=time>=360 and time<1080
    if wave>=5 then
        farm.status("Holding wave-5 vote; moving to Ammo Box position.")
        return true
    end
    if wave<5 and daytime and readValue(values,"Vote")==true and readValue(LocalPlayer,"Voted")==false then
        local run=farm.runId
        local character=LocalPlayer.Character
        local map=child(Workspace,"Map")
        job("Farm early waves",3,function()
            local current=readValue(values,"LocalWave")
            local t=game:GetService("Lighting"):GetMinutesAfterMidnight()
            if e.Autofarm and farm.stage==5 and farm.runId==run and LocalPlayer.Character==character and child(Workspace,"Map")==map and type(current)=="number" and current<5 and t>=360 and t<1080 then state.skip() end
        end)
    end
    if not farm.forwardPosition() then return false end
    if wave>=2 and wave<=4 then farm.priorityUpgrades() end
    if farm.inFlight then farm.waitStatus("native priority purchase response; early-wave voting still active")
    elseif state.spendingBusy then farm.waitStatus("support purchase/repair response; early-wave voting still active")
    else farm.status("Early-wave farming: "..wave..". Ready "..tostring(readValue(values,"Vote"))..", voted "..tostring(readValue(LocalPlayer,"Voted"))..". C96 then Shop Money; mount Ammo Box on day 5 before voting.") end
    return false
end
-- Resolve the shop's physical AmmoBox, never RoofAmmo or a deployable.
function farm.rootOffset(character,humanoid,root)
    local leg=child(character,"Left Leg") or child(character,"Right Leg")
    return (humanoid.HipHeight or 0)+root.Size.Y/2+(leg and leg.Size.Y or 0)
end
function farm.ammoSurface()
    local box=child(child(child(Workspace,"Map"),"Upgrades"),"AmmoBox")
    if not box then return nil,"Shop Ammo Box has not loaded" end
    local cached=farm.ammoTop
    if cached and cached.box==box and cached.part.Parent and (cached.part==box or cached.part:IsDescendantOf(box)) and cached.part.CanCollide
        and (cached.part.Size-cached.partSize).Magnitude<.05 and cached.part.CFrame.UpVector.Y>.9 then
        return box,cached.part.CFrame:PointToWorldSpace(cached.localPoint),cached.part
    end
    if os.clock()<(farm.ammoScanAt or 0) then return nil,"Waiting for a standable Ammo Box top" end
    farm.ammoScanAt=os.clock()+1
    local ok,frame,size=pcall(function()
        if box:IsA("BasePart") then return box.CFrame,box.Size end
        return box:GetBoundingBox()
    end)
    if not ok or not frame or not size then return nil,"Ammo Box geometry unavailable" end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances={box};params.RespectCanCollide=true
    local height=size.Magnitude+4
    for _,offset in ipairs({Vector3.new(0,0,0),Vector3.new(size.X*.2,0,0),Vector3.new(-size.X*.2,0,0),Vector3.new(0,0,size.Z*.2),Vector3.new(0,0,-size.Z*.2)}) do
        local sample=frame:PointToWorldSpace(offset)
        local hit=Workspace:Raycast(sample+Vector3.new(0,height,0),Vector3.new(0,-height*2,0),params)
        if hit and hit.Instance and hit.Instance.CanCollide and hit.Normal.Y>.9 then
            -- Verify a small footprint so a decorative edge cannot count as a safe top.
            local supported=true
            for _,foot in ipairs({Vector3.new(.65,0,0),Vector3.new(-.65,0,0),Vector3.new(0,0,.65),Vector3.new(0,0,-.65)}) do
                local contact=Workspace:Raycast(hit.Position+foot+Vector3.new(0,.5,0),Vector3.new(0,-1,0),params)
                if not contact or contact.Normal.Y<.9 or math.abs(contact.Position.Y-hit.Position.Y)>.15 then supported=false;break end
            end
            if supported then
                farm.ammoTop={box=box,part=hit.Instance,partSize=hit.Instance.Size,localPoint=hit.Instance.CFrame:PointToObjectSpace(hit.Position),frame=frame,size=size}
                return box,hit.Position,hit.Instance
            end
        end
    end
    return nil,"No flat, collidable Ammo Box top with enough footing"
end
function farm.ammoSupported(root,box,offset)
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances={box};params.RespectCanCollide=true
    local hit=Workspace:Raycast(root.Position,Vector3.new(0,-offset-.75,0),params)
    return hit and hit.Instance and (hit.Instance==box or hit.Instance:IsDescendantOf(box)) and hit.Normal.Y>.9 or false
end
function farm.ammoApproach(box,surface,humanoid,root,avoid)
    local cached=farm.ammoTop
    if not cached or cached.box~=box then return nil end
    local frame,size=cached.part.CFrame,cached.part.Size
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={LocalPlayer.Character,box};params.RespectCanCollide=true
    local chosen,score
    for _,offset in ipairs({Vector3.new(size.X/2+2,0,0),Vector3.new(-size.X/2-2,0,0),Vector3.new(0,0,size.Z/2+2),Vector3.new(0,0,-size.Z/2-2)}) do
        local point=frame:PointToWorldSpace(offset)
        local hit=Workspace:Raycast(Vector3.new(point.X,surface.Y+3,point.Z),Vector3.new(0,-30,0),params)
        if hit and hit.Normal.Y>.8 and hit.Position.Y<=surface.Y+.1 then
            local goal=hit.Position+Vector3.new(0,farm.rootOffset(LocalPlayer.Character,humanoid,root),0)
            local distance=(goal-root.Position).Magnitude
            if avoid and (goal-avoid).Magnitude<.5 then distance=distance+10000 end
            if not score or distance<score then chosen=goal;score=distance end
        end
    end
    return chosen
end
function farm.holdAmmoBox()
    local character,humanoid=alive();local root=child(character,"HumanoidRootPart")
    if not root or not humanoid or not root.Size then return false end
    local room=child(child(storage(),"ShopRegions"),"MainShopRegion")
    if readValue(LocalPlayer,"InsideShop")==true or (room and farm.inRegion(root,room)) then
        if not farm.leave(2) then return false end
    end
    local box,surface,part=farm.ammoSurface()
    if not box then farm.cancelWalk();farm.boxPosition=nil;farm.status(tostring(surface));return false end
    local state=farm.boxPosition
    if not state or state.box~=box or state.part~=part or state.character~=character then
        farm.cancelWalk();state={box=box,part=part,character=character,at=os.clock()};farm.boxPosition=state
    end
    local offset=farm.rootOffset(character,humanoid,root)
    local goal=surface+Vector3.new(0,offset,0)
    local horizontal=Vector3.new(goal.X-root.Position.X,0,goal.Z-root.Position.Z).Magnitude
    local height=goal.Y-root.Position.Y
    if horizontal<.7 and math.abs(height)<.65 and farm.grounded(humanoid,root) and farm.ammoSupported(root,box,offset) then
        farm.cancelWalk();state.stableAt=state.stableAt or os.clock();state.at=os.clock()
        if os.clock()-state.stableAt<.35 then farm.status("Checking stable Ammo Box arrival");return false end
        state.phase="holding";farm.status("Holding center of Ammo Box top");return true
    end
    state.stableAt=nil
    if state.phase=="holding" then state.phase=nil;state.at=os.clock() end
    if state.retryAt and os.clock()<state.retryAt then farm.stopSprint();farm.status("Ammo Box ascent stalled; retrying shortly");return false end
    if (horizontal>3 and state.phase~="mounting") or height< -3 then
        local approach=state.approach or farm.ammoApproach(box,surface,humanoid,root,state.avoidApproach)
        if not approach then farm.cancelWalk();farm.status("No supported ground approach to Ammo Box");return false end
        local distance=(approach-root.Position).Magnitude
        if not state.approach then state.approach=approach;state.progressAt=os.clock();state.best=distance end
        if distance<(state.best or distance)-.25 then state.progressAt=os.clock();state.best=distance end
        if os.clock()-(state.progressAt or os.clock())>12 then
            farm.cancelWalk();state.avoidApproach=approach;state.approach=nil;state.best=nil
            farm.status("Ammo Box approach stalled; selecting another supported side");return false
        end
        state.phase="approach"
        if farm.walk(approach,"Walking to Ammo Box ground approach",.8) then state.phase="mounting";state.at=os.clock();state.approach=nil;state.best=nil end
        return false
    end
    local jumpHeight=humanoid.JumpHeight or 7
    if humanoid.UseJumpPower~=false and finite(humanoid.JumpPower) and finite(Workspace.Gravity) and Workspace.Gravity>0 then jumpHeight=humanoid.JumpPower^2/(2*Workspace.Gravity) end
    if height>jumpHeight+.5 then farm.cancelWalk();farm.status("Ammo Box top exceeds native jump height");return false end
    if os.clock()-state.at>8 then
        farm.cancelWalk();state.retryAt=os.clock()+3;state.at=state.retryAt;state.phase=nil;state.approach=nil;state.best=nil
        farm.status("Ammo Box ascent stalled; stopping before retry");return false
    end
    if farm.route or farm.pathBusy then farm.cancelWalk() end
    farm.stopSprint();state.phase="mounting";farm.moving=true;farm.walkPoint=goal
    humanoid:MoveTo(goal)
    if height>.65 and farm.grounded(humanoid,root) and os.clock()>=(state.jumpAt or 0) then
        humanoid.Jump=true;farm.jumpUntil=os.clock()+.25;state.jumpAt=os.clock()+1
    end
    farm.status("Jumping / adjusting onto Ammo Box top");return false
end

local conflicts={"AutoVote","AutoSkip","AutoEquip","AutoUpgrade1","AutoUpgrade2","AutoUpgrade3","AutoPurchase","AutoDonate","AutoC96","AutoLeaveSpawn","MeleeAura"}
function farm.begin()
    farm.runId=(farm.runId or 0)+1
    if runtime.cancelRefill then runtime.cancelRefill() end
    if runtime.cancelAction then runtime.cancelAction() end
    farm.stage=1;farm.character=LocalPlayer.Character;farm.map=child(Workspace,"Map");farm.mapId=farm.mapName();farm.requestAt=farm.requestAt or 0;farm.active=true
    farm.ammoTop=nil;farm.ammoScanAt=0;farm.boxPosition=nil
    farm.waitReason=nil;farm.waitSince=nil
    farm.earlyDone=false
    farm.positionReached=false;farm.recovering=nil;farm.lastWave=nil;farm.purchaseBudget=nil
    farm.healingDone=false;farm.healingBuyAt=0
    farm.healthDone=false
    farm.wave30NightReached=false;farm.resetAttempt=nil;farm.resetMessage=nil;farm.resetCount=0
    farm.forwardDone=false;farm.forwardGoal=nil;farm.forwardScanAt=0
    farm.pathAt=0;farm.forcePathUntil=0;farm.fault=nil;farm.exitTransit=nil;farm.exitWalking=nil
    farm.savedTrigger=config.Triggerbot;triggerToggle:SetValue(false)
    for _,key in ipairs(conflicts) do if e[key] then e[key]=false;if ui[key] then ui[key]:SetValue(false) end end end
    farm.status("Starting ordered C96 autofarm.")
end
function farm.stop()
    farm.resetAttempt=nil;farm.resetMessage=nil;farm.wave30NightReached=false
    if runtime.cancelInstantConsumables then runtime.cancelInstantConsumables("autofarm") end
    farm.runId=(farm.runId or 0)+1
    farm.cancelWalk()
    farm.exitTransit=nil;farm.exitWalking=nil
    if farm.active then triggerToggle:SetValue(farm.savedTrigger==true) end
    farm.active=false;farm.status("Off")
end
function farm.equipC96()
    local character,humanoid=alive();local tool=child(character,"C96") or child(child(LocalPlayer,"Backpack"),"C96")
    if not humanoid or not tool then return false end
    if farm.sprintSavedTool then return false end
    if tool.Parent==character then return true end
    if runtime.consumableBusy or runtime.refillBusy or reloadState.key then farm.waitStatus("item use/refill/reload before C96 equip");return false end
    if tool.Parent~=character then if not releaseHeld() then return false end;humanoid:EquipTool(tool) end
    return true
end
function farm.resumeCharacter()
    if runtime.cancelInstantConsumables then runtime.cancelInstantConsumables() end
    farm.runId=(farm.runId or 0)+1
    farm.cancelWalk()
    if runtime.cancelRefill then runtime.cancelRefill() end
    if runtime.cancelAction then runtime.cancelAction() end
    farm.character=LocalPlayer.Character;farm.recovering=1
    farm.exitTransit=nil;farm.exitWalking=nil;farm.pathAt=0
    farm.ammoTop=nil;farm.ammoScanAt=0;farm.boxPosition=nil
    farm.forwardDone=true;farm.next=0
    triggerToggle:SetValue(false);releaseHeld()
end
function farm.ongoingSkip()
    if farm.wave30VoteHeld and farm.wave30VoteHeld() then return end
    local values=child(storage(),"Values")
    local currentWave=readValue(values,"LocalWave")
    if not e.Autofarm or (not farm.positionReached and not (finite(currentWave) and currentWave>5)) or farm.recovering then return end
    if (readValue(values,"LocalLives") or 1)<=0 or (readValue(values,"VotingTime") or 0)>0 then return end
    if readValue(values,"Vote")~=true or readValue(LocalPlayer,"Voted")~=false then return end
    local run,character,map,wave=farm.runId,LocalPlayer.Character,child(Workspace,"Map"),readValue(values,"LocalWave")
    job("Farm skip",3,function()
        if e.Autofarm and farm.active and (farm.positionReached or (finite(wave) and wave>5)) and not farm.recovering and farm.runId==run
            and not (farm.wave30VoteHeld and farm.wave30VoteHeld())
            and LocalPlayer.Character==character and child(Workspace,"Map")==map
            and readValue(values,"LocalWave")==wave and (readValue(values,"LocalLives") or 1)>0
            and (readValue(values,"VotingTime") or 0)<=0 and readValue(values,"Vote")==true and readValue(LocalPlayer,"Voted")==false then state.skip() end
    end)
end
function farm.step()
    if not e.Autofarm then if farm.active then farm.stop() end;return end
    if not farm.active then farm.begin() end
    local values=child(storage(),"Values")
    local wave=readValue(values,"LocalWave")
    local newRound=type(wave)=="number" and type(farm.lastWave)=="number" and wave<farm.lastWave
    if farm.map~=child(Workspace,"Map") or farm.mapId~=farm.mapName() or newRound then
        farm.stop();farm.begin()
    elseif farm.character~=LocalPlayer.Character then
        if farm.positionReached or farm.stage>=6 then farm.positionReached=true;farm.resumeCharacter()
        else farm.stop();farm.begin() end
    end
    farm.lastWave=wave;farm.lastTick=os.clock()
    for _,key in ipairs(conflicts) do if e[key] then e[key]=false;if ui[key] then ui[key]:SetValue(false) end end end
    if farm.voteMap() then triggerToggle:SetValue(false);releaseHeld();farm.cancelWalk();return end
    if not farm.supported() then
        triggerToggle:SetValue(false);releaseHeld();farm.cancelWalk()
        local values=child(storage(),"Values")
        if readValue(values,"Vote")==true and readValue(LocalPlayer,"Voted")==false then job("Farm wait skip",3,state.skip) end
        farm.status("Unsupported map: staying put, skipping when allowed. Shop lives: "..tostring(readValue(values,"LocalLives") or "unknown")..". Waiting for game over.")
        return
    end
    if (readValue(values,"LocalLives") or 1)<=0 then farm.cancelWalk();triggerToggle:SetValue(false);farm.status("Run lost; waiting for map voting.");return end
    local _,humanoid=alive()
    if not humanoid then
        if farm.positionReached or farm.stage>=6 then farm.positionReached=true;farm.recovering=1 end
        farm.cancelWalk();farm.status("Waiting for respawn.");return
    end
    if farm.stage>=6 then farm.positionReached=true end
    -- Some returns to spawn keep the Character instance, or finish between
    -- polling ticks. Reconcile the live interaction region as well as identity.
    if not farm.recovering and farm.stage>=3 then
        local root=child(LocalPlayer.Character,"HumanoidRootPart")
        local spawn=child(child(storage(),"ShopRegions"),"SpawnExit")
        local minutes=game:GetService("Lighting"):GetMinutesAfterMidnight()
        if minutes>=360 and minutes<1080 and readValue(LocalPlayer,"CanExitSpawn")==true and farm.inRegion(root,spawn) then
            if farm.positionReached then farm.resumeCharacter()
            else
                farm.resumeCharacter();farm.recovering=nil;farm.stage=1;farm.forwardDone=false
            end
        end
    end
    if farm.wave30ResetTick and farm.wave30ResetTick() then return end
    -- Recovery holds ready-up until the character is securely back on the Ammo Box.
    if farm.recovering then
        if farm.recovering<=2 then
            if farm.leave(farm.recovering) then farm.recovering=farm.recovering+1 end
        else
            if farm.equipC96() and not config.Triggerbot then triggerToggle:SetValue(true) end
            if farm.holdAmmoBox() then farm.recovering=nil;farm.status("Respawn recovery complete; resuming upgrades and ready-up.") end
        end
        return
    end
    farm.ongoingSkip()
    if runtime.action and farm.stage>=3 then farm.waitStatus("active item action; ready-up remains independent");return end
    if os.clock()<farm.next then return end;farm.next=os.clock()+.1
    if farm.stage>=3 and not farm.forwardDone then
        if not farm.forwardPosition() then return end
        farm.forwardDone=true
    end
    if farm.stage>=3 then
        if farm.equipC96() then
            if not config.Triggerbot then triggerToggle:SetValue(true) end
        elseif farm.sprintSavedTool then farm.status("Sprinting on clear route; C96 resumes at approach")
        elseif farm.stage<6 then farm.status("Waiting to equip C96.");return end
    end
    if farm.stage>=6 and (farm.healthDue() or farm.healingDue() or (farm.stage~=7 and farm.stage~=10)) and not farm.holdAmmoBox() then return end
    if farm.stage>=3 and not farm.healthPriority() then return end
    local done=false
    if farm.stage==1 then done=farm.leave(1)
    elseif farm.stage==2 then done=farm.leave(2)
    elseif farm.stage==3 then done=farm.upgradeC96(true)
    elseif farm.stage==4 then
        done=readValue(LocalPlayer,"FirstWave")==false
        if not done and readValue(values,"Vote")==true and readValue(LocalPlayer,"Voted")==false then job("Farm first night",3,state.skip) end
        if not done then farm.status("Waiting for first night completion; vote alone is not completion.") end
    elseif farm.stage==5 then
        if not farm.earlyDone then
            if not farm.earlyWaves() then return end
            farm.earlyDone=true
        end
        done=farm.holdAmmoBox()
    elseif farm.stage==6 then done=farm.priorityUpgrades()
    elseif farm.stage==7 then done=farm.upgrades("Armour",{ArmourDurability=true,Absorption=true})
    elseif farm.stage==8 then done=farm.upgrades("Barricade")
    elseif farm.stage==9 then done=farm.upgrades("Shop")
    elseif farm.stage==10 then done=farm.nightVisionAndDrinks()
    elseif farm.stage==11 then done=farm.sniperAndHandling()
    elseif farm.stage==12 then done=farm.healingPriority()
    elseif farm.stage==13 then done=farm.upgrades("MortarSquad")
    else
        if not farm.holdAmmoBox() then return end
        done=farm.upgrades("AmmoBox",{AmmoDamage=true})
        if done then farm.status("All available ordered upgrades complete. Holding Ammo Box, C96 and skip.") end
        return
    end
    if done then
        farm.stage=farm.stage+1
        if farm.stage==6 then farm.positionReached=true end
        farm.status("Autofarm stage "..farm.stage)
    end
end
function farm.applyJump(humanoid)
    if farm.moving and farm.jumpUntil and os.clock()<farm.jumpUntil then humanoid.Jump=true end
end
if RunService.BindToRenderStep then
    local binding="CombatAssistantFarmMovement"
    RunService:BindToRenderStep(binding,Enum.RenderPriority.Last.Value,function()
        if runtime.active and (e.Autofarm or e.AutoLeaveSpawn) and (not e.Autofarm or farm.supported()) then
            local character,humanoid=alive();local root=child(character,"HumanoidRootPart")
            if humanoid and root then
                if farm.route and not farm.retreat and farm.steerRoute then farm.steerRoute(humanoid,root) end
                if farm.motionTick then farm.motionTick(humanoid,root) end
                local direction=farm.climbDirection
                if farm.walkPoint then
                    local offset=Vector3.new(farm.walkPoint.X-root.Position.X,0,farm.walkPoint.Z-root.Position.Z)
                    direction=offset.Magnitude>.25 and offset.Unit*math.min(1,offset.Magnitude/2) or Vector3.new(0,0,0)
                end
                if direction then humanoid:Move(direction,false) end
                farm.applyJump(humanoid)
            elseif farm.stopSprint then farm.stopSprint() end
        elseif farm.stopSprint then farm.stopSprint() end
    end)
    table.insert(runtime.connections,{Disconnect=function() RunService:UnbindFromRenderStep(binding) end})
end
local farmGroup=automation:AddLeftGroupbox("C96 autofarm")
control(farmGroup,"Autofarm","One-click C96 autofarm")
control(farmGroup,"AutoLeaveSpawn","Auto Leave Spawn")
farm.label=runtime.label(farmGroup,"Off",true)
runtime.label(farmGroup,"Forest > Arctic > Lakeside voting priority. Other maps: wait in spawn and ready up. Sniper is followed by Body Building Handling, then Bandage, First Aid Kit and Booster Kit before Mortar Squad. Wave 28 prioritizes Max Health and Health Regen, then resumes interrupted upgrades. Weapon and support settings are preserved. Backup Weapon required for starting C96. Farm stands on the shop Ammo Box; no roof access or Rooftop Camper required. Live routes remain unverified.",true)

-- All drinks and healing items share immediate backpack requests. Never equip,
-- synthesize input, wait for animations, or take the gun/movement lock here.
runtime.instantUses={}
function runtime.consumableAmount(name)
    return readValue(child(child(LocalPlayer,"Charges"),name),"Amount")
end
function runtime.finishInstantUse(job,status,reason)
    if job.reported then return end
    job.reported=true
    if runtime.instantUses[job.entry.name]==job and (job.returned or not job.invoked) then
        runtime.instantUses[job.entry.name]=nil
    end
    if job.done then job.done(job.entry,status,reason) end
end
function runtime.instantConsumableMonitor()
    for name,job in pairs(runtime.instantUses) do
        local amount=runtime.consumableAmount(name)
        if finite(amount) and finite(job.entry.before) and amount<job.entry.before then
            runtime.finishInstantUse(job,"consumed")
        elseif not runtime.active or LocalPlayer.Character~=job.character or job.humanoid.Health<=0 then
            runtime.finishInstantUse(job,job.invoked and "unknown" or "pending","Character changed before confirmation")
        elseif os.clock()>=job.deadline then
            runtime.finishInstantUse(job,job.invoked and "unknown" or "pending","No charge decrease observed")
        end
        if job.reported and job.returned and runtime.instantUses[name]==job then runtime.instantUses[name]=nil end
    end
end
function runtime.cancelInstantConsumables(scope)
    for name,job in pairs(runtime.instantUses) do
        if not scope or job.scope==scope then
            job.cancelled=true
            runtime.finishInstantUse(job,job.invoked and "unknown" or "pending","Use cancelled")
            -- An outstanding network call retains only its per-item lease until it
            -- returns. It cannot freeze firing, movement, or other consumables.
            if not job.invoked or job.returned then runtime.instantUses[name]=nil end
        end
    end
    return true
end
function runtime.instantConsumableBatch(entries,eligible,done,scope)
    runtime.instantConsumableMonitor()
    local folder=child(game:GetService("ReplicatedStorage"),"RemoteFunctions")
    local remote=child(folder,"UseConsumable")
    if not remote or not remote:IsA("RemoteFunction") then return false end
    local c=runtime.consumables;c.itemAt=c.itemAt or {}
    local started=0
    for _,entry in ipairs(entries) do
        local supported=false
        for _,item in ipairs(runtime.consumableDefinitions) do if item[1]==entry.name then supported=true;break end end
        local ok,tool,target,duration,amount,character,humanoid=pcall(runtime.consumableContext,entry.name)
        if supported and ok and not runtime.instantUses[entry.name] and os.clock()>=(c.itemAt[entry.name] or 0) then
            entry.before=amount
            local job={entry=entry,tool=tool,target=target,character=character,humanoid=humanoid,
                done=done,scope=scope,deadline=os.clock()+8}
            runtime.instantUses[entry.name]=job;started=started+1
            c.itemAt[entry.name]=os.clock()+math.max(1,duration)
            task.spawn(function()
                if job.cancelled or not runtime.active or runtime.instantUses[entry.name]~=job then return end
                local valid,liveTool,liveTarget=pcall(runtime.consumableContext,entry.name)
                if not valid or liveTool~=tool or liveTarget~=target or LocalPlayer.Character~=character or (eligible and not eligible(entry)) then
                    runtime.finishInstantUse(job,"pending","Use cancelled before dispatch");return
                end
                job.invoked=true;c.lastItem=entry.name
                local success,response=pcall(function() return remote:InvokeServer(entry.name,target) end)
                job.returned=true
                local after=runtime.consumableAmount(entry.name)
                if finite(after) and after<amount then runtime.finishInstantUse(job,"consumed")
                elseif success and (response==false or response=="FAIL") then runtime.finishInstantUse(job,"pending","Game rejected use")
                elseif not success then runtime.finishInstantUse(job,"unknown",tostring(response))
                else c.message=entry.name..": request returned; awaiting charge confirmation." end
                if job.reported and runtime.instantUses[entry.name]==job then runtime.instantUses[entry.name]=nil end
            end)
        elseif done then
            done(entry,"pending",not ok and tostring(tool) or "Item already requested or cooling down")
        end
    end
    return started>0
end
connect(RunService.Heartbeat,runtime.instantConsumableMonitor)
table.insert(runtime.connections,{Disconnect=function() runtime.cancelInstantConsumables() end})

-- One activation per drink per night slot; routing does not own the clock.
function farm.tripleDrinkWave(wave)
    return finite(wave) and wave>0 and wave%5==0
end
function farm.drinkEligible(wave,minimumWave)
    return finite(wave) and (wave>=minimumWave or farm.tripleDrinkWave(wave))
end
function farm.drinkSlots(wave)
    if farm.tripleDrinkWave(wave) then
        return {{key="evening",at="18:15",minutes=1095},{key="midnight",at="00:05",minutes=5},{key="late",at="00:40",minutes=40}}
    end
    return {{key="evening",at="18:15",minutes=1095},{key="midnight",at="00:10",minutes=10}}
end
function farm.drinkTimes(wave)
    return farm.tripleDrinkWave(wave) and "18:15 / 00:05 / 00:40" or "18:15 / 00:10"
end
function farm.drinkSchedule(wave,minutes,map,minimumWave)
    local clock=farm.drinkClock
    if not clock or clock.map~=map or wave~=clock.wave then
        clock={map=map,wave=wave,slots={}};farm.drinkClock=clock
    end
    if not farm.drinkEligible(wave,minimumWave or 15) then return clock end
    for _,definition in ipairs(farm.drinkSlots(wave)) do
        local due=definition.key=="evening" and minutes>=definition.minutes
            or definition.key~="evening" and minutes<360 and minutes>=definition.minutes
        if due and not clock.slots[definition.key] then
            clock.slots[definition.key]={at=definition.at,items={}}
        end
    end
    return clock
end
function farm.drinkSummary(clock)
    local consumed,pending,unknown=0,0,0
    local reason
    for _,slot in pairs(clock.slots) do
        for _,item in ipairs(farm.drinkItems) do
            local entry=slot.items[item.name]
            if entry and entry.state=="consumed" then consumed=consumed+1
            elseif entry and entry.state=="unknown" then unknown=unknown+1
            else pending=pending+1;reason=reason or (entry and entry.reason and item.name..": "..entry.reason) end
        end
    end
    return "Drinks: "..consumed.." consumed, "..pending.." pending, "..unknown.." unconfirmed."..(reason and " "..reason or "")
end
function farm.drinkPolicy()
    if e.Autofarm then return farm.active and farm.supported(),15,"autofarm" end
    return e.AutoNightDrinks==true,1,"standalone"
end
function farm.drinkTick()
    local enabled,minimumWave,owner=farm.drinkPolicy()
    if not enabled then return end
    local values=child(storage(),"Values")
    if (readValue(values,"LocalLives") or 1)<=0 or (readValue(values,"VotingTime") or 0)>0 then return end
    local wave=readValue(values,"LocalWave")
    if not finite(wave) then return end
    local minutes=game:GetService("Lighting"):GetMinutesAfterMidnight()
    local clock=farm.drinkSchedule(wave,minutes,child(Workspace,"Map"),minimumWave)
    if not farm.drinkEligible(wave,minimumWave) then return end
    if minutes>=360 and minutes<1080 then
        farm.drinkMessage="Drinks: wave "..wave.." schedule "..farm.drinkTimes(wave)..".";return
    end
    local character,humanoid=alive();local root=child(character,"HumanoidRootPart")
    if not humanoid or not root or runtime.consumableBusy or runtime.refillBusy or runtime.action then return end
    local c=runtime.consumables;c.itemAt=c.itemAt or {}
    if os.clock()<(c.drinkAt or 0) then return end
    local slot;local entries={}
    for _,definition in ipairs(farm.drinkSlots(wave)) do
        local candidate=clock.slots[definition.key]
        if candidate then
            for _,item in ipairs(farm.drinkItems) do
                local entry=candidate.items[item.name] or {state="pending",retryAt=0};candidate.items[item.name]=entry
                -- Late replication can resolve a previously uncertain use without another click.
                local amount=runtime.consumableAmount(item.name)
                if entry.state=="unknown" and finite(amount) and finite(entry.before) and amount<entry.before then entry.state="consumed";entry.reason=nil end
                if entry.state=="pending" and os.clock()>=entry.retryAt and os.clock()>=(c.itemAt[item.name] or 0) then
                    local ok,err=pcall(runtime.consumableContext,item.name)
                    entry.retryAt=os.clock()+5
                    if ok then table.insert(entries,{name=item.name,record=entry})
                    else entry.reason=tostring(err) end
                end
            end
            if #entries>0 then slot=candidate;break end
        end
    end
    if not slot then farm.drinkMessage=farm.drinkSummary(clock);return end
    for _,entry in ipairs(entries) do entry.record.owner=entry;entry.record.state="inflight" end
    local started=runtime.instantConsumableBatch(entries,function()
        local t=game:GetService("Lighting"):GetMinutesAfterMidnight()
        local active,currentMinimum,currentOwner=farm.drinkPolicy()
        local currentWave=readValue(values,"LocalWave")
        return active and currentOwner==owner and currentWave==clock.wave and farm.drinkEligible(currentWave,currentMinimum) and farm.drinkClock==clock
            and (clock.slots.evening==slot or clock.slots.midnight==slot or clock.slots.late==slot) and (t>=1080 or t<360)
            and (readValue(values,"LocalLives") or 1)>0 and child(Workspace,"Map")==clock.map
            and (readValue(values,"VotingTime") or 0)<=0
    end,function(entry,status,reason)
        if entry.record.owner~=entry then return end
        entry.record.owner=nil
        entry.record.state=status;entry.record.reason=status~="consumed" and reason or nil
        entry.record.before=entry.before
        entry.record.attempts=(entry.record.attempts or 0)+1
        entry.record.retryAt=os.clock()+math.min(60,5*entry.record.attempts)
        c.itemAt[entry.name]=os.clock()+1
        farm.drinkMessage=farm.drinkSummary(clock)
    end,owner)
    if started then
        c.drinkAt=os.clock()+1
        farm.drinkMessage=slot.at..": using "..#entries.." immediate backpack drink requests."
    else
        for _,entry in ipairs(entries) do
            if entry.record.owner==entry then entry.record.owner=nil;entry.record.state="pending" end
        end
    end
end
farm.drinkLabel=runtime.label(farmGroup,"Drinks: 18:15 / 00:10 from wave 15. Every 5th wave (including 5 and 10): 18:15 / 00:05 / 00:40. Uses owned drinks; charge confirmation required.",true)
function farm.addNightDrinkControls(group)
    group:AddDivider()
    control(group,"AutoNightDrinks","Auto use nightly drinks")
    runtime.label(group,"All four owned drinks: 18:15 / 00:10 normally; 18:15 / 00:05 / 00:40 on waves divisible by 5. Immediate backpack use. Autofarm starts regular nights at wave 15 and also handles waves 5 and 10. Shared tracking prevents duplicate activations.",true)
    farm.nightDrinkLabel=runtime.label(group,"Nightly drinks: off",true)
end
farm.addNightDrinkControls(healing)
function farm.showDrinks()
    local message=farm.drinkMessage
    if message and message~=farm.drinkDisplayed then
        local ok,result=pcall(function() return farm.drinkLabel:SetText(message) end)
        if ok and result~=false then farm.drinkDisplayed=message end
    end
    local status=not e.AutoNightDrinks and "Nightly drinks: off" or
        (e.Autofarm and "Nightly drinks: autofarm controls the shared schedule." or (message or "Nightly drinks: waiting for scheduled night slots."))
    if farm.nightDrinkLabel and status~=farm.nightDrinkDisplayed then
        local ok,result=pcall(function() return farm.nightDrinkLabel:SetText(status) end)
        if ok and result~=false then farm.nightDrinkDisplayed=status end
    end
end
-- Standalone use has its own timer and does not require the autofarm route.
function farm.standaloneDrinkMonitor()
    if not runtime.active then return end
    if os.clock()<(farm.standaloneDrinkAt or 0) then return end
    farm.standaloneDrinkAt=os.clock()+.2
    if not e.Autofarm and e.AutoNightDrinks then
        local ok,err=pcall(farm.drinkTick)
        if not ok then farm.drinkMessage="Drink scheduler: "..tostring(err) end
    end
    farm.showDrinks()
end
connect(RunService.Heartbeat,farm.standaloneDrinkMonitor)

-- Separate local settings file; not included in shareable gameplay profiles.
farm.webhook={enabled=false,url="",sent={}}
farm.webhookFile="CombatAssistantWebhook.json"
function farm.saveWebhook()
    local w=farm.webhook
    if w.loading then return end
    if w.url~="" and not farm.webhookURL(w.url) then w.saveMessage="Not saved: invalid webhook URL.";return false end
    if type(writefile)~="function" then w.saveMessage="Not saved: file writing unavailable.";return false end
    local ok=pcall(function()
        writefile(farm.webhookFile,HttpService:JSONEncode({Version=1,URL=w.url,Enabled=w.enabled}))
    end)
    w.saveMessage=ok and "Webhook settings saved locally." or "Webhook settings could not be saved."
    return ok
end
function farm.loadWebhook()
    local w=farm.webhook
    if type(readfile)~="function" then w.saveMessage="Local settings unavailable: no file reader.";return end
    if type(isfile)=="function" then
        local ok,exists=pcall(isfile,farm.webhookFile)
        if ok and not exists then return end
    end
    local ok,data=pcall(function() return HttpService:JSONDecode(readfile(farm.webhookFile)) end)
    if not ok or type(data)~="table" or data.Version~=1 or type(data.URL)~="string" or type(data.Enabled)~="boolean"
        or (data.URL~="" and not farm.webhookURL(data.URL)) then
        w.saveMessage="Saved webhook settings unavailable or invalid; enter them again.";return
    end
    w.url=data.URL:match("^%s*(.-)%s*$");w.enabled=data.Enabled
    w.saveMessage="Saved webhook settings loaded."
end
function farm.webhookStep()
    if farm.recovering then return "Returning to Ammo Box after respawn" end
    if readValue(child(storage(),"Values"),"LocalWave")==30 and farm.resetAttempt and not farm.resetAttempt.confirmed then return "Wave 30 reset / awaiting death" end
    if farm.healthDue() then return "Max Health / Health Regen" end
    if farm.healingDue() then return "Healing items and upgrades" end
    if farm.stage==5 then
        local wave=readValue(child(storage(),"Values"),"LocalWave") or 0
        return wave>=5 and "Mounting Ammo Box" or "Early farming: C96 / Shop Money"
    end
    local names={"Leaving spawn","Leaving shop","C96 Unlimited Ammo","Completing first night","Early farming / Ammo Box","C96 / Shop Money","Armour upgrades","Barricade upgrades","Shop upgrades","Night Vision / drinks","Sniper / Handling Speed","Healing items and upgrades","Mortar upgrades"}
    return names[farm.stage] or "Ammo Box damage upgrades"
end
function farm.webhookURL(value)
    if type(value)~="string" then return nil end
    value=value:match("^%s*(.-)%s*$")
    if value:match("^https://discord%.com/api/webhooks/%d+/[%w_%-]+$") or value:match("^https://discordapp%.com/api/webhooks/%d+/[%w_%-]+$") then return value.."?wait=true" end
end
function farm.webhookTick()
    local w=farm.webhook
    local values=child(storage(),"Values")
    local wave=readValue(values,"LocalWave")
    if not finite(wave) or wave<1 or wave%1~=0 then return end
    local map=child(Workspace,"Map")
    if not map then return end
    if w.map~=map or (w.wave and wave<w.wave) then w.map=map;w.sent={} end
    w.wave=wave
    if not runtime.active or not e.Autofarm or not farm.active or not w.enabled or wave%5~=0 or (readValue(values,"VotingTime") or 0)>0 then return end
    if w.sent[wave] or w.busy or os.clock()<(w.retryAt or 0) then return end
    local url=farm.webhookURL(w.url)
    if not url then w.message="Enter a valid Discord webhook URL.";return end
    local send=request or http_request
    if type(send)~="function" then w.message="HTTP request function unavailable.";return end
    local name=farm.mapName()
    name=({Default="Forest",Winter="Arctic"})[name] or name or "Unknown"
    name=tostring(name):gsub("[%c]"," "):sub(1,50)
    local content="Currently wave "..wave.."\nMap: "..name.."\nCurrent step: "..farm.webhookStep()
    local body=HttpService:JSONEncode({content=content,allowed_mentions={parse={}}})
    -- Explicitly encode an empty JSON array, even on encoders that use {} for empty tables.
    body=body:gsub('"parse"%s*:%s*{}','"parse":[]')
    local sent=w.sent
    sent[wave]="pending";w.busy=true;w.message="Sending wave "..wave.." update..."
    task.spawn(function()
        if not runtime.active or not e.Autofarm or not w.enabled or w.sent~=sent or farm.webhookURL(w.url)~=url then
            sent[wave]=nil;w.busy=false;return
        end
        local ok,response=pcall(send,{Url=url,Method="POST",Headers={["Content-Type"]="application/json"},Body=body})
        w.busy=false
        if w.sent~=sent then return end
        local code=ok and type(response)=="table" and tonumber(response.StatusCode)
        if code and code>=200 and code<300 then
            sent[wave]="sent";w.message="Sent wave "..wave.." update."
        elseif code==429 then
            local delay=60
            local decoded,data=pcall(function() return HttpService:JSONDecode(response.Body) end)
            if decoded and type(data)=="table" and finite(data.retry_after) then delay=math.max(delay,data.retry_after) end
            w.retryAt=os.clock()+delay;sent[wave]=nil;w.message="Rate limited; waiting before retry."
        else
            sent[wave]="failed"
            -- Never print response bodies/errors: they can contain the webhook token.
            w.message=code and ("Webhook HTTP "..code.."; check URL/channel.") or "Delivery uncertain; not retrying this wave."
        end
    end)
end
local webhookGroup=automation:AddRightGroupbox("Wave webhook")
farm.loadWebhook()
farm.webhook.loading=true
addControl(webhookGroup,"Input","FarmWebhookURL",{Text="Discord webhook URL (saved locally)",Default=farm.webhook.url,Finished=true,Callback=function(value) farm.webhook.url=tostring(value or ""):match("^%s*(.-)%s*$");farm.saveWebhook() end})
addControl(webhookGroup,"Toggle","FarmWebhookEnabled",{Text="Send every 5 waves",Default=farm.webhook.enabled,Callback=function(value) farm.webhook.enabled=value==true;farm.saveWebhook() end})
farm.webhook.loading=false
farm.webhook.label=runtime.label(webhookGroup,"Off. Sends wave, map and current step only.",true)
connect(RunService.Heartbeat,function()
    local w=farm.webhook
    if os.clock()<(w.tickAt or 0) then return end
    w.tickAt=os.clock()+1
    local ok=pcall(farm.webhookTick)
    if not ok then w.message="Webhook update failed locally." end
    local message=w.enabled and (w.message or "Waiting for a 5-wave milestone.") or "Off"
    if w.saveMessage then message=message.."\n"..w.saveMessage end
    if w.label and w.displayed~=message then
        local ok,result=pcall(function() return w.label:SetText(message) end)
        if ok and result~=false then w.displayed=message end
    end
end)

function farm.grounded(humanoid,root)
    local material=humanoid.FloorMaterial
    local velocity=root.AssemblyLinearVelocity
    return material~=nil and material~=Enum.Material.Air and (not velocity or math.abs(velocity.Y)<2)
end
function farm.nativeSprinting()
    local actions=child(child(LocalPlayer,"PlayerScripts"),"PlayerActions")
    return readValue(actions,"Sprinting")
end
function farm.restoreSprintTool()
    local saved=farm.sprintSavedTool
    if not saved then return end
    farm.sprintSavedTool=nil
    local character,humanoid=alive()
    if character==saved.character and humanoid and saved.tool.Parent==child(LocalPlayer,"Backpack") and not character:FindFirstChildOfClass("Tool") then
        pcall(function() humanoid:EquipTool(saved.tool) end)
    end
end
function farm.sprintKey(key,down)
    if virtualInput then virtualInput:SendKey(down,key,false)
    elseif legacyInput then legacyInput:SendKeyEvent(down,key,false,game)
    else error("No virtual keyboard") end
end
function farm.stopSprint()
    local held=farm.sprintHeld
    if not held then farm.restoreSprintTool();return end
    local ok=pcall(function()
        -- Only turn native toggle sprint off when its replicated local state is on.
        if held.toggle and farm.nativeSprinting()==true then farm.sprintKey(held.key,true) end
        farm.sprintKey(held.key,false)
    end)
    if ok then farm.sprintHeld=nil;farm.restoreSprintTool() else farm.motionStatus="Sprint release failed; retrying" end
end
function farm.sprint(wanted)
    if not wanted then farm.stopSprint();return end
    if farm.sprintHeld then
        local held=farm.sprintHeld
        local character=LocalPlayer.Character;local root=child(character,"HumanoidRootPart")
        local velocity=root and root.AssemblyLinearVelocity
        -- Native sprint may turn off while velocity is momentarily zero. Do
        -- not unstow/re-equip and restart the whole sprint at each waypoint.
        if farm.nativeSprinting()==false and velocity and Vector3.new(velocity.X,0,velocity.Z).Magnitude>1
            and os.clock()>=(held.retryAt or held.at+2) then
            held.retryAt=os.clock()+2
            local ok=pcall(function()
                if not held.toggle then farm.sprintKey(held.key,false) end
                farm.sprintKey(held.key,true)
                if held.toggle then farm.sprintKey(held.key,false) end
            end)
            if not ok then farm.stopSprint();farm.sprintRetryAt=os.clock()+2 end
        end
        return
    end
    if os.clock()<(farm.sprintRetryAt or 0) then return end
    local data=_G.LocalReplicatedDataStore
    if type(getrenv)=="function" then
        local ok,env=pcall(getrenv)
        if ok and env and env._G and env._G.LocalReplicatedDataStore then data=env._G.LocalReplicatedDataStore end
    end
    local key=data and data.KeyBinds and data.KeyBinds.Sprint
    if type(key)=="string" then key=Enum.KeyCode[key] end
    if not key or not data then farm.motionStatus="Walking: sprint binding unavailable";return end
    local toggle=data.ToggleSprint==true
    if toggle and type(farm.nativeSprinting())~="boolean" then farm.motionStatus="Walking: native toggle sprint state unavailable";return end
    if UIS:GetFocusedTextBox() or guiService.MenuIsOpen then return end
    if UIS:IsKeyDown(key) then return end
    if toggle and farm.nativeSprinting()==true then return end -- Leave a user's existing sprint alone.
    local character,humanoid=alive()
    local armed=character and character:FindFirstChildOfClass("Tool")
    if armed and not child(child(LocalPlayer,"PlayerPerks"),"RunGun") then
        if not e.Autofarm or not child(armed,"GunScript") or not releaseHeld() then return end
        farm.sprintSavedTool={character=character,tool=armed}
        local stowed=pcall(function() humanoid:UnequipTools() end)
        if not stowed or character:FindFirstChildOfClass("Tool") then farm.restoreSprintTool();return end
    end
    farm.sprintHeld={key=key,toggle=toggle,at=os.clock()}
    local ok=pcall(function() farm.sprintKey(key,true);if toggle then farm.sprintKey(key,false) end end)
    if ok then farm.motionStatus="Sprint requested"
    else farm.motionStatus="Walking: sprint input unavailable";farm.stopSprint() end
end
function farm.clearGroundSegment(root,destination)
    local delta=Vector3.new(destination.X-root.Position.X,0,destination.Z-root.Position.Z)
    if delta.Magnitude<.1 then return false end
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={LocalPlayer.Character};params.RespectCanCollide=true
    local sideways=Vector3.new(-delta.Unit.Z,0,delta.Unit.X)*1.5
    local _,humanoid=alive()
    local standingOffset=root.Size and humanoid and farm.rootOffset(LocalPlayer.Character,humanoid,root) or 3
    local endFloor=Workspace:Raycast(Vector3.new(destination.X,math.max(root.Position.Y,destination.Y)+3,destination.Z),Vector3.new(0,-12,0),params)
    if not endFloor or endFloor.Normal.Y<.8 then return false end
    local corridor=delta+Vector3.new(0,endFloor.Position.Y+standingOffset-root.Position.Y,0)
    for _,offset in ipairs({Vector3.new(0,0,0),sideways,sideways*-1}) do
        if Workspace:Raycast(root.Position+offset,corridor,params) then return false end
    end
    local previousFloor
    for distance=0,delta.Magnitude+2,2 do
        local origin=root.Position+corridor*(math.min(distance,delta.Magnitude)/delta.Magnitude)
        local floor=Workspace:Raycast(origin,Vector3.new(0,-6,0),params)
        if not floor or floor.Normal.Y<.8 then return false end
        local expected=previousFloor or (root.Position.Y-standingOffset)
        if math.abs(floor.Position.Y-expected)>1.5 then return false end
        previousFloor=floor.Position.Y
    end
    return true
end
function farm.movementTarget(route,root)
    local point=route.points[route.index];if not point then return nil end
    local target=point.Position
    local base=Vector3.new(target.X-root.Position.X,0,target.Z-root.Position.Z)
    if base.Magnitude<.1 or point.Action==Enum.PathWaypointAction.Jump then return target end
    for i=route.index+1,#route.points do
        local candidate=route.points[i]
        local delta=Vector3.new(candidate.Position.X-root.Position.X,0,candidate.Position.Z-root.Position.Z)
        local dot=base.Unit.X*delta.Unit.X+base.Unit.Z*delta.Unit.Z
        if delta.Magnitude>32 or math.abs(candidate.Position.Y-target.Y)>1 or candidate.Action==Enum.PathWaypointAction.Jump or delta.Magnitude<.1 or dot<.98 then break end
        target=candidate.Position
    end
    if target~=point.Position and farm.clearGroundSegment(root,target) then return target end
    return point.Position
end
function farm.passedWaypoint(route,root)
    local point,nextPoint=route.points[route.index],route.points[route.index+1]
    if not point or not nextPoint or point.Action==Enum.PathWaypointAction.Jump then return false end
    local delta=Vector3.new(nextPoint.Position.X-point.Position.X,0,nextPoint.Position.Z-point.Position.Z)
    local offset=Vector3.new(root.Position.X-point.Position.X,0,root.Position.Z-point.Position.Z)
    if delta.Magnitude<.1 then return false end
    local along=offset.X*delta.Unit.X+offset.Z*delta.Unit.Z
    local limit=delta.Magnitude+1.25
    if route.sentPoint then
        local aimed=Vector3.new(route.sentPoint.X-point.Position.X,0,route.sentPoint.Z-point.Position.Z)
        if aimed.Magnitude>.1 and aimed.Unit.X*delta.Unit.X+aimed.Unit.Z*delta.Unit.Z>.98 then
            limit=math.max(limit,aimed.X*delta.Unit.X+aimed.Z*delta.Unit.Z+1.25)
        end
    end
    return along>0 and along<=limit and (offset-delta.Unit*along).Magnitude<1.25
end
function farm.steerRoute(humanoid,root)
    local route=farm.route
    if not route or route.obstructed then return route and route.points[route.index] end
    local function horizontal(point) return Vector3.new(point.X-root.Position.X,0,point.Z-root.Position.Z).Magnitude end
    local point=route.points[route.index]
    -- Advance every render frame instead of waiting for the purchase/state
    -- tick. Keep the final target until the grounded arrival check completes.
    while point and route.index<#route.points and (horizontal(point.Position)<1.25 or farm.passedWaypoint(route,root))
        and math.abs(root.Position.Y-point.Position.Y)<6
        and (point.Action~=Enum.PathWaypointAction.Jump or humanoid.FloorMaterial==Enum.Material.Air) do
        route.index=route.index+1;point=route.points[route.index];route.best=nil;route.progressAt=os.clock()
    end
    if not point then return nil end
    local remaining=horizontal(point.Position)
    if not route.best or remaining<route.best-.25 then route.best=remaining;route.progressAt=os.clock() end
    if point.Action==Enum.PathWaypointAction.Jump and remaining<3.5 then humanoid.Jump=true;farm.jumpUntil=os.clock()+.25 end
    if route.targetIndex~=route.index or not route.targetRoot or (root.Position-route.targetRoot).Magnitude>=2
        or os.clock()>=(route.targetAt or 0) then
        farm.walkPoint=farm.movementTarget(route,root)
        route.targetIndex=route.index;route.targetRoot=root.Position;route.targetAt=os.clock()+.12
    end
    -- Native MoveTo and render steering must agree; a short intermediate
    -- MoveTo would brake while render steering is trying to keep sprinting.
    if farm.walkPoint and (not route.sentPoint or (route.sentPoint-farm.walkPoint).Magnitude>.1) then
        humanoid:MoveTo(farm.walkPoint);route.sentPoint=farm.walkPoint
    end
    return point
end
function farm.motionTick(humanoid,root)
    local route=farm.route
    local values=child(LocalPlayer,"PlayerValues")
    local stamina,maximum=readValue(values,"Stamina"),readValue(values,"StaminaMax")
    if not finite(maximum) or maximum<=0 then
        if os.clock()>=(farm.staminaMaxAt or 0) then
            farm.staminaMaxAt=os.clock()+.5
            local ok,value=pcall(function() return gameModule("CharacterManager"):GetValue("MaxStamina",LocalPlayer) end)
            farm.staminaMaximum=ok and finite(value) and value>0 and value or nil
        end
        maximum=farm.staminaMaximum
    end
    local ratio=finite(stamina) and finite(maximum) and maximum>0 and stamina/maximum or 0
    if ratio<=.2 then farm.staminaRest=true elseif ratio>=.45 then farm.staminaRest=false end
    local wanted=false
    if humanoid.FloorMaterial~=nil and humanoid.FloorMaterial~=Enum.Material.Air then farm.lastGroundAt=os.clock() end
    local onGround=farm.lastGroundAt and os.clock()-farm.lastGroundAt<.2
    local point=route and route.points and route.points[route.index]
    if route and farm.walkPoint and not UIS:GetFocusedTextBox() and not guiService.MenuIsOpen and not farm.retreat and not farm.exitWalking
        and not (farm.boxPosition and farm.boxPosition.phase=="mounting")
        and not farm.staminaRest and ratio>.2 and not runtime.consumableBusy and not runtime.refillBusy and not runtime.action and not reloadState.key
        and onGround and not (point and point.Action==Enum.PathWaypointAction.Jump) then
        local remaining=(Vector3.new(route.goal.X,0,route.goal.Z)-Vector3.new(root.Position.X,0,root.Position.Z)).Magnitude
        local ahead=Vector3.new(farm.walkPoint.X-root.Position.X,0,farm.walkPoint.Z-root.Position.Z).Magnitude
        if remaining>6 and ahead>(farm.sprintHeld and 2 or 5) then
            if os.clock()>=(farm.clearAt or 0) or not farm.clearPoint or (farm.clearPoint-farm.walkPoint).Magnitude>.1 then
                farm.clearPoint=farm.walkPoint
                farm.clearAt=os.clock()+.15;farm.sprintClear=farm.clearGroundSegment(root,farm.walkPoint)
            end
            wanted=farm.sprintClear==true and not farm.sprintThreat(root)
        end
    end
    farm.sprint(wanted)
    if not wanted and not farm.sprintHeld then farm.motionStatus=farm.retreat and "Backing up and replanning" or (farm.staminaRest and "Walking: preserving stamina" or "Walking / precise approach") end
end
function farm.sprintThreat(root)
    if os.clock()>=(farm.sprintThreatAt or 0) then
        farm.sprintThreatAt=os.clock()+.25;farm.sprintThreatPresent=false
        for _,zombie in ipairs(zombiesFolder:GetChildren()) do
            local humanoid=zombie:FindFirstChildOfClass("Humanoid")
            local body=child(zombie,"HumanoidRootPart") or child(zombie,"Torso") or child(zombie,"UpperTorso") or child(zombie,"Head")
            if humanoid and humanoid.Health>0 and body and (body.Position-root.Position).Magnitude<40 then farm.sprintThreatPresent=true;break end
        end
    end
    return farm.sprintThreatPresent
end
function farm.backoff(root,point,goal)
    local away=Vector3.new(root.Position.X-point.X,0,root.Position.Z-point.Z)
    if away.Magnitude<.1 then return end
    local destination=root.Position+away.Unit*2
    if farm.clearGroundSegment(root,destination) then
        farm.retreat={goal=goal,point=destination,untilAt=os.clock()+.65}
        farm.walkPoint=destination;farm.moving=true
    end
end
table.insert(runtime.connections,{Disconnect=function() farm.stopSprint() end})

function farm.purchaseSummary()
    local p=farm.purchaseObservation
    if not p then return "No request yet" end
    if p.state=="Request sent" then
        if p.event=="BuyHealing" then
            local _,tools=ownedTools()
            if tools[p.item] then p.state="Item received" end
        elseif p.object and p.object.Value~=p.before then
            if p.object.Value==true then p.state="Ownership observed"
            elseif finite(p.object.Value) and finite(p.before) and p.object.Value>p.before then p.state="Level increase observed" end
        end
    end
    return p.state..": "..tostring(p.item or p.name)
end
function farm.nextDrinkSummary(wave,minutes)
    if not farm.drinkEligible(wave,15) then
        return "Wave "..math.min(15,(math.floor(wave/5)+1)*5).." at 18:15"
    end
    if minutes>=360 and minutes<1080 then return "18:15" end
    local clock=farm.drinkClock
    local definitions=farm.drinkSlots(wave)
    if clock and clock.wave==wave then
        for _,definition in ipairs(definitions) do
            local slot=clock.slots[definition.key]
            if slot then
                for _,item in ipairs(farm.drinkItems) do
                    local entry=slot.items[item.name]
                    if not entry or entry.state=="pending" or entry.state=="inflight" then return slot.at.." batch pending" end
                end
            end
        end
    end
    for _,definition in ipairs(definitions) do
        if (minutes>=1080 and (definition.key~="evening" or minutes<definition.minutes))
            or (minutes<360 and definition.key~="evening" and minutes<definition.minutes) then return definition.at end
    end
    return "18:15"
end
farm.detailLabel=runtime.label(farmGroup,"",true)
connect(RunService.Heartbeat,function()
    if os.clock()<(farm.detailAt or 0) then return end
    farm.detailAt=os.clock()+1
    if not e.Autofarm then return end
    pcall(function()
        local wave=readValue(child(storage(),"Values"),"LocalWave") or 0
        local priority=farm.healthDue() and "Wave 28 health" or (farm.healingDue() and "Post-Handling healing" or "Normal upgrades")
        local purchase=farm.purchaseBudget
        local nextPurchase=purchase and (tostring(purchase.item).." ($"..math.ceil(purchase.cost)..")") or "Waiting for purchase selection"
        local text="Step: "..farm.webhookStep().."\nPurchase: "..nextPurchase.."\n"..farm.purchaseSummary().."\nCash reserve: $"..state.purchaseReserve().."\nPriority: "..priority.."\nNext drinks: "..farm.nextDrinkSummary(wave,game:GetService("Lighting"):GetMinutesAfterMidnight()).."\nMovement: "..(farm.motionStatus or "Idle")
        if farm.detailDisplayed~=text then
            local result=farm.detailLabel:SetText(text)
            if result~=false then farm.detailDisplayed=text end
        end
    end)
end)

-- Readiness must not depend on inventory refresh, purchase completion or pathfinding.
function farm.reconcileVote()
    local values=child(storage(),"Values")
    local wave=readValue(values,"LocalWave")
    local map=child(Workspace,"Map")
    local open=readValue(values,"Vote")==true
    local cycle=farm.voteCycle
    if not cycle or cycle.wave~=wave or cycle.map~=map or cycle.open~=open then
        farm.voteCycle={wave=wave,map=map,open=open}
        state.skipCycle=(state.skipCycle or 0)+1
        farm.voteMismatchAt=nil
    end
    local flag=child(LocalPlayer,"Voted")
    local count=readValue(values,"Voted")
    if not e.Autofarm or not farm.active or (farm.wave30VoteHeld and farm.wave30VoteHeld()) or not open or (readValue(values,"VotingTime") or 0)>0
        or not flag or flag.Value~=true or count~=0 or state.skipBusy then
        farm.voteMismatchAt=nil;return
    end
    -- An aggregate count of zero contradicts a local affirmative vote. Allow
    -- replication to catch up before clearing ONLY the local vote latch.
    farm.voteMismatchAt=farm.voteMismatchAt or os.clock()
    if os.clock()-farm.voteMismatchAt<10 or os.clock()-(state.skipLastAttempt or -100)<10 then return end
    flag.Value=false
    farm.voteMismatchAt=nil;farm.voteRepairs=(farm.voteRepairs or 0)+1
    state.skipLastResult=nil
end
function farm.voteStatus()
    local values=child(storage(),"Values")
    local wave=readValue(values,"LocalWave")
    if not e.Autofarm then return "Autofarm ready-up: off" end
    if not farm.active then return "Ready-up: waiting for autofarm initialization" end
    if (readValue(values,"LocalLives") or 1)<=0 then return "Ready-up: run ended" end
    if (readValue(values,"VotingTime") or 0)>0 then return "Ready-up: map voting in progress" end
    if farm.wave30VoteHeld and farm.wave30VoteHeld() then return "Ready-up: held for wave 30 reset; no vote to advance past night 30" end
    if readValue(values,"Vote")~=true then return "Ready-up: CLOSED by game (wave "..tostring(wave)..")" end
    if state.skipBusy then return "Ready-up: request pending for "..math.floor(os.clock()-(state.skipStartedAt or os.clock())).."s" end
    if readValue(LocalPlayer,"Voted")==true then
        local count=readValue(values,"Voted")
        if count==0 then return "Ready-up: local vote conflicts with 0 counted votes; checking before retry" end
        return "Ready-up: local vote recorded; counted votes "..tostring(count or "unknown")
    end
    if readValue(LocalPlayer,"Voted")~=false then return "Ready-up: player vote state unavailable" end
    if farm.recovering then return "Ready-up: held while returning from spawn to Ammo Box" end
    if state.skipLastWave==wave and state.skipLastError then return "Ready-up request failed: "..state.skipLastError end
    if state.jobs["Farm skip"] then return "Ready-up: vote dispatch queued/in flight" end
    if state.skipLastWave==wave and state.skipLastResult=="not acknowledged" then return "Ready-up: game did not acknowledge vote; retrying" end
    if farm.positionReached or (finite(wave) and wave>5) then return "Ready-up: eligible; automatic vote scheduled" end
    if wave==5 then return "Ready-up: holding wave 5 until first Ammo Box arrival" end
    return "Ready-up: early-wave sequence controls this vote"
end
function farm.voteMonitor()
    if not runtime.active then return end
    farm.reconcileVote()
    if e.Autofarm and farm.active and farm.supported() then
        local _,humanoid=alive()
        if humanoid then
            local ok=pcall(farm.ongoingSkip)
            farm.voteError=not ok and "Ready-up: scheduler failed; retrying" or nil
        end
    end
    local message=farm.voteError or farm.voteStatus()
    if farm.voteLabel and farm.voteDisplayed~=message then
        local ok,result=pcall(function() return farm.voteLabel:SetText(message) end)
        if ok and result~=false then farm.voteDisplayed=message end
    end
    if e.Autofarm and state.readyStatus and state.readyText~=message then
        local ok,result=pcall(function() return state.readyStatus:SetText(message) end)
        if ok and result~=false then state.readyText=message end
    end
end
farm.voteLabel=runtime.label(farmGroup,"Ready-up: off",true)
connect(RunService.Heartbeat,function()
    if os.clock()<(farm.voteMonitorAt or 0) then return end
    farm.voteMonitorAt=os.clock()+1
    local ok=pcall(farm.voteMonitor)
    if not ok and farm.voteLabel then pcall(function() farm.voteLabel:SetText("Ready-up: unable to read live vote state") end) end
end)

-- Bounded, local evidence only. The client dump cannot identify a server kill reason.
farm.diagnostics={samples={},deaths={}}
function farm.deathSample(humanoid)
    local character=LocalPlayer.Character;local root=child(character,"HumanoidRootPart")
    local function vector(value) return value and {value.X,value.Y,value.Z} or nil end
    local values=child(storage(),"Values")
    local sample={at=os.clock(),wave=readValue(values,"LocalWave"),minutes=game:GetService("Lighting"):GetMinutesAfterMidnight(),
        map=farm.mapName(),step=farm.stage,health=humanoid and humanoid.Health,
        position=vector(root and root.Position),velocity=vector(root and root.AssemblyLinearVelocity),
        floor=humanoid and tostring(humanoid.FloorMaterial),state=humanoid and tostring(humanoid:GetState()),
        recovering=farm.recovering,positionPhase=farm.boxPosition and farm.boxPosition.phase,moving=farm.moving==true,
        drink=runtime.consumables.lastItem,target=runtime.targetName,targetTier=runtime.targetTier,
        nearbyBlocked=runtime.targetBlocked,lastShotRedirectAge=runtime.lastRedirect and os.clock()-runtime.lastRedirect,
        exit=farm.exitTransit and farm.exitTransit.which,nativeDamageCounter=farm.diagnostics.damageValue}
    if root then
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={character};params.RespectCanCollide=true
        local hit=Workspace:Raycast(root.Position,Vector3.new(0,-8,0),params)
        if hit then sample.support=hit.Instance and hit.Instance.Name;sample.floorDistance=root.Position.Y-hit.Position.Y end
    end
    return sample
end
function farm.recordDeath(humanoid)
    local d=farm.diagnostics
    if not e.Autofarm or not farm.active or d.logged or humanoid~=d.humanoid then return end
    d.logged=true
    local ok,sample=pcall(farm.deathSample,humanoid)
    local history={};for _,record in ipairs(d.samples) do table.insert(history,record) end
    if ok then table.insert(history,sample) end
    local planned=farm.resetAttempt and farm.resetAttempt.humanoid==humanoid and farm.resetAttempt.invoked==true
    local record={previousHealth=d.lastPositive,serverCause="Not available in client dump",scheduledReset=planned or false,samples=history}
    table.insert(d.deaths,record);if #d.deaths>5 then table.remove(d.deaths,1) end
    d.message="Last death: HP "..tostring(d.lastPositive or "?").." → 0. "..(planned and "Wave 30 reset was requested." or "Cause unconfirmed.")
    if type(writefile)=="function" then
        local saved=pcall(function() writefile("CombatAssistantDeaths.json",HttpService:JSONEncode({version=1,deaths=d.deaths})) end)
        d.message=d.message..(saved and " Diagnostic saved." or " Diagnostic remains in memory.")
    end
    if runtime.cancelInstantConsumables then runtime.cancelInstantConsumables() end
    farm.cancelWalk()
end
function farm.deathMonitor()
    local d=farm.diagnostics
    local character=LocalPlayer.Character;local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    if d.humanoid~=humanoid then
        for _,connection in ipairs(d.connections or {}) do connection:Disconnect() end
        d.connections={};d.humanoid=humanoid;d.samples={};d.logged=false;d.lastPositive=humanoid and humanoid.Health
        if humanoid then
            if humanoid.HealthChanged then table.insert(d.connections,humanoid.HealthChanged:Connect(function(value)
                if value>0 then d.lastPositive=value;d.logged=false
                else farm.recordDeath(humanoid) end
            end)) end
            if humanoid.Died then table.insert(d.connections,humanoid.Died:Connect(function() farm.recordDeath(humanoid) end)) end
        end
    end
    local damage=child(child(storage(),"RemoteEvents"),"SendPlayerDamage")
    if damage~=d.damageRemote then
        if d.damageConnection then d.damageConnection:Disconnect() end
        d.damageRemote=damage;d.damageValue=nil;d.damageConnection=nil
        if damage and damage.OnClientEvent then d.damageConnection=damage.OnClientEvent:Connect(function(value)
            d.damageValue=finite(value) and value or nil
        end) end
    end
    if e.Autofarm and farm.active and humanoid then
        if humanoid.Health<=0 then farm.recordDeath(humanoid)
        else
            local ok,sample=pcall(farm.deathSample,humanoid)
            if ok then table.insert(d.samples,sample);if #d.samples>48 then table.remove(d.samples,1) end end
        end
    end
    if d.message and d.message~=d.displayed then
        local ok,result=pcall(function() return d.label:SetText(d.message) end)
        if ok and result~=false then d.displayed=d.message end
    end
end
farm.diagnostics.label=runtime.label(farmGroup,"Death diagnostic: waiting for evidence.",true)
farmGroup:AddButton({Text="Copy death diagnostic",Func=function()
    local d=farm.diagnostics
    if #d.deaths==0 then d.message="No autofarm death recorded yet.";return end
    local ok=pcall(function()
        assert(type(setclipboard)=="function","Clipboard unavailable")
        setclipboard(HttpService:JSONEncode({version=1,deaths=d.deaths}))
    end)
    d.message=ok and "Death diagnostic copied." or "Clipboard unavailable; use CombatAssistantDeaths.json."
end})
connect(RunService.Heartbeat,function()
    local d=farm.diagnostics
    if os.clock()<(d.nextAt or 0) then return end;d.nextAt=os.clock()+.25
    pcall(farm.deathMonitor)
end)
table.insert(runtime.connections,{Disconnect=function()
    local d=farm.diagnostics
    for _,connection in ipairs(d.connections or {}) do pcall(function() connection:Disconnect() end) end
    d.connections={}
    if d.damageConnection then pcall(function() d.damageConnection:Disconnect() end);d.damageConnection=nil end
end})

-- End-of-run character resets do not change the game clock or shop lives.
function farm.wave30VoteHeld()
    if not e.Autofarm or not farm.active or not farm.supported() then return false end
    local wave=readValue(child(storage(),"Values"),"LocalWave")
    if not finite(wave) then return false end
    local minutes=game:GetService("Lighting"):GetMinutesAfterMidnight()
    if wave==30 and (minutes>=1080 or minutes<360) then farm.wave30NightReached=true end
    return wave==30 and farm.wave30NightReached==true
end
function farm.wave30ResetWindow()
    if not runtime.active or not e.Autofarm or not farm.active or not farm.supported() then return false end
    local values=child(storage(),"Values")
    if readValue(values,"LocalWave")~=30 or (readValue(values,"LocalLives") or 1)<=0 or (readValue(values,"VotingTime") or 0)>0 then return false end
    local minutes=game:GetService("Lighting"):GetMinutesAfterMidnight()
    return finite(minutes) and minutes>=240 and minutes<360
end
function farm.confirmWave30Death(attempt)
    if attempt.confirmed then return end
    attempt.confirmed=true;attempt.phase="death confirmed"
    -- Mark recovery even if this game's respawn reuses the same Character object.
    farm.resumeCharacter()
    farm.resetMessage="Wave 30 reset: death confirmed; recovering to Ammo Box."
end
function farm.wave30ResetTick()
    if not runtime.active or not e.Autofarm or not farm.active or not farm.supported() then return false end
    local values=child(storage(),"Values")
    if (readValue(values,"VotingTime") or 0)>0 or (readValue(values,"LocalLives") or 1)<=0 then return false end
    farm.wave30VoteHeld()
    local character=LocalPlayer.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    local attempt=farm.resetAttempt
    if attempt and attempt.character==character and attempt.humanoid==humanoid then
        if humanoid.Health<=0 then farm.confirmWave30Death(attempt);return true end
        if not attempt.confirmed then
            if attempt.phase=="queued" then return true end
            farm.resetMessage=attempt.phase=="failed" and "Wave 30 reset failed; no repeated requests for this life."
                or "Wave 30 reset: waiting for death confirmation"..(os.clock()-attempt.at>=8 and " (not confirmed; no duplicate request)." or ".")
            return false
        end
    end
    if not farm.wave30ResetWindow() then return false end
    if not humanoid or humanoid.Health<=0 then farm.resetMessage="Wave 30 reset: waiting for respawn.";return false end
    if farm.recovering then farm.resetMessage="Wave 30 reset: recovering to Ammo Box before next reset.";return false end
    if not farm.positionReached and farm.stage<6 then farm.resetMessage="Wave 30 reset: waiting for initial Ammo Box arrival.";return false end
    local run,map=farm.runId,child(Workspace,"Map")
    attempt={character=character,humanoid=humanoid,at=os.clock(),phase="queued"}
    farm.resetAttempt=attempt;farm.resetCount=(farm.resetCount or 0)+1
    farm.cancelWalk();releaseHeld()
    farm.resetMessage="Wave 30 reset queued at 04:00 or later; attempt "..farm.resetCount.."."
    task.spawn(function()
        if farm.resetAttempt~=attempt or farm.runId~=run or LocalPlayer.Character~=character or child(Workspace,"Map")~=map
            or not farm.wave30ResetWindow() or farm.recovering or humanoid.Health<=0 then
            if farm.resetAttempt==attempt then farm.resetAttempt=nil;farm.resetMessage="Wave 30 reset cancelled before dispatch." end
            return
        end
        attempt.phase="requested";attempt.invoked=true
        -- One ordinary Humanoid death request per life; never forge remote names,
        -- life counts, teleport positions, or repeated joint-breaking calls.
        local ok=pcall(function() humanoid.Health=0 end)
        if not ok then attempt.phase="failed";farm.resetMessage="Wave 30 reset failed; no repeated requests for this life."
        elseif humanoid.Health<=0 then farm.confirmWave30Death(attempt)
        else farm.resetMessage="Wave 30 reset: requested; waiting for death confirmation." end
    end)
    return true
end
function farm.wave30ResetStatus()
    local values=child(storage(),"Values")
    local wave=readValue(values,"LocalWave")
    if not e.Autofarm or not farm.active then return "Wave 30 reset: off" end
    if (readValue(values,"LocalLives") or 1)<=0 then return "Wave 30 reset: run ended; waiting for next map." end
    if wave==30 then
        if farm.resetMessage then return farm.resetMessage end
        return farm.wave30VoteHeld() and "Wave 30: farming until 04:00; advancing vote held." or "Wave 30: ready to start night; reset scheduled for 04:00."
    end
    if finite(wave) and wave>30 then
        return farm.recovering and "Wave 30 reset window passed; recovering before normal auto-skip resumes."
            or "Wave 30 reset window passed; normal auto-skip resumed."
    end
    return "Wave 30 reset: scheduled for 04:00; repeat after Ammo Box recovery."
end
farm.resetLabel=runtime.label(farmGroup,"Wave 30 reset: scheduled for 04:00",true)
connect(RunService.Heartbeat,function()
    if os.clock()<(farm.resetTickAt or 0) then return end
    farm.resetTickAt=os.clock()+.1
    local ok=pcall(farm.wave30ResetTick)
    if not ok then farm.resetMessage="Wave 30 reset check failed; will check again." end
    local message=farm.wave30ResetStatus()
    if message~=farm.resetDisplayed then
        local shown,result=pcall(function() return farm.resetLabel:SetText(message) end)
        if shown and result~=false then farm.resetDisplayed=message end
    end
end)

function state.upgradeShopMoney()
    if not e.AutoShopMoney or e.Autofarm or readValue(LocalPlayer,"FirstWave")~=false then return false end
    if e.AutoC96 and state.farm and not state.farm.unlimitedOwned() then return false end
    local owned=child(child(storage(),"Upgrades"),"Shop")
    if readValue(owned,"UPurchased")~=true then return false end
    return state.upgradeShop("Shop",true,owned,availableMoney(),{MoneyUpgrade=true})
end
function state.spending(supportOnly)
    if state.spendingBusy or os.clock()<(state.spendAt or 0) then return end
    local _,humanoid=alive();if not humanoid or runtime.consumableBusy or runtime.refillBusy then return end
    state.spendAt=os.clock()+e.ActionInterval
    if not supportOnly and e.AutoC96 and state.farm then if not state.farm.upgradeC96(false) then return end end
    local actions={}
    if not supportOnly and e.AutoShopMoney and not e.Autofarm then table.insert(actions,{name="Shop Money",run=state.upgradeShopMoney}) end
    local function selections(enabledKey,selectedKey,fn)
        if e[enabledKey] then
            for name,on in pairs(e[selectedKey]) do
                if on then table.insert(actions,{name=name,run=function()
                    if e[enabledKey] and e[selectedKey][name] then return fn(name) end
                    return false
                end}) end
            end
        end
    end
    if not supportOnly then selections("AutoPurchase","Purchases",state.purchase) end
    selections("AutoRepair","Repairs",state.repair)
    selections("AutoReplenish","Replenish",state.repair)
    for index=1,(supportOnly and 0 or 3) do
        selections("AutoUpgrade"..index,"Upgrades"..index,function(name) return state.upgradeTool(e["Tool"..index],name) end)
    end
    table.sort(actions,function(a,b) return a.name<b.name end)
    if #actions==0 then return end
    state.spendingBusy=true
    local epoch=state.epoch or 0
    task.spawn(function()
        local ok,err=pcall(function()
            for offset=1,#actions do
                if not runtime.active or (state.epoch or 0)~=epoch then return end
                local index=((state.spendIndex or 0)+offset-1)%#actions+1
                if actions[index].run() then state.spendIndex=index;return end
            end
        end)
        state.spendingBusy=false
        if not ok then notice("Automatic spending paused: "..tostring(err)) end
    end)
end

connect(UIS.InputBegan,function(input,processed)
    if processed or UIS:GetFocusedTextBox() then return end
    if input.KeyCode==Enum.KeyCode.End then state.stop() return end
end)
connect(RunService.Heartbeat,function()
    if os.clock()<state.next then return end
    state.next=os.clock()+.1
    for _,fn in ipairs({state.hipADSStep,state.fireMode,state.automation,state.visuals}) do
        local ok,err=pcall(fn);if not ok then notice(err) end
    end
    if os.clock()>=state.catalogAt then state.catalogAt=os.clock()+3;local ok,err=pcall(state.refresh);if not ok then notice(err) end end
    if state.displayed~=state.message then state.displayed=state.message;state.status:SetText(state.message) end
end)
local op={wrappers={},hits={},last="No modifier requests sent",any=false}
runtime.op=op
local function on(id) return runtime.active and e["OP"..id]==true end
local function copy(t) local n={} for k,v in pairs(t or {}) do n[k]=v end return n end
local function currentTool() local c=LocalPlayer.Character;return c and c:FindFirstChildOfClass("Tool") end
local function owned(tool) return tool and (tool.Parent==LocalPlayer.Character or tool.Parent==child(LocalPlayer,"Backpack")) end
local function mark(id,text) op.hits[id]=(op.hits[id] or 0)+1;op.last=text.."; server result unverified" end
local function modsFor(tool)
    local saved=_G.ClientPlayerMods and _G.ClientPlayerMods[tool.Name]
    return saved and rangeMods and rangeMods:GetModStats(saved) or {}
end
local function wrap(object,key,factory)
    if not object or type(object[key])~="function" then return end
    local original=object[key];local wrapper=factory(original)
    object[key]=wrapper;table.insert(op.wrappers,{object=object,key=key,original=original,wrapper=wrapper})
end
function op.install()
    if op.installed then return end
    op.installed=true
    wrap(rangeManager,"GetMulti",function(original) return function(self,key,player,context)
        local value=original(self,key,player,context)
        if player~=LocalPlayer or not finite(value) or key~="ProjectileSpeed" then return value end
        local tool=context and context.Tool
        if owned(tool) then
            if on(17) and key=="ProjectileSpeed" then return value*e.ProjectileMultiplier end
        end
        return value
    end end)

end
function op.cleanup()
    for i=#op.wrappers,1,-1 do local r=op.wrappers[i];if r.object[r.key]==r.wrapper then r.object[r.key]=r.original end end
    op.wrappers={};op.installed=false
end
function op.safePoint(point,radius)
    if typeof(point)~="Vector3" or not finite(radius) or radius<0 then return false end
    for _,player in ipairs(Players:GetPlayers()) do
        local root=child(player.Character,"HumanoidRootPart")
        if root and (root.Position-point).Magnitude<=math.max(50,radius+5) then return false end
    end
    local root=child(LocalPlayer.Character,"HumanoidRootPart")
    return root~=nil and (root.Position-point).Magnitude>math.max(50,radius+5)
end
function op.overrideHits(kind,hits,tool,tags)
    if not config.HeadshotConversion or not owned(tool) or not child(tool,"GunScript") or type(hits)~="table" then return hits end
    if tags and tags.IgnoreHeadshot or child(child(tool,"OtherValues"),"IgnoreHeadshot") then
        op.last="Hit Override: weapon disables headshot damage";return hits
    end
    local function convert(hit)
        if type(hit)~="table" then return hit end
        local head=runtime.headForHit(hit[1])
        if not head or typeof(head.Position)~="Vector3" or not finite(head.Position.Magnitude) then return hit end
        local changed=copy(hit);changed[1]=head;changed[2]=head.Position
        runtime.lastHeadshot=os.clock()
        op.last="Head hit requested; server damage unverified"
        return changed
    end
    if kind=="ProjectileImpact" then return convert(hits) end
    if kind~="WeaponAttack" then return hits end
    local converted=copy(hits)
    for index,hit in pairs(hits) do converted[index]=convert(hit) end
    return converted
end

function op.namecall(object,method,args)
    local events=child(storage(),"RemoteEvents")
    if method~="FireServer" or not events or object.Parent~=events then return end
    local name=object.Name
    if name=="PacketRemote" and type(args[1])=="table" then
        local data=copy(args[1]);local changed=false
        for _,kind in ipairs({"WeaponAttack","ProjectileImpact"}) do
            if type(data[kind])=="table" then
                local entries=copy(data[kind])
                for i,entry in pairs(entries) do
                    if type(entry)=="table" then
                        local tool=typeof(entry[1])=="Instance" and entry[1] or currentTool()
                        if owned(tool) and (entry[1]==tool or entry[1]==tool.Name) then
                            local shot=copy(entry)
                            shot[2]=op.overrideHits(kind,entry[2],tool,entry[3])
                            entries[i]=shot;changed=true
                        end
                    end
                end
                data[kind]=entries
            end
        end
        if changed then args[1]=data;return args end
    elseif name=="RemoteFireMelee" and (owned(args[1]) or args[1]=="Melee") and type(args[2])=="table" then
        local knife=args[1]=="Melee"
        local tool=not knife and args[1] or nil;local hits={};local seen={}
        for _,hit in ipairs(args[2]) do
            if type(hit)=="table" then local nextHit=copy(hit);table.insert(hits,nextHit);if hit[1] then seen[hit[1].Parent]=true end end
        end
        if e.MeleeAura and (knife or child(tool,"MeleeScript")) then
            local root=child(LocalPlayer.Character,"HumanoidRootPart");local base=knife and rangeManager:GetValue("MeleeRange",LocalPlayer) or readValue(child(tool,"CurrentValues"),"Range")
            if root and finite(base) then
                local range=base
                if not knife then
                    local context={Tool=tool,ModStats=modsFor(tool)}
                    range=(base+rangeManager:GetAdded("Range",LocalPlayer,context))*rangeManager:GetMulti("Range",LocalPlayer,context)
                end
                range=math.min(100,range)
                for _,target in ipairs(state.actionTargets(root.Position,range,true)) do
                    if #hits>=20 then break end
                    if not seen[target.model] then table.insert(hits,{target.part,{}});seen[target.model]=true end
                end
                mark(16,"Melee sweep hit list modified")
            end
        end
        args[2]=hits;return args
    end
end
function op.step()
    op.any=e.MeleeAura==true or config.HeadshotConversion==true;for _,definition in ipairs(runtime.opDefinitions) do if on(definition[1]) then op.any=true end end
    if not op.any then
        if op.installed then op.cleanup() end
        return
    end
    op.install()

end
function op.detonate()
    if not on(6) or os.clock()<(op.canAt or 0) then return end
    op.canAt=os.clock()+1
    local root=child(LocalPlayer.Character,"HumanoidRootPart");if not root then return end
    local best,distance
    for _,object in ipairs(Workspace:GetDescendants()) do
        if object.Name=="DetonateCan" and object:IsA("RemoteEvent") then
            local model=object.Parent;local creator=readValue(model,"Creator");local anchor=model:IsA("Model") and model.PrimaryPart
            local recognized=model.Name=="GasCan" or model.Name=="PropaneCan"
            local radius=readValue(child(model,"CurrentValues"),"Radius") or readValue(model,"Radius")
            if recognized and creator==LocalPlayer and anchor and finite(radius) and op.safePoint(anchor.Position,radius) then
                local d=(anchor.Position-root.Position).Magnitude;if not distance or d<distance then best=object;distance=d end
            end
        end
    end
    if best then best:FireServer();mark(6,"Owned can detonation requested") else op.last="No owned can with known radius and safe player clearance" end
end
local utilities=runtime.extensionTabs.Items:AddRightGroupbox("Throwable utilities")
control(utilities,"OP5","Predict throwable targets")
local canToggle=control(utilities,"OP6","Detonate owned can [J]")
canToggle:AddKeyPicker("OPCanHotkey",{Default=e.OPCanKey,NoUI=true,Mode="Toggle",Modes={"Toggle"},SyncToggleState=false,Text="Detonate owned can",ChangedCallback=function() if ui.OPCanKey then e.OPCanKey=ui.OPCanKey.Value end end})
ui.OPCanKey=canToggle.Addons[#canToggle.Addons]
control(weapons,"OP17","Projectile velocity multiplier (PVM)")
control(weapons,"ProjectileMultiplier","Projectile velocity (1–3x)")
runtime.label(weapons,"Projectile weapons only. Re-equip if the gun caches its values. Server acceptance remains unverified.",true)
control(priority,"OP2","Armour-aware aim points")
runtime.label(priority,"Skips armour and shield intersections. Hit Override independently requests head damage; server acceptance is unverified.",true)
control(weapons,"OP3","Hot Harmony heat optimization")
runtime.label(weapons,"Needs Hot Harmony + triggerbot. Keeps heat above 50% when possible; real overheating still waits for zero.",true)
connect(UIS.InputBegan,function(input,processed)
    if processed or UIS:GetFocusedTextBox() or not on(6) then return end
    local key=e.OPCanKey
    if input.KeyCode and input.KeyCode.Name==key then local ok,err=pcall(op.detonate);if not ok then op.last=tostring(err) end end
end)
connect(RunService.Heartbeat,function()
    if os.clock()<(op.next or 0) then return end;op.next=os.clock()+.1
    local ok,err=pcall(op.step);if not ok then op.last="Weapon modifier error: "..tostring(err) end
end)

control(utilities,"OPPredictionSeconds","Throw prediction seconds")
function state.cleanup()
    state.restoreHipADS()
    if state.farm then state.farm.stop() end
    if runtime.op then runtime.op.cleanup() end
    state.epoch=(state.epoch or 0)+1
    if runtime.cancelAction then runtime.cancelAction() end
    restoreFireMode();clearVisuals()
    for key,value in pairs(e) do if type(value)=="boolean" then e[key]=false end end
end
end
runtime.initializeExtensions()
runtime.initializeExtensions = nil

task.defer(function()
    if not runtime.active then return end
    profileAction(function() refreshProfiles() end)
    profileAction(function()
        diskReady()
        if not isfile(autoloadPath) then return end
        local data = HttpService:JSONDecode(readfile(autoloadPath))
        assert(type(data) == "table" and data.Version == 1 and type(data.Enabled) == "boolean", "Invalid autoload file.")
        if not data.Enabled then return end
        local name = cleanName(data.Name)
        assert(type(data.HideMenu) == "boolean", "Invalid autoload menu setting.")
        loadProfile(name)
        hideOnAutoload = data.HideMenu
        hideAutoloadToggle:SetValue(data.HideMenu)
        setAutoloadLabel(name)
        selectedProfile = name
        profileDropdown:SetValue(name)
        if hideOnAutoload then setMenuVisible(false) end
        profileNotice("Autoloaded: " .. name)
    end)
end)
