-- Steal Or Die helper v8. Execute the entire file as raw Luau.
-- Home toggles the panel. Touch/controller: select the HELPER button.
-- Client/shared dump reviewed October 7, 2026. No downloaded libraries.
-- Only loaded objects can be tracked. Travel estimates are rough straight-line estimates.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Run = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local Tags = game:GetService("CollectionService")
local player = assert(Players.LocalPlayer, "Run on the client")
local playerGui = player:WaitForChild("PlayerGui")
local GUI_NAME = "SOD_ClientHelper"
for _, old in ipairs(playerGui:GetChildren()) do
    if old.Name == GUI_NAME then
        local sync, event = old:FindFirstChild("StopHelperSync"), old:FindFirstChild("StopHelper")
        if sync and sync:IsA("BindableFunction") then
            local ok,result
            for attempt=1,3 do
                ok,result=pcall(function() return sync:Invoke() end)
                if ok and result==true and not old.Parent then break end
                if attempt<3 then task.wait(0.05) end
            end
            assert(ok and result==true and not old.Parent,"Previous helper cleanup incomplete; loading stopped")
        elseif event and event:IsA("BindableEvent") then
            event:Fire()
            local deadline = os.clock() + 3
            while old.Parent and os.clock() < deadline do task.wait() end
            if old.Parent then old:Destroy(); task.wait() end
        else old:Destroy(); task.wait() end
        assert(not old.Parent, "Previous helper still exists")
    end
end
local stopped, dirty, cleanupComplete, cleaning = false, true, false, false
local connections, watchers, candidates, markers, modules = {}, {}, {}, {}, {}
local groups = {inventory={}, map={}}
local jobs, bindings, created = {}, {}, {}
local gui, restoreCamera, releaseMouse, removeMarker
local initializing = true
local options = {Loot=true, Enemies=true, Exits=true, Players=true, Hiding=false,
    Alerts=true, AutoGrab=false, ThirdPerson=false, ExtractFocus=false}
local minimumValue, lootOrder, cameraDistance, shoulder = 0, "Value / kg", 8, 1.4
local trackedPlayer, lastSeen, huntTargets = nil, nil, {}
local lastGrab, message, messageUntil, lastWarning = -math.huge, "", 0, -math.huge
local roundIdentity, exitWasOpen, deadlineWarned = nil, false, {}
local cleanup
local function initialize()
    local refresh
    local C = {bg=Color3.fromRGB(14,18,26), card=Color3.fromRGB(23,30,42), line=Color3.fromRGB(46,59,77),
        text=Color3.fromRGB(232,238,246), muted=Color3.fromRGB(149,165,187), accent=Color3.fromRGB(87,218,203),
        danger=Color3.fromRGB(255,108,123), amber=Color3.fromRGB(250,202,113), blue=Color3.fromRGB(121,180,255)}
    local rarityColors = {Common=C.text, Uncommon=Color3.fromRGB(125,208,141), Rare=Color3.fromRGB(189,149,247),
        Mythic=C.danger, Legendary=C.amber, Secret=Color3.fromRGB(243,169,245)}
    local menuAttrs = {"InventoryOpen","ShopOpen","VoteOpen","AdminOpen","SettingsOpen","SkillTreeOpen",
        "MouseFree","AbilityMenuOpen","EmoteWheelOpen","LockerOpen","TradeOpen","TradePrompt","CaseOpening",
        "DuelOpen","DuelPrompt","ResultsOpen","TipsOpen","RebirthOpen","RebirthMoment","InMenu","VRMenuLock",
        "PadMenuOpen","MobileMenuOpen","ReviveOpen"}
    local function num(v: any) return type(v)=="number" and v==v and math.abs(v)<math.huge and v or nil end
    local K = {UpdateInterval=0.2, ReconcileInterval=6, DependencyInterval=0.5, DependencyAttempts=8,
        LootRange=180, AdviceRange=120, HidingRange=120, LootLabels=5, AdviceItems=3, Highlights=24,
        ContactRange=60, UnknownHeightRange=15, LootRiskRange=35, StairRange=35, LastSeenLife=5,
        GrabCooldown=0.5, GrabMaxBackoff=2, GrabVertical=7, GrabClose=2.5,
        CameraRadius=0.4, CameraMargin=0.15, CameraMinimum=1.6, ViewmodelTail=0.6,
        DefaultCapacity=15, DefaultExtractHold=0.5, ReminderLead=20, ReminderMaximum=120, ToastLife=6}
    local names8={"AHEAD","FRONT-RIGHT","RIGHT","BACK-RIGHT","BEHIND","BACK-LEFT","LEFT","FRONT-LEFT"}
    local carryRank={BAG=1,HANDS=2,UNKNOWN=3,FULL=4}
    local emptyBag={items={}}
    local cache={bagDirty=true,partsDirty=true,body={},arms={},pending={},tagSets={},tagsDirty=true,
        base=nil,height=nil,zones={},inventoryItems={},candidateFailures=setmetatable({},{__mode="k"})}
    local moduleStatus, buttonActions, systemErrors = {}, {}, {}
    local messagePriority, nextDependency, grabStatus = 0, 0, "OFF"
    local manualGrabAt, nextGrabAt, grabAttempt = -math.huge, -math.huge, nil
    local onModulesChanged, pollDependencies, syncButtons
    local function notice(text,priority)
        priority=priority or 1
        if os.clock()<messageUntil and priority<messagePriority then return end
        message,messageUntil,messagePriority=text,os.clock()+K.ToastLife,priority
    end
    local function set(object,key,value) if object[key]~=value then object[key]=value end end
    local function report(name,err)
        systemErrors[name]=tostring(err)
        if os.clock()-lastWarning>5 then
            lastWarning=os.clock(); notice(name.." unavailable; see Output",3)
            warn("[SOD Helper] "..name..": "..tostring(err))
        end
    end
    local function connect(signal, fn, list)
        local c=signal:Connect(function(...)
            if stopped then return end
            local ok,err=pcall(fn,...); if not ok then report("Listener",err) end
        end)
        table.insert(list or connections,c)
        return c
    end
    local function disconnect(list) for _, c in ipairs(list) do c:Disconnect() end; table.clear(list) end
    local specs={
        {name="GameConfig",parent="Shared"},{name="EntityConfig",parent="Shared"},{name="VKeys",parent="Shared"},
        {name="UIHook",parent="Shared"},{name="StoreConfig",parent="Shared"},
        {name="IntroState",parent="Player"},{name="CourtCam",parent="Player"},
        {name="EmoteCam",parent="Player"},{name="VRCore",parent="Player"}}
    local safetyModules={"VKeys","IntroState","CourtCam","EmoteCam","VRCore"}
    local function startJob(fn)
        local job={}; jobs[job]=true
        job.thread=task.spawn(function()
            local ok,err=pcall(fn)
            jobs[job]=nil
            if not ok and not stopped then report("Dependency loader",err) end
        end)
    end
    local function ready(name)
        local state=moduleStatus[name]
        return modules[name]~=nil and state and state.state=="ready"
    end
    pollDependencies=function(force)
        local now=os.clock()
        if not force and now<nextDependency then return end
        nextDependency=now+K.DependencyInterval
        for _,spec in ipairs(specs) do
            local parent=spec.parent=="Shared" and RS or player:FindFirstChild("PlayerScripts")
            local object=parent and parent:FindFirstChild(spec.name)
            local state=moduleStatus[spec.name]
            if not state or state.object~=object then
                state={object=object,attempts=0,nextTry=0,state="waiting"}; moduleStatus[spec.name]=state
                modules[spec.name]=nil
            end
            if force and not state.loading and not modules[spec.name] then state.attempts,state.nextTry=0,0 end
            if not modules[spec.name] and not state.loading and now>=state.nextTry and state.attempts<K.DependencyAttempts then
                if object and object:IsA("ModuleScript") then
                    state.loading,state.state,state.attempts=true,"loading",state.attempts+1
                    startJob(function()
                        local ok,result=pcall(require,object)
                        if stopped or moduleStatus[spec.name]~=state then return end
                        state.loading=false
                        if ok and type(result)=="table" then
                            modules[spec.name],state.state,state.error=result,"ready",nil
                            cache.bagDirty=true
                            if onModulesChanged then onModulesChanged(spec.name) end
                        else
                            state.state,state.error="failed",tostring(result)
                            state.nextTry=os.clock()+math.min(10,2^(state.attempts-1))
                        end
                    end)
                else state.state="waiting" end
            end
        end
    end
    local function itemConfig(key) local m=modules.GameConfig; return m and m.Items and m.Items[key] end
    local function displayName(key) local c=itemConfig(key); return c and c.displayName or tostring(key or "Unknown item") end
    local function anchor(target)
        if not target then return end
        if target:IsA("BasePart") then return target end
        if target:IsA("Model") then return target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart",true) end
        return nil
    end
    local function menuOpen()
        local keys=modules.VKeys
        if keys and type(keys.menuOpen)=="function" then
            local ok,result=pcall(keys.menuOpen)
            if not ok then return true end
            if result==true then return true end
        end
        for _, name in ipairs(menuAttrs) do if player:GetAttribute(name)==true then return true end end
        return Input:GetFocusedTextBox()~=nil
    end
    local function moduleActive(name,field)
        local m=modules[name]; local v=m and m[field]
        if type(v)=="function" then
            local ok,result=pcall(v)
            if not ok then
                local state=moduleStatus[name]; if state then state.error=tostring(result) end
                return true -- A failed safety query blocks overrides/actions.
            end
            return result==true
        end
        return v==true or type(v)=="number" and v>0.001
    end
    local function direction(position)
        local camera=workspace.CurrentCamera; if not camera then return "" end
        local offset=position-(cache.directionOrigin or camera.CFrame.Position)
        if Vector3.new(offset.X,0,offset.Z).Magnitude<1 then return "HERE" end
        local look=cache.directionLook or camera.CFrame.LookVector; local forward=Vector3.new(look.X,0,look.Z)
        if forward.Magnitude<0.001 then return "" end
        forward=forward.Unit
        local right=forward:Cross(Vector3.yAxis)
        return names8[math.floor(math.atan2(offset:Dot(right),offset:Dot(forward))/(math.pi/4)+0.5)%8+1]
    end
    local function floorDifference(a,b)
        local base,height=cache.base,cache.height
        if base and height and height>0 then return math.floor((b.Y-base-0.5)/height)-math.floor((a.Y-base-0.5)/height),true end
        if math.abs(b.Y-a.Y)>=7 then return b.Y>a.Y and 1 or -1,false end
        return 0,false
    end
    local function floorText(a,b)
        local diff,exact=floorDifference(a,b)
        if diff==0 then return exact and "SAME FLOOR" or "SIMILAR HEIGHT" end
        return exact and string.format("%d FLOOR%s %s",math.abs(diff),math.abs(diff)==1 and "" or "S",diff>0 and "ABOVE" or "BELOW")
            or (diff>0 and "ABOVE" or "BELOW")
    end
    local sightParams=RaycastParams.new()
    sightParams.FilterType=Enum.RaycastFilterType.Exclude
    local cameraParams=RaycastParams.new()
    cameraParams.FilterType=Enum.RaycastFilterType.Exclude; cameraParams.RespectCanCollide=true
    local function clearSight(origin,destination,target)
        local offset=destination-origin; if offset.Magnitude<0.01 then return true end
        -- Keep the game's queryable-geometry semantics; loot itself is excluded as the target.
        sightParams.FilterDescendantsInstances={player.Character,workspace.CurrentCamera}
        local hit=workspace:Raycast(origin,offset,sightParams)
        return not hit or hit.Instance==target or hit.Instance:IsDescendantOf(target)
    end
    local function refreshMap()
        local map=workspace:FindFirstChild("ActiveMap")
        if map~=cache.map then
            disconnect(groups.map); cache.map=map; cache.mapDirty=true
            if map then connect(map.AttributeChanged,function() cache.mapDirty=true end,groups.map) end
        end
        if not cache.mapDirty then return end
        cache.mapDirty=false; cache.base=map and num(map:GetAttribute("FloorBase")); cache.height=map and num(map:GetAttribute("FloorHeight"))
        cache.zones={}
        local encoded=map and map:GetAttribute("StairZones")
        if type(encoded)=="string" then
            for zone in string.gmatch(encoded,"[^;]+") do
                local bounds={}
                for token in string.gmatch(zone,"[%d%.%-]+") do
                    local n=num(tonumber(token)); if n then table.insert(bounds,n) end
                end
                if #bounds==4 then table.insert(cache.zones,bounds) end
            end
        end
    end
    local function inStairs(position)
        for _,bounds in ipairs(cache.zones) do
            if position.X>=bounds[1] and position.X<=bounds[3] and position.Z>=bounds[2] and position.Z<=bounds[4] then return true end
        end
        return false
    end
    local function effectiveValue(target,tool,round)
        local value=num(target:GetAttribute("Value")); if not value then return end
        -- Value already includes progression boosts. Only uncollected, non-tool loot gets this adjustment.
        local secondLife=player:GetAttribute("SecondLife")
        if not tool and type(target:GetAttribute("Rarity"))=="string" and secondLife~=nil and round
            and secondLife==round:GetAttribute("MatchId") and not target:GetAttribute("Dropped") then
            local store=modules.StoreConfig
            local divisor=store and store.SecondLife and num(store.SecondLife.lootDiv) or 2.5
            if divisor>0 then value=math.max(1,math.floor(value/divisor+0.5)) end
        end
        return value
    end
    local function bindInventory(inventory)
        disconnect(groups.inventory); cache.inventoryItems={}; cache.inventory=inventory; cache.bagDirty=true
        if not inventory then return end
        local function watch(item)
            if cache.inventory~=inventory or item.Parent~=inventory or cache.inventoryItems[item] then return end
            cache.inventoryItems[item]=connect(item.AttributeChanged,function() cache.bagDirty=true end,groups.inventory)
        end
        for _,item in ipairs(inventory:GetChildren()) do watch(item) end
        connect(inventory.ChildAdded,function(item) watch(item); cache.bagDirty=true end,groups.inventory)
        connect(inventory.ChildRemoved,function(item)
            if cache.inventory~=inventory then return end
            local c=cache.inventoryItems[item]; if c then c:Disconnect(); cache.inventoryItems[item]=nil
                local i=table.find(groups.inventory,c); if i then table.remove(groups.inventory,i) end end
            cache.bagDirty=true
        end,groups.inventory)
    end
    -- Inventory values are local; CarryWeight takes precedence over its weight sum.
    local function bagStats()
        local inventory=player:FindFirstChild("Inventory")
        if inventory~=cache.inventory then bindInventory(inventory) end
        if not cache.bagDirty and cache.bag then return cache.bag end
        local sum,value,known,items=0,0,true,{}
        if inventory then
            for _, item in ipairs(inventory:GetChildren()) do
                local w,v=num(item:GetAttribute("Weight")),num(item:GetAttribute("Value"))
                if w and w>=0 then sum=sum+w else known=false end
                if v then value=value+v end
                local key=item:GetAttribute("ItemKey") or item.Name; local config=itemConfig(key)
                table.insert(items,{key=key,name=displayName(key),weight=w,value=v,tool=item:GetAttribute("Tool")==true or config and config.tool==true,
                    inUse=item:GetAttribute("InUse")==true})
            end
        else known=false end
        local weight=num(player:GetAttribute("CarryWeight")); local inferred=weight==nil
        if inferred and known then weight=sum end
        local m=modules.GameConfig
        cache.bag={weight=weight,value=value,capacity=num(player:GetAttribute("CarryCapacity")) or m and num(m.CarryCapacity) or K.DefaultCapacity,
            inferred=inferred,items=items,hand=player:GetAttribute("HandItem"),
            handWeight=num(player:GetAttribute("HandWeight")),handValue=num(player:GetAttribute("HandValue"))}
        cache.bagDirty=false; return cache.bag
    end
    local function carryMode(item,bag)
        if not item.weight or item.weight<0 or not bag.weight then return "UNKNOWN" end
        local config=itemConfig(item.key); if not config then return "UNKNOWN" end
        if not config.armsOnly and bag.weight+item.weight<=bag.capacity+1e-6 then return "BAG" end
        if not item.tool and not config.tool and bag.hand==nil then return "HANDS" end
        return "FULL"
    end
    local function carryMultiplier(weight,capacity,handWeight)
        if not num(weight) then return end
        local f=capacity<=0 and 1 or math.clamp(weight/capacity,0,1); local hand=1
        if handWeight and handWeight>0 then
            local config=modules.GameConfig
            if config and type(config.handSpeed)=="function" then
                local ok,result=pcall(config.handSpeed,handWeight)
                if ok and num(result) then hand=result else return end
            else hand=math.max(0.5,0.86-0.034*handWeight) end
        end
        return (1-0.45*f*f)*hand
    end
    local function swapAdvice(item,bag)
        local config=itemConfig(item.key)
        if not bag.weight or not item.weight or not item.value or not config or config.armsOnly or item.tool then return end
        local best
        for _, carried in ipairs(bag.items) do
            if not carried.tool and not carried.inUse and carried.weight and carried.value and carried.weight>0
                and bag.weight-carried.weight+item.weight<=bag.capacity+1e-6 and item.value>carried.value
                and (not best or carried.value<best.value) then best=carried end
        end
        if best then return string.format("Swap %s: +$%.0f (manual)",best.name,item.value-best.value) end
        return nil
    end
    local function create(class,props,parent)
        local object=Instance.new(class)
        if initializing then table.insert(created,object) end
        for k,v in pairs(props or {}) do object[k]=v end
        object.Parent=parent; return object
    end
    local function corners(parent,r) create("UICorner",{CornerRadius=UDim.new(0,r or 10)},parent) end
    local function stroke(parent) create("UIStroke",{Color=C.line,Thickness=1,Transparency=0.35},parent) end
    local function pad(parent,n) create("UIPadding",{PaddingLeft=UDim.new(0,n),PaddingRight=UDim.new(0,n),PaddingTop=UDim.new(0,n),PaddingBottom=UDim.new(0,n)},parent) end
    local function list(parent,gap) create("UIListLayout",{Padding=UDim.new(0,gap or 10),SortOrder=Enum.SortOrder.LayoutOrder},parent) end
    local function label(parent,name,text,size,color)
        return create("TextLabel",{Name=name,BackgroundTransparency=1,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,
            Font=Enum.Font.Gotham,TextSize=size or 13,TextColor3=color or C.text,TextXAlignment=Enum.TextXAlignment.Left,
            TextYAlignment=Enum.TextYAlignment.Top,TextWrapped=true,Text=text},parent)
    end
    gui=create("ScreenGui",{Name=GUI_NAME,ResetOnSpawn=false,DisplayOrder=100,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},playerGui)
    local sync=create("BindableFunction",{Name="StopHelperSync"},gui); sync.OnInvoke=cleanup
    local event=create("BindableEvent",{Name="StopHelper"},gui); connect(event.Event,cleanup); connect(gui.Destroying,cleanup)
    local visuals=create("Folder",{Name="Markers"},gui)
    local panel=create("Frame",{Name="Panel",Size=UDim2.fromOffset(360,550),Position=UDim2.fromOffset(20,70),BackgroundColor3=C.bg,BorderSizePixel=0},gui)
    corners(panel,15); stroke(panel)
    local uiScale=create("UIScale",{Scale=1},panel)
    local header=create("Frame",{Name="Header",Size=UDim2.new(1,0,0,68),BackgroundTransparency=1,Active=true},panel)
    local title=label(header,"Title","STEAL / DIE",21); title.Font=Enum.Font.GothamBold
    title.Position,title.Size,title.AutomaticSize=UDim2.fromOffset(18,12),UDim2.fromOffset(235,25),Enum.AutomaticSize.None
    local roleBadge=label(header,"Role","CLIENT HELPER / v8",11,C.accent)
    roleBadge.Position,roleBadge.Size,roleBadge.AutomaticSize=UDim2.fromOffset(18,40),UDim2.fromOffset(270,18),Enum.AutomaticSize.None
    local function bindButton(button,callback)
        local action={button=button,callback=function(...)
            if stopped then return end
            local ok,err=pcall(callback,...); if not ok then report("Button action",err) end
        end}
        action.fallback=connect(button.Activated,function(...) if not action.hooked then action.callback(...) end end)
        table.insert(buttonActions,action)
    end
    syncButtons=function()
        local hook=modules.UIHook
        if not hook or type(hook.click)~="function" then return end
        local failed=false
        for _,action in ipairs(buttonActions) do
            if not action.hooked and action.button.Parent then
                local ok,c=pcall(hook.click,action.button,action.callback)
                if ok then
                    action.hooked=true; action.fallback:Disconnect()
                    if c then table.insert(connections,c) end
                else failed=true; report("Controller buttons",c) end
            end
        end
        if not failed then systemErrors["Controller buttons"]=nil end
    end
    local function smallButton(parent,name,text,pos,width,callback)
        local b=create("TextButton",{Name=name,Text=text,Position=pos,Size=UDim2.fromOffset(width,30),BackgroundColor3=C.card,BorderSizePixel=0,
            Font=Enum.Font.GothamBold,TextSize=12,TextColor3=C.text,Selectable=true},parent)
        corners(b,7); bindButton(b,callback); return b
    end
    local pages,tabs,controls={},{},{}
    local mouseOwned,mousePrevious=false,nil
    releaseMouse=function()
        if mouseOwned and player:GetAttribute("MouseFree")==true then player:SetAttribute("MouseFree",mousePrevious) end
        mouseOwned,mousePrevious=false,nil
    end
    local panelClosing=false
    local function setPanel(visible)
        set(panel,"Visible",visible)
        if visible then
            if not mouseOwned and player:GetAttribute("MouseFree")~=true then
                mousePrevious=player:GetAttribute("MouseFree"); mouseOwned=true; player:SetAttribute("MouseFree",true)
            end
        else panelClosing=true; releaseMouse(); panelClosing=false end
    end
    smallButton(header,"Hide","-",UDim2.new(1,-46,0,17),28,function() setPanel(false) end)
    smallButton(gui,"Reopen","HELPER",UDim2.fromOffset(20,25),82,function() setPanel(not panel.Visible) end)
    local function selectPage(name)
        for k,page in pairs(pages) do page.Visible=k==name end
        for k,tab in pairs(tabs) do tab.TextColor3=k==name and C.accent or C.muted end
    end
    for i,name in ipairs({"Overview","Visuals","Camera"}) do
        tabs[name]=smallButton(panel,"Tab"..name,name,UDim2.fromOffset(16+(i-1)*112,73),104,function() selectPage(name) end)
        local page=create("ScrollingFrame",{Name=name,Position=UDim2.fromOffset(14,114),Size=UDim2.new(1,-28,1,-162),
            CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=3,ScrollBarImageColor3=C.accent,
            BackgroundTransparency=1,BorderSizePixel=0,Visible=i==1},panel)
        pad(page,3); list(page,10); pages[name]=page
    end
    local function card(page,name,heading)
        local f=create("Frame",{Name=name,Size=UDim2.new(1,-4,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundColor3=C.card,BorderSizePixel=0},page)
        corners(f); pad(f,13); list(f,8); label(f,"Heading",heading,11,C.accent).Font=Enum.Font.GothamBold; return f
    end
    local function row(parent,name,text,callback)
        local b=create("TextButton",{Name=name,Text="",Size=UDim2.new(1,0,0,38),BackgroundColor3=C.bg,BorderSizePixel=0,Selectable=true},parent)
        corners(b,7)
        local caption=label(b,"Label",text,12); caption.Position,caption.Size,caption.AutomaticSize=UDim2.fromOffset(10,10),UDim2.new(1,-100,0,18),Enum.AutomaticSize.None
        caption.TextWrapped=false
        local value=label(b,"Value","",11,C.accent)
        value.Position,value.Size,value.AutomaticSize=UDim2.new(1,-91,0,11),UDim2.fromOffset(81,17),Enum.AutomaticSize.None
        value.TextXAlignment=Enum.TextXAlignment.Right
        controls[name]={button=b,value=value}
        bindButton(b,function() callback(); if refresh then refresh() end end)
        return b
    end
    local function toggle(parent,name,text) return row(parent,name,text,function() options[name]=not options[name] end) end
    local roundCard=card(pages.Overview,"RoundCard","ROUND")
    local roundText=label(roundCard,"RoundStatus","Waiting for round data",15)
    local noticeLabel=label(roundCard,"Notice","Home hides the panel and restores mouse control.",12,C.muted)
    local carryCard=card(pages.Overview,"CarryCard","CARRY / VALUE")
    local bagText=label(carryCard,"BagStatus","Waiting for inventory",14)
    local bar=create("Frame",{Size=UDim2.new(1,0,0,5),BackgroundColor3=C.line,BorderSizePixel=0},carryCard); corners(bar,3)
    local barFill=create("Frame",{Name="Load",Size=UDim2.fromScale(0,1),BackgroundColor3=C.accent,BorderSizePixel=0},bar); corners(barFill,3)
    local carryText=label(carryCard,"CarryCost","",12,C.muted)
    local lootCard=card(pages.Overview,"LootCard","NEARBY LOOT ADVISOR")
    local lootText=label(lootCard,"LootAdvice","No nearby loot loaded",13)
    local extractCard=card(pages.Overview,"ExtractionCard","EXTRACTION")
    local extractText=label(extractCard,"ExtractionAdvice","Waiting for an exit",13)
    toggle(extractCard,"ExtractFocus","Extraction focus")
    local threatCard=card(pages.Overview,"ThreatCard","THREAT")
    local threatText=label(threatCard,"ThreatStatus","No loaded threats",13)
    local huntCard=card(pages.Overview,"HuntCard","MONSTER HUNT")
    local huntText=label(huntCard,"HuntStatus","No living survivors loaded",13)
    row(huntCard,"CycleTarget","Cycle hunt target",function()
        if player:GetAttribute("IsEntity")~=true then return end
        local index=table.find(huntTargets,trackedPlayer) or 0
        trackedPlayer=huntTargets[index%math.max(1,#huntTargets)+1]
        local targetRoot=trackedPlayer and trackedPlayer.Character and anchor(trackedPlayer.Character)
        lastSeen=targetRoot and {position=targetRoot.Position,time=os.clock()} or nil
        notice(trackedPlayer and "Tracking "..trackedPlayer.DisplayName or "No living survivors loaded")
    end)
    toggle(huntCard,"AutoGrab","Auto-grab in reach")
    local grabNote=label(huntCard,"GrabNote","Auto-grab OFF. Hunt target is a tracking guide, not a grab lock.",11,C.muted)
    local hidingCard=card(pages.Overview,"HidingCard","CLOSETS / VENTS")
    local hidingText=label(hidingCard,"HidingStatus","No nearby hiding places loaded",12)
    local espCard=card(pages.Visuals,"ESPCard","MARKERS")
    for _,entry in ipairs({{"Enemies","Monster markers"},{"Players","Survivor markers"},{"Loot","Loot markers"},
        {"Exits","Exit guide"},{"Hiding","Closets and vents"},{"Alerts","Threat warnings"}}) do toggle(espCard,entry[1],entry[2]) end
    local filters=card(pages.Visuals,"FiltersCard","LOOT FILTERS")
    local valueSteps,orders={0,100,500,1000},{"Value / kg","Nearest","Value"}
    row(filters,"MinimumValue","Minimum value",function() minimumValue=valueSteps[(table.find(valueSteps,minimumValue) or 1)%#valueSteps+1] end)
    row(filters,"LootOrder","Preference",function() lootOrder=orders[(table.find(orders,lootOrder) or 1)%#orders+1] end)
    label(filters,"FilterNote","Recommended order: same floor, carry fit, lower risk, then preference. All rarities included. 3 advice items / 5 loot labels. Actors have no range cutoff.",11,C.muted)
    local camCard=card(pages.Camera,"CameraCard","VIEW")
    toggle(camCard,"ThirdPerson","Third person")
    local distances,shoulders={5,8,11},{1.4,0,-1.4}
    row(camCard,"CameraDistance","Camera distance",function() cameraDistance=distances[(table.find(distances,cameraDistance) or 2)%#distances+1] end)
    row(camCard,"CameraShoulder","Shoulder",function() shoulder=shoulders[(table.find(shoulders,shoulder) or 1)%#shoulders+1] end)
    local cameraText=label(camCard,"CameraStatus","Native first person",12,C.muted)
    label(camCard,"CameraNote","Wall collision enabled. Native view resumes for menus, scenes, tools, carried items and gadget animations. Look controls stay unchanged.",11,C.muted)
    local healthCard=card(pages.Camera,"HealthCard","STATUS")
    local healthText=label(healthCard,"HealthStatus","Checking available systems",11,C.muted)
    row(healthCard,"RetryModules","Retry unavailable systems",function()
        for name,state in pairs(moduleStatus) do if not state.loading then
            if state.error then modules[name]=nil end
            state.attempts,state.nextTry,state.error=0,0,nil
        end end
        pollDependencies(true)
    end)
    smallButton(panel,"Unload","UNLOAD",UDim2.new(1,-101,1,-36),85,function() if cleanup then cleanup() end end)
    local footer=label(panel,"Footer","HOME / PANEL    v8",10,C.muted)
    footer.Position,footer.Size,footer.AutomaticSize=UDim2.new(0,18,1,-27),UDim2.fromOffset(226,18),Enum.AutomaticSize.None
    local notifications=create("Frame",{Name="Notifications",AnchorPoint=Vector2.new(0.5,0),Position=UDim2.new(0.5,0,0,20),
        Size=UDim2.new(0.65,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1},gui)
    list(notifications,8)
    local alert=create("TextLabel",{Name="Alert",Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,LayoutOrder=1,
        BackgroundColor3=C.bg,BackgroundTransparency=0.08,BorderSizePixel=0,TextColor3=C.danger,Font=Enum.Font.GothamBold,
        TextSize=14,TextWrapped=true,Text="",Visible=false},notifications); corners(alert); stroke(alert); pad(alert,10)
    local toast=create("TextLabel",{Name="Toast",Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,LayoutOrder=2,
        BackgroundColor3=C.card,BackgroundTransparency=0.08,BorderSizePixel=0,TextColor3=C.accent,Font=Enum.Font.GothamBold,
        TextSize=13,TextWrapped=true,Text="",Visible=false},notifications); corners(toast); stroke(toast); pad(toast,10)
    refresh=function()
        for name,control in pairs(controls) do
            if options[name]~=nil then control.value.Text=options[name] and "ON" or "OFF"; control.value.TextColor3=options[name] and C.accent or C.muted end
        end
        controls.MinimumValue.value.Text="$"..minimumValue; controls.LootOrder.value.Text=lootOrder=="Nearest" and "DISTANCE" or lootOrder
        controls.CameraDistance.value.Text=cameraDistance.." studs"
        controls.CameraShoulder.value.Text=shoulder==0 and "CENTER" or shoulder>0 and "RIGHT" or "LEFT"
        controls.CycleTarget.value.Text="NEXT >"
        controls.RetryModules.value.Text="RETRY"
    end
    local dragging,dragStart,dragPosition
    connect(header.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging,dragStart,dragPosition=input,input.Position,panel.Position
        end
    end)
    connect(Input.InputEnded,function(input) if input==dragging then dragging=nil end end)
    connect(Input.InputChanged,function(input)
        if dragging and (input==dragging or input.UserInputType==Enum.UserInputType.MouseMovement) then
            local camera=workspace.CurrentCamera; if not camera then return end
            local delta=input.Position-dragStart; local view=camera.ViewportSize
            panel.Position=UDim2.fromOffset(math.clamp(dragPosition.X.Offset+delta.X,0,math.max(0,view.X-360*uiScale.Scale)),
                math.clamp(dragPosition.Y.Offset+delta.Y,0,math.max(0,view.Y-550*uiScale.Scale-40)))
        end
    end)
    connect(Input.InputBegan,function(input,processed)
        if not processed and not Input:GetFocusedTextBox() and input.KeyCode==Enum.KeyCode.Home then setPanel(not panel.Visible) end
    end)
    -- Incremental discovery; the full scan remains a recovery path for streaming/late attributes.
    local entityNames={["The Hollow"]="The Hollow",TheHollow="The Hollow",["The Rictus"]="The Rictus",TheRictus="The Rictus",["The Locust"]="The Locust",Locust="The Locust"}
    local entityKinds={Hollow="The Hollow",Rictus="The Rictus",Locust="The Locust"}
    local function refreshTags()
        if not cache.tagsDirty then return end
        cache.tagsDirty=false; cache.tagSets={}
        for _,tag in ipairs({"Entity","SecondEntity","Closet","Vent"}) do
            local members={}; cache.tagSets[tag]=members
            for _,target in ipairs(Tags:GetTagged(tag)) do members[target]=true end
        end
    end
    local function addCandidate(target,kind,name,owner)
        if target and (target:IsA("BasePart") or target:IsA("Model")) then
            local previous=candidates[target]
            if previous and previous.kind==kind and previous.owner==owner then previous.name=name
            else candidates[target]={kind=kind,name=name,owner=owner} end
        end
    end
    local function classify(object)
        if not object.Parent or not object:IsDescendantOf(workspace) then return end
        local ownerMap=cache.owners or {}
        local tagSets=cache.tagSets
        if object:IsA("Model") or (tagSets.Entity and tagSets.Entity[object]) or (tagSets.SecondEntity and tagSets.SecondEntity[object]) then
            local target=object:IsA("Model") and object or object:FindFirstAncestorOfClass("Model")
            local parent=target
            while parent do
                local owner=ownerMap[parent]
                if owner then
                    if owner~=player then addCandidate(owner.Character,owner:GetAttribute("IsEntity")==true and "Enemies" or "Players",owner.DisplayName,owner) end
                    return
                end
                parent=parent.Parent
            end
            if target then
                local name=entityKinds[target:GetAttribute("EntityKind")] or entityNames[target.Name]
                if name or tagSets.Entity[object] or tagSets.SecondEntity[object] then addCandidate(target,"Enemies",name or target.Name) end
            end
        end
        for _,tag in ipairs({"Closet","Vent"}) do
            if tagSets[tag][object] then addCandidate(object,"Hiding",string.upper(tag)); return end
        end
        if object:IsA("BasePart") then
            local parent=object.Parent; local inLoot=false
            while parent and parent~=workspace do
                if parent.Name=="MyLoot" or parent.Name=="LootItems" then inLoot=true; break end
                parent=parent.Parent
            end
            if inLoot and object:GetAttribute("Loot")==true then addCandidate(object,"Loot",object:GetAttribute("ItemKey") or object.Name) end
            if cache.map and object:IsDescendantOf(cache.map) and object:GetAttribute("Exit")==true then addCandidate(object,"Exits","EXIT") end
        elseif object:IsA("ProximityPrompt") and cache.map and object:IsDescendantOf(cache.map) then
            local parent=object.Parent
            while parent and parent~=cache.map do
                if tagSets.Closet[parent] or tagSets.Vent[parent] then
                    addCandidate(parent,"Hiding",tagSets.Closet[parent] and "CLOSET" or "VENT"); return
                end
                if candidates[parent] and candidates[parent].kind=="Hiding" then return end
                parent=parent.Parent
            end
            local text=string.lower(object.ActionText.." "..object.ObjectText.." "..object.Parent.Name)
            local kind=text:find("closet",1,true) and "CLOSET" or text:find("vent",1,true) and "VENT"
            local target=object:FindFirstAncestorOfClass("Model") or object.Parent
            if kind and anchor(target) then addCandidate(target,"Hiding",kind) end
        end
    end
    local function indexObject(object)
        local ok,err=pcall(classify,object)
        if not ok then report("Discovery",err) end
    end
    local function rebuildOwners()
        cache.owners={}
        for _,other in ipairs(Players:GetPlayers()) do
            if other.Character then
                cache.owners[other.Character]=other
                if other~=player then addCandidate(other.Character,other:GetAttribute("IsEntity")==true and "Enemies" or "Players",other.DisplayName,other) end
            end
        end
        cache.playersDirty=false
    end
    local function discover(full)
        refreshMap(); refreshTags()
        if full or cache.playersDirty then rebuildOwners() end
        if full then
            candidates={}; rebuildOwners()
            for _,tag in ipairs({"Entity","SecondEntity","Closet","Vent"}) do
                for target in pairs(cache.tagSets[tag]) do indexObject(target) end
            end
            for _,object in ipairs(workspace:GetChildren()) do if object:IsA("Model") then indexObject(object) end end
            for _,name in ipairs({"MyLoot","LootItems"}) do
                local folder=workspace:FindFirstChild(name)
                if folder then for _,object in ipairs(folder:GetDescendants()) do indexObject(object) end end
            end
            if cache.map then for _,object in ipairs(cache.map:GetDescendants()) do indexObject(object) end end
        else
            for object in pairs(cache.pending) do indexObject(object) end
        end
        for target in pairs(candidates) do if not target.Parent or not target:IsDescendantOf(workspace) then candidates[target]=nil end end
        table.clear(cache.pending); dirty=false
    end
    local function playersChanged() cache.playersDirty=true; cache.partsDirty=true end
    local function watchPlayer(other)
        if watchers[other] then return end
        local cs={}; watchers[other]=cs
        connect(other.CharacterAdded,playersChanged,cs)
        connect(other.CharacterRemoving,function()
            playersChanged()
            if other==player then cache.character=nil; cache.body,cache.arms={},{}; cache.partObjects=nil end
        end,cs)
        connect(other:GetAttributeChangedSignal("IsEntity"),playersChanged,cs)
    end
    for _,other in ipairs(Players:GetPlayers()) do watchPlayer(other) end
    connect(Players.PlayerAdded,function(other) watchPlayer(other); playersChanged() end)
    connect(Players.PlayerRemoving,function(other)
        if watchers[other] then disconnect(watchers[other]); watchers[other]=nil end
        if trackedPlayer==other then trackedPlayer,lastSeen=nil,nil end
        playersChanged()
    end)
    connect(player.AttributeChanged,function(name)
        if name=="CarryWeight" or name=="CarryCapacity" or name=="HandItem" or name=="HandWeight" or name=="HandValue" then cache.bagDirty=true end
        if name=="MouseFree" and panel.Visible and not panelClosing and player:GetAttribute(name)~=true then
            -- Native Back/pointer controls won ownership; close without undoing their write.
            mouseOwned,mousePrevious=false,nil; set(panel,"Visible",false)
        end
    end)
    local function worldChanged(object)
        local camera=workspace.CurrentCamera; local character=player.Character
        if cache.partObjects and cache.partObjects[object] then cache.partsDirty=true; return end
        if (camera and (object==camera or object:IsDescendantOf(camera))) or (character and (object==character or object:IsDescendantOf(character))) then
            cache.partsDirty=true; return
        end
        if object.Name=="MyLoot" or object.Name=="LootItems" or object.Name=="ActiveMap" then dirty=true; cache.mapDirty=true; return end
        if object:IsA("Model") then cache.pending[object]=true; cache.tagsDirty=true
        elseif object:IsA("ProximityPrompt") or object:IsA("BasePart") and (object:GetAttribute("Loot")==true or object:GetAttribute("Exit")==true or object.Name=="HumanoidRootPart") then
            cache.pending[object]=true
            local model=object:FindFirstAncestorOfClass("Model"); if model then cache.pending[model]=true end
        end
    end
    connect(workspace.DescendantAdded,worldChanged); connect(workspace.DescendantRemoving,worldChanged)
    for _,tag in ipairs({"Entity","SecondEntity","Closet","Vent"}) do
        local function changed(target,removed)
            cache.tagsDirty=true
            if target then
                cache.pending[target]=true
                if removed then
                    candidates[target]=nil
                    if not target:IsA("Model") then
                        local model=target:FindFirstAncestorOfClass("Model")
                        if model then candidates[model]=nil; cache.pending[model]=true end
                    end
                end
            end
        end
        connect(Tags:GetInstanceAddedSignal(tag),function(target) changed(target,false) end)
        connect(Tags:GetInstanceRemovedSignal(tag),function(target) changed(target,true) end)
    end
    removeMarker=function(target)
        local m=markers[target]
        if m then if m.highlight then m.highlight:Destroy() end; m.billboard:Destroy(); markers[target]=nil end
    end
    local function markerFor(target,part)
        local m=markers[target]
        if not m then
            local b=create("BillboardGui",{Adornee=part,Size=UDim2.fromOffset(235,56),StudsOffsetWorldSpace=Vector3.new(0,2.5,0),AlwaysOnTop=true},visuals)
            m={billboard=b,label=create("TextLabel",{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Font=Enum.Font.GothamBold,
                TextSize=12,TextWrapped=true,TextStrokeTransparency=0.25},b)}; markers[target]=m
        end
        return m
    end
    local function hidingInfo(target,name,monster,bag)
        if name=="CLOSET" then
            local l,r=num(target:GetAttribute("OccupantL")),num(target:GetAttribute("OccupantR"))
            if not l or not r then return "CLOSET - occupancy unknown",false end
            local occupied=(l~=0 and 1 or 0)+(r~=0 and 1 or 0)
            local text=string.format("CLOSET - %d/2 occupied",occupied)
            if monster and occupied>0 then
                local names={}
                for _,id in ipairs({l,r}) do if id>0 then local other=Players:GetPlayerByUserId(id); if other then table.insert(names,other.DisplayName) end end end
                if #names>0 then text=text.." ("..table.concat(names,", ")..")" end
            end
            return text,monster and occupied>0 or not monster and occupied<2
        end
        if target:GetAttribute("Broken")==true then return "VENT - cover broken",true end
        local bolts=num(target:GetAttribute("BoltsLeft"))
        if bolts==nil then
            local cover=target:FindFirstChild("Cover")
            if cover then
                local total,left=0,0
                for _,bolt in ipairs(cover:GetChildren()) do
                    if bolt:GetAttribute("Bolt")==true then total=total+1; if bolt:GetAttribute("Removed")~=true then left=left+1 end end
                end
                if total>0 then bolts=left end
            end
        end
        if bolts then
            local hasTool=false
            for _,item in ipairs(bag.items) do if item.key=="Screwdriver" then hasTool=true; break end end
            return string.format("VENT - %d bolts left / %s",math.max(0,bolts),
                monster and "opening required" or hasTool and "screwdriver available" or "no screwdriver in bag"),false
        end
        return "VENT - cover state unknown",false
    end
    local function ownerAlive(other,target)
        local h=target:FindFirstChildOfClass("Humanoid")
        return other.Character==target and h and h.Health>0 and other:GetAttribute("InMatch")~=false and other:GetAttribute("Spectating")~=true
    end
    local function lootLess(a,b)
        if (a.floorDelta==0)~=(b.floorDelta==0) then return a.floorDelta==0 end
        if carryRank[a.mode]~=carryRank[b.mode] then return carryRank[a.mode]<carryRank[b.mode] end
        if a.risky~=b.risky then return not a.risky end
        if lootOrder=="Nearest" then return a.distance<b.distance end
        local av,bv=lootOrder=="Value" and a.value or a.density,lootOrder=="Value" and b.value or b.density
        if av~=bv then return av>bv end
        return a.distance<b.distance
    end
    local function canAct(character)
        local round=RS:FindFirstChild("Round"); local h=character and character:FindFirstChildOfClass("Humanoid")
        if not ready("IntroState") or not ready("VKeys") then return false,"Waiting for input/scene systems" end
        if not round or round:GetAttribute("Phase")~="Match" or player:GetAttribute("InMatch")~=true or not h or h.Health<=0 then return false,"Outside an active match" end
        if menuOpen() then return false,"Menu open" end
        if moduleActive("IntroState","active") then return false,"Intro active or unavailable" end
        for _,attr in ipairs({"Hiding","BeingKilled","Stunned","Dragging","Spectating","Grabbed","Grabbing","IntroPlaying"}) do
            if player:GetAttribute(attr)==true then return false,"Paused: "..attr end
        end
        if character:GetAttribute("Killing")==true or character:GetAttribute("BeingKilled")==true then return false,"Special scene" end
        return true
    end
    local function autoGrab(root,character,survivors)
        if not options.AutoGrab then grabStatus="OFF"; grabAttempt=nil; nextGrabAt=-math.huge; return end
        if player:GetAttribute("EntityStage")~="hunt" then grabStatus="Waiting for hunt stage"; return end
        local can,reason=canAct(character)
        if not can then grabStatus=reason; grabAttempt=nil; return end
        local camera=workspace.CurrentCamera; local config=modules.EntityConfig and modules.EntityConfig.Player
        if not camera or not ready("EntityConfig") or not config or not num(config.GRAB_RANGE) or not num(config.GRAB_CONE) then grabStatus="Waiting for reach configuration"; return end
        if os.clock()-manualGrabAt<K.GrabCooldown then grabStatus="Manual grab input"; return end
        local look=camera.CFrame.LookVector; local facing=Vector3.new(look.X,0,look.Z)
        facing=facing.Magnitude>0.001 and facing.Unit or Vector3.new(0,0,-1)
        for _,item in ipairs(survivors) do
            local other,target=item.data.owner,item.target
            local offset=item.position-root.Position; local flat=Vector3.new(offset.X,0,offset.Z); local length=flat.Magnitude
            if target:FindFirstChild("HumanoidRootPart")==item.part and other:GetAttribute("BeingKilled")~=true
                and other:GetAttribute("Grabbed")~=true and other:GetAttribute("Hiding")~=true
                and target:GetAttribute("BeingKilled")~=true and length<=config.GRAB_RANGE and math.abs(offset.Y)<K.GrabVertical
                and (length<K.GrabClose or length>0 and flat.Unit:Dot(facing)>config.GRAB_CONE)
                and clearSight(root.Position,item.position,target) then
                local now=os.clock()
                if not grabAttempt or grabAttempt.target~=target or (grabAttempt.position-item.position).Magnitude>1 then
                    grabAttempt={target=target,position=item.position,count=0}; nextGrabAt=math.min(nextGrabAt,now)
                end
                if now<nextGrabAt or now-lastGrab<K.GrabCooldown then grabStatus="Retry cooldown / "..other.DisplayName; return end
                local remotes=RS:FindFirstChild("Remotes"); local grab=remotes and remotes:FindFirstChild("EntityGrab")
                if not grab or not grab:IsA("RemoteEvent") then grabStatus="EntityGrab remote unavailable"; return end
                local ok,err=pcall(function() grab:FireServer() end)
                if not ok then options.AutoGrab=false; grabStatus="Disabled after remote error"; report("Auto-grab",err); refresh(); return end
                lastGrab=now; grabAttempt.count=grabAttempt.count+1
                nextGrabAt=now+math.min(K.GrabMaxBackoff,K.GrabCooldown*2^math.min(2,grabAttempt.count-1))
                grabStatus="Attempt sent / "..other.DisplayName.." (server chooses target)"; return
            end
        end
        grabAttempt=nil; nextGrabAt=-math.huge; grabStatus="No eligible survivor in reach"
    end
    -- Restore local writes before the game camera's next render step, then offset last.
    local visibility,nativeCamera,nativeFrame,appliedFrame={},nil,nil,nil
    local cameraReason="Native first person"
    local PRE,POST="SOD_HelperCameraRestore","SOD_HelperThirdPerson"
    local visibilityPool=setmetatable({},{__mode="k"})
    restoreCamera=function()
        local errors={}
        for part,state in pairs(visibility) do
            local ok,err=pcall(function()
                if part.Parent and part.LocalTransparencyModifier==state.applied then part.LocalTransparencyModifier=state.original end
            end)
            if ok then visibility[part]=nil else table.insert(errors,tostring(err)) end
        end
        if nativeCamera then
            local ok,err=pcall(function() if nativeFrame and nativeCamera.CFrame==appliedFrame then nativeCamera.CFrame=nativeFrame end end)
            if ok then nativeCamera,nativeFrame,appliedFrame=nil,nil,nil else table.insert(errors,tostring(err)) end
        end
        if #errors>0 then error(table.concat(errors,"; ")) end
    end
    local function setVisibility(part,value)
        if not visibility[part] then
            local state=visibilityPool[part] or {}; visibilityPool[part]=state
            state.original,state.applied=part.LocalTransparencyModifier,value; visibility[part]=state
        end
        if part.LocalTransparencyModifier~=value then part.LocalTransparencyModifier=value end
    end
    local function refreshParts(character,camera)
        if cache.character~=character or cache.camera~=camera then cache.partsDirty=true end
        if not cache.partsDirty then return end
        cache.partsDirty=false; cache.character,cache.camera=character,camera; cache.body,cache.arms={},{}
        cache.partObjects=setmetatable({},{__mode="k"})
        cache.carryModel,cache.flashlight=false,false
        if character then for _,part in ipairs(character:GetDescendants()) do
            cache.partObjects[part]=true
            if part:IsA("BasePart") and part.Name~="HumanoidRootPart" and part.Name~="CameraBlocker" and (num(part.Transparency) or 0)<1 then
                local parent=part.Parent; local held=false
                while parent and parent~=character do
                    if parent.Name=="HeldTool" or parent.Name=="HeldProp" then held=true; break end
                    parent=parent.Parent
                end
                if not held then table.insert(cache.body,part) end
            end
        end end
        if camera then for _,object in ipairs(camera:GetDescendants()) do cache.partObjects[object]=true end end
        if camera then for _,child in ipairs(camera:GetChildren()) do
            if child.Name=="ViewArms" then for _,part in ipairs(child:GetDescendants()) do
                if part:IsA("BasePart") then table.insert(cache.arms,part) end
            end elseif child.Name=="CarryItem" then cache.carryModel=true
            elseif child.Name=="Flashlight" and child:IsA("BasePart") then cache.flashlight=true end
        end end
    end
    local viewmodelUntil=0
    local function cameraBlocked(character,root)
        if not options.ThirdPerson then return "Native first person" end
        if not character or not root then return "Waiting for character" end
        for _,name in ipairs(safetyModules) do if not ready(name) then return "Waiting for "..name end end
        local h=character:FindFirstChildOfClass("Humanoid"); local round=RS:FindFirstChild("Round")
        if not h or h.Health<=0 or not round or round:GetAttribute("Phase")~="Match" or player:GetAttribute("InMatch")~=true then return "Paused outside active match" end
        if Input.VREnabled or moduleActive("VRCore","active") then return "Paused in VR" end
        if menuOpen() then return "Paused while a menu is open" end
        for _,attr in ipairs({"Hiding","Grabbed","BeingKilled","Spectating","IntroPlaying","InVent","Grabbing","Dragging","Stunned"}) do
            if player:GetAttribute(attr)==true then return "Paused: "..attr end
        end
        if character:GetAttribute("Killing")==true or character:GetAttribute("BeingKilled")==true or root.Anchored then return "Paused during a special scene" end
        if player:GetAttribute("IsEntity")==true and player:GetAttribute("EntityStage")~="hunt" then return "Paused during monster setup" end
        if moduleActive("IntroState","active") or moduleActive("CourtCam","weight") or moduleActive("EmoteCam","weight") then return "Paused during a game camera scene" end
        for _,name in ipairs({"VentGrab","EntityBash"}) do
            local scene=playerGui:FindFirstChild(name)
            if scene and scene:IsA("ScreenGui") and scene.Enabled then return "Paused during "..name end
        end
        local throwBar=playerGui:FindFirstChild("ThrowBar")
        local throwPanel=throwBar and throwBar:FindFirstChildOfClass("CanvasGroup")
        if throwPanel and throwPanel.Visible and throwPanel.GroupTransparency<0.99 then return "Paused for throw animation" end
        local keys=modules.VKeys
        local interacting=false
        for _,key in ipairs({Enum.KeyCode.F,Enum.KeyCode.E,Enum.KeyCode.R}) do
            interacting=interacting or Input:IsKeyDown(key)
            if keys and type(keys.isDown)=="function" then
                local ok,result=pcall(keys.isDown,key); interacting=interacting or ok and result==true
            end
        end
        if player:GetAttribute("EquippedTool")~=nil or interacting then return "Paused for aimed interaction" end
        if player:GetAttribute("HandItem")~=nil or cache.carryModel then return "Paused while carrying an item" end
        if player:GetAttribute("ViewArmL") or player:GetAttribute("ViewArmR") or character:GetAttribute("Drinking")~=nil then
            viewmodelUntil=os.clock()+K.ViewmodelTail; return "Paused for item/gadget animation"
        end
        if os.clock()<viewmodelUntil then return "Paused for animation finish" end
        if cache.flashlight then return "Paused for native flashlight" end
        return nil
    end
    local function thirdPerson()
        if not options.ThirdPerson then cameraReason="Native first person"; return end
        local character=player.Character; local root=character and character:FindFirstChild("HumanoidRootPart")
        refreshParts(character,workspace.CurrentCamera)
        local reason=cameraBlocked(character,root); cameraReason=reason or "Third person active"
        if reason then return end
        local camera=workspace.CurrentCamera; if not camera then cameraReason="Waiting for camera"; return end
        local base=camera.CFrame
        local pivot=root.Position+Vector3.new(0,math.clamp(base.Position.Y-root.Position.Y,0.3,8),0)
        local desired=pivot+base.RightVector*shoulder-base.LookVector*cameraDistance
        -- Keep the camera on the native listener floor when the map separates sound by floor.
        local map=cache.map
        if player:GetAttribute("IsEntity")~=true and map and map:GetAttribute("FloorHearing")==true and cache.base and cache.height and cache.height>0 then
            local floor=math.floor((base.Position.Y-cache.base-0.5)/cache.height)
            local bottom=cache.base+0.5+floor*cache.height
            desired=Vector3.new(desired.X,math.clamp(desired.Y,bottom+0.05,bottom+cache.height-0.05),desired.Z)
        end
        local offset=desired-pivot
        cameraParams.FilterDescendantsInstances={character,camera}
        local hit=workspace:Spherecast(pivot,K.CameraRadius,offset,cameraParams)
        local safe=hit and math.max(0,hit.Distance-K.CameraMargin) or offset.Magnitude
        if safe<K.CameraMinimum then cameraReason="First person: wall too close"; return end
        local position=pivot+offset.Unit*safe
        if player:GetAttribute("IsEntity")~=true and map and map:GetAttribute("FloorHearing")==true and inStairs(base.Position)~=inStairs(position) then
            cameraReason="Paused at stair hearing boundary"; return
        end
        nativeCamera,nativeFrame=camera,base
        appliedFrame=CFrame.new(position)*base.Rotation; camera.CFrame=appliedFrame
        for _,part in ipairs(cache.body) do if part.Parent then setVisibility(part,0) end end
        for _,part in ipairs(cache.arms) do if part.Parent then setVisibility(part,1) end end
    end
    local function cameraError(err)
        options.ThirdPerson=false; cameraReason="Camera disabled after an error"
        local restored,restoreErr=pcall(restoreCamera)
        report("Camera",restored and err or tostring(err).." / restore: "..tostring(restoreErr)); refresh()
    end
    bindings[PRE]=true
    Run:BindToRenderStep(PRE,Enum.RenderPriority.Camera.Value-1,function()
        if stopped then return end
        local ok,err=pcall(restoreCamera); if not ok then cameraError(err) end
    end)
    bindings[POST]=true
    Run:BindToRenderStep(POST,Enum.RenderPriority.Last.Value+1,function()
        if stopped then return end
        local ok,err=pcall(thirdPerson); if not ok then cameraError(err) end
    end)
    local nativeKeys
    onModulesChanged=function(name)
        if name=="UIHook" then syncButtons() end
        if name=="VKeys" then
            if nativeKeys then nativeKeys:Disconnect() end
            local keys=modules.VKeys
            if keys and keys.Began then nativeKeys=connect(keys.Began,function(input,processed)
                if not processed and input.UserInputType==Enum.UserInputType.MouseButton1 then manualGrabAt=os.clock() end
            end) end
        end
    end
    connect(Input.InputBegan,function(input,processed)
        if not processed and input.UserInputType==Enum.UserInputType.MouseButton1 then manualGrabAt=os.clock() end
    end)
    local function nearest(a,b) return a.distance<b.distance end
    local function sortPlaces(a,b) if a.useful~=b.useful then return a.useful end; return nearest(a,b) end
    local function sortThreats(a,b)
        if a.danger~=b.danger then return a.danger end
        if a.chasing~=b.chasing then return a.chasing end
        return nearest(a,b)
    end
    local function evaluateCandidate(target,data,context,bag)
        local part=target.Parent and anchor(target)
        if not context.inMatch or not context.root or not part or not part:IsA("BasePart") or not target:IsDescendantOf(workspace) then return end
        local available=true; local position=part.Position; local distance=(position-context.position).Magnitude
        if data.owner then
            available=ownerAlive(data.owner,target); data.name=data.owner.DisplayName
            if data.kind=="Players" then available=available and context.monster and data.owner:GetAttribute("InMatch")==true and data.owner:GetAttribute("IsEntity")~=true
            else available=available and not context.monster and data.owner:GetAttribute("IsEntity")==true end
        end
        local floorDelta,floorExact=floorDifference(context.position,position)
        local item={target=target,part=part,position=position,data=data,distance=distance,floorDelta=floorDelta,floorExact=floorExact}
        if data.kind=="Loot" and not context.monster and distance<=K.LootRange and part.LocalTransparencyModifier<=0.5 then
            local prompt=target:FindFirstChildWhichIsA("ProximityPrompt",true)
            item.key=target:GetAttribute("ItemKey") or target.Name; item.name=displayName(item.key)
            local config=itemConfig(item.key); item.tool=target:GetAttribute("Tool")==true or config and config.tool==true
            item.weight,item.value=num(target:GetAttribute("Weight")),effectiveValue(target,item.tool,context.round)
            item.hold=prompt and num(prompt.HoldDuration)
            if item.value and item.value>=minimumValue and item.weight and item.weight>0 and (not prompt or prompt.Enabled) then
                item.density,item.mode=item.value/item.weight,carryMode(item,bag); return item
            end
        elseif available and data.kind=="Enemies" and not context.monster then
            local h=target:FindFirstChildOfClass("Humanoid")
            if not h or h.Health>0 then
                item.calm=(num(target:GetAttribute("CalmUntil")) or 0)>context.now
                item.chasing=target:GetAttribute("ChaseTarget")==player.UserId
                local state: any=target:GetAttribute("State")
                item.state=item.calm and "CALM" or item.chasing and "CHASING YOU" or data.owner and "PLAYER ENTITY" or type(state)=="string" and string.upper(state) or "STATE UNKNOWN"
                item.stairRisk=not item.calm and floorExact and math.abs(floorDelta)==1 and distance<K.StairRange and (inStairs(context.position) or inStairs(position))
                item.danger=not item.calm and (item.chasing or floorDelta==0 and distance<K.ContactRange or not floorExact and distance<K.UnknownHeightRange or item.stairRisk)
                if item.stairRisk then item.state=item.state.." / NEAR STAIRS" end
                return item
            end
        elseif available and data.kind=="Players" then
            item.health=target:FindFirstChildOfClass("Humanoid").Health
            item.shieldUntil=num(data.owner:GetAttribute("SpawnShield")); return item
        elseif data.kind=="Exits" and not context.monster then return item
        elseif data.kind=="Hiding" and distance<=K.HidingRange then item.info,item.useful=hidingInfo(target,data.name,context.monster,bag); return item end
        return nil
    end
    local function candidateFailed(target,err)
        local failure=cache.candidateFailures[target] or {count=0}; cache.candidateFailures[target]=failure
        failure.count=failure.count+1; failure.retryAt=os.clock()+math.min(5,failure.count)
        if markers[target] then local ok,removeErr=pcall(removeMarker,target); if not ok then report("Marker cleanup",removeErr) end end
        report("Object data",err)
    end
    local function renderMarker(item,index,root)
        local kind,target=item.data.kind,item.target; local m=markerFor(target,item.part)
        if index>K.Highlights and m.highlight then m.highlight:Destroy(); m.highlight=nil end
        if index<=K.Highlights and not m.highlight then m.highlight=create("Highlight",{Adornee=target,DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,FillTransparency=0.88,OutlineTransparency=0.1},visuals) end
        local color,caption=C.text,item.data.name
        if kind=="Loot" then color=rarityColors[target:GetAttribute("Rarity")] or C.text; caption=string.format("%s  $%.0f / %.1fkg [%s]",item.name,item.value,item.weight,item.mode)
        elseif kind=="Enemies" then color,caption=item.stairRisk and C.amber or C.danger,caption.." / "..item.state
        elseif kind=="Players" then
            color=C.blue; caption=caption..string.format(" / %.0f HP",item.health)
            if item.data.owner:GetAttribute("Hiding")==true then caption=caption.." [HIDING]" end
            if item.shieldUntil and item.shieldUntil>workspace:GetServerTimeNow() then caption=caption.." [SPAWN SHIELD]" end
        elseif kind=="Hiding" then color,caption=C.accent,item.info
        elseif kind=="Exits" then color,caption=C.accent,item.exitCaption end
        if m.highlight then set(m.highlight,"FillColor",color); set(m.highlight,"OutlineColor",color) end
        set(m.billboard,"Enabled",true); set(m.billboard,"Adornee",item.part); set(m.billboard,"MaxDistance",(kind=="Enemies" or kind=="Players") and 0 or 1200)
        set(m.label,"TextColor3",color); set(m.label,"TextSize",item.distance>250 and 10 or 12)
        set(m.label,"Text",caption..string.format("\n%.0f studs / %s / %s",item.distance,direction(item.position),floorText(root.Position,item.position)))
    end
    local function update()
        local monster=player:GetAttribute("IsEntity")==true
        local character=player.Character; local root=character and character:FindFirstChild("HumanoidRootPart")
        local hum=character and character:FindFirstChildOfClass("Humanoid"); local round=RS:FindFirstChild("Round")
        local phase=round and round:GetAttribute("Phase") or "Unknown"
        local inMatch=phase=="Match" and player:GetAttribute("InMatch")==true and hum and hum.Health>0 and player:GetAttribute("Spectating")~=true
        local now=workspace:GetServerTimeNow(); local opens=round and num(round:GetAttribute("ExtractOpensAt")); local ends=round and num(round:GetAttribute("PhaseEnds"))
        local remaining=ends and math.max(0,ends-now)
        local open=inMatch and opens and opens>0 and opens<=now
        local exitStatus=open and "OPEN" or opens and opens>now and string.format("opens in %ds",math.ceil(opens-now)) or "locked"
        local identity=tostring(round).."/"..tostring(round and round:GetAttribute("MatchId")).."/"..phase
        if identity~=roundIdentity then roundIdentity,deadlineWarned,exitWasOpen=identity,{},false end
        local camera=workspace.CurrentCamera
        cache.directionOrigin=root and root.Position or camera and camera.CFrame.Position
        cache.directionLook=camera and camera.CFrame.LookVector
        local bag=monster and emptyBag or bagStats()
        local lists={Loot={},Enemies={},Players={},Hiding={},Exits={}}
        local loot,threats,survivors,places,exits=lists.Loot,lists.Enemies,lists.Players,lists.Hiding,lists.Exits
        local context={monster=monster,inMatch=inMatch,root=root,position=root and root.Position,now=now,round=round}
        for target,data in pairs(candidates) do
            local failure=cache.candidateFailures[target]
            if not failure or os.clock()>=failure.retryAt then
                local ok,item=pcall(evaluateCandidate,target,data,context,bag)
                if ok then cache.candidateFailures[target]=nil; if item then table.insert(lists[data.kind],item) end
                else candidateFailed(target,item) end
            end
        end
        for _,item in ipairs(loot) do
            item.risky=false
            for _,threat in ipairs(threats) do
                if not threat.calm and (threat.position-item.position).Magnitude<K.LootRiskRange
                    and (floorDifference(item.position,threat.position)==0
                        or math.abs(floorDifference(item.position,threat.position))==1 and (inStairs(item.position) or inStairs(threat.position))) then item.risky=true; break end
            end
        end
        table.sort(loot,lootLess)
        table.sort(survivors,nearest); table.sort(exits,nearest)
        table.sort(places,sortPlaces)
        table.sort(threats,sortThreats)
        huntTargets={}; for _,item in ipairs(survivors) do table.insert(huntTargets,item.data.owner) end
        if trackedPlayer then
            local h=trackedPlayer.Character and trackedPlayer.Character:FindFirstChildOfClass("Humanoid")
            if trackedPlayer:GetAttribute("InMatch")~=true or trackedPlayer:GetAttribute("IsEntity")==true or trackedPlayer:GetAttribute("Spectating")==true or h and h.Health<=0 then
                trackedPlayer,lastSeen=nil,nil
            end
        end
        if not trackedPlayer then trackedPlayer=huntTargets[1] end
        local tracked; for _,item in ipairs(survivors) do if item.data.owner==trackedPlayer then tracked=item; break end end
        if tracked then lastSeen={position=tracked.part.Position,time=os.clock()} end
        if not monster then trackedPlayer,lastSeen=nil,nil end
        local visible,chosen={},{}
        local function select(items,enabled,limit)
            if enabled then for i,item in ipairs(items) do if i>limit then break end; table.insert(visible,item); chosen[item.target]=true end end
        end
        select(threats,options.Enemies,math.huge); select(survivors,options.Players,math.huge)
        for _,item in ipairs(exits) do item.exitCaption="EXIT / "..exitStatus end
        select(exits,options.Exits,1); select(places,options.Hiding,2); select(loot,options.Loot and not options.ExtractFocus,K.LootLabels)
        for target in pairs(markers) do if not chosen[target] then removeMarker(target) end end
        for i,item in ipairs(visible) do
            local ok,err=pcall(renderMarker,item,i,root)
            if not ok then candidateFailed(item.target,err) end
        end
        set(roleBadge,"Text","v8 / "..(monster and "MONSTER" or "SURVIVOR")..(inMatch and "" or " / WAITING"))
        if cache.uiRole~=monster or cache.uiMatch~=inMatch then
            cache.uiRole,cache.uiMatch=monster,inMatch
            set(roleBadge,"TextColor3",monster and C.danger or C.accent)
            carryCard.Visible,lootCard.Visible,extractCard.Visible,threatCard.Visible=not monster,not monster,not monster,not monster; huntCard.Visible=monster
            controls.Enemies.button.Visible,controls.Players.button.Visible=not monster,monster
            controls.Loot.button.Visible,controls.Exits.button.Visible,filters.Visible=not monster,not monster,not monster
            set(controls.Alerts.button,"Visible",not monster)
        end
        set(roundText,"Text",tostring(phase)..(remaining and string.format(" / %d:%02d left",math.floor(remaining/60),math.floor(remaining%60)) or ""))
        if not monster and panel.Visible and pages.Overview.Visible then
            if bag.weight then
                set(bagText,"Text",string.format("%.1f / %.1f kg / Bag $%.0f%s",bag.weight,bag.capacity,bag.value,bag.inferred and " (weight estimated)" or ""))
                barFill.Size=UDim2.fromScale(bag.capacity>0 and math.clamp(bag.weight/bag.capacity,0,1) or 1,1); barFill.BackgroundColor3=bag.weight>=bag.capacity and C.amber or C.accent
            else bagText.Text="Carry weight unavailable"; barFill.Size=UDim2.fromScale(0,1) end
            local multiplier=not (bag.hand and bag.handWeight==nil) and carryMultiplier(bag.weight,bag.capacity,bag.hand and bag.handWeight or nil)
            set(carryText,"Text",multiplier and string.format("Carry speed: %.0f%% of otherwise applicable speed",multiplier*100) or "Carry speed unknown")
            if bag.hand then carryText.Text=carryText.Text.."\nHands: "..displayName(bag.hand)..(bag.handValue and string.format(" / $%.0f",bag.handValue) or "") end
        end
        local advice={}
        for _,item in ipairs(loot) do if panel.Visible and pages.Overview.Visible and not options.ExtractFocus and item.distance<=K.AdviceRange and #advice<K.AdviceItems then
            local text=string.format("%s  $%.0f / %s\n%.0f studs / %s / %s",item.name,item.value,item.mode,item.distance,direction(item.part.Position),floorText(root.Position,item.part.Position))
            if item.hold then text=text..string.format(" / hold %.1fs",item.hold) end
            if item.risky then text=text.."\nMonster near this item" end
            local speed=item.mode=="BAG" and not (bag.hand and bag.handWeight==nil) and carryMultiplier(bag.weight+item.weight,bag.capacity,bag.hand and bag.handWeight or nil)
                or item.mode=="HANDS" and carryMultiplier(bag.weight,bag.capacity,item.weight)
            if speed then text=text..string.format("\nAfter pickup: %.0f%% carry speed",speed*100) end
            if item.mode=="FULL" or item.mode=="HANDS" then local swap=swapAdvice(item,bag); if swap then text=text.."\n"..swap end end
            if root and not clearSight(root.Position,item.part.Position,item.target) then text=text.."\nObstructed / route unknown" end
            table.insert(advice,text)
        end end
        set(lootText,"Text",options.ExtractFocus and "Extraction focus: loot advice paused" or #advice>0 and table.concat(advice,"\n\n") or "No matching loot within 120 studs")
        local exit,travel=exits[1],nil
        local minimum=modules.GameConfig and num(modules.GameConfig.ExtractMinimum) or 0
        if open and minimum>0 and (num(player:GetAttribute("Money")) or 0)<minimum then exitStatus=exitStatus..string.format(" / need $%.0f",minimum) end
        if exit and root then
            local speed=hum and num(hum.WalkSpeed); if speed and speed>0.1 then travel=exit.distance/speed+(modules.GameConfig and num(modules.GameConfig.ExtractHold) or K.DefaultExtractHold) end
            extractText.Text="Exit "..exitStatus..string.format("\n%.0f studs / %s / %s",exit.distance,direction(exit.part.Position),floorText(root.Position,exit.part.Position))
                ..(travel and string.format("\nRough ~%ds straight-line estimate; route unknown",math.ceil(travel)) or "\nTravel estimate unavailable")
        else extractText.Text="Exit "..exitStatus.."\nNo exit loaded on this client" end
        if open and not exitWasOpen and not monster then notice("Extraction is open",1) end; exitWasOpen=open==true
        if inMatch and not monster and remaining then
            if remaining<=math.min(K.ReminderMaximum,math.max(30,(travel or 0)+K.ReminderLead)) and not deadlineWarned.leave then deadlineWarned.leave=true; notice("Extraction reminder: "..math.ceil(remaining).."s left. Consider heading to the exit.",2) end
            if remaining<=15 and not deadlineWarned.final then deadlineWarned.final=true; notice("Round ends in "..math.ceil(remaining).."s",3) end
        end
        local threat=threats[1]
        set(threatText,"Text",threat and string.format("%s / %s\n%.0f studs / %s / %s",threat.data.name,threat.state,threat.distance,direction(threat.part.Position),floorText(root.Position,threat.part.Position)) or "No loaded monsters detected")
        set(threatText,"TextColor3",threat and threat.danger and C.danger or C.text)
        alert.Visible=options.Alerts and not monster and threat~=nil and threat.danger==true; if alert.Visible then alert.Text=threatText.Text end
        local huntLines={string.format("%d living survivors loaded",#survivors)}
        if tracked and root then
            table.insert(huntLines,string.format("Target: %s\n%.0f studs / %s / %s%s",trackedPlayer.DisplayName,tracked.distance,direction(tracked.part.Position),floorText(root.Position,tracked.part.Position),trackedPlayer:GetAttribute("Hiding")==true and " / HIDING" or ""))
        elseif trackedPlayer then
            table.insert(huntLines,"Target: "..trackedPlayer.DisplayName.." / currently unloaded")
            if lastSeen and root and os.clock()-lastSeen.time<=K.LastSeenLife then table.insert(huntLines,string.format("Last seen %.1fs ago / %s / %s",os.clock()-lastSeen.time,direction(lastSeen.position),floorText(root.Position,lastSeen.position))) else lastSeen=nil end
        end
        set(huntText,"Text",table.concat(huntLines,"\n"))
        local placeLines={}; for i,item in ipairs(places) do if i>2 then break end
            table.insert(placeLines,item.info..string.format("\n%.0f studs / %s / %s",item.distance,direction(item.part.Position),floorText(root.Position,item.part.Position)))
        end
        set(hidingText,"Text",#placeLines>0 and table.concat(placeLines,"\n\n") or "No closets or vents loaded within 120 studs")
        set(cameraText,"Text",cameraReason)
        set(noticeLabel,"Text",os.clock()<messageUntil and message or "Home hides the panel and restores mouse control.")
        set(toast,"Visible",os.clock()<messageUntil)
        set(toast,"Text",message)
        if camera and camera.ViewportSize.X>0 and camera.ViewportSize.Y>0 and (cache.viewX~=camera.ViewportSize.X or cache.viewY~=camera.ViewportSize.Y) then
            local view=camera.ViewportSize; cache.viewX,cache.viewY=view.X,view.Y
            uiScale.Scale=math.min(1,math.max(0.35,(view.X-32)/360),math.max(0.35,(view.Y-110)/550))
            panel.Position=UDim2.fromOffset(math.clamp(panel.Position.X.Offset,0,math.max(0,view.X-360*uiScale.Scale)),
                math.clamp(panel.Position.Y.Offset,0,math.max(0,view.Y-550*uiScale.Scale-40)))
        end
        if monster and root then autoGrab(root,character,survivors) else grabStatus="OFF / survivor role"; grabAttempt=nil end
        set(grabNote,"Text","Auto-grab: "..grabStatus.."\nHunt selection tracks a person; grab requests do not name a target.")
        local health={}
        for _,spec in ipairs(specs) do
            local state=moduleStatus[spec.name]
            if not ready(spec.name) then table.insert(health,spec.name..": "..(state and state.state or "waiting"))
            elseif state.error then table.insert(health,spec.name..": state query failed") end
        end
        local failedObjects=0; for target in pairs(cache.candidateFailures) do if target.Parent then failedObjects=failedObjects+1 end end
        if failedObjects>0 then table.insert(health,tostring(failedObjects).." object(s) temporarily unavailable")
        else systemErrors["Object data"],systemErrors["Marker cleanup"]=nil,nil end
        for name in pairs(systemErrors) do if name~="Object data" then table.insert(health,name..": interrupted (see Output)") end end
        if #health==0 then table.insert(health,"Input, camera and item systems ready") end
        set(healthText,"Text",table.concat(health,"\n"))
    end
    pollDependencies(true); syncButtons()
    refresh(); selectPage("Overview"); setPanel(true)
    local elapsed,reconciliation=0,0
    local function safeUpdate()
        local ok,err=pcall(update)
        if ok then systemErrors.Update=nil
        else
            set(alert,"Visible",false)
            for _,marker in pairs(markers) do pcall(set,marker.billboard,"Enabled",false) end
            report("Update",err)
            set(healthText,"Text","Data update interrupted; displays may be stale. See Output.")
        end
    end
    connect(Run.Heartbeat,function(dt)
        elapsed,reconciliation=elapsed+dt,reconciliation+dt
        if elapsed<K.UpdateInterval then return end
        elapsed=elapsed%K.UpdateInterval
        pollDependencies(); syncButtons()
        local full=dirty or reconciliation>=K.ReconcileInterval
        if full then cache.partsDirty=true; cache.tagsDirty=true end
        local ok,err=pcall(discover,full)
        if ok then if full then reconciliation=0 end; systemErrors.Discovery=nil
        else report("Discovery",err) end
        safeUpdate()
    end)
    discover(true); safeUpdate()
    print("[SOD Helper] v8 loaded. Home toggles the panel. Unload restores local changes.")
end

-- Teardown attempts every resource; failures retain ownership and remain retryable.
cleanup=function()
    if cleanupComplete then return true end
    if cleaning then return false,"Cleanup already in progress" end
    cleaning,stopped=true,true
    for name in pairs(options) do options[name]=false end
    local errors={}
    local function attempt(label,fn)
        local ok,err=pcall(fn)
        if not ok then table.insert(errors,label..": "..tostring(err)) end
        return ok
    end
    for name in pairs(bindings) do if attempt(name,function() Run:UnbindFromRenderStep(name) end) then bindings[name]=nil end end
    if restoreCamera then attempt("Camera restore",restoreCamera) end
    if releaseMouse then attempt("Cursor restore",releaseMouse) end
    local function disconnectAll(list)
        for i=#list,1,-1 do if attempt("Connection",function() list[i]:Disconnect() end) then table.remove(list,i) end end
    end
    disconnectAll(connections)
    for owner,list in pairs(watchers) do disconnectAll(list); if #list==0 then watchers[owner]=nil end end
    for _,list in pairs(groups) do disconnectAll(list) end
    for job in pairs(jobs) do
        if not job.thread or coroutine.status(job.thread)=="dead" then jobs[job]=nil
        elseif attempt("Loader task",function() task.cancel(job.thread) end) then jobs[job]=nil end
    end
    if removeMarker then for target in pairs(markers) do attempt("Marker",function() removeMarker(target) end) end end
    table.clear(candidates); table.clear(huntTargets); trackedPlayer,lastSeen=nil,nil
    if #errors==0 then
        if gui then attempt("GUI",function() gui:SetAttribute("CleanupComplete",true); gui:Destroy() end) end
        if initializing then for _,object in ipairs(created) do attempt("Startup object",function() object:Destroy() end) end end
    end
    cleaning=false
    if #errors==0 then cleanupComplete=true; table.clear(created); return true end
    local reason=table.concat(errors,"; ")
    warn("[SOD Helper] Cleanup incomplete; execute again to retry: "..reason)
    return false,reason
end
local ok,err=pcall(initialize)
if not ok then
    for _=1,3 do if cleanup() then break end end
    error("[SOD Helper] Startup failed: "..tostring(err))
end
initializing=false; table.clear(created)
