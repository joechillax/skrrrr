-- JoesAAS 5.7 | standalone source | October 2026
-- Built against the supplied client export. See JoesAAS-README.md for limits and validation.
-- Fluent UI from dawid-scripts/Fluent. Settings save and restore automatically; each feature uses its own toggle.
local environment = (type(getgenv) == "function" and getgenv()) or _G
local previous = environment.JoesAAS or environment.AnimeSuite
if previous and type(previous.stop) == "function" then pcall(previous.stop) end
if game.GameId ~= 10502841145 then
    warn("JoesAAS: this build targets the exported game's universe, not this experience.")
    return
end
local A = {}
environment.JoesAAS = A
environment.AnimeSuite = A -- Compatibility with older running versions.
A.Core = (function()
local Core = {}
Core.defaultPriority={'MaxTac','Tower','TimeTrial','Dungeon','Gate','Combat','BossRush'}
Core.priorityLabels={MaxTac='MaxTac',Tower='Tower',TimeTrial='Time Trials',Dungeon='Dungeon',Gate='Gate',Combat='Raid / Defense',BossRush='Boss Rush'}
function Core.copy(t)
    if type(t) ~= 'table' then return t end
    local out = {}; for k,v in pairs(t) do out[k] = Core.copy(v) end; return out
end
function Core.keys(t)
    local out = {}; for k in pairs(t or {}) do out[#out+1] = k end
    table.sort(out, function(a,b) return tostring(a)<tostring(b) end); return out
end
function Core.contains(list, value)
    for _,v in ipairs(list or {}) do if tostring(v)==tostring(value) then return true end end
    return false
end
function Core.merge(defaults, saved)
    local result = Core.copy(defaults)
    if type(saved)~='table' then return result end
    for k,v in pairs(defaults) do
        if type(saved[k])==type(v) then
            if type(v)=='table' then result[k]=Core.copy(saved[k]) else result[k]=saved[k] end
        end
    end
    return result
end
function Core.singleSelection(selection)
    local result={}
    for _,key in ipairs(Core.keys(selection)) do
        if type(key)=='string' and selection[key]==true then result[key]=true; break end
    end
    return result
end
function Core.equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not Core.equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
function Core.priorityOrder(saved)
    local result,seen={},{}
    for _,key in ipairs(type(saved)=='table' and saved or {}) do
        if Core.priorityLabels[key] and not seen[key] then result[#result+1]=key; seen[key]=true end
    end
    for _,key in ipairs(Core.defaultPriority) do if not seen[key] then result[#result+1]=key end end
    return result
end
function Core.portalMode(key,cfg)
    if cfg and cfg.GateOnly~=true then return nil end
    if tostring(key):lower():find('maxtac',1,true)
        or (cfg and (tostring(cfg.AchievementModeKey):find('^MaxTacCall') or tostring(cfg.Name):lower():find('maxtac',1,true))) then return 'MaxTac' end
    return 'Gate'
end
function Core.renameEligible(id,pet,named,target,petStats)
    if type(id)~='string' or type(pet)~='table' then return false,'unexpected inventory format' end
    if not petStats or type(petStats.GetRarity)~='function' then return false,'rarity API missing' end
    if petStats.GetRarity(pet)~='Astral' then return false,'not Astral' end
    -- Match NamedStateUtil.IsNamed: only a table is a naming record.
    if type(named)=='table' and type(named[id])=='table' then return false,'existing named record' end
    -- Pet.Name is catalog data; the game stores custom names in NamedPets.
    if petStats and petStats.IsDynamicById and petStats.IsDynamicById(pet.PetId) then return false,'percentage pet' end
    return true,'eligible'
end
function Core.activityKeys(choices,mode)
    local keys=Core.keys(choices)
    local function trialRank(key)
        local label=(tostring(key)..' '..tostring(choices[key].Name or '')):lower()
        for rank,name in ipairs({'insane','hard','medium','easy'}) do
            if label:find('%f[%a]'..name..'%f[%A]') then return rank end
        end
        return 5
    end
    table.sort(keys,function(a,b)
        local x,y
        if mode=='TimeTrial' then x,y=trialRank(a),trialRank(b)
        else x,y=tonumber(choices[a].WorldId) or math.huge,tonumber(choices[b].WorldId) or math.huge end
        if x~=y then return x<y end
        local an,bn=tostring(choices[a].Name or a),tostring(choices[b].Name or b)
        if an~=bn then return an<bn end
        return tostring(a)<tostring(b)
    end)
    return keys
end
function Core.chooseTarget(items,mode)
    table.sort(items,function(a,b)
        if mode=='Highest HP' and a.health~=b.health then return a.health>b.health end
        if mode=='Lowest HP' and a.health~=b.health then return a.health<b.health end
        if a.distance~=b.distance then return a.distance<b.distance end
        return a.id<b.id
    end)
    return items[1]
end
function Core.webhookRetry(status,headers,body,attempt)
    if status>=200 and status<300 then return 'done',0 end
    if status==429 then
        local delay=tonumber(body and body.retry_after)
        for k,v in pairs(headers or {}) do
            if tostring(k):lower()=='retry-after' then delay=tonumber(v) or delay end
        end
        return 'retry',math.max(1,delay or 5)
    end
    if status==0 or status>=500 then return 'retry',math.min(120,2^attempt) end
    return 'stop',0
end
return Core

end)()
local bootOK, bootError = pcall(function()

-- ===== runtime =====
(function()
return function(A)
    local Core=A.Core
    A.S={Players=game:GetService('Players'),RS=game:GetService('ReplicatedStorage'),
        Run=game:GetService('RunService'),HTTP=game:GetService('HttpService'),
        UIS=game:GetService('UserInputService'),Gui=game:GetService('GuiService')}
    A.player=A.S.Players.LocalPlayer
    A.logs={}; A.status={}; A.connections={}; A.tasks={}; A.cache={}; A.cooldowns={}
    A.alive=true; A.running=false; A.epoch=0; A.started=os.clock()
    A.defaults={version=4,priority=Core.copy(Core.defaultPriority),world='0',mobsByWorld={},target='Nearest',farm=false,trialFollow=false,trialAutoJoin=false,trialJoinSelection={},
        towerAutoJoin=false,towerSelection={},raidAutoJoin=false,raidSelection={},defenseAutoJoin=false,defenseSelection={},
        gateAutoJoin=false,gateSelection={},gateRanks={S=true,A=true,B=true,C=true,D=true,E=true},
        maxTacAutoJoin=false,maxTacSelection={},maxTacRanks={Low=true,Medium=true,High=true,Extreme=true,Psycho=true},
        dungeonAutoJoin=false,dungeonSelection={},bossRushAutoJoin=false,bossRushSelection={},
        rename=false,petName='',webhook=false,webhookURL='',pingId='',ping=false,sendDisconnect=true,
        webhookEvents={Disconnect=true,Mode=true,Progress=true,Error=true,Inventory=true},
        pingEvents={Disconnect=true,Error=true,Mode=false,Progress=false,Inventory=false},
        blackScreen=false,moveStyle='Walk',distance=5,saveSecrets=false,ripperdocAuto=false,ripperdocSlots={},
        autoLeaveStuck=true,stuckSeconds=10,trialDungeonStuckSeconds=20,fixerAutoClaim=false}
    A.legacyFolder='AnimeSuite_'..tostring(game.GameId)..'_'..tostring(A.player.UserId)
    A.folder='JoesAAS/'..tostring(game.GameId)..'_'..tostring(A.player.UserId)
    A.file=A.folder..'/settings.json'
    function A.log(kind,text)
        text=tostring(text)
        text=text:gsub('https://[^%s]+/api/webhooks/[^%s]+','[webhook redacted]')
        local line=os.date('%H:%M:%S')..' ['..kind..'] '..text
        A.logs[#A.logs+1]=line; if #A.logs>150 then table.remove(A.logs,1) end
        print('[JoesAAS] '..line)
    end
    function A.connect(signal,fn)
        local c=signal:Connect(function(...)
            if A.alive then
                local ok,err=pcall(fn,...)
                if not ok then A.status.Event=tostring(err); A.log('Event',err) end
            end
        end)
        A.connections[#A.connections+1]=c; return c
    end
    function A.safeLoad(path)
        if type(readfile)~='function' then return nil end
        local ok,value=pcall(function() return A.S.HTTP:JSONDecode(readfile(path)) end)
        if ok and type(value)=='table' then return value end
    end
    function A.validate(saved)
        local s=Core.merge(A.defaults,saved)
        if type(saved)=='table' and saved.dungeonFollow==true then s.trialFollow=true end
        local n=tonumber(s.distance); s.distance=(n and n==n and n<math.huge) and n or 5
        s.distance=math.clamp(s.distance,2,20)
        for _,key in ipairs({'stuckSeconds','trialDungeonStuckSeconds'}) do
            local value=tonumber(s[key])
            s[key]=(value and value==value and value<math.huge) and math.clamp(value,1,3600) or A.defaults[key]
        end
        if not Core.contains({'Nearest','Highest HP','Lowest HP'},s.target) then s.target='Nearest' end
        if not Core.contains({'Walk','Teleport'},s.moveStyle) then s.moveStyle='Walk' end
        for _,k in ipairs({'webhookEvents','pingEvents','trialJoinSelection','towerSelection','raidSelection','defenseSelection','dungeonSelection','gateSelection','gateRanks','maxTacSelection','maxTacRanks','bossRushSelection','ripperdocSlots'}) do
            for id,v in pairs(s[k]) do if type(id)~='string' or type(v)~='boolean' then s[k][id]=nil end end
        end
        for world,selection in pairs(s.mobsByWorld) do
            if type(world)~='string' or type(selection)~='table' then s.mobsByWorld[world]=nil else
                for id,value in pairs(selection) do if type(id)~='string' or type(value)~='boolean' then selection[id]=nil end end
            end
        end
        s.raidSelection=Core.singleSelection(s.raidSelection)
        s.defenseSelection=Core.singleSelection(s.defenseSelection)
        if s.raidAutoJoin and s.defenseAutoJoin then s.defenseAutoJoin=false end
        -- Separate the previous combined Gate / MaxTac profile.
        local movedMaxTac=false
        for key,value in pairs(Core.copy(s.gateSelection)) do
            if Core.portalMode(key)=='MaxTac' then
                movedMaxTac=true
                if s.maxTacSelection[key]==nil then s.maxTacSelection[key]=value end
                if value and s.gateAutoJoin and (not saved or saved.maxTacAutoJoin==nil) then s.maxTacAutoJoin=true end
                s.gateSelection[key]=nil
            end
        end
        if movedMaxTac then
            local remaining=false
            for _,selected in pairs(s.gateSelection) do if selected then remaining=true; break end end
            if not remaining then s.gateAutoJoin=false end
        end
        for _,rank in ipairs({'Low','Medium','High','Extreme','Psycho'}) do
            if type(saved)=='table' and type(saved.gateRanks)=='table' and type(saved.gateRanks[rank])=='boolean'
                and saved.maxTacRanks==nil then s.maxTacRanks[rank]=saved.gateRanks[rank] end
            s.gateRanks[rank]=nil
        end
        for rank in pairs(s.maxTacRanks) do if A.defaults.maxTacRanks[rank]==nil then s.maxTacRanks[rank]=nil end end
        s.priority=Core.priorityOrder(s.priority)
        s.version=4; return s
    end
    function A.setCombatEnabled(mode,value)
        local own=mode=='Raid' and 'raidAutoJoin' or 'defenseAutoJoin'
        local other=mode=='Raid' and 'defenseAutoJoin' or 'raidAutoJoin'
        A.settings[own]=value==true
        if value then A.settings[other]=false end
        if A.settingsChanged then A.settingsChanged() end
        if A.refreshUI then A.refreshUI() end
        if A.coordinateActivities then A.coordinateActivities() end
    end
    -- Copy previous settings once; never overwrite a new-folder file.
    if type(makefolder)=='function' and type(readfile)=='function' and type(writefile)=='function' then
        pcall(makefolder,'JoesAAS'); pcall(makefolder,A.folder)
        if not A.safeLoad(A.folder..'/migration.json') then
            local function copyLegacy(name)
                local destination=A.folder..'/'..name
                if pcall(readfile,destination) then return end
                local ok,bytes=pcall(readfile,A.legacyFolder..'/'..name)
                if not ok then return end
                writefile(destination,bytes)
                assert(readfile(destination)==bytes,'Migration read-back failed: '..name)
            end
            local ok,err=pcall(function()
                for _,name in ipairs({'settings.json','settings.json.bak'}) do copyLegacy(name) end
                writefile(A.folder..'/migration.json',A.S.HTTP:JSONEncode({complete=true}))
            end)
            assert(ok,'Could not preserve previous saves: '..tostring(err)..'. Old files are untouched; rerun to retry.')
        end
    end
    local saved=A.safeLoad(A.file..'.tmp') or A.safeLoad(A.file) or A.safeLoad(A.file..'.bak')
    A.settings=A.validate(saved)
    local lastSaved,saveDue,saveRetry,saveBusy,saveReady,nextCheck=nil,nil,0,false,false,0
    local function settingsSnapshot()
        local snapshot=Core.copy(A.settings)
        if not snapshot.saveSecrets then snapshot.webhookURL='' end
        return snapshot
    end
    function A.finishStartup()
        saveReady=true; A.saveSettings(true)
        A.setRunning(true)
        if A.flushJoinDiagnostics then A.flushJoinDiagnostics(true) end
    end
    function A.saveSettings(force)
        if not saveReady or saveBusy then return false end
        local snapshot=settingsSnapshot()
        if Core.equal(snapshot,lastSaved) then saveDue=nil; return true end
        if not force and os.clock()<saveRetry then return false end
        if type(writefile)~='function' or type(readfile)~='function' or type(makefolder)~='function' then
            A.status.Settings='Autosave unavailable: executor file APIs missing; settings are session-only.'
            saveRetry=os.clock()+30; return false
        end
        saveBusy=true
        local ok,err=pcall(function()
            pcall(makefolder,A.folder)
            local encoded=A.S.HTTP:JSONEncode(snapshot)
            local staged=A.file..'.tmp'
            writefile(staged,encoded)
            assert(Core.equal(A.safeLoad(staged),snapshot),'Staged settings read-back failed')
            local prior=A.safeLoad(A.file)
            if prior then
                if not snapshot.saveSecrets then prior.webhookURL='' end
                writefile(A.file..'.bak',A.S.HTTP:JSONEncode(prior))
            end
            writefile(A.file,encoded)
            assert(Core.equal(A.safeLoad(A.file),snapshot),'Settings read-back failed')
            -- A valid staged file recovers a save interrupted before the main write.
            if type(delfile)=='function' then pcall(delfile,staged) else pcall(writefile,staged,'') end
        end)
        saveBusy=false
        if ok then
            lastSaved=snapshot; saveDue=nil; saveRetry=0
            A.status.Settings='Settings saved automatically; restored next execution.'
        else
            saveRetry=os.clock()+10; A.status.Settings='Autosave failed; retrying: '..tostring(err)
            A.log('Settings',A.status.Settings)
        end
        return ok
    end
    function A.settingsChanged(delay)
        if not saveReady or not A.alive or A.stopping then return end
        if delay and delay>0 then saveDue=os.clock()+delay else A.saveSettings() end
    end
    function A.module(kind,name)
        local key=kind..':'..name
        if A.cache[key] then return A.cache[key] end
        local folder=kind=='Config' and A.Library.Config or kind=='Client' and A.Library.Client
            or kind=='Utils' and A.Library.Utils or A.Library.Packages
        if not folder or not folder:FindFirstChild(name) then return nil end
        local getter=kind=='Config' and A.Library.getConfig or kind=='Client' and A.Library.getClient
            or kind=='Utils' and A.Library.getUtil or A.Library.getPackage
        local ok,result=pcall(getter,name)
        if ok and type(result)=='table' then A.cache[key]=result; return result end
        A.status[key]='Module unavailable'; return nil
    end
    function A.config(name) return A.module('Config',name) end
    function A.util(name) return A.module('Utils',name) end
    function A.client(name) return A.module('Client',name) end
    function A.data()
        if A.container and A.container.Ready and type(A.container.Data)=='table' then return A.container.Data end
        return nil
    end
    function A.number(value)
        if type(value)=='number' then return value==value and value or 0 end
        local big=A.util('BigNum')
        if big and type(big.ToFiniteNumber)=='function' then
            local ok,n=pcall(function()
                local parsed=big.TryFrom and big.TryFrom(value) or (big.Decode and big.Decode(value))
                return parsed and big.ToFiniteNumber(parsed)
            end)
            if ok and type(n)=='number' and n==n then return n end
        end
        local p=A.util('NumberParser'); return p and p.Parse(value) or tonumber(value) or 0
    end
    function A.balance(key)
        local data=A.data(); if not data then return 0 end
        return math.max(0,A.number(data[key]))
    end
    function A.ready(key,seconds)
        local now=os.clock(); if (A.cooldowns[key] or 0)>now then return false end
        A.cooldowns[key]=now+(seconds or 1); return true
    end
    function A.bridge(name)
        -- Do not create guessed bridges; only use the game's declared registry.
        local known=A.Library.Network.Bridges.KnownNames
        if type(known)~='table' or known[name]~=true then return nil end
        local key='Bridge:'..name
        if not A.cache[key] then A.cache[key]=A.Library.getBridge(name) end
        return A.cache[key]
    end
    function A.fire(name,...)
        if not A.alive then return false end
        local first=select(1,...)
        if not A.running and not (name=='RangeToggle' and first==false) then return false end
        local b=A.bridge(name)
        if not b then A.status[name]='Bridge unavailable'; return false end
        local ok,err=pcall(b.Fire,b,...)
        if not ok then A.log('Remote',name..': '..tostring(err)) end
        return ok
    end
    function A.on(name,fn)
        local b=A.bridge(name); if b then return A.connect(b,fn) end
    end
    function A.job(name,interval,fn,always)
        A.tasks[name]={name=name,interval=interval,fn=fn,always=always,next=0,busy=false,failures=0}
    end
    function A.setRunning(value)
        A.running=value; A.epoch=A.epoch+1
        A.status.Gameplay=value and 'Ready: each feature uses its own toggle' or 'Stopped or disconnected; rerun after reconnecting'
        if not value then
            A.saveSettings(true)
            if A.stopFarmMovement then A.stopFarmMovement() end
            if A.stopTrialMovement then A.stopTrialMovement() end
            if A.stopDungeonMovement then A.stopDungeonMovement() end
            if A.watchTarget then A.watchTarget(nil) end
            local h=A.player.Character and A.player.Character:FindFirstChildOfClass('Humanoid')
            if h then h:Move(Vector3.zero) end
            if A.rangeOwned then A.fire('RangeToggle',false); A.rangeOwned=false end
        end
        A.log('Run',value and 'Started enabled features.' or 'Paused automation.')
    end
    function A.stop()
        if not A.alive then return end
        A.stopping=true
        if A.flushJoinDiagnostics then A.flushJoinDiagnostics() end
        A.setRunning(false); if A.render then A.render(false) end
        if A.cleanupTrialMovement then A.cleanupTrialMovement() end
        if A.cleanupDungeonMovement then A.cleanupDungeonMovement() end
        A.alive=false
        for _,c in ipairs(A.connections) do pcall(function() c:Disconnect() end) end
        if A.fluent then A.fluent:Destroy() elseif A.gui then A.gui:Destroy() end
        if A.overlay then A.overlay:Destroy() end
        if A.touchGui then A.touchGui:Destroy() end
    end
    function A.schedule()
        function A.runJob(job)
            if not A.alive or job.busy or not (job.always or A.running) then return end
            job.busy=true; job.next=os.clock()+job.interval
            local epoch=A.epoch
            task.spawn(function()
                if not A.alive or (not job.always and (not A.running or A.epoch~=epoch)) then job.busy=false; return end
                local ok,err=pcall(job.fn)
                job.busy=false
                if ok then job.failures=0 else
                    job.failures=job.failures+1
                    job.next=os.clock()+math.min(120,2^job.failures)
                    A.status[job.name]=tostring(err)
                    A.log('Error',job.name..': '..tostring(err))
                    if job.failures==3 and A.notify then A.notify('Error',job.name..' failed repeatedly; backing off.') end
                end
            end)
        end
        task.spawn(function()
            while A.alive do
                local now=os.clock()
                for _,job in pairs(A.tasks) do
                    if not job.busy and now>=job.next and (job.always or A.running) then
                        A.runJob(job)
                    end
                end
                task.wait(0.2)
            end
        end)
    end
    local root=A.S.RS:WaitForChild('SimpleWorld',20)
    assert(root and root:FindFirstChild('Library'),'SimpleWorld.Library not found; wait for the game to load.')
    A.Library=require(root.Library)
    local package=A.module('Packages','DataContainer')
    assert(package and package.New,'PlayerData interface unavailable')
    A.container=package.New('PlayerData')
    A.job('Settings autosave',0.2,function()
        local now=os.clock()
        if saveDue then
            if now<saveDue or now<saveRetry then return end
        elseif now<nextCheck or now<saveRetry then return end
        nextCheck=now+2; A.saveSettings()
    end,true)
    A.job('Connection cleanup',60,function()
        local live={}
        for _,c in ipairs(A.connections) do
            local ok,connected=pcall(function() return c.Connected end)
            if not ok or connected~=false then live[#live+1]=c end
        end
        A.connections=live
    end,true)
    A.log('Startup','Standalone suite loaded. Settings ready.')
end

end)()(A);

-- ===== notifications =====
(function()
return function(A)
    A.outbox={}
    for _,entry in ipairs(A.safeLoad(A.folder..'/outbox.json') or {}) do
        if type(entry)=='table' and not entry.attachment and A.settings.webhookEvents[entry.kind]~=nil then
            A.outbox[#A.outbox+1]=entry
            if #A.outbox>=50 then break end
        end
    end
    A.httpRequest=(type(request)=='function' and request) or (type(http_request)=='function' and http_request)
        or (type(http)=='table' and type(http.request)=='function' and http.request)
        or (type(syn)=='table' and type(syn.request)=='function' and syn.request)
    A.webhookNext=0
    local env=(type(getgenv)=='function' and getgenv()) or _G
    env.AnimeSuiteHTTP=env.AnimeSuiteHTTP or {busy=false}
    local transport=env.AnimeSuiteHTTP
    local function fingerprint(url)
        local n=0; for i=1,#url do n=(n*31+url:byte(i))%2147483647 end; return tostring(n)
    end
    local function persist()
        if type(writefile)=='function' and type(makefolder)=='function' then
            local ok,err=pcall(function() pcall(makefolder,A.folder); writefile(A.folder..'/outbox.json',A.S.HTTP:JSONEncode(A.outbox)) end)
            if not ok then A.status.Webhook='Outbox save failed: '..tostring(err); A.log('Webhook',A.status.Webhook) end
            return ok
        end
        return false
    end
    function A.http(options,completeOnStop)
        if not A.httpRequest then return false,'HTTP request API unavailable' end
        if transport.busy then return false,'HTTP already in flight' end
        options.Timeout=15
        A.httpBusy=true; transport.busy=true; local response
        task.spawn(function() response=table.pack(pcall(A.httpRequest,options)); A.httpBusy=false; transport.busy=false end)
        local deadline=os.clock()+15
        while (A.alive or completeOnStop) and not response and os.clock()<deadline do task.wait(0.05) end
        if not response then return false,'HTTP timed out; waiting for transport to recover' end
        return table.unpack(response,1,response.n)
    end
    function A.notify(kind,message,force)
        local s=A.settings
        if not s.webhook then A.status.Webhook='Webhook disabled: enable it in this tab'; return end
        if not force and s.webhookEvents[kind]==false then return end
        if kind=='Disconnect' and not s.sendDisconnect then return end
        s.webhookURL=s.webhookURL:match('^%s*(.-)%s*$')
        if not s.webhookURL:match('^https://discord%.com/api/webhooks/%d+/[%w_%-]+')
            and not s.webhookURL:match('^https://discordapp%.com/api/webhooks/%d+/[%w_%-]+') then
            A.status.Webhook='Enter a Discord webhook URL'; return
        end
        if #A.outbox>=50 then table.remove(A.outbox,1) end
        local ping=s.ping and kind~='Test' and s.pingEvents[kind]~=false and s.pingId:match('^%d+$') and s.pingId or nil
        A.outbox[#A.outbox+1]={kind=kind,message=tostring(message):sub(1,1500),time=os.time(),attempt=0,
            target=fingerprint(s.webhookURL),ping=ping}
        persist(); A.webhookNext=kind=='Disconnect' and 0 or A.webhookNext
        A.status.Webhook='Queued '..kind..' ('..#A.outbox..' waiting)'
        return A.outbox[#A.outbox]
    end
    A.job('Webhook delivery',1,function()
        if not A.alive or not A.settings.webhook or #A.outbox==0 or os.clock()<A.webhookNext then return end
        if transport.busy then A.status.Webhook='Waiting for executor HTTP request to finish'; return end
        local entry=A.outbox[1]
        if type(entry)~='table' or type(entry.message)~='string' or entry.target~=fingerprint(A.settings.webhookURL) then
            table.remove(A.outbox,1); persist(); return
        end
        local payload={content=entry.ping and ('<@'..entry.ping..'>') or '',
            embeds={{title='JoesAAS / '..tostring(entry.kind),description=entry.message,
                footer={text='Place '..tostring(game.PlaceId)..' | event '..tostring(entry.time)}}}}
        local contentType='application/json'; local data=A.S.HTTP:JSONEncode(payload)
        -- Empty Lua tables may encode as objects. Discord requires arrays here.
        local mentions='"allowed_mentions":{"parse":[],"users":'
            ..(entry.ping and ('['..A.S.HTTP:JSONEncode(entry.ping)..']') or '[]')..'}'
        data=data:sub(1,-2)..','..mentions..'}'
        local url=A.settings.webhookURL:gsub('([?&])wait=[^&]*','%1wait=true')
        if not url:find('wait=',1,true) then url=url..(url:find('?',1,true) and '&' or '?')..'wait=true' end
        local ok,response=A.http({Url=url,Method='POST',Headers={['Content-Type']=contentType},Body=data})
        if not A.alive then return end
        local status=ok and type(response)=='table' and tonumber(response.StatusCode or response.Status) or 0
        local body; if ok and type(response)=='table' then
            local parsed,value=pcall(A.S.HTTP.JSONDecode,A.S.HTTP,response.Body or '')
            if parsed and type(value)=='table' then body=value end
        end
        entry.attempt=(tonumber(entry.attempt) or 0)+1
        local action,delay=A.Core.webhookRetry(status or 0,ok and type(response)=='table' and response.Headers or {},body,entry.attempt)
        if action=='done' then
            table.remove(A.outbox,1); A.status.Webhook='Delivered '..tostring(entry.kind); A.webhookNext=os.clock()+2
        elseif action=='stop' then
            table.remove(A.outbox,1); A.status.Webhook='Rejected with HTTP '..tostring(status)..'; check webhook URL'
            -- Keep the user's toggle intact; report the rejection instead of silently disabling it.
        elseif entry.attempt>=8 and status~=429 then
            table.remove(A.outbox,1); A.status.Webhook='Failed after 8 attempts; event dropped'
        else
            A.webhookNext=os.clock()+delay; A.status.Webhook='Retry in '..math.ceil(delay)..'s (HTTP '..tostring(status)..')'
        end
        if action~='done' then
            local detail=type(response)=='table' and tostring(response.Body or ''):sub(1,500) or tostring(response):sub(1,500)
            detail=detail:gsub('https://[^%s"<>]+/api/webhooks/[^%s"<>]+','[webhook redacted]')
            A.status.Webhook=A.status.Webhook..' | '..detail
            A.log('Webhook',A.status.Webhook)
        end
        A.webhookDiagnostic={at=os.time(),kind=entry.kind,httpStatus=status,attempt=entry.attempt,
            result=A.status.Webhook,transportAvailable=type(A.httpRequest)=='function'}
        if type(writefile)=='function' then
            pcall(function() writefile(A.folder..'/webhook-diagnostics.json',A.S.HTTP:JSONEncode(A.webhookDiagnostic)) end)
        end
        persist()
    end,true)
    local sent=false
    function A.isDisconnectMessage(message)
        local text=tostring(message or ''):lower()
        for _,phrase in ipairs({'disconnected','lost connection','connection lost','kicked from','shut down','shutdown','reconnect','same account launched','internet connection'}) do
            if text:find(phrase,1,true) then return true end
        end
        return false
    end
    local function disconnected(message)
        if not sent and A.isDisconnectMessage(message) then
            sent=true; A.notify('Disconnect','Client connection/error message: '..tostring(message))
            A.status.Gameplay='Disconnected: rerun the script after reconnecting'
            A.setRunning(false)
            if A.runJob and A.tasks['Webhook delivery'] then A.runJob(A.tasks['Webhook delivery']) end
        end
    end
    local connected=false
    local ok,signal=pcall(function() return A.S.Gui.ErrorMessageChanged end)
    if ok and signal then
        local hooked=pcall(A.connect,signal,disconnected); connected=hooked or connected
    end
    local modernOK,modern=pcall(function() return A.S.Gui.UiMessageChanged end)
    if modernOK and modern then
        local hooked=pcall(A.connect,modern,function(kind,message)
            if tostring(kind):lower():find('error',1,true) then disconnected(message) end
        end)
        connected=hooked or connected
    end
    A.status.Disconnect=connected and 'Error-message listener connected' or 'Error-message signals unavailable in this executor'
    A.job('Disconnect fallback',2,function()
        if not sent and (A.settings.webhook and A.settings.sendDisconnect) then
            local readOK,message=pcall(function() return A.S.Gui:GetErrorMessage() end)
            if readOK and type(message)=='string' and message~='' then disconnected(message) end
        end
    end,true)
    A.connect(A.player.OnTeleport,function(state)
        if state==Enum.TeleportState.Started then A.notify('Mode','Teleporting to another server. Run the suite again after arrival.') end
    end)
end

end)()(A);

-- ===== discovery =====
(function()
return function(A)
    local C=A.Core
    A.catalog={worlds={},enemies={}}
    function A.unlocked(id)
        local cfg=A.config('WorldConfig'); local d=A.data()
        return d and cfg and cfg:IsUnlocked(tonumber(id),d) or false
    end
    function A.currentWorld()
        local ctrl=A.client('WorldController')
        return ctrl and ctrl:GetCurrentWorld() or (A.data() or {}).CurrentWorld
    end
    function A.discover()
        local cat=A.catalog
        local world=A.config('WorldConfig'); if world then cat.worlds=world:GetAllWorlds() end
        local enemy=A.config('EnemyConfig'); if enemy then cat.enemies=enemy:GetAllEnemies() end
        A.status.Discovery=string.format('%d worlds / %d enemies',#C.keys(cat.worlds),#C.keys(cat.enemies))
        if A.refreshUI then A.refreshUI() end
    end
    A.discover()
    A.job('Discovery',30,function()
        if A.settings.farm then A.discover() end
    end)
    A.on('WorldChanged',function(id)
        A.confirmedWorld=tonumber(id); A.status.World=tostring(id)
    end)
end

end)()(A);

-- ===== spending =====
(function()
return function(A)
    local C=A.Core
    A.sessionNamed={}
    function A.renameDiagnostics()
        local d=A.data() or {}; local stats=A.util('PetStatsUtil')
        local report={version='5.7',status=A.status.Rename,inventoryType=type(d.Pets),namedType=type(d.NamedPets),total=0,reasons={},rarities={},samples={},
            inventoryEvents=A.renameInventoryEvents or 0,lastInventoryEvent=A.renameLastInventoryEvent}
        local named=type(d.NamedPets)=='table' and d.NamedPets or {}
        local sampled={}
        for _,id in ipairs(C.keys(type(d.Pets)=='table' and d.Pets or {})) do
            local pet=d.Pets[id]; report.total=report.total+1
            local ok,eligible,reason=pcall(C.renameEligible,id,pet,named,A.settings.petName,stats)
            reason=ok and (A.sessionNamed[id] and 'renamed this session' or reason) or 'eligibility error'
            report.reasons[reason]=(report.reasons[reason] or 0)+1
            local rarityOK,rarity=pcall(function() return stats.GetRarity(pet) end)
            rarity=rarityOK and tostring(rarity) or 'unknown'
            report.rarities[rarity]=(report.rarities[rarity] or 0)+1
            if #report.samples<40 and (sampled[reason] or 0)<5 then
                sampled[reason]=(sampled[reason] or 0)+1
                report.samples[#report.samples+1]={id=tostring(id),idType=type(id),petType=type(pet),
                    petId=type(pet)=='table' and tostring(pet.PetId) or '',rarity=rarity,reason=reason,
                    inventoryRarity=type(pet)=='table' and tostring(pet.Rarity) or '',
                    namedRecordType=type(named[id]),
                    fields=type(pet)=='table' and C.keys(pet) or {}}
            end
        end
        return report
    end
    local lastDiagnostic,nextDiagnostic=nil,0
    local function saveDiagnostic()
        if A.status.Rename==lastDiagnostic or os.clock()<nextDiagnostic then return end
        nextDiagnostic=os.clock()+60
        local ok,err=pcall(function()
            assert(type(writefile)=='function','File writing unavailable')
            writefile(A.folder..'/rename-diagnostics.json',A.S.HTTP:JSONEncode(A.renameDiagnostics()))
        end)
        if ok then lastDiagnostic=A.status.Rename end
        A.status['Rename report']=ok and ('Saved '..A.folder..'/rename-diagnostics.json')
            or ('Could not save rename report: '..tostring(err))
    end
    local pending,retries,retryAfter={},{},{}
    local nextRename=0
    A.renamePending=nil
    local function isConfirmed(id)
        local d=A.data()
        return d and type(d.NamedPets)=='table' and type(d.NamedPets[id])=='table'
    end
    local function finish(id,success,reason)
        if success then
            A.sessionNamed[id]=true; retries[id]=nil
            A.status.Rename='Named Astral: '..id
            if A.settings.webhook then A.notify('Inventory','Renamed an unnamed Astral pet: '..id) end
        else
            if (retries[id] or 0)>=3 then retryAfter[id]=os.clock()+120 end
            A.status.Rename='Rename failed for '..id..': '..tostring(reason)
            A.log('Rename',A.status.Rename)
        end
        pending[id]=nil; A.renamePending=nil
    end
    A.on('NameRenameResult',function(accepted,reason,payload)
        local id=A.renamePending
        if not id then return end
        if type(payload)=='table' and ((payload.UniqueId and payload.UniqueId~=id)
            or (payload.Kind and payload.Kind~='Pet')) then return end
        -- An uncorrelated rejection may belong to another script or the game's UI.
        if accepted==true and type(payload)=='table' and (payload.Kind==nil or payload.Kind=='Pet')
            and payload.UniqueId==id then finish(id,true)
        elseif type(payload)=='table' and payload.UniqueId==id then
            finish(id,false,reason)
        end
    end)
    local function renameStep()
        local d=A.data()
        if not d then A.status.Rename='Waiting for player data'; return end
        local id=A.renamePending
        if id then
            if isConfirmed(id) then finish(id,true)
            elseif os.clock()-pending[id]>=20 then finish(id,false,'No confirmation; will retry, up to 3 attempts per pet')
            else A.status.Rename='Waiting for confirmation: '..id; return end
        end
        if not A.settings.rename then return end
        local cfg=A.config('NamedConfig'); local stats=A.util('PetStatsUtil')
        if type(d.Pets)~='table' then A.status.Rename='Pet inventory unavailable'; return end
        if not cfg or not stats or type(stats.GetRarity)~='function' then
            A.status.Rename='Naming configuration unavailable'; return
        end
        if cfg.WorldId and not A.unlocked(cfg.WorldId) then
            A.status.Rename='Unlock naming world '..tostring(cfg.WorldId)..' first'; return
        end
        local name=cfg:Normalize(A.settings.petName)
        local valid,reason=cfg:Validate(name)
        if not valid then A.status.Rename=cfg:GetErrorMessage(reason); return end
        local skipped,total={},0
        -- Removed pets must not leave session state or retry timers behind.
        for petId in pairs(A.sessionNamed) do
            if d.Pets[petId]==nil then A.sessionNamed[petId]=nil; A.cooldowns['rename:'..petId]=nil end
        end
        for petId in pairs(retries) do
            if d.Pets[petId]==nil then retries[petId]=nil; retryAfter[petId]=nil; A.cooldowns['rename:'..petId]=nil end
        end
        for _,petId in ipairs(C.keys(d.Pets)) do
            total=total+1
            -- A partially replicated or malformed entry must not block the rest.
            local checked,canRename,skip=pcall(C.renameEligible,petId,d.Pets[petId],d.NamedPets or {},name,stats)
            if not checked then canRename=false; skip='eligibility unavailable; will recheck' end
            if retryAfter[petId] and os.clock()>=retryAfter[petId] then
                retries[petId]=nil; retryAfter[petId]=nil
            end
            if A.sessionNamed[petId] then canRename=false; skip='renamed this session' end
            if (retries[petId] or 0)>=3 then canRename=false; skip='retry paused for 120s after 3 unconfirmed attempts' end
            if canRename then
                local cost=cfg:GetCost('Pet','Astral'); local balance=A.balance(cfg.ItemId)
                if type(cost)~='number' or cost<0 then A.status.Rename='Naming cost unavailable'; return end
                if balance<cost then
                    A.status.Rename=string.format('Need %s %s per Astral; have %s',tostring(cost),cfg.ItemId,tostring(balance)); return
                end
                -- Live inventory events can wake this job faster than its normal interval.
                -- The server limit is shared across pets, so throttle all naming requests.
                if os.clock()<nextRename then
                    A.tasks.Renaming.next=nextRename
                    A.status.Rename='Waiting between naming requests'; return
                end
                if A.ready('rename:'..petId,25) then
                    nextRename=os.clock()+1
                    -- Set pending before Fire: responses may arrive synchronously.
                    retries[petId]=(retries[petId] or 0)+1
                    pending[petId]=os.clock(); A.renamePending=petId
                    A.status.Rename='Requesting Astral rename: '..petId
                    if not A.fire('NameRenameRequest',{Kind='Pet',UniqueId=petId,Name=name}) then
                        finish(petId,false,'Bridge send failed')
                    end
                    return
                end
                skip='retry cooling down'
            end
            skipped[skip]=(skipped[skip] or 0)+1
        end
        local details={}
        for _,reason in ipairs(C.keys(skipped)) do details[#details+1]=skipped[reason]..' '..reason end
        A.status.Rename='Scanned '..total..' pets. '..table.concat(details,', ')
    end
    function A.retryRenaming()
        if A.renamePending then return end
        retries={}; retryAfter={}
        A.status.Rename='Retry enabled; checking unnamed Astral pets'
    end
    A.job('Renaming',1,function()
        if not A.settings.rename and not A.renamePending then return end
        local ok,err=pcall(renameStep)
        if not ok then A.status.Rename='Rename error: '..tostring(err); A.log('Rename',A.status.Rename) end
        if not A.renamePending and not tostring(A.status.Rename):find('^Named Astral:') then saveDiagnostic() end
    end)
    -- Wake the existing serial worker when live replication adds/updates pets.
    -- Keep polling as a fallback: no per-pet listeners or extra scan loops.
    if A.container and type(A.container.OnChange)=='function' then
        local function wake()
            if not A.alive then return end
            A.renameInventoryEvents=(A.renameInventoryEvents or 0)+1
            A.renameLastInventoryEvent=os.clock()
            A.tasks.Renaming.next=0
        end
        for _,field in ipairs({'Pets','NamedPets'}) do
            local ok,connection=pcall(A.container.OnChange,A.container,{field},wake)
            if ok and connection then A.connections[#A.connections+1]=connection end
        end
    end
end

end)()(A);

-- ===== farming =====
(function()
return function(A)
    local C=A.Core
    local movingHuman
    function A.stopFarmMovement()
        if movingHuman then pcall(function() movingHuman:Move(Vector3.zero) end); movingHuman=nil end
    end
    function A.inMode()
        local ctrl=A.client('TeleportController')
        return (ctrl and ctrl:IsInGamemode()) or false
    end
    function A.travel(world)
        local wanted=tonumber(world)
        if not wanted then A.status.Farm='Choose a valid world'; return false end
        local current=tonumber(A.currentWorld())
        local context=A.player:GetAttribute('VisibilityContext')
        local contextWorld=type(context)=='string' and tonumber(context:match('^World:(%d+)$')) or nil
        local attributeWorld=tonumber(A.player:GetAttribute('CurrentWorldId'))
        local ctrl=A.client('TeleportController')
        local loading=ctrl and ctrl.IsLoading and ctrl:IsLoading()
        -- Never treat a local/controller value alone as proof of server world membership.
        local verified=(contextWorld==wanted or attributeWorld==wanted or A.confirmedWorld==wanted)
            and (current==nil or current==wanted)
            and (contextWorld==nil or contextWorld==wanted)
            and (attributeWorld==nil or attributeWorld==wanted)
        if verified and not loading and not A.inMode() then
            A.worldTransition=nil; return true
        end
        A.worldTransition=wanted; A.watchTarget(nil)
        local character=A.player.Character
        local human=character and character:FindFirstChildOfClass('Humanoid')
        if human then human:Move(Vector3.zero) end
        if A.rangeOwned then A.fire('RangeToggle',false); A.rangeOwned=false end
        if A.inMode() then A.status.Farm='Waiting for the current mode to finish'; return false end
        if not A.unlocked(wanted) then A.status.Farm='World locked: '..wanted; return false end
        A.status.Farm='Waiting for registered World '..wanted..' (current '..tostring(contextWorld or attributeWorld or current or 'unknown')..')'
        if loading then return false end
        if A.ready('travel',5) then
            if not A.fire('RequestChangeWorld',wanted) then A.status.Farm='World teleport request failed' end
        end
        return false
    end
    local function resolveEnemy(name)
        for key,e in pairs(A.catalog.enemies) do
            if key==name or e.Name==name or e.ModelName==name then return key,e end
        end
    end
    local function enemyHealth(enemy)
        if enemy:GetAttribute('EnemyDead')==true then return false end
        local big=A.util('BigNum'); local real=enemy:GetAttribute('HealthReal')
        if real~=nil and big then
            local ok,alive,health=pcall(function()
                local value=big.Decode(real)
                if value==nil then return nil end
                return big.IsPositive(value),big.Log10(value)
            end)
            if ok and alive~=nil then return alive,health end
        end
        local hum=enemy:FindFirstChildOfClass('Humanoid')
        if not hum then return nil end
        return hum.Health>0,math.log10(math.max(hum.Health,1e-300))
    end
    A.enemyHealth=enemyHealth
    function A.findEnemies(world)
        local folders={}
        local root=workspace:FindFirstChild('Worlds')
        local w=root and root:FindFirstChild(tostring(world))
        local f=w and w:FindFirstChild('Enemies'); if f then folders[#folders+1]=f end
        local items={}; local char=A.player.Character; local hrp=char and char:FindFirstChild('HumanoidRootPart')
        if not hrp then return items end
        for _,folder in ipairs(folders) do
            for _,enemy in ipairs(folder:GetChildren()) do
                local part=enemy:FindFirstChild('HumanoidRootPart')
                local id,info=resolveEnemy(enemy.Name)
                local selection=A.settings.mobsByWorld[tostring(world)] or {}
                local allowed=next(selection)==nil or selection[id]==true
                local alive,health=enemyHealth(enemy)
                if allowed and part and alive==true
                    and enemy:GetAttribute('EnemyDead')~=true and enemy:GetAttribute('IsClientVisualClone')~=true
                    and not A.S.Players:GetPlayerFromCharacter(enemy) and id then
                    items[#items+1]={model=enemy,part=part,health=health,distance=(part.Position-hrp.Position).Magnitude,
                        id=enemy:GetFullName(),label=info and info.Name or enemy.Name}
                end
            end
        end
        return items
    end
    A.targetConnections={}
    function A.watchTarget(target)
        if A.currentTarget==target then return end
        for _,c in ipairs(A.targetConnections) do c:Disconnect() end
        A.targetConnections={}; A.currentTarget=target
        A.targetWorld=target and tostring(A.settings.world) or nil
        if not target then return end
        local function died()
            if not A.alive or not A.running or A.currentTarget~=target then return end
            if target.Parent and enemyHealth(target)~=false then return end
            A.watchTarget(nil)
            task.defer(function()
                if A.alive and A.running and A.runJob then
                    A.runJob(A.tasks.Farm)
                end
            end)
        end
        local hum=target:FindFirstChildOfClass('Humanoid')
        if hum then
            A.targetConnections[#A.targetConnections+1]=hum.Died:Connect(died)
            A.targetConnections[#A.targetConnections+1]=hum:GetPropertyChangedSignal('Health'):Connect(died)
        end
        A.targetConnections[#A.targetConnections+1]=target:GetAttributeChangedSignal('HealthReal'):Connect(died)
        A.targetConnections[#A.targetConnections+1]=target:GetAttributeChangedSignal('EnemyDead'):Connect(function()
            if target:GetAttribute('EnemyDead') then died() end
        end)
        A.targetConnections[#A.targetConnections+1]=target.AncestryChanged:Connect(function(_,parent) if not parent then died() end end)
    end
    A.job('Farm',0.2,function()
        if not A.data() then A.status.Farm='Waiting for player data'; return end
        local char=A.player.Character; local hrp=char and char:FindFirstChild('HumanoidRootPart')
        local hum=char and char:FindFirstChildOfClass('Humanoid')
        if not hrp or not hum or hum.Health<=0 then A.status.Farm='Waiting for respawn'; return end
        if not A.settings.farm or (A.activityBlocksFarm and A.activityBlocksFarm()) or A.inMode() or (A.trialContext and A.trialContext()) then
            A.watchTarget(nil)
            A.stopFarmMovement()
            if A.rangeOwned then A.fire('RangeToggle',false); A.rangeOwned=false; hum:Move(Vector3.zero) end
            return
        end
        local targetMode=A.settings.target; local world=A.settings.world
        if not A.travel(world) then return end
        local ctrl=A.client('TeleportController'); if ctrl and ctrl:IsLoading() then return end
        local chosen
        local target=A.currentTarget
        if target and (A.targetWorld~=tostring(world) or not target.Parent or enemyHealth(target)==false) then
            A.watchTarget(nil); target=nil
        end
        if target then
            -- Selection and HP ranking changes only affect the NEXT target.
            local part=target:FindFirstChild('HumanoidRootPart')
            if not part then A.status.Farm='Target locked; waiting for its root part'; return end
            chosen={model=target,part=part,label=target.Name,distance=(part.Position-hrp.Position).Magnitude}
        else
            chosen=C.chooseTarget(A.findEnemies(world),targetMode)
            if not chosen then A.status.Farm='Waiting for a live matching enemy'; return end
            A.watchTarget(chosen.model)
        end
        local destination=chosen.part.Position+Vector3.new(0,0,A.settings.distance)
        if chosen.distance>A.settings.distance+2 then
            if A.settings.moveStyle=='Teleport' then hrp.CFrame=CFrame.new(destination,chosen.part.Position)
            else movingHuman=hum; hum:MoveTo(destination) end
        end
        -- The game's range system owns damage validation; no fabricated damage/hits.
        local d=A.data()
        if d.RangeState~=true and A.ready('rangeOn',4) then
            if A.fire('RangeToggle',true) then A.rangeOwned=true end
        end
        A.status.Farm='Target: '..chosen.label
    end)
end

end)()(A);

-- ===== trial_follow =====
(function()
return function(A)
    local function install(kind,bridge,folder,toggle,label,keyField)
        local activeKey,target,loadingSince,endedKey
        local mapReady,state={},{}
        local streamBusy,nextStream=false,0
        local stalledSince,lastReportAt=nil,0
        local function getContext()
            local context=A.player:GetAttribute('VisibilityContext')
            return type(context)=='string' and context:match('^'..kind..':(.+)$') or nil
        end
        local movingHuman,movementRoot,movementKey,anchor
        local function stopMovement()
            if movingHuman then pcall(function() movingHuman:Move(Vector3.zero,false) end) end
            movingHuman=nil; movementRoot=nil; movementKey=nil; anchor=nil
        end
        local function followMovement()
            if not A.running or not A.settings[toggle] or (A.activityExitPending and A.activityExitPending()) then stopMovement(); return end
            local key=getContext()
            if not key or endedKey==key then stopMovement(); return end
            local character=A.player.Character
            local root=character and character:FindFirstChild('HumanoidRootPart')
            local human=character and character:FindFirstChildOfClass('Humanoid')
            if not root or not human or human.Health<=0 or root.Anchored or human.Sit then
                stopMovement(); return
            end
            if movingHuman~=human or movementRoot~=root or movementKey~=key then
                stopMovement(); movingHuman=human; movementRoot=root; movementKey=key
            end
            -- Recenter after a room teleport; small steps should never pull back to the old room.
            if not anchor or (root.Position-anchor).Magnitude>6 then anchor=root.Position end
            local phase=os.clock()*2
            local dx=anchor.X+math.cos(phase)*0.75-root.Position.X
            local dz=anchor.Z+math.sin(phase)*0.75-root.Position.Z
            local length=math.sqrt(dx*dx+dz*dz)
            if length>0.05 then
                human:Move(Vector3.new(dx/length*0.2,0,dz/length*0.2),false)
            else human:Move(Vector3.zero,false) end
        end
        A[kind=='Trial' and 'trialContext' or 'dungeonContext']=getContext
        A['stop'..kind..'Movement']=stopMovement
        local renderName='JoesAAS'..kind..'Movement'
        local renderBound=false
        if A.S.Run.BindToRenderStep then
            local ok=pcall(function()
                A.S.Run:BindToRenderStep(renderName,Enum.RenderPriority.Input.Value+1,function()
                    if A.alive then followMovement() end
                end)
            end)
            renderBound=ok
        end
        if not renderBound then A.connect(A.S.Run.Heartbeat,followMovement) end
        A['cleanup'..kind..'Movement']=function()
            stopMovement()
            if renderBound then A.S.Run:UnbindFromRenderStep(renderName); renderBound=false end
        end
        A.on(bridge..'MapReady',function(key,room,generation,position,token)
            if type(key)~='string' then return end
            mapReady={key=key,room=tonumber(room) or 1,generation=generation,position=position,token=token,at=os.clock()}
            state={[keyField]=key,Room=tonumber(room) or 1}
            endedKey=nil
        end)
        A.on(bridge..'State',function(packet)
            if type(packet)~='table' or packet.Refused then return end
            if packet.Full or (packet[keyField] and packet[keyField]~=state[keyField]) then state={} end
            for k,v in pairs(packet) do if k~='Full' and k~='Cleared' then state[k]=v end end
            for _,k in ipairs(type(packet.Cleared)=='table' and packet.Cleared or {}) do state[k]=nil end
        end)
        A.on(bridge..'Ended',function() stopMovement(); endedKey=getContext(); target=nil; mapReady={}; state={} end)
        local function roomSpawn(arena,index)
            local rooms=arena and arena:FindFirstChild('Rooms')
            local room=rooms and rooms:FindFirstChild('Room'..tostring(index))
            local spawn=room and room:FindFirstChild('Spawn',true)
            return spawn and spawn:IsA('BasePart') and spawn or nil
        end
        local function recoverLoading(key,arena)
            local room=state[keyField]==key and state.Room or (mapReady.key==key and mapReady.room)
            local spawn=room and roomSpawn(arena,room)
            local position=spawn and spawn.Position or (mapReady.key==key and mapReady.position)
            if position and not streamBusy and os.clock()>=nextStream then
                nextStream=os.clock()+10; streamBusy=true
                task.spawn(function()
                    if A.alive and A.running and A.settings[toggle] and getContext()==key then
                        local ok,err=pcall(function() A.player:RequestStreamAroundAsync(position) end)
                        A.status[label..' streaming']=ok and 'Requested current room streaming' or ('Streaming request failed: '..tostring(err))
                    end
                    streamBusy=false
                end)
            end
            if kind=='Trial' and mapReady.key==key and (mapReady.attempts or 0)<3 and os.clock()-mapReady.at>=3
                and os.clock()>=(mapReady.nextAck or 0)
                and type(mapReady.generation)=='number' and type(mapReady.token)=='string'
                and (not room or room==mapReady.room) and roomSpawn(arena,mapReady.room) then
                -- Bounded retries of the acknowledgement issued for this exact loaded room.
                mapReady.acknowledged=true; mapReady.attempts=(mapReady.attempts or 0)+1
                mapReady.nextAck=os.clock()+10
                A.fire(bridge..'ClientReady',key,mapReady.generation,mapReady.token)
            end
        end
        local function stalled(message,key,root,arena,enemies)
            A.status[label..' follow']=message
            stalledSince=stalledSince or os.clock()
            if os.clock()-stalledSince<5 then return end
            if root and not endedKey then recoverLoading(key,arena) end
            if os.clock()-lastReportAt<60 then return end
            lastReportAt=os.clock()
            pcall(function()
                if type(writefile)~='function' then return end
                local samples={}
                for _,enemy in ipairs(enemies and enemies:GetChildren() or {}) do
                    if #samples>=12 then break end
                    local h=enemy:FindFirstChildOfClass('Humanoid')
                    samples[#samples+1]={name=enemy.Name,health=h and h.Health,real=tostring(enemy:GetAttribute('HealthReal')),
                        dead=enemy:GetAttribute('EnemyDead'),clone=enemy:GetAttribute('IsClientVisualClone'),
                        context=enemy:GetAttribute('VisibilityContext'),hasRoot=enemy:FindFirstChild('HumanoidRootPart')~=nil}
                end
                local ctrl=A.client('TeleportController')
                writefile(A.folder..'/'..kind:lower()..'-diagnostics.json',A.S.HTTP:JSONEncode({version='5.7',reason=message,
                    context=A.player:GetAttribute('VisibilityContext'),room=state[keyField]==key and state.Room,
                    serverEnemies=state[keyField]==key and state.EnemyCount,anchored=root and root.Anchored,
                    loading=ctrl and ctrl:IsLoading(),mapReady=mapReady.key==key,readyRetried=mapReady.acknowledged==true,readyAttempts=mapReady.attempts or 0,
                    movementDriver=renderBound and 'after input' or 'heartbeat',
                    characterPosition=root and {x=root.Position.X,y=root.Position.Y,z=root.Position.Z},
                    hasArena=arena~=nil,hasEnemiesFolder=enemies~=nil,enemies=samples}))
            end)
        end
        A.connect(A.player:GetAttributeChangedSignal('VisibilityContext'),function()
            if getContext()~=movementKey then stopMovement() end
            if getContext()~=activeKey then target=nil; loadingSince=nil; endedKey=nil end
        end)
        A.job(label..' follow',0.2,function()
            if not A.settings[toggle] then target=nil; loadingSince=nil; stalledSince=nil; return end
            if A.activityExitPending and A.activityExitPending() then target=nil; stopMovement(); return end
            local key=getContext()
            if key~=activeKey then activeKey=key; target=nil; loadingSince=nil; stalledSince=nil end
            if not key then A.status[label..' follow']='Waiting to enter a '..label; return end
            if endedKey==key then A.status[label..' follow']=label..' ended; waiting for return teleport'; return end
            local character=A.player.Character
            local root=character and character:FindFirstChild('HumanoidRootPart')
            local human=character and character:FindFirstChildOfClass('Humanoid')
            if not root or not human or human.Health<=0 then
                target=nil; loadingSince=nil; A.status[label..' follow']='Waiting for your character to respawn'; return
            end
            local arenas=workspace:FindFirstChild(folder)
            local arena=arenas and arenas:FindFirstChild(key)
            local enemies=arena and arena:FindFirstChild('Enemies')
            if not enemies then target=nil; loadingSince=nil; stalled('Waiting for your '..label..' arena to load',key,root,arena,enemies); return end
            local function eligible(enemy)
                if enemy.Parent~=enemies or enemy:GetAttribute('IsClientVisualClone')==true then return end
                local context=enemy:GetAttribute('VisibilityContext')
                if context~=nil and context~='' and context~=kind..':'..key then return end
                if A.enemyHealth(enemy)~=true then return end
                return enemy:FindFirstChild('HumanoidRootPart')
            end
            local part=target and eligible(target)
            if not part then
                target=nil; local closest
                for _,enemy in ipairs(enemies:GetChildren()) do
                    local candidate=eligible(enemy)
                    if candidate then
                        local distance=(candidate.Position-root.Position).Magnitude
                        if not closest or distance<closest then target=enemy; part=candidate; closest=distance end
                    end
                end
            end
            if not part then loadingSince=nil; stalled('Waiting for living enemies in your '..label,key,root,arena,enemies); return end
            if root.Anchored then loadingSince=nil; stalled('Character anchored by game; waiting for release',key,root,arena,enemies); return end
            local ctrl=A.client('TeleportController')
            local loading=ctrl and ctrl:IsLoading()
            if loading then
                loadingSince=loadingSince or os.clock()
                if os.clock()-loadingSince<3 then A.status[label..' follow']='Waiting for '..label..' loading'; return end
                -- Recover only with a living target in our exact arena and a usable character.
                -- Do not modify the game's loading flag or join/room-ready handshake.
            else loadingSince=nil end
            stalledSince=nil
            local offset=math.min(A.settings.distance,3)
            if (part.Position-root.Position).Magnitude>offset+0.5 then
                root.CFrame=CFrame.new(part.Position+Vector3.new(0,0,offset),part.Position)
                anchor=nil
            end
            A.status[label..' follow']=(loading and 'Following own '..label..' despite stale loading flag: ' or 'Following '..label..' mob: ')..target.Name
        end)
    end
    install('Trial','TimeTrial','TimeTrialArenas','trialFollow','Trial','TrialKey')
    install('Dungeon','Dungeon','DungeonArenas','trialFollow','Dungeon','DungeonKey')
end

end)()(A);

-- ===== join_diagnostics =====
(function()
return function(A)
    local path=A.folder..'/join-diagnostics.json'
    local saved=A.safeLoad(path)
    local events,openings={},{}
    local dirty=true
    local fields={mode=true,key=true,reason=true,accepted=true,selected=true,duration=true,rank=true,
        source=true,action=true,sent=true,retry=true,autoRetry=true,timeTrialTransfer=true}
    local function clean(input)
        local result={}
        for key,value in pairs(type(input)=='table' and input or {}) do
            if fields[key] then
                if type(value)=='string' then result[key]=value:sub(1,240)
                elseif type(value)=='boolean' then result[key]=value
                elseif type(value)=='number' and value==value and math.abs(value)<1e12 then result[key]=value end
            end
        end
        return result
    end
    if type(saved)=='table' and saved.schema==1 and saved.userId==A.player.UserId and saved.gameId==game.GameId then
        for _,event in ipairs(type(saved.events)=='table' and saved.events or {}) do
            if #events>=400 then break end
            if type(event)=='table' and type(event.kind)=='string' then
                events[#events+1]={time=tonumber(event.time),kind=event.kind:sub(1,60),details=clean(event.details),
                    context=type(event.context)=='string' and event.context:sub(1,120) or nil,loading=event.loading==true}
            end
        end
    end
    local lastStatus
    function A.joinTrace(kind,details)
        if kind=='status' then
            local reason=details and details.reason
            if reason==lastStatus then return end
            lastStatus=reason
        end
        local ctrl=A.client('TeleportController')
        local ok,loading=pcall(function() return ctrl and ctrl:IsLoading() end)
        local event={time=os.time(),kind=kind,details=clean(details),
            context=A.player:GetAttribute('VisibilityContext'),loading=ok and loading==true,running=A.running}
        events[#events+1]=event; if #events>400 then table.remove(events,1) end
        if kind=='opening' then
            openings[#openings+1]={time=event.time,mode=event.details.mode,key=event.details.key,
                selected=event.details.selected,rank=event.details.rank,duration=event.details.duration}
            if #openings>40 then table.remove(openings,1) end
        end
        dirty=true
    end
    function A.flushJoinDiagnostics(force)
        if not dirty and not force then return true end
        if type(writefile)~='function' then A.status['Join diagnostics']='File writing unavailable: '..path; return false end
        local ctrl=A.client('TeleportController')
        local stateOK,gameState=pcall(function() return {loading=ctrl and ctrl:IsLoading()==true,inMode=A.inMode()} end)
        local coordinatorOK,coordinator=pcall(function() return A.joinSnapshot and A.joinSnapshot() or {} end)
        local activityJob=A.tasks.Activities
        local snapshot={schema=1,version='5.7',userId=A.player.UserId,gameId=game.GameId,
            savedAt=os.time(),context=A.player:GetAttribute('VisibilityContext'),running=A.running,
            activities=A.status.Activities,error=A.status['Activity error'],events=events,openings=openings,
            coordinator=coordinatorOK and coordinator or {error=tostring(coordinator):sub(1,240)},
            gameState=stateOK and gameState or {error=tostring(gameState):sub(1,240)},
            eventError=A.status.Event,activityJobFailures=activityJob and activityJob.failures,settings={}}
        for _,key in ipairs({'towerAutoJoin','towerSelection','trialAutoJoin','trialJoinSelection','dungeonAutoJoin',
            'dungeonSelection','gateAutoJoin','gateSelection','gateRanks','maxTacAutoJoin','maxTacSelection','maxTacRanks','priority','raidAutoJoin','raidSelection',
            'defenseAutoJoin','defenseSelection','bossRushAutoJoin','bossRushSelection',
            'autoLeaveStuck','stuckSeconds','trialDungeonStuckSeconds'}) do snapshot.settings[key]=A.settings[key] end
        local ok,err=pcall(function()
            if type(makefolder)=='function' then pcall(makefolder,'JoesAAS'); pcall(makefolder,A.folder) end
            local encoded=A.S.HTTP:JSONEncode(snapshot)
            writefile(path,encoded)
            if type(readfile)=='function' then assert(readfile(path)==encoded,'Diagnostic read-back failed') end
        end)
        A.status['Join diagnostics']=ok and ('Saved: '..path) or ('Save failed: '..path..' - '..tostring(err))
        if ok then dirty=false end
        return ok
    end
    A.connect(A.player:GetAttributeChangedSignal('VisibilityContext'),function() A.joinTrace('context',{}) end)
    A.job('Join diagnostics',5,A.flushJoinDiagnostics,true)
    A.joinTrace('script started',{})
    A.flushJoinDiagnostics(true)
end

end)()(A);

-- ===== activities =====
(function()
return function(A)
    local definitions={
        MaxTac={config='RaidConfig',method='GetAllRaids',toggle='maxTacAutoJoin',selection='maxTacSelection',ranks='maxTacRanks'},
        Tower={config='TowerConfig',method='GetAllTowers',toggle='towerAutoJoin',selection='towerSelection'},
        TimeTrial={config='TimeTrialConfig',method='GetAllTrials',toggle='trialAutoJoin',selection='trialJoinSelection'},
        Gate={config='RaidConfig',method='GetAllRaids',toggle='gateAutoJoin',selection='gateSelection',ranks='gateRanks'},
        Raid={config='RaidConfig',method='GetAllRaids',toggle='raidAutoJoin',selection='raidSelection'},
        Defense={config='DefenseConfig',method='GetAllDefenses',toggle='defenseAutoJoin',selection='defenseSelection'},
        Dungeon={config='DungeonConfig',method='GetAllDungeons',toggle='dungeonAutoJoin',selection='dungeonSelection'},
        BossRush={config='BossRushConfig',method='GetAllRushes',toggle='bossRushAutoJoin',selection='bossRushSelection'}
    }
    local order={'MaxTac','Tower','TimeTrial','Dungeon','Gate','Raid','Defense','BossRush'}
    local protected={MaxTac=true,Tower=true,TimeTrial=true,Dungeon=true}
    local available,backoff={},{}
    local pending,leaving,locked,returning,returningContext,waitingReason,stuckExit
    local stuckBackoff={}
    local stuckRetry
    local leaveAt,leaveAttempts=0,0
    local raidInstance,raidKey
    for _,mode in ipairs(order) do available[mode]={} end
    function A.activityOrder()
        local result={}
        for _,mode in ipairs(A.Core.priorityOrder(A.settings.priority)) do
            if mode=='Combat' then result[#result+1]='Raid'; result[#result+1]='Defense'
            else result[#result+1]=mode end
        end
        return result
    end
    local function priority(mode)
        mode=(mode=='Raid' or mode=='Defense') and 'Combat' or mode
        for i,key in ipairs(A.Core.priorityOrder(A.settings.priority)) do if key==mode then return 8-i end end
        return 0
    end
    function A.priorityText()
        local labels={}
        for _,key in ipairs(A.Core.priorityOrder(A.settings.priority)) do labels[#labels+1]=A.Core.priorityLabels[key] end
        return table.concat(labels,' > ')..' > Mob Autofarm'
    end
    function A.moveActivityPriority(mode,delta)
        local list=A.Core.priorityOrder(A.settings.priority)
        for i,key in ipairs(list) do
            if key==mode then
                local destination=math.clamp(i+delta,1,#list)
                list[i],list[destination]=list[destination],list[i]; break
            end
        end
        A.settings.priority=list; A.settingsChanged()
        if A.refreshUI then A.refreshUI() end
        A.coordinateActivities()
    end
    function A.resetActivityPriority()
        A.settings.priority=A.Core.copy(A.Core.defaultPriority); A.settingsChanged()
        if A.refreshUI then A.refreshUI() end
        A.coordinateActivities()
    end
    function A.activityChoices(mode)
        local def=definitions[mode]; if not def then return {} end
        local cfg=A.config(def.config)
        local choices=cfg and type(cfg[def.method])=='function' and cfg[def.method](cfg) or {}
        if mode=='BossRush' then
            local rows={}
            for key,rush in pairs(choices) do
                if type(rush.Modes)=='table' then
                    for variant,entry in pairs(rush.Modes) do
                        if (variant=='V1' or variant=='V2') and type(entry)=='table' then
                            rows[key..':'..variant]={Name=entry.Name or rush.Name or key,WorldId=rush.WorldId,
                                Cost=entry.Cost,RushKey=key,ModeId=variant,RequiresChallenge=entry.RequiresChallenge}
                        end
                    end
                end
            end
            return rows
        end
        if mode=='Gate' or mode=='MaxTac' or mode=='Raid' then
            local filtered={}
            for key,value in pairs(choices) do
                if (mode=='Raid' and value.GateOnly~=true) or A.Core.portalMode(key,value)==mode then filtered[key]=value end
            end
            return filtered
        end
        return choices
    end
    -- Older profiles stored only the rush key. Keep the same V1 choice when declared.
    local rushChoices=A.activityChoices('BossRush')
    for key,selected in pairs(A.Core.copy(A.settings.bossRushSelection)) do
        if selected and not rushChoices[key] then
            local migrated=key..':V1'
            if rushChoices[migrated] then
                A.settings.bossRushSelection[key]=nil; A.settings.bossRushSelection[migrated]=true
                A.settingsChanged()
            end
        end
    end
    local rankOrders={Gate={'S','A','B','C','D','E'},MaxTac={'Low','Medium','High','Extreme','Psycho'}}
    local rankWeight={S=6,A=5,B=4,C=3,D=2,E=1,Low=5,Medium=4,High=3,Extreme=2,Psycho=1}
    local function rankRows(mode)
        local present={}; local rows={}
        for _,cfg in pairs(A.activityChoices(mode)) do
            for _,rank in ipairs(type(cfg.GateRanks)=='table' and cfg.GateRanks or {}) do
                if type(rank)=='table' and type(rank.Rank)=='string' then present[rank.Rank]=true end
            end
        end
        for _,rank in ipairs(rankOrders[mode]) do if present[rank] then rows[#rows+1]={key=rank,label=rank} end end
        return rows
    end
    function A.gateRankRows() return rankRows('Gate') end
    function A.maxTacRankRows() return rankRows('MaxTac') end
    local function portalRank(mode,key,p)
        local cfg=A.activityChoices(mode)[key]
        if not cfg then return nil end
        for _,entry in ipairs(type(cfg.GateRanks)=='table' and cfg.GateRanks or {}) do
            local rank=type(entry)=='table' and entry.Rank
            if type(rank)=='string' and rankWeight[rank] and (p.GateRank==rank
                or (type(p.Name)=='string' and p.Name:match('Rank%s+([%a]+)')==rank)
                or (type(p.Title)=='string' and p.Title:match('Rank%s+([%a]+)')==rank)) then return rank end
        end
    end
    local function candidateKeys(mode,choices)
        if mode=='TimeTrial' then return A.Core.activityKeys(choices,mode) end
        local keys=A.Core.keys(choices)
        if mode=='Gate' or mode=='MaxTac' then
            table.sort(keys,function(a,b)
                local left=available[mode][a]; local right=available[mode][b]
                local x=left and rankWeight[left.rank] or 0; local y=right and rankWeight[right.rank] or 0
                if x~=y then return x>y end
                return a<b
            end)
        end
        return keys
    end
    function A.trialChoices() return A.activityChoices('TimeTrial') end
    function A.activityRows(mode)
        local choices=A.activityChoices(mode); local rows={}
        for _,key in ipairs(A.Core.activityKeys(choices,mode)) do
            local cfg=choices[key]; local label=cfg.Name or key
            if mode~='TimeTrial' then
                local id=tonumber(cfg.WorldId)
                label=(id and ('World '..id..' | ') or 'Other | ')..label
            end
            rows[#rows+1]={key=key,label=label}
        end
        return rows
    end
    local function context()
        local raw=A.player:GetAttribute('VisibilityContext')
        local mode=type(raw)=='string' and raw:match('^([^:]+):') or nil
        if mode=='Trial' then mode='TimeTrial' end
        if mode=='Raid' then
            local instance=raw:match('^Raid:(.+)$')
            local key=instance==raidInstance and raidKey or instance
            local cfg=A.config('RaidConfig'); local entries=cfg and cfg:GetAllRaids() or {}
            if instance and not entries[key] then
                local arenas=workspace:FindFirstChild('RaidArenas')
                local arena=arenas and arenas:FindFirstChild(instance)
                local observed=arena and arena:GetAttribute('RaidKey')
                local base=instance:match('^([^_]+)_')
                if type(observed)=='string' and entries[observed] then key=observed
                elseif base and entries[base] then key=base end
                if entries[key] then raidInstance=instance; raidKey=key end
            end
            if entries[key] and entries[key].GateOnly==true then mode=A.Core.portalMode(key,entries[key])
            elseif pending and (pending.mode=='Gate' or pending.mode=='MaxTac') and raw~=pending.fromContext then mode=pending.mode end
        end
        return mode~='World' and mode or nil,raw
    end
    A.activityContext=context
    function A.activityExitPending() return stuckExit~=nil end
    local function enabled(mode,key)
        local def=definitions[mode]
        return A.settings[def.toggle] and A.settings[def.selection][key]==true
    end
    local function selectCandidate()
        waitingReason=nil
        for _,mode in ipairs(A.activityOrder()) do
            local choices=A.settings[definitions[mode].toggle] and (stuckBackoff[mode] or 0)<=os.clock() and A.activityChoices(mode) or {}
            for _,key in ipairs(candidateKeys(mode,choices)) do
                if enabled(mode,key) and (backoff[mode..':'..key] or 0)<=os.clock() then
                    local entry=available[mode][key]
                    if mode=='Tower' then
                        local cfg=A.config('TowerConfig'); local util=A.util('TowerStateUtil'); local d=A.data()
                        local tower=choices[key]
                        if cfg and cfg.Enabled~=false and util and d and A.unlocked(tower.WorldId)
                            and util.GetCooldownRemaining(d,tower)<=0 then return mode,key,{} end
                    elseif mode=='Gate' or mode=='MaxTac' then
                        if entry and entry.deadline>os.clock() then
                            if not entry.rank then waitingReason=mode..' rank not provided; waiting for a ranked announcement'
                            elseif A.settings[definitions[mode].ranks][entry.rank] then return mode,key,entry end
                        end
                    elseif mode~='Raid' and mode~='Defense' and mode~='BossRush' and entry and entry.deadline>os.clock() then return mode,key,entry
                    elseif mode=='Raid' or mode=='Defense' or mode=='BossRush' then
                        local cfg=choices[key]
                        local data=A.data()
                        local progress=data and type(data.BossRushProgress)=='table' and data.BossRushProgress[cfg.RushKey]
                        if cfg.GateOnly then waitingReason=mode..': portal-only entry; own-run creation unavailable'
                        elseif cfg.WorldId and not A.unlocked(cfg.WorldId) then
                            waitingReason=mode..': unlock World '..tostring(cfg.WorldId)
                        elseif not data then waitingReason='Waiting for player data'
                        elseif cfg.RequiresChallenge and (type(progress)~='table' or progress.ChallengeCompleted~=true) then
                            waitingReason=mode..': complete the native Challenge first'
                        else
                            local cost=cfg.Cost
                            if type(cost)=='table' and A.balance(cost.ItemId)<(tonumber(cost.Amount) or 1) then
                                waitingReason=mode..': need '..tostring(cost.Amount or 1)..' '..tostring(cost.ItemId)
                            else return mode,key,{action='Create',rushKey=cfg.RushKey or key,modeId=cfg.ModeId or 'V1'} end
                        end
                    end
                end
            end
        end
    end
    local function status(text) A.status.Activities=text; A.status['Trial join']=text; A.joinTrace('status',{reason=text}) end
    local function suspendFarm()
        A.watchTarget(nil)
        A.stopFarmMovement()
        if A.rangeOwned then A.fire('RangeToggle',false); A.rangeOwned=false end
        local c=A.player.Character; local h=c and c:FindFirstChildOfClass('Humanoid')
        if h then h:Move(Vector3.zero) end
    end
    function A.activityBlocksFarm()
        local mode=context()
        return mode~=nil or pending~=nil or leaving~=nil or locked~=nil or returning~=nil or stuckExit~=nil
    end
    function A.requestStuckExit(mode,raw)
        local current,contextRaw=context()
        if not A.alive or not A.running or not A.settings.autoLeaveStuck or not definitions[mode]
            or current~=mode or raw~=contextRaw or pending or leaving or returning or stuckExit
            or (stuckRetry and stuckRetry.mode==mode and stuckRetry.context==raw and stuckRetry.untilTime>os.clock()) then return false end
        stuckExit={mode=mode,context=raw,attempts=0,lastSent=-math.huge}
        pending=nil; locked=nil
        suspendFarm()
        if A.stopTrialMovement then A.stopTrialMovement() end
        if A.stopDungeonMovement then A.stopDungeonMovement() end
        A.joinTrace('stuck timeout',{mode=mode,reason='No run or combat progress within configured timeout'})
        A.coordinateActivities()
        return true
    end
    local function sendRequest(mode,key,entry)
        if mode=='Gate' or mode=='MaxTac' then return A.fire('RaidGateTeleport',key) end
        if mode=='Tower' then return A.fire('TowerJoin',{TowerKey=key}) end
        if mode=='Raid' or (mode=='Defense' and entry.action=='Create') then return A.fire(mode..'Join','Create',key,true) end
        if mode=='BossRush' then return A.fire('BossRushJoin','Create',entry.rushKey or key,entry.modeId or 'V1') end
        return A.fire(mode..'Join',entry.action or 'Join',key)
    end
    local function sendJoin(mode,key,entry)
        A.joinTrace('join request',{mode=mode,key=key,action=entry.action or 'Join',rank=entry.rank})
        local sent=sendRequest(mode,key,entry)
        A.joinTrace('join sent',{mode=mode,key=key,sent=sent==true})
        return sent
    end
    function A.coordinateActivities()
        if not A.alive or not A.running then return end
        if A.settings.raidAutoJoin and A.settings.defenseAutoJoin then A.settings.defenseAutoJoin=false end
        local current,raw=context()
        local ctrl=A.client('TeleportController')
        local loading=ctrl and ctrl:IsLoading()
        if stuckRetry and raw~=stuckRetry.context then stuckRetry=nil end
        if returning and current and returningContext and raw~=returningContext then returning=nil; returningContext=nil end
        if stuckExit and not A.settings.autoLeaveStuck then stuckExit=nil end
        if stuckExit then
            local exit=stuckExit
            if current and raw~=exit.context then
                -- A new instance or direct native transfer is already confirmed.
                stuckBackoff[exit.mode]=os.clock()+30; stuckExit=nil
            elseif not current and not A.inMode() and not loading then
                stuckBackoff[exit.mode]=os.clock()+30; stuckExit=nil
                locked=nil; returning=nil; leaving=nil
            else
                if raw==exit.context and os.clock()-exit.lastSent>=5 then
                    if exit.attempts>=3 then
                        stuckBackoff[exit.mode]=os.clock()+30; stuckExit=nil
                        stuckRetry={mode=exit.mode,context=exit.context,untilTime=os.clock()+30}
                        if protected[current] and returning~=current then locked=current end
                        A.status['Activity error']='Stuck '..exit.mode..' exit not confirmed; retry in 30s'
                        A.status['Stuck recovery']=A.status['Activity error']
                        status(A.status['Activity error']); return
                    end
                    exit.attempts=exit.attempts+1; exit.lastSent=os.clock()
                    local bridge=(exit.mode=='Gate' or exit.mode=='MaxTac') and 'RaidLeave' or exit.mode..'Leave'
                    local sent=A.fire(bridge)
                    A.joinTrace('stuck leave request',{mode=exit.mode,sent=sent,retry=exit.attempts>1})
                    A.status['Stuck recovery']='Leaving stuck '..exit.mode..' · attempt '..exit.attempts..'/3'
                end
                status('Waiting for stuck '..exit.mode..' exit confirmation'); return
            end
        end
        if protected[current] and returning~=current then locked=current end
        if type(raw)=='string' and raw:match('^World:') and not A.inMode() and not loading then
            locked=nil; returning=nil; leaving=nil
        end
        if pending and not pending.accepted and not loading and not protected[current] then
            local nextMode=selectCandidate()
            if nextMode and priority(nextMode)>priority(pending.mode) then pending=nil end
        end
        if pending then
            if current==pending.mode then
                pending=nil; returning=nil
            elseif protected[current] and returning~=current then pending=nil
            elseif not loading and (not current or definitions[current]) then
                local entry=available[pending.mode][pending.key]
                local scheduled=pending.mode~='Tower' and pending.entry.action~='Create'
                if not enabled(pending.mode,pending.key) or (scheduled and (not entry or entry.deadline<=os.clock()))
                    or (definitions[pending.mode].ranks and (not entry or not entry.rank or not A.settings[definitions[pending.mode].ranks][entry.rank] or entry.rank~=pending.entry.rank)) then
                    pending=nil
                elseif not pending.accepted and os.clock()-pending.lastSent>=8 then
                    if pending.attempts<3 then
                        pending.attempts=pending.attempts+1; pending.lastSent=os.clock()
                        sendJoin(pending.mode,pending.key,pending.entry)
                        status('Retrying '..pending.mode..' entry: '..pending.key); return
                    else
                        backoff[pending.mode..':'..pending.key]=os.clock()+5; pending=nil
                    end
                elseif pending.accepted and os.clock()-pending.at>=60 then
                    backoff[pending.mode..':'..pending.key]=os.clock()+5; pending=nil
                else status('Waiting for '..pending.mode..' entry confirmation'); return end
            else status('Waiting for '..pending.mode..' entry confirmation'); return end
        end
        if locked then status(locked..' locked until the run ends'); return end
        if loading then status('Blocked by game loading'); return end
        local mode,key,entry=selectCandidate()
        if not mode then status(current and ('In '..current) or (waitingReason or 'Waiting for a selected activity')); return end
        local direct=mode=='MaxTac' or mode=='Tower' or mode=='TimeTrial' or mode=='Dungeon'
        if leaving and not direct then
            if os.clock()-leaveAt>=5 then
                if leaveAttempts<3 then
                    leaveAttempts=leaveAttempts+1; leaveAt=os.clock()
                    A.fire((leaving=='Gate' or leaving=='MaxTac') and 'RaidLeave' or leaving..'Leave')
                else
                    A.status['Activity error']='No '..leaving..' exit confirmation; retrying later'
                    backoff[mode..':'..key]=os.clock()+30; leaving=nil; status(A.status['Activity error']); return
                end
            end
            status('Waiting for '..leaving..' exit confirmation'); return
        end
        if current then
            local def=definitions[current]
            if not def then status('Waiting for current mode to finish'); return end
            -- Finished protected runs may transfer next; unfinished ones stay locked above.
            if returning~=current and priority(mode)<=priority(current) then status('Current '..current..' has equal/higher priority than '..mode); return end
            if not direct then
                if returning==current then status('Waiting for '..current..' return teleport'); return end
                leaving=current; leaveAt=os.clock(); leaveAttempts=1; suspendFarm(); status('Leaving '..current..' for '..mode)
                if not A.fire((current=='Gate' or current=='MaxTac') and 'RaidLeave' or current..'Leave') then leaving=nil; status('Leave bridge unavailable: '..current) end
                return
            end
        elseif returning then status('Waiting for '..returning..' return teleport'); return
        elseif A.inMode() then status('Waiting for current mode to finish'); return end
        if direct then leaving=nil end
        pending={mode=mode,key=key,entry=entry,at=os.clock(),lastSent=os.clock(),attempts=1,fromContext=raw}
        suspendFarm()
        status(current and ('Transferring '..current..' to '..mode..': '..key)
            or ((mode=='Raid' and 'Starting your own Raid: ' or ('Joining '..mode..': '))..key))
        if not sendJoin(mode,key,entry) then
            backoff[mode..':'..key]=os.clock()+5; pending=nil; status('Join bridge unavailable: '..mode)
        end
    end
    A.tryTrialJoin=A.coordinateActivities
    for _,name in ipairs(order) do
        local mode=name
        if mode~='Gate' and mode~='MaxTac' then
        if mode~='Raid' then A.on(mode..'Announcement',function(p)
            if type(p)~='table' or p.NotifyKind~='GamemodeOpen' or p.GamemodeType~=mode or type(p.Key)~='string' then return end
            -- A raid gate announcement is a world gate teleport, not a joinable raid.
            if p.GateTeleport then return end
            A.joinTrace('opening',{mode=mode,key=p.Key,selected=enabled(mode,p.Key),duration=tonumber(p.ExpiresIn),source='bridge'})
            local duration=tonumber(p.ExpiresIn) or 10
            if duration<=0 or duration~=duration then return end
            available[mode][p.Key]={deadline=os.clock()+math.min(duration,600),modeId=p.ModeId}
            A.coordinateActivities()
        end) end
        A.on(mode..'Ended',function(_,packet)
            A.joinTrace('run ended',{mode=mode,autoRetry=type(packet)=='table' and packet.AutoRetry==true,timeTrialTransfer=type(packet)=='table' and packet.TimeTrialTransfer==true})
            local current=context()
            -- The native portal transfer can deliver the previous Raid's end
            -- after MaxTac entry; that packet must not end the new locked run.
            if mode=='Raid' and type(packet)=='table' and packet.AutoGateTransfer==true
                and (current=='MaxTac' or locked=='MaxTac') then A.coordinateActivities(); return end
            local ended=mode=='Raid' and ((current=='MaxTac' or locked=='MaxTac') and 'MaxTac'
                or ((current=='Gate' or locked=='Gate') and 'Gate')) or mode
            if (current==ended or locked==ended) and A.settings.webhook then
                A.notify('Mode',ended..' run ended'..(type(packet)=='table' and packet.AutoRetry==true and ' (native auto retry)' or ''))
            end
            if current==ended or locked==ended then locked=nil; returning=ended; returningContext=select(2,context()) end
            if pending and (pending.mode==mode or pending.mode==ended) then pending=nil end
            A.coordinateActivities()
        end)
        if mode=='TimeTrial' or mode=='Dungeon' then
            A.on(mode..'MapReady',function(instance)
                local current,raw=context()
                -- These modes reuse their arena key across runs. A fresh map
                -- after Ended confirms a new run even without a World context.
                if current~=mode or returning~=mode or raw~=returningContext
                    or instance~=raw:match('^[^:]+:(.+)$') then return end
                if stuckExit then stuckBackoff[stuckExit.mode]=os.clock()+30; stuckExit=nil end
                stuckRetry=nil; returning=nil; returningContext=nil; locked=mode
                A.joinTrace('run restarted',{mode=mode,reason='Own map ready after run ended'})
                A.coordinateActivities()
            end)
        end
        if mode~='Tower' then
            A.on(mode..'Join',function(accepted,reason)
                A.joinTrace('server reply',{mode=mode,accepted=accepted==true,reason=tostring(reason)})
                if not pending or pending.mode~=mode then return end
                if accepted==true then pending.accepted=true end
                if accepted==false then
                    local key=pending.key
                    if mode=='Defense' and reason=='defense_already_active' then
                        available[mode][key]={deadline=os.clock()+15}
                        backoff[mode..':'..key]=0
                    else
                        if reason=='no_active_raid' or reason=='no_active_defense' or reason=='join_closed' or reason=='trial_closed' or reason=='dungeon_closed' then available[mode][key]=nil end
                        backoff[mode..':'..key]=os.clock()+(mode=='Raid' and 30 or 5)
                    end
                    pending=nil
                    A.status['Activity error']=mode..' refused: '..tostring(reason)
                    status(A.status['Activity error'])
                end
            end)
        end
    end
    end
    A.on('RaidAnnouncement',function(p)
        if type(p)~='table' or p.NotifyKind~='GamemodeOpen' or p.GateTeleport~=true or type(p.Key)~='string' then return end
        local duration=tonumber(p.ExpiresIn) or 60
        if duration<=0 or duration~=duration then return end
        local cfg=A.config('RaidConfig'); local entries=cfg and cfg:GetAllRaids() or {}
        local mode=A.Core.portalMode(p.Key,entries[p.Key])
        if mode~='Gate' and mode~='MaxTac' then return end
        local rank=portalRank(mode,p.Key,p)
        A.joinTrace('opening',{mode=mode,key=p.Key,rank=rank,selected=enabled(mode,p.Key) and rank~=nil and A.settings[definitions[mode].ranks][rank]==true,duration=duration,source='bridge'})
        available[mode][p.Key]={deadline=os.clock()+math.min(duration,600),rank=rank}
        A.coordinateActivities()
    end)
    A.on('RaidMapReady',function(instance,key)
        if type(instance)=='string' and type(key)=='string' then raidInstance=instance; raidKey=key end
        A.coordinateActivities()
    end)
    A.on('RaidState',function(packet)
        if type(packet)=='table' and type(packet.RaidKey)=='string' and type(packet.InstanceKey)=='string' then
            raidInstance=packet.InstanceKey; raidKey=packet.RaidKey
        end
        A.coordinateActivities()
    end)
    for _,name in ipairs({'Defense'}) do
        local mode=name
        A.on(mode..'ActiveStatus',function(states)
            if type(states)~='table' then return end
            local replacement={}
            for key,value in pairs(states) do
                if type(key)=='string' and (value==true or (type(value)=='table' and value.Active~=false)) then
                    replacement[key]={deadline=os.clock()+30}
                end
            end
            available[mode]=replacement
            A.coordinateActivities()
        end)
    end
    A.on('TowerState',function(p)
        if type(p)=='table' and p.Refused then A.joinTrace('server reply',{mode='Tower',accepted=false,reason=tostring(p.Refused)}) end
        if type(p)=='table' and p.Refused and pending and pending.mode=='Tower' then
            backoff['Tower:'..pending.key]=os.clock()+10; pending=nil
            A.status['Activity error']='Tower refused: '..tostring(p.Refused)
            status(A.status['Activity error'])
        end
    end)
    local lastTrialSchedule,hasTrialSchedule,trialScheduleOpen
    A.on('TimeTrialActiveStatus',function(_,p)
        if type(p)~='table' then return end
        hasTrialSchedule=true; trialScheduleOpen=p.IsOpen==true
        local signature=tostring(p.IsOpen)..':'..table.concat(A.Core.keys(type(p.OpenTrialKeys)=='table' and p.OpenTrialKeys or {[p.OpenTrialKey or '']=true}),',')
        if signature~=lastTrialSchedule then A.joinTrace('Trial schedule',{mode='TimeTrial',key=p.OpenTrialKey,reason=signature}); lastTrialSchedule=signature end
        available.TimeTrial={}
        if p.IsOpen==true then
            local keys=p.OpenTrialKeys or {[p.OpenTrialKey or '']=true}
            for key,value in pairs(keys) do
                if type(key)=='string' and value==true then available.TimeTrial[key]={deadline=math.huge} end
            end
        end
        A.coordinateActivities()
    end)
    -- Native popup attributes provide recovery when injection happens after the
    -- announcement. Read only the small notification containers, never the scene.
    local observedRoots={}
    local function readCard(card)
        if not card:IsA('GuiObject') or card.Visible~=true or not card.Parent then return end
        local setting=card:GetAttribute('GamemodePopupSettingKey')
        if type(setting)~='string' then return end
        local mode,key=setting:match('^([^:]+):(.+)$')
        if mode=='Portal' or card:GetAttribute('GamemodePopupIsPortal')==true then
            local cfg=A.config('RaidConfig'); local entries=cfg and cfg:GetAllRaids() or {}
            mode=A.Core.portalMode(key,entries[key])
        end
        local modeId=mode=='BossRush' and key:match('^[^:]+:(.+)$') or nil
        if mode=='BossRush' and not modeId then
            local base,variant=key:match('^(.*)_(%w+)$') -- Native Boss Rush setting-key format.
            if base then key=base..':'..variant; modeId=variant end
        end
        if not definitions[mode] or mode=='Raid' or not key or not enabled(mode,key) then return end
        if mode=='TimeTrial' and hasTrialSchedule and not trialScheduleOpen then return end
        local cfg=A.activityChoices(mode)[key]; if not cfg then return end
        local ranked=definitions[mode].ranks~=nil
        local rank=ranked and portalRank(mode,key,{GateRank=card:GetAttribute('GamemodePopupGateRank')}) or nil
        if ranked and not rank then return end
        local entry=available[mode][key]
        if not entry or entry.deadline<=os.clock() or (ranked and not entry.rank) then
            available[mode][key]={deadline=os.clock()+1,rank=rank,modeId=modeId,source='popup'}
            A.joinTrace('opening',{mode=mode,key=key,rank=rank,selected=true,source='native popup'})
        elseif entry.source=='popup' then entry.deadline=os.clock()+1; entry.rank=rank end
    end
    function A.refreshOpenCards()
        local pg=A.player:FindFirstChildOfClass('PlayerGui'); if not pg then return end
        local hud=pg:FindFirstChild('HUD'); local main=hud and hud:FindFirstChild('Main')
        local overlay=pg:FindFirstChild('GamemodeNotifyOverlay')
        local roots={}
        for _,parent in ipairs({main or false,overlay or false}) do
            local root=parent and parent:FindFirstChild('GamemodeNotify')
            if root then roots[#roots+1]=root end
        end
        for _,root in ipairs(roots) do
            if not observedRoots[root] and root.ChildAdded then
                observedRoots[root]=true
                A.connect(root.ChildAdded,function(card)
                    readCard(card); A.coordinateActivities()
                end)
            end
            if root.Visible~=false then for _,card in ipairs(root:GetChildren()) do readCard(card) end end
        end
    end
    A.job('Opening recovery',0.5,function()
        for _,mode in ipairs(order) do
            if A.settings[definitions[mode].toggle] then A.refreshOpenCards(); A.coordinateActivities(); return end
        end
    end)
    function A.joinSnapshot()
        local openings={}
        for mode,entries in pairs(available) do
            openings[mode]={}
            for key,entry in pairs(entries) do
                openings[mode][key]={open=entry.deadline>os.clock(),remaining=entry.deadline==math.huge and 'until schedule closes' or math.max(0,entry.deadline-os.clock()),rank=entry.rank}
            end
        end
        return {pending=pending and {mode=pending.mode,key=pending.key,accepted=pending.accepted==true,
            attempts=pending.attempts,age=os.clock()-pending.at},locked=locked,leaving=leaving,returning=returning,available=openings,
            stuckExit=stuckExit and {mode=stuckExit.mode,context=stuckExit.context,attempts=stuckExit.attempts},
            stuckRecovery=A.stuckSnapshot and A.stuckSnapshot() or nil}
    end
    A.connect(A.player:GetAttributeChangedSignal('VisibilityContext'),A.coordinateActivities)
    local lastNotifiedContext
    A.connect(A.player:GetAttributeChangedSignal('VisibilityContext'),function()
        local mode,raw=context()
        if raw==lastNotifiedContext then return end
        lastNotifiedContext=raw
        if mode and definitions[mode] and A.settings.webhook then A.notify('Mode','Entered '..mode..': '..raw) end
    end)
    A.job('Activities',0.2,A.coordinateActivities)
end

end)()(A);

-- ===== stuck_recovery =====
(function()
return function(A)
    local specs={MaxTac={bridge='Raid',folder='RaidArenas',key='RaidKey'},Gate={bridge='Raid',folder='RaidArenas',key='RaidKey'},
        Raid={bridge='Raid',folder='RaidArenas',key='RaidKey'},Defense={bridge='Defense',folder='DefenseArenas',key='DefenseKey'},
        Tower={bridge='Tower',folder='TowerArenas',key='TowerKey'},BossRush={bridge='BossRush',folder='BossRushArenas',key='RushKey'},
        TimeTrial={bridge='TimeTrial',folder='TimeTrialArenas',key='TrialKey'},Dungeon={bridge='Dungeon',folder='DungeonArenas',key='DungeonKey'}}
    local watch
    local observed={'Wave','Room','Floor','EnemyCount','Alive','Phase','ShieldBoss','JoinTimeLeft','LandingTimeLeft'}
    local function valid(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
    function A.stuckTimeout(mode)
        local key=(mode=='TimeTrial' or mode=='Dungeon') and 'trialDungeonStuckSeconds' or 'stuckSeconds'
        local value=tonumber(A.settings[key])
        return valid(value) and math.clamp(value,1,3600) or A.defaults[key]
    end
    local function arenaFor(mode,raw)
        local arenas=workspace:FindFirstChild(specs[mode].folder)
        return arenas and arenas:FindFirstChild(raw:match('^[^:]+:(.+)$'))
    end
    local function current()
        if not A.alive or not A.running or not A.settings.autoLeaveStuck then watch=nil; return end
        local mode,raw=A.activityContext()
        if not specs[mode] or type(raw)~='string' then watch=nil; return end
        if not watch or watch.context~=raw or watch.mode~=mode then
            watch={mode=mode,context=raw,lastProgress=os.clock(),state={},deaths={},phase=nil,graceUntil=0}
        end
        return watch
    end
    local function progress(w,reason)
        w.lastProgress=os.clock(); w.reason=reason
    end
    local function isDead(enemy)
        if enemy:GetAttribute('EnemyDead')==true then return true end
        local real=enemy:GetAttribute('HealthReal')
        if real~=nil then
            local big=A.util('BigNum')
            if big and type(big.Decode)=='function' and type(big.Compare)=='function' then
                local ok,decoded=pcall(big.Decode,real)
                if ok and decoded~=nil then
                    local compared,result=pcall(big.Compare,decoded,0)
                    if compared and type(result)=='number' then return result<=0 end
                end
            end
            local n=tonumber(real)
            if valid(n) then return n<=0 end
        end
        local human=enemy:FindFirstChildOfClass('Humanoid')
        return human~=nil and valid(human.Health) and human.Health<=0
    end
    local function phaseGrace(w)
        local phase=w.state.Phase
        if phase==w.phase then return end
        if w.phase~=nil then progress(w,'Run phase advanced') end
        w.phase=phase; w.graceUntil=0
        if w.mode~='Tower' then return end
        local cfg=A.config('TowerConfig') or {}
        local entries=A.activityChoices('Tower')
        local tower=entries[w.key] or {}
        local seconds
        if phase=='Joining' then seconds=tonumber(w.state.JoinTimeLeft) or tonumber(tower.JoinWindowSeconds) or 25
        elseif phase=='Landing' then seconds=tonumber(w.state.LandingTimeLeft) or tonumber(cfg.LandingDecisionSeconds) or 20
        elseif phase=='Rising' then seconds=tonumber(cfg.FloorTransitionSeconds) or 2 end
        if valid(seconds) then w.graceUntil=os.clock()+math.clamp(seconds,0,60) end
    end
    local function gateGrace(w)
        if w.mode~='Gate' or tonumber(w.state.EnemyCount)~=0 then return end
        local mode=A.activityChoices('Gate')[w.key]
        local wave=tonumber(w.state.Wave)
        local every=mode and tonumber(mode.BossEvery)
        if not wave or wave<=0 or not every or every<=0 or wave%every~=0 or w.ariseWave==wave then return end
        w.ariseWave=wave
        local delay=mode.ShadowArise and tonumber(mode.ShadowArise.WaveDelay)
        if valid(delay) then w.graceUntil=math.max(w.graceUntil,os.clock()+math.clamp(delay,0,60)) end
    end
    local function receive(prefix,packet)
        if type(packet)~='table' or packet.Refused then return end
        local w=current()
        if not w or specs[w.mode].bridge~=prefix or w.ended then return end
        local instance=w.context:match('^[^:]+:(.+)$')
        if packet.InstanceKey and packet.InstanceKey~=instance then return end
        local key=packet[specs[w.mode].key]
        if prefix=='TimeTrial' or prefix=='Dungeon' then
            if key and key~=instance then return end
        elseif key and w.key and key~=w.key then return end
        -- Keyed/full packets establish ownership; ignore unassociated deltas.
        if not w.associated and not packet.Full and not packet.InstanceKey and not key then return end
        w.associated=true; if key then w.key=key end
        local old=w.state
        local nextState=packet.Full and {} or A.Core.copy(old)
        for _,field in ipairs(observed) do if packet[field]~=nil then nextState[field]=A.Core.copy(packet[field]) end end
        for _,field in ipairs(type(packet.Cleared)=='table' and packet.Cleared or {}) do nextState[field]=nil end
        for _,field in ipairs({'Wave','Room','Floor'}) do
            local before,after=tonumber(old[field]),tonumber(nextState[field])
            if after and (not before or after>before) then progress(w,field..' advanced') end
        end
        for _,field in ipairs({'EnemyCount','Alive'}) do
            local before,after=tonumber(old[field]),tonumber(nextState[field])
            if before and after and after<before then progress(w,'Enemies defeated') end
        end
        local beforePhase=type(old.ShieldBoss)=='table' and old.ShieldBoss.Phase
        local afterPhase=type(nextState.ShieldBoss)=='table' and nextState.ShieldBoss.Phase
        if beforePhase and afterPhase and beforePhase~=afterPhase then progress(w,'Boss phase advanced') end
        w.state=nextState; phaseGrace(w); gateGrace(w)
    end
    for _,prefix in ipairs({'Raid','Defense','Tower','TimeTrial','Dungeon','BossRush'}) do
        local name=prefix
        A.on(name..'State',function(packet) receive(name,packet) end)
        A.on(name..'Ended',function(_,packet)
            local w=current()
            if not w or specs[w.mode].bridge~=name then return end
            if name=='Raid' and w.mode=='MaxTac' and type(packet)=='table' and packet.AutoGateTransfer==true then return end
            if type(packet)=='table' and packet.InstanceKey and packet.InstanceKey~=w.context:match('^[^:]+:(.+)$') then return end
            w.ended=true; w.deaths={}
        end)
        if name~='Tower' then A.on(name..'MapReady',function(instance,detail)
            local w=current()
            if not w or specs[w.mode].bridge~=name or instance~=w.context:match('^[^:]+:(.+)$') then return end
            local room=(name=='TimeTrial' or name=='Dungeon') and tonumber(detail)
            if w.ended then
                watch=nil; w=current()
            end
            w.associated=true
            if room and (not tonumber(w.state.Room) or room>tonumber(w.state.Room)) then
                w.state.Room=room; progress(w,'Room loaded')
            end
        end) end
    end
    A.connect(A.player:GetAttributeChangedSignal('VisibilityContext'),current)
    function A.stuckSnapshot()
        local w=watch
        return w and {mode=w.mode,context=w.context,key=w.key,timeout=A.stuckTimeout(w.mode),
            idle=math.max(0,os.clock()-math.max(w.lastProgress,w.graceUntil)),reason=w.reason,ended=w.ended==true} or {}
    end
    A.job('Stuck recovery',0.5,function()
        local w=current()
        if not A.settings.autoLeaveStuck then A.status['Stuck recovery']='Disabled'; return end
        if not w then A.status['Stuck recovery']='Watching game modes · normal world farming is unaffected'; return end
        if A.activityExitPending() then return end
        local coordinator=A.joinSnapshot()
        if w.ended or coordinator.returning then A.status['Stuck recovery']='Run ended; waiting for normal return'; return end
        if coordinator.pending or coordinator.leaving then
            progress(w,'Activity transfer pending'); A.status['Stuck recovery']='Waiting for activity transfer'; return
        end
        local arena=arenaFor(w.mode,w.context)
        if arena and not w.key then w.key=arena:GetAttribute(specs[w.mode].key) end
        local enemies=arena and arena:FindFirstChild('Enemies')
        local nextDeaths={}
        local observer=A.client('EnemyController')
        for _,enemy in ipairs(enemies and enemies:GetChildren() or {}) do
            local context=enemy:GetAttribute('VisibilityContext')
            local visible=enemy:GetAttribute('IsClientVisualClone')~=true and (context==nil or context=='' or context==w.context)
            if visible and observer and type(observer.IsGamemodeEnemyVisibleLocally)=='function' then
                local ok,value=pcall(observer.IsGamemodeEnemyVisibleLocally,observer,enemy)
                visible=ok and value==true
            end
            if visible then
                local dead=isDead(enemy)
                if dead and w.deaths[enemy]==false then progress(w,'Enemy defeated') end
                nextDeaths[enemy]=dead
            end
        end
        w.deaths=nextDeaths
        if os.clock()<w.graceUntil then
            A.status['Stuck recovery']=w.mode..' · normal run transition ('..math.ceil(w.graceUntil-os.clock())..'s)'; return
        end
        local idle=os.clock()-math.max(w.lastProgress,w.graceUntil)
        local timeout=A.stuckTimeout(w.mode)
        A.status['Stuck recovery']=w.mode..' · no progress '..string.format('%.1f',idle)..'/'..timeout..'s'
        if idle>=timeout then A.requestStuckExit(w.mode,w.context) end
    end)
end

end)()(A);

-- ===== cyber =====
(function()
return function(A)
    local pending,nextAttempt=nil,0
    function A.ripperdocRows()
        local cfg=A.config('RipperdocConfig'); local rows={}
        for _,slot in ipairs(cfg and cfg.SlotOrder or {}) do rows[#rows+1]={key=slot,label=slot} end
        return rows
    end
    function A.openCyberSystem(kind)
        local cfg=A.config(kind..'Config'); local ctrl=A.client('TeleportController')
        if not cfg or cfg.Enabled~=true then A.status.Cyber='System unavailable'; return end
        if not A.unlocked(cfg.WorldId) then A.status.Cyber='Unlock World '..tostring(cfg.WorldId)..' first'; return end
        if not ctrl or type(ctrl.OpenRemoteSystem)~='function' then A.status.Cyber='Native menu unavailable'; return end
        if ctrl:IsLoading() then A.status.Cyber='Waiting for game loading'; return end
        ctrl:OpenRemoteSystem(cfg.WorldId,kind)
    end
    function A.cyberSummary()
        local cfg=A.config('CyberdeckConfig'); local d=A.data()
        if not cfg or cfg.Enabled~=true then return 'Cyberdeck unavailable in this game version' end
        if not d then return 'Waiting for player data' end
        local equipped={}
        for _,key in ipairs(cfg:GetEquipped(d)) do
            local item=cfg:GetQuickhack(key)
            local overclock=type(cfg.GetOverclocks)=='function' and cfg:GetOverclocks(d,key) or 0
            equipped[#equipped+1]=(item and item.Name or key)..' Lv.'..cfg:GetQuickhackLevel(d,key)
                ..(overclock>0 and (' · OC '..overclock) or '')
        end
        return 'Militech Convoy level: '..cfg:GetConvoyLevel(d)..' | Skill points: '..cfg:GetPoints(d)
            ..'\nRAM: '..cfg:GetUsedRam(d)..' / '..cfg:GetMaxRam(d)
            ..'\nEquipped: '..(#equipped>0 and table.concat(equipped,', ') or 'None')
            ..'\nOverclock Chips: '..A.balance('OverclockChip')
    end
    function A.fixerSummary()
        local cfg=A.config('FixerGigConfig'); local d=A.data(); local util=A.util('FixerGigUtil')
        if not cfg or cfg.Enabled~=true or not util then return 'Fixer Gigs unavailable' end
        if not d then return 'Waiting for player data' end
        local slots=type(d.FixerGigs)=='table' and tonumber(d.FixerGigs.Slots) or nil
        local lines={'Active gigs: '..util.CountActive(d)..' / '..(slots or cfg:GetSlots(d))}
        local now=os.time()
        for i,gig in ipairs(util.GetBoard(d)) do
            if type(gig)=='table' then
                local duration=cfg.Durations and cfg.Durations[gig.Duration]
                local label=duration and duration.Name or tostring(gig.Duration or 'Gig')
                local remaining=type(gig.EndsAt)=='number' and math.max(0,gig.EndsAt-now) or nil
                local state=type(gig.PetUid)~='string' and 'Available' or
                    (util.IsReady(gig,now) and 'READY TO CLAIM' or
                    (remaining and (math.floor(remaining/60)..'m '..math.floor(remaining%60)..'s remaining') or 'End time unavailable'))
                lines[#lines+1]=i..'. '..label..' · '..tostring(gig.Name or 'Fixer gig')..' · '..state
            end
        end
        return table.concat(lines,'\n')
    end
    function A.serverBoostSummary()
        local cfg=A.config('ServerBoostConfig')
        local folder=cfg and A.S.RS:FindFirstChild(cfg.StateFolderName)
        if not folder then return 'Waiting for server boost state' end
        local lines={}; local now=workspace:GetServerTimeNow()
        for _,kind in ipairs(cfg.TypeOrder or {}) do
            local owner=folder:GetAttribute(kind..'Owner')
            local finish=tonumber(folder:GetAttribute(kind..'EndsAt')) or 0
            local remaining=math.max(0,finish-now)
            local entry=cfg.Types and cfg.Types[kind] or {}
            local bonus=entry.Multiplier and ('x'..entry.Multiplier) or ('+'..tostring(entry.Bonus or 0))
            lines[#lines+1]=kind..' '..bonus..' · '..(remaining>0 and type(owner)=='string' and owner~='' and
                (math.ceil(remaining/60)..'m left · '..owner) or 'Inactive')
        end
        return table.concat(lines,'\n')
    end
    local gigPending,gigNext=nil,0
    local function sameGig(gig,request)
        return type(gig)=='table' and gig.Id==request.id and gig.PetUid==request.pet and gig.EndsAt==request.endsAt
    end
    A.job('Fixer gigs',5,function()
        if not A.settings.fixerAutoClaim and not gigPending then return end
        local cfg=A.config('FixerGigConfig'); local util=A.util('FixerGigUtil'); local d=A.data()
        if not cfg or cfg.Enabled~=true or not util or not d then return end
        -- An unavailable replication snapshot is not evidence of a successful claim.
        if type(d.FixerGigs)~='table' or type(d.FixerGigs.Board)~='table' then
            A.status['Fixer gigs']='Waiting for the gig board'; return
        end
        local board=util.GetBoard(d)
        if gigPending then
            if not sameGig(board[gigPending.index],gigPending) then
                A.status['Fixer gigs']='Claimed completed gig '..gigPending.index
                if A.settings.webhook then A.notify('Progress',A.status['Fixer gigs']) end
                gigPending=nil
            elseif os.clock()-gigPending.at<20 then
                A.status['Fixer gigs']='Waiting for gig claim confirmation'; return
            else
                gigPending=nil; gigNext=os.clock()+120
                A.status['Fixer gigs']='Gig claim unconfirmed; retrying after 120s'; return
            end
        end
        if not A.settings.fixerAutoClaim or not A.alive or not A.running or os.clock()<gigNext then return end
        if not A.unlocked(cfg.WorldId) then A.status['Fixer gigs']='Unlock Night City first'; return end
        local ctrl=A.client('TeleportController')
        if ctrl and ctrl:IsLoading() then A.status['Fixer gigs']='Waiting for game loading'; return end
        local index,gig
        for i,value in ipairs(board) do if util.IsReady(value,os.time()) then index=i; gig=value; break end end
        if not index then A.status['Fixer gigs']='Waiting for completed gigs'; return end
        local fn=A.Library.Network.Functions:FindFirstChild('FixerGigAction')
        if not fn then A.status['Fixer gigs']='FixerGigAction unavailable'; return end
        gigPending={index=index,id=gig.Id,pet=gig.PetUid,endsAt=gig.EndsAt,at=os.clock()}
        gigNext=os.clock()+5
        -- Exact native Claim payload. Never send pets, buy slots or finish gigs for Robux.
        local ok,accepted,reason=pcall(fn.InvokeServer,fn,'Claim',index,nil)
        if not A.alive then return end
        if not ok or accepted~=true then
            gigPending=nil; gigNext=os.clock()+30
            A.status['Fixer gigs']='Claim refused: '..tostring(ok and reason or accepted)
        end
    end)
    if A.container and type(A.container.OnChange)=='function' then
        local ok,connection=pcall(A.container.OnChange,A.container,{'FixerGigs'},function()
            if A.alive and A.settings.fixerAutoClaim then A.tasks['Fixer gigs'].next=0 end
        end)
        if ok and connection then A.connections[#A.connections+1]=connection end
    end
    A.job('Ripperdoc',1,function()
        if not A.settings.ripperdocAuto and not pending then return end
        local cfg=A.config('RipperdocConfig'); local d=A.data()
        if not cfg or cfg.Enabled~=true or not d then return end
        if pending then
            if cfg:GetLevel(d,pending.slot)>pending.level then
                A.status.Ripperdoc='Upgraded '..pending.slot..' to Lv.'..cfg:GetLevel(d,pending.slot)
                if A.settings.webhook then A.notify('Progress',A.status.Ripperdoc) end
                pending=nil
            elseif os.clock()-pending.at<20 then
                A.status.Ripperdoc='Waiting for '..pending.slot..' upgrade confirmation'; return
            else
                A.status.Ripperdoc='Upgrade unconfirmed; waiting 120s before retrying'
                pending=nil; nextAttempt=os.clock()+120; return
            end
        end
        if not A.settings.ripperdocAuto or os.clock()<nextAttempt then return end
        if not A.unlocked(cfg.WorldId) then A.status.Ripperdoc='Unlock Night City first'; return end
        local chosen,level,cost
        for _,slot in ipairs(cfg.SlotOrder) do
            if A.settings.ripperdocSlots[slot] then
                local current=cfg:GetLevel(d,slot)
                local amount=cfg:GetNextCost(slot,current)
                if amount and cfg:IsSlotOpen(d,slot) then chosen=slot; level=current; cost=amount; break end
            end
        end
        if not chosen then A.status.Ripperdoc='Select unfinished slots; later slots require the previous slot at max'; return end
        if A.balance(cfg.CostItemId)<cost then
            A.status.Ripperdoc='Need '..cost..' '..cfg.CostItemId..' for '..chosen; return
        end
        local fn=A.Library.Network.Functions:FindFirstChild('RipperdocUpgrade')
        if not fn then A.status.Ripperdoc='RipperdocUpgrade unavailable'; return end
        -- One normal, serial server request; never spend again before replication confirms.
        pending={slot=chosen,level=level,at=os.clock()}; nextAttempt=os.clock()+2
        A.status.Ripperdoc='Upgrading '..chosen
        local ok,accepted,reason=pcall(fn.InvokeServer,fn,chosen)
        if not A.alive then return end
        if not ok or accepted~=true then
            pending=nil; nextAttempt=os.clock()+30
            A.status.Ripperdoc='Upgrade refused: '..tostring(ok and reason or accepted)
        end
    end)
end

end)()(A);

-- ===== index_sources =====
(function()
return function(A)
    local order={'Accessories','PetAccessories','Titans','Shadows','Swords','Primordials','Mounts'}
    local configs={Accessories='AccessoryConfig',PetAccessories='PetAccessoryConfig',Titans='TitansConfig',
        Shadows='ShadowsConfig',Swords='SwordConfig',Primordials='PrimordialsConfig',Mounts='MountConfig'}
    local rewardCategories={Accessory='Accessories',Accesory='Accessories',PetAccessory='PetAccessories',Mount='Mounts'}
    local accessoryRarities={Common=true,Uncommon=true,Rare=true,Epic=true,Legendary=true,Mythical=true,Secret=true,Divine=true,Limited=true}
    local function finite(n) return type(n)=='number' and n==n and n>=0 and n<math.huge end
    local function percent(n)
        n=tonumber(n)
        if not finite(n) then return 'Chance not published' end
        if n==0 then return '0%' end
        local text=string.format('%.10f',n):gsub('0+$',''):gsub('%.$','')
        if tonumber(text)==0 then text=string.format('%.4g',n) end
        return text..'%'
    end
    local function esc(text)
        return tostring(text or ''):gsub('[%c]',' '):gsub('([\\`*_~|%[%]<>])','\\%1')
    end
    A.indexPercent=percent
    A.indexEscape=esc

    function A.indexSnapshot()
        local data=A.data()
        assert(type(data)=='table','Player data is not ready. Try again after the game loads.')
        local collection=A.util('CollectionUtil')
        assert(collection and type(collection.GetKeys)=='function' and type(collection.GetObtained)=='function',
            'The game Index collection API is unavailable. No report was sent.')
        local cache={}
        local warnings={}
        local function config(name,required)
            if cache[name]==nil then
                local ok,value=pcall(A.config,name)
                cache[name]=ok and type(value)=='table' and value or false
                if not cache[name] then warnings[#warnings+1]=name..' unavailable' end
            end
            if required then assert(cache[name],name..' is unavailable. No incomplete Index scan was sent.') end
            return cache[name] or nil
        end
        local function all(name,getter,field)
            local cfg=config(name)
            if not cfg then return {} end
            if type(cfg[getter])=='function' then
                local ok,value=pcall(cfg[getter],cfg)
                if ok and type(value)=='table' then return value end
                warnings[#warnings+1]=name..'.'..getter..' failed'
            end
            return type(cfg[field])=='table' and cfg[field] or {}
        end
        local worlds=all('WorldConfig','GetAllWorlds','Worlds')
        local enemies=all('EnemyConfig','GetAllEnemies','Enemies')
        local spawnConfig=config('SpawnBossConfig')
        local spawnEnemies={}
        for _,boss in pairs(spawnConfig and type(spawnConfig.Bosses)=='table' and spawnConfig.Bosses or {}) do
            if type(boss)=='table' and type(boss.EnemyId)=='string' then spawnEnemies[boss.EnemyId]=boss end
        end
        local raids=all('RaidConfig','GetAllRaids','Raids')
        local defenses=all('DefenseConfig','GetAllDefenses','Defenses')
        local trials=all('TimeTrialConfig','GetAllTrials','Trials')
        local dungeons=all('DungeonConfig','GetAllDungeons','Dungeons')
        local towers=all('TowerConfig','GetAllTowers','Towers')
        local rushes=all('BossRushConfig','GetAllRushes','Rushes')
        local resources=config('ResourcesConfig')
        local function resource(id)
            local item=resources and resources.Items and resources.Items[id]
            return esc(item and item.Name or id or 'currency')
        end
        local function worldId(key,explicit)
            local id=tonumber(explicit)
            if id then return id end
            for wid,w in pairs(worlds) do
                for _,system in pairs(type(w.Systems)=='table' and w.Systems or {}) do
                    if type(system)=='table' and system.Key==key then return tonumber(wid) end
                end
            end
            return tonumber(tostring(key):match('^World(%d+)'))
        end
        local function location(id)
            local w=id and (worlds[id] or worlds[tostring(id)])
            return id and ('World '..tostring(id)..' — '..esc(w and w.Name or 'world name unavailable')) or 'Global'
        end
        local function enemyName(id)
            return esc(type(enemies[id])=='table' and enemies[id].Name or id)
        end
        local function cost(value)
            if type(value)~='table' or value.ItemId==nil then return '' end
            return ' | Cost: '..esc(value.Amount or 1)..' '..resource(value.ItemId)
        end
        local result={at=os.time(),categories={},missing=0,total=0,unknown=0,warnings=warnings}
        local targets={}
        local count=0
        local function yieldScan()
            count=count+1
            if count%40==0 then
                task.wait()
                assert(A.alive,'Index scan cancelled because JoesAAS was unloaded.')
            end
        end
        for _,category in ipairs(order) do
            local cfg=config(configs[category],true)
            local keys=collection.GetKeys(category)
            local obtained=collection.GetObtained(data,category)
            assert(type(keys)=='table' and type(obtained)=='table','Invalid Index snapshot for '..category)
            local group={key=category,name=category=='PetAccessories' and 'Pet Accessories' or category,total=0,items={}}
            result.categories[#result.categories+1]=group
            targets[category]={}
            local seen={}
            for _,key in ipairs(keys) do
                if type(key)=='string' and not seen[key] then
                    seen[key]=true
                    local system,rarity=key:match('^(.-)::(.+)$')
                    local item
                    if category=='Titans' then item=cfg.Titans and cfg.Titans[system] and cfg.Titans[system].Items[rarity]
                    elseif category=='Swords' then item=cfg.Swords and cfg.Swords[system] and cfg.Swords[system].Items[rarity]
                    elseif category=='Shadows' then item=cfg:GetShadow(key)
                    elseif category=='Primordials' then item=cfg.Demons and cfg.Demons[key]
                    else item=cfg.Items and cfg.Items[key] end
                    assert(type(item)=='table','Index metadata is missing for '..category..' / '..key)
                    local include=(category~='Accessories' or accessoryRarities[item.Rarity]==true)
                        and ((category~='Accessories' and category~='PetAccessories') or item.IndexDisabled~=true)
                    if include then
                        group.total=group.total+1
                        if obtained[key]~=true then
                            local name=item.Name or key
                            if category=='Shadows' and item.Rank then name=name..' · Rank '..item.Rank end
                            local entry={key=key,name=tostring(name),rarity=item.Rarity or rarity or 'Unknown',
                                system=system,variant=rarity,metadata=item,sources={},sourceKeys={}}
                            group.items[#group.items+1]=entry; targets[category][key]=entry
                        end
                    end
                end
                yieldScan()
            end
            result.total=result.total+group.total; result.missing=result.missing+#group.items
        end
        local function add(category,id,wid,text)
            local item=targets[category] and targets[category][id]
            if not item then return end
            local line=location(wid)..'\n'..text
            if not item.sourceKeys[line] then
                item.sourceKeys[line]=true
                item.sources[#item.sources+1]={world=wid or math.huge,text=line}
            end
        end
        local function identify(id,kind)
            if kind~=nil then return rewardCategories[kind] end
            local match
            for _,category in ipairs({'Accessories','PetAccessories','Mounts'}) do
                local cfg=config(configs[category],true)
                if cfg.Items and cfg.Items[id] then
                    if match then return nil end -- A shared ID needs its explicit RewardType.
                    match=category
                end
            end
            return match
        end
        local function drops(values,wid,label,unit,extra)
            for id,drop in pairs(type(values)=='table' and values or {}) do
                if type(drop)=='table' then
                    local itemId=drop.ItemId or drop.Id or id
                    local category=identify(itemId,drop.RewardType or drop.Type)
                    if category then
                        add(category,itemId,wid,label..'\nBase chance: '..percent(drop.Chance)..' '..unit..(extra or ''))
                    end
                end
                yieldScan()
            end
        end
        for id,enemy in pairs(enemies) do
            local spawn=spawnEnemies[id]
            local extra=spawn and ('\nSummon cost: '..tostring(spawn.CostAmount or 1)..' '..resource(spawn.CostItemId)
                ..'\nLoot requires the game\'s participation threshold') or ''
            drops(enemy.Drops,tonumber(spawn and spawn.WorldId or enemy.World),
                (spawn and 'Spawn boss: ' or 'Enemy: ')..enemyName(id),'per kill',extra)
        end
        local function modes(values,kind)
            for key,mode in pairs(values) do
                local wid=worldId(key,mode.WorldId)
                local name=esc(mode.Name or key)
                local label=kind..': '..name
                local extra=cost(mode.Cost)
                drops(mode.Drops,wid,label..' — all enemies','per kill',extra)
                drops(mode.CompletionRewards,wid,label..' — completion reward','per completed run',extra)
                local grouped={}
                for id,enemy in pairs(type(mode.Enemies)=='table' and mode.Enemies or {}) do
                    for itemId,drop in pairs(type(enemy.Drops)=='table' and enemy.Drops or {}) do
                        if type(drop)=='table' then
                            local category=identify(itemId,drop.RewardType or drop.Type)
                            if category then
                                local identity=category..'/'..itemId..'/'..tostring(drop.Chance)
                                local entry=grouped[identity]
                                if not entry then entry={category=category,id=itemId,chance=drop.Chance,enemies={}}; grouped[identity]=entry end
                                entry.enemies[enemyName(id)]=true
                            end
                        end
                        yieldScan()
                    end
                end
                for _,entry in pairs(grouped) do
                    add(entry.category,entry.id,wid,label..'\nEnemies: '..table.concat(A.Core.keys(entry.enemies),', ')
                        ..'\nBase chance: '..percent(entry.chance)..' per kill'..extra)
                end
            end
        end
        modes(raids,'Raid / Gate'); modes(defenses,'Defense'); modes(trials,'Time Trial')
        modes(dungeons,'Dungeon'); modes(towers,'Tower')
        for key,rush in pairs(rushes) do
            for _,mode in pairs(type(rush.Modes)=='table' and rush.Modes or {}) do
                local wid=worldId(key,rush.WorldId)
                local name='Boss Rush: '..esc(mode.Name or rush.Name or key)
                drops(mode.BossDrops,wid,name..' — boss drops','per boss kill',cost(mode.Cost))
                drops(mode.CompletionRewards,wid,name..' — completion reward','per completed run',cost(mode.Cost))
            end
        end
        local function roll(category,cfg,systemKey,system,items)
            local orderForRoll={}
            for _,rarity in ipairs(cfg.Rarity_Order or {}) do
                for _,item in pairs(items) do
                    if item.Rarity==rarity then orderForRoll[#orderForRoll+1]=rarity; break end
                end
                if items[rarity] and not A.Core.contains(orderForRoll,rarity) then orderForRoll[#orderForRoll+1]=rarity end
            end
            local weights=cfg.Rarity_Weights or {}; local sum=0
            for _,rarity in ipairs(orderForRoll) do sum=sum+math.max(0,tonumber(weights[rarity]) or 0) end
            for id,item in pairs(items) do
                local rarity=item.Rarity or id
                local key=category=='Primordials' and id or systemKey..'::'..id
                local probability=sum>0 and math.max(0,tonumber(weights[rarity]) or 0)/sum*100
                    or (#orderForRoll>0 and 100/#orderForRoll or nil)
                add(category,key,worldId(systemKey,system.WorldId),
                    'Roll: '..esc(system.Name or category)..'\nBase chance: '..percent(probability)..' per roll'..cost(system.ItemCost))
                yieldScan()
            end
        end
        local titans=config('TitansConfig',true)
        for key,system in pairs(titans.Titans or {}) do roll('Titans',titans,key,system,system.Items or {}) end
        local swords=config('SwordConfig',true)
        for key,system in pairs(swords.Swords or {}) do roll('Swords',swords,key,system,system.Items or {}) end
        local primordials=config('PrimordialsConfig',true)
        roll('Primordials',primordials,primordials.SystemKey or 'Primordials',primordials,primordials.Demons or {})
        local shadows=config('ShadowsConfig',true)
        for key,mode in pairs(raids) do
            if type(mode.ShadowArise)=='table' then
                for _,rank in ipairs(mode.GateRanks or {{Rank='Default'}}) do
                    local bosses=rank.Bosses or mode.Bosses or {}; local bossTotal=0
                    for _,boss in ipairs(bosses) do bossTotal=bossTotal+math.max(0,tonumber(boss.Weight) or 0) end
                    local weights=rank.AriseVariantWeights or {}; local total=0
                    for _,variant in ipairs(shadows.AriseVariants or {}) do
                        total=total+math.max(0,tonumber(weights[variant.Rarity] or variant.Weight) or 0)
                    end
                    for _,boss in ipairs(bosses) do
                        for _,variant in ipairs(shadows.AriseVariants or {}) do
                            local variantChance=total>0 and math.max(0,tonumber(weights[variant.Rarity] or variant.Weight) or 0)/total*100 or nil
                            add('Shadows',shadows:GetVariantShadowKey(boss.EnemyId,variant.Rarity),worldId(key,mode.WorldId),
                                'Gate: '..esc(mode.Name or key)..' · Gate rank '..esc(rank.Rank)..'\nBoss: '..enemyName(boss.EnemyId)
                                ..' | Spawn share: '..percent(bossTotal>0 and math.max(0,tonumber(boss.Weight) or 0)/bossTotal*100 or nil)
                                ..'\nARISE success: '..percent(mode.ShadowArise.ChancePercent)..' per attempt; '
                                ..esc(mode.ShadowArise.Chances or '?')..' attempts\nVariant chance after successful ARISE: '..percent(variantChance))
                        end
                    end
                end
            end
        end
        local bundles=config('DevProductConfig')
        for key,bundle in pairs(bundles or {}) do
            if type(bundle)=='table' then
                for _,spec in ipairs({{'Accessories','AccessoryId'},{'PetAccessories','PetAccessoryId'},{'Mounts','MountId'}}) do
                    for _,reward in pairs(type(bundle[spec[1]])=='table' and bundle[spec[1]] or {}) do
                        add(spec[1],reward[spec[2]],nil,'Shop: '..esc(bundle.Name or key)
                            ..'\nGuaranteed on purchase (no drop roll) | Price: '..esc(bundle.Price or '?')..' Robux'
                            ..(bundle.TicketPrice and (' / '..esc(bundle.TicketPrice)..' paid tickets') or '')
                            ..(bundle.GlobalMaxPurchases and (' | Limited stock: '..esc(bundle.GlobalMaxPurchases)) or ''))
                    end
                end
            end
        end
        local passes=config('BattlepassConfig')
        for key,pass in pairs(passes and passes.Passes or {}) do
            for _,track in ipairs({'FreeRewards','PremiumRewards'}) do
                for level,reward in ipairs(pass[track] or {}) do
                    local category=rewardCategories[reward.Type]
                    if category then add(category,reward.Id,worldId(key,pass.WorldId),
                        'Battlepass: '..esc(pass.Name or key)..'\n'..(track=='FreeRewards' and 'Free' or 'Premium')
                        ..' track · Level '..level..'\nGuaranteed when eligible reward is claimed (no drop roll)') end
                end
            end
        end
        local merchant=config('MerchantConfig')
        for key,shop in pairs(merchant and merchant.Shops or {}) do
            for _,product in ipairs(shop.Products or {}) do
                local category=identify(product.ItemId,product.RewardType)
                if category then add(category,product.ItemId,worldId(key,shop.WorldId),
                    'Shop: '..esc(shop.Name or key)..' (when available)\nGuaranteed on purchase (no drop roll) | Cost: '
                    ..esc(product.Price or '?')..' '..resource(shop.Currency and shop.Currency.ItemId)) end
            end
        end
        for _,name in ipairs({'CorvoConfig','BallConfig'}) do
            local cfg=config(name)
            if cfg then
                local label='Event: '..esc(cfg.Prompt and cfg.Prompt.ObjectText or name)..' — find it and claim the prompt'
                for _,reward in ipairs(cfg.Rewards or {}) do
                    local category=identify(reward.ItemId,reward.RewardType)
                    if category then
                        local pity=cfg.AccessoryPity
                        add(category,reward.ItemId,tonumber(cfg.WorldId),label..'\nBase chance: '..percent(reward.Chance)..' per claim'
                            ..(pity and pity.Enabled and pity.ItemId==reward.ItemId and (' | Configured pity: '..esc(pity.Threshold)..' claims') or ''))
                    end
                end
            end
        end
        local medal=config('MedalConfig')
        for _,reward in ipairs(medal and medal.Rewards or {}) do
            local category=rewardCategories[reward.Type]
            if category then add(category,reward.PetAccessoryId or reward.ItemId or reward.Id,nil,
                'Medal rewards: link your Medal account, post an Anime Astral clip and play for '
                ..esc((tonumber(medal.PlaytimeRequired) or 0)/60)..' minutes\nGuaranteed when eligible reward is claimed (no drop roll)'
                ..(medal.Enabled==false and ' | Disabled in current config' or '')) end
        end
        for _,group in ipairs(result.categories) do
            local names={}
            for _,item in ipairs(group.items) do names[item.name]=(names[item.name] or 0)+1 end
            for _,item in ipairs(group.items) do
                if names[item.name]>1 and group.key=='Mounts' then
                    local stats=A.Core.keys(item.metadata.Multiplier or {})
                    item.name=item.name..' · '..(#stats>0 and table.concat(stats,' / ') or item.key)
                end
                if #item.sources==0 then
                    result.unknown=result.unknown+1
                    item.sources[1]={world=math.huge,text='Source and chance not published in the current client configs.\nThis entry is still in the game Index; availability cannot be verified.'}
                end
                table.sort(item.sources,function(a,b) if a.world==b.world then return a.text<b.text end return a.world<b.world end)
                item.world=item.sources[1].world
                item.metadata=nil; item.sourceKeys=nil
            end
            table.sort(group.items,function(a,b)
                if a.world~=b.world then return a.world<b.world end
                if a.name~=b.name then return a.name<b.name end
                if a.rarity~=b.rarity then return a.rarity<b.rarity end
                return a.key<b.key
            end)
        end
        return result
    end
end

end)()(A);

-- ===== index_report =====
(function()
return function(A)
    -- This destination belongs only to the manual Index report button.
    local destination='https://discord.com/api/webhooks/1556049988575035502/Mh4wKE7W2mnvtsgRt6UfPYaHRiwzFLhI-CkZ2YUYDk4gg1RjjiXEfye8mghrmVKxlrXC'
    local env=(type(getgenv)=='function' and getgenv()) or _G
    local state=env.JoesAASIndexDelivery
    if type(state)~='table' or state.version~=1 then
        state={version=1,pages={},cursor=1,next=0,attempt=0,busy=false,building=false}
        env.JoesAASIndexDelivery=state
    end
    local colors={Accessories=16763955,PetAccessories=12418047,Titans=16742972,Shadows=8282367,
        Swords=5031394,Primordials=15755396,Mounts=6804333}
    local function chunks(text,limit)
        local out={}
        while #text>limit do
            local cut=limit
            -- Byte budgets are conservative for Discord's character limits.
            -- Never cut a UTF-8 code point or discard any source text.
            while cut>0 and (text:byte(cut+1) or 0)>=128 and (text:byte(cut+1) or 0)<192 do cut=cut-1 end
            local newline=text:sub(1,cut):match('.*()\n')
            if newline and newline>cut/2 then cut=newline end
            out[#out+1]=text:sub(1,cut)
            text=text:sub(cut+1)
        end
        if text~='' then out[#out+1]=text end
        return out
    end
    local function label(value,limit)
        return chunks(A.indexEscape(value),limit)[1] or 'Unnamed item'
    end
    function A.indexPages(snapshot)
        assert(type(snapshot)=='table' and type(snapshot.categories)=='table','Invalid Index report snapshot')
        local esc=A.indexEscape
        local summary={}
        for _,group in ipairs(snapshot.categories) do
            summary[#summary+1]='**'..esc(group.name)..'** — '..#group.items..' missing / '..group.total..' total'
        end
        local description='**'..esc(A.player.Name)..'** · '..snapshot.missing..' missing entries\n\n'
            ..table.concat(summary,'\n')..'\n\n'
            ..'Chances are **base, unboosted** percentages. Luck, Drop bonuses and pity can change actual odds. '
            ..'Shadow variant chances apply **after a successful ARISE**, separately from boss spawns.\n'
            ..'Obtained entries follow the game Index inventory and collection history. **Pets are excluded.**'
        if snapshot.unknown>0 then description=description..'\n**'..snapshot.unknown..' entries have unpublished source/chance details**; they are listed explicitly.' end
        if snapshot.missing==0 then description=description..'\n\nAll seven requested collections are complete.' end
        local pages={{title='JoesAAS · Missing Index',description=description,color=5031394}}
        for _,group in ipairs(snapshot.categories) do
            local page,size,categoryPages=nil,0,{}
            local function newPage()
                page={title='JoesAAS · '..group.name,description=#group.items..' missing entries · ordered by world',
                    color=colors[group.key] or 5031394,fields={}}
                size=#page.title+#page.description+180
                pages[#pages+1]=page; categoryPages[#categoryPages+1]=page
            end
            for _,item in ipairs(group.items) do
                local sources={}
                for i,source in ipairs(item.sources) do sources[#sources+1]='**Source '..i..'**\n'..source.text end
                local text='**'..esc(item.rarity)..'**\n'..table.concat(sources,'\n\n')
                local name=esc(item.name)
                if #name>220 then text='**Full name:** '..name..'\n'..text; name=label(item.name,200) end
                for part,value in ipairs(chunks(text,900)) do
                    local fieldName=name..(part>1 and (' · continued '..part) or '')
                    if not page or #page.fields>=8 or size+#fieldName+#value>5400 then newPage() end
                    page.fields[#page.fields+1]={name=fieldName,value=value,inline=false}
                    size=size+#fieldName+#value
                end
            end
            for i,categoryPage in ipairs(categoryPages) do
                categoryPage.description=categoryPage.description..' · category page '..i..'/'..#categoryPages
            end
        end
        if #(snapshot.warnings or {})>0 then
            local warnings='Some source configs could not be read. Missing-entry counts still use the complete game Index.\n\n'
                ..table.concat(snapshot.warnings,'\n')
            for _,part in ipairs(chunks(warnings,3500)) do
                pages[#pages+1]={title='JoesAAS · Source lookup warnings',description=part,color=16763955}
            end
        end
        local reportID=os.date('!%Y%m%d-%H%M%S',snapshot.at)..'-'..tostring(math.floor(os.clock()*1000)%100000)
        for i,page in ipairs(pages) do
            page.footer={text='Report '..reportID..' · Part '..i..'/'..#pages..' · '..os.date('!%Y-%m-%d %H:%M UTC',snapshot.at)}
        end
        return pages
    end
    local function progress()
        return math.max(0,state.cursor-1)..'/'..#state.pages..' pages'
    end
    local function setStatus(message)
        state.status=message; A.status.Index=message
    end
    function A.sendIndexReport()
        if state.building then setStatus('Scanning your Index; please wait'); return false end
        if state.cursor<=#state.pages then
            if state.blocked then
                state.blocked=false; state.attempt=0; state.next=0
                setStatus('Resuming report · '..progress())
                return true
            end
            A.status.Index=state.status or ('Sending report · '..progress()); return false
        end
        if type(A.httpRequest)~='function' then setStatus('Executor HTTP request API unavailable; no report was sent'); return false end
        state.building=true; setStatus('Scanning your Index and looking up sources…')
        task.spawn(function()
            local ok,pages=pcall(function() return A.indexPages(A.indexSnapshot()) end)
            state.building=false
            if not A.alive then return end
            if not ok then
                setStatus('Index scan failed: '..tostring(pages):gsub('https://[^%s]+/api/webhooks/[^%s]+','[webhook redacted]'))
                A.log('Index',A.status.Index); return
            end
            state.pages=pages; state.cursor=1; state.next=0; state.attempt=0; state.blocked=false
            setStatus('Sending report · '..progress())
        end)
        return true
    end
    A.status.Index=state.status or 'Ready · press the button to send your missing Index'
    A.job('Index report delivery',0.2,function()
        if state.building or state.busy then return end
        if state.status then A.status.Index=state.status end
        if state.blocked or state.cursor>#state.pages or os.clock()<state.next then return end
        if env.AnimeSuiteHTTP and env.AnimeSuiteHTTP.busy then return end
        local page=state.pages[state.cursor]
        state.busy=true
        local ok,response=pcall(function()
            local body=A.S.HTTP:JSONEncode({username='JoesAAS Index',embeds={page}})
            -- Roblox encodes an empty table as {}; Discord requires an array.
            body=body:sub(1,-2)..',"allowed_mentions":{"parse":[]}}'
            local sent,value=A.http({Url=destination..'?wait=true',Method='POST',
                Headers={['Content-Type']='application/json'},Body=body},true)
            return {sent=sent,value=value}
        end)
        state.busy=false
        local result=ok and response.sent and type(response.value)=='table' and response.value or nil
        local status=result and tonumber(result.StatusCode or result.Status) or 0
        local parsed
        if result then
            local decoded,value=pcall(A.S.HTTP.JSONDecode,A.S.HTTP,result.Body or '')
            if decoded and type(value)=='table' then parsed=value end
        end
        state.attempt=state.attempt+1
        local headers=result and type(result.Headers)=='table' and result.Headers or {}
        local action,delay=A.Core.webhookRetry(status or 0,headers,parsed,state.attempt)
        if action=='done' then
            state.cursor=state.cursor+1; state.attempt=0; state.next=os.clock()+2
            state.status=state.cursor>#state.pages and ('Report sent · '..progress()) or ('Sending report · '..progress())
            if state.cursor>#state.pages then state.pages={}; state.cursor=1 end
        elseif action=='stop' or (state.attempt>=8 and status~=429) then
            state.blocked=true
            state.status='Report paused · '..progress()..' · HTTP '..tostring(status)
                ..' · press the button to retry the unsent pages'
        else
            state.next=os.clock()+delay
            state.status='Sending report · '..progress()..' · retry in '..math.ceil(delay)..'s (HTTP '..tostring(status)..')'
        end
        A.status.Index=state.status
        -- Do not log HTTP responses: an executor or Discord error can echo the secret URL.
    end,true)
end

end)()(A);

-- ===== ui =====
(function()
return function(A)
    local C=A.Core
    assert(type(loadstring)=='function','This executor session has no loadstring API; Fluent cannot load.')
    local downloaded,source=pcall(function()
        return game:HttpGet('https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua')
    end)
    assert(downloaded and type(source)=='string','Could not download Fluent; check this executor session and network connection.')
    local loader,err=loadstring(source)
    assert(loader,'Fluent download could not compile: '..tostring(err))
    local F=loader(); A.fluent=F; A.gui=F.GUI
    local touch=A.S.UIS.TouchEnabled==true
    local camera=workspace.CurrentCamera
    local function dimensions()
        local viewport=camera and camera.ViewportSize or Vector2.new(720,600)
        return math.min(680,math.max(120,viewport.X-24)),math.min(540,math.max(120,viewport.Y-(touch and 76 or 48)))
    end
    local width,height=dimensions()
    local window=F:CreateWindow({Title='JoesAAS',SubTitle='5.7',TabWidth=touch and 92 or 150,
        Size=UDim2.fromOffset(width,height),Acrylic=false,Theme='Dark',MinimizeKey=Enum.KeyCode.RightShift})
    A.gui.DisplayOrder=100001
    local popupLimits={}
    local function fitScreen()
        local w,h=dimensions()
        if window.Root then
            local viewport=camera and camera.ViewportSize or Vector2.new(720,600)
            window.Size=UDim2.fromOffset(w,h)
            window.Position=UDim2.fromOffset((viewport.X-w)/2,(viewport.Y-h)/2)
            window.Root.Size=window.Size; window.Root.Position=window.Position
        end
        if A.clampTouchButton then A.clampTouchButton() end
        if touch then
            for _,limit in ipairs(popupLimits) do limit.MaxSize=Vector2.new(w,h) end
        end
    end
    local function bindCamera()
        if A.viewportConnection then A.viewportConnection:Disconnect() end
        camera=workspace.CurrentCamera
        if camera then A.viewportConnection=A.connect(camera:GetPropertyChangedSignal('ViewportSize'),fitScreen) end
        fitScreen()
    end
    A.connect(workspace:GetPropertyChangedSignal('CurrentCamera'),bindCamera)
    bindCamera()
    if touch then
        function window:Minimize()
            self.Minimized=not self.Minimized; self.Root.Visible=not self.Minimized
        end
        A.touchGui=Instance.new('ScreenGui'); A.touchGui.Name='JoesAASTouchControls'
        A.touchGui.ResetOnSpawn=false; A.touchGui.DisplayOrder=100002
        A.touchGui.Parent=A.player:WaitForChild('PlayerGui')
        A.touchControls={}
        local function touchButton(name,offset,callback)
            local b=Instance.new('TextButton'); b.Name=name; b.Text=name
            b.Size=UDim2.fromOffset(78,44); b.Position=UDim2.new(1,offset,0,6)
            b.TextSize=15; b.TextColor3=Color3.new(1,1,1); b.BackgroundColor3=Color3.fromRGB(28,31,38)
            b.Parent=A.touchGui; local corner=Instance.new('UICorner'); corner.CornerRadius=UDim.new(0,8); corner.Parent=b
            A.connect(b.Activated,callback); A.touchControls[name]=b; return b
        end
        local dragging,suppressTap=nil,false
        local suite=touchButton('JoesAAS',-122,function()
            if not suppressTap then window:Minimize() end
        end)
        suite.Size=UDim2.fromOffset(110,46); suite.Text='JoesAAS'; suite.TextSize=15
        suite.Font=Enum.Font.GothamBold; suite.AutoButtonColor=false
        suite.BackgroundColor3=Color3.fromRGB(18,24,34); suite.TextColor3=Color3.fromRGB(230,245,255)
        local shape=suite:FindFirstChildOfClass('UICorner'); if shape then shape.CornerRadius=UDim.new(0,16) end
        local outline=Instance.new('UIStroke'); outline.Color=Color3.fromRGB(77,197,232)
        outline.Thickness=1.3; outline.Transparency=0.2; outline.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; outline.Parent=suite
        local accent=Instance.new('Frame'); accent.Size=UDim2.fromOffset(5,18)
        accent.Position=UDim2.fromOffset(9,14); accent.BorderSizePixel=0
        accent.BackgroundColor3=Color3.fromRGB(77,197,232); accent.Parent=suite
        local accentRound=Instance.new('UICorner'); accentRound.CornerRadius=UDim.new(1,0); accentRound.Parent=accent
        for x=0,1 do for y=0,2 do
            local dot=Instance.new('Frame'); dot.Size=UDim2.fromOffset(2,2)
            dot.Position=UDim2.fromOffset(96+x*4,17+y*5); dot.BorderSizePixel=0
            dot.BackgroundColor3=Color3.fromRGB(122,147,166); dot.Parent=suite
        end end
        local area=Instance.new('Frame'); area.Name='TouchBounds'; area.Size=UDim2.fromScale(1,1)
        area.BackgroundTransparency=1; area.Parent=A.touchGui; suite.Parent=area
        local function bounds()
            local size=area.AbsoluteSize
            if size and size.X>0 and size.Y>0 then return size.X,size.Y end
            local v=camera and camera.ViewportSize or Vector2.new(720,600)
            return v.X,math.max(46,v.Y-60)
        end
        local function place(x,y)
            local w,h=bounds()
            suite.Position=UDim2.fromOffset(math.clamp(x,4,math.max(4,w-114)),math.clamp(y,4,math.max(4,h-50)))
        end
        function A.clampTouchButton()
            local w,h=bounds(); local pos=suite.Position
            place(pos.X.Scale*w+pos.X.Offset,pos.Y.Scale*h+pos.Y.Offset)
        end
        A.connect(area:GetPropertyChangedSignal('AbsoluteSize'),A.clampTouchButton)
        A.clampTouchButton()
        A.connect(suite.InputBegan,function(input)
            if dragging then return end
            if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
                suppressTap=false
                dragging={input=input,start=input.Position,x=suite.Position.X.Offset,y=suite.Position.Y.Offset}
            end
        end)
        A.connect(A.S.UIS.InputChanged,function(input)
            if not dragging then return end
            if input==dragging.input or (dragging.input.UserInputType==Enum.UserInputType.MouseButton1
                and input.UserInputType==Enum.UserInputType.MouseMovement) then
                local delta=input.Position-dragging.start
                if delta.Magnitude>=6 then suppressTap=true end
                if suppressTap then place(dragging.x+delta.X,dragging.y+delta.Y) end
            end
        end)
        A.connect(A.S.UIS.InputEnded,function(input)
            if dragging and (input==dragging.input or (dragging.input.UserInputType==Enum.UserInputType.MouseButton1
                and input.UserInputType==Enum.UserInputType.MouseButton1)) then dragging=nil end
        end)
        local restore=touchButton('RESTORE',-84,function() if A.render then A.render(false) end end)
        restore.Size=UDim2.fromOffset(130,44); restore.Position=UDim2.new(.5,-65,1,-58)
        restore.Visible=false
    end
    local tabs={}
    for _,name in ipairs({'Farm','Modes','Pets','Cyber','Index','Webhook','Settings'}) do
        tabs[name]=window:AddTab({Title=name,Icon=''})
    end
    local sync=true; local bindings={}; local statuses={}
    local function guard(fn,saveDelay)
        return function(...)
            if sync or not A.alive then return end
            local ok,why=pcall(fn,...)
            if ok and A.alive then A.settingsChanged(saveDelay) end
            if not ok then A.log('UI',why); F:Notify({Title='JoesAAS',Content=tostring(why),Duration=6}) end
        end
    end
    local function button(tab,title,fn) return tabs[tab]:AddButton({Title=title,Callback=guard(fn)}) end
    local function note(tab,title,content)
        local paragraph=tabs[tab]:AddParagraph({Title=title,Content=content})
        local last=content; local set=paragraph.SetDesc
        paragraph.SetDesc=function(self,value)
            if value~=last then last=value; set(self,value) end
        end
        return paragraph
    end
    local function status(tab,key)
        local p=note(tab,key,'Ready')
        statuses[#statuses+1]=function() p:SetDesc(tostring(A.status[key] or 'Ready')) end
    end
    local function toggle(tab,title,key,changed)
        local option=tabs[tab]:AddToggle(key,{Title=title,Default=A.settings[key]})
        option:OnChanged(guard(function(value)
            A.settings[key]=value==true
            if changed then changed(A.settings[key]) end
        end))
        bindings[#bindings+1]=function()
            if option.Value~=A.settings[key] then option:SetValue(A.settings[key]) end
        end
        return option
    end
    local function input(tab,title,key,numeric,minimum,maximum)
        local option=tabs[tab]:AddInput(key,{Title=title,Default=tostring(A.settings[key]),Numeric=numeric==true,Finished=false})
        option:OnChanged(guard(function(value)
            if numeric then
                local n=tonumber(value)
                if not n or n~=n or n<0 or n==math.huge then return end
                if minimum then n=math.clamp(n,minimum,maximum) end
                A.settings[key]=n
            else A.settings[key]=tostring(value):match('^%s*(.-)%s*$') end
        end,0.4))
        bindings[#bindings+1]=function()
            local value=tostring(A.settings[key]); if option.Value~=value then option:SetValue(value) end
        end
    end
    local function choices(values)
        return function() local out={}; for _,v in ipairs(values) do out[#out+1]={key=v,label=v} end; return out end
    end
    local function dropdown(tab,title,id,provider,get,set,multi)
        local option=tabs[tab]:AddDropdown(id,{Title=title,Values={},Multi=multi==true,Default=multi and {} or nil,AllowNull=true})
        if touch and type(F.OpenFrames)=='table' then
            local popup=F.OpenFrames[#F.OpenFrames]
            if popup then
                local limit=Instance.new('UISizeConstraint'); local w,h=dimensions()
                limit.MaxSize=Vector2.new(w,h); limit.Parent=popup; popupLimits[#popupLimits+1]=limit
            end
        end
        local rows,byLabel={},{}
        local function refresh()
            rows=provider(); byLabel={}; local labels={}; local selected=multi and {} or nil
            for i,row in ipairs(rows) do
                if touch and #row.label>30 then row.label=row.label:sub(1,26)..'… '..i end
                labels[#labels+1]=row.label; byLabel[row.label]=row.key
                if get(row.key) then
                    if multi then selected[row.label]=true else selected=row.label end
                end
            end
            local changed=#option.Values~=#labels
            if not changed then
                for i,value in ipairs(labels) do if option.Values[i]~=value then changed=true; break end end
            end
            local valueChanged=option.Value~=selected
            if multi then
                valueChanged=false
                for key in pairs(selected) do if not option.Value[key] then valueChanged=true; break end end
                if not valueChanged then
                    for key,value in pairs(option.Value) do
                        if value and not selected[key] then valueChanged=true; break end
                    end
                end
            end
            -- Fluent recreates dropdown rows on both setters. Never call them for unchanged data.
            if changed then option:SetValues(labels) end
            if valueChanged then option:SetValue(selected) end
        end
        bindings[#bindings+1]=refresh
        option:OnChanged(guard(function(value)
            if multi then
                local selected={}
                for _,row in ipairs(rows) do selected[row.key]=type(value)=='table' and value[row.label]==true end
                set(selected)
            elseif value and byLabel[value] then set(byLabel[value]) end
        end))
        return option
    end
    local function choose(tab,title,key,provider)
        return dropdown(tab,title,key,provider,function(id) return tostring(A.settings[key])==id end,
            function(id) A.settings[key]=id; if key=='world' then A.watchTarget(nil) end; A.refreshUI() end)
    end
    local function multi(tab,title,key,provider)
        dropdown(tab,title,key,provider,function(id) return A.settings[key][id]~=false end,function(selected)
            for id,value in pairs(selected) do A.settings[key][id]=value end
        end,true)
        button(tab,'Include all '..title:lower()..' / future entries',function() A.settings[key]={}; A.refreshUI() end)
    end
    choose('Farm','World','world',function()
        local out={}
        for id,w in pairs(A.catalog.worlds) do
            out[#out+1]={key=tostring(id),label=tostring(id)..' - '..w.Name..(A.unlocked(id) and '' or ' [locked]')}
        end
        table.sort(out,function(a,b) return tonumber(a.key)<tonumber(b.key) end); return out
    end)
    dropdown('Farm','Mobs in selected world','worldMobs',function()
        local out={}
        for key,e in pairs(A.catalog.enemies) do
            if tostring(e.World)==A.settings.world then out[#out+1]={key=key,label=tostring(e.ModelName or key)} end
        end
        table.sort(out,function(a,b) return a.label<b.label end); return out
    end,function(id)
        local selected=A.settings.mobsByWorld[A.settings.world] or {}
        return next(selected)==nil or selected[id]==true
    end,function(selected)
        -- Explicit false values distinguish selecting none from the initial all-mobs setting.
        local saved=A.settings.mobsByWorld[A.settings.world] or {}
        for id,value in pairs(selected) do saved[id]=value end
        A.settings.mobsByWorld[A.settings.world]=saved
    end,true)
    button('Farm','Select all mobs / include future mobs in this world',function()
        A.settings.mobsByWorld[A.settings.world]={}; A.refreshUI()
    end)
    choose('Farm','Target order','target',choices({'Nearest','Highest HP','Lowest HP'}))
    choose('Farm','Movement','moveStyle',choices({'Walk','Teleport'}))
    toggle('Farm','Auto farm selected mobs','farm',function(enabled)
        if not enabled then A.stopFarmMovement(); A.watchTarget(nil) end
    end)
    note('Farm','World handling','Joins through the normal world system before combat. Keeps one target until death or removal, then immediately picks across all selected mobs. Selections are saved separately per world.')
    status('Farm','Farm'); status('Farm','Discovery')
    toggle('Farm','Auto teleport to Trial / Dungeon mobs','trialFollow',function()
        if not A.settings.trialFollow then A.stopTrialMovement(); A.stopDungeonMovement() end
    end)
    note('Farm','Trial / Dungeon movement','Teleports to mobs in your current Trial or Dungeon and keeps small anti-stuck steps running between rooms. Stops on exit, death, run end or toggle off.')
    status('Farm','Trial follow'); status('Farm','Dungeon follow')
    dropdown('Farm','Trials to auto join','trialJoinSelection',function()
        return A.activityRows('TimeTrial')
    end,function(key) return A.settings.trialJoinSelection[key]==true end,
    function(selected) A.settings.trialJoinSelection=selected end,true)
    toggle('Farm','Auto join selected trials when open','trialAutoJoin',function() A.tryTrialJoin() end)
    status('Farm','Trial join')
    note('Farm','Trial priority','Insane > Hard > Medium > Easy among selected trials currently open. An active trial finishes first unless your stuck timeout is reached.')
    status('Modes','Activities')
    status('Modes','Activity error'); status('Modes','Join diagnostics')
    button('Modes','Save join diagnostics now',function() A.flushJoinDiagnostics(true) end)
    note('Modes','Raid / Defense','Raid starts YOUR OWN run only; never joins other raids. Defense starts or joins an available run. Normal entry costs apply; errors appear above.')
    local priorityNote=note('Modes','Activity priority',A.priorityText())
    statuses[#statuses+1]=function() priorityNote:SetDesc(A.priorityText()) end
    local editingPriority='MaxTac'
    dropdown('Modes','Activity to move in priority order','priorityEditor',function()
        local rows={}
        for _,key in ipairs(A.Core.priorityOrder(A.settings.priority)) do rows[#rows+1]={key=key,label=A.Core.priorityLabels[key]} end
        return rows
    end,function(key) return editingPriority==key end,function(key) editingPriority=key end)
    button('Modes','Move selected activity higher',function() A.moveActivityPriority(editingPriority,-1) end)
    button('Modes','Move selected activity lower',function() A.moveActivityPriority(editingPriority,1) end)
    button('Modes','Reset activity priority',A.resetActivityPriority)
    note('Modes','Run locks','MaxTac, Tower, Time Trials and Dungeon finish or fail before priority switching. Enabled stuck recovery can leave an unfinished run only after its no-progress timeout. Mob Autofarm always comes last.')
    toggle('Modes','Auto leave stuck runs','autoLeaveStuck',function() A.coordinateActivities() end)
    input('Modes','Stuck timeout · other modes (seconds)','stuckSeconds',true,1,3600)
    input('Modes','Stuck timeout · Trial + Dungeon (seconds)','trialDungeonStuckSeconds',true,1,3600)
    note('Modes','Stuck detection','Defaults: 10 seconds for MaxTac, Tower, Gate, Raid, Defense and Boss Rush; 20 seconds shared by Time Trials and Dungeon. Kills, fewer remaining enemies, new waves/rooms/floors and run/boss phase changes reset the timer. Damage never resets it. Normal Tower join/choice timers and Gate ARISE delays are allowed first. Walking and countdown updates do not reset it. Normal world mob farming is unaffected. Failed modes wait 30 seconds before this script rejoins.')
    status('Modes','Stuck recovery')
    note('Modes','Transfers','MaxTac, Tower, Trials and Dungeons use direct native entry. Other destinations wait for normal exit. MaxTac, Gate and Tower stay at their join position.')
    note('Modes','Movement','Time Trials and Dungeons follow mobs with continuous anti-stuck steps. Tower opens your own tower. Turn off competing auto-join / movement in your other script to let this coordinator control switching.')
    for _,entry in ipairs({{'MaxTac','maxTacAutoJoin','maxTacSelection'},{'Tower','towerAutoJoin','towerSelection'},{'Dungeon','dungeonAutoJoin','dungeonSelection'},{'Gate','gateAutoJoin','gateSelection'},{'Raid','raidAutoJoin','raidSelection'},
        {'Defense','defenseAutoJoin','defenseSelection'},
        {'BossRush','bossRushAutoJoin','bossRushSelection'}}) do
        local mode,toggleKey,selectionKey=entry[1],entry[2],entry[3]
        dropdown('Modes',mode..' selection',selectionKey,function()
            return A.activityRows(mode)
        end,function(key) return A.settings[selectionKey][key]==true end,
        function(selected)
            A.settings[selectionKey]=(mode=='Raid' or mode=='Defense') and {[selected]=true} or selected
            A.coordinateActivities()
        end,mode~='Raid' and mode~='Defense')
        if mode=='Gate' or mode=='MaxTac' then
            local ranksKey=mode=='Gate' and 'gateRanks' or 'maxTacRanks'
            dropdown('Modes',mode=='Gate' and 'Gate ranks' or 'MaxTac threats',ranksKey,mode=='Gate' and A.gateRankRows or A.maxTacRankRows,
                function(key) return A.settings[ranksKey][key]==true end,
                function(selected) A.settings[ranksKey]=selected; A.coordinateActivities() end,true)
            note('Modes',mode..' rank order',mode=='Gate' and 'S > A > B > C > D > E. Only declared ranks are listed.'
                or 'Low → Medium → High → Extreme → Psycho. MaxTac stays at its join position. Only enabled stuck recovery can leave a stalled unfinished run.')
        end
        toggle('Modes',mode=='Raid' and 'Auto start my own Raid' or (mode=='BossRush' and 'Auto start my own Boss Rush' or ('Auto join '..mode)),toggleKey,function(value)
            if mode=='Raid' or mode=='Defense' then A.setCombatEnabled(mode,value) else A.coordinateActivities() end
        end)
    end
    note('Modes','Boss Rush entry','Choose the exact variant, such as Cursed Rush or King of Curses. Creates your own run after checking the world unlock and key cost. Old base-only choices migrate to the declared V1 variant.')
    input('Pets','Name for unnamed Astral pets','petName')
    toggle('Pets','Auto rename Astral pets ONLY','rename')
    note('Pets','Astral naming','Only verified Astral rarity is eligible. Already named and percentage pets are skipped. Uses the normal Magicule cost. Check the status below for blockers.')
    status('Pets','Rename')
    status('Pets','Rename report')
    button('Pets','Retry unconfirmed renames',A.retryRenaming)
    local cyberSummary=note('Cyber','Night City',A.cyberSummary())
    statuses[#statuses+1]=function() cyberSummary:SetDesc(A.cyberSummary()) end
    button('Cyber','Open Cyberdeck',function() A.openCyberSystem('Cyberdeck') end)
    button('Cyber','Open Ripperdoc',function() A.openCyberSystem('Ripperdoc') end)
    dropdown('Cyber','Ripperdoc slots to upgrade','ripperdocSlots',A.ripperdocRows,
        function(key) return A.settings.ripperdocSlots[key]==true end,
        function(selected) A.settings.ripperdocSlots=selected end,true)
    toggle('Cyber','Auto upgrade selected Ripperdoc slots','ripperdocAuto')
    note('Cyber','Ripperdoc costs','Spends Eddies only when enabled, in the normal Head → Torso → Shoulder → Waist → Back order. Each previous slot must be maxed. Waits for the game to confirm every upgrade.')
    status('Cyber','Ripperdoc'); status('Cyber','Cyber')
    button('Cyber','Open Fixer Gigs',function() A.openCyberSystem('FixerGig') end)
    local fixerSummary=note('Cyber','Fixer Gigs',A.fixerSummary())
    local serverBoosts=note('Cyber','Server boosts',A.serverBoostSummary())
    statuses[#statuses+1]=function() fixerSummary:SetDesc(A.fixerSummary()); serverBoosts:SetDesc(A.serverBoostSummary()) end
    toggle('Cyber','Auto claim completed Fixer Gigs','fixerAutoClaim')
    status('Cyber','Fixer gigs')
    note('Cyber','Gigs and Overclock','Pick your pet and start gigs in the native Fixer menu. Auto claim collects completed gigs only. Big Jobs can reward Overclock Chips. The native Cyberdeck handles Overclock upgrades; equipped quickhack OC levels and chip balance appear above.')
    note('Index','Missing collections','Accessories, pet accessories, titans, shadows, swords, primordials and mounts. Checks the game Index, including its collection history. Pets are excluded.')
    button('Index','Send missing index to Discord',A.sendIndexReport)
    note('Index','Report details','Uses your fixed report webhook. Shows world, source and base chance on numbered category pages. Purchases and claims are marked guaranteed; unpublished details are marked unknown. Works independently of the other webhook settings.')
    status('Index','Index')
    input('Webhook','Webhook URL','webhookURL'); input('Webhook','Discord user ID','pingId')
    toggle('Webhook','Enable webhook','webhook'); toggle('Webhook','Send disconnect notification','sendDisconnect')
    toggle('Webhook','Ping selected user','ping')
    multi('Webhook','Events to send','webhookEvents',choices({'Disconnect','Mode','Progress','Error','Inventory'}))
    multi('Webhook','Events to ping','pingEvents',choices({'Disconnect','Mode','Progress','Error','Inventory'}))
    toggle('Webhook','Save webhook URL locally with settings','saveSecrets')
    button('Webhook','Send test notification',function() A.notify('Test','Webhook test from JoesAAS',true) end)
    note('Webhook','Disconnect limits','Disconnect notices send while the executor can still run. A force-closed Roblox app cannot send a webhook. Settings restore automatically; enable local URL storage above to restore your webhook URL too.')
    status('Webhook','Webhook'); status('Webhook','Disconnect')
    note('Settings','Automatic settings','Choices and toggles save automatically. Typing saves after a short pause. The next time you execute JoesAAS, it restores your settings and resumes enabled features. No Save, Load or Autoload buttons are needed.')
    toggle('Settings','Black screen / disable 3D rendering','blackScreen',function(value) if A.render then A.render(value) end end)
    note('Settings','Controls',touch and 'Tap JoesAAS to hide/show; drag it to reposition. Use each feature’s own toggle. RESTORE enables rendering. Landscape gives the menus more room.'
        or 'Right Shift: minimize/show Fluent. F8: restore rendering.')
    note('Settings','Executor capabilities',
        'Automatic settings: '..((type(writefile)=='function' and type(readfile)=='function' and type(makefolder)=='function') and 'available' or 'file APIs missing')
        ..' | Webhook HTTP: '..(A.httpRequest and 'available' or 'request API missing')
        ..'. Rendering availability is checked when you use it.')
    status('Settings','Settings')
    status('Settings','Gameplay')
    button('Settings','Refresh catalogs',function() A.discover(); A.refreshUI() end)
    button('Settings','Write diagnostics',function()
        local ok,err=pcall(function()
        assert(type(writefile)=='function','File API unavailable')
        pcall(makefolder,A.folder)
        local jobs,enabled={},{}
        for name,job in pairs(A.tasks) do jobs[name]={busy=job.busy,failures=job.failures,nextIn=math.max(0,job.next-os.clock())} end
        for key,value in pairs(A.settings) do if type(value)=='boolean' then enabled[key]=value end end
        writefile(A.folder..'/diagnostics.json',A.S.HTTP:JSONEncode({version='5.7',rename=A.renameDiagnostics(),status=A.status,logs=A.logs,jobs=jobs,enabled=enabled,
            running=A.running,
            worlds=#C.keys(A.catalog.worlds),enemies=#C.keys(A.catalog.enemies)}))
        assert(A.safeLoad(A.folder..'/diagnostics.json'),'Could not read back diagnostics file')
        end)
        A.status.Settings=ok and ('Saved '..A.folder..'/diagnostics.json') or ('Diagnostics save failed: '..tostring(err))
        A.log('Diagnostics',A.status.Settings)
        F:Notify({Title='Diagnostics',Content=A.status.Settings,Duration=8})
    end)
    button('Settings','Unload',A.stop); status('Settings','Rendering')
    A.overlay=Instance.new('ScreenGui'); A.overlay.Name='JoesAASBlackScreen'
    A.overlay.ResetOnSpawn=false; A.overlay.IgnoreGuiInset=true; A.overlay.DisplayOrder=100000; A.overlay.Enabled=false
    A.overlay.Parent=A.player:WaitForChild('PlayerGui')
    local black=Instance.new('TextButton'); black.Size=UDim2.fromScale(1,1); black.BackgroundColor3=Color3.new(0,0,0)
    black.Text=touch and 'Tap to restore rendering' or 'Rendering disabled - click here or press F8 to restore'
    black.TextColor3=Color3.new(1,1,1); black.TextWrapped=true; black.TextSize=18
    black.AutoButtonColor=false; black.Parent=A.overlay
    function A.render(disabled)
        local ok=pcall(function() A.S.Run:Set3dRenderingEnabled(not disabled) end)
        A.overlay.Enabled=disabled; A.settings.blackScreen=disabled
        if A.touchControls then A.touchControls.RESTORE.Visible=disabled end
        A.status.Rendering=disabled and (ok and '3D rendering disabled' or 'Overlay only: rendering API unavailable') or 'Rendering enabled'
        if A.refreshUI then A.refreshUI() end
        A.settingsChanged()
    end
    A.connect(black.Activated,function() A.render(false) end)
    A.connect(A.S.UIS.InputBegan,function(key) if key.KeyCode==Enum.KeyCode.F8 then A.render(false) end end)
    function A.refreshUI()
        if sync or not A.alive then return end
        sync=true
        local ok,why=pcall(function() for _,update in ipairs(bindings) do update() end end)
        sync=false
        if not ok then A.log('UI',why) end
    end
    sync=false; A.render(A.settings.blackScreen); A.refreshUI(); window:SelectTab(1)
    A.job('UI status',1,function()
        if F.Unloaded or not A.gui.Parent then A.stop(); return end
        for _,update in ipairs(statuses) do update() end
    end,true)
end


end)()(A);

A.schedule()
A.finishStartup()
end)
if not bootOK then
    if A.stop then pcall(A.stop) end
    warn("JoesAAS startup failed: " .. tostring(bootError))
end
