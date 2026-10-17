task.wait(7)
-- DTEC JoeJoe Automation.lua: put this complete file in the executor's auto-execute folder.
-- Version 0.80: walk to lobby queue pads without character teleports.
-- Claims owned startup items once; sells disposable loot and raw mined gems for Coins.
-- Quest limits: church save at 20 minutes (depth: 35) or 1.5 minutes idle; remembers streamed-out churches.
-- Results include the Roblox account username; ordinary return does not save carried loot.
-- Hides the default Gameplay Paused popup after readiness; streaming pauses still apply.
-- Includes local ending reports, personal Discord delivery, cached discovery, and ranged dodging.
-- Optional class quests: native combat, mining, sales, shredding, turrets, dungeons, fuel, potions and upgrades.
-- Quest mode OFF preserves chest-only travel; no healing, mining or team purchases.
-- Every execution waits seven seconds first; this script never queues itself for teleport.
-- All additional readiness checks and recovery happen automatically.
local SOURCE = [======[
return function(source)
    local env = (getgenv and getgenv()) or _G
    local KEY = "__ChestFarmAutoLoop_20261009"
    local REVISION = 80
    local VERSION = string.format("%.2f", REVISION / 100)
    local BUILD = "v0.80-lobby-walking"
    local job = tostring(game.PlaceId) .. ":" .. tostring(game.JobId)
    local previous = env[KEY]
    if previous and previous.job == job and previous.thread
        and coroutine.status(previous.thread) ~= "dead"
        and ((previous.revision or 1) > REVISION
            or ((previous.revision or 1) == REVISION and previous.build == BUILD)) then
        return -- Repeated execution must not start a second owner in this server.
    end
    if previous and previous.farm then
        if previous.job==job and not previous.questDriveLease and
            (previous.farm.questDriving or previous.farm.questSeating or previous.questCalls and previous.questCalls.drive) then
            previous.questDriveLease={ctx=previous.farm,drill=previous.farm.drill,abandoned=true,
                stopIssued=previous.questCalls and previous.questCalls.drive and previous.questCalls.drive.method=='StopDriving'}
        end
        pcall(previous.farm.dispose)
    end
    if previous and previous.thread and previous.thread ~= coroutine.running() then
        pcall(task.cancel, previous.thread)
    end
    if previous and previous.connections then
        for _, connection in ipairs(previous.connections) do pcall(function() connection:Disconnect() end) end
    end
    if previous and previous.fullbright then pcall(previous.fullbright.cleanup)end
    if previous and previous.lobbyWalker then pcall(previous.lobbyWalker.cleanup);previous.lobbyWalker=nil end
    if previous and previous.gui then pcall(previous.gui.dispose); previous.gui = nil end
    local s = previous and previous.job == job and previous or {}
    s.questInputRelease=s.questInputRelease or previous and previous.questInputRelease
    if s.revision ~= REVISION or s.build ~= BUILD then s.freshChecked=nil end
    s.revision, s.version, s.build = REVISION, VERSION, BUILD
    print("[DTEC JoeJoe Automation] Version "..VERSION.." active ("..BUILD..")")
    s.pauseNoticeHidden, s.pauseNoticeRetryAt, s.pauseNoticeWarned = nil, nil, nil
    s.job, s.owner, s.connections = job, {}, {}
    s.farm, s.teleporting, s.status = nil, false, nil
    s.signalsBound = false
    s.teleportSignalsBound, s.departureBound = false, false
    s.currencyBound, s.classBound = false, false
    s.achievementsLoading = false
    env[KEY] = s
    local owner = s.owner
    local lobbyWalker
    local Players = game:GetService("Players")
    local RS = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local CollectionService = game:GetService("CollectionService")
    local TeleportService = game:GetService("TeleportService")
    local buildStore = (function()
-- One executor file, separate profiles by immutable Roblox UserId.
-- Native teleport settings are account-tagged backups, never a global profile.
return function(api)
    local s,env=api.state,api.env or _G
    local FILE='DTEC JoeJoe Automation'
    local player=(api.Players or game:GetService('Players')).LocalPlayer
    local user=player and tonumber(player.UserId)
    local key=user and user==user and user>0 and user<math.huge and tostring(user) or nil
    s.accountStores=s.accountStores or {}
    if key and s.accountStores[key]then return s.accountStores[key]end
    local store={accountId=key,file=FILE}
    local profile
    local dirty={}
    local http
    pcall(function()http=game:GetService('HttpService')end)
    local function resolve()
        if not key then
            local current=(api.Players or game:GetService('Players')).LocalPlayer
            local id=current and tonumber(current.UserId)
            if id and id==id and id>0 and id<math.huge then
                key=tostring(id);store.accountId=key;profile=nil
                if not s.accountStores[key]then s.accountStores[key]=store end
            end
        end
        return key and s.accountStores[key]
    end
    local function readDocument()
        local reader=env.readfile or readfile
        if type(reader)~='function' or not http then return {schema=1,accounts={}},false end
        local found,body=pcall(reader,FILE)
        if not found then
            -- A transient read failure is not evidence that an existing shared
            -- account document is absent. Use an optional executor probe; keep
            -- the tagged dirty backup until this exact file becomes readable.
            local exists=env.isfile or isfile
            if type(exists)=='function'then
                local checked,present=pcall(exists,FILE)
                if not checked or present~=false then return {schema=1,accounts={}},false end
            end
            return {schema=1,accounts={}},true
        end
        local decoded,data=pcall(http.JSONDecode,http,body)
        if not decoded or type(data)~='table' or data.schema~=1 or type(data.accounts)~='table'then
            return {schema=1,accounts={}},false -- Preserve corrupt/unsupported files instead of erasing other accounts.
        end
        return data,true
    end
    local function load()
        if profile then return profile end
        profile={}
        if not key then return profile end
        local ok,value=pcall(function()return api.TeleportService:GetTeleportSetting('DTEC JoeJoe Automation:'..key)end)
        local document=readDocument()
        if type(document.accounts[key])=='table'then profile=document.accounts[key]end
        -- Disk is authoritative when present; a stale teleport snapshot must not
        -- replace newer preferences/reports. Fill absent sections from backup.
        if ok and type(value)=='table' and value.accountId==key and type(value.profile)=='table'then
            dirty=type(value.dirtySections)=='table' and value.dirtySections or {}
            for section,data in pairs(value.profile)do if profile[section]==nil or dirty[section]then profile[section]=data end end
        end
        return profile
    end
    function store:get(section)
        local canonical=resolve()
        if canonical and canonical~=store then return canonical:get(section)end
        return load()[section]
    end
    function store:set(section,value)
        local canonical=resolve()
        if canonical and canonical~=store then return canonical:set(section,value)end
        if not key then return false end
        local data=load()
        data[section]=value
        dirty[section]=true
        pcall(function()api.TeleportService:SetTeleportSetting('DTEC JoeJoe Automation:'..key,
            {accountId=key,profile=data,dirtySections=dirty})end)
        local writer=env.writefile or writefile
        local document,writable=readDocument()
        if type(writer)~='function' or not http or not writable then
            if not s.accountSaveNotice then
                s.accountSaveNotice=true
                warn('[DTEC JoeJoe Automation] File save unavailable or invalid; using account-tagged session/teleport settings.')
            end
            return false
        end
        local merged=type(document.accounts[key])=='table' and document.accounts[key] or {}
        for name,entry in pairs(data)do if merged[name]==nil or dirty[name]then merged[name]=entry end end
        merged[section]=value -- Own this section only, preserving concurrent sequential writes to others.
        document.accounts[key]=merged
        local encoded,body=pcall(http.JSONEncode,http,document)
        if not encoded then return false end
        local saved=pcall(writer,FILE,body)
        if saved then
            local verified,valid=readDocument()
            local entry=verified.accounts[key]
            local function equal(a,b)
                if type(a)~=type(b)then return false end
                if type(a)~='table'then return a==b end
                for name,v in pairs(a)do if not equal(v,b[name])then return false end end
                for name in pairs(b)do if a[name]==nil then return false end end
                return true
            end
            saved=valid and equal(entry,merged)
        end
        if saved then
            profile=merged;dirty={};s.accountSaveNotice=nil
            pcall(function()api.TeleportService:SetTeleportSetting('DTEC JoeJoe Automation:'..key,{accountId=key,profile=merged,dirtySections=dirty})end)
        end
        return saved
    end
    if key then s.accountStores[key]=store end
    return store
end

end)()
    local saveStore=buildStore({state=s,env=env,Players=Players,TeleportService=TeleportService})
    local function saveFresh(value)return saveStore:set('freshRun',value)end
    local function loadFresh()
        if not s.freshChecked then
            local value=saveStore:get('freshRun')
            if saveStore.accountId then
                if value==true then s.forceFresh=true end
                if s.forceFresh==true then saveStore:set('freshRun',true)end
                s.freshChecked=true
            end
        end
    end
    loadFresh()
    local unpackValues = table.unpack or unpack
    local function pack(...) return { n = select("#", ...), ... } end
    local function now() return os.clock() end
    s.stats = s.stats or { started = now(), coreEarned = 0, coinEarned = 0, gems = 0,
        promptFires = 0, lootObserved = 0, badgeClaims = 0, chestProgress = 0 }
    for _,key in ipairs({'questCashRequests','questCashConfirmed','questCashRejected','confirmedQuestUpgrades',
        'questMedicalRequests','questMedicalStackReceipts','questHealingHpRises','questMedicalUseTimeouts'})do
        if s.stats[key]==nil then s.stats[key]=0 end
    end
    s.chests = s.chests or {}
    s.stats.chestStarts = s.stats.chestStarts or 0
    s.claims = s.claims or {}
    s.gemSeen = s.gemSeen or setmetatable({}, { __mode = "k" })
    local function owned() return env[KEY] == s and s.owner == owner end
    local requestSlots = { "request", "rewardRequest", "classRequest", "skipRequest", "probeRequest", "equipmentRequest", "lootRequest", "lootQuery", "upgradeRequest" }
    local function requestSlot(kind)
        if kind == "claim-reward" or kind == "claim-vip" then return "rewardRequest" end
        if kind == "class-data" then return "classRequest" end
        if kind == "skip-cutscene" then return "skipRequest" end
        if kind == "probe" then return "probeRequest" end
        if kind == "equip-weapon" then return "equipmentRequest" end
        if kind == "loot-action" then return "lootRequest" end
        if kind == "loot-query" then return "lootQuery" end
        if kind == "team-upgrade" then return "upgradeRequest" end
        return "request"
    end
    -- Migrate an outstanding older call without cancelling or sending it twice.
    if s.request and requestSlot(s.request.kind) ~= "request" then
        local slot = requestSlot(s.request.kind)
        s[slot], s.request = s.request, nil
    end
    s.requestBackoff = s.requestBackoff or {}
    local function status(message)
        if s.status ~= message then s.status = message; print("[ChestFarm Auto] " .. message) end
    end
    local function connect(signal, fn)
        local connection = signal:Connect(function(...) if owned() then fn(...) end end)
        table.insert(s.connections, connection)
        return connection
    end
    local buildFullbright = (function()
-- Always-on display lighting. Preserve native Event/night quest state and UI effects.
return function(api)
    local F,records={},setmetatable({}, {__mode='k'})
    local ok,lighting=pcall(function()return game:GetService('Lighting')end)
    local function force(object,key,value)
        pcall(function()
            local row=records[object]
            if not row then row={};records[object]=row end
            local saved=row[key]
            local current=object[key]
            if not saved then saved={before=current,applied=value};row[key]=saved
            elseif current~=saved.applied then saved.before=current end
            saved.applied=value
            if current~=value then object[key]=value end
        end)
    end
    local white=lighting and Color3.fromRGB(255,255,255)
    function F.step()
        if not ok or not lighting or not api.owned()then return end
        force(lighting,'Ambient',white);force(lighting,'OutdoorAmbient',white)
        force(lighting,'Brightness',5);force(lighting,'GlobalShadows',false)
        force(lighting,'FogStart',0);force(lighting,'FogEnd',1000000)
        force(lighting,'ExposureCompensation',0)
        -- Late/replaced atmosphere and the native cave darkness effect are
        -- small Lighting child lists. Do not disable death/UI color corrections.
        for _,effect in ipairs(lighting:GetChildren())do
            if effect:IsA('Atmosphere')then force(effect,'Density',0);force(effect,'Haze',0)
            elseif effect.Name=='Cave_ColorCorrection' and effect:IsA('ColorCorrectionEffect')then force(effect,'Enabled',false)end
        end
    end
    function F.cleanup()
        if F.connection then pcall(function()F.connection:Disconnect()end);F.connection=nil end
        for object,row in pairs(records)do
            for key,saved in pairs(row)do pcall(function()
                if object[key]==saved.applied then object[key]=saved.before end
            end)end
        end
        records=setmetatable({}, {__mode='k'})
    end
    if lighting then
        F.step()
        F.connection=api.connect(api.RunService.Stepped,F.step)
    end
    return F
end

end)()
    s.fullbright=buildFullbright({owned=owned,connect=connect,RunService=RunService})
    local function character()
        local player = Players.LocalPlayer
        local model = player and player.Character
        local humanoid = model and model:FindFirstChildOfClass("Humanoid")
        local root = model and model:FindFirstChild("HumanoidRootPart")
        return player, model, humanoid, root
    end
    local function alive(player, model, humanoid, root)
        return player and model and model.Parent and humanoid and root and root.Parent
            and humanoid.Health > 0 and player:GetAttribute("RejoinDead") ~= true
    end
    local function child(parent, name) return parent and parent:FindFirstChild(name) end
    local function services()
        local packages = child(RS, "Packages")
        local index = child(packages, "_Index")
        local knitPackage = child(index, "sleitnick_knit@1.4.6")
        if not knitPackage and index then
            for _, candidate in ipairs(index:GetChildren()) do
                if candidate.Name:match("^sleitnick_knit@") then knitPackage = candidate; break end
            end
        end
        return child(child(knitPackage, "knit"), "Services"), packages
    end
    local function remote(service, method)
        local rf = child(child(s.services, service), "RF")
        local object = child(rf, method)
        return object and object:IsA("RemoteFunction") and object or nil
    end
    local function event(service, name)
        local object = child(child(child(s.services, service), "RE"), name)
        return object and object:IsA("RemoteEvent") and object.OnClientEvent or nil
    end
    local function controller(name)
        if not s.knit then return nil end
        local ok, value = pcall(s.knit.GetController, name)
        return ok and value or nil
    end
    local REPORT_SOURCE = [=====[return function(api)
    local s, env, now = api.state, api.env, api.now
    local R = {}
    local saveStore=assert(api.saveStore,'DTEC account store is required')
    local http
    -- User-authorized personal default, shared across devices and accounts.
    local DEFAULT_WEBHOOK="https://discord.com/api/webhooks/1551830162650435584/V_EItPsWyCQDQgEvZlAGjaH4XoKXchAD6UbPwEiiJ6mPUmiU-2cOlioFzvPW79KlZGgu"
    local function currentAccount()
        local ok,player=pcall(function()return (api.Players or game:GetService('Players')).LocalPlayer end)
        local id=ok and player and tonumber(player.UserId)
        return id and id==id and id>0 and id<math.huge and id%1==0 and tostring(id) or nil
    end
    local function endpoint(value)
        if type(value)~='string' then return end
        local base,suffix=value:match('^(https://discord%.com/api/webhooks/%d+/[%w_-]+)(.*)$')
        if base and (suffix=='' or suffix=='?wait=true')then return base..'?wait=true' end
    end
    local function reportingConfiguration()
        local account=currentAccount()
        if not account or account~=saveStore.accountId or env.DTECReportingEnabled==false then return end
        -- An explicit override is rechecked before dispatch; no separate file
        -- or per-account opt-in is needed for the personal built-in default.
        if env.DTECWebhookURL~=nil then
            local url=endpoint(env.DTECWebhookURL)
            if url then return account,url,'environment' end
            return
        end
        local url=endpoint(DEFAULT_WEBHOOK)
        if url then return account,url,'default' end
    end
    local function notice(message)
        if s.reportNotice~=message then s.reportNotice=message;warn('[DTEC JoeJoe Automation Results] '..message)end
    end
    local function clock()return os.time()end
    local ok
    ok,http=pcall(function()return game:GetService('HttpService')end)
    if not ok then http=nil end
    local ledger=saveStore:get('reports')
    local migrate=saveStore.accountId and s.reportLedger and s.reportAccountId==nil
    if s.reportLedger and (s.reportAccountId==nil or s.reportAccountId==saveStore.accountId)then ledger=s.reportLedger end
    if s.reportAccountId and s.reportAccountId~=saveStore.accountId then s.reportRun=nil end
    ledger=type(ledger)=='table' and ledger or {}
    ledger.records=type(ledger.records)=='table' and ledger.records or {}
    s.reportLedger,s.reportAccountId=ledger,saveStore.accountId
    if migrate then saveStore:set('reports',ledger)end
    local ledgerAccount=saveStore.accountId
    local function readyLedger()
        local saved=saveStore:get('reports')
        local account=saveStore.accountId
        if not account or currentAccount()~=account then return false end
        if ledgerAccount~=account then
            ledger=type(saved)=='table' and saved or {}
            ledger.records=type(ledger.records)=='table' and ledger.records or {}
            ledgerAccount=account;s.reportLedger,s.reportAccountId=ledger,account
        end
        return true
    end
    local function persist()return saveStore:set('reports',ledger)end
    local function clean(text, limit)
        text = tostring(text):gsub('[%c]', ' '):gsub('[@`*_~|<>]', '')
        return text:sub(1, limit or 100)
    end
    local function finite(value)
        value = tonumber(value)
        return value and value == value and math.abs(value) < math.huge and value >= 0 and value or nil
    end
    local function clearHealthWatch(record)
        record=record or s.reportHealthWatch
        if not record then return end
        if record.connection then pcall(record.connection.Disconnect,record.connection)end
        if s.reportHealthWatch==record then s.reportHealthWatch=nil end
    end
    clearHealthWatch() -- Retire an older reporter's read-only event handler on replacement.
    local function watchHealth(run,ctx)
        local player=(api.Players or game:GetService('Players')).LocalPlayer
        local h=ctx.humanoid
        if not h or ctx.character~=player.Character or h.Parent~=ctx.character then return end
        local record=s.reportHealthWatch
        if record and (record.run~=run or record.character~=ctx.character or record.humanoid~=h)then
            clearHealthWatch(record);record=nil
        end
        if not record then
            record={run=run,character=ctx.character,humanoid=h,health=finite(h.Health),maximum=finite(h.MaxHealth)}
            s.reportHealthWatch=record
        end
        if record.connection or not h.HealthChanged then return end
        local function observe()
            if s.reportHealthWatch~=record or s.reportRun~=run or run.ended
                or currentAccount()~=ledgerAccount or player.Character~=record.character
                or h.Parent~=record.character then clearHealthWatch(record);return end
            -- Read the current native properties, never a supplied event value.
            -- No action, inventory/map scan, snapshot trigger, send or file write.
            local hp,maximum=finite(h.Health),finite(h.MaxHealth)
            if not hp or not maximum or maximum<=0 then return end
            local progress=run.farmProgress;if not progress then return end
            local previous=record.health
            if previous and record.maximum and maximum<record.maximum then previous=math.min(previous,maximum)end
            if previous and hp<previous then
                progress.lastHpDropFrom=math.max(0,math.min(100,previous/maximum*100))
                progress.lastHpDropTo=math.max(0,math.min(100,hp/maximum*100));progress.lastHpDropAt=now()
            end
            if hp>0 then
                local ratio=math.max(0,math.min(100,hp/maximum*100))
                progress.lastLivingHp=ratio;progress.lowLivingHp=math.min(progress.lowLivingHp or ratio,ratio)
            end
            record.health,record.maximum=hp,maximum
        end
        local ok,connection=pcall(function()return h.HealthChanged:Connect(observe)end)
        if ok then record.connection=connection end
    end
    local function attribute(item, key)
        local db = s.itemDatabase
        if db and type(db.GetAttribute) == 'function' then
            local read, value = pcall(db.GetAttribute, item, key)
            if read and value ~= nil then return value end
        end
        if type(item) ~= 'string' then return item:GetAttribute(key) end
    end
    local function identity(item)
        local armor = item:GetAttribute('ArmorName')
        if armor then return tostring(armor) end
        local db = s.itemDatabase
        if db and type(db.GetId) == 'function' then
            local read, value = pcall(db.GetId, item)
            if read and value then return tostring(value) end
        end
        return item:GetAttribute('ItemDatabaseId') or item.Name
    end
    local function snapshot(player)
        local counts, models = {}, {}
        local containers = {}
        if player:FindFirstChild('Backpack') then containers[#containers + 1] = player:FindFirstChild('Backpack') end
        if player.Character then containers[#containers + 1] = player.Character end
        for _, container in ipairs(containers) do
            for _, item in ipairs(container and container:GetChildren() or {}) do
                if item.Parent and (item:IsA('Tool') or item:GetAttribute('ArmorName')
                    or (item:IsA('Model') and attribute(item, 'Tool') == true)) then
                    local id = identity(item)
                    local target = item:IsA('Model') and not item:GetAttribute('ArmorName') and models or counts
                    local rawCount = item:GetAttribute('MedicalStackCount')
                    local count = type(rawCount) == 'number' and finite(rawCount) or nil
                    count = count and count > 0 and math.max(1, math.floor(count)) or 1
                    target[id] = (target[id] or 0) + count
                end
            end
        end
        -- The active custom Model can coexist with its Backpack template.
        for id, count in pairs(models) do counts[id] = math.max(counts[id] or 0, count) end
        return counts
    end
    local function observeQuest(run)
        if not (s.config and s.config.classQuest)then return end
        local data=s.classData
        local name=type(data)=='table' and data.SelectedClass
        local progress=type(name)=='string' and type(data.ClassProgress)=='table' and data.ClassProgress[name]
        local level=type(progress)=='table' and finite(progress.Level)
        if not level or level<1 or type(progress.Objectives)~='table'then return end
        local quest=run.quest or {stages={},order={}};run.quest=quest
        local key=name..':'..level
        local stage=quest.stages[key]
        if not stage then
            stage={name=name,level=level,baseline={},latest={}}
            quest.stages[key]=stage;quest.order[#quest.order+1]=key
            for objective,count in pairs(progress.Objectives)do
                if type(objective)=='string' and finite(count)then stage.baseline[objective]=finite(count)end
            end
        end
        -- Copy values: class events can mutate the source table or replace it
        -- when a level changes. Earlier stages must keep their own observations.
        stage.latest={}
        for objective,count in pairs(progress.Objectives)do
            if type(objective)=='string' and finite(count)then stage.latest[objective]=finite(count)end
        end
        quest.currentName,quest.currentLevel=name,level
    end
    local driveStates={
        {'Previous native driver stop is unresolved','stop-pending'},
        {'Native driver stop has not cleared server ownership','stop-owner'},
        {'Drill made no observed distance progress','no-distance'},
        {'Drill start not confirmed','start-unconfirmed'},
        {'Approaching driver seat','seat-start'},
        {'Native physical seat and local driver presentation','seat-loading'},
        {'Native drill seats still loading','seat-loading'},
        {'Drill belongs to another driver','foreign-driver'},
        {'Another player is driving','foreign-driver'},
        {'Driving input paused while a text box is focused','text-focus'},
        {'No loaded free fuel for the drill','no-fuel'},
        {'Refuelling','refuel'},
        {'Driving damage observed','drive-defense-handoff'},
        {'Driving paused after native damage','drive-defense'},
        {'Wall drilling has no fresh damage receipt','wall-no-damage'},
        {'Wall needs over 10 seconds','wall-detour'},
        {'Wall estimate','wall-driving'},
        {'Wall damage rate loading','wall-driving'},
        {'Loot break: native driver released','loot-seat-clear'},
        {'Driving drill with native forward input','driving'},
        {'Mobile native seat throttle','driving'},
        {'Native forward input unavailable','driving'},
    }
    local exitLabels={
        phase={funding=true,loot=true,drive=true,upgrades=true,unknown=true},
        planner={waiting=true,complete=true,unsupported=true,advance=true,combat=true,mining=true,depth=true,
            fuel=true,chests=true,gold=true,sale=true,upgrades=true,potion=true,shred=true,turret=true,dungeon=true,unknown=true},
        nativeDungeon={yes=true,no=true,unknown=true},boundRoom={unavailable=true,none=true,mine=true,other=true},
        refuel={none=true,active=true,['other-drill']=true},
        driveLease={none=true,['other-context']=true,retired=true,active=true,['stop-accepted']=true,['stop-unresolved']=true,abandoned=true},
        equipmentTransport={none=true,settled=true,pending=true},
        routeGate={chest=true,feature=true,defense=true,dodge=true,bring=true,loot=true,equipment=true,['await-ack']=true,ready=true},
        route={parked=true,unparked=true},driver={none=true,self=true,other=true,invalid=true},
        seat={none=true,['sit-only']=true,drill=true,other=true},hotbar={visible=true,hidden=true,unavailable=true},
        work={recovery=true,['drive-defense']=true,['mine-transition']=true,mining=true,startup=true,combat=true,
            ['seat-entry']=true,driving=true,chest=true,delivery=true,other=true},
        stage={['head-start']=true,['stop-unresolved']=true,['stop-owner']=true,['seat-start']=true,
            ['start-timeout']=true,['start-retry']=true,['seats-loading']=true,['foreign-driver']=true,
            ['fuel-empty']=true,['fuel-loading']=true,refuelling=true,['seat-exit']=true,['text-focus']=true,
            ['drive-stalled']=true,wall=true,['pickaxe-unready']=true,['mining-wait']=true,startup=true,
            ['chest-scan']=true,['chest-open']=true,['delivery-unconfirmed']=true,driving=true,['planner-wait']=true},
        flags={currentChest=true,featureHold=true,questOwns=true,chestLease=true,smartLoot=true,defense=true,
            equipment=true,loot=true,bring=true,delivery=true,cash=true,upgrade=true,equipmentLock=true,
            worldScan=true,workerFailed=true,chestPending=true,paused=true,cutscene=true,rebase=true},
        calls={drive=true,throttle=true,cash=true,drag=true,shop=true,wallet=true,upgrade=true,upgradeWallet=true,
            classes=true,crateRead=true,crateClaim=true,medicalDrop=true,healingWallet=true,inventoryDrop=true,place=true},
    }
    local function observeExit(run)
        if run.exitContext then return end
        local exit=s.questChurchExit;local detail=exit and exit.observed
        if type(detail)~='table' or not finite(detail.at) or detail.at~=exit.requestedAt
            or detail.at<run.started or detail.at>now() or not finite(detail.runStarted)
            or detail.runStarted~=s.lootStarted then return end
        local copy={}
        for key,allowed in pairs(exitLabels)do
            local value=detail[key]
            if key=='flags' or key=='calls'then
                local values,seen={},{}
                if type(value)=='table'then for i=1,20 do
                    local label=value[i]
                    if type(label)=='string' and allowed[label] and not seen[label]then
                        seen[label]=true;values[#values+1]=label
                    end
                end end
                copy[key]=table.concat(values,', ')
            elseif type(value)=='string' and allowed[value]then copy[key]=value end
        end
        for _,key in ipairs({'idleAge','workerAge','walletAge','equipmentAge','fuel','capacity','refuelAge','driveRetryIn'})do
            local value=finite(detail[key]);if value and value>=0 then copy[key]=math.min(value,999999)end
        end
        run.exitContext=copy
    end
    local function exitText(run)
        local detail=run.exitContext
        if not detail then return end
        local function age(key)return detail[key] and string.format('%.0fs',detail[key])or 'unknown'end
        local function value(key)return detail[key] and string.format('%.0f',detail[key])or '?'end
        return 'Phase '..(detail.phase or 'unknown')..' | Work '..(detail.work or 'unknown')..' | Stage '..(detail.stage or 'unmapped')
            ..'\nIdle '..age('idleAge')..' | Worker pulse age '..age('workerAge')..' | Wallet age '..age('walletAge')
            ..'\nDriver '..(detail.driver or 'unknown')..' | Seat '..(detail.seat or 'unknown')
            ..' | Fuel '..value('fuel')..' / '..value('capacity')
            ..'\nRoute '..(detail.route or 'unknown')..' | Hotbar '..(detail.hotbar or 'unknown')..' | Equipment request age '..age('equipmentAge')
            ..'\nActive flags: '..(detail.flags~='' and detail.flags or 'none')
            ..'\nPending calls: '..(detail.calls~='' and detail.calls or 'none')
            ..'\nFrozen when the exit was requested; observations do not establish the cause.'
    end
    local function handoffText(run)
        local d=run.exitContext
        if not d or not(d.planner or d.nativeDungeon or d.boundRoom or d.refuel or d.driveLease or d.routeGate or d.equipmentTransport)then return end
        local function label(key)return d[key] or 'unknown'end
        local function seconds(key)return d[key] and string.format('%.0fs',d[key])or 'unknown'end
        return 'Planner '..label('planner')..' | Native InDungeon '..label('nativeDungeon')..' | Bound room '..label('boundRoom')
            ..'\nRefill intent '..label('refuel')..' | Age '..seconds('refuelAge')..' | Drive retry in '..seconds('driveRetryIn')
            ..'\nDrive lease '..label('driveLease')..' | Equipment transport '..label('equipmentTransport')..' | Route gate '..label('routeGate')
            ..'\nFrozen native/local state; a gate or binding alone does not establish the cause.'
    end
    local function observeFarm(run)
        observeExit(run)
        local progress=run.farmProgress
        if not progress then
            progress={baseline={},latest={},invalid={},partial=now()>run.started+.001}
            run.farmProgress=progress
        end
        local revision=finite(s.revision)
        local version=revision and revision%1==0 and string.format('%.2f',revision/100) or nil
        if version then
            progress.firstVersion=progress.firstVersion or version
            if version~=progress.firstVersion then progress.changedVersion=true end
            progress.latestVersion=version
        end
        local mode=s.config and s.config.classQuest
        if mode==true then progress.questsOn=true elseif mode==false then progress.questsOff=true end
        if s.config and type(s.config.driveDepth)=='boolean'then progress.drivingEnabled=s.config.driveDepth end
        local wallet=finite(s.questWallet)
        if wallet then progress.lastCoins=wallet end
        local ctx=s.farm
        if ctx and ctx.active then
            pcall(watchHealth,run,ctx)
            local text=type(s.questStatus)=='string' and s.questStatus or ''
            for _,entry in ipairs(driveStates)do
                if text:find(entry[1],1,true)==1 then
                    progress.lastDriveState,progress.lastDriveStateAt=entry[2],now();break
                end
            end
            local cycle=ctx.questDepthEconomy
            local phase=cycle and cycle.phase
            if phase=='funding' or phase=='upgrades' or phase=='drive' or phase=='loot'then progress.lastDrivePhase=phase end
            if progress.driveSeen==nil then progress.driveSeen=false end
            if ctx.questDriving and ctx.drill and type(ctx.drill.GetAttribute)=='function'then
                local ok,owner=pcall(ctx.drill.GetAttribute,ctx.drill,'DriverUserId')
                local read,player=pcall(function()return (api.Players or game:GetService('Players')).LocalPlayer end)
                if ok and read and player and owner==player.UserId then progress.driveSeen=true end
            end
            if ctx.questMobileThrottle then progress.mobileFramesSeen=true end
            local living,hp,maximum=pcall(function()
                local player=(api.Players or game:GetService('Players')).LocalPlayer
                if ctx.character~=player.Character or not ctx.humanoid then return end
                return finite(ctx.humanoid.Health),finite(ctx.humanoid.MaxHealth)
            end)
            if living and hp and hp>0 and maximum and maximum>0 then
                local ratio=math.max(0,math.min(100,hp/maximum*100))
                progress.lastLivingHp=ratio;progress.lowLivingHp=math.min(progress.lowLivingHp or ratio,ratio)
                if ctx.questHealing then
                    local stages={['safety-handoff']=true,['route-handoff']=true,['cash-receipt']=true,
                        ['item-reservation']=true,['consume-receipt']=true,['handler-wait']=true,
                        ['unresolved-item']=true,['supply-checkout']=true,['shop-search']=true,
                        ['cash-search']=true,['funding-sale']=true,['safe-chest']=true,['no-ready-supply']=true}
                    progress.lastRecoveryStage=stages[ctx.questRecoveryStage] and ctx.questRecoveryStage or 'unobserved'
                end
                progress.lastLivingWork=ctx.questHealAttempt and 'medical-use' or ctx.questHealing and 'recovery'
                    or ctx.questDrivingDefense and 'drive-defense' or ctx.questCombat and 'combat'
                    or ctx.questMining and 'mining' or ctx.questDriving and 'driving' or ctx.questSeating and 'seat-entry'
                    or ctx.questChestTaking and 'chest' or ctx.questMineEntry and 'mine-transition'
                    or s.questDelivery and 'item-delivery' or 'other'
                local calls=s.questCalls or {}
                progress.lastLivingReservation=calls.upgrade and 'upgrade' or calls.shop and 'shop'
                    or calls.drag and 'item' or calls.medicalDrop and 'medical-drop'
                    or s.equipmentRequest and 'equipment' or calls.cash and 'cash'
                    or calls.wallet and 'checkout-balance' or calls.healingWallet and 'medical-balance'
                    or calls.upgradeWallet and 'upgrade-balance' or 'none'
            end
        end
        local drive=s.questActivity and s.questActivity.drill
        local advance=drive and finite(drive.lastProgressAt)
        if advance and advance>=run.started and advance<=now()then progress.lastNativeDriveAdvanceAt=advance end
        -- Scalar counters only. Observations never inspect the map, yield,
        -- request an action or reset an existing diagnostic/scheduler budget.
        for _,key in ipairs({'lootObserved','promptFires','questCashRequests','questCashConfirmed','questCashRejected',
            'confirmedQuestUpgrades','questMedicalRequests','questMedicalStackReceipts','questHealingHpRises','questMedicalUseTimeouts'})do
            local value=finite((s.stats or {})[key])
            if value then
                if progress.baseline[key]==nil then
                    progress.baseline[key]=value
                    if now()>run.started+.001 then progress.partial=true end
                end
                if progress.latest[key] and value<progress.latest[key]then progress.invalid[key]=true end
                progress.latest[key]=value
            end
        end
    end
    function R.observe(player, isPlanet, live)
        if not readyLedger()then return end
        if not isPlanet then return end
        local run = s.reportRun
        if not run then
            run = {id = s.job, started = now(), gained = {}, cores = nil, account = player.Name}
            s.reportRun = run
        end
        if run.ended then return end
        run.account = run.account or player.Name
        run.cores = finite(player:GetAttribute('CoresEarned')) or run.cores
        observeFarm(run)
        observeQuest(run)
        -- Retain the last living inventory when death removes the character/tools.
        if live and s.itemDatabase then
            local counts = snapshot(player)
            if not run.baseline then run.baseline = counts end
            for id, count in pairs(counts) do
                local gain = math.max(0, count - (run.baseline[id] or 0))
                run.gained[id] = math.max(run.gained[id] or 0, gain)
            end
            run.carried = counts
        end
    end
    local function itemsText(counts, missing)
        if not counts then return missing end
        local rows = {}
        for id, count in pairs(counts) do
            if count > 0 then
                local label = attribute(id, 'DisplayName') or id:gsub('_', ' ')
                rows[#rows + 1] = clean(label, 80) .. (count > 1 and (' x' .. count) or '')
            end
        end
        table.sort(rows)
        if #rows == 0 then return 'None observed' end
        local text = ''
        for i, row in ipairs(rows) do
            if #text + #row > 900 then return text .. '\n+' .. (#rows - i + 1) .. ' more item types' end
            text = text .. (#text > 0 and '\n' or '') .. row
        end
        return text
    end
    local function numberText(value)
        local digits=tostring(math.floor(value))
        while true do local nextText,count=digits:gsub('^(%d+)(%d%d%d)','%1,%2');digits=nextText;if count==0 then break end end
        return digits
    end
    local objectiveNames={CutlassKills='Cutlass kills',FlintlockKills='Flintlock kills',SellGoldItems='Gold items sold',
        MineGems='Gems mined',MineOres='Ores mined',MineCoal='Coal mined',MineDiamond='Diamonds mined',MineRuby='Rubies mined',
        TotalDepth='Total depth',EnemyKills='Enemies defeated'}
    local function questText(run)
        observeQuest(run)
        local quest=run.quest
        if not quest then return 'Quest data not ready; progress unavailable.' end
        local rows={clean(quest.currentName,60)..' - Lv '..numberText(quest.currentLevel)}
        for _,key in ipairs(quest.order)do
            local stage=quest.stages[key]
            if #quest.order>1 then rows[#rows+1]=clean(stage.name,60)..' - Lv '..numberText(stage.level)..' objectives:'end
            local entry=s.questCatalog and s.questCatalog[stage.name]
            local goals=type(entry)=='table' and type(entry.Requirements)=='table' and entry.Requirements[stage.level+1]
            local objectives={}
            for objective in pairs(type(goals)=='table' and goals or stage.latest)do
                if type(objective)=='string'then objectives[#objectives+1]=objective end
            end
            table.sort(objectives)
            if #objectives==0 then rows[#rows+1]=type(goals)=='table' and 'No pending objectives.' or 'Objective counts unavailable.' end
            for _,objective in ipairs(objectives)do
                local current=stage.latest[objective] or 0
                local before=stage.baseline[objective] or 0
                local delta=current-before
                local label=objectiveNames[objective] or objective:gsub('(%l)(%u)','%1 %2'):gsub('_',' ')
                local goal=type(goals)=='table' and finite(goals[objective])
                rows[#rows+1]=clean(label,70)..': '..numberText(current)..(goal and ' / '..numberText(goal) or '')
                    ..(delta>=0 and ' (+'..numberText(delta)..')' or ' (counter decreased)')
            end
        end
        rows[#rows+1]='+ = gain since first quest observation this run.'
        local text=''
        for _,row in ipairs(rows)do
            if #text+#row>900 then return text..'\nMore objectives omitted.'end
            text=text..(#text>0 and '\n' or '')..row
        end
        return text
    end
    local function farmText(run)
        observeFarm(run)
        local progress=run.farmProgress
        local version=progress.firstVersion or 'unavailable'
        if progress.changedVersion then version=version..' → '..progress.latestVersion..' (changed)' end
        local mode=progress.questsOn and progress.questsOff and 'CHANGED'
            or progress.questsOn and 'ON' or progress.questsOff and 'OFF' or 'unknown'
        local function delta(key)
            local before,after=progress.baseline[key],progress.latest[key]
            return before and after and not progress.invalid[key] and tostring(math.floor(after-before)) or 'unavailable'
        end
        return 'Version '..version..' | Quests '..mode
            ..'\nChest removals observed: '..delta('lootObserved')..' | Prompt calls: '..delta('promptFires')
            ..'\nDriving enabled: '..(progress.drivingEnabled==true and 'YES' or progress.drivingEnabled==false and 'NO' or 'unknown')
            ..' | Native driver observed: '..(progress.driveSeen==true and 'YES' or progress.driveSeen==false and 'NO' or 'unavailable')
            ..'\nLast drive phase: '..(progress.lastDrivePhase or 'unavailable')
            ..' | Last observed Coins: '..(progress.lastCoins and string.format('%.0f',progress.lastCoins) or 'unavailable')
            ..'\nLast drive state: '..(progress.lastDriveState or 'unobserved')
            ..(progress.lastDriveStateAt and string.format(' | observed %.0fs before report',math.max(0,now()-progress.lastDriveStateAt))or '')
            ..'\nCash pickups: '..delta('questCashRequests')..' requests | '..delta('questCashConfirmed')..' verified | '..delta('questCashRejected')..' rejected'
            ..(progress.mobileFramesSeen and ' | Mobile frame input observed' or '')
            ..(progress.partial and '\nCounts cover only the observed part of this run.' or '')
    end
    local function survivalText(run)
        local progress=run.farmProgress
        local function delta(key)
            local before,after=progress.baseline[key],progress.latest[key]
            return before and after and not progress.invalid[key] and tostring(math.floor(after-before)) or 'unavailable'
        end
        local last=progress.lastLivingHp and string.format('%.0f%%',progress.lastLivingHp)or 'unavailable'
        local low=progress.lowLivingHp and string.format('%.0f%%',progress.lowLivingHp)or 'unavailable'
        return 'Observed living HP: last '..last..' | low '..low
            ..'\nLast living work: '..(progress.lastLivingWork or 'unavailable')..' | Reservation: '..(progress.lastLivingReservation or 'unavailable')
            ..'\nLast recovery stage: '..(progress.lastRecoveryStage or 'unobserved')
            ..'\nMedical packets: '..delta('questMedicalRequests')..' | Stack receipts: '..delta('questMedicalStackReceipts')
            ..'\nHP rises during recovery: '..delta('questHealingHpRises')..' | Medical timeouts: '..delta('questMedicalUseTimeouts')
            ..'\nUpgrades confirmed: '..delta('confirmedQuestUpgrades')
            ..'\nNative drive advance: '..(progress.lastNativeDriveAdvanceAt and string.format('last observed %.0fs before report',math.max(0,now()-progress.lastNativeDriveAdvanceAt))or 'not observed')
            ..'\nObserved HP drop: '..(progress.lastHpDropAt and string.format('%.0f%% → %.0f%%; %.0fs before report',progress.lastHpDropFrom,progress.lastHpDropTo,math.max(0,now()-progress.lastHpDropAt))or 'not observed')
            ..'\nHP rises do not prove medicine caused them.'
    end
    local function payload(outcome, reason)
        local run = s.reportRun
        if not run or run.ended then return nil end
        local seconds = math.floor(math.max(0, now() - run.started))
        local fields = {
            {name = 'Cores earned', value = run.cores and tostring(math.floor(run.cores)) or 'Unavailable', inline = true},
            {name = 'Run time', value = string.format('%dm %02ds', math.floor(seconds / 60), seconds % 60), inline = true},
            {name = 'Items gained (observed)', value = itemsText(run.baseline and run.gained, 'Inventory not ready'), inline = false},
            {name = 'Last carried gear', value = itemsText(run.carried, 'Inventory not ready'), inline = false},
            {name = 'Loot saved', value = outcome == 'RETURNED' and 'No verified save — ordinary lobby return does not save carried loot.'
                or outcome == 'EXTRACTED' and 'Game saved-exit confirmed; saved item contents remain unverified.'
                or 'No verified gear save.', inline = false}
        }
        fields[#fields + 1] = {name = 'Run Cores/min', value = run.cores and seconds > 0
            and string.format('%.1f', run.cores * 60 / math.max(1, now() - run.started)) or 'Unavailable', inline = true}
        fields[#fields + 1] = {name = 'Account', value = tostring(run.account or 'Unavailable'):gsub('[^%w_]', ''):sub(1,256), inline = true}
        if s.config and s.config.classQuest then
            fields[#fields+1]={name='Quest progress (observed)',value=questText(run),inline=false}
        end
        fields[#fields+1]={name='Farm diagnostics',value=farmText(run),inline=false}
        local frozen=exitText(run)
        if frozen then fields[#fields+1]={name='At exit request (observed)',value=frozen,inline=false}end
        local handoff=handoffText(run)
        if handoff then fields[#fields+1]={name='Quest handoff (observed)',value=handoff,inline=false}end
        if run.farmProgress.questsOn then fields[#fields+1]={name='Survival diagnostics',value=survivalText(run),inline=false}end
        return {id = run.id, status = 'queued', attempts = 0, created = clock(), revision=s.revision, version=s.version, build=s.build, body = {
            username = 'DTEC JoeJoe Automation',
            embeds = {{title = 'Earth run - ' .. outcome, color = outcome == 'LOSS' and 15158332
                or (outcome == 'EXTRACTED' and 3066993 or 15844367), description = clean(reason, 250), fields = fields,
                footer = {text = 'Item observations are not proof of loot saved. Run ' .. clean(run.id, 100)}}}
        }}
    end
    local function enqueue(record)
        for _, existing in ipairs(ledger.records) do if existing.id == record.id then persist(); return end end
        ledger.records[#ledger.records + 1] = record
        -- Retain recent dedup receipts without growing the executor file indefinitely.
        while #ledger.records > 30 do table.remove(ledger.records, 1) end
        persist()
    end
    function R.finish(outcome, reason)
        if not readyLedger()then return end
        local record = payload(outcome, reason)
        if not record then return end
        s.reportRun.ended = true
        clearHealthWatch()
        ledger.departure = nil
        enqueue(record)
        R.pump()
    end
    function R.departing(outcome, reason)
        if not readyLedger()then return end
        local record = payload(outcome, reason)
        if record then ledger.departure = record; persist() end
    end
    function R.failedTeleport()
        if not readyLedger()then return end
        if ledger.departure and ledger.departure.id == s.job then ledger.departure = nil; persist() end
    end
    function R.arrived(isLobby)
        if isLobby then clearHealthWatch()end
        if not readyLedger()then return end
        local staged = ledger.departure
        if isLobby and staged and staged.id ~= s.job then
            ledger.departure = nil; enqueue(staged)
        end
    end
    function R.pump()
        if not readyLedger()then return end
        local waiting = false
        for _, record in ipairs(ledger.records) do if record.status == 'queued' then waiting = true; break end end
        if not waiting then return end
        local account,url,configuration=reportingConfiguration()
        if not account then return end -- Local end-run observations remain available without external reporting.
        if not http then notice('HttpService unavailable; farming continues without Discord reports.'); return end
        local send = env.request or env.http_request or http_request or request
            or (env.syn and env.syn.request) or (syn and syn.request)
            or (env.http and env.http.request)
        if type(send) ~= 'function' then
            notice('Executor HTTP request API unavailable; results remain queued.'); return
        end
        for _, record in ipairs(ledger.records) do
            if record.status == 'queued' and clock() >= (record.retryAt or 0) then
                local scheduledLedger,scheduledAccount=ledger,ledgerAccount
                local previousAttempts=record.attempts or 0
                local function allowed()
                    local current,currentURL,source=reportingConfiguration()
                    return current==account and currentURL==url and source==configuration
                        and ledger==scheduledLedger and ledgerAccount==scheduledAccount
                        and saveStore.accountId==scheduledAccount and currentAccount()==scheduledAccount
                end
                local function persistOwn()
                    if currentAccount()==scheduledAccount and saveStore.accountId==scheduledAccount
                        and ledger==scheduledLedger and ledgerAccount==scheduledAccount then persist()end
                end
                local function unsent()
                    record.status,record.sentAt,record.attempts='queued',nil,previousAttempts
                    persistOwn()
                end
                -- Persist before dispatch. An uncertain send is never blindly repeated after teleport/re-execution.
                record.status, record.sentAt = 'sending', clock()
                record.attempts = (record.attempts or 0) + 1
                persist()
                task.spawn(function()
                    if not allowed()then unsent();return end
                    local encoded, body = pcall(function() return http:JSONEncode(record.body) end)
                    if not encoded then record.status = 'failed'; persistOwn(); notice('Result encoding failed.'); return end
                    -- Empty Lua tables encode ambiguously; use an explicit empty JSON array for mentions.
                    body = '{"allowed_mentions":{"parse":[]},' .. body:sub(2)
                    if not allowed()then unsent();return end
                    local sent, response = pcall(send, {Url = url, Method = 'POST',
                        Headers = {['Content-Type'] = 'application/json'}, Body = body})
                    local code = sent and type(response) == 'table' and tonumber(response.StatusCode or response.Status)
                    if code and code >= 200 and code < 300 then
                        record.status = 'sent'; print('[Earth Results] End-of-run report sent.')
                    elseif code == 429 and record.attempts < 4 then
                        local decoded, data = pcall(function() return http:JSONDecode(response.Body or '') end)
                        local delay = decoded and type(data) == 'table' and finite(data.retry_after) or nil
                        record.status, record.retryAt = 'queued', clock() + math.max(2, math.min(delay or 10, 3600))
                        notice('Discord rate limited the report; retry queued.')
                    else
                        record.status = code and code >= 400 and code < 500 and 'failed' or 'uncertain'
                        notice('Discord report ' .. record.status .. (code and (' (HTTP ' .. code .. ')') or '')
                            .. '; farming continues. Uncertain sends are not duplicated.')
                    end
                    persistOwn()
                end)
                return
            end
        end
    end
    return R
end
]=====]
    local reports = assert((loadstring or load)(REPORT_SOURCE, '@EarthResults'))()({
        state = s, env = env, now = now, TeleportService = TeleportService, saveStore = saveStore
    })
    local function reportDeparture()
        local player, model, humanoid, root = character()
        if player and player:GetAttribute('SavedExitTeleportLocked') == true then
            return 'EXTRACTED', (s.questChurchExit and s.questChurchExit.reason..'; ' or '')
                .. 'Game saved-exit state confirmed; lobby arrival and saved item contents remain unverified.'
        end
        local live = alive(player, model, humanoid, root)
        if not live then return 'LOSS', 'Died; returning to lobby.' end
        if s.extractionAttempt and s.extractionAttemptAt and now() - s.extractionAttemptAt <= 30 then
            return 'RETURNED', 'Departure followed a church prompt, but no game saved-exit state was observed; loot saving is unverified.'
        end
        return 'RETURNED', (s.returnReason or 'Run left for the lobby') .. '; no verified victory or church extraction.'
    end
    local function stopFarm()
        local farm = s.farm
        s.farm = nil
        if farm then pcall(farm.dispose) end
    end
    local function restoreZoneTouches()
        if s.touchParts then
            for part, value in pairs(s.touchParts) do
                pcall(function() if part.Parent then part.CanTouch = value end end)
            end
            s.touchParts = nil
        end
    end
    local function restoreZoneOrigin(zone)
        if lobbyWalker then lobbyWalker.leave(zone)end
    end
    local function muteZoneTouches(model)
        s.touchParts=s.touchParts or {}
        for _,part in ipairs(model:GetDescendants())do
            if part:IsA('BasePart')then
                if s.touchParts[part]==nil then s.touchParts[part]=part.CanTouch end
                part.CanTouch=false
            end
        end
    end
    local function configureParty()
        local c = controller("PartyCreateController")
        if not c or not c.CreateUI then return nil end
        c.PartySize, c.Place, c.FriendsOnly = 1, "Earth", false
        c.SelectedMapButton = child(child(c.CreateUI, "MapSelect"), "Unranked")
        -- Cancel the game's default 20-second Ranked auto-start, and guard its StartParty method.
        if c.AutoStartThread then pcall(task.cancel, c.AutoStartThread); c.AutoStartThread = nil end
        if c.Zone then
            c.StartRequest = s.partyToken or c.StartRequest
        end
        -- Repeatedly rebuilding these UI tweens every tick wastes work.
        if s.partyConfigured ~= c or s.partyConfiguredZone ~= c.Zone then
            s.partyConfigured, s.partyConfiguredZone = c, c.Zone
            pcall(function() c:UpdateUI(); c:UpdateMapSelection(); c:UpdateFriendsOnly() end)
        end
        return c
    end
    -- Transition calls remain serialized. Independent read/reward/skip calls have
    -- bounded slots so a stuck optional feature cannot lock the gameplay loop.
    local function request(kind, service, method, args, finished, dispatchGuard)
        local slot = requestSlot(kind)
        if s[slot] or now() < (s.requestBackoff[service .. "." .. method] or 0) then return false end
        if slot == "request" and (s.awaiting or now() < (s.nextAction or 0)) then return false end
        local rf = remote(service, method)
        if not rf then status("Waiting for " .. service .. "." .. method); return false end
        local token = { kind = kind, started = now(), callback = finished,
            method = service .. "." .. method, character = Players.LocalPlayer and Players.LocalPlayer.Character,
            farm = s.farm, owner = owner }
        s[slot] = token
        if slot == "request" then stopFarm() end
        status("Requesting " .. method)
        task.spawn(function()
            -- Recovery selections must still be permitted when their queued
            -- task actually runs. A skipped guard proves no RPC was sent.
            local allowed=owned()
            if allowed and dispatchGuard then
                local checked,value=pcall(dispatchGuard,token)
                allowed=checked and value==true
            end
            -- A replacement owns the native actions now. Even a guard that
            -- yielded cannot authorize this retired runtime to send its RPC.
            if not allowed or not owned()then
                token.result=pack(true,false)
                token.result.notDispatched=true
                token.settled=true
                return
            end
            token.result = pack(pcall(function() return rf:InvokeServer(unpackValues(args, 1, args.n or #args)) end))
            token.settled = true
        end)
        return true
    end
    local function waitTransition(kind, detail, duration)
        s.awaiting = { kind = kind, detail = detail, started = now(), duration = duration or 75 }
    end
    local function accepted(result) return result[1] and result[2] ~= false end
    local function hasBadge(list, id)
        if type(list) ~= "string" then return false end
        local wanted = string.format("%.0f", id)
        for token in list:gmatch("%d+") do if token == wanted then return true end end
        return false
    end
    local function observeClassData(data)
        if type(data) ~= "table" then return end
        -- Native ClassesController retains fields omitted by an update.
        -- Preserve ownership through a progress-only event; never invent it.
        local merged = {}
        for key, value in pairs(s.classData or {}) do merged[key] = value end
        for key, value in pairs(data) do merged[key] = value end
        s.classData = merged
        s.classObservedAt = now()
        -- Count server-reported objective changes separately from prompt attempts.
        for name, progress in pairs(data.ClassProgress or {}) do
            local objectives = type(progress) == "table" and progress.Objectives
            if type(objectives) == "table" and type(objectives.OpenChest) == "number" then
                s.chestProgressByClass = s.chestProgressByClass or {}
                local previousValue = s.chestProgressByClass[name]
                if previousValue and objectives.OpenChest > previousValue then
                    -- Per update, use the largest delta; several owned classes can progress together.
                    s.pendingChestProgress = math.max(s.pendingChestProgress or 0, objectives.OpenChest - previousValue)
                end
                s.chestProgressByClass[name] = objectives.OpenChest
            end
        end
        s.stats.chestProgress = s.stats.chestProgress + (s.pendingChestProgress or 0)
        s.pendingChestProgress = nil
    end
    local function updateMetrics(player)
        if s.farm and s.farm.pruneConnections then s.farm.pruneConnections()end
        for _, record in pairs(s.chests) do
            if record.attempted and record.model and not record.model.Parent and not record.removalRecorded then
                record.removalRecorded, record.retired = true, true
                s.stats.lootObserved, s.lastLootAt = s.stats.lootObserved + 1, now()
                print('[ChestFarm] Observed chest removal: ' .. record.model.Name)
            end
            local current=s.farm and s.farm.currentChest
            if record.model and not record.model:IsDescendantOf(workspace)
                and not(current and current.model==record.model)then
                -- Keep retry/removal accounting, without retaining an unloaded
                -- model, all its descendants and a dead prompt through the run.
                record.model,record.prompt,record.entry=nil,nil,nil
            end
        end
        local earned = tonumber(player:GetAttribute("CoresEarned"))
        if earned then
            if s.lastRunCores and not s.currencyBound then
                s.stats.coreEarned = s.stats.coreEarned + math.max(0, earned - s.lastRunCores)
            end
            s.lastRunCores = earned
        end
        if s.itemCategories and s.itemDatabase then
            local baseline = not s.gemBaseline or s.metricCharacter ~= player.Character
            local containers = {}
            if child(player, "Backpack") then table.insert(containers, child(player, "Backpack")) end
            if player.Character then table.insert(containers, player.Character) end
            for _, container in ipairs(containers) do
                for _, tool in ipairs(container:GetChildren()) do
                    if tool:IsA("Tool") then
                        local seen = s.gemSeen[tool]
                        if not seen then seen = { baseline = baseline }; s.gemSeen[tool] = seen end
                        if not seen.classified then
                        local ok, id = pcall(s.itemDatabase.GetId, tool)
                        if ok and id then
                            seen.classified = true
                            if not seen.baseline and (s.itemCategories.Gems or {})[id] then s.stats.gems = s.stats.gems + 1 end
                        end
                        end
                    end
                end
            end
            s.gemBaseline, s.metricCharacter = true, player.Character
        end
        if now() >= (s.metricsAt or s.stats.started + 60) then
            s.metricsAt = now() + 60
            local minutes = math.max((now() - s.stats.started) / 60, 0.01)
            local coreRate = (s.currencyBound or s.lastRunCores) and string.format("%.1f", s.stats.coreEarned / minutes) or "n/a"
            local coinRate = s.currencyBound and string.format("%.1f", s.stats.coinEarned / minutes) or "n/a"
            local gemRate = s.itemCategories and s.itemDatabase and string.format("%.1f", s.stats.gems / minutes) or "n/a"
            print(string.format("[ChestFarm Rates] %s earned Cores/min | %s earned Coins/min | %s gem tools/min | %d prompt attempts | %d observed loot removals | %d server chest-progress increments | %d confirmed badge claims | %d chest prompt transitions",
                coreRate, coinRate, gemRate,
                s.stats.promptFires, s.stats.lootObserved, s.stats.chestProgress, s.stats.badgeClaims, s.stats.chestStarts))
        end
    end
    local function claimRewards(player)
        if not s.achievements then return end
        for _, group in pairs(s.achievements) do
            for name, badge in pairs(group) do
                if type(badge) == "table" and tonumber(badge.Reward) and badge.Reward > 0 and badge.BadgeID then
                    local record = s.claims[name]
                    if hasBadge(player:GetAttribute("ClaimedBadges"), badge.BadgeID) then
                        if record and record.sent and not record.confirmed then
                            record.confirmed = true; s.stats.badgeClaims = s.stats.badgeClaims + 1
                        end
                    elseif hasBadge(player:GetAttribute("Badges"), badge.BadgeID) and not (record and record.sent)
                        and now() >= ((record and record.retryAt) or 0) then
                        record = record or {}; s.claims[name] = record
                        if request("claim-reward", "BadgeAwardingService", "ClaimBadgeReward", pack(name), function(result)
                            -- A thrown reply cannot prove the native claim failed.
                            record.sent = not (result.notDispatched or result[1] and result[2] == false)
                            record.retryAt = now() + 15
                        end,function()
                            return owned() and Players.LocalPlayer==player and s.claims[name]==record
                                and hasBadge(player:GetAttribute("Badges"),badge.BadgeID)
                                and not hasBadge(player:GetAttribute("ClaimedBadges"),badge.BadgeID)
                        end) then record.sent=true;return end
                    end
                end
            end
        end
    end
    local function pumpRequest()
        for _, slot in ipairs(requestSlots) do
            local token = s[slot]
            if token then
                if not token.settled then
                    if now() - token.started > 30 and not token.warned then
                        token.warned = true
                        warn("[ChestFarm Auto] " .. token.kind .. " is still pending; this call will not be duplicated. Independent work continues.")
                    end
                elseif s[slot] == token then
                    s[slot] = nil
                    if token.teleportFailed then token.result = pack(true, false) end
                    -- Successful requests can advance immediately. Only failures back off.
                    if not accepted(token.result) then
                        s.requestBackoff[token.method or token.kind] = now() + 3
                    end
                    local staleLife = (token.kind == "revive" or token.kind == "probe" or token.kind == "equip-weapon" or token.kind == "loot-action")
                        and token.character ~= (Players.LocalPlayer and Players.LocalPlayer.Character)
                    if token.kind == "loot-action" and (token.farm ~= s.farm or token.owner ~= owner) then staleLife = true end
                    if token.callback and not staleLife then token.callback(token.result)
                    elseif token.callback and staleLife and token.kind=='equip-weapon' then
                        -- The old mutation has actually replied. Retire its local
                        -- pending flag without applying old-character equipment.
                        token.callback(pack(false,'Equipment reply belongs to the previous character'))
                    end
                end
            end
        end
        return s.request ~= nil
    end
    local function failTeleport(reason)
        reports.failedTeleport()
        s.extractionAttempt, s.extractionAttemptAt = nil, nil
        if s.request then s.request.teleportFailed = true end
        s.teleporting = false
        s.departureAt = nil
        s.awaiting, s.startedZone = nil, nil
        s.nextAction = now() + 5
        status("Teleport failed; retrying automatically: " .. tostring(reason))
    end
    local buildLobbyWalk = (function()
-- Lobby character travel uses native pathfinding and Humanoid:MoveTo only.
return function(api)
    local W,s,now={},api.state,api.now
    local function finite(n)return type(n)=='number' and n==n and math.abs(n)<math.huge end
    local function vector(v)
        local ok,x,y,z=pcall(function()return v.X,v.Y,v.Z end)
        return ok and finite(x) and finite(y) and finite(z)
    end
    local function horizontal(a,b)return math.sqrt((a.X-b.X)^2+(a.Z-b.Z)^2)end
    local function near(a,b,r)return vector(a) and vector(b) and horizontal(a,b)<=r and math.abs(a.Y-b.Y)<=6 end
    local function isLobby()return game.PlaceId==101906032112547 or workspace:FindFirstChild('Lobby')~=nil end
    local function current(job,queueEntry)
        local player,model,h,root=api.character()
        return api.owned() and game:IsLoaded() and isLobby() and api.enabled() and model and model.Parent and h and root and root.Parent
            and player.Character==model and finite(h.Health) and h.Health>0 and player:GetAttribute('RejoinDead')~=true
            and not s.teleporting and not s.departureAt and (not s.request or queueEntry and s.request.kind=='create') and not s.awaiting
            and not workspace:GetAttribute('InCutScene') and player.GameplayPaused~=true
            and not h.SeatPart and not h.Sit and root.Anchored~=true
            and not(type(player:GetAttribute('PendingSessionId'))=='string' and player:GetAttribute('PendingSessionId')~='')
            and (not job or job.character==model and job.humanoid==h and job.root==root and not job.cancelled)
    end
    function W.inside(zone,point)
        if not zone or not zone.Parent or not vector(point) or not vector(zone.Size)then return end
        local ok,p=pcall(zone.CFrame.PointToObjectSpace,zone.CFrame,point)
        if not ok or not vector(p)then return end
        return math.abs(p.X)<=zone.Size.X*.5 and math.abs(p.Z)<=zone.Size.Z*.5
            and math.abs(p.Y)<=zone.Size.Y*.5+8
    end
    local function disconnect(job)
        if job and job.blocked then pcall(job.blocked.Disconnect,job.blocked);job.blocked=nil end
        if job and job.path and type(job.path.Destroy)=='function'then pcall(job.path.Destroy,job.path)end
        if job then job.path=nil;job.points=nil end
    end
    local function settleQuery()
        local q=s.lobbyWalkQuery;if not q then return true end
        if not q.settled and q.cancelled and q.thread then
            pcall(task.cancel,q.thread)
            if coroutine.status(q.thread)=='dead'then q.settled=true;q.ok=false end
        end
        if not q.settled then return false end
        if q.cancelled or not current(q.job) or s.lobbyWalk~=q.job then
            if q.path and type(q.path.Destroy)=='function'then pcall(q.path.Destroy,q.path)end
        else
            local job=q.job
            if q.ok then
                job.path,job.points,job.index=q.path,q.points,1
                local event=q.path.Blocked
                if event and type(event.Connect)=='function'then
                    job.blocked=event:Connect(function(index)
                        if s.lobbyWalk==job and finite(index) and index>=job.index then job.repath=true end
                    end)
                end
            else
                if q.path and type(q.path.Destroy)=='function'then pcall(q.path.Destroy,q.path)end
                job.failures=job.failures+1;job.retryAt=now()+3
            end
        end
        if s.lobbyWalkQuery==q then s.lobbyWalkQuery=nil end
        return true
    end
    function W.stop(restore)
        local job=s.lobbyWalk
        if job then
            job.cancelled=true;disconnect(job)
            local _,model,h,root=api.character()
            if job.moving and api.owned() and model==job.character and h==job.humanoid and root==job.root
                and root.Parent and h.Health>0 and type(h.MoveTo)=='function'then
                pcall(h.MoveTo,h,root.Position) -- Cancel only this walk's last owned goal.
            end
            s.lobbyWalk=nil
        end
        local q=s.lobbyWalkQuery
        if q and (not job or q.job==job)then q.cancelled=true end
        settleQuery()
        if restore then api.restoreTouches()end
    end
    local function manual()
        local ok,uis=pcall(game.GetService,game,'UserInputService')
        if not ok or not uis or type(uis.GetFocusedTextBox)~='function'then return true end
        local read,focus=pcall(uis.GetFocusedTextBox,uis)
        if not read or focus then return true end
        if type(uis.IsKeyDown)=='function'then
            for _,name in ipairs({'W','A','S','D','Up','Down','Left','Right','Space'})do
                local key=Enum and Enum.KeyCode and Enum.KeyCode[name]
                if key then local good,down=pcall(uis.IsKeyDown,uis,key);if not good or down then return true end end
            end
        end
        -- This is the same native PlayerModule control read used by the
        -- exported TrainComponent. It observes actual thumbstick/gamepad input,
        -- independently of Humanoid.MoveDirection produced by our MoveTo.
        local player=api.Players.LocalPlayer
        local scripts=player:FindFirstChild('PlayerScripts');local module=scripts and scripts:FindFirstChild('PlayerModule')
        local controls
        if module then
            if W.controlsModule~=module then
                local read=W.controlsRead
                if not read or read.module~=module or read.settled and not read.controls and now()>=(read.retryAt or math.huge)then
                    read={module=module};W.controlsRead=read
                    -- Requiring PlayerModule can yield while native startup is
                    -- loading. Keep that read off the supervisor thread.
                    task.spawn(function()
                        local loaded,value=pcall(require,module)
                        local got,result=pcall(function()return loaded and value and value:GetControls()end)
                        read.controls=got and result or nil;read.retryAt=now()+10;read.settled=true
                    end)
                end
                if not read.settled or not read.controls then return true end
                W.controlsModule,W.controls=module,read.controls
            end
            controls=W.controlsModule==module and W.controls
        end
        if controls and type(controls.GetMoveVector)=='function'then
            local good,value=pcall(controls.GetMoveVector,controls)
            if not good or not vector(value) or math.abs(value.X)>.05 or math.abs(value.Z)>.05 then return true end
        else
            local c=api.controller('InputController')
            if c and (c.Platform=='Mobile' or c.Platform=='Console') or uis.TouchEnabled and not uis.KeyboardEnabled then return true end
        end
        return false
    end
    function W.guard()
        settleQuery()
        if not current(s.lobbyWalk)then W.stop(true);return false end
        if manual()then
            local exit=s.lobbyWalkExit;local _,_,_,root=api.character()
            if exit and exit.zone and root and W.inside(exit.zone,root.Position)==false then s.lobbyWalkExit=nil end
            s.lobbyWalkPauseUntil=now()+2;W.stop(true);return false
        end
        if now()<(s.lobbyWalkPauseUntil or 0)then W.stop(true);return false end
        return true
    end
    function W.entryAllowed(zone,model,h,root)
        local player,liveModel,liveHumanoid,liveRoot=api.character()
        return current(nil,true) and model==liveModel and h==liveHumanoid and root==liveRoot and player.Character==model
            and now()>=(s.lobbyWalkPauseUntil or 0) and not manual()
            and zone and zone.Parent and zone:IsDescendantOf(workspace) and W.inside(zone,root.Position)==true
            and (tonumber(zone:GetAttribute('PlayerCount'))or 0)==0 and (tonumber(zone:GetAttribute('State'))or 0)<=1
    end
    local function goalFor(zone,h,root)
        local hip=finite(h.HipHeight) and math.max(0,h.HipHeight) or 2
        local size=root.Size and root.Size.Y;local height=finite(size) and math.max(1,size)*.5 or 1
        local ok,goal=pcall(zone.CFrame.PointToWorldSpace,zone.CFrame,Vector3.new(0,zone.Size.Y*.5+hip+height,0))
        return ok and vector(goal) and goal or nil
    end
    local function query(job,goal)
        if not settleQuery()then return end
        local q={job=job,started=now()};s.lobbyWalkQuery=q
        q.thread=task.spawn(function()
            local ok=pcall(function()
                local service=game:GetService('PathfindingService')
                if not service or not current(job) or s.lobbyWalk~=job then return end
                local path=service:CreatePath({AgentRadius=2,AgentHeight=6,AgentCanJump=true,WaypointSpacing=4})
                q.path=path;path:ComputeAsync(job.root.Position,goal)
                if not current(job) or s.lobbyWalk~=job or q.cancelled or path.Status~=Enum.PathStatus.Success then return end
                local points=path:GetWaypoints()
                if type(points)~='table' or #points<1 or #points>128 then return end
                q.points={}
                for _,point in ipairs(points)do
                    if not vector(point.Position)then return end
                    q.points[#q.points+1]={position=point.Position,jump=point.Action==Enum.PathWaypointAction.Jump}
                end
                q.ok=true
            end)
            if not ok then q.ok=false end
            q.settled=true
        end)
    end
    function W.step(zone,mode,exit)
        if not W.guard()then api.status('Lobby walking yields to manual input, focus or native readiness');return false end
        local _,model,h,root=api.character()
        local goal=mode=='exit' and exit and exit.goal or zone and goalFor(zone,h,root)
        if not vector(root.Position) or not vector(goal)then W.stop(true);api.status('Lobby walking waits for loaded route geometry');return false end
        if mode=='enter' and W.inside(zone,root.Position)==true or mode=='exit' and near(root.Position,goal,2.5)then
            W.stop(false);return true
        end
        local job=s.lobbyWalk
        if job and (job.zone~=zone or job.mode~=mode or not near(job.goal,goal,2))then W.stop(false);job=nil end
        if not job then
            job={character=model,humanoid=h,root=root,zone=zone,mode=mode,goal=goal,started=now(),failures=0,
                progressAt=now(),progressPoint=root.Position};s.lobbyWalk=job
        end
        if not settleQuery()then
            local q=s.lobbyWalkQuery
            if now()-q.started>=8 and not q.cancelled then
                q.cancelled=true;job.failures=job.failures+1;job.retryAt=now()+3;settleQuery()
            end
            api.status('Lobby walking: waiting for the owned path computation');return false
        end
        if job.failures>=3 or now()-job.started>=60 then
            W.stop(true);s.lobbyWalkPauseUntil=now()+5
            api.status('Lobby walk blocked; waiting before another walking attempt');return false
        end
        if horizontal(root.Position,job.progressPoint)>=1 then job.progressPoint=root.Position;job.progressAt=now()end
        if job.repath or job.moving and now()-job.progressAt>=6 then
            disconnect(job);job.repath=nil;job.moving=nil;job.lastGoal=nil;job.failures=job.failures+1;job.retryAt=now()+1
            job.progressAt=now()
            if type(h.MoveTo)=='function'then pcall(h.MoveTo,h,root.Position)end
        end
        if not job.points then
            if now()>=(job.retryAt or 0)then query(job,goal)end
            api.status('Finding a walking path to the lobby '..(mode=='exit' and 'exit point' or 'pad'));return false
        end
        while job.index<=#job.points and near(root.Position,job.points[job.index].position,2)do job.index=job.index+1 end
        local point=job.points[job.index]
        if not point then
            disconnect(job);job.failures=job.failures+1;job.retryAt=now()+1
            api.status('Lobby path ended outside the pad; recalculating without teleporting');return false
        end
        if not current(job) or type(h.MoveTo)~='function'then W.stop(true);return false end
        api.muteTouches(model)
        if point~=job.lastGoal or now()>=(job.moveAt or 0)then
            if point.jump then h.Jump=true end
            local moved=pcall(h.MoveTo,h,point.position)
            if not moved then W.stop(true);api.status('Native lobby walking unavailable; waiting without teleporting');return false end
            job.lastGoal,job.moveAt,job.moving=point,now()+3,true
        end
        api.status('Walking to the lobby '..(mode=='exit' and 'exit point' or 'Earth pad'))
        return false
    end
    function W.leave(zone)
        local _,model,h,root=api.character()
        if not model or not h or not root or not vector(root.Position)then return end
        if s.lobbyWalkExit and s.lobbyWalkExit.character==model then return end
        local origin=s.zoneOriginCharacter==model and s.zoneOrigin
        local goal=origin and origin.Position
        if not vector(goal) or zone and W.inside(zone,goal)~=false then
            if not zone or W.inside(zone,root.Position)==false then return end
            local ok,value=pcall(zone.CFrame.PointToWorldSpace,zone.CFrame,Vector3.new(zone.Size.X*.5+6,0,0))
            if not ok or not vector(value)then return end
            goal=Vector3.new(value.X,root.Position.Y,value.Z)
        end
        W.stop(false);s.lobbyWalkExit={character=model,goal=goal,zone=zone}
        s.zoneOrigin,s.zoneOriginCharacter=nil,nil
    end
    function W.exitStep()
        local exit=s.lobbyWalkExit;if not exit then return true end
        local _,model=api.character()
        if exit.character~=model then s.lobbyWalkExit=nil;W.stop(true);return true end
        if not W.step(exit.zone,'exit',exit)then return false end
        s.lobbyWalkExit=nil;api.restoreTouches();return true
    end
    function W.cleanup()W.stop(true)end
    return W
end

end)()
    local features
    lobbyWalker=buildLobbyWalk({state=s,now=now,owned=owned,Players=Players,character=character,
        enabled=function()return features and features.enabled()end,controller=controller,status=status,muteTouches=muteZoneTouches,
        restoreTouches=function()
            local c=controller('PartyCreateController')
            -- Keep the original touch/RPC serialization while a queue entry or
            -- native membership is unresolved. A paused walk is not a receipt.
            if not s.lobbyWalkExit and not s.touchCandidate and not s.zone and not(c and c.Zone) and not(s.request
                and (s.request.kind=='create' or s.request.kind=='start' or s.request.kind=='exit-zone'))then restoreZoneTouches()end
        end})
    s.lobbyWalker=lobbyWalker
    local function setup(player, packages)
        local shared = child(RS, "Shared")
        for _, descriptor in ipairs({ { "achievements", "Achievements" }, { "itemCategories", "ItemCategories" }, { "itemDatabase", "ItemDatabase" } }) do
            local key, name = descriptor[1], descriptor[2]
            local module = child(shared, name)
            if module and not s[key] and not s[key .. "Loading"] and now() >= (s[key .. "Retry"] or 0) then
                s[key .. "Loading"] = true
                task.spawn(function()
                    local ok, value = pcall(require, module)
                    if owned() then
                        if ok and type(value) == "table" then s[key] = value end
                        s[key .. "Loading"], s[key .. "Retry"] = false, now() + 10
                    end
                end)
            end
        end
        if not s.currencyBound then
            local signal = event("CurrencyService", "Update")
            if signal then
                s.currencyBound = true
                connect(signal, function(amount, balance, isCore)
                    local key = isCore and "coreEarned" or "coinEarned"
                    s.stats[key] = s.stats[key] + math.max(0, tonumber(amount) or 0)
                    if not isCore and type(balance)=="number" and balance==balance
                        and balance>=0 and balance<math.huge then
                        if features and features.quest and features.quest.observeCoins then
                            features.quest.observeCoins(balance)
                        else
                            s.questWallet,s.questWalletAt=balance,now()
                            s.questWalletVersion=(s.questWalletVersion or 0)+1
                        end
                    end
                end)
            end
        end
        if not s.classBound then
            local signal = event("ClassService", "UpdateClasses")
            if signal then s.classBound = true; connect(signal, function(data)
                observeClassData(data)
            end) end
        end
        if not s.knit and not s.knitLoading and child(packages, "Knit") then
            s.knitLoading = true
            task.spawn(function()
                local ok, value = pcall(require, packages.Knit)
                if owned() then
                    if ok then s.knit = value end
                    s.knitLoading = false
                end
            end)
        end
        if not s.teleportSignalsBound then
            s.teleportSignalsBound = true
            connect(player.OnTeleport, function(state)
                if state == Enum.TeleportState.Failed then failTeleport("OnTeleport.Failed")
                else
                    -- Stage on Started for destination delivery; send only once departure advances.
                    if state == Enum.TeleportState.Started then reports.departing(reportDeparture()) end
                    if state == Enum.TeleportState.InProgress then reports.finish(reportDeparture()) end
                    s.teleporting, s.teleportSince = true, now()
                    stopFarm(); status("Teleport in progress")
                end
            end)
            connect(TeleportService.TeleportInitFailed, function(who, _, message)
                if who == player then failTeleport(message) end
            end)
        end
        if not s.departureBound then
            local departure = event("TeleportManagerService", "DepartureFade")
            if departure then
                s.departureBound = true
                connect(departure, function() stopFarm(); s.departureAt = now() end)
            end
        end
        if not s.signalsBound then
            local created = event("TeleportManagerService", "CreateZone")
            local entered = event("TeleportManagerService", "EnteredZone")
            local exited = event("TeleportManagerService", "ExitedZone")
            if not created or not entered or not exited then return end
            s.signalsBound = true
            connect(created, function(zone)
                s.zone, s.zoneOwned, s.partyToken = zone, true, {}
                s.startedZone, s.touchCandidate = nil, nil
                task.defer(function() if owned() then configureParty() end end)
            end)
            connect(entered, function(zone)
                if s.zone ~= zone then s.zoneOwned = false end
                s.zone = zone
            end)
            connect(exited, function()
                local oldZone=s.zone
                s.zone, s.zoneOwned, s.startedZone, s.touchCandidate = nil, false, nil, nil
                s.partyToken = nil
                local c = controller("PartyCreateController")
                if c then c.StartRequest = nil end
                restoreZoneOrigin(oldZone)
                task.delay(0.2, function() if owned() and not s.lobbyWalkExit then restoreZoneTouches() end end)
            end)
        end
    end

    local FARM_SOURCE = [====[return function(ctx) local __farmConnect=ctx.connect; local __farmCheck=ctx.check; local __farmCapture=ctx.capture or function(_,fn)return fn end; return (function(...) return (function(p, V, N, Y, i, w, a, A, Q, x, b, M, t, f, u, h, j, K, q, B, J, v, e, W) e, B, J, M, q, K, h, W, u, j, b, Q, x, A, v, t, f = function(p, z) local i = K(z) local w = function(w) return B(p, { w, }, z, i) end return w end, function(B, w, Y, a) local r, UL, n, yL, xL, J, rL, y, d, QL, SL, qL, aL, WL, m, tL, OL, g, XL, X, R, D, jL, bL, YL, hL, P, iL, l, fL, gL, G, ML, v, CL, s, S, I, VL, uL, sL, h, H, IL, eL, vL, EL, wL, lL, K, GL, LL, f, o, E, NL, pL, mL, F, U, C, JL, AL, RL, KL, FL, cL, ZL, T, V, TL, zL, c, BL, O, HL, nL, k, Z, L, kL, dL while B do __farmCheck() if 8404549 > B then if B < 3481681 then if 2011092 > B then if B > 1064961 then if B < 1609571 then if 1429944 > B then if 1239341 > B then if B < 1072920 then V = 4388422 < 10995253 Q[J] = V B = 3322234 elseif 1085528 > B then B = X and 5601817 or 8311567 elseif 1160137 > B then d = p["table"] B = 8892653 V = d["insert"] d = V(O, g) else n = 14928581 >= 10257774 B = n and 4197832 or 4298790 end else if B < 1280438 then B = 10686391 elseif B < 1348147 then S = Q[Y[5]] g = S() S = Q[Y[6]] I = g < S B = I and 1793345 or 13638227 elseif B < 1400796 then B, V = p["C0hCoOBmSW4z"], { } else B = 16132387 end end else if B < 1505944 then if B < 1461734 then B = Q[Y[4]] K = p["string"] J = K["format"] v = b(v) E = Q[Y[5]] O = E() f = O * 100 K = { J("HP recovered (%.0f%%) - resuming.", f), } V = B(i(K)) B = Q[Y[6]] V = B() V, B = { }, p["1UvyrOAZFVpJ"] elseif B < 1485322 then V = { "locked", } B = p["cVcC1O7PYjIfh"] elseif 1497136 > B then Q[Y[20]] = Q[Y[20]] + 1 V = Q[Y[5]] n = g["Model"] H = n["Name"] B = 7368094 L = #d T = L .. " enemies nearby." n = ": " .. T U = H .. n r = "SKIP " .. U R = V(r) V = Q[Y[13]] R = V() else B = 10252446 end else if B < 1510312 then s = p["_G"] O = s["ScanX"] s = Q[Y[4]] B = 5335161 E = O <= s h = E elseif 1532646 > B then h = J B = W() Q[B] = h h = B B = W() Q[B] = f O = Q[h] E, f = O, B B = O and 14419034 or 5413919 elseif 1575133 > B then B = Q[Y[1]] J = p["Vector3"] v = J["zero"] B["AssemblyLinearVelocity"] = v B = Q[Y[1]] J = p["CFrame"] v = J["new"] K = Q[Y[4]] J = v(K) B["CFrame"] = J V, B = { }, p["ROxgz2l0i05Xr"] else V = W() Q[V] = m m = V V = Q[m] I = V["IsA"] I = I(V, "Model") B = I and 12336406 or 14876967 end end end else if 1817177 > B then if B > 1712184 then if 1726952 > B then d = p["task"] V = d["wait"] B = 11809829 d = V(0.15) elseif 1741176 > B then I = b(I) B = 2595611 elseif 1770548 > B then V = Q[Y[1]] B = V["Enabled"] V = { B, } B = p["XnvnjSt4Q3HERl"] else S = Q[Y[7]] g = S() I = not g B = I and 5773972 or 10007280 end else if B < 1657071 then B = { } Q[Y[2]] = B V = J % 35184372088832 Q[Y[4]] = V E = J % 255 B = 9771883 f = E + 2 Q[Y[5]] = f E = #v K[J] = "" s = "" m = E S = 1 g = 1 < 0 I = 1 - 1 elseif B < 1697108 then B = Q[Y[10]] J = Q[Y[11]] v[B] = J B = Q[Y[12]] J = { B(v), } V, B = { i(J), }, p["lh5PseQNXv0eU"] elseif 1703591 > B then B = 2638638 pL = C[1] o = pL else B = 11121287 end end else if 1918041 > B then if 1841386 > B then V = Q[J] B = V ~= "fR2yublGNor" B = B and 13124183 or 11317998 elseif B < 1868693 then I = p["math"] O = I["random"] I = W() Q[I] = O S = p["table"] O = S["concat"] r = p["table"] d, B = r, r and 6267227 or 3338712 elseif B < 1904569 then B = 14876967 else B = 7570852 end else if B < 1964428 then B = Q[Y[4]] V = B() B = 16500342 >= 3307824 V = { B, } B = p["OxSqrQUO0cliv"] elseif 2007693 > B then K = v["WaitForChild"] B = 12182679 K = K(v, "Humanoid", 5) J = K else B = p["_G"] v = 14380748 > 14527838 B["ChestFarm"] = v B = 13787160 end end end end else if 574474 > B then if B > 392133 then if B > 525443 then if 538447 > B then B = 8017606 O = f["Enabled"] E = not O V = E elseif 545901 > B then V = p["_G"] B = V["SafeMode"] B = B and 9609369 or 2274060 elseif B < 552440 then B = 2564830 else I = Q[J] S = 8217649 > 8562236 m = I == S B = m and 6453497 or 13662550 end else if 435026 > B then B = 2317164 K = v["MaxHealth"] J = K <= 0 V = J elseif B < 469246 then V = Q[Y[3]] B = 7493530 f = V("STOP after 40 empty scans.") V = p["_G"] E = 1917900 >= 16148366 V["ChestFarm"] = E elseif 497347 > B then B = 10686391 else B = W() Q[B] = s s = B m = Q[s] I = m["IsA"] I = I(m, "Model") B, X = I and 3736778 or 5826503, I end end else if B > 255903 then if 278661 > B then B = V and 13746815 or 10220335 elseif B < 297941 then B, X = 3425667, I elseif B < 336954 then B, V = p["DKU4gHLEVaxxF"], { V, } else V = p["task"] B = V["spawn"] v = Q[Y[6]] V = B(v) B = 4979985 end else if 87561 > B then B, X = 1079472, g elseif 174871 > B then J = Q[Y[3]] v = J % 32 E = Q[Y[3]] f = E - v h = f / 32 J = 13 - h f = Q[Y[4]] s = Q[Y[2]] X = 2 ^ J O = s / X E = f(O) h = E % 4294967296 f = 2 ^ v B = 7985072 K = h / f f = Q[Y[4]] s = K % 1 O = s * 4294967296 E = f(O) f = Q[Y[4]] O = f(K) h = E + O f = h % 65536 O = h - f E = O / 65536 s = f % 256 I = f % 256 m = f - I X = m / 256 m = E % 256 g = E % 256 S = E - g I = S / 256 O = { s, X, m, I, } Q[Y[1]] = O elseif 240527 > B then K = Q[Y[6]] B = 2698186 J = K == v V = J else V = p["task"] v = w[1] B = V["wait"] V = B(0.3) B = Q[Y[3]] V = B(v) B = p["_G"] J = 12333726 < 486718 B["SafeMode"] = J B, V = p["4eYXjxIQ9PybJ6"], { } end end end else if 855126 > B then if B < 697059 then if 602693 > B then v = p["_G"] V = v["SafeMode"] B = not V B = B and 12536449 or 2643329 elseif B < 610826 then K, O = K + f, not E V = h >= K V = O and V O = h <= K O = E and O V = O or V B = V and 4319611 B = B or 13056992 elseif B < 639260 then V = E or 20 f = V V = Q[Y[5]] s = p["string"] O = s["format"] m = Q[Y[4]] I = Q[Y[7]] s = { O("START scan x=%.0f -> %.0f, step %d", J, m, I), } B = 9272629 E = V(i(s)) else B = f and 6010191 or 6450991 end else if 727910 > B then B, V = p["lhdwuZDfJ7VLZ"], { } elseif 769576 > B then R = r k = R d[R] = k B = 15491759 elseif B < 812400 then B = Q[Y[1]] J = Q[Y[4]] h = p["Vector3"] K = h["new"] h = K(0, 5, 0) v = J + h B["CFrame"] = v V, B = { }, p["RdSTEnvwRUBHUu"] else B = 3322234 end end else if B < 964029 then if 918230 > B then D = YL B = 10850024 elseif B < 943575 then B = 1228690 elseif 950679 > B then r = g["Model"] R = r["Parent"] B, V = R and 5867209 or 8588739, R else d = Q[Y[8]] R = d() d = Q[Y[9]] V = R < d B = V and 14627229 or 947254 end else if B < 994143 then B = 15862886 elseif B < 1038942 then B = { } Q[Y[2]] = B v = Q[Y[3]] B = p["WbO1tKfqeZe9la"] V = v["Stepped"] J = u(595914, { Y[4], Y[5], Y[6], Y[1], Y[7], Y[8], }) v = __farmConnect v = v(V, J) Q[Y[1]] = v V = Q[Y[7]] J = V("NOCLIP ON (safe mode).") V = { } else B = 8311567 end end end end end else if B < 2651989 then if 2388112 > B then if 2279311 > B then if 2208252 > B then if 2058753 > B then K = Q[Y[9]] B = { } v, h = B, K B = 10880782 f = 1 E = 1 < 0 K = 1 - 1 elseif 2109309 > B then B = 2660989 f = J["Position"] K = f elseif 2158057 > B then V, B = { }, p["1Xf0UZsd8gWN4"] else V = Q[Y[23]] E = V() V = Q[Y[5]] B = p["lldyNIb4f3kX"] E = V("STOP scan.") V = { } end else if B < 2227270 then B = Q[Y[12]] V = B() V = { "ok", } B = p["JkeD1O4nCoQhL"] elseif B < 2241006 then V = { "no-prompt", } B = p["VFd2289VPIPG"] elseif 2258060 > B then h = Q[Y[7]] f = h() V = not f B = V and 11226927 or 13903632 else B = 8607109 <= 2123643 V = { B, } B = p["qBosAWrwunC3z"] end end else if B > 2321944 then if 2328078 > B then B, V = p["JTmUlsHdjaFoOP"], { } elseif 2341956 > B then O = 13017433 > 15527500 E["CanCollide"] = O B = 13155724 elseif B < 2366714 then B = 7156397 U = p["tonumber"] n = Q[I] H = U(n) r = H or 0 R = r < 0.5 g = R else B = Q[Y[1]] v = Q[Y[4]] B["CanCollide"] = v V, B = { }, p["n69OK5iqpzwjeG"] end else if 2298851 > B then Q[J] = H n = Q[J] B = n and 14924226 or 973955 elseif B < 2314885 then J = J + h V, E = K >= J, not f V = E and V E = J >= K E = f and E V = E or V B = V and 9369623 B = B or 8825855 elseif 2316897 > B then B = 1895623 else B = V and 3561277 or 7007230 end end end else if B < 2569018 then if B < 2443283 then if 2406107 > B then B = 5524880 K = Q[Y[1]] J = K["Character"] V = J elseif B < 2415278 then g = p["Instance"] S = g["new"] g = S("ScreenGui") g["Name"] = "ChestFarmMenu" d = 14164689 <= 12336477 g["ResetOnSpawn"] = d g["DisplayOrder"] = 999 d = I g["Parent"] = d d = p["Instance"] S = d["new"] d = S("Frame") d["Name"] = "Main" r = p["UDim2"] R = r["new"] r = R(0, 220, 0, 200) d["Size"] = r r = p["UDim2"] R = r["new"] r = R(0, 20, 0, 120) d["Position"] = r r = p["Color3"] R = r["fromRGB"] r = R(25, 25, 30) d["BackgroundColor3"] = r V = { } d["BorderSizePixel"] = 0 R = 11185489 > 5251094 d["Active"] = R iL = W() R = 14905430 > 1715190 d["Draggable"] = R R = g d["Parent"] = R R = p["Instance"] S = R["new"] R = S("UICorner", d) G = p["UDim"] r = G["new"] G = r(0, 8) R["CornerRadius"] = G R = p["Instance"] S = R["new"] R = S("TextLabel") G = p["UDim2"] r = G["new"] G = r(1, 0, 0, 28) R["Size"] = G VL = W() R["BackgroundTransparency"] = 1 R["Text"] = "\240\159\159\163 Chest Farm" U = p["Enum"] G = U["Font"] r = G["GothamBold"] R["Font"] = r R["TextSize"] = 15 G = p["Color3"] KL = W() r = G["fromRGB"] G = r(255, 255, 255) R["TextColor3"] = G BL = W() r = d R["Parent"] = r r = p["Instance"] S = r["new"] r = S("TextButton") S = W() Q[S] = r r = Q[S] r["Name"] = "Scan" r = Q[S] k = p["UDim2"] U = k["new"] k = U(1, -20, 0, 36) r["Size"] = k r = Q[S] k = p["UDim2"] U = k["new"] k = U(0, 10, 0, 36) r["Position"] = k r = Q[S] k = p["Color3"] U = k["fromRGB"] k = U(60, 90, 180) r["BackgroundColor3"] = k r = Q[S] r["Text"] = "SCAN: OFF" r = Q[S] l = p["Enum"] k = l["Font"] QL = W() U = k["GothamBold"] r["Font"] = U r = Q[S] r["TextSize"] = 15 r = Q[S] k = p["Color3"] U = k["fromRGB"] k = U(255, 255, 255) r["TextColor3"] = k r = Q[S] U = d r["Parent"] = U G = p["Instance"] r = G["new"] k = Q[S] G = r("UICorner", k) k = p["UDim"] U = k["new"] aL = W() k = U(0, 8) G["CornerRadius"] = k NL = W() G = p["Instance"] r = G["new"] G = r("TextLabel") r = W() Q[r] = G G = Q[r] G["Name"] = "Status" G = Q[r] l = p["UDim2"] k = l["new"] l = k(1, -20, 0, 118) G["Size"] = l G = Q[r] l = p["UDim2"] k = l["new"] l = k(0, 10, 0, 80) G["Position"] = l G = Q[r] G["BackgroundTransparency"] = 1 G = Q[r] G["Text"] = "Status: FARM \240\159\159\162\010Loot: 0 | Skip: 0\010Locked: 0\010Scan: -" G = Q[r] Z = p["Enum"] l = Z["Font"] vL = W() k = l["Gotham"] G["Font"] = k G = Q[r] G["TextSize"] = 13 G = Q[r] l = p["Color3"] wL = W() B = p["Wv58s2ycZEbA"] k = l["fromRGB"] l = k(200, 200, 200) G["TextColor3"] = l G = Q[r] P = W() k = 4535226 >= 3350811 G["TextWrapped"] = k G = Q[r] k = d Z = W() c = W() G["Parent"] = k zL = W() C = W() k = W() Q[k] = 80 Q[Z] = 0 Q[C] = 3 y = W() Q[y] = 0.02 Q[c] = 0.05 Q[P] = 3 Q[zL] = 0.1 Q[wL] = 0.3 Q[BL] = 0.6 Q[iL] = 100 Q[aL] = 0.4 Q[NL] = 150 Q[VL] = ctx.scanEnd or 36000 Q[QL] = 1200 Q[vL] = 0.6 Q[KL] = 0 l = W() Q[l] = 0 WL = W() Q[WL] = 0 JL = p["_G"] JL["ScanInfo"] = "-" eL = W() hL = q(3906543, { h, J, }) fL = x(7594730, { O, h, J, }) JL = W() Q[JL] = hL hL = W() bL = e(14923516, { h, J, }) Q[hL] = bL qL = e(8419400, { O, h, J, }) bL = W() Q[bL] = fL fL = W() Q[fL] = qL qL = W() uL = u(4085716, { fL, h, J, }) xL = W() AL = A(10832111, { xL, h, J, }) Q[qL] = uL uL = { } Q[xL] = uL tL = e(14695700, { O, h, J, xL, }) dL = __farmCapture(14099732, u(14099732, { C, Z, h, J, y, })) Q[eL] = nil uL = W() Q[uL] = tL tL = W() Q[tL] = AL AL = W() jL = A(9814636, { eL, xL, K, h, J, tL, hL, uL, }) y = b(y) Q[AL] = jL ML = Q[O] eL = b(eL) K = b(K) jL = ML["CharacterAdded"] ML = __farmConnect IL = q(10628738, { h, J, xL, }) ML = ML(jL, IL) ML = x(12898395, { fL, h, J, hL, }) jL = W() Q[jL] = ML IL = W() Q[IL] = nil EL = e(8056308, { O, h, J, IL, hL, }) ML = W() Q[ML] = EL EL = Q[ML] sL = Q[O] mL = sL["Character"] OL = EL(mL) OL = Q[O] EL = OL["CharacterAdded"] XL = j(5573090, { bL, h, J, JL, }) mL = j(248418, { h, J, ML, }) OL = __farmConnect OL = OL(EL, mL) OL = x(10439019, { h, J, r, KL, l, WL, }) mL = __farmCapture(13917854, x(13917854, { h, J, })) EL = W() Q[EL] = OL SL = __farmCapture(9164528, u(9164528, { bL, h, J, WL, JL, EL, })) OL = W() Q[OL] = mL gL = W() sL = __farmCapture(7185824, M(7185824, { h, J, O, })) uL = b(uL) mL = W() Q[mL] = sL sL = W() ML = b(ML) Q[sL] = XL HL = A(9382639, { h, J, S, EL, }) XL = W() rL = __farmCapture(2847902, t(2847902, { h, J, bL, iL, gL, AL, hL, qL, EL, })) Q[XL] = SL tL = b(tL) RL = __farmCapture(12562248, A(12562248, { h, J, bL, hL, qL, EL, })) O = b(O) Q[gL] = nil SL = W() Q[SL] = rL rL = W() r = b(r) Q[rL] = RL GL = __farmCapture(16446958, x(16446958, { SL, h, J, rL, qL, BL, bL, gL, aL, })) RL = W() Q[RL] = GL nL = __farmCapture(7136366, u(7136366, { h, J, bL, })) SL = b(SL) GL = W() UL = __farmCapture(16361397, t(16361397, { h, J, bL, jL, sL, JL, OL, GL, c, KL, hL, EL, })) Q[GL] = dL BL = b(BL) xL = b(xL) dL = W() Q[dL] = UL UL = W() Q[UL] = HL IL = b(IL) HL = W() Q[HL] = nL LL = __farmCapture(3369653, t(3369653, { h, J, HL, VL, hL, bL, NL, qL, wL, RL, zL, jL, EL, vL, XL, QL, JL, mL, k, l, dL, rL, UL, })) nL = W() Q[nL] = LL LL = __farmCapture(11145377, q(11145377, { h, J, hL, bL, qL, wL, RL, zL, XL, WL, P, mL, k, l, EL, dL, rL, })) RL = b(RL) qL = b(qL) mL = b(mL) TL = Q[S] iL = b(iL) k = b(k) cL = TL["MouseButton1Click"] yL = x(8779035, { h, J, rL, UL, EL, nL, hL, }) NL = b(NL) OL = b(OL) c = b(c) TL = __farmConnect QL = b(QL) TL = TL(cL, yL) cL = Q[UL] dL = b(dL) TL = cL() WL = b(WL) zL = b(zL) TL = p["task"] Z = b(Z) HL = b(HL) GL = b(GL) bL = b(bL) sL = b(sL) aL = b(aL) UL = b(UL) C = b(C) EL = b(EL) cL = TL["spawn"] TL = cL(LL) jL = b(jL) JL = b(JL) cL = Q[hL] fL = b(fL) P = b(P) rL = b(rL) l = b(l) nL = b(nL) wL = b(wL) XL = b(XL) gL = b(gL) VL = b(VL) S = b(S) J = b(J) h = b(h) vL = b(vL) KL = b(KL) AL = b(AL) TL = cL("Menu OK. Farm auto-ON. Click SCAN for track sweep. Auto-dismount + Safe Mode + NoClip + Leave-on-loot.") hL = b(hL) elseif 2417445 > B then m = 12039276 > 9625445 B = m and 10698099 or 7585355 else B = S and 11535100 or 1503389 end else if B < 2485214 then X = Q[Y[5]] g = Q[s] S = X(g) B = S and 11631822 or 12688007 elseif 2508870 > B then B = Q[Y[1]] v = B["GetPivot"] V = { v(B), } B, V = p["qWQmbQXX4VmQQ"], { i(V), } elseif B < 2539717 then v = "SAFE \226\155\145\239\184\143 REGEN" B = 11472810 else B = 3322234 end end else if B < 2628954 then if B < 2579635 then K = q(2503136, { v, }) B = p["pcall"] h = { B(K), } V, J = h[1], h[2] K = V V, B = K, K and 8389699 or 16373456 elseif B < 2590837 then J, f = K(v, J) B = J and 1512125 or 13161543 elseif 2608581 > B then X = b(X) B = 6799258 else B = 2313140 end else if 2637498 > B then B = 10960638 elseif B < 2640983 then Q[J] = o wL = Q[Z] zL = wL + 1 P = C[zL] pL = d + P B = 11103020 YL = pL % 256 d = YL zL = Q[l] P = R + zL pL = P % 256 R = pL else V = Q[Y[6]] B = p["xuh45HTvOBnL"] v = V() V = { } end end end end else if 3117455 > B then if 2798376 > B then if 2730807 > B then if 2660819 > B then B = O["IsA"] B = B(O, "ProximityPrompt") B = B and 13875691 or 11241139 elseif B < 2679587 then V = K B = K and 8462415 or 11740424 elseif B < 2700773 then B = 7982694 Q[Y[5]] = V else V = p["task"] B = V["wait"] O = Q[Y[5]] V = B(O) B = 2621551 end else if 2760663 > B then h = p["_G"] V = h["ChestFarm"] B = V and 8805998 or 7493530 elseif B < 2774834 then V = { nil, } B = p["X1u4FY0Xv9ejg"] elseif 2792143 > B then v = Q[Y[1]] V = #v B = V == 0 B = B and 12705080 or 7985072 else B = 9272629 E = b(E) O = p["task"] V = O["wait"] O = V(0.1) end end else if 3037073 > B then if 2823481 > B then B = Q[Y[2]] v = 5456053 <= 12466774 B["Anchored"] = v V, B = { }, p["6Z8TklukcUN5Yp"] elseif B < 2897029 then V = p["_G"] B = V["SafeMode"] B = B and 16291473 or 7145320 elseif B < 2990461 then f = p["task"] B = 9517195 V = f["wait"] E = Q[Y[11]] f = V(E) else B = p["pcall"] J = A(7154195, { v, Y[1], Y[2], }) V = B(J) B = 1443707 end else if B < 3061225 then s = O == 4 B = s and 3206321 or 6618969 elseif B < 3096488 then V, B = { }, 13089986 >= 12858857 Q[Y[1]] = B B = p["hC8xnOODsRvG5f"] else B = V and 6719882 or 1895623 end end end else if B < 3308872 then if B > 3201202 then if B < 3226294 then s = 9251678 ~= 15660190 Q[J] = s B = 3322234 elseif 3266444 > B then B = W() Q[B] = X X = B B = Q[X] m = B["IsA"] m = m(B, "ImageLabel") B = m and 11301941 or 2595611 elseif 3291065 > B then S = E["Destroy"] S = S(E) B = 2414939 else J = p["_G"] V = J["ChestFarm"] B = V and 13527837 or 11411361 end else if B < 3130757 then B = 8446674 elseif B < 3151075 then B = p["fireproximityprompt"] v = Q[Y[2]] J = Q[Y[1]] V = B(v, J) B = 2326724 elseif B < 3180862 then X = W() Q[X] = s s = X X = Q[s] m = X["IsA"] m = m(X, "Model") B = m and 13688621 or 7533310 else B = 15426340 end end else if B > 3359807 then if 3365503 > B then B = 11317998 elseif B < 3397660 then V = p["_G"] B = V["__ScanRunning"] B = B and 9209652 or 6018447 else B = X and 2467293 or 14047090 end else if 3330473 > B then B = 609472 elseif 3346558 > B then S = d B = d and 9943720 or 10846809 elseif B < 3356332 then n = d["Position"] H = n - K B = 4279473 U = H["Magnitude"] r = U else V, B = { }, p["Lx1k2m70xbRw"] end end end end end end else if 6452244 > B then if B < 5002297 then if B > 4289131 then if 4591274 > B then if B < 4338383 then if B < 4305007 then B, V = p["cvewqTlKNYEtsR"], { } elseif B < 4315418 then B, V = p["6UAZfjFIw6cdUn"], { } elseif 4323551 > B then O = K B = O == 0 B = B and 1841009 or 10275072 else f = p["table"] B = p["eBH4XbMCWxy0gp"] V = { K, } h = f["sort"] E = j(15617489, { Y[2], Y[3], }) f = h(K, E) h = Q[Y[6]] f = h() end else if 4363379 > B then r = I["Position"] R = r - v d = R["Magnitude"] g = d <= J S, B = g, 2419274 elseif 4409982 > B then I = p["pcall"] d = Q[Y[16]] R = { I(d, X), } S, g = R[1], R[2] I = not S B = I and 8141254 or 16741558 elseif 4511222 > B then V = { "gone", } B = p["uMfY4tfXu6SP"] else X = q(15881992, { }) B = p["tonumber"] v = Q[Y[4]] K = p["tostring"] O = p["pcall"] s = { O(X), } E = { i(s), } f = E[2] h = K(f) J = v(h, ":(%d*):") v = { J(), } V = B(i(v)) v = V J = Q[Y[5]] B, V = J and 232637 or 2698186, J end end else if 4816036 > B then if 4643202 > B then f = Q[Y[5]] E = f() f = Q[Y[8]] V = E < f B = V and 13079762 or 10337494 elseif 4702314 > B then h = p["_G"] K = h["SafeMode"] J, B = not K, 263389 V = J elseif B < 4754216 then V, B = { }, p["IhGdZqCInRyo6E"] else r = K B = K and 3354405 or 4279473 end else if B < 4912216 then B = p["ipairs"] O = Q[J] X = O["GetDescendants"] s = { X(O), } O = { B(i(s)), } E, f, B, V = O[3], O[2], 6799258, O[1] O = V elseif 4986626 > B then V, B = { }, p["09vyvCdicBke"] else V = Q[Y[6]] h = V() E = h B = h and 15826198 or 612181 end end end else if 4094091 > B then if B < 3888333 then if B < 3549486 then X = I U = p["string"] G = U["byte"] B = 9771883 U = G(v, X) G = Q[Y[6]] H = G() r = U + H R = r + O d = R % 256 O = d G = O + 1 r = h[G] R = s .. r s = R elseif B < 3649027 then V = { 0, } B = p["VoqoXUUhfI41g"] elseif 3803451 > B then I = Q[s] g = Q[Y[3]] B = 5826503 S = g["Character"] m = I ~= S X = m else v, B = "SCAN \240\159\159\162", 11472810 end else if 3936128 > B then v = w[1] B = v["FindFirstChild"] J = 10558898 <= 13967950 B = B(v, "LockGui", J) J = W() Q[J] = B V = Q[J] B = not V B = B and 12973837 or 13639824 elseif B < 4025715 then B = Q[Y[3]] V = B() J = V B, K = J and 2104420 or 2660989, J elseif 4088882 > B then B = Q[Y[1]] V = B() v = V J = not v V, B = J, J and 2317164 or 412308 else B = 7317359 S = X["Health"] I = S > 0 m = I end end else if B < 4217330 then if B < 4112262 then F = d == R H, B = F, 2284562 elseif B < 4147883 then E = 47443 > 15112444 f = K == E B, V = 9675773, f elseif 4182604 > B then V = p["_G"] O = 16365909 <= 2075258 V["__ScanRunning"] = O V = p["_G"] V["ScanInfo"] = "-" E = p["_G"] V = E["SafeMode"] B = V and 14545731 or 2201916 else n = Q[I] F = n(1, 6) p["l2"] = F T = p["l2"] n = T > 2 B = n and 16088627 or 13779644 end else if B < 4248660 then h, O = f(K, h) B = h and 2660649 or 2763073 elseif B < 4268556 then V = Q[Y[5]] d = p["math"] g = d["floor"] d = g(J) G = #O r = G .. " chests matched -> teleporting to loot..." g = ": " .. r S = d .. g B = 11809829 m = "x=" .. S X = V(m) V = p["ipairs"] S = { V(O), } m, X, I = S[2], S[1], S[3] elseif B < 4278046 then B = p["pcall"] K = x(12037862, { J, Y[2], Y[3], }) V = B(K) V = p["task"] B = V["wait"] V = B(0.3) B = 14648130 else V = r or 0 R = V V = R < h B = V and 12969050 or 9672953 end end end end else if B < 5687894 then if 5422812 > B then if 5326308 > B then if 5063590 > B then v = W() B = Q[Y[7]] V = B() Q[v] = V J = Q[v] V, B = J, J and 15498653 or 15479639 elseif 5185486 > B then B = V and 4787625 or 2316631 elseif 5286287 > B then B = 8446674 else B = Q[Y[3]] J = W() V = B() Q[J] = V V = Q[J] B = not V B = B and 11238578 or 12488785 end else if 5359122 > B then V = h B = 10533794 elseif 5385723 > B then V = Q[Y[5]] O = V("Scan COMPLETE (end of track).") V = p["_G"] E = b(E) V["ScanX"] = nil V = p["_G"] B, s = 4167377, 6425899 < 5921492 V["TrackScan"] = s elseif B < 5401141 then f = Q[v] B = 16262286 h = f["Model"] V = h else B = E and 14551240 or 6402229 end end else if 5498071 > B then if 5432517 > B then K, E = h(J, K) B = K and 9671719 or 727779 elseif B < 5439115 then V = Q[Y[1]] B = V["Visible"] V = { B, } B = p["IEFLEIqjsJWgG"] elseif 5470693 > B then B = 9974009 else YL = Q[J] D = YL B = YL and 14920708 or 10850024 end else if B < 5512268 then B = Q[Y[4]] J = B["Disconnect"] J = J(B) Q[Y[4]] = nil B = 7493453 elseif 5548985 > B then v = V B = not v B = B and 12685973 or 16764486 elseif 5587453 > B then v = w[1] B = Q[Y[1]] V = B() J = V K, B = J, J and 16150368 or 14840177 else d = p["table"] X = d["insert"] r = "Model" G = Q[s] U = "Pos" H = g["Position"] n = "Dist" L = J B = J and 9215071 or 15323556 end end end else if B < 6014319 then if 5865947 > B then if B < 5800237 then B = 7570852 elseif 5843594 > B then B = X and 7670050 or 7730409 elseif 5862685 > B then V = Q[Y[1]] B = V["ImageTransparency"] Q[Y[4]] = B B, V = p["QcryN30UksvW1"], { } else V = Q[Y[5]] B = p["NnJpb7cYe6Pitx"] v = V("NOCLIP OFF.") V = { } end else if B < 5877176 then r = Q[Y[17]] U = g["Model"] G = r(U) B, R = 8588739, not G V = R elseif B < 5895114 then B = Q[Y[3]] B["Text"] = "SCAN: ON" B = Q[Y[3]] J = p["Color3"] v = J["fromRGB"] J = v(50, 170, 80) B["BackgroundColor3"] = J B = 3358260 elseif 5956638 > B then B = J["Position"] V = { B, } B = p["oErei7iIakJZk"] else B = 15382206 ~= 1732140 V = { B, } B = p["3s66yN9YqskDjX"] end end else if B < 6224439 then if 6036789 > B then B = p["_G"] v = 6573172 ~= 7180641 B["__ScanRunning"] = v B = Q[Y[3]] V = B() v = V B = v["X"] V = v["Z"] J, K = B, V f = p["type"] s = p["_G"] O = s["ScanX"] E = f(O) h = E == "number" B, V = h and 7079558 or 10533794, h elseif 6098030 > B then B = { } Q[Y[3]] = B B = 4720807 elseif B < 6161291 then J = Q[Y[1]] K = J(1, 2) v = K == 1 B, V = v and 12543280 or 15089953, v else J = Q[v] V = J["Position"] K = p["Vector3"] J = K["new"] f = Q[Y[4]] K = J(0, f, 0) B = V + K Q[Y[5]] = B B = 7467180 K = u(6713366, { v, Y[1], Y[2], Y[5], }) V = p["pcall"] J = V(K) end else if 6334728 > B then B = 3338712 G = p["table"] r = G["unpack"] d = r elseif 6426610 > B then h = b(h) f = b(f) B = 2586064 else B = 16067697 <= 10469983 V = { B, } B = p["Qq0v6ujBlsZbq"] end end end end end else if B > 7493491 then if 7939647 > B then if B < 7690726 then if 7578103 > B then if 7513420 > B then h = p["_G"] E = 10435605 < 2621338 h["__FarmRunning"] = E f = p["_G"] h = f["SafeMode"] B = h and 8732236 or 13994701 elseif B < 7540370 then B = 11588539 s = b(s) elseif 7559141 > B then K = p["_G"] B = 12033068 J = K["TrackScan"] V = J else E = p["task"] B = 9517195 f = E["wait"] E = f(0.3) end else if 7587716 > B then B = 813689 elseif B < 7592403 then O = e(811111, { E, Y[1], Y[2], J, }) V = p["pcall"] f = V(O) B = 16697569 elseif B < 7632390 then V = Q[Y[1]] B = V["Character"] v = B V, B = v, v and 14441563 or 9156743 else B = Q[s] X = B["FindFirstChildOfClass"] X = X(B, "Humanoid") m, B = X, X and 4092048 or 7317359 end end else if 7750077 > B then if 7720906 > B then O = Q[J] V, B = O, 15877838 elseif 7738273 > B then s = b(s) B = 15175639 elseif 7747329 > B then B, V = 5115852, d else B = p["error"] J = Q[Y[8]] v = B(J, 0) B = 2013086 end else if B < 7810493 then E = Q[Y[8]] O = E() E = Q[Y[9]] V = O < E B = V and 10185824 or 11121287 elseif 7882976 > B then B = p["l2"] V = p["l1"] p["l1"] = B B = 9848414 p["l2"] = V v = Q[Y[1]] J = v() else B, V = p["8jjLAzI7BJkB"], { } end end end else if B < 8173600 then if B < 8047722 then if B < 7983883 then B = Q[Y[7]] B = B and 7748520 or 2013086 elseif 8001339 > B then J = Q[Y[1]] v = #J K = Q[Y[1]] J = K[v] K = Q[Y[1]] B = p["ZX6yV7ukgNyXk"] K[v] = nil V = { J, } elseif B < 8028371 then B = V and 2239952 or 9556308 else B = Q[Y[7]] V = B("Scan OFF.") B = 4979985 end else if 8075870 > B then v = w[1] B, V = v and 5524880 or 2397276, v elseif B < 8118343 then B, V = p["Bxf0u7wpGqjB3O"], { } elseif 8152929 > B then I = Q[Y[3]] G = p["tostring"] U = G(g) R = "Error: " .. U B = 16741558 d = I(R) else B = Q[Y[6]] V = B(h) B = V and 1479762 or 13153703 end end else if 8303169 > B then if B < 8198829 then n = T + n H, k = F >= n, not L H = k and H k = n >= F k = L and k H = k or H B = H and 13341767 B = B or 10720795 elseif 8228130 > B then B = 947254 elseif B < 8267985 then V = p["_G"] B = V["TrackScan"] B = B and 5887144 or 12835545 else I = 13415829 ~= 13658982 m = Q[J] X = m == I B = X and 16698363 or 11026002 end else if 8344028 > B then B = 14255469 elseif B < 8383094 then v = b(v) V = p["task"] B = V["wait"] J = Q[Y[9]] V = B(J) B = 539956 else V, B = J, 16373456 end end end end else if 7022655 > B then if B < 6716624 then if 6621656 > B then if B < 6467256 then B = 813689 elseif B < 6486990 then B = S and 10073132 or 1734600 elseif 6555966 > B then v = "IDLE" V = p["_G"] B = V["SafeMode"] B = B and 2514604 or 3295510 else X = O == 5 B = X and 8294771 or 9270560 end else if B < 6628322 then B = p["_G"] v = 16586065 > 5159535 B["__FarmRunning"] = v B = Q[Y[3]] V = B("START farm (auto). 0 boss attacks.") B = Q[Y[4]] V = B() v = V B, J = v and 9393565 or 14814348, v elseif 6637956 > B then B = V and 8946494 or 16600767 elseif B < 6678488 then V = K >= 40 B = V and 457745 or 2946156 else B = Q[Y[1]] J = p["Vector3"] v = J["zero"] B["AssemblyLinearVelocity"] = v B = Q[Y[1]] J = p["CFrame"] v = J["new"] K = Q[Y[4]] J = v(K) B["CFrame"] = J B = Q[Y[1]] v = 9911192 >= 1135751 B["Anchored"] = v V, B = { }, p["G3DMpVYdHgrh1"] end end else if 6784773 > B then if B < 6725347 then R = e(12343378, { m, }) V = p["pcall"] r = { V(R), } d = r[2] g = r[1] V = g B = g and 7746138 or 5115852 elseif B < 6731964 then B = 5123897 < 12371649 B = B and 12070566 or 3361354 elseif B < 6751702 then B = Q[Y[1]] v = B["GetPivot"] V = { v(B), } V, B = { i(V), }, p["bAVMmxXUq718L"] else B, V = 3109906, d end else if 6859784 > B then E, X = O(f, E) B = E and 3246268 or 14059071 elseif 6942689 > B then m = O == 7 B = m and 553034 or 11759325 elseif 6986149 > B then B = Q[Y[1]] J = p["Vector3"] v = J["zero"] B["AssemblyLinearVelocity"] = v B = Q[Y[1]] J = p["CFrame"] v = J["new"] K = Q[Y[4]] J = v(K) B["CFrame"] = J B, V = p["RwtE61klAG4OJ1"], { } else V = v["Health"] J = v["MaxHealth"] B = V / J V = { B, } B = p["ZRyE73FjfkWEl"] end end end else if B < 7177324 then if B > 7140843 then if B < 7149757 then B = p["_G"] v = 10190927 <= 15959612 B["SafeMode"] = v B = Q[Y[3]] v = W() V = B() Q[v] = V B = Q[v] B = B and 6181652 or 7467180 elseif 7155296 > B then B = Q[Y[1]] v = 5148967 > 13886589 B["Anchored"] = v B, V = p["rr3AVtVXlgOd3H"], { } elseif B < 7162611 then B, S = 6481016, g else B = Q[Y[4]] O = E["CanCollide"] B[E] = O B = 15503894 end else if B < 7048859 then V = Q[Y[12]] O = V() B = 15033315 O = p["Vector3"] V = O["new"] s = W() O = V(J, f, K) X = x(6965069, { E, Y[1], Y[2], s, }) Q[s] = O V = p["pcall"] O = V(X) V = p["_G"] g = p["math"] S = g["floor"] g = S(J) R = Q[Y[4]] S = "/" .. R I = g .. S X = "x=" .. I V["ScanInfo"] = X V = Q[Y[13]] O = V() O = p["task"] V = O["wait"] X = Q[Y[14]] O = V(X) V = { } O = V V = p["ipairs"] S = Q[Y[15]] g = { S(), } S = { V(i(g)), } I, X, m = S[3], S[1], S[2] elseif B < 7069598 then V = Q[Y[3]] B = 6643611 S = Q[Y[10]] I = S .. " LOCKED." X = ": 0 unlocked, " .. I s = K .. X E = "Scan " .. s f = V(E) elseif B < 7107962 then s = p["_G"] O = s["ScanX"] E = O >= J B, h = E and 1508500 or 5335161, E else B = p["workspace"] V = B["FindFirstChild"] V = V(B, "Drill") v = W() Q[v] = V B = Q[v] B = B and 2573206 or 3965714 end end else if 7368385 > B then if B < 7226134 then B, v, J = { }, w[1], w[2] K = B B = p["ipairs"] E = p["workspace"] s = E["GetDescendants"] O = { s(E), } E = { B(i(O)), } f, h, V = E[3], E[2], E[1] E, B = V, 15175639 elseif 7291901 > B then Q[Y[10]] = Q[Y[10]] + 1 B = Q[Y[11]] O = "Looted: " .. E V = B(O) B = 2214588 elseif B < 7342726 then B = m and 14090643 or 10252446 else B = 1719304 end else if B < 7417928 then B = Q[Y[1]] v = 9726848 <= 6852102 B["Sit"] = v B = Q[Y[1]] v = 12565162 > 7469799 B["Jump"] = v B, V = p["wBnPreVBeIxQw"], { } elseif B < 7480316 then V = Q[Y[6]] J = V() V = Q[Y[7]] h = p["string"] B = p["lwAtT0tu8hp4"] K = h["format"] v = b(v) O = Q[Y[8]] s = O() E = s * 100 O = Q[Y[4]] h = { K("HP %.0f%% - SAFE MODE, floated %d studs up + regen.", E, O), } J = V(i(h)) V = Q[Y[9]] J = V() V = { } else B = p["eGmuME7E1PCiR"] h = Q[K] V = { } J = h["Seated"] h = __farmConnect f = x(13175923, { Y[2], Y[3], K, Y[5], }) K = b(K) h = h(J, f) Q[Y[4]] = h end end end end end end end else if 12696543 > B then if 10706745 > B then if B > 9520376 then if B < 10040206 then if B < 9723828 then if B < 9609134 then if B < 9524972 then V = Q[Y[3]] B = 6643611 s = K .. ": no chest." E = "Scan " .. s f = V(E) elseif 9541347 > B then B = 4327491 s = b(s) elseif B < 9582603 then B = h["Name"] E = B B = Q[Y[8]] V = B(f) V = p["task"] B = V["wait"] O = Q[Y[9]] V = B(O) V = h["Parent"] B = not V B = B and 7266444 or 15396740 else B = Q[Y[1]] B = B and 13143497 or 2799061 end else if 9640544 > B then K = p["_G"] J = K["ChestFarm"] B, V = J and 12033068 or 7547431, J elseif B < 9672336 then B = E["IsA"] B = B(E, "BasePart") B = B and 8685938 or 13206972 elseif 9674363 > B then B = 2316631 else B = V and 13566339 or 4844448 end end else if B < 9900480 then if 9793259 > B then I, d = S + I, not g X = I <= m X = d and X d = I >= m d = g and d X = d or X B = X and 3537696 B = B or 11212642 elseif B < 9831525 then B = Q[Y[1]] B = B and 1385411 or 1014331 elseif B < 9866092 then B = 9807712 > 7991906 B = B and 7869353 or 4311225 else I = b(I) f = b(f) J = b(J) U = b(U) S = b(S) E = b(E) f = W() g = b(g) h = b(h) h = W() Q[h] = nil J = W() Q[J] = nil Q[f] = 2 E = p["math"] K = E["floor"] I = W() E = W() Q[E] = K O = W() B = 15491759 Q[O] = 0 K = { } Q[I] = K S = p["string"] G = 256 K = S["char"] g = p["table"] S = g["remove"] d = p["math"] g = d["random"] d = { } U = 1 L = 0 > 1 r = 1 - 1 end else if 9930455 > B then zL = C[2] wL = Q[c] P = zL == wL B, YL = 896564, P elseif 9958864 > B then g = W() Q[g] = S S = Q[I] H = x(11350692, { }) d = S(3, 65) S = W() R = 0 Q[S] = d d = 0 G = p["pcall"] U = { G(H), } B, r = 8182596, { i(U), } G = r[2] U = p["tonumber"] n = Q[h] T = p["tostring"] L = T(G) F = n(L, ":(%d*):") n = { F(), } H = U(i(n)) U = W() Q[U] = H n = Q[S] F = n T = 1 L = 1 < 0 n = 1 - 1 elseif B < 9990644 then B = 3322234 else B = 13638227 end end end else if 10388256 > B then if B > 10236390 then if B < 10254006 then B = 7730409 elseif B < 10265319 then s, X = E(O, s) B = s and 12051075 or 7570852 elseif 10306283 > B then V = O == 1 B = V and 15428175 or 11508942 else V = Q[Y[9]] f = V() h = f f = #h V = f == 0 B = V and 13499361 or 15073848 end else if 10086762 > B then B = 1832633 ~= 14580906 V = { B, } B = p["BznEIX98ywr4"] elseif B < 10143108 then B = Q[Y[1]] v = B["GetPivot"] V = { v(B), } B, V = p["lDeeEo6yF6105"], { i(V), } elseif B < 10203079 then E = Q[Y[10]] O = E() V = not O B = V and 16390245 or 1705064 else B = 11351942 end end else if B > 10659999 then if 10684917 > B then I = q(1553168, { m, Y[1], Y[2], s, }) V = p["pcall"] X = V(I) B = 12468205 elseif B < 10692245 then V = Q[Y[6]] X = V() m = W() Q[m] = X V = Q[m] B = V and 10683443 or 12468205 else B = 2415617 end else if B < 10486406 then v = q(6492964, { Y[1], Y[2], Y[3], Y[4], Y[5], Y[6], }) B = p["pcall"] V = B(v) B, V = p["C8xW3srj2hmH7G"], { } elseif B < 10581266 then B = V and 11980463 or 11058059 elseif B < 10632646 then V = p["task"] B = V["wait"] V = B(0.3) V = p["_G"] B = V["SafeMode"] B = B and 6055131 or 4720807 else E = W() V = Q[Y[6]] O = V() Q[E] = O O = Q[E] V = not O B = V and 13673125 or 7038080 end end end end else if B > 8988035 then if B > 9271594 then if B > 9388102 then if B < 9420920 then B = 14814348 h = v["CFrame"] J = h elseif B < 9482735 then h = Q[J] B = 15916683 K = h["Sit"] V = K else B = 2758254 end else if 9282971 > B then E = p["_G"] V = E["TrackScan"] B = V and 7751634 or 4167377 elseif B < 9331468 then G = Q[Y[4]] H = Q[m] B = 6770288 U = G(H) r = not U d = r elseif B < 9376131 then E = J O = e(13416371, { Y[2], v, }) B = p["pcall"] V = B(O) V = Q[Y[1]] B = E < V B = B and 2703360 or 2621551 else v = u(8241199, { Y[1], Y[2], Y[3], }) B = p["pcall"] V = B(v) B = Q[Y[4]] V = B() V, B = { }, p["GYtI41Jxun4G3"] end end else if B < 9212361 then if B < 9093159 then B = 12494533 V = Q[Y[5]] n = p["tostring"] F = n(r) U = "Error: " .. F G = V(U) elseif B < 9160635 then V, B = { V, }, p["25b8ashv5DvDU"] elseif 9187090 > B then B = Q[Y[1]] V = B() v = V J, B = v, v and 9254864 or 12787114 else B, V = p["lH1R8IdgHv7a"], { } end else if 9225413 > B then C = g["Position"] Z = C - J B = 15323556 l = Z["Magnitude"] L = l elseif B < 9245309 then B = Q[Y[1]] J = B["GetAttribute"] V = { J(B, "RuntimeChestModel"), } V, B = { i(V), }, p["iJdz7CyecOxTmZ"] elseif 9262712 > B then B = 12787114 h = v["Position"] J = h else X = O == 6 B = X and 11147024 or 6920310 end end end else if 8755635 > B then if 8613234 > B then if B < 8433037 then V = Q[Y[1]] B = V["Character"] v = B V, B = v, v and 11644916 or 301950 elseif B < 8454544 then s = 11335595 ~= 15169456 B = s and 3125004 or 2636358 elseif 8525577 > B then V, B = { V, }, p["EhRgH4HPnGbXl"] else B = V and 13497434 or 1719304 end else if 8644975 > B then B = p["ipairs"] f = v["GetDescendants"] h = { f(v), } f = { B(i(h)), } V = f[1] h, J, B, K = V, f[2], 5431705, f[3] elseif 8669079 > B then B = Q[Y[4]] V = B() B = 9490552 >= 13753759 V = { B, } B = p["owDBoXGHuXLGcW"] elseif B < 8709087 then s = Q[Y[4]] O = s[E] B = O == nil B = B and 7168825 or 15503894 else B = 13994701 h = Q[Y[17]] f = h() end end else if 8863244 > B then if B < 8792516 then B = p["_G"] K = p["_G"] J = K["TrackScan"] v = not J B["TrackScan"] = v V = p["_G"] B = V["TrackScan"] B = B and 2009098 or 16117330 elseif B < 8815926 then h = Q[Y[5]] f = h() h = Q[Y[6]] V = f < h B = V and 2242061 or 4602584 elseif 8832272 > B then B = p["3lkmPqUkNGuqPV"] v = b(v) V = { } else K = Q[v] B = 6632302 J = K["Sit"] V = J end else if B < 8890225 then B, V = p["ifjEJZLicOL6"], { K, } elseif 8900952 > B then B = 15033315 elseif 8927872 > B then B = 1228690 else J = x(7368676, { v, Y[2], Y[3], }) B = p["pcall"] V = B(J) V = p["task"] B = V["wait"] V = B(0.4) J = W() B = Q[Y[1]] V = B() Q[J] = V K = Q[J] V, B = K, K and 9448275 or 15916683 end end end end end else if B > 11561819 then if 12220698 > B then if B < 11784577 then if B > 11735221 then if 11738908 > B then E = h["Parent"] V, B = E, 16627728 elseif 11740452 > B then h = p["Vector3"] K = h["new"] B = 8462415 h = K(-740, 20, -771.5) V = h elseif 11749903 > B then pL = Q[J] o = pL B = pL and 1702118 or 2638638 else m = O == 8 B = m and 13638988 or 3322234 end else if 11610180 > B then O, s = f(E, O) B = O and 3165640 or 4327491 elseif B < 11638369 then B = 14255469 Q[Y[4]] = Q[Y[4]] + 1 elseif B < 11688983 then B = 301950 J = v["FindFirstChildOfClass"] J = J(v, "Humanoid") V = J else B = J["FindFirstChildOfClass"] B = B(J, "ProximityPrompt") K = B B = K and 13805553 or 3196084 end end else if B < 12044468 then if 11895146 > B then I, g = X(m, I) B = I and 15229519 or 10686391 elseif B < 12006765 then V = p["_G"] B = V["ScanX"] V = Q[Y[5]] J = B X = p["math"] s = X["floor"] X = s(J) B = 4993267 O = X .. "." f = "Resuming scan from x=" .. O h = V(f) elseif B < 12035465 then B = not V B = B and 8652220 or 13690062 else B = Q[Y[1]] v = 15822282 < 1452844 B["Sit"] = v B, V = p["XR2BYFSIa69d"], { } end else if 12060820 > B then S = p["_G"] I = S["ChestFarm"] m = not I B = m and 1913516 or 1310883 elseif B < 12126622 then B = 6730812 else K = W() Q[K] = J J = Q[K] B = not J B = B and 7896600 or 12526461 end end end else if B < 12491659 then if B > 12403608 then if B < 12466021 then B = Q[Y[1]] J = B["GetAttribute"] V = { J(B, "RuntimeChestModel"), } V, B = { i(V), }, p["ZGD0BKJ1M4ilP1"] elseif B < 12476961 then X = p["task"] m = b(m) B = 11480809 V = X["wait"] X = V(0.2) elseif 12487251 > B then r = g["Pos"] G = Q[s] R = r - G d = R["Magnitude"] R = Q[Y[16]] V = d <= R B = V and 1091584 or 8892653 else B = Q[Y[4]] V = B() B = p["pcall"] K = e(14380474, { J, Y[1], Y[2], v, }) V = B(K) V = p["task"] B = V["wait"] V = B(0.2) B = Q[Y[5]] V = B(20) K = V h, B = K, K and 12294651 or 15931243 end else if B < 12276684 then B = Q[Y[4]] V = B["Disconnect"] V = V(B) Q[Y[4]] = nil B = 5864685 elseif 12315528 > B then B = 15931243 E = K["Model"] h = E elseif B < 12339892 then g = A(12463838, { m, Y[2], Y[3], }) V = p["pcall"] d = { V(g), } I = d[1] S = d[2] B, V = I and 11530877 or 3109906, I else B = Q[Y[1]] v = B["GetPivot"] V = { v(B), } B, V = p["kUaum51oFTCD"], { i(V), } end end else if 12552764 > B then if 12510497 > B then B = 7368094 elseif 12531455 > B then B = Q[Y[4]] B = B and 5499656 or 7493453 elseif 12539864 > B then B = Q[Y[3]] V = B() B = Q[Y[4]] B = B and 12258718 or 5864685 else B = V and 4579964 or 7982694 end else if B < 12624110 then v = p["_G"] V = v["SafeMode"] B = not V B = B and 2114199 or 16123142 elseif B < 12686990 then B, V = p["0gPTcKIDXOuo"], { } else X = p["pcall"] d = q(6733117, { s, }) R = { X(d), } g = R[2] S = R[1] B, X = S and 58016 or 1079472, S end end end end else if B < 11219784 then if B < 10993320 then if B > 10839460 then if 10848416 > B then B = 9943720 d = p["unpack"] S = d elseif B < 10865403 then Q[J] = D B = 11103020 elseif 10920710 > B then K, O = f + K, not E J = h >= K J = O and J O = h <= K O = E and O J = O or J B = J and 15354854 B = B or 1692099 else B = 3322234 end else if 10718093 > B then B = Q[Y[1]] v = 16285521 < 11389691 B["Sit"] = v B = Q[Y[1]] v = 3946760 < 15849383 B["Jump"] = v V, B = { }, p["MjTCrsr1DbFlk5"] elseif B < 10735535 then F = Q[J] H, B = F, F and 4096134 or 2284562 elseif 10791193 > B then B = p["error"] V = B("Tamper Detected!") B, V = p["ffF6ZEW1874Cx"], { } else B = p["pairs"] K = Q[Y[1]] h = { B(K), } v, J, B, V = h[2], h[3], 2586064, h[1] K = V end end else if B < 11112153 then if B < 11042030 then B = 14668478 elseif B < 11058347 then V = p["_G"] B = 4993267 f = J V["ScanX"] = f elseif B < 11080828 then J = W() Q[J] = "fR2yublGNor" h = 8 B = 609472 f = 1 E = 1 < 0 K = 0 - 1 else k = b(k) Z = b(Z) c = b(c) y = b(y) l = b(l) B = 8182596 H = b(H) end else if B < 11133332 then O = Q[Y[8]] s = O() O = Q[Y[11]] V = s < O B = V and 13042276 or 15182894 elseif B < 11146200 then V = p["_G"] B = V["__FarmRunning"] B = B and 8095433 or 6624343 elseif B < 11179833 then X, B = 2488765 >= 9714369, 3322234 Q[J] = X else X = s K[J] = X B = 12765146 end end end else if 11381651 > B then if B < 11305973 then if B < 11232752 then B = 7493530 elseif 11239858 > B then V = { "no-hrp", } B = p["pgXHUPxDP4nr2L"] elseif 11271540 > B then B = 4236829 else I = e(5433329, { X, Y[1], Y[2], }) B = p["pcall"] m = B(I) I = W() g = t(5860685, { X, Y[1], Y[2], I, }) Q[I] = 0 B = p["pcall"] S = B(g) B, S = m and 13190025 or 6481016, m end else if B < 11314001 then J = e(9608899, { Y[8], v, Y[2], Y[3], }) B = p["pcall"] V = B(J) B = 8376489 elseif 11334345 > B then B = 10899469 < 9266332 Q[J] = B B = 3322234 elseif B < 11351317 then v = "VJWiAPUA" ^ 6071958 B = 896278 - v v = B B = "4RaSUD" / v V = { B, } B = p["rOOhwcq6SC46a"] else B, V = p["Z8huKCSaqP1gNV"], { } end end else if B < 11506722 then if B < 11442085 then K = p["_G"] J = K["TrackScan"] B = J and 3870124 or 11472810 elseif 11476809 > B then K = Q[Y[3]] h = "Text" E = "Status: " X = "\010Loot: " I = Q[Y[4]] g = " | Skip: " R = Q[Y[5]] G = "\010Locked (needs boss): " H = Q[Y[6]] F = "\010Scan: " T = p["tostring"] C = p["_G"] Z = C["ScanInfo"] k, B = Z, Z and 14978953 or 13776255 elseif 11492656 > B then V = Q[Y[7]] B = 2797691 J = J + V V = p["_G"] s = b(s) m = J V["ScanX"] = m else s = O == 3 B = s and 14387389 or 3039380 end else if 11519909 > B then V = O == 2 B = V and 1066369 or 11504503 elseif B < 11532988 then d = S B = S and 9293314 or 6770288 else S = p["table"] B = S["insert"] R = Q[s] U = Q[s] G = U["Name"] g = { ["Model"] = R, ["Name"] = G, } S = B(K, g) B = 1503389 end end end end end end else if B > 14552478 then if 15513252 > B then if B > 15083123 then if B < 15375797 then if B > 15195783 then if B < 15219096 then V = p["task"] B = V["wait"] V = B(0.1) K = Q[Y[3]] J = K["Sit"] V, B = J, J and 4683821 or 263389 elseif B < 15276537 then R = p["_G"] d = R["TrackScan"] V = not d B = V and 1249993 or 954104 elseif B < 15339205 then F = L or 0 R = { [r] = G, [U] = H, [n] = F, } d = X(K, R) d = #K X = d >= 60 B = X and 9526387 or 1063554 else J = K B = Q[Y[1]] O = B(0, 255) v[J] = O B = 10880782 end else if 15090705 > B then B = 12543280 J = Q[Y[2]] K = Q[Y[3]] v = J == K V = v elseif B < 15133548 then B, O = 666340, 16148928 > 7971927 E = K == O f = E elseif B < 15179266 then f, s = E(h, f) B = f and 513947 or 8887798 else O = Q[Y[4]] V = J > O B = V and 5383083 or 10636555 end end else if B > 15485699 then if B < 15495206 then r, k = r + U, not L R = r <= G R = k and R k = G <= r k = L and k R = k or R B = R and 728042 B = B or 1416181 elseif 15501273 > B then h = Q[v] B = 15479639 K = h["Anchored"] J = not K V = J else B = E["CanCollide"] B = B and 2329432 or 13155724 end else if 15411540 > B then Q[Y[10]] = Q[Y[10]] + 1 B = Q[Y[11]] X = E .. " - moving to next." O = "Fired " .. X V = B(O) B = 2214588 elseif 15427257 > B then B = p["ipairs"] E = v["GetDescendants"] f = { E(v), } E = { B(i(f)), } B, V, K = 4236829, E[1], E[2] f, h = V, E[3] elseif 15453907 > B then X = 13453595 <= 11371805 s = Q[J] V = s == X B = V and 551847 or 2564830 else B = V and 11310005 or 8376489 end end end else if 14862521 > B then if B > 14682089 then if B < 14755024 then V = Q[Y[1]] B = V["Character"] v = B B = not v B = B and 16304404 or 8637730 elseif 14827262 > B then V, B = J or nil, 2758254 J = W() Q[J] = V K = 0 elseif 14844126 > B then V = K or nil K, h = V, v or 1000000000 f = nil V = p["ipairs"] X = p["workspace"] B, I = 13325255, X["GetDescendants"] m = { I(X), } X = { V(i(m)), } O, s, E = X[2], X[3], X[1] else B = 10960638 end else if B < 14590472 then r = W() R = { } G = e(2786596, { r, O, f, E, }) U = W() Q[r] = R R = W() Q[R] = G G = { } Q[U] = G k = { } G = p["setmetatable"] C = Q[U] l = { ["__index"] = C, ["__metatable"] = nil, } E = b(E) L = G(k, l) G = x(15732229, { U, r, I, O, f, R, }) U = b(U) O = b(O) f = b(f) I = b(I) Q[h] = L r = b(r) R = b(R) Q[J] = G K = p["_G"] E = 14549158 ~= 1051495 K["ChestFarm"] = E K = p["_G"] E = 10710733 >= 11749749 K["__FarmRunning"] = E K = p["_G"] E = 6821869 >= 13798017 K["TrackScan"] = E K = p["_G"] E = 15672959 <= 14248414 K["__ScanRunning"] = E K = p["_G"] E = 10061407 <= 2332047 K["SafeMode"] = E K = p["game"] f = K["GetService"] f = f(K, "Players") K = p["game"] E = K["GetService"] E = E(K, "RunService") K = W() Q[K] = E E = f["LocalPlayer"] O = W() Q[O] = E E = Q[O] I = E["WaitForChild"] I = I(E, "PlayerGui") E = I["FindFirstChild"] E = E(I, "ChestFarmMenu") B = E and 3286621 or 2414939 elseif B < 14637679 then d = Q[Y[10]] R = d() V = not R B = V and 480747 or 8215062 elseif 14658304 > B then B = Q[Y[4]] V = B("Dismounted from train seat.") B = 9542109 >= 9164083 V = { B, } B = p["0rwQz9UDL0RUY"] else X = 14513727 <= 14646868 B = X and 15700987 or 5444901 end end else if B < 14951589 then if B < 14898837 then m = b(m) B = 13325255 elseif B < 14922112 then zL = C[1] wL = 13578987 < 3171962 P = zL == wL B, YL = P and 9917190 or 896564, P elseif 14923871 > B then v = w[1] B = p["print"] h = p["tostring"] f = h(v) J = "[ChestFarm] " .. f V = B(J) V, B = { }, p["3aFp6H2kIpMf"] else B = 9883770 end else if 15006134 > B then L = T(k) n = F .. L U = H .. n r = G .. U d = R .. r S = g .. d m = I .. S s = X .. m O = v .. s V = { } f = E .. O B = p["yfqip5pGGQ0s"] K[h] = f elseif 15053581 > B then I, g = X(m, I) B = I and 12485718 or 12725367 elseif B < 15075070 then K = 0 f = p["ipairs"] X = { f(h), } B, s, E, O = 10255566, X[3], X[1], X[2] else B = 10255566 S = p["task"] I = S["wait"] S = I(0.15) end end end end else if 16141377 > B then if B > 15899337 then if 16102978 > B then if 15923963 > B then B = V and 4276620 or 14648130 elseif 15965690 > B then V = h B = h and 16262286 or 5388364 elseif 16044382 > B then V = p["pcall"] G = Q[Y[21]] U = { V(G, g), } r = U[2] R = U[1] V = not R B = V and 9029576 or 12494533 else B = 8909251 n = p["tostring"] L = p["l1"] T = n(L) p["l2"] = T end else if 16120236 > B then B = Q[Y[3]] V = B() B = 13787160 elseif B < 16127764 then B = p["_G"] v = 8400462 > 11369163 B["SafeMode"] = v B = Q[Y[3]] V = B() v = W() Q[v] = V B = Q[v] B = B and 3034766 or 1443707 else G = #d R = g(1, G) r = S(d, R) G = Q[I] L = r - 1 U = K(L) G[r] = U U = #d G = U == 0 B = G and 14553716 or 16132387 end end else if 15779213 > B then if B < 15570049 then B = 9848414 elseif B < 15659238 then J, v = w[2], w[1] V = v["Dist"] K = J["Dist"] B = V < K V = { B, } B = p["mtiaCUJpuE0Y"] elseif 15716608 > B then B = 14668478 else J = w[2] B = Q[Y[1]] K = B B = K[J] v, B = w[1], B and 16460271 or 1622044 end else if 15844542 > B then B = 612181 X = h["Position"] s = X["Y"] E = s elseif 15870362 > B then n = e(15522610, { f, }) B = p["FWjKxfCjJw11Sz"] F = { n(), } V = { i(F), } elseif B < 15879915 then B = V and 7590077 or 16697569 else v = "Mtu6a" ^ 8082145 B = 10002513 - v v = B B = "Mlv3c" / v V = { B, } B = p["2DL6skadDaig"] end end end else if B < 16453614 then if B < 16332900 then if 16206327 > B then B = 14840177 f = J["Position"] K = f elseif 16276879 > B then h = V V = h B = h and 11737393 or 16627728 elseif 16297938 > B then V, B = { }, p["IowrNaajaJr4"] else B, V = p["F0BnYzFZ2IAu7"], { } end else if B < 16367426 then v = W() Q[v] = w[1] V = p["_G"] B = V["SafeMode"] B = B and 13311217 or 5317455 elseif B < 16381850 then B = V and 5903085 or 13558997 elseif B < 16418601 then E = b(E) B = 4167377 else B = Q[Y[1]] V = B() B = 539956 end end else if 16697966 > B then if 16530519 > B then B, V = p["cJEQGxSoyboGi3"], { J, } elseif B < 16614247 then B = 843278 < 350039 V = { B, } B = p["nODScTfBrCxeN"] elseif B < 16662648 then B = not V B = B and 4442481 or 8164605 else B = 7493530 V = p["_G"] E = b(E) O = 10471264 >= 11257300 V["ChestFarm"] = O end else if B < 16719960 then B = 9974009 elseif 16753022 > B then B = 15076293 else K = v["FindFirstChildOfClass"] K = K(v, "Humanoid") J, B = K, K and 12182679 or 2006289 end end end end end else if B < 13602283 then if B < 13154713 then if B > 13008056 then if B > 13091276 then if B < 13113487 then B, V = p["5tTQ3n7eSAIL"], { } elseif 13133840 > B then B = 6730812 elseif 13148600 > B then B = Q[Y[2]] J = p["CFrame"] v = J["new"] K = Q[Y[1]] J = v(K) B["CFrame"] = J B = 2799061 else B = Q[Y[7]] V = B(h) f = V E = not f B, V = E and 8017606 or 536939, E end else if 13043323 > B then V = Q[Y[5]] O = V("HP critically low - STOP scan.") E = b(E) V = p["_G"] B, s = 4167377, 15080741 < 4998865 V["TrackScan"] = s elseif B < 13050681 then J = Q[Y[3]] v = J * 201 V = v % 257 Q[Y[3]] = V J = Q[Y[3]] v = J ~= 1 B = v and 117106 or 13044370 elseif B < 13068377 then B = 985213 ~= 1245884 Q[J] = B h = p["string"] K = h["gmatch"] h = W() Q[h] = K f = W() K = u(10750275, { }) Q[f] = K E = W() K = 14836391 >= 16228214 Q[E] = K I = p["pcall"] g = u(3083071, { E, }) S = I(g) B = S and 14519565 or 1841764 else V = Q[Y[3]] f = V("HP critically low - STOP.") V = Q[Y[4]] f = V() E = W() Q[E] = f O = Q[E] V = O B = O and 7711403 or 15877838 end end else if B < 12811329 then if B < 12715223 then J = Q[Y[2]] v = J * 213 V = v + 27552854471197 B = V % 35184372088832 Q[Y[2]] = B B = 13044370 elseif B < 12745256 then X = #O V = X > 0 B = V and 4260492 or 11480809 elseif 12776130 > B then B, V = p["eYnfEpzQqGiE"], { J, } else V = J or nil J = V V = { } K = V Q[Y[4]] = 0 h = p["ipairs"] s = p["workspace"] m = s["GetDescendants"] X = { m(s), } s = { h(i(X)), } O, B, E, f = s[3], 11588539, s[2], s[1] end else if B < 12866970 then B = Q[Y[3]] B["Text"] = "SCAN: OFF" B = Q[Y[3]] J = p["Color3"] v = J["fromRGB"] J = v(60, 90, 180) B["BackgroundColor3"] = J B = 3358260 elseif 12933722 > B then v = W() B = Q[Y[1]] V = B() Q[v] = V J = Q[v] B, V = J and 8838690 or 6632302, J elseif B < 12971443 then G = Q[m] H = d["Position"] V = { ["Model"] = G, ["Pos"] = H, ["Dist"] = R, } r, f, B = R, V, 9672953 h = r else B = 9905388 > 10361310 V = { B, } B = p["Vkt3asvWbGux2S"] end end end else if B > 13379069 then if B < 13513599 then if B < 13441411 then V = Q[Y[1]] B = V > 0 B = B and 3136511 or 13701406 elseif 13481942 > B then J = Q[Y[1]] K = J B = 2313140 h = 1 f = 0 > 1 J = 1 - 1 elseif 13498397 > B then V = Q[Y[18]] R = g["Pos"] r = Q[Y[19]] d = V(R, r) R = #d V = R > 0 B = V and 1490883 or 16000138 else f = Q[Y[10]] K = K + 1 V = f > 0 B = V and 7059638 or 9523558 end else if B < 13543417 then B = 11472810 v = "FARM \240\159\159\162" elseif B < 13562668 then B = 3965714 else B = 11534791 <= 2942944 V = { B, } B = p["8Vi2d0IHEM4L"] end end else if B > 13198498 then if B < 13259094 then B = 5431705 elseif B < 13318236 then V = { "safe-mode", } B = p["00QpFOKfZ2vE"] elseif 13333511 > B then s, m = E(O, s) B = s and 1597098 or 13676734 else H = W() Q[H] = n l = p["math"] k = l["random"] l = k(1, 100) k = W() Q[k] = l l = Q[I] Z = l(0, 255) l = W() Q[l] = Z Z = Q[I] c = Q[k] C = Z(1, c) Z = W() Q[Z] = C y = Q[I] c = y(1, 2) C = c == 1 y = W() Q[y] = C pL = p["tostring"] zL = Q[I] wL = { zL(0, 10000), } P = pL(i(wL)) YL = P .. ":" D = ":" .. YL C = G["gsub"] C = C(G, ":(%d*):", D) c = W() YL = e(6140930, { I, H, S, h, J, U, y, c, k, Z, l, g, }) Q[c] = C D = p["pcall"] o = { D(YL), } C = { i(o), } D = Q[y] B = D and 5496486 or 11740481 end else if B < 13158633 then B = 13206972 elseif 13168733 > B then v = p["table"] B = v["clear"] J = Q[Y[1]] v = B(J) V, B = { }, p["AjQzPtRH2x0hdi"] elseif B < 13182974 then v = w[1] B = v and 15208673 or 11351942 else r = Q[X] R = r["Visible"] g, B = R, R and 2354480 or 7156397 end end end end else if B > 13910743 then if B > 14383931 then if B < 14507673 then if 14403211 > B then m = 11196116 < 14747332 X = Q[J] s = X == m B = s and 14848075 or 5255120 elseif B < 14430298 then s = Q[h] O = s["Parent"] B, E = 5413919, O elseif 14468672 > B then B = 9156743 J = v["FindFirstChild"] J = J(v, "HumanoidRootPart") V = J else Q[Y[14]] = Q[Y[14]] + 1 B = 15076293 I = Q[Y[3]] G = X["Model"] r = G["Name"] n = #m H = n .. " enemies nearby." G = ": " .. H R = r .. G g = "SKIP " .. R S = I(g) I = Q[Y[15]] S = I() end else if 14532648 > B then B = 1841764 elseif 14548485 > B then V = Q[Y[22]] E = V() B = 2201916 else O = x(2378948, { h, Y[2], Y[3], f, }) B = p["pcall"] E = B(O) B = 6402229 end end else if B < 14074857 then if B < 13956277 then v = w[1] B, J = v["FindFirstChild"], 9730207 ~= 744340 B = B(v, "Chest", J) J = B B = J and 11733050 or 15426340 elseif B < 14020895 then B = p["gybmiXPAaJOVmq"] h = Q[Y[15]] f = h() h = Q[Y[3]] J = b(J) V = { } f = h("STOP farm.") elseif 14053080 > B then B = 7533310 else B, f = h and 15091457 or 666340, h end else if 14095187 > B then S = q(10100393, { s, }) B = p["pcall"] g = { B(S), } I = g[2] m = g[1] S, B = m, m and 4349275 or 2419274 elseif 14177600 > B then v = W() Q[v] = w[1] V = Q[v] B = not V B = B and 13102791 or 13466451 elseif B < 14317971 then B = 14047090 else B = Q[Y[1]] J = p["Vector3"] v = J["zero"] B["AssemblyLinearVelocity"] = v B = Q[Y[1]] J = p["CFrame"] v = J["new"] f = Q[Y[4]] h = f["Pos"] E = p["Vector3"] f = E["new"] E = f(0, 3, 2) K = h + E f = Q[Y[4]] h = f["Pos"] J = v(K, h) B["CFrame"] = J B, V = p["K1E2RwOJCQrf"], { } end end end else if B > 13695734 then if B < 13783402 then if 13724110 > B then B = p["fireproximityprompt"] v = Q[Y[2]] V = B(v) B = 2326724 elseif 13761535 > B then B = p["pcall"] J = e(10715391, { Y[3], Y[1], Y[2], }) V = B(J) B = Q[Y[4]] V = B("Auto-dismounted from seat.") B = 10220335 elseif 13777949 > B then B = 14978953 k = "-" else B = 8909251 n = p["l2"] p["l1"] = n end else if 13796356 > B then B = Q[Y[4]] V = B() B = Q[Y[5]] V = B() V = p["_G"] B = V["TrackScan"] B = B and 371958 or 8039136 elseif B < 13840622 then V, B = { K, }, p["1RkMGpVmui10l5"] elseif 13889661 > B then B, V = p["zz6g49pAa9Eq"], { O, } else B = 4602584 end end else if 13667837 > B then if 13638607 > B then I = Q[Y[12]] g = X["Pos"] d = Q[Y[13]] S = I(g, d) m = S S = #m I = S > 0 B = I and 14495781 or 4377484 elseif B < 13639406 then m = 7495096 >= 8008796 Q[J] = m B = 3322234 elseif B < 13651187 then B = p["pcall"] h = e(1747752, { J, Y[1], Y[2], }) f = { B(h), } K = f[2] V = f[1] h = V V, B = h, h and 4128390 or 9675773 else B = 2415617 end else if B < 13674929 then O = p["task"] V = O["wait"] B = 2797691 O = V(1) elseif B < 13682677 then V, B = { f, }, p["PEko2nISRNoG"] elseif B < 13689341 then S = A(9235755, { s, Y[2], Y[3], }) X = p["pcall"] g = { X(S), } I, m = g[2], g[1] X, B = m, m and 293933 or 3425667 else V = Q[Y[5]] v = V() V = Q[Y[6]] B = v >= V B = B and 1922567 or 5011328 end end end end end end end end end B = #a return i(V) end, 0, function(p, z) local i = K(z) local w = function(w, Y, a, N, V, Q, v) return B(p, { w, Y, a, N, V, Q, v, }, z, i) end return w end, function(p, z) local i = K(z) local w = function(w, Y, a, N, V) return B(p, { w, Y, a, N, V, }, z, i) end return w end, function(p) for z = 1, #p, 1 do v[p[z]] = 1 + v[p[z]] end if w then local B = w(true) local i = a(B) i["__index"], i["__gc"], i["__len"] = p, h, function() return 2641646 end return B else return Y({ }, { ["__gc"] = h, ["__index"] = p, ["__len"] = function() return 2641646 end, }) end end, function(p) local z, B = 1, p[1] while B do v[B], z = v[B] - 1, 1 + z if 0 == v[B] then v[B], Q[B] = nil, nil end B = p[z] end end, function() J = 1 + J v[J] = 1 return J end, function(p, z) local i = K(z) local w = function(w, Y, a) return B(p, { w, Y, a, }, z, i) end return w end, function(p, z) local i = K(z) local w = function(w, Y, a, N, V, Q) return B(p, { w, Y, a, N, V, Q, }, z, i) end return w end, function(p) v[p] = v[p] - 1 if 0 == v[p] then v[p], Q[p] = nil, nil end end, { }, function(p, z) local i = K(z) local w = function(w, Y) return B(p, { w, Y, }, z, i) end return w end, function(p, z) local i = K(z) local w = function() return B(p, { }, z, i) end return w end, { }, function(p, z) local i = K(z) local w = function(w, Y, a, N) return B(p, { w, Y, a, N, }, z, i) end return w end, function(p, z) local i = K(z) local w = function(...) return B(p, { ..., }, z, i) end return w end return (f(11058636, { }))(i(V)) end)(ctx.env, { ..., }, select, setmetatable, unpack or table["unpack"], newproxy, getmetatable) end)() end]====]
    local FEATURE_SOURCE = [=====[return function(api)
    local s, now, controller = api.state, api.now, api.controller
    local F = {}
    local bring, quest, pickupAllowed
    local buildBring = (function()
-- Native Request(item) ownership and alignment holding adapted from EarthManualAssist.
-- Interact accepts LockedTarget in the game's DragController: collect while held,
-- then Cancel(true). This avoids a moving character outrunning a dropped item.
return function(api)
    local s, now = api.state, api.now
    local B = {}
    local memoryStep, cancelReload
    local RELOAD_WINDOW = 4.5
    local function policy(record)
        if api.reloadPolicy then return api.reloadPolicy(record.target) end
        return 2, 30
    end
    local function countReload(reload)
        if reload.token.called and not reload.counted then
            reload.record.attempts = (reload.record.attempts or 0) + 1
            reload.counted = true
        end
    end
    local function chargeReload(reload)
        countReload(reload)
        if not reload.charged and reload.token.called then
            s.lootReloadObservationSeconds = (s.lootReloadObservationSeconds or 0) + math.max(0, now() - reload.token.started)
            reload.charged = true
        end
    end
    local function reloadDue(reload)
        local token = reload.token
        return token.expired or token.timedOut or token.blocked or token.skipped
            or token.started and now() >= token.started + RELOAD_WINDOW
            or not token.started and now() - reload.started >= 10
            or reload.pollUntil and now() >= reload.pollUntil
    end
    local unpackValues = table.unpack or unpack
    local function manual()
        local c = api.controller('DragController')
        return c and c.LockedTarget ~= nil
            or api.Players.LocalPlayer:GetAttribute('PlacingCraftedPlaceable') == true
    end
    function B.available()
        return api.remote and api.remote('DragService', 'Request') and api.remote('DragService', 'Cancel')
            and api.remote('InteractionService', 'Interact') ~= nil
    end
    local function clearHold(job)
        for _, object in ipairs(job.constraints or {}) do pcall(function() object:Destroy() end) end
        job.constraints = {}; job.goal = nil
        job.ctx.bringEquipmentLock = nil
    end
    local function retire(job)
        clearHold(job)
        if s.bringDelivery == job then s.bringDelivery = nil end
    end
    local cancel
    local function call(job, method, rf, args, callback, guard)
        if job.pending or not rf then return false end
        local token = {started = now(), method = method}
        job.pending = token
        task.spawn(function()
            -- Cancel has no target argument. A manual drag that began while
            -- this task was queued must keep its native ownership untouched.
            if method=='Cancel' and manual()then
                if job.pending==token then job.pending=nil;job.manualConflict=true end
                return
            end
            if guard then
                local checked,allowed=pcall(guard)
                if not checked or allowed~=true then
                    if job.pending==token then job.pending=nil;pcall(callback,true,false)end
                    return -- Proven not sent; never acquire or compensate ownership.
                end
            end
            -- Native calls may yield indefinitely. Keep the slot quarantined until
            -- the actual reply; timeout must never authorize another ownership request.
            local ok, value = pcall(function() return rf:InvokeServer(unpackValues(args, 1, #args)) end)
            if job.pending ~= token then return end
            job.pending = nil
            local handled = pcall(callback, ok, value)
            if not handled then
                if method == 'Cancel' then job.releaseFailed = true; clearHold(job)
                else job.owns = true; cancel(job) end
            end
        end)
        return true
    end
    cancel = function(job)
        job.cancelled = true
        clearHold(job)
        if job.pending then return end
        if job.releaseFailed then return end
        if not job.owns then retire(job); return end
        if manual() then
            job.manualConflict = true
            s.smartLootStatus = 'Bring cleanup waits for your manual drag'
            return -- Cancel has no item argument; never cancel another manual drag.
        end
        job.stage = 'release'
        call(job, 'Cancel', job.cancelRemote, {true}, function(ok, value)
            if ok and value ~= false then job.owns = false; retire(job)
            else
                job.releaseFailed = true
                s.smartLootStatus = 'Bring ownership release unconfirmed; further bringing paused'
            end
        end)
    end
    function B.cleanup(ctx)
        if B.worldChanged then pcall(B.worldChanged,ctx) end
        if cancelReload then pcall(cancelReload,ctx) end
        ctx.itemObservePending, ctx.itemObserveCount = nil, nil
        ctx.itemWorldSnapshot, ctx.itemWorldAt, ctx.itemWorldDirty = nil, nil, nil
        local job = s.bringDelivery
        if job and job.ctx == ctx then cancel(job) end
    end
    function B.blocksSave()
        local job = s.bringDelivery
        -- A timed-out/cancelled ownership call quarantines further bringing,
        -- not extraction. Its late reply can only release; it cannot pick up loot.
        return job ~= nil and not job.cancelled
    end
    local function looseMetadata(item)
        if not api.free(item) or api.skip(item) then return false end
        if item:GetAttribute('Welded') or api.tag(item, 'Welded') or api.tag(item, 'BuyPart')
            or api.tag(item, 'Ore') or item:GetAttribute('Placed') == true
            or item:GetAttribute('CraftedPlaceable') == true then return false end
        local ancestor = item.Parent
        while ancestor and ancestor ~= workspace do
            if api.tag(ancestor, 'BuyPart') then return false end
            ancestor = ancestor.Parent
        end
        local owner = tonumber(item:GetAttribute('OwnerUserId'))
        return not owner or owner == 0 or owner == api.Players.LocalPlayer.UserId
    end
    local function loose(ctx, item) return api.part(item) ~= nil and looseMetadata(item) end
    -- Remembered Item Reloading adapted from manual DTeC's Memory/LoadTick.
    -- Only real seen loose drops are remembered. No saved Instance is sent to
    -- the server after unloading; normal bringing revalidates the loaded item.
    local function memory(ctx)
        local band = tonumber(workspace:GetAttribute('InfiniteDepthOffsetMeters')) or 0
        local job = tostring(game.PlaceId) .. ':' .. tostring(game.JobId)
        local m = s.lootItemMemory
        if not m or m.band ~= band or m.job ~= job then
            if m and m.reload and api.cancelReload then chargeReload(m.reload); api.cancelReload(m.reload.ctx, m.reload.token) end
            m = {records = {}, byTarget = {}, serial = 0, band = band, job = job}
            s.lootItemMemory = m
            ctx.bringScan = nil
            ctx.itemWorldSnapshot, ctx.itemWorldAt, ctx.itemWorldDirty = nil, nil, nil
        end
        if m.schedulerVersion ~= 1 then
            m.schedulerVersion, m.areas, m.pass, m.passNumber = 1, {}, nil, nil
        end
        return m
    end
    local function areaFor(m, position, create)
        for _, area in ipairs(m.areas) do
            if (area.position - position).Magnitude <= 32 then return area end
        end
        if not create then return end
        if #m.areas >= 32 then
            local oldest = 1
            for i = 2, #m.areas do if m.areas[i].seenAt < m.areas[oldest].seenAt then oldest = i end end
            table.remove(m.areas, oldest)
        end
        local area = {position = position, seenAt = now(), retryAt = 0, misses = 0}
        m.areas[#m.areas + 1] = area
        return area
    end
    local function areaReady(m, record)
        local area = areaFor(m, record.position)
        local limit = policy(record)
        return not area or now() >= area.retryAt
            or limit >= 4 and limit > (area.limit or 0) or api.score(record.target) > (area.score or 0)
    end
    function B.worldChanged(ctx)
        local m = s.lootItemMemory
        if workspace:GetAttribute('InfiniteRebasing') then
            if m then
                if m.reload then chargeReload(m.reload); api.cancelReload(m.reload.ctx, m.reload.token); m.reload = nil end
                for _, record in ipairs(m.records) do record.invalid = true end
                m.records, m.byTarget, m.areas, m.rebasing = {}, {}, {}, true
            end
            ctx.itemObservePending, ctx.itemObserveCount, ctx.bringScan = nil, nil, nil
            ctx.itemWorldSnapshot, ctx.itemWorldAt, ctx.itemWorldDirty = nil, nil, nil
            if api.enabled() then s.smartLootStatus = 'World coordinates are shifting; remembered loot reload paused' end
            return true
        elseif m and m.rebasing then
            m.rebasing = nil; ctx.bringScan, ctx.bringScanAt = nil, 0
            if api.enabled() then s.smartLootStatus = 'World ready; remembered loot scan resumed' end
        end
        return false
    end
    local function loadedItems(ctx, force)
        -- Share the read-only view between reloading and ordinary delivery.
        -- Events invalidate it, but cannot trigger repeated whole-list reads.
        local age = now() - (ctx.itemWorldAt or -math.huge)
        if force or not ctx.itemWorldSnapshot or age >= 1 or ctx.itemWorldDirty and age >= 0.25 then
            ctx.itemWorldSnapshot, ctx.itemWorldAt, ctx.itemWorldDirty = api.items(), now(), nil
        end
        return ctx.itemWorldSnapshot
    end
    local function live(ctx, record)
        local item = record.target
        if record.invalid or not item then return nil end
        if item.Parent and item.Parent ~= workspace:FindFirstChild('Items') then record.invalid = true; return nil end
        if item.Parent and not looseMetadata(item) then record.invalid = true; return nil end
        if item.Parent and api.part(item) then
            if api.id(item) == record.id then return item end
            record.invalid = true -- Loaded stock/ownership/tag changes are not streaming loss.
        end
    end
    local function prune(m)
        for i = #m.records, 1, -1 do
            local record = m.records[i]
            if record.invalid or now() - record.seenAt > 1800 then
                record.invalid = true
                m.byTarget[record.target] = nil; table.remove(m.records, i)
            end
        end
        while #m.records > 256 do
            local oldest = 1
            for i = 2, #m.records do if m.records[i].seenAt < m.records[oldest].seenAt then oldest = i end end
            m.records[oldest].invalid = true
            m.byTarget[m.records[oldest].target] = nil; table.remove(m.records, oldest)
        end
    end
    local function capture(ctx, item, useful)
        if not api.enabled() or not useful or workspace:GetAttribute('InfiniteRebasing') then return end
        local m = memory(ctx)
        local record = m.byTarget[item]
        if s.bringDelivery and s.bringDelivery.item == item then return record end
        -- Losing the parent/parts is the condition this feature recovers from;
        -- it must not be mistaken for a newly ineligible loaded drop.
        if not item.Parent then return record end
        if not looseMetadata(item) then
            if record then record.invalid = true end
            return
        end
        if not api.part(item) then return record end
        if not useful(item) then
            if record then record.invalid = true end
            return
        end
        local p = api.part(item)
        local name = api.id(item)
        if not record then
            local match, ambiguous
            for _, old in ipairs(m.records) do
                if not old.invalid and old.id == name and not live(ctx, old) and not old.invalid
                    and (old.position - p.Position).Magnitude <= 4 then
                    if match then ambiguous = true; break end
                    match = old
                end
            end
            if match and not ambiguous then record = match; m.byTarget[record.target] = nil
            else m.serial = m.serial + 1; record = {serial = m.serial}; m.records[#m.records + 1] = record end
        end
        record.target, record.id, record.position, record.seenAt = item, name, p.Position, now()
        record.invalid = false; m.byTarget[item] = record
        -- Preserve request cooldown across a recreated streamed Instance.
        ctx.itemRetry[item] = math.max(ctx.itemRetry[item] or 0, record.retryAt or 0)
        if #m.records > 256 then prune(m) end
        return record
    end
    function B.observe(ctx, item)
        if not api.enabled() or not ctx.active or not api.rememberSnapshot or B.worldChanged(ctx) then return end
        local items = workspace:FindFirstChild('Items')
        if not items then return end
        local target = item
        for _ = 1, 12 do
            if not target or target == workspace or target.Parent == items then break end
            target = target.Parent
        end
        if not target or target.Parent ~= items or not (target:IsA('Model') or target:IsA('BasePart')) then return end
        ctx.itemWorldDirty = true
        ctx.itemObservePending = ctx.itemObservePending or {}
        if not ctx.itemObservePending[target] and (ctx.itemObserveCount or 0) < 256 then
            ctx.itemObservePending[target] = true; ctx.itemObserveCount = (ctx.itemObserveCount or 0) + 1
        end
    end
    function B.forget(item)
        local m = s.lootItemMemory
        local record = m and m.byTarget[item]
        if record then record.invalid = true; m.byTarget[item] = nil end
    end
    cancelReload = function(ctx)
        local m = s.lootItemMemory
        local reload = m and m.reload
        if reload and (not ctx or reload.ctx == ctx) then
            chargeReload(reload)
            api.cancelReload(reload.ctx, reload.token); m.reload = nil
        end
    end
    memoryStep = function(ctx)
        if not api.rememberSnapshot then return end
        if api.reloadTick then api.reloadTick(ctx) end
        if B.worldChanged(ctx) then cancelReload(ctx); return end
        if not ctx.active or not api.enabled() or not api.owned() or not api.safe(ctx) or manual() then
            cancelReload(ctx); return
        end
        local m = memory(ctx)
        if ctx.itemObservePending and next(ctx.itemObservePending) then
            local useful, count = api.rememberSnapshot(ctx), 0
            for item in pairs(ctx.itemObservePending) do
                ctx.itemObservePending[item] = nil; ctx.itemObserveCount = math.max(0, (ctx.itemObserveCount or 0) - 1)
                capture(ctx, item, useful); count = count + 1
                if count >= 32 then break end
            end
        end
        if now() >= (m.pruneAt or 0) then prune(m); m.pruneAt = now() + 2 end
        local reload = m.reload
        if reload and (reload.ctx ~= ctx or api.reloadEnabled and not api.reloadEnabled(ctx)) then cancelReload(); reload = nil end
        if reload then
            local record, token = reload.record, reload.token
            -- Charge successful early arrivals too. Restreaming or a recreated
            -- target cannot erase the original remembered entry's attempt count.
            countReload(reload)
            if token.done and not reload.pollUntil then
                reload.pollUntil = token.ok and math.max(token.started + 3, now() + 0.15) or now() + 0.25
            end
            local finishing = reloadDue(reload)
            -- Bounded rescan handles fresh Instances, partial model loading and
            -- delayed replication even when DescendantAdded is unavailable.
            -- Like Memory.Poll in the manual script, force a final real view at
            -- the observation boundary instead of trusting a stale earlier scan.
            if finishing and not reload.finalStarted then
                reload.scan = {items = loadedItems(ctx, true), cursor = 1}; reload.finalStarted = true
            elseif not reload.scan and now() >= (reload.scanAt or 0) and not reload.finalStarted then
                reload.scan = {items = loadedItems(ctx), cursor = 1}; reload.scanAt = now() + 1
            end
            if reload.scan then
                local scan, useful = reload.scan, api.rememberSnapshot(ctx)
                for _ = 1, 128 do
                    local item = scan.items[scan.cursor]; if not item then break end
                    scan.cursor = scan.cursor + 1; capture(ctx, item, useful)
                end
                if scan.cursor > #scan.items then
                    reload.scan = nil
                    if reload.finalStarted then reload.finalDone = true end
                end
            end
            local item = live(ctx, record)
            if item then
                local area = areaFor(m, record.position)
                if area then area.retryAt, area.misses, area.seenAt = 0, 0, now() end
                cancelReload(ctx); ctx.bringScan, ctx.bringScanAt = nil, 0
                s.smartLootStatus = 'Remembered loot loaded: ' .. record.id
                return
            end
            if record.invalid or now() - record.seenAt > 1800 or not api.eligible(ctx, record.target) then cancelReload(ctx); return end
            api.pollReload(ctx, token)
            countReload(reload)
            if token.done and not reload.pollUntil then
                -- Match the manual script: a short native read still gets a
                -- full three-second arrival window measured from actual dispatch.
                reload.pollUntil = token.ok and math.max(token.started + 3, now() + 0.15) or now() + 0.25
            end
            local hardStop = token.started and now() >= token.started + RELOAD_WINDOW
                or not token.started and now() - reload.started >= 12
            if reloadDue(reload) and (reload.finalDone or hardStop) then
                if token.called and not token.skipped then
                    local _, base = policy(record)
                    record.reloadAt = now() + math.min(120, base * 2 ^ math.max(0, (record.attempts or 1) - 1))
                    local area = areaFor(m, record.position, true)
                    area.misses, area.seenAt = area.misses + 1, now()
                    area.limit, area.score = math.max(area.limit or 0, (policy(record))), math.max(area.score or 0, api.score(record.target))
                    area.retryAt = now() + math.min(120, 30 * 2 ^ (area.misses - 1))
                end
                cancelReload(ctx)
                s.smartLootStatus = (token.blocked or token.cancelFailed)
                    and 'Area request stalled; loaded loot and chest work continue'
                    or 'Remembered loot still unloaded; chest route continues'
            end
            return
        end
        if not api.requestReload or not B.available() or api.reloadEnabled and not api.reloadEnabled(ctx)
            or now() < (m.reloadAt or 0) then return end
        if #m.records == 0 then return end
        m.reloadAt = now() + 1 -- bounded selection; request cadence is independently eight seconds.
        local eligible = api.snapshot(ctx)
        local best, score, loadedReady
        for _, record in ipairs(m.records) do
            local item = not record.invalid and live(ctx, record)
            local limit = policy(record)
            if item and now() >= (ctx.itemRetry[item] or 0) and eligible(item) then
                loadedReady = math.max(loadedReady or 0, api.score(item))
            end
            if not record.invalid and not item and (record.attempts or 0) < limit and now() >= (record.reloadAt or 0)
                and now() >= (record.retryAt or 0) and areaReady(m, record) and eligible(record.target) then
                local value = api.score(record.target)
                if not best or value > score or value == score and record.seenAt > best.seenAt then best, score = record, value end
            end
        end
        if loadedReady and (not best or loadedReady >= score) then return end
        if best then
            local limit = policy(best)
            local token = api.requestReload(ctx, best.position, function()
                return ctx.active and api.enabled() and api.owned() and api.safe(ctx) and not manual()
                    and not workspace:GetAttribute('InfiniteRebasing') and s.lootItemMemory == m and m.reload and m.reload.record == best
                    and (not api.reloadEnabled or api.reloadEnabled(ctx)) and not best.invalid
                    and (best.attempts or 0) < policy(best) and not live(ctx, best) and not best.invalid
                    and areaReady(m, best) and api.eligible(ctx, best.target)
            end)
            if token then
                m.reload = {ctx = ctx, record = best, token = token, started = now()}; m.reloadAt = now() + 1
                s.smartLootStatus = string.format('Reloading useful loot: %s [item #%d, attempt %d/%d]',
                    best.id, best.serial, (best.attempts or 0) + 1, limit)
            end
        end
    end
    local function moveItem(job)
        local item, root = job.item, job.ctx.root
        local p = api.part(item)
        if not p or not root.Parent then return false end
        local cf = root.CFrame * CFrame.new(3, 1, -4)
        local previous = job.rootPosition
        local moving = previous and (root.Position - previous).Magnitude > 6
        local error = (item:GetPivot().Position - cf.Position).Magnitude
        if not previous or moving or error > 2 then
            if previous and not moving and error > 8 then
                job.corrections = (job.corrections or 0) + 1
                if job.corrections > 3 then return false end
            end
            item:PivotTo(cf)
            p.AssemblyLinearVelocity, p.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
        end
        job.rootPosition = root.Position
        return true
    end
    local function hold(job)
        local p, root = api.part(job.item), job.ctx.root
        job.constraints = {}
        local function create(class, parent)
            local object = Instance.new(class); job.constraints[#job.constraints + 1] = object
            object.Name, object.Parent = 'EarthAutofarmBring', parent
            return object
        end
        local attach = create('Attachment', p)
        attach.CFrame = p.CFrame:ToObjectSpace(job.item:GetPivot())
        local goal = create('Attachment', root); goal.CFrame = CFrame.new(3, 1, -4)
        local align = create('AlignPosition', p)
        align.Attachment0, align.Attachment1 = attach, goal
        align.Responsiveness, align.MaxForce = 45, 45000
        align.RigidityEnabled, align.ReactionForceEnabled = false, false
        local orientation = create('AlignOrientation', p)
        orientation.Attachment0, orientation.Attachment1 = attach, goal
        orientation.Responsiveness, orientation.MaxTorque = 45, 500000
        orientation.RigidityEnabled, orientation.ReactionTorqueEnabled = false, false
        job.goal = goal; job.ctx.bringEquipmentLock = true
        if not moveItem(job) then error('Bring placement unavailable') end
        job.stage, job.readyAt = 'hold', now() + 0.45
    end
    function B.step(ctx, allowNew)
        if api.settleRoom then api.settleRoom(ctx) end
        memoryStep(ctx)
        local job = s.bringDelivery
        if job then
            if job.ctx ~= ctx or not ctx.active or not api.enabled() or not api.owned()
                or not api.safe(ctx) or manual() then cancel(job); return true end
            if job.cancelled then
                if not job.pending and not job.releaseFailed then cancel(job) end
                return true
            end
            if job.pending and now() - job.pending.started >= 8 then
                s.smartLootStatus = 'Bring reply delayed; chest route continues without duplicate requests'
                cancel(job); return true
            end
            if job.receipt and api.received(ctx, job.receipt) then
                api.confirm(ctx, job.receipt); cancel(job); return true
            end
            if not loose(ctx, job.item) or not api.eligible(ctx, job.item) then cancel(job); return true end
            if job.owns then
                local ok, moved = pcall(moveItem, job)
                if not ok or not moved then cancel(job); return true end
            end
            if job.stage == 'hold' and now() >= job.readyAt and not s.lootRequest then
                -- Recheck after the ownership wait, while beside the current root.
                if not api.eligible(ctx, job.item) then cancel(job); return true end
                local p = api.part(job.item)
                if not p or (p.Position - ctx.root.Position).Magnitude > 8 then cancel(job); return true end
                -- Capacity replacement happens only after a successful ownership
                -- grant and stable delivery. It never holds the character route.
                if api.makeRoom and not api.makeRoom(ctx, job.item) then return true end
                local receipt = api.receipt(ctx, job.item); receipt.brought = true
                job.receipt, ctx.gearPickup = receipt, receipt
                job.stage, job.receiptUntil = 'receipt', now() + 5
                if not api.interact(ctx, job.item, function(result)
                    receipt.settled, receipt.settledAt = true, now()
                    if not api.accepted(result) then
                        if ctx.gearPickup == receipt then ctx.gearPickup = nil end
                        s.smartLootStatus = 'Brought item pickup rejected; continuing chest route'
                        cancel(job)
                    end
                end) then
                    ctx.gearPickup = nil; cancel(job)
                end
            elseif job.stage == 'receipt' and now() >= job.receiptUntil then
                s.smartLootStatus = 'Brought item has no inventory receipt; chest route continues'
                cancel(job)
            end
            return true
        end
        if not allowNew or not api.enabled() or not api.safe(ctx) or manual() or s.lootRequest
            or s.equipmentRequest or ctx.gearPickup or api.roomPending and api.roomPending()
            or now() < (ctx.bringScanAt or 0) then return false end
        -- Bounded work per pulse: one local inventory view per chunk, 128 items
        -- maximum, and one world snapshot per second. Never walks Workspace here.
        if not ctx.bringScan then
            ctx.bringScan = {items = loadedItems(ctx), cursor = 1}
        end
        local scan = ctx.bringScan
        local eligible, useful = api.snapshot(ctx)
        for _ = 1, 128 do
            local item = scan.items[scan.cursor]
            if not item then break end
            scan.cursor = scan.cursor + 1
            capture(ctx, item, useful)
            if loose(ctx, item) and now() >= (ctx.itemRetry[item] or 0) and eligible(item) then
                local score = api.score(item)
                if not scan.best or score > scan.score then scan.best, scan.score = item, score end
            end
        end
        if scan.cursor <= #scan.items then return false end
        ctx.bringScan, ctx.bringScanAt = nil, now() + 1
        local item = scan.best
        if not item or not loose(ctx, item) or not api.eligible(ctx, item) then return false end
        job = {ctx = ctx, item = item, stage = 'request', cancelRemote = api.remote('DragService', 'Cancel')}
        s.bringDelivery = job; ctx.itemRetry[item] = now() + 300
        local m = s.lootItemMemory
        local remembered = m and m.byTarget[item]
        if remembered then remembered.retryAt = now() + 300 end
        ctx.bringEquipmentLock = true
        s.smartLootStatus = 'Bringing useful loot: ' .. api.id(item)
        local issued = call(job, 'Request', api.remote('DragService', 'Request'), {item}, function(ok, granted)
            if ok and granted == false then retire(job); return end
            -- Unknown replies can still have granted ownership: release once,
            -- with no guessed success or duplicate Request.
            job.owns = true
            if not ok or granted ~= true or job.cancelled or not ctx.active or not api.owned()
                or not api.enabled() or not api.safe(ctx) or manual() or not loose(ctx, item)
                or not api.eligible(ctx, item) then cancel(job); return end
            local held = pcall(hold, job)
            if not held then cancel(job) end
        end,function()
            return s.bringDelivery==job and ctx.active and s.farm==ctx and api.owned() and api.enabled()
                and ctx.character==api.Players.LocalPlayer.Character and ctx.humanoid.Health>0
                and api.safe(ctx) and not manual() and not job.cancelled
                and loose(ctx,item) and api.eligible(ctx,item)
        end)
        if not issued then retire(job) end
        return true
    end
    return B
end

end)()
    local buildQuest = (function()
-- Optional quest worker. Only replicated objective counts establish progress.
-- Selling/refuelling use owned loose items and physical contact, not invented remotes.
return function(api)
    local Q, s, cfg, now = {}, api.state, api.state.config, api.now
    local buildQuestLoadout = (function()
-- Owned lobby gear only. Native SetEquipped(itemId) toggles selection;
-- never repeat an unknown swap, and never purchase unavailable Void items.
return function(api,Q)
    local L,s,cfg,now={},api.state,api.state.config,api.now
    local function lobby()return game.PlaceId==101906032112547 or workspace:FindFirstChild('Lobby')~=nil end
    local function contains(t,id)
        if type(t)~='table' then return false end
        for _,value in pairs(t)do if value==id then return true end end
        return false
    end
    local function add(out,t)
        if type(t)~='table' then return end
        for _,value in pairs(t)do
            local id=type(value)=='table' and value.Name or value
            if type(id)=='string' then
                -- Native ToolStack.GetInventoryCount: saved gear records do
                -- not need Count. Ordinary gear counts as one by Name.
                local count=type(value)=='table' and tonumber(value.Count) or nil
                count=count or 1
                if count and count>0 then out[id]=true end
            end
        end
    end
    function L.desired(data,catalog,owned)
        local result={}
        local plan=Q.plan(data,catalog,cfg.driveDepth)
        if Q.special and Q.special.fastPlacement(plan)then
            local ids=Q.special.starterIds(plan)
            for id in pairs(ids)do if owned[id]then result[#result+1]=id end end
            table.sort(result);return result
        end
        for _,id in ipairs({'Void_Helmet','Void_Chest','Void_Legs','Pickaxe_Void'})do if owned[id]then result[#result+1]=id end end
        local id=plan.weapon or (plan.weaponClass=='Sword' or plan.kind~='combat') and 'Sword_Void'
        -- Gun-only objectives do not add a sword over their class weapon.
        if id and owned[id]then result[#result+1]=id end
        return result
    end
    function L.lobby()
        if not cfg.classQuest or not api.owned() or not lobby() then return false end
        local desiredPlan=Q.plan(s.classData,s.questCatalog,cfg.driveDepth)
        local key=tostring(game.JobId or '')..':'..tostring(s.classData and s.classData.SelectedClass or '')..':'
            ..tostring(desiredPlan.level)..':'..tostring(desiredPlan.kind)..':'..tostring(desiredPlan.weapon)
            ..':'..tostring(desiredPlan.weaponClass)..':'..tostring(desiredPlan.objective)
        local job=s.questLoadout
        if not job or job.key~=key then
            if s.questCalls.loadoutData or s.questCalls.loadoutRead or s.questCalls.loadoutSwap then
                s.questStatus='Waiting for the existing startup loadout reply before lobby start';return true
            end
            job={key=key,started=now(),attempted={},owned={}};s.questLoadout=job
            Q.call('loadoutData','PlayerDataService','GetData',{},function(ok,data)
                if ok and type(data)=='table' then
                    add(job.owned,data.Armor);add(job.owned,data.Tools);add(job.owned,data.ArmoryItems)
                    job.loaded=true
                else job.failed=true end
            end,function()return cfg.classQuest and api.owned() and lobby() and s.questLoadout==job end)
            Q.call('loadoutRead','LobbyBackpackService','GetEquipped',{},function(ok,data)
                if ok and type(data)=='table'then job.equipped=data else job.failed=true end
            end,function()return cfg.classQuest and api.owned() and lobby() and s.questLoadout==job end)
        end
        local preview=Q.plan(s.classData,s.questCatalog,cfg.driveDepth)
        local fast=Q.special and Q.special.fastPlacement(preview)
        if job.done then return false end
        if job.failed or now()-job.started>=20 then
            if not fast then return false end
            if job.equipped then job.loaded=true;job.failed=nil end
            if not job.equipped and not s.questCalls.loadoutRead and now()>=(job.recheckAt or 0)then
                job.recheckAt=now()+5
                Q.call('loadoutRead','LobbyBackpackService','GetEquipped',{},function(ok,data)
                    if ok and type(data)=='table'then job.equipped=data;job.loaded=true;job.failed=nil end
                end,function()return cfg.classQuest and lobby() and s.questLoadout==job end)
            end
            if not job.equipped then s.questStatus='Starter-only loop waits for verified lobby equipment; saved gear is not consumed';return true end
        end
        if not job.loaded or not job.equipped or not s.classData or not s.questCatalog then return true end
        local plan=Q.plan(s.classData,s.questCatalog,cfg.driveDepth)
        if plan.kind=='waiting' then return true end
        local entry=s.questCatalog[plan.name]
        if entry then
            for level,tools in pairs(entry.StarterTools or {})do
                if type(level)=='number' and level<=plan.level then add(job.owned,tools)end
            end
        end
        local c=api.controller('BackpackController')
        if c and (c.EquipPending or 0)>0 then return true end
        local actions={}
        fast=Q.special and Q.special.fastPlacement(plan)
        if fast then
            local keep=Q.special.starterIds(plan)
            for _,id in pairs(job.equipped)do if type(id)=='string' and not keep[id]then actions[#actions+1]={id=id,wanted=false}end end
        end
        if plan.weapon and plan.weapon~='Sword_Void' and (plan.weaponClass~='Sword' or not job.owned[plan.weapon])
            or plan.weaponClass=='Gun' or plan.weaponClass=='Rifle' or plan.weaponClass=='Shotgun'then
            actions[#actions+1]={id='Sword_Void',wanted=false}
        end
        for _,id in ipairs(L.desired(s.classData,s.questCatalog,job.owned))do actions[#actions+1]={id=id,wanted=true}end
        for _,action in ipairs(actions)do
            local id,wanted=action.id,action.wanted
            if fast and contains(job.equipped,id)~=wanted and job.attempted[id]then
                if not s.questCalls.loadoutRead and not s.questCalls.loadoutSwap and now()>=(job.recheckAt or 0)then
                    job.recheckAt=now()+5
                    Q.call('loadoutRead','LobbyBackpackService','GetEquipped',{},function(ok,data)
                        if ok and type(data)=='table'then job.equipped=data end
                    end,function()return cfg.classQuest and lobby() and s.questLoadout==job end)
                end
                s.questStatus='Starter-only loop waits for its actual equipment-selection receipt';return true
            end
            if contains(job.equipped,id)~=wanted and not job.attempted[id]then
                if s.questCalls.loadoutSwap then return true end
                local issued=Q.call('loadoutSwap','LobbyBackpackService','SetEquipped',{id},function(ok,accepted,equipped)
                    if ok and accepted and type(equipped)=='table' then
                        job.equipped=equipped
                        if c and type(c.SetEquipped)=='function' then pcall(c.SetEquipped,c,equipped)end
                        s.questStatus=contains(equipped,id) and 'Quest startup gear confirmed: '..id or 'Startup gear not selected: '..id
                    else s.questStatus='Startup gear unconfirmed: '..id..'; no repeat toggle' end
                end,function()return cfg.classQuest and api.owned() and lobby() and s.questLoadout==job
                    and contains(job.equipped,id)~=wanted and (not c or (c.EquipPending or 0)==0) end)
                if issued then job.attempted[id]=true end
                return true
            end
        end
        job.done=true;return false
    end
    local function carried(ctx,id)
        for _,piece in ipairs(ctx.character:GetChildren())do
            if piece:GetAttribute('ArmorName')==id then return true end
        end
        return api.findOwned(ctx,id)~=nil
    end
    function L.step(ctx,plan)
        if Q.special and Q.special.fastPlacement(plan)then ctx.questStartup=nil;return false end
        if not cfg.classQuest or lobby() or api.Players.LocalPlayer:GetAttribute('InitialInventoryLoaded')~=true
            or api.extractionReady() then return false end
        local c=api.controller('CrateController')
        if c and (c.DeathChest or c.ClaimPending)then return false end
        local job=s.questCrateLoadout
        local key=tostring(plan.name)..':'..tostring(plan.level)..':'..tostring(plan.kind)..':'..tostring(plan.weapon)
            ..':'..tostring(plan.weaponClass)..':'..tostring(plan.objective)
        if job and job.done and job.planKey~=key and not s.questCalls.crateClaim then
            s.questCrateLoadout=nil;s.questCrateProbeAt=nil;job=nil
        end
        if job and job.ctx~=ctx and not s.questCalls.crateClaim then s.questCrateLoadout=nil;s.questCrateProbeAt=nil;job=nil end
        if s.questDeathClaim or s.questCalls.deathClaim then return false end
        if job and job.readFailed and not job.issued and not s.questCalls.crateRead
            and not s.questCalls.crateClaim and now()>=(job.retryAt or 0)then
            -- A failed read did not consume saved equipment. Retry only that
            -- read; an issued or uncertain SetLoadout stays a one-time claim.
            s.questCrateLoadout=nil;s.questCrateProbeAt=now();job=nil
        end
        if not job then
            if now()<(s.questCrateProbeAt or 0)then return false end
            s.questCrateProbeAt=now()+2
            job={ctx=ctx,started=now(),planKey=key};s.questCrateLoadout=job
            if not Q.call('crateRead','PlayerService','GetCrateItems',{},function(ok,data)
                if ok and type(data)=='table'then job.owned={};add(job.owned,data);job.loaded=true
                else
                    job.readFailed=true;job.retryAt=now()+10
                    s.questStatus='Saved startup crate read unavailable; retrying the read while other work continues'
                end
            end,function()return Q.enabled(ctx) and not api.extractionReady()end)then s.questCrateLoadout=nil end
            return false
        end
        if job.done then ctx.questStartup=nil;return false end
        if not job.loaded then return false end
        if job.issued then
            local missing={}
            for _,id in ipairs(job.ids)do if not carried(ctx,id)then missing[#missing+1]=id end end
            if #missing==0 then
                job.done=true;ctx.questStartup=nil;s.questStatus='Void quest startup confirmed in worn armor / inventory'
                return false
            end
            if job.rejected or now()-job.issuedAt>=8 then
                job.done=true;ctx.questStartup=nil
                s.questStatus='Void startup not confirmed: '..table.concat(missing,', ')..'; no repeated crate claim'
                return false
            end
            ctx.questStartup=true;Q.stopDrive(ctx)
            s.questStatus='Awaiting Void startup armor / tools replication';return true
        end
        local ids=L.desired(s.classData,s.questCatalog,job.owned);local payload={};job.ids={}
        for _,id in ipairs(ids)do if not carried(ctx,id)then payload[id]=1;job.ids[#job.ids+1]=id end end
        if #job.ids==0 then
            job.done=true;s.questStatus='Saved crate has no missing eligible Void startup gear';return false
        end
        if Q.manual() or s.questDelivery or s.bringDelivery or s.lootRequest then return false end
        if Q.call('crateClaim','PlayerService','SetLoadout',{payload},function(ok,accepted)
            job.rejected=not ok or not accepted
        end,function()return Q.enabled(ctx) and not api.extractionReady() and not Q.manual()
            and not (c and (c.DeathChest or c.ClaimPending))end)then
            job.issued,job.issuedAt=true,now();ctx.questStartup=true;Q.stopDrive(ctx)
            s.questStatus='Claiming owned Void quest gear from the saved-items crate';return true
        end
        return false
    end
    local function count(ctx,id)
        local total=0
        for _,container in ipairs({ctx.character,api.Players.LocalPlayer:FindFirstChild('Backpack')})do
            if container then for _,item in ipairs(container:GetChildren())do
                if item:GetAttribute('ArmorName')==id then total=total+1
                elseif api.id(item)==id then total=total+(tonumber(api.stackCount(item)) or 1)end
            end end
        end
        return total
    end
    function L.remember(ctx)
        if not cfg.classQuest or ctx.humanoid.Health<=0 or now()<(ctx.questGearRememberAt or 0)then return end
        ctx.questGearRememberAt=now()+.5
        local ids={}
        for _,container in ipairs({ctx.character,api.Players.LocalPlayer:FindFirstChild('Backpack')})do
            if container then for _,item in ipairs(container:GetChildren())do
                local id=item:GetAttribute('ArmorName')
                if not id and item:IsA('Tool')then id=api.id(item)end
                if type(id)=='string' and id~=''then ids[id]=true end
            end end
        end
        ctx.questGearSnapshot=ids
    end
    function L.stopped(ctx)
        if cfg.classQuest and ctx.questGearSnapshot and (ctx.humanoid.Health<=0
            or api.Players.LocalPlayer.Character~=ctx.character)then s.questDeathGear=ctx.questGearSnapshot end
    end
    local function contentCounts(data)
        if type(data)~='table'then return end
        local result={}
        for _,id in pairs(data)do
            if type(id)~='string' or id==''then return end -- Native DrawCrate counts a list of IDs.
            result[id]=(result[id] or 0)+1
        end
        return result
    end
    local function ownChest(chest)
        if not chest or type(chest.GetAttribute)~='function' or not chest.Parent or not chest:IsDescendantOf(workspace)
            or chest:GetAttribute('DeathChest')~=true or tonumber(chest:GetAttribute('Owner'))~=api.Players.LocalPlayer.UserId then return false end
        local expires=tonumber(chest:GetAttribute('DeathChestDespawnExpiresAt'))
        return (not expires or expires>workspace:GetServerTimeNow()) and api.position(chest)~=nil
    end
    local function missing(ctx,job)
        local ids={}
        for id in pairs(job.expected or {})do if count(ctx,id)==0 then ids[#ids+1]=id end end
        table.sort(ids,function(a,b)
            local preferred=s.questDeathGear or {}
            local pa=preferred[a] or a:find('Void',1,true) or a=='Sword_Pirate' or a=='Flintlock'
            local pb=preferred[b] or b:find('Void',1,true) or b=='Sword_Pirate' or b=='Flintlock'
            if (not not pa)~=(not not pb) then return not not pa end
            return a<b
        end)
        return ids
    end
    local function releaseRecovery(ctx,job,text,keepPriority)
        ctx.questRecovering=nil;ctx.questOwns=nil
        if not keepPriority then ctx.questRecoveryDue=nil end
        if text then s.questStatus=text end
        return false
    end
    local function readChest(ctx,job)
        if job.reading or s.questCalls.deathContents or now()<(job.nextReadAt or 0)then return false end
        job.reading=true;local life=ctx;local started=now()
        local issued=Q.call('deathContents','DeathChestService','GetContents',{job.chest},function(ok,data)
            job.reading=nil
            if job.ctx~=life then job.nextReadAt=now();return end
            local counts=ok and contentCounts(data)
            if not counts then
                job.nextReadAt=now()+10;job.readFailed=true
                s.questStatus='Death chest contents unavailable; retrying the read, not an uncertain claim';return
            end
            job.readFailed=nil;job.remaining=counts;job.readAt=started;job.nextReadAt=now()+2
            if not job.expected then job.expected=counts;job.before={};job.credited={}
                for id in pairs(counts)do job.before[id]=count(ctx,id)end
            end
        end,function()return Q.enabled(life) and ownChest(job.chest) and not Q.manual()
            and (api.position(job.chest)-life.root.Position).Magnitude<=10 end)
        if not issued then job.reading=nil;job.nextReadAt=now()+2 end
        return issued
    end
    function L.recover(ctx,plan)
        ctx.questRecovering=nil
        if not Q.enabled(ctx) or api.extractionReady() or lobby() or Q.manual()
            or api.Players.LocalPlayer:GetAttribute('InitialInventoryLoaded')~=true then ctx.questRecoveryDue=nil;return false end
        local c=api.controller('CrateController')
        if c and c.ClaimPending then ctx.questRecoveryDue=nil;return false end
        local records=s.questDeathClaims or setmetatable({}, {__mode='k'});s.questDeathClaims=records
        local job=s.questDeathClaim
        if job and job.ctx~=ctx then
            job.ctx=ctx;job.leaseUntil=now()+12;job.nextReadAt=now();job.done=nil
            job.expected=nil;job.remaining=nil;job.readAt=nil;job.before={};job.credited={}
        end
        if not job then
            if now()<(s.questDeathProbeAt or 0)then return false end
            s.questDeathProbeAt=now()+.5
            local candidates,seen={},{}
            local function candidate(chest)
                if seen[chest] or not ownChest(chest)then return end
                seen[chest]=true
                local record=records[chest]
                if type(record)=='table' and (record.emptyVerified or record.done and record.ctx==ctx)then return end
                candidates[#candidates+1]=chest
            end
            -- The UI holds the real supply instance, not its separately cloned visible crate.
            if c and c.DeathChest then candidate(c.DeathChest)end
            for _,chest in ipairs(api.tagged('SupplyCrate'))do candidate(chest)end
            local chest=c and c.DeathChest
            if not seen[chest]then chest=Q.nearest(candidates,ctx.root.Position)end
            if not chest then return false end
            local record=records[chest]
            job=type(record)=='table' and record or {chest=chest,attempts=0}
            if type(record)=='boolean' and record then job.unknown=true end -- Old uncertain claim cannot be blindly replayed.
            if job.ctx and job.ctx~=ctx then job.expected=nil;job.remaining=nil;job.readAt=nil;job.before={};job.credited={};job.nextReadAt=now()end
            job.ctx=ctx;job.done=nil;job.leaseUntil=now()+12
            records[chest]=job;s.questDeathClaim=job
        end
        if job.expected and job.mutationFinished and not job.rejected then
            local gained=0
            for id,amount in pairs(job.expected)do
                local observed=math.min(amount,math.max(0,count(ctx,id)-(job.before[id] or 0)))
                local previous=job.credited[id] or 0
                if observed>previous then gained=gained+observed-previous;job.credited[id]=observed end
            end
            if gained>0 then
                s.stats.smartPickups=(s.stats.smartPickups or 0)+gained;job.leaseUntil=now()+8
                s.questStatus='Death gear received: '..gained..'; checking remaining equipment'
            end
        end
        local absent=job.expected and missing(ctx,job)
        if job.expected and not next(job.expected)then
            job.done=true;job.emptyVerified=true;records[job.chest]=job;s.questDeathClaim=nil
            return releaseRecovery(ctx,job,'Own death chest is empty; checking other gear sources')
        end
        if absent and #absent==0 then
            job.done=true;records[job.chest]=job;s.questDeathClaim=nil
            if c and c.DeathChest==job.chest and c.Frame and c.Frame.Visible and not c.ClaimPending then
                local ui=api.controller('UIController')
                if ui and type(ui.ToggleFrame)=='function'then pcall(ui.ToggleFrame,ui,'Crate',false)end
            end
            return releaseRecovery(ctx,job,job.issued and 'Death gear restored; all listed equipment is available'
                or 'Listed death gear is already carried; no duplicate claim needed')
        end
        if not ownChest(job.chest)then
            s.questDeathClaim=nil;job.nextReadAt=now()+10
            return releaseRecovery(ctx,job,'Own death chest is unloaded or unavailable; continuing loaded work')
        end
        if s.questDelivery or s.bringDelivery or s.lootRequest then
            ctx.questRecoveryDue=true
            return releaseRecovery(ctx,job,'Death gear recovery queued behind the current item transaction',true)
        end
        ctx.questRecoveryDue=nil
        local point=api.position(job.chest)
        local waiting=job.unknown or s.questCalls.deathClaim or now()<(job.cooldown or 0)
        if waiting and now()>=(job.leaseUntil or 0)then
            -- Retain the transaction and read receipts, while independent chest work resumes.
            if (point-ctx.root.Position).Magnitude<=10 then readChest(ctx,job)end
            return releaseRecovery(ctx,job,'Death claim unresolved; missing '..table.concat(absent or {},', ')..'; other work continues')
        end
        if not Q.holdRoute(ctx)then return true end
        Q.stopDrive(ctx);api.hover(ctx);api.watch(ctx);ctx.questRecovering=true
        if (point-ctx.root.Position).Magnitude>6 then
            ctx.root.CFrame=CFrame.new(point+Vector3.new(0,2,3));s.questDeathProbeAt=0
            s.questStatus='Returning to own death chest before collecting replacement gear';return true
        end
        if not job.expected or job.issued and (not job.readAt or job.readAt<=math.max(job.issuedAt,job.finishedAt or 0))then
            readChest(ctx,job)
            if job.readFailed then return releaseRecovery(ctx,job,'Death contents read failed; other work continues until retry')end
            return true
        end
        if job.unknown or s.questCalls.deathClaim then return true end
        if job.issued and now()<job.retryAt then return true end
        if job.issued and not job.mutationFinished then return true end
        if job.issued and not next(job.remaining or {})then
            -- Empty stock alone does not prove inventory replication. Give it a bounded settling window.
            if now()>=(job.leaseUntil or 0)then
                return releaseRecovery(ctx,job,'Death chest is empty; missing gear replication remains unconfirmed')
            end
            return true
        end
        if now()<(job.cooldown or 0)then return releaseRecovery(ctx,job,'Death recovery cooling down; other work continues')end
        if job.attempts>=3 then job.attempts=0;job.cooldown=now()+30
            return releaseRecovery(ctx,job,'Death claims were rejected or incomplete; retrying after cooldown')end
        local payload={}
        for _,id in ipairs(absent or {})do if (job.remaining[id] or 0)>0 then payload[id]=job.remaining[id]end end
        if job.issued and not next(payload)then
            return releaseRecovery(ctx,job,'Missing death gear is no longer in the chest; other work continues')
        end
        local method=job.issued and 'TakeItems' or 'TakeAllItems'
        local args=method=='TakeItems' and {job.chest,payload} or {job.chest}
        local life=ctx
        job.mutationFinished=nil;job.rejected=nil;job.issuedAt=now();job.nextReadAt=now()+1
        local issued=Q.call('deathClaim','DeathChestService',method,args,function(ok,value,_,dispatch)
            job.finishedAt=now()
            job.mutationFinished=true;job.rejected=ok and value==false or dispatch=='not-sent'
            job.unknown=not ok and dispatch~='not-sent'
            job.retryAt=now()+(job.rejected and 5 or 3)
            job.nextReadAt=now()+1
        end,function()return Q.enabled(life) and not api.extractionReady() and not Q.manual() and ownChest(job.chest)
            and (api.position(job.chest)-life.root.Position).Magnitude<=10 and not (c and c.ClaimPending)end)
        if issued then
            job.issued=true;job.attempts=job.attempts+1;job.leaseUntil=now()+12
            s.questStatus=method=='TakeAllItems' and 'Recovering own dropped gear; observing all equipment receipts'
                or 'Recovering verified remaining death gear through native TakeItems'
            return true
        end
        return releaseRecovery(ctx,job,'Death claim prerequisites changed; retrying the read before acting')
    end
    return L
end

end)()
    local buildQuestHealing = (function()
-- Quest-only 30%/70% hysteresis. HP and inventory changes, not a consume
-- dispatch, determine recovery. Only authorized Rare/Epic shards may yield a
-- full toolbar slot to medical supplies during healing; no paid revives.
return function(api,Q)
    local H,s,cfg,now={},api.state,api.state.config,api.now
    local function observed(key)s.stats[key]=(s.stats[key] or 0)+1 end
    local known={Advanced_Medkit=.6,Basic_Medkit=.3,Bandages=.1,Golden_Medkit=1}
    local function finite(value)return type(value)=='number' and value==value and math.abs(value)<math.huge end
    local function scope(ctx)
        local inside=Q.drillSupport.inDungeon(ctx)
        local room=inside and (Q.drillSupport.activeMine(ctx) or Q.special and Q.special.bound(ctx)) or nil
        return inside,room,room and room:GetAttribute('SessionDungeonId'),workspace:GetAttribute('InfiniteDepthOffsetMeters')
    end
    function H.itemAccessible(ctx,item)
        if not item or not item.Parent or not item:IsDescendantOf(workspace)then return false end
        local inside,room,session=scope(ctx)
        if inside then
            if not room then return false end
            if Q.drillSupport.activeMine(ctx)then return Q.drillSupport.accessible(item) end
            return item:IsDescendantOf(room) or session~=nil and item:GetAttribute('SessionDungeonId')==session
        end
        if Q.drillSupport.mineshaft(item) or item:GetAttribute('SessionDungeonId')~=nil
            or item:GetAttribute('DungeonWaveNpc')==true then return false end
        local ancestor=item
        while ancestor and ancestor~=workspace do
            if ancestor.Name=='Goblin_Ring' or ancestor.Name=='GoblinRing' or ancestor.Name=='VampireMansion'
                or api.tag(ancestor,'VampireMansion')then return false end
            ancestor=ancestor.Parent
        end
        return true
    end
    function H.isMedical(item)
        if not item or Q.protectedRelic(item) or api.attr(item,'Category')=='Explosive'
            or (tonumber(api.attr(item,'Damage')) or 0)>0 then return false end
        if known[api.id(item)]then return true end
        local fraction=tonumber(api.attr(item,'Health'))
        return api.attr(item,'Class')=='Medkit' and fraction and fraction>0 and fraction<=1
            and (api.attr(item,'Category')==nil or api.attr(item,'Category')=='Consumable')
            and (api.attr(item,'ActionType')==nil or api.attr(item,'ActionType')=='Use')
    end
    local function score(ctx,item)
        local amount=tonumber(api.attr(item,'Health')) or known[api.id(item)] or 0
        local needed=math.max(0,.7-ctx.humanoid.Health/ctx.humanoid.MaxHealth)
        return amount>=needed and 2-amount or amount -- sufficient heal, then less waste
    end
    function H.supplyIds(ctx)
        local ids,seen={},{}
        for _,item in ipairs(Q.looseItems())do
            local id=api.id(item)
            if H.isMedical(item) and H.itemAccessible(ctx,item) and not seen[id]then ids[#ids+1]={id=id,score=score(ctx,item)};seen[id]=true end
        end
        table.sort(ids,function(a,b)return a.score>b.score or a.score==b.score and a.id<b.id end)
        local out={};for _,entry in ipairs(ids)do out[#out+1]=entry.id end;return out
    end
    local function shard(ctx)
        for _,id in ipairs({'RareShard','EpicShard'})do
            for _,tool in ipairs(api.ownedTools(ctx))do
                local blocked=s.questMedicalDropBlocked and s.questMedicalDropBlocked[tool]
                if tool:IsA('Tool') and api.id(tool)==id and (not blocked or api.stackCount(tool)<blocked)then return tool end
            end
        end
    end
    function H.canMakeRoom(ctx,item)
        if api.hasRoom(ctx,item)then return true end
        return cfg.classQuest and ctx.questHealing and ctx.humanoid.Health>0
            and ctx.humanoid.Health/ctx.humanoid.MaxHealth<.7 and H.isMedical(item)
            and not Q.manual() and api.remote('ToolService','DropSpecificItem')~=nil and shard(ctx)~=nil
    end
    function H.settleRoom()
        local job=s.questMedicalDrop;if not job then return true end
        local tool=job.tool
        local remains=tool.Parent and (tool:IsDescendantOf(job.character) or job.backpack and tool:IsDescendantOf(job.backpack))
        local sameLife=api.Players.LocalPlayer.Character==job.character and job.ctx.humanoid.Health>0
        if sameLife and (not remains or api.stackCount(tool)<job.count)then
            -- Inventory loss is the receipt for this exact drop. Retire a lost
            -- reply only after its waiter actually stops, so the next medical
            -- slot can be freed without replaying an uncertain mutation.
            local token=job.token
            if token and Q.calls.medicalDrop==token then
                if token.thread then pcall(task.cancel,token.thread)end
                if token.thread and coroutine.status(token.thread)=='dead' then Q.calls.medicalDrop=nil
                else s.questStatus='Medical shard drop received; waiting for its request waiter to stop';return false end
            end
            s.questMedicalDrop=nil;s.questStatus='Medical room: shard drop receipt confirmed; rechecking slots';return true
        end
        if not job.settled then return false end
        if job.notSent then s.questMedicalDrop=nil;return true end
        if now()-job.started<5 or now()-(job.settledAt or job.started)<1.5 then return false end
        s.questMedicalDropBlocked=s.questMedicalDropBlocked or setmetatable({}, {__mode='k'})
        s.questMedicalDropBlocked[tool]=job.count;s.questMedicalDrop=nil
        s.questStatus='Medical room: shard drop unconfirmed; no duplicate drop';return true
    end
    function H.makeRoom(ctx,item)
        if not H.settleRoom()then return false end
        if api.hasRoom(ctx,item)then return true end
        if not H.canMakeRoom(ctx,item) or s.rareShardDrop or s.lootRequest or s.equipmentRequest
            or Q.calls.medicalDrop then return false end
        local tool=shard(ctx)
        local job={ctx=ctx,tool=tool,count=api.stackCount(tool),started=now(),character=ctx.character,
            backpack=api.Players.LocalPlayer:FindFirstChild('Backpack')};s.questMedicalDrop=job
        local issued=Q.call('medicalDrop','ToolService','DropSpecificItem',{tool},function(ok,value,_,dispatch)
            job.settled=true;job.settledAt=now();job.notSent=dispatch=='not-sent'
        end,function()return Q.enabled(ctx) and ctx.questHealing and not api.extractionReady() and not Q.manual()
            and s.questMedicalDrop==job and tool.Parent and api.stackCount(tool)==job.count
            and not api.hasRoom(ctx,item) and ctx.humanoid.Health/ctx.humanoid.MaxHealth<.7 end)
        if issued then job.token=Q.calls.medicalDrop end
        if not issued then s.questMedicalDrop=nil end
        s.questStatus='Medical room: dropping '..api.id(tool)..'; awaiting a real free slot';return false
    end
    local function quarantine(ctx,attempt)
        ctx.questHealTried=ctx.questHealTried or setmetatable({}, {__mode='k'})
        ctx.questHealTried[attempt.tool]={character=attempt.character or ctx.character,
            humanoid=attempt.humanoid or ctx.humanoid,nativeCount=attempt.nativeCount}
    end
    local function nativeCount(value)
        return finite(value) and value>=1 and value%1==0
    end
    function H.observe(ctx)
        -- Read-only recovery evidence. HP rises may be regeneration/teammates;
        -- they never authorize replaying an uncertain medical packet.
        local hp=ctx.humanoid.Health;local prior=ctx.questMedicalHpWatch
        if cfg.classQuest and ctx.character==api.Players.LocalPlayer.Character and finite(hp) and hp>0 then
            if prior and prior.character==ctx.character and prior.humanoid==ctx.humanoid
                and ctx.questHealing and hp>prior.health then observed('questHealingHpRises')end
            ctx.questMedicalHpWatch={character=ctx.character,humanoid=ctx.humanoid,health=hp}
        else ctx.questMedicalHpWatch=nil end
        -- A late exact stack loss proves that the earlier unit was consumed.
        -- Re-arm only its remaining unit; HP changes or stale/missing count
        -- metadata cannot authorize replaying an uncertain Consume.
        local backpack=api.Players.LocalPlayer:FindFirstChild('Backpack')
        for tool,record in pairs(ctx.questHealTried or {})do
            if type(record)=='table' and record.character==ctx.character and record.humanoid==ctx.humanoid
                and ctx.character==api.Players.LocalPlayer.Character and ctx.humanoid.Health>0
                and tool.Parent and (tool.Parent==ctx.character or tool.Parent==backpack) and H.isMedical(tool)then
                local count=tool:GetAttribute('MedicalStackCount')
                if nativeCount(record.nativeCount) and nativeCount(count) and count<record.nativeCount then
                    observed('questMedicalStackReceipts')
                    ctx.questHealTried[tool]=nil
                end
            end
        end
        local attempt=ctx.questHealAttempt
        if not attempt then return false end
        local sameLife=(attempt.character or ctx.character)==ctx.character and ctx.character==api.Players.LocalPlayer.Character
            and (not attempt.humanoid or attempt.humanoid==ctx.humanoid) and ctx.humanoid.Health>0
        if not sameLife then ctx.questHealAttempt=nil;ctx.questHealTried=nil;return true end
        local count=attempt.tool:GetAttribute('MedicalStackCount')
        local consumed=not attempt.tool.Parent or nativeCount(attempt.nativeCount) and nativeCount(count) and count<attempt.nativeCount
        if consumed then
            observed('questMedicalStackReceipts')
            ctx.questHealAttempt=nil
        elseif ctx.humanoid.Health>attempt.health then
            -- Passive or teammate healing can raise HP without consuming this
            -- unit. Recovery may continue, but its unknown packet is not replayed.
            quarantine(ctx,attempt);ctx.questHealAttempt=nil
        elseif now()-attempt.started>=3 then
            observed('questMedicalUseTimeouts')
            quarantine(ctx,attempt)
            ctx.questHealAttempt=nil;s.questStatus='Medical use unconfirmed; no repeated consume for that item'
        end
        return true
    end
    function H.cleanup(ctx)
        local job=s.questDelivery
        if job and job.healingSupply and not job.buySent then Q.release(job)end
        H.observe(ctx)
        local attempt=ctx.questHealAttempt
        if attempt and not cfg.classQuest then
            -- Explicit OFF may retire local observation, but never authorizes
            -- this same living tool's uncertain Consume to be repeated on ON.
            quarantine(ctx,attempt)
            ctx.questHealAttempt=nil;attempt=nil
        end
        local sameLife=ctx.character==api.Players.LocalPlayer.Character and ctx.humanoid.Health>0
        local temporary=cfg.classQuest and sameLife and not Q.enabled(ctx)
        local keep=cfg.classQuest and sameLife and (attempt~=nil or temporary and ctx.questHealing==true)
            and ctx.humanoid.MaxHealth>0 and ctx.humanoid.Health/ctx.humanoid.MaxHealth<.7
        ctx.questHealing=keep and true or nil
        if not keep then ctx.questRecoveryStage=nil end
        local search=ctx.questMedicalSearch
        if api.clearMedicalSearch and (search or not keep)then api.clearMedicalSearch(ctx,search)end
        ctx.questMedicalSearch,ctx.questMedicalSearchRetryAt,ctx.questMedicalLowWalletAt,ctx.questHealReadiness=nil,nil,nil,nil
        ctx.questHealPoint=nil
    end
    local function searchWallet(ctx)
        if Q.calls.healingWallet or Q.calls.wallet or Q.calls.upgradeWallet or now()<(ctx.questHealWalletAt or 0)then return end
        if finite(s.questWallet) and now()-(s.questWalletAt or -math.huge)<3 then return end
        ctx.questHealWalletAt=now()+3
        local character,drill=ctx.character,ctx.drill
        local readVersion=s.questWalletVersion or 0
        Q.call('healingWallet','CurrencyService','GetCurrency',{},function(ok,value)
            if ok and ctx.character==character and ctx.drill==drill and api.Players.LocalPlayer.Character==character
                and cfg.classQuest and ctx.questHealing and ctx.humanoid.Health>0 and not Q.manual()then Q.observeCoins(value,readVersion)end
        end,function()return Q.enabled(ctx) and ctx.questHealing and ctx.character==character and ctx.drill==drill
            and api.Players.LocalPlayer.Character==character and not Q.manual() and not api.extractionReady()end)
    end
    function H.search(ctx)
        if not api.medicalSearch or Q.manual() or api.extractionReady() or s.questDelivery or s.bringDelivery
            or s.lootRequest or ctx.bringEquipmentLock or ctx.questHealAttempt or s.questMedicalDrop
            or ctx.questMineEntry or ctx.nativeGateMotion or ctx.humanoid.SeatPart or ctx.humanoid.Sit then return false end
        searchWallet(ctx)
        local inside,room,session,band=scope(ctx)
        local job=ctx.questMedicalSearch
        if job and (job.character~=ctx.character or job.drill~=ctx.drill or job.inside~=inside or job.room~=room
            or job.session~=session or job.band~=band)then
            if api.clearMedicalSearch then api.clearMedicalSearch(ctx,job)end
            ctx.questMedicalSearch=nil;ctx.questMedicalSearchRetryAt=nil;ctx.questMedicalLowWalletAt=nil;job=nil
        end
        -- Native Bandages Cost=10 is only a scheduling hint. Scarce coins
        -- give funding the first five seconds, then still allow discovery of
        -- genuinely discounted stock or free medicine. Quotes decide spending.
        if finite(s.questWallet) and s.questWallet<10 and not job then
            ctx.questMedicalLowWalletAt=ctx.questMedicalLowWalletAt or now()+5
            if now()<ctx.questMedicalLowWalletAt then return false,'scarce Coins; funding before the next bounded medical search' end
        end
        if job and now()-job.started>=15 then
            if api.clearMedicalSearch then api.clearMedicalSearch(ctx,job)end
            ctx.questMedicalSearch=nil;ctx.questMedicalSearchRetryAt=now()+5;ctx.questMedicalLowWalletAt=now()+5
            return false,'bounded medical shop search exhausted'
        end
        if now()<(ctx.questMedicalSearchRetryAt or 0)then return false,'medical shop search retry cooling down' end
        if not job then
            job={character=ctx.character,drill=ctx.drill,inside=inside,room=room,session=session,band=band,started=now()}
            ctx.questMedicalSearch=job
        end
        local busy,reason,progressed=api.medicalSearch(ctx,job)
        if progressed then job.progressAt=now()end -- Does not reset the burst deadline.
        if busy then s.questStatus='Quest healing: '..tostring(reason or 'actively searching loaded native shops for medical supplies');return true end
        return false,reason
    end
    local function usableHandler(ctx,tool,active)
        local c=api.controller('ToolController')
        local name=api.id(tool)
        if not c or c.ActiveTool~=active or not active or active._Destroyed or not active.Tool
            or active.Tool.Parent~=ctx.character or not (active.Tool==tool or active.Tool.Name==name
                or active.Tool.Name==name..tostring(api.Players.LocalPlayer.UserId))
            or type(active.Consume)~='function' or now()<(tonumber(active.NextMedicalUseAt) or 0)then return false end
        local ok,ready=pcall(api.readyAction,active)
        if not ok or not ready then return false end
        local seen,visible=pcall(api.watcherReady,ctx)
        return seen and visible==true
    end
    local function readiness(ctx,tool)
        local ledger=ctx.questHealReadiness or setmetatable({}, {__mode='k'});ctx.questHealReadiness=ledger
        local wait=ledger[tool]
        if wait and wait.character~=ctx.character then ledger[tool]=nil;wait=nil end
        return ledger,wait
    end
    function H.step(ctx,plan)
        ctx.questRecoveryStage='safety-handoff'
        local h=ctx.humanoid;local maximum=tonumber(h.MaxHealth)
        if not cfg.classQuest or not maximum or maximum<=0 or h.Health<=0 then H.cleanup(ctx);return false end
        local ratio=h.Health/maximum
        H.settleRoom()
        if Q.prepareHealing then
            local wasHealing=ctx.questHealing
            local needs,blocked,reason=Q.prepareHealing(ctx)
            if not needs then
                H.cleanup(ctx)
                if wasHealing and h.Health/maximum>=.7 then ctx.questOwns=nil;s.questStatus='Quest healing complete; resuming at 70% HP' end
                return false
            end
            if blocked then s.questStatus=reason or 'Quest healing: waiting for native safety handoff';return true end
        end
        if not ctx.questHealing and ratio>.3 then return false end
        if ratio>=.7 then
            H.cleanup(ctx);ctx.questOwns=nil;s.questStatus='Quest healing complete; resuming at 70% HP';return false
        end
        Q.drillSupport.stopMine(ctx)
        ctx.questHealing=true
        -- Healing returns before the upgrade worker. Settle its old reservation
        -- here too, or a completed/timed-out upgrade blocks every medical buy.
        Q.drillSupport.settleUpgrade(ctx)
        ctx.questCombat=nil -- Waiting for healing is not quest counter progress.
        Q.stopDrive(ctx)
        if h.SeatPart or h.Sit then local _,holding=Q.unseat(ctx);api.watch(ctx);return holding end
        local expired=s.questDelivery
        if expired and expired.ctx==ctx and expired.kind=='supply' and finite(expired.started)
            and now()-expired.started>(expired.shop and 25 or 12)
            and not expired.pending and not expired.owns and not expired.stockPlaced
            and not Q.calls.drag and not Q.calls.shop and not Q.calls.wallet then
            -- An unacknowledged route must not retain this expired local lease.
            -- These guards exclude every native release/stock-return branch.
            Q.release(expired)
        end
        if not Q.holdRoute(ctx)then ctx.questRecoveryStage='route-handoff';return true end
        api.watch(ctx)
        if not h.SeatPart and now()>=(ctx.questHealRetreatAt or 0)
            and (not api.healingPointSafe or not api.healingPointSafe(ctx,ctx.root.Position)) then
            ctx.questHealRetreatAt=now()+3;api.retreat(ctx);api.watch(ctx)
        end
        local job=s.questDelivery
        if job then
            if job.healingFunding or job.kind=='supply' and H.isMedical(job.item) then Q.deliveryStep(ctx,plan)
            else Q.release(job)end
        end
        if Q.cashStep(ctx)then ctx.questRecoveryStage='cash-receipt';return true end
        local reserved=s.questDelivery
        local detached=reserved and reserved.cancelled and reserved.movementReleased
        if Q.manual() or reserved and not detached or s.bringDelivery or s.lootRequest or ctx.bringEquipmentLock then
            ctx.questRecoveryStage='item-reservation'
            s.questStatus='Quest healing: waiting for owned item action to release';return true
        end
        if H.observe(ctx)then ctx.questRecoveryStage='consume-receipt';return true end
        local tool,best
        for _,found in ipairs(api.ownedTools(ctx))do
            if H.isMedical(found) and not (ctx.questHealTried or {})[found]then
                local _,wait=readiness(ctx,found)
                local c=api.controller('ToolController');local active=c and c.ActiveTool
                local ready=usableHandler(ctx,found,active)
                if ready or not wait or now()>=(wait.retryAt or 0)then
                    local value=score(ctx,found)
                    if not best or value>best then tool,best=found,value end
                end
            end
        end
        if tool then
            ctx.questRecoveryStage='handler-wait'
            local ledger,wait=readiness(ctx,tool)
            if not wait or wait.retryAt then wait={started=now(),character=ctx.character};ledger[tool]=wait end
            local active=api.equip(ctx,tool)
            if usableHandler(ctx,tool,active)then
                local attempt={tool=tool,health=h.Health,count=api.stackCount(tool),nativeCount=tool:GetAttribute('MedicalStackCount'),
                    started=now(),character=ctx.character,humanoid=h}
                local sent,reason=api.consume(ctx,active)
                if sent then
                    ctx.questRecoveryStage='consume-receipt'
                    observed('questMedicalRequests')
                    ledger[tool]=nil
                    ctx.questHealAttempt=attempt
                    s.questStatus='Quest healing: using '..api.id(tool)..'; awaiting actual HP recovery'
                else s.questStatus='Quest healing: '..tostring(reason or 'native Consume dispatch unavailable')end
            else s.questStatus='Quest healing: waiting for native medical handler / Watcher attention'end
            if ctx.questHealAttempt or now()-wait.started<8 then return true end
            wait.retryAt=now()+5
            s.questStatus='Medical handler readiness unconfirmed after 8s; seeking other real supplies without repeating Consume'
        end
        if detached then
            ctx.questRecoveryStage='unresolved-item'
            if Q.chestTurn(ctx,plan)then return true end
            s.questStatus='Quest healing: unresolved item request reserved; native regeneration while held medical stock is unavailable'
            return true
        end
        local supplies=H.supplyIds(ctx);local problem=#supplies==0 and 'no medical stock loaded' or nil
        for _,id in ipairs(supplies)do
            local ready,reason=Q.supplyReady(ctx,id)
            if ready and Q.supply(ctx,plan,id)then
                ctx.questRecoveryStage='supply-checkout'
                s.questStatus='Quest healing: collecting medical supplies at the current coin quote';return true
            end
            problem=reason or s.questUpgradeJob and 'waiting for the upgrade receipt'
                or Q.calls.upgrade and 'upgrade purchase request still pending'
                or Q.calls.upgradeWallet and 'currency read still pending' or problem
        end
        local searching,searchReason=H.search(ctx)
        if searching then ctx.questRecoveryStage='shop-search';return true end
        problem=searchReason or problem
        if Q.collectMoney(ctx)then
            ctx.questRecoveryStage='cash-search'
            s.questStatus='Quest healing: collecting available Coins for medical supplies';return true
        end
        if Q.drillSupport.sellLoose(ctx,plan)then
            ctx.questRecoveryStage='funding-sale'
            if s.questDelivery then s.questDelivery.healingFunding=true end
            s.questStatus='Quest healing: selling disposable loot for medical supplies';return true
        end
        if Q.chestTurn(ctx,plan)then ctx.questRecoveryStage='safe-chest';return true end
        ctx.questRecoveryStage='no-ready-supply'
        s.questStatus=string.format('Quest healing %.0f%% → 70%%; %s; seeking safer chests and sales of $100+',ratio*100,problem or 'medical supply retry pending')
        return true
    end
    return H
end

end)()
    local buildQuestDrill = (function()
-- Native coin/reward offers and loaded mineshaft resources. No Larry medals,
-- paid products, map generation, fabricated mining damage or refinery calls.
return function(api,Q)
    local D,s,cfg,now={},api.state,api.state.config,api.now
    local buildQuestProcessing = (function()
-- Physical ore processing uses the confirmed FurnacePost intake or an active placed Furnace.
return function(api,Q,D)
    local M,s,now={},api.state,api.now
    local recipes={Ore_Iron='IronBar',Ore_Gold='GoldBar'}
    local failed=s.questProcessFailed or setmetatable({}, {__mode='k'});s.questProcessFailed=failed
    local function finite(v)return type(v)=='number' and v==v and math.abs(v)<math.huge end
    local function live(item)return item and item.Parent and item:IsDescendantOf(workspace)end
    local function status(text)s.questStatus=text end
    local function protected(item,ctx)
        if Q.protectedRelic(item) or (tonumber(api.attr(item,'Fuel')) or 0)>0
            or api.attr(item,'Class')=='Medkit' or api.attr(item,'Class')=='ReviveKit'
            or api.useful(ctx,item)then return true end
        local id=api.id(item)
        local function contains(value)
            if type(value)=='string'then return value==id end
            if type(value)=='table'then for _,entry in pairs(value)do if contains(entry)then return true end end end
            return false
        end
        for _,entry in pairs(s.questCatalog or {})do
            if contains(entry.StarterTools) or contains(entry.StarterArmor)then return true end
        end
        return id=='Sword_Void' or id=='Pickaxe_Void' or id=='Void_Helmet' or id=='Void_Chest' or id=='Void_Legs'
    end
    function M.inputEligible(item,ctx)
        if not recipes[api.id(item)] or failed[item] or not Q.free(item,'sale') or protected(item,ctx)
            or item:FindFirstChild('Health') or api.tag(item,'CraftedPlaceable')then return false end
        local plan=Q.plan(s.classData,s.questCatalog,s.config.driveDepth)
        return plan.kind~='shred' and not ctx.questNeedScrap and D.accessible(item)
    end
    function M.carriedOre(item,ctx)
        local player=api.Players.LocalPlayer
        return item and item:IsA('Tool') and recipes[api.id(item)]~=nil and not failed[item]
            and player.Character==ctx.character and (item.Parent==ctx.character or item.Parent==player:FindFirstChild('Backpack'))
            and not protected(item,ctx) and not item:FindFirstChild('Health') and not api.tag(item,'CraftedPlaceable')
            and Q.plan(s.classData,s.questCatalog,s.config.driveDepth).kind~='shred' and not ctx.questNeedScrap
    end
    function M.hasOre(ctx)
        for _,item in ipairs(Q.looseItems())do if M.inputEligible(item,ctx)then return true end end
        for _,item in ipairs(api.ownedTools(ctx))do if M.carriedOre(item,ctx)then return true end end
        return false
    end
    function M.machine(item,ctx)
        local catalog=api.sharedModule('CraftingCatalog');local entry=catalog and catalog.Furnace
        return entry and entry.UseType=='Placeable' and live(item) and api.id(item)=='Furnace'
            and ctx.drill==workspace:FindFirstChild('Drill')
            and item:GetAttribute('CraftedPlaceable')==true and item:GetAttribute('Placed')==true
            and item:GetAttribute('Deactivated')~=true and item:IsDescendantOf(ctx.drill)
            and not api.tag(item,'ShopItem') and api.part(item)~=nil and D.accessible(item)
    end
    function M.findMachine(ctx)
        local folder=ctx.drill:FindFirstChild('CraftedPlaceables')
        for _,item in ipairs(folder and folder:GetChildren() or {})do if M.machine(item,ctx)then return item end end
        for _,item in ipairs(ctx.drill:GetDescendants())do if M.machine(item,ctx)then return item end end
    end
    function M.shopRoot(box,ctx)
        if not live(box) or not box:IsA('BasePart') or box.Name~='OreConvertBox' or box.CanTouch==false
            or ctx.drill~=workspace:FindFirstChild('Drill') or not D.accessible(box)then return end
        local convert=box.Parent;local furnace=convert and convert.Parent
        local structure=furnace and furnace.Parent;local root=structure and structure.Parent
        local touch=box:FindFirstChild('TouchInterest')
        if convert and convert.Name=='OreConvert' and furnace and furnace.Name=='Furnace'
            and structure and structure.Name=='Structure' and root and root.Name=='FurnacePost' and root.Parent==workspace
            and root:FindFirstChild('Structure')==structure and structure:FindFirstChild('Furnace')==furnace
            and furnace:FindFirstChild('OreConvert')==convert and convert:FindFirstChild('OreConvertBox')==box
            and touch and touch:IsA('TouchTransmitter')then
            for _,node in ipairs({box,convert,furnace,structure,root})do if node:GetAttribute('Deactivated')==true then return end end
            return root,touch
        end
    end
    function M.processor(item,ctx)return M.shopRoot(item,ctx)~=nil or M.machine(item,ctx)end
    function M.findProcessor(ctx,origin)
        local best,distance
        for _,root in ipairs(workspace:GetChildren())do
            if root.Name=='FurnacePost'then
                local structure=root:FindFirstChild('Structure');local furnace=structure and structure:FindFirstChild('Furnace')
                local convert=furnace and furnace:FindFirstChild('OreConvert');local box=convert and convert:FindFirstChild('OreConvertBox')
                if box and M.shopRoot(box,ctx)then
                    local value=(box.Position-(origin or ctx.root.Position)).Magnitude
                    if not distance or value<distance then best,distance=box,value end
                end
            end
        end
        return best or M.findMachine(ctx)
    end
    local function bounds(item)
        if item:IsA('Model') and type(item.GetBoundingBox)=='function'then
            local ok,cf,size=pcall(item.GetBoundingBox,item);if ok and cf and size then return cf,size end
        end
        local part=api.part(item);return part and part.CFrame,part and part.Size
    end
    local function session(root)return root and root:GetAttribute('SessionDungeonId')end
    local function sameScope(observed,ctx)
        return observed.drill==ctx.drill and observed.drill==workspace:FindFirstChild('Drill')
            and observed.mine==D.activeMine(ctx) and observed.mineSession==session(observed.mine)
            and observed.campaign==Q.special.bound(ctx) and observed.campaignSession==session(observed.campaign)
    end
    local function sameProcessor(observed,ctx)
        if not observed.shopRoot then return true end
        local root,touch=M.shopRoot(observed.machine,ctx)
        return root==observed.shopRoot and touch==observed.shopTouch
            and observed.machine.Parent==observed.shopConvert and observed.shopConvert.Parent==observed.shopFurnace
            and observed.shopFurnace.Parent==observed.shopStructure and observed.shopStructure.Parent==root
    end
    function M.capture(ctx,item,machine)
        local cf,size=bounds(machine);if not cf or not size then return end
        local before={};for _,bar in ipairs(Q.looseItems())do before[bar]=true end
        local key=api.id(item)=='Ore_Iron' and 'SmeltIron' or 'SmeltGold'
        local plan=Q.plan(s.classData,s.questCatalog,s.config.driveDepth)
        local mine,campaign=D.activeMine(ctx),Q.special.bound(ctx)
        local shopRoot,shopTouch=M.shopRoot(machine,ctx)
        return {input=api.id(item),output=recipes[api.id(item)],machine=machine,before=before,
            position=cf.Position,radius=math.max(12,size.Magnitude),band=workspace:GetAttribute('InfiniteDepthOffsetMeters'),
            drill=ctx.drill,mine=mine,mineSession=session(mine),campaign=campaign,campaignSession=session(campaign),
            shopRoot=shopRoot,shopTouch=shopTouch,shopConvert=shopRoot and machine.Parent,
            shopFurnace=shopRoot and machine.Parent.Parent,shopStructure=shopRoot and machine.Parent.Parent.Parent,
            class=plan.name,key=key,count=tonumber(plan.counts and plan.counts[key]) or 0}
    end
    function M.goal(job)
        if not job.processing or not sameScope(job.processing,job.ctx) or not sameProcessor(job.processing,job.ctx)
            or not M.inputEligible(job.item,job.ctx) or not M.processor(job.target,job.ctx)then return end
        local center=bounds(job.target);local itemCenter=bounds(job.item)
        if center and itemCenter then return center*itemCenter:ToObjectSpace(job.item:GetPivot())end
    end
    function M.receipt(job)
        local observed=job.processing
        if not observed or not job.processingContact or observed.machine~=job.target
            or observed.band~=workspace:GetAttribute('InfiniteDepthOffsetMeters')
            or not sameScope(observed,job.ctx) or not sameProcessor(observed,job.ctx)then return false end
        if job.item.Parent and api.id(job.item)==observed.input then return false end
        local plan=Q.plan(s.classData,s.questCatalog,s.config.driveDepth)
        if plan.name==observed.class and (tonumber(plan.counts and plan.counts[observed.key]) or 0)>observed.count then return true end
        local center=M.processor(job.target,job.ctx) and bounds(job.target)
        local position=center and center.Position or observed.position
        for _,bar in ipairs(Q.looseItems())do
            if (not observed.before[bar] or bar==job.item) and api.id(bar)==observed.output and Q.free(bar,'sale')then
                local room=observed.campaign or observed.mine
                local ownSession=bar:GetAttribute('SessionDungeonId')
                local expected=observed.campaignSession or observed.mineSession
                local belongs=ownSession==nil or expected~=nil and ownSession==expected
                if room and room~=observed.mine then
                    belongs=belongs and (bar:IsDescendantOf(room) or ownSession~=nil and ownSession==expected)
                else belongs=belongs and D.accessible(bar)end
                local part=api.part(bar)
                if belongs and part and (part.Position-position).Magnitude<=observed.radius then return true end
            end
        end
        return false
    end
    function M.contactComplete(job)
        local observed=job.processing
        if not observed or not job.processingContact or job.item.Parent and api.id(job.item)==observed.input then return false end
        if M.receipt(job)then job.processingConfirmed=true end
        return true -- Consumed/reidentified input is never moved or constrained again.
    end
    function M.timeout(job)
        if job.processingTimedOut then return end
        job.processingTimedOut=true
        failed[job.item]=true
        if Q.free(job.item,'sale')then s.questItemRetries[job.item]=nil end
        status(job.processingConfirmed and 'Furnace output observed; native drag release remains reserved'
            or 'Furnace output unconfirmed; this ore is not processed again, other work continues')
    end
    function M.fundingEligible(item,ctx)
        local value=tonumber(api.attr(item,'Value'));local id=api.id(item)
        return Q.free(item) and api.attr(item,'Category')=='Scrap' and finite(value) and value>0 and value<100
            and not recipes[id] and id~='IronBar' and id~='GoldBar' and not protected(item,ctx)
            and not item:FindFirstChild('Health') and D.accessible(item)
    end
    local function blueprint(ctx)
        for _,tool in ipairs(api.ownedTools(ctx))do if tool:IsA('Tool') and api.id(tool)=='Furnace'then return tool end end
    end
    local function unlockReady(controller)
        return controller and controller.HasCraftingState==true and finite(tonumber(controller.UnlockedLevel))
            and tonumber(controller.UnlockedLevel)>=2
    end
    local function craftPrice()
        local catalog=api.sharedModule('CraftingCatalog');local price=api.sharedModule('CraftingPrice')
        local entry=catalog and catalog.Furnace
        if not entry or entry.UseType~='Placeable' or entry.Craftable==false or not price or type(price.GetPrice)~='function'then return end
        local ok,value=pcall(price.GetPrice,entry.Price,api.Players.LocalPlayer,workspace,entry)
        return ok and finite(value) and value>=0 and value or nil
    end
    local function releaseCraft(job)
        if job.controller._EarthFurnaceCraft==job then job.controller._EarthFurnaceCraft=nil;job.controller.PendingCraft=false end
    end
    function M.observeCraft(ctx)
        local job=s.questFurnaceCraft;if not job then return false end
        -- A rebuilt optional worker retains this same native transaction. Its
        -- new ctx may observe the actual blueprint/count receipt, but a new
        -- life, drill or native controller cannot retire the old reservation.
        local sameLife=job.ctx.character==ctx.character and job.ctx.humanoid==ctx.humanoid
            and ctx.character==api.Players.LocalPlayer.Character and job.drill==ctx.drill
            and ctx.drill==workspace:FindFirstChild('Drill')
            and api.controller('CraftingController')==job.controller
        if not sameLife then
            if s.questCalls.craft~=job.token then releaseCraft(job);s.questFurnaceCraft=nil end
            return false
        end
        local tool=blueprint(ctx)
        local controller=api.controller('CraftingController')
        local count=tonumber(controller and controller.HasCraftingState and controller.CraftedCounts and controller.CraftedCounts.Furnace)
            or tonumber(s.questCraftState and s.questCraftState.CraftedCounts and s.questCraftState.CraftedCounts.Furnace) or 0
        if tool and not job.beforeTools[tool] and (job.accepted or count>job.before)then
            if Q.retireConfirmedCall('craft',job.token)then releaseCraft(job);s.questFurnaceCraft=nil;return true end
        elseif job.rejected then releaseCraft(job);s.questFurnaceCraft=nil;ctx.questFurnaceRetry=now()+15 end
        return false
    end
    local function stopPreview(job)
        local c=job.controller
        if not c then return false end
        if c.Active and c.Item==job.item and live(job.item) and api.id(job.item)=='Furnace'
            and job.item:GetAttribute('PlacingUserId')==api.Players.LocalPlayer.UserId
            and type(c.StopLocalPlacement)=='function'then pcall(c.StopLocalPlacement,c)end
        job.localPreviewStopped=c.Active~=true and c.Item~=job.item
            and api.Players.LocalPlayer:GetAttribute('PlacingCraftedPlaceable')~=true or nil
        return job.localPreviewStopped==true
    end
    function M.observePlacement(ctx)
        local job=s.questFurnacePlacement;if not job then return false end
        if job.background and not job.localPreviewStopped and now()>=(job.stopRetryAt or 0)then
            job.stopRetryAt=now()+1;stopPreview(job)
        end
        if job.drill==ctx.drill and M.machine(job.item,ctx)then
            if Q.retireConfirmedCall('place',job.token)then
                stopPreview(job)
                if job.ctx.questPlacement==job then job.ctx.questPlacement=nil;job.ctx.questOwns=nil end
                if ctx.questPlacement==job then ctx.questPlacement=nil;ctx.questOwns=nil end
                s.questFurnacePlacement=nil;return true
            end
        elseif job.detached and s.questCalls.place~=job.token then s.questFurnacePlacement=nil end
        return false
    end
    function M.cleanup(ctx)
        local job=ctx.questPlacement
        if not job or not job.processingPlacement then return end
        if job.sent and not job.rejected then
            job.background,job.detached=true,true
            stopPreview(job);s.questFurnacePlacement=job
            ctx.questPlacement=nil;ctx.questOwns=nil
        else Q.special.cancelPreview(ctx)end
    end
    function M.craft(ctx,plan)
        local job=s.questFurnaceCraft
        if job then
            M.observeCraft(ctx);if s.questFurnaceCraft~=job or job.ctx~=ctx then return false end
            Q.special.readCraft(ctx)
            if now()-job.started>=12 then ctx.questOwns=nil;status('Furnace craft receipt is pending; its request stays reserved');return false end
            return true
        end
        local c=api.controller('CraftingController');local price=craftPrice()
        if not unlockReady(c) or not price or s.questCalls.craft or s.questCraftJob or c.PendingCraft
            or now()<(ctx.questFurnaceRetry or 0)then return false end
        local portable=type(c.CanCraftAnywhere)=='function' and c:CanCraftAnywhere()
        if not live(c.CraftSource) and not portable then
            local source,distance
            for _,part in ipairs(api.tagged('MagnitudeFrame'))do
                if live(part) and part.Name=='Crafting' and api.part(part) and D.accessible(part)then
                    local value=(api.part(part).Position-ctx.root.Position).Magnitude
                    if not distance or value<distance then source,distance=part,value end
                end
            end
            if source and type(c.SetCraftSource)=='function' and Q.holdRoute(ctx)then
                Q.stopDrive(ctx);D.stopMine(ctx)
                if ctx.humanoid.SeatPart or ctx.humanoid.Sit then local _,holding=Q.unseat(ctx);return holding end
                api.hover(ctx)
                ctx.root.CFrame=CFrame.new(api.part(source).Position+Vector3.new(0,2,0))
                pcall(c.SetCraftSource,c,source);return true
            end
            return false
        end
        local source=live(c.CraftSource) and api.part(c.CraftSource)
        if source and (source.Position-ctx.root.Position).Magnitude>10 then
            if not Q.holdRoute(ctx)then return true end
            Q.stopDrive(ctx);D.stopMine(ctx)
            if ctx.humanoid.SeatPart or ctx.humanoid.Sit then local _,holding=Q.unseat(ctx);return holding end
            api.hover(ctx)
            ctx.root.CFrame=CFrame.new(source.Position+Vector3.new(0,2,0));return true
        end
        if (tonumber(c.ScrapCount) or 0)<price then
            local pad=Q.special.scrapPad(ctx);local best,value
            for _,item in ipairs(Q.looseItems())do
                if M.fundingEligible(item,ctx) and now()>=(s.questItemRetries[item] or 0)then
                    local amount=tonumber(api.attr(item,'Value'))
                    if not value or amount>value then best,value=item,amount end
                end
            end
            if pad and best and Q.startDelivery(ctx,best,pad,'shred',{name=plan.name,counts=plan.counts,objective='ShredScrap',processingFunding=true})then
                status('Shredding disposable loot below 100 for the native unlocked Furnace quote');return true
            end
            return false
        end
        if type(c.CanCraft)~='function'then return false end
        local ok,allowed=pcall(c.CanCraft,c,'Furnace');if not ok or not allowed then return false end
        job={ctx=ctx,drill=ctx.drill,controller=c,started=now(),source=c.CraftSource,before=tonumber(c.CraftedCounts and c.CraftedCounts.Furnace) or 0,beforeTools={}}
        for _,tool in ipairs(api.ownedTools(ctx))do job.beforeTools[tool]=true end
        s.questFurnaceCraft=job
        if Q.call('craft','CraftingService','Craft',{'Furnace',job.source},function(ok,value,_,dispatch)
            releaseCraft(job);job.rejected=dispatch=='not-sent' or ok and value==false
            if ok and type(value)=='table'then
                job.accepted=true;s.questCraftState=value
                if type(c.ApplyState)=='function'then pcall(c.ApplyState,c,value)end
            end
        end,function()
            local allowed=Q.enabled(ctx) and not Q.manual() and not api.extractionReady() and not c.PendingCraft
                and api.controller('CraftingController')==c and unlockReady(c) and c.CraftSource==job.source and c:CanCraft('Furnace')
                and craftPrice()==price and (tonumber(c.ScrapCount) or 0)>=price and not ctx.questHealing
                and not s.questDelivery and not s.bringDelivery and not s.lootRequest and not s.equipmentRequest
                and (not Q.refuelActive or not Q.refuelActive(ctx))
            if allowed then c._EarthFurnaceCraft=job;c.PendingCraft=true end
            return allowed
        end)then job.token=s.questCalls.craft else s.questFurnaceCraft=nil end
        status('Crafting Furnace at its native scrap quote; awaiting the actual blueprint');return true
    end
    function M.placement(ctx,plan)
        if M.observePlacement(ctx)then return true end
        local job=ctx.questPlacement;local c=api.controller('PlaceablePlacementController')
        if job and not job.processingPlacement then return false end
        if s.questFurnaceCraft then
            local pending=M.craft(ctx,plan)
            if pending or s.questFurnaceCraft then return pending end
        end
        if job then
            if job.sent or now()-job.started>=12 then
                if job.rejected then Q.special.cancelPreview(ctx);ctx.questFurnaceRetry=now()+30
                elseif now()-job.started>=12 then
                    job.background=true;ctx.questOwns=nil
                    if job.sent then stopPreview(job)
                    else Q.special.cancelPreview(ctx);ctx.questFurnaceRetry=now()+30 end
                    status('Furnace placement unconfirmed; exact request retained while other work continues')
                end
                return now()-job.started<12
            end
            if not c or not c.Active or not live(c.Item) or api.id(c.Item)~='Furnace'
                or c.Item:GetAttribute('CraftedPlaceable')~=true or c.Item:GetAttribute('PlacingUserId')~=api.Players.LocalPlayer.UserId then return true end
            job.item=c.Item
            if c.PendingRequest or c.PendingCancel or Q.manual()then return false end
            if not Q.holdRoute(ctx)then return true end
            if ctx.humanoid.SeatPart or ctx.humanoid.Sit then Q.stopDrive(ctx);local _,holding=Q.unseat(ctx);return holding end
            if type(c.UpdatePreview)~='function'then return false end
            if not c.ValidRegion or not c.PlacementOffset then
                if (job.pose or 0)>=9 then Q.special.cancelPreview(ctx);ctx.questFurnaceRetry=now()+30;return false end
                Q.special.positionPreview(ctx,c,job);pcall(c.UpdatePreview,c)
            end
            local region,offset,item=c.ValidRegion,c.PlacementOffset,c.Item
            if not live(region) or not region:IsDescendantOf(ctx.drill) or not offset then return true end
            job.sent=true
            if Q.call('place','PlaceableService','Place',{region,offset},function(ok,value,_,dispatch)
                job.rejected=dispatch=='not-sent' or ok and value==false
                if job.pendingOwned and c.Item==item and (ok or dispatch=='not-sent')then
                    c.PendingRequest=false;job.pendingOwned=nil
                end
                if ok and value and c.Item==item and type(c.StopLocalPlacement)=='function'then pcall(c.StopLocalPlacement,c)end
            end,function()
                local allowed=Q.enabled(ctx) and ctx.questPlacement==job and not ctx.questPreviewCancel
                    and api.controller('PlaceablePlacementController')==c and not Q.manual() and not api.extractionReady() and c.Active and c.Item==item
                    and c.ValidRegion==region and c.PlacementOffset==offset and not c.PendingRequest
                    and live(region) and region:IsDescendantOf(ctx.drill) and live(item)
                    and item:GetAttribute('CraftedPlaceable')==true
                    and item:GetAttribute('PlacingUserId')==api.Players.LocalPlayer.UserId
                if allowed then c.PendingRequest=true;job.pendingOwned=true end
                return allowed
            end)then job.token=s.questCalls.place else job.sent=nil end
            return true
        end
        local tool=blueprint(ctx)
        if not tool then return M.craft(ctx,plan)end
        if not unlockReady(api.controller('CraftingController')) or not c or c.Active or c.PendingRequest or c.PendingCancel
            or s.questCalls.place or s.questCalls.craft or s.questCalls.placementCancel or now()<(ctx.questFurnaceRetry or 0)then return false end
        if not Q.holdRoute(ctx)then return true end
        Q.stopDrive(ctx);D.stopMine(ctx)
        if ctx.humanoid.SeatPart or ctx.humanoid.Sit then local _,holding=Q.unseat(ctx);return holding end
        local active=api.equip(ctx,tool)
        if not active or type(active.BeginPlacement)~='function'then ctx.questOwns=nil;return false end
        ctx.questPlacement={ctx=ctx,controller=c,drill=ctx.drill,tool=tool,recipe='Furnace',processingPlacement=true,started=now()}
        s.questFurnacePlacement=ctx.questPlacement
        pcall(active.BeginPlacement,active);return true
    end
    function M.step(ctx,plan)
        if not Q.enabled(ctx) or not Q.activePlan(plan) or ctx.questHealing or Q.manual() or api.extractionReady()
            or s.questDelivery or s.bringDelivery or s.lootRequest or s.equipmentRequest or s.questCalls.drag then return false end
        if ctx.questPlacement and ctx.questPlacement.processingPlacement then return M.placement(ctx,plan)end
        local item
        for _,candidate in ipairs(Q.looseItems())do
            if M.inputEligible(candidate,ctx) and now()>=(s.questItemRetries[candidate] or 0)then item=candidate;break end
        end
        if not item then return false end
        local machine=M.findProcessor(ctx,api.part(item).Position)
        if not machine then
            Q.special.readCraft(ctx)
            if M.placement(ctx,plan)then return true end
            if plan.kind~='depth' or s.config.driveDepth~=true then return false end
            if not api.hasRoom(ctx,item) or not M.inputEligible(item,ctx)then return false end
            local name,before=api.id(item),0
            for _,tool in ipairs(api.ownedTools(ctx))do if api.id(tool)==name then before=before+1 end end
            local carry={name=plan.name,counts=plan.counts,objective=plan.objective,processingCarry=true}
            if Q.startDelivery(ctx,item,ctx.root,'supply',carry)then
                local job=s.questDelivery
                if job then job.id,job.inventoryBefore=name,before end
                status('Collecting ore for a later Furnace; retaining it while advancing the map')
                return true
            end
            return false
        end
        if Q.startDelivery(ctx,item,machine,'smelt',plan)then
            status('Delivering ore to the confirmed native Furnace intake; awaiting a real bar output');return true
        end
        return false
    end
    return M
end

end)()
    local calls=s.questCalls
    local weights={DrillPower=120,RPMOverclock=140,UltraDrill=130,MegaDrill=110,PowerSlam=100,
        DriveSpeed=140,PowerDrive=100,EngineOverdrive=90,FuelStorage=45,MoneyDrill=60,
        TeamMeleeDamage=100,TeamPickaxeDamage=100,TeamGunDamage=100,TeamExplosiveDamage=100,TeamHealth=70,SackStorage=6,PowerBurst=120}
    local blocked={CartExtension=true,MountedGunner=true,SackStorage=true,LifeSteal=true,HealthRegen=true,MoneyDrill=true}
    local lastResort={} -- Ordinary ranking keeps the blacklist; complete blocked rolls use the scoped exception below.
    local damage={TeamMeleeDamage=true,TeamPickaxeDamage=true,TeamGunDamage=true,TeamExplosiveDamage=true}
    local ores={Ore_Iron=true,Ore_Gold=true,Ore_Diamond=true,Ore_Emerald=true,Ore_Ruby=true,Ore_Coal=true,Ore_VoidCoal=true,IronBar=true,GoldBar=true}
    local rarity={Common=1,Rare=2,Epic=3,Legendary=4,Mythic=5}
    local ledger=s.questUpgradeLedger or {};s.questUpgradeLedger=ledger
    local function finite(v)return type(v)=='number' and v==v and math.abs(v)<math.huge end
    local function status(text)s.questStatus=text end
    -- A depth run funds its initial budget before taking the driver seat.
    -- Later rounds allow up to one minute of loot, sales and upgrade work.
    -- A gem value is not a finish signal; confirmed empty loaded work may yield early.
    D.depthFundingCoins,D.depthDriveSeconds,D.depthLootSeconds=10000,150,60
    D.depthFundingIdleSeconds=60
    function D.depthEconomy(ctx,plan)
        if plan.kind~='depth' or not cfg.driveDepth or not Q.enabled(ctx) then return end
        local cycle=ctx.questDepthEconomy
        local function sameLife(record)
            return record and record.character==ctx.character and record.humanoid==ctx.humanoid and record.drill==ctx.drill
                and record.job==game.JobId and record.runStarted==s.lootStarted
        end
        -- A supervisor rebuild replaces ctx while the same living character,
        -- humanoid, drill and run remain. Its initial budget must not restart.
        local localCycle=cycle and cycle.character==ctx.character and cycle.drill==ctx.drill
            and (cycle.humanoid==nil or sameLife(cycle))
        if not localCycle then
            local retained=s.questDepthEconomy
            cycle=sameLife(retained) and retained or {character=ctx.character,drill=ctx.drill,phase='funding',started=now()}
            cycle.emptyAt=nil -- A new worker must independently confirm an empty break.
        end
        cycle.humanoid,cycle.job,cycle.runStarted=ctx.humanoid,game.JobId,s.lootStarted
        ctx.questDepthEconomy,s.questDepthEconomy=cycle,cycle
        local wallet=Q.coinBalance(s.questWallet,s.questWalletAt,s.questWalletVersion)
        if cycle.phase=='funding' then
            -- Aim for 10k while real funding progresses. An exhausted loaded
            -- route must not wait below the target until the 90s save exit.
            -- The existing activity watch counts native income, chest removal,
            -- observed loot and objective changes; requests cannot reset it.
            local activity=s.questActivity
            local dry=activity and now()-math.max(cycle.started,activity.at)>=D.depthFundingIdleSeconds
            local idleReady=dry and not Q.manual() and not api.extractionReady() and not D.inDungeon(ctx)
                and not ctx.currentChest and not ctx.questChestLease and not ctx.questChestTaking and not ctx.questHealing
                and not s.equipmentRequest
                and not s.questDelivery and not s.questCashJob and not s.questUpgradeJob
                and not calls.cash and not calls.drag and not calls.shop and not calls.wallet and not calls.upgrade
            if wallet and (wallet>=D.depthFundingCoins or idleReady)then
                cycle.fundingLimited=wallet<D.depthFundingCoins or nil
                cycle.phase,cycle.driveAt='drive',nil
            end
        elseif cycle.phase=='drive' then
            if cycle.fundingExplore and now()>=(cycle.exploreProbeAt or 0)then
                cycle.exploreProbeAt=now()+3
                if wallet and wallet>=D.depthFundingCoins then
                    cycle.fundingExplore=nil
                elseif D.processing and D.processing.hasOre(ctx) and D.processing.findProcessor(ctx,ctx.root.Position)then
                    cycle.phase,cycle.fundingExplore,cycle.emptyAt='funding',nil,nil
                end
            end
            if ctx.questDriving then cycle.driveAt=cycle.driveAt or now() end
            if cycle.phase=='drive' and cycle.driveAt and now()-cycle.driveAt>=D.depthDriveSeconds then
                cycle.phase,cycle.lootAt,cycle.driveAt=cycle.fundingExplore and 'funding' or 'loot',now(),nil
                cycle.fundingExplore,cycle.emptyAt=nil,nil
            end
        elseif cycle.phase=='upgrades' or cycle.phase=='loot' and now()-cycle.lootAt>=D.depthLootSeconds then
            -- Upgrades have their own passive pulse. Neither unavailable cards
            -- nor an unknown purchase owns the movement/loot schedule.
            cycle.phase,cycle.driveAt='drive',nil
        end
        return cycle
    end
    function D.depthFundingStatus(ctx,plan)
        local cycle=D.depthEconomy(ctx,plan)
        if not cycle then return end
        if cycle.phase=='funding' then
            return string.format('Head start: chests, mines, ore processing and sales, %.0f / 10000 Coins',s.questWallet or 0)
        elseif cycle.phase=='loot' then
            return string.format('Chest loot, sales and upgrade checks: up to %.0fs remaining',math.max(0,D.depthLootSeconds-(now()-cycle.lootAt)))
        end
    end
    function D.finishEmptyLoot(ctx,plan,empty)
        local cycle=ctx.questDepthEconomy
        if not cycle or cycle.phase~='loot' and cycle.phase~='funding' then return false end
        local funding=cycle.phase=='funding'
        local pending=false
        for key in pairs(calls)do
            if key~='upgrade' and key~='upgradeWallet'then pending=true;break end
        end
        local clear=empty==true and Q.enabled(ctx) and not Q.manual() and not api.extractionReady() and not D.inDungeon(ctx)
            and not ctx.currentChest and not ctx.questChestLease and not ctx.questChestTaking and not ctx.questHealing
            and not ctx.featureHold and not ctx.smartLootWindow and not ctx.questMineJob and not ctx.questMineEntry
            and not ctx.humanoid.SeatPart and not ctx.humanoid.Sit
            and not s.questDelivery and not s.questCashJob and not s.questInventoryDrop
            and not s.bringDelivery and not s.lootRequest and not s.equipmentRequest and not s.rareShardDrop
            and not pending and Q.coinBalance(s.questWallet,s.questWalletAt,s.questWalletVersion)~=nil
        if not clear then cycle.emptyAt=nil;return false end
        local activity=s.questActivity
        local started=funding and cycle.started or cycle.lootAt
        local last=math.max(started,activity and activity.at or started)
        if not cycle.emptyAt or last>cycle.emptyAt then cycle.emptyAt=now();return false end
        -- A complete loaded candidate pass and eight quiet seconds allow late
        -- drops/receipts to arrive. No request or phase change invents progress.
        if now()-cycle.emptyAt<8 then return false end
        if funding then
            cycle.phase,cycle.fundingExplore,cycle.driveAt,cycle.emptyAt='drive',true,nil,nil
            cycle.exploreProbeAt=now()+3
            s.questUpgradeStatus='Head start: advancing for more loaded mines, loot and a native Furnace'
        else
            cycle.phase,cycle.driveAt,cycle.emptyEnded='drive',nil,true
        end
        return true
    end
    function D.paidUpgradeWindow(ctx,cycle)
        return not Q.manual() and (not cycle or cycle.phase~='funding' and not cycle.fundingExplore)
    end
    function D.upgradePulse(ctx)
        if not Q.enabled(ctx) or ctx.character~=api.Players.LocalPlayer.Character
            or ctx.drill~=workspace:FindFirstChild('Drill') or api.extractionReady()
            then return end
        if s.questUpgradeJob and s.questUpgradeJob.ctx==ctx then D.settleUpgrade(ctx)end
        if now()<(ctx.questUpgradePulseAt or 0)then return end
        ctx.questUpgradePulseAt=now()+.5
        -- The supervisor also pulses this while optional movement/chest work
        -- yields. Native wallet/purchase calls already run asynchronously.
        Q.poll() -- Retire timed-out reads even while the optional worker yields.
        D.upgrades(ctx,Q.plan(s.classData,s.questCatalog,cfg.driveDepth))
    end
    function D.cost(offer)
        local cost=tonumber(offer and offer.Cost)
        if not finite(cost) or cost<0 then return nil end
        local passives=api.passives and api.passives()
        local factor=passives and passives.DrillUpgradeDiscounts and passives.DrillUpgradeDiscounts[offer.UpgradeName]
        if finite(factor)then cost=math.max(0,math.floor(cost*math.max(0,math.min(1,factor))))end
        return cost
    end
    function D.capAllowed(ctx,offer,c)
        local name=offer.UpgradeName
        if name=='FuelStorage'then
            local capacity=tonumber(ctx.drill:GetAttribute('MaxFuel'))
            local amount=tonumber(offer.UpgradeAmount) or 1
            return finite(capacity) and capacity>0 and capacity<250 and finite(amount) and amount>0
        end
        if not damage[name]then return true end
        local count=math.max(tonumber(ctx.drill:GetAttribute(name)) or 0,tonumber(c and c.Owned and c.Owned[name]) or 0)
        local info=c and c.DisplayInfo and c.DisplayInfo[name]
        local increment=tonumber(info and info.Increment) or 20 -- native damage cards: +20% per tier
        local amount=tonumber(offer.UpgradeAmount) or 1
        return finite(count) and finite(increment) and increment>0 and finite(amount) and amount>0
            and count*increment<500
    end
    function D.score(ctx,plan,offer)
        if type(offer)~='table' or not weights[offer.UpgradeName] or blocked[offer.UpgradeName] then return end
        local name=offer.UpgradeName;local weight=weights[name]
        if not D.capAllowed(ctx,offer,api.controller('DrillUpgradeController'))then return end
        local needed=plan.kind=='depth' and cfg.driveDepth and name~='TeamMeleeDamage' and name~='TeamPickaxeDamage'
            and name~='TeamHealth' and name~='SackStorage' and name~='TeamGunDamage' and name~='TeamExplosiveDamage'
        for _,goal in ipairs(plan.unmet or {})do
            local key=goal.key or ''
            if Q.capabilities.upgrades[key]==name then needed=true end
            if name=='TeamMeleeDamage' and (key=='CutlassKills' or Q.capabilities.melee[key]
                or key=='CompleteDungeon' or key=='CompleteGoblinRing')then needed=true end
            if name=='TeamPickaxeDamage' and key:find('Mine',1,true)==1 then needed=true end
            if name=='TeamGunDamage' and (key=='TurretKills' or key=='FlintlockKills' or key=='HeadShot' or key:find('Gun',1,true)
                or key=='RifleKills' or key=='ShotgunKills')then needed=true end
            if name=='TeamExplosiveDamage' and key:find('Explosive',1,true)then needed=true end
        end
        if name=='TeamGunDamage' or name=='TeamExplosiveDamage' then if not needed then return end end
        local general=name=='TeamMeleeDamage' or name=='TeamPickaxeDamage' or name=='TeamHealth' or name=='SackStorage'
        if not needed and not general then return end
        local hp=ctx.humanoid.MaxHealth>0 and ctx.humanoid.Health/ctx.humanoid.MaxHealth or 1
        if name=='TeamHealth' then weight=weight*(hp<.7 and 3 or hp<.9 and 1.75 or 1)end
        if name=='TeamPickaxeDamage' and ctx.questMining then weight=weight*2 end
        if name=='SackStorage' then
            local capacity=tonumber(s.sackCapacity);local fill=tonumber(s.sackSize)
            weight=weight*(capacity and fill and fill>=capacity*.75 and 3 or .5)
        end
        local level=tonumber(ctx.drill:GetAttribute(name)) or 0
        if plan.kind=='depth' and now()-(ctx.questProgressAt or now())>=10 then
            if name=='DrillPower' or name=='RPMOverclock' or name=='UltraDrill' or name=='MegaDrill' or name=='PowerSlam'then weight=weight*2 end
            if name=='DriveSpeed' or name=='PowerDrive'then weight=weight*.5 end
        end
        local amount=tonumber(offer.UpgradeAmount) or 1
        if not finite(amount) or amount<=0 then return end
        local cost=D.cost(offer) or 0
        local tier=needed and 2 or 1
        if plan.kind=='depth' and cfg.driveDepth then
            if name=='DrillPower' or name=='RPMOverclock' or name=='UltraDrill' or name=='MegaDrill'
                or name=='PowerSlam' or name=='PowerBurst' then tier=8
            elseif name=='DriveSpeed' or name=='PowerDrive' or name=='EngineOverdrive' or name=='FuelStorage' then tier=7
            elseif name=='TeamMeleeDamage' then tier=6
            elseif name=='TeamPickaxeDamage' then tier=5
            elseif name=='TeamHealth' then tier=4 end
        elseif name=='TeamMeleeDamage' or name=='TeamPickaxeDamage' then
            tier=needed and 4 or 3
        elseif name=='TeamHealth' then
            tier=1
        elseif needed then
            tier=4
        end
        return tier*1000000+weight*amount/(1+math.max(0,level)/8)/math.max(1,cost)^.35,needed
    end
    function D.worthSaving(ctx,plan,offer)
        if offer.Type~='Coins' or (rarity[offer.Rarity] or 0)<rarity.Legendary then return end
        local value,needed=D.score(ctx,plan,offer)
        if not value then return end
        local amount=tonumber(offer.UpgradeAmount) or 1
        local name=offer.UpgradeName
        local hp=ctx.humanoid.MaxHealth>0 and ctx.humanoid.Health/ctx.humanoid.MaxHealth or 1
        local strong=needed or (name=='TeamMeleeDamage' or name=='TeamPickaxeDamage') and amount>=3
            or name=='TeamHealth' and amount>=2 and hp<.7
        return strong and value or nil
    end
    function D.blacklistFallback(ctx,c)
        local reward=c.ActiveClassReward
        local options=reward and reward.Options or c.Options
        if type(options)~='table' or #options<3 or #options>(reward and 3 or 4)then return end
        local count,premium,entries,seen,best,price,bestIndex=0,0,0,{}
        for index,offer in pairs(options)do
            if not finite(index) or index%1~=0 or index<1 or index>#options or type(offer)~='table'then return end
            entries=entries+1
            if offer.Type==(reward and 'ClassReward' or 'Coins')then
                local name=offer.UpgradeName
                local amount=offer.UpgradeAmount==nil and 1 or tonumber(offer.UpgradeAmount)
                local cost=reward and 0 or D.cost(offer)
                if not blocked[name] or seen[name] or not finite(amount) or amount<=0 or amount%1~=0
                    or not finite(cost) or cost<0 or not D.capAllowed(ctx,offer,c)then return end
                count=count+1;seen[name]=true
                if price==nil or cost<price or cost==price and index<bestIndex then best,price,bestIndex=offer,cost,index end
            elseif not reward and offer.Type=='Robux'then premium=premium+1
            else return end
        end
        -- Native paid rolls have three Coin cards and a separate Robux card.
        -- Only the three Coin choices authorize this exception; no paid product.
        if entries==#options and count==3 and premium<=1 then return best,price end
    end
    function D.choose(ctx,plan,c,wallet,reservedKey)
        wallet=Q.coinSpendable(wallet)
        local reward=c.ActiveClassReward
        local options=reward and reward.Options or c.Options
        local version=reward and reward.Id or c.OptionsVersion
        if type(options)~='table' or not finite(version) or version<=0 then return end
        local key=tostring(game.JobId or '')..':'..(reward and 'reward:' or 'coins:')..version
        if ledger[key]==true and key~=reservedKey then return nil,nil,nil,nil,nil,'reserved' end
        if type(ledger[key])=='number' and now()<ledger[key]then return nil,nil,nil,nil,nil,'retry' end
        local blockedChoice,blockedCost=D.blacklistFallback(ctx,c)
        local best,score,fallback,fallbackCost,desperate,desperateCost,saving,savingScore
        for _,offer in ipairs(options)do
            local free=reward and offer.Type=='ClassReward'
            local cost=D.cost(offer)
            if not reward and offer.Type=='Coins' and finite(cost) and cost>=0 and finite(wallet) and cost>wallet then
                local value=D.worthSaving(ctx,plan,offer)
                if value and (not savingScore or value>savingScore)then saving,savingScore=offer,value end
            end
            -- Same class-discount multiplier and rounding as the native card UI.
            if free or not reward and offer.Type=='Coins' and finite(cost) and cost>=0 and finite(wallet) and wallet>=cost then
                local value=D.score(ctx,plan,offer)
                if value and (not score or value>score)then best,score=offer,value end
                local name=offer.UpgradeName
                local known=type(name)=='string' and (weights[name] or lastResort[name] or type(c.DisplayInfo)=='table' and c.DisplayInfo[name])
                if known and not blocked[name] and D.capAllowed(ctx,offer,c)then
                    if lastResort[name]then
                        if not desperateCost or (cost or 0)<desperateCost then desperate,desperateCost=offer,cost or 0 end
                    elseif not fallbackCost or (cost or 0)<fallbackCost then fallback,fallbackCost=offer,cost or 0 end
                end
            end
        end
        local choice=best or fallback or desperate
            or blockedChoice and (reward or wallet>=blockedCost) and blockedChoice
        -- Keep priority ranking, then spend on the cheapest safe normal card.
        -- An unaffordable preferred card cannot hold an affordable roll hostage.
        if choice or plan.kind=='depth' and cfg.driveDepth then saving=nil end
        return not saving and choice or nil,key,version,reward~=nil,saving,
            choice and blocked[choice.UpgradeName] and 'blacklist_fallback' or not choice and not saving and 'no_eligible' or nil
    end
    function D.fundingTarget(ctx,plan)
        local cycle=D.depthEconomy(ctx,plan)
        if cycle and cycle.phase=='funding' then return D.depthFundingCoins end
        local c=api.controller('DrillUpgradeController');local fallback,desperate
        local wallet=finite(s.questWallet) and s.questWallet or 0
        local chosen,key,_,_,saving
        if c then chosen,key,_,_,saving=D.choose(ctx,plan,c,wallet)end
        if saving or chosen then return math.max(Q.coinTarget(D.cost(saving or chosen) or 0,false),Q.supplyFundingTarget(ctx,plan))end
        if not key then return math.max(Q.medicalReserve,Q.supplyFundingTarget(ctx,plan))end
        local blockedChoice,blockedCost=D.blacklistFallback(ctx,c)
        if blockedChoice then return math.max(Q.coinTarget(blockedCost,false),Q.supplyFundingTarget(ctx,plan))end
        for _,offer in ipairs(c and c.Options or {})do
            local price=D.cost(offer)
            local name=offer.UpgradeName
            local known=type(name)=='string' and (weights[name] or lastResort[name] or type(c.DisplayInfo)=='table' and c.DisplayInfo[name])
            if offer.Type=='Coins' and finite(price) and price>=0 and known and not blocked[name]
                and D.capAllowed(ctx,offer,c)then
                if lastResort[name]then desperate=math.min(desperate or price,price)
                else fallback=math.min(fallback or price,price)end
            end
        end
        -- Preserve the user's medical balance above the actual upgrade quote.
        return math.max(Q.coinTarget(fallback or desperate or 0,false),Q.supplyFundingTarget(ctx,plan))
    end
    local function sameUpgradeUI(job)
        local c=job.controller
        if not c or api.controller('DrillUpgradeController')~=c then return false end
        local version=job.version or tonumber(tostring(job.key):match(':(%d+)$'))
        local reward=c.ActiveClassReward
        return (job.reward and reward and reward.Id==version or not job.reward and not reward and c.OptionsVersion==version)
            and c.RollToken==job.rollToken
    end
    local function releaseUpgradeUI(job)
        local c=job.controller
        if sameUpgradeUI(job) and type(c.SetPurchasePending)=='function'then pcall(c.SetPurchasePending,c,false)end
    end
    function D.settleUpgrade(ctx)
        local job=s.questUpgradeJob
        if not job then return false end
        local sameLife=job.ctx and job.ctx.character==ctx.character and job.ctx.humanoid==ctx.humanoid
            and job.ctx.drill==ctx.drill
        local count=sameLife and tonumber(ctx.drill:GetAttribute(job.name)) or job.before
        local confirmed=sameLife and (count>job.before or job.confirmed)
        if confirmed or job.rejected or not sameLife or now()-job.started>=8 then
            if confirmed then
                s.stats.confirmedQuestUpgrades=(s.stats.confirmedQuestUpgrades or 0)+1
                s.questUpgradeStatus='Upgrades: confirmed '..job.name
            elseif job.rejected then ledger[job.key]=now()+5;s.questUpgradeStatus='Upgrades: server rejected '..job.name..'; retry in 5s'
            else s.questUpgradeStatus='Upgrades: '..job.name..' unconfirmed; this card will not be repeated'end
            releaseUpgradeUI(job)
            s.questUpgradeJob=nil
        else s.questUpgradeStatus='Upgrades: awaiting server confirmation for '..job.name end
        return true
    end
    function D.upgrades(ctx,plan)
        if plan.kind=='waiting' or plan.kind=='advance' or plan.kind=='complete' or plan.kind=='unsupported'then return end
        local function info(text)s.questUpgradeStatus='Upgrades: '..text end
        local c=api.controller('DrillUpgradeController')
        -- Reading the wallet is independent of movement/delivery ownership.
        -- Purchase dispatch below still shares the native spending reservation.
        local function readWallet(callback)
            if calls.upgradeWallet or calls.wallet or calls.shop or now()<(ctx.questUpgradeWalletAt or 0)then return end
            ctx.questUpgradeWalletAt=now()+3
            local walletVersion=s.questWalletVersion or 0
            local medicalEpoch=ctx.questMedicalCheckoutEpoch or 0
            Q.call('upgradeWallet','CurrencyService','GetCurrency',{},function(ok,wallet)
                if ok and finite(wallet) and wallet>=0 then
                    local balance,observedAt,version=Q.observeCoins(wallet,walletVersion)
                    if balance~=nil and callback and medicalEpoch==(ctx.questMedicalCheckoutEpoch or 0)then callback(balance,observedAt,version)end
                else info('wallet read unavailable; purchases paused')end
            end,function()return Q.enabled(ctx) and not api.extractionReady()end)
        end
        if not c or type(c.Options)~='table' then info('waiting for native upgrade cards');readWallet();return end
        local function refreshCards()
            if type(c.FetchUpgradeOptions)=='function' and not c.OptionsFetchPending and not c.OptionsRetryPending
                and now()>=(ctx.questCardFetchAt or 0)then
                ctx.questCardFetchAt=now()+5;task.spawn(function()pcall(c.FetchUpgradeOptions,c)end)
            end
        end
        if D.settleUpgrade(ctx)then
            if not c.ActiveClassReward then readWallet()end
            return
        end
        if not c.ActiveClassReward and (#c.Options==0 or (tonumber(c.OptionsVersion) or 0)<=0)then
            info('waiting for native upgrade cards')
            refreshCards()
            readWallet();return
        end
        local function dispatch(wallet,walletAt,walletVersion)
            if not Q.enabled(ctx) or api.extractionReady()then return end
            if calls.upgrade then info('previous native upgrade result remains pending; purchases paused');return end
            if s.questDelivery and s.questDelivery.shop or calls.shop or calls.wallet then info('waiting for shop checkout / currency transaction');return end
            if c.PurchasePending or c.RerollPending or c.CardsLocked then info('native cards locked / purchase pending');return end
            if now()<(ctx.questUpgradeAt or 0)then return end
            local current=Q.plan(s.classData,s.questCatalog,cfg.driveDepth)
            local cycle=D.depthEconomy(ctx,current)
            if not c.ActiveClassReward and not D.paidUpgradeWindow(ctx,cycle)then
                info(D.depthFundingStatus(ctx,current) or 'Initial head-start funding or manual input; purchases paused')
                return
            end
            local offer,key,version,reward,saving,reason=D.choose(ctx,current,c,wallet)
            if not offer then
                if saving then info(string.format('Saving for %s %s: %.0f / %.0f Coins (1000 held for medkits)',saving.Rarity,saving.UpgradeName,wallet,Q.coinTarget(D.cost(saving),false)))
                elseif reason=='reserved' then
                    info('current roll already requested; waiting for native refreshed cards')
                    if not c.ActiveClassReward then refreshCards()end
                elseif reason=='retry' then info('server-rejected roll cooling down before its bounded retry')
                elseif c.ActiveClassReward then info('no eligible free card')
                else
                    local blockedChoice,blockedCost=D.blacklistFallback(ctx,c)
                    local target=D.fundingTarget(ctx,current)
                    if blockedChoice then
                        info(string.format('all three Coin cards blacklisted; cheapest %s needs %.0f Coins (1000 held for medkits)',blockedChoice.UpgradeName,Q.coinTarget(blockedCost,false)))
                    elseif target<=math.max(Q.medicalReserve,Q.supplyFundingTarget(ctx,current))then
                        info('no eligible card on this roll: capped or incomplete; Coins retained')
                    else info(string.format('%.0f Coins; funding target %.0f',wallet,target))end
                end
                return
            end
            local name=offer.UpgradeName
            local method=reward and 'ChooseClassReward' or 'UpgradeDrill'
            local args=reward and {version,name} or {name,version}
            local job={ctx=ctx,name=name,key=key,started=now(),before=tonumber(ctx.drill:GetAttribute(name)) or 0,
                controller=c,version=version,reward=reward==true,rollToken=c.RollToken,blacklistFallback=reason=='blacklist_fallback'}
            if Q.call('upgrade','DrillService',method,args,function(ok,value,_,dispatchState)
                -- An explicit native rejection permits a bounded retry. A lost
                -- response cannot prove the purchase failed and stays quarantined.
                if ok and value==false then
                    job.rejected=true;ledger[job.key]=now()+5
                    if s.questUpgradeJob~=job then releaseUpgradeUI(job)end
                end
                if dispatchState=='not-sent'then ledger[job.key]=nil;job.rejected=true end
                if reward and ok and type(value)=='table' and value.Success==true and value.ClaimedOfferId==version then
                    job.confirmed=true
                    if sameUpgradeUI(job)then
                        releaseUpgradeUI(job)
                        if type(c.HandleClassRewardChoiceResult)=='function'then pcall(c.HandleClassRewardChoiceResult,c,value,version)end
                    end
                end
            end,function()
                local balance=reward and wallet or Q.coinBalance(wallet,walletAt,walletVersion)
                local reservation=s.questUpgradeJob==job and not job.rejected and not job.confirmed and sameUpgradeUI(job)
                local picked,pickedKey,pickedVersion=D.choose(ctx,Q.plan(s.classData,s.questCatalog,cfg.driveDepth),c,balance,reservation and key or nil)
                return Q.enabled(ctx) and not api.extractionReady() and not(s.questDelivery and s.questDelivery.shop) and not calls.shop and not calls.wallet
                    and (reward or not cycle or ctx.questDepthEconomy==cycle and D.paidUpgradeWindow(ctx,cycle))
                    and (not c.PurchasePending or reservation and job.uiPendingOwned==true) and not c.RerollPending and not c.CardsLocked
                    and (reward or Q.canSpend(balance,D.cost(offer),false))
                    and picked==offer and pickedKey==key and pickedVersion==version
            end)then
                ledger[key]=true;s.questUpgradeJob=job
                ctx.questUpgradeAt=now()+3
                if not job.confirmed and sameUpgradeUI(job) and type(c.SetPurchasePending)=='function'then
                    local held=pcall(c.SetPurchasePending,c,true)
                    job.uiPendingOwned=held and c.PurchasePending==true or nil
                end
                info((job.blacklistFallback and 'all three cards blacklisted; cheapest fallback requested: ' or 'requested ')..name..'; awaiting server receipt')
            end
        end
        local reward=c.ActiveClassReward
        if reward then dispatch(s.questWallet or 0,s.questWalletAt,s.questWalletVersion or 0)
        else readWallet(dispatch)end
    end
    function D.mineshaft(item)
        while item and item~=workspace do
            if item.Name=='Mineshaft' or item.Name=='VoidMineshaft' or api.tag(item,'Mineshaft')then return item end
            item=item.Parent
        end
    end
    local function health(node)
        local value=node and node:FindFirstChild('Health')
        return value and tonumber(value.Value)
    end
    function D.nodeAllowed(node,coal)
        local model=node and node:GetAttribute('Ore_Model')
        local hp=health(node)
        return node and node.Parent and node:IsDescendantOf(workspace) and api.tag(node,'Ore') and type(model)=='string'
            and (not api.miningNodeAllowed or api.miningNodeAllowed(node))
            and hp and hp>0 and api.part(node) and (not coal or model:lower():find('coal',1,true)~=nil)
    end
    function D.goalEligible(node,plan)
        if not D.nodeAllowed(node,false) then return false end
        local kind=node:GetAttribute('Ore_Model'):lower()
        local coal=kind:find('coal',1,true)~=nil
        local diamond=kind:find('diamond',1,true)~=nil
        local ruby=kind:find('ruby',1,true)~=nil
        local gem=diamond or ruby or kind:find('emerald',1,true)~=nil or kind:find('heartgem',1,true)~=nil
        local ore=coal or kind:find('iron',1,true)~=nil or kind:find('gold',1,true)~=nil
        for _,goal in ipairs(plan.unmet or {})do
            if (goal.key=='MineGems' or goal.key=='SellGems') and gem or goal.key=='MineDiamond' and diamond or goal.key=='MineRuby' and ruby
                or goal.key=='MineCoal' and coal or goal.key=='MineOres' and ore then return true end
        end
        return false
    end
    function D.moneyNode(node)
        if not D.nodeAllowed(node,false)then return false end
        local kind=node:GetAttribute('Ore_Model'):lower()
        return not kind:find('coal',1,true) and (kind:find('diamond',1,true) or kind:find('emerald',1,true)
            or kind:find('ruby',1,true) or kind:find('gold',1,true) or kind:find('iron',1,true))~=nil
    end
    local function capturedMineInside(snapshot,point)
        if not snapshot or not snapshot.frame or not snapshot.size or not point then return end
        local ok,inside=pcall(function()
            local p=snapshot.frame:PointToObjectSpace(point);local half=snapshot.size*.5
            if not finite(p.X) or not finite(p.Y) or not finite(p.Z) or not finite(half.X) or not finite(half.Y) or not finite(half.Z)
                or half.X<=0 or half.Y<=0 or half.Z<=0 then return end
            return math.abs(p.X)<=half.X and math.abs(p.Y)<=half.Y and math.abs(p.Z)<=half.Z
        end)
        if ok then return inside end
    end
    local function returnedInside(ctx,returned)
        local loaded=returned.mine.Parent and returned.mine:IsDescendantOf(workspace)
        local inside
        if loaded then inside=D.contains(returned.mine,ctx.root.Position,0)end
        if inside~=nil then return inside end
        return capturedMineInside(returned.boundsSnapshot,ctx.root.Position)
    end
    local function returnState(ctx)
        local returned=ctx and ctx.questMineReturn
        local player=api.Players.LocalPlayer
        local valid=returned and returned.character==ctx.character and ctx.character==player.Character and ctx.humanoid.Health>0
            and returned.drill==ctx.drill and ctx.drill==workspace:FindFirstChild('Drill') and ctx.drill.Parent
            and returned.band==workspace:GetAttribute('InfiniteDepthOffsetMeters') and returned.mine
            and returned.session==returned.mine:GetAttribute('SessionDungeonId')
            and player:GetAttribute('ActiveDungeonQueueId')==nil and player:GetAttribute('DungeonRunLocked')~=true
        if not valid then return end
        local c=api.controller('DungeonUIController')
        if c and c._BoundDungeon and c._BoundDungeon~=returned.mine then return end
        if returned.mine.Parent and returned.mine:IsDescendantOf(workspace)then return returned end
        local transition=ctx.questMineTransition
        local entered=transition and transition~=returned.transition and transition.mode=='Enter' and transition.mine==returned.mine
        local exited=transition and transition.mode=='Exit' and transition.mine==returned.mine
        -- An unloaded room cannot erase an already observed outdoor return.
        -- Preserve only actual outside position evidence in the same native
        -- room/session; neither the old binding nor completion is rewritten.
        if returned.arrivalObserved and not entered and not returned.reentered
            and (exited or player:GetAttribute('InDungeon')==false or c and c._BoundDungeon==nil
                or c and c._BoundDungeon==returned.mine and player:GetAttribute('InDungeon')==true
                    and returnedInside(ctx,returned)==false)then return returned end
    end
    local function outsideMineState(ctx)
        local lease=ctx and ctx.questOutsideMine
        if not lease then return end
        local player=api.Players.LocalPlayer;local controller=api.controller('DungeonUIController')
        local transition=ctx.questMineTransition
        local entered=transition and transition~=lease.transition and transition.mode=='Enter' and transition.mine==lease.mine
        local valid=lease.character==ctx.character and ctx.character==player.Character and ctx.humanoid.Health>0
            and lease.drill==ctx.drill and ctx.drill==workspace:FindFirstChild('Drill') and ctx.drill.Parent
            and lease.band==workspace:GetAttribute('InfiniteDepthOffsetMeters') and lease.mine.Parent
            and lease.mine:IsDescendantOf(workspace) and controller and controller._BoundDungeon==lease.mine
            and lease.session==lease.mine:GetAttribute('SessionDungeonId')
            and lease.bounds==lease.mine:FindFirstChild('MineshaftBounds',true)
            and player:GetAttribute('InDungeon')==true and player:GetAttribute('ActiveDungeonQueueId')==nil
            and player:GetAttribute('DungeonRunLocked')~=true and not entered
        local inside=valid and D.contains(lease.mine,ctx.root.Position,0)
        if not valid or inside~=false then
            ctx.questOutsideMine=nil;ctx.questOutsideMineAt=nil;ctx.questOutsideMineCandidate=nil
            if ctx.questMineTransition and ctx.questMineTransition.mode=='Outside'
                and ctx.questMineTransition.mine==lease.mine then ctx.questMineTransition=nil end
            return
        end
        return lease
    end
    function D.returnSuspended(ctx,item)
        ctx=ctx or s.farm
        local returned=returnState(ctx);local c=api.controller('DungeonUIController')
        if not returned or not returned.suspended or returned.nativeCleared or not c or c._BoundDungeon~=returned.mine
            or api.Players.LocalPlayer:GetAttribute('InDungeon')~=true
            or api.Players.LocalPlayer:GetAttribute('ActiveDungeonQueueId')~=nil or api.Players.LocalPlayer:GetAttribute('DungeonRunLocked')==true
            or returned.reentered or ctx and returnedInside(ctx,returned)==true
            or ctx and ctx.questMineTransition and ctx.questMineTransition~=returned.transition
                and ctx.questMineTransition.mode=='Enter' and ctx.questMineTransition.mine==returned.mine then returned=outsideMineState(ctx)end
        if not returned then return end
        if not item then return returned end
        if item==returned.mine or item:IsDescendantOf(returned.mine) or D.mineshaft(item)==returned.mine then return returned end
        local session=item:GetAttribute('SessionDungeonId')
        if session~=nil and returned.session~=nil and session==returned.session then return returned end
    end
    function D.inDungeon(ctx)
        ctx=ctx or s.farm
        if D.returnSuspended(ctx)then return false end
        local transition=ctx and ctx.questMineTransition
        local c=api.controller('DungeonUIController')
        if transition and transition.mode=='Exit' and (not c or not c._BoundDungeon or c._BoundDungeon==transition.mine)then return false end
        return api.Players.LocalPlayer:GetAttribute('InDungeon')==true
    end
    function D.contains(mine,point,padding)
        local bounds=mine and mine:FindFirstChild('MineshaftBounds',true)
        if not bounds or not bounds.Parent or not bounds:IsA('BasePart') or not bounds:IsDescendantOf(mine)then return nil end
        local ok,inside=pcall(function()
            local localPoint=bounds.CFrame:PointToObjectSpace(point);local half=bounds.Size*.5
            local extra=padding or 0
            if not finite(localPoint.X) or not finite(localPoint.Y) or not finite(localPoint.Z)
                or not finite(half.X) or not finite(half.Y) or not finite(half.Z)
                or half.X<=0 or half.Y<=0 or half.Z<=0 or not finite(extra)then return nil end
            return math.abs(localPoint.X)<=half.X+extra and math.abs(localPoint.Y)<=half.Y+extra and math.abs(localPoint.Z)<=half.Z+extra
        end)
        if ok then return inside end
    end
    function D.activeMine(ctx)
        ctx=ctx or s.farm
        local c=api.controller('DungeonUIController')
        local root=c and c._BoundDungeon
        return root and root.Parent and root:IsDescendantOf(workspace)
            and D.inDungeon(ctx) and D.mineshaft(root) or nil
    end
    function D.pruneDoorObservers(ctx)
        if not ctx.questDoorRemotes or now()<(ctx.questDoorListenerPruneAt or 0)then return end
        ctx.questDoorListenerPruneAt=now()+1
        local native=api.controller('DungeonUIController');local bound=native and native._BoundDungeon
        for item,record in pairs(ctx.questDoorRemotes)do
            if type(record)=='table'then
                local mine=record.mine
                local entry,visit=ctx.questMineEntry,ctx.questDepthMine
                local keep=mine==bound or not native and mine==ctx.questLastBoundMine or ctx.nativeGateMotion
                    or entry and (entry.mine==mine or entry.gate and entry.gate:IsDescendantOf(mine)
                        or entry.prompt and entry.prompt:IsDescendantOf(mine))
                    or visit and (visit.mine==mine or visit.source==mine)
                if not keep and not(mine.Parent and mine:IsDescendantOf(workspace))then
                    pcall(function()record.connection:Disconnect()end);ctx.questDoorRemotes[item]=nil
                end
            end
        end
    end
    function D.observeDoors(ctx)
        local c=api.controller('DungeonUIController')
        local bound=c and c._BoundDungeon
        local function exited(mine)
            ctx.questMineTransition={mode='Exit',mine=mine}
            ctx.questOutsideMine=nil;ctx.questOutsideMineCandidate=nil;ctx.questOutsideMineAt=nil
            D.stopGate(ctx)
            D.stopMine(ctx);ctx.questMineEntry=nil;ctx.questMineReadyAt=nil;ctx.questFundingMine=nil
            ctx.questOwns=nil;ctx.questThreat=nil;ctx.questCombat=nil;ctx.questExitCombat=nil;ctx.combatTarget=nil
            ctx.questBindMineAt=nil;ctx.questMineExit=nil;ctx.questMineChurchFallback=nil
            status('Native mineshaft exit confirmed; resuming outdoor work')
        end
        -- UpdateState(false) also clears the bound root after a manual exit.
        -- Never set InDungeon ourselves or treat a teleport as an exit receipt.
        if ctx.questLastBoundMine and not bound and api.Players.LocalPlayer:GetAttribute('ActiveDungeonQueueId')==nil then
            exited(ctx.questLastBoundMine)
        end
        ctx.questLastBoundMine=bound and D.mineshaft(bound) or nil
        local player=api.Players.LocalPlayer
        local outside=outsideMineState(ctx)
        local inside=bound and D.mineshaft(bound)==bound and D.contains(bound,ctx.root.Position,0)
        if not outside and inside==false and player:GetAttribute('InDungeon')==true
            and ctx.character==player.Character and ctx.humanoid.Health>0 and ctx.drill==workspace:FindFirstChild('Drill') and ctx.drill.Parent
            and (not ctx.questMineEntry or ctx.questMineEntry.direct) and player:GetAttribute('ActiveDungeonQueueId')==nil
            and player:GetAttribute('DungeonRunLocked')~=true and not player.GameplayPaused
            and not workspace:GetAttribute('InfiniteRebasing') and not workspace:GetAttribute('InCutScene')then
            local bounds=bound:FindFirstChild('MineshaftBounds',true)
            local candidate=ctx.questOutsideMineCandidate
            local band=workspace:GetAttribute('InfiniteDepthOffsetMeters');local session=bound:GetAttribute('SessionDungeonId')
            if not candidate or candidate.character~=ctx.character or candidate.drill~=ctx.drill or candidate.mine~=bound
                or candidate.band~=band or candidate.session~=session or candidate.bounds~=bounds then
                candidate={character=ctx.character,drill=ctx.drill,mine=bound,session=session,band=band,bounds=bounds,transition=ctx.questMineTransition,
                    started=now(),suspended=true}
                ctx.questOutsideMineCandidate=candidate;ctx.questOutsideMineAt=candidate.started
            end
            if now()-candidate.started>=2 and not(ctx.questMineTransition and ctx.questMineTransition.mode=='Exit')then
                -- This is physical outside proof, never a native Exit receipt.
                -- Retire the old mine route once; subsequent pulses must not
                -- erase a new outdoor chest, driving or combat lease.
                ctx.questOutsideMine=candidate;ctx.questOutsideMineCandidate=nil
                ctx.questMineTransition={mode='Outside',mine=bound}
                if ctx.questMineEntry and ctx.questMineEntry.mine==bound then D.cancelDoor(ctx,false)end
                local owned=ctx.questMining or ctx.questFundingMine or ctx.questDepthMine and ctx.questDepthMine.mine==bound
                D.stopMine(ctx);ctx.questMineReadyAt=nil;ctx.questFundingMine=nil
                if ctx.questThreat and D.mineEnemy(ctx.questThreat,bound)then
                    ctx.questThreat=nil;ctx.questMineExitPickaxe=nil;ctx.questFuelThreat=nil
                end
                if ctx.combatTarget and D.mineEnemy(ctx.combatTarget,bound)then
                    ctx.combatTarget=nil;ctx.questCombat=nil;ctx.questExitCombat=nil;owned=true
                end
                if owned and not(ctx.questDriving or ctx.questSeating or ctx.currentChest or ctx.featureHold
                    or ctx.bringEquipmentLock)then ctx.questOwns=nil end
                ctx.questBindMineAt=nil;ctx.questMineExit=nil;ctx.questMineChurchFallback=nil
                status('Outside loaded mineshaft bounds; releasing stale local mine route')
            end
        elseif not outside then ctx.questOutsideMineAt=nil;ctx.questOutsideMineCandidate=nil end
        D.pruneDoorObservers(ctx)
        if now()<(ctx.questDoorScanAt or 0)then return end
        ctx.questDoorScanAt=now()+1
        if not ctx.connect then return end
        if Q.special and Q.special.observe then Q.special.observe(ctx,nil)end
        ctx.questDoorRemotes=ctx.questDoorRemotes or setmetatable({}, {__mode='k'})
        local roots,seen={},{}
        local function add(item)
            local mine=D.mineshaft(item)
            if mine and not seen[mine] and (mine==bound or mine.Parent and mine:IsDescendantOf(workspace))then
                seen[mine]=true;roots[#roots+1]=mine
            end
        end
        add(bound)
        for _,door in ipairs(api.tagged('DungeonDoor'))do add(door)end
        for _,mine in ipairs(api.tagged('Mineshaft'))do add(mine)end
        for _,item in ipairs(workspace:GetChildren())do add(item)end
        for _,mine in ipairs(roots)do
            for _,item in ipairs(mine:GetDescendants())do
                if item.Name=='DungeonDoorTransition' and item:IsA('RemoteEvent') and item.OnClientEvent and not ctx.questDoorRemotes[item]then
                    local record={mine=mine}
                    ctx.questDoorRemotes[item]=record
                    record.connection=ctx.connect(item.OnClientEvent,function(mode)
                        if not ctx.active or ctx.questDoorRemotes[item]~=record then return end
                        if mode=='Enter'then
                            if not item:IsDescendantOf(workspace)then return end
                            ctx.questMineTransition={mode='Enter',mine=mine};ctx.questMineReadyAt=now()+3
                        elseif mode=='Exit'then
                            local current=api.controller('DungeonUIController')
                            local bound=current and current._BoundDungeon
                            if bound and bound~=mine and bound.Parent and bound:IsDescendantOf(workspace)then return end
                            local active=D.activeMine(ctx)
                            local pending=ctx.questMineEntry
                            if active==mine or ctx.questLastBoundMine==mine or pending and pending.mine==mine then exited(mine)end
                        end
                    end)
                end
            end
        end
    end
    function D.mineEnemy(npc,mine)
        if D.mineshaft(npc)==mine then return true end
        local session=mine and mine:GetAttribute('SessionDungeonId')
        local npcSession=npc:GetAttribute('SessionDungeonId')
        if session~=nil and npcSession~=nil then return npcSession==session and npc:GetAttribute('DungeonWaveNpc')==true end
        local p=api.part(npc)
        local inside=p and D.contains(mine,p.Position)
        if inside~=nil then return inside end
        -- Legacy Watchers can live in workspace.Npc, without wave/session fields.
        local ctx=s.farm
        local watcher=api.tag(npc,'Watcher') or tostring(npc:GetAttribute('RealName') or npc.Name):lower():find('watcher',1,true)
        return p and ctx and watcher and (p.Position-ctx.root.Position).Magnitude<=80 or false
    end
    function D.exitPrompt(mine)
        local prompt=mine and (mine:FindFirstChild('DungeonExitPrompt',true) or mine:FindFirstChild('ExitPrompt',true))
        if prompt and prompt:IsA('ProximityPrompt')then return prompt end
        for _,door in ipairs(api.tagged('DungeonDoor'))do
            if D.mineshaft(door)==mine then
                prompt=door:FindFirstChild('DungeonExitPrompt',true) or door:FindFirstChild('ExitPrompt',true)
                if prompt and prompt:IsA('ProximityPrompt')then return prompt end
            end
        end
        -- Legacy exit gates may keep the generic ProximityPrompt name. Only
        -- inspect the verified Gate_Cave transition part, never an entry/NPC.
        for _,gate in ipairs(mine and mine:GetChildren() or {})do
            if gate.Name=='Gate_Cave' and gate:IsA('BasePart') and gate:FindFirstChild('DungeonDoorTransition')then
                prompt=gate:FindFirstChildWhichIsA('ProximityPrompt',true)
                if prompt then return prompt end
            end
        end
    end
    function D.accessible(node)
        local mine=D.mineshaft(node)
        local active=D.activeMine()
        if D.inDungeon()then
            if not active then return false end
            if mine then return mine==active end
            local session=node:GetAttribute('SessionDungeonId')
            local current=active:GetAttribute('SessionDungeonId')
            if session~=nil and current~=nil then return session==current end
            local p=api.part(node)
            return p and D.contains(active,p.Position)==true or false
        end
        return mine==nil
    end
    function D.exitState(ctx,mine)
        local state=ctx.questMineExit
        if not state or state.mine~=mine then
            state={mine=mine,started=now(),attempts=0,failures=0};ctx.questMineExit=state
        end
        return state
    end
    function D.cancelDoor(ctx,failed)
        local job=ctx.questMineEntry
        if job and job.prompt and ctx.heldPrompts and ctx.heldPrompts[job.prompt]then
            pcall(function()job.prompt:InputHoldEnd()end);ctx.heldPrompts[job.prompt]=nil
        end
        if job then job.cancelled=true end
        D.stopGate(ctx);ctx.questMineEntry=nil
        if job then ctx.questOwns=nil end
        if job and failed then
            local retries=s.questMineDoorRetries or setmetatable({}, {__mode='k'});s.questMineDoorRetries=retries
            local door=job.gate or job.prompt
            if door then retries[door]=now()+(job.exit and 8 or 30)end
            if job.exit then
                local state=D.exitState(ctx,job.mine)
                state.failures=state.failures+1;state.lastFailure=now()
                status('Native mine exit produced no transition; releasing this attempt')
            else status('Native mine entrance produced no transition; outdoor work continues')end
        end
    end
    function D.churchFallback(ctx)
        if not s.questChurchExit then return false end
        local mine=D.activeMine(ctx)
        if not mine then return false end
        local state=D.exitState(ctx,mine)
        if state.failures<2 and now()-state.started<30 then return false end
        -- SaveGear has no client-side dungeon prerequisite. Try the real loaded
        -- church flow instead of repeating this failed door forever. The server
        -- still decides acceptance; no dungeon attribute or exit receipt is forged.
        D.cancelDoor(ctx,false);D.stopMine(ctx);ctx.questExitCombat=nil;ctx.questThreat=nil
        ctx.questCombat=nil;ctx.combatTarget=nil;ctx.questOwns=nil;ctx.questMineChurchFallback=true
        status('Mine exit unconfirmed; switching to the native church save route')
        return true
    end
    function D.exitGate(mine)
        if not mine or mine:FindFirstChild('QueueSpot')then return end
        local wave=mine:FindFirstChild('Wave')
        if wave and wave:GetAttribute('QueueControlled')==true then return end
        for _,gate in ipairs(mine:GetChildren())do
            if gate.Name=='Gate_Cave' and gate:IsA('BasePart') and gate.CanTouch==true
                and gate:FindFirstChild('DungeonDoorTransition') and gate:FindFirstChild('SpawnNode')
                and gate:GetAttribute('DungeonDoorReady')~=false and gate:GetAttribute('DungeonDoorAvailable')~=false then return gate end
        end
    end
    function D.crossGate(ctx,gate)
        -- Legacy exit doors are touch parts, not DungeonExitPrompt objects.
        -- Cross their local thin axis using the real character. The notification
        -- RemoteEvent is observed only; no guessed FireServer call is sent.
        if not gate or not gate.Parent or gate.CanTouch~=true or ctx.root.CanTouch==false
            or api.Players.LocalPlayer.GameplayPaused or workspace:GetAttribute('InCutScene')then return false end
        local x=gate.Size.X<gate.Size.Z
        local normal=x and Vector3.new(1,0,0) or Vector3.new(0,0,1)
        local offset=(x and gate.Size.X or gate.Size.Z)*.5+3
        local side=gate.CFrame:PointToObjectSpace(ctx.root.Position)
        if (x and side.X or side.Z)<0 then normal=normal*-1 end
        local begin=gate.CFrame:PointToWorldSpace(normal*offset)
        local finish=gate.CFrame:PointToWorldSpace(normal*-offset)
        local mine=D.activeMine(ctx)
        local state=D.exitState(ctx,mine)
        state.attempts=state.attempts+1
        if state.attempts%2==0 then begin,finish=finish,begin end
        local distance=(finish-begin).Magnitude
        local speed=math.max(12,math.min(40,distance/4))
        local travel=math.min(8,distance/speed+1)
        ctx.questMineEntry={started=now(),exit=true,mine=mine,gate=gate,finish=finish,phase=0,
            speed=speed,travelUntil=now()+travel,lastPosition=begin,movedAt=now()}
        ctx.nativeGateMotion=true
        api.releaseHover(ctx);ctx.root.CFrame=CFrame.new(begin)
        ctx.root.AssemblyLinearVelocity=(finish-begin).Unit*speed
        if type(ctx.humanoid.MoveTo)=='function'then ctx.humanoid:MoveTo(finish)end
        status('Crossing native Gate_Cave; waiting for the game exit transition')
        return true
    end
    function D.stopGate(ctx)
        ctx.nativeGateMotion=nil
        if ctx.questMineEntry and ctx.questMineEntry.gate then
            ctx.root.AssemblyLinearVelocity=Vector3.zero
            if type(ctx.humanoid.MoveTo)=='function'then ctx.humanoid:MoveTo(ctx.root.Position)end
        end
    end
    local function readyPrompt(prompt)
        local player=api.Players.LocalPlayer
        return prompt and prompt.Parent and prompt:IsA('ProximityPrompt') and prompt.Enabled~=false
            and prompt:GetAttribute('DungeonDoorReady')==true and prompt:GetAttribute('DungeonDoorAvailable')==true
            and player:GetAttribute('InitialInventoryLoaded')==true and player:GetAttribute('RejoinDead')~=true
            and player:GetAttribute('DungeonRunLocked')~=true and player:GetAttribute('ActiveDungeonQueueId')==nil
            and api.miningDoorAllowed(prompt)
    end
    local function entryMine(item)
        local root=D.mineshaft(item)
        if root then return root end
        while item and item~=workspace do
            if item.Name=='Gate_Mineshaft'then return item end
            item=item.Parent
        end
    end
    local function detachedDepthDelivery(ctx,mine)
        local job=s.questDelivery;local visit=ctx.questDepthMine
        return job and job.ctx==ctx and job.cancelled and job.movementReleased
            and mine and visit and visit.mine==mine and visit.class==(s.classData and s.classData.SelectedClass)
            and not ctx.bringEquipmentLock and not s.equipmentRequest
            and not(s.questCashJob and s.questCashJob.movementHeld)
    end
    local function activeOwnedPickaxe(ctx)
        local c=api.controller('ToolController');local active=c and c.ActiveTool
        local display=active and active.DisplayTool;local tool=active and active.Tool
        local backpack=api.Players.LocalPlayer:FindFirstChild('Backpack')
        if not active or active._Destroyed or type(active.Swing)~='function' or not tool or tool.Parent~=ctx.character
            or not display or display.Parent~=ctx.character and display.Parent~=backpack or api.attr(display,'Class')~='Pickaxe'then return end
        local name=api.id(display)
        if api.id(tool)==name or tool.Name==name or tool.Name==name..tostring(api.Players.LocalPlayer.UserId)then return display end
    end
    local function validPoint(point)
        return point and finite(point.X) and finite(point.Y) and finite(point.Z)
    end
    function D.observeReturn(ctx)
        local returned=ctx.questMineReturn
        if not returned then return end
        local job=ctx.questMineEntry
        local ownJob=job and job.direct and job.returned==returned
        if returnState(ctx)~=returned then
            if ownJob then D.cancelDoor(ctx,false)end
            ctx.questMineReturn=nil;return
        end
        local player=api.Players.LocalPlayer;local c=api.controller('DungeonUIController')
        local bound=c and c._BoundDungeon;local transition=ctx.questMineTransition
        local cleared=player:GetAttribute('InDungeon')==false
            or c and bound==nil and player:GetAttribute('ActiveDungeonQueueId')==nil
            or transition and transition.mode=='Exit' and transition.mine==returned.mine
        if cleared then
            returned.nativeCleared=true;returned.suspended=nil
            if ownJob then D.cancelDoor(ctx,false)end
            return
        end
        if bound and bound~=returned.mine then
            returned.suspended=nil
            if ownJob then D.cancelDoor(ctx,false)end
            return
        end
        local point=ctx.root.Position
        local inside=validPoint(point) and returnedInside(ctx,returned)
        local entered=transition and transition~=returned.transition and transition.mode=='Enter' and transition.mine==returned.mine
        if entered then
            if ownJob then D.cancelDoor(ctx,false)end
            ctx.questMineReturn=nil;return -- A new actual native entrance is a new visit.
        end
        if inside==true then
            if returned.suspended then returned.reentered=true end
            returned.suspended=nil
        end
        if not returned.reentered and not returned.suspended and now()>returned.started and inside~=true and validPoint(point)then
            local near=returned.frame and validPoint(returned.frame.Position) and (point-returned.frame.Position).Magnitude<=24
            local seat=returned.label=='current drill' and ctx.drill:FindFirstChild('DrillPhysicsSeat') or nil
            seat=seat or returned.label=='current drill' and ctx.drill:FindFirstChild('VehicleSeat')
            if seat and seat:IsA('BasePart') and seat:IsDescendantOf(ctx.drill) and validPoint(seat.Position)
                and (point-seat.Position).Magnitude<=30 then near=true end
            if near and bound==returned.mine then
                -- Position was observed after the return, not merely requested.
                -- Suspend travel back into this stale bound room without claiming
                -- a native exit, a completed visit, or any quest credit.
                returned.suspended=true;returned.unconfirmedAt=now();returned.arrivalObserved=true
                local bounds=returned.mine:FindFirstChild('MineshaftBounds',true)
                if inside==false and bounds and bounds.Parent and bounds:IsA('BasePart') and bounds:IsDescendantOf(returned.mine)then
                    local snapshot={frame=bounds.CFrame,size=bounds.Size}
                    if capturedMineInside(snapshot,point)==false then returned.boundsSnapshot=snapshot end
                end
                D.stopMine(ctx)
                if D.returnSuspended(ctx,ctx.questThreat)then ctx.questThreat=nil;ctx.questMineExitPickaxe=nil end
                if D.returnSuspended(ctx,ctx.combatTarget)then ctx.combatTarget=nil;ctx.questCombat=nil end
                if ownJob then D.cancelDoor(ctx,false)end
                status('Mine return position observed; native clear unconfirmed, local outdoor work continues')
            end
        end
        if ownJob and ctx.questMineEntry==job and now()-job.started>=10 then
            returned.unconfirmedAt=now();D.cancelDoor(ctx,false)
            status('Mine return unconfirmed after 10s; local job released without repeating its teleport')
        end
    end
    function D.returnDestination(ctx,mine)
        local drill=ctx.drill;local origin=ctx.questMineOrigin
        if not drill or not drill.Parent or drill~=workspace:FindFirstChild('Drill')
            or ctx.character~=api.Players.LocalPlayer.Character or ctx.humanoid.Health<=0 then return end
        local band=workspace:GetAttribute('InfiniteDepthOffsetMeters')
        local validOrigin=origin and origin.character==ctx.character and origin.drill==drill and origin.band==band
            and origin.mine==mine and origin.mineSession==mine:GetAttribute('SessionDungeonId')
            and origin.frame and validPoint(origin.frame.Position)
        local reference=validOrigin and origin.frame.Position or ctx.root.CFrame.Position or ctx.root.Position
        local seat=drill:FindFirstChild('DrillPhysicsSeat') or drill:FindFirstChild('VehicleSeat')
        if seat and seat.Parent and seat:IsA('BasePart') and seat:IsDescendantOf(drill) and seat.CFrame
            and not D.mineshaft(drill) and validPoint(seat.CFrame.Position) and validPoint(reference)
            and ((seat.CFrame.Position-reference).Magnitude<=500
                or not origin and D.activeMine(ctx)==mine and D.contains(mine,ctx.root.Position,0)==true
                    and D.contains(mine,seat.CFrame.Position,0)==false) then
            -- Use the actual train seat frame, outside its <=3-stud automatic
            -- driver-start radius; a model's authored pivot is not a safe deck.
            local frame=seat.CFrame*CFrame.new(0,5,12)
            if validPoint(frame.Position) and D.contains(mine,frame.Position,0)~=true then return frame,'current drill' end
        end
        if validOrigin and D.contains(mine,origin.frame.Position,0)~=true then return origin.frame,'saved pre-entry position' end
    end
    function D.returnMine(ctx,mine)
        local player=api.Players.LocalPlayer
        if Q.manual() or not Q.enabled(ctx) or player:GetAttribute('ActiveDungeonQueueId')~=nil
            or player:GetAttribute('DungeonRunLocked')==true or player:GetAttribute('InitialInventoryLoaded')~=true
            or player.GameplayPaused or workspace:GetAttribute('InCutScene') or workspace:GetAttribute('InfiniteRebasing')then return false end
        local returned=ctx.questMineReturn
        if returned and returned.mine==mine and returned.session==mine:GetAttribute('SessionDungeonId')
            and returned.character==ctx.character and returned.drill==ctx.drill
            and returned.band==workspace:GetAttribute('InfiniteDepthOffsetMeters')then return false,true end
        local frame,label=D.returnDestination(ctx,mine)
        if not frame then return false end
        if s.questDelivery or calls.drag or s.questCashJob or s.bringDelivery or s.lootRequest or s.equipmentRequest then return false,true end
        if not Q.holdRoute(ctx)then return ctx.questOwns==true,true end
        Q.stopDrive(ctx)
        if ctx.humanoid.SeatPart or ctx.humanoid.Sit then local _,holding=Q.unseat(ctx);return holding,true end
        D.cancelDoor(ctx,false);D.stopMine(ctx)
        local origin=ctx.questMineOrigin
        returned={mine=mine,session=mine:GetAttribute('SessionDungeonId'),character=ctx.character,drill=ctx.drill,
            band=workspace:GetAttribute('InfiniteDepthOffsetMeters'),frame=frame,label=label,started=now(),
            source=origin and origin.source,sourceSession=origin and origin.sourceSession,transition=ctx.questMineTransition}
        ctx.questMineReturn=returned
        ctx.questMineEntry={started=now(),exit=true,direct=true,mine=mine,returned=returned}
        ctx.nativeGateMotion=true;api.releaseHover(ctx)
        ctx.root.CFrame=frame
        if ctx.root.AssemblyLinearVelocity then ctx.root.AssemblyLinearVelocity=Vector3.zero end
        status('Returning from the mineshaft to '..label..' and observing native dungeon state')
        return true,true
    end
    function D.entry(ctx,depthVisit)
        D.observeReturn(ctx)
        D.observeDoors(ctx)
        local active=D.activeMine()
        local job=ctx.questMineEntry
        local returned=ctx.questMineReturn;local transition=ctx.questMineTransition
        local controller=api.controller('DungeonUIController')
        if returned and (returned.character~=ctx.character or returned.drill~=ctx.drill
            or returned.band~=workspace:GetAttribute('InfiniteDepthOffsetMeters'))then
            ctx.questMineReturn=nil;returned=nil
        end
        if returned and (transition and transition.mode=='Exit' and transition.mine==returned.mine
            or controller and controller._BoundDungeon==nil and api.Players.LocalPlayer:GetAttribute('ActiveDungeonQueueId')==nil
            or api.Players.LocalPlayer:GetAttribute('InDungeon')==false)then
            returned.nativeCleared=true
        end
        if active and job and not job.exit and job.origin and job.origin==ctx.questMineOrigin then
            job.origin.mine=active;job.origin.mineSession=active:GetAttribute('SessionDungeonId')
        end
        if job then
            if (not job.exit and active) or (job.exit and not D.inDungeon(ctx)) then
                if not job.exit then ctx.questMineReadyAt=now()+3 else ctx.questFundingMine=nil end
                D.stopGate(ctx)
                ctx.questMineEntry=nil;ctx.questOwns=nil;return false
            end
            if job.prompt and job.holding then return true end
            if job.direct then
                if job.returned.character~=ctx.character or job.returned.drill~=ctx.drill
                    or ctx.drill~=workspace:FindFirstChild('Drill') or job.returned.band~=workspace:GetAttribute('InfiniteDepthOffsetMeters')
                    or job.returned.session~=job.mine:GetAttribute('SessionDungeonId')then
                    D.cancelDoor(ctx,false);return false
                end
                ctx.nativeGateMotion=true;api.releaseHover(ctx)
                if now()-job.started>=10 then
                    job.returned.unconfirmedAt=now();D.cancelDoor(ctx,false)
                    status('Returned from the mine; native dungeon clear remains unconfirmed, checking useful work without repeating the teleport')
                    return false
                end
                Q.holdRoute(ctx);api.watch(ctx)
                status('Returned to '..job.returned.label..'; observing the native dungeon clear')
                return true
            end
            if job.prompt then ctx.nativeGateMotion=true;api.releaseHover(ctx)end
            if now()-job.started>=10 then D.cancelDoor(ctx,true);return false end
            if job.gate then
                if not job.gate.Parent or job.gate.CanTouch~=true then D.cancelDoor(ctx,true);return false end
                if job.phase==0 then
                    local point=ctx.root.CFrame.Position or ctx.root.Position
                    local delta=job.finish-point
                    if (point-job.lastPosition).Magnitude>=.25 then job.lastPosition=point;job.movedAt=now()end
                    if delta.Magnitude<=1 then
                        D.stopGate(ctx);job.phase=1;job.receiptUntil=now()+2
                    elseif now()>=job.travelUntil or now()-job.movedAt>=1.5 then
                        D.cancelDoor(ctx,true);return false
                    else
                        ctx.root.AssemblyLinearVelocity=delta.Unit*job.speed
                        if type(ctx.humanoid.MoveTo)=='function'then ctx.humanoid:MoveTo(job.finish)end
                    end
                elseif now()>=(job.receiptUntil or 0)then D.cancelDoor(ctx,true);return false end
            end
            if Q.holdRoute(ctx)then status(job.exit and 'Awaiting native mineshaft exit' or 'Awaiting native mineshaft entry / queue')end
            return true
        end
        if not active and D.inDungeon(ctx)then return false end
        if not active and outsideMineState(ctx)then return false end -- Old native binding is still unconfirmed.
        if not active and returned and not returned.nativeCleared
            and controller and controller._BoundDungeon==returned.mine
            and api.Players.LocalPlayer:GetAttribute('InDungeon')==true then return false end
        local delivery=s.questDelivery;local detached=detachedDepthDelivery(ctx,active)
        if Q.manual() or delivery and not detached or s.bringDelivery or s.lootRequest then return false end
        local retries=s.questMineDoorRetries or setmetatable({}, {__mode='k'});s.questMineDoorRetries=retries
        local candidates={}
        if active then
            local used,reserved=D.returnMine(ctx,active)
            if used or reserved then return used end
            local exit=D.exitPrompt(active)
            local state=D.exitState(ctx,active);local ready=readyPrompt(exit)
            if ready and (state.prompt~=exit or state.promptReady~=true)then retries[exit]=nil end
            state.prompt,state.promptReady=exit,ready==true
            if ready then candidates[1]=exit end
            if not exit then
                local gate=D.exitGate(active)
                if gate and now()>=(retries[gate] or 0) and Q.holdRoute(ctx)then
                    Q.stopDrive(ctx);api.watch(ctx)
                    if ctx.humanoid.SeatPart or ctx.humanoid.Sit then
                        local _,holding=Q.unseat(ctx);return holding
                    end
                    if not api.watcherReady(ctx)then return false end
                    retries[gate]=now()+8
                    return D.crossGate(ctx,gate)
                end
            end
        else
            for _,door in ipairs(api.tagged('DungeonDoor'))do
                local mine=D.mineshaft(door)
                if not mine then
                    local p=door
                    while p and p~=workspace do if p.Name=='Gate_Mineshaft' then mine=p;break end;p=p.Parent end
                end
                local prompt=mine and door:FindFirstChildWhichIsA('ProximityPrompt',true)
                local visit=s.questDepthMineVisits and s.questDepthMineVisits[mine]
                local finished=visit and visit.session==mine:GetAttribute('SessionDungeonId')
                local returnedSource=returned and not returned.nativeCleared and returned.source==mine
                    and returned.sourceSession==mine:GetAttribute('SessionDungeonId')
                if readyPrompt(prompt) and prompt.Name~='ExitPrompt' and prompt.Name~='DungeonExitPrompt'
                    and not returnedSource and (not depthVisit or not finished)then candidates[#candidates+1]=prompt end
            end
        end
        local prompt,distance
        for _,candidate in ipairs(candidates)do
            local point=api.position(candidate)
            if point and now()>=(retries[candidate] or 0)then
                local d=(point-ctx.root.Position).Magnitude
                if (active or not depthVisit or d<=500) and (not distance or d<distance)then prompt,distance=candidate,d end
            end
        end
        if not prompt then return false end
        if not Q.holdRoute(ctx)then
            status('Waiting for chest route to acknowledge mineshaft entry handoff')
            return ctx.questOwns==true
        end
        Q.stopDrive(ctx);api.watch(ctx)
        if ctx.humanoid.SeatPart or ctx.humanoid.Sit then
            local _,holding=Q.unseat(ctx);return holding
        end
        if not api.watcherReady(ctx)then ctx.questOwns=nil;return false end
        retries[prompt]=now()+(active and 8 or 60)
        local origin
        if not active then
            local frame=ctx.root.CFrame;local source=entryMine(prompt) or prompt
            if frame and validPoint(frame.Position)then
                origin={character=ctx.character,drill=ctx.drill,band=workspace:GetAttribute('InfiniteDepthOffsetMeters'),
                    frame=frame,source=source,sourceSession=source:GetAttribute('SessionDungeonId'),started=now()}
                ctx.questMineOrigin=origin
            end
        end
        local attempt={started=now(),exit=active~=nil,mine=active or D.mineshaft(prompt),prompt=prompt,holding=true,origin=origin}
        ctx.questMineEntry=attempt
        if depthVisit and not active then
            local source=entryMine(prompt) or prompt
            ctx.questDepthMine={source=source,sourceSession=source:GetAttribute('SessionDungeonId'),prompt=prompt,started=now(),
                class=s.classData and s.classData.SelectedClass,
                failures=setmetatable({}, {__mode='k'}),blocked=setmetatable({}, {__mode='k'})}
        end
        if active then D.exitState(ctx,active).attempts=D.exitState(ctx,active).attempts+1 end
        if api.fireMiningPrompt(ctx,prompt)then
            if ctx.questMineEntry==attempt then
                attempt.started=now();attempt.holding=nil;attempt.holdFinished=true;ctx.nativeGateMotion=true;api.releaseHover(ctx)
                status(active and 'Leaving a depleted mineshaft' or 'Entering a ready Mineshaft for mining objectives')
            end
            return true
        end
        if ctx.questMineEntry==attempt then D.cancelDoor(ctx,true)end
        if depthVisit and not active then ctx.questDepthMine=nil end
        ctx.questOwns=nil;return false
    end
    local function saleEligible(item,ctx,snapshot,objective,carried)
        ctx=ctx or s.farm
        if not item or not ctx then return false end
        if carried then
            local player=api.Players.LocalPlayer
            if not item:IsA('Tool') or player.Character~=ctx.character
                or item.Parent~=ctx.character and item.Parent~=player:FindFirstChild('Backpack')then return false end
        elseif not Q.free(item,'sale')then return false end
        local id=api.id(item);local class=api.attr(item,'Class');local category=api.attr(item,'Category')
        local value=tonumber(api.attr(item,'Value'))
        local current=Q.plan(s.classData,s.questCatalog,cfg.driveDepth)
        if current.kind=='depth' and cfg.driveDepth and (id=='Ore_Iron' or id=='Ore_Gold')then return false end
        if category=='Scrap' and (current.kind=='shred' or ctx.questNeedScrap)then return false end
        local fuelValue=tonumber(api.attr(item,'Fuel')) or 0
        if not finite(value) or value<100 or Q.protectedRelic(item)
            or class=='Medkit' or class=='ReviveKit' or category=='Ammo' or id:sub(-5)=='_Ammo'
            or id=='Money_Sack' or api.tag(item,'MoneySack') or fuelValue>0 and (Q.fuelNeeded() or category=='Fuel' and not ores[id])
            or id=='Void_Helmet' or id=='Void_Chest' or id=='Void_Legs' or id=='Pickaxe_Void' or id=='Sword_Void'
            or id=='Flintlock' or id=='Sword_Pirate' then return false end
        if Q.protectedStarter(item)then return false end
        local hum=item:FindFirstChildOfClass('Humanoid')
        if hum and hum.Health>0 and (not api.enemyAlive or api.enemyAlive(item))then return false end
        if snapshot and snapshot(item) or not snapshot and api.useful(ctx,item)then return false end
        local gem=s.itemCategories and s.itemCategories.Gems and s.itemCategories.Gems[id]==true
        if objective=='SellCorpse'then return category=='Corpse' end
        if objective=='SellScrap'then return category=='Scrap' end
        if objective=='SellGems'then return gem end
        if ores[id] or gem then return true end
        -- Corpse and ordinary non-returnable valuables are native item categories.
        -- Weapon/armor/sack candidates above were compared against owned gear.
        return category=='Corpse' or category=='Valuable' or category=='Resource' or category=='Scrap'
            or api.attr(item,'ArmorType')~=nil or class=='Sword' or class=='Pickaxe' or class=='ItemBag'
            or class=='Revolver' or class=='Rifle' or class=='Shotgun'
    end
    function D.saleEligible(item,ctx,snapshot,objective)
        return saleEligible(item,ctx,snapshot,objective,false)
    end
    function D.carriedSaleEligible(item,ctx)
        if not item then return false end
        local id=api.id(item);local category=api.attr(item,'Category')
        local gem=s.itemCategories and s.itemCategories.Gems and s.itemCategories.Gems[id]==true
        -- Only consumable sale resources enter the inventory drop lane. Never
        -- expand this to carried weapons, armor, bags or class equipment.
        return (gem or ores[id] or category=='Valuable' or category=='Resource' or category=='Scrap')
            and api.attr(item,'Class')~='Sword' and api.attr(item,'Class')~='Pickaxe'
            and api.attr(item,'Class')~='ItemBag' and api.attr(item,'Class')~='Revolver'
            and api.attr(item,'Class')~='Rifle' and api.attr(item,'Class')~='Shotgun'
            and api.attr(item,'Class')~='RPG' and api.attr(item,'Class')~='Cannon'
            and api.attr(item,'Class')~='Blueprint' and api.attr(item,'ArmorType')==nil
            and saleEligible(item,ctx,nil,nil,true)
    end
    function D.saleReceipt(job)
        if job.item.Parent then return false end
        if (s.stats.coinEarned or 0)>(job.coinBefore or 0)then return true end
        local target=api.part(job.target)
        local point=target and target.Position or job.saleBand==(tonumber(workspace:GetAttribute('InfiniteDepthOffsetMeters')) or 0) and job.salePosition
        if not point then return false end
        for _,bag in ipairs(api.tagged('MoneySack'))do
            if not (job.moneyBefore or {})[bag] and api.id(bag)=='Money_Sack' and api.free(bag) then
                local p=api.part(bag);local creator=bag:GetAttribute('BagCreator')
                if p and creator==api.Players.LocalPlayer.Name and (p.Position-point).Magnitude<=30 then return true end
            end
        end
        return false
    end
    function D.stopMine(ctx)
        local face=ctx.questMineFacing;ctx.questMineFacing=nil
        if face then pcall(function()
            if face.active.FaceNearestEnemyInThirdPerson==face.wrapper then face.active.FaceNearestEnemyInThirdPerson=face.original end
            if face.aligner and face.aligner.Parent then face.aligner.Enabled=face.enabled end
        end)end
        if ctx.questMineRotate~=nil then ctx.humanoid.AutoRotate=ctx.questMineRotate;ctx.questMineRotate=nil end
        ctx.questMining=nil;ctx.questMineJob=nil
    end
    function D.findSeller(ctx,origin)
        local pad=Q.bestSeller(ctx,origin)
        local reader=api.worldSnapshot or ctx.readWorld
        if not pad and not ctx.worldReading and reader then
            -- Advance the existing bounded reader for either a loose item or
            -- carried sale resources; never start another whole-map scan.
            local ok,objects=pcall(reader,ctx)
            if ok and type(objects)=='table'then
                for _,object in ipairs(objects)do
                    if object.Parent and object.Name=='TradingPost'then
                        ctx.questPosts=ctx.questPosts or {};ctx.questPosts[object]=true
                    elseif Q.sellPad(object)then
                        ctx.worldPending=ctx.worldPending or {};ctx.worldPending[object]=true
                    end
                end
                ctx.questPadsAt=0;pad=Q.bestSeller(ctx,origin)
            end
        end
        return pad
    end
    function D.sellLoose(ctx,plan,immediate)
        if not Q.activePlan(plan) or ctx.questPotionUsing or s.questDelivery or calls.drag or s.bringDelivery or s.lootRequest or Q.manual()
            or s.questCashJob and s.questCashJob.movementHeld
            or ctx.questMineEntry or ctx.nativeGateMotion
            or not immediate and now()<(ctx.questValueSaleAt or 0)then return false end
        ctx.questValueSaleAt=now()+1
        local useful=api.snapshot and api.snapshot(ctx)
        local item,score,objective
        for _,candidate in ipairs(Q.looseItems())do
            if now()>=(s.questItemRetries[candidate] or 0)then
                local key
                for _,goal in ipairs(plan.unmet or {})do
                    if goal.key=='SellGoldItems' and Q.gold(candidate,ctx,useful)
                        or goal.key~='SellGoldItems' and Q.capabilities.sales[goal.key]
                            and D.saleEligible(candidate,ctx,useful,goal.key)then key=goal.key;break end
                end
                if key or D.saleEligible(candidate,ctx,useful)then
                    local gem=s.itemCategories and s.itemCategories.Gems and s.itemCategories.Gems[api.id(candidate)]==true
                    local value=(key and 1000000000 or 0)+(gem and 1000000 or 0)+(tonumber(api.attr(candidate,'Value')) or 0)
                    if not score or value>score then item,score,objective=candidate,value,key end
                end
            end
        end
        local gem=item and s.itemCategories and s.itemCategories.Gems and s.itemCategories.Gems[api.id(item)]==true
        if immediate and not item then return false end
        if not immediate and not gem and D.processing and D.processing.step(ctx,plan)then return true end
        local itemPart=item and api.part(item)
        if item and (not itemPart or not itemPart.Parent or not validPoint(itemPart.Position))then return false end
        local pad=itemPart and D.findSeller(ctx,itemPart.Position)
        -- Map discovery may yield while ownership or geometry changes.
        itemPart=item and api.part(item)
        if item and (not itemPart or not itemPart.Parent or not validPoint(itemPart.Position)
            or not Q.free(item,'sale'))then return false end
        if not pad then return false end
        local requestPlan={name=plan.name,counts=plan.counts,objective=objective or plan.objective}
        if Q.startDelivery(ctx,item,pad,objective=='SellGoldItems' and 'gold' or 'sale',requestPlan)then
            status('Selling disposable '..api.id(item)..'; collecting native sale receipts');return true
        end
        return false
    end
    function D.cleanup(ctx)
        D.stopDrivingDefense(ctx)
        D.stopGate(ctx)
        D.stopMine(ctx)
        ctx.questMineExitPickaxe=nil
        ctx.questMineEntry=nil
        ctx.questMineReadyAt=nil
        ctx.questFundingMine=nil
        if not api.extractionReady()then ctx.questMineExit=nil;ctx.questMineChurchFallback=nil end
        if s.questUpgradeJob and s.questUpgradeJob.ctx==ctx then
            releaseUpgradeUI(s.questUpgradeJob)
            s.questUpgradeJob=nil
        end
    end
    function D.leechReady(ctx,npc,selected)
        if not ctx or not npc or not npc.Parent or not api.isFuelLeech or not api.isFuelLeech(npc)
            or ctx.drill~=workspace:FindFirstChild('Drill') or not ctx.drill.Parent then return false end
        local hp=tonumber(npc:GetAttribute('FuelLeechHealth'))
        if not finite(hp) or hp<=0 or not npc:IsDescendantOf(workspace)
            or npc:GetAttribute('Category')=='Corpse' or npc:GetAttribute('NpcFaction')=='FriendlyCompanion' then return false end
        local ancestor=npc.Parent
        while ancestor and ancestor~=workspace do
            if ancestor.Name=='Drill' and ancestor~=ctx.drill then return false end
            ancestor=ancestor.Parent
        end
        if D.inDungeon(ctx)then
            local mine=D.activeMine(ctx);local root=not mine and Q.special.bound(ctx)
            if mine and not D.mineEnemy(npc,mine) or root and not Q.special.belongs(npc,root)
                or not mine and not root then return false end
        end
        -- Native FuelLeechComponent defaults to Buried and plays its stealing
        -- animation only when Attached. Native hit hints also require the
        -- replicated Vulnerable flag. A reveal is detection, not attack proof.
        local phase=npc:GetAttribute('FuelLeechState')
        local vulnerable=npc:GetAttribute('FuelLeechVulnerable')==true
        ctx.questLeechWatch=ctx.questLeechWatch or setmetatable({}, {__mode='k'})
        local check=ctx.questLeechWatch[npc]
        local band=workspace:GetAttribute('InfiniteDepthOffsetMeters')
        if not check or check.drill~=ctx.drill or check.band~=band
            or check.phase~=phase or check.vulnerable~=vulnerable then
            check={drill=ctx.drill,band=band,phase=phase,vulnerable=vulnerable,health=hp}
            ctx.questLeechWatch[npc]=check
        elseif hp<check.health then
            -- Real damage or a native vulnerability transition permits an
            -- immediate retry; merely moving or sending Swing does not.
            check.untilAt=nil;check.selectedAt=nil;check.progressAt=nil;check.unarmedAt=nil
        end
        check.health=hp
        if phase~='Attached' or not vulnerable then return false end
        if check.untilAt then
            if now()<check.untilAt then return false end
            check.untilAt=nil;check.selectedAt=nil;check.progressAt=nil;check.unarmedAt=nil
        end
        if check.selectedAt then
            local pickaxe=api.findOwned(ctx,'Pickaxe_Void') or api.findTool(ctx,'Pickaxe')
            if pickaxe then check.unarmedAt=nil else check.unarmedAt=check.unarmedAt or now()end
            if now()-(check.progressAt or check.selectedAt)>=12
                or check.unarmedAt and now()-check.unarmedAt>=8 then
                check.untilAt=now()+10;check.selectedAt=nil;check.progressAt=nil;check.unarmedAt=nil
                return false
            end
        end
        if selected and not check.selectedAt then
            check.selectedAt=now();check.progressAt=now()
            if not(api.findOwned(ctx,'Pickaxe_Void') or api.findTool(ctx,'Pickaxe'))then check.unarmedAt=now()end
        end
        return true
    end
    function D.threat(ctx,plan,onlyLeeches)
        local armedStartup=onlyLeeches and (api.findOwned(ctx,'Pickaxe_Void') or api.findTool(ctx,'Pickaxe'))
        if not cfg.classQuest or Q.manual()
            or s.lootRequest or ctx.questStartup and not onlyLeeches or ctx.questRecovering then return false end
        local best,score
        local list,seen={},{}
        for _,group in ipairs({api.enemies(),api.tagged('Watcher'),api.tagged('FuelLeech')})do
            for _,npc in ipairs(group)do if not seen[npc]then seen[npc]=true;list[#list+1]=npc end end
        end
        local pickaxe=armedStartup or api.findOwned(ctx,'Pickaxe_Void') or api.findTool(ctx,'Pickaxe')
        for _,npc in ipairs(list)do
            local real=tostring(npc:GetAttribute('RealName') or npc.Name):lower()
            local watcher=api.tag(npc,'Watcher') or real:find('watcher',1,true)
            local blinker=real:find('blinker',1,true)
            local leech=api.isFuelLeech and api.isFuelLeech(npc)
            local h=npc:FindFirstChildOfClass('Humanoid') or npc:FindFirstChild('Health')
            local nativeHealth=h and h:IsA('Humanoid') and h.Health
                or h and (h:IsA('NumberValue') or h:IsA('IntValue')) and h.Value
            local hp=leech and tonumber(npc:GetAttribute('FuelLeechHealth')) or tonumber(nativeHealth)
            local p=api.part(npc)
            local armored=not api.swordTargetAllowed(npc)
            -- Urgent native deflection needs a pickaxe even while the class
            -- planner requires a sword/gun for its ordinary quest targets.
            local canHit=watcher or leech or not armored or pickaxe~=nil
            if (leech or not onlyLeeches and (watcher or blinker)) and p and npc:IsDescendantOf(workspace) and finite(hp) and hp>0
                and (not api.enemyAlive or api.enemyAlive(npc))
                and (leech and D.leechReady(ctx,npc) or not leech and Q.targetResponsive(ctx,npc))
                and (not D.activeMine() or D.mineEnemy(npc,D.activeMine()))
                and canHit
                and npc:GetAttribute('Category')~='Corpse' and npc:GetAttribute('NpcFaction')~='FriendlyCompanion' then
                local distance=(p.Position-ctx.root.Position).Magnitude
                if distance<=(leech and 600 or 400)
                    and (not D.returnSuspended(ctx,npc) or api.questTargetAllowed and api.questTargetAllowed(ctx,npc))then
                    local value=(leech and -1000000 or watcher and 0 or 1000)+distance
                    if not score or value<score then best,score=npc,value end
                end
            end
        end
        if not best then
            if onlyLeeches and not ctx.questFuelThreat then return false end
            ctx.questFuelThreat=nil
            if ctx.questThreat then ctx.questThreat=nil;ctx.combatTarget=nil;ctx.questCombat=nil;ctx.questOwns=nil end
            return false
        end
        ctx.questFuelThreat=api.isFuelLeech and api.isFuelLeech(best) or nil
        if ctx.questFuelThreat then D.leechReady(ctx,best,true)end
        if ctx.questPlacement and ctx.questPlacement.processingPlacement and D.processing then D.processing.cleanup(ctx)end
        Q.abortResources(ctx)
        D.cancelDoor(ctx,false);D.stopMine(ctx)
        if not Q.holdRoute(ctx)then return true end
        Q.stopDrive(ctx);ctx.questMining=nil;ctx.questThreat=best
        ctx.questCombat,ctx.questWeapon,ctx.questWeaponClass=true,plan.weapon,plan.weaponClass or 'Sword'
        local tool=Q.preferred(ctx)
        ctx.questTurretKills=nil
        ctx.combatTarget=best;Q.armTarget(ctx,best);ctx.questExitCombat=s.questChurchExit~=nil
        if ctx.humanoid.SeatPart or ctx.humanoid.Sit then
            Q.unseat(ctx);api.watch(ctx)
            status('Urgent threat: '..tostring(best:GetAttribute('RealName') or best.Name)..'; waiting for actual seat exit before attacking')
            return true
        end
        if not tool then status('Urgent threat: waiting for the permitted quest weapon');api.watch(ctx);return true end
        local p=api.part(best);api.hover(ctx)
        if not ctx.defenseMoving and now()>=(ctx.dodgeUntil or 0) and (p.Position-ctx.root.Position).Magnitude>8
            and not D.returnSuspended(ctx,best)then
            ctx.root.CFrame=CFrame.new(p.Position+Vector3.new(0,2,6))
        end
        api.watch(ctx)
        status(Q.attackStatus(ctx,'Urgent threat: '..tostring(best:GetAttribute('RealName') or best.Name)..'; mining paused'))
        return true
    end
    function D.leechThreat(ctx,plan)return D.threat(ctx,plan,true)end
    local function ownedDriving(ctx)
        local drill=ctx.drill;local lease=s.questDriveLease
        if not cfg.classQuest or not cfg.driveDepth or not drill or drill~=workspace:FindFirstChild('Drill')
            or not drill.Parent or drill:GetAttribute('DriverUserId')~=api.Players.LocalPlayer.UserId then return false end
        local scripted=ctx.questDriving or ctx.questSeating or lease and lease.ctx==ctx and lease.drill==drill
            and lease.confirmed and not lease.abandoned
        local seat=ctx.humanoid.SeatPart
        if seat and not seat:IsDescendantOf(drill)then return false end
        return scripted and (ctx.questDriving or seat and seat:IsDescendantOf(drill)) or false
    end
    local drivingHealth,drivingEnemy
    function D.observeDrivingHealth(ctx)
        local hp=tonumber(ctx.humanoid.Health);local maximum=tonumber(ctx.humanoid.MaxHealth)
        local watch=ctx.questDrivingHealth or s.questDrivingHealth
        if not finite(hp)then return end
        local owned=ownedDriving(ctx);local selected=s.classData and s.classData.SelectedClass
        local band=workspace:GetAttribute('InfiniteDepthOffsetMeters')
        if not watch or watch.character~=ctx.character or watch.humanoid~=ctx.humanoid or watch.drill~=ctx.drill
            or watch.class~=selected or watch.band~=band then
            watch={character=ctx.character,humanoid=ctx.humanoid,drill=ctx.drill,class=selected,band=band,health=hp,maximum=maximum}
        end
        ctx.questDrivingHealth=watch;s.questDrivingHealth=watch
        if watch.boundCtx~=ctx and ctx.connect and ctx.humanoid.HealthChanged then
            watch.boundCtx=ctx
            ctx.connect(ctx.humanoid.HealthChanged,function()
                if ctx.active and s.farm==ctx and ctx.character==api.Players.LocalPlayer.Character then D.observeDrivingHealth(ctx)end
            end)
        end
        -- A reduced MaxHealth can clamp current HP without an enemy attack.
        -- Any decrease below that real clamped baseline is still damage.
        local previous=watch.health
        if finite(maximum) and maximum>0 and finite(watch.maximum) and maximum<watch.maximum then previous=math.min(previous,maximum)end
        if hp>0 and hp<previous and owned then
            watch.damageAt=now();watch.damagePoint=ctx.root.CFrame.Position or ctx.root.Position
            local target,distance
            local seen={}
            for _,group in ipairs({api.enemies(),api.tagged('Watcher'),api.tagged('FuelLeech')})do
                for _,npc in ipairs(group)do if not seen[npc]then
                    seen[npc]=true
                    local health,d=drivingEnemy(ctx,npc,watch.damagePoint)
                    if health and (not target or d<distance)then target,distance=npc,d end
                end end
            end
            if target then
                watch.intent={target=target,origin=watch.damagePoint,started=now(),lease=s.questDriveLease}
                ctx.questDrivingDefenseUntil=nil -- A fresh real hit is not an old retry signal.
            end
        end
        watch.health,watch.maximum=hp,maximum
        if not cfg.classQuest or hp<=0 then watch.intent=nil;watch.damageAt=nil;watch.damagePoint=nil
        elseif not watch.intent and watch.damageAt and now()-watch.damageAt>3 then watch.damageAt=nil;watch.damagePoint=nil end
    end
    function D.stopDrivingDefense(ctx,preserveIntent)
        local job=ctx.questDrivingDefense
        if job then
            if ctx.combatTarget==job.target then ctx.combatTarget=nil;ctx.questCombat=nil end
            if ctx.questThreat==job.target then ctx.questThreat=nil end
            if job.owns and not ctx.questHealing and not ctx.bringEquipmentLock then ctx.questOwns=nil end
        end
        ctx.questDrivingDefense=nil
        local watch=ctx.questDrivingHealth
        if not preserveIntent and watch then watch.intent=nil;watch.damageAt=nil;watch.damagePoint=nil end
    end
    drivingHealth=function(npc)
        local hum=npc:FindFirstChildOfClass('Humanoid')
        return api.isFuelLeech and api.isFuelLeech(npc) and tonumber(npc:GetAttribute('FuelLeechHealth'))
            or hum and tonumber(hum.Health)
    end
    drivingEnemy=function(ctx,npc,origin)
        local p=api.part(npc)
        local leech=api.isFuelLeech and api.isFuelLeech(npc)
        local hp=drivingHealth(npc)
        if not npc.Parent or not npc:IsDescendantOf(workspace) or not p or not finite(hp) or hp<=0
            or npc:GetAttribute('Category')=='Corpse' or npc:GetAttribute('NpcFaction')=='FriendlyCompanion'
            or api.enemyAlive and not api.enemyAlive(npc)then return end
        local point=ctx.root.CFrame.Position or ctx.root.Position
        local seat=ctx.drill:FindFirstChild('DrillPhysicsSeat') or ctx.drill:FindFirstChild('VehicleSeat')
        local nearDrill=seat and seat.Parent and seat:IsDescendantOf(ctx.drill) and (p.Position-seat.Position).Magnitude<=45
        if not nearDrill and (p.Position-origin).Magnitude>45 or (p.Position-point).Magnitude>60 then return end
        local mine=D.activeMine(ctx)
        if D.inDungeon(ctx)then
            local bound=not mine and Q.special.bound(ctx)
            if mine and not D.mineEnemy(npc,mine) or bound and not Q.special.belongs(npc,bound)
                or not mine and not bound then return end
        else
            if D.mineshaft(npc) or npc:GetAttribute('SessionDungeonId')~=nil or npc:GetAttribute('DungeonWaveNpc')==true then return end
            local ancestor=npc.Parent
            while ancestor and ancestor~=workspace do
                if ancestor.Name=='Goblin_Ring' or ancestor.Name=='GoblinRing' or ancestor.Name=='VampireMansion'then return end
                ancestor=ancestor.Parent
            end
        end
        if leech and not D.leechReady(ctx,npc) or not leech and not Q.targetResponsive(ctx,npc)then return end
        local retry=ctx.questDrivingEnemyRetry and ctx.questDrivingEnemyRetry[npc]
        if retry then
            if hp<retry.health or now()>=retry.untilAt then ctx.questDrivingEnemyRetry[npc]=nil else return end
        end
        return hp,(p.Position-point).Magnitude
    end
    function D.drivingDefense(ctx,plan)
        local job=ctx.questDrivingDefense
        local health=tonumber(ctx.humanoid.Health);local max=tonumber(ctx.humanoid.MaxHealth)
        local driver=ctx.drill and ctx.drill:GetAttribute('DriverUserId')
        local foreign=driver~=nil and driver~=0 and driver~=api.Players.LocalPlayer.UserId
        local attached=ctx.humanoid.SeatPart
        if not cfg.driveDepth or not Q.enabled(ctx) or Q.manual() or api.extractionReady() or foreign
            or ctx.drill~=workspace:FindFirstChild('Drill') or not ctx.drill.Parent
            or attached and not attached:IsDescendantOf(ctx.drill)
            or not finite(health) or health<=0 or finite(max) and max>0 and health/max<=.3
            or ctx.questHealing or Q.refuelActive and Q.refuelActive(ctx)
            or ctx.questStartup or ctx.questRecovering then
            D.stopDrivingDefense(ctx);return false
        end
        if ctx.nativeGateMotion or ctx.questMineEntry then D.stopDrivingDefense(ctx,true);return false end
        if job and (job.character~=ctx.character or job.drill~=ctx.drill or ctx.drill~=workspace:FindFirstChild('Drill')
            or job.band~=workspace:GetAttribute('InfiniteDepthOffsetMeters') or job.class~=(s.classData and s.classData.SelectedClass))then
            D.stopDrivingDefense(ctx);job=nil
        end
        local watch=ctx.questDrivingHealth;local intent=watch and watch.intent
        if intent and (watch.character~=ctx.character or watch.humanoid~=ctx.humanoid or watch.drill~=ctx.drill
            or watch.band~=workspace:GetAttribute('InfiniteDepthOffsetMeters') or watch.class~=(s.classData and s.classData.SelectedClass))then
            watch.intent=nil;intent=nil
        end
        if not job then
            local own=ownedDriving(ctx)
            if not watch or not own and not intent or not intent and (not watch.damageAt or now()-watch.damageAt>3)then return false end
            -- An old script receipt cannot stop a later manually occupied seat.
            if not own and driver==api.Players.LocalPlayer.UserId
                and not(intent and intent.lease and s.questDriveLease==intent.lease and intent.lease.ctx==ctx and intent.lease.abandoned)then return false end
            if intent and intent.retryAt then
                local released=intent.waiting=='seat' and not ctx.humanoid.SeatPart and not ctx.humanoid.Sit
                    or intent.waiting=='action' and not(s.bringDelivery or s.lootRequest or s.equipmentRequest or ctx.bringEquipmentLock)
                        and not Q.driveHandoff(ctx)
                    or intent.waiting=='route' and ctx.routeParked==true and not(ctx.currentChest or ctx.featureHold or ctx.defenseMoving
                        or s.bringDelivery or s.lootRequest or s.equipmentRequest or ctx.bringEquipmentLock)
                if released then intent.retryAt=nil;intent.waiting=nil;ctx.questDrivingDefenseUntil=nil
                elseif now()<intent.retryAt then return false end
            end
            if now()<(ctx.questDrivingDefenseUntil or 0)then return false end
            job={character=ctx.character,drill=ctx.drill,band=workspace:GetAttribute('InfiniteDepthOffsetMeters'),
                class=s.classData and s.classData.SelectedClass,origin=intent and intent.origin or watch.damagePoint,
                started=now(),owns=ctx.questOwns==true,intent=intent,driveLease=intent and intent.lease or s.questDriveLease}
        end
        if job.target then
            local current=drivingHealth(job.target)
            if finite(current) and current<job.health then job.health,job.progressAt,job.unarmedAt=current,now(),nil end
        end
        local candidates,seen={},{}
        for _,group in ipairs({api.enemies(),api.tagged('Watcher'),api.tagged('FuelLeech')})do
            for _,npc in ipairs(group)do if not seen[npc]then seen[npc]=true;candidates[#candidates+1]=npc end end
        end
        local npc,hp,distance
        for _,candidate in ipairs(candidates)do
            local value,d=drivingEnemy(ctx,candidate,job.origin)
            if value and (ctx.questDrivingDefense or not intent or candidate==intent.target)
                and (not npc or candidate==job.target or npc~=job.target and d<distance)then npc,hp,distance=candidate,value,d end
        end
        if not npc then
            if not ctx.questDrivingDefense and intent and watch.intent==intent then
                watch.intent=nil;watch.damageAt=nil;watch.damagePoint=nil
            end
            if ctx.questDrivingDefense and job.target and ctx.questTargetRetry and ctx.questTargetRetry[job.target]then
                ctx.questDrivingDefenseUntil=now()+10
            end
            D.stopDrivingDefense(ctx);return false
        end
        if not ctx.questDrivingDefense then
            ctx.questDrivingDefense=job;watch.damageAt=nil;watch.damagePoint=nil
        end
        local attack=ctx.questDamageWatch and ctx.questDamageWatch[npc]
        if job.attackStartedAt and attack and attack.lastAttempt and attack.lastAttempt>=job.attackStartedAt then
            if watch and watch.intent==job.intent then watch.intent=nil end
            job.intent=nil -- Actual permitted-target packet; never a kill or HP receipt.
        end
        if job.target~=npc then
            if ctx.combatTarget==job.target then ctx.combatTarget=nil;ctx.questCombat=nil end
            if ctx.questThreat==job.target then ctx.questThreat=nil end
            job.target,job.health=npc,hp
            job.progressAt=job.progressAt or now()
        elseif hp<job.health then job.health,job.progressAt,job.unarmedAt=hp,now(),nil end
        Q.abortResources(ctx);Q.stopDrive(ctx)
        local stoppedLease=job.driveLease
        local stoppedOwner=ctx.drill:GetAttribute('DriverUserId')
        if stoppedLease and stoppedLease.ctx==ctx and stoppedLease.drill==ctx.drill
            and stoppedLease.confirmed and stoppedLease.abandoned and stoppedLease.stopAccepted==true
            and (stoppedOwner==nil or finite(stoppedOwner) and stoppedOwner>=0 and stoppedOwner~=api.Players.LocalPlayer.UserId)then
            job.driverReleased=true
        end
        local function yieldHandoff(reason)
            if job.intent then job.intent.retryAt=now()+10;job.intent.waiting=reason end
            ctx.questDrivingDefenseUntil=now()+10;D.stopDrivingDefense(ctx,true);return false
        end
        if s.bringDelivery or s.lootRequest or s.equipmentRequest or ctx.bringEquipmentLock or Q.driveHandoff(ctx)then
            if ctx.combatTarget==npc then ctx.combatTarget=nil;ctx.questCombat=nil end
            if now()-job.started>=8 then
                return yieldHandoff('action')
            end
            status('Driving damage observed; waiting for native driving, input or item ownership to release')
            return true
        end
        if not Q.holdRoute(ctx)then
            job.owns=ctx.questOwns==true
            if now()-job.started>=8 then
                return yieldHandoff('route')
            end
            return true
        end
        job.owns=true
        if ctx.humanoid.SeatPart or ctx.humanoid.Sit then
            job.seatWaitAt=job.seatWaitAt or now()
            if ctx.combatTarget==npc then ctx.combatTarget=nil;ctx.questCombat=nil end
            local _,holding=Q.unseat(ctx);api.watch(ctx)
            if now()-job.seatWaitAt>=8 then
                return yieldHandoff('seat')
            end
            status('Driving damage observed; waiting for actual seat exit before clearing nearby enemies')
            return holding or now()-job.seatWaitAt<8
        end
        job.seatWaitAt=nil
        if not job.attackStartedAt then job.attackStartedAt=now();job.progressAt=now()end
        ctx.questThreat=npc;ctx.questCombat=true;ctx.questWeapon,ctx.questWeaponClass=plan.weapon,plan.weaponClass or 'Sword'
        ctx.combatTarget=npc;Q.armTarget(ctx,npc)
        local seat=ctx.drill:FindFirstChild('DrillPhysicsSeat') or ctx.drill:FindFirstChild('VehicleSeat')
        local function movementFree()
            local currentMax=tonumber(ctx.humanoid.MaxHealth)
            return cfg.driveDepth and Q.enabled(ctx) and not Q.manual() and not api.extractionReady()
                and ctx.questDrivingDefense==job and job.character==ctx.character
                and ctx.character==api.Players.LocalPlayer.Character and job.drill==ctx.drill
                and ctx.drill==workspace:FindFirstChild('Drill') and job.band==workspace:GetAttribute('InfiniteDepthOffsetMeters')
                and job.class==(s.classData and s.classData.SelectedClass)
                and not ctx.questHealing and not ctx.questMineEntry and not ctx.nativeGateMotion
                and not(finite(currentMax) and currentMax>0 and ctx.humanoid.Health/currentMax<=.3)
                and Q.driveStopped(ctx,job.driveLease)
                and not(calls.drag or calls.cash or calls.shop or s.questDelivery or s.questCashJob
                    or s.bringDelivery or s.lootRequest or s.equipmentRequest or ctx.bringEquipmentLock
                    or ctx.currentChest or ctx.featureHold or ctx.defenseMoving or now()<(ctx.dodgeUntil or 0))
        end
        local escaped=false
        if movementFree() and seat and seat.Parent and seat:IsA('BasePart') and seat:IsDescendantOf(ctx.drill)
            and validPoint(seat.Position) and validPoint(ctx.root.Position) and (ctx.root.Position-seat.Position).Magnitude<=3 then
            -- Native TrainComponent checks this radius every0.1s. Waiting for
            -- equipment here can re-seat us and hide/unequip the weapon again.
            local read,frame=pcall(function()return seat.CFrame*CFrame.new(0,2,6)end)
            if read and frame and validPoint(frame.Position) and (frame.Position-seat.Position).Magnitude>3 then
                api.hover(ctx)
                if movementFree()then
                    ctx.root.CFrame=frame;escaped=true
                    if ctx.root.AssemblyLinearVelocity then ctx.root.AssemblyLinearVelocity=Vector3.zero end
                end
            end
        end
        local tool=Q.preferred(ctx)
        if tool then job.unarmedAt=nil else job.unarmedAt=job.unarmedAt or now()end
        if now()-job.progressAt>=12 or job.unarmedAt and now()-job.unarmedAt>=8 then
            ctx.questDrivingEnemyRetry=ctx.questDrivingEnemyRetry or setmetatable({}, {__mode='k'})
            ctx.questDrivingEnemyRetry[npc]={health=hp,untilAt=now()+10}
            ctx.questDrivingDefenseUntil=now()+10;D.stopDrivingDefense(ctx)
            status('Nearby driving defense made no native damage progress; resuming other work with a bounded retry')
            return false
        end
        api.watch(ctx)
        if not tool then status('Driving defense: waiting for an owned compatible weapon');return true end
        api.hover(ctx)
        distance=(api.part(npc).Position-ctx.root.Position).Magnitude
        if movementFree() and not escaped and distance>8 then
            local destination=api.part(npc).Position+Vector3.new(0,2,6)
            if not seat or not seat.Parent or validPoint(seat.Position) and (destination-seat.Position).Magnitude>3 then
                ctx.root.CFrame=CFrame.new(destination)
            end
        end
        status(Q.attackStatus(ctx,'Driving paused after native damage; clearing nearby enemies before continuing'))
        return true
    end
    function D.boost(ctx)
        local drill=ctx.drill;local user=api.Players.LocalPlayer.UserId
        if not cfg.classQuest or not cfg.driveDepth or not ctx.questDriving or api.extractionReady()
            or drill:GetAttribute('DriverUserId')~=user or (tonumber(drill:GetAttribute('PowerBurst')) or 0)<=0
            or now()<(s.questBoostAt or 0) or calls.boost then return false end
        local seat=drill:FindFirstChild('LocalDriverSeat') or drill:FindFirstChild('VehicleSeat')
        if not seat or not seat.Parent or ctx.humanoid.Health<=0 then return false end
        local serverNow=workspace:GetServerTimeNow();local last=tonumber(drill:GetAttribute('LastBoost'))
        if last and serverNow-last<60 then return false end
        local character,band,class=ctx.character,workspace:GetAttribute('InfiniteDepthOffsetMeters'),s.classData and s.classData.SelectedClass
        if Q.call('boost','DrillService','ActivateBoost',{},function(ok,accepted,cooldown)
            if ok and accepted==false and finite(tonumber(cooldown))then
                s.questBoostAt=math.max(s.questBoostAt or 0,now()+math.max(1,tonumber(cooldown)))
            end
        end,function()
            local current=Q.plan(s.classData,s.questCatalog,cfg.driveDepth)
            local ok,uis=pcall(function()return game:GetService('UserInputService')end)
            local focused=not ok or not uis or type(uis.GetFocusedTextBox)~='function' or uis:GetFocusedTextBox()~=nil
            local boosted=tonumber(drill:GetAttribute('LastBoost'))
            return Q.enabled(ctx) and cfg.driveDepth and ctx.questDriving and not Q.manual() and not focused
                and not api.extractionReady() and not ctx.questHealing and not ctx.nativeGateMotion and not ctx.questMineEntry
                and ctx.character==character and ctx.drill==drill and drill==workspace:FindFirstChild('Drill')
                and band==workspace:GetAttribute('InfiniteDepthOffsetMeters') and class==(s.classData and s.classData.SelectedClass)
                and (current.kind=='depth' or current.kind=='fuel') and drill:GetAttribute('DriverUserId')==user
                and seat.Parent and seat:IsDescendantOf(drill)
                and seat==(drill:FindFirstChild('LocalDriverSeat') or drill:FindFirstChild('VehicleSeat'))
                and (tonumber(drill:GetAttribute('PowerBurst')) or 0)>0
                and (not boosted or workspace:GetServerTimeNow()-boosted>=60)
        end)then
            s.questBoostAt=now()+60;status('Requested native drill Power Burst; observing its 60-second cooldown')
            return true
        end
        return false
    end
    function D.leaveMine(ctx,plan)
        ctx.questExitCombat=nil;ctx.questMineExitPickaxe=nil
        local mine=D.activeMine()
        if not mine then ctx.questFundingMine=nil;return false end
        D.exitState(ctx,mine)
        -- A real prompt hold/physical crossing owns movement until its native
        -- transition arrives or the bounded attempt finishes. Do not float,
        -- relocate toward another target, or start a sale during that phase.
        local pending=ctx.questMineEntry
        if pending and pending.exit and not pending.direct and D.returnDestination(ctx,mine) and not Q.manual()then
            D.cancelDoor(ctx,false)
        end
        if ctx.questMineEntry and D.entry(ctx)then return true end
        if not D.activeMine(ctx)then return false end
        -- Native queue ownership can require clearing its scoped hostiles.
        -- A return changes position; only observed native state settles the
        -- dungeon lease and any completed depth-mine visit.
        local candidates={}
        local seen={};local loaded={}
        for _,group in ipairs({api.enemies(),api.tagged('Watcher')})do
            for _,npc in ipairs(group)do if not seen[npc]then seen[npc]=true;loaded[#loaded+1]=npc end end
        end
        for _,npc in ipairs(loaded)do
            local h=npc:FindFirstChildOfClass('Humanoid')
            if D.mineEnemy(npc,mine) and h and h.Health>0 and api.part(npc) and Q.targetResponsive(ctx,npc)
                and (not api.enemyAlive or api.enemyAlive(npc))
                and (api.swordTargetAllowed(npc) or api.findOwned(ctx,'Pickaxe_Void') or api.findTool(ctx,'Pickaxe'))
                and npc:GetAttribute('NpcFaction')~='FriendlyCompanion'then candidates[#candidates+1]=npc end
        end
        if not Q.holdRoute(ctx)then return true end
        Q.stopDrive(ctx);ctx.questMining=nil
        local npc,priority,distance
        for _,candidate in ipairs(candidates)do
            local real=tostring(candidate:GetAttribute('RealName') or candidate.Name):lower()
            local value=(real:find('watcher',1,true) or real:find('blinker',1,true) or api.tag(candidate,'Watcher')) and 1 or 0
            local d=(api.part(candidate).Position-ctx.root.Position).Magnitude
            if not priority or value>priority or value==priority and d<distance then npc,priority,distance=candidate,value,d end
        end
        if npc then
            D.cancelDoor(ctx,false);ctx.questOwns=true
            ctx.questCombat,ctx.questWeapon,ctx.questWeaponClass=true,plan.weapon,plan.weaponClass or 'Sword'
            ctx.questThreat=not api.swordTargetAllowed(npc) and npc or nil
            local tool=Q.preferred(ctx)
            if not tool and ctx.questDepthMine and ctx.questDepthMine.mine==mine
                and ctx.questDepthMine.class==(s.classData and s.classData.SelectedClass)
                and (api.findOwned(ctx,'Pickaxe_Void') or api.findTool(ctx,'Pickaxe'))then
                ctx.questThreat=npc;ctx.questMineExitPickaxe=npc;tool=Q.preferred(ctx)
            end
            if ctx.humanoid.SeatPart or ctx.humanoid.Sit then
                Q.unseat(ctx);api.watch(ctx);return true
            end
            if tool then
                ctx.combatTarget=npc;Q.armTarget(ctx,npc);api.hover(ctx)
                ctx.questExitCombat=s.questChurchExit~=nil
                local point=api.part(npc).Position
                if (point-ctx.root.Position).Magnitude>8 then ctx.root.CFrame=CFrame.new(point+Vector3.new(0,2,6))end
                api.watch(ctx);status(Q.attackStatus(ctx,'Mineshaft exit gated; clearing a loaded hostile with the permitted quest weapon'))
                return true
            end
        end
        ctx.combatTarget=nil;ctx.questCombat=nil
        if api.extractionReady()then
            local used,reserved=D.returnMine(ctx,mine)
            if used then return true end
            if not reserved and D.churchFallback(ctx)then return false end
        end
        -- A retry cooldown is not an exit receipt and need not be idle. Keep
        -- the native mine route scoped while settling existing transactions,
        -- selling loaded disposable drops, collecting native coin bags and
        -- opening eligible chests in this room. An unknown Drag lane still
        -- prevents replacement deliveries through the ordinary helpers.
        if s.questDelivery then
            local busy=Q.deliveryStep(ctx,plan)
            if busy and s.questDelivery and not detachedDepthDelivery(ctx,mine)then return true end
        end
        if s.questCashJob and Q.cashStep(ctx)then return true end
        if D.sellLoose(ctx,plan)then return true end
        if Q.collectMoney(ctx)then return true end
        if Q.chestTurn(ctx,plan)then return true end
        if D.entry(ctx)then return true end
        local returned=ctx.questMineReturn
        if returned and returned.mine==mine and returned.session==mine:GetAttribute('SessionDungeonId')then
            api.releaseHover(ctx);ctx.questOwns=nil;api.watch(ctx)
            status('Mine return attempted; native dungeon clear remains unconfirmed, checking useful work without repeating the teleport')
            return false
        end
        if D.churchFallback(ctx)then return false end
        local prompt=D.exitPrompt(mine)
        local player=api.Players.LocalPlayer
        local reason=ctx.questPromptProblem or not prompt and 'native exit ProximityPrompt not loaded'
            or prompt:GetAttribute('DungeonDoorReady')~=true and 'DungeonDoorReady is false'
            or prompt:GetAttribute('DungeonDoorAvailable')~=true and 'DungeonDoorAvailable is false'
            or player:GetAttribute('ActiveDungeonQueueId')~=nil and 'native queue still active'
            or player:GetAttribute('DungeonRunLocked')==true and 'DungeonRunLocked is true'
            or player:GetAttribute('InitialInventoryLoaded')~=true and 'inventory not confirmed loaded'
            or prompt.Enabled==false and 'native exit prompt disabled' or 'exit retry cooling down'
        api.releaseHover(ctx)
        status('Mineshaft exit waits: '..reason..'; checking loaded drops and chests between bounded retries')
        api.watch(ctx);return true
    end
    local function miningPause(ctx,node,text,delay)
        local visit=ctx.questDepthMine
        if visit and visit.mine==D.activeMine(ctx) and node and not text:lower():find('cooldown',1,true)then
            visit.failures[node]=(visit.failures[node] or 0)+1
            if visit.failures[node]>=2 then visit.blocked[node]=true end
        end
        if node and delay then
            ctx.questMineRetry=ctx.questMineRetry or setmetatable({}, {__mode='k'})
            ctx.questMineRetry[node]=now()+delay
        end
        D.stopMine(ctx);ctx.questOwns=nil
        ctx.questMineYieldUntil=now()+1.5;s.questMiningProblem=text
        status(text..'; chest discovery continues')
        return false
    end
    local function miningHandoff(ctx,mine)
        if Q.holdRoute(ctx)then mine.handoffAt=nil;return true end
        if not ctx.questOwns then return false end -- finish an in-flight chest first
        mine.handoffAt=mine.handoffAt or now()
        status('Mining waits for chest route to yield; target retained')
        if now()-mine.handoffAt>=3 then
            miningPause(ctx,mine.node,'Mining handoff timed out',5)
        end
        return false
    end
    local function pickaxeReadiness(ctx,pickaxe,node,begin,attemptProof)
        local waits=s.questPickaxeReadiness
        local wait=waits and waits[pickaxe]
        if wait and (wait.character~=ctx.character or wait.drill~=ctx.drill)then
            waits[pickaxe]=nil;wait=nil
        end
        local controller=api.controller('ToolController');local active=controller and controller.ActiveTool
        local display=active and (active.DisplayTool or active.Tool);local name=api.id(pickaxe)
        local backpack=api.Players.LocalPlayer:FindFirstChild('Backpack')
        local owned=pickaxe and (pickaxe.Parent==ctx.character or pickaxe.Parent==backpack)
        local pickClass=display and (api.attr(display,'Class')=='Pickaxe' or api.id(display)=='Champions_Hammer')
        local matching=active and active.Tool and (active.Tool==pickaxe or api.id(active.Tool)==name
            or active.Tool.Name==name or active.Tool.Name==name..tostring(api.Players.LocalPlayer.UserId))
        if owned and active and not active._Destroyed and active.Tool and active.Tool.Parent==ctx.character
            and (controller.ServerEquipId==nil or active.Tool:GetAttribute('ServerToolEquipId')==controller.ServerEquipId)
            and pickClass and matching and type(active.Swing)=='function'then
            if waits then waits[pickaxe]=nil end
            return active,nil,false
        end
        local record=s.equipRecords and s.equipRecords[pickaxe]
        local retryProof
        if wait and record and record.rejected and finite(record.retryAt)
            and now()>=record.retryAt and wait.retryUsed~=record.retryAt then retryProof=record.retryAt end
        local remote,backoff
        if begin or wait and wait.notDispatched then
            if api.remote then local ok,value=pcall(api.remote,'ToolService','EquipTool');if ok then remote=value end end
            backoff=s.requestBackoff and s.requestBackoff['ToolService.EquipTool'] or 0
        end
        if wait and wait.notDispatched then
            if remote and remote~=wait.remote then retryProof=remote
            elseif finite(wait.backoff) and wait.backoff>wait.started and now()>=wait.backoff
                and wait.retryUsed~=wait.backoff then retryProof=wait.backoff end
        end
        if begin and attemptProof then retryProof=attemptProof end
        if not wait and begin then
            waits=waits or setmetatable({}, {__mode='k'});s.questPickaxeReadiness=waits
            wait={character=ctx.character,drill=ctx.drill,started=now(),health=setmetatable({}, {__mode='k'})}
            waits[pickaxe]=wait
        end
        if wait then
            if begin then
                if retryProof then
                    wait.retryUsed=retryProof
                    if record and not record.notDispatched and not record.uncertain
                        and (record.pending or record.accepted or record.rejected)then wait.started=now();wait.yielded=nil end
                end
                wait.notDispatched=record and record.notDispatched==true
                if wait.notDispatched then wait.remote,wait.backoff=remote,backoff end
                retryProof=nil -- The proven retry was consumed by this attempt.
            end
            -- A different streamed vein is not a new equipment attempt. Only
            -- observed native damage to an already remembered vein rearms it.
            for remembered,previous in pairs(wait.health)do
                local hp=remembered.Parent and api.tag(remembered,'Ore') and D.accessible(remembered) and health(remembered)
                if finite(hp)then
                    if hp<previous then wait.started=now();wait.yielded=nil end
                    wait.health[remembered]=hp
                end
            end
            if node then local hp=health(node);if finite(hp)then wait.health[node]=hp end end
            if record and (record.rejected or record.uncertain) or now()-wait.started>=8 then wait.yielded=true end
        end
        return nil,wait,wait and wait.yielded==true and not retryProof,retryProof
    end
    local function yieldPickaxeReadiness(ctx)
        local owned=ctx.questMining==true
        D.stopMine(ctx)
        if owned and not(ctx.questDriving or ctx.featureHold or ctx.currentChest or ctx.nativeGateMotion
            or ctx.questCombat or ctx.defenseMoving or ctx.bringEquipmentLock)then ctx.questOwns=nil end
        status('Owned pickaxe readiness did not confirm within 8s; other loaded work continues')
        return false
    end
    local function miningPose(ctx,mine,active)
        local ok,center,size=pcall(api.miningBounds,mine.surface or mine.node)
        if not ok or not center or not size or size.X<=0 or size.Y<=0 or size.Z<=0 then return false end
        if not mine.anchor or (center-mine.center).Magnitude>2 or not mine.boundsSize or (size-mine.boundsSize).Magnitude>.5 then
            local delta=ctx.root.Position-center
            local side=Vector3.new(delta.X,0,delta.Z)
            if side.Magnitude<.1 then side=Vector3.new(0,0,1)else side=side.Unit end
            if mine.alternate then side=side*-1 end
            local extent=(math.abs(side.X)*size.X+math.abs(side.Z)*size.Z)*.5
            local range=tonumber(active.Range) or 13
            local gap=math.min(2,math.max(.5,range*.2))
            mine.center,mine.boundsSize=center,size
            -- Native pickaxe checks a forward box and rejects ore below pivotY-2.
            -- GetSwingCFrame raises the native box another TWO studs. Standing
            -- above the top puts a short-range pickaxe's entire box in the air.
            local height=center.Y+size.Y*.5+math.min(0,range*.5-2-.5)
            if mine.surface then
                local nc,ns=api.miningBounds(mine.node)
                if nc and ns then height=math.min(height,nc.Y+ns.Y*.5+1)end
            end
            mine.anchor=Vector3.new(center.X,height,center.Z)+side*(extent+gap)
            mine.frame=CFrame.lookAt(mine.anchor,Vector3.new(center.X,mine.anchor.Y,center.Z))
            mine.placed=nil
        end
        api.hover(ctx)
        -- The native pickaxe auto-faces nearby enemies every 0.1s. Body
        -- AutoRotate=false alone does not stop that AlignOrientation loop.
        local face=ctx.questMineFacing
        if face and face.active~=active then
            pcall(function()
                if face.active.FaceNearestEnemyInThirdPerson==face.wrapper then face.active.FaceNearestEnemyInThirdPerson=face.original end
                if face.aligner and face.aligner.Parent then face.aligner.Enabled=face.enabled end
            end)
            ctx.questMineFacing=nil;face=nil
        end
        if not face and type(active.FaceNearestEnemyInThirdPerson)=='function'then
            face={active=active,original=active.FaceNearestEnemyInThirdPerson,aligner=active.AutoFaceAligner,
                enabled=active.AutoFaceAligner and active.AutoFaceAligner.Enabled}
            face.wrapper=function(self,...)
                if self==active and ctx.questMining and ctx.questMineJob==mine then
                    if self.AutoFaceAligner then self.AutoFaceAligner.Enabled=false end
                    return
                end
                return face.original(self,...)
            end
            active.FaceNearestEnemyInThirdPerson=face.wrapper;ctx.questMineFacing=face
        end
        if active.AutoFaceAligner then active.AutoFaceAligner.Enabled=false end
        if ctx.questMineRotate==nil then ctx.questMineRotate=ctx.humanoid.AutoRotate end
        ctx.humanoid.AutoRotate=false
        local pivot=type(ctx.character.GetPivot)=='function' and ctx.character:GetPivot() or ctx.root.CFrame
        if not mine.placed or (pivot.Position-mine.anchor).Magnitude>2 then
            if type(ctx.character.PivotTo)=='function' then ctx.character:PivotTo(mine.frame)
            else ctx.root.CFrame=mine.frame end
            mine.placed=true
        elseif pivot.LookVector then
            local direction=Vector3.new(center.X-pivot.Position.X,0,center.Z-pivot.Position.Z)
            if direction.Magnitude>.1 and pivot.LookVector:Dot(direction.Unit)<.98 then
                local facing=CFrame.lookAt(pivot.Position,Vector3.new(center.X,pivot.Position.Y,center.Z))
                if type(ctx.character.PivotTo)=='function'then ctx.character:PivotTo(facing)else ctx.root.CFrame=facing end
            end
        end
        return true
    end
    local function mineSnapshot(ctx,visit)
        local scan=ctx.worldScan
        local watch=visit.snapshotWatch
        if scan and (not watch or watch.scan~=scan)then
            watch={scan=scan,cursor=scan.cursor,childCursor=scan.childCursor,children=scan.children,progressAt=now()}
            visit.snapshotWatch=watch
        elseif scan and (watch.cursor~=scan.cursor or watch.childCursor~=scan.childCursor or watch.children~=scan.children)then
            watch.cursor,watch.childCursor,watch.children=scan.cursor,scan.childCursor,scan.children
            watch.progressAt=now();visit.snapshotRetryAt=nil
        end
        local reader=ctx.worldReader
        local busy=ctx.worldReading and (not reader or coroutine.status(reader)~='dead')
        if (scan or not visit.snapshotReadStarted) and type(ctx.readWorld)=='function' and not busy
            and now()>=(visit.snapshotRetryAt or 0)then
            local ok,why=pcall(ctx.readWorld)
            if not ok then
                local text=tostring(why)
                if text:find('__CHESTFARM_CANCELLED',1,true) or text:find('__EARTH_DEFENSE_RETRY',1,true)
                    or text:find('__EARTH_MODE_CHANGED',1,true)then error(why,0)end
                visit.snapshotProblem='native chest snapshot reader failed'
            elseif type(why)=='table'then visit.snapshotReadStarted=true;visit.snapshotProblem=nil
            else visit.snapshotProblem='native chest snapshot reader returned no snapshot' end
            local current=ctx.worldScan
            if current~=scan or scan and (scan.cursor~=watch.cursor or scan.childCursor~=watch.childCursor or scan.children~=watch.children)then
                -- The candidate cache must see descendants from this slice, even
                -- when the last slice clears worldScan before chestTurn runs.
                ctx.chestsDirty=true;visit.snapshotRetryAt=nil
                watch=current and {scan=current,cursor=current.cursor,childCursor=current.childCursor,
                    children=current.children,progressAt=now()} or nil
                visit.snapshotWatch=watch
            end
            scan=current
        end
        if not scan and not visit.snapshotProblem and not(busy and not visit.snapshotReadStarted)then
            if visit.snapshotWatch then ctx.chestsDirty=true end
            visit.snapshotWatch=nil;visit.snapshotRetryAt=nil;return false,busy
        end
        watch=visit.snapshotWatch
        if not watch then
            watch={scan=scan,cursor=scan and scan.cursor,childCursor=scan and scan.childCursor,
                children=scan and scan.children,progressAt=now()}
            visit.snapshotWatch=watch
        end
        if now()-watch.progressAt>=10 then
            visit.snapshotRetryAt=visit.snapshotRetryAt or now()+3
            return true,busy
        end
        return false,busy
    end
    function D.depthMine(ctx,plan)
        if ctx.questDepthMine and ctx.questDepthMine.class~=(s.classData and s.classData.SelectedClass)then
            ctx.questDepthMine=nil;ctx.questMineExitPickaxe=nil
        end
        local ownedVisit=ctx.questDepthMine and ctx.questDepthMine.class==(s.classData and s.classData.SelectedClass)
        if ((plan.kind~='depth' and plan.kind~='fuel') or not cfg.driveDepth) and not ownedVisit or not Q.enabled(ctx)
            or api.extractionReady() or Q.manual()then return false end
        if ctx.drill~=workspace:FindFirstChild('Drill') or not ctx.drill.Parent then D.stopMine(ctx);ctx.questOwns=nil;return false end
        D.observeDoors(ctx)
        local active=D.activeMine(ctx);local visit=ctx.questDepthMine
        local pending=ctx.questMineEntry
        local returned=D.returnSuspended(ctx)
        if returned and visit and visit.mine==returned.mine then
            local job=ctx.questMineJob
            if job and job.node and D.returnSuspended(ctx,job.node)==returned then
                local owns=ctx.questMining==true and ctx.questOwns==true
                D.stopMine(ctx)
                -- This unfinished visit retains only its old room's scope.
                -- Once that mine job is gone, a later outdoor coal/chest/driver
                -- lease must survive every subsequent suspended-room pulse.
                if owns and not(ctx.questDriving or ctx.questSeating or ctx.currentChest or ctx.featureHold
                    or ctx.defenseMoving or ctx.nativeGateMotion or ctx.bringEquipmentLock or ctx.questCombat
                    or s.bringDelivery or s.lootRequest or s.equipmentRequest or s.questDelivery or s.questCashJob)then
                    ctx.questOwns=nil
                end
            end
            return false
        end
        if visit and visit.mine and active~=visit.mine then
            local transition=ctx.questMineTransition
            local c=api.controller('DungeonUIController')
            local player=api.Players.LocalPlayer
            local confirmed=transition and transition.mode=='Exit' and transition.mine==visit.mine
                or c and c._BoundDungeon==nil and player:GetAttribute('ActiveDungeonQueueId')==nil
                or returnState(ctx) and ctx.questMineReturn.mine==visit.mine and ctx.questMineReturn.nativeCleared
            if confirmed and visit.drained and not visit.incomplete then
                s.questDepthMineVisits=s.questDepthMineVisits or setmetatable({}, {__mode='k'})
                s.questDepthMineVisits[visit.source]={session=visit.sourceSession}
                s.questDepthMineVisits[visit.mine]={session=visit.mineSession}
            end
            ctx.questDepthMine=nil;visit=nil
        end
        if not active then
            if pending then return D.entry(ctx,true)end
            if visit and not visit.mine then ctx.questDepthMine=nil end
            if D.inDungeon(ctx)then return false end -- Another/unbound native dungeon owns its route.
            if plan.kind~='depth' and plan.kind~='fuel' or not cfg.driveDepth then return false end
            local pickaxe=api.findOwned(ctx,'Pickaxe_Void') or api.findTool(ctx,'Pickaxe')
            if not pickaxe then return false end
            local _,_,unready=pickaxeReadiness(ctx,pickaxe)
            if unready then status('Owned pickaxe readiness remains unconfirmed; deferring another mine entry');return false end
            if s.questDelivery or s.questCashJob or s.bringDelivery or s.lootRequest then return false end
            return D.entry(ctx,true)
        end
        if not visit then
            local source=pending and not pending.exit and (pending.mine or entryMine(pending.prompt) or pending.prompt) or active
            visit={source=source,sourceSession=source:GetAttribute('SessionDungeonId'),mine=active,
                mineSession=active:GetAttribute('SessionDungeonId'),started=now(),
                class=s.classData and s.classData.SelectedClass,
                failures=setmetatable({}, {__mode='k'}),blocked=setmetatable({}, {__mode='k'})}
            ctx.questDepthMine=visit
        elseif not visit.mine then visit.mine=active;visit.mineSession=active:GetAttribute('SessionDungeonId')end
        if not visit.snapshotStarted then
            ctx.chestsDirty=true;ctx.worldRefreshAt=0;visit.snapshotStarted=true
        end
        Q.stopDrive(ctx)
        if ctx.humanoid.SeatPart or ctx.humanoid.Sit then local _,holding=Q.unseat(ctx);return holding end
        if pending and pending.exit then return D.entry(ctx)end
        if s.questDelivery then
            Q.deliveryStep(ctx,plan)
            if s.questDelivery and not(s.questDelivery.cancelled and s.questDelivery.movementReleased)then return true end
        end
        if Q.cashStep(ctx)then return true end
        if D.step(ctx,plan)then visit.drainAt=nil;return true end
        local stalled,snapshotBusy=mineSnapshot(ctx,visit)
        ctx.questChestDue=now()
        if not snapshotBusy and Q.chestTurn(ctx,plan)then visit.drainAt=nil;return true end
        if not s.questDelivery and not s.questCashJob then
            if api.collectMineLoot and api.collectMineLoot(ctx)then visit.drainAt=nil;return true end
            if Q.collectMoney(ctx)then visit.drainAt=nil;return true end
            if D.sellLoose(ctx,plan)then visit.drainAt=nil;return true end
        end
        local remains=false
        for _,node in ipairs(api.tagged('Ore'))do
            if D.nodeAllowed(node,false) and D.accessible(node)then
                if visit.blocked[node]then visit.incomplete=true else remains=true end
            end
        end
        local readinessBlocked=false
        if remains and visit.detachedBlocked then visit.incomplete=true
        elseif remains then
            local pickaxe=api.findOwned(ctx,'Pickaxe_Void') or api.findTool(ctx,'Pickaxe')
            local unready=false
            if pickaxe then local _,_,blocked=pickaxeReadiness(ctx,pickaxe);unready=blocked end
            if unready then
                visit.incomplete=true;readinessBlocked=true
            elseif pickaxe then
                visit.drainAt=nil
                Q.holdRoute(ctx);api.watch(ctx);status('Depth mineshaft: loaded veins remain; allowing native cooldown / bounded retry')
                return true
            else visit.incomplete=true end -- Missing gear cannot claim a completed mine.
        end
        if ctx.worldScan or visit.snapshotProblem or snapshotBusy and not visit.snapshotReadStarted then
            visit.drainAt=nil
            if stalled then
                ctx.questOwns=nil
                status('Depth mine chest snapshot stalled; other loaded work continues, retrying its actual scan')
                return false
            end
            if readinessBlocked then
                ctx.questOwns=nil;status('Unready pickaxe: settling the actual chest snapshot before an incomplete mine return');return false
            end
            Q.holdRoute(ctx);status('Depth mineshaft: completing its loaded chest snapshot');return true
        end
        visit.drainAt=visit.drainAt or now()
        if now()-visit.drainAt<2 then
            if readinessBlocked then
                ctx.questOwns=nil;status('Unready pickaxe: allowing real loaded drops to settle before an incomplete mine return');return false
            end
            Q.holdRoute(ctx);api.watch(ctx);status('Depth mineshaft: allowing mined/chest drops to arrive before native exit');return true
        end
        if readinessBlocked and (s.equipmentRequest or s.questDelivery or calls.drag or s.questCashJob
            or s.bringDelivery or s.lootRequest or ctx.bringEquipmentLock)then
            ctx.questOwns=nil;status('Incomplete mine return waits for the reserved native action; other loaded work continues');return false
        end
        visit.drained=true
        return D.leaveMine(ctx,plan)
    end
    function D.step(ctx,plan)
        local goal=plan.kind=='mining' or plan.objective=='SellGems'
        local depth=(plan.kind=='depth' or plan.kind=='fuel') and cfg.driveDepth
        local activeMine=D.activeMine(ctx)
        local collectAll=activeMine and (depth or ctx.questDepthMine and ctx.questDepthMine.mine==activeMine
            and ctx.questDepthMine.class==(s.classData and s.classData.SelectedClass))
        local refueling=Q.refuelActive and Q.refuelActive(ctx)
        if depth and (ctx.drill~=workspace:FindFirstChild('Drill') or not ctx.drill.Parent)then
            D.stopMine(ctx);ctx.questOwns=nil;return false
        end
        if not collectAll and not refueling and (plan.kind=='waiting' or plan.kind=='advance' or plan.kind=='complete' or plan.kind=='unsupported')then D.cleanup(ctx);return false end
        if ctx.questMineEntry and (not ctx.questMineEntry.exit or not D.inDungeon(ctx)) and D.entry(ctx)then return true end
        if D.activeMine() and now()<(ctx.questMineReadyAt or 0)then
            Q.holdRoute(ctx);api.watch(ctx);status('Mineshaft entry confirmed; allowing veins to stream in');return true
        end
        if now()<(ctx.questMineYieldUntil or 0)then return false end
        local detached=collectAll and detachedDepthDelivery(ctx,activeMine)
        if Q.manual() or s.questDelivery and not s.questDelivery.background and not detached or s.bringDelivery or s.lootRequest then return false end
        local detachedPickaxe=detached and activeOwnedPickaxe(ctx)
        local visit=ctx.questDepthMine
        if detached and not detachedPickaxe then
            D.stopMine(ctx)
            local needsPickaxe=false
            for _,node in ipairs(api.tagged('Ore'))do
                if D.nodeAllowed(node,false) and D.accessible(node) and not visit.blocked[node]then needsPickaxe=true;break end
            end
            if not needsPickaxe then visit.detachedBlocked=nil;visit.detachedToolBlockedAt=nil;return false end
            visit.detachedToolBlockedAt=visit.detachedToolBlockedAt or now()
            if now()-visit.detachedToolBlockedAt<5 then
                Q.holdRoute(ctx);api.watch(ctx);status('Depth mine: unresolved delivery permits only an already active owned pickaxe');return true
            end
            visit.detachedBlocked=true;return false
        elseif visit then visit.detachedBlocked=nil;visit.detachedToolBlockedAt=nil end
        local tank=tonumber(ctx.drill:GetAttribute('Fuel'));local capacity=tonumber(ctx.drill:GetAttribute('MaxFuel'))
        local needFuel=refueling or depth and finite(tank) and finite(capacity) and capacity>0 and tank<=capacity*.2
        local wall=ctx.questWallWork
        local wallFunding=depth and wall and wall.drill==ctx.drill and wall.band==workspace:GetAttribute('InfiniteDepthOffsetMeters')
            and ctx.drill:GetAttribute('IsDrilling')==true
        local needCoins=wallFunding or finite(s.questWallet) and s.questWallet<D.fundingTarget(ctx,plan)
        -- A stalled empty tank needs coal ahead of optional coin bags/sales.
        -- Reuse the native support-mine return lease; no separate dungeon state.
        if ctx.questFundingMine=='fuel' and not needFuel and not collectAll then
            D.stopMine(ctx);return D.leaveMine(ctx,plan)
        end
        if not collectAll and not needFuel and Q.moneyTarget(ctx) and not ctx.questMineJob then return false end
        if ctx.questMineJob and not needFuel and not detached and D.sellLoose(ctx,plan)then
            -- Retain the live vein, but allow mined gems/ores their native sale
            -- turn before another swing. Fuel starvation keeps coal priority.
            ctx.questMineJob.progressAt=nil;ctx.questMining=nil;return true
        end
        local mine=ctx.questMineJob
        if mine then
            if not D.nodeAllowed(mine.node,mine.coal) or not D.accessible(mine.node) or not collectAll and goal and not D.goalEligible(mine.node,plan)
                or not collectAll and not goal and not needFuel and not needCoins
                then
                D.stopMine(ctx);ctx.questOwns=nil;return false
            end
            if now()-mine.started>=((goal or collectAll) and 120 or 30)then
                return miningPause(ctx,mine.node,'Mining target time limit reached',8)
            end
            local pickaxe=detachedPickaxe or api.findOwned(ctx,'Pickaxe_Void') or api.findTool(ctx,'Pickaxe')
            if not pickaxe then
                D.stopMine(ctx);ctx.questOwns=nil;status('Mining waits for an actually owned pickaxe; other loaded work continues');return false
            end
            local _,_,unready,retryProof=pickaxeReadiness(ctx,pickaxe,mine.node)
            if unready then return yieldPickaxeReadiness(ctx)end
            ctx.questMining=true
            if not miningHandoff(ctx,mine)then return ctx.questOwns==true end
            Q.stopDrive(ctx);ctx.questMining=true;api.watch(ctx)
            if ctx.humanoid.SeatPart or ctx.humanoid.Sit then
                local _,holding=Q.unseat(ctx);return holding
            end
            mine.readyAt=mine.readyAt or now()
            api.equip(ctx,pickaxe)
            local active;active,_,unready=pickaxeReadiness(ctx,pickaxe,mine.node,true,retryProof)
            if not active then
                if unready then return yieldPickaxeReadiness(ctx)end
                mine.progressAt=nil;status('Mining waits for owned pickaxe readiness; target retained');return true
            end
            local hp=health(mine.node)
            if hp<mine.health then
                mine.health,mine.progressAt=hp,now()
                if ctx.questDepthMine then ctx.questDepthMine.failures[mine.node]=nil end
            end
            if not miningPose(ctx,mine,active)then return miningPause(ctx,mine.node,'Vein geometry is not loaded',3)end
            if api.miningHitReady then
                local hit,why=api.miningHitReady(ctx,active,mine.node)
                if not hit then
                    if not mine.surfaceTried and api.miningSurface then
                        mine.surfaceTried=true;mine.surface=api.miningSurface(ctx,mine.node);mine.anchor=nil;mine.progressAt=nil
                        if mine.surface then status('Mining approach adjusts to a loaded ore part');return true end
                    end
                    if not mine.alternate then
                        mine.alternate=true;mine.anchor=nil;mine.progressAt=nil
                        status('Mining approach missed the native ore hitbox; trying the other side');return true
                    end
                    return miningPause(ctx,mine.node,'Mining blocked: '..(why or 'ore outside native hitbox'),5)
                end
            end
            api.watch(ctx)
            if not api.watcherReady(ctx)then mine.progressAt=nil;status('Mining pauses for Watcher camera attention');return true end
            if mine.progressAt and now()-mine.progressAt>=8 then
                if not mine.alternate then
                    mine.alternate=true;mine.anchor=nil;mine.progressAt=nil
                    status('Vein HP unchanged; trying its other side once');return true
                end
                return miningPause(ctx,mine.node,'Vein HP unchanged after both approaches',8)
            end
            local swung,why=api.mine(ctx,active)
            local aura=ctx.lastMiningAura
            local auraStatus=aura and now()-aura.time<=2 and '; pickaxe aura: '..aura.count..' nearby hostiles' or ''
            if swung then mine.progressAt=mine.progressAt or now()
            else
                local reason=why or 'native pickaxe action / cooldown'
                if not mine.progressAt and now()-mine.readyAt>=15 then return miningPause(ctx,mine.node,'Mining blocked: '..reason,5)end
                status('Mining waits: '..reason..auraStatus);return true
            end
            status((goal and 'Mining class objectives with '..api.id(pickaxe)..'; awaiting server counters'
                or mine.coal and 'Mining loaded coal for fuel' or 'Mining loaded ore for upgrade coins')..auraStatus);return true
        end
        if goal and not (api.findOwned(ctx,'Pickaxe_Void') or api.findTool(ctx,'Pickaxe'))then
            s.questMiningProblem='Mining quest requires an owned pickaxe';return false
        end
        s.questMiningProblem=nil
        if not collectAll and not goal and not needFuel and not needCoins then
            ctx.questMining=nil
            if ctx.questFundingMine then return D.leaveMine(ctx,plan)end
            return false
        end
        if not detached and needFuel and now()>=(ctx.questSupportFuelAt or 0)then
            local item,furnace=Q.fuelItem(ctx)
            if item then
                if not Q.holdRoute(ctx)then return ctx.questOwns==true end
                Q.stopDrive(ctx);ctx.questSupportFuelAt=now()+20
                return Q.startDelivery(ctx,item,furnace,'fuel',plan)
            end
        end
        if not needFuel and not s.questDelivery and D.sellLoose(ctx,plan)then return true end
        local pickaxe=detachedPickaxe or api.findOwned(ctx,'Pickaxe_Void') or api.findTool(ctx,'Pickaxe')
        if not pickaxe then
            if needFuel then s.questMiningProblem='Coal fuel needs an owned pickaxe; looking for free fuel and useful gear' end
            return false
        end
        local _,_,unready=pickaxeReadiness(ctx,pickaxe)
        if unready then
            status('Owned pickaxe readiness remains unconfirmed; other loaded work continues');return false
        end
        local nodes={};local rejected={loading=0,unavailable=0,objective=0,retry=0,distant=0}
        for _,node in ipairs(api.tagged('Ore'))do
            if not D.nodeAllowed(node,needFuel and not collectAll)then rejected.loading=rejected.loading+1
            elseif not D.accessible(node)then rejected.unavailable=rejected.unavailable+1
            elseif ctx.questDepthMine and ctx.questDepthMine.blocked[node]then rejected.loading=rejected.loading+1
            elseif not collectAll and (goal and not D.goalEligible(node,plan) or not goal and not needFuel and not D.moneyNode(node))then rejected.objective=rejected.objective+1
            elseif now()<((ctx.questMineRetry or {})[node] or 0)then rejected.retry=rejected.retry+1
            elseif not collectAll and (api.part(node).Position-ctx.root.Position).Magnitude>600 then rejected.distant=rejected.distant+1
            else nodes[#nodes+1]=node end
        end
        local node=Q.nearest(nodes,ctx.root.Position)
        if collectAll and needFuel then
            local coal={};for _,candidate in ipairs(nodes)do if D.nodeAllowed(candidate,true)then coal[#coal+1]=candidate end end
            node=Q.nearest(coal,ctx.root.Position) or node
        end
        if goal then
            local primary={unmet={{key=plan.objective}}};local preferred={}
            for _,item in ipairs(nodes)do if D.goalEligible(item,primary)then preferred[#preferred+1]=item end end
            node=Q.nearest(preferred,ctx.root.Position) or node
        end
        if node then
            if ctx.questMineEntry and ctx.questMineEntry.exit then D.cancelDoor(ctx,false)end
            ctx.questMineExit=nil
            if not Q.holdRoute(ctx) and not ctx.questOwns then return false end
            ctx.questMining=true
            if not goal and D.activeMine()then ctx.questFundingMine=needFuel and 'fuel' or not depth and true or ctx.questFundingMine end
            ctx.questMineJob={node=node,coal=needFuel and D.nodeAllowed(node,true),started=now(),health=health(node)}
            if not miningHandoff(ctx,ctx.questMineJob)then return ctx.questOwns==true end
            Q.stopDrive(ctx);s.questIdle=nil
            return true
        end
        s.questMiningProblem=string.format('No eligible nearby vein (%d loading/dead, %d other dungeon, %d wrong type, %d retry, %d distant)',
            rejected.loading,rejected.unavailable,rejected.objective,rejected.retry,rejected.distant)
        if collectAll then return false end -- The depth visit still owes its chest/loot/native exit turn.
        if goal or needFuel or ctx.questFundingMine then
            if D.activeMine() and (rejected.retry>0 or rejected.distant>0)then
                D.cancelDoor(ctx,false);Q.holdRoute(ctx);api.watch(ctx)
                status('Loaded mining targets remain; waiting for their retry or nearer streaming')
                return true
            end
            if D.activeMine()then return D.leaveMine(ctx,plan)end
            if goal or needFuel or needCoins and #Q.sellers(ctx)>0 then
                ctx.questFundingMine=not goal and (needFuel and 'fuel' or true) or nil
                -- Fuel/funding searches belong to the same depth visit policy.
                -- Reopening a drained native session cannot provide more coal;
                -- keep finished-session exclusion, the entry radius and the
                -- visit lease used by the normal depth mineshaft path.
                return D.entry(ctx,depth and not goal)
            end
        end
        return false
    end
    D.processing=buildQuestProcessing(api,Q,D)
    return D
end

end)()
    local buildQuestSpecial = (function()
-- Native crafting intake, blueprint placement and dungeon campaigns.
-- This worker never manufactures class counters, placement validity or kills.
return function(api,Q)
    local S,s,cfg,now={},api.state,api.state.config,api.now
    local calls=s.questCalls
    local function finite(v)return type(v)=='number' and v==v and math.abs(v)<math.huge end
    local function status(text)s.questStatus=text end
    local function count(plan,key)return tonumber(plan.counts and plan.counts[key]) or 0 end
    local function unmet(plan,key)
        for _,goal in ipairs(plan.unmet or {})do if goal.key==key then return goal end end
    end
    local function live(item)return item and item.Parent and item:IsDescendantOf(workspace)end
    local function native(name)return api.sharedModule and api.sharedModule(name)end
    local function toolId(item)return item and api.id(item)end
    local function turretId(id)
        local catalog=native('CraftingCatalog');local entry=catalog and catalog[id]
        if type(entry)~='table' then return false end
        for _,tag in ipairs(entry.Tags or {})do if tag=='SentryTurret'then return true end end
        return false
    end
    function S.fastPlacement(plan)
        return cfg.classQuest and plan and plan.name=='Engineer' and unmet(plan,'PlaceTurrets')~=nil
    end
    function S.matches(npc,key)
        local name=tostring(npc:GetAttribute('RealName') or npc.Name):lower():gsub('[^%w]','')
        if key=='CrazyMinerKills'then return name:match('^crazyminer%d*$')~=nil or name:match('^voidcrazyminer%d*$')~=nil
            or name:match('^minercrazy%d*$')~=nil or name:match('^voidminercrazy%d*$')~=nil end
        if key=='BanditMinerKills'then return name:match('^banditminer%d*$')~=nil or name:match('^voidbanditminer%d*$')~=nil
            or name:match('^minerbandit%d*$')~=nil or name:match('^voidminerbandit%d*$')~=nil end
        if key=='GoblinKills'then return name:find('goblin',1,true)~=nil end
        if key=='GoblinLordKills'then return name=='goblinlord' or name=='voidgoblinlord' end
        return true
    end
    function S.matchesPlan(npc,plan)
        if plan.objective=='CrazyMinerKills' or plan.objective=='BanditMinerKills'then
            for _,goal in ipairs(plan.unmet or {})do
                if (goal.key=='CrazyMinerKills' or goal.key=='BanditMinerKills') and S.matches(npc,goal.key)then return true end
            end
            return false
        end
        return S.matches(npc,plan.objective)
    end
    function S.starterIds(plan)
        local entry=s.questCatalog and s.questCatalog[plan.name];local ids={}
        for level,list in pairs(entry and entry.StarterTools or {})do
            if type(level)=='number' and level<=plan.level then
                for _,id in ipairs(list)do if turretId(id)then ids[id]=true end end
            end
        end
        return ids
    end
    function S.protectedCarried(ctx,plan)
        local entry=s.questCatalog and s.questCatalog[plan.name];local allowed={ItemBag=true,Pickaxe_Wooden=true,Sword_Wooden=true}
        local function add(value)
            if type(value)=='string'then allowed[value]=true
            elseif type(value)=='table'then for _,v in pairs(value)do add(v)end end
        end
        add(entry and entry.StarterTools);add(entry and entry.StarterArmor)
        for _,container in ipairs({ctx.character,api.Players.LocalPlayer:FindFirstChild('Backpack')})do
            if container then for _,item in ipairs(container:GetChildren())do
                local armor=item:GetAttribute('ArmorName');local id=armor or toolId(item)
                if type(id)=='string' and not allowed[id]then
                    for name in pairs(allowed)do if id==name..tostring(api.Players.LocalPlayer.UserId)then id=name;break end end
                end
                if armor and not allowed[id]then return true end
                if (item:IsA('Tool') or api.attr(item,'Tool')==true or api.attr(item,'Class')~=nil) and not allowed[id]then return true end
            end end
        end
        return false
    end
    function S.quickReturn(ctx)
        local job=s.questTurretRestart
        if not cfg.classQuest or not job or job.ctx~=ctx or not ctx.active then return false end
        local plan=Q.plan(s.classData,s.questCatalog,cfg.driveDepth)
        if plan.name~=job.class or plan.level~=job.level or not unmet(plan,'PlaceTurrets')then s.questTurretRestart=nil;return false end
        if count(plan,'PlaceTurrets')<=job.before or Q.manual() or s.lootRequest or s.equipmentRequest
            or s.questDelivery or s.bringDelivery or s.questDeathClaim or calls.place or calls.craft
            or api.Players.LocalPlayer:GetAttribute('PlacingCraftedPlaceable')==true then return false end
        if S.protectedCarried(ctx,plan)then
            s.questChurchExit=s.questChurchExit or {reason='Turret placed; church save preserves carried equipment before the starter-only loop',requestedAt=now()}
            return false
        end
        return not s.questChurchExit
    end
    function S.scrapPad(ctx)
        local best,distance
        local function add(part)
            if not live(part) or not part:IsA('BasePart')then return end
            local p=part
            while p and p~=workspace and p.Name~='CraftingShack'do p=p.Parent end
            if not p or p==workspace then return end
            local d=(part.Position-ctx.root.Position).Magnitude
            if not distance or d<distance then best,distance=part,d end
        end
        for _,part in ipairs(api.tagged('ScrapCollector'))do add(part)end
        -- The exported CraftingShack SellSpot intake is distinct from TradingPost.
        for _,item in ipairs(ctx.worldObjects or {})do
            if item.Name=='SellSpot' and item.Parent and item.Parent.Name=='SellSpot'then add(item)end
        end
        return best
    end
    function S.scrapEligible(item,ctx)
        return Q.free(item) and api.attr(item,'Category')=='Scrap'
            and not Q.protectedRelic(item) and not api.useful(ctx,item)
    end
    function S.shred(ctx,plan)
        local pad=S.scrapPad(ctx)
        if not pad then status('Scrap quest: looking for a loaded CraftingShack shredder; chest discovery continues');return false end
        local best,score
        for _,item in ipairs(Q.looseItems())do
            if S.scrapEligible(item,ctx) and now()>=(s.questItemRetries[item] or 0)then
                local value=tonumber(api.attr(item,'Value')) or 0
                if not score or value>score then best,score=item,value end
            end
        end
        if not best then status('Scrap quest: collecting chests for disposable scrap');return false end
        local request={name=plan.name,counts=plan.counts,objective='ShredScrap'}
        if Q.startDelivery(ctx,best,pad,'shred',request)then
            status('Delivering disposable scrap to the native shredder; awaiting Cogs-worth quest credit');return true
        end
        return false
    end
    function S.blueprint(ctx)
        for _,container in ipairs({ctx.character,api.Players.LocalPlayer:FindFirstChild('Backpack')})do
            if container then for _,tool in ipairs(container:GetChildren())do
                if tool:IsA('Tool') and turretId(toolId(tool))then return tool end
            end end
        end
    end
    function S.readCraft(ctx)
        if calls.craftState or now()<(ctx.questCraftReadAt or 0)then return end
        ctx.questCraftReadAt=now()+3
        Q.call('craftState','CraftingService','GetState',{},function(ok,value)
            if ok and type(value)=='table' and finite(tonumber(value.ScrapCount))then
                s.questCraftState=value
                local c=api.controller('CraftingController')
                if c and type(c.ApplyState)=='function'then pcall(c.ApplyState,c,value)end
            end
        end,function()return Q.enabled(ctx) and not api.extractionReady()end)
    end
    function S.craft(ctx,plan)
        S.readCraft(ctx)
        local c=api.controller('CraftingController');local job=s.questCraftJob
        if job then
            local blueprint=S.blueprint(ctx)
            local total=tonumber(s.questCraftState and s.questCraftState.CraftedCounts and s.questCraftState.CraftedCounts.BasicSentry)
            if blueprint and toolId(blueprint)=='BasicSentry' and (job.accepted or total and total>job.before)then
                local token=calls.craft
                if token and token.thread then
                    pcall(task.cancel,token.thread)
                    if coroutine.status(token.thread)=='dead' and calls.craft==token then calls.craft=nil end
                end
                if not calls.craft then s.questCraftJob=nil end
                return false
            end
            if job.rejected then s.questCraftJob=nil;ctx.questCraftRetry=now()+10;return false end
            if now()-job.started>=12 then ctx.questOwns=nil;status('Turret craft unconfirmed; request reserved, chest work continues');return false end
            status('Awaiting the crafted turret blueprint inventory receipt');return true
        end
        if not c or type(c.CanCraft)~='function' or not s.questCraftState or c.PendingCraft or calls.craft
            or now()<(ctx.questCraftRetry or 0)then return false end
        local catalog=native('CraftingCatalog');local entry=catalog and catalog.BasicSentry
        if not entry or entry.UseType~='Placeable' or entry.Craftable==false then return false end
        local portable=type(c.CanCraftAnywhere)=='function' and c:CanCraftAnywhere()
        if not live(c.CraftSource) and not portable then
            local source,distance
            for _,part in ipairs(api.tagged('MagnitudeFrame'))do
                if part.Name=='Crafting' and live(part) and api.part(part)then
                    local d=(api.part(part).Position-ctx.root.Position).Magnitude
                    if not distance or d<distance then source,distance=part,d end
                end
            end
            if source and Q.holdRoute(ctx)then
                Q.stopDrive(ctx);api.hover(ctx);ctx.root.CFrame=CFrame.new(api.part(source).Position+Vector3.new(0,2,0))
                if type(c.SetCraftSource)=='function'then pcall(c.SetCraftSource,c,source)end
                status('At a native Crafting source for turret replenishment');return true
            end
            status('Turret quest: looking for a loaded CraftingShack source');return false
        end
        if live(c.CraftSource) and api.part(c.CraftSource) and (api.part(c.CraftSource).Position-ctx.root.Position).Magnitude>10 then
            if not Q.holdRoute(ctx)then return true end
            api.hover(ctx);ctx.root.CFrame=CFrame.new(api.part(c.CraftSource).Position+Vector3.new(0,2,0));return true
        end
        local ok,can=pcall(c.CanCraft,c,'BasicSentry')
        if not ok or not can then
            -- Only native scrap credit funds this recipe. Coins are a different balance.
            if (tonumber(s.questCraftState.ScrapCount) or 0)<(tonumber(entry.Price) or 0)then
                ctx.questNeedScrap=true;return S.shred(ctx,plan)
            end
            status('Turret recipe is not natively craftable at this source/level');return false
        end
        ctx.questNeedScrap=nil
        job={ctx=ctx,started=now(),source=c.CraftSource,class=plan.name,level=plan.level,objective=plan.objective,
            before=tonumber(s.questCraftState.CraftedCounts and s.questCraftState.CraftedCounts.BasicSentry) or 0};s.questCraftJob=job
        if not Q.call('craft','CraftingService','Craft',{'BasicSentry',c.CraftSource},function(ok,value,_,dispatch)
            job.rejected=dispatch=='not-sent' or ok and value==false
            if ok and type(value)=='table'then job.accepted=true;s.questCraftState=value;if type(c.ApplyState)=='function'then pcall(c.ApplyState,c,value)end end
        end,function()
            local current=Q.plan(s.classData,s.questCatalog,cfg.driveDepth)
            return Q.enabled(ctx) and s.questCraftJob==job and not api.extractionReady() and not Q.manual()
                and current.name==job.class and current.level==job.level and current.kind=='turret' and current.objective==job.objective
                and api.controller('CraftingController')==c and c.CraftSource==job.source and not c.PendingCraft
                and not calls.place and not S.blueprint(ctx) and c:CanCraft('BasicSentry')
        end)then s.questCraftJob=nil;return false end
        return true
    end
    function S.positionPreview(ctx,c,job)
        local regions=api.tagged('CraftPartRegion');local root=ctx.drill
        local attempts=job.pose or 0
        local candidate
        for _,part in ipairs(regions)do
            if live(part) and part:IsA('BasePart') and part:IsDescendantOf(root)then
                if c.Item and c.Item:GetAttribute('BackOfDrillOnly')==true then
                    local pivot=root:GetPivot()
                    if pivot:PointToObjectSpace(part.Position).Z>=0 then candidate=part;break end
                else candidate=part;break end
            end
        end
        if not candidate then
            for _,part in ipairs(root:GetDescendants())do
                if part.Name=='CraftPartRegion' and part:IsA('BasePart')then candidate=part;break end
            end
        end
        if not candidate then return false end
        job.pose=attempts+1
        local half=candidate.Size*.5
        local x=((attempts%3)-1)*math.max(0,half.X-3)
        local z=(math.floor(attempts/3)%3-1)*math.max(0,half.Z-3)
        local point=candidate.CFrame:PointToWorldSpace(Vector3.new(x,half.Y+3,z))
        local forward=candidate.CFrame.LookVector or Vector3.new(0,0,-1)
        api.hover(ctx);ctx.root.CFrame=CFrame.lookAt(point-forward*7,point)
        return true
    end
    function S.placement(ctx,plan)
        local c=api.controller('PlaceablePlacementController')
        local job=ctx.questPlacement
        if job and job.processingPlacement then return false end
        if job then
            local current=Q.plan(s.classData,s.questCatalog,cfg.driveDepth)
            local counter=current.name==job.class and count(current,'PlaceTurrets')>job.before
            local placed=not unmet(current,'PlaceTurrets') and job.accepted and live(job.item) and job.item:GetAttribute('Placed')==true
            if counter or placed then
                ctx.questPlacement=nil;ctx.questOwns=nil;ctx.questTurretKills=nil
                local token=calls.place
                if token and token.thread then
                    pcall(task.cancel,token.thread)
                    if coroutine.status(token.thread)=='dead' and calls.place==token then calls.place=nil end
                end
                s.questPlacedTurrets=s.questPlacedTurrets or setmetatable({}, {__mode='k'})
                if live(job.item)then s.questPlacedTurrets[job.item]=true end
                if S.fastPlacement(current)then
                    s.questTurretRestart={ctx=ctx,class=job.class,level=job.level,before=job.before}
                    status('Turret placement counter increased; preparing the starter-only lobby loop')
                else status('Placement quota reached; staying for turret kill credit')end
                return true
            end
            if job.sent then
                if job.rejected and (job.attempts or 0)<3 and c and c.Active and c.Item==job.item then
                    job.sent=nil;job.rejected=nil;job.retryAt=now()+3;c.ValidRegion=nil
                    ctx.questOwns=nil;return false
                end
                if job.rejected then
                    ctx.questOwns=nil;ctx.questPlacementRetry=now()+15;S.cancelPreview(ctx)
                    status('Native placement rejected repeatedly; cancelling the owned preview before another attempt');return false
                end
                if now()-job.issuedAt>=12 then ctx.questOwns=nil;status('Placement credit unconfirmed; mutation reserved, other work continues');return false end
                status('Awaiting native turret placement quest credit');return true
            end
            if not c or not c.Active or not live(c.Item) or c.Item:GetAttribute('CraftedPlaceable')~=true
                or c.Item:GetAttribute('PlacingUserId')~=api.Players.LocalPlayer.UserId then
                if now()-job.started>=15 then ctx.questOwns=nil;status('Blueprint start unconfirmed; the same tool is not started again');return false end
                status('Awaiting the native Blueprint StartPlacement state');return true
            end
            job.item=c.Item
            if now()<(job.retryAt or 0)then ctx.questOwns=nil;return false end
            if c.PendingRequest or c.PendingCancel or Q.manual()then return false end
            if not Q.holdRoute(ctx)then return true end
            if type(c.UpdatePreview)~='function'then ctx.questOwns=nil;return false end
            if c.ValidRegion and (not live(c.ValidRegion) or not c.ValidRegion:IsDescendantOf(ctx.drill))then
                c.ValidRegion=nil;c.PlacementOffset=nil
            end
            if not c.ValidRegion or not c.PlacementOffset then
                if job.pose and job.pose>=9 then
                    ctx.questOwns=nil;ctx.questPlacementRetry=now()+15;S.cancelPreview(ctx)
                    status('No collision-valid turret space; cancelled the owned preview before retrying');return false
                end
                S.positionPreview(ctx,c,job);pcall(c.UpdatePreview,c)
            end
            if not live(c.ValidRegion) or not c.PlacementOffset or not c.ValidRegion:IsDescendantOf(ctx.drill)then return true end
            local region,offset,item=c.ValidRegion,c.PlacementOffset,c.Item
            job.sent,job.issuedAt=true,now();job.attempts=(job.attempts or 0)+1
            if not Q.call('place','PlaceableService','Place',{region,offset},function(ok,value,_,dispatch)
                job.rejected=dispatch=='not-sent' or ok and value==false
                if job.pendingOwned and c.Item==item and (ok or dispatch=='not-sent')then
                    c.PendingRequest=false;job.pendingOwned=nil
                end
                if ok and value then
                    job.accepted=true
                    if c.Item==item and type(c.StopLocalPlacement)=='function'then pcall(c.StopLocalPlacement,c)end
                end
                s.questPollAt=0
            end,function()
                local allowed=Q.enabled(ctx) and ctx.questPlacement==job and not ctx.questPreviewCancel
                and api.controller('PlaceablePlacementController')==c and not api.extractionReady() and not Q.manual() and c.Active
                and c.Item==item and c.ValidRegion==region and c.PlacementOffset==offset
                and not c.PendingRequest and live(region) and region:IsDescendantOf(ctx.drill) and live(item)
                and item:GetAttribute('CraftedPlaceable')==true
                and item:GetAttribute('PlacingUserId')==api.Players.LocalPlayer.UserId
                if allowed then c.PendingRequest=true;job.pendingOwned=true end
                return allowed
            end)then job.sent=nil;return false end
            return true
        end
        if s.questCraftJob then return S.craft(ctx,plan)end
        if not c or c.Active or c.PendingRequest or c.PendingCancel or calls.place or calls.craft or calls.placementCancel or Q.manual() or s.questDelivery or s.bringDelivery or s.lootRequest
            or now()<(ctx.questPlacementRetry or 0)then return false end
        local tool=S.blueprint(ctx)
        if not tool then return S.craft(ctx,plan)end
        if not Q.holdRoute(ctx)then return true end
        Q.stopDrive(ctx);Q.drillSupport.stopMine(ctx);ctx.questCombat=nil;ctx.combatTarget=nil
        local active=api.equip(ctx,tool)
        if not active or type(active.BeginPlacement)~='function'then status('Turret quest waits for the owned Blueprint handler');return true end
        job={tool=tool,recipe=toolId(tool),class=plan.name,level=plan.level,before=count(plan,'PlaceTurrets'),started=now()};ctx.questPlacement=job
        pcall(active.BeginPlacement,active)
        status('Beginning native turret placement with the owned starter blueprint');return true
    end
    function S.turretKills(ctx,plan)
        local own={}
        for _,item in ipairs(api.tagged('SentryTurret'))do
            if live(item) and item:GetAttribute('Placed')==true and api.part(item)
                and (item:GetAttribute('OwnerUserId')==api.Players.LocalPlayer.UserId
                    or item:GetAttribute('PlacingUserId')==api.Players.LocalPlayer.UserId
                    or s.questPlacedTurrets and s.questPlacedTurrets[item])then own[#own+1]=item end
        end
        if #own==0 then return S.placement(ctx,plan)end
        ctx.questTurretKills=true;ctx.questCombat=nil;ctx.combatTarget=nil
        local target,turret,distance
        for _,item in ipairs(own)do
            local center=api.part(item).Position;local radius=tonumber(item:GetAttribute('ActiveDistance')) or 300
            for _,npc in ipairs(api.enemies())do
                local p=api.part(npc)
                if api.enemyAlive(npc) and api.questTargetAllowed(ctx,npc) and p and (p.Position-center).Magnitude<=radius then
                    local d=(p.Position-center).Magnitude
                    if not distance or d<distance then target,turret,distance=npc,item,d end
                end
            end
        end
        if not target then status('Turret quest: no enemy near the owned sentry; chest discovery continues');return false end
        local h=target:FindFirstChildOfClass('Humanoid');local monitor=ctx.questTurretMonitor
        if not monitor or monitor.target~=target or h and h.Health<monitor.health then
            monitor={target=target,health=h and h.Health or 0,started=now()};ctx.questTurretMonitor=monitor
        elseif now()-monitor.started>=10 then
            ctx.questTargetRetry=ctx.questTargetRetry or setmetatable({}, {__mode='k'})
            ctx.questTargetRetry[target]={untilAt=now()+10,health=h and h.Health or 0}
            ctx.questTurretMonitor=nil;ctx.questOwns=nil;ctx.combatTarget=nil
            status('Owned turret is not damaging this target; trying other loaded work');return false
        end
        ctx.combatTarget=target
        if not Q.holdRoute(ctx)then return true end
        Q.stopDrive(ctx);Q.drillSupport.stopMine(ctx);api.hover(ctx)
        local center=api.part(turret).Position;local range=tonumber(turret:GetAttribute('TargetRange')) or 100
        if distance>range*.8 and not ctx.questTurretLureUntil then
            ctx.root.CFrame=CFrame.new(api.part(target).Position+Vector3.new(0,2,5));ctx.questTurretLureUntil=now()+1
        elseif not ctx.questTurretLureUntil or now()>=ctx.questTurretLureUntil then
            ctx.root.CFrame=CFrame.new(center+Vector3.new(0,3,8));ctx.questTurretLureUntil=nil
        end
        api.watch(ctx);status('Letting the owned sentry earn turret kills; ordinary aura paused')
        return true
    end
    function S.root(item)
        local state=native('DungeonDoorState')
        if state and type(state.GetRoot)=='function'then
            local ok,root=pcall(state.GetRoot,item)
            if ok and live(root)then return root end
        end
    end
    function S.bound(ctx)
        if Q.drillSupport and not Q.drillSupport.inDungeon(ctx)then return nil end
        local c=api.controller('DungeonUIController');local root=c and c._BoundDungeon
        local old=ctx.questCampaignExit
        if old and old.root==root then return nil end
        return api.Players.LocalPlayer:GetAttribute('InDungeon')==true and live(root) and root or nil
    end
    function S.belongs(npc,root)
        if not live(npc) or not live(root)then return false end
        local session=root:GetAttribute('SessionDungeonId');local own=npc:GetAttribute('SessionDungeonId')
        if session~=nil and own~=nil then return own==session and npc:GetAttribute('DungeonWaveNpc')==true end
        local spider=root:GetAttribute('SpiderPitId');local npcSpider=npc:GetAttribute('SpiderPitId')
        if spider~=nil and npcSpider~=nil then return spider==npcSpider and npc:GetAttribute('DungeonWaveNpc')==true end
        return npc:IsDescendantOf(root)
    end
    function S.observe(ctx,root)
        if not ctx.connect then return end
        ctx.questCampaignRemotes=ctx.questCampaignRemotes or setmetatable({}, {__mode='k'})
        ctx.questCampaignScans=ctx.questCampaignScans or setmetatable({}, {__mode='k'})
        local nativeController=api.controller('DungeonUIController')
        local function protected(watched)
            if nativeController and nativeController._BoundDungeon==watched or ctx.nativeGateMotion then return true end
            for _,job in pairs({ctx.questCampaign,ctx.questCampaignDoor,ctx.questMineEntry,ctx.questDepthMine})do
                if job.root==watched or job.mine==watched or job.source==watched
                    or job.prompt and job.prompt:IsDescendantOf(watched)
                    or job.gate and job.gate:IsDescendantOf(watched)then return true end
            end
            return false
        end
        if now()>=(ctx.questCampaignListenerPruneAt or 0)then
            ctx.questCampaignListenerPruneAt=now()+1
            for watched,record in pairs(ctx.questCampaignScans)do
                if not live(watched) and not protected(watched)then
                    if record.added then pcall(function()record.added:Disconnect()end)end
                    for item,connection in pairs(record.connections or {})do
                        pcall(function()connection:Disconnect()end)
                        if ctx.questCampaignRemotes[item]==connection then ctx.questCampaignRemotes[item]=nil end
                    end
                    ctx.questCampaignScans[watched]=nil
                end
            end
        end
        if not root or not live(root) and not protected(root)then return end
        local scan=ctx.questCampaignScans[root]
        if not scan then scan={connections={}};ctx.questCampaignScans[root]=scan end
        local function bind(item)
            if ctx.questCampaignScans[root]~=scan then return end
            if item.Name=='DungeonDoorTransition' and item:IsA('RemoteEvent') and item.OnClientEvent
                and not ctx.questCampaignRemotes[item]then
                local connection
                connection=ctx.connect(item.OnClientEvent,function(mode)
                    if not ctx.active or ctx.questCampaignRemotes[item]~=connection then return end
                    if mode=='Enter'then ctx.questCampaignExit=nil
                    elseif mode=='Exit' and (S.bound(ctx)==root or ctx.questCampaign and ctx.questCampaign.root==root)then
                        local controller=api.controller('DungeonUIController')
                        local current=controller and controller._BoundDungeon
                        if live(current) and current~=root then return end
                        ctx.questCampaignExit={root=root};ctx.questCampaign=nil;ctx.questOwns=nil
                        ctx.questCombat=nil;ctx.questExitCombat=nil;ctx.combatTarget=nil
                    end
                end)
                ctx.questCampaignRemotes[item]=connection;scan.connections[item]=connection
            end
        end
        if not scan.added and root.DescendantAdded then scan.added=ctx.connect(root.DescendantAdded,bind)end
        if now()<(scan.nextAt or 0)then return end
        scan.nextAt=now()+2
        for _,item in ipairs(root:GetDescendants())do bind(item)end
    end
    local function ready(prompt)
        local module=native('DungeonDoorState')
        return live(prompt) and prompt:IsA('ProximityPrompt') and prompt.Enabled~=false
            and prompt:GetAttribute('DungeonDoorReady')==true and prompt:GetAttribute('DungeonDoorAvailable')==true
            and module and type(module.CanUsePlayer)=='function' and module.CanUsePlayer(api.Players.LocalPlayer)
    end
    function S.unbound(ctx)
        local player=api.Players.LocalPlayer
        if player:GetAttribute('InDungeon')~=true or ctx.questCampaignExit
            or S.bound(ctx) or Q.drillSupport.activeMine(ctx)then
            ctx.questUnboundDungeon=nil;return false
        end
        if not Q.enabled(ctx)then ctx.questUnboundDungeon=nil;return true,false end
        local key=table.concat({tostring(player:GetAttribute('ActiveDungeonWaveRoomId')),
            tostring(player:GetAttribute('ActiveSpiderPitId')),tostring(player:GetAttribute('ActiveDungeonQueueId'))},':')
        local waiting=ctx.questUnboundDungeon
        if not waiting or waiting.key~=key then
            waiting={key=key,started=now(),attempts=0};ctx.questUnboundDungeon=waiting
        end
        local controller=api.controller('DungeonUIController')
        if controller and type(controller.TryBindActiveDungeon)=='function' and now()>=(waiting.nextAt or 0)then
            waiting.nextAt=now()+2;waiting.attempts=waiting.attempts+1
            pcall(controller.TryBindActiveDungeon,controller)
        end
        if S.bound(ctx) or Q.drillSupport.activeMine(ctx)then ctx.questUnboundDungeon=nil;return false end
        if now()-waiting.started>=30 then
            -- Binding is a native read, not an exit. After its bounded retry
            -- window, let the existing real SaveGear flow try the church;
            -- never clear InDungeon, queue membership or award quest credit.
            Q.abortResources(ctx);Q.stopDrive(ctx);Q.drillSupport.stopMine(ctx)
            if ctx.questCampaign and ctx.questCampaign.moving then
                ctx.nativeGateMotion=nil;ctx.root.AssemblyLinearVelocity=Vector3.zero
                if type(ctx.humanoid.MoveTo)=='function'then ctx.humanoid:MoveTo(ctx.root.Position)end
            end
            ctx.questCampaign=nil;ctx.questCampaignDoor=nil;ctx.questOwns=nil
            ctx.questCombat=nil;ctx.questExitCombat=nil;ctx.questThreat=nil;ctx.combatTarget=nil
            ctx.questCampaignChurch=true
            s.questChurchExit=s.questChurchExit or {reason='Native dungeon room binding unavailable for 30 seconds; trying the church save route',requestedAt=now()}
            status('Native dungeon binding unconfirmed after '..waiting.attempts..' attempts; handing off to the church save route')
            return true,false
        end
        Q.holdRoute(ctx);api.watch(ctx);status('Dungeon state is active; waiting for its loaded native root before moving')
        return true,true
    end
    function S.dungeon(ctx,plan,forceExit)
        if forceExit and ctx.questCampaignChurch then return false end
        if api.Players.LocalPlayer:GetAttribute('InDungeon')~=true then ctx.questUnboundDungeon=nil end
        local root=S.bound(ctx)
        local job=ctx.questCampaign
        if root then
            ctx.questUnboundDungeon=nil
            S.observe(ctx,root)
            if not job or job.root~=root then job={root=root,started=now(),entered=true};ctx.questCampaign=job end
            if job.moving then ctx.nativeGateMotion=nil;ctx.root.AssemblyLinearVelocity=Vector3.zero;job.moving=nil end
            job.entered=true
            if forceExit and now()-job.started>=30 then
                ctx.questCampaign=nil;ctx.questOwns=nil;ctx.questCombat=nil;ctx.combatTarget=nil
                ctx.questCampaignChurch=true;return false
            end
            if not Q.holdRoute(ctx)then return true end
            local target,score
            for _,npc in ipairs(api.enemies())do
                if api.enemyAlive(npc) and S.belongs(npc,root) and Q.targetResponsive(ctx,npc)then
                    local h=npc:FindFirstChildOfClass('Humanoid');local p=api.part(npc)
                    if h and p then
                        local urgent=api.tag(npc,'Watcher') or tostring(npc:GetAttribute('RealName') or npc.Name):lower():find('blinker',1,true)
                        local value=(urgent and -1e9 or 0)+h.Health
                        if not score or value<score then target,score=npc,value end
                    end
                end
            end
            if target then
                if ctx.questCampaignDoor and now()<ctx.questCampaignDoor.untilAt then ctx.questCampaignDoor=nil end
                ctx.questExitCombat=forceExit==true
                if not api.swordTargetAllowed(target)then ctx.questThreat=target else ctx.questThreat=nil end
                return Q.combatWork(ctx,{kind='combat',name=plan.name,level=plan.level,counts=plan.counts,unmet=plan.unmet,
                    objective='EnemyKills',weaponClass='Sword'},target)
            end
            ctx.questCombat=nil;ctx.combatTarget=nil;api.watch(ctx)
            if not forceExit and Q.chestTurn(ctx,plan)then return true end
            local exit=root:FindFirstChild('DungeonExitPrompt',true) or root:FindFirstChild('ExitPrompt',true)
            local pending=ctx.questCampaignDoor
            if pending then
                if now()<pending.untilAt then status('Awaiting the native dungeon exit transition');return true end
                ctx.questCampaignDoor=nil;ctx.questCampaignRetry=now()+30
            end
            if ready(exit) and now()>=(ctx.questCampaignRetry or 0)then
                ctx.questCampaignDoor={prompt=exit,untilAt=now()+10};ctx.questCampaignRetry=now()+30
                api.fireMiningPrompt(ctx,exit);return true
            end
            status('Dungeon campaign: watching for its next native wave or enabled exit');return true
        end
        if ctx.questCampaignChurch then return false end
        if job and job.entered then ctx.questCampaign=nil;ctx.questCampaignDoor=nil;ctx.questOwns=nil;job=nil end
        if api.Players.LocalPlayer:GetAttribute('InDungeon')==true and not ctx.questCampaignExit then
            local missing,holding=S.unbound(ctx)
            if missing then return holding end
            if S.bound(ctx)then return S.dungeon(ctx,plan,forceExit)end
        end
        if forceExit then return false end
        if job then
            if job.queue and job.moving then
                local point=ctx.root.CFrame.Position or ctx.root.Position
                local delta=job.finish-point
                if delta.Magnitude<=1 or now()-job.started>=3 then
                    ctx.nativeGateMotion=nil;ctx.root.AssemblyLinearVelocity=Vector3.zero;job.moving=nil
                    if type(ctx.humanoid.MoveTo)=='function'then ctx.humanoid:MoveTo(point)end
                else ctx.root.AssemblyLinearVelocity=delta.Unit*12 end
            end
            if job.queue and api.Players.LocalPlayer:GetAttribute('ActiveDungeonQueueId')==job.queueId then
                local ends=tonumber(job.queue:GetAttribute('CountdownEndsAt'))
                if finite(ends) and job.countdownEnds~=ends and type(workspace.GetServerTimeNow)=='function'then
                    job.countdownEnds=ends;job.untilAt=now()+math.max(0,ends-workspace:GetServerTimeNow())+10
                elseif not job.joined then job.untilAt=now()+45 end
                job.joined=true
            end
            if now()<(job.untilAt or job.started+15)then Q.holdRoute(ctx);api.watch(ctx);status('Awaiting native dungeon entry / queue receipt');return true end
            if job.queue then ctx.nativeGateMotion=nil;ctx.root.AssemblyLinearVelocity=Vector3.zero end
            ctx.questCampaign=nil;ctx.questOwns=nil
            ctx.questCampaignRetries=ctx.questCampaignRetries or setmetatable({}, {__mode='k'})
            ctx.questCampaignRetries[job.prompt or job.queue]=now()+30
        end
        local best,score,selectedRoot
        local ring=unmet(plan,'CompleteGoblinRing') or unmet(plan,'GoblinLordKills')
        for _,door in ipairs(api.tagged('DungeonDoor'))do
            local candidate=S.root(door)
            if candidate then
                local prompt=door:FindFirstChildWhichIsA('ProximityPrompt',true)
                local wave=candidate:FindFirstChild('Wave');local id=wave and wave:GetAttribute('WaveId') or candidate.Name
                local goblin=tostring(id):lower():gsub('[^%w]',''):find('goblinring',1,true)~=nil
                local module=native('DungeonDoorState')
                if (not ring or goblin) and ready(prompt) and prompt.Name~='DungeonExitPrompt' and prompt.Name~='ExitPrompt'
                    and not(module.IsCompleted and module.IsCompleted(candidate))
                    and now()>=((ctx.questCampaignRetries or {})[prompt] or 0)then
                    local p=api.position(prompt)
                    if p then
                        local value=(p-ctx.root.Position).Magnitude+(goblin and 0 or 10000)
                        if not score or value<score then best,score,selectedRoot=prompt,value,candidate end
                    end
                end
            end
        end
        if not best then
            for _,spot in ipairs(api.tagged('DungeonQueueSpot'))do
                local candidate=S.root(spot)
                local state=spot:GetAttribute('QueueState');local id=spot:GetAttribute('QueueId')
                local wave=candidate and candidate:FindFirstChild('Wave')
                local kind=wave and wave:GetAttribute('WaveId') or candidate and candidate.Name or ''
                local goblin=tostring(kind):lower():gsub('[^%w]',''):find('goblinring',1,true)~=nil
                local module=native('DungeonDoorState')
                if candidate and spot:IsA('BasePart') and spot.CanTouch==true and ctx.root.CanTouch~=false
                    and type(id)=='string' and id~='' and (state=='Idle' or state=='Countdown') and (not ring or goblin)
                    and module and module.CanUsePlayer(api.Players.LocalPlayer) and not module.IsCompleted(candidate)
                    and now()>=((ctx.questCampaignRetries or {})[spot] or 0)then
                    if not Q.holdRoute(ctx)then return true end
                    Q.stopDrive(ctx);Q.drillSupport.stopMine(ctx);S.observe(ctx,candidate)
                    -- Queue UI binds through actual InDungeon/ActiveDungeonQueueId
                    -- changes. There is no client JoinQueue remote to fabricate.
                    local direction=spot.CFrame.LookVector or Vector3.new(0,0,-1)
                    local finish=spot.Position
                    local begin=finish-direction*(spot.Size.Z*.5+3)
                    ctx.questCampaign={root=candidate,queue=spot,queueId=id,started=now(),finish=finish,moving=true}
                    ctx.nativeGateMotion=true;api.hover(ctx);ctx.root.CFrame=CFrame.new(begin)
                    ctx.root.AssemblyLinearVelocity=direction*12
                    if type(ctx.humanoid.MoveTo)=='function'then ctx.humanoid:MoveTo(finish)end
                    status('Approaching the native dungeon queue; waiting for real queue membership');return true
                end
            end
        end
        if not best then status('Goblin campaign: seeking a loaded, ready dungeon entrance; chest discovery continues');return false end
        if not Q.holdRoute(ctx)then return ctx.questOwns==true end
        Q.stopDrive(ctx);Q.drillSupport.stopMine(ctx);S.observe(ctx,selectedRoot)
        ctx.questCampaign={root=selectedRoot,prompt=best,started=now()};ctx.questCampaignExit=nil
        if not api.fireMiningPrompt(ctx,best)then ctx.questCampaign=nil;ctx.questOwns=nil;return false end
        return true
    end
    function S.cancelPreview(ctx)
        local job=ctx.questPreviewCancel or ctx.questPlacement
        if job then
            local c=api.controller('PlaceablePlacementController');local item=c and c.Item
            local own=c and c.Active and live(item) and item:GetAttribute('PlacingUserId')==api.Players.LocalPlayer.UserId
                and toolId(item)==job.recipe and (not job.item or job.item==item)
            ctx.questPlacement=nil
            if not own then ctx.questPreviewCancel=nil;return end
            ctx.questPreviewCancel=job
            if job.cancelAt and now()-job.cancelAt>=12 then
                -- A local preview is reversible; unknown server mutations remain
                -- reserved. A missing cancellation reply cannot park every worker.
                if type(c.StopLocalPlacement)=='function'then pcall(c.StopLocalPlacement,c)end
                ctx.questPreviewCancel=nil;ctx.questOwns=nil;return
            end
            if not job.cancelRequested and not c.PendingCancel and not calls.placementCancel then
                job.cancelRequested=true;job.cancelAt=now()
                local issued=Q.call('placementCancel','PlaceableService','CancelPlacement',{},function(ok,value,_,dispatch)
                    if job.cancelPendingOwned and c.Item==item then c.PendingCancel=false;job.cancelPendingOwned=nil end
                    if dispatch=='not-sent'then job.cancelRequested=nil;job.cancelAt=nil;return end
                    -- Native CancelPlacement stops its local preview on both
                    -- fulfilled and rejected promises, including a pending Place.
                    if c.Item==item and type(c.StopLocalPlacement)=='function'then pcall(c.StopLocalPlacement,c)end
                    if ctx.questPreviewCancel==job then ctx.questPreviewCancel=nil end
                end,function()
                    if api.owned() and ctx.questPreviewCancel==job and api.controller('PlaceablePlacementController')==c
                        and c.Active and c.Item==item and not c.PendingCancel then
                        c.PendingCancel=true;job.cancelPendingOwned=true;return true
                    end
                    return false
                end)
                if not issued then job.cancelRequested=nil;job.cancelAt=nil end
            end
        end
        -- Place/Craft replies stay reserved. Cleanup cannot prove an unacknowledged
        -- consuming mutation failed, and must not permit a duplicate blueprint.
    end
    function S.cleanup(ctx)
        ctx.questTurretKills=nil
        ctx.questUnboundDungeon=nil
        if ctx.questCampaign and ctx.questCampaign.moving then
            ctx.nativeGateMotion=nil;ctx.root.AssemblyLinearVelocity=Vector3.zero;ctx.questCampaign.moving=nil
        end
        if not api.extractionReady()then ctx.questCampaignChurch=nil end
        S.cancelPreview(ctx)
    end
    return S
end

end)()
    local buildQuestRewards = (function()
-- Claim only completed native daily quests. No reroll, purchase or invented credit.
return function(api,Q)
    local R,s,now={},api.state,api.now
    local function finite(v)return type(v)=='number' and v==v and math.abs(v)<math.huge end
    local function fingerprint(entry)return tostring(entry.Objective)..':'..tostring(entry.Amount)end
    s.dailyRewardLedger=s.dailyRewardLedger or {}
    function R.observe(data)
        if not api.owned() or type(data)~='table' or type(data.Quests)~='table'then return end
        s.dailyQuestData=data;s.dailyQuestAt=now();s.dailyQuestVersion=(s.dailyQuestVersion or 0)+1
        for tier,entry in pairs(data.Quests)do
            local record=s.dailyRewardLedger[tier]
            if record and type(entry)=='table'then
                local progress,amount=tonumber(entry.Progress),tonumber(entry.Amount)
                if entry.Claimed==true and fingerprint(entry)==record.fingerprint and not record.confirmed then
                    record.confirmed=true;s.stats.dailyQuestClaims=(s.stats.dailyQuestClaims or 0)+1
                elseif entry.Claimed~=true and finite(progress) and finite(amount) and amount>0
                    and (fingerprint(entry)~=record.fingerprint or progress<amount and record.confirmed)then
                    -- An observed new/incomplete quest re-arms the tier. Merely
                    -- receiving another unclaimed complete snapshot never does.
                    s.dailyRewardLedger[tier]=nil
                end
            end
        end
    end
    local function allowed(ctx)
        return api.owned() and ctx.active and s.farm==ctx and ctx.humanoid.Health>0
            and not s.teleporting and not s.request and not s.awaiting and not s.departureAt
            and not workspace:GetAttribute('InCutScene') and not workspace:GetAttribute('InfiniteRebasing')
    end
    function R.step(ctx)
        Q.poll() -- Read cancellation also runs with class quests OFF.
        if not allowed(ctx)then return end
        local catalog=api.sharedModule and api.sharedModule('QuestData')
        if not catalog or type(catalog.DailyReward)~='table'then return end
        if ctx.dailyRewardBound~=true and api.event and ctx.connect then
            local signal=api.event('QuestService','UpdateQuests')
            if signal then ctx.dailyRewardBound=true;ctx.connect(signal,function(data)R.observe(data)end)end
        end
        if now()>=(s.dailyQuestReadAt or 0) and not Q.calls.dailyQuestRead then
            local version=s.dailyQuestVersion or 0
            if Q.call('dailyQuestRead','QuestService','FetchQuests',{},function(ok,data)
                if ok and (s.dailyQuestVersion or 0)==version then R.observe(data)end
            end,function()return allowed(ctx)end)then s.dailyQuestReadAt=now()+20 end
        end
        local pending=Q.calls.dailyQuestClaim;local record=s.dailyClaimRecord
        if pending and record and record.confirmed and pending.thread then
            -- A native Claimed receipt resolves this exact mutation. Terminate
            -- the old client waiter before permitting the next different tier.
            pcall(task.cancel,pending.thread)
            if coroutine.status(pending.thread)=='dead' and Q.calls.dailyQuestClaim==pending then Q.calls.dailyQuestClaim=nil end
        end
        if Q.calls.dailyQuestClaim or not s.dailyQuestData or now()-(s.dailyQuestAt or 0)>30 then return end
        for _,tier in ipairs({'Hard','Medium','Easy'})do
            local entry=s.dailyQuestData.Quests[tier];local previous=s.dailyRewardLedger[tier]
            local progress=type(entry)=='table' and tonumber(entry.Progress)
            local amount=type(entry)=='table' and tonumber(entry.Amount)
            if catalog.DailyReward[tier] and finite(progress) and finite(amount) and amount>0
                and progress>=amount and entry.Claimed~=true and not (previous and previous.sent)
                and now()>=(previous and previous.retryAt or 0)then
                record={tier=tier,fingerprint=fingerprint(entry),sent=true};s.dailyRewardLedger[tier]=record;s.dailyClaimRecord=record
                local version=s.dailyQuestVersion or 0
                local issued=Q.call('dailyQuestClaim','QuestService','ClaimQuestReward',{tier},function(ok,data,_,dispatch)
                    if dispatch=='not-sent' or ok and data==false then record.sent=nil;record.retryAt=now()+30 end
                    if ok and (s.dailyQuestVersion or 0)==version then R.observe(data)end
                    s.dailyQuestReadAt=math.min(s.dailyQuestReadAt or 0,now()+2)
                end,function()
                    local current=s.dailyQuestData and s.dailyQuestData.Quests[tier]
                    return allowed(ctx) and current==entry and current.Claimed~=true and fingerprint(current)==record.fingerprint
                end)
                if not issued then record.sent=nil;record.retryAt=now()+3 end
                return
            end
        end
    end
    return R
end

end)()
    local buildQuestInventory = (function()
-- Class starter toolbar cleanup uses the native item-specific drop and real inventory receipts.
return function(api,Q)
    local I,s,cfg,now={},api.state,api.state.config,api.now
    local blocked=s.questInventoryBlocked or setmetatable({}, {__mode='k'});s.questInventoryBlocked=blocked
    local cached,starters
    local shared={ItemBag=true,Money_Sack=true,Large_Sack=true,Pickaxe_Wooden=true,Sword_Wooden=true,
        Pickaxe_Rusty=true,Sword_Rusty=true,Sword_Steel=true,Revolver=true,RPG=true}
    local exact={CutlassKills='Sword_Pirate',FlintlockKills='Flintlock',UseSpeedPotion='SpeedPotion',
        UseStrengthPotion='StrengthPotion',UseInvisibilityPotion='InvisibilityPotion',UseReviveKit='ReviveKit',
        BlessTeammates='Staff_Priest',ConsumeCorpses='VampirePendant',MeleeLifestealHealing='VampirePendant'}
    local turrets={BasicSentry=true,AdvancedSentry=true,Flamethrower=true,Frostthrower=true}
    local function finite(v)return type(v)=='number' and v==v and math.abs(v)<math.huge end
    function I.catalog()
        local catalog=s.questCatalog or api.sharedModule and api.sharedModule('ClassCatalog')
        if type(catalog)~='table'then return end
        if catalog~=cached then
            cached,starters=catalog,{}
            local function add(value)
                if type(value)=='string'then starters[value]=true
                elseif type(value)=='table'then for _,entry in pairs(value)do add(entry)end end
            end
            for _,entry in pairs(catalog)do if type(entry)=='table'then add(entry.StarterTools)end end
        end
        return catalog,starters
    end
    local function owned(ctx,tool)
        local backpack=api.Players.LocalPlayer:FindFirstChild('Backpack')
        return tool and tool.Parent and tool:IsA('Tool') and (tool.Parent==ctx.character or tool.Parent==backpack)
    end
    local function sameTool(a,b)return a==b or a and b and api.id(a)==api.id(b)end
    local function currentPlan(plan)
        if not cfg.classQuest then return plan end
        local catalog=I.catalog();local data=s.classData
        if type(data)~='table'then return end
        local name=data.SelectedClass
        local progress=type(data.ClassProgress)=='table' and data.ClassProgress[name]
        if not catalog or not name or type(data.ClassProgress)~='table'
            or type(catalog[name])~='table' or type(catalog[name].Requirements)~='table'then return end
        if progress~=nil and (type(progress)~='table' or not finite(progress.Level)
            or progress.Level<1 or progress.Level%1~=0 or progress.Objectives~=nil and type(progress.Objectives)~='table')then return end
        -- Q.plan owns the native initial Level1 rule and requires explicit
        -- OwnedClasses membership before a missing first progress entry is valid.
        local current=Q.plan(data,catalog,cfg.driveDepth)
        return current.name==name and current.kind~='waiting' and current or nil
    end
    local function loadedPickaxeThreat(ctx)
        local mine=Q.drillSupport.activeMine(ctx);local campaign=not mine and Q.special.bound(ctx)
        for _,npc in ipairs(api.enemies())do
            local p=api.part(npc);local name=tostring(npc:GetAttribute('RealName') or npc.Name):lower()
            local leech=api.isFuelLeech and api.isFuelLeech(npc)
            local urgent=leech or name:find('watcher',1,true) or name:find('blinker',1,true)
                or api.tag(npc,'Watcher') or mine and not api.swordTargetAllowed(npc)
            local belongs=not mine and not campaign or mine and Q.drillSupport.mineEnemy(npc,mine)
                or campaign and Q.special.belongs(npc,campaign)
            if p and urgent and belongs and (not api.enemyAlive or api.enemyAlive(npc))
                and not api.swordTargetAllowed(npc) and (p.Position-ctx.root.Position).Magnitude<=(leech and 600 or 400)then
                local ancestor=npc.Parent;local current=true
                while ancestor and ancestor~=workspace do
                    if ancestor.Name=='Drill' and ancestor~=ctx.drill then current=false;break end
                    ancestor=ancestor.Parent
                end
                if current then return true end
            end
        end
        return false
    end
    local function neededTool(ctx,tool,plan)
        local id=api.id(tool);local unmet={}
        for _,goal in ipairs(plan.unmet or {})do unmet[goal.key]=true end
        for key,wanted in pairs(exact)do if unmet[key] and id==wanted then return true end end
        if (turrets[id] or id=='Blueprint') and (unmet.PlaceTurrets or unmet.TurretKills)then return true end
        local placement=ctx.questPlacement or s.questFurnacePlacement
        if placement and placement.processingPlacement and placement.tool==tool
            and (now()-(placement.started or now())<12 or placement.token and Q.calls.place==placement.token)then return true end
        local class=api.attr(tool,'Class')
        if Q.healing and Q.healing.isMedical(tool)then return true end
        local preferred=Q.preferred and Q.preferred(ctx)
        if sameTool(preferred,tool)then return true end
        local pick=false;local sword=false;local guns={}
        for key in pairs(unmet)do
            if key:find('Mine',1,true)==1 or key=='SmeltIron' or key=='SmeltGold' or key=='ContributeFuel'
                or key=='TotalDepth' and cfg.driveDepth then pick=true end
            if Q.capabilities.melee[key] or key=='CompleteDungeon' or key=='CompleteGoblinRing' or key=='GoblinLordKills'then sword=true end
            local gun=Q.capabilities.guns[key]
            if gun then
                if type(gun)=='string' and gun~='Gun'then guns[gun]=true
                else guns.Revolver,guns.Rifle,guns.Shotgun=true,true,true end
            end
        end
        if Q.refuelActive and Q.refuelActive(ctx)then pick=true end
        if class=='Pickaxe' and (ctx.questDepthMine and ctx.questDepthMine.class==(s.classData and s.classData.SelectedClass)
            or ctx.questMining or loadedPickaxeThreat(ctx))then pick=true end
        local threat=ctx.questThreat
        if threat and threat.Parent and (not api.enemyAlive or api.enemyAlive(threat))
            and (api.isFuelLeech and api.isFuelLeech(threat) or not api.swordTargetAllowed(threat))then pick=true end
        if class=='Pickaxe' and pick then
            local best=api.findOwned(ctx,'Pickaxe_Void') or api.findTool(ctx,'Pickaxe')
            return not best or sameTool(best,tool) or not owned(ctx,tool) and api.useful(ctx,tool)
        end
        if class=='Sword' and sword then
            local best=api.findOwned(ctx,'Sword_Void') or api.findTool(ctx,'Sword')
            return not best or sameTool(best,tool) or not owned(ctx,tool) and api.useful(ctx,tool)
        end
        if guns[class]then
            local best=api.findTool(ctx,class);return not best or sameTool(best,tool) or not owned(ctx,tool) and api.useful(ctx,tool)
        end
        if (id=='RPG' or id=='Cannon') and unmet.ExplosiveDamage then return true end
        return false
    end
    function I.needed(ctx,tool,plan)
        if not cfg.classQuest then return false end
        plan=currentPlan(plan);return not plan or neededTool(ctx,tool,plan)
    end
    local function classOnly(tool)
        local _,ids=I.catalog();if not ids or not tool then return false end
        local id=api.id(tool)
        if not(ids[id] or id=='Blueprint') or shared[id] or tostring(id):lower():find('void',1,true)
            or api.attr(tool,'Class')=='ItemBag' then return false end
        -- The same native medkit ID is used by Healer starters and purchased supplies.
        -- No exported provenance distinguishes them, so useful medicine is retained.
        if Q.healing and Q.healing.isMedical(tool) or api.attr(tool,'Class')=='ReviveKit' or id=='ReviveKit'then return false end
        return true
    end
    function I.allowPickup(ctx,item)
        if not ctx or not classOnly(item)then return true end
        return I.needed(ctx,item)
    end
    local function standingRejectedReady(ctx,record)
        local at=now();local player=api.Players.LocalPlayer
        local drill=record.drill
        local driver=drill and drill:GetAttribute('DriverUserId')
        return record.standingRetry==true and record.character==ctx.character and finite(record.count)
            and record.count>=1 and record.count%1==0 and finite(record.started) and finite(record.settledAt)
            and finite(at) and at>=record.started and at>=record.settledAt
            and not ctx.questDriving and not ctx.questSeating and not ctx.humanoid.SeatPart and not ctx.humanoid.Sit
            and drill and drill.Parent and drill==ctx.drill and drill==workspace:FindFirstChild('Drill')
            and (driver==nil or finite(driver) and driver>=0 and driver%1==0) and driver~=player.UserId
    end
    local function saleCandidate(ctx,tool)
        local D=Q.drillSupport
        if not cfg.classQuest or ctx.questHealing or ctx.questDriving or ctx.questSeating
            or s.questCashJob and s.questCashJob.movementHeld or Q.moneyTarget(ctx)
            or ctx.humanoid.SeatPart or ctx.humanoid.Sit or not D.carriedSaleEligible(tool,ctx)then return false end
        local seller=Q.bestSeller(ctx,ctx.root.Position)
        return seller and D.accessible(seller) or false
    end
    local function processingCandidate(ctx,tool)
        local M=Q.drillSupport.processing
        return cfg.classQuest and not ctx.questHealing and not ctx.questDriving and not ctx.questSeating
            and not ctx.humanoid.SeatPart and not ctx.humanoid.Sit and M and M.carriedOre(tool,ctx)
            and M.findProcessor(ctx,ctx.root.Position)~=nil
    end
    function I.candidate(ctx,tool,plan)
        if not owned(ctx,tool) or not (classOnly(tool) or saleCandidate(ctx,tool) or processingCandidate(ctx,tool))then return false end
        local placement=ctx.questPlacement or s.questFurnacePlacement
        if placement and placement.processingPlacement and placement.tool==tool
            and placement.token and Q.calls.place==placement.token then return false end
        local count=api.stackCount(tool)
        local record=blocked[tool];local limit=type(record)=='table' and record.count or record
        if record and (not finite(limit) or limit<1 or limit%1~=0)then return false end
        if limit and count>=limit and (type(record)~='table' or count~=limit or not standingRejectedReady(ctx,record))then return false end
        return not I.needed(ctx,tool,plan)
    end
    local function passiveDriving(ctx,tool)
        local player=api.Players.LocalPlayer;local drill=ctx.drill
        local seat=ctx.humanoid.SeatPart
        local lease=s.questDriveLease;local seating=ctx.questSeating
        local drop=Q.calls.inventoryDrop;local job=s.questInventoryDrop
        local hotbar=api.controller('HotbarController');local ui=hotbar and hotbar.BackpackUI
        local visible=ui and ui.Parent and ui.Visible==true
        -- TrainComponent hides the toolbar for its native Drill presentation.
        -- This item-specific Backpack drop does not select equipment; accept
        -- only that exact hidden reason, never a frame/manual/cutscene hide.
        if not visible and ui and ui.Parent and ui.Visible==false
            and type(hotbar.HiddenReasons)=='table' and rawget(hotbar.HiddenReasons,'Drill')==true then
            visible=true
            for reason in pairs(hotbar.HiddenReasons)do if reason~='Drill'then visible=false;break end end
        end
        -- Q.drive retains its finite seating start time after native driving is
        -- confirmed. Only that exact confirmed lease is a passive driver, not
        -- a new or unresolved seating/start-stop handoff.
        if not ctx.questDriving or not lease or lease.ctx~=ctx or lease.drill~=drill
            or lease.confirmed~=true or lease.abandoned
            or seating~=nil and (not finite(seating) or seating>now()) or not drill or not drill.Parent
            or drill~=workspace:FindFirstChild('Drill') or drill:GetAttribute('DriverUserId')~=player.UserId
            or not visible
            or seat and not seat:IsDescendantOf(drill) or Q.calls.drive
            or Q.calls.drag or Q.calls.shop or Q.calls.place or Q.calls.placementCancel
            or Q.calls.medicalDrop or drop and (not tool or not job or job.ctx~=ctx or job.tool~=tool
                or not drop.args or drop.args[1]~=tool)then return false end
        if not tool then return true end -- Read-only candidate selection follows.
        if not tool:IsA('Tool') or tool.Parent~=player:FindFirstChild('Backpack')then return false end
        local receipt=s.equipRecords and s.equipRecords[tool]
        if receipt and (receipt.pending or receipt.uncertain or receipt.accepted)then return false end
        local native=api.controller('ToolController');local active=native and native.ActiveTool
        local name=api.id(tool)
        if active and not active._Destroyed and (active.DisplayTool==tool or active.Tool==tool
            or active.Tool and (api.id(active.Tool)==name or active.Tool.Name==name
                or active.Tool.Name==name..tostring(player.UserId)))then return false end
        return true
    end
    local function ready(ctx,tool)
        local player=api.Players.LocalPlayer
        local placement=ctx and ctx.questPlacement
        local passivePlacement=placement and placement.processingPlacement and placement.background and placement.localPreviewStopped
        local hotbar=api.controller('HotbarController');local nativePlacement=api.controller('PlaceablePlacementController')
        local equipping=false
        for _,record in pairs(s.equipRecords or {})do if record.pending then equipping=true;break end end
        return api.owned() and ctx and ctx.active and s.farm==ctx and player.Character==ctx.character
            and ctx.humanoid.Health>0 and not s.teleporting and not s.request and not s.awaiting and not s.departureAt
            and not player.GameplayPaused and not workspace:GetAttribute('InCutScene') and not workspace:GetAttribute('InfiniteRebasing')
            and not api.extractionReady() and not Q.manual() and not (hotbar and hotbar.IsDraggingHotbarItem)
            and not(nativePlacement and nativePlacement.Active) and not(placement and not passivePlacement)
            and not ctx.questPreviewCancel and not ctx.questPotionUsing and not ctx.questHealAttempt
            and not ctx.questStartup and not ctx.questRecovering and not ctx.questRecoveryDue
            and not ctx.currentChest and not ctx.featureHold and not ctx.questMineEntry and not ctx.nativeGateMotion
            and (not ctx.questDriving and not ctx.questSeating and not ctx.humanoid.SeatPart and not ctx.humanoid.Sit
                or passiveDriving(ctx,tool)) and not Q.calls.drive
            and not equipping and not ctx.bringEquipmentLock and not s.bringDelivery and not s.questDelivery and not s.lootRequest and not s.equipmentRequest
            and not s.rareShardDrop and not s.questMedicalDrop and not Q.calls.medicalDrop
    end
    function I.observe(ctx)
        local job=s.questInventoryDrop;if not job then return false end
        local sameLife=api.Players.LocalPlayer.Character==job.character and job.ctx.humanoid.Health>0
        local remains=job.tool.Parent and (job.tool.Parent==job.character or job.tool.Parent==job.backpack)
        local count=remains and api.stackCount(job.tool) or 0
        if sameLife and job.token and job.token.called and (not remains or count<job.count)then
            if Q.retireConfirmedCall('inventoryDrop',job.token)then
                s.questInventoryDrop=nil;return false
            end
            return false
        end
        if job.notSent then s.questInventoryDrop=nil;return false end
        if job.settled and (not sameLife or now()-job.started>=5 and now()-(job.settledAt or job.started)>=1.5)then
            if sameLife and job.passiveDriving and job.rejected then
                blocked[job.tool]={count=job.count,character=job.character,drill=job.drill,
                    started=job.started,settledAt=job.settledAt,standingRetry=true}
            else
                blocked[job.tool]=job.count
            end
            s.questInventoryDrop=nil;return false
        end
        if now()-job.started>=1.5 then return false end
        -- Item-specific Backpack cleanup owns no driver, movement or active
        -- handler lease. A pending reply must not defer forward input/defense.
        return not job.passiveDriving and job.ctx==ctx and sameLife
    end
    function I.step(ctx,plan)
        local held=I.observe(ctx)
        if s.questInventoryDrop or Q.calls.inventoryDrop then return held end
        if not ready(ctx) or not I.catalog()then return false end
        if cfg.classQuest and not currentPlan(plan)then return false end
        local target,score;local searched=false
        for _,tool in ipairs(api.ownedTools(ctx))do
            if cfg.classQuest and not ctx.questHealing and not ctx.questDriving and not ctx.questSeating
                and not ctx.humanoid.SeatPart and not ctx.humanoid.Sit and Q.drillSupport.carriedSaleEligible(tool,ctx)then
                if not searched then Q.drillSupport.findSeller(ctx,ctx.root.Position);searched=true end
                if I.candidate(ctx,tool,plan) and ready(ctx,tool)then
                    local value=tonumber(api.attr(tool,'Value')) or 0
                    if not score or value>score then target,score=tool,value end
                end
            elseif not target and I.candidate(ctx,tool,plan) and ready(ctx,tool)then target=tool end
        end
        if not target then return false end
        local job={ctx=ctx,tool=target,id=api.id(target),count=api.stackCount(target),started=now(),character=ctx.character,
            backpack=api.Players.LocalPlayer:FindFirstChild('Backpack'),drill=ctx.drill,
            passiveDriving=ctx.questDriving and passiveDriving(ctx,target) or false}
        s.questInventoryDrop=job
        local issued,token=Q.call('inventoryDrop','ToolService','DropSpecificItem',{target},function(ok,value,_,dispatch)
            job.settled=true;job.settledAt=now();job.notSent=dispatch=='not-sent'
            job.rejected=ok==true and value==false and not job.notSent
        end,function()
            local allowed=s.questInventoryDrop==job and ready(ctx,target) and api.stackCount(target)==job.count
                and I.candidate(ctx,target,plan)
            local record=blocked[target]
            if allowed and type(record)=='table' and record.standingRetry then record.standingRetry=nil end
            return allowed
        end)
        job.token=token
        if not issued then s.questInventoryDrop=nil;return false end
        if score then s.questStatus='Dropping owned sale resource; waiting for its native world item before selling' end
        return I.observe(ctx)
    end
    return I
end

end)()
    local buildQuestParasite = (function()
-- The tagged original Worm is damaged by native melee. Its camera clone is cosmetic.
return function(api,Q)
    local P,s,now={},api.state,api.now
    local function finite(v)return type(v)=='number' and v==v and math.abs(v)<math.huge end
    local function status(text)s.questStatus=text end
    function P.valid(ctx,worm)
        local player=api.Players.LocalPlayer;local npc=workspace:FindFirstChild('Npc')
        if not ctx.active or ctx.character~=player.Character or not npc or not worm or worm.Parent~=npc
            or not worm:IsA('Model') or not api.tag(worm,'Worm') or worm:GetAttribute('OnFace')~=true
            or worm:GetAttribute('NpcFaction')=='FriendlyCompanion' or worm:GetAttribute('Category')=='Corpse'then return false end
        local target=worm:FindFirstChild('Target');local hum=worm:FindFirstChildOfClass('Humanoid')
        return target and target:IsA('ObjectValue') and target.Value==ctx.character
            and hum and finite(hum.Health) and hum.Health>0 and (not api.enemyAlive or api.enemyAlive(worm)) or false
    end
    function P.target(ctx)
        if P.valid(ctx,ctx.questParasiteTarget)then return ctx.questParasiteTarget end
        for _,worm in ipairs(api.tagged('Worm'))do if P.valid(ctx,worm)then return worm end end
    end
    local function owned(ctx,tool)
        local backpack=api.Players.LocalPlayer:FindFirstChild('Backpack')
        return tool and tool:IsA('Tool') and (tool.Parent==ctx.character or tool.Parent==backpack)
    end
    local function toolClass(tool)
        local name=api.id(tool)
        if name=='Champions_Hammer'then return 'Pickaxe' end
        if name=='Sword_Executioner'then return 'Sword' end
        return api.attr(tool,'Class')
    end
    local function compatible(ctx,worm,tool)
        if not owned(ctx,tool)then return false end
        local class=toolClass(tool)
        return class=='Pickaxe' or class=='Sword' and api.swordTargetAllowed(worm)
    end
    local function activeOwned(ctx,worm)
        local controller=api.controller('ToolController');local active=controller and controller.ActiveTool
        local tool=active and active.DisplayTool
        if active and not active._Destroyed and active.Tool and active.Tool.Parent==ctx.character
            and compatible(ctx,worm,tool) and (active.Tool==tool or api.id(active.Tool)==api.id(tool)
                or active.Tool.Name==api.id(tool)..tostring(api.Players.LocalPlayer.UserId))then return tool,active end
    end
    local function activeOnly(ctx)
        local calls=s.questCalls or {}
        return calls.drag or calls.shop or calls.cash or s.bringDelivery or s.lootRequest or s.equipmentRequest
            or ctx.bringEquipmentLock or ctx.questPlacement or calls.medicalDrop
    end
    local function choose(ctx,worm)
        local held=activeOwned(ctx,worm);if held then return held end
        if activeOnly(ctx)then return end
        if api.swordTargetAllowed(worm)then
            local sword=api.findOwned(ctx,'Sword_Void') or api.findTool(ctx,'Sword')
            if compatible(ctx,worm,sword)then return sword end
        end
        local pick=api.findOwned(ctx,'Pickaxe_Void') or api.findTool(ctx,'Pickaxe')
        if compatible(ctx,worm,pick)then return pick end
    end
    function P.required(ctx)
        local worm=ctx.questParasiteTarget
        if not P.valid(ctx,worm)then return end
        if ctx.questHealAttempt or (s.questCalls or {}).medicalDrop or ctx.questPlacement then return nil,nil,true end
        local tool=ctx.questParasiteTool
        if activeOnly(ctx)then tool=activeOwned(ctx,worm)end
        if compatible(ctx,worm,tool)then return api.id(tool),toolClass(tool),true end
        if activeOnly(ctx)then return nil,nil,true end
        return nil,api.swordTargetAllowed(worm) and 'Sword' or 'Pickaxe',true
    end
    function P.stop(ctx)
        local job=ctx.questParasite
        if job then
            if ctx.combatTarget==job.worm then ctx.combatTarget=nil;ctx.questCombat=nil end
            if ctx.questThreat==job.worm then ctx.questThreat=nil end
            if job.owns and not ctx.questHealing and not ctx.bringEquipmentLock and not ctx.nativeGateMotion
                and not ctx.questMineEntry and not ctx.featureHold and not ctx.questPlacement then ctx.questOwns=nil end
        end
        ctx.questParasite=nil;ctx.questParasiteTarget=nil;ctx.questParasiteTool=nil
    end
    local function medicalBusy(ctx)
        if ctx.questHealAttempt or (s.questCalls or {}).medicalDrop or ctx.questPlacement then return true end
        local job=s.questDelivery
        return job and job.ctx==ctx and job.kind=='supply' and Q.healing and Q.healing.isMedical(job.item)
            and not(job.cancelled and job.movementReleased) or false
    end
    function P.step(ctx)
        if not api.owned() or s.farm~=ctx or ctx.character~=api.Players.LocalPlayer.Character
            or not ctx.active or ctx.humanoid.Health<=0 or s.awaiting or s.teleporting or s.departureAt
            or workspace:GetAttribute('InCutScene') or workspace:GetAttribute('InfiniteRebasing') or Q.manual()then
            P.stop(ctx);return false
        end
        if s.request or api.Players.LocalPlayer.GameplayPaused or ctx.nativeGateMotion or ctx.questMineEntry
            or ctx.featureHold or ctx.swingEdit then P.stop(ctx);return false end
        if medicalBusy(ctx)then P.stop(ctx);return false end
        local worm=P.target(ctx);local job=ctx.questParasite
        if not worm then P.stop(ctx);return false end
        local hp=worm:FindFirstChildOfClass('Humanoid').Health
        ctx.questParasiteRetries=ctx.questParasiteRetries or setmetatable({}, {__mode='k'})
        local retry=ctx.questParasiteRetries[worm]
        if retry and retry.character==ctx.character and hp>=retry.health and now()<retry.untilAt then P.stop(ctx);return false end
        if not job or job.worm~=worm or job.character~=ctx.character then
            P.stop(ctx);job={worm=worm,character=ctx.character,health=hp,started=now(),progressAt=now(),owns=ctx.questOwns==true}
            ctx.questParasite=job
        elseif hp<job.health then job.health,job.progressAt,job.unarmedAt=hp,now(),nil end
        ctx.questParasiteTarget=worm;ctx.questParasiteTool=choose(ctx,worm)
        local seat=ctx.humanoid.SeatPart;local lease=s.questDriveLease
        if seat and ctx.drill and seat:IsDescendantOf(ctx.drill) and lease and lease.ctx==ctx then job.ownedSeat=seat end
        Q.abortResources(ctx);Q.stopDrive(ctx)
        local function yielded(reason)
            ctx.questParasiteRetries[worm]={character=ctx.character,health=hp,untilAt=now()+10}
            P.stop(ctx);status(reason..'; other loaded work continues while the real Worm remains');return false
        end
        if not Q.holdRoute(ctx)then
            job.owns=ctx.questOwns==true
            if now()-job.started>=8 then return yielded('Attached Worm handoff did not settle in 8s')end
            return true
        end
        job.owns=true
        if ctx.humanoid.SeatPart or ctx.humanoid.Sit then
            if ctx.humanoid.SeatPart==job.ownedSeat then Q.unseat(ctx)end
            if now()-job.started>=8 then return yielded('Attached Worm attack waits for actual seat exit')end
            status('Attached Worm detected; waiting for actual seat detachment before native melee');return true
        end
        if not job.attackAt then job.attackAt=now();job.progressAt=now()end
        local tool=ctx.questParasiteTool
        local _,active=activeOwned(ctx,worm)
        if not active and tool and not activeOnly(ctx)then active=api.equip(ctx,tool)end
        if active then job.unarmedAt=nil else job.unarmedAt=job.unarmedAt or now()end
        if now()-job.progressAt>=12 or job.unarmedAt and now()-job.unarmedAt>=8 then
            return yielded(active and 'Attached Worm took no native damage in 12s' or 'Attached Worm has no ready owned melee handler after 8s')
        end
        ctx.questThreat=worm;ctx.combatTarget=worm;ctx.questCombat=true
        if not active then status('Attached Worm: waiting for an owned compatible melee handler');return true end
        local ok,sent,reason=pcall(api.attack,ctx,active)
        if not ok then
            local why=tostring(sent)
            if why:find('__CHESTFARM_CANCELLED',1,true) or why:find('__EARTH_',1,true)then error(sent,0)end
        end
        if not P.valid(ctx,worm)then P.stop(ctx);status('Native attached Worm removal observed; resuming work');return false end
        local current=worm:FindFirstChildOfClass('Humanoid').Health
        if current<hp then job.health,job.progressAt=current,now()end
        status(sent and ok and 'Attacking the original attached Worm with native melee; observing its real health'
            or 'Attached Worm native melee waits: '..tostring(ok and reason or sent))
        return true
    end
    return P
end

end)()
    local buildQuestFuelCargo = (function()
-- Native drill fuel reserves: confirmed drag, physical WeldPart contact, then
-- DragService.Weld's attached/detached receipts. Never toggle an unknown result.
return function(api,Q)
    local M,s,cfg,now={},api.state,api.state.config,api.now
    local records=s.questFuelCargo or {};s.questFuelCargo=records
    local unknown=s.questFuelCargoUnknown or setmetatable({}, {__mode='k'});s.questFuelCargoUnknown=unknown
    local retry=s.questFuelCargoRetry or setmetatable({}, {__mode='k'});s.questFuelCargoRetry=retry
    local function finite(n)return type(n)=='number' and n==n and math.abs(n)<math.huge end
    local function live(item)return item and item.Parent and item:IsDescendantOf(workspace)end
    local function welded(item)return item:GetAttribute('Welded')==true or api.tag(item,'Welded')end
    local function disconnect(record)
        if record.connection then pcall(record.connection.Disconnect,record.connection);record.connection=nil end
    end
    local function key(item)
        if not item then return end
        local identity=item:GetAttribute('SessionSnapshotItemId')
        if type(identity)=='string' and #identity>0 and #identity<=128 or finite(identity)then
            return tostring(api.id(item))..':'..type(identity)..':'..tostring(identity)
        end
    end
    local function watch(record)
        local item=record.item
        record.connection=item:GetAttributeChangedSignal('Welded'):Connect(function()
            if item:GetAttribute('Welded')==true then record.seen=true
            elseif record.seen and not record.detaching then record.state='manual-release';disconnect(record)end
        end)
    end
    function M.observe(ctx)
        for item,record in pairs(records)do
            record.key=record.key or key(item)
            if record.drill~=ctx.drill or record.character~=ctx.character or ctx.drill~=workspace:FindFirstChild('Drill')then
                if record.drill==ctx.drill and (record.state=='pending' or record.state=='uncertain')then
                    unknown[item]=true -- Keep its observed identity excluded on this same drill.
                else
                if record.state=='pending' or record.state=='uncertain'then unknown[item]=true end
                disconnect(record);records[item]=nil
                end
            elseif record.state=='detached' and not Q.calls.drag and item:GetAttribute('Welded')==false
                and not api.tag(item,'Welded')then
                disconnect(record);records[item]=nil
            end
        end
    end
    function M.reserved(item)
        local record=records[item]
        if unknown[item] or record and record.state~='available'then return true end
        local identity=key(item)
        if identity then for _,entry in pairs(records)do
            if entry.key==identity and entry.drill==workspace:FindFirstChild('Drill')then return true end
        end end
        return false
    end
    local function fuel(item,ctx,stored)
        local amount=item and tonumber(api.attr(item,'Fuel'))
        if not live(item) or item.Parent~=workspace:FindFirstChild('Items') or not finite(amount) or amount<=0
            or Q.protectedRelic(item) or Q.protectedStarter(item) or api.useful(ctx,item)
            or item:GetAttribute('Robux')==true or item:GetAttribute('ProductId')~=nil or item:GetAttribute('RobuxProductId')~=nil
            or api.attr(item,'CostCurrency')~=nil and api.attr(item,'CostCurrency')~='Coins'
            or api.tag(item,'ShopItem') or item:GetAttribute('Welded')~=nil and type(item:GetAttribute('Welded'))~='boolean'
            or item:GetAttribute('Placed') or item:GetAttribute('CraftedPlaceable') or api.tag(item,'Welded') and not stored
            or item:FindFirstChild('Health') or not api.part(item)then return false end
        local rawOwner=item:GetAttribute('OwnerUserId');local owner=tonumber(rawOwner)
        if rawOwner~=nil and not finite(owner)then return false end
        if owner and owner~=0 and owner~=api.Players.LocalPlayer.UserId then return false end
        local class=api.attr(item,'Class');local category=api.attr(item,'Category')
        if class=='Medkit' or class=='ReviveKit' or class=='Sword' or class=='Pickaxe'
            or category=='Ammo' or category=='Relic' or item:IsA('Tool')then return false end
        local humanoid=item:FindFirstChildOfClass('Humanoid')
        if humanoid and humanoid.Health>0 then return false end
        return Q.drillSupport.accessible(item) and (stored or not M.reserved(item) and Q.free(item,true))
    end
    local function eligible(ctx,plan)
        local input=game:GetService('UserInputService')
        if type(input.GetFocusedTextBox)=='function' and input:GetFocusedTextBox()then return false end
        local hp,maximum=tonumber(ctx.humanoid.Health),tonumber(ctx.humanoid.MaxHealth)
        if not finite(hp) or not finite(maximum) or maximum<=0 or hp/maximum<=.3 then return false end
        return Q.enabled(ctx) and not Q.manual() and not api.extractionReady() and not ctx.questHealing
            and (plan.kind=='depth' and cfg.driveDepth or plan.kind=='fuel')
            and not Q.drillSupport.inDungeon(ctx) and not ctx.questMineEntry and not ctx.nativeGateMotion
            and not ctx.questCombat and not ctx.defenseMoving and now()>=(ctx.dodgeUntil or 0)
            and not s.bringDelivery and not s.lootRequest and not s.equipmentRequest and not s.questCashJob
            and not ctx.questPlacement and not ctx.questPreviewCancel and not ctx.questStartup
            and not api.Players.LocalPlayer:GetAttribute('PlacingCraftedPlaceable')
            and not (ctx.humanoid.MoveDirection and ctx.humanoid.MoveDirection.Magnitude>.05)
    end
    local function surface(ctx,p,item)
        return live(p) and p:IsA('BasePart') and p:IsDescendantOf(ctx.drill) and api.tag(p,'WeldPart')
            and p.Name~='Furnace' and p~=item and not p:IsDescendantOf(item)
    end
    function M.touching(ctx,item)
        local origin=api.part(item);if not origin then return end
        local best,distance,foreignDistance
        local parts=item:IsA('BasePart') and {item} or item:GetDescendants()
        for _,part in ipairs(parts)do if part:IsA('BasePart') and type(part.GetTouchingParts)=='function'then
            for _,p in ipairs(part:GetTouchingParts())do
                if live(p) and p:IsA('BasePart') and api.tag(p,'WeldPart') and p~=item and not p:IsDescendantOf(item)then
                    local d=(p.Position-origin.Position).Magnitude
                    if surface(ctx,p,item)then
                        if not distance or d<distance then best,distance=p,d end
                    elseif not foreignDistance or d<foreignDistance then foreignDistance=d end
                end
            end
        end end
        -- Native DragController chooses the nearest touched WeldPart, including
        -- surfaces outside the drill. Ambiguous foreign contact proves no safe
        -- drill attachment, even when another piece touches our deck too.
        if best and (not foreignDistance or foreignDistance>distance+.01)then return best end
    end
    local function geometry(item)
        local bounds,size
        if item:IsA('BasePart')then bounds,size=item.CFrame,item.Size else bounds,size=item:GetBoundingBox()end
        if not bounds or not size or not finite(size.X) or not finite(size.Y) or not finite(size.Z)
            or math.min(size.X,size.Y,size.Z)<=0 or math.max(size.X,size.Y,size.Z)>24 then return end
        return bounds,size,bounds:ToObjectSpace(item:GetPivot())
    end
    local function clear(ctx,item,p,offset,size,pivotOffset)
        if not surface(ctx,p,item)then return false end
        local pivot=p.CFrame*offset
        local bounds=pivot*pivotOffset:Inverse()
        local seat=ctx.drill:FindFirstChild('DrillPhysicsSeat') or ctx.drill:FindFirstChild('VehicleSeat')
        local furnace=ctx.drill:FindFirstChild('Furnace')
        if seat and api.part(seat) and ((bounds.Position-api.part(seat).Position).Magnitude<6
                or (bounds.Position+Vector3.new(0,3,5)-api.part(seat).Position).Magnitude<=4)
            or furnace and api.part(furnace) and (bounds.Position-api.part(furnace).Position).Magnitude<size.Magnitude*.5+6 then return false end
        local params=OverlapParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={item,p,ctx.character}
        local inner=Vector3.new(math.max(.05,size.X-.12),math.max(.05,size.Y-.16),math.max(.05,size.Z-.12))
        for _,part in ipairs(workspace:GetPartBoundsInBox(bounds,inner,params))do
            if part~=p and not part:IsDescendantOf(item) and not part:IsDescendantOf(ctx.character)then
                local parent=part
                while parent.Parent and parent.Parent~=workspace:FindFirstChild('Items') and parent.Parent~=workspace do parent=parent.Parent end
                if part.CanCollide==true or welded(parent) or M.reserved(parent)then return false end
            end
        end
        return true
    end
    function M.placement(ctx,item)
        local bounds,size,pivotOffset=geometry(item);if not bounds then return end
        local candidates={}
        for _,p in ipairs(api.tagged('WeldPart'))do if surface(ctx,p,item) and #candidates<256
            and p.Size.X>=size.X+.1 and p.Size.Z>=size.Z+.1 then
            local point=p.CFrame:PointToObjectSpace(bounds.Position)
            local hx,hz=(p.Size.X-size.X)*.5-.05,(p.Size.Z-size.Z)*.5-.05
            for ix=-2,2 do for iz=-2,2 do
                local offset=CFrame.new(math.clamp(point.X+ix*math.max(1,size.X+.35),-hx,hx),
                    p.Size.Y*.5+size.Y*.5-.06,math.clamp(point.Z+iz*math.max(1,size.Z+.35),-hz,hz))*pivotOffset
                candidates[#candidates+1]={surface=p,offset=offset,distance=(p.CFrame*offset).Position-bounds.Position}
            end end
        end end
        table.sort(candidates,function(a,b)return a.distance.Magnitude<b.distance.Magnitude end)
        for i=1,math.min(64,#candidates)do local c=candidates[i]
            if clear(ctx,item,c.surface,c.offset,size,pivotOffset)then return c.surface,c.offset,size,pivotOffset end
        end
    end
    local function valid(job,plan)
        return s.questDelivery==job and not job.cancelled and eligible(job.ctx,plan)
            and job.ctx.character==job.character and job.ctx.drill==job.drill and plan.name==job.class
            and live(job.surface) and surface(job.ctx,job.surface,job.item) and fuel(job.item,job.ctx,true)
    end
    local function ready(job)
        local ctx=job.ctx
        Q.stopDrive(ctx)
        if Q.driveHandoff(ctx) or ctx.drill:GetAttribute('DriverUserId')~=nil and ctx.drill:GetAttribute('DriverUserId')~=0 then return false end
        if ctx.humanoid.SeatPart or ctx.humanoid.Sit then Q.unseat(ctx);return false end
        return Q.holdRoute(ctx)
    end
    function M.place(job)
        if not job.owns or not job.ownershipConfirmed or welded(job.item)
            or not clear(job.ctx,job.item,job.surface,job.offset,job.size,job.pivotOffset)then return false end
        local goal=job.surface.CFrame*job.offset
        local center=(goal*job.pivotOffset:Inverse()).Position
        api.hover(job.ctx);job.ctx.root.CFrame=CFrame.new(center+Vector3.new(0,3,5));api.watch(job.ctx)
        job.item:PivotTo(goal)
        local part=api.part(job.item);part.AssemblyLinearVelocity=Vector3.zero;part.AssemblyAngularVelocity=Vector3.zero
        if not job.constraints then
            job.constraints={}
            local function create(class,parent)local object=Instance.new(class);job.constraints[#job.constraints+1]=object
                object.Name,object.Parent='DTECFuelReserve',parent;return object end
            local attachment=create('Attachment',part);attachment.CFrame=part.CFrame:ToObjectSpace(job.item:GetPivot())
            local destination=create('Attachment',job.surface);destination.CFrame=job.offset
            local align=create('AlignPosition',part);align.Attachment0,align.Attachment1=attachment,destination
            align.Responsiveness,align.MaxForce,align.RigidityEnabled,align.ReactionForceEnabled=45,45000,false,false
            local rotation=create('AlignOrientation',part);rotation.Attachment0,rotation.Attachment1=attachment,destination
            rotation.Responsiveness,rotation.MaxTorque,rotation.RigidityEnabled,rotation.ReactionTorqueEnabled=45,500000,true,false
        end
        return true
    end
    local function release(job,message)
        if message then s.questStatus=message end
        retry[job.item]=now()+30
        Q.release(job)
    end
    local function track(job)
        local record={item=job.item,key=key(job.item),drill=job.drill,character=job.character,surface=job.surface,offset=job.offset,state='pending'}
        records[job.item]=record;job.record=record
        watch(record)
        return record
    end
    local function toggle(job,plan)
        local record=job.record
        job.pending=true
        local sent,token=Q.call('drag','DragService','Weld',{job.item},function(ok,value,_,dispatch)
            job.pending=nil
            if dispatch=='not-sent'then
                if job.mode=='store' and records[job.item]==record then disconnect(record);records[job.item]=nil end
                release(job);return
            end
            if ok and value==(job.mode=='store' and 'attached' or 'detached')then
                if job.mode=='store'then
                    record.state='stored';record.seen=record.seen or welded(job.item)
                    s.stats.questFuelStored=(s.stats.questFuelStored or 0)+1
                    release(job,'Fuel reserve attached to the native drill; keeping it for later')
                else
                    record.state='detached';job.stage='detach-receipt';job.receiptUntil=now()+5
                    if job.cancelled then release(job)end
                end
            else
                record.state='uncertain';unknown[job.item]=true
                release(job,'Fuel weld outcome unconfirmed; this item stays reserved without another toggle')
            end
        end,function()
            if not valid(job,plan) or not ready(job) or (api.part(job.item).Position-job.ctx.root.Position).Magnitude>11 then return false end
            if job.mode=='store'then
                local allowed=job.owns and not welded(job.item) and M.touching(job.ctx,job.item)==job.surface
                    and clear(job.ctx,job.item,job.surface,job.offset,job.size,job.pivotOffset)
                return allowed
            end
            local expected=record.surface.CFrame*record.offset
            if record.state~='stored' or not record.seen or not welded(job.item)
                or (job.item:GetPivot().Position-expected.Position).Magnitude>3 then return false end
            record.detaching=true;record.state='pending';return true
        end)
        if not sent then job.pending=nil;release(job)else job.weldToken=token end
    end
    function M.step(ctx,plan,job)
        if job.pending then
            if not valid(job,plan) or now()-job.started>=12 then release(job,'Fuel reserve waits for its original native reply; other work continues')end
            return true
        end
        if not valid(job,plan) or now()-job.started>=12 then release(job);return true end
        if job.stage=='detach-receipt'then
            if job.item:GetAttribute('Welded')==false and not api.tag(job.item,'Welded')then
                disconnect(job.record);records[job.item]=nil;retry[job.item]=nil
                Q.release(job);s.questStatus='Stored fuel detached; delivering it through the native Furnace next'
            elseif now()>=job.receiptUntil then
                job.record.state='uncertain';unknown[job.item]=true;release(job,'Detached fuel attributes remain unconfirmed; no repeated toggle')
            end
            return true
        end
        if not ready(job)then return true end
        if job.stage=='approach'then
            local part=api.part(job.item)
            if (part.Position-ctx.root.Position).Magnitude>10 then
                api.hover(ctx);ctx.root.CFrame=CFrame.new(part.Position+Vector3.new(0,3,5));api.watch(ctx);return true
            end
            if job.mode=='retrieve'then toggle(job,plan);return true end
            if not fuel(job.item,ctx,false)then release(job);return true end
            job.pending=true
            if not Q.call('drag','DragService','Request',{job.item},function(ok,value,_,dispatch)
                job.pending=nil;job.owns=dispatch~='not-sent' and (not ok or value==true)
                job.ownershipConfirmed=ok and value==true
                if not ok or not job.ownershipConfirmed or not valid(job,plan) or not fuel(job.item,ctx,false)then release(job);return end
                local p,offset,size,pivotOffset=M.placement(ctx,job.item)
                if not p then release(job,'No clear drill fuel storage surface remains');return end
                job.surface,job.offset,job.size,job.pivotOffset=p,offset,size,pivotOffset
                if not M.place(job)then release(job);return end
                job.stage='contact';job.contactUntil=now()+2
            end,function()return valid(job,plan) and ready(job) and fuel(job.item,ctx,false)
                and (api.part(job.item).Position-ctx.root.Position).Magnitude<=11 end)then job.pending=nil;release(job)end
        elseif job.stage=='contact'then
            if not job.owns or welded(job.item)then release(job);return true end
            local touched=M.touching(ctx,job.item)
            if touched then
                job.surface,job.target=touched,touched
                job.offset=touched.CFrame:ToObjectSpace(job.item:GetPivot())
                track(job);toggle(job,plan)
            elseif now()>=job.contactUntil then release(job,'Fuel storage had no real drill contact; no weld sent')
            elseif (job.item:GetPivot().Position-(job.surface.CFrame*job.offset).Position).Magnitude>2
                and not job.recovered then job.recovered=true;if not M.place(job)then release(job)end end
        end
        return true
    end
    local function begin(ctx,plan,item,mode,p,offset,size,pivotOffset,record)
        if s.questDelivery or Q.calls.drag or Q.calls.shop or Q.calls.cash or not eligible(ctx,plan)then return false end
        if not api.remote('DragService','Weld') or not api.remote('DragService','Request') or not api.remote('DragService','Cancel')then return false end
        if not Q.holdRoute(ctx)then return ctx.questOwns==true end
        local job={kind='fuel-cargo',mode=mode,ctx=ctx,item=item,surface=p,target=p,offset=offset,size=size,pivotOffset=pivotOffset,
            character=ctx.character,drill=ctx.drill,class=plan.name,stage='approach',started=now(),record=record}
        s.questDelivery=job;ctx.bringEquipmentLock=job
        return M.step(ctx,plan,job)
    end
    function M.retrieve(ctx,plan)
        if not eligible(ctx,plan)then return false end
        local tank,capacity=tonumber(ctx.drill:GetAttribute('Fuel')),tonumber(ctx.drill:GetAttribute('MaxFuel'))
        if not finite(tank) or not finite(capacity) or capacity<=0 or tank>=capacity
            or not (Q.refuelActive(ctx,plan) or plan.kind=='fuel' or tank<=capacity*.2)then return false end
        for item,record in pairs(records)do
            if record.state=='stored' and record.drill==ctx.drill and record.character==ctx.character and not live(item)
                and record.key and surface(ctx,record.surface,item)then
                for _,candidate in ipairs(Q.looseItems())do
                    if key(candidate)==record.key and candidate:GetAttribute('Welded')==true
                        and type(candidate.GetAttributeChangedSignal)=='function'
                        and fuel(candidate,ctx,true) and (candidate:GetPivot().Position-(record.surface.CFrame*record.offset).Position).Magnitude<=3 then
                        disconnect(record);records[item]=nil;record.item=candidate;record.seen=true;records[candidate]=record
                        watch(record);item=candidate;break
                    end
                end
            end
            if record.state=='stored' and record.drill==ctx.drill and record.character==ctx.character
                and record.seen and welded(item) and live(item) and fuel(item,ctx,true)
                and surface(ctx,record.surface,item)then
                return begin(ctx,plan,item,'retrieve',record.surface,record.offset,nil,nil,record)
            end
        end
        return false
    end
    function M.store(ctx,plan)
        if not eligible(ctx,plan) or Q.refuelActive(ctx,plan) or s.questDelivery or Q.calls.drag
            or type(workspace.GetPartBoundsInBox)~='function'then return false end
        local tank,capacity=tonumber(ctx.drill:GetAttribute('Fuel')),tonumber(ctx.drill:GetAttribute('MaxFuel'))
        if not finite(tank) or not finite(capacity) or capacity<=0 or tank<capacity*.8 then return false end
        local count=0;for _ in pairs(records)do count=count+1 end;if count>=32 then return false end
        local item,distance
        for _,candidate in ipairs(Q.looseItems())do
            if fuel(candidate,ctx,false) and now()>=(retry[candidate] or 0)
                and type(candidate.GetAttributeChangedSignal)=='function'then
                local d=(api.part(candidate).Position-ctx.root.Position).Magnitude
                if d<=120 and (not distance or d<distance)then item,distance=candidate,d end
            end
        end
        if not item then return false end
        local p,offset,size,pivotOffset=M.placement(ctx,item)
        if not p or (p.Position-ctx.root.Position).Magnitude>500 then retry[item]=now()+5;return false end
        return begin(ctx,plan,item,'store',p,offset,size,pivotOffset)
    end
    return M
end

end)()
    local unpackValues = table.unpack or unpack
    local packValues = table.pack or function(...)return {n=select('#',...),...}end
    local calls = s.questCalls or {}; s.questCalls = calls
    Q.calls=calls
    local retries = s.questItemRetries or setmetatable({}, {__mode = 'k'}); s.questItemRetries = retries
    local purchases = s.questPurchaseJobs or setmetatable({}, {__mode='k'}); s.questPurchaseJobs=purchases
    local weapons = {FlintlockKills = 'Flintlock', CutlassKills = 'Sword_Pirate'}
    local melee = {MeleeKills=true, MeleeDamage=true, MeleeCrits=true, EnemyKills=true, VampireKills=true,
        CrazyMinerKills=true, BanditMinerKills=true, DarknessEnemyKills=true,GoblinKills=true,GoblinLordKills=true}
    local guns = {GunKills=true, HeadShot=true, ShotgunKills='Shotgun', RifleKills='Rifle'}
    local mining = {MineCoal=true,MineDiamond=true,MineRuby=true,MineOres=true,MineGems=true}
    local sales = {SellGoldItems=true,SellCorpse=true,SellScrap=true,SellGems=true}
    local potions = {UseSpeedPotion='SpeedPotion',UseStrengthPotion='StrengthPotion',UseInvisibilityPotion='InvisibilityPotion'}
    local upgradeGoals = {BuyDriveSpeed='DriveSpeed',BuyEngineOverdrive='EngineOverdrive'}
    local specialGoals={ShredScrap=true,PlaceTurrets=true,TurretKills=true,CompleteDungeon=true,CompleteGoblinRing=true}
    local stock
    Q.capabilities={weapons=weapons,melee=melee,guns=guns,mining=mining,sales=sales,potions=potions,upgrades=upgradeGoals,special=specialGoals}
    local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
    Q.medicalReserve=1000
    function Q.coinSpendable(wallet)return finite(wallet) and math.max(0,wallet-Q.medicalReserve) or 0 end
    function Q.coinTarget(price,medical)
        return math.max(0,finite(price) and price or 0)+(medical and 0 or Q.medicalReserve)
    end
    function Q.canSpend(wallet,price,medical)
        return finite(wallet) and finite(price) and price>=0 and wallet>=price
            and (medical or price==0 or wallet-price>=Q.medicalReserve)
    end
    function Q.observeCoins(balance,readVersion)
        if not finite(balance) or balance<0 then return end
        if readVersion==nil or readVersion==(s.questWalletVersion or 0)then
            s.questWallet,s.questWalletAt=balance,now()
            s.questWalletVersion=(s.questWalletVersion or 0)+1
        end
        return s.questWallet,s.questWalletAt,s.questWalletVersion
    end
    function Q.coinBalance(fallback,quotedAt,version)
        if (s.questWalletVersion or 0)~=(version or 0)then
            if finite(s.questWallet) and now()-(s.questWalletAt or -math.huge)<3 then return s.questWallet end
        elseif finite(fallback) and now()-(quotedAt or -math.huge)<3 then return fallback end
    end
    local function setStatus(text) s.questStatus = text end
    function Q.ownedClass(data, name)
        if type(data)~='table' then return false end
        if type(data.OwnedClasses)=='table' then
            for _, v in ipairs(data.OwnedClasses) do if v==name then return true end end
        end
        -- ClassesController tests the OwnedClasses array with table.find.
        -- Progress entries alone are not proof of ownership.
        return false
    end
    function Q.supported(key, drive)
        return weapons[key]~=nil or melee[key]~=nil or guns[key]~=nil
            or mining[key]==true
            or sales[key]==true or potions[key]~=nil or upgradeGoals[key]~=nil or key=='ContributeFuel'
            or specialGoals[key]==true or key=='OpenChest' or key=='TotalDepth' and drive==true
    end
    function Q.activePlan(plan)
        return plan and plan.kind~='waiting' and plan.kind~='complete' and plan.kind~='advance' and plan.kind~='unsupported'
    end
    function Q.protectedRelic(item)
        return api.relic and api.relic(item) or api.attr(item,'Relic') or api.attr(item,'ClassRelic')
            or api.attr(item,'Class')=='Relic' or api.attr(item,'Category')=='Relic'
    end
    function Q.fuelNeeded()
        if Q.refuelActive and Q.refuelActive(s.farm)then return true end
        local plan=Q.plan(s.classData,s.questCatalog,cfg.driveDepth)
        if plan.kind=='depth' or plan.kind=='fuel'then return true end
        for _,goal in ipairs(plan.unmet or {})do if goal.key=='ContributeFuel'then return true end end
        return false
    end
    function Q.refuelActive(ctx,plan)
        if not ctx then return false end
        local current=workspace:FindFirstChild('Drill')
        local latch=s.questRefuelLatch
        if latch and (latch.drill~=current or not current or not current.Parent)then s.questRefuelLatch=nil;latch=nil end
        plan=plan or Q.plan(s.classData,s.questCatalog,cfg.driveDepth)
        local eligible=plan.kind=='depth' and cfg.driveDepth or plan.kind=='fuel'
        local selected=type(s.classData)=='table' and s.classData.SelectedClass or plan.name
        if latch and selected and latch.class and selected~=latch.class then s.questRefuelLatch=nil;latch=nil end
        if not cfg.classQuest or api.extractionReady() or not(eligible or latch)
            or latch and latch.kind=='depth' and not cfg.driveDepth and not eligible then
            s.questRefuelLatch=nil;ctx.questRefuel=nil;return false
        end
        if ctx.drill~=current or not current or not current.Parent then ctx.questRefuel=nil;return false end
        local tank,capacity=tonumber(current:GetAttribute('Fuel')),tonumber(current:GetAttribute('MaxFuel'))
        if finite(tank) and finite(capacity) and capacity>0 then
            if not latch and eligible and tank<=0 then
                latch={drill=current,kind=plan.kind,class=selected,started=now()};s.questRefuelLatch=latch
            end
            if latch and tank>=capacity then s.questRefuelLatch=nil;latch=nil end
        end
        -- This is a read-only intent, not a delivery/driver ownership lease.
        -- Preserve it through healing, same-class stage handoffs and worker
        -- recovery; partial fuel cannot authorize driving before the tank is full.
        ctx.questRefuel=latch
        return latch~=nil
    end
    function Q.plan(data, catalog, drive)
        local name = type(data)=='table' and data.SelectedClass
        local progress = name and type(data.ClassProgress)=='table' and data.ClassProgress[name]
        local entry = name and type(catalog)=='table' and catalog[name]
        -- The lobby displays level 1 for an owned class before its first
        -- ClassProgress entry exists; it does not infer ownership from progress.
        if progress==nil and Q.ownedClass(data,name) then progress={Level=1,Objectives={}} end
        if type(progress)~='table' or not finite(progress.Level) or progress.Level<1 or progress.Level%1~=0
            or not entry or not entry.Requirements then return {kind='waiting'} end
        local requirements = entry.Requirements[progress.Level+1]
        local plan = {name=name, level=progress.Level, unmet={}, unsupported={},
            counts=type(progress.Objectives)=='table' and progress.Objectives or {}}
        if not requirements then plan.kind='complete'; return plan end
        local pending = {}
        for key, goal in pairs(requirements) do
            local count=tonumber(plan.counts[key]) or 0
            if not finite(count) or count<0 then count=0 end
            if finite(goal) and count<goal then
                plan.unmet[#plan.unmet+1]={key=key, count=count, goal=goal}; pending[key]=true
                if not Q.supported(key,drive) then plan.unsupported[#plan.unsupported+1]=key end
            end
        end
        table.sort(plan.unmet,function(a,b)return a.key<b.key end)
        table.sort(plan.unsupported)
        plan.partial=#plan.unsupported>0 and #plan.unsupported<#plan.unmet
        -- Exact weapon objectives take precedence over general combat.
        for _, key in ipairs({'FlintlockKills','CutlassKills'}) do
            if pending[key] then
                plan.kind,plan.weapon,plan.objective='combat',weapons[key],key
                plan.weaponClass=key=='CutlassKills' and 'Sword' or 'Revolver'
                return plan
            end
        end
        if pending.PlaceTurrets then plan.kind,plan.objective='turret','PlaceTurrets';return plan end
        if pending.TurretKills then plan.kind,plan.objective='turret','TurretKills';return plan end
        if pending.ShredScrap then plan.kind,plan.objective='shred','ShredScrap';return plan end
        if pending.CompleteDungeon or pending.CompleteGoblinRing or pending.GoblinLordKills then
            plan.kind,plan.objective='dungeon',pending.CompleteGoblinRing and 'CompleteGoblinRing' or pending.CompleteDungeon and 'CompleteDungeon' or 'GoblinLordKills'
            return plan
        end
        if pending.SellGoldItems then plan.kind,plan.objective='gold','SellGoldItems'; return plan end
        for _, item in ipairs(plan.unmet) do
            if melee[item.key] or guns[item.key] then
                plan.kind,plan.objective='combat',item.key
                plan.weaponClass=guns[item.key] and (type(guns[item.key])=='string' and guns[item.key] or 'Gun') or 'Sword'
                return plan
            end
        end
        if pending.OpenChest then plan.kind,plan.objective='chests','OpenChest'; return plan end
        for _,key in ipairs({'MineGems','MineDiamond','MineRuby','MineCoal','MineOres'})do
            if pending[key]then plan.kind,plan.objective='mining',key;return plan end
        end
        if pending.TotalDepth and drive then plan.kind,plan.objective='depth','TotalDepth'; return plan end
        for _,key in ipairs({'SellCorpse','SellScrap','SellGems'})do
            if pending[key]then plan.kind,plan.objective='sale',key;return plan end
        end
        if pending.ContributeFuel then plan.kind,plan.objective='fuel','ContributeFuel';return plan end
        for _,item in ipairs(plan.unmet)do
            if potions[item.key]then plan.kind,plan.objective,plan.potion='potion',item.key,potions[item.key];return plan end
            if upgradeGoals[item.key]then plan.kind,plan.objective='upgrades',item.key;return plan end
        end
        plan.kind=#plan.unmet==0 and 'advance' or 'unsupported'
        return plan
    end
    local function call(key,service,method,args,callback,guard)
        if calls[key] then return false end
        local rf=api.remote(service,method); if not rf then return false end
        local token={started=now(),service=service,method=method,args=args,failed=callback}; calls[key]=token
        token.thread=task.spawn(function()
            if guard then
                local checked,allowed=pcall(guard)
                if not checked or not allowed then
                    token.notSent=true
                    if calls[key]==token then calls[key]=nil;pcall(callback,false,nil,nil,'not-sent')end
                    return
                end
            end
            token.called=true
            if key=='cash' and service=='InteractionService' and method=='Interact'then
                s.stats.questCashRequests=(s.stats.questCashRequests or 0)+1
            end
            local results=packValues(pcall(function()return rf:InvokeServer(unpackValues(args,1,#args))end))
            local ok,value=results[1],results[2]
            if calls[key]~=token then return end
            calls[key]=nil
            -- Even a late ownership reply must run its compensating release path.
            local handled,why=pcall(callback,ok,value,unpackValues(results,3,results.n))
            if not handled then setStatus('Quest action needs recovery: '..tostring(why)) end
        end)
        return not token.notSent,token
    end
    function Q.retireConfirmedCall(key,token)
        if not token or calls[key]~=token then return true end
        local thread=token.thread
        if thread and thread~=coroutine.running() and coroutine.status(thread)~='dead'then pcall(task.cancel,thread)end
        if not thread or coroutine.status(thread)=='dead'then
            if calls[key]==token then calls[key]=nil end
            return true
        end
        return false -- A failed cancellation cannot authorize another mutation.
    end
    function Q.poll()
        -- Reads have no spending/ownership side effects. Cancel a hung read only
        -- after its coroutine actually stops, then notify its waiting consumer.
        for key,token in pairs(calls)do
            if (token.method=='GetClasses' or token.method=='GetBuyQuote' or token.method=='GetCurrency' or token.method=='FetchQuests'
                or token.method=='GetState' or token.method=='GetData' or token.method=='GetEquipped' or token.method=='GetCrateItems' or token.method=='GetContents')
                and now()-token.started>=8 and token.thread then
                pcall(task.cancel,token.thread)
                if coroutine.status(token.thread)=='dead' and calls[key]==token then
                    calls[key]=nil
                    if token.failed then pcall(token.failed,false,nil)end
                end
            end
        end
        if not cfg.classQuest then return end
        if not s.questCatalog and not s.questCatalogLoading then
            local shared=api.RS:FindFirstChild('Shared'); local module=shared and shared:FindFirstChild('ClassCatalog')
            if module and now()>=(s.questCatalogRetry or 0) then
                s.questCatalogLoading=true; s.questCatalogRetry=now()+10
                task.spawn(function()
                    local ok,value=pcall(require,module); s.questCatalogLoading=nil
                    if ok and type(value)=='table' then s.questCatalog=value end
                end)
            end
        end
        if now()>=(s.questPollAt or 0) then
            local started=now()
            if call('classes','ClassService','GetClasses',{},function(ok,value)
                if ok and type(value)=='table' and value.ClassProgress and (s.classObservedAt or -1)<=started then api.observeClass(value) end
            end) then s.questPollAt=now()+5 end
        end
    end
    local function enabled(ctx)
        return cfg.classQuest and api.owned() and ctx and ctx.active and s.farm==ctx
            and ctx.character==api.Players.LocalPlayer.Character
            and ctx.drill==workspace:FindFirstChild('Drill') and ctx.drill and ctx.drill.Parent
            and not s.teleporting and not s.request and not s.awaiting and not s.departureAt
            and ctx.humanoid.Health>0 and not workspace:GetAttribute('InCutScene')
            and not workspace:GetAttribute('InfiniteRebasing') and api.Players.LocalPlayer.GameplayPaused~=true
    end
    local function manual()
        local c=api.controller('DragController')
        local job=s.farm and (s.farm.questPlacement or s.farm.questPreviewCancel)
        local placement=api.controller('PlaceablePlacementController')
        local own=job and placement and placement.Active and placement.Item and placement.Item.Parent
            and placement.Item:GetAttribute('CraftedPlaceable')==true
            and placement.Item:GetAttribute('PlacingUserId')==api.Players.LocalPlayer.UserId
            and job.recipe==api.id(placement.Item) and (not job.item or job.item==placement.Item)
        return c and c.LockedTarget or api.Players.LocalPlayer:GetAttribute('PlacingCraftedPlaceable')==true and not own
    end
    local function clearThrottle(ctx)
        local frameInput=ctx.questMobileThrottle
        if frameInput then
            ctx.questMobileThrottle=nil
            pcall(api.RunService.UnbindFromRenderStep,api.RunService,frameInput.name)
        end
        if ctx.questDriveInput then
            local input=ctx.questDriveInput
            -- Release only the key this worker injected. Cleanup must work even
            -- after OFF, death or a transition makes new quest work ineligible.
            local ok=pcall(input.send,false)
            if input.uis and type(input.uis.IsKeyDown)=='function'then
                local read,down=pcall(input.uis.IsKeyDown,input.uis,Enum.KeyCode.W)
                if read then ok=not down end
            end
            if ok then
                ctx.questDriveInput=nil
                if s.questInputRelease==ctx then s.questInputRelease=nil end
            else s.questInputRelease=ctx end
        end
        for seat,value in pairs(ctx.questSeats or {}) do pcall(function() if seat.Parent then seat.ThrottleFloat=value end end) end
        ctx.questSeats=nil
    end
    local function mobileInput()
        local controller=api.controller('InputController')
        if controller and controller.Platform=='Mobile'then return true end
        local ok,uis=pcall(function()return game:GetService('UserInputService')end)
        return ok and uis and uis.TouchEnabled==true and uis.KeyboardEnabled==false
    end
    local function forwardInput(ctx)
        if s.questInputRelease then
            clearThrottle(s.questInputRelease)
            if s.questInputRelease then return false end
        end
        -- Native TrainComponent accepts the owned seat throttle on Mobile.
        -- Delta does not need desktop key injection or a virtual keyboard.
        if mobileInput()then
            if ctx.questDriveInput then clearThrottle(ctx)end
            return false
        end
        if now()<(ctx.questDriveInputRetryAt or 0)then return false end
        local ok,uis=pcall(function()return game:GetService('UserInputService')end)
        if not ok or not uis or not Enum.KeyCode or not Enum.KeyCode.W then return false end
        if type(uis.GetFocusedTextBox)=='function' and uis:GetFocusedTextBox()then return false end
        local function focused()
            -- OS key injection is usable only when this Roblox client is
            -- positively identified as active; never assume another window is us.
            if type(isrbxactive)~='function'then return false end
            local read,value=pcall(isrbxactive);return read and value==true
        end
        local input=ctx.questDriveInput
        if input then
            if input.backend=='keys' and not focused()then clearThrottle(ctx);return false end
            local read,down=pcall(uis.IsKeyDown,uis,Enum.KeyCode.W)
            if read and down then input.verified=true
            elseif now()>=(input.verifyAt or 0)then
                if input.backend=='virtual'then ctx.questDriveVimRetryAt=now()+30 end
                clearThrottle(ctx);if ctx.questDriveInput then return false end
                input=nil
            end
            if input then
                if now()>=(input.refreshAt or 0)then
                    input.refreshAt=now()+.5
                    local sent=pcall(input.send,true)
                    if not sent then
                        if input.backend=='virtual'then ctx.questDriveVimRetryAt=now()+30 end
                        clearThrottle(ctx);if ctx.questDriveInput then return false end
                    else return input.verified==true end
                else return input.verified==true end
            end
        end
        local read,down=pcall(uis.IsKeyDown,uis,Enum.KeyCode.W)
        if read and down then return true end -- Respect an already-held human key.
        local available,vim=pcall(function()return game:GetService('VirtualInputManager')end)
        local options={}
        if available and vim and type(vim.SendKeyEvent)=='function' and now()>=(ctx.questDriveVimRetryAt or 0)then
            options[#options+1]={backend='virtual',send=function(value)vim:SendKeyEvent(value,Enum.KeyCode.W,false,game)end}
        end
        if focused() and type(keypress)=='function' and type(keyrelease)=='function'then
            options[#options+1]={backend='keys',send=function(value)if value then keypress(0x57)else keyrelease(0x57)end end}
        end
        for _,candidate in ipairs(options)do
            candidate.uis,candidate.refreshAt,candidate.verifyAt=uis,now()+.5,now()+.2
            ctx.questDriveInput=candidate -- Register before dispatch for error cleanup.
            if pcall(candidate.send,true)then
                local observed,held=pcall(uis.IsKeyDown,uis,Enum.KeyCode.W)
                candidate.verified=observed and held
                return candidate.verified==true
            end
            if candidate.backend=='virtual'then ctx.questDriveVimRetryAt=now()+30 end
            clearThrottle(ctx);if ctx.questDriveInput then return false end
        end
        ctx.questDriveInputRetryAt=now()+5;return false
    end
    local function clearHold(job)
        for _,object in ipairs(job.constraints or {}) do pcall(function()object:Destroy()end) end
        job.constraints=nil
    end
    local function driverId(drill)
        local value=drill and drill:GetAttribute('DriverUserId')
        return finite(value) and value or nil -- Match native number-only driver state.
    end
    function Q.recoverDrive()
        if s.questInputRelease then clearThrottle(s.questInputRelease)end
        local lease=s.questDriveLease
        if not lease or not lease.abandoned then return end
        local current=workspace:FindFirstChild('Drill')
        if not lease.drill or not lease.drill.Parent or lease.drill~=current then lease.retired=true end
        if lease.retired then
            -- StopDriving has no instance argument. Stale driver attributes on
            -- a still-parented replaced train cannot authorize stopping its successor.
            -- Keep an unknown sent stop reserved while current ownership is ours.
            if not lease.stopIssued or lease.stopAccepted==true or current and driverId(current)~=api.Players.LocalPlayer.UserId then
                s.questDriveLease=nil
            end
            return
        end
        -- A native StartDriving reply can arrive after timeout, OFF or reload.
        -- Compensate only after our own server driver ID appears, never another's.
        if driverId(lease.drill)==api.Players.LocalPlayer.UserId and not lease.stopIssued
            and not calls.drive and now()>=(lease.stopRetryAt or 0)then
            -- Native TrainComponent retries a rejected stop. Unknown outcomes
            -- remain reserved; only a completed explicit rejection may rearm.
            -- Set before dispatch because an executor/mock may settle immediately.
            lease.stopIssued=true
            local issued,token=call('drive','DrillService','StopDriving',{},function(ok,value,_,dispatch)
                lease.stopSettled=true;lease.stopAccepted=ok and value~=false
                if dispatch=='not-sent' or ok and value==false then
                    lease.stopIssued=nil
                    lease.stopRejections=(lease.stopRejections or 0)+1
                    lease.stopRetryAt=now()+math.min(10,lease.stopRejections)
                end
            end,function()return api.owned() and s.questDriveLease==lease and lease.abandoned and not lease.retired
                and workspace:FindFirstChild('Drill')==lease.drill
                and driverId(lease.drill)==api.Players.LocalPlayer.UserId end)
            if issued then lease.stopToken=token else lease.stopIssued=nil end
        end
    end
    local function humanDrivingInput(ctx)
        if ctx.questDriveInput or s.questInputRelease then return false end
        local ok,uis=pcall(function()return game:GetService('UserInputService')end)
        if ok and uis and type(uis.IsKeyDown)=='function'then
            for _,name in ipairs({'W','Up','S','Down'})do
                local key=Enum.KeyCode[name]
                if key then
                    local read,down=pcall(uis.IsKeyDown,uis,key)
                    if read and down then return true end
                end
            end
        end
        return false
    end
    local function mobileThrottle(ctx,seat,lease)
        if not mobileInput()then return false end
        local renderer=api.RunService
        if not renderer or type(renderer.BindToRenderStep)~='function'
            or type(renderer.UnbindFromRenderStep)~='function'then return false end
        local previous=ctx.questMobileThrottle
        if previous and previous.seat==seat and previous.lease==lease then return true end
        if previous then
            ctx.questMobileThrottle=nil;pcall(renderer.UnbindFromRenderStep,renderer,previous.name)
        end
        local record={name='DTECDriveThrottle_'..tostring(ctx),seat=seat,lease=lease,character=ctx.character,
            band=workspace:GetAttribute('InfiniteDepthOffsetMeters'),class=s.classData and s.classData.SelectedClass}
        local function release()
            if ctx.questMobileThrottle~=record then return end
            ctx.questMobileThrottle=nil;pcall(renderer.UnbindFromRenderStep,renderer,record.name)
        end
        local function update()
            local own=ctx.questMobileThrottle==record and enabled(ctx) and cfg.driveDepth and ctx.questDriving
                and ctx.character==record.character and ctx.character==api.Players.LocalPlayer.Character
                and ctx.drill==workspace:FindFirstChild('Drill') and ctx.drill.Parent
                and s.questDriveLease==lease and lease.ctx==ctx and lease.drill==ctx.drill
                and lease.confirmed and not lease.abandoned and driverId(ctx.drill)==api.Players.LocalPlayer.UserId
                and record.band==workspace:GetAttribute('InfiniteDepthOffsetMeters')
                and record.class==(s.classData and s.classData.SelectedClass)
                and seat.Parent and seat:IsDescendantOf(ctx.drill) and not manual() and not humanDrivingInput(ctx)
                and not api.extractionReady() and not ctx.questHealing and not ctx.nativeGateMotion and not ctx.questMineEntry
                and not(finite(ctx.humanoid.MaxHealth) and ctx.humanoid.Health<=ctx.humanoid.MaxHealth*.3)
            local ok,uis=pcall(function()return game:GetService('UserInputService')end)
            if own and ok and uis and type(uis.GetFocusedTextBox)=='function'then
                local read,value=pcall(uis.GetFocusedTextBox,uis)
                own=read and not value
            else own=false end
            if not own then release();return end
            local current=ctx.drill:FindFirstChild('LocalDriverSeat')
                or ctx.drill:FindFirstChild('DrillPhysicsSeat') or ctx.drill:FindFirstChild('VehicleSeat')
            if current~=seat then release();return end
            -- CoreScripts writes idle mobile throttle during Input priority.
            -- Apply only our owned seat afterward, before native Heartbeat
            -- samples it. No keys, touch events, remotes or progress are forged.
            local written=pcall(function()seat.ThrottleFloat=1 end)
            if not written then release()end
        end
        ctx.questMobileThrottle=record
        local priority=Enum.RenderPriority.Input and Enum.RenderPriority.Input.Value or 200
        local bound=pcall(renderer.BindToRenderStep,renderer,record.name,priority+1,update)
        if not bound then release();return false end
        return true
    end
    function Q.clearLootStop(ctx)
        local record=ctx.questLootStop
        if record and record.connection then pcall(record.connection.Disconnect,record.connection)end
        ctx.questLootStop=nil
    end
    local function lootStopCurrent(ctx,record)
        local cycle=ctx.questDepthEconomy
        return record and ctx.questLootStop==record and cfg.classQuest and cfg.driveDepth and enabled(ctx)
            and ctx.active and s.farm==ctx and not manual() and not api.extractionReady()
            and not ctx.questHealing and not ctx.nativeGateMotion and not ctx.questMineEntry
            and record.cycle==cycle and cycle and (cycle.phase=='loot' or cycle.phase=='funding')
            and record.character==ctx.character and ctx.character==api.Players.LocalPlayer.Character
            and record.humanoid==ctx.humanoid and ctx.humanoid.Health>ctx.humanoid.MaxHealth*.3
            and record.drill==ctx.drill and ctx.drill==workspace:FindFirstChild('Drill') and ctx.drill.Parent
            and record.band==workspace:GetAttribute('InfiniteDepthOffsetMeters')
            and record.class==(s.classData and s.classData.SelectedClass)
            and record.job==game.JobId and record.runStarted==s.lootStarted
    end
    local function observeLootStop(ctx,lease)
        local cycle=ctx.questDepthEconomy;local record=ctx.questLootStop
        if record and record.lease==lease then
            if lootStopCurrent(ctx,record)then return record end
            Q.clearLootStop(ctx);return
        end
        if not cycle or cycle.phase~='loot' and cycle.phase~='funding' or not lease
            or lease.ctx~=ctx or lease.drill~=ctx.drill or not lease.confirmed then return end
        Q.clearLootStop(ctx)
        record={cycle=cycle,lease=lease,character=ctx.character,humanoid=ctx.humanoid,drill=ctx.drill,
            band=workspace:GetAttribute('InfiniteDepthOffsetMeters'),class=s.classData and s.classData.SelectedClass,
            job=game.JobId,runStarted=s.lootStarted};ctx.questLootStop=record
        if not lootStopCurrent(ctx,record)then Q.clearLootStop(ctx);return end
        local function observe()
            if not lootStopCurrent(ctx,record)then return end
            local owner=record.drill:GetAttribute('DriverUserId')
            if owner==nil then record.releasedAt=record.releasedAt or now()
            elseif owner~=api.Players.LocalPlayer.UserId then record.foreignSeen=true end
        end
        -- Capture an actual clear even if native proximity StartDriving seats
        -- us again before the optional worker's next (possibly lagged) pulse.
        pcall(function()
            record.connection=record.drill:GetAttributeChangedSignal('DriverUserId'):Connect(observe)
        end)
        observe();return record
    end
    function Q.leaveLootSeat(ctx,cycle)
        local record=ctx.questLootStop;local lease=record and record.lease
        if not lootStopCurrent(ctx,record) or record.cycle~=cycle or record.foreignSeen
            or not lease or not lease.abandoned or lease.stopAccepted~=true or not record.releasedAt
            or not Q.driveStopped(ctx,lease) or calls.drive or humanDrivingInput(ctx)
            or s.questDelivery or s.questCashJob or calls.drag or calls.cash or calls.shop
            or s.bringDelivery or s.lootRequest or s.equipmentRequest or ctx.bringEquipmentLock then return false end
        local seat=ctx.drill:FindFirstChild('DrillPhysicsSeat') or ctx.drill:FindFirstChild('VehicleSeat')
        if not seat or not seat.Parent or not seat:IsA('BasePart') or not seat:IsDescendantOf(ctx.drill)
            or (ctx.root.Position-seat.Position).Magnitude>3 then return false end
        if not Q.holdRoute(ctx)then return ctx.questOwns==true end
        -- Native TrainComponent auto-starts every0.1s inside three studs. Move
        -- only this detached character after our accepted stop and real clear.
        api.hover(ctx);ctx.root.CFrame=seat.CFrame*CFrame.new(0,5,12)
        if ctx.root.AssemblyLinearVelocity then ctx.root.AssemblyLinearVelocity=Vector3.zero end
        setStatus('Loot break: native driver released; moving clear of the auto-start area')
        return true
    end
    function Q.stopDrive(ctx)
        local wasDriving=ctx.questDriving or ctx.questSeating
        local lease=s.questDriveLease
        local wall=ctx.questWallWork;local drill=ctx.drill;local attached=ctx.humanoid.SeatPart
        local localSeat=drill and drill:FindFirstChild('LocalDriverSeat')
        local pending=calls.drive or lease and lease.abandoned and lease.stopIssued and lease.stopAccepted~=true
        local handoff=ctx.questLootStop
        if lootStopCurrent(ctx,handoff) and not handoff.foreignSeen and not handoff.recoveryUsed
            and handoff.releasedAt and now()-handoff.releasedAt<=8
            and handoff.lease.confirmed and handoff.lease.abandoned and handoff.lease.stopAccepted==true
            and (not lease or lease==handoff.lease) and attached and attached==localSeat
            and localSeat.Occupant==ctx.humanoid and driverId(drill)==api.Players.LocalPlayer.UserId
            and not pending and not humanDrivingInput(ctx)then
            -- The prior session actually cleared, then this exact character
            -- was reseated in the still-owned break. Rearm once for this newly
            -- observed session; an accepted/unknown stop alone is insufficient.
            handoff.recoveryUsed=true;ctx.questDriving=true;wasDriving=true
            lease={ctx=ctx,drill=drill,started=now(),confirmed=true};s.questDriveLease=lease
        end
        local defense=ctx.questDrivingDefense
        if cfg.classQuest and enabled(ctx) and not manual() and defense and defense.driverReleased
            and defense.character==ctx.character and ctx.character==api.Players.LocalPlayer.Character
            and defense.drill==drill and drill==workspace:FindFirstChild('Drill') and drill.Parent
            and defense.band==workspace:GetAttribute('InfiniteDepthOffsetMeters')
            and defense.class==(s.classData and s.classData.SelectedClass)
            and defense.driveLease and defense.driveLease.ctx==ctx and defense.driveLease.drill==drill
            and defense.driveLease.confirmed and defense.driveLease.abandoned and defense.driveLease.stopAccepted==true
            and (not lease or lease==defense.driveLease) and attached and attached==localSeat
            and localSeat.Occupant==ctx.humanoid and driverId(drill)==api.Players.LocalPlayer.UserId
            and not pending and not humanDrivingInput(ctx)then
            -- Knockback can restart the native driver after our verified stop.
            -- Adopt only this still-active defense's actual reseated character,
            -- and require a new observed driver release before another stop.
            ctx.questDriving=true;wasDriving=true
            lease={ctx=ctx,drill=drill,started=now(),confirmed=true};s.questDriveLease=lease
            defense.driveLease=lease;defense.driverReleased=nil
            if defense.intent then defense.intent.lease=lease end
        end
        if cfg.classQuest and enabled(ctx) and not manual() and wall and wall.drill==drill
            and drill==workspace:FindFirstChild('Drill') and drill.Parent
            and wall.band==workspace:GetAttribute('InfiniteDepthOffsetMeters')
            and attached and (attached==wall.seat or attached==localSeat)
            and driverId(drill)==api.Players.LocalPlayer.UserId and not pending and not humanDrivingInput(ctx)
            and (not lease or lease.ctx==ctx and (not lease.abandoned or lease.stopAccepted==true and wall.released))then
            -- A known script wall context can re-enter the native auto-start
            -- radius during loot/healing. Only an actually attached current
            -- local seat authorizes adopting that accidental session to stop it.
            -- One observed release is required before rearming an accepted stop.
            ctx.questDriving=true;wasDriving=true;wall.released=nil
            lease={ctx=ctx,drill=drill,started=now(),confirmed=true};s.questDriveLease=lease
        end
        if wasDriving and lease then observeLootStop(ctx,lease)end
        clearThrottle(ctx)
        if (ctx.questDriving or ctx.questSeating) and (not lease or lease.ctx~=ctx) then
            lease={ctx=ctx,drill=ctx.drill,started=ctx.questSeating or now()};s.questDriveLease=lease
        end
        if lease and lease.ctx==ctx then
            if lease.confirmed and driverId(lease.drill)~=api.Players.LocalPlayer.UserId and not calls.drive then
                -- A replicated different/no driver ends a confirmed lease.
                -- It cannot later stop a new session just because its ID is ours.
                s.questDriveLease=nil
            else lease.abandoned=true;Q.recoverDrive()end
        end
        local observed=ctx.questLootStop
        if observed and lootStopCurrent(ctx,observed) and driverId(ctx.drill)==nil then
            observed.releasedAt=observed.releasedAt or now()
        end
        ctx.questDriving=nil
        ctx.questSeatAckAt=nil
        ctx.questDriveWatch=nil
        ctx.questDriveSessionAt=nil
        ctx.questDrivePausedAt=nil
        if wasDriving then
            ctx.humanoid.Sit=false; ctx.humanoid.Jump=true; ctx.questSeating=nil
        end
    end
    function Q.unseat(ctx)
        local h=ctx.humanoid;local seat=h.SeatPart
        if not seat and not h.Sit then ctx.questSeatExit=nil;return true,false end
        if manual() or not cfg.classQuest or not enabled(ctx)then return false,false end
        local job=ctx.questSeatExit
        if not job or job.seat~=seat then job={seat=seat,started=now()};ctx.questSeatExit=job end
        if now()>=(job.inputAt or 0)then
            job.inputAt=now()+1;h.Sit=false;h.Jump=true
            if type(h.ChangeState)=='function' and Enum.HumanoidStateType.GettingUp then pcall(h.ChangeState,h,Enum.HumanoidStateType.GettingUp)end
        end
        -- TrainComponent releases its own seat joint during native driver exit.
        -- Only a joint verified to attach THIS character may be released here.
        if seat and not job.jointReleased and now()-job.started>=1.5 and seat.Occupant==h then
            local weld=seat:FindFirstChild('SeatWeld')
            if weld and weld:IsA('JointInstance') and weld.Part0==seat and weld.Part1
                and weld.Part1:IsDescendantOf(ctx.character)then
                local ok=pcall(weld.Destroy,weld);job.jointReleased=ok or nil
            end
        end
        local holding=now()-job.started<4
        ctx.questOwns=holding or nil
        setStatus(holding and 'Leaving the actual seat; waiting for SeatPart to clear'
            or 'Seat exit unconfirmed; native jump retries continue without claiming escape')
        return false,holding
    end
    function Q.driveStopped(ctx,lease)
        local current=workspace:FindFirstChild('Drill');local token=lease and lease.stopToken
        local owner=current and current:GetAttribute('DriverUserId')
        local stopped=owner==nil or finite(owner) and owner>=0 and owner~=api.Players.LocalPlayer.UserId
        return token and token.called==true and token.service=='DrillService' and token.method=='StopDriving'
            and lease.ctx==ctx and lease.drill==current and ctx.drill==current and current and current.Parent
            and lease.confirmed and lease.abandoned and stopped
            and not ctx.humanoid.SeatPart and not ctx.humanoid.Sit
            and not ctx.questDriveInput and not s.questInputRelease and not humanDrivingInput(ctx)
    end
    function Q.driveHandoff(ctx)
        local lease=s.questDriveLease;local current=workspace:FindFirstChild('Drill')
        if ctx.questDriveInput or s.questInputRelease then return true end
        local token=calls.drive
        -- A real effect receipt permits only local standing work. The exact
        -- unknown RPC remains reserved; no reply or cancellation is invented.
        if token and not(lease and lease.stopToken==token and Q.driveStopped(ctx,lease))then return true end
        return lease and lease.ctx==ctx and lease.drill==current and lease.abandoned
                and lease.stopIssued and lease.stopAccepted~=true
                and driverId(current)==api.Players.LocalPlayer.UserId
    end
    local function release(job)
        if job.kind=='smelt' and Q.drillSupport and Q.drillSupport.processing then
            Q.drillSupport.processing.timeout(job)
        end
        job.cancelled=true
        clearHold(job)
        job.movementReleased,job.background=true,true
        if job.ctx.bringEquipmentLock==job then
            job.ctx.bringEquipmentLock=nil
            job.ctx.questOwns=nil -- Release only this delivery's movement/equipment lease.
        end
        if job.pending or calls.drag or calls.shop or calls.wallet then return end
        if job.shop and not job.buySent and job.stockPlaced and job.stockOrigin and stock(job.item)
            and workspace:GetAttribute('InfiniteDepthOffsetMeters')==job.originOffset then
            if not job.owns and not job.stockReturnAttempted and not manual()then
                job.stockReturnAttempted=true;job.pending=true
                if not call('drag','DragService','Request',{job.item},function(ok,value,_,dispatch)
                    job.pending=nil;job.owns=dispatch~='not-sent' and (not ok or value==true);job.ownershipConfirmed=ok and value==true
                    if ok and value==true and s.questDelivery==job and not manual() and stock(job.item)
                        and workspace:GetAttribute('InfiniteDepthOffsetMeters')==job.originOffset then
                        local moved=pcall(job.item.PivotTo,job.item,job.stockOrigin)
                        if moved then job.stockPlaced=false else setStatus('Unpaid stock return failed; checkout may remain occupied')end
                    else setStatus('Unpaid stock return unconfirmed; checkout may remain occupied')end
                    release(job)
                end,function()return api.owned() and s.questDelivery==job and stock(job.item) and not manual()end)then job.pending=nil end
                return
            elseif job.owns and job.ownershipConfirmed and not manual()then
                local moved=pcall(job.item.PivotTo,job.item,job.stockOrigin)
                if moved then job.stockPlaced=false end
            end
        end
        if not job.owns then if s.questDelivery==job then s.questDelivery=nil end; return end
        if manual() then setStatus('Quest release waits for manual drag'); return end
        if job.releaseFailed then return end
        call('drag','DragService','Cancel',{job.kind~='fuel-cargo'},function(ok,value,_,dispatch)
            if dispatch=='not-sent'then return end -- The owned lease still needs a later safe release.
            if ok and value~=false then
                job.owns=false; if s.questDelivery==job then s.questDelivery=nil end
            else job.releaseFailed=true; setStatus('Quest drag release unconfirmed; deliveries paused') end
        end,function()return api.owned() and s.questDelivery==job and job.owns and not manual()end)
    end
    function Q.cleanup(ctx)
        if Q.parasite then pcall(Q.parasite.stop,ctx)end
        if Q.drillSupport and Q.drillSupport.processing then pcall(Q.drillSupport.processing.cleanup,ctx)end
        if Q.special then pcall(Q.special.cleanup,ctx)end
        if Q.loadout then pcall(Q.loadout.stopped,ctx)end
        if Q.healing then pcall(Q.healing.cleanup,ctx)end
        if Q.drillSupport then pcall(Q.drillSupport.cleanup,ctx)end
        pcall(Q.stopDrive,ctx)
        Q.clearLootStop(ctx)
        if s.questDelivery and s.questDelivery.ctx==ctx then pcall(release,s.questDelivery) end
        if s.questCashJob and s.questCashJob.ctx==ctx then
            s.questCashJob.cancelled=true
            s.questCashJob.movementHeld=nil
            if not calls.cash then s.questCashJob=nil end
        end
        ctx.questOwns,ctx.questCombat,ctx.questWeapon,ctx.questWeaponClass,ctx.questAimHead=nil,nil,nil,nil,nil
        ctx.questStartup=nil;ctx.questRecovering=nil;ctx.questThreat=nil;ctx.questFuelThreat=nil;ctx.questChestTaking=nil;ctx.questChestDue=nil
        ctx.questPotionUsing=nil
        ctx.questRecoveryDue=nil
        ctx.questExitCombat=nil
        ctx.questDamageWatch=nil;ctx.questTargetRetry=nil
        ctx.questSeatExit=nil
        ctx.questWallWork=nil;ctx.questWallRetryAt=nil
        Q.refuelActive(ctx) -- OFF/extraction retire the latch; same-drill recovery preserves it.
        if not ctx.currentChest then ctx.questChestLease=nil end
    end
    function Q.abortResources(ctx)
        if s.questDelivery and s.questDelivery.ctx==ctx then release(s.questDelivery)end
        if s.questCashJob and s.questCashJob.ctx==ctx then
            s.questCashJob.cancelled=true
            if s.questCashJob.movementHeld then ctx.questOwns=nil;s.questCashJob.movementHeld=nil end
            if not calls.cash then s.questCashJob=nil end
        end
    end
    local function free(item,allowFuelOre)
        if Q.fuelCargo and Q.fuelCargo.reserved(item)then return false end
        if not api.free(item) or not api.part(item) or item:GetAttribute('Welded') or api.tag(item,'Welded')
            or item:GetAttribute('Placed') or item:GetAttribute('CraftedPlaceable')
            or api.tag(item,'Ore') and item:FindFirstChild('Health')~=nil
            or api.tag(item,'Ore') and not (allowFuelOre and (api.id(item)=='Ore_Coal' or api.id(item)=='Ore_VoidCoal') and (tonumber(api.attr(item,'Fuel')) or 0)>0
                or allowFuelOre=='sale' and not item:FindFirstChild('Health') and (api.id(item)=='Ore_Iron' or api.id(item)=='Ore_Gold'
                    or api.id(item)=='IronBar' or api.id(item)=='GoldBar'
                    or s.itemCategories and s.itemCategories.Gems and s.itemCategories.Gems[api.id(item)]==true)) then return false end
        local owner=tonumber(item:GetAttribute('OwnerUserId'))
        return not owner or owner==0 or owner==api.Players.LocalPlayer.UserId
    end
    function Q.protectedStarter(item)
        if s.questProtectedCatalog~=s.questCatalog or not s.questProtectedIds then
            s.questProtectedCatalog=s.questCatalog; s.questProtectedIds={}
            local function collect(t)
                if type(t)=='string' then s.questProtectedIds[t]=true
                elseif type(t)=='table' then for _,v in pairs(t) do collect(v) end end
            end
            for _,entry in pairs(s.questCatalog or {}) do
                if type(entry)=='table' then collect(entry.StarterArmor); collect(entry.StarterTools) end
            end
        end
        return s.questProtectedIds[api.id(item)]==true
    end
    function Q.gold(item,ctx,snapshot)
        if item and ctx and ctx.questHealing and Q.healing.isMedical(item)then return false end
        if not free(item,'sale') then return false end
        local id=api.id(item)
        local value=tonumber(api.attr(item,'Value'))
        if not finite(value) or value<100 then return false end
        if Q.protectedRelic(item) or (tonumber(api.attr(item,'Fuel')) or 0)>0 and Q.fuelNeeded() or api.tag(item,'MoneySack')
            or id=='Money_Sack' or id=='Flintlock' or id=='Sword_Pirate' or Q.protectedStarter(item)then return false end
        local isGold=s.itemCategories and s.itemCategories.GoldenItems and s.itemCategories.GoldenItems[id]==true
        -- User-confirmed live rule supplements the export's finite category list.
        for _,name in ipairs({id or '',item.Name or '',api.attr(item,'DisplayName') or '',item:GetAttribute('RealName') or ''}) do
            if type(name)=='string' and name:lower():find('gold',1,true) then isGold=true;break end
        end
        -- Never take carried gear, or a useful loose upgrade, to sell.
        return isGold and not (snapshot and snapshot(item) or not snapshot and api.useful(ctx,item))
    end
    function Q.sellPad(item)
        if not item or not item:IsA('BasePart') or item.Name~='SellPart' or not item.Parent
            or item.Parent.Name~='SellParts' or not item.Parent.Parent or item.Parent.Parent.Name~='TradingPost' then return false end
        local parent=item.Parent.Parent
        while parent and parent~=workspace do
            if parent.Name=='CraftingShack' or parent.Name=='SellSpot' then return false end
            parent=parent.Parent
        end
        return item:IsDescendantOf(workspace)
    end
    local function sellers(ctx)
        if now()<(ctx.questPadsAt or 0) then return ctx.questPads or {} end
        ctx.questPadsAt=now()+5; ctx.questPads={}
        local seen={}; ctx.questPosts=setmetatable(ctx.questPosts or {},{__mode='k'})
        local function loaded(item)return item and item.Parent and item:IsDescendantOf(workspace)end
        local function add(item)
            if not loaded(item) then return end
            if Q.sellPad(item) and not seen[item] then seen[item]=true;ctx.questPads[#ctx.questPads+1]=item end
            if item.Name=='TradingPost' then ctx.questPosts[item]=true end
        end
        -- Reuse the route's amortized world snapshot instead of another full scan.
        for _,item in ipairs(ctx.worldObjects or {}) do add(item) end
        for item in pairs(ctx.worldPending or {}) do add(item) end
        -- Model events can precede replication of their sell parts while the route
        -- is parked in a driving quest. Revisit only known posts, not all Workspace.
        for post in pairs(ctx.questPosts) do
            if not loaded(post) then ctx.questPosts[post]=nil
            else local parts=post:FindFirstChild('SellParts'); if parts then for _,item in ipairs(parts:GetChildren()) do add(item) end end end
        end
        return ctx.questPads
    end
    local function nearest(list,origin,predicate)
        local best,distance
        for _,item in ipairs(list) do
            local p=api.part(item)
            if p and (not predicate or predicate(item)) then
                local d=(p.Position-origin).Magnitude
                if not distance or d<distance then best,distance=item,d end
            end
        end
        return best
    end
    function Q.bestSeller(ctx,origin)
        local best,multiplier,distance
        for _,pad in ipairs(sellers(ctx))do
            if Q.sellPad(pad)then
                local amount=tonumber(pad:GetAttribute('Multiplier')) or 1
                local d=(pad.Position-origin).Magnitude
                if finite(amount) and amount>0 and (not multiplier or amount>multiplier or amount==multiplier and d<distance)then
                    best,multiplier,distance=pad,amount,d
                end
            end
        end
        return best
    end
    local function objective(plan,key) return tonumber(plan.counts and plan.counts[key]) or 0 end
    local function place(job)
        if job.kind=='smelt' and Q.drillSupport.processing.contactComplete(job)then return true end
        local p,target=api.part(job.item),api.part(job.target)
        if not p or not target or not job.owns then return false end
        if job.healingSupply and (not Q.healing.itemAccessible(job.ctx,job.item)
            or job.shop and api.medicalLocationAllowed and not api.medicalLocationAllowed(job.ctx,job.target))then return false end
        local cf,size
        if job.item:IsA('BasePart') then cf,size=job.item.CFrame,job.item.Size else cf,size=job.item:GetBoundingBox() end
        local offset
        if job.kind=='supply' and not job.shop then offset=CFrame.new(3,1,-4)
        elseif job.kind=='fuel' then offset=CFrame.new()
        else offset=CFrame.new(0,target.Size.Y*.5+size.Y*.5-.08,0)*cf:ToObjectSpace(job.item:GetPivot())end
        local goal=target.CFrame*offset
        if job.kind=='fuel' then
            -- Onboarding attachments are beam destinations, not intake proof.
            -- Put the item's actual bounds through the Furnace part, including
            -- models whose authored pivot sits well away from their ore mesh.
            goal=target.CFrame*cf:ToObjectSpace(job.item:GetPivot())
        end
        if job.kind=='smelt'then
            goal=Q.drillSupport.processing.goal(job)
            if not goal then return false end
            -- Conversion may destroy the ore or rename it during this contact.
            -- Finish input-only work first and never constrain the resulting bar.
            p.AssemblyLinearVelocity,p.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
            local before=job.processingContact
            job.processingContact=true
            local moved,why=pcall(job.item.PivotTo,job.item,goal)
            if not moved then
                if Q.drillSupport.processing.contactComplete(job)then return true end
                job.processingContact=before;error(why,0)
            end
            Q.drillSupport.processing.contactComplete(job)
            return true
        end
        job.item:PivotTo(goal)
        p.AssemblyLinearVelocity,p.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
        if not job.constraints then
            job.constraints={}
            local function create(class,parent)
                local object=Instance.new(class);job.constraints[#job.constraints+1]=object
                object.Name,object.Parent='EarthQuestDelivery',parent;return object
            end
            local attachment=create('Attachment',p);attachment.CFrame=p.CFrame:ToObjectSpace(job.item:GetPivot())
            local destination=create('Attachment',target);destination.CFrame=target.CFrame:ToObjectSpace(goal)
            local align=create('AlignPosition',p);align.Attachment0,align.Attachment1=attachment,destination
            align.Responsiveness,align.MaxForce,align.RigidityEnabled,align.ReactionForceEnabled=45,45000,false,false
            local orientation=create('AlignOrientation',p);orientation.Attachment0,orientation.Attachment1=attachment,destination
            orientation.Responsiveness,orientation.MaxTorque,orientation.RigidityEnabled,orientation.ReactionTorqueEnabled=45,500000,false,false
        end
        return true
    end
    local function startDelivery(ctx,item,target,kind,plan)
        if s.questDelivery or calls.drag or s.bringDelivery or s.lootRequest or s.equipmentRequest or manual() then return false end
        local function eligible()
            return free(item,(kind=='gold' or kind=='sale' or kind=='smelt' or kind=='supply' and plan.processingCarry) and 'sale' or kind=='fuel')
                and (kind~='gold' or Q.gold(item,ctx))
                and (kind~='sale' or Q.drillSupport.saleEligible(item,ctx,nil,plan.objective))
                and (kind~='shred' or Q.special.scrapEligible(item,ctx))
                and (not plan.processingFunding or Q.drillSupport.processing.fundingEligible(item,ctx))
                and (not plan.processingCarry or kind=='supply' and target==ctx.root and api.hasRoom(ctx,item)
                    and Q.drillSupport.processing.inputEligible(item,ctx))
                and (kind~='smelt' or Q.drillSupport.processing.inputEligible(item,ctx)
                    and Q.drillSupport.processing.processor(target,ctx))
                and (kind~='supply' or not Q.healing.isMedical(item) or Q.healing.itemAccessible(ctx,item))
        end
        if not eligible()then return false end
        local job={ctx=ctx,item=item,target=target,kind=kind,started=now(),stage='request',objective=plan.objective,
            before=kind=='fuel' and tonumber(ctx.drill:GetAttribute('Fuel')) or objective(plan,plan.objective or 'SellGoldItems'),class=plan.name,
            questBefore=objective(plan,plan.objective or 'SellGoldItems'),coinBefore=s.stats.coinEarned or 0,moneyBefore={}}
        job.healingSupply=kind=='supply' and ctx.questHealing and Q.healing.isMedical(item) or nil
        if kind=='fuel'then job.fuelLow=job.before end
        job.processingFunding=plan.processingFunding==true
        job.processingCarry=plan.processingCarry==true
        if kind=='smelt'then
            job.processing=Q.drillSupport.processing.capture(ctx,item,target)
            if not job.processing then return false end
        end
        local salePart=api.part(target)
        job.salePosition=salePart and salePart.Position
        job.saleBand=tonumber(workspace:GetAttribute('InfiniteDepthOffsetMeters')) or 0
        for _,bag in ipairs(api.tagged('MoneySack'))do job.moneyBefore[bag]=true end
        if kind=='shred'then local c=api.controller('CraftingController');job.scrapBefore=tonumber(c and c.ScrapCount) or tonumber(s.questCraftState and s.questCraftState.ScrapCount)end
        s.questDelivery=job; ctx.bringEquipmentLock=job
        job.pending=true
        if not call('drag','DragService','Request',{item},function(ok,value,_,dispatch)
            job.pending=nil; job.owns=dispatch~='not-sent' and (not ok or value==true);job.ownershipConfirmed=ok and value==true
            if not job.owns then retries[item]=now()+15 end
            if not ok or not job.owns or job.cancelled or not enabled(ctx) then release(job); return end
            if not free(item,(kind=='gold' or kind=='sale' or kind=='smelt' or job.processingCarry) and 'sale' or kind=='fuel') or kind=='gold' and not Q.gold(item,ctx)
                or kind=='sale' and not Q.drillSupport.saleEligible(item,ctx,nil,job.objective)
                or kind=='shred' and not Q.special.scrapEligible(item,ctx)
                or job.processingFunding and not Q.drillSupport.processing.fundingEligible(item,ctx)
                or job.processingCarry and (not Q.drillSupport.processing.inputEligible(item,ctx) or not api.hasRoom(ctx,item))
                or kind=='smelt' and (not Q.drillSupport.processing.inputEligible(item,ctx)
                    or not Q.drillSupport.processing.processor(target,ctx))then release(job); return end
            local moved,result=pcall(place,job)
            if not moved or not result then release(job); return end
            job.stage,job.readyAt='placed',now()+.55
        end,function()return enabled(ctx) and s.questDelivery==job and not job.cancelled
            and not api.extractionReady() and eligible() and not manual()end) then
            job.pending=nil; s.questDelivery=nil; ctx.bringEquipmentLock=nil; return false
        end
        return true
    end
    local function deliveryStep(ctx,plan)
        local job=s.questDelivery; if not job then return false end
        if job.kind=='fuel-cargo'then return Q.fuelCargo.step(ctx,plan,job)end
        if job.ctx==ctx and job.kind=='smelt' and job.dropToken and job.dropToken.called
            and Q.drillSupport.processing.receipt(job)then
            job.processingConfirmed=true
            -- Contact can produce a bar before Cancel executes. That output
            -- cannot authorize a successor drag while the global drop is unknown.
            if not job.dropOutcomeKnown or calls.drag==job.dropToken then
                if now()-job.started>12 then release(job)end
                return true
            end
            if Q.retireConfirmedCall('drag',job.dropToken)then
                job.pending=nil;job.owns=false;retries[job.item]=math.huge;clearHold(job)
                if s.questDelivery==job then s.questDelivery=nil end
                if ctx.bringEquipmentLock==job then ctx.bringEquipmentLock=nil;ctx.questOwns=nil end
                setStatus('Native furnace bar output confirmed; collecting its actual sale receipt next')
            end
            return true
        end
        if job.ctx==ctx and job.kind=='supply' and job.buySent and Q.purchaseReceipt(job) and job.cancelled then
            release(job);return true
        end
        -- A late real inventory receipt settles only the exact dispatched pickup,
        -- even after its movement lease has been released on timeout.
        if job.ctx==ctx and ctx.character==api.Players.LocalPlayer.Character and job.kind=='supply'
            and job.pickupToken and job.pickupToken.called and Q.supplyReceipt(job)
            and (not job.item.Parent or job.item:IsDescendantOf(ctx.character)
                or api.Players.LocalPlayer:FindFirstChild('Backpack')
                    and job.item:IsDescendantOf(api.Players.LocalPlayer:FindFirstChild('Backpack')))then
            if Q.retireConfirmedCall('drag',job.pickupToken)then
                job.pending=nil;retries[job.item]=math.huge
                setStatus('Quest supply pickup confirmed');release(job)
            end
            return true
        end
        if job.kind=='fuel'then
            local tank=tonumber(ctx.drill:GetAttribute('Fuel'))
            if finite(tank)then
                if finite(job.fuelLow) and tank>job.fuelLow+.01 then job.fuelReceipt=true end
                job.fuelLow=math.min(job.fuelLow or tank,tank)
            end
        end
        if job.kind=='fuel' and (plan.kind~='fuel' and (plan.kind~='depth' or not cfg.driveDepth))
            and not Q.refuelActive(ctx)then release(job);return true end
        -- A confirmed native drop ends ownership. Its replication receipt gets
        -- a separate window; slow Request/Cancel replies cannot consume it.
        local receiptOnly=job.stage=='receipt' and job.droppedAt and not job.owns and not job.pending
            and job.kind~='smelt' and not job.shop
        if job.ctx~=ctx or not enabled(ctx) or manual() or not receiptOnly and now()-job.started>(job.shop and 25 or 12)
            or job.healingSupply and not Q.healing.itemAccessible(ctx,job.item)then release(job); return true end
        if job.cancelled then release(job); return true end
        if job.pending or not receiptOnly and (calls.shop or calls.wallet) then return true end
        if job.shop then return Q.shopStep(job,plan) end
        if job.kind=='supply' and job.stage=='placed' and now()>=job.readyAt then
            if Q.healing.isMedical(job.item) and not api.hasRoom(ctx,job.item)then
                Q.healing.makeRoom(ctx,job.item);return true
            end
            job.stage='pickup'; job.receiptUntil=now()+5
            job.pending=true
            if call('drag','InteractionService','Interact',{job.item},function(_,_,_,dispatch)
                job.pending=nil
                job.stage=dispatch=='not-sent' and 'placed' or 'receipt'
            end,function()return enabled(ctx) and s.questDelivery==job and not job.cancelled
                and not api.extractionReady() and not manual()
                and free(job.item,job.processingCarry and 'sale') and job.owns
                and (not job.processingCarry or Q.drillSupport.processing.inputEligible(job.item,ctx) and api.hasRoom(ctx,job.item))end)then job.pickupToken=calls.drag
            else job.pending=nil end
        end
        if job.kind=='supply' then
            if Q.supplyReceipt(job) then
                retries[job.item]=math.huge; setStatus('Quest supply pickup confirmed'); release(job)
            elseif now()-job.started>8 then retries[job.item]=now()+120; release(job) end
            return true
        end
        if job.stage=='placed' and now()>=job.readyAt then
            job.stage='receipt'; job.receiptUntil=now()+5
            pcall(place,job);clearHold(job)
            local sent,dropToken=call('drag','DragService','Cancel',{true},function(ok,value,_,dispatch)
                if dispatch=='not-sent'then
                    job.stage='placed';job.readyAt=now()+.3
                    return -- Retain our old lease for a later safe release.
                end
                if job.kind=='smelt'then job.dropOutcomeKnown=ok==true end
                if ok and value~=false then
                    job.owns=false
                    if ctx.bringEquipmentLock==job then ctx.bringEquipmentLock=nil;ctx.questOwns=nil end
                    job.background=true
                    if job.kind~='smelt' and not job.cancelled then
                        job.droppedAt=now();job.receiptUntil=job.droppedAt+8
                    end
                else job.releaseFailed=true; release(job) end
            end,function()return api.owned() and s.questDelivery==job and job.owns and not job.cancelled and not manual()end)
            if sent and job.kind=='smelt'then job.dropToken=dropToken end
        elseif job.stage=='receipt' then
            if calls.drag or job.owns then return true end
            if job.kind=='smelt'then
                if Q.drillSupport.processing.receipt(job)then
                    retries[job.item]=math.huge;clearHold(job);s.questDelivery=nil
                    if ctx.bringEquipmentLock==job then ctx.bringEquipmentLock=nil;ctx.questOwns=nil end
                    setStatus('Native furnace bar output confirmed; collecting its actual sale receipt next')
                elseif now()>=job.receiptUntil then
                    Q.drillSupport.processing.timeout(job);clearHold(job);s.questDelivery=nil
                    if ctx.bringEquipmentLock==job then ctx.bringEquipmentLock=nil;ctx.questOwns=nil end
                end
                return true
            end
            local count=job.kind=='fuel' and tonumber(ctx.drill:GetAttribute('Fuel'))
                or plan.name==job.class and objective(plan,job.objective or 'SellGoldItems')
            local questReceipt=plan.name==job.class and (sales[job.objective] or job.objective=='ContributeFuel')
                and objective(plan,job.objective)>job.questBefore
            local c=job.kind=='shred' and api.controller('CraftingController')
            local scrap=tonumber(c and c.ScrapCount) or tonumber(s.questCraftState and s.questCraftState.ScrapCount)
            local shredReceipt=job.kind=='shred' and not job.item.Parent and finite(scrap) and finite(job.scrapBefore) and scrap>job.scrapBefore
            if shredReceipt or questReceipt or job.kind=='fuel' and job.fuelReceipt or job.kind=='sale' and Q.drillSupport.saleReceipt(job)
                or job.kind~='sale' and finite(count) and finite(job.before) and count>job.before then
                setStatus(job.kind=='shred' and 'Native scrap credit confirmed; observing Cogs-worth quest progress' or job.kind=='fuel' and 'Drill fuel increase confirmed' or job.kind=='sale' and 'Sale receipt confirmed; observing '..tostring(job.objective)..' counter' or 'Gold-sales quest progress confirmed')
                retries[job.item]=math.huge;clearHold(job);s.questDelivery=nil
                if ctx.bringEquipmentLock==job then ctx.bringEquipmentLock=nil;ctx.questOwns=nil end
            elseif now()>=job.receiptUntil then
                retries[job.item]=now()+120;clearHold(job);s.questDelivery=nil
                if ctx.bringEquipmentLock==job then ctx.bringEquipmentLock=nil;ctx.questOwns=nil end
                setStatus('Delivery did not confirm server progress; only this item waits 120s; other work continues')
            end
        end
        return true
    end
    local function looseItems() local folder=workspace:FindFirstChild('Items'); return folder and folder:GetChildren() or {} end
    local function fuelItem(ctx)
        local furnace=ctx.drill:FindFirstChild('Furnace')
        if not furnace or not api.part(furnace) then return end
        local item=nearest(looseItems(),ctx.root.Position,function(item)
            local value=tonumber(api.attr(item,'Fuel'))
            return free(item,true) and finite(value) and value>0 and not Q.protectedRelic(item)
                and now()>=(retries[item] or 0)
        end)
        return item,furnace
    end
    local function driveReady(ctx)
        if Q.refuelActive(ctx)then return false,'Refuelling to the current maximum; native tank is not full' end
        if now()<(ctx.questDriveRetryAt or 0) then return false,'Drill start failed; retry cooling down' end
        local tank,capacity=tonumber(ctx.drill:GetAttribute('Fuel')),tonumber(ctx.drill:GetAttribute('MaxFuel'))
        if not finite(tank) or not finite(capacity) or capacity<=0 then return false,'Drill fuel state loading' end
        if tank<=0 and fuelItem(ctx) then return true end
        if tank<=0 then return false,'No loaded free fuel for the drill' end
        local physical=ctx.drill:FindFirstChild('DrillPhysicsSeat') or ctx.drill:FindFirstChild('VehicleSeat')
        local presentation=ctx.drill:FindFirstChild('LocalDriverSeat')
        if not presentation and physical and physical:IsA('VehicleSeat') then presentation=physical end
        if not physical or not physical:IsA('BasePart') or not presentation or not presentation:IsA('VehicleSeat') then
            return false,'Native drill seats still loading'
        end
        local driver=driverId(ctx.drill)
        if driver~=nil and driver~=api.Players.LocalPlayer.UserId then return false,'Another player is driving' end
        return true
    end
    local function fuel(ctx,plan)
        local tank=tonumber(ctx.drill:GetAttribute('Fuel'))
        local capacity=tonumber(ctx.drill:GetAttribute('MaxFuel'))
        if not finite(tank) or not finite(capacity) or capacity<=0 or tank>=capacity
            or tank>0 and plan.kind~='fuel' and not Q.refuelActive(ctx,plan) then return false end
        local item,furnace=fuelItem(ctx)
        if item then
            if not ctx.questDriving then Q.stopDrive(ctx)end
            if startDelivery(ctx,item,furnace,'fuel',plan) then
            setStatus('Refuelling through Drill.Furnace; awaiting tank increase'); return true
            end
        end
        -- Low positive fuel remains usable; an empty tank without a deliverable
        -- fuel item is handled by preflight without taking the chest route.
        return not item and Q.fuelCargo.retrieve(ctx,plan) or false
    end
    local function holdRoute(ctx)
        if ctx.currentChest or ctx.featureHold or ctx.defenseMoving or now()<(ctx.dodgeUntil or 0)
            or s.bringDelivery or s.lootRequest or s.equipmentRequest then return false end
        if not ctx.questOwns then api.cancelTravel(ctx)end
        ctx.questOwns=true
        return ctx.routeParked==true
    end
    local function abandonDrive(ctx,seat,reason)
        Q.stopDrive(ctx);ctx.questDriveRetryAt=now()+30;ctx.questOwns=nil;s.questIdle=true
        -- Leave the native <=3-stud auto-start area once no seat weld holds us.
        if not ctx.humanoid.SeatPart then
            api.hover(ctx);ctx.root.CFrame=seat.CFrame*CFrame.new(0,5,12)
        end
        setStatus(reason..'; chest farming continues');return false
    end
    function Q.wallEstimate(ctx,wall)
        local node,drill=wall.node,ctx.drill
        local hp=node and tonumber(node:GetAttribute('Health'))
        if not finite(hp) or hp<=0 then
            wall.rate=nil;wall.health=nil;wall.lastHitAt=nil;wall.firstHitAt=nil;wall.damageTotal=0
            wall.eta=nil;wall.estimateSource=nil;return
        end
        local power=tonumber(drill:GetAttribute('DrillPower') or 0)
        local bonus=tonumber(drill:GetAttribute('BonusDamage') or 0)
        local rpm=tonumber(drill:GetAttribute('RPMOverclock') or 0)
        local damage=finite(power) and finite(bonus) and 1+power+bonus
        -- These are the native WALL DAMAGE / DRILL HITS / S UI formulas.
        -- Observed same-wall damage below accounts for actual class/boost effects.
        local hits=finite(rpm) and rpm>=0 and 1+.05*rpm
        local signature=table.concat({tostring(power),tostring(bonus),tostring(rpm),
            tostring(drill:GetAttribute('LastBoost')),tostring(drill:GetAttribute('CraftedDrillBoostActive')),
            tostring(drill:GetAttribute('CraftedDrillBoostPowerMultiplier'))},':')
        local previous=wall.health
        local changed=wall.signature~=signature or not finite(previous) or hp>previous
        local loss=finite(previous) and hp<previous and previous-hp or 0
        if changed then wall.rate=nil;wall.lastHitAt=nil;wall.firstHitAt=nil;wall.damageTotal=0 end
        if loss>0 then
            wall.progressAt=now();ctx.questProgressAt=now();s.questStalled=nil
            if ctx.questDriveWatch then ctx.questDriveWatch.progressAt=now()end
            if wall.lastHitAt and now()-wall.lastHitAt>=.05 then
                wall.damageTotal=(wall.damageTotal or 0)+loss
                local elapsed=now()-(wall.firstHitAt or wall.lastHitAt)
                if elapsed>=.05 then wall.rate=wall.damageTotal/elapsed end
            else
                -- A first immediate hit or zero-time replication burst cannot
                -- establish a trustworthy hits-per-second measurement.
                wall.rate=nil;wall.firstHitAt=now();wall.damageTotal=0
            end
            wall.lastHitAt=now()
        end
        wall.signature,wall.health=signature,hp
        local fresh=wall.lastHitAt and now()-wall.lastHitAt<=math.max(2,finite(hits) and hits>0 and 2/hits or 2)
        if fresh and finite(wall.rate) and wall.rate>0 then
            wall.estimateSource='observed damage';wall.eta=hp/wall.rate
        elseif finite(damage) and damage>0 and finite(hits) and hits>0 then
            wall.estimateSource='native drill stats';wall.eta=math.ceil(hp/damage)/hits
        else wall.eta=nil;wall.estimateSource=nil end
        return wall.eta
    end
    local function wallWork(ctx)
        local drill=ctx.drill;local wall=ctx.questWallWork
        if drill~=workspace:FindFirstChild('Drill') or not drill.Parent then ctx.questWallWork=nil;return false end
        local band=workspace:GetAttribute('InfiniteDepthOffsetMeters')
        if wall and (wall.drill~=drill or wall.band~=band)then ctx.questWallWork=nil;wall=nil end
        if drill:GetAttribute('IsDrilling')~=true then ctx.questWallWork=nil;return false end
        local tank,capacity=tonumber(drill:GetAttribute('Fuel')),tonumber(drill:GetAttribute('MaxFuel'))
        if not finite(tank) or tank<=0 or not finite(capacity) or capacity<=0 then return false end
        if not wall then
            if now()<(ctx.questWallRetryAt or 0)
                or not(ctx.questDriving or ctx.questSeating or driverId(drill)==api.Players.LocalPlayer.UserId)then return false end
            local origin=drill:GetPivot().Position
            local node=nearest(api.tagged('RockWall'),origin,function(item)
                local hp=tonumber(item:GetAttribute('Health'));local p=api.part(item)
                return item.Parent and item:IsDescendantOf(workspace) and finite(hp) and hp>0 and p
                    and (p.Position-origin).Magnitude<=160
            end)
            wall={drill=drill,band=band,node=node,health=node and tonumber(node:GetAttribute('Health')),
                progressAt=now(),started=now(),seat=drill:FindFirstChild('DrillPhysicsSeat') or drill:FindFirstChild('VehicleSeat')}
            ctx.questWallWork=wall
        end
        if wall.node and (not wall.node.Parent or not wall.node:IsDescendantOf(workspace)
            or finite(tonumber(wall.node:GetAttribute('Health'))) and tonumber(wall.node:GetAttribute('Health'))<=0)then
            ctx.questWallWork=nil;ctx.questWallRetryAt=now()+.75;return false
        end
        local eta=Q.wallEstimate(ctx,wall)
        -- A missing or unchanged signal is not proof that a drill is working.
        if now()-wall.progressAt>=15 then
            Q.stopDrive(ctx)
            ctx.questWallWork=nil;ctx.questWallRetryAt=now()+10
            setStatus('Wall drilling has no fresh damage receipt; allowing a bounded native driving retry')
            if ctx.humanoid.SeatPart then local _,holding=Q.unseat(ctx);return true,holding end
            return false
        end
        if not wall.detouring then
            local user=api.Players.LocalPlayer.UserId;local id=driverId(drill);local lease=s.questDriveLease
            local pending=calls.drive or lease and lease.abandoned and lease.stopIssued and lease.stopAccepted~=true
            if id~=user or pending then return false end
            if not finite(eta) or eta<=10 or now()-wall.started<2 then
                -- Let drive() service the actual seat, native throttle/keys,
                -- boosts and focused-text input; do not claim distance credit.
                return true,true,true
            end
            if humanDrivingInput(ctx)then
                ctx.questOwns=true;setStatus('Wall work yields to manual driving input');return true,true
            end
            wall.detouring=true
            Q.stopDrive(ctx)
        end
        local user=api.Players.LocalPlayer.UserId;local id=driverId(drill)
        local lease=s.questDriveLease
        if lease and lease.ctx==ctx and lease.drill==drill and lease.confirmed and id~=user and not calls.drive then
            s.questDriveLease=nil;lease=nil
        end
        local attached=ctx.humanoid.SeatPart
        local localSeat=drill:FindFirstChild('LocalDriverSeat')
        if attached and (attached==wall.seat or attached==localSeat) and id==user then
            if humanDrivingInput(ctx)then
                ctx.questOwns=true
                setStatus('Wall work yields to manual driving input; owned automation keys remain released')
                return true,true
            end
            Q.stopDrive(ctx)
        end
        if ctx.humanoid.SeatPart or ctx.humanoid.Sit then
            local _,holding=Q.unseat(ctx);api.watch(ctx)
            setStatus('Wall drilling continues; leaving the actual seat for chests and recovery')
            return true,holding
        end
        wall.released=true
        if wall.seat and wall.seat.Parent and (ctx.root.Position-wall.seat.Position).Magnitude<=3 then
            api.hover(ctx);ctx.root.CFrame=wall.seat.CFrame*CFrame.new(0,5,12)
        end
        ctx.questOwns=nil;s.questIdle=nil
        setStatus('Wall needs over 10 seconds; collecting chests and recovering while observing native damage')
        return true,false
    end
    local function throttleOwner(ctx,lease,drill,character,band)
        return api.owned() and ctx.active and s.farm==ctx and ctx.character==character
            and api.Players.LocalPlayer.Character==character and ctx.humanoid.Health>0
            and ctx.drill==drill and drill and drill.Parent and workspace:FindFirstChild('Drill')==drill
            and workspace:GetAttribute('InfiniteDepthOffsetMeters')==band
            and s.questDriveLease==lease and lease and lease.ctx==ctx and lease.drill==drill
            and lease.confirmed==true and not lease.abandoned and ctx.questDriving
            and driverId(drill)==api.Players.LocalPlayer.UserId
    end
    local function focusedText()
        local ok,uis=pcall(function()return game:GetService('UserInputService')end)
        if not ok or not uis or type(uis.GetFocusedTextBox)~='function'then return nil end
        local read,value=pcall(uis.GetFocusedTextBox,uis)
        if read then return value~=nil end
    end
    local function drive(ctx,plan)
        if plan.kind~='depth' or not cfg.driveDepth then Q.stopDrive(ctx);ctx.questOwns=nil;return false end
        if manual()then Q.stopDrive(ctx);ctx.questOwns=nil;setStatus('Quest driving yields to manual item work');return false end
        if ctx.drill~=workspace:FindFirstChild('Drill') or not ctx.drill.Parent then
            Q.stopDrive(ctx);ctx.questWallWork=nil;ctx.questOwns=nil;return false
        end
        local working,holding,quick=wallWork(ctx)
        if working and not quick then return holding end
        local stopping=s.questDriveLease
        -- The RPC lane outlives a retired/replaced drill lease. A pending or
        -- thrown-unknown stop cannot overlap a new script-owned driving session.
        if calls.drive or stopping and stopping.abandoned and stopping.stopIssued and stopping.stopAccepted~=true then
            clearThrottle(ctx);ctx.questOwns=nil
            setStatus('Previous native driver stop is unresolved; other work continues without another drive request');return false
        end
        if stopping and stopping.abandoned then
            if driverId(stopping.drill)==api.Players.LocalPlayer.UserId then
                clearThrottle(ctx);ctx.questOwns=nil
                setStatus('Native driver stop has not cleared server ownership; other work continues without another drive request');return false
            else s.questDriveLease=nil end
        end
        if not ctx.questDriving and fuel(ctx,plan) then return true end
        local ready,reason=driveReady(ctx)
        if not ready then
            Q.stopDrive(ctx);ctx.questOwns=nil;setStatus(reason..'; chest farming continues');return false
        end
        local seat=ctx.drill:FindFirstChild('DrillPhysicsSeat') or ctx.drill:FindFirstChild('VehicleSeat')
        local presentation=ctx.drill:FindFirstChild('LocalDriverSeat')
        if not presentation and seat and seat:IsA('VehicleSeat') then presentation=seat end
        if not seat or not seat:IsA('BasePart') or not presentation or not presentation:IsA('VehicleSeat') then
            setStatus('Native physical seat and local driver presentation still loading'); return
        end
        local user=api.Players.LocalPlayer.UserId; local driver=driverId(ctx.drill)
        if driver~=nil and driver~=user then setStatus('Drill belongs to another driver; waiting'); return end
        s.seatBlockedSince=nil -- Intentional quest driving is not a failed chest dismount.
        -- Remove hover forces before sitting. Never move the drill locally.
        api.releaseHover(ctx)
        if driver~=user then
            if not ctx.questSeating then
                ctx.humanoid.Sit,ctx.humanoid.Jump=false,false
                ctx.root.CFrame=seat.CFrame*CFrame.new(0,1,0); ctx.questSeating=now()
                if ctx.root.AssemblyLinearVelocity then ctx.root.AssemblyLinearVelocity=Vector3.zero end
                s.questDriveLease={ctx=ctx,drill=ctx.drill,started=now()}
            elseif now()-ctx.questSeating>=8 then
                return abandonDrive(ctx,seat,'Drill start not confirmed after 8s')
            elseif not ctx.humanoid.Sit and (ctx.root.Position-seat.Position).Magnitude>2.5
                and now()>=(ctx.questApproachAt or 0) then
                ctx.questApproachAt=now()+.5;ctx.humanoid.Jump=false
                ctx.root.CFrame=seat.CFrame*CFrame.new(0,1,0)
                if ctx.root.AssemblyLinearVelocity then ctx.root.AssemblyLinearVelocity=Vector3.zero end
            end
            -- Native TrainComponent checks the actual root within 3 studs every
            -- 0.1s, serializes StartDriving, then sits only on accepted server state.
            -- Do not race its request by seating early or issuing our own duplicate.
            setStatus('Approaching driver seat; native start awaiting server confirmation'); return true
        end
        local lease=s.questDriveLease
        if not lease or lease.ctx~=ctx or lease.abandoned then
            lease={ctx=ctx,drill=ctx.drill,started=now()};s.questDriveLease=lease
        end
        lease.confirmed=true
        ctx.questDriving=true; ctx.questSeating=ctx.questSeating or now()
        ctx.questSeatAckAt=ctx.questSeatAckAt or now()
        if ctx.drill:GetAttribute('IsDrilling')==true and now()>=(ctx.questWallRetryAt or 0)then
            Q.drillSupport.boost(ctx)
            local busy,waiting,quick=wallWork(ctx)
            if busy and not quick then return waiting end
        end
        if presentation.Occupant~=ctx.humanoid then
            ctx.humanoid.Jump=false;ctx.humanoid.Sit=true;pcall(function()presentation:Sit(ctx.humanoid)end)
        end
        -- TrainComponent.isLocalDriverContextValid requires the replicated
        -- driver ID and live character/seat instances, not Occupant/SeatPart.
        -- Local anchored presentation-seat occupancy can arrive later.
        local nativeInput=forwardInput(ctx)
        ctx.questDriveSessionAt=ctx.questDriveSessionAt or now()
        ctx.questSeats=ctx.questSeats or {}
        -- TrainComponent reads seat throttle when keyboard/thumbstick input is zero.
        -- Setting its physical/local presentation seats avoids fighting its 0.1s sender.
        for _,candidate in ipairs({presentation}) do
            if ctx.questSeats[candidate]==nil then ctx.questSeats[candidate]=candidate.ThrottleFloat end
            candidate.ThrottleFloat=1
        end
        mobileThrottle(ctx,presentation,lease)
        if now()>=(ctx.questThrottleAt or 0) then
            local drill,character,band,class=ctx.drill,ctx.character,workspace:GetAttribute('InfiniteDepthOffsetMeters'),s.classData and s.classData.SelectedClass
            if call('throttle','DrillService','UpdateDriverThrottle',{1},function()end,
                function()return throttleOwner(ctx,lease,drill,character,band) and enabled(ctx) and cfg.driveDepth
                    and class==(s.classData and s.classData.SelectedClass)
                    and (Q.plan(s.classData,s.questCatalog,true).kind=='depth' or plan.objective=='ContributeFuel'
                        and Q.plan(s.classData,s.questCatalog,true).kind=='fuel')
                    and not manual() and focusedText()==false and not api.extractionReady() and not ctx.questHealing
                    and not ctx.nativeGateMotion and not ctx.questMineEntry
                    and not(finite(ctx.humanoid.MaxHealth) and ctx.humanoid.Health<=ctx.humanoid.MaxHealth*.3)end)
                then ctx.questThrottleAt=now()+.25 end
        end
        local watch=ctx.questDriveWatch
        local band=workspace:GetAttribute('InfiniteDepthOffsetMeters')
        local depth=objective(plan,'TotalDepth')
        local distanceController=api.controller('DistanceController')
        local distance=distanceController and distanceController.CurrentLogicalDistance
        local distanceSource,epsilon='native',.05
        if not finite(distance)then
            -- A seat can bob sideways or oscillate without advancing. Measure
            -- only its forward route projection when native distance is absent.
            local start,finish=workspace:GetAttribute('Start_Position'),workspace:GetAttribute('End_Position')
            local read,projected,geometry=pcall(function()
                if not start or not finish then return end
                local axis=finish-start
                if not finite(axis.X) or not finite(axis.Y) or not finite(axis.Z) or axis.Magnitude<=.001 then return end
                return (seat.Position-start):Dot(axis.Unit),table.concat({start.X,start.Y,start.Z,finish.X,finish.Y,finish.Z},':')
            end)
            distance=read and finite(projected) and projected or seat.Position.X
            distanceSource=read and finite(projected) and 'route:'..geometry or 'route:x'
            epsilon=.5
        end
        if not watch then
            watch={distanceHigh=distance,distanceSource=distanceSource,band=band,depth=depth,progressAt=now(),started=now()}
            ctx.questDriveWatch=watch
        else
            local advanced=depth>watch.depth
            if watch.distanceSource~=distanceSource or watch.band~=band then
                -- Calibration/rebasing replaces the baseline; it is not proof
                -- of new distance and cannot postpone a failed-drive timeout.
                watch.distanceHigh,watch.distanceSource,watch.band=distance,distanceSource,band
            elseif finite(distance) and (not finite(watch.distanceHigh) or distance>watch.distanceHigh+epsilon)then
                watch.distanceHigh=distance;advanced=true
            end
            watch.depth=math.max(watch.depth,depth)
            if advanced then watch.progressAt=now();watch.moved=true;ctx.questDriveFailures=0 end
        end
        local drilling=ctx.drill:GetAttribute('IsDrilling')==true
        local stalled=now()-watch.progressAt
        if stalled>=(drilling and 60 or 15)then
            ctx.questDriveFailures=(ctx.questDriveFailures or 0)+1
            local retry=ctx.questDriveFailures>=3 and 30 or 3
            Q.stopDrive(ctx);ctx.questDriveRetryAt=now()+retry;ctx.questOwns=nil
            -- Allow native exit before returning to the <=3-stud auto-start area.
            if not ctx.humanoid.SeatPart then api.hover(ctx);ctx.root.CFrame=seat.CFrame*CFrame.new(0,5,12)end
            setStatus('Drill made no observed distance progress for '..math.floor(stalled)..'s; releasing drive and retrying in '..retry..'s')
            return false
        end
        local wall=ctx.questWallWork
        setStatus(drilling and (wall and finite(wall.eta) and string.format('Wall estimate %.1fs (%s); staying seated and driving',wall.eta,wall.estimateSource)
                or 'Wall damage rate loading; staying seated with bounded progress checks')
            or nativeInput and 'Driving drill with native forward input; observing distance and TotalDepth'
            or mobileInput() and 'Mobile native seat throttle; distance monitored'
            or 'Native forward input unavailable; seat throttle fallback, distance monitored')
        Q.drillSupport.boost(ctx)
        return true
    end
    local function refuelWork(ctx,plan)
        if not Q.refuelActive(ctx,plan)then return nil end
        if manual()then Q.stopDrive(ctx);ctx.questOwns=nil;return false end
        if plan.kind=='depth' and Q.drillSupport.depthMine and (Q.drillSupport.activeMine(ctx) or ctx.questMineEntry)
            and Q.drillSupport.depthMine(ctx,plan)then return true end
        local tank,capacity=tonumber(ctx.drill:GetAttribute('Fuel')),tonumber(ctx.drill:GetAttribute('MaxFuel'))
        if not finite(tank) or not finite(capacity) or capacity<=0 then
            Q.stopDrive(ctx);ctx.questOwns=nil;setStatus('Refuelling remains active; waiting for native Fuel / MaxFuel state')
            return false
        end
            Q.stopDrive(ctx)
            if ctx.humanoid.SeatPart or ctx.humanoid.Sit then local _,holding=Q.unseat(ctx);return holding end
            local seat=ctx.drill:FindFirstChild('DrillPhysicsSeat') or ctx.drill:FindFirstChild('VehicleSeat')
            if seat and seat:IsA('BasePart') and (ctx.root.Position-seat.Position).Magnitude<=3 then
                -- Coal selection and delivery receipts can take another pulse.
                -- Leave native proximity auto-start immediately after the real
                -- seat clears, so an empty drill cannot recapture that handoff.
                api.hover(ctx);ctx.root.CFrame=seat.CFrame*CFrame.new(0,5,12)
            end
            if Q.cashStep(ctx)then return true end -- Finish an already-owned bag receipt before fuel handoff.
            local job=s.questDelivery
            if job and job.ctx==ctx then
                deliveryStep(ctx,plan)
                if s.questDelivery and not(s.questDelivery.background and not s.questDelivery.owns
                    and not s.questDelivery.pending and not calls.drag)then return true end
            elseif job then return false end
            if not (api.findOwned(ctx,'Pickaxe_Void') or api.findTool(ctx,'Pickaxe')) and not fuelItem(ctx)
                and Q.loadout.step(ctx,plan)then
                setStatus('Refuelling until full; awaiting the owned startup pickaxe before mining coal')
                return true
            end
            if not s.questDelivery and fuelItem(ctx)then
                if not holdRoute(ctx)then return ctx.questOwns==true end
                if fuel(ctx,plan)then return true end
            end
            if not s.questDelivery and Q.fuelCargo.retrieve(ctx,plan)then return true end
            if Q.drillSupport.step(ctx,plan)then return true end
            ctx.questOwns=nil;setStatus(string.format('Refuelling %.0f / %.0f until full; %s; chest discovery continues',
                tank,capacity,s.questMiningProblem or 'searching for loaded coal / a ready mineshaft'))
            return false
    end
    local function depthWork(ctx,plan)
        if plan.kind~='depth' or not cfg.driveDepth or manual()then return nil end
        if ctx.drill~=workspace:FindFirstChild('Drill') or not ctx.drill.Parent then
            Q.stopDrive(ctx);ctx.questWallWork=nil;ctx.questOwns=nil;return false
        end
        if Q.drillSupport.depthMine and (Q.drillSupport.activeMine(ctx) or ctx.questMineEntry)
            and Q.drillSupport.depthMine(ctx,plan)then return true end
        local refilling=refuelWork(ctx,plan)
        if refilling~=nil then return refilling end
        local economy=ctx.questDepthEconomy
        local explore=economy and economy.fundingExplore and now()>=(ctx.questFundingMineProbeAt or 0)
        if explore then ctx.questFundingMineProbeAt=now()+3 end
        if explore and Q.drillSupport.depthMine and Q.drillSupport.depthMine(ctx,plan)then
            economy.phase,economy.fundingExplore,economy.emptyAt='funding',nil,nil
            return true
        end
        local working,holding,quick=wallWork(ctx)
        if working and not quick then return holding and true or nil end
        if not quick and not economy and Q.drillSupport.depthMine and Q.drillSupport.depthMine(ctx,plan)then return true end
        if Q.drillSupport.inDungeon(ctx) or now()<(ctx.questDriveDetourUntil or 0)then return nil end
        local ready,reason=driveReady(ctx)
        if not ready then Q.stopDrive(ctx);ctx.questOwns=nil;setStatus(reason..'; other work continues');return false end
        local job=s.questDelivery
        if job and job.ctx==ctx and (job.kind=='fuel' or job.background)then deliveryStep(ctx,plan)
        elseif job then return nil end
        if s.questCashJob or ctx.questPotionUsing or ctx.questMineEntry then return nil end
        do
            local ok,uis=pcall(function()return game:GetService('UserInputService')end)
            if ok and uis and type(uis.GetFocusedTextBox)=='function' and uis:GetFocusedTextBox()then
                clearThrottle(ctx);ctx.questDrivePausedAt=ctx.questDrivePausedAt or now()
                if driverId(ctx.drill)==api.Players.LocalPlayer.UserId and now()>=(ctx.questThrottleAt or 0)then
                    local lease,drill,character,band=s.questDriveLease,ctx.drill,ctx.character,workspace:GetAttribute('InfiniteDepthOffsetMeters')
                    if call('throttle','DrillService','UpdateDriverThrottle',{0},function()end,
                        function()return throttleOwner(ctx,lease,drill,character,band) and focusedText()==true end)
                        then ctx.questThrottleAt=now()+.25 end
                end
                setStatus('Driving input paused while a text box is focused');return true
            end
        end
        if ctx.questDrivePausedAt then
            local paused=now()-ctx.questDrivePausedAt;ctx.questDrivePausedAt=nil
            if ctx.questDriveWatch then ctx.questDriveWatch.progressAt=ctx.questDriveWatch.progressAt+paused end
            if ctx.questDriveSessionAt then ctx.questDriveSessionAt=ctx.questDriveSessionAt+paused end
        end
        if not holdRoute(ctx)then return ctx.questOwns==true end
        -- The economy scheduler owns the 150s drive / 60s loot cadence.
        -- Nearby chest polls must not preempt the driving interval every 30s.
        Q.drillSupport.stopMine(ctx)
        local tank,capacity=tonumber(ctx.drill:GetAttribute('Fuel')),tonumber(ctx.drill:GetAttribute('MaxFuel'))
        if not s.questDelivery and finite(tank) and finite(capacity) and tank<=capacity*.2 then
            local item,furnace=fuelItem(ctx)
            if item and startDelivery(ctx,item,furnace,'fuel',plan) and not ctx.questDriving then return true end
        end
        return drive(ctx,plan)
    end
    function Q.darknessActive()
        -- DarknessUtil.IsActive: Lighting.Event==Night OR the player's
        -- InDarknessZone flag; clock time and a dark-looking screenshot differ.
        local lighting=game:GetService('Lighting')
        return lighting and lighting:GetAttribute('Event')=='Night'
            or api.Players.LocalPlayer:GetAttribute('InDarknessZone')==true
    end
    function Q.armTarget(ctx,npc)
        local h=npc and npc:FindFirstChildOfClass('Humanoid')
        if not h then return end
        ctx.questDamageWatch=ctx.questDamageWatch or setmetatable({}, {__mode='k'})
        if not ctx.questDamageWatch[npc]then
            ctx.questDamageWatch[npc]={health=h.Health,progressAt=now(),selectedAt=now(),attempts=0}
        end
    end
    function Q.attackStatus(ctx,text)
        local wait=ctx.questCombatWait
        return wait and wait.target==ctx.combatTarget and text..'; '..wait.reason or text
    end
    function Q.targetResponsive(ctx,npc)
        if api.questTargetAllowed and not api.questTargetAllowed(ctx,npc)then return false end
        local check=ctx.questDamageWatch and ctx.questDamageWatch[npc]
        local h=npc:FindFirstChildOfClass('Humanoid')
        if check and h then
            if h.Health<check.health then check.health,check.progressAt,check.attempts=h.Health,now(),0
            elseif check.attempts>=3 and now()-check.progressAt>=10
                or now()-(check.lastAttempt or check.selectedAt or now())>=12 then
                ctx.questTargetRetry=ctx.questTargetRetry or setmetatable({}, {__mode='k'})
                ctx.questTargetRetry[npc]={untilAt=now()+10,health=h.Health}
                ctx.questDamageWatch[npc]=nil
                if ctx.combatTarget==npc then ctx.combatTarget=nil end
                setStatus(check.attempts>=3 and 'Quest target took no damage for 10s; trying other loaded work'
                    or Q.attackStatus(ctx,'Quest attack did not dispatch for 12s; releasing the target'))
                return false
            end
        end
        return true
    end
    local function combatTarget(ctx,plan,gun)
        if plan.objective=='DarknessEnemyKills' and not Q.darknessActive() then return nil end
        local best,score,bestDistance
        local pickaxe=api.findOwned(ctx,'Pickaxe_Void') or api.findTool(ctx,'Pickaxe')
        local killGoal=plan.objective and (plan.objective:find('Kills',1,true) or plan.objective=='HeadShot')
        for _,npc in ipairs(api.enemies()) do
            local h=npc:FindFirstChildOfClass('Humanoid')
            local p=api.part(npc)
            local allowed=npc:GetAttribute('NpcFaction')~='FriendlyCompanion' and h and h.Health>0 and p
                and (not api.enemyAlive or api.enemyAlive(npc)) and (not api.questTargetAllowed or api.questTargetAllowed(ctx,npc))
                and (gun or api.swordTargetAllowed(npc) or api.weaponClass and api.weaponClass(ctx,npc)=='Pickaxe')
            if allowed and api.weaponClass and api.weaponClass(ctx,npc)=='Pickaxe' and not pickaxe then allowed=false end
            if allowed then allowed=Q.targetResponsive(ctx,npc)end
            if allowed and plan.objective=='VampireKills' then allowed=tostring(npc:GetAttribute('RealName') or npc.Name):find('Vampire',1,true)~=nil end
            if allowed and Q.special then allowed=Q.special.matchesPlan(npc,plan)end
            if allowed then
                local distance=(p.Position-ctx.root.Position).Magnitude
                -- Finishing low-health targets earns kill objectives sooner than
                -- camping a nearby boss. Damage objectives still prefer proximity.
                local value=killGoal and h.Health or distance
                if not score or value<score or value==score and distance<bestDistance then best,score,bestDistance=npc,value,distance end
            end
        end
        return best
    end
    local function combatWork(ctx,plan,override)
        if plan.kind~='combat' then return false end
        ctx.questCombat,ctx.questWeapon,ctx.questWeaponClass=true,plan.weapon,plan.weaponClass
        ctx.questAimHead=plan.objective=='HeadShot'
        local planGun=plan.weaponClass=='Gun' or plan.weaponClass=='Revolver' or plan.weaponClass=='Rifle' or plan.weaponClass=='Shotgun'
        local npc=override or combatTarget(ctx,plan,planGun)
        if not npc then ctx.combatTarget=nil;ctx.questCombat=nil;return false end
        ctx.combatTarget=npc
        local tool=Q.preferred(ctx);if not tool then return false end
        local class=api.attr(tool,'Class');local gun=class=='Revolver' or class=='Rifle' or class=='Shotgun'
        if gun and (tonumber(api.attr(tool,'Ammo')) or 0)<=0
            and (tonumber(api.Players.LocalPlayer:GetAttribute(class=='Revolver' and 'Pistol_Ammo' or class..'_Ammo')) or 0)<=0 then return false end
        Q.drillSupport.stopMine(ctx)
        s.questIdle=nil;s.questStalled=nil
        if not holdRoute(ctx) then return true end
        Q.stopDrive(ctx);ctx.combatTarget=npc;Q.armTarget(ctx,npc)
        local targetPart=api.part(npc);local point=targetPart.Position;local delta=ctx.root.Position-point
        local radius=gun and 30 or math.min(4,math.max(2.5,(tonumber(api.attr(tool,'Range')) or 12)*.35))
        local velocity=targetPart.AssemblyLinearVelocity
        local moving=not gun and velocity and finite(velocity.X) and finite(velocity.Z)
            and Vector3.new(velocity.X,0,velocity.Z) or Vector3.zero
        local predicted=point
        if moving.Magnitude>2 then predicted=point+moving.Unit*math.min(4,moving.Magnitude*.12)end
        local closing=(ctx.root.Position-predicted).Magnitude>radius+(gun and 2 or 1)
        if closing and not ctx.defenseMoving and now()>=(ctx.dodgeUntil or 0)
            and not (ctx.pendingThreat and ctx.pendingThreat.expires>now()) then
            api.hover(ctx)
            local side=Vector3.new(delta.X,0,delta.Z)
            if not gun and moving.Magnitude>2 then side=moving.Unit
            elseif side.Magnitude>.1 then side=side.Unit else side=Vector3.new(0,0,1)end
            local destination=predicted+side*radius+Vector3.new(0,1,0)
            ctx.root.CFrame=CFrame.lookAt(destination,Vector3.new(point.X,destination.Y,point.Z))
        end
        setStatus('Class quest: '..plan.objective..' using '..api.id(tool));return true
    end
    local function runnable(ctx,plan)
        if plan.objective=='DarknessEnemyKills' and not Q.darknessActive() then
            return false,'Darkness quest waits for Night or InDarknessZone'
        end
        if plan.kind=='combat' then
            ctx.questCombat,ctx.questWeapon,ctx.questWeaponClass=true,plan.weapon,plan.weaponClass
            ctx.questAimHead=plan.objective=='HeadShot'
        end
        if Q.moneyTarget(ctx) then return true end
        if plan.kind=='combat' then
            local tool=Q.preferred(ctx)
            if tool then
                local class=api.attr(tool,'Class');local gun=class=='Revolver' or class=='Rifle' or class=='Shotgun'
                local ammo=class=='Revolver' and 'Pistol_Ammo' or tostring(class)..'_Ammo'
                local armed=not gun or (tonumber(api.attr(tool,'Ammo')) or 0)>0 or (tonumber(api.Players.LocalPlayer:GetAttribute(ammo)) or 0)>0
                if armed and combatTarget(ctx,plan,gun) then return true end
                if not armed and Q.supplyReady(ctx,ammo) then return true end
            elseif plan.weapon and Q.supplyReady(ctx,plan.weapon) then return true end
        elseif plan.kind=='depth' then
            local seat=ctx.drill:FindFirstChild('DrillPhysicsSeat') or ctx.drill:FindFirstChild('VehicleSeat')
            if seat and now()-(ctx.questProgressAt or now())>=20 and api.findTool(ctx,'Sword') then
                for _,npc in ipairs(api.enemies()) do
                    local hp=npc:FindFirstChildOfClass('Humanoid');local p=api.part(npc)
                    if hp and hp.Health>0 and p and npc:GetAttribute('NpcFaction')~='FriendlyCompanion'
                        and (p.Position-seat.Position).Magnitude<=120 then return true end
                end
            end
        end
        local ready,reason=false,nil
        if plan.kind=='depth' and cfg.driveDepth then ready,reason=driveReady(ctx) end
        return ready,reason or 'No loaded quest target or supply'
    end
    Q.combatWork=combatWork
    local function drivingWeapon(ctx,plan,target)
        local job=ctx.questDrivingDefense
        local c=api.controller('ToolController');local active=c and c.ActiveTool
        local scene=api.controller('CutSceneController')
        if not job or job.target~=target or ctx.questThreat~=target or ctx.combatTarget~=target
            or not target or not target.Parent or not target:IsDescendantOf(workspace)
            or target:GetAttribute('NpcFaction')=='FriendlyCompanion'
            or not api.enemyAlive(target) or not api.questTargetAllowed(ctx,target)
            or job.character~=ctx.character or ctx.character~=api.Players.LocalPlayer.Character
            or job.drill~=ctx.drill or ctx.drill~=workspace:FindFirstChild('Drill')
            or job.band~=workspace:GetAttribute('InfiniteDepthOffsetMeters')
            or job.class~=(s.classData and s.classData.SelectedClass)
            or plan.kind=='combat' or plan.kind=='waiting' or not cfg.driveDepth or not enabled(ctx) or manual()
            or ctx.humanoid.MaxHealth>0 and ctx.humanoid.Health/ctx.humanoid.MaxHealth<=.3
            or ctx.questDriving or ctx.questSeating or ctx.humanoid.SeatPart or ctx.humanoid.Sit
            or ctx.questMining or ctx.questHealing or ctx.questStartup or ctx.questRecovering
            or ctx.questMineEntry or ctx.nativeGateMotion or ctx.bringEquipmentLock
            or s.bringDelivery or s.lootRequest or s.equipmentRequest or ctx.featureHold or ctx.currentChest
            or ctx.questHealAttempt or s.questMedicalDrop or ctx.questPotionUsing or ctx.questPreviewCancel
            or ctx.questPlacement or ctx.swingEdit or ctx.defenseMoving or now()<(ctx.dodgeUntil or 0)
            or Q.driveHandoff(ctx)
            or scene and (scene.CurrentCutScene or scene.AbortingCutScene)
            or not active or active._Destroyed or not active.Tool or active.Tool.Parent~=ctx.character
            or api.attr(active.Tool,'Tool')~=true or c.ServerEquipId==nil
            or active.Tool:GetAttribute('ServerToolEquipId')~=c.ServerEquipId
            or type(active.Swing)~='function' or type(active.CanUseAction)~='function'
            or type(active.RecordUseCooldown)~='function' or not active.Execute
            or type(active.Execute.Fire)~='function' then return end
        local backpack=api.Players.LocalPlayer:FindFirstChild('Backpack')
        local tool=active.DisplayTool
        local function matches(candidate)
            if not candidate or not candidate:IsA('Tool')
                or candidate.Parent~=ctx.character and candidate.Parent~=backpack then return false end
            local name=api.id(candidate)
            return active.Tool==candidate or active.Tool.Name==name
                or active.Tool.Name==name..tostring(api.Players.LocalPlayer.UserId)
        end
        if not matches(tool)then
            tool=nil
            for _,candidate in ipairs(api.ownedTools(ctx))do if matches(candidate)then tool=candidate;break end end
        end
        if not tool then return end
        local class=api.attr(tool,'Class')
        local compatible=api.weaponClass and api.weaponClass(ctx,target)
        if api.attr(active.Tool,'Class')~=class or class~='Sword' and class~='Pickaxe' or compatible and compatible~=class
            or class=='Sword' and not api.swordTargetAllowed(target)then return end
        local range=active.Range
        local bounds=api.sharedModule('MeleeSwingBounds')
        if not finite(range) or range<=0 or not bounds or type(bounds.GetModelHitPosition)~='function'then return end
        local ok,point=pcall(bounds.GetModelHitPosition,target,{Position=ctx.root.Position})
        if not ok or not point or (point-ctx.root.Position).Magnitude>math.min(range,45)then return end
        if job.weaponHandler~=active or job.weaponTool~=tool or job.weaponServerId~=c.ServerEquipId then
            local ready,value=pcall(api.readyAction,active)
            if not ready or not value then return end
            job.weaponHandler,job.weaponTool,job.weaponServerId=active,tool,c.ServerEquipId
        end
        -- Keep this proven current handler through its native swing cooldown.
        -- Replacing it immediately would recreate the unnecessary equip wait.
        return api.id(tool),class
    end
    function Q.required(ctx)
        if Q.parasite then
            local tool,class,strict=Q.parasite.required(ctx)
            if strict then return tool,class,strict end
        end
        if not cfg.classQuest then return nil,nil,false end
        local plan=Q.plan(s.classData,s.questCatalog,cfg.driveDepth)
        local threat=ctx.questThreat
        local liveThreat=threat and threat.Parent and (not api.enemyAlive or api.enemyAlive(threat))
            and (not api.isFuelLeech(threat) or Q.drillSupport.leechReady(ctx,threat))
        local target=liveThreat and threat or ctx.combatTarget
        local compatible
        if target and target.Parent and (not api.enemyAlive or api.enemyAlive(target))
            and (not api.questTargetAllowed or api.questTargetAllowed(ctx,target))then
            if api.weaponClass then compatible=api.weaponClass(ctx,target)
            elseif not api.swordTargetAllowed(target) or ctx.pickaxeTargets and ctx.pickaxeTargets[target]then compatible='Pickaxe' end
        end
        -- Native armor compatibility also applies to ordinary combat targets.
        -- The exact unfinished quest weapon resumes when this enemy clears.
        if compatible=='Pickaxe' then
            if api.findOwned(ctx,'Pickaxe_Void')then return 'Pickaxe_Void','Pickaxe',true end
            return nil,'Pickaxe',true
        end
        if liveThreat and ctx.questMineExitPickaxe==threat and ctx.questDepthMine
            and ctx.questDepthMine.mine==Q.drillSupport.activeMine(ctx)then
            if api.findOwned(ctx,'Pickaxe_Void')then return 'Pickaxe_Void','Pickaxe',true end
            return nil,'Pickaxe',true
        end
        -- Mining can supply fuel or fund a depth run while the primary class
        -- objective still requires another weapon. Both workers share this
        -- temporary pickaxe requirement until the mining handoff is released.
        if ctx.questMining then
            if api.findOwned(ctx,'Pickaxe_Void')then return 'Pickaxe_Void','Pickaxe',true end
            return nil,'Pickaxe',true
        end
        if plan.kind=='combat' then
            if not plan.weapon and plan.weaponClass=='Sword' and api.findOwned(ctx,'Sword_Void')then return 'Sword_Void','Sword',true end
            return plan.weapon,plan.weaponClass,true
        end
        if plan.name=='Pirate' and plan.kind~='combat' and not ctx.questThreat then return 'Sword_Void','Sword',true end
        if plan.kind=='waiting'then return nil,nil,true end
        if liveThreat then
            local held,class=drivingWeapon(ctx,plan,threat)
            if held then return held,class,true end
            if api.findOwned(ctx,'Sword_Void')then return 'Sword_Void','Sword',true end
            return nil,'Sword',true
        end
        if plan.kind=='mining' then
            if api.findOwned(ctx,'Sword_Void')then return 'Sword_Void','Sword',true end
            return nil,'Sword',true
        end
        if api.findOwned(ctx,'Sword_Void')then return 'Sword_Void','Sword',true end
        return nil,nil,false
    end
    function Q.preferred(ctx)
        local required,requiredClass,strict=Q.required(ctx)
        if not strict and ctx.questCombat then required,requiredClass,strict=ctx.questWeapon,ctx.questWeaponClass,true end
        if not strict then return nil,false end
        if not required and not requiredClass then return nil,true end
        local controller=api.controller('ToolController')
        local active=controller and controller.ActiveTool
        local display=active and active.DisplayTool
        local backpack=api.Players.LocalPlayer:FindFirstChild('Backpack')
        local function wanted(tool)
            local name=api.id(tool);local class=api.attr(tool,'Class')
            return required and (name==required or tool.Name==required..tostring(api.Players.LocalPlayer.UserId))
                or not required and (class==requiredClass or requiredClass=='Gun'
                    and (class=='Revolver' or class=='Rifle' or class=='Shotgun'))
        end
        if active and not active._Destroyed and active.Tool and active.Tool.Parent==ctx.character
            and (controller.ServerEquipId==nil or active.Tool:GetAttribute('ServerToolEquipId')==controller.ServerEquipId)then
            local function matches(tool)
                local name=api.id(tool)
                return active.Tool==tool or api.id(active.Tool)==name or active.Tool.Name==name
                    or active.Tool.Name==name..tostring(api.Players.LocalPlayer.UserId)
            end
            if display and display:IsA('Tool') and (display.Parent==ctx.character or display.Parent==backpack)
                and wanted(display) and matches(display)then return display,true end
            -- Sword/Pickaxe do not populate DisplayTool. Resolve their real
            -- inventory Tool before returning the already active native model.
            for _,container in ipairs({backpack,ctx.character})do
                if container then for _,tool in ipairs(container:GetChildren())do
                    if tool.Parent==container and tool:IsA('Tool') and wanted(tool) and matches(tool)then return tool,true end
                end end
            end
            if wanted(active.Tool)then return active.Tool,true end
        end
        -- Changing tools cancels native drag ownership. An unresolved request
        -- permits only the already active compatible handler above.
        if calls.drag then return nil,true end
        for _,container in ipairs({backpack,ctx.character}) do
            if container then for _,tool in ipairs(container:GetChildren()) do
                if tool.Parent==container and tool:IsA('Tool') and required and wanted(tool) then return tool,true end
            end end
        end
        -- A model can await its native handler, but cannot be an inventory
        -- EquipTool argument. Exclude only a proven old server representation.
        if required then
            for _,tool in ipairs(ctx.character:GetChildren())do
                if tool.Parent==ctx.character and tool:IsA('Model') and api.attr(tool,'Tool')==true and wanted(tool)
                    and (not api.canSelectEquipment or api.canSelectEquipment(ctx,tool))then return tool,true end
            end
        end
        if required then return nil,true end
        if requiredClass=='Sword' then
            for _,container in ipairs({backpack,ctx.character}) do
                if container then for _,tool in ipairs(container:GetChildren()) do
                    if api.id(tool)=='Sword_Void' and (not api.canSelectEquipment or api.canSelectEquipment(ctx,tool))then return tool,true end
                end end
            end
        end
        if requiredClass=='Gun' then
            local best,score
            for _,class in ipairs({'Revolver','Rifle','Shotgun'}) do
                local tool=api.findTool(ctx,class)
                if tool then
                    local ammo=class=='Revolver' and 'Pistol_Ammo' or class..'_Ammo'
                    local armed=(tonumber(api.attr(tool,'Ammo')) or 0)>0 or (tonumber(api.Players.LocalPlayer:GetAttribute(ammo)) or 0)>0
                    local value=(armed and 1e9 or 0)+(tonumber(api.attr(tool,'Damage')) or 0)*(tonumber(api.attr(tool,'FireRate')) or 1)
                    if not score or value>score then best,score=tool,value end
                end
            end
            return best,true
        end
        return requiredClass and api.findTool(ctx,requiredClass) or nil,true
    end
    function Q.chestTurn(ctx,plan)
        local delivery=s.questDelivery;local cash=s.questCashJob
        local visit=ctx.questDepthMine
        local mineTurn=visit and visit.mine and visit.class==(s.classData and s.classData.SelectedClass)
            and visit.mine==Q.drillSupport.activeMine(ctx)
        local detachedWork=ctx.questHealing or mineTurn
        local deliveryDetached=detachedWork and delivery and delivery.cancelled and delivery.movementReleased
            and not ctx.bringEquipmentLock
        local cashDetached=detachedWork and cash and cash.cancelled and not cash.movementHeld
        if not cfg.classQuest or not ctx.questChestCandidate or not api.chestCandidate or ctx.currentChest
            or ctx.featureHold or ctx.defenseMoving or ctx.dodgeUntil and now()<ctx.dodgeUntil
            or delivery and not deliveryDetached or cash and not cashDetached
            or s.bringDelivery or s.lootRequest or s.equipmentRequest
            or ctx.questMineEntry or ctx.questPotionUsing or Q.drillSupport.inDungeon(ctx) and not Q.drillSupport.activeMine()
                and not Q.special.bound(ctx) or Q.manual()
            or not Q.activePlan(plan) and not mineTurn then return false end
        ctx.questChestDue=ctx.questChestDue or now()+(ctx.questHealing and 0 or 8)
        if now()<ctx.questChestDue then return false end
        if not Q.holdRoute(ctx)then return true end
        ctx.questChestTaking=true;ctx.questChestLease=coroutine.running()
        setStatus('Checking loaded chests alongside class quests')
        local function eligible(entry)
            if not entry or not entry.Model or api.chestAllowed and not api.chestAllowed(entry.Model)then return false end
            if ctx.questHealing and api.healingChestSafe and not api.healingChestSafe(ctx,entry)then return false end
            if not Q.drillSupport.inDungeon(ctx)then return true end
            local root=Q.special.bound(ctx)
            return entry and entry.Model and (root and entry.Model:IsDescendantOf(root)
                or Q.drillSupport.accessible(entry.Model))
        end
        local ok,entry,empty=pcall(api.chestCandidate,ctx,ctx.questHealing and 1000 or 250,eligible)
        if not ok then ctx.questChestTaking=nil;ctx.questChestLease=nil;error(entry,0)end
        if not entry or not eligible(entry)then
            ctx.questChestTaking=nil;ctx.questChestLease=nil;ctx.questChestDue=now()+3
            return false,entry==nil and empty==true
        end
        Q.drillSupport.stopMine(ctx);Q.stopDrive(ctx)
        if plan.kind=='depth'then ctx.questDriveDetourUntil=now()+6 end
        if ctx.humanoid.SeatPart or ctx.humanoid.Sit then
            ctx.humanoid.Sit=false;ctx.humanoid.Jump=true;ctx.questChestTaking=nil;ctx.questChestLease=nil
            setStatus('Leaving drill seat for a nearby quest chest');return true
        end
        ctx.questCombat=nil;ctx.combatTarget=nil
        ctx.questChestDue=now()+10
        setStatus('Opening a nearby chest alongside class quests')
        local result,why=pcall(api.openChest,ctx,entry)
        ctx.questChestTaking=nil;ctx.questChestLease=nil
        if not result then error(why,0)end
        -- Receipt/cooldown/loot handling is the original chest helper's job.
        -- Moving or attempting a chest does not fabricate quest progress.
        return true
    end
    function Q.prepareHealing(ctx)
        if not enabled(ctx)then return false,false end
        local h=ctx.humanoid;local maximum=tonumber(h.MaxHealth)
        if not finite(maximum) or maximum<=0 or h.Health<=0 then return false,false end
        local ratio=h.Health/maximum
        if ratio>=.7 or not ctx.questHealing and ratio>.3 then return false,false end
        ctx.questHealing=true
        ctx.questRecoveryStage='safety-handoff'
        Q.drillSupport.stopMine(ctx);Q.stopDrive(ctx)
        local worm=Q.parasite and Q.parasite.target(ctx)
        if ctx.combatTarget~=worm then ctx.combatTarget=nil;ctx.questCombat=nil end
        if ctx.questThreat~=worm then ctx.questThreat=nil;ctx.questFuelThreat=nil end
        if manual()then return true,true,'waiting for manual item movement' end
        if ctx.nativeGateMotion or ctx.questMineEntry then return true,true,'waiting for the actual dungeon transition' end
        if h.SeatPart or h.Sit then
            local ready=Q.unseat(ctx);api.watch(ctx)
            if not ready then return true,true,'waiting for actual seat detachment' end
        end
        local point=ctx.root.CFrame.Position or ctx.root.Position
        if api.healingPointSafe and not api.healingPointSafe(ctx,point)then
            -- Release a danger-bound funding or medicine transport before it
            -- can pose another item at this unsafe position. Its exact native
            -- mutation remains reserved until its real reply/receipt settles.
            local job=s.questDelivery
            if job and job.ctx==ctx then release(job)end
            local cash=s.questCashJob
            if cash and cash.ctx==ctx then cash.cancelled=true;Q.cashStep(ctx)end
            local moved,reason=api.retreat(ctx)
            if reason then return true,true,reason end
            if moved then ctx.questHealRetreatAt=now()+3 end
        end
        return true,false
    end
    function Q.step(ctx)
        Q.fuelCargo.observe(ctx)
        Q.drillSupport.upgradePulse(ctx)
        if Q.drillSupport.observeDrivingHealth then Q.drillSupport.observeDrivingHealth(ctx)end
        if Q.drillSupport.observeReturn then Q.drillSupport.observeReturn(ctx)end
        Q.recoverDrive()
        if Q.drillSupport.processing then
            Q.drillSupport.processing.observePlacement(ctx)
            Q.drillSupport.processing.observeCraft(ctx)
        end
        if Q.inventory then Q.inventory.observe(ctx)end
        if cfg.classQuest then
            Q.drillSupport.observeDoors(ctx)
            local healing,blocked,reason=Q.prepareHealing(ctx)
            if healing and blocked then setStatus('Quest healing retreat: '..tostring(reason));return true end
        end
        if Q.parasite and Q.parasite.step(ctx)then return true end
        if not cfg.classQuest then
            if ctx.questOwns or ctx.questDriving or ctx.questSeating or ctx.questDriveInput or ctx.questRecoveryDue or ctx.questRecovering or ctx.questPreviewCancel or s.questDelivery or s.questCashJob then Q.cleanup(ctx) end
            if Q.inventory and Q.inventory.step(ctx)then return true end
            return false
        end
        Q.poll()
        local plan=Q.plan(s.classData,s.questCatalog,cfg.driveDepth)
        if not enabled(ctx) then ctx.questProgressAt=now(); Q.cleanup(ctx); return false end
        Q.refuelActive(ctx,plan) -- Observe an empty tank even while healing/urgent combat preempts driving.
        -- Advance the cadence before optional work can return early. A pending
        -- independent upgrade or continuous sales cannot pin an expired break.
        Q.drillSupport.depthEconomy(ctx,plan)
        if not ctx.humanoid.SeatPart and not ctx.humanoid.Sit then ctx.questSeatExit=nil end
        if (plan.kind~='depth' and plan.kind~='fuel' or api.extractionReady()
            or ctx.humanoid.MaxHealth>0 and ctx.humanoid.Health/ctx.humanoid.MaxHealth<=.3)
            and (ctx.humanoid.SeatPart or ctx.humanoid.Sit)then
            Q.stopDrive(ctx);api.watch(ctx)
            local ready,holding=Q.unseat(ctx)
            if not ready then return holding end
        end
        Q.loadout.remember(ctx)
        if ctx.questPreviewCancel then Q.special.cancelPreview(ctx)end
        s.questPlan=plan
        local intent=table.concat({tostring(plan.name),tostring(plan.level),tostring(plan.kind),
            tostring(plan.objective),tostring(plan.weapon),tostring(plan.weaponClass)},':')
        if ctx.questIntent and ctx.questIntent~=intent then
            -- Every objective handoff uses the new replicated requirement set.
            -- Old targeting/equipment intent cannot pin a completed weapon or job.
            ctx.questCombat=nil;ctx.questWeapon=nil;ctx.questWeaponClass=nil;ctx.questAimHead=nil;ctx.combatTarget=nil
            ctx.questTurretKills=nil;ctx.questTurretMonitor=nil;ctx.questTurretLureUntil=nil
            if plan.kind~='mining'then Q.drillSupport.stopMine(ctx)end
            if plan.kind~='depth' and plan.kind~='fuel'then Q.stopDrive(ctx)end
        end
        ctx.questIntent=intent
        if plan.objective~='TurretKills'then ctx.questTurretKills=nil end
        if plan.kind~='turret'then
            ctx.questNeedScrap=nil
            if ctx.questPlacement and not ctx.questPlacement.processingPlacement then Q.special.cancelPreview(ctx)end
        end
        if ctx.questPotion and (plan.kind~='potion' or ctx.questPotion.objective~=plan.objective)then
            ctx.questPotion=nil;ctx.questPotionUsing=nil;ctx.questOwns=nil
        end
        if plan.kind~='combat'then
            ctx.questCombat=nil;ctx.questWeapon=nil;ctx.questWeaponClass=nil;ctx.questAimHead=nil;ctx.combatTarget=nil
        end
        if plan.kind=='combat'then
            ctx.questCombat,ctx.questWeapon,ctx.questWeaponClass=true,plan.weapon,plan.weaponClass
            ctx.questAimHead=plan.objective=='HeadShot'
        end
        if plan.name then
            local fingerprint=plan.name..':'..plan.level
            for _,item in ipairs(plan.unmet)do fingerprint=fingerprint..':'..item.key..'='..item.count end
            if cfg.driveDepth then fingerprint=fingerprint..':depth='..objective(plan,'TotalDepth')end
            if ctx.questFingerprint~=fingerprint then
                ctx.questFingerprint,ctx.questProgressAt=fingerprint,now();s.questStalled=nil
            end
        end
        if api.extractionReady() then
            if Q.special.bound(ctx) and not Q.drillSupport.activeMine() and not ctx.questCampaignChurch then
                Q.abortResources(ctx);Q.stopDrive(ctx)
                return Q.special.dungeon(ctx,plan,true)
            end
            if Q.drillSupport.activeMine() and not ctx.questMineChurchFallback then
                if Q.drillSupport.churchFallback(ctx)then Q.cleanup(ctx);return false end
                if Q.healing.step(ctx,plan)then return true end
                if Q.drillSupport.threat(ctx,plan)then return true end
                Q.abortResources(ctx);Q.stopDrive(ctx);Q.drillSupport.stopMine(ctx)
                return Q.drillSupport.leaveMine(ctx,plan)
            end
            Q.cleanup(ctx); return false
        end
        -- Survival takes precedence over a death-crate trip or chasing a leech.
        -- Attached face-Worm removal above remains native in-range defense.
        if ctx.questHealing then
            if Q.inventory and Q.inventory.step(ctx,plan)then return true end
            if Q.healing.step(ctx,plan)then return true end
        end
        if Q.loadout.recover(ctx,plan)then return true end
        if ctx.questPotion then Q.potionStep(ctx,plan)end -- Settle only a previously dispatched consume before urgent work.
        if ctx.questStartup and s.questCrateLoadout and s.questCrateLoadout.ctx==ctx and s.questCrateLoadout.issued then
            Q.loadout.step(ctx,plan) -- Receipt/time-limit only; no new claim can enter this issued branch.
        end
        if Q.drillSupport.leechThreat and Q.drillSupport.leechThreat(ctx,plan)then
            if ctx.questFuelThreat and not(api.findOwned(ctx,'Pickaxe_Void') or api.findTool(ctx,'Pickaxe'))then
                Q.loadout.step(ctx,plan) -- Owned saved gear only; no missing-weapon shop buy or synthetic class plan.
            end
            return true
        end
        if Q.inventory and Q.inventory.step(ctx,plan)then return true end
        if Q.special.bound(ctx) and not Q.drillSupport.activeMine() or plan.kind=='dungeon' and (ctx.questCampaign or Q.drillSupport.inDungeon(ctx) and not ctx.questCampaignExit)then
            if Q.healing.step(ctx,plan)then return true end
            return Q.special.dungeon(ctx,plan,false)
        end
        if Q.drillSupport.inDungeon(ctx) and not Q.drillSupport.activeMine() and not ctx.questCampaignExit then
            local missing,holding=Q.special.unbound(ctx)
            if missing then return holding end
        elseif ctx.questUnboundDungeon then ctx.questUnboundDungeon=nil end
        if Q.healing.step(ctx,plan)then return true end
        if ctx.questPlacement and ctx.questPlacement.processingPlacement
            and Q.drillSupport.processing.placement(ctx,plan)then return true end
        if Q.special.fastPlacement(plan)then
            if Q.special.quickReturn(ctx)then ctx.questOwns=true;return true end
            return Q.special.placement(ctx,plan)
        end
        if Q.drillSupport.drivingDefense and Q.drillSupport.drivingDefense(ctx,plan)then return true end
        if Q.drillSupport.threat(ctx,plan)then return true end
        -- Collect native sale proceeds before another sale can monopolize the
        -- item-delivery lane. A slow cash reply retains its exact observer.
        local cashCycle=ctx.questDepthEconomy
        local drivingDue=plan.kind=='depth' and cfg.driveDepth and cashCycle and cashCycle.phase=='drive'
        if not ctx.questDriving and not ctx.questSeating and not drivingDue then
            if Q.cashStep(ctx)then return true end
            if Q.activePlan(plan) and not Q.refuelActive(ctx,plan) and Q.collectMoney(ctx)then return true end
        end
        -- New disposable drops get the next safe sale turn, before optional
        -- mining/readiness waits or another chest. Never steal a driver or a
        -- pending native prompt/ownership lane to satisfy the sale preference.
        if not ctx.questDriving and not ctx.questSeating then
            local sale=s.questDelivery
            if sale and sale.ctx==ctx and (sale.kind=='sale' or sale.kind=='gold') then
                local busy=deliveryStep(ctx,plan)
                if busy and not (sale.cancelled and sale.movementReleased) then return true end
            end
            -- Finish the existing sale above, then give an already-due drive
            -- its turn. A stream of new sale items must not restart this lane.
            if not drivingDue and not Q.refuelActive(ctx,plan) and Q.drillSupport.sellLoose(ctx,plan,true) then return true end
        end
        if ctx.questMineEntry and Q.drillSupport.entry(ctx,ctx.questDepthMine~=nil)then return true end
        if ctx.questDepthMine and Q.drillSupport.depthMine and Q.drillSupport.depthMine(ctx,plan)then return true end
        local refilling=refuelWork(ctx,plan)
        if refilling~=nil then return refilling end
        local cycle=Q.drillSupport.depthEconomy(ctx,plan)
        if cycle and cycle.phase=='drive' then Q.clearLootStop(ctx)end
        if cycle and cycle.phase~='drive' and not Q.manual() and not Q.drillSupport.inDungeon(ctx) then
            Q.stopDrive(ctx)
            if ctx.humanoid.SeatPart or ctx.humanoid.Sit then
                local ready,holding=Q.unseat(ctx);if not ready then return holding end
            end
            if Q.leaveLootSeat(ctx,cycle)then return true end
            -- Finish the existing native owner before starting another pickup,
            -- sale, upgrade or driver session. A deadline cannot cancel an RPC.
            if s.questDelivery then
                local sale=s.questDelivery;local busy=deliveryStep(ctx,plan)
                if busy and not (sale.cancelled and sale.movementReleased) then return true end
                if s.questDelivery then ctx.questOwns=nil;return false end
            end
            if Q.cashStep(ctx) then return true end
            if Q.loadout.step(ctx,plan) then return true end
            if cycle.phase~='upgrades' then
                if cycle.phase=='loot' and Q.fuelCargo.store(ctx,plan)then return true end
                if Q.collectMoney(ctx) or Q.drillSupport.sellLoose(ctx,plan) then return true end
                ctx.questChestDue=math.min(ctx.questChestDue or now(),now())
                local chestBusy,empty=Q.chestTurn(ctx,plan)
                if chestBusy then return true end
                if cycle.phase=='funding' then
                    if Q.drillSupport.step(ctx,plan) or Q.drillSupport.depthMine(ctx,plan)then return true end
                end
                Q.drillSupport.finishEmptyLoot(ctx,plan,empty)
            end
            ctx.questOwns=nil
            setStatus(Q.drillSupport.depthFundingStatus(ctx,plan) or 'Settling upgrade purchases before driving')
            if cycle.phase~='drive' then return false end -- Give ordinary chest/gear work its turn until the break ends.
        end
        -- Optional startup gear and new mine/loot trips wait for a short wall;
        -- urgent defense, healing, native mine exits and refuelling run above.
        if plan.kind=='depth' and cfg.driveDepth and not Q.manual() and not Q.drillSupport.inDungeon(ctx)
            and not ctx.questDepthMine and not ctx.questMineEntry then
            local working,holding,quick=wallWork(ctx)
            if quick then return depthWork(ctx,plan)end
            if working and holding then return true end
        end
        if Q.loadout.step(ctx,plan)then return true end
        local driving=depthWork(ctx,plan)
        if driving~=nil then return driving end
        if plan.kind=='combat' and plan.weapon and api.enforceClassWeapon then api.enforceClassWeapon(ctx,plan.weapon,Q.preferred(ctx))end
        if Q.cashStep(ctx) then return true end
        if Q.activePlan(plan) and not s.questCashJob and Q.collectMoney(ctx)then return true end
        local outstanding=s.questDelivery
        if deliveryStep(ctx,plan) then
            if outstanding and (outstanding.cancelled and outstanding.movementReleased
                or outstanding.background and not outstanding.owns and not outstanding.pending and not calls.drag)then
                s.questPlan=plan
                if combatWork(ctx,plan) then return true end
                if ctx.questMineJob and Q.drillSupport.step(ctx,plan)then return true end
                ctx.questOwns=nil;return false
            end
            return true
        end
        if Q.chestTurn(ctx,plan)then return true end
        if plan.kind=='shred'then return Q.special.shred(ctx,plan)end
        if plan.kind=='turret'then return Q.special.turretKills(ctx,plan)end
        if plan.kind=='dungeon'then return Q.special.dungeon(ctx,plan,false)end
        if plan.kind=='depth' and ctx.questWallWork and not ctx.questDepthEconomy and Q.drillSupport.depthMine
            and Q.drillSupport.depthMine(ctx,plan)then return true end
        if Q.drillSupport.sellLoose(ctx,plan)then return true end
        if plan.kind=='potion'then return Q.potionStep(ctx,plan)end
        if plan.kind=='fuel'then
            if fuel(ctx,plan)then return true end
            if Q.drillSupport.step(ctx,plan)then return true end
            local tank,capacity=tonumber(ctx.drill:GetAttribute('Fuel')),tonumber(ctx.drill:GetAttribute('MaxFuel'))
            if cfg.driveDepth and finite(tank) and finite(capacity) and tank>=capacity*.8 and holdRoute(ctx)then
                local driving={kind='depth',name=plan.name,counts=plan.counts,unmet=plan.unmet,objective='ContributeFuel'}
                return drive(ctx,driving)
            end
            ctx.questOwns=nil;setStatus('Fuel quest: collecting loaded fuel; full tanks need native driving enabled');return false
        end
        if plan.kind=='gold' or plan.kind=='sale' or plan.kind=='upgrades'then
            if Q.drillSupport.step(ctx,plan)then return true end
            ctx.questOwns=nil;setStatus('Quest '..tostring(plan.objective)..': chest collection and disposable-item funding continue');return false
        end
        if combatWork(ctx,plan)then return true end
        if Q.drillSupport.step(ctx,plan)then return true end
        if plan.kind=='mining' then
            ctx.questOwns=nil;ctx.questMining=nil;s.questIdle=true
            setStatus((s.questMiningProblem or 'Mining quest: no eligible loaded veins / ready mineshaft entrance')..'; chest discovery continues')
            return false
        end
        if now()<(ctx.questTickAt or 0) then return ctx.questOwns end
        ctx.questTickAt=now()+.2
        s.questPlan=plan
        if plan.kind=='waiting' then
            -- Losing planner data retires the old local movement intent just
            -- like a completed objective. Native mutations keep their original
            -- reservations/observers through cleanup; no reply is invented.
            Q.cleanup(ctx)
            setStatus('Waiting for native class catalog and quest counters');return false
        end
        if plan.kind=='complete' or plan.kind=='unsupported' then
            Q.cleanup(ctx);setStatus((plan.kind=='complete' and 'Equipped class is fully levelled' or 'Next objectives need unsupported actions')..'; chest farming continues')
            return false
        elseif plan.kind=='advance' then
            Q.cleanup(ctx); setStatus('Requirements met; waiting for server class level to advance'); return false
        end
        if now()-(ctx.questProgressAt or now())>120 then
            Q.cleanup(ctx);s.questStalled=true
            setStatus('No quest counter progress for 120s; chest farming continues');return false
        end
        if plan.kind=='chests' then Q.cleanup(ctx); setStatus('Opening chests for '..plan.name..' quest'); return false end
        local canWork,reason=runnable(ctx,plan)
        if not canWork then
            Q.stopDrive(ctx);ctx.questOwns=nil;ctx.combatTarget=nil;s.questIdle=true
            setStatus(plan.weapon and not Q.preferred(ctx) and ('Required '..plan.weapon..' is missing; looking for own gear / free or coin stock; chest farming continues')
                or reason..'; chest farming continues');return false
        end
        s.questIdle=nil
        if not holdRoute(ctx) then return true end
        if plan.kind=='depth' then
            ctx.questCombat,ctx.questWeapon,ctx.questWeaponClass=nil,nil,nil
            local seat=ctx.drill:FindFirstChild('DrillPhysicsSeat') or ctx.drill:FindFirstChild('VehicleSeat')
            local enemy=seat and now()-ctx.questProgressAt>=20 and nearest(api.enemies(),seat.Position,function(npc)
                local hp=npc:FindFirstChildOfClass('Humanoid'); local p=api.part(npc)
                return hp and hp.Health>0 and npc:GetAttribute('NpcFaction')~='FriendlyCompanion'
                    and api.swordTargetAllowed(npc)
                    and p and (p.Position-seat.Position).Magnitude<=120
            end)
            if enemy then
                Q.stopDrive(ctx); ctx.questCombat,ctx.questWeaponClass=true,'Sword'
                local tool=Q.preferred(ctx); local p=api.part(enemy)
                if tool and p and not ctx.defenseMoving and now()>=(ctx.dodgeUntil or 0) then
                    api.hover(ctx); ctx.combatTarget=enemy
                    if (ctx.root.Position-p.Position).Magnitude>9 then ctx.root.CFrame=CFrame.new(p.Position+Vector3.new(0,2,6)) end
                    setStatus('Drill depth stalled; fighting a nearby obstruction')
                else setStatus('Drill obstruction needs an owned sword') end
            else return drive(ctx,plan) end
            return true
        end
        local tool=Q.preferred(ctx)
        if not tool then
            setStatus('Quest weapon unavailable: '..tostring(plan.weapon or plan.weaponClass))
            if plan.weapon then
                if Q.supply(ctx,plan,plan.weapon) then return true end
            end
            Q.stopDrive(ctx)
            ctx.questOwns=nil; return false
        end
        local class=api.attr(tool,'Class'); local gun=class=='Revolver' or class=='Rifle' or class=='Shotgun'
        if gun and (tonumber(api.attr(tool,'Ammo')) or 0)<=0
            and (tonumber(api.Players.LocalPlayer:GetAttribute(class=='Revolver' and 'Pistol_Ammo' or class..'_Ammo')) or 0)<=0 then
            setStatus('Quest gun needs ammunition')
            if Q.supply(ctx,plan,class=='Revolver' and 'Pistol_Ammo' or class..'_Ammo') then return true end
            Q.stopDrive(ctx);ctx.questOwns=nil
            return false
        end
        local npc=combatTarget(ctx,plan,gun)
        if not npc then
            Q.stopDrive(ctx); ctx.questOwns=nil; setStatus('Finding a living quest target'); return false
        end
        return combatWork(ctx,plan)
    end
    Q.call=call
    Q.free,Q.place,Q.release,Q.startDelivery,Q.enabled,Q.manual,Q.looseItems=free,place,release,startDelivery,enabled,manual,looseItems
    local supplyIds={Flintlock=true,Sword_Pirate=true,Pistol_Ammo=true,Rifle_Ammo=true,Shotgun_Ammo=true,
        Bandages=true,Basic_Medkit=true,Advanced_Medkit=true,Golden_Medkit=true}
    for _,id in pairs(potions)do supplyIds[id]=true end
    function Q.potionStep(ctx,plan)
        local job=ctx.questPotion
        if job then
            if not job.tool.Parent or api.stackCount(job.tool)<job.count then ctx.questPotionUsing=nil;ctx.questOwns=nil end
            if plan.name~=job.class or objective(plan,job.objective)>job.before then
                ctx.questPotion=nil;ctx.questPotionUsing=nil;ctx.questOwns=nil;setStatus('Potion quest counter confirmed');return false
            end
            if now()-job.started>=8 then
                ctx.questPotion=nil;ctx.questPotionUsing=nil;ctx.questOwns=nil
                ctx.questPotionRetry=ctx.questPotionRetry or setmetatable({}, {__mode='k'})
                ctx.questPotionRetry[job.tool]=math.huge
                setStatus('Potion use unconfirmed; no immediate duplicate consume')
            end
            return ctx.questPotionUsing==true -- Consumption holds equipment; final counter accounting is background.
        end
        local tool=api.findOwned(ctx,plan.potion)
        if not tool then return Q.supply(ctx,plan,plan.potion)end
        if now()<((ctx.questPotionRetry or {})[tool] or 0) or not holdRoute(ctx)then return ctx.questOwns==true end
        Q.stopDrive(ctx)
        local active=api.equip(ctx,tool)
        if active and type(active.Consume)=='function' and api.readyAction(active) and api.watcherReady(ctx)then
            job={tool=tool,class=plan.name,objective=plan.objective,before=objective(plan,plan.objective),started=now(),count=api.stackCount(tool)}
            ctx.questPotion=job;ctx.questPotionUsing=true;ctx.questCombat=nil
            pcall(active.Consume,active)
            setStatus('Using required '..plan.potion..'; awaiting native quest counter')
        end
        return ctx.questOwns==true
    end
    function Q.moneyTarget(ctx)
        if calls.cash or s.questCashJob or s.questDelivery or s.bringDelivery or s.lootRequest or manual() then return nil end
        return nearest(api.tagged('MoneySack'),ctx.root.Position,function(item)
            local creator=item:GetAttribute('BagCreator')
            local p=api.part(item)
            return free(item) and api.id(item)=='Money_Sack' and api.tag(item,'Interactive')
                and (not ctx.questHealing or not api.healingPointSafe or p and api.healingPointSafe(ctx,p.Position))
                and (not creator or creator=='' or creator==api.Players.LocalPlayer.Name) and now()>=(retries[item] or 0)
        end)
    end
    local cashRejected=s.questCashRejected or setmetatable({}, {__mode='k'});s.questCashRejected=cashRejected
    local function rejectCash(job)
        local record=cashRejected[job.item]
        local count=record and record.character==job.character and record.count or 0
        count=count+1;cashRejected[job.item]={character=job.character,count=count}
        -- Only an explicit native false permits a fresh attempt. Accepted,
        -- thrown or still-pending mutations never enter this bounded retry.
        retries[job.item]=count<=2 and now()+(count==1 and 2 or 8) or math.huge
    end
    function Q.cashStep(ctx)
        local job=s.questCashJob;if not job then return false end
        local function releaseMovement()
            if job.movementHeld then job.movementHeld=nil;job.ctx.questOwns=nil end
        end
        if job.ctx==ctx and api.Players.LocalPlayer.Character==ctx.character and (job.sent or job.token and job.token.called)
            and (s.stats.coinEarned or 0)>job.before and (not job.item.Parent or not api.tag(job.item,'Interactive'))then
            Q.retireConfirmedCall('cash',job.token)
            s.stats.questCashConfirmed=(s.stats.questCashConfirmed or 0)+1
            retries[job.item]=math.huge;job.cancelled=true;s.questCashJob=nil;releaseMovement()
            setStatus('Money bag coin increase confirmed');return false
        end
        if job.ctx~=ctx or job.cancelled or not enabled(ctx) or manual() then
            job.cancelled=true;releaseMovement()
            if not calls.cash then s.questCashJob=nil end
            return false
        end
        if ctx.questHealing and api.healingPointSafe then
            local p=api.part(job.item)
            if not p or not api.healingPointSafe(ctx,p.Position)then
                job.cancelled=true;releaseMovement()
                if not calls.cash then s.questCashJob=nil end
                setStatus('Healing cash approach became unsafe; staying clear of loaded attackers');return false
            end
        end
        if job.stage=='approach' and now()>=job.readyAt then
            job.stage='receipt'
            -- DragController collects Money_Sack through Interact(item), not ItemBag.
            local issued,token=call('cash','InteractionService','Interact',{job.item},function(ok,value,_,dispatch)
                job.knownRejected=ok==true and value==false and dispatch~='not-sent'
                job.rejected=not ok or value==false
                job.sent=dispatch~='not-sent';job.receiptUntil=now()+8
                if job.knownRejected then s.stats.questCashRejected=(s.stats.questCashRejected or 0)+1 end
                if job.cancelled then
                    if job.knownRejected then rejectCash(job)
                    elseif job.sent then retries[job.item]=math.huge end
                    if s.questCashJob==job then s.questCashJob=nil end;return
                end
                releaseMovement()
            end,function()return enabled(ctx) and not job.cancelled and free(job.item) and api.tag(job.item,'Interactive')
                and (not ctx.questHealing or not api.healingPointSafe or api.healingPointSafe(ctx,api.part(job.item).Position))
                and (api.part(job.item).Position-ctx.root.Position).Magnitude<=10 and not manual()end)
            if issued then job.token=token else
                retries[job.item]=now()+15;s.questCashJob=nil;releaseMovement()
            end
        elseif job.stage=='receipt' then
            if job.token and calls.cash==job.token then
                if now()-job.started>=1.5 then releaseMovement()end
                return ctx.questOwns==true
            end
            if job.rejected or job.receiptUntil and now()>=job.receiptUntil then
                if job.knownRejected then rejectCash(job)
                else retries[job.item]=job.sent and math.huge or now()+30 end
                job.cancelled=true;releaseMovement()
                if not calls.cash then s.questCashJob=nil end
                setStatus(job.knownRejected and 'Money bag pickup rejected; bounded reapproach retry scheduled'
                    or 'Money bag pickup unconfirmed; farming continues without a duplicate request')
            end
        end
        return ctx.questOwns==true
    end
    function Q.collectMoney(ctx)
        if ctx.questPotionUsing then return false end
        local mine=ctx.questMineJob
        if mine and mine.coal and Q.drillSupport.nodeAllowed(mine.node,true) and Q.fuelNeeded()then return false end
        local item=Q.moneyTarget(ctx)
        if not item then return false end
        if not holdRoute(ctx)then return ctx.questOwns==true end
        Q.stopDrive(ctx)
        if ctx.humanoid.SeatPart or ctx.humanoid.Sit then
            local _,holding=Q.unseat(ctx);return holding
        end
        if ctx.questHealing and api.healingPointSafe and not api.healingPointSafe(ctx,api.part(item).Position)then ctx.questOwns=nil;return false end
        Q.drillSupport.stopMine(ctx);api.hover(ctx)
        ctx.root.CFrame=CFrame.new(api.part(item).Position+Vector3.new(0,1,2))
        s.questCashJob={ctx=ctx,character=ctx.character,item=item,started=now(),readyAt=now()+.2,stage='approach',before=s.stats.coinEarned or 0,movementHeld=true}
        setStatus('Collecting a free money bag for quest supplies and upgrades');return true
    end
    local function supplyCount(ctx,id)
        if id:sub(-5)=='_Ammo' then return tonumber(api.Players.LocalPlayer:GetAttribute(id)) or 0 end
        local count=0
        for _,container in ipairs({ctx.character,api.Players.LocalPlayer:FindFirstChild('Backpack')}) do
            if container then for _,tool in ipairs(container:GetChildren()) do
                if api.id(tool)==id then count=count+(Q.healing.isMedical(tool) and api.stackCount(tool) or 1)end
            end end
        end
        return count
    end
    function Q.supplyFundingTarget(ctx,plan)
        local need=s.questSupplyFunding
        if not need or need.ctx~=ctx or need.class~=plan.name or need.objective~=plan.objective
            or now()>=need.expires or supplyCount(ctx,need.id)>need.before
            or Q.healing.isMedical(need.item) and not ctx.questHealing then return 0 end
        return Q.coinTarget(need.price,Q.healing.isMedical(need.item))
    end
    function Q.supplyReceipt(job) return supplyCount(job.ctx,job.id)>job.inventoryBefore end
    function Q.purchaseReceipt(job)
        if job.purchaseConfirmed then return true end
        local item=job.item
        -- This exact stock becoming a free owned-eligible item is a native
        -- purchase receipt. A reply alone never authorizes picking up stock.
        if not job.buySent or purchases[item]~=job or not job.stockAtBuy
            or not (job.buySettled or job.buyToken and job.buyToken.called)
            or api.id(item)~=job.id or item.Parent~=workspace:FindFirstChild('Items')
            or api.tag(item,'ShopItem') or not free(item)then return false end
        if not Q.retireConfirmedCall('shop',job.buyToken)then return false end
        job.purchaseConfirmed=true
        retries[item]=nil -- Clear pickup suppression once, keeping the Buy ledger.
        if not job.cancelled then job.stage='purchase-confirm';job.confirmUntil=now()+5 end
        return true
    end
    local function supplyRetryReady(item)
        local purchase=purchases[item]
        if purchase and purchase.buySent then
            if Q.purchaseReceipt(purchase) and purchase.cancelled then release(purchase)end
            if stock(item)then return false end -- Never issue another Buy for this stock identity.
        end
        return now()>=(retries[item] or 0)
    end
    local function supplyAllowed(id,item)
        if supplyIds[id]then return true end
        if item then return Q.healing and Q.healing.isMedical(item)end
        for _,candidate in ipairs(looseItems())do if api.id(candidate)==id and Q.healing.isMedical(candidate)then return true end end
        return false
    end
    stock=function(item)
        return item and item.Parent==workspace:FindFirstChild('Items') and api.part(item) and api.tag(item,'ShopItem')
            and supplyAllowed(api.id(item),item) and (api.attr(item,'CostCurrency')==nil or api.attr(item,'CostCurrency')=='Coins') and not item:GetAttribute('Welded') and not api.tag(item,'Welded')
            and not Q.protectedRelic(item) and item:GetAttribute('Placed')~=true
            and not item:GetAttribute('Robux') and not item:GetAttribute('ProductId') and not item:GetAttribute('RobuxProductId')
    end
    local function checkout(item) return item and item.Parent and item:IsA('BasePart') and api.tag(item,'BuyPart') and item:IsDescendantOf(workspace) end
    local function supplyAccessible(ctx,item,target)
        return not Q.healing.isMedical(item) or Q.healing.itemAccessible(ctx,item)
            and (not target or not api.medicalLocationAllowed or api.medicalLocationAllowed(ctx,target))
    end
    function Q.supplyReady(ctx,id)
        if not supplyAllowed(id) then return false,'medical item is not eligible for coin purchase' end
        local item=nearest(looseItems(),ctx.root.Position,function(item)
            return api.id(item)==id and supplyAccessible(ctx,item) and supplyRetryReady(item) and (free(item) or stock(item))
                and (id:sub(-5)=='_Ammo' or api.hasRoom(ctx,item) or Q.healing.canMakeRoom(ctx,item))
        end)
        if not item then
            for _,found in ipairs(looseItems())do
                if api.id(found)==id and supplyAccessible(ctx,found) and (free(found) or stock(found))then
                    if not supplyRetryReady(found)then return false,'medical item is waiting for its retry / receipt' end
                    return false,'toolbar is full; no authorized shard slot is available'
                end
            end
            return false,'no eligible medical stock loaded'
        end
        if free(item) or nearest(api.tagged('BuyPart'),api.part(item).Position,function(pad)return checkout(pad) and supplyAccessible(ctx,item,pad)end)then return true end
        return false,'medical stock has no loaded BuyPart checkout'
    end
    local function obstructed(job)
        if not checkout(job.target) then return true end
        for _,item in ipairs(looseItems()) do
            local p=api.part(item)
            if item~=job.item and p and (p.Position-job.target.Position).Magnitude<job.target.Size.Magnitude*.5+5 then return true end
        end
        return false
    end
    function Q.supply(ctx,plan,id)
        if not supplyAllowed(id) or s.questDelivery or s.bringDelivery or calls.drag or manual() then ctx.questOwns=nil; return false end
        local loose=nearest(looseItems(),ctx.root.Position,function(item)return free(item) and api.id(item)==id and supplyAccessible(ctx,item) and supplyRetryReady(item)end)
        if loose then
            if id:sub(-5)~='_Ammo' and not api.hasRoom(ctx,loose) then
                if Q.healing.canMakeRoom(ctx,loose)then Q.healing.makeRoom(ctx,loose);return true end
                ctx.questOwns=nil; setStatus('Quest tool needs a free toolbar slot'); return false
            end
            Q.stopDrive(ctx)
            local before=supplyCount(ctx,id)
            if startDelivery(ctx,loose,ctx.root,'supply',plan) then
                local job=s.questDelivery
                if not job then return false end
                job.id,job.inventoryBefore=id,before
                job.healingSupply=ctx.questHealing and Q.healing.isMedical(loose) or nil
                return true
            end
        end
        -- Coin purchases share a reservation with native drill upgrades.
        if s.questUpgradeJob or calls.upgrade then return false end
        if now()<(ctx.questSupplyAt or 0) then ctx.questOwns=nil; return false end
        local item=nearest(looseItems(),ctx.root.Position,function(item)return stock(item) and api.id(item)==id and supplyAccessible(ctx,item) and supplyRetryReady(item)end)
        -- An upgrade balance lookup spends nothing. Let needed medicine reserve
        -- checkout first; its existing shop reservation blocks a late upgrade
        -- dispatch, and the medical Buy still requires its own fresh quote/wallet.
        if calls.upgradeWallet and not(ctx.questHealing and item and Q.healing.isMedical(item))then return false end
        ctx.questSupplyAt=now()+3
        local pad=item and nearest(api.tagged('BuyPart'),api.part(item).Position,function(pad)return checkout(pad) and supplyAccessible(ctx,item,pad)end)
        if not item or not pad then ctx.questOwns=nil; setStatus('No free or coin-shop quest supply loaded: '..id); return false end
        if id:sub(-5)~='_Ammo' and not api.hasRoom(ctx,item) and not Q.healing.canMakeRoom(ctx,item) then ctx.questOwns=nil; setStatus('Quest tool needs a free toolbar slot; no purchase'); return false end
        local job={ctx=ctx,item=item,target=pad,kind='supply',shop=true,id=id,class=plan.name,
            objective=plan.objective,stage='empty',started=now(),inventoryBefore=supplyCount(ctx,id),
            healingSupply=ctx.questHealing and Q.healing.isMedical(item) or nil,
            stockOrigin=item:GetPivot(),originOffset=workspace:GetAttribute('InfiniteDepthOffsetMeters')}
        if obstructed(job) then ctx.questOwns=nil; return false end
        if job.healingSupply then ctx.questMedicalCheckoutEpoch=(ctx.questMedicalCheckoutEpoch or 0)+1 end
        Q.stopDrive(ctx)
        s.questDelivery=job; ctx.bringEquipmentLock=job; setStatus('Checking coin checkout for '..id)
        return true
    end
    function Q.shopStep(job,plan)
        local ctx=job.ctx
        if job.stage~='purchase-confirm' and (not stock(job.item) or obstructed(job)) then
            retries[job.item]=now()+120; release(job); return true
        end
        if job.pending or calls.drag or calls.shop or calls.wallet or now()<(job.nextAt or 0) then return true end
        job.nextAt=now()+.25
        local function guarded() return enabled(ctx) and s.questDelivery==job and not job.cancelled and not manual()
            and (not job.healingSupply or (ctx.questHealing or job.buySent) and supplyAccessible(ctx,job.item,job.target))end
        local function fail(text) retries[job.item]=job.buySent and math.huge or now()+120; setStatus(text); release(job)end
        if job.stage=='empty' then
            call('shop','ShopService','GetBuyQuote',{job.target},function(ok,price)
                if not guarded() then release(job); return end
                if ok and price==0 then job.stage='shop-request' else fail('Checkout is not empty; no purchase') end
            end,guarded)
        elseif job.stage=='shop-request' then
            job.pending=true
            if not call('drag','DragService','Request',{job.item},function(ok,value,_,dispatch)
                job.pending=nil; job.owns=dispatch~='not-sent' and (not ok or value==true);job.ownershipConfirmed=ok and value==true
                if not ok or not guarded() or not job.owns or not stock(job.item) then release(job); return end
                local moved,result=pcall(place,job)
                if moved and result then
                    job.stockPlaced=true
                    job.stage,job.readyAt='shop-drop',now()+.6
                else fail('Stock placement failed; no purchase') end
            end,guarded) then job.pending=nil end
        elseif job.stage=='shop-drop' and now()>=job.readyAt then
            pcall(place,job);clearHold(job)
            call('drag','DragService','Cancel',{true},function(ok,value)
                if ok and value~=false then job.owns=false; job.stage='quote' else fail('Checkout release unconfirmed; no purchase') end
            end,guarded)
        elseif job.stage=='quote' then
            call('shop','ShopService','GetBuyQuote',{job.target},function(ok,price)
                if not guarded() then release(job); return end
                if ok and finite(price) and price>0 then job.price=price; job.stage='wallet'
                elseif ok and price==0 and now()-job.started<8 then job.nextAt=now()+.5
                else fail('Quest supply coin quote unavailable') end
            end,guarded)
        elseif job.stage=='wallet' then
            local readVersion=s.questWalletVersion or 0
            call('wallet','CurrencyService','GetCurrency',{},function(ok,coins)
                if not guarded() then release(job); return end
                if ok then coins,job.balanceAt,job.walletVersion=Q.observeCoins(coins,readVersion)end
                if ok and Q.canSpend(coins,job.price,Q.healing.isMedical(job.item))then
                    job.balance=coins;job.stage='recheck';s.questSupplyFunding=nil
                else
                    if ok and finite(coins)then
                        s.questSupplyFunding={ctx=ctx,class=job.class,objective=job.objective,id=job.id,item=job.item,
                            before=job.inventoryBefore,price=job.price,expires=now()+120}
                    end
                    fail('Insufficient Coins for quest supply; earning its quoted price')
                end
            end,guarded)
        elseif job.stage=='recheck' then
            call('shop','ShopService','GetBuyQuote',{job.target},function(ok,price)
                if not guarded() then release(job); return end
                if ok and price==job.price and not obstructed(job) and now()-job.balanceAt<3 then job.stage='buy'
                else fail('Checkout changed; no quest purchase') end
            end,guarded)
        elseif job.stage=='buy' then
            if not Q.canSpend(Q.coinBalance(job.balance,job.balanceAt,job.walletVersion),job.price,Q.healing.isMedical(job.item))then
                job.stage='wallet';return true
            end
            if job.id:sub(-5)~='_Ammo' and not api.hasRoom(ctx,job.item)then
                if Q.healing.isMedical(job.item)then Q.healing.makeRoom(ctx,job.item)else fail('Toolbar filled before purchase; no purchase')end
                return true
            end
            if now()-(job.balanceAt or 0)>=3 then job.stage='wallet';return true end
            -- One sent Buy, including unknown replies, is never repeated for this stock.
            if job.buySent then return true end
            job.buySent=true;job.stockAtBuy=true;purchases[job.item]=job;retries[job.item]=math.huge
            if call('shop','ShopService','Buy',{job.target},function(ok,value,_,dispatch)
                if dispatch=='not-sent'then
                    job.buySent=nil;if purchases[job.item]==job then purchases[job.item]=nil end
                    retries[job.item]=now()+15;release(job);return
                end
                job.buySettled=true
                Q.purchaseReceipt(job)
                if not guarded() then release(job); return end
                if job.purchaseConfirmed then job.stage='purchase-confirm';job.confirmUntil=now()+5
                elseif not ok or value==false then fail('Quest purchase rejected or unknown; no repeat Buy')
                else job.stage='purchase-confirm'; job.confirmUntil=now()+5 end
            end,function()
                return guarded() and stock(job.item) and not obstructed(job)
                    and Q.canSpend(Q.coinBalance(job.balance,job.balanceAt,job.walletVersion),job.price,Q.healing.isMedical(job.item))
                    and (job.id:sub(-5)=='_Ammo' or api.hasRoom(ctx,job.item))
            end)then job.buyToken=calls.shop
            else
                job.buySent=nil;if purchases[job.item]==job then purchases[job.item]=nil end
                retries[job.item]=now()+15;release(job)
            end
        elseif job.stage=='purchase-confirm' then
            if not job.item.Parent then fail('Purchased stock identity lost; waiting for another supply')
            elseif not api.tag(job.item,'ShopItem') and free(job.item) then
                job.shop=false; job.stage='request'; job.pending=true
                if not call('drag','DragService','Request',{job.item},function(ok,value,_,dispatch)
                    job.pending=nil; job.owns=dispatch~='not-sent' and (not ok or value==true);job.ownershipConfirmed=ok and value==true
                    if not ok or not guarded() or not job.owns or not free(job.item) then release(job); return end
                job.target=ctx.root -- Paid stock must come to the waiting player, not remain at checkout.
                local moved,result=pcall(place,job)
                if moved and result then job.stage='placed'; job.readyAt=now()+.45 else release(job) end
                end,guarded) then job.pending=nil end
            elseif now()>=job.confirmUntil then fail('Purchase not confirmed by ShopItem removal; no repeat Buy') end
        end
        return true
    end
    Q.holdRoute,Q.deliveryStep,Q.nearest,Q.sellers,Q.fuelItem=holdRoute,deliveryStep,nearest,sellers,fuelItem
    Q.special=buildQuestSpecial(api,Q)
    Q.loadout=buildQuestLoadout(api,Q)
    Q.healing=buildQuestHealing(api,Q)
    Q.drillSupport=buildQuestDrill(api,Q)
    Q.fuelCargo=buildQuestFuelCargo(api,Q)
    Q.rewards=buildQuestRewards(api,Q)
    Q.inventory=buildQuestInventory(api,Q)
    Q.parasite=buildQuestParasite(api,Q)
    function Q.lobby()
        if not cfg.classQuest or game.PlaceId~=101906032112547 and not workspace:FindFirstChild('Lobby')then return false end
        Q.poll()
        return Q.loadout.lobby()
    end
    function Q.miningAuraAllowed(ctx)
        local plan=Q.plan(s.classData,s.questCatalog,cfg.driveDepth)
        return enabled(ctx) and ctx.questMining and not ctx.questHealing and not ctx.questStartup
            and not ctx.questRecovering and not ctx.questPotionUsing and not ctx.bringEquipmentLock
            and (not s.questDelivery or s.questDelivery.cancelled and s.questDelivery.movementReleased)
            and not s.bringDelivery and not s.lootRequest and not manual()
            and not api.extractionReady() and ctx.humanoid.MaxHealth>0 and ctx.humanoid.Health/ctx.humanoid.MaxHealth>.3
            and plan.objective~='TurretKills'
    end
    function Q.pauseCombat(ctx,ownedEdit)
        local placement=ctx.questPlacement
        local placementBusy=placement and not(placement.processingPlacement and placement.background and placement.localPreviewStopped)
        local exitFight=ctx.questExitCombat and ctx.combatTarget and Q.drillSupport.activeMine()
            and Q.drillSupport.mineEnemy(ctx.combatTarget,Q.drillSupport.activeMine())
            and (not api.enemyAlive or api.enemyAlive(ctx.combatTarget))
        if ctx.questExitCombat and ctx.combatTarget and Q.special.bound(ctx) and Q.special.belongs(ctx.combatTarget,Q.special.bound(ctx))
            and api.enemyAlive(ctx.combatTarget)then exitFight=true end
        local plan=Q.plan(s.classData,s.questCatalog,cfg.driveDepth)
        local turret=plan.objective=='TurretKills' and not ctx.questThreat
        local target=ctx.combatTarget
        local fuelFight=cfg.classQuest and ctx.questFuelThreat and target and api.isFuelLeech and api.isFuelLeech(target)
            and api.enemyAlive(target) and (not api.extractionReady() or exitFight)
            and Q.drillSupport.leechReady(ctx,target)
            and (not api.questTargetAllowed or api.questTargetAllowed(ctx,target))
        if fuelFight then
            -- A draining native leech must die before driving/healing continues.
            -- Retain healing hysteresis, but let the permitted pickaxe retaliate
            -- only after the actual seat/transition and manual work have cleared.
            local pickaxe=api.findOwned(ctx,'Pickaxe_Void') or api.findTool(ctx,'Pickaxe')
            return ctx.questDriving or ctx.questSeating or ctx.humanoid.SeatPart~=nil or ctx.humanoid.Sit
                or Q.driveHandoff(ctx)
                or ctx.questMineEntry or ctx.nativeGateMotion or manual() or ctx.questStartup and not pickaxe or ctx.questRecovering
                or placementBusy or ctx.questPreviewCancel or ctx.questPotionUsing or ctx.questHealAttempt or s.questMedicalDrop
                or ctx.swingEdit and not(ctx.swingEdit==ownedEdit and ownedEdit.thread==coroutine.running())
        end
        -- Standing beside loot, preparing a pickaxe or waiting for extraction
        -- does not disable native in-range retaliation. Actual handoffs do.
        local handoff=ctx.questDriving or ctx.questSeating or ctx.humanoid.SeatPart~=nil or ctx.humanoid.Sit
            or Q.driveHandoff(ctx)
            or ctx.questMineEntry or ctx.nativeGateMotion or manual() or ctx.bringEquipmentLock
            or s.bringDelivery or s.lootRequest or s.equipmentRequest
            or ctx.swingEdit and not(ctx.swingEdit==ownedEdit and ownedEdit.thread==coroutine.running())
            or ctx.questHealAttempt or s.questMedicalDrop or ctx.questRecovering
            or placementBusy or ctx.questPreviewCancel or ctx.questPotionUsing
        if Q.parasite and Q.parasite.target(ctx)then return handoff end
        return handoff or cfg.classQuest and (turret or ctx.questTurretKills or ctx.questStartup)
    end
    return Q
end

end)()
    local buildMovement = (function()
return function(api)
    local M, now = {}, api.now
    local ok, tweenService = pcall(function() return game:GetService('TweenService') end)
    if not ok then tweenService = nil end
    local function point(ctx) return ctx.root.CFrame.Position or ctx.root.Position end
    local function frame(p, delta, scale)
        return CFrame.new(p.X + delta.X * scale, p.Y + delta.Y * scale, p.Z + delta.Z * scale)
    end
    local function finite(value) return type(value) == 'number' and value == value and math.abs(value) < math.huge end
    function M.releaseHover(ctx)
        if ctx.hoverConnection then pcall(function()ctx.hoverConnection:Disconnect()end);ctx.hoverConnection=nil end
        if ctx.hoverForce then pcall(function()ctx.hoverForce:Destroy()end);ctx.hoverForce=nil end
        if ctx.hoverAttachment then pcall(function()ctx.hoverAttachment:Destroy()end);ctx.hoverAttachment=nil end
    end
    function M.hover(ctx)
        if ctx.questDriving or ctx.questSeating or ctx.humanoid and ctx.humanoid.SeatPart then
            M.releaseHover(ctx);return
        end
        -- Local anchoring can stop the assembly's normal physics replication.
        -- Balance gravity while keeping the character unanchored and movable.
        ctx.root.Anchored = false
        if ctx.root.AssemblyLinearVelocity and (not ctx.nativeGateMotion or ctx.defenseMoving or now()<(ctx.dodgeUntil or 0))then ctx.root.AssemblyLinearVelocity = Vector3.zero end
        local mass, gravity = ctx.root.AssemblyMass, workspace.Gravity
        if not finite(mass) or not finite(gravity) or mass <= 0 or gravity < 0 then return end
        if not ctx.hoverForce then
            local attachment = Instance.new('Attachment'); attachment.Name = 'EarthAutofarmHover'; attachment.Parent = ctx.root
            ctx.hoverAttachment = attachment
            local force = Instance.new('VectorForce'); ctx.hoverForce = force
            force.Name, force.Attachment0, force.ApplyAtCenterOfMass = 'EarthAutofarmGravity', attachment, true
            force.RelativeTo = Enum.ActuatorRelativeTo.World
            force.Parent = ctx.root
            local function update()
                if ctx.active and force.Parent and ctx.root.Parent then
                    if ctx.questDriving or ctx.questSeating or ctx.humanoid and ctx.humanoid.SeatPart then force.Force=Vector3.zero;return end
                    local currentMass, currentGravity = ctx.root.AssemblyMass, workspace.Gravity
                    if not ctx.root.Anchored and finite(currentMass) and finite(currentGravity) then
                        force.Force = Vector3.new(0, currentMass * currentGravity, 0)
                    else force.Force = Vector3.zero end
                end
            end
            if ctx.connect and api.RunService.Heartbeat then ctx.hoverConnection = ctx.connect(api.RunService.Heartbeat, update) end
        end
        ctx.hoverForce.Force = Vector3.new(0, mass * gravity, 0)
    end
    local function validVector(value)
        local read, valid = pcall(function() return finite(value.X) and finite(value.Y) and finite(value.Z) end)
        return read and valid
    end
    -- Keep one logical checkpoint per server. A streamed replacement drill is
    -- not a new run; rebasing changes coordinates, not credited route progress.
    function M.syncRoute(drill)
        local s = api.state
        local start, finish = workspace:GetAttribute('Start_Position'), workspace:GetAttribute('End_Position')
        local configured = validVector(start) and validVector(finish)
            and finish.X > start.X and math.abs(finish.Z - start.Z) < 1 and math.abs(finish.Y - start.Y) < 1
        if not configured then
            local read, pivot = pcall(function() return drill:GetPivot() end)
            start = read and pivot.Position or nil
            if not validVector(start) then return end
        end
        local offset = tonumber(workspace:GetAttribute('InfiniteDepthOffsetMeters')) or 0
        local scale = configured and (finish - start).Magnitude / 100000 or 2
        local old = s.routeGeometry
        local bandChanged = old and old.offset ~= offset
        if not old and finite(s.routeScanX) then
            s.routeLogical = offset + math.max(0, s.routeScanX - start.X) / scale
        elseif old and finite(s.routeScanX) then
            s.routeLogical = math.max(s.routeLogical or old.offset,
                old.offset + math.max(0, s.routeScanX - old.start.X) / old.scale)
        end
        -- Without configured positions, retain the original track origin when
        -- the drill itself advances or is streamed out and back in.
        if old and not configured and not bandChanged then start = old.start end
        s.routeGeometry = {start = start, finishX = configured and finish.X or 36000,
            scale = scale, offset = offset}
        s.routeLogical = math.max(offset, s.routeLogical or offset)
        if old and not bandChanged and finite(s.routeScanX) then
            -- Route attributes can arrive after the drill. Recalibration within
            -- the same band must not turn a forward physical checkpoint backward.
            s.routeScanX = math.min(s.routeGeometry.finishX, math.max(start.X, s.routeScanX))
            s.routeLogical = offset + math.max(0, s.routeScanX - start.X) / scale
        else
            s.routeScanX = math.min(s.routeGeometry.finishX,
                start.X + math.max(0, s.routeLogical - offset) * scale)
        end
        if bandChanged then
            s.chests = {}
            s.sweepComplete, s.sweepCompletedAt, s.emptySince, s.runExhausted = nil, nil, nil, nil
        end
        return bandChanged
    end
    function M.initializeRoute(ctx)
        M.syncRoute(ctx.drill)
        local geometry = api.state.routeGeometry
        if geometry then ctx.scanEnd = geometry.finishX end
    end
    function M.scanPoint(ctx, x, ground)
        local geometry = api.state.routeGeometry
        local base = geometry and geometry.start or point(ctx)
        return Vector3.new(x, base.Y + (ground and 0 or 100), base.Z)
    end
    function M.commitRoute(ctx, position)
        local s, geometry = api.state, api.state.routeGeometry
        if not geometry then return end
        local x = math.min(geometry.finishX, math.max(s.routeScanX or geometry.start.X, position.X))
        s.routeScanX, ctx.flags.ScanX = x, x
        s.routeLogical = geometry.offset + math.max(0, x - geometry.start.X) / geometry.scale
    end
    function M.cancel(ctx)
        local token = ctx.travel
        if not token then return end
        token.cancelled = true
        if token.tween then pcall(function() token.tween:Cancel() end) end
        ctx.travel = nil
    end
    function M.paused(ctx)
        if ctx.questOwns or ctx.questDriving or ctx.questSeating then return true end
        if ctx.dungeon then return true end
        if ctx.smartLootWindow and now() < ctx.smartLootWindow.untilAt and coroutine.running() ~= ctx.featureThread then return true end
        if ctx.defenseMoving or ctx.pendingThreat or now() < (ctx.dodgeUntil or 0) then return true end
        if ctx.featureHold and coroutine.running() ~= ctx.featureThread then return true end
        local read, paused = pcall(function() return api.Players.LocalPlayer.GameplayPaused end)
        return read and paused == true
    end
    local function travel(ctx, destination, progress)
        if M.paused(ctx) then return false end
        M.cancel(ctx)
        local token = {thread = coroutine.running()}
        ctx.travel = token
        while not token.cancelled and ctx.active and api.owned() do
            ctx.check()
            if M.paused(ctx) then M.cancel(ctx); return false end
            local origin = point(ctx)
            local delta = destination - origin
            if delta.Magnitude <= 1 then ctx.travel = nil; return true end
            -- Continuous linear segments avoid a fresh teleport for each depth step.
            local scale = math.min(1, 300 / delta.Magnitude)
            local goal = Vector3.new(origin.X + delta.X * scale, origin.Y + delta.Y * scale, origin.Z + delta.Z * scale)
            local speed = 600
            local duration = (goal - origin).Magnitude / speed
            local started, last = now(), now()
            if tweenService and TweenInfo and Enum.EasingStyle and Enum.EasingDirection then
                local made, tween = pcall(function()
                    return tweenService:Create(ctx.root, TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
                        {CFrame = CFrame.new(goal)})
                end)
                if made then
                    token.tween = tween
                    local played = pcall(function() tween:Play() end)
                    if not played then M.cancel(ctx); return false end
                end
            end
            local elapsed = 0
            while elapsed < duration and not token.cancelled do
                ctx.check()
                if M.paused(ctx) then M.cancel(ctx); return false end
                local current = now()
                local gap = current - last; last = current
                -- Fallback is interpolated too; a slow frame never jumps to the endpoint.
                elapsed = elapsed + math.min(math.max(gap, 0), 0.12)
                if token.tween then elapsed = current - started
                else ctx.root.CFrame = frame(origin, goal - origin, math.min(1, elapsed / duration)) end
                if progress then progress(point(ctx)) end
                if ctx.root.AssemblyLinearVelocity then ctx.root.AssemblyLinearVelocity = Vector3.zero end
                ctx.featurePulse = coroutine.running() == ctx.featureThread and current or ctx.featurePulse
                task.wait(0.03)
            end
            if token.cancelled then return false end
            if token.tween then pcall(function() token.tween:Cancel() end); token.tween = nil end
            if M.paused(ctx) then M.cancel(ctx); return false end
            ctx.root.CFrame = CFrame.new(goal)
            if progress then progress(goal) end
        end
        if ctx.travel == token then ctx.travel = nil end
        return false
    end
    function M.travel(ctx, destination, progress)
        local ok, reached = pcall(travel, ctx, destination, progress)
        if not ok then
            -- A cancelled character or interrupted feature must never leave an
            -- engine tween moving the root after its coroutine has unwound.
            M.cancel(ctx)
            error(reached, 0)
        end
        return reached
    end
    local function deadStream(token)
        return token.done or type(token.thread) == 'thread' and coroutine.status(token.thread) == 'dead'
    end
    local function clearStream(ctx, token)
        if ctx.streamRequest == token then ctx.streamRequest = nil end
        if token.ctx and token.ctx.streamRequest == token then token.ctx.streamRequest = nil end
        if api.state.itemReloadFlight == token then api.state.itemReloadFlight = nil end
    end
    local function cancelStream(ctx, token)
        if not deadStream(token) then
            if now() < (token.cancelRetryAt or 0) then return false end
            token.cancelRetryAt = now() + 0.5
            if type(token.thread) == 'thread' and type(task.cancel) == 'function' then pcall(task.cancel, token.thread) end
            if not deadStream(token) then token.cancelFailed = true; return false end
        end
        token.expired, token.done, token.ok, token.cancelFailed = true, true, false, nil
        clearStream(ctx, token)
        return true
    end
    function M.stepItemReload(ctx)
        -- Retain an uncancellable read across worker replacement/reexecution.
        -- Its real return (or confirmed closed coroutine) alone frees the slot.
        local token = api.state.itemReloadFlight
        if not token then return end
        if deadStream(token) then clearStream(ctx, token); return end
        if now() >= token.started + 3.5 then token.timedOut = true end
        if token.cancelled or token.timedOut then cancelStream(ctx, token) end
    end
    local function streamAhead(ctx, position)
        M.stepItemReload(ctx)
        local flight = api.state.itemReloadFlight
        if flight and flight ~= ctx.streamRequest then return end
        if ctx.streamRequest then
            local token = ctx.streamRequest
            if token.purpose == 'remembered-item' then
                if not deadStream(token) then return end
            elseif now() - token.started > 8 and token.thread and coroutine.status(token.thread) ~= 'dead' then
                if type(task.cancel) == 'function' then pcall(task.cancel, token.thread) end
                if coroutine.status(token.thread) ~= 'dead' then token.cancelFailed = true; return end
            end
            if not token.done and (not token.thread or coroutine.status(token.thread) ~= 'dead') then return end
            ctx.streamRequest = nil
        end
        if now() < (ctx.streamAt or 0) or ctx.streamUnsupported then return end
        local read, method = pcall(function() return api.Players.LocalPlayer.RequestStreamAroundAsync end)
        if not read or type(method) ~= 'function' then ctx.streamUnsupported = true; return end
        ctx.streamAt = now() + 2
        -- Item reloads share the route's one streaming slot. At most one reload
        -- every eight seconds; the route otherwise keeps its existing cadence.
        local queued = ctx.itemReloadRequest
        if queued and queued.cancelled then ctx.itemReloadRequest = nil; queued = nil end
        local token
        if queued and now() >= math.max(ctx.itemReloadAt or 0, api.state.itemReloadAt or 0) then
            token, position = queued, queued.position
            ctx.itemReloadRequest = nil
        else token = {position = position} end
        token.started = now(); ctx.streamRequest = token
        if token.purpose == 'remembered-item' then
            token.ctx = ctx; api.state.itemReloadFlight = token
        end
        token.thread = task.spawn(function()
            if not ctx.active or token.cancelled or api.owned and not api.owned() then
                token.done, token.ok = true, false; return
            end
            if token.purpose == 'remembered-item' then
                if token.guard and not token.guard() then
                    token.done, token.ok, token.skipped = true, false, true
                    if api.state.itemReloadFlight == token then api.state.itemReloadFlight = nil end
                    return
                end
                ctx.itemReloadAt, api.state.itemReloadAt = now() + 8, now() + 8
                token.called = true
            end
            local ok = pcall(method, api.Players.LocalPlayer, position,
                token.purpose == 'remembered-item' and 0.75 or 3)
            token.done, token.ok = true, ok
            if api.state.itemReloadFlight == token then api.state.itemReloadFlight = nil end
        end)
    end
    function M.prefetchAt(ctx, position) streamAhead(ctx, position) end
    function M.requestItemReload(ctx, position, guard)
        local flight = api.state.itemReloadFlight or ctx.streamRequest
        if flight and flight.cancelFailed and not deadStream(flight) then return nil end
        if not ctx.active or not validVector(position) or ctx.streamUnsupported
            or workspace:GetAttribute('InfiniteRebasing')
            or ctx.itemReloadRequest or ctx.streamRequest and ctx.streamRequest.purpose == 'remembered-item'
                and not ctx.streamRequest.done and (not ctx.streamRequest.thread or coroutine.status(ctx.streamRequest.thread) ~= 'dead')
            or now() < math.max(ctx.itemReloadAt or 0, api.state.itemReloadAt or 0) then return nil end
        local available, enabled = pcall(function() return workspace.StreamingEnabled end)
        local read, method = pcall(function() return api.Players.LocalPlayer.RequestStreamAroundAsync end)
        if available and enabled == false or not read or type(method) ~= 'function' then return nil end
        local token = {position = position, purpose = 'remembered-item', queuedAt = now(), guard = guard}
        ctx.itemReloadRequest = token
        return token
    end
    function M.pollItemReload(ctx, token)
        M.stepItemReload(ctx)
        if token.cancelled or token.done then return end
        local flight = api.state.itemReloadFlight or ctx.streamRequest
        if not token.started and flight and flight.cancelFailed then token.blocked = true; return end
        -- Also progresses when the normal chest sweep is parked/exhausted.
        streamAhead(ctx, M.scanPoint(ctx, api.state.routeScanX or point(ctx).X, true))
    end
    function M.cancelItemReload(ctx, token)
        token.cancelled = true
        if ctx.itemReloadRequest == token then ctx.itemReloadRequest = nil end
        if token.started then cancelStream(ctx, token) end
        -- Failed cancellation retains the actual read; late replies cannot
        -- resume the retired loot job or start a parallel area request.
    end
    function M.routeReady(ctx, x)
        local ground = M.scanPoint(ctx, x, true)
        streamAhead(ctx, ground)
        -- A returned prefetch request does not establish that usable map geometry
        -- arrived. Check the next track position independently of the request.
        local read, streaming = pcall(function() return workspace.StreamingEnabled end)
        local chunks = workspace:FindFirstChild('Chunks')
        if not chunks and not (read and streaming == true) then return true end
        if not workspace.Raycast or not RaycastParams then return true end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {ctx.character, ctx.drill, workspace:FindFirstChild('Npc')}
        local found, result = pcall(function()
            return workspace:Raycast(ground + Vector3.new(0, 40, 0), Vector3.new(0, -240, 0), params)
        end)
        if found and result then ctx.streamWaiting = nil; return true end
        ctx.streamWaiting = x
        local s = api.state
        local message = 'Waiting for loaded tunnel at x=' .. tostring(math.floor(x)) .. '; holding forward checkpoint'
        s.featureStatus = message
        if now() >= (ctx.streamNoticeAt or 0) then
            ctx.streamNoticeAt = now() + 10
            print('[ChestFarm] ' .. message)
        end
        return false
    end
    function M.travelRoute(ctx, x)
        -- Prefetch is useful during an engine loading pause too; it must not
        -- depend on permission to move the character first.
        streamAhead(ctx, M.scanPoint(ctx, x, true))
        -- An incomplete snapshot may not have reached nearby Common chests yet.
        -- Keep scanning this checkpoint; known chests and quest actions remain
        -- usable while the resumable reader discovers the rest of the map.
        if ctx.worldScan then return false end
        if M.paused(ctx) then return false end
        -- Rise at the checkpoint first; chest collection must not set the scan
        -- height or sideways route axis for the rest of the run.
        M.hover(ctx)
        local checkpoint = api.state.routeScanX or point(ctx).X
        if not M.travel(ctx, M.scanPoint(ctx, checkpoint)) then return false end
        if not M.routeReady(ctx, x) then return false end
        return M.travel(ctx, M.scanPoint(ctx, x), function(position) M.commitRoute(ctx, position) end)
    end
    function M.cleanup(ctx)
        pcall(M.cancel,ctx)
        M.releaseHover(ctx)
        local token = ctx.streamRequest
        if token and token.purpose == 'remembered-item' then M.cancelItemReload(ctx, token)
        elseif token and token.thread and coroutine.status(token.thread) ~= 'dead' then pcall(task.cancel, token.thread) end
        ctx.streamRequest = nil
        if ctx.itemReloadRequest then ctx.itemReloadRequest.cancelled = true; ctx.itemReloadRequest = nil end
    end
    return M
end

end)()
    local movement = buildMovement(api)
    F.travelDepth, F.cancelTravel = movement.travel, movement.cancel
    F.syncRoute, F.initializeRoute, F.travelRoute = movement.syncRoute, movement.initializeRoute, movement.travelRoute
    F.hover = movement.hover
    local DEFAULTS = { lootExtract = false, minutes = 7, classQuest = false, driveDepth = true }
    local saveStore=assert(api.saveStore,'DTEC account store is required')
    local function clamp(value, low, high, fallback)
        value = tonumber(value)
        if not value or value ~= value or math.abs(value) == math.huge then return fallback end
        return math.max(low, math.min(high, value))
    end
    local function getService(name)
        local ok, value = pcall(function() return game:GetService(name) end)
        return ok and value or nil
    end
    local function validate(data)
        data = type(data) == 'table' and data or {}
        -- Preserve either former optional choice as the one combined feature.
        -- An explicit new OFF takes precedence over old saved flags.
        local enabled = data.lootExtract == true
        if data.lootExtract == nil then enabled = data.smartLoot == true or data.extraction == true end
        return { chest = true, lootExtract = enabled,
            minutes = clamp(data.minutes, 0, 180, DEFAULTS.minutes), classQuest = data.classQuest == true,
            driveDepth = data.driveDepth ~= false, schema = 40 }
    end
    local previousConfig,previousAccountId=s.config,s.configAccountId
    local loaded=saveStore:get('settings')
    local accountId=saveStore.accountId
    -- Only the currently running legacy client can migrate its untagged config.
    -- Never import a shared legacy disk/teleport profile into an unknown account.
    if accountId and previousConfig and (previousAccountId==accountId or previousAccountId==nil)then loaded=previousConfig end
    s.config=validate(loaded);s.configAccountId=accountId
    local cfg=s.config
    local identityPending=accountId==nil
    local earlyChanges={}
    local function hydrate()
        if not identityPending then return true,false end
        local saved=saveStore:get('settings')
        local resolved=saveStore.accountId
        if not resolved then return false,false end
        if previousAccountId==resolved and previousConfig then saved=previousConfig end
        local merged=validate(saved)
        for key in pairs(earlyChanges)do merged[key]=cfg[key]end
        -- Quest and GUI modules retain this table. Identity readiness updates
        -- its contents rather than replacing their captured configuration.
        for key in pairs(cfg)do cfg[key]=nil end
        for key,value in pairs(merged)do cfg[key]=value end
        accountId=resolved;s.configAccountId=resolved;identityPending=false;earlyChanges={}
        return true,true
    end
    local function persist()
        if not hydrate()then return false end
        return saveStore:set('settings',cfg)
    end
    local function status(text)
        if s.featureStatus ~= text then
            s.featureStatus, s.featureStatusAt = text, now()
            print('[DTEC JoeJoe Automation] ' .. text)
        end
    end
    function F.change(key, value)
        local _,hydrated=hydrate()
        if key == 'smartLoot' or key == 'extraction' then key = 'lootExtract' end
        if DEFAULTS[key] == nil then if hydrated then persist()end;return end
        if key == 'minutes' then cfg.minutes = clamp(value, 0, 180, cfg.minutes)
        elseif type(value) == 'boolean' then cfg[key] = value else return end
        if identityPending then earlyChanges[key]=true end
        if key=='classQuest' and not value then
            if not (s.churchSave and s.churchSave.issued)then s.questChurchExit=nil;s.questActivity=nil end
        end
        persist()
        if key == 'classQuest' and not value and quest and s.farm then quest.cleanup(s.farm) end
        if key == 'lootExtract' and not value and s.farm then
            s.farm.smartLootWindow = nil
            if bring then bring.cleanup(s.farm) end
        end
        -- An option change never resets chest progress or replaces a live farm.
        status('Chest farm running; optional settings updated')
        if s.gui then pcall(s.gui.update) end
    end
    -- Freeze observations before extraction cleans up the worker. Fixed labels
    -- and finite scalars only: never copy a status, request or inventory object.
    local function questExitContext(ctx,watch,at)
        local player=api.Players.LocalPlayer
        if not ctx or not ctx.active or s.farm~=ctx or ctx.character~=player.Character then return end
        local function number(v)
            return type(v)=='number' and v==v and math.abs(v)<math.huge and v>=0 and v or nil
        end
        local function age(v)local n=number(v);return n and n<=at and at-n or nil end
        local phase=ctx.questDepthEconomy and ctx.questDepthEconomy.phase
        local details={at=at,runStarted=s.lootStarted,
            phase=({funding=true,loot=true,drive=true,upgrades=true})[phase] and phase or 'unknown',
            idleAge=age(watch.at),workerAge=age(ctx.featurePulse),walletAge=age(s.questWalletAt),
            equipmentAge=s.equipmentRequest and age(s.equipmentRequest.started),
            route=ctx.routeParked==true and 'parked' or 'unparked',
            work=ctx.questHealing and 'recovery' or ctx.questDrivingDefense and 'drive-defense'
                or ctx.questMineEntry and 'mine-transition' or ctx.questMining and 'mining'
                or ctx.questStartup and 'startup' or ctx.questCombat and 'combat'
                or ctx.questDriving and 'driving' or ctx.questSeating and 'seat-entry'
                or ctx.questChestTaking and 'chest' or s.questDelivery and 'delivery' or 'other',
            flags={},calls={}}
        for _,entry in ipairs({
            {'currentChest',ctx.currentChest},{'featureHold',ctx.featureHold},{'questOwns',ctx.questOwns},
            {'chestLease',ctx.questChestLease},{'smartLoot',ctx.smartLootWindow},{'defense',ctx.defenseMoving},
            {'equipment',s.equipmentRequest},{'loot',s.lootRequest},{'bring',s.bringDelivery},
            {'delivery',s.questDelivery},{'cash',s.questCashJob},{'upgrade',s.questUpgradeJob},
            {'equipmentLock',ctx.bringEquipmentLock},{'worldScan',ctx.worldScan or ctx.worldReading},
            {'workerFailed',ctx.failed},{'chestPending',ctx.chestsDirty or ctx.chestCandidatesPending or next(ctx.worldPending or {})},
            {'paused',player.GameplayPaused==true},{'cutscene',workspace:GetAttribute('InCutScene')==true},
            {'rebase',workspace:GetAttribute('InfiniteRebasing')==true},
        })do if entry[2]then details.flags[#details.flags+1]=entry[1]end end
        for _,key in ipairs({'drive','throttle','cash','drag','shop','wallet','upgrade','upgradeWallet',
            'classes','crateRead','crateClaim','medicalDrop','healingWallet','inventoryDrop','place'})do
            if s.questCalls and s.questCalls[key]then details.calls[#details.calls+1]=key end
        end
        local drill=ctx.drill
        pcall(function()if drill and drill==workspace:FindFirstChild('Drill')then
            local driver=drill:GetAttribute('DriverUserId')
            details.driver=driver==nil and 'none' or number(driver) and (driver==player.UserId and 'self' or 'other') or 'invalid'
            details.fuel=number(drill:GetAttribute('Fuel'));details.capacity=number(drill:GetAttribute('MaxFuel'))
            local seat=ctx.humanoid.SeatPart
            details.seat=not seat and (ctx.humanoid.Sit and 'sit-only' or 'none')
                or seat:IsDescendantOf(drill) and 'drill' or 'other'
        end end)
        pcall(function()
            local hotbar=controller('HotbarController');local ui=hotbar and hotbar.BackpackUI
            details.hotbar=ui and (ui.Visible==true and 'visible' or 'hidden') or 'unavailable'
        end)
        -- Freeze the actual planner/native handoff state, separately from the
        -- last human-readable status. A stale status is not the current gate.
        local plans={waiting=true,complete=true,unsupported=true,advance=true,combat=true,mining=true,
            depth=true,fuel=true,chests=true,gold=true,sale=true,upgrades=true,potion=true,shred=true,turret=true,dungeon=true}
        pcall(function()
            local plan=quest and quest.plan(s.classData,s.questCatalog,cfg.driveDepth)
            details.planner=plan and plans[plan.kind] and plan.kind or 'unknown'
            local native=player:GetAttribute('InDungeon')
            details.nativeDungeon=native==true and 'yes' or native==false and 'no' or 'unknown'
            local ui=controller('DungeonUIController');local root=ui and ui._BoundDungeon
            details.boundRoom=not ui and 'unavailable' or not root and 'none'
                or quest.drillSupport.mineshaft(root) and 'mine' or 'other'
            local latch=s.questRefuelLatch
            details.refuel=not latch and 'none' or latch.drill==ctx.drill and 'active' or 'other-drill'
            details.refuelAge=latch and latch.drill==ctx.drill and age(latch.started) or nil
            local retry=ctx.questDriveRetryAt
            details.driveRetryIn=retry==nil and 0 or number(retry) and math.max(0,retry-at) or nil
            local lease=s.questDriveLease
            details.driveLease=not lease and 'none' or (lease.ctx~=ctx or lease.drill~=ctx.drill) and 'other-context'
                or lease.retired and 'retired' or not lease.abandoned and 'active'
                or lease.stopAccepted==true and 'stop-accepted' or lease.stopIssued and 'stop-unresolved' or 'abandoned'
            details.equipmentTransport=not s.equipmentRequest and 'none' or s.equipmentRequest.settled==true and 'settled' or 'pending'
            details.routeGate=ctx.currentChest and 'chest' or ctx.featureHold and 'feature' or ctx.defenseMoving and 'defense'
                or at<(ctx.dodgeUntil or 0) and 'dodge' or s.bringDelivery and 'bring' or s.lootRequest and 'loot'
                or s.equipmentRequest and 'equipment' or ctx.routeParked~=true and 'await-ack' or 'ready'
        end)
        local text=type(s.questStatus)=='string' and s.questStatus or ''
        for _,entry in ipairs({
            {'Head start:','head-start'},{'Waiting for native class catalog','planner-wait'},
            {'Previous native driver stop','stop-unresolved'},
            {'Native driver stop has not cleared','stop-owner'},{'Approaching driver seat','seat-start'},
            {'Drill start not confirmed','start-timeout'},{'Drill start failed','start-retry'},
            {'Native drill seats still loading','seats-loading'},{'Native physical seat','seats-loading'},
            {'Another player is driving','foreign-driver'},{'No loaded free fuel','fuel-empty'},
            {'Drill fuel state loading','fuel-loading'},{'Refuelling','refuelling'},
            {'Leaving the actual seat','seat-exit'},{'Seat exit unconfirmed','seat-exit'},
            {'Driving input paused','text-focus'},{'Drill made no observed distance','drive-stalled'},
            {'Wall','wall'},{'Owned pickaxe readiness','pickaxe-unready'},
            {'Mining waits','mining-wait'},{'Awaiting Void startup','startup'},
            {'Claiming owned Void','startup'},{'Checking loaded chests','chest-scan'},
            {'Opening a nearby chest','chest-open'},{'Delivery did not confirm','delivery-unconfirmed'},
            {'Driving drill with native','driving'},{'Mobile native seat throttle','driving'},
            {'Native forward input unavailable','driving'},
        })do if text:find(entry[1],1,true)==1 then details.stage=entry[2];break end end
        return details
    end
    -- This clock survives worker recovery. Requests, retry messages, local
    -- movement and camera changes are not evidence of useful quest progress.
    function F.checkQuestExit(ctx)
        if not cfg.classQuest or not s.lootStarted or s.questChurchExit then return end
        local watch = s.questActivity
        if not watch then watch = {at = now(), values = {}, health = setmetatable({}, {__mode='k'})}; s.questActivity = watch end
        local function increase(key, value)
            if type(value) ~= 'number' or value ~= value or math.abs(value) == math.huge then return end
            local before = watch.values[key]
            if before ~= nil and value > before then watch.at = now() end
            watch.values[key] = value
        end
        for _, key in ipairs({'coreEarned','coinEarned','smartPickups','chestProgress','lootObserved','confirmedQuestUpgrades'}) do
            increase(key, (s.stats or {})[key] or 0)
        end
        local data = s.classData
        local progress = data and data.ClassProgress and data.ClassProgress[data.SelectedClass]
        if progress then
            increase(tostring(data.SelectedClass)..':level', progress.Level)
            for key, value in pairs(progress.Objectives or {}) do increase(tostring(data.SelectedClass)..':'..key, value) end
        end
        local plan=quest and quest.plan(s.classData,s.questCatalog,cfg.driveDepth)
        if ctx then
            if api.Players.LocalPlayer:GetAttribute('InDungeon')~=true then watch.inDungeon=false
            elseif quest and quest.drillSupport.activeMine() and not watch.inDungeon then
                watch.inDungeon=true;watch.at=now() -- One confirmed native entry starts a new activity.
            end
            -- Repeated damage/regeneration is not forward recovery. Retain the
            -- same-life high through worker/temporary healing handoffs; only a
            -- new HP fraction high can refresh the global activity deadline.
            local h=ctx.humanoid
            local hp,maximum=h.Health,h.MaxHealth
            local valid=ctx.character==api.Players.LocalPlayer.Character and h.Parent==ctx.character
                and type(hp)=='number' and hp==hp and hp>0 and hp<math.huge
                and type(maximum)=='number' and maximum==maximum and maximum>0 and maximum<math.huge
            local recovery=watch.recovery
            local same=recovery and recovery.character==ctx.character and recovery.humanoid==h
                and recovery.job==game.JobId and recovery.runStarted==s.lootStarted
            if ctx.questHealing and valid then
                local ratio=hp/maximum
                if not same then
                    watch.recovery={character=ctx.character,humanoid=h,maximum=maximum,high=ratio,
                        job=game.JobId,runStarted=s.lootStarted}
                elseif recovery.maximum~=maximum then
                    recovery.maximum=maximum;recovery.high=math.max(recovery.high,ratio)
                elseif ratio>recovery.high then
                    recovery.high=ratio;watch.at=now()
                end
            elseif not valid or not same or hp/maximum>=.7 then watch.recovery=nil end
            local mining = ctx.questMineJob
            for _, target in pairs({combat=ctx.combatTarget, mining=mining and mining.node}) do
                if target and target.Parent then
                    local health = target:FindFirstChildOfClass('Humanoid') or target:FindFirstChild('Health')
                    local value = F.isFuelLeech(target) and tonumber(target:GetAttribute('FuelLeechHealth'))
                        or health and (health:IsA('Humanoid') and health.Health or health.Value)
                    if type(value)=='number' then
                        local before = watch.health[target]
                        if before and value < before then watch.at = now() end
                        watch.health[target] = value
                    end
                end
            end
            local wall=ctx.questWallWork
            local node=wall and wall.node
            local band=workspace:GetAttribute('InfiniteDepthOffsetMeters')
            if node and node.Parent and node:IsDescendantOf(workspace) and wall.drill==ctx.drill
                and ctx.drill==workspace:FindFirstChild('Drill') and ctx.drill.Parent and wall.band==band then
                local value=tonumber(node:GetAttribute('Health'))
                if type(value)=='number' and value==value and math.abs(value)<math.huge then
                    local previous=watch.wall
                    local same=previous and previous.node==node and previous.drill==ctx.drill and previous.band==band
                    local before=same and watch.health[node]
                    if before and value<before then watch.at=now()end
                    watch.health[node]=value;watch.wall={node=node,drill=ctx.drill,band=band}
                else watch.wall=nil end
            else watch.wall=nil end
            -- DistanceController reads the actual Drill pivot, not the character
            -- or a throttle request. Native class counters can arrive later.
            local seen,metres,band=pcall(function()
                local player=api.Players.LocalPlayer
                local drill=workspace:FindFirstChild('Drill');local lease=s.questDriveLease
                if not cfg.driveDepth or not plan or plan.kind~='depth' or not ctx.active or s.farm~=ctx
                    or ctx.character~=player.Character or ctx.humanoid.Parent~=ctx.character or ctx.humanoid.Health<=0
                    or ctx.drill~=drill or not drill or not drill.Parent or not ctx.questDriving
                    or drill:GetAttribute('DriverUserId')~=player.UserId or not lease or lease.ctx~=ctx
                    or lease.drill~=drill or not lease.confirmed or lease.abandoned then return end
                local native=controller('DistanceController')
                return native and native.CurrentLogicalDistance,workspace:GetAttribute('InfiniteDepthOffsetMeters')
            end)
            local drive=watch.drill
            if seen and type(metres)=='number' and metres==metres and math.abs(metres)<math.huge then
                local same=drive and drive.character==ctx.character and drive.humanoid==ctx.humanoid
                    and drive.drill==ctx.drill and drive.band==band and drive.job==game.JobId
                    and drive.runStarted==s.lootStarted and drive.class==plan.name
                if not same then
                    drive={character=ctx.character,humanoid=ctx.humanoid,drill=ctx.drill,band=band,job=game.JobId,
                        runStarted=s.lootStarted,class=plan.name,distanceHigh=metres};watch.drill=drive
                elseif not drive.active then
                    drive.distanceHigh=math.max(drive.distanceHigh,metres) -- Resume calibrates; it is not progress.
                elseif metres>drive.distanceHigh+1 then
                    drive.distanceHigh=metres;drive.lastProgressAt=now();watch.at=now()
                end
                drive.active=true
            elseif drive then drive.active=false end
        end
        local minutes=plan and plan.kind=='depth' and cfg.driveDepth and 35 or 20
        local reason = now()-s.lootStarted >= minutes*60 and tostring(minutes)..'-minute quest run limit reached'
            or now()-watch.at >= 90 and 'No meaningful progress for 1.5 minutes'
        if reason then
            local requestedAt=now()
            s.questChurchExit = {reason=reason, requestedAt=requestedAt}
            local ok,details=pcall(questExitContext,ctx,watch,requestedAt)
            if ok then s.questChurchExit.observed=details end
            status(reason..'; saving at a church / altar before leaving')
        end
    end
    function F.extractionEnabled() return s.questChurchExit ~= nil or cfg.lootExtract and not cfg.classQuest end
    function F.extractionReady()
        return s.questChurchExit ~= nil or F.extractionEnabled() and s.lootStarted ~= nil and now() - s.lootStarted >= cfg.minutes * 60
    end
    local buildGui = (function()
return function(api)
    local s, cfg = api.state, api.state.config
    local ui = { connections = {} }
    local function make(class, parent, props)
        local item = Instance.new(class)
        for key, value in pairs(props or {}) do item[key] = value end
        item.Parent = parent
        return item
    end
    local color = {
        bg = Color3.fromRGB(14, 20, 33), card = Color3.fromRGB(24, 33, 49),
        edge = Color3.fromRGB(44, 59, 78), text = Color3.fromRGB(232, 240, 250),
        muted = Color3.fromRGB(141, 160, 180), accent = Color3.fromRGB(75, 220, 194)
    }
    local font = Enum.Font.Gotham
    local bold = Enum.Font.GothamBold
    local function rounded(item, radius)
        make('UICorner', item, { CornerRadius = UDim.new(0, radius or 10) })
    end
    local function label(parent, text, x, y, width, height, size, tint, strong)
        return make('TextLabel', parent, { BackgroundTransparency = 1, Position = UDim2.new(0, x, 0, y),
            Size = UDim2.new(0, width, 0, height), Text = text, Font = strong and bold or font,
            TextSize = size, TextColor3 = tint or color.text, TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true })
    end
    local parent
    if type(api.env.gethui or gethui) == 'function' then
        local ok, value = pcall(api.env.gethui or gethui); if ok then parent = value end
    end
    parent = parent or api.player:FindFirstChild('PlayerGui')
    if not parent then error('Waiting for PlayerGui') end
    local existing = parent:FindFirstChild('DTECJoeJoeAutomationPanel')
    if existing then existing:Destroy() end
    ui.screen = make('ScreenGui', parent, { Name = 'DTECJoeJoeAutomationPanel', ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 1500, IgnoreGuiInset = false })
    local panel = make('Frame', ui.screen, { Name = 'Panel', AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -20, 0, 30), Size = UDim2.new(0, 410, 0, 570),
        BackgroundColor3 = color.bg, BorderSizePixel = 0, Active = true })
    rounded(panel, 16)
    make('UIStroke', panel, { Color = color.edge, Thickness = 1 })
    local scale = make('UIScale', panel, { Scale = 1 })
    local header = make('Frame', panel, { Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1, Active = true })
    local mark = label(header, 'E', 18, 16, 32, 32, 22, color.accent, true)
    mark.TextXAlignment = Enum.TextXAlignment.Center
    label(header, 'DTEC JoeJoe Automation', 62, 13, 260, 23, 17, color.text, true)
    label(header, 'Version '..tostring(s.version or '?')..' · Account settings', 62, 36, 270, 16, 11, color.muted)
    local minimize = make('TextButton', header, { Text = '−', Font = bold, TextSize = 24,
        TextColor3 = color.muted, BackgroundTransparency = 1, Position = UDim2.new(1, -46, 0, 13),
        Size = UDim2.new(0, 32, 0, 34), AutoButtonColor = false })
    local body = make('Frame', panel, { Position = UDim2.new(0, 0, 0, 64),
        Size = UDim2.new(1, 0, 0, 506), BackgroundTransparency = 1 })
    local function bind(signal, fn)
        local c = signal:Connect(fn); ui.connections[#ui.connections + 1] = c
        return c
    end
    local function row(number, title, subtitle, y, height)
        local box = make('Frame', body, { Position = UDim2.new(0, 16, 0, y),
            Size = UDim2.new(1, -32, 0, height or 70), BackgroundColor3 = color.card, BorderSizePixel = 0 })
        rounded(box, 10)
        label(box, string.format('%02d', number), 12, 12, 26, 20, 12, color.accent, true)
        label(box, title, 46, 10, 228, 22, 14, color.text, true)
        local detail = label(box, subtitle, 46, 35, 232, 26, 10, color.muted)
        return box, detail
    end
    local smart,smartHint = row(1, 'Smart loot + altar extraction', 'Collect useful gear and relics; save at an altar', 0)
    local minimum,minimumHint = row(2, 'Minimum run time', 'Only applies when loot + extraction is ON', 80)
    local classQuest = row(3, 'Auto equipped-class quest', 'Quest weapons, Void gear, smart upgrades and 30/70 healing', 160)
    local depthQuest = row(4, 'Drive for depth / fuel quests', 'Native depth progress or room for contributed fuel', 240)
    local function input(parentBox, value, x, y, width, changed)
        local box = make('TextBox', parentBox, { Text = tostring(value), Font = bold, TextSize = 14,
            TextColor3 = color.accent, BackgroundColor3 = color.bg, BorderSizePixel = 0,
            Position = UDim2.new(0, x, 0, y), Size = UDim2.new(0, width, 0, 32), ClearTextOnFocus = false })
        rounded(box, 7)
        bind(box.FocusLost, function() changed(box.Text); box.Text = tostring(changed()) end)
        return box
    end
    local minutes = input(minimum, cfg.minutes, 282, 11, 62, function(value)
        if value ~= nil then api.change('minutes', value) end
        return cfg.minutes
    end)
    label(minimum, 'min', 348, 14, 26, 24, 10, color.muted)
    local function toggle(parentBox, key)
        local button = make('TextButton', parentBox, { Name = 'Toggle_' .. key, Position = UDim2.new(1, -71, 0, 16),
            Size = UDim2.new(0, 57, 0, 29), Font = bold, TextSize = 11, BorderSizePixel = 0,
            AutoButtonColor = false })
        rounded(button, 8)
        bind(button.Activated, function() api.change(key, not cfg[key]) end)
        return button
    end
    local switches = { lootExtract = toggle(smart, 'lootExtract'), classQuest = toggle(classQuest, 'classQuest'),
        driveDepth = toggle(depthQuest, 'driveDepth') }
    local status = make('Frame', body, { Position = UDim2.new(0, 16, 0, 320), Size = UDim2.new(1, -32, 0, 176),
        BackgroundTransparency = 1 })
    ui.stage = label(status, 'Waiting for readiness…', 0, 0, 378, 31, 12, color.accent, true)
    ui.stats = label(status, '', 0, 34, 378, 137, 11, color.muted)
    local collapsed = false
    bind(minimize.Activated, function()
        collapsed = not collapsed; body.Visible = not collapsed
        panel.Size = UDim2.new(0, 410, 0, collapsed and 64 or 570); minimize.Text = collapsed and '+' or '−'
    end)
    local UIS = api.getService('UserInputService')
    if UIS then
        local dragging, origin, initial
        bind(header.InputBegan, function(inputObject)
            if inputObject.UserInputType == Enum.UserInputType.MouseButton1 or inputObject.UserInputType == Enum.UserInputType.Touch then
                if not dragging then dragging, origin, initial = inputObject, inputObject.Position, panel.Position end
            end
        end)
        bind(UIS.InputEnded, function(inputObject)
            if dragging and (inputObject==dragging or dragging.UserInputType==Enum.UserInputType.MouseButton1
                and inputObject.UserInputType==Enum.UserInputType.MouseButton1)then dragging=nil end
        end)
        bind(UIS.InputChanged, function(inputObject)
            if dragging and (inputObject==dragging or dragging.UserInputType==Enum.UserInputType.MouseButton1
                and inputObject.UserInputType==Enum.UserInputType.MouseMovement) then
                local delta = inputObject.Position - origin
                panel.Position = UDim2.new(initial.X.Scale, initial.X.Offset + delta.X, initial.Y.Scale, initial.Y.Offset + delta.Y)
            end
        end)
    end
    function ui.update()
        for key, button in pairs(switches) do
            button.Text = cfg[key] and 'ON' or 'OFF'
            button.BackgroundColor3 = cfg[key] and color.accent or color.edge
            button.TextColor3 = cfg[key] and color.bg or color.muted
        end
        minutes.TextEditable = cfg.lootExtract and not cfg.classQuest
        minutes.TextTransparency = minutes.TextEditable and 0 or 0.55
        local limit=s.questPlan and s.questPlan.kind=='depth' and cfg.driveDepth and 35 or 20
        smartHint.Text = cfg.classQuest and ((cfg.lootExtract and 'Smart loot ON' or 'Smart loot OFF')..'; quest exit at '..limit..' min or 90s idle') or 'Collect useful gear and relics; save at an altar'
        minimumHint.Text = cfg.classQuest and 'Quest limits: 20 min; depth 35 min / 90s idle' or 'Only applies when loot + extraction is ON'
        local elapsed = math.max(0, api.now() - (s.lootStarted or api.now()))
        local ctx = s.farm
        local optionalActive = s.questChurchExit ~= nil or cfg.lootExtract and (s.runExhausted or elapsed >= cfg.minutes * 60)
            or cfg.lootExtract and (s.lootRequest or ctx and (ctx.featureHold or ctx.gearPickup))
            or s.featureStatusAt and api.now() - s.featureStatusAt < 3
        ui.stage.Text = optionalActive and s.featureStatus or s.status or 'Waiting for readiness…'
        if cfg.classQuest and ctx and (ctx.questOwns or ctx.questDepthEconomy and ctx.questDepthEconomy.phase~='drive') then
            ui.stage.Text = s.questStatus or ui.stage.Text
        end
        if ctx and ctx.questChestLease and ctx.worldReading then ui.stage.Text='Reading loaded map for a quest chest' end
        local h = api.player.Character and api.player.Character:FindFirstChildOfClass('Humanoid')
        local health = h and h.MaxHealth > 0 and math.floor(100 * h.Health / h.MaxHealth) or 0
        local bag = s.sackSize and string.format('%s/%s', s.sackSize, s.sackCapacity or '?') or '—'
        ui.stats.Text = string.format('%02d:%02d elapsed   ·   HP %d%%   ·   Sack %s\n%d chest removals   ·   %d Cores observed',
            math.floor(elapsed / 60), math.floor(elapsed % 60), health, bag, s.stats.lootObserved or 0, s.stats.coreEarned or 0)
        local cores = tonumber(api.player:GetAttribute('CoresEarned'))
        local rateElapsed = s.reportRun and api.now() - s.reportRun.started or elapsed
        if cores and cores == cores and cores >= 0 and cores < math.huge and rateElapsed > 0 then
            ui.stats.Text = ui.stats.Text .. string.format(' · %.1f run Cores/min', cores * 60 / rateElapsed)
        end
        if cfg.lootExtract then
            ui.stats.Text = ui.stats.Text .. string.format('\n%d loot pickups · %s', s.stats.smartPickups or 0, s.smartLootStatus or 'Checking loose items')
        end
        if cfg.classQuest then
            local plan = s.questPlan
            if plan and plan.name then
                local progress = {}
                for i, item in ipairs(plan.unmet or {}) do
                    if i > 2 then break end
                    progress[#progress+1] = string.format('%s %d/%d', item.key, item.count, item.goal)
                end
                ui.stats.Text = ui.stats.Text .. string.format('\n%s Lv %d · %s', plan.name, plan.level, table.concat(progress, ' · '))
                if plan.unsupported and #plan.unsupported>0 then
                    ui.stats.Text = ui.stats.Text .. '\nNot automated: '..table.concat(plan.unsupported, ', ')
                end
                if s.questStatus then ui.stats.Text = ui.stats.Text .. '\n' .. s.questStatus end
                if s.questUpgradeStatus then ui.stats.Text=ui.stats.Text..'\n'..s.questUpgradeStatus end
            else ui.stats.Text = ui.stats.Text .. '\n' .. (s.questStatus or 'Waiting for class quests') end
            if ctx then
                local control=ctx.questChestLease and 'Quest chest' or ctx.featureHold and 'Loot/extraction'
                    or ctx.questOwns and 'Quest' or ctx.travel and 'Chest travel' or ctx.routeParked and 'Route waiting' or 'Chest route'
                ui.stats.Text=ui.stats.Text..'\nMovement: '..control..(ctx.worldReading and ' · reading map' or '')
            end
        end
        local camera = workspace.CurrentCamera
        if camera then scale.Scale = math.min(1, math.max(0.25, math.min((camera.ViewportSize.Y - 60) / 570, (camera.ViewportSize.X - 40) / 410))) end
    end
    function ui.dispose()
        for _, c in ipairs(ui.connections) do pcall(function() c:Disconnect() end) end
        if ui.screen then pcall(function() ui.screen:Destroy() end) end
    end
    ui.update()
    return ui
end

end)()
    function F.ui(player)
        local ready,hydrated=hydrate()
        if not ready or not player then return end
        if hydrated then persist()end
        if not s.gui and now() >= (s.guiRetryAt or 0) then
            s.guiRetryAt = now() + 10
            local ok, value = pcall(buildGui, { state = s, env = api.env, player = player,
                now = now, getService = getService, change = F.change })
            if ok then s.gui = value else
                if not s.guiWarned then s.guiWarned = true; warn('[Earth Autofarm] GUI waiting: ' .. tostring(value)) end
            end
        end
        if s.gui then pcall(s.gui.update) end
    end
    function F.enabled() return true end
    function F.chestEnabled() return true end
    local function tag(item, name)
        local ok, value = pcall(function() return api.CollectionService:HasTag(item, name) end)
        return ok and value == true
    end
    local function tagged(name)
        local ok, value = pcall(function() return api.CollectionService:GetTagged(name) end)
        return ok and value or {}
    end
    -- Native dungeon-root names from DungeonDoorComponent / DungeonUIController.
    -- Walk every ancestor: a wave room can be nested inside the excluded root.
    function F.skipLootArea(item)
        while item and item ~= workspace do
            if item.Name == 'VampireMansion' or item.Name == 'Goblin_Ring' or item.Name == 'GoblinRing'
                or tag(item, 'VampireMansion') then return true end
            item = item.Parent
        end
        return false
    end
    function F.chestAreaAllowed(ctx,item)
        if not item or not item.Parent then return false end
        local player=api.Players.LocalPlayer
        if not player then return false end
        if player:GetAttribute('InDungeon')~=true then return true end
        if quest and quest.drillSupport and not quest.drillSupport.inDungeon(ctx)then
            -- A verified return/Outside observation can precede native UI clear.
            -- Permit local outdoor chests while retaining the unresolved room;
            -- never use that observation to travel into another native dungeon.
            local current=item
            while current and current~=workspace do
                if quest.drillSupport.mineshaft(current) or current:GetAttribute('SessionDungeonId')~=nil
                    or current.Name=='Goblin_Ring' or current.Name=='GoblinRing' or current.Name=='VampireMansion'
                    or tag(current,'VampireMansion')then return false end
                current=current.Parent
            end
            return item:IsDescendantOf(workspace)
        end
        local mine=quest and quest.drillSupport and quest.drillSupport.activeMine(ctx)
        if mine then return quest.drillSupport.accessible(item)end
        local root=quest and quest.special and quest.special.bound(ctx)
        return root and item:IsDescendantOf(root) or false
    end
    local function children(item) return item and item:GetChildren() or {} end
    local function finite(value)
        return type(value) == 'number' and value == value and math.abs(value) < math.huge
    end
    function F.isFuelLeech(npc)
        if not npc then return false end
        local name=npc:GetAttribute('RealName') or npc.Name
        return name=='FuelLeech' or name=='MagmaFuelLeech' or tag(npc,'FuelLeech')
    end
    function F.enemyAlive(npc)
        if not npc or not npc.Parent or not npc:IsA('Model') or not npc:IsDescendantOf(workspace)
            or npc:GetAttribute('Category')=='Corpse' or npc:GetAttribute('NpcFaction')=='FriendlyCompanion' then return false end
        local h=npc:FindFirstChildOfClass('Humanoid')
        local hp=F.isFuelLeech(npc) and tonumber(npc:GetAttribute('FuelLeechHealth'))
            or h and tonumber(h.Health) or tonumber(npc:GetAttribute('FuelLeechHealth'))
        if not finite(hp) or hp<=0 then return false end
        if h and type(h.GetState)=='function' and Enum.HumanoidStateType.Dead then
            local ok,state=pcall(h.GetState,h)
            if ok and state==Enum.HumanoidStateType.Dead then return false end
        end
        return true
    end
    local function ownFaceWorm(ctx,npc)
        if not ctx or not npc or npc~=ctx.questParasiteTarget then return false end
        local target=npc:FindFirstChild('Target')
        return npc:IsA('Model') and npc.Parent==workspace:FindFirstChild('Npc') and F.enemyAlive(npc)
            and tag(npc,'Worm') and npc:GetAttribute('OnFace')==true and target and target:IsA('ObjectValue')
            and target.Value==ctx.character and api.Players.LocalPlayer.Character==ctx.character
    end
    local function outdoorEnemyAllowed(npc)
        if not npc or not npc.Parent or npc:GetAttribute('SessionDungeonId')~=nil
            or npc:GetAttribute('DungeonWaveNpc')==true
            or quest and quest.drillSupport.mineshaft(npc)then return false end
        local ancestor=npc.Parent
        while ancestor and ancestor~=workspace do
            if ancestor.Name=='Goblin_Ring' or ancestor.Name=='GoblinRing' or ancestor.Name=='VampireMansion'
                or tag(ancestor,'VampireMansion')then return false end
            ancestor=ancestor.Parent
        end
        return true
    end
    local suspendedMeleeDefense
    function F.questTargetAllowed(ctx,npc)
        if ownFaceWorm(ctx,npc)then return true end
        if quest and quest.drillSupport.inDungeon(ctx)then
            local mine=quest.drillSupport.activeMine(ctx)
            local root=not mine and quest.special.bound(ctx)
            if mine and not quest.drillSupport.mineEnemy(npc,mine)
                or root and not quest.special.belongs(npc,root) or not mine and not root then return false end
        elseif not outdoorEnemyAllowed(npc) and not suspendedMeleeDefense(ctx,npc)then return false end
        if F.isFuelLeech(npc)then
            return quest and quest.drillSupport.leechReady(ctx,npc) or false
        end
        if not cfg.classQuest then return true end
        local retry=ctx.questTargetRetry and ctx.questTargetRetry[npc]
        if not retry then return true end
        local h=npc:FindFirstChildOfClass('Humanoid')
        if now()>=retry.untilAt or h and h.Health<retry.health then
            ctx.questTargetRetry[npc]=nil;return true
        end
        return false
    end
    function F.enemies()
        local result, seen = {}, {}
        local function add(npc)
            if F.enemyAlive(npc) and not seen[npc] then
                seen[npc] = true; result[#result + 1] = npc
            end
        end
        for _, npc in ipairs(children(workspace:FindFirstChild('Npc'))) do add(npc) end
        -- DungeonUIController discovers dungeon bosses through NpcManager.Parent.
        for _, manager in ipairs(tagged('NpcManager')) do add(manager.Parent) end
        for _, npc in ipairs(tagged('Watcher')) do add(npc) end
        for _, npc in ipairs(tagged('FuelLeech')) do add(npc) end
        return result
    end
    local function armorFields(npc)
        if not npc then return false,false,false end
        local stone=npc:GetAttribute('Mutation_Stone')==true
        -- Native name/icon presentation also publishes the comma-separated
        -- mutation list. Honor Stone while its separate armor markers stream.
        local mutations=npc:GetAttribute('Mutations')
        if type(mutations)=='string'then
            for mutation in mutations:gmatch('[^,]+')do
                if mutation:match('^%s*(.-)%s*$')=='Stone'then stone=true end
            end
        end
        local name=tostring(npc:GetAttribute('RealName') or npc.Name)
        local watcher=name:find('Watcher',1,true)==1 or tag(npc,'Watcher')
        -- GunRaycast uses the same native deflection attribute/tag on a hit
        -- part or its ancestors. Stone armor can be marked only on its body.
        local ancestor=npc
        while ancestor and ancestor~=workspace do
            if ancestor:GetAttribute('DeflectPart')==true or tag(ancestor,'DeflectPart')then return stone,watcher,true end
            ancestor=ancestor.Parent
        end
        for _,item in ipairs(npc:GetDescendants())do
            if item:GetAttribute('DeflectPart')==true or tag(item,'DeflectPart')then return stone,watcher,true end
        end
        return stone,watcher,false
    end
    function F.swordTargetAllowed(npc)
        if not npc or F.isFuelLeech(npc)then return false end
        local stone,watcher,deflect=armorFields(npc)
        if watcher then return false end
        if stone then
            local passives=F.combatPassives and F.combatPassives()
            return passives and passives.MeleePiercesStoneEnemies==true or false
        end
        return not deflect
    end
    local function part(item)
        if not item or not item.Parent then return nil end
        if item:IsA('BasePart') then return item end
        if item:IsA('Attachment') then return item.Parent and part(item.Parent) end
        if item:IsA('ProximityPrompt') then return part(item.Parent) end
        return (item:IsA('Model') and item.PrimaryPart) or item:FindFirstChild('HumanoidRootPart') or item:FindFirstChild('RootPart')
            or (type(item.FindFirstChildWhichIsA) == 'function' and item:FindFirstChildWhichIsA('BasePart', true))
    end
    local function position(item)
        if not item or not item.Parent then return nil end
        if item:IsA('ProximityPrompt') then return position(item.Parent) end
        if item:IsA('Attachment') then return item.WorldPosition end
        local p = part(item); return p and p.Position
    end
    function F.healingPointSafe(ctx,point)
        if not point or not finite(point.X) or not finite(point.Y) or not finite(point.Z) then return false end
        local player=api.Players.LocalPlayer
        local inside=quest and quest.drillSupport.inDungeon(ctx) or not quest and player and player:GetAttribute('InDungeon')==true
        local mine=inside and quest and quest.drillSupport.activeMine(ctx)
        local room=inside and not mine and quest and quest.special.bound(ctx)
        for _,npc in ipairs(F.enemies())do
            local isPlayer=npc==ctx.character or type(api.Players.GetPlayerFromCharacter)=='function'
                and api.Players:GetPlayerFromCharacter(npc)~=nil
            -- Quest retry suppression is not protection from a living enemy.
            -- Dungeon session ownership, however, keeps another native room's
            -- loaded wave from blocking a chest that it cannot reach.
            local belongs=not inside and outdoorEnemyAllowed(npc) or inside and not mine and not room or mine and quest.drillSupport.mineEnemy(npc,mine)
                or room and quest.special.belongs(npc,room)
            local p=position(npc)
            if not isPlayer and not ownFaceWorm(ctx,npc) and belongs and p and finite(p.X) and finite(p.Y) and finite(p.Z)
                and (p-point).Magnitude<80 then return false end
        end
        return true
    end
    function F.healingChestSafe(ctx,entry)
        if not ctx.questHealing then return true end
        local model=entry and entry.Model
        if not model or not model.Parent or not F.chestAreaAllowed(ctx,model)
            or not F.chestFallbackAllowed(model)then return false end
        local prompt=model:FindFirstChildWhichIsA('ProximityPrompt',true)
        if not prompt or not prompt.Parent or prompt.Enabled==false then return false end
        local target=position(prompt)
        local radius=tonumber(prompt.MaxActivationDistance) or 12
        if not target or not finite(radius) or radius<=0 then return false end
        local offset=math.min(2,radius/4)
        return F.healingPointSafe(ctx,target)
            and F.healingPointSafe(ctx,target+Vector3.new(0,offset,offset))
    end
    function F.oreBroken(packet)
        if type(packet)~='table' then return end
        local node=packet.Node
        if node and type(node.GetAttribute)=='function' and tag(node,'Ore') and node:IsDescendantOf(workspace) then
            s.questBrokenNodes=s.questBrokenNodes or setmetatable({}, {__mode='k'})
            s.questBrokenNodes[node]={session=node:GetAttribute('SessionOreId'),model=node:GetAttribute('Ore_Model')}
        end
        local key=packet.Id
        if type(key)=='string' or type(key)=='number' and finite(key) then
            s.questBrokenOreIds=s.questBrokenOreIds or {};s.questBrokenOreOrder=s.questBrokenOreOrder or {}
            if not s.questBrokenOreIds[key] then
                s.questBrokenOreOrder[#s.questBrokenOreOrder+1]=key;s.questBrokenOreIds[key]=true
                if #s.questBrokenOreOrder>256 then s.questBrokenOreIds[table.remove(s.questBrokenOreOrder,1)]=nil end
            end
        end
    end
    function F.liveOre(node)
        if not node or not node.Parent then return false end
        local session=node:GetAttribute('SessionOreId')
        local record=s.questBrokenNodes and s.questBrokenNodes[node]
        if record and record.session==session and record.model==node:GetAttribute('Ore_Model') then return false end
        if session~=nil and s.questBrokenOreIds and s.questBrokenOreIds[session] then return false end
        -- OreComponent's proxy is CanQuery=false; its loaded child meshes are
        -- queryable. MiningFeedback hides broken meshes without disabling query.
        local function visible(p)
            return p:IsA('BasePart') and p.CanQuery~=false
                and (tonumber(p.Transparency) or 0)<1 and (tonumber(p.LocalTransparencyModifier) or 0)<1
        end
        if visible(node)then return true end
        for _,p in ipairs(node:GetDescendants())do if visible(p)then return true end end
        return false
    end
    function F.bindOreBreaks(ctx)
        if not cfg.classQuest or ctx.oreBreakBound or not api.event or not ctx.connect or now()<(ctx.oreBreakBindAt or 0)then return end
        ctx.oreBreakBindAt=now()+2
        local signal=api.event('OreService','OreBroken')
        if signal then
            ctx.oreBreakBound=true
            ctx.connect(signal,function(packet)
                if ctx.active and api.owned() and cfg.classQuest then F.oreBroken(packet)end
            end)
        end
    end
    F.promptPosition = position
    function F.chestFallbackAllowed(item)
        while item and item ~= workspace do
            local name=tostring(item.Name):lower():gsub('[%s_%-]','')
            local real=tostring(item:GetAttribute('RealName') or ''):lower():gsub('[%s_%-]','')
            if name=='mimic' or name=='mimicchest' or name=='chestmimic'
                or real=='mimic' or real=='mimicchest' or real=='chestmimic' then return false end
            if name=='commonchest' or name=='chestcommon' or real=='commonchest' or real=='chestcommon'
                or item:GetAttribute('RuntimeChestModel') and (name=='common' or real=='common') then return false end
            if tag(item, 'ShopItem') or (tonumber(item:GetAttribute('Cost')) or 0) > 0
                or item:GetAttribute('Robux') == true or item:GetAttribute('ProductId') ~= nil
                or item:GetAttribute('RobuxProductId') ~= nil then return false end
            item = item.Parent
        end
        return true
    end
    local function descendant(item, ancestor)
        local ok, value = pcall(function() return item:IsDescendantOf(ancestor) end)
        return ok and value
    end
    local function ancestry(item, word)
        while item and item ~= workspace do
            if tostring(item.Name):lower():find(word, 1, true) then return item end
            item = item.Parent
        end
    end
    local function id(item)
        if not s.itemDatabase or type(s.itemDatabase.GetId) ~= 'function' then return item.Name end
        local ok, value = pcall(s.itemDatabase.GetId, item)
        return ok and value or item.Name
    end
    local function attr(item, key)
        if s.itemDatabase and type(s.itemDatabase.GetAttribute) == 'function' then
            local ok, value = pcall(s.itemDatabase.GetAttribute, item, key)
            if ok and value ~= nil then return value end
            local found, fallback = pcall(s.itemDatabase.GetAttribute, id(item), key)
            if found then return fallback end
        end
        return type(item) ~= 'string' and item:GetAttribute(key) or nil
    end
    function F.freeWorldItemAllowed(item)
        -- Native ItemDatabase.Apply copies Cost onto ordinary loot templates.
        -- DragController identifies purchasable stock with ShopItem instead.
        -- Only accept that base Cost on a recognized top-level loose item;
        -- keep price overrides, paid ancestors and premium markers excluded.
        local container = workspace:FindFirstChild('Items')
        if quest and quest.fuelCargo and quest.fuelCargo.reserved(item)then return false end
        if not item or item.Parent ~= container or not (item:IsA('Model') or item:IsA('BasePart')) then return false end
        local root = item
        while item and item ~= workspace do
            if tag(item, 'ShopItem') or item:GetAttribute('Robux') == true
                or item:GetAttribute('ProductId') ~= nil or item:GetAttribute('RobuxProductId') ~= nil then return false end
            local cost = tonumber(item:GetAttribute('Cost')) or 0
            if cost > 0 then
                if item ~= root or not s.itemDatabase then return false end
                local ok, base = pcall(s.itemDatabase.GetAttribute, id(root), 'Cost')
                if not ok or tonumber(base) ~= cost then return false end
            end
            item = item.Parent
        end
        return not (quest and quest.inventory) or quest.inventory.allowPickup(s.farm, root)
    end
    function F.chestLootWindow(ctx, point)
        if cfg.lootExtract and bring and bring.available() then
            -- Background delivery scans late drops without parking at the chest.
            ctx.smartLootWindow = nil
            return
        end
        if cfg.lootExtract then
            ctx.smartLootWindow = { position = point, arrivalUntil = now() + 1.5, untilAt = now() + 1.5, expires = now() + 7 }
            s.smartLootStatus = 'Waiting for chest drops'
        end
    end
    function F.smartLootPending(ctx)
        local window = ctx.smartLootWindow
        if not cfg.lootExtract or window and now() >= window.untilAt then ctx.smartLootWindow = nil; return false end
        return window ~= nil
    end
    local function ownedTool(ctx,tool)
        local backpack=api.Players.LocalPlayer:FindFirstChild('Backpack')
        return tool and tool.Parent and (tool.Parent==ctx.character or tool.Parent==backpack)
            and (tool:IsA('Tool') or tool:IsA('Model') and attr(tool,'Tool')==true)
    end
    function F.canSelectEquipment(ctx,tool)
        if not ownedTool(ctx,tool)then return false end
        if tool:IsA('Tool')then return true end
        local native=controller('ToolController')
        local equipId=tool:GetAttribute('ServerToolEquipId')
        -- Missing IDs remain uncertain. Only two explicit unequal native IDs
        -- prove that a leftover character representation is no longer selected.
        return not(native and native.ServerEquipId~=nil and equipId~=nil and equipId~=native.ServerEquipId)
    end
    local function tools(ctx)
        local list, seen, instances = {}, {}, {}
        for _, container in ipairs({ ctx.character, api.Players.LocalPlayer:FindFirstChild('Backpack') }) do
            for _, tool in ipairs(children(container)) do
                if tool.Parent==container and tool:IsA('Tool') then list[#list + 1] = tool; seen[id(tool)] = true;instances[tool]=true end
            end
        end
        -- ToolController equips a Tool=true Model named item+UserId. It is owned gear,
        -- even when its backpack Tool is absent; avoid counting a retained proxy twice.
        local native=controller('ToolController');local active=native and native.ActiveTool
        for _, model in ipairs(children(ctx.character)) do
            local represented=active and active.Tool==model and instances[active.DisplayTool]
            if model.Parent==ctx.character and model:IsA('Model') and attr(model, 'Tool') == true and not represented and not seen[id(model)] then
                list[#list + 1] = model; seen[id(model)] = true
            end
        end
        return list
    end
    -- ToolStack uses MedicalStackCount for relics as well as stacked medical tools.
    local RELICS = {RareShard = true, EpicShard = true, LegendaryShard = true, MythicShard = true, VoidCrystal = true}
    local function isRelic(item) return RELICS[id(item)] == true or attr(item, 'Class') == 'Relic'
        or attr(item,'Category')=='Relic' or attr(item,'Relic')==true or attr(item,'ClassRelic')==true end
    local function stackCount(item)
        local count = item:GetAttribute('MedicalStackCount')
        return type(count) == 'number' and count == count and count > 0 and count < math.huge and math.max(1, math.floor(count)) or 1
    end
    local function inventoryCount(ctx, name, inventory)
        local total = 0
        for _, tool in ipairs(inventory or tools(ctx)) do if id(tool) == name then total = total + stackCount(tool) end end
        return total
    end
    local function toolbarCapacity()
        local hotbar=controller('HotbarController');local ui=hotbar and hotbar.BackpackUI
        if not ui or not ui.Parent or type(ui.GetChildren)~='function' then return 6 end
        -- Native HotbarController maps its direct ImageButtons by LayoutOrder
        -- and binds keys 1..9. Hidden empty slots still provide real capacity.
        local slots,maximum={},0
        for _,slot in ipairs(ui:GetChildren())do
            if slot:IsA('ImageButton')then
                local index=slot.LayoutOrder
                if type(index)=='number' and index==index and index>=1 and index<=9 and index%1==0 then
                    slots[index]=true;maximum=math.max(maximum,index)
                end
            end
        end
        for index=1,maximum do if not slots[index]then return 6 end end
        return maximum>0 and maximum or 6
    end
    local function stacksMedical(item)
        if attr(item,'Class')~='Medkit' then return false end
        local resolver=s.medicalStackResolver
        if not resolver then
            local shared=api.RS and api.RS:FindFirstChild('Shared')
            local module=shared and shared:FindFirstChild('ClassResolver')
            if module then
                local ok,value=pcall(require,module)
                if ok and type(value)=='table' then resolver=value;s.medicalStackResolver=value end
            end
        end
        if not resolver or type(resolver.ResolvePlayerPassives)~='function' then return false end
        local ok,passives=pcall(resolver.ResolvePlayerPassives,api.Players.LocalPlayer,workspace)
        return ok and type(passives)=='table' and passives.StackMedicalTools==true
    end
    local function hasRoom(ctx, item, inventory)
        inventory = inventory or tools(ctx)
        return #inventory < toolbarCapacity() or (RELICS[id(item)] == true or stacksMedical(item))
            and inventoryCount(ctx, id(item), inventory) > 0
    end
    F.isRelic, F.stackCount, F.hasRoom = isRelic, stackCount, hasRoom
    local rarity = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Secret = 7 }
    local GUNS = {Revolver = true, Rifle = true, Shotgun = true, BlackholeGun = true}
    local function rarityRank(item) return rarity[attr(item, 'Rarity')] or 0 end
    local function weaponValue(item)
        local damage = tonumber(attr(item, 'Damage')) or 0
        local speed = tonumber(attr(item, GUNS[attr(item, 'Class')] and 'FireRate' or 'AttackSpeed')) or 1
        if damage ~= damage or damage == math.huge or damage < 0 then return 0 end
        if speed ~= speed or speed == math.huge or speed <= 0 then speed = 1 end
        return damage * speed
    end
    local function findTool(ctx, class, inventory, rarityFirst)
        local best, score, rank
        for _, tool in ipairs(inventory or tools(ctx)) do
            local name = id(tool)
            local candidate = attr(tool, 'Class')
            if name == 'Champions_Hammer' then candidate = 'Pickaxe' end
            if name == 'Sword_Executioner' then candidate = 'Sword' end
            if F.canSelectEquipment(ctx,tool) and (candidate == class or class == 'ItemBag' and (name == 'Large_Sack' or name == 'ItemBag')) then
                local value = class == 'ItemBag' and (tonumber(attr(tool, 'MaxSize')) or (name == 'Large_Sack' and 20 or 10))
                    or weaponValue(tool)
                local tier = rarityRank(tool)
                local different = best and rarityFirst and tier > 0 and rank > 0 and tier ~= rank
                if not best or different and tier > rank or not different and value > score then
                    best, score, rank = tool, value, tier
                end
            end
        end
        return best
    end
    local function activeFor(ctx, tool)
        local c = controller('ToolController')
        local active = c and c.ActiveTool
        if active and not active._Destroyed and active.Tool and active.Tool.Parent == ctx.character
            and (c.ServerEquipId==nil or active.Tool:GetAttribute('ServerToolEquipId')==c.ServerEquipId)then
            local name = id(tool)
            if active.Tool == tool or active.Tool.Name == name
                or active.Tool.Name == name .. tostring(api.Players.LocalPlayer.UserId) then return active end
        end
    end
    local function rebindHandler(ctx,tool)
        local c=controller('ToolController');local name=id(tool)
        if not c or type(c.Equip)~='function' or not name or c.ServerEquipId==nil
            or not finite(c.EquipVersion) then return false end
        local proxy
        for _,piece in ipairs(children(ctx.character))do
            if piece.Parent==ctx.character and attr(piece,'Tool')==true
                and (piece.Name==name or piece.Name==name..tostring(api.Players.LocalPlayer.UserId))
                and piece:GetAttribute('ServerToolEquipId')~=nil
                and piece:GetAttribute('ServerToolEquipId')==c.ServerEquipId then proxy=piece;break end
        end
        if not proxy then return false end
        -- The actual server-selected representation forbids another EquipTool
        -- toggle, even while its local class is missing. Rebuild only the
        -- original native handler after its own ten-second replication budget.
        s.equipRebindRecords=s.equipRebindRecords or setmetatable({}, {__mode='k'})
        local record=s.equipRebindRecords[proxy]
        local version=c.EquipVersion
        if not record or record.character~=ctx.character or record.controller~=c or record.serverId~=c.ServerEquipId
            or version~=record.version and version~=record.resultVersion then
            record={character=ctx.character,controller=c,serverId=c.ServerEquipId,version=version,started=now()}
            s.equipRebindRecords[proxy]=record
        end
        if record.attempted or now()-record.started<10 then return true end
        local own=s.equipRecords[tool];local calls=quest and quest.calls or {}
        local scene=controller('CutSceneController');local native=c.ActiveTool
        local nativeId=native and native.Tool and native.Tool:GetAttribute('ServerToolEquipId')
        local otherCurrent=native and not native._Destroyed and native.Tool and native.Tool.Parent==ctx.character
            and (nativeId==nil or nativeId==c.ServerEquipId)
        if not ctx.active or not api.owned() or ctx.character~=api.Players.LocalPlayer.Character or ctx.humanoid.Health<=0
            or tool.Parent~=ctx.character and tool.Parent~=api.Players.LocalPlayer:FindFirstChild('Backpack')
            or own and (own.pending or own.uncertain) or s.equipmentRequest or s.lootRequest or s.bringDelivery
            or calls.drag or calls.cash or ctx.bringEquipmentLock or quest and quest.manual()
            or ctx.questDriving or ctx.questSeating or ctx.humanoid.SeatPart or ctx.humanoid.Sit
            or ctx.questMineEntry or ctx.nativeGateMotion or workspace:GetAttribute('InCutScene') or workspace:GetAttribute('InfiniteRebasing')
            or scene and (scene.CurrentCutScene or scene.AbortingCutScene)
            or s.request or s.awaiting or s.teleporting or s.departureAt or ctx.currentChest or ctx.featureHold or ctx.defenseMoving
            or now()<(ctx.dodgeUntil or 0) or ctx.questPlacement or ctx.questPreviewCancel or ctx.questPotionUsing
            or ctx.questHealAttempt or s.questMedicalDrop or ctx.swingEdit
            or otherCurrent then return true end
        -- Set before native dispatch; a failed constructor or our own version
        -- increment cannot create a reconstruction loop or a server mutation.
        record.attempted=true
        record.accepted=pcall(c.Equip,c,name,proxy,record.serverId)
        record.resultVersion=c.EquipVersion
        return true
    end
    local function emptyRecoveryBudget(record,use)
        local at=now();local times=record.emptyRecoveryTimes
        if type(times)~='table'then
            times={};record.emptyRecoveryTimes=times
            if record.emptyRecoveryUsed then times[1]=finite(record.settledAt) and math.min(at,record.settledAt) or at end
        end
        for _,time in ipairs(times)do if not finite(time) or time>at then return false end end
        while times[1] and at-times[1]>=60 do table.remove(times,1)end
        if #times>=3 then return false end
        if use then times[#times+1]=at end
        return true
    end
    local function selectionRecoveryState(ctx,tool,ownRequest,observeChest)
        local player=api.Players.LocalPlayer
        local c=controller('ToolController');local calls=quest and quest.calls or {}
        local scene=controller('CutSceneController')
        local placement=controller('PlaceablePlacementController')
        local class=attr(tool,'Class')
        -- A completed transport reply is not an equipped-tool receipt. Only an
        -- stable native state with the target absent permits a guarded selection.
        if not ctx.active or not api.owned() or s.farm~=ctx or ctx.character~=player.Character
            or ctx.humanoid.Health<=0 or not tool:IsA('Tool') or tool.Parent~=player:FindFirstChild('Backpack')
            or not c or not finite(c.EquipVersion)
            or c.EquipVersion<0 or c.EquipVersion%1~=0
            or s.equipmentRequest and s.equipmentRequest~=ownRequest or s.lootRequest or s.upgradeRequest or s.bringDelivery
            or calls.drag or calls.cash or calls.drive or calls.shop or calls.place or calls.placementCancel
            or calls.craft or calls.upgrade or calls.medicalDrop or calls.inventoryDrop
            or s.questDelivery or s.questCashJob or ctx.bringEquipmentLock or quest and quest.manual()
            or ctx.questDriving or ctx.questSeating or ctx.humanoid.SeatPart or ctx.humanoid.Sit
            or ctx.questMineEntry or ctx.nativeGateMotion or workspace:GetAttribute('InCutScene')
            or workspace:GetAttribute('InfiniteRebasing') or player.GameplayPaused==true
            or scene and (scene.CurrentCutScene or scene.AbortingCutScene)
            or player:GetAttribute('PlacingCraftedPlaceable')==true or placement and placement.Active
            or s.request or s.awaiting or s.teleporting or s.departureAt
            or ctx.currentChest and not observeChest or ctx.featureHold or ctx.defenseMoving or now()<(ctx.dodgeUntil or 0)
            or ctx.questPlacement or ctx.questPreviewCancel or ctx.questPotionUsing or ctx.questRecovering
            or ctx.questHealAttempt or s.questMedicalDrop or ctx.swingEdit
            or ctx.questHealing and class~='Medkit'
            or ctx.questMining and class~='Pickaxe' and class~='Champions_Hammer' then return nil end
        local other,ownedOther=c.ActiveTool
        if other~=nil or c.ServerEquipId~=nil then
            local proxy=other and other.Tool
            local otherClass=proxy and attr(proxy,'Class')
            if not other or other._Destroyed or not proxy or proxy.Parent~=ctx.character
                or not proxy:IsA('Model') or attr(proxy,'Tool')~=true or c.ServerEquipId==nil
                or proxy:GetAttribute('ServerToolEquipId')~=c.ServerEquipId
                or (otherClass~='Sword' and otherClass~='Pickaxe') or id(proxy)==id(tool)then return nil end
            for _,found in ipairs(tools(ctx))do
                if found~=tool and found:IsA('Tool') and ownedTool(ctx,found) and activeFor(ctx,found)==other then ownedOther=found;break end
            end
            if not ownedOther then return nil end
        end
        local name=id(tool);local qualified=name..tostring(player.UserId)
        for _,piece in ipairs(children(ctx.character))do
            if piece.Parent==ctx.character and piece~=ownedOther and (not other or piece~=other.Tool)
                and (piece:IsA('Tool') or attr(piece,'Tool')==true
                or piece:IsA('Model') and attr(piece,'Tool')==nil and (id(piece)==name or piece.Name==qualified))then return nil end
        end
        return c,c.EquipVersion,other,c.ServerEquipId
    end
    local function equipmentRequirementAllowed(ctx,tool,class)
        if cfg.classQuest and quest and not ctx.questMining and not ctx.questHealing
            and (class=='Sword' or class=='Pickaxe' or class=='Champions_Hammer' or GUNS[class])then
            local required,requiredClass,strict=quest.required(ctx)
            if required and id(tool)~=required or strict and not required and not requiredClass
                or requiredClass=='Gun' and not GUNS[class]
                or requiredClass and requiredClass~='Gun' and class~=requiredClass then return false end
        end
        return true
    end
    local function equipmentSelectionReady()
        local hotbar=controller('HotbarController')
        local ui=hotbar and hotbar.BackpackUI
        local scene=controller('CutSceneController')
        -- The native hotbar refuses new selection while hidden or dragging.
        -- Driver presentation hides it and requests UnequipTool independently
        -- of the physical seat; wait for the actual loaded UI to be ready.
        return ui~=nil and ui.Visible==true and not hotbar.IsDraggingHotbarItem
            and not workspace:GetAttribute('InCutScene')
            and not(scene and (scene.CurrentCutScene or scene.AbortingCutScene))
    end
    local function equip(ctx, tool)
        local record=tool and s.equipRecords[tool]
        if ctx.bringEquipmentLock or not tool or not tool.Parent or not F.canSelectEquipment(ctx,tool)then
            if record then record.emptyRecovery=nil end
            return nil
        end
        local class=attr(tool,'Class')
        if not equipmentRequirementAllowed(ctx,tool,class)then
            if record then record.emptyRecovery=nil end
            return nil
        end
        local active = activeFor(ctx, tool)
        if active then s.equipRecords[tool] = nil; return active end
        if rebindHandler(ctx,tool)then
            if record then record.emptyRecovery=nil end
            active=activeFor(ctx,tool)
            if active then s.equipRecords[tool]=nil;return active end
            return nil
        end
        if tool.Parent == ctx.character then if record then record.emptyRecovery=nil end;return nil end
        if not equipmentSelectionReady()then
            if record then record.emptyRecovery=nil end
            return nil
        end
        -- An accepted request can be superseded by another confirmed tool before
        -- its next observation. Recover every tool family, not just the sack.
        -- EquipTool toggles: never resend while this tool is represented on the character.
        if record and (record.accepted or record.emptyRecoveryUsed)
            and now() >= (record.retryAt or 0) then
            local c = controller('ToolController')
            local other = c and c.ActiveTool
            local serverId=c and c.ServerEquipId
            local current=other and not other._Destroyed and other.Tool and other.Tool.Parent==ctx.character
                and (serverId==nil or other.Tool:GetAttribute('ServerToolEquipId')==serverId)
            local changed=serverId~=nil and record.previousServerEquipId~=nil and serverId~=record.previousServerEquipId
            local represented = false
            for _, piece in ipairs(children(ctx.character)) do
                if id(piece) == id(tool) or piece.Name == id(tool) .. tostring(api.Players.LocalPlayer.UserId) then
                    local equipId=piece:GetAttribute('ServerToolEquipId')
                    -- Only a different confirmed native server equip outcome
                    -- can prove this older character model is no longer current.
                    if not(current and changed and equipId~=nil and equipId~=serverId)then represented=true end
                end
            end
            if not represented and current and other~=record.previousActive and (serverId==nil or changed)then
                record.accepted=nil;record.emptyRecovery=nil;record.emptyRecoveryUsed=nil
            end
        end
        local recovery
        -- Hot replacement can retain a settled pre-44 record without these
        -- diagnostics. Start a new observation now; never credit earlier time.
        if record and record.accepted==true and not record.pending and not record.uncertain
            and not s.equipmentRequest and not finite(record.settledAt)then
            record.settledAt=now();record.emptyRecovery=nil
        end
        if record and record.accepted and not record.pending and not record.uncertain
            and finite(record.settledAt)then
            local c,version,other,serverId=selectionRecoveryState(ctx,tool,nil,true)
            local observation=record.emptyRecovery
            if not c then record.emptyRecovery=nil
            elseif not observation or observation.character~=ctx.character or observation.controller~=c or observation.version~=version or observation.other~=other or observation.serverId~=serverId then
                record.emptyRecovery={character=ctx.character,controller=c,version=version,other=other,serverId=serverId,started=now()}
            elseif not ctx.currentChest and now()-observation.started>=10 and now()>=(record.retryAt or 0) and emptyRecoveryBudget(record,false)then recovery=observation end
        elseif record then record.emptyRecovery=nil end
        if record and (record.pending or record.uncertain or record.accepted and not recovery
            or now() < (record.retryAt or 0)) then return nil end
        record = record or {}; s.equipRecords[tool] = record
        local nativeController=controller('ToolController')
        if not recovery then
            record.previousActive=nativeController and nativeController.ActiveTool
            record.previousServerEquipId=nativeController and nativeController.ServerEquipId
        end
        local acceptedBefore=record.accepted
        record.pending = true; record.notDispatched = nil; record.rejected = nil
        record.issuedAt=now();record.settledAt=nil
        local dispatchGuard=function(token)
            if not equipmentSelectionReady() or not ctx.active or not api.owned() or s.farm~=ctx
                or ctx.character~=api.Players.LocalPlayer.Character or ctx.humanoid.Health<=0
                or ctx.bringEquipmentLock or not F.canSelectEquipment(ctx,tool) or activeFor(ctx,tool)
                or tool.Parent~=api.Players.LocalPlayer:FindFirstChild('Backpack')
                or not equipmentRequirementAllowed(ctx,tool,attr(tool,'Class'))then
                record.emptyRecovery=nil;return false
            end
            if recovery then
                local required=equipmentRequirementAllowed(ctx,tool,attr(tool,'Class'))
                local c,version,other,serverId
                if required then c,version,other,serverId=selectionRecoveryState(ctx,tool,token)end
                if s.equipRecords[tool]~=record or not record.pending or record.uncertain or not emptyRecoveryBudget(record,false)
                    or not required or record.emptyRecovery~=recovery or not c or c~=recovery.controller
                    or ctx.character~=recovery.character or version~=recovery.version or other~=recovery.other or serverId~=recovery.serverId or now()-recovery.started<10 then
                    record.emptyRecovery=nil;return false
                end
                record.emptyRecoveryUsed=true;emptyRecoveryBudget(record,true);record.emptyRecovery=nil
                record.previousActive=c.ActiveTool;record.previousServerEquipId=c.ServerEquipId
                record.issuedAt=now()
                print('[DTEC Equipment] Requested tool absent from stable native equipment for 10 seconds; one recovery selection dispatched')
            end
            return true
        end
        local issued = api.request('equip-weapon', 'ToolService', 'EquipTool', api.pack(tool), function(result)
            record.pending = nil
            record.settledAt=now()
            record.replyType=type(result[2])
            record.replyArity=math.max(0,(result.n or #result)-1)
            if result.notDispatched then
                record.notDispatched=true;record.rejected=nil;record.uncertain=nil
                record.accepted=acceptedBefore;record.emptyRecovery=nil;record.retryAt=now()+3
                return
            end
            record.notDispatched = nil
            record.rejected = result[1] == true and result[2] == false
            record.uncertain = result[1] ~= true
            record.accepted, record.retryAt = api.accepted(result), now() + 3
        end,dispatchGuard)
        if not issued then
            record.pending=nil;record.notDispatched=true
            if recovery then record.accepted=acceptedBefore;record.emptyRecovery=nil;record.settledAt=now() end
        end
    end
    local function wait(ctx, seconds)
        ctx.featurePulse = now()
        ctx.check(); task.wait(seconds or 0.1); ctx.check()
        ctx.featurePulse = now()
        if ctx.pendingThreat and ctx.pendingThreat.expires > now()
            and ctx.featureOperation ~= 'dodge' then
            error('__EARTH_DEFENSE_RETRY', 0)
        end
        if ctx.featureOperation == 'gear' and not cfg.lootExtract
            or (ctx.featureOperation == 'extract' or ctx.featureOperation == 'discovery' or ctx.featureOperation == 'church-search') and not F.extractionReady() then
            error('__EARTH_MODE_CHANGED', 0)
        end
    end
    local function safeToWork(ctx)
        return ctx.active and not s.request and not s.awaiting and not s.teleporting and not s.departureAt
            and not workspace:GetAttribute('InCutScene') and not workspace:GetAttribute('InfiniteRebasing')
            and not ctx.questDriving and not ctx.questSeating
            and not ctx.humanoid.SeatPart and not ctx.humanoid.Sit
    end
    local function acquire(ctx, kind)
        if ctx.currentChest or not safeToWork(ctx) then return false end
        ctx.featureHold, ctx.featureOperation = true, kind
        -- Translation changes require an acknowledgement from the original route.
        local deadline = now() + 1
        while (not ctx.routeParked or ctx.travel) and now() < deadline do wait(ctx, 0.05) end
        if not ctx.routeParked or ctx.travel then ctx.featureHold, ctx.featureOperation = nil, nil; return false end
        return true
    end
    local function release(ctx)
        ctx.featureHold, ctx.featureOperation = nil, nil
    end
    local function move(ctx, target, offset)
        if not safeToWork(ctx) then return false end
        movement.hover(ctx)
        local p = position(target)
        if not p then return false end
        local destination = p + (offset or Vector3.new(0, 3, 5))
        if (destination - ctx.root.Position).Magnitude <= 2 then return target.Parent ~= nil end
        ctx.root.CFrame = CFrame.new(destination)
        if ctx.root.AssemblyLinearVelocity then ctx.root.AssemblyLinearVelocity = Vector3.zero end
        wait(ctx, 0.12)
        return target.Parent ~= nil
    end
    local function readyAction(active)
        if not active or active._Destroyed then return false end
        local ending = math.max(tonumber(active.LastSwing) or 0, tonumber(active.Debounce) or 0, tonumber(active.AttackLockedUntil) or 0)
        return now() >= ending and (type(active.CanUseAction) ~= 'function' or active:CanUseAction())
    end
    local function operation(ctx, service, method, argument, callback)
        ctx.check()
        if not pickupAllowed(ctx,argument) then return false end
        return api.request('loot-action', service, method, api.pack(argument), callback,
            function()return pickupAllowed(ctx,argument)end)
    end
    function F.isChurchSavePrompt(item)
        -- UIController's native FramePrompt handler opens the frame whose name
        -- equals the prompt Name. SaveGear is not a ReturnToLobby prompt.
        return item and item.Parent and descendant(item, workspace) and item:IsA('ProximityPrompt')
            and item.Name == 'SaveGear' and F.chestFallbackAllowed(item) and not F.skipLootArea(item)
            and (tag(item, 'FramePrompt') or ancestry(item, 'church') or ancestry(item, 'altar'))
    end
    local function rememberChurch(ctx, item)
        if workspace:GetAttribute('InfiniteRebasing') then return end
        local point = position(item)
        if not point then return end
        local band = tonumber(workspace:GetAttribute('InfiniteDepthOffsetMeters')) or 0
        local key = string.format('%.1f:%.1f:%.1f:%s', point.X, point.Y, point.Z, tostring(band))
        s.churchMemories = s.churchMemories or {}
        for _, record in ipairs(s.churchMemories) do
            if record.key == key then record.seen = now(); return end
        end
        s.churchMemories[#s.churchMemories + 1] = {key = key, position = point, band = band, seen = now()}
        if #s.churchMemories > 64 then table.remove(s.churchMemories, 1) end
    end
    function F.observeChurch(ctx)
        if not (cfg.lootExtract or cfg.classQuest or s.questChurchExit) or workspace:GetAttribute('InfiniteRebasing')
            or now() < (ctx.churchObserveAt or 0) then return end
        ctx.churchObserveAt = now() + 1
        if ctx.indexPending then
            setmetatable(ctx.indexPending,{__mode='k'})
            for item in pairs(ctx.indexPending)do
                if not item.Parent or not descendant(item,workspace)then ctx.indexPending[item]=nil end
            end
        end
        -- Read-only collection before the timer prevents streaming-out churches
        -- from being forgotten. Movement and SaveGear still require the timer.
        for _, item in ipairs(tagged('FramePrompt')) do
            if F.isChurchSavePrompt(item) then rememberChurch(ctx, item) end
        end
        -- OnboardingFeedbackController uses this exact tag/name for a church.
        for _, item in ipairs(tagged('OnboardingAttachment')) do
            if item.Name == 'Church' and descendant(item, workspace) and not F.skipLootArea(item)
                and F.chestFallbackAllowed(item) then rememberChurch(ctx, item) end
        end
    end
    local function index(ctx)
        F.observeChurch(ctx)
        local retained=ctx.featureIndex and ctx.featureIndex.church
        for i=#(retained or {}),1,-1 do
            local item=retained[i]
            if not item.Parent or not descendant(item,workspace)then table.remove(retained,i)end
        end
        if ctx.featureIndex and not ctx.worldScan and now() < (ctx.indexAt or 0)
            and now() < (ctx.fullIndexAt or 0) and not next(ctx.indexPending or {}) then return ctx.featureIndex end
        local refresh = ctx.worldScan or not ctx.featureIndex or now() >= (ctx.fullIndexAt or 0)
        local data, seen = { church = {} }, {}
        local function classify(item)
            if not item or not item.Parent or not descendant(item,workspace) or not item:IsA('ProximityPrompt') or seen[item] or F.skipLootArea(item) then return end
            local action = (tostring(item.ActionText or '') .. ' ' .. item.Name):lower()
            if F.isChurchSavePrompt(item) or (ancestry(item, 'church') or ancestry(item, 'altar')) and F.chestFallbackAllowed(item)
                and (action:find('lobby', 1, true) or action:find('extract', 1, true) or action:find('return', 1, true)) then
                seen[item] = true; data.church[#data.church + 1] = item
                if cfg.lootExtract or cfg.classQuest or s.questChurchExit then rememberChurch(ctx, item) end
            end
        end
        for _, item in ipairs(ctx.featureIndex and ctx.featureIndex.church or {}) do classify(item) end
        if refresh then
            -- Reuse the chest route's bounded reader. Extraction must not start
            -- a second full-map walk or lose a discovered altar to a partial scan.
            local snapshot=api.worldSnapshot(ctx)
            local scan=ctx.worldScan
            if scan then
                -- The reader's live snapshot can be pruned in place. Consume
                -- its append-only scan list by exact scan identity instead of
                -- revisiting the cumulative snapshot after every small slice.
                local progress=ctx.featureIndexScan
                if not progress or progress.scan~=scan then
                    progress=setmetatable({scan=scan,cursor=1},{__mode='v'});ctx.featureIndexScan=progress
                end
                for i=progress.cursor,#scan.list do classify(scan.list[i])end
                progress.cursor=#scan.list+1;ctx.fullIndexAt=0
            else
                -- One finalized pass also catches old live entries and any
                -- shifts caused by membership pruning during the scan.
                for _,item in ipairs(snapshot)do classify(item)end
                ctx.featureIndexScan=nil;ctx.fullIndexAt=now()+30
            end
        end
        for item in pairs(ctx.indexPending or {}) do classify(item) end
        -- Tags can arrive after DescendantAdded. Query the small native registry
        -- independently of a full workspace refresh.
        for _, item in ipairs(tagged('FramePrompt')) do classify(item) end
        ctx.indexPending = setmetatable({}, {__mode='k'})
        ctx.featureIndex, ctx.indexAt = data, now() + 2
        return data
    end
    local function nearest(ctx, list, predicate, limit)
        local best, distance
        for _, item in ipairs(list) do
            local p = position(item)
            if p and not F.skipLootArea(item) and (not predicate or predicate(item)) then
                local d = (p - ctx.root.Position).Magnitude
                if (not limit or d <= limit) and (not distance or d < distance) then best, distance = item, d end
            end
        end
        return best, distance
    end
    local function worldItems()
        local result = {}
        for _, item in ipairs(children(workspace:FindFirstChild('Items'))) do
            if not F.skipLootArea(item) then result[#result + 1] = item end
        end
        return result
    end
    local function worldSnapshot()
        local result = {}; for _, item in ipairs(worldItems()) do result[item] = true end; return result
    end
    local function newlyDropped(before, ctx, expected)
        return nearest(ctx, worldItems(), function(item)
            return not before[item] and not tag(item, 'ShopItem') and (not expected or id(item) == expected)
        end, 25)
    end
    local function firePrompt(ctx, prompt, dungeon)
        if not prompt or not prompt.Parent or prompt.Enabled == false then return false end
        if not F.chestFallbackAllowed(prompt) then return false end
        local ready = prompt:GetAttribute('DungeonDoorReady')
        if ready == false then return false end
        if dungeon then
            if not safeToWork(ctx)then return false end
            movement.releaseHover(ctx)
            local point=position(prompt);local radius=tonumber(prompt.MaxActivationDistance) or 10
            if not point or radius<=0 then return false end
            if (point-ctx.root.Position).Magnitude>radius then
                -- Approach only actual loaded collidable ground within this
                -- prompt's range. Gate centers/SpawnNode indices are not proof
                -- that an airborne character can complete the native E hold.
                local floor
                if RaycastParams and type(workspace.Raycast)=='function'then
                    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
                    params.FilterDescendantsInstances={ctx.character,workspace:FindFirstChild('Npc'),workspace:FindFirstChild('Items')}
                    local ok,hit=pcall(workspace.Raycast,workspace,point+Vector3.new(0,12,2),Vector3.new(0,-180,0),params)
                    if ok and hit and hit.Instance and hit.Instance.Parent and hit.Instance.CanCollide~=false and hit.Position then
                        local lift=(tonumber(ctx.humanoid.HipHeight) or 2)+(ctx.root.Size and ctx.root.Size.Y*.5 or 1)+.1
                        local destination=hit.Position+Vector3.new(0,lift,0)
                        if (destination-point).Magnitude<=radius then floor=destination end
                    end
                end
                if not floor then
                    ctx.questPromptProblem='native dungeon prompt has no loaded standing approach within its activation range'
                    return false
                end
                ctx.root.CFrame=CFrame.new(floor)
                if ctx.root.AssemblyLinearVelocity then ctx.root.AssemblyLinearVelocity=Vector3.zero end
                wait(ctx,.12)
            end
        elseif not move(ctx, prompt, Vector3.new(0, 0, 2)) then return false end
        local paused = api.Players.LocalPlayer.GameplayPaused
        local point = position(prompt)
        local radius = tonumber(prompt.MaxActivationDistance) or 10
        if paused or not point or (point - ctx.root.Position).Magnitude > radius then
            status('Prompt waiting for loaded content and its actual activation range'); return false
        end
        local original = prompt.HoldDuration
        if dungeon then
            -- Use the real E-hold duration for dungeon doors: changing the local
            -- duration to zero does not change the server's entrance requirement.
            if not finite(original) or original<0 or original>10 then return false end
            ctx.nativeGateMotion=true
            local ok,why=false,'native ProximityPrompt hold input is unavailable'
            if type(prompt.InputHoldBegin)=='function' and type(prompt.InputHoldEnd)=='function'then
                ctx.heldPrompts=ctx.heldPrompts or {};ctx.heldPrompts[prompt]=true
                ok,why=pcall(function()prompt:InputHoldBegin();wait(ctx,original+.15)end)
                if ctx.heldPrompts[prompt]then pcall(function()prompt:InputHoldEnd()end)end
                ctx.heldPrompts[prompt]=nil
            end
            if ok then ctx.questPromptProblem=nil;return true end
            if tostring(why):find('__CHESTFARM_CANCELLED',1,true) or tostring(why):find('__EARTH_',1,true)then error(why,0)end
            -- Some executors deny native hold input. Preserve the real duration
            -- when trying their helper, then require the actual exit receipt.
            local helper=api.env.fireproximityprompt or fireproximityprompt
            if type(helper)=='function'then
                ok,why=pcall(function()helper(prompt);wait(ctx,original+.15)end)
                if not ok and (tostring(why):find('__CHESTFARM_CANCELLED',1,true)
                    or tostring(why):find('__EARTH_',1,true))then error(why,0)end
            end
            ctx.questPromptProblem=not ok and 'ProximityPrompt input failed: '..tostring(why) or nil
            if not ok then status(ctx.questPromptProblem)end
            return ok
        end
        ctx.instantPrompts = ctx.instantPrompts or {}; ctx.instantPrompts[prompt] = original
        prompt.HoldDuration = 0
        local fire = api.env.fireproximityprompt or fireproximityprompt
        local ok, why
        if type(fire) == 'function' then ok, why = pcall(fire, prompt)
        else
            ctx.heldPrompts = ctx.heldPrompts or {}; ctx.heldPrompts[prompt] = true
            ok, why = pcall(function() prompt:InputHoldBegin(); wait(ctx, 0.03) end)
            pcall(function() prompt:InputHoldEnd() end)
            ctx.heldPrompts[prompt] = nil
        end
        pcall(function() if prompt.Parent then prompt.HoldDuration = original end end)
        ctx.instantPrompts[prompt] = nil
        if not ok and (tostring(why):find('__CHESTFARM_CANCELLED', 1, true)
            or tostring(why):find('__EARTH_', 1, true)) then error(why, 0) end
        if not ok then
            if dungeon then ctx.questPromptProblem='ProximityPrompt action failed: '..tostring(why)end
            status('Prompt action failed: ' .. tostring(why))
        elseif dungeon then ctx.questPromptProblem=nil end
        return ok
    end
    function F.prompt(ctx, prompt) return firePrompt(ctx, prompt) end
    local function armorSlot(item)
        local slot = attr(item, 'ArmorType')
        if slot == 'Helmet' then slot = 'Head' elseif slot == 'Chestplate' then slot = 'Chest' elseif slot == 'Pants' then slot = 'Legs' end
        if slot == 'Head' or slot == 'Chest' or slot == 'Legs' or slot == 'Boots' then return slot end
    end
    local function armorState(ctx)
        local state = {}
        for _, slot in ipairs({'Head', 'Chest', 'Legs', 'Boots'}) do
            state[slot] = {armor = tonumber(ctx.character:GetAttribute(slot)) or 0, speed = 0, rarity = 0, names = {}}
        end
        for _, equipped in ipairs(children(ctx.character)) do
            local name = equipped:GetAttribute('ArmorName')
            local current = state[armorSlot(equipped)]
            if current and name and equipped:GetAttribute('AdminArmorLabPreview') ~= true then
                current.names[name] = true
                local ok, baseArmor, baseSpeed = pcall(function()
                    return s.itemDatabase.GetAttribute(name, 'Armor'), s.itemDatabase.GetAttribute(name, 'SpeedBoost')
                end)
                current.armor = math.max(current.armor, tonumber(equipped:GetAttribute('Armor')) or 0, ok and tonumber(baseArmor) or 0)
                current.speed = math.max(current.speed, tonumber(equipped:GetAttribute('SpeedBoost')) or 0, ok and tonumber(baseSpeed) or 0)
                local ranked, value = pcall(function() return s.itemDatabase.GetAttribute(name, 'Rarity') end)
                current.rarity = math.max(current.rarity, rarityRank(equipped), ranked and (rarity[value] or 0) or 0)
            end
        end
        return state
    end
    local function armorBetter(ctx, item, state)
        local slot = armorSlot(item); if not slot then return false end
        local current = (state or armorState(ctx))[slot]
        if current.names[id(item)] then return false end
        local rank = rarityRank(item)
        if rank > 0 and current.rarity > 0 and rank ~= current.rarity then return rank > current.rarity end
        local armor = tonumber(attr(item, 'Armor')) or 0
        local speed = tonumber(attr(item, 'SpeedBoost')) or 0
        return armor > current.armor or armor == current.armor and slot == 'Boots' and speed > current.speed
    end
    local function weaponBetter(ctx, item, owned)
        local class = attr(item, 'Class')
        if GUNS[class] then
            if rarityRank(item) < rarity.Mythic then return false end
        elseif class ~= 'Sword' and class ~= 'Pickaxe' and class ~= 'ItemBag' then return false end
        local current
        if owned then current = owned[class] else current = findTool(ctx, class, nil, true) end
        if not current then return true end
        if id(current) == id(item) then return false end
        local rank, existingRank = rarityRank(item), rarityRank(current)
        if rank > 0 and existingRank > 0 and rank ~= existingRank then return rank > existingRank end
        local value = class == 'ItemBag' and (tonumber(attr(item, 'MaxSize')) or 0) or weaponValue(item)
        local existing = class == 'ItemBag' and (tonumber(attr(current, 'MaxSize')) or 0) or weaponValue(current)
        return value > existing or value == existing and rank > existingRank
    end
    local function interact(ctx, item, callback)
        if not F.freeWorldItemAllowed(item) then return false end
        if not move(ctx, item) then return false end
        return operation(ctx, 'InteractionService', 'Interact', item, callback)
    end
    local function gearReceipt(ctx, pending)
        if pending.relic and inventoryCount(ctx, pending.id) > pending.beforeCount then return true end
        for _, tool in ipairs(tools(ctx)) do
            if id(tool) == pending.id and not pending.inventory[tool] then return true end
        end
        if pending.slot then
            for _, piece in ipairs(children(ctx.character)) do
                if piece:GetAttribute('ArmorName') == pending.id and not pending.inventory[piece] then return true end
            end
        end
        return false
    end
    local function finishGearReceipt(ctx, pending)
        if ctx.gearPickup ~= pending or not gearReceipt(ctx, pending) then return false end
        if bring then bring.forget(pending.item) end
        ctx.gearPickup = nil; ctx.itemRetry[pending.item] = math.huge
        s.stats.smartPickups = (s.stats.smartPickups or 0) + 1
        s.smartLootStatus = 'Confirmed ' .. pending.id
        status('Gear pickup confirmed: ' .. pending.id)
        local window = ctx.smartLootWindow
        if window and not pending.brought then window.untilAt = math.min(window.expires, math.max(window.arrivalUntil or window.untilAt, now() + 0.35)) end
        return true
    end
    local function settleGear(ctx)
        local pending = ctx.gearPickup
        if not pending then return true end
        if finishGearReceipt(ctx, pending) then return true end
        if not pending.settled or now() - pending.started < 5
            or now() - (pending.settledAt or pending.started) < 1.5 then
            s.smartLootStatus = 'Awaiting inventory receipt: ' .. pending.id
            return false
        end
        ctx.itemRetry[pending.item] = now() + 300; ctx.gearPickup = nil
        s.smartLootStatus = 'No pickup receipt: ' .. pending.id
        status('No gear receipt for ' .. pending.id .. '; skipping that item for 5 minutes')
        return true
    end
    local function ownedSnapshot(ctx, inventory)
        local owned = {}
        for _, class in ipairs({'Sword', 'Pickaxe', 'ItemBag', 'Revolver', 'Rifle', 'Shotgun', 'BlackholeGun'}) do
            owned[class] = findTool(ctx, class, inventory, true)
        end
        return owned
    end
    local function lootScore(item)
        -- Protect all other relics. Only RareShard yields its slot to Mythic+
        -- gear (including Phoenix) or a higher-priority relic.
        local tier = isRelic(item) and id(item) ~= 'RareShard' and 4
            or rarityRank(item) >= rarity.Mythic and 3 or id(item) == 'RareShard' and 2 or 1
        local value = armorSlot(item) and (tonumber(attr(item, 'Armor')) or 0)
            or attr(item, 'Class') == 'ItemBag' and (tonumber(attr(item, 'MaxSize')) or 0) or weaponValue(item)
        return tier * 1000000000 + rarityRank(item) * 1000000 + math.min(value, 999999)
    end
    local function reloadPolicy(item)
        if id(item) == 'VoidCrystal' or rarityRank(item) == rarity.Secret then return 5, 15 end
        if isRelic(item) and id(item) ~= 'RareShard' or rarityRank(item) >= rarity.Mythic then return 4, 15 end
        if id(item) == 'RareShard' then return 1, 30 end
        return 2, 30
    end
    local function rareShardTool(ctx, inventory)
        for _, tool in ipairs(inventory or tools(ctx)) do
            if id(tool) == 'RareShard' and tool:IsA('Tool') and tool.Parent
                and (descendant(tool, ctx.character) or descendant(tool, api.Players.LocalPlayer:FindFirstChild('Backpack')))
                and not (s.rareDropBlocked and s.rareDropBlocked[tool]) then return tool end
        end
    end
    local function canReplaceRare(ctx, item, inventory)
        return not armorSlot(item) and (isRelic(item) and id(item) ~= 'RareShard' or rarityRank(item) >= rarity.Mythic)
            and api.remote and api.remote('ToolService', 'DropSpecificItem') ~= nil
            and rareShardTool(ctx, inventory) ~= nil
    end
    local function settleRareDrop(ctx)
        local record = s.rareShardDrop
        if not record then return true end
        -- The exact tool instance and reply survive cancellation/re-execution.
        -- An unreturned RPC never authorizes a second drop or an altar save.
        if not record.settled then return false end
        local tool = record.tool
        local remains = tool.Parent and (descendant(tool, record.character) or descendant(tool, record.backpack))
        if not remains or stackCount(tool) < record.count then
            s.rareShardDrop = nil
            s.smartLootStatus = 'Rare Shard drop confirmed; rechecking toolbar space'
            return true
        end
        if now() - record.started < 5 or now() - record.settledAt < 1.5 then return false end
        s.rareDropBlocked = s.rareDropBlocked or setmetatable({}, {__mode = 'k'})
        s.rareDropBlocked[tool] = true
        s.rareShardDrop = nil
        s.smartLootStatus = 'Rare Shard drop unconfirmed; no duplicate drop'
        return true
    end
    local function makeRoom(ctx, item)
        if not settleRareDrop(ctx) then return false end
        local inventory = tools(ctx)
        if armorSlot(item) or hasRoom(ctx, item, inventory) then return true end
        if not cfg.lootExtract or not safeToWork(ctx) or s.lootRequest or s.equipmentRequest
            or not canReplaceRare(ctx, item, inventory) then return false end
        local tool = rareShardTool(ctx, inventory)
        local record = {tool = tool, count = stackCount(tool), started = now(), character = ctx.character,
            backpack = api.Players.LocalPlayer:FindFirstChild('Backpack')}
        local rf = api.remote('ToolService', 'DropSpecificItem')
        s.rareShardDrop = record
        s.smartLootStatus = 'Making room for ' .. id(item) .. ': dropping Rare Shards'
        task.spawn(function()
            -- This coroutine may run after OFF, a manual action, inventory
            -- changes or an improved owned weapon. A skipped drop is proven
            -- unsent and must neither consume a shard nor quarantine its stack.
            local inventory=tools(ctx)
            if s.rareShardDrop~=record or not pickupAllowed(ctx,item,true)
                or hasRoom(ctx,item,inventory) or not canReplaceRare(ctx,item,inventory)
                or rareShardTool(ctx,inventory)~=tool or stackCount(tool)~=record.count then
                record.notSent,record.settled,record.settledAt=true,true,now()
                if s.rareShardDrop==record then s.rareShardDrop=nil end
                return
            end
            -- Native hotbar action: exactly one Tool argument. No guessed stack
            -- count or DropAll argument; repeat only after a real count decrease.
            record.result = api.pack(pcall(function() return rf:InvokeServer(tool) end))
            record.settled, record.settledAt = true, now()
        end)
        return false
    end
    local function usefulSnapshot(ctx, allowReplacement)
        local armor, inventory = armorState(ctx), tools(ctx)
        local owned = ownedSnapshot(ctx, inventory)
        local function useful(item)
            return isRelic(item) or armorSlot(item) and armorBetter(ctx, item, armor) or weaponBetter(ctx, item, owned)
        end
        return function(item)
            local room = hasRoom(ctx, item, inventory) or allowReplacement and canReplaceRare(ctx, item, inventory)
            return isRelic(item) and room
                or armorSlot(item) and armorBetter(ctx, item, armor)
                or weaponBetter(ctx, item, owned) and room
        end, useful
    end
    pickupAllowed=function(ctx,item,needsRoom)
        local player=api.Players.LocalPlayer
        local drag=controller('DragController')
        local current=cfg.lootExtract and api.owned() and s.farm==ctx and ctx.character==player.Character
            and ctx.humanoid.Health>0 and safeToWork(ctx)
            and not(drag and drag.LockedTarget~=nil) and player:GetAttribute('PlacingCraftedPlaceable')~=true
            and F.freeWorldItemAllowed(item)
        if not current then return false end
        local eligible,useful=usefulSnapshot(ctx,false)
        return (needsRoom and useful or eligible)(item)
    end
    local function pickupRecord(ctx, target)
        local record = {item = target, id = id(target), slot = armorSlot(target), inventory = {}, started = now(),
            relic = isRelic(target), beforeCount = inventoryCount(ctx, id(target))}
        for _, item in ipairs(tools(ctx)) do record.inventory[item] = true end
        for _, item in ipairs(children(ctx.character)) do record.inventory[item] = true end
        return record
    end
    bring = buildBring({state = s, now = now, controller = controller, remote = api.remote, Players = api.Players,
        owned = api.owned, enabled = function() return cfg.lootExtract and not s.questDelivery end, safe = safeToWork,
        free = F.freeWorldItemAllowed, skip = F.skipLootArea, part = part, tag = tag,
        items = function() return children(workspace:FindFirstChild('Items')) end, id = id,
        snapshot = function(ctx) return usefulSnapshot(ctx, true) end,
        eligible = function(ctx, item) return usefulSnapshot(ctx, true)(item) end,
        rememberSnapshot = function(ctx) local _, useful = usefulSnapshot(ctx, true); return useful end,
        requestReload = movement.requestItemReload, pollReload = movement.pollItemReload,
        reloadTick = movement.stepItemReload,
        cancelReload = movement.cancelItemReload,
        reloadEnabled = function(ctx)
            return not F.extractionReady() and not ctx.questOwns and not ctx.streamWaiting and api.Players.LocalPlayer.GameplayPaused ~= true
        end,
        reloadPolicy = reloadPolicy,
        score = lootScore, makeRoom = makeRoom, settleRoom = settleRareDrop,
        roomPending = function() return s.rareShardDrop ~= nil end,
        receipt = pickupRecord, received = gearReceipt, confirm = finishGearReceipt, accepted = api.accepted,
        interact = function(ctx, item, callback) return operation(ctx, 'InteractionService', 'Interact', item, callback) end})
    local auraModule
    local questApi
    questApi = {state=s, now=now, controller=controller, remote=api.remote, event=api.event, RS=api.RS, RunService=api.RunService,
        passives=function()
            local resolver=auraModule and auraModule('ClassResolver')
            if resolver and type(resolver.ResolvePlayerPassives)=='function'then
                local ok,value=pcall(resolver.ResolvePlayerPassives,api.Players.LocalPlayer,workspace)
                if ok and type(value)=='table'then return value end
            end
        end,
        Players=api.Players, owned=api.owned, observeClass=api.observeClass or function(data)s.classData=data;s.classObservedAt=now()end,
        free=F.freeWorldItemAllowed, relic=isRelic, part=part, position=position, tag=tag, tagged=tagged, id=id, attr=attr,
        -- A full toolbar can block picking up an upgrade without making that
        -- upgrade disposable gold. Sale protection tests value, not free slots.
        useful=function(ctx,item)local _,useful=usefulSnapshot(ctx,true);return useful(item) end,
        snapshot=function(ctx)local _,useful=usefulSnapshot(ctx,true);return useful end,
        sharedModule=function(name)
            s.questNativeModules=s.questNativeModules or {}
            if s.questNativeModules[name]then return s.questNativeModules[name]end
            local shared=api.RS and api.RS:FindFirstChild('Shared')
            local module=shared and shared:FindFirstChild(name)
            if module then local ok,value=pcall(require,module);if ok then s.questNativeModules[name]=value;return value end end
        end,
        findTool=findTool, canSelectEquipment=F.canSelectEquipment, hasRoom=hasRoom, ownedTools=tools, enemies=F.enemies, enemyAlive=F.enemyAlive, questTargetAllowed=F.questTargetAllowed,
        swordTargetAllowed=F.swordTargetAllowed, weaponClass=function(ctx,target)return F.weaponClass(ctx,target)end,
        attack=function(ctx,active)return F.swing(ctx,active)end,
        isFuelLeech=F.isFuelLeech, persist=persist, hover=movement.hover,
        miningBounds=function(node)
            local cf,size
            local model=node:IsA('Model')
            if model then cf,size=node:GetBoundingBox()
            else local p=part(node);if p then cf,size=p.CFrame,p.Size end end
            if not cf or not size then return end
            if cf.RightVector and cf.UpVector and cf.LookVector then
                local r,u,l=cf.RightVector,cf.UpVector,cf.LookVector
                size=Vector3.new(math.abs(r.X)*size.X+math.abs(u.X)*size.Y+math.abs(l.X)*size.Z,
                    model and size.Y or math.abs(r.Y)*size.X+math.abs(u.Y)*size.Y+math.abs(l.Y)*size.Z,
                    math.abs(r.Z)*size.X+math.abs(u.Z)*size.Y+math.abs(l.Z)*size.Z)
            end
            return cf.Position,size
        end,
        miningNodeAllowed=function(node)return not F.skipLootArea(node) and F.liveOre(node)end,
        chestCandidate=function(ctx,radius,predicate)
            if ctx.questChestCandidate then return ctx.questChestCandidate(radius,predicate)end
        end,
        chestAllowed=F.chestFallbackAllowed,
        collectMineLoot=function(ctx)return F.upgradeGear(ctx)end,
        openChest=function(ctx,entry)return ctx.helpers[16361397](entry)end,
        healingChestSafe=F.healingChestSafe,healingPointSafe=F.healingPointSafe,
        medicalLocationAllowed=function(ctx,item)return F.medicalLocationAllowed(ctx,item)end,
        medicalSearch=function(ctx,search)return F.medicalSearch(ctx,search)end,
        clearMedicalSearch=function(ctx,search)return F.clearMedicalSearch(ctx,search)end,
        miningSurface=function(ctx,node)
            local best,distance
            local parts=node:GetDescendants();if node:IsA('BasePart')then parts[#parts+1]=node end
            for _,p in ipairs(parts)do
                if p:IsA('BasePart') and p.CanQuery~=false and (tonumber(p.Transparency) or 0)<1
                    and (tonumber(p.LocalTransparencyModifier) or 0)<1 then
                    local d=(p.Position-ctx.root.Position).Magnitude
                    if not distance or d<distance then best,distance=p,d end
                end
            end
            return best
        end,
        miningHitReady=function(ctx,active,node)
            local bounds=auraModule('MeleeSwingBounds')
            if not bounds or type(bounds.GetSwingCFrame)~='function' then return false,'native swing bounds unavailable' end
            local range=tonumber(active.Range)
            if not range or range<=0 or range~=range or range==math.huge then return false,'invalid pickaxe range' end
            local ok,hit=pcall(function()
                local pivot=ctx.character:GetPivot()
                local top
                if node:IsA('Model')then local cf,sz=node:GetBoundingBox();top=cf.Position.Y+sz.Y*.5
                elseif type(bounds.GetPartTopY)=='function'then top=bounds.GetPartTopY(node)
                else local center,sz=questApi.miningBounds(node);top=center and center.Y+sz.Y*.5 end
                if not top or top<pivot.Position.Y-2 then return false end
                local box=bounds.GetSwingCFrame(pivot,-math.min(range,30000)/4)
                local params=OverlapParams.new()
                params.FilterType=Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances={ctx.character}
                for _,p in ipairs(workspace:GetPartBoundsInBox(box,Vector3.new(range,range,range),params))do
                    while p and p~=workspace do
                        if tag(p,'Ore')then
                            if p==node then return F.liveOre(node) end
                            break
                        end
                        p=p.Parent
                    end
                end
                return false
            end)
            if not ok then return false,'native ore overlap unavailable' end
            return hit,not hit and 'target ore outside native swing box' or nil
        end,
        cancelTravel=movement.cancel, extractionReady=F.extractionReady,
        equip=equip,readyAction=readyAction,stackCount=stackCount,
        consume=function(ctx,active)return F.medicalConsume(ctx,active)end,
        findOwned=function(ctx,wanted)for _,tool in ipairs(tools(ctx))do if ownedTool(ctx,tool) and id(tool)==wanted then return tool end end end,
        watch=function(ctx)return F.watcher(ctx)end,
        watcherReady=function(ctx)return F.watcherVisible(ctx)end,
        retreat=function(ctx)return F.questRetreat(ctx)end,
        mine=function(ctx,active)
            local c=controller('ToolController')
            if not c or c.ActiveTool~=active or active._Destroyed then return false,'equipped pickaxe handler changed' end
            if not safeToWork(ctx)then return false,'seat or transition still active' end
            if type(active.Swing)~='function'then return false,'native pickaxe Swing handler missing' end
            local ending=math.max(tonumber(active.LastSwing) or 0,tonumber(active.Debounce) or 0,tonumber(active.AttackLockedUntil) or 0)
            if now()<ending then return false,string.format('pickaxe cooldown %.1fs',ending-now())end
            if type(active.CanUseAction)=='function'then
                local ok,ready=pcall(active.CanUseAction,active)
                if not ok or not ready then return false,active.CooldownOwner==nil and 'native cooldown owner not ready' or 'shared weapon cooldown' end
            end
            local ok,why=F.miningSwing(ctx,active)
            if not ok then return false,'native Swing failed: '..tostring(why):gsub('[%c]',' '):sub(1,100) end
            return true
        end,
        miningDoorAllowed=function(prompt)return F.chestFallbackAllowed(prompt) and not F.skipLootArea(prompt)end,
        fireMiningPrompt=function(ctx,prompt)return firePrompt(ctx,prompt,true)end,
        enforceClassWeapon=function(ctx,wanted,tool)
            if ctx.questMining or ctx.questHealing or ctx.questStartup or ctx.questRecovering
                or ctx.questPotionUsing or ctx.bringEquipmentLock then return end
            local c=controller('ToolController');local active=c and c.ActiveTool
            if not active or active._Destroyed or not active.Tool or active.Tool.Parent~=ctx.character then ctx.questWrongWeapon=nil;return end
            local inventory
            for _,candidate in ipairs(tools(ctx))do
                if id(candidate)=='Sword_Void' and (active.Tool==candidate or active.DisplayTool==candidate
                    or active.Tool.Name=='Sword_Void'..tostring(api.Players.LocalPlayer.UserId))then inventory=candidate;break end
            end
            if not inventory or wanted=='Sword_Void' then ctx.questWrongWeapon=nil;return end
            if tool then equip(ctx,tool);return end
            local record=ctx.questWrongWeapon
            if record and record.active==active then return end -- Native equip toggles; unknown replies are not resent.
            record={active=active};ctx.questWrongWeapon=record
            local issued=api.request('equip-weapon','ToolService','EquipTool',api.pack(inventory),function(result)
                record.accepted=api.accepted(result)
            end)
            if not issued then ctx.questWrongWeapon=nil end
        end,
        releaseHover=movement.releaseHover}
    quest=buildQuest(questApi)
    F.quest=quest
    function F.questPreferred(ctx) return quest.preferred(ctx) end
    function F.questQuickReturn(ctx)return ctx and quest.special.quickReturn(ctx)end
    function F.questLobby() return quest.lobby() end
    function F.questKeepsRun() return cfg.classQuest and not s.questStalled and not s.questIdle and s.questPlan
        and quest.activePlan(s.questPlan) end
    function F.questPreventsExit() return s.questChurchExit ~= nil or cfg.classQuest end
    local function upgradeGear(ctx)
        if not cfg.lootExtract then return false end
        F.smartLootPending(ctx)
        if not settleGear(ctx) then return false end
        if s.lootRequest then return false end
        if bring.available() then return bring.step(ctx, not F.extractionReady() and not ctx.questRecoveryDue and not ctx.questRecovering) end
        if ctx.questRecoveryDue or ctx.questRecovering then return false end
        -- Snapshot only for this non-yielding candidate pass. Inventory receipts
        -- and packing still read live state after every asynchronous action.
        local armor = armorState(ctx)
        local inventory = tools(ctx)
        local owned = ownedSnapshot(ctx, inventory)
        local items = worldItems()
        local target, score
        for _, item in ipairs(items) do
            local p = position(item)
            if p and (p - ctx.root.Position).Magnitude <= 180 and F.freeWorldItemAllowed(item)
                and now() >= (ctx.itemRetry[item] or 0)
                and (isRelic(item) and hasRoom(ctx, item, inventory) or armorBetter(ctx, item, armor)
                    or weaponBetter(ctx, item, owned) and hasRoom(ctx, item, inventory)) then
                local value = lootScore(item)
                if not target or value > score then target, score = item, value end
            end
        end
        if not target then
            if not ctx.smartLootWindow then
                local nearby = nearest(ctx, items, nil, 180)
                local blocked = nearest(ctx, items, function(item)
                    return F.freeWorldItemAllowed(item) and (isRelic(item) or weaponBetter(ctx, item, owned))
                        and not hasRoom(ctx, item, inventory)
                end, 180)
                s.smartLootStatus = blocked and 'Toolbar full; useful loot skipped'
                    or nearby and 'No eligible upgrades nearby' or 'No loose gear nearby'
            end
            return false
        end
        if not acquire(ctx, 'gear') then s.smartLootStatus = 'Waiting for chest movement to yield'; return false end
        -- Acquisition can yield. Recheck live equipment/capacity before dispatch;
        -- the candidate-pass snapshot must never authorize an outdated downgrade.
        if not F.freeWorldItemAllowed(target) or not (isRelic(target) and hasRoom(ctx, target)
            or armorSlot(target) and armorBetter(ctx, target) or weaponBetter(ctx, target) and hasRoom(ctx, target)) then
            release(ctx); return false
        end
        status((isRelic(target) and 'Collecting a relic: ' or 'Equipping a useful upgrade: ') .. id(target))
        s.smartLootStatus = 'Picking up ' .. id(target)
        if not move(ctx, target) then release(ctx); return false end
        local record = { item = target, id = id(target), slot = armorSlot(target), inventory = {}, started = now(),
            relic = isRelic(target), beforeCount = inventoryCount(ctx, id(target)) }
        for _, item in ipairs(tools(ctx)) do record.inventory[item] = true end
        for _, item in ipairs(children(ctx.character)) do record.inventory[item] = true end
        ctx.gearPickup = record; ctx.itemRetry[target] = now() + 300
        -- Keep the initial replication grace and an in-flight receipt hold.
        -- A successful pickup needs only a short quiet tail, not another fixed two seconds.
        local issued = operation(ctx, 'InteractionService', 'Interact', target, function(result)
            record.settled, record.settledAt = true, now()
            if not api.accepted(result) then
                ctx.itemRetry[target] = now() + 300
                if ctx.gearPickup == record then ctx.gearPickup = nil end
                s.smartLootStatus = 'Pickup rejected: ' .. record.id
                status('Gear interaction rejected: ' .. record.id .. '; continuing the farm')
            end
        end)
        if not issued then ctx.gearPickup = nil; ctx.itemRetry[target] = now() + 5 end
        -- Keep the replicated character near the item while its one native
        -- request and inventory update settle. An uncertain reply cannot stall
        -- the chest route indefinitely, and only a real receipt counts as loot.
        local deadline = now() + 1.5
        while issued and ctx.gearPickup == record and now() < deadline and not gearReceipt(ctx, record) do wait(ctx, 0.05) end
        if issued then finishGearReceipt(ctx, record) end
        release(ctx); return issued
    end
    local function sendTool(ctx, active, payload, originalFire)
        local c = controller('ToolController')
        if not ctx.active or not api.owned() or not safeToWork(ctx) or not c or c.ActiveTool ~= active or active._Destroyed
            or not active.Tool or active.Tool.Parent~=ctx.character then return false end
        local signal = active.Execute
        local count; pcall(function() count = #signal:GetConnections() end)
        if count == 0 then
            local ok, service = pcall(function() return s.knit.GetService('ToolService') end)
            if ok and service and service.Update and type(service.Update.Fire) == 'function' and c.ActiveTool == active then
                service.Update:Fire(payload); return true,'ToolService.Update (listener fallback)'
            end
        elseif signal and type(originalFire or signal.Fire) == 'function' then
            (originalFire or signal.Fire)(signal,payload);return true,'CustomTool.Execute'
        end
        return false
    end
    local function bag(ctx)
        local tool = findTool(ctx, 'ItemBag'); if not tool then return nil end
        local active = equip(ctx, tool)
        -- EquipTool is asynchronous. Keep the route/combat hold until its native
        -- handler arrives, rather than releasing it on every feature-worker pass.
        local deadline = now() + 4
        while not active and now() < deadline do
            status('Church packing: waiting for the sack to equip')
            wait(ctx, 0.05); active = activeFor(ctx, tool)
        end
        if active then
            s.equipRecords[tool] = nil
            s.sackCapacity = tonumber(active.MaxSize)
            s.sackSize = ctx.bagConfirmed == active and tonumber(active.Size) or nil
            if not ctx.bagObserver or ctx.bagObserver.active ~= active then
                if ctx.bagObserver and ctx.bagObserver.controller.UpdateSackSize == ctx.bagObserver.wrapper then
                    ctx.bagObserver.controller.UpdateSackSize = ctx.bagObserver.original
                end
                local c = controller('ToolController')
                local original = c and c.UpdateSackSize
                if c and type(active.UpdateSackSize) == 'function' and (original == nil or type(original) == 'function') then
                    -- Native ToolService.Update dispatches controller methods first,
                    -- then ActiveTool methods. Observe that server dispatch only:
                    -- local capacity refreshes also call active:UpdateSackSize(0).
                    local wrapper = function(self, quantity, ...)
                        local current = self.ActiveTool
                        local result
                        if original then result = original(self, quantity, ...)
                        elseif current and type(current.UpdateSackSize) == 'function' then result = current:UpdateSackSize(quantity, ...) end
                        if current == active and not active._Destroyed and active.Tool and active.Tool.Parent == ctx.character
                            and type(quantity) == 'number' and quantity >= 0 and quantity < math.huge and quantity == math.floor(quantity) then
                            ctx.bagConfirmed = active; s.sackSize, s.sackCapacity = quantity, active.MaxSize
                        end
                        return result
                    end
                    ctx.bagObserver = { active = active, controller = c, original = original, wrapper = wrapper }
                    c.UpdateSackSize = wrapper
                end
            end
            local observer = ctx.bagObserver
            if observer and observer.active == active and ctx.bagConfirmed ~= active
                and now() >= (observer.queryAt or 0) then
                observer.queryAt = now() + 2
                -- Read-only native request, safe to retry after a lost response.
                -- Match ToolController's forwarding when Execute has no listener.
                local sent = sendTool(ctx, active, { 'GetStoredItems' })
                status(sent and 'Church packing: waiting for the sack quantity response'
                    or 'Church packing: waiting for the native sack request listener')
                deadline = now() + 2
                while sent and ctx.bagConfirmed ~= active and activeFor(ctx, tool) == active and now() < deadline do wait(ctx, 0.05) end
            end
        end
        return active, tool
    end
    local function store(ctx, active, item)
        if not item or not item.Parent or not readyAction(active) or (active.Size or 0) >= (active.MaxSize or 0) then return false end
        if tag(item, 'ShopItem') or item.Name == 'Money_Sack' or item.Name == 'SoulOrb' then return false end
        -- The native Interact falls through to Drop when the target cannot be bagged.
        -- Verify its eligibility first so a failed pickup cannot unload another item.
        if not descendant(item, workspace:FindFirstChild('Items')) or item:GetAttribute('CraftedPlaceable') == true then return false end
        if not move(ctx, item, Vector3.new(0, 2, 3)) then return false end
        local drag = controller('DragController'); if not drag or type(active.Interact) ~= 'function' then return false end
        local oldTarget, oldLock = drag.Target, drag.LockedTarget
        if oldLock and oldLock ~= item then return false end
        local before = active.Size or 0
        drag.Target, drag.LockedTarget = item, nil
        local ok, why = pcall(active.Interact, active)
        if drag.Target == item then drag.Target = oldTarget end
        if drag.LockedTarget == nil then drag.LockedTarget = oldLock end
        if not ok then error(why, 0) end
        wait(ctx, 0.3)
        if (active.Size or 0) > before or not item.Parent then
            s.sackSize, s.sackCapacity = active.Size, active.MaxSize
            return true
        end
        return false
    end
    local function dropSackItem(ctx, active)
        if ctx.sackDrop then
            local item = ctx.sackDrop.item or newlyDropped(ctx.sackDrop.snapshot, ctx)
            if item then ctx.sackDrop.item = item; return item end
            status('Waiting for the previous sack drop; no duplicate drop is sent')
            return nil
        end
        if ctx.bagConfirmed ~= active or not readyAction(active) then
            status('Waiting for a native sack quantity update before unloading'); return nil
        end
        ctx.sackDrop = { snapshot = worldSnapshot(), at = now() }
        if not sendTool(ctx, active, { 'Drop' }) then
            ctx.sackDrop = nil; status('Church packing: waiting for the native sack drop listener'); return nil
        end
        wait(ctx, 0.35)
        ctx.sackDrop.item = newlyDropped(ctx.sackDrop.snapshot, ctx)
        return ctx.sackDrop.item
    end
    local function npcHealth(npc)
        if F.isFuelLeech(npc)then return tonumber(npc:GetAttribute('FuelLeechHealth')) or 0 end
        local h = npc:FindFirstChildOfClass('Humanoid')
        return h and h.Health or tonumber(npc:GetAttribute('FuelLeechHealth')) or 0
    end
    auraModule=function(name)
        s.auraModules, s.auraModuleRetry = s.auraModules or {}, s.auraModuleRetry or {}
        if s.auraModules[name] then return s.auraModules[name] end
        if now() < (s.auraModuleRetry[name] or 0) then return nil end
        local shared = api.RS:FindFirstChild('Shared')
        local object = shared and shared:FindFirstChild(name)
        s.auraModuleRetry[name] = now() + 2
        if not object then return nil end
        local ok, value = pcall(require, object)
        if ok and type(value) == 'table' then s.auraModules[name] = value; return value end
    end
    local function auraHealth(target)
        if not target or not target.Parent or not descendant(target, workspace) then return nil end
        if F.isFuelLeech(target)then return tonumber(target:GetAttribute('FuelLeechHealth'))end
        local h = target:FindFirstChildOfClass('Humanoid')
        if h then return h.Health end
        local value = target:FindFirstChild('Health')
        if value and (value:IsA('NumberValue') or value:IsA('IntValue')) then return value.Value end
        return tonumber(target:GetAttribute('FuelLeechHealth')) or tonumber(target:GetAttribute('Health'))
    end
    local function auraClass(active)
        local tool = active.DisplayTool or active.Tool
        local name = id(tool)
        local class = attr(tool, 'Class') or attr(active.Tool, 'Class')
        if name == 'Sword_Executioner' then class = 'Sword' end
        if name == 'Champions_Hammer' then class = 'Pickaxe' end
        return class, name == 'Champions_Hammer'
    end
    function F.weaponRange(active, tool)
        local range = active and active.Range
        if finite(range) and range > 0 then return range end
        tool = tool or active and (active.DisplayTool or active.Tool)
        if not tool then return 0 end
        local raw = tonumber(attr(tool, 'Range'))
        local bounds = auraModule('MeleeSwingBounds')
        if bounds and type(bounds.GetWeaponRange) == 'function' then
            local ok, value = pcall(bounds.GetWeaponRange, raw)
            if ok and finite(value) and value > 0 then return value end
        end
        return finite(raw) and raw > 0 and raw or 0
    end
    suspendedMeleeDefense=function(ctx,npc)
        local drill=quest and quest.drillSupport
        if not drill or not drill.returnSuspended or not drill.returnSuspended(ctx,npc)then return false end
        local native=controller('ToolController');local active=native and native.ActiveTool
        if not active or not active.Tool or active.Tool.Parent~=ctx.character then return false end
        local class=auraClass(active)
        if class~='Sword' and class~='Pickaxe'then return false end
        local bounds=auraModule('MeleeSwingBounds')
        if not bounds or type(bounds.GetModelHitPosition)~='function'then return false end
        local ok,point=pcall(bounds.GetModelHitPosition,npc,{Position=ctx.root.Position})
        if not ok then return false end
        local range=F.weaponRange(active,active.DisplayTool or active.Tool)
        return point and finite(range) and range>0 and (point-ctx.root.Position).Magnitude<=math.min(45,range) or false
    end
    function F.usePendant(ctx)
        -- Only an already-owned pendant; use its native lifecycle/cooldown handler.
        if ctx.featureHold or ctx.currentChest or ctx.bringEquipmentLock or not safeToWork(ctx) then return false end
        local serverNow = workspace:GetServerTimeNow()
        local ending = tonumber(api.Players.LocalPlayer:GetAttribute('VampirePendantCooldownEndsAt')) or 0
        if ending > serverNow then ctx.pendantAttempt = nil; return false end
        if now() < (ctx.pendantRetryAt or 0) then return false end
        local pendant
        for _, tool in ipairs(tools(ctx)) do if id(tool) == 'VampirePendant' then pendant = tool; break end end
        if not pendant then ctx.pendantAttempt = nil; return false end
        local hostile = false
        for _, npc in ipairs(F.enemies()) do
            local hp, point = auraHealth(npc), position(npc)
            if npc:GetAttribute('NpcFaction') ~= 'FriendlyCompanion' and hp and hp > 0 and point
                and (point - ctx.root.Position).Magnitude <= 80 then hostile = true; break end
        end
        if not hostile then ctx.pendantAttempt = nil; return false end
        local pending = ctx.pendantAttempt
        if pending and pending.sentAt and now() - pending.sentAt >= 1 then
            ctx.pendantAttempt, ctx.pendantRetryAt = nil, now() + 59
            status('Pendant request sent; cooldown not yet observed, resuming combat')
            return false
        end
        if pending and now() - pending.started >= 5 then
            ctx.pendantAttempt, ctx.pendantRetryAt = nil, now() + 15
            status('Pendant use unconfirmed; resuming the weapon instead of repeating equipment requests')
            return false
        end
        if not pending then pending = {started = now()}; ctx.pendantAttempt = pending end
        local active = equip(ctx, pendant)
        if active and not pending.sent and type(active.Use) == 'function' and readyAction(active) then
            pending.sent = true
            local ok = pcall(function() active:Use() end)
            if ok then pending.sentAt = now(); status('Requested owned Vampire Pendant summons; waiting briefly for its cooldown'); return true end
            ctx.pendantAttempt, ctx.pendantRetryAt = nil, now() + 15
            status('Pendant handler failed; resuming combat'); return false
        end
        return true
    end
    function F.auraTargets(ctx, active)
        if not active or not active.Tool then return {} end
        local class = auraClass(active)
        if class ~= 'Sword' and class ~= 'Pickaxe' then return {} end
        local range = F.weaponRange(active, active.DisplayTool or active.Tool)
        if not finite(range) or range <= 0 then return {} end
        local bounds = auraModule('MeleeSwingBounds')
        local targets, seen = {}, {}
        local function add(target)
            local hp = auraHealth(target)
            if not seen[target] and finite(hp) and hp > 0 then
                seen[target] = true; targets[#targets + 1] = target
            end
        end
        if bounds and type(bounds.GetModelHitPosition) == 'function' then
            for _, npc in ipairs(F.enemies()) do
                local isPlayer = npc == ctx.character or (type(api.Players.GetPlayerFromCharacter) == 'function'
                    and api.Players:GetPlayerFromCharacter(npc) ~= nil)
                if npc:IsA('Model') and not isPlayer and npc:GetAttribute('NpcFaction') ~= 'FriendlyCompanion'
                    and (not ctx.questMining or not quest or not quest.drillSupport.activeMine()
                        or quest.drillSupport.mineEnemy(npc,quest.drillSupport.activeMine()))
                    and F.questTargetAllowed(ctx,npc) and (class~='Sword' or F.swordTargetAllowed(npc))
                    and (not tag(npc,'Watcher') and tostring(npc:GetAttribute('RealName') or npc.Name):find('Watcher',1,true)~=1
                        or F.watcherVisible(ctx,npc))
                    and (not ownFaceWorm(ctx,ctx.questParasiteTarget) or npc==ctx.questParasiteTarget)then
                    local point = bounds.GetModelHitPosition(npc, { Position = ctx.root.Position })
                    if point and (point - ctx.root.Position).Magnitude <= range then add(npc) end
                end
            end
        end
        return targets
    end
    function F.swing(ctx, active)
        ctx.check()
        if not active or active._Destroyed or not active.Tool or active.Tool.Parent ~= ctx.character then return false,'equipped weapon is stale' end
        local c = controller('ToolController')
        if not c or c.ActiveTool ~= active then return false,'native active weapon changed' end
        if not safeToWork(ctx) then return false,'seat or transition is active' end
        if quest and quest.pauseCombat(ctx)then return false,'current native quest action owns combat' end
        if not readyAction(active) then return false,'native weapon action / cooldown is not ready' end
        if type(active.CanUseAction) ~= 'function' or type(active.RecordUseCooldown) ~= 'function' then return false,'native cooldown handler missing' end
        local class, hammer = auraClass(active)
        if class ~= 'Sword' and class ~= 'Pickaxe' then return false end
        local function compatible()
            if not quest then return true end
            local required,requiredClass,strict=quest.required(ctx)
            local held=id(active.DisplayTool or active.Tool)
            if strict and (required and held~=required and active.Tool.Name~=required
                    and active.Tool.Name~=required..tostring(api.Players.LocalPlayer.UserId)
                or requiredClass and requiredClass~=class
                or not required and not requiredClass)then return false end
            return true
        end
        if not compatible()then return false,'current native weapon requirement changed' end
        if hammer and (active.InputDown or active.PendingAttackType) then return false end
        local interval
        if type(active.GetAttackInterval) == 'function' then interval = active:GetAttackInterval(hammer and 'Weak' or nil)
        else
            local speed = auraModule('AttackSpeed')
            if speed and type(speed.GetInterval) == 'function' then interval = speed.GetInterval(active.AttackSpeed or 0) end
        end
        if not finite(interval) or interval <= 0 then return false,'native attack interval unavailable' end
        local impactDelay
        if hammer then
            local timing = auraModule('ChampionHammerTiming')
            if not timing or type(timing.GetLightImpactDelay) ~= 'function' then return false end
            impactDelay = timing.GetLightImpactDelay(interval)
        end
        local signal = active.Execute
        if not signal or type(signal.Fire) ~= 'function' then return false,'native Execute signal missing' end
        -- Refresh after any yielding native-module lookup; a previous snapshot can be stale.
        local targets = F.auraTargets(ctx, active)
        if #targets == 0 then return false,'no permitted hostile inside native hit range' end
        ctx.check()
        if c.ActiveTool ~= active or active.Tool.Parent ~= ctx.character or not safeToWork(ctx) or not readyAction(active)
            or quest and quest.pauseCombat(ctx)then return false end
        if not compatible()then return false,'current native weapon requirement changed' end
        local payload = hammer and { 'Swing', targets, 'Weak', impactDelay, workspace:GetServerTimeNow() } or { 'Swing', targets }
        local before = {}
        for _, target in ipairs(targets) do before[target] = auraHealth(target) or 0 end
        local sent,route=sendTool(ctx,active,payload)
        if not sent then status('Aura signal has no listener; waiting for native ToolService.Update');return false,'native listener unavailable' end
        active.LastSwing = now() + interval
        if hammer then active.AttackLockedUntil = active.LastSwing end
        active:RecordUseCooldown(active.LastSwing)
        ctx.lastAura = { time = now(), route = route, count = #targets, class = class }
        for _, target in ipairs(targets) do
            if not tag(target, 'Ore') then F.afterAttack(ctx, target, class, before[target]) end
        end
        return true
    end
    function F.restoreWeaponSignal(ctx,thread)
        local edit=ctx.swingEdit
        if not edit or thread and edit.thread~=thread then return end
        pcall(function()if edit.signal.Fire==edit.wrapper then edit.signal.Fire=edit.original end end)
        if ctx.swingEdit==edit then ctx.swingEdit=nil end
    end
    function F.miningSwing(ctx,active)
        local signal=active.Execute
        local original=signal and signal.Fire
        if type(original)~='function' or not cfg.classQuest or not ctx.questMining then return pcall(active.Swing,active)end
        -- Native Pickaxe.Swing supports ore and NPC targets in one packet. Extend
        -- that packet without changing native ore geometry, cooldown or animation.
        if ctx.swingEdit then return false,'another native weapon dispatch is pending' end
        local wrapper,dispatched
        wrapper=function(self,payload,...)
            if self~=signal or type(payload)~='table' or payload[1]~='Swing' or type(payload[2])~='table'then
                return original(self,payload,...)
            end
            if not safeToWork(ctx) or ctx.questHealing or not ctx.questMining then return end
            local hostiles=quest.miningAuraAllowed(ctx) and F.auraTargets(ctx,active) or {}
            local targets,seen,before={}, {}, {}
            for _,target in ipairs(payload[2])do
                if tag(target,'Ore') and not seen[target]then targets[#targets+1]=target;seen[target]=true end
            end
            for _,target in ipairs(hostiles)do
                if not seen[target]then targets[#targets+1]=target;seen[target]=true;before[target]=auraHealth(target)end
            end
            local packet={};for i,value in ipairs(payload)do packet[i]=value end;packet[2]=targets
            local sent=sendTool(ctx,active,packet,original)
            if not sent then return end
            dispatched=true
            ctx.lastMiningAura={time=now(),count=#hostiles}
            for _,target in ipairs(hostiles)do F.afterAttack(ctx,target,'Pickaxe',before[target])end
        end
        local installed=pcall(function()signal.Fire=wrapper end)
        if not installed then return false,'native mining aura signal is not writable' end
        local edit={signal=signal,wrapper=wrapper,original=original,thread=coroutine.running()};ctx.swingEdit=edit
        local ok,why=pcall(active.Swing,active)
        if ctx.swingEdit==edit then F.restoreWeaponSignal(ctx,edit.thread)end
        if not ok then return false,why end
        return dispatched==true,not dispatched and 'native pickaxe produced no Swing packet' or nil
    end
    function F.gunShot(ctx,active)
        if not active or active._Destroyed or type(active.Shoot)~='function' or not safeToWork(ctx) then return false,'native gun is not ready' end
        if quest and quest.pauseCombat(ctx)then return false,'current native quest action owns combat' end
        if not F.watcherVisible(ctx)then return false,'native Watcher visibility is blocked' end
        if ownFaceWorm(ctx,ctx.questParasiteTarget)then return false,'native face Worm needs a compatible melee tool' end
        local signal=active.Execute;local original=signal and signal.Fire
        if type(original)~='function' or ctx.swingEdit then return false,'native gun signal is unavailable / busy' end
        local owner=coroutine.running();local dispatched,action,wrapper,edit
        wrapper=function(self,payload,...)
            if coroutine.running()~=owner or self~=signal or type(payload)~='table'then return original(self,payload,...)end
            if payload[1]=='Shoot'then
                if quest and quest.pauseCombat(ctx,edit) or not F.watcherVisible(ctx)then return end
                local target=ctx.questThreat or ctx.combatTarget
                if target and F.weaponClass(ctx,target)then return end
                if quest then
                    local required,requiredClass,strict=quest.required(ctx)
                    local held=active.DisplayTool or active.Tool;local name=id(held);local class=attr(held,'Class')
                    if strict and (required and name~=required or requiredClass and requiredClass~=class
                        and not(requiredClass=='Gun' and (class=='Revolver' or class=='Rifle' or class=='Shotgun'))
                        or not required and not requiredClass)then return end
                end
            end
            local sent=sendTool(ctx,active,payload,original)
            if sent then action=payload[1];if action=='Shoot'then dispatched=true end end
        end
        local installed=pcall(function()signal.Fire=wrapper end)
        if not installed then return false,'native gun signal is not writable' end
        edit={signal=signal,wrapper=wrapper,original=original,thread=owner};ctx.swingEdit=edit
        local ok,why=pcall(active.Shoot,active)
        if ctx.swingEdit==edit then F.restoreWeaponSignal(ctx,edit.thread)end
        if not ok then error(why,0)end
        if dispatched then ctx.lastGunShot={time=now(),action='Shoot'};return true end
        return false,action=='Reload' and 'native reload is in progress' or 'native gun produced no Shoot packet (viewmodel / aim / action not ready)'
    end
    function F.medicalConsume(ctx,active)
        if not active or active._Destroyed or type(active.Consume)~='function' or not safeToWork(ctx)
            or not cfg.classQuest or not ctx.questHealing then return false,'native medical handler is not ready' end
        local signal=active.Execute;local original=signal and signal.Fire
        if type(original)~='function' or ctx.swingEdit then return false,'native medical signal is unavailable / busy' end
        local owner=coroutine.running();local wrapper,dispatched,route
        wrapper=function(self,payload,...)
            if coroutine.running()~=owner or self~=signal or type(payload)~='table' or payload[1]~='Consume'then
                return original(self,payload,...)
            end
            if not cfg.classQuest or not ctx.questHealing then return end
            local sent,used=sendTool(ctx,active,payload,original)
            if sent then dispatched=true;route=used end
        end
        local installed=pcall(function()signal.Fire=wrapper end)
        if not installed then return false,'native medical signal is not writable' end
        local edit={signal=signal,wrapper=wrapper,original=original,thread=owner};ctx.swingEdit=edit
        -- Keep native Consume's cooldown and full-health checks. A local heal
        -- flash without its actual packet is not an attempted healing action.
        local ok,why=pcall(active.Consume,active)
        if ctx.swingEdit==edit then F.restoreWeaponSignal(ctx,owner)end
        if dispatched then ctx.lastMedicalUse={time=now(),route=route};return true end
        if not ok then return false,tostring(why) end
        return false,'native medical handler produced no Consume packet / listener'
    end
    function F.combatPassives()
        local resolver=auraModule('ClassResolver')
        if resolver and type(resolver.ResolvePlayerPassives)=='function'then
            local ok,passives=pcall(resolver.ResolvePlayerPassives,api.Players.LocalPlayer,workspace)
            if ok and type(passives)=='table'then return passives end
        end
    end
    function F.weaponClass(ctx, target)
        if not target or not F.enemyAlive(target) or not F.questTargetAllowed(ctx,target)then return end
        if ownFaceWorm(ctx,target)then return end
        local stone,watcher,deflect=armorFields(target)
        local leech=F.isFuelLeech(target)
        local plan=cfg.classQuest and quest and quest.plan(s.classData,s.questCatalog,cfg.driveDepth)
        if not stone and not watcher and not deflect and not leech then
            if ctx.pickaxeTargets and ctx.pickaxeTargets[target] and not(plan and plan.kind=='combat')then return 'Pickaxe' end
            return
        end
        local active=controller('ToolController');active=active and active.ActiveTool
        local class=plan and plan.kind=='combat' and plan.weaponClass or active and attr(active.DisplayTool or active.Tool,'Class')
        if class=='Gun' or class=='Revolver' or class=='Rifle' or class=='Shotgun'then
            local passives=F.combatPassives()
            local ray=auraModule('GunRaycast')
            if passives and ray and type(ray.CanPierceDeflectPart)=='function'then
                local ok,allowed=pcall(ray.CanPierceDeflectPart,target,passives.GunsPierceEnemies==true,passives.GunsPierceStoneEnemies==true)
                if ok and allowed==true then return end
            end
            return 'Pickaxe'
        end
        if not F.swordTargetAllowed(target) or ctx.pickaxeTargets and ctx.pickaxeTargets[target]then return 'Pickaxe' end
    end
    function F.afterAttack(ctx, target, class, before)
        if cfg.classQuest and (ctx.questCombat or ctx.questMining) and target and F.enemyAlive(target) then
            ctx.questDamageWatch=ctx.questDamageWatch or setmetatable({}, {__mode='k'})
            local check=ctx.questDamageWatch[target]
            local hp=npcHealth(target)
            if not check or hp<check.health or check.weaponClass and check.weaponClass~=class then
                check={health=hp,progressAt=now(),attempts=0};ctx.questDamageWatch[target]=check
            end
            check.weaponClass=class;ctx.questCombatWait=nil
            check.attempts=check.attempts+1;check.lastAttempt=now()
        end
        if class ~= 'Sword' or not target or not target.Parent then return end
        local record = ctx.damageChecks[target] or { failures = 0 }
        ctx.damageChecks[target] = record
        if record.before and npcHealth(target) >= record.before then record.failures = record.failures + 1 else record.failures = 0 end
        record.before = before
        if record.failures >= 3 and findTool(ctx, 'Pickaxe') then
            ctx.pickaxeTargets[target] = true
            local plan=cfg.classQuest and quest and quest.plan(s.classData,s.questCatalog,cfg.driveDepth)
            if not plan or plan.kind~='combat'then status('Sword attacks show no health change; trying an owned pickaxe')end
        end
    end
    local function relevantWatcher(ctx,npc)
        local inside=quest and quest.drillSupport.inDungeon(ctx)
        local mine=inside and quest and quest.drillSupport.activeMine(ctx)
        local room=inside and not mine and quest and quest.special.bound(ctx)
        if not F.enemyAlive(npc) or not position(npc) or (position(npc)-ctx.root.Position).Magnitude>400 then return false end
        if inside then
            return mine and quest.drillSupport.mineEnemy(npc,mine) or room and quest.special.belongs(npc,room)
        end
        return outdoorEnemyAllowed(npc) or suspendedMeleeDefense(ctx,npc)
    end
    local function currentWatchers(ctx)
        local native=controller('WatcherController')
        local folder=workspace:FindFirstChild('Npc')
        local cache=ctx.watcherDiscovery
        if not cache or cache.folder~=folder or cache.native~=native then
            cache={folder=folder,native=native,at=0,list={}};ctx.watcherDiscovery=cache
        end
        if not ctx.watcherTagSignals and ctx.connect and type(api.CollectionService.GetInstanceAddedSignal)=='function'then
            ctx.watcherTagSignals=true
            for _,method in ipairs({'GetInstanceAddedSignal','GetInstanceRemovedSignal'})do
                if type(api.CollectionService[method])=='function'then
                    local ok,signal=pcall(api.CollectionService[method],api.CollectionService,'Watcher')
                    if ok and signal then ctx.connect(signal,function()ctx.watcherDiscoveryDirty=true end)end
                end
            end
        end
        if now()>=cache.at or ctx.watcherDiscoveryDirty then
            local discovered,seen={},{}
            local function discover(npc)
                if npc and npc.Parent and not seen[npc]then seen[npc]=true;discovered[#discovered+1]=npc end
            end
            for _,npc in ipairs(tagged('Watcher'))do discover(npc)end
            -- Native identity covers the short interval before a Watcher tag
            -- streams in; ordinary enemy enumeration is structural, not per-frame.
            for _,npc in ipairs(F.enemies())do
                if tostring(npc:GetAttribute('RealName') or npc.Name):find('Watcher',1,true)==1 then discover(npc)end
            end
            cache.list,cache.at=discovered,now()+.2;ctx.watcherDiscoveryDirty=nil
        end
        local result,seen={},{}
        local function add(npc)
            if npc and not seen[npc] and relevantWatcher(ctx,npc)then seen[npc]=true;result[#result+1]=npc end
        end
        for _,npc in ipairs(cache.list)do add(npc)end
        -- These are small authoritative/urgent sets. Recheck them immediately,
        -- together with every cached candidate's live health, range and session.
        for npc in pairs(native and native.TrackedWatchers or {})do add(npc)end
        for _,npc in pairs({ctx.questThreat,ctx.combatTarget})do
            if npc and (tag(npc,'Watcher') or tostring(npc:GetAttribute('RealName') or npc.Name):find('Watcher',1,true)==1)then add(npc)end
        end
        table.sort(result,function(a,b)return (position(a)-ctx.root.Position).Magnitude<(position(b)-ctx.root.Position).Magnitude end)
        return result
    end
    function F.watcher(ctx)
        local targets=currentWatchers(ctx);local closest=targets[1]
        ctx.watcher=closest
        if closest and workspace.CurrentCamera then
            local eyes = closest:FindFirstChild('Head', true) or closest:FindFirstChild('Eyes', true) or part(closest)
            if eyes then
                local camera = workspace.CurrentCamera
                if ctx.watcherCamera and ctx.watcherCamera~=camera then
                    if ctx.cameraBeforeWatcher and ctx.watcherCamera.CFrame==ctx.watcherFrame then
                        ctx.watcherCamera.CFrame=ctx.cameraBeforeWatcher
                    end
                    ctx.cameraBeforeWatcher,ctx.watcherFrame=nil,nil
                end
                ctx.watcherCamera = camera
                ctx.cameraBeforeWatcher = ctx.cameraBeforeWatcher or camera.CFrame
                camera.CFrame = CFrame.lookAt(camera.CFrame.Position, eyes.Position)
                ctx.watcherFrame = camera.CFrame
                if cfg.classQuest and now()>=(ctx.watcherViewTryAt or 0) then
                    ctx.watcherViewTryAt=now()+.15
                    if not F.watcherVisible(ctx)then
                    -- Each actual current-room Watcher must pass the native ray
                    -- and viewport test. Real cluster viewpoints can cover more
                    -- than one; an occluded member remains unobserved.
                    local point,count=Vector3.zero,0
                    for _,npc in ipairs(targets)do
                        local target=npc:FindFirstChild('Head',true) or npc:FindFirstChild('Eyes',true) or part(npc)
                        if target then point=point+target.Position;count=count+1 end
                    end
                    point=count>0 and Vector3.new(point.X/count,point.Y/count,point.Z/count) or eyes.Position
                    local origin=ctx.root.Position+Vector3.new(0,2,0)
                    local found=false
                    for _,aim in ipairs({point,eyes.Position})do
                        for _,offset in ipairs({Vector3.zero,Vector3.new(3,0,0),Vector3.new(-3,0,0),Vector3.new(0,0,3),Vector3.new(0,0,-3)})do
                            if (aim-origin-offset).Magnitude>.001 then
                                camera.CFrame = CFrame.lookAt(origin+offset,aim);ctx.watcherFrame=camera.CFrame
                                if F.watcherVisible(ctx)then found=true;break end
                            end
                        end
                        if found then break end
                    end
                    -- If all-visible is impossible, face the urgent attacked
                    -- Watcher honestly; its melee packet verifies that target
                    -- independently without declaring the others safe.
                    if not found then
                        local threat=ctx.questThreat or ctx.combatTarget
                        local target=threat and relevantWatcher(ctx,threat) and (tag(threat,'Watcher')
                            or tostring(threat:GetAttribute('RealName') or threat.Name):find('Watcher',1,true)==1) and part(threat) or eyes
                        if target and (target.Position-origin).Magnitude>.001 then
                            camera.CFrame=CFrame.lookAt(origin,target.Position);ctx.watcherFrame=camera.CFrame
                        end
                    end
                    end
                end
            end
        elseif ctx.cameraBeforeWatcher then
            local camera = ctx.watcherCamera
            if camera and camera.CFrame == ctx.watcherFrame then camera.CFrame = ctx.cameraBeforeWatcher end
            ctx.cameraBeforeWatcher, ctx.watcherFrame = nil, nil
        end
    end
    function F.watcherVisible(ctx,target)
        local targets=target and {target} or currentWatchers(ctx)
        if #targets==0 then return true end
        local camera=workspace.CurrentCamera
        if not camera then return false end
        local native=controller('WatcherController')
        if native and type(native.IsWatcherVisible)=='function'then
            for _,npc in ipairs(targets)do
                if not relevantWatcher(ctx,npc)then return false end
                local ok,visible=pcall(native.IsWatcherVisible,native,npc)
                if not ok or visible~=true then return false end
            end
            return true
        end
        -- Missing native controller is not proof of a clear line of sight.
        return false
    end
    function F.healingMovementBlocked(ctx)
        if not cfg.classQuest or not ctx.questHealing or not quest.enabled(ctx)then return 'native scene or character is not ready' end
        if quest.manual()then return 'manual item movement is active' end
        if ctx.humanoid.SeatPart or ctx.humanoid.Sit then return 'actual seat detachment is pending' end
        if ctx.questDriveInput or ctx.questDriving or ctx.questSeating then return 'owned driving input has not released' end
        if ctx.nativeGateMotion or ctx.questMineEntry then return 'actual dungeon transition is pending' end
        if ctx.questPlacement or ctx.questPreviewCancel then return 'native placement cancellation is pending' end
        if s.bringDelivery or ctx.bringEquipmentLock or quest.calls.drag then return 'native item transport is still reserved' end
        local job=s.questDelivery
        if job and job.ctx==ctx and (job.owns or job.pending or not job.movementReleased)then return 'native delivery release is pending' end
        if s.questCashJob and s.questCashJob.ctx==ctx and quest.calls.cash then return 'native coin interaction is pending' end
        if ctx.featureHold or ctx.defenseMoving then return 'another movement owner is active' end
        if ctx.currentChest then
            ctx.defenseAbort=true;movement.cancel(ctx)
            return 'waiting for the chest route to acknowledge retreat'
        end
    end
    function F.medicalLocationAllowed(ctx,item)
        if not item or not item.Parent or not item:IsDescendantOf(workspace)then return false end
        if quest.drillSupport.inDungeon(ctx)then return F.chestAreaAllowed(ctx,item)end
        local ancestor=item
        while ancestor and ancestor~=workspace do
            if quest.drillSupport.mineshaft(ancestor) or ancestor:GetAttribute('SessionDungeonId')~=nil
                or ancestor.Name=='Goblin_Ring' or ancestor.Name=='GoblinRing' or ancestor.Name=='VampireMansion'
                or tag(ancestor,'VampireMansion')then return false end
            ancestor=ancestor.Parent
        end
        return true
    end
    local function healingFloor(ctx,origin,height)
        if not RaycastParams or type(workspace.Raycast)~='function'then return end
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true
        params.FilterDescendantsInstances={ctx.character,ctx.drill,workspace:FindFirstChild('Npc'),workspace:FindFirstChild('Items')}
        local ok,hit=pcall(workspace.Raycast,workspace,origin+Vector3.new(0,150,0),Vector3.new(0,-500,0),params)
        if not ok or not hit or not hit.Instance or not hit.Instance.Parent or not hit.Instance:IsA('BasePart')
            or hit.Instance.CanCollide~=true or not hit.Position or not hit.Normal or not finite(hit.Normal.Y) or hit.Normal.Y<.65
            or not F.medicalLocationAllowed(ctx,hit.Instance)then return end
        local inside=quest.drillSupport.inDungeon(ctx)
        local point=hit.Position+Vector3.new(0,height or (inside and 3 or 100),0)
        local mine=inside and quest.drillSupport.activeMine(ctx)
        if mine and quest.drillSupport.contains(mine,point,0)~=true then return end
        if F.healingPointSafe(ctx,point)then return point end
    end
    function F.questRetreat(ctx)
        local blocked=F.healingMovementBlocked(ctx)
        if blocked then return false,blocked end
        local current=ctx.root.CFrame.Position or ctx.root.Position
        if F.healingPointSafe(ctx,current)then ctx.questHealPoint=current;return false end
        local best,score
        for _,direction in ipairs({Vector3.new(1,0,0),Vector3.new(-1,0,0),Vector3.new(0,0,1),Vector3.new(0,0,-1)})do
            local point=healingFloor(ctx,current+direction*80)
            if point then
                local distance=1000
                for _,npc in ipairs(F.enemies())do
                    local hp=npc:FindFirstChildOfClass('Humanoid');local p=part(npc)
                    if hp and hp.Health>0 and p and npc:GetAttribute('NpcFaction')~='FriendlyCompanion'then distance=math.min(distance,(point-p.Position).Magnitude)end
                end
                if F.healingPointSafe(ctx,point) and distance>=80 and (not score or distance>score)then best,score=point,distance end
            end
        end
        if not best then return false end
        movement.cancel(ctx);movement.hover(ctx);ctx.root.CFrame=CFrame.new(best);ctx.questHealPoint=best;return true
    end
    function F.clearMedicalSearch(ctx,search)
        if search and search.streamToken then movement.cancelItemReload(ctx,search.streamToken);search.streamToken=nil end
        if not ctx.questHealing then ctx.medicalSearchScan=nil end
    end
    function F.medicalSearch(ctx,search)
        if not cfg.classQuest or not ctx.questHealing or not quest.enabled(ctx) or F.extractionReady()then return false,'medical search is paused',false end
        local band=workspace:GetAttribute('InfiniteDepthOffsetMeters')
        local native=controller('DungeonUIController');local room=native and native._BoundDungeon
        local cache=ctx.medicalSearchScan
        if not cache or cache.character~=ctx.character or cache.drill~=ctx.drill or cache.band~=band or cache.room~=room
            or cache.session~=(room and room:GetAttribute('SessionDungeonId'))then
            cache={character=ctx.character,drill=ctx.drill,band=band,room=room,session=room and room:GetAttribute('SessionDungeonId'),
                cursor=1,candidates=setmetatable({}, {__mode='k'}),tried=setmetatable({}, {__mode='k'}),origin=ctx.root.CFrame.Position or ctx.root.Position,survey=0}
            ctx.medicalSearchScan=cache;ctx.worldRefreshAt=0
        end
        local progressed=false
        if now()>=(cache.readAt or 0) and type(ctx.readWorld)=='function'then
            cache.readAt=now()+1
            local reader=ctx.worldReader
            if not ctx.worldReading or reader and coroutine.status(reader)=='dead'then
                local before=ctx.worldScan;local cursor=before and before.cursor;local child=before and before.childCursor
                local ok,why=pcall(ctx.readWorld)
                if not ok then
                    local text=tostring(why)
                    if text:find('__CHESTFARM_CANCELLED',1,true) or text:find('__EARTH_',1,true)then error(why,0)end
                else
                    progressed=ctx.worldScan~=before or before and (before.cursor~=cursor or before.childCursor~=child) or false
                end
            end
        end
        if now()>=(cache.tagsAt or 0)then
            cache.tagsAt=now()+1
            for _,pad in ipairs(tagged('BuyPart'))do
                if pad:IsA('BasePart') and F.medicalLocationAllowed(ctx,pad)then cache.candidates[pad]=true end
            end
        end
        local source=ctx.worldObjects or ctx.worldScan and ctx.worldScan.list or {}
        local ending=math.min(#source,cache.cursor+199)
        for i=cache.cursor,ending do
            local item=source[i]
            if item and item.Parent
                and (item:IsA('BasePart') and tag(item,'BuyPart') or item:IsA('Model') and (item.Name=='Shop' or item.Name=='TradingPost'))
                and F.medicalLocationAllowed(ctx,item)then
                cache.candidates[item]=true
            end
        end
        if ending>=cache.cursor then progressed=true end
        cache.cursor=ending+1
        if cache.cursor>#source and not ctx.worldScan then cache.cursor=1 end
        if cache.target then
            if not cache.target.Parent or not F.medicalLocationAllowed(ctx,cache.target)then cache.target=nil
            elseif now()<(cache.targetUntil or 0)then
                movement.prefetchAt(ctx,position(cache.target));return true,'streaming medical stock at a verified shop',progressed
            else cache.tried[cache.target]=now()+30;cache.target=nil;cache.surveyDue=true end
        end
        local blocked=F.healingMovementBlocked(ctx)
        if blocked then return false,'medical search waits: '..blocked,progressed end
        if now()<(cache.surveyHoldUntil or 0)then
            if cache.surveyPoint then movement.prefetchAt(ctx,cache.surveyPoint)end
            return true,'streaming the newly surveyed medical area',progressed
        end
        local function survey()
            if not quest.drillSupport.inDungeon(ctx) and now()>=(cache.surveyAt or 0)then
                cache.surveyAt=now()+3;cache.survey=cache.survey+1
                local direction=cache.survey%2==1 and 1 or -1
                local offset=math.ceil(cache.survey/2)*160*direction
                local surveyOrigin=cache.origin+Vector3.new(offset,0,0)
                -- Streaming is read-only. Ask for the candidate area before its
                -- floor is visible, but never move there without actual geometry.
                movement.prefetchAt(ctx,surveyOrigin)
                local point=healingFloor(ctx,surveyOrigin)
                if point then
                    movement.cancel(ctx);movement.hover(ctx);ctx.root.CFrame=CFrame.new(point);ctx.questHealPoint=point
                    movement.prefetchAt(ctx,point-Vector3.new(0,100,0));ctx.worldRefreshAt=0
                    cache.surveyPoint=point;cache.surveyHoldUntil=now()+3
                    return true,'surveying loaded safe tunnel for a medical shop',true
                end
            end
            return false
        end
        -- Unrelated loaded shops cannot monopolize discovery. After a real
        -- shop streaming window, give the next safe survey probe its turn.
        -- This alternation survives bounded search bursts in the same scope.
        if cache.surveyDue and not quest.drillSupport.inDungeon(ctx) and now()>=(cache.surveyAt or 0)then
            cache.surveyDue=nil
            local surveyed,reason,moved=survey();if surveyed then return surveyed,reason,moved end
        end
        local target,distance,pose
        for candidate in pairs(cache.candidates)do
            local p=position(candidate)
            local inside=quest.drillSupport.inDungeon(ctx)
            local point=p and p+Vector3.new(0,inside and 3 or 100,0)
            local mine=inside and quest.drillSupport.activeMine(ctx)
            if mine and point and quest.drillSupport.contains(mine,point,0)~=true then point=nil end
            if point and F.medicalLocationAllowed(ctx,candidate) and now()>=(cache.tried[candidate] or 0)
                and F.healingPointSafe(ctx,point)then
                local d=(p-(ctx.root.CFrame.Position or ctx.root.Position)).Magnitude
                if not distance or d<distance then target,distance,pose=candidate,d,point end
            end
        end
        if target then
            movement.cancel(ctx);movement.hover(ctx);ctx.root.CFrame=CFrame.new(pose);ctx.questHealPoint=pose
            cache.target,cache.targetUntil=target,now()+3;movement.prefetchAt(ctx,position(target))
            ctx.worldRefreshAt=0;return true,'searching medical stock at a verified shop',true
        end
        local surveyed,reason,moved=survey();if surveyed then return surveyed,reason,moved end
        return progressed,'searching the actual streamed map for a medical shop',progressed
    end
    local function bossAt(origin, source)
        for _, manager in ipairs(tagged('NpcManager')) do
            local npc = manager.Parent
            if npc and npcHealth(npc) > 0 and npc:GetAttribute('NpcFaction') ~= 'FriendlyCompanion'
                and manager:GetAttribute('IsBoss') == true then
                if source and (source == npc or descendant(source, npc)) then return npc end
                local point = position(npc)
                if not source and point and (point - origin).Magnitude <= 15 then return npc end
            end
        end
    end
    -- Only Blinker and identified boss projectiles/telegraphs participate in defensive movement.
    function F.npcShot(ctx, origin, destination, _, speed, serverTime, targetUserId, kind)
        if not safeToWork(ctx) or not F.enabled() then return end
        if typeof(origin) ~= 'Vector3' or typeof(destination) ~= 'Vector3' then return end
        local boss = kind ~= 'BlinkerShard' and bossAt(origin)
        if kind ~= 'BlinkerShard' and not boss then return end
        if targetUserId and tonumber(targetUserId) ~= api.Players.LocalPlayer.UserId then return end
        local vector = destination - origin
        if vector.Magnitude < 0.01 then return end
        local toPlayer = ctx.root.Position - origin
        local projected = toPlayer:Dot(vector.Unit)
        if projected < 0 or projected > vector.Magnitude + 10 then return end
        local miss = (toPlayer - vector.Unit * projected).Magnitude
        if miss > 10 then return end
        if type(speed) ~= 'number' or speed <= 0 then
            if kind ~= 'BlinkerShard' then return end
            speed = 300 -- BlinkerConfig.ProjectileSpeed
        end
        local age = 0
        if type(serverTime) == 'number' and type(workspace.GetServerTimeNow) == 'function' then
            age = math.max(0, workspace:GetServerTimeNow() - serverTime)
        end
        local remaining = projected / speed - age
        if remaining < -0.15 or remaining > 2 then return end
        ctx.pendingThreat = {kind = boss and 'boss projectile' or 'Blinker shard', origin = origin, direction = vector.Unit,
            deadline = now() + math.max(0.05, remaining), expires = now() + math.max(0.2, remaining + 0.15)}
        if ctx.currentChest then ctx.defenseAbort = true end
    end
    function F.bossCharge(ctx, action, chargeId, origin, duration, _, _, source)
        if action ~= 'Start' or not safeToWork(ctx) or not F.enabled()
            or typeof(origin) ~= 'Vector3' or type(duration) ~= 'number' or duration <= 0 then return end
        local boss = bossAt(origin, source)
        if not boss or (origin - ctx.root.Position).Magnitude > 125 then return end
        ctx.bossCharges = ctx.bossCharges or {}
        if ctx.bossCharges[chargeId] then return end
        ctx.bossCharges[chargeId] = true
        ctx.pendingThreat = {kind = 'boss black-hole charge', origin = origin, npc = boss,
            radius = 120, expires = now() + math.min(duration, 2), hold = math.min(duration + 0.2, 2)}
        if ctx.currentChest then ctx.defenseAbort = true end
    end
    function F.bindShots(ctx)
        if (ctx.shotsBound and ctx.chargeBound) or not api.event or now() < (ctx.shotBindAt or 0) then return end
        ctx.shotBindAt = now() + 2
        local signal = api.event('BulletService', 'FiredNpcBullet')
        if signal and not ctx.shotsBound then
            ctx.shotsBound = true
            ctx.connect(signal, function(...) F.npcShot(ctx, ...) end)
        end
        local charge = api.event('BulletService', 'NpcBlackHoleCharge')
        if charge and not ctx.chargeBound then
            ctx.chargeBound = true
            ctx.connect(charge, function(...) F.bossCharge(ctx, ...) end)
        end
    end
    local function cueNpc(manager)
        local npc=manager and manager.Parent
        if not npc or not manager:IsDescendantOf(workspace) or not F.enemyAlive(npc)
            or npc:GetAttribute('NpcFaction')=='FriendlyCompanion'then return end
        local name=npc:GetAttribute('RealName') or npc.Name
        if name=='Blinker' or manager:GetAttribute('IsBoss')==true then return npc,name end
    end
    local function disconnectCue(ctx,manager)
        local record=ctx.cueConnections and ctx.cueConnections[manager]
        if type(record)=='table'then
            for _,connection in ipairs(record)do pcall(function()connection:Disconnect()end)end
        end
        if ctx.cueConnections then ctx.cueConnections[manager]=nil end
    end
    local function observeCue(ctx,manager,npc,name)
        -- Room ownership is safety; a quest retry is not protection from a
        -- living ranged enemy. The same live/session predicate used by the
        -- camera applies here without suppressing retry-held native attacks.
        if not ctx.active or not api.owned() or not safeToWork(ctx) or not relevantWatcher(ctx,npc)then return end
        local animation,nonce=manager:GetAttribute('ForceAnimation'),manager:GetAttribute('ForceAnimationNonce')
        local point=position(npc);local token=tostring(animation)..':'..tostring(nonce)
        local ranged=type(animation)=='string' and (animation:lower():match('shoot')
            or animation:lower():match('projectile') or animation:lower():match('cast'))
        if ((name=='Blinker' and animation=='Attack') or (manager:GetAttribute('IsBoss')==true and ranged))
            and point and (point-ctx.root.Position).Magnitude<=120 and ctx.attackCues[manager]~=token then
            ctx.pendingThreat={npc=npc,origin=point,kind=name=='Blinker' and 'Blinker cast' or 'boss ranged cast',
                source=manager,token=token,expires=now()+.6}
            if ctx.currentChest then ctx.defenseAbort=true end
            return ctx.pendingThreat
        end
    end
    local function bindCue(ctx,manager)
        if ctx.cueConnections[manager] or not ctx.connect or type(manager.GetAttributeChangedSignal)~='function'then return end
        local record={};ctx.cueConnections[manager]=record
        local function changed()
            local npc,name=cueNpc(manager)
            if not npc or not ctx.active then disconnectCue(ctx,manager);return end
            -- Attribute events inspect their exact eligible manager;
            -- ordinary NPC animation bursts cannot rescan the registry.
            pcall(observeCue,ctx,manager,npc,name)
        end
        record[1]=ctx.connect(manager:GetAttributeChangedSignal('ForceAnimation'),changed)
        record[2]=ctx.connect(manager:GetAttributeChangedSignal('ForceAnimationNonce'),changed)
    end
    function F.observeThreat(ctx)
        if not F.enabled() or not safeToWork(ctx) then return nil end
        F.bindShots(ctx)
        ctx.attackCues=ctx.attackCues or setmetatable({}, {__mode='k'})
        ctx.cueConnections=ctx.cueConnections or setmetatable({}, {__mode='k'})
        for manager in pairs(ctx.cueConnections)do if not cueNpc(manager)then disconnectCue(ctx,manager)end end
        if ctx.pendingThreat and now()>=ctx.pendingThreat.expires then ctx.pendingThreat,ctx.defenseAbort=nil,nil end
        if ctx.pendingThreat then return ctx.pendingThreat end
        if now()<(ctx.blinkerObserveAt or 0)then return nil end
        ctx.blinkerObserveAt=now()+.1
        if not ctx.cueTagSignals and ctx.connect and type(api.CollectionService.GetInstanceAddedSignal)=='function'then
            ctx.cueTagSignals=true
            for _,method in ipairs({'GetInstanceAddedSignal','GetInstanceRemovedSignal'})do
                if type(api.CollectionService[method])=='function'then
                    local removed=method=='GetInstanceRemovedSignal'
                    local ok,signal=pcall(api.CollectionService[method],api.CollectionService,'NpcManager')
                    if ok and signal then ctx.connect(signal,function(manager)
                        if removed then disconnectCue(ctx,manager);ctx.cueDiscoveryAt=0;return end
                        local npc,name=cueNpc(manager)
                        if npc then bindCue(ctx,manager);pcall(observeCue,ctx,manager,npc,name)end
                    end)end
                end
            end
        end
        if now()>=(ctx.cueDiscoveryAt or 0)then
            ctx.cueDiscoveryAt=now()+.2
            local managers,seen={},{}
            for _,manager in ipairs(tagged('NpcManager'))do
                if not seen[manager] and cueNpc(manager)then seen[manager]=true;managers[#managers+1]=manager end
            end
            for manager in pairs(ctx.cueConnections)do if not seen[manager]then disconnectCue(ctx,manager)end end
            ctx.cueManagers=managers
        end
        for _,manager in ipairs(ctx.cueManagers or {})do
            local npc,name=cueNpc(manager)
            if npc then
                bindCue(ctx,manager)
                local threat=observeCue(ctx,manager,npc,name)
                if threat then return threat end
            else disconnectCue(ctx,manager)end
        end
        return nil
    end
    local function escapePosition(ctx, threat)
        local origin, point = ctx.root.Position, threat.origin or position(threat.npc)
        if not point then return nil end
        local forward = threat.direction or (origin - point)
        forward = Vector3.new(forward.X, 0, forward.Z)
        if forward.Magnitude < 0.01 then forward = Vector3.new(1, 0, 0) end
        forward = forward.Unit
        local side = Vector3.new(-forward.Z, 0, forward.X)
        local rayParams
        if type(workspace.Raycast) == 'function' and RaycastParams then
            rayParams = RaycastParams.new()
            rayParams.FilterType = Enum.RaycastFilterType.Exclude
            rayParams.FilterDescendantsInstances = {ctx.character, workspace:FindFirstChild('Npc'), workspace:FindFirstChild('Items')}
            rayParams.RespectCanCollide = true
        end
        local best, score
        -- 16 studs exceeds the native shard's eight-stud visual tracking adjustment.
        local directions = threat.radius and {forward, (forward + side * 0.4).Unit, (forward - side * 0.4).Unit}
            or {side, side * -1, (side + forward * 0.4).Unit, (side * -1 + forward * 0.4).Unit}
        for _, direction in ipairs(directions) do
            local candidate = threat.radius and point + direction * threat.radius or origin + direction * 16
            local clear = true
            if rayParams then
                if workspace:Raycast(origin, candidate - origin, rayParams) then clear = false end
                local floor = clear and workspace:Raycast(candidate + Vector3.new(0, 10, 0), Vector3.new(0, -256, 0), rayParams)
                if not floor or floor.Normal.Y < 0.65 then clear = false
                elseif origin.Y - floor.Position.Y <= 12 then candidate = floor.Position + Vector3.new(0, 3, 0) end
                if clear and workspace:Raycast(candidate, Vector3.new(0, 4, 0), rayParams) then clear = false end
            end
            if clear and (not ctx.questHealing or F.healingPointSafe(ctx,candidate))then
                local offset = candidate - point
                local lateral = threat.radius and offset.Magnitude or math.abs(offset:Dot(side))
                if not best or lateral > score then best, score = candidate, lateral end
            end
        end
        return best
    end
    F.escapePosition = escapePosition
    function F.dodge(ctx)
        local threat = F.observeThreat(ctx)
        if not threat or not safeToWork(ctx) then return false end
        if ctx.questHealing and F.healingMovementBlocked(ctx)then return false end
        local thread = coroutine.running()
        if (thread ~= ctx.defenseThread and thread ~= ctx.featureThread) or now() < (ctx.dodgeAt or 0) then return false end
        local destination = escapePosition(ctx, threat)
        if not destination then
            ctx.dodgeAt = now() + 0.1
            status('Ranged attack detected; no clear supported dodge'); return false
        end
        -- Cancel the current tween before taking movement ownership. The route and
        -- feature worker yield at their next check instead of writing over the dodge.
        ctx.defenseMoving = true
        movement.cancel(ctx)
        if ctx.currentChest then ctx.defenseAbort = true end
        if threat.source then ctx.attackCues[threat.source] = threat.token end
        ctx.pendingThreat = nil
        -- A cast cue and its ensuing shot need at most one immediate sidestep.
        ctx.dodgeAt = now() + 0.3
        ctx.root.CFrame = CFrame.new(destination)
        if ctx.root.AssemblyLinearVelocity then ctx.root.AssemblyLinearVelocity = Vector3.zero end
        ctx.dodgeUntil = now() + (threat.hold or 0.3)
        ctx.defenseMoving = nil
        status('Dodging ' .. threat.kind)
        return true
    end

    function F.startDefense(ctx)
        if ctx.defenseThread and coroutine.status(ctx.defenseThread) ~= 'dead' then return end
        ctx.defenseThread = task.spawn(function()
            ctx.defenseThread = coroutine.running()
            while ctx.active and api.owned() and s.farm == ctx do
                local ok, why = pcall(F.dodge, ctx)
                if not ok then
                    ctx.defenseMoving = nil
                    status('Defense recovering: ' .. tostring(why))
                end
                task.wait(ok and 0.03 or 0.3)
            end
        end)
    end

    local function packingReceipt(ctx, pending)
        if not pending or not pending.expected or not pending.inventory then return false end
        if pending.item and isRelic(pending.item)
            and inventoryCount(ctx, pending.expected) > (pending.beforeCount or 0) then return true end
        for _, tool in ipairs(tools(ctx)) do
            if not pending.inventory[tool] and id(tool) == pending.expected then return true end
        end
        if pending.item and armorSlot(pending.item) then
            for _, piece in ipairs(children(ctx.character)) do
                if not pending.inventory[piece] and piece:GetAttribute('ArmorName') == pending.expected
                    and piece:GetAttribute('ArmorType') then return true end
            end
        end
        return false
    end
    local function packForReturn(ctx, data)
        -- Waiting for replication never repeatedly equips the sack or moves its dropped item.
        if packingReceipt(ctx, ctx.sackDrop) then ctx.sackDrop, s.pendingSackDrop = nil, nil; return false end
        if ctx.sackDrop and ctx.sackDrop.interactIssued
            and (not ctx.sackDrop.interactSettled or ctx.sackDrop.interactAccepted) then
            status('Church packing waits for the original pickup receipt; that item is not moved or requested again')
            return false
        end
        if not findTool(ctx, 'ItemBag') then return true end
        local active, bagTool = bag(ctx)
        if not active or ctx.bagConfirmed ~= active or activeFor(ctx, bagTool) ~= active then
            if active and not ctx.bagObserver then status('Church packing: native sack quantity handler is not ready') end
            return false
        end
        if active.Size == 0 and not ctx.sackDrop then return true end
        local item = dropSackItem(ctx, active)
        if not item then return false end
        local pending = ctx.sackDrop
        pending.inventory = pending.inventory or {}
        if not pending.expected then
            pending.expected = id(item)
            pending.beforeCount = inventoryCount(ctx, pending.expected)
            for _, tool in ipairs(tools(ctx)) do pending.inventory[tool] = true end
            for _, piece in ipairs(children(ctx.character)) do pending.inventory[piece] = true end
        end
        local function confirmed() return packingReceipt(ctx, pending) end
        if confirmed() then ctx.sackDrop, s.pendingSackDrop = nil, nil; return false end
        -- Only actual hotbar replication is evidence that a sack item can be carried home.
        if not armorSlot(item) and hasRoom(ctx, item) or armorSlot(item) and armorBetter(ctx, item) then
            status('Packing a remaining sack item into the hotbar / equipped armor')
            if not pending.interactIssued then
                pending.interactAt = now()
                pending.interactIssued = interact(ctx, item, function(result)
                    pending.interactSettled, pending.interactAccepted = true, api.accepted(result)
                end)
                wait(ctx, 0.5)
            end
            if confirmed() then ctx.sackDrop, s.pendingSackDrop = nil, nil; return false end
            if pending.interactIssued and (not pending.interactSettled or pending.interactAccepted) then
                status('Church packing waits for the original pickup receipt; that item is not moved or requested again')
                return false
            end
        end
        if item.Parent then
            if readyAction(active) then store(ctx, active, item) end
            if not item.Parent then ctx.sackDrop = nil end
            ctx.packRetryAt = now() + 10
            status('Church return waiting: sack item cannot fit in the hotbar; no owned gear is dropped or sold')
        else
            status('Return waits for carried-item replication; no saved loot is assumed')
        end
        return false
    end
    local function savedChurchState()
        if api.Players.LocalPlayer:GetAttribute('SavedExitTeleportLocked') ~= true then return false end
        s.forceFresh = true
        saveStore:set('freshRun',true)
        status('Game saved-exit state confirmed; awaiting lobby transfer')
        return true
    end
    local function saveGearFrame()
        local ui = controller('UIController')
        if not ui or type(ui.GetFrame) ~= 'function' then return nil end
        local ok, frame = pcall(ui.GetFrame, ui, 'SaveGear')
        if not ok or not frame or not frame.Parent then return nil end
        if type(ui.GetUI) == 'function' then
            local read, root = pcall(ui.GetUI, ui)
            if not read or not root or root.Enabled == false then return nil end
        end
        return frame, ui
    end
    local function confirmChurch(ctx, prompt)
        if not F.extractionReady() or not F.isChurchSavePrompt(prompt) or prompt.Enabled == false then return false end
        if not tag(prompt, 'FramePrompt') then status('Church SaveGear prompt is waiting for its native FramePrompt tag'); return false end
        local point = position(prompt)
        local radius = tonumber(prompt.MaxActivationDistance) or 10
        if not point or radius <= 0 or api.Players.LocalPlayer.GameplayPaused == true
            or (ctx.root.Position - point).Magnitude > radius then
            status('Church confirmation waits for actual prompt range and loaded content'); return false
        end
        local frame, ui = saveGearFrame()
        if frame and frame.Visible ~= true and type(ui.ToggleFrame) == 'function' then
            -- Some executor helpers only deliver the server Triggered event.
            -- Reproduce the verified native local FramePrompt UI action too.
            pcall(ui.ToggleFrame, ui, 'SaveGear', true, false, true)
            wait(ctx, 0.1)
        end
        frame = saveGearFrame()
        if not frame or frame.Visible ~= true then
            status('Church SaveGear prompt found; waiting for its native confirmation frame'); return false
        end
        -- Revalidate after the UI yield; an option change or correction cannot
        -- turn a delayed local frame into permission for a save elsewhere.
        ctx.check()
        if not F.extractionReady() or not safeToWork(ctx) or not F.isChurchSavePrompt(prompt)
            or prompt.Enabled == false or api.Players.LocalPlayer.GameplayPaused == true
            or (ctx.root.Position - point).Magnitude > radius or s.churchSave then return false end
        local record = {started = now(), prompt = prompt, point = point}
        local player,character,humanoid,drill=api.Players.LocalPlayer,ctx.character,ctx.humanoid,ctx.drill
        local band=workspace:GetAttribute('InfiniteDepthOffsetMeters')
        s.churchSave = record
        local issued = api.request('church-save', 'PlayerService', 'SaveGear', api.pack(), function(result)
            record.settled, record.accepted = true, result[1] and not not result[2]
            record.retryAt = now() + 15
            if record.accepted then
                status('Church SaveGear accepted; awaiting the game saved-exit state')
            else status('Church SaveGear unconfirmed; native retry remains available after 15 seconds') end
        end,function()
            -- The transition request intentionally stops ctx before dispatch.
            -- Check its frozen living owner and native prompt, not ctx.active.
            local current=saveGearFrame();local drag=controller('DragController')
            return api.owned() and s.churchSave==record and F.extractionReady()
                and player==api.Players.LocalPlayer and player.Character==character and humanoid.Health>0
                and drill and drill.Parent and workspace:FindFirstChild('Drill')==drill
                and band==workspace:GetAttribute('InfiniteDepthOffsetMeters')
                and not s.teleporting and not s.awaiting and not s.departureAt
                and not workspace:GetAttribute('InCutScene') and not workspace:GetAttribute('InfiniteRebasing')
                and player.GameplayPaused~=true and not humanoid.SeatPart and not humanoid.Sit
                and not(drag and drag.LockedTarget) and player:GetAttribute('PlacingCraftedPlaceable')~=true
                and player:GetAttribute('SavedExitTeleportLocked')~=true
                and F.isChurchSavePrompt(prompt) and prompt.Enabled~=false and tag(prompt,'FramePrompt')
                and current==frame and current.Visible==true
                and position(prompt) and (ctx.root.Position-position(prompt)).Magnitude<=radius
        end)
        if not issued then s.churchSave = nil; status('Church save request not ready; retrying without a duplicate'); return false end
        record.issued = true
        status('Confirming church SaveGear; awaiting server reply')
        -- The transition request is owned by the supervisor, survives a worker
        -- replacement, and blocks overlapping lobby/start/save requests.
        return true
    end
    local function revisitChurch(ctx)
        if not F.extractionReady() or s.churchSave then return false end
        local band = tonumber(workspace:GetAttribute('InfiniteDepthOffsetMeters')) or 0
        local reload = ctx.churchReload
        if reload then
            if reload.band ~= band or now() >= reload.untilAt then
                ctx.churchReload = nil; release(ctx); return false
            end
            -- The remembered position is useful even after its Instance streams
            -- out. Returning from RequestStream does not prove the altar exists.
            movement.prefetchAt(ctx, reload.position)
            status('At a remembered church; waiting for the live SaveGear prompt')
            return true
        end
        if now() < (ctx.churchRevisitAt or 0) then return false end
        local best, distance
        for _, record in ipairs(s.churchMemories or {}) do
            if record.band == band and now() >= (record.retryAt or 0) then
                local d = (record.position - ctx.root.Position).Magnitude
                if not distance or d < distance then best, distance = record, d end
            end
        end
        if not best or not acquire(ctx, 'church-search') then return false end
        ctx.churchRevisitAt, best.retryAt = now() + 10, now() + 30
        status('Revisiting a church seen earlier; waiting for its SaveGear prompt to stream in')
        movement.prefetchAt(ctx, best.position)
        movement.hover(ctx)
        ctx.root.CFrame = CFrame.new(best.position + Vector3.new(0, 3, 3))
        if ctx.root.AssemblyLinearVelocity then ctx.root.AssemblyLinearVelocity = Vector3.zero end
        if ctx.root.AssemblyAngularVelocity then ctx.root.AssemblyAngularVelocity = Vector3.zero end
        ctx.churchReload = {position=best.position, band=band, untilAt=now()+8}
        wait(ctx, 0.5)
        ctx.indexAt, ctx.fullIndexAt = 0, 0
        return true
    end
    local function extract(ctx, data)
        if not F.extractionReady() then return false end
        if savedChurchState() then return true end
        if bring.blocksSave() then status('Church waits for background item ownership cleanup; chest work continues'); return false end
        local save = s.churchSave
        if save then
            if not save.settled then status('Church SaveGear reply pending; no duplicate save is sent'); return false end
            if save.accepted then status('Church save accepted; waiting for server exit confirmation'); return false end
            if now() < (save.retryAt or 0) then return false end
            s.churchSave = nil
        end
        local prompt = nearest(ctx, data.church, function(item)
            return (not s.questChurchExit or F.isChurchSavePrompt(item)) and item.Enabled ~= false and F.chestFallbackAllowed(item)
        end)
        if not prompt then
            if revisitChurch(ctx) then return true end
            status(s.runExhausted and 'No church SaveGear prompt loaded; available tunnel exhausted, waiting for server content'
                or s.questChurchExit and s.questChurchExit.reason..'; looking for native church SaveGear prompts'
                or 'Minimum time met; looking for native church SaveGear prompts')
            if now() >= (ctx.churchNoticeAt or 0) then
                ctx.churchNoticeAt = now() + 30
                print('[Earth Church] No eligible prompt loaded; remembered churches=' .. tostring(#(s.churchMemories or {}))
                    .. ', route exhausted=' .. tostring(s.runExhausted == true) .. '. Ordinary return does not save loot.')
            end
            return false
        end
        if ctx.churchReload then ctx.churchReload=nil; release(ctx) end
        if now() < (ctx.extractAt or 0) or now() < (ctx.packRetryAt or 0) then return false end
        if s.lootRequest then status('Church return waits for the outstanding item reply; chest work continues'); return false end
        if not settleRareDrop(ctx) then status('Church return waits for the Rare Shard drop receipt; chest work continues'); return false end
        if not settleGear(ctx) then status('Church return waits briefly for the last smart pickup inventory receipt'); return false end
        if not acquire(ctx, 'extract') then return false end
        -- A hard/idle deadline saves the current hotbar, armor and relic stacks.
        -- Sack inspection is optional preparation, not a native SaveGear
        -- prerequisite; it must not turn a forced exit into an endless bag wait.
        if not s.questChurchExit and not packForReturn(ctx, data) then
            ctx.packRetryAt = math.max(ctx.packRetryAt or 0, now() + 1)
            release(ctx); return true
        end
        if not F.extractionReady() then release(ctx); return false end
        status('Using church return; awaiting the game saved-exit state')
        -- Set the attempt before dispatch: a synchronous departure can happen during the prompt.
        ctx.extractAt = now() + 15
        s.extractionAttempt, s.extractionAttemptAt = true, now()
        local fired = firePrompt(ctx, prompt)
        if fired then
            if F.isChurchSavePrompt(prompt) and not savedChurchState() then
                confirmChurch(ctx, prompt)
            end
            local deadline = now() + 1
            while safeToWork(ctx) and now() < deadline and api.Players.LocalPlayer:GetAttribute('SavedExitTeleportLocked') ~= true do wait(ctx, 0.05) end
            if not savedChurchState() and not s.churchSave and not F.isChurchSavePrompt(prompt) then
                status('Church prompt sent; save is unconfirmed, checking again after the retry interval')
            end
        else
            s.extractionAttempt, s.extractionAttemptAt = nil, nil
        end
        release(ctx); return true
    end
    local function discover(ctx)
        if not F.extractionReady() or not (s.runExhausted or s.questChurchExit) or now() < (ctx.discoveryAt or 0) then return false end
        movement.initializeRoute(ctx)
        local checkpoint = s.routeScanX or (ctx.root.CFrame.Position or ctx.root.Position).X
        local limit = ctx.scanEnd or 36000
        if checkpoint >= limit then return false end
        if not acquire(ctx, 'discovery') then return false end
        ctx.discoveryAt = now() + 0.5
        F.travelRoute(ctx, math.min(checkpoint + 150, limit))
        wait(ctx, 0.15)
        release(ctx); return true
    end
    function F.cleanup(ctx)
        if not ctx.active then
            for manager in pairs(ctx.cueConnections or {})do disconnectCue(ctx,manager)end
            ctx.cueManagers,ctx.watcherDiscovery=nil,nil
        end
        ctx.churchReload=nil
        if quest then pcall(quest.cleanup,ctx) end
        pcall(bring.cleanup,ctx)
        pcall(movement.cleanup,ctx)
        if not ctx.active and ctx.defenseThread and ctx.defenseThread ~= coroutine.running() then pcall(task.cancel, ctx.defenseThread) end
        pcall(release,ctx); ctx.combatTarget = nil
        pcall(F.restoreWeaponSignal,ctx)
        pcall(function() if ctx.dragEdit and ctx.dragEdit.controller.ResolveLockedTargetPosition == ctx.dragEdit.wrapper then
            ctx.dragEdit.controller.ResolveLockedTargetPosition = ctx.dragEdit.original
        end end)
        pcall(function() if ctx.dragController and ctx.dragController.LockedTarget == ctx.draggedItem then ctx.dragController:ReleaseLockedTarget() end end)
        for prompt, duration in pairs(ctx.instantPrompts or {}) do pcall(function() if prompt.Parent then prompt.HoldDuration = duration end end) end
        local camera = ctx.watcherCamera
        pcall(function() if camera and camera.CFrame == ctx.watcherFrame and ctx.cameraBeforeWatcher then camera.CFrame = ctx.cameraBeforeWatcher end end)
        if ctx.watcherBinding and not ctx.active then pcall(function() api.RunService:UnbindFromRenderStep(ctx.watcherBinding) end) end
        ctx.swingEdit, ctx.dragEdit, ctx.instantPrompts = nil, nil, nil
        pcall(function() if ctx.bagObserver and ctx.bagObserver.controller.UpdateSackSize == ctx.bagObserver.wrapper then
            ctx.bagObserver.controller.UpdateSackSize = ctx.bagObserver.original
        end end)
        ctx.bagObserver = nil
        s.pendingSackDrop = ctx.sackDrop
    end
    function F.snapshotPulse(ctx)
        local player=api.Players.LocalPlayer
        local function current()
            return api.owned() and ctx and ctx.active and s.farm==ctx and player and player.Character==ctx.character
                and ctx.humanoid and ctx.humanoid.Parent==ctx.character and ctx.humanoid.Health>0
        end
        if not current()then return false end
        local at=now();if not finite(at)then return false end
        local ledger=s.runtimeSnapshots
        if type(ledger)~='table' or ledger.character~=ctx.character or ledger.job~=game.JobId then
            ledger={character=ctx.character,job=game.JobId,count=0};s.runtimeSnapshots=ledger
        end
        if not finite(ledger.count) or ledger.count<0 or ledger.count>3 or ledger.count%1~=0 then ledger.count=3 end
        if ledger.busy or ledger.count>=3 or ledger.lastAt~=nil and not finite(ledger.lastAt)then return false end
        local health,maximum=ctx.humanoid.Health,ctx.humanoid.MaxHealth
        local critical=finite(health) and finite(maximum) and maximum>0 and health/maximum<.3
        if finite(health) and finite(maximum) and maximum>0 and finite(ledger.lastHealth)
            and health<math.min(ledger.lastHealth,maximum)then ledger.lastDamageAt=at end
        local injured=finite(health) and finite(maximum) and maximum>0 and health/maximum<.7
        local recentDamage=finite(ledger.lastDamageAt) and at>=ledger.lastDamageAt and at-ledger.lastDamageAt<=30
        local waitTarget=ctx.questCombatWait and ctx.questCombatWait.target
        local combatNeed=F.enemyAlive(waitTarget) or F.enemyAlive(ctx.combatTarget)
        local equipmentNeeded=not ctx.questDriving and not ctx.questSeating and not ctx.humanoid.SeatPart and not ctx.humanoid.Sit
            and (ctx.questMining or combatNeed or injured or recentDamage)
        local native=controller('ToolController');local active=native and native.ActiveTool
        local nativeCurrent=active and not active._Destroyed and active.Tool and active.Tool.Parent==ctx.character
            and (native.ServerEquipId==nil or active.Tool:GetAttribute('ServerToolEquipId')==native.ServerEquipId)
        local equipmentWait=ctx.questMining and not(nativeCurrent and type(active.Swing)=='function'
            and (attr(active.Tool,'Class')=='Pickaxe' or attr(active.Tool,'Class')=='Champions_Hammer')) or false
        local backpack=player:FindFirstChild('Backpack');local inspected=0
        for tool,receipt in pairs(s.equipRecords or {})do
            inspected=inspected+1;if inspected>16 then break end
            local class=attr(tool,'Class')
            local relevant=ctx.questHealing and class=='Medkit' or not ctx.questHealing
                and (not ctx.questMining or class=='Pickaxe' or class=='Champions_Hammer')
            if tool.Parent and (tool.Parent==ctx.character or tool.Parent==backpack) and type(receipt)=='table'
                and relevant and (receipt.pending or receipt.uncertain or receipt.accepted) and not activeFor(ctx,tool)then equipmentWait=true;break end
        end
        equipmentWait=equipmentWait and equipmentNeeded
        if equipmentWait then
            if not finite(ledger.equipmentSince) or ledger.equipmentSince>at then ledger.equipmentSince=at end
        else ledger.equipmentSince=nil end
        if ctx.questHealing then
            if not finite(ledger.healingSince) or finite(health) and finite(ledger.lastHealth) and health>ledger.lastHealth then ledger.healingSince=at end
        else ledger.healingSince=nil end
        ledger.lastHealth=finite(health) and health or nil
        local function age(value)return finite(value) and at>=value and at-value or nil end
        local reason=critical and 'critical-health'
            or equipmentWait and (age(ledger.equipmentSince) or 0)>=15 and 'equipment-wait'
            or ctx.questHealing and (age(ledger.healingSince) or 0)>=15 and 'healing-stall'
        if not reason or finite(ledger.lastAt) and at-ledger.lastAt<60 then return false end
        -- Reserve before collecting/printing. A failed or re-entrant diagnostic
        -- must neither spam nor change any gameplay ownership or request lane.
        ledger.count=ledger.count+1;ledger.lastAt=at;ledger.busy=true
        local ok=pcall(function()
            local json=getService('HttpService');if not json or type(json.JSONEncode)~='function'then return end
            local classes={Sword=true,Pickaxe=true,Champions_Hammer=true,Medkit=true,Blueprint=true,
                Revolver=true,Rifle=true,Shotgun=true,BlackholeGun=true,ItemBag=true}
            local replyTypes={['nil']=true,boolean=true,number=true,string=true,table=true,['function']=true,
                thread=true,userdata=true,Instance=true,Vector3=true,CFrame=true}
            local function boolean(value)return not not value end
            local function number(value)return finite(value) and value or nil end
            local function scope(instance)
                if typeof(instance)~='Instance'then return 'absent' end
                if instance.Parent==ctx.character then return 'character' end
                if instance.Parent==backpack then return 'backpack' end
                if instance.Parent==nil then return 'detached' end
                if instance:IsDescendantOf(ctx.character)then return 'inside-character' end
                if workspace.CurrentCamera and instance:IsDescendantOf(workspace.CurrentCamera)then return 'camera' end
                return 'other'
            end
            local function proof(instance)
                local valid=typeof(instance)=='Instance'
                local proxyId;if valid then proxyId=instance:GetAttribute('ServerToolEquipId')end
                local currentId=native and native.ServerEquipId
                local class=valid and attr(instance,'Class') or nil
                return {scope=scope(instance),class=classes[class] and class or 'other',has_proxy_id=proxyId~=nil,
                    has_controller_id=currentId~=nil,ids_both_known=proxyId~=nil and currentId~=nil,
                    ids_match=proxyId~=nil and currentId~=nil and proxyId==currentId,
                    native_tool_attribute=valid and attr(instance,'Tool')==true or false}
            end
            local inventory,truncated={},false
            local characterTruncated,backpackTruncated=false,false
            local anyCharacterTool,anyCharacterProxy=false,false
            for _,container in ipairs({ctx.character,backpack})do
                local scanned=0
                for _,item in ipairs(children(container))do
                    scanned=scanned+1
                    if scanned>64 then
                        truncated=true
                        if container==ctx.character then characterTruncated=true else backpackTruncated=true end
                        break
                    end
                    if item.Parent==container then
                        local isTool=item:IsA('Tool');local isProxy=item:IsA('Model') and attr(item,'Tool')==true
                        if container==ctx.character then anyCharacterTool=anyCharacterTool or isTool;anyCharacterProxy=anyCharacterProxy or isProxy end
                        if isTool or isProxy then
                            if #inventory>=16 then truncated=true
                            else
                                local entry=proof(item)
                                entry.is_active_tool=active and active.Tool==item or false
                                entry.is_display_tool=active and active.DisplayTool==item or false
                                local receipt=s.equipRecords and s.equipRecords[item]
                                if type(receipt)=='table'then
                                    entry.request={pending=receipt.pending==true,uncertain=receipt.uncertain==true,
                                        accepted=receipt.accepted==true,rejected=receipt.rejected==true,not_dispatched=receipt.notDispatched==true,
                                        recovery_used=receipt.emptyRecoveryUsed==true,issued_age=age(receipt.issuedAt),settled_age=age(receipt.settledAt),
                                        empty_age=type(receipt.emptyRecovery)=='table' and age(receipt.emptyRecovery.started) or nil,
                                        reply_type=replyTypes[receipt.replyType] and receipt.replyType or nil,
                                        reply_arity=number(receipt.replyArity),previous_server_id_known=receipt.previousServerEquipId~=nil,
                                        server_id_changed=receipt.previousServerEquipId~=nil and native~=nil and native.ServerEquipId~=nil
                                            and receipt.previousServerEquipId~=native.ServerEquipId}
                                end
                                inventory[#inventory+1]=entry
                            end
                        end
                    end
                end
            end
            local calls=quest and quest.calls or s.questCalls or {}
            local requestSlots,callSlots={},{}
            for _,key in ipairs({'request','equipmentRequest','lootRequest','lootQuery','upgradeRequest','awaiting','teleporting','departureAt'})do requestSlots[key]=boolean(s[key])end
            for _,key in ipairs({'drag','cash','drive','shop','place','placementCancel','craft','upgrade','medicalDrop','inventoryDrop'})do callSlots[key]=boolean(calls[key])end
            local scene=controller('CutSceneController');local placement=controller('PlaceablePlacementController');local drag=controller('DragController')
            local function output(section,value)
                if not current()then return end
                local prefix='[DTEC Runtime Snapshot] '..section..' '
                local encoded=json:JSONEncode(value)
                if type(encoded)~='string' or #prefix+#encoded>=900 then encoded='{"truncated":true}'end
                if not current()then return end
                print(prefix..encoded)
            end
            output('core',{revision=number(s.revision),trigger=reason,snapshot=ledger.count,health=number(health),max_health=number(maximum),
                tool_controller_present=native~=nil,native_handler_present=active~=nil,native_handler_destroyed=active and active._Destroyed==true or false,
                native_handler_current=boolean(nativeCurrent),native_equip_version=number(native and native.EquipVersion),
                active_swing=active and type(active.Swing)=='function' or false,active_consume=active and type(active.Consume)=='function' or false,
                equipment_wait_age=age(ledger.equipmentSince),healing_wait_age=age(ledger.healingSince)})
            output('identity',{active_tool=proof(active and active.Tool),display_scope=scope(active and active.DisplayTool),inventory_truncated=truncated,
                character_scan_truncated=characterTruncated,backpack_scan_truncated=backpackTruncated,
                any_character_tool=anyCharacterTool,any_character_proxy=anyCharacterProxy})
            output('phase',{healing=boolean(ctx.questHealing),mining=boolean(ctx.questMining),driving=boolean(ctx.questDriving),seating=boolean(ctx.questSeating),
                seated=boolean(ctx.humanoid.SeatPart or ctx.humanoid.Sit),feature_hold=boolean(ctx.featureHold),equipment_lock=boolean(ctx.bringEquipmentLock),
                equipment_lock_matches_bring_delivery=boolean(ctx.bringEquipmentLock and s.bringDelivery and ctx.bringEquipmentLock==s.bringDelivery),
                equipment_lock_matches_quest_delivery=boolean(ctx.bringEquipmentLock and s.questDelivery and ctx.bringEquipmentLock==s.questDelivery),
                consume_observation=boolean(ctx.questHealAttempt),medical_drop_reserved=boolean(s.questMedicalDrop),native_gate_motion=boolean(ctx.nativeGateMotion),
                native_mine_entry=boolean(ctx.questMineEntry),delivery_reserved=boolean(s.questDelivery),cash_reserved=boolean(s.questCashJob),bring_delivery_reserved=boolean(s.bringDelivery)})
            output('guards',{manual_drag=drag and boolean(drag.LockedTarget) or false,native_placement=placement and boolean(placement.Active) or false,
                player_placing=player:GetAttribute('PlacingCraftedPlaceable')==true,cutscene=boolean(workspace:GetAttribute('InCutScene')
                    or scene and (scene.CurrentCutScene or scene.AbortingCutScene)),rebasing=boolean(workspace:GetAttribute('InfiniteRebasing')),
                gameplay_paused=player.GameplayPaused==true,recovering=boolean(ctx.questRecovering),placement=boolean(ctx.questPlacement),
                preview_cancel=boolean(ctx.questPreviewCancel),potion=boolean(ctx.questPotionUsing),swing_edit=boolean(ctx.swingEdit),
                current_chest=boolean(ctx.currentChest),defense_moving=boolean(ctx.defenseMoving),dodge=at<(ctx.dodgeUntil or 0)})
            output('requests',requestSlots);output('calls',callSlots)
            local delivery=type(s.questDelivery)=='table' and s.questDelivery or nil
            local stages={request=true,placed=true,pickup=true,receipt=true,empty=true,['shop-request']=true,
                ['shop-drop']=true,quote=true,wallet=true,recheck=true,buy=true,['purchase-confirm']=true}
            local kinds={supply=true,fuel=true,sale=true,gold=true,smelt=true,shred=true}
            output('delivery',{route_parked=ctx.routeParked==true,quest_owns=boolean(ctx.questOwns),present=delivery~=nil,
                current_context=delivery and delivery.ctx==ctx or false,age=delivery and age(delivery.started) or nil,
                kind=delivery and kinds[delivery.kind] and delivery.kind or nil,
                stage=delivery and stages[delivery.stage] and delivery.stage or nil,
                pending=delivery and boolean(delivery.pending) or false,owns=delivery and boolean(delivery.owns) or false,
                shop=delivery and boolean(delivery.shop) or false,stock_placed=delivery and boolean(delivery.stockPlaced) or false,
                buy_sent=delivery and boolean(delivery.buySent) or false,healing_supply=delivery and boolean(delivery.healingSupply) or false,
                cancelled=delivery and boolean(delivery.cancelled) or false,movement_released=delivery and boolean(delivery.movementReleased) or false,
                release_failed=delivery and boolean(delivery.releaseFailed) or false,
                drag_reserved=boolean(calls.drag),shop_reserved=boolean(calls.shop),wallet_reserved=boolean(calls.wallet),
                healing_wallet_reserved=boolean(calls.healingWallet),wallet=number(s.questWallet)})
            for index,entry in ipairs(inventory)do output('inventory-'..index,entry)end
        end)
        ledger.busy=nil
        return ok
    end
    function F.watchdog(ctx)
        F.checkQuestExit(ctx)
        if ctx.active and quest then
            pcall(quest.drillSupport.upgradePulse,ctx)
            if quest.special and quest.special.observe then pcall(quest.special.observe,ctx,nil)end
            if quest.drillSupport and quest.drillSupport.pruneDoorObservers then pcall(quest.drillSupport.pruneDoorObservers,ctx)end
        end
        if ctx.active then F.bindOreBreaks(ctx) end
        if ctx.active then F.startDefense(ctx) end
        if not ctx.active or not ctx.initialized or not ctx.featureThread then return end
        local worker = ctx.featureThread
        local dead = coroutine.status(worker) == 'dead'
        local ownsMovement=ctx.featureHold or ctx.questOwns or ctx.questChestLease or ctx.worldReader==worker
        local pulse=ctx.featurePulse or now()
        if ctx.worldReader==worker and ctx.worldReading then pulse=math.max(pulse,ctx.worldReadPulse or pulse)end
        if not dead and (not ownsMovement or now() - pulse < 20) then return end
        if not dead then
            pcall(task.cancel, worker)
            if coroutine.status(worker) ~= 'dead' then
                status('Stalled optional worker could not be cancelled; waiting to avoid duplicate workers'); return
            end
        end
        if ctx.lootThread == worker then
            if ctx.currentChest then ctx.currentChest.retryAt = now() + 30 end
            ctx.currentChest, ctx.lootThread, ctx.defenseAbort = nil, nil, nil
        end
        if ctx.worldReader==worker then ctx.worldReading,ctx.worldReader=nil,nil end
        ctx.questChestLease=nil;ctx.questChestTaking=nil
        F.cleanup(ctx)
        ctx.featureThread = nil
        ctx.featureRecoveries = (ctx.featureRecoveries or 0) + 1
        status('Recovered optional worker; preserving chest route')
        F.runWorker(ctx)
    end
    function F.start(ctx)
        F.bindOreBreaks(ctx)
        s.equipRecords = s.equipRecords or setmetatable({}, { __mode = 'k' })
        s.lootStarted = s.lootStarted or now()
        s.sackSize, s.sackCapacity = nil, nil
        ctx.itemRetry,ctx.damageChecks,ctx.pickaxeTargets=setmetatable({}, {__mode='k'}),
            setmetatable({}, {__mode='k'}),setmetatable({}, {__mode='k'})
        ctx.sackDrop = s.pendingSackDrop
        if type(workspace.GetAttributeChangedSignal) == 'function' then
            ctx.connect(workspace:GetAttributeChangedSignal('InfiniteRebasing'), function()
                if cfg.lootExtract or s.lootItemMemory then bring.worldChanged(ctx) end
            end)
        end
        if workspace.DescendantAdded then
            ctx.connect(workspace.DescendantAdded, function(item)
                if cfg.lootExtract then bring.observe(ctx, item) end
                if item:IsA('ProximityPrompt') and (cfg.lootExtract or cfg.classQuest or s.questChurchExit) then
                    ctx.indexPending = ctx.indexPending or setmetatable({}, {__mode='k'}); ctx.indexPending[item] = true
                    if F.isChurchSavePrompt(item) then rememberChurch(ctx, item) end
                end
            end)
        end
        if type(api.RunService.BindToRenderStep) == 'function' then
            ctx.watcherBinding = 'EarthAutofarmWatcher_' .. tostring(api.Players.LocalPlayer.UserId)
            api.RunService:BindToRenderStep(ctx.watcherBinding, Enum.RenderPriority.Last.Value - 1, function()
                if ctx.active and api.owned() and not s.teleporting and not workspace:GetAttribute('InCutScene') then pcall(F.watcher, ctx) end
            end)
        end
        F.startDefense(ctx)
        F.runWorker(ctx)
    end
    function F.runWorker(ctx)
        if ctx.featureThread and coroutine.status(ctx.featureThread) ~= 'dead' then return end
        ctx.featurePulse = now()
        ctx.featureThread = task.spawn(function()
            ctx.featureThread = coroutine.running()
            while ctx.active and api.owned() and s.farm == ctx do
                ctx.featurePulse = now()
                local ok, why = pcall(function()
                    F.checkQuestExit(ctx)
                    F.observeChurch(ctx)
                    ctx.check()
                    quest.rewards.step(ctx)
                    -- Progress delivery and stale ownership cleanup even while the
                    -- optional switch is OFF or a transition prevents new actions.
                    bring.step(ctx, false)
                    if quest.step(ctx) then
                        -- Native bringing is independent of quest movement. Useful
                        -- loot can arrive beside a fighting character without a trip.
                        if cfg.lootExtract and not quest.special.fastPlacement(s.questPlan) and s.itemDatabase and ctx.questCombat and not ctx.questDriving and not s.questDelivery
                            and not s.questCashJob and safeToWork(ctx) then upgradeGear(ctx) end
                        return
                    end
                    F.watcher(ctx)
                    if not safeToWork(ctx) then release(ctx); return end
                    if not ctx.defenseThread and F.dodge(ctx) then return end
                    if ctx.dodgeUntil and now() < ctx.dodgeUntil then return end
                    if ctx.pendantAttempt and now() - ctx.pendantAttempt.started < 5 then release(ctx); return end
                    if not cfg.lootExtract and not s.questChurchExit then release(ctx); return end
                    F.observeChurch(ctx)
                    if not s.itemDatabase then
                        status('Waiting for item definitions before smart loot / church packing'); return
                    end
                    -- Church return takes priority as soon as the minimum time is met.
                    if F.extractionReady() then
                        local data = index(ctx)
                        if extract(ctx, data) then return end
                        if not s.churchSave and discover(ctx) then return end
                    elseif F.extractionEnabled() and s.runExhausted then
                        status(string.format('Chest route complete; church extraction unlocks in %.0fs', cfg.minutes * 60 - (now() - s.lootStarted)))
                    end
                    if cfg.lootExtract and not quest.special.fastPlacement(s.questPlan)then
                        upgradeGear(ctx)
                    end
                end)
                if not ok then
                    F.cleanup(ctx)
                    if tostring(why):find('__CHESTFARM_CANCELLED', 1, true) then return end
                    if tostring(why):find('__EARTH_DEFENSE_RETRY', 1, true)
                        or tostring(why):find('__EARTH_MODE_CHANGED', 1, true) then task.wait(0.05)
                    else status('Optional worker recovering: ' .. tostring(why)); task.wait(2) end
                else task.wait(0.1) end
            end
            F.cleanup(ctx)
        end)
    end
    F.validate, F.armorBetter, F.weaponBetter, F.findTool = validate, armorBetter, weaponBetter, findTool
    F.equip, F.extract, F.upgradeGear = equip, extract, upgradeGear
    F.index = index
    persist()
    return F
end
]=====]
    local function startCombat(ctx, player, model, humanoid, root)
        if ctx.combatThread then return end
        s.equipRecords = s.equipRecords or setmetatable({}, { __mode = "k" })
        local combat = { equipRecords = s.equipRecords, nextAttack = 0, pulse=now() }
        ctx.combat = combat
        local function notice(message, ready)
            if ctx.combatTarget then
                ctx.questCombatWait = not ready and {target=ctx.combatTarget,reason=message} or nil
            end
            if combat.notice ~= message then combat.notice = message; print("[ChestFarm Combat] " .. message) end
        end
        local function attribute(tool, name)
            if not s.itemDatabase or type(s.itemDatabase.GetAttribute) ~= "function" then return nil end
            local ok, value = pcall(s.itemDatabase.GetAttribute, tool, name)
            if ok and value ~= nil then return value end
            -- Backpack templates omit some stats; use the verified item definition.
            if type(s.itemDatabase.GetId) == "function" then
                local found, id = pcall(s.itemDatabase.GetId, tool)
                if found and id then
                    local read, fallback = pcall(s.itemDatabase.GetAttribute, id, name)
                    if read then return fallback end
                end
            end
        end
        local function weapon(tool)
            if not tool:IsA("Tool") and not (tool:IsA("Model") and attribute(tool, "Tool") == true) then return nil end
            if features and features.canSelectEquipment and not features.canSelectEquipment(ctx,tool)then return nil end
            local id
            if s.itemDatabase and type(s.itemDatabase.GetId) == "function" then
                local ok, value = pcall(s.itemDatabase.GetId, tool)
                if ok then id = value end
            end
            id = id or tool.Name
            local class = attribute(tool, "Class")
            if id == "Sword_Executioner" then class = "Sword" end
            if id == "Web_Revolver" then class = "Revolver" end
            if id == "Champions_Hammer" then class = "Champions_Hammer" end
            local melee = class == "Sword" or class == "Pickaxe" or class == "Champions_Hammer"
            local gun = class == "Revolver" or class == "Rifle" or class == "Shotgun"
            if not melee and not gun then return nil end
            local damage = tonumber(attribute(tool, "Damage")) or 0
            local speed = tonumber(attribute(tool, melee and "AttackSpeed" or "FireRate")) or 0
            local priority = class == "Pickaxe" and 1 or (melee and 3 or 2)
            if gun then
                local reserve = tonumber(player:GetAttribute(class == "Revolver" and "Pistol_Ammo" or class .. "_Ammo")) or 0
                if (tonumber(attribute(tool, "Ammo")) or 0) <= 0 and reserve <= 0 then priority = 0 end
            end
            return { tool = tool, id = id, class = class, melee = melee, priority = priority,
                score = damage * math.max(speed, 0.01), range = tonumber(attribute(tool, "Range")) }
        end
        local function bestWeapon()
            local best
            for _, container in ipairs({ model, child(player, "Backpack") }) do
                if container then
                    for _, tool in ipairs(container:GetChildren()) do
                        local candidate = weapon(tool)
                        if candidate and (not best or candidate.priority > best.priority
                            or (candidate.priority == best.priority and candidate.score > best.score)
                            or (candidate.priority == best.priority and candidate.score == best.score and candidate.tool.Parent == model)) then
                            best = candidate
                        end
                    end
                end
            end
            return best
        end
        local function nearestHostile(radius, class)
            local npcFolder = workspace:FindFirstChild("Npc")
            local target, targetPart, distance
            for _, npc in ipairs(features and features.enemies() or (npcFolder and npcFolder:GetChildren() or {})) do
                if features.enemyAlive(npc) and features.questTargetAllowed(ctx,npc)
                    and (class~='Sword' or features.swordTargetAllowed(npc)) then
                    local health = npc:FindFirstChildOfClass("Humanoid")
                    local living = health and health.Health > 0 or (tonumber(npc:GetAttribute("FuelLeechHealth")) or 0) > 0
                    local part = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("RootPart") or npc.PrimaryPart
                    if living and part and part.Parent then
                        local separation = (part.Position - root.Position).Magnitude
                        if separation <= radius and (not distance or separation < distance) then
                            target, targetPart, distance = npc, part, separation
                        end
                    end
                end
            end
            return target, targetPart, distance
        end
        function combat.restoreAim()
            local edit = combat.aimEdit
            combat.aimEdit = nil
            if edit then pcall(function()
                if edit.controller.GetAimRay == edit.wrapper then edit.controller.GetAimRay = edit.original end
            end) end
        end
        local function step()
            ctx.check()
            if features then pcall(features.watcher, ctx) end
            if features then
                local ok, threat = pcall(features.observeThreat, ctx)
                if ok and threat then notice("Dodging a current projectile cue"); combat.holdUntil, combat.burstUntil = nil, nil; return end
            end
            local scene = controller("CutSceneController")
            if workspace:GetAttribute("InCutScene") or workspace:GetAttribute("InfiniteRebasing")
                or (scene and (scene.CurrentCutScene or scene.AbortingCutScene))
                or s.request or s.awaiting or s.departureAt
                or ctx.featureHold then
                notice(ctx.featureHold and "Waiting for the current item operation" or "Waiting for the current game transition")
                combat.holdUntil, combat.burstUntil = nil, nil
                return
            end
            if ctx.dodgeUntil and now() < ctx.dodgeUntil then notice("Finishing the current dodge"); return end
            if features and features.dodge(ctx) then notice("Dodging a current attack"); return end
            if features and features.quest.pauseCombat(ctx)then notice("Combat paused by healing, mining or another quest action"); return end
            local _, _, questCombatRequired = features.quest.required(ctx)
            if features and not questCombatRequired and not ctx.questCombat and not ctx.bringEquipmentLock and features.usePendant(ctx) then return end
            if now() >= (combat.inventoryAt or 0) or not combat.selected
                or not combat.selected.tool.Parent or (combat.selected.tool.Parent ~= model and combat.selected.tool.Parent ~= child(player, "Backpack")) then
                combat.selected, combat.inventoryAt = bestWeapon(), now() + 1
            end
            local selected = combat.selected
            local questTool, questStrict = features.questPreferred(ctx)
            if questStrict then selected = questTool and weapon(questTool) or nil end
            -- Native armor compatibility precedes an exact kill requirement.
            -- Only loaded living targets already in local melee reach can
            -- trigger this in-place defense; it never starts a distant chase.
            local armorTarget,armorDistance
            if features and not ctx.questParasiteTarget then
                local range=selected and selected.melee and selected.range or 13
                range=type(range)=='number' and math.max(0,math.min(45,range)) or 13
                for _,npc in ipairs(features.enemies())do
                    local p=npc.PrimaryPart or npc:FindFirstChild('HumanoidRootPart') or npc:FindFirstChild('RootPart')
                    if p and features.enemyAlive(npc) and features.questTargetAllowed(ctx,npc)
                        and features.weaponClass(ctx,npc)then
                        local distance=(p.Position-root.Position).Magnitude
                        if distance<=range and (not armorDistance or distance<armorDistance)then armorTarget,armorDistance=npc,distance end
                    end
                end
            end
            local target=armorTarget or ctx.combatTarget or combat.target
            local preferClass = features and features.weaponClass(ctx,target)
            if preferClass then
                if armorTarget then ctx.combatTarget=armorTarget end
                local preferred = features.findTool(ctx, preferClass)
                if questStrict then
                    local required=features.questPreferred(ctx)
                    selected=required and weapon(required) or nil
                elseif preferred then selected = weapon(preferred); combat.selected = selected
                else selected=nil end
            end
            if not selected then notice("No supported weapon found; checking inventory automatically"); return end
            if selected.priority == 0 then notice("Weapon has no available ammunition; checking for alternatives"); return end
            local c = controller("ToolController")
            if not c then notice("Waiting for the native ToolController"); return end
            local active = c.ActiveTool
            local currentActive=active and not active._Destroyed and active.Tool and active.Tool.Parent==model
                and (c.ServerEquipId==nil or active.Tool:GetAttribute('ServerToolEquipId')==c.ServerEquipId)
            local ready = currentActive
                and (active.Tool == selected.tool or (active.DisplayTool == selected.tool))
            -- The native equipped representation can be a separate model named item+UserId.
            if not ready and currentActive then
                ready = active.Tool.Name == selected.id or active.Tool.Name == selected.id .. tostring(player.UserId)
            end
            if not ready then
                if ctx.bringEquipmentLock then return end -- Native tool changes cancel drag ownership.
                -- A weapon change destroys the current native handler. Do not
                -- take medical/mining equipment merely to prepare idle combat.
                -- Inspect actual permitted hit geometry before requesting equip.
                if ctx.questHealing or ctx.questMining then
                    local nearby
                    if selected.melee then
                        local range=features.weaponRange(nil,selected.tool)
                        nearby=features.auraTargets(ctx,{Tool=selected.tool,DisplayTool=selected.tool,Range=range})
                    else
                        local npc=nearestHostile(80,selected.class)
                        nearby=npc and {npc} or {}
                    end
                    if not nearby or #nearby==0 then
                        notice("No permitted hostile inside the native weapon range")
                        combat.holdUntil,combat.burstUntil,combat.target=nil,nil,nil
                        return
                    end
                end
                -- Share the receipt-aware equip path with mining and healing.
                -- It can recover a superseded accepted request only after a
                -- different native tool is confirmed and this one is absent.
                features.equip(ctx, selected.tool)
                notice(selected.tool.Parent == model and "Waiting for the equipped weapon's native attack handler"
                    or "Equipping " .. selected.tool.Name .. "; waiting for its native handler")
                return
            end
            combat.equipRecords[selected.tool] = nil
            if now() < combat.nextAttack then return end
            if humanoid.SeatPart or humanoid.Sit then notice("Leaving the seat before attacking"); return end
            local radius = selected.melee and features.weaponRange(active, selected.tool) or 80
            local auraTargets = selected.melee and features and features.auraTargets(ctx, active)
            local target, part = nearestHostile(radius, selected.class)
            if ctx.combatTarget and features.enemyAlive(ctx.combatTarget) and features.questTargetAllowed(ctx,ctx.combatTarget)
                and (selected.class~='Sword' or features.swordTargetAllowed(ctx.combatTarget)) then
                local desiredPart = ctx.combatTarget:FindFirstChild("HumanoidRootPart") or ctx.combatTarget.PrimaryPart
                if desiredPart and (desiredPart.Position - root.Position).Magnitude <= radius then target, part = ctx.combatTarget, desiredPart end
            end
            if not target and (not auraTargets or #auraTargets == 0) then
                notice("No permitted hostile inside the native weapon range")
                combat.holdUntil, combat.burstUntil, combat.target = nil, nil, nil; return
            end
            if type(active.CanUseAction) == "function" and not active:CanUseAction() then notice("Native weapon action is not ready"); return end
            local cooldown = math.max(tonumber(active.LastSwing) or 0, tonumber(active.AttackLockedUntil) or 0, tonumber(active.Debounce) or 0)
            if now() < cooldown then notice("Waiting for the native weapon cooldown"); combat.nextAttack = cooldown; return end
            local method = selected.melee and active.Swing or active.Shoot
            if not selected.melee and type(method) ~= "function" then notice("Waiting for a supported native attack method"); return end
            if not selected.melee then
                if ctx.watcher and not features.watcherVisible(ctx)then notice("Gun waits for real Watcher visibility"); return end
                if ctx.questAimHead and target then part = target:FindFirstChild('Head') or part end
                local camera = controller("CameraController")
                if not camera or type(camera.GetAimRay) ~= "function" then return end
                local original = camera.GetAimRay
                local ray = original(camera)
                if not ray or (part.Position - ray.Origin).Magnitude < 0.001 then return end
                local wrapper = function(self, ...)
                    if self == camera and ctx.active then return Ray.new(ray.Origin, (part.Position - ray.Origin).Unit) end
                    return original(self, ...)
                end
                combat.aimEdit = { controller = camera, original = original, wrapper = wrapper }
                camera.GetAimRay = wrapper
            end
            local health = target and target:FindFirstChildOfClass("Humanoid")
            local healthBefore = health and health.Health or (target and tonumber(target:GetAttribute("FuelLeechHealth"))) or 0
            local ok, why, blocker
            if selected.melee and features then ok, why, blocker = pcall(features.swing, ctx, active, auraTargets)
            else ok, why, blocker = pcall(features.gunShot, ctx, active) end
            combat.restoreAim()
            if not ok then error(why, 0) end
            if why ~= true then notice("Native attack dispatch blocked: " .. tostring(blocker or 'no eligible targets or handler')); return end
            notice("Always-on aura ready: " .. selected.tool.Name, true)
            if not selected.melee and features then features.afterAttack(ctx, target, selected.class, healthBefore) end
            local endsAt = math.max(tonumber(active.LastSwing) or 0, tonumber(active.AttackLockedUntil) or 0, tonumber(active.Debounce) or 0)
            combat.nextAttack = math.max(now() + 0.1, endsAt)
            -- Native cooldowns delay the next attack, never the chest route.
            -- Standing beside a living enemy through several swings only exposes
            -- the player to more hits. The separate ranged-defense worker can
            -- still take movement ownership for an actual projectile/telegraph.
            combat.target, combat.holdUntil, combat.burstUntil = target, nil, nil
        end
        ctx.combatThread = task.spawn(function()
            while ctx.active and owned() and s.farm == ctx do
                combat.pulse=now()
                local ok, why = pcall(step)
                if not ok then
                    combat.restoreAim()
                    combat.holdUntil = nil
                    if tostring(why):find("__CHESTFARM_CANCELLED", 1, true) then return end
                    notice("Combat action failed; retrying automatically: " .. tostring(why))
                    task.wait(2)
                else task.wait(0.1) end
            end
            combat.restoreAim()
        end)
    end

    do
        local loader = loadstring or load
        local chunk, why = loader(FEATURE_SOURCE, "@EarthAutofarmFeatures")
        assert(chunk, why)
        features = chunk()({ state = s, env = env, now = now, controller = controller, remote = remote, event = event,
            request = request, pack = pack, accepted = accepted, owned = owned, stopFarm = stopFarm,
            Players = Players, RS = RS, CollectionService = CollectionService, RunService = RunService,
            TeleportService = TeleportService, observeClass = observeClassData, saveStore = saveStore,
            worldSnapshot = function(ctx)return ctx.readWorld()end })
    end

    local factory
    local function startFarm(player, model, humanoid, root, drill)
        if s.farm then return end
        local loader = loadstring or load
        if not factory then
            local chunk, why = loader(FARM_SOURCE, "@PreservedChestFarm")
            if not chunk then error(why) end
            factory = chunk()
        end
        local ctx = { active = true, character = model, humanoid = humanoid, root = root, drill = drill,
            flags = {}, threads = {}, connections = {}, savedParts = setmetatable({}, {__mode='k'}), started = now() }
        features.initializeRoute(ctx)
        s.farm = ctx
        ctx.helpers = {}
        local taskApi = {}
        local function readWorld()
            local function live(item)return item==workspace or item and item.Parent and item:IsDescendantOf(workspace)end
            -- This lock protects a READ-ONLY snapshot, not character movement.
            -- Parking its producer for quest movement makes a quest consumer
            -- wait forever for the very producer it has parked.
            while ctx.worldReading do
                if ctx.worldReader and coroutine.status(ctx.worldReader)=='dead' then
                    ctx.worldReading,ctx.worldReader=nil,nil
                    break
                end
                ctx.check();task.wait(0.03)
            end
            if ctx.worldScan or not ctx.worldObjects or now() >= (ctx.worldRefreshAt or 0) then
                ctx.worldReading = true
                local reader=coroutine.running();ctx.worldReader=reader;ctx.worldReadPulse=now()
                local scan=ctx.worldScan
                if not scan then
                    scan={list={},queue={workspace},cursor=1,seen=setmetatable({[workspace]=true}, {__mode='k'}),published=0};ctx.worldScan=scan
                end
                local ok, complete = pcall(function()
                    local visited,steps,nextYield,started=0,0,100,now()
                    while scan.children or scan.cursor<=#scan.queue do
                        if not scan.children then
                            local parent=scan.queue[scan.cursor];scan.cursor=scan.cursor+1
                            scan.children,scan.childCursor=live(parent) and parent:GetChildren() or {},1
                        else
                            local child=scan.children[scan.childCursor]
                            if child then
                                visited=visited+1
                                scan.childCursor=scan.childCursor+1
                                if live(child) and not scan.seen[child]then
                                    scan.seen[child]=true;scan.list[#scan.list+1]=child;scan.queue[#scan.queue+1]=child
                                end
                            else scan.children=nil end
                        end
                        steps=steps+1
                        -- Yield per inspected child, as the earlier loot reader
                        -- did. Queue entry/exit bookkeeping is not another item.
                        if visited>=nextYield then
                            nextYield=visited+100
                            ctx.worldReadPulse=now();ctx.check();task.wait(0.03)
                            -- Publish a partial snapshot and resume this same queue
                            -- next time. Large maps cannot monopolize a quest pulse
                            -- or lose all scan progress to the worker watchdog.
                            if visited>=1000 or now()-started>=.75 then return false end
                        elseif steps%100==0 and now()-started>=.75 then
                            ctx.worldReadPulse=now();ctx.check();return false
                        end
                    end
                    return true
                end)
                if ctx.worldReader==reader then ctx.worldReading,ctx.worldReader=nil,nil end
                if not ok then error(complete, 0) end
                if complete then
                    ctx.worldObjects,ctx.worldScan,ctx.worldRefreshAt=scan.list,nil,now()+(workspace.DescendantAdded and 30 or 2)
                    ctx.worldSeen=setmetatable({}, {__mode='k'});ctx.worldPruneAt=0
                    for _,item in ipairs(ctx.worldObjects)do ctx.worldSeen[item]=true end
                else
                    -- Publish only this slice's new identities. Recopying the
                    -- cumulative scan at every slice makes large maps quadratic.
                    ctx.worldObjects=ctx.worldObjects or {}
                    if not ctx.worldSeen then
                        ctx.worldSeen=setmetatable({}, {__mode='k'})
                        for _,item in ipairs(ctx.worldObjects)do ctx.worldSeen[item]=true end
                    end
                    for i=(scan.published or 0)+1,#scan.list do
                        local item=scan.list[i]
                        if live(item) and not ctx.worldSeen[item]then
                            ctx.worldObjects[#ctx.worldObjects+1]=item;ctx.worldSeen[item]=true
                        end
                    end
                    scan.published=#scan.list
                end
            end
            local list=ctx.worldObjects or {};ctx.worldObjects=list
            if not ctx.worldSeen then
                ctx.worldSeen=setmetatable({}, {__mode='k'})
                for _,item in ipairs(list)do ctx.worldSeen[item]=true end
            end
            local seen=ctx.worldSeen
            for item in pairs(ctx.worldPending or {}) do
                if live(item) and not seen[item] then list[#list + 1] = item;seen[item]=true end
                local scan=ctx.worldScan
                if scan and live(item) and not scan.seen[item]then
                    scan.seen[item]=true;scan.list[#scan.list+1]=item;scan.queue[#scan.queue+1]=item
                end
            end
            ctx.worldPending={}
            if now()>=(ctx.worldPruneAt or 0)then
                local write=1
                for i=1,#list do
                    local item=list[i]
                    if live(item)then list[write]=item;write=write+1 else seen[item]=nil end
                end
                for i=#list,write,-1 do list[i]=nil end
                ctx.worldPruneAt=now()+1
            end
            return list
        end
        ctx.readWorld=readWorld
        local function chestRecord(entry)
            local part = entry.Pos
            local key = tostring(entry.Model.Name) .. ":" .. string.format("%.1f:%.1f:%.1f", part.X, part.Y, part.Z)
            local record = s.chests[key]
            if not record then record = { key = key, failures = 0 }; s.chests[key] = record end
            local prompt = ctx.helpers[13917854](entry.Model)
            local enabled = prompt and prompt.Enabled ~= false or false
            if prompt ~= record.prompt or enabled ~= record.enabled or record.model ~= entry.Model then
                record.retryAt = 0
                -- A newly enabled prompt is new usable work, even at a reused location.
                if enabled then
                    record.retired, record.failures, record.pending = false, 0, nil
                    record.attempted, record.removalRecorded, record.startRecorded, record.usedNative = nil, nil, nil, nil
                end
            end
            record.model, record.prompt, record.entry = entry.Model, prompt, entry
            record.enabled, record.locked = enabled, not enabled
            return record
        end
        function ctx.capture(id, fn)
            local wrapped = fn
            if id == 16446958 then
                wrapped = function(...)
                    -- The recovered chest helper also invokes recovery internally.
                    -- Chest-only mode must not enter that legacy wait-for-HP loop.
                    ctx.flags.SafeMode = false; return
                end
            elseif id == 9164528 then
                wrapped = function(...)
                    if ctx.worldScan or not ctx.candidates or ctx.chestsDirty or now() >= (ctx.cacheAt or 0) then
                        readWorld()
                        ctx.candidates = fn(...)
                        ctx.cacheAt, ctx.chestsDirty = now() + (workspace.DescendantAdded and 30 or 2), false
                    end
                    local list, pending = {}, false
                    for _, entry in ipairs(ctx.candidates) do
                        if entry.Model.Parent and features.chestAreaAllowed(ctx,entry.Model)
                            and features.chestFallbackAllowed(entry.Model) then
                            local record = chestRecord(entry)
                            if not record.locked and not record.retired and now() >= (record.retryAt or 0)
                                and not ((record.failures or 0) >= 3 and entry.Pos.X < (s.routeScanX or entry.Pos.X) - 300) then
                                entry.Dist = (entry.Pos - root.Position).Magnitude
                                table.insert(list, entry)
                            elseif not record.locked and not record.retired then
                                pending = true -- Cooling/unconfirmed chests are not an empty route.
                            end
                        end
                    end
                    ctx.chestCandidatesPending = pending
                    table.sort(list, function(a, b) return a.Dist < b.Dist end)
                    return list
                end
            elseif id == 16361397 then
                wrapped = function(entry, ...)
                    if not features.chestAreaAllowed(ctx,entry.Model) or not features.chestFallbackAllowed(entry.Model) then return "skipped" end
                    if not features.healingChestSafe(ctx,entry)then return 'unsafe' end
                    if ctx.awaitCombat then ctx.awaitCombat() end
                    if not features.chestEnabled() and coroutine.running() ~= ctx.featureThread then return "disabled" end
                    local record = chestRecord(entry)
                    if record.locked or record.retired or now() < (record.retryAt or 0) then return "locked" end
                    local attempts = s.stats.promptFires
                    ctx.currentChest = record
                    record.healingPosed=nil
                    ctx.chestStarted = now()
                    ctx.lootThread = coroutine.running()
                    local result = pack(pcall(fn, entry, ...))
                    if result[1] and s.stats.promptFires > attempts then
                        local checked, why = pcall(function()
                            local function changed()
                                return not entry.Model.Parent or not record.prompt.Parent or record.prompt.Enabled == false
                            end
                            local deadline = now() + 1.25
                            while not changed() and now() < deadline do taskApi.wait(0.05) end
                            if not changed() and not record.usedNative and features.chestFallbackAllowed(entry.Model) then
                                -- Some executors expose a no-op prompt helper. One
                                -- normal hold is a chest-only compatibility fallback.
                                ctx.nativeChestPrompt(record.prompt)
                                deadline = now() + 1.25
                                while not changed() and now() < deadline do taskApi.wait(0.05) end
                            end
                            record.pending = changed() and entry.Model.Parent ~= nil
                            if record.pending and not record.startRecorded then
                                record.startRecorded = true; s.stats.chestStarts = s.stats.chestStarts + 1
                                print('[ChestFarm] Chest prompt changed; waiting for reward/removal: ' .. entry.Model.Name)
                            end
                            if not entry.Model.Parent and not record.removalRecorded then
                                record.removalRecorded = true; s.stats.lootObserved = s.stats.lootObserved + 1; s.lastLootAt = now()
                                print('[ChestFarm] Observed chest removal: ' .. entry.Model.Name)
                            elseif not changed() then
                                local position = features.promptPosition(record.prompt) or entry.Pos
                                print(string.format('[ChestFarm] UNCONFIRMED %s: distance %.1f, anchored=%s; no prompt transition or removal',
                                    entry.Model.Name, (position - root.Position).Magnitude, tostring(root.Anchored)))
                            end
                        end)
                        if not checked then result = pack(false, why) end
                    end
                    if result[1] and (record.pending or record.removalRecorded) then features.chestLootWindow(ctx, entry.Pos) end
                    ctx.currentChest, ctx.lootThread, ctx.chestStarted = nil, nil, nil
                    if not result[1] and tostring(result[2]):find('__EARTH_DEFENSE_RETRY', 1, true) then
                        ctx.defenseAbort = nil
                        for prompt in pairs(ctx.heldPrompts or {}) do pcall(function() prompt:InputHoldEnd() end) end
                        ctx.heldPrompts = {}
                        for prompt, duration in pairs(ctx.instantPrompts or {}) do
                            pcall(function() if prompt.Parent then prompt.HoldDuration = duration end end)
                        end
                        ctx.instantPrompts = {}
                        record.retryAt = now() + 1
                        return 'interrupted'
                    end
                    if not record.pending and not record.removalRecorded then record.failures = record.failures + 1 end
                    record.retired = record.removalRecorded == true
                    record.retryAt = now() + ((record.failures or 0) >= 3 and 300
                        or math.min(30, 5 * 2 ^ math.min(math.max(0, record.failures - 1), 3)))
                    if not result[1] then error(result[2], 0) end
                    return unpackValues(result, 2, result.n)
                end
            end
            ctx.helpers[id] = wrapped
            return wrapped
        end
        local function captureParts()
            for _, part in ipairs(model:GetDescendants()) do
                if part:IsA("BasePart") and not ctx.savedParts[part] then
                    ctx.savedParts[part] = { part.Anchored, part.CanCollide }
                end
            end
        end
        captureParts()
        function ctx.check()
            ctx.flags.SafeMode = false
            if not ctx.active or not owned() or s.farm ~= ctx or s.teleporting
                or player.Character ~= model or not model.Parent or not root.Parent
                or not drill.Parent or humanoid.Health <= 0
                or player:GetAttribute("RejoinDead") == true then
                error("__CHESTFARM_CANCELLED", 0)
            end
            if ctx.currentChest and ctx.defenseAbort and coroutine.running() == ctx.lootThread then
                error('__EARTH_DEFENSE_RETRY', 0)
            end
            local chest=ctx.currentChest
            if chest and ctx.questHealing and chest.model.Parent and coroutine.running()==ctx.lootThread then
                local target=features.promptPosition(chest.prompt) or features.promptPosition(chest.model) or chest.entry.Pos
                if not features.healingPointSafe(ctx,target) or chest.healingPosed
                    and not features.healingPointSafe(ctx,root.CFrame.Position or root.Position)then
                    s.questStatus='Healing chest interrupted: a living enemy approached'
                    error('__EARTH_DEFENSE_RETRY',0)
                end
            end
            if ctx.questChestLease and coroutine.running() == ctx.questChestLease and not s.config.classQuest then
                error('__EARTH_DEFENSE_RETRY', 0)
            end
            if coroutine.running() == ctx.featureThread and (ctx.defenseMoving or now() < (ctx.dodgeUntil or 0)) then
                error('__EARTH_DEFENSE_RETRY', 0)
            end
        end
        function ctx.awaitCombat()
            while ctx.active and ((ctx.questOwns and not (ctx.questChestTaking and coroutine.running() == ctx.featureThread)) or ctx.questDriving or ctx.questSeating or (ctx.featureHold and coroutine.running() ~= ctx.featureThread)
                or (ctx.questChestLease and coroutine.running() ~= ctx.questChestLease)
                or (features.smartLootPending(ctx) and coroutine.running() ~= ctx.featureThread)
                or ctx.defenseMoving
                or (ctx.dodgeUntil and now() < ctx.dodgeUntil)) do
                ctx.routeParked = true
                ctx.check()
                task.wait(0.05)
            end
            if coroutine.running() ~= ctx.featureThread then ctx.routeParked = nil end
        end
        function ctx.questChestCandidate(radius,predicate)
            -- Only the owning optional worker may borrow one chest action;
            -- the discovery route stays parked throughout the detour.
            if not s.config.classQuest or not ctx.questChestTaking
                or coroutine.running() ~= ctx.featureThread or ctx.currentChest then return end
            local any=false
            for _,entry in ipairs(ctx.helpers[9164528]())do
                if not predicate or predicate(entry)then
                    any=true
                    if entry.Dist<=radius then return entry,false end
                end
            end
            local complete=type(ctx.worldObjects)=='table' and not ctx.worldScan and not ctx.worldReading
                and now()<(ctx.worldRefreshAt or 0) and not ctx.chestsDirty and not ctx.chestCandidatesPending
                and not next(ctx.worldPending or {}) and not ctx.streamWaiting and player.GameplayPaused~=true
            return nil,not any and complete
        end
        local function run(fn, ...)
            if not ctx.active then return end
            local thread = coroutine.running()
            ctx.threads[thread] = (ctx.threads[thread] or 0) + 1
            local result = pack(pcall(fn, ...))
            local depth = (ctx.threads[thread] or 1) - 1
            ctx.threads[thread] = depth > 0 and depth or nil
            if not result[1] and not tostring(result[2]):find("__CHESTFARM_CANCELLED", 1, true) then
                ctx.failed = tostring(result[2])
                warn("[ChestFarm Auto] Farm action failed; supervisor will recover: " .. ctx.failed)
            end
            return unpackValues(result, 2, result.n)
        end
        function ctx.pruneConnections()
            if now()<(ctx.connectionsPruneAt or 0)then return end
            local kept={}
            for _,existing in ipairs(ctx.connections)do
                local ok,connected=pcall(function()return existing.Connected end)
                if not ok or connected~=false then kept[#kept+1]=existing end
            end
            ctx.connections=kept;ctx.connectionsPruneAt=now()+1
        end
        function ctx.connect(signal, fn)
            local connection
            if type(signal) == "table" and signal.__headless then
                connection = { Connected = true }
                function connection:Disconnect() self.Connected = false end
                if signal.__scan then ctx.beginScan = function() if connection.Connected then run(fn) end end end
            else
                connection = signal:Connect(function(...)
                    if ctx.active then
                        if signal == RunService.Stepped and not model.DescendantAdded and now() >= (ctx.partsAt or 0) then
                            ctx.partsAt = now() + 1; captureParts()
                        end
                        run(fn, ...)
                    end
                end)
            end
            if #ctx.connections>=128 then ctx.connectionsPruneAt=0 end
            ctx.pruneConnections()
            table.insert(ctx.connections, connection)
            return connection
        end
        if model.DescendantAdded then
            ctx.connect(model.DescendantAdded, function(part)
                if part:IsA('BasePart') and not ctx.savedParts[part] then
                    ctx.savedParts[part] = { part.Anchored, part.CanCollide }
                end
            end)
        end
        function ctx.dispose()
            if not ctx.active then return end
            ctx.active = false
            ctx.flags.ChestFarm, ctx.flags.TrackScan = false, false
            for _, connection in ipairs(ctx.connections) do pcall(function() connection:Disconnect() end) end
            for thread in pairs(ctx.threads) do
                if thread ~= coroutine.running() then pcall(task.cancel, thread) end
            end
            if ctx.combatThread and ctx.combatThread ~= coroutine.running() then pcall(task.cancel, ctx.combatThread) end
            if ctx.combat then pcall(ctx.combat.restoreAim) end
            if ctx.featureThread and ctx.featureThread ~= coroutine.running() then pcall(task.cancel, ctx.featureThread) end
            if features then pcall(features.cleanup, ctx) end
            for prompt in pairs(ctx.heldPrompts or {}) do
                pcall(function() prompt:InputHoldEnd() end)
            end
            ctx.heldPrompts = {}
            for part, original in pairs(ctx.savedParts) do
                pcall(function() if part.Parent then part.Anchored, part.CanCollide = original[1], original[2] end end)
            end
        end
        local fakeClasses = { ScreenGui = true, Frame = true, TextLabel = true, TextButton = true, UICorner = true }
        local instanceApi = {}
        function instanceApi.new(class, parent)
            if not fakeClasses[class] then return Instance.new(class, parent) end
            -- Status placeholders retain the original code paths without creating any GUI controls.
            local object = { Name = class, ClassName = class, Parent = parent }
            function object:Destroy() self.Parent = nil end
            object.MouseButton1Click = { __headless = true, __scan = class == "TextButton" }
            return object
        end
        function taskApi.wait(seconds)
            ctx.check()
            local duration = task.wait(seconds)
            ctx.check()
            ctx.awaitCombat()
            return duration
        end
        function taskApi.spawn(fn, ...)
            if fn == ctx.helpers[11145377] then
                -- The single route worker replaces the original recurring nearby-chest worker.
                return task.spawn(function() end)
            end
            local args = pack(...)
            local thread = task.spawn(function() run(fn, unpackValues(args, 1, args.n)) end)
            if coroutine.status(thread) ~= "dead" and not ctx.threads[thread] then ctx.threads[thread] = 1 end
            return thread
        end
        function taskApi.defer(fn, ...) return taskApi.spawn(fn, ...) end
        function taskApi.delay(seconds, fn, ...)
            local args = pack(...)
            return taskApi.spawn(function() taskApi.wait(seconds); return fn(unpackValues(args, 1, args.n)) end)
        end
        taskApi.cancel = task.cancel
        ctx.env = setmetatable({ _G = ctx.flags, Instance = instanceApi, task = taskApi,
            wait = taskApi.wait, spawn = taskApi.spawn, delay = taskApi.delay }, { __index = function(_, key)
                local value = env[key]
                if value ~= nil then return value end
                return getfenv and getfenv()[key] or _G[key]
            end })
        -- The recovered finder keeps its matching rules while its Workspace walk
        -- uses a yielded snapshot plus streaming additions instead of allocating
        -- all descendants on each chest scan.
        ctx.env.workspace = setmetatable({GetDescendants = function()
            local objects=ctx.worldObjects or readWorld()
            if not ctx.currentChest then return objects end
            -- The recovered interaction repeats a nearby-chest search after
            -- moving. Keep that search on the chosen chest, so a closer locked,
            -- Mimic, priced or foreign-room model cannot replace its identity.
            local list={}
            for _,item in ipairs(objects)do
                local ancestor,allowed=item,true
                while ancestor and ancestor~=workspace do
                    if ancestor:IsA('Model') and ancestor:GetAttribute('RuntimeChestModel')
                        and ancestor~=ctx.currentChest.model then allowed=false;break end
                    ancestor=ancestor.Parent
                end
                if allowed then list[#list+1]=item end
            end
            return list
        end},
            {__index = function(_, key)
                local value = workspace[key]
                if type(value) == 'function' then return function(_, ...) return value(workspace, ...) end end
                return value
            end})
        function ctx.prepareChestPrompt(prompt)
            ctx.check()
            local function allowed()
                return prompt and prompt.Parent and prompt.Enabled~=false and features.chestFallbackAllowed(prompt)
                    and features.chestAreaAllowed(ctx,prompt)
                    and (not ctx.currentChest or prompt:IsDescendantOf(ctx.currentChest.model))
                    and (not ctx.questHealing or features.healingPointSafe(ctx,features.promptPosition(prompt)))
            end
            if not allowed()then return false end
            local target = features.promptPosition(prompt) or (ctx.currentChest and ctx.currentChest.entry.Pos)
            if not target then
                print('[ChestFarm] Waiting for a chest prompt position to load'); return false
            end
            local radius = tonumber(prompt.MaxActivationDistance) or 12
            if radius <= 0 then return false end
            features.hover(ctx)
            local offset = math.min(2, radius / 4)
            local destination = target + Vector3.new(0, offset, offset)
            if ctx.questHealing and not features.healingPointSafe(ctx,destination)then return false end
            if ((root.CFrame.Position or root.Position) - destination).Magnitude > 0.5 then
                root.CFrame = CFrame.new(destination)
            end
            if ctx.currentChest then ctx.currentChest.healingPosed=ctx.questHealing or nil end
            taskApi.wait(0.15) -- Let the unanchored character's new position propagate.
            local deadline = now() + 2
            while player.GameplayPaused == true and now() < deadline do taskApi.wait(0.1) end
            if player.GameplayPaused == true or ((root.CFrame.Position or root.Position) - target).Magnitude > radius then
                print('[ChestFarm] Chest prompt not ready: loading pause or character outside activation range')
                return false
            end
            return allowed() and (not ctx.questHealing or features.healingPointSafe(ctx,root.CFrame.Position or root.Position))
            -- Streaming, room, stock and living enemies can change during the pose wait.
        end
        function ctx.nativeChestPrompt(prompt)
            if not ctx.prepareChestPrompt(prompt) then return false end
            local duration = ctx.instantPrompts and ctx.instantPrompts[prompt] or prompt.HoldDuration or 0
            if duration > 8 then print('[ChestFarm] Native chest hold exceeds the bounded compatibility wait'); return false end
            ctx.instantPrompts = ctx.instantPrompts or {}; ctx.instantPrompts[prompt] = duration
            ctx.heldPrompts = ctx.heldPrompts or {}; ctx.heldPrompts[prompt] = true
            prompt.HoldDuration = duration
            local result = pack(pcall(function()
                prompt:InputHoldBegin()
                s.stats.promptFires = s.stats.promptFires + 1
                if ctx.currentChest then ctx.currentChest.attempted, ctx.currentChest.usedNative = true, true end
                local deadline = now() + math.max(0.03, duration + 0.05)
                while prompt.Parent and prompt.Enabled ~= false and now() < deadline do
                    taskApi.wait(math.min(0.05, deadline - now()))
                end
                return true
            end))
            if ctx.heldPrompts[prompt] then pcall(function() prompt:InputHoldEnd() end) end
            pcall(function() if ctx.active and prompt.Parent then prompt.HoldDuration = duration end end)
            ctx.heldPrompts[prompt], ctx.instantPrompts[prompt] = nil, nil
            if not result[1] then error(result[2], 0) end
            return result[2]
        end
        ctx.env.fireproximityprompt = function(prompt, ...)
            if not ctx.prepareChestPrompt(prompt) then return false end
            local original = prompt.HoldDuration
            ctx.instantPrompts = ctx.instantPrompts or {}; ctx.instantPrompts[prompt] = original
            prompt.HoldDuration = 0
            local fire = env.fireproximityprompt or fireproximityprompt
            local result
            if type(fire) == "function" then
                s.stats.promptFires = s.stats.promptFires + 1
                if ctx.currentChest then ctx.currentChest.attempted = true end
                -- Preserve the recovered helper's actual argument list. A zero
                -- second argument can mean zero executions in an executor API.
                result = pack(pcall(fire, prompt, ...))
            else
                if ctx.currentChest and ctx.currentChest.usedNative then result = pack(true, false)
                else result = pack(pcall(ctx.nativeChestPrompt, prompt)) end
            end
            pcall(function() if ctx.active and prompt.Parent then prompt.HoldDuration = original end end)
            ctx.instantPrompts[prompt] = nil
            if not result[1] then
                local why = tostring(result[2])
                if why:find('__CHESTFARM_CANCELLED', 1, true) or why:find('__EARTH_DEFENSE_RETRY', 1, true) then error(why, 0) end
                print('[ChestFarm] Executor prompt call failed: ' .. why)
                return false
            end
            return unpackValues(result, 2, result.n)
        end
        ctx.env.print = function(...)
            local args = pack(...)
            local pieces = {}
            for i = 1, args.n do pieces[i] = tostring(args[i]) end
            ctx.lastMessage = table.concat(pieces, " ")
            if ctx.lastMessage:find("STOP after 40", 1, true) then ctx.exhausted = true end
            if ctx.lastMessage:find("Scan COMPLETE (end of track).", 1, true) then
                s.sweepComplete, s.sweepCompletedAt = true, now()
            end
            if ctx.currentChest and ctx.lastMessage:find("Looted: ", 1, true) then
                -- Original routine observed the chest disappear; this is not a currency award.
                if not ctx.currentChest.removalRecorded then
                    ctx.currentChest.removalRecorded = true
                    s.stats.lootObserved = s.stats.lootObserved + 1
                    s.lastLootAt = now()
                end
            end
            if ctx.currentChest and ctx.lastMessage:find('Fired ', 1, true) then return end
            if ctx.lastMessage:find("Menu OK. Farm auto-ON. Click SCAN", 1, true) then
                print("[ChestFarm Auto] Farm ready; targeting loaded chests, with a discovery sweep when needed")
                return
            end
            print(unpackValues(args, 1, args.n))
        end
        -- Prevent an older standalone copy of the supplied farm from continuing beside this owner.
        _G.ChestFarm, _G.TrackScan = false, false
        status("Starting chest route with optional smart loot and church extraction")
        taskApi.spawn(function()
            factory(ctx)
            ctx.initialized = true
            if not ctx.helpers[9164528] or not ctx.helpers[16361397] then
                if ctx.beginScan then ctx.beginScan() end
                return
            end
            -- Keep the recovered chest interaction routine. Replace its depth
            -- sweep with one owned worker that streams across short tween segments.
            function ctx.beginScan()
                if ctx.depthThread and coroutine.status(ctx.depthThread) ~= 'dead' then return end
                ctx.flags.TrackScan, ctx.flags.ChestFarm = true, false
                print('[ChestFarm] START scan: continuous depth travel; direct chest collection')
                ctx.depthThread = taskApi.spawn(function()
                    ctx.depthThread = coroutine.running()
                    while ctx.active and features.chestEnabled() do
                        ctx.check()
                        ctx.awaitCombat()
                        for _, entry in ipairs(ctx.helpers[9164528]()) do
                            ctx.check(); ctx.awaitCombat()
                            if not features.chestEnabled() then break end
                            ctx.helpers[16361397](entry)
                        end
                        local current = root.CFrame.Position or root.Position
                        local scanX = s.routeScanX or current.X
                        local nextX = math.min(scanX + 150, ctx.scanEnd or 36000)
                        local reached = features.travelRoute(ctx, nextX)
                        if reached then
                            ctx.flags.ScanX, s.routeScanX = nextX, nextX
                            taskApi.wait(0.15)
                            local candidates = ctx.helpers[9164528]()
                            for _, entry in ipairs(candidates) do
                                ctx.check(); ctx.awaitCombat()
                                if not features.chestEnabled() then break end
                                ctx.helpers[16361397](entry)
                            end
                            if nextX >= (ctx.scanEnd or 36000) then
                                s.sweepComplete, s.sweepCompletedAt = true, now()
                                break
                            end
                        else taskApi.wait(0.1) end
                    end
                    features.cancelTravel(ctx)
                    ctx.flags.TrackScan, ctx.flags.ChestFarm = false, true
                end)
            end
            if workspace.DescendantAdded then
                ctx.connect(workspace.DescendantAdded, function(instance)
                    local isModel, isPrompt = instance:IsA('Model'), instance:IsA('ProximityPrompt')
                    if isModel or isPrompt then
                        ctx.worldPending = ctx.worldPending or {}; ctx.worldPending[instance] = true
                    end
                    if isPrompt or (isModel and instance:GetAttribute("RuntimeChestModel")) then
                        ctx.chestsDirty = true
                    end
                end)
            end
            ctx.flags.ChestFarm = true
            features.start(ctx)
            startCombat(ctx, player, model, humanoid, root)
            while ctx.active do
                ctx.check()
                ctx.awaitCombat()
                if not features.chestEnabled() then
                    taskApi.wait(0.2)
                elseif ctx.flags.TrackScan then
                    taskApi.wait(0.2)
                else
                    ctx.flags.ChestFarm = true
                    ctx.flags.SafeMode = false
                    -- Do not move/fire from a seat that rejected the original dismount.
                    if humanoid.SeatPart or humanoid.Sit then
                        s.seatBlockedSince = s.seatBlockedSince or now()
                        if now() >= (ctx.dismountAt or 0) then
                            ctx.dismountAt = now() + 1
                            humanoid.Sit, humanoid.Jump = false, true
                            pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end)
                        end
                        if humanoid.SeatPart or humanoid.Sit then
                            status("Waiting to leave the seat before farming")
                            taskApi.wait(0.2)
                        end
                    end
                    if not humanoid.SeatPart and not humanoid.Sit then
                    s.seatBlockedSince = nil
                    local candidates = ctx.helpers[9164528]()
                    if #candidates > 0 then
                        s.emptySince = nil
                        ctx.helpers[16361397](candidates[1])
                        taskApi.wait(0.1)
                    elseif s.sweepComplete then
                        s.emptySince = s.emptySince or now()
                        local cooling, repeatedlyFailed = false, true
                        for _, record in pairs(s.chests) do
                            if record.model and record.model.Parent and not record.retired and record.enabled then
                                cooling = true
                                if (record.failures or 0) < 3 then repeatedlyFailed = false end
                            end
                        end
                        local stalled = cooling and repeatedlyFailed
                            and now() - math.max(s.lastLootAt or 0, s.sweepCompletedAt or 0) >= 90
                        if (not cooling and now() - math.max(s.emptySince, s.sweepCompletedAt or 0) >= 15) or stalled then
                            s.runExhausted = true
                            status(stalled and "Discovery complete; repeated chest attempts made no observed progress for 90 seconds"
                                or "Discovery sweep completed; no usable chests remain")
                            taskApi.wait(0.5)
                        else taskApi.wait(0.5) end
                    else
                        ctx.flags.ScanX = s.routeScanX
                        if ctx.beginScan then ctx.beginScan() end
                        taskApi.wait(0.2)
                    end
                    end
                end
            end
        end)
    end

    local function leaveZone(zone)
        request("exit-zone", "TeleportManagerService", "ExitZone", pack(zone), function(result)
            if not result[1] or result[2] == false then return end
            restoreZoneOrigin(zone)
            if not s.lobbyWalkExit then restoreZoneTouches()end
            -- Do not assume membership changed until ExitedZone/controller state confirms it.
            waitTransition("exit-zone", zone, 12)
        end)
    end
    local function lobby(player, model, humanoid, root)
        stopFarm()
        if not alive(player, model, humanoid, root) then lobbyWalker.stop(true);status("Waiting for lobby character"); return end
        for _, method in ipairs({ "TouchedZone", "CreatedZone", "ExitZone" }) do
            if not remote("TeleportManagerService", method) then lobbyWalker.stop(true);status("Waiting for lobby action " .. method); return end
        end
        local c = configureParty()
        if not c or not s.signalsBound then lobbyWalker.stop(true);status("Waiting for lobby controller and zone signals"); return end
        local pending = player:GetAttribute("PendingSessionId")
        local retry = player:GetAttribute("SessionRejoinRetryAvailable") == true
        if retry ~= s.rejoinRetryFlag then
            s.rejoinRetryFlag = retry
            if retry then s.failedSession = nil end
        end
        if type(pending) == "string" and pending ~= "" then
            if s.forceFresh then
                request("end-session", "TeleportManagerService", "EndSession", pack(pending), function(result)
                    if accepted(result) then waitTransition("end-session", pending, 15) end
                end)
            elseif s.failedSession ~= pending then
                request("rejoin", "TeleportManagerService", "RejoinSession", pack(), function(result)
                    if accepted(result) then waitTransition("rejoin", pending)
                    else s.failedSession = pending end
                end)
            else
                request("end-session", "TeleportManagerService", "EndSession", pack(pending), function(result)
                    if result[1] and result[2] then waitTransition("end-session", pending, 15) end
                end)
            end
            return
        end
        s.failedSession = nil
        if not lobbyWalker.exitStep()then return end
        local zone = c.Zone or s.zone
        if zone and zone.Parent then
            lobbyWalker.stop(false)
            s.zone = zone
            if not s.zoneOwned and c.CreateUI.Visible then s.zoneOwned = true; s.partyToken = {} end
            configureParty()
            if not s.zoneOwned then leaveZone(zone); return end
            if (tonumber(zone:GetAttribute("PlayerCount")) or 0) > 1 then leaveZone(zone); return end
            if s.startedZone == zone then
                if now() - (s.zoneStartedAt or now()) > 90 then leaveZone(zone)
                else status("Solo party started; waiting for the server teleport") end
                return
            end
            s.partyToken = s.partyToken or {}
            c.StartRequest = s.partyToken
            request("start", "TeleportManagerService", "CreatedZone", pack(zone, 1, "Earth", false, false), function(result)
                if result[1] and result[2] then
                    s.forceFresh = false
                    pcall(function() saveFresh(false) end)
                    s.startedZone, s.zoneStartedAt = zone, now()
                    waitTransition("start", zone)
                else status("Solo start rejected; retrying after backoff") end
            end)
            return
        end
        s.zone, s.zoneOwned = nil, false
        if s.touchCandidate and now() - s.touchAt < 12 then status("Waiting for zone creation confirmation"); return end
        local candidates = CollectionService:GetTagged("PartyZone")
        local parts = {}
        for _, candidate in ipairs(candidates) do
            if candidate:IsA("BasePart") and candidate:IsDescendantOf(workspace) then table.insert(parts, candidate) end
        end
        candidates = parts
        table.sort(candidates, function(a, b)
            return (a.Position - root.Position).Magnitude < (b.Position - root.Position).Magnitude
        end)
        local selected
        for _, zoneObject in ipairs(candidates) do
            if zoneObject:IsA("BasePart") and zoneObject:IsDescendantOf(workspace)
                and (tonumber(zoneObject:GetAttribute("PlayerCount")) or 0) == 0
                and (tonumber(zoneObject:GetAttribute("State")) or 0) <= 1 then
                selected = zoneObject; break
            end
        end
        if not selected then lobbyWalker.stop(true);status("Waiting for an empty PartyZone"); return end
        if now() < (s.nextAction or 0) then return end
        -- Walk into the actual native zone before the existing serialized
        -- queue request. Preserve its touch guard so one entry sends one RPC.
        if s.zoneOriginCharacter ~= model then s.zoneOrigin, s.zoneOriginCharacter = root.CFrame, model end
        if not lobbyWalker.step(selected,'enter')then return end
        muteZoneTouches(model)
        s.touchCandidate, s.touchAt = selected, now()
        request("create", "TeleportManagerService", "TouchedZone", pack(selected), function(result)
            if not result[1] or result[2] == false then s.touchCandidate = nil
            elseif s.touchCandidate == selected then s.touchAt = now() end
        end,function(token)
            local currentParty=controller('PartyCreateController')
            return s.request==token and s.touchCandidate==selected and not s.zone and not(currentParty and currentParty.Zone)
                and lobbyWalker.entryAllowed(selected,model,humanoid,root)
        end)
    end
    local function returnToLobby()
        local player, model, humanoid, root = character()
        if s.questChurchExit and alive(player, model, humanoid, root) then
            status('Quest exit requires church SaveGear; ordinary lobby return is blocked')
            return
        end
        request("return", "TeleportManagerService", "TeleportToLobby", pack(true), function(result)
            if accepted(result) then waitTransition("return") end
        end)
    end
    local function recoverDeath(player, model)
        s.questDepthEconomy=nil
        stopFarm()
        if not s.deadSince then s.deadSince = now() end
        if now() - s.deadSince < 8 then status("Waiting for death/respawn state to settle"); return end
        if player:GetAttribute("SavedExitTeleportLocked") == true then
            if player:GetAttribute("SavedExitRetryAvailable") == true then
                local c = controller("DeathScreenController")
                if c and c.SavedExitRetryRequest then status("Saved-gear return already in progress"); return end
                request("saved-return", "PlayerService", "SaveGear", pack(), function(result)
                    if accepted(result) then waitTransition("saved-return") end
                end)
            else status("Waiting for the game's saved-gear return") end
            return
        end
        local deadIdentity = model or s.lastCharacter or "missing"
        if s.awaiting and s.awaiting.kind=="revive" then
            status("Revive accepted; waiting for the character to become alive")
            return
        end
        if s.reviveIdentity ~= deadIdentity then
            local kit = (tonumber(player:GetAttribute("DeathChestReviveKits")) or 0) > 0
            local backpack = child(player, "Backpack")
            kit = kit or child(backpack, "ReviveKit") ~= nil
            local equipped = model and model:FindFirstChildOfClass("Tool")
            kit = kit or (equipped and equipped.Name == "ReviveKit")
            local credits = (tonumber(player:GetAttribute("ReviveCredits")) or 0) > 0
            if not kit and not credits and not s.freeReviveChecked then
                s.freeReviveProbeAt = s.freeReviveProbeAt or now()
                if now() - s.freeReviveProbeAt >= 10 then
                    s.freeReviveChecked, s.freeRevive = true, false
                    warn("[ChestFarm Auto] Free-revive check is unavailable or still pending; continuing death recovery without duplicating it.")
                else
                request("probe", "PlayerService", "CanUseTutorialFreeRevive", pack(), function(result)
                    s.freeReviveChecked, s.freeRevive = true, result[1] and result[2] == true
                end)
                return
                end
            end
            if s.freeRevive or kit or credits then
                request("revive", "PlayerService", "SelfRevive", pack(), function(result)
                    s.reviveIdentity = deadIdentity
                    if result[1] and result[2] == true and not result[3] then waitTransition("revive", deadIdentity, 20) end
                end)
                return
            end
            s.reviveIdentity = deadIdentity
        end
        reports.finish('LOSS', 'Died; no successful automatic revive remains. Returning to lobby.')
        returnToLobby()
    end
    local function skipCutscene()
        local c = controller("CutSceneController")
        if not c or not c.CurrentCutScene then
            s.cutsceneSkip = nil
            if c and c.AbortingCutScene then
                stopFarm(); status("Waiting for cutscene cleanup"); return true
            end
            return false
        end
        stopFarm()
        s.seatBlockedSince = nil -- A cutscene may deliberately seat/position the character.
        local context = c.CurrentCutSceneContext
        local runtimeId = context and context.RuntimeId
        local private = context and context.Private and runtimeId ~= nil or false
        local record = s.cutsceneSkip
        if not record or record.controller ~= c or record.session ~= c.CurrentCutSceneSessionId
            or record.name ~= c.CurrentCutScene or record.runtimeId ~= runtimeId or record.private ~= private then
            record = { controller = c, session = c.CurrentCutSceneSessionId,
                name = c.CurrentCutScene, runtimeId = runtimeId, private = private }
            s.cutsceneSkip = record
        end
        if c.AbortingCutScene or (context and context.DisableSkip == true) then
            status("Waiting for cutscene: " .. tostring(record.name)); return true
        end
        if not c.UI or not c.UI.Enabled or not c.SkipButton or not c.SkipButton.Visible then
            status("Waiting for the cutscene Skip button"); return true
        end
        if record.voted then
            status("Skip vote sent; waiting for cutscene completion"); return true
        end
        if now() >= (record.nextAttempt or 0) then
            -- These are the exact two calls made by CutSceneUI.Skip.MouseButton1Click.
            local method = private and "VoteSkipPrivate" or "VoteSkip"
            local args = private and pack(runtimeId, record.name) or pack(record.name, runtimeId)
            request("skip-cutscene", "CutSceneService", method, args, function(result)
                record.voted = accepted(result)
                record.nextAttempt = now() + 5
            end)
        end
        return true
    end
    local function tick()
        loadFresh()
        local player, model, humanoid, root = character()
        lobbyWalker.guard()
        if not game:IsLoaded() or not player or not child(player, "PlayerGui") then
            status("Waiting for game, LocalPlayer, and PlayerGui"); return
        end
        if not s.pauseNoticeHidden and now() >= (s.pauseNoticeRetryAt or 0) then
            s.pauseNoticeRetryAt = now() + 10
            local ok, reason = pcall(function()
                game:GetService("GuiService"):SetGameplayPausedNotificationEnabled(false)
            end)
            s.pauseNoticeHidden = ok
            if not ok and not s.pauseNoticeWarned then
                s.pauseNoticeWarned = true
                warn("[ChestFarm Auto] Pause notification setting unavailable; retrying: " .. tostring(reason))
            end
        end
        local serviceRoot, packages = services()
        if not serviceRoot then status("Waiting for replicated Knit services"); return end
        s.services = serviceRoot
        setup(player, packages)
        features.ui(player)
        if features.quest and features.quest.recoverDrive then pcall(features.quest.recoverDrive)end
        updateMetrics(player)
        local live = alive(player, model, humanoid, root)
        local isLobby = game.PlaceId == 101906032112547 or workspace:FindFirstChild("Lobby")
        local isPlanet = not isLobby and (game.PlaceId == 74507545904779 or workspace:GetAttribute("IsPlanet") == true)
        reports.arrived(isLobby)
        reports.observe(player, isPlanet, live)
        reports.pump()
        pumpRequest()
        if s.departureAt and not s.teleporting then
            if now() - s.departureAt < 30 then status("Waiting for departure/loading fade"); return end
            s.departureAt = nil
        end
        local awaitingPending = false
        if s.awaiting then
            local action = s.awaiting
            if action.kind == "revive" and live then s.awaiting = nil
            elseif action.kind == "end-session" and (not player:GetAttribute("PendingSessionId") or player:GetAttribute("PendingSessionId") == "") then s.awaiting = nil
            elseif action.kind == "exit-zone" and not ((controller("PartyCreateController") or {}).Zone or s.zone) then s.awaiting = nil
            elseif now() - action.started >= action.duration then
                s.awaiting = nil
                if action.kind == "rejoin" then s.failedSession = action.detail end
                status("Transition confirmation timed out; recovering")
            else status("Waiting for " .. action.kind .. " completion"); awaitingPending = true end
        end
        -- A delayed independent call must not delay cutscene/death handling.
        if isPlanet and not s.teleporting then
            if not live and (s.everReady or player:GetAttribute("RejoinDead") == true or (humanoid and humanoid.Health <= 0)) then
                recoverDeath(player, model)
                return
            end
            if skipCutscene() then return end
        end
        if awaitingPending then return end
        if s.teleporting then
            if now() - (s.teleportSince or now()) < 120 then return end
            failTeleport("no departure after 120 seconds")
        end
        if s.request then
            stopFarm(); status("Waiting for outstanding " .. tostring(s.request.kind) .. " transition request"); return
        end
        if isLobby then
            s.questDepthEconomy=nil
            s.deadSince, s.drillMissingSince, s.everReady = nil, nil, false
            s.lootStarted, s.extractionAttempt, s.extractionAttemptAt = nil, nil, nil
            s.churchSave, s.churchMemories = nil, nil
            s.questChurchExit, s.questActivity = nil, nil
            if not features.enabled() then stopFarm(); status("Both farm modes are off"); return end
            if features.questLobby() then lobbyWalker.stop(true);status(s.questStatus or "Waiting for equipped-class startup loadout"); return end
            lobby(player, model, humanoid, root)
            claimRewards(player)
            return
        end
        if not isPlanet then
            stopFarm(); status("Waiting for a recognized lobby/planet state"); return
        end
        if not features.enabled() then stopFarm(); status("Both farm modes are off"); return end
        if not live then
            if s.everReady or player:GetAttribute("RejoinDead") == true
                or (humanoid and humanoid.Health <= 0) then
                recoverDeath(player, model)
            else status("Waiting for the in-game character to load") end
            return
        end
        s.deadSince = nil
        if model ~= s.lastCharacter then
            stopFarm()
            s.lastCharacter, s.reviveIdentity = model, nil
            s.seatBlockedSince = nil
            s.freeReviveChecked, s.freeRevive = nil, nil
            s.freeReviveProbeAt = nil
        end
        if player:GetAttribute('SavedExitTeleportLocked') == true then
            stopFarm()
            if not s.forceFresh then
                s.forceFresh = true
                pcall(function() saveFresh(true) end)
            end
            local savedUI = controller('DeathScreenController')
            if player:GetAttribute('SavedExitRetryAvailable') == true and not (savedUI and savedUI.SavedExitRetryRequest) then
                request('saved-return', 'PlayerService', 'SaveGear', pack(), function(result)
                    if accepted(result) then waitTransition('saved-return') end
                end)
            else status('Game saved-exit state confirmed; waiting for lobby transfer') end
            return
        end
        features.checkQuestExit(s.farm)
        local drill = workspace:FindFirstChild("Drill")
        if not drill then
            stopFarm()
            if s.everReady then
                s.drillMissingSince = s.drillMissingSince or now()
                if now() - s.drillMissingSince >= 120 then s.returnReason = 'Drill missing for 120 seconds; automatic recovery'; returnToLobby(); return end
            end
            status("Waiting for the in-game Drill to load"); return
        end
        s.drillMissingSince, s.everReady = nil, true
        if workspace:GetAttribute("InfiniteRebasing") == true then
            stopFarm(); status("Waiting for the game's tunnel rebase"); return
        end
        local depthOffset = workspace:GetAttribute("InfiniteDepthOffsetMeters")
        if depthOffset ~= s.depthOffset then
            stopFarm()
            s.depthOffset = depthOffset
        end
        if not remote("TeleportManagerService", "TeleportToLobby") then status("Waiting for return-to-lobby readiness"); return end
        features.syncRoute(drill)
        if s.cacheDrill ~= drill then
            s.cacheDrill = drill
            s.seatBlockedSince = nil
        end
        if s.seatBlockedSince and now() - s.seatBlockedSince >= 30 then
            s.runExhausted = true
            status("Seat did not release after 30 seconds; recovering through a fresh solo run")
        end
        if s.farm and features.questQuickReturn(s.farm)then
            s.returnReason='Engineer placement counter confirmed; starter-only lobby loop'
            s.forceFresh=true;pcall(function()saveFresh(true)end)
            returnToLobby();return
        end
        features.checkQuestExit(s.farm)
        if s.runExhausted and not features.questPreventsExit() and (not features.questKeepsRun() and not features.extractionEnabled()
            or s.seatBlockedSince and now() - s.seatBlockedSince >= 30) then
            s.returnReason = s.seatBlockedSince and 'Seat recovery started a fresh chest run' or 'Chest route exhausted; starting a fresh run'
            s.forceFresh = true
            local ok = pcall(function() saveFresh(true) end)
            if not ok and not s.freshNotice then
                s.freshNotice = true
                warn("[ChestFarm Auto] Cannot persist exhausted-run intent through Roblox teleport settings; destination auto-execute may rejoin a pending session.")
            end
            returnToLobby(); return
        end
        local ctx = s.farm
        if ctx and ctx.currentChest and ctx.chestStarted
            and now() - ctx.chestStarted > 15 then
            local old, record = ctx.lootThread, ctx.currentChest
            if old and old ~= coroutine.running() then pcall(task.cancel, old) end
            if old and coroutine.status(old) ~= 'dead' then
                status('Chest call is stalled and cannot be cancelled; duplicate interaction blocked'); return
            end
            record.failures, record.retryAt = (record.failures or 0) + 1, now() + 300
            ctx.currentChest, ctx.lootThread, ctx.chestStarted = nil, nil, nil
            ctx.failed = 'Chest interaction exceeded 15 seconds; holding its retry while recovering the worker'
            print('[ChestFarm] ' .. ctx.failed)
        end
        if ctx then
            if type(features.snapshotPulse)=='function'then pcall(features.snapshotPulse,ctx)end
            features.watchdog(ctx)
        end
        if ctx and ctx.active and ctx.combatThread and now()>=(ctx.combatRestartAt or 0)then
            local thread,combat=ctx.combatThread,ctx.combat
            if coroutine.status(thread)=='dead' or combat and now()-(combat.pulse or now())>=20 then
                ctx.combatRestartAt=now()+2
                if coroutine.status(thread)~='dead' then pcall(task.cancel,thread)end
                if coroutine.status(thread)=='dead' then
                    if combat then pcall(combat.restoreAim)end
                    pcall(features.restoreWeaponSignal,ctx,thread)
                    ctx.combatThread=nil;startCombat(ctx,player,model,humanoid,root)
                    status('Recovered the combat worker; native cooldowns and quest progress retained')
                else status('Stalled native combat handler could not be cancelled; duplicate worker blocked')end
            end
        end
        local workerAlive = false
        if ctx then
            for thread in pairs(ctx.threads or {}) do
                if coroutine.status(thread) ~= "dead" then workerAlive = true; break end
            end
        end
        -- SCAN intentionally disables ChestFarm while its own TrackScan worker sweeps.
        -- Either mode is active work; restarting a live scan resets it to the train.
        if ctx and (ctx.character ~= model or ctx.humanoid ~= humanoid or ctx.root ~= root or ctx.drill ~= drill or ctx.failed
            or (ctx.initialized and ((not ctx.flags.ChestFarm and not ctx.flags.TrackScan) or not workerAlive))) then
            local exhausted = ctx.exhausted
            local reason = ctx.failed or (ctx.character ~= model and "character changed")
                or ((ctx.humanoid ~= humanoid or ctx.root ~= root) and "character parts changed")
                or (ctx.drill ~= drill and "Drill changed")
                or (not workerAlive and "workers finished") or "both farm modes finished"
            stopFarm(); s.farmRestartAt = now() + (exhausted and 5 or 3)
            status("Restarting farm: " .. tostring(reason))
        end
        if not s.farm and now() >= (s.farmRestartAt or 0) then startFarm(player, model, humanoid, root, drill) end
        claimRewards(player)
    end
    s.thread = task.spawn(function()
        while owned() do
            local ok, why = pcall(tick)
            if not ok then
                stopFarm()
                status("Recovering from an action error: " .. tostring(why))
                s.nextAction = now() + 3
            end
            task.wait(0.5)
        end
    end)
end

]======]
local loader = loadstring or load
assert(type(loader) == "function", "ChestFarm: this executor must support loadstring")
local entry, why = loader(SOURCE, "@DTEC JoeJoe Automation")
assert(entry, why)
entry()(SOURCE)
