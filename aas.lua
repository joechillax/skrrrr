-- JoesAAS 4.4 | standalone source | September 2026
-- Built against the supplied client export. See JoesAAS-README.md for limits and validation.
-- Fluent UI from dawid-scripts/Fluent. Autoload is opt-in; each feature uses its own toggle.
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
A.GuildCore = (function()
local G={pollSeconds=30,maxObservedInterval=45,autosaveSeconds=90,heartbeatSeconds=20,historyLimit=128,cphSettlingSeconds=120}
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function iso(t) return os.date('!%Y-%m-%dT%H:%M:%SZ',t) end
function G.append(owner,key,event)
    local list=owner[key] or {}; owner[key]=list
    if #list>=G.historyLimit then table.remove(list,1); owner[key..'Dropped']=(owner[key..'Dropped'] or 0)+1 end
    list[#list+1]=event
end
function G.migrate(s)
    if s.schemaVersion==1 then
        s.legacyWallElapsedSeconds=s.totalElapsedSeconds
        s.activeTrackingSeconds=s.observedSeconds
        s.runtimeMigration='Legacy file had no runtime clock; retained observed seconds as a conservative active-runtime baseline.'
        s.schemaVersion=2
    end
    if s.schemaVersion==2 then
        for _,m in pairs(s.members) do
            m.cphContribution=0; m.cphOnlineSeconds=0; m.cphReadyAt=false; m.cphMeasurementStartedAt=false
        end
        s.cphMigration='Original totals retained. Matched CpH measurements start after upgrading; old gains cannot be assigned to live intervals.'
        s.cphMethod='cphContribution / (cphOnlineSeconds / 3600); excluded contribution remains included in Gained.'
        s.efficiencyCaveat='CpH is a sampled live estimate after 120-second settling periods; delayed server updates may still affect attribution.'
        s.schemaVersion=3
    end
    s.recoveries=s.recoveries or {}
    for _,key in ipairs({'gaps','recoveries'}) do
        while #s[key]>G.historyLimit do table.remove(s[key],1); s[key..'Dropped']=(s[key..'Dropped'] or 0)+1 end
    end
    for _,m in pairs(s.members) do
        for _,key in ipairs({'membershipEvents','counterDecreases'}) do
            while #m[key]>G.historyLimit do table.remove(m[key],1); m[key..'Dropped']=(m[key..'Dropped'] or 0)+1 end
        end
    end
    return s
end
function G.id(v)
    local n=tonumber(v)
    if not n or not finite(n) or n<=0 or n%1~=0 then return nil end
    return string.format('%.0f',n)
end
function G.roster(payload,guildId,selfId)
    if type(payload)~='table' or payload.Live==true or G.id(payload.Id)~=G.id(guildId)
        or type(payload.Members)~='table' then return nil,'Waiting for a complete roster for your guild' end
    local out={}; local count=0
    for _,row in pairs(payload.Members) do
        if type(row)~='table' then return nil,'Invalid roster member' end
        local id=G.id(row.Id); local week=tonumber(row.Week)
        if not id or out[id] or not finite(week) or week<0 then return nil,'Incomplete or duplicate roster data' end
        local username=type(row.Name)=='string' and row.Name or ('User '..id)
        out[id]={userId=tonumber(id),username=username,
            displayName=type(row.DisplayName)=='string' and row.DisplayName or username,
            displayNameSource=type(row.DisplayName)=='string' and 'roster' or 'usernameFallback',
            contribution=week,online=row.Online==true,
            presenceKnown=type(row.Online)=='boolean',serverLastSeen=tonumber(row.Seen) or 0}
        count=count+1
    end
    if count==0 or not out[G.id(selfId)] then return nil,'Roster does not include this account; session preserved' end
    return out
end
local function member(row,t)
    return {userId=row.userId,username=row.username,displayName=row.displayName,displayNameSource=row.displayNameSource,
        firstDetectedAt=t,firstDetectedAtISO=iso(t),lastDetectedAt=t,lastContributionAt=t,
        startingContribution=row.contribution,finalContribution=row.contribution,contributionGained=0,
        cphContribution=0,cphOnlineSeconds=0,cphReadyAt=t+G.cphSettlingSeconds,cphMeasurementStartedAt=t,
        onlineSeconds=0,onlineMinutes=0,onlineHours=0,observedSeconds=0,
        onlineStatus='unknown',lastKnownOnline=false,lastSeenOnlineAt=false,serverLastSeen=row.serverLastSeen,
        inGuild=true,departedAt=false,membershipEvents={{at=t,event='firstDetected'}},
        counterDecreases={},contributionComparable=true,contributionPerHour=false}
end
function G.new(rows,guildId,ownerId,gameId,t,sessionId,generation)
    local s={schemaVersion=3,sessionId=sessionId,generation=generation or 1,revision=0,
        activeTrackingSeconds=0,lastSessionStartedAt=t,lastHeartbeatAt=false,recoveries={},
        ownerUserId=ownerId,gameId=gameId,guildId=tonumber(guildId),active=true,
        startedAt=t,startedAtISO=iso(t),endedAt=false,endedAtISO=false,lastSavedAt=false,
        lastObservedAt=false,totalElapsedSeconds=0,observedSeconds=0,unobservedSeconds=0,
        trackedMemberCount=0,members={},gaps={},finalSnapshotStatus='notStopped',
        contributionSource='Guild roster Members[].Week',
        onlineTimeMethod='Sampled presence: credit only intervals <=45 seconds with online at both endpoints; never bridge a reload or observation gap.',
        efficiencyCaveat='Gained includes the full period. CpH uses only matched live online intervals after a 120-second settling period. Server batching can still affect attribution.',
        cphMethod='cphContribution / (cphOnlineSeconds / 3600); gap, settling, unknown/offline presence and final-snapshot deltas are excluded only from CpH, never from Gained.'}
    for id,row in pairs(rows) do s.members[id]=member(row,t) end
    return s
end
function G.metrics(s,t)
    local ending=s.active and t or s.endedAt
    s.wallElapsedSeconds=math.max(0,(tonumber(ending) or t)-s.startedAt)
    s.totalElapsedSeconds=s.activeTrackingSeconds or s.observedSeconds
    s.activeTrackingHours=s.totalElapsedSeconds/3600
    s.totalElapsedHours=s.totalElapsedSeconds/3600
    s.totalElapsedMinutes=s.totalElapsedSeconds/60
    s.observedHours=s.observedSeconds/3600
    s.unobservedSeconds=math.max(0,s.wallElapsedSeconds-s.observedSeconds)
    s.unobservedActiveSeconds=math.max(0,s.totalElapsedSeconds-s.observedSeconds)
    s.unobservedHours=s.unobservedSeconds/3600
    local count=0
    for _,m in pairs(s.members) do
        count=count+1
        m.onlineMinutes=m.onlineSeconds/60; m.onlineHours=m.onlineSeconds/3600
        m.contributionGained=m.finalContribution-m.startingContribution
        m.cphOnlineHours=m.cphOnlineSeconds/3600
        m.contributionPerHour=m.cphOnlineSeconds>0 and m.contributionComparable
            and m.cphContribution/m.cphOnlineHours or false
        m.contributionExcludedFromCph=m.contributionGained-m.cphContribution
        m.cphCoverageOfOnlineTime=m.onlineSeconds>0 and math.min(1,m.cphOnlineSeconds/m.onlineSeconds) or 0
        m.cphSampleSufficient=m.cphOnlineSeconds>=300
        local memberEnd=m.inGuild and (tonumber(ending) or t) or (tonumber(m.departedAt) or m.lastDetectedAt)
        m.observationSpanSeconds=math.max(0,memberEnd-m.firstDetectedAt)
        m.unobservedSeconds=math.max(0,m.observationSpanSeconds-m.observedSeconds)
        m.efficiencyReliable=m.cphSampleSufficient and m.contributionComparable and m.unobservedSeconds==0
    end
    s.trackedMemberCount=count
end
function G.sample(s,rows,t,previous)
    local interval=previous and t-previous.at or 0
    local continuous=previous~=nil and interval>=0 and interval<=G.maxObservedInterval
    if continuous then s.observedSeconds=s.observedSeconds+interval
    elseif s.lastObservedAt and t>s.lastObservedAt then
        G.append(s,'gaps',{from=s.lastObservedAt,to=t,seconds=t-s.lastObservedAt,reason='No continuous observation'})
    end
    local changedMembers=false
    for id,row in pairs(rows) do
        local m=s.members[id]
        if not m then m=member(row,t); s.members[id]=m; changedMembers=true end
        if not m.inGuild then
            G.append(m,'membershipEvents',{at=t,event='returned'}); changedMembers=true
        end
        if m.username~=row.username or m.displayName~=row.displayName then changedMembers=true end
        if m.finalContribution~=row.contribution or m.onlineStatus~=(row.presenceKnown and (row.online and 'online' or 'offline') or 'unknown') then changedMembers=true end
        m.username=row.username; m.displayName=row.displayName; m.displayNameSource=row.displayNameSource
        local prior=continuous and previous.rows[id]
        local matched=prior and interval>0 and prior.presenceKnown and row.presenceKnown and prior.online and row.online
        local delta=row.contribution-m.finalContribution
        if not m.cphMeasurementStartedAt then m.cphMeasurementStartedAt=t end
        if not matched or delta<0 then
            m.cphReadyAt=t+G.cphSettlingSeconds
        elseif m.contributionComparable and prior.contribution==m.finalContribution
            and previous.at>=(tonumber(m.cphReadyAt) or (t+G.cphSettlingSeconds)) then
            m.cphContribution=m.cphContribution+delta
            m.cphOnlineSeconds=m.cphOnlineSeconds+interval
        end
        if prior then
            if prior.presenceKnown and row.presenceKnown then m.observedSeconds=m.observedSeconds+interval end
            if prior.presenceKnown and row.presenceKnown and prior.online and row.online then m.onlineSeconds=m.onlineSeconds+interval end
        end
        if row.contribution<m.finalContribution then
            G.append(m,'counterDecreases',{at=t,before=m.finalContribution,after=row.contribution,
                possibleWeeklyReset=true})
            m.contributionComparable=false
        end
        m.finalContribution=row.contribution; m.lastContributionAt=t
        m.lastDetectedAt=t; m.inGuild=true; m.departedAt=false
        m.onlineStatus=row.presenceKnown and (row.online and 'online' or 'offline') or 'unknown'
        m.lastKnownOnline=row.online; m.serverLastSeen=row.serverLastSeen
        if row.presenceKnown and row.online then m.lastSeenOnlineAt=t end
    end
    for id,m in pairs(s.members) do
        if not rows[id] and m.inGuild then
            m.inGuild=false; m.departedAt=t; m.onlineStatus='unknown'
            G.append(m,'membershipEvents',{at=t,event='noLongerInRoster'}); changedMembers=true
        end
    end
    s.lastObservedAt=t; G.metrics(s,t)
    return {at=t,rows=rows},changedMembers
end
function G.stop(s,t)
    s.active=false; s.endedAt=t; s.endedAtISO=iso(t)
    s.finalSnapshotStatus='pending'; G.metrics(s,t)
end
function G.finalSnapshot(s,rows,receivedAt)
    -- Stopping freezes time/membership. Only existing members get a fresh final counter.
    for id,m in pairs(s.members) do
        local row=rows[id]
        if row then
            if row.contribution<m.finalContribution then
                G.append(m,'counterDecreases',{at=receivedAt,before=m.finalContribution,after=row.contribution,possibleWeeklyReset=true})
                m.contributionComparable=false
            end
            m.finalContribution=row.contribution; m.lastContributionAt=receivedAt
        end
    end
    s.finalSnapshotStatus='received'; s.finalSnapshotReceivedAt=receivedAt
    G.metrics(s,s.endedAt)
end
function G.valid(s,ownerId,gameId)
    if type(s)~='table' or (s.schemaVersion~=1 and s.schemaVersion~=2 and s.schemaVersion~=3) or s.ownerUserId~=ownerId or s.gameId~=gameId
        or not G.id(s.guildId) or type(s.sessionId)~='string' or type(s.active)~='boolean'
        or not finite(s.startedAt) or type(s.startedAtISO)~='string'
        or not finite(s.generation) or s.generation<1 or not finite(s.revision) or s.revision<0
        or type(s.members)~='table' or type(s.gaps)~='table' or not finite(s.observedSeconds)
        or s.observedSeconds<0 or (s.lastObservedAt~=false and not finite(s.lastObservedAt))
        or (s.lastSavedAt~=false and not finite(s.lastSavedAt))
        or (not s.active and not finite(s.endedAt)) then return false end
    if s.schemaVersion>=2 and (not finite(s.activeTrackingSeconds) or s.activeTrackingSeconds<0
        or type(s.recoveries)~='table') then return false end
    for id,m in pairs(s.members) do
        if type(m)~='table' or G.id(m.userId)~=id or type(m.username)~='string' or type(m.displayName)~='string'
            or type(m.onlineStatus)~='string' or type(m.inGuild)~='boolean' or type(m.contributionComparable)~='boolean'
            or not finite(m.startingContribution) or not finite(m.finalContribution)
            or not finite(m.onlineSeconds) or m.onlineSeconds<0 or not finite(m.observedSeconds) or m.observedSeconds<0
            or not finite(m.firstDetectedAt) or not finite(m.lastDetectedAt)
            or type(m.membershipEvents)~='table' or type(m.counterDecreases)~='table' then return false end
        if s.schemaVersion==3 and (not finite(m.cphContribution) or m.cphContribution<0
            or not finite(m.cphOnlineSeconds) or m.cphOnlineSeconds<0
            or (m.cphReadyAt~=false and not finite(m.cphReadyAt))
            or (m.cphMeasurementStartedAt~=false and not finite(m.cphMeasurementStartedAt))) then return false end
    end
    return true
end
return G

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
    A.defaults={version=3,world='0',mobsByWorld={},target='Nearest',farm=false,trialFollow=false,trialAutoJoin=false,trialJoinSelection={},
        towerAutoJoin=false,towerSelection={},raidAutoJoin=false,raidSelection={},defenseAutoJoin=false,defenseSelection={},
        gateAutoJoin=false,gateSelection={},gateRanks={S=true,A=true,B=true,C=true,D=true,E=true},dungeonAutoJoin=false,dungeonSelection={},bossRushAutoJoin=false,bossRushSelection={},
        rename=false,petName='',webhook=false,webhookURL='',pingId='',ping=false,sendDisconnect=true,
        webhookEvents={Disconnect=true,Mode=true,Progress=true,Error=true,Inventory=true},
        pingEvents={Disconnect=true,Error=true,Mode=false,Progress=false,Inventory=false},
        blackScreen=false,moveStyle='Walk',distance=5,saveSecrets=false}
    A.legacyFolder='AnimeSuite_'..tostring(game.GameId)..'_'..tostring(A.player.UserId)
    A.folder='JoesAAS/'..tostring(game.GameId)..'_'..tostring(A.player.UserId)
    A.file=A.folder..'/settings.json'
    function A.log(kind,text)
        text=tostring(text)
        if A.settings and A.settings.webhookURL~='' then
            text=text:gsub('https://[^%s]+/api/webhooks/[^%s]+','[webhook redacted]')
        end
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
        if not Core.contains({'Nearest','Highest HP','Lowest HP'},s.target) then s.target='Nearest' end
        if not Core.contains({'Walk','Teleport'},s.moveStyle) then s.moveStyle='Walk' end
        for _,k in ipairs({'webhookEvents','pingEvents','trialJoinSelection','towerSelection','raidSelection','defenseSelection','dungeonSelection','gateSelection','gateRanks','bossRushSelection'}) do
            for id,v in pairs(s[k]) do if type(id)~='string' or type(v)~='boolean' then s[k][id]=nil end end
        end
        for world,selection in pairs(s.mobsByWorld) do
            if type(world)~='string' or type(selection)~='table' then s.mobsByWorld[world]=nil else
                for id,value in pairs(selection) do if type(id)~='string' or type(value)~='boolean' then selection[id]=nil end end
            end
        end
        s.version=3; return s
    end
    -- Copy once before reading settings/session state; never overwrite a new-folder file.
    if type(makefolder)=='function' and type(readfile)=='function' and type(writefile)=='function' then
        pcall(makefolder,'JoesAAS'); pcall(makefolder,A.folder)
        if not A.safeLoad(A.folder..'/migration.json') then
            local function copyLegacy(name,transform)
                local destination=A.folder..'/'..name
                if pcall(readfile,destination) then return end
                local ok,bytes=pcall(readfile,A.legacyFolder..'/'..name)
                if not ok then return end
                if transform then bytes=transform(bytes) end
                writefile(destination,bytes)
                assert(readfile(destination)==bytes,'Migration read-back failed: '..name)
            end
            local ok,err=pcall(function()
                for _,name in ipairs({'autoload.json','settings.json','settings.json.bak',
                    'guild-weekly-tracking.json','guild-weekly-tracking.json.bak','guild-weekly-tracking.json.tmp',
                    'guild-heartbeat.json','guild-heartbeat.json.bak'}) do copyLegacy(name) end
                copyLegacy('outbox.json',function(bytes)
                    local queue=A.S.HTTP:JSONDecode(bytes)
                    for _,entry in ipairs(queue) do
                        local file=entry.attachment
                        if type(file)=='table' and type(file.path)=='string' then
                            local name=file.path:sub(#A.legacyFolder+2)
                            if file.path:sub(1,#A.legacyFolder+1)==A.legacyFolder..'/'
                                and name:match('^guild%-export%-[%w%-]+%.json$') then
                                copyLegacy(name); file.path=A.folder..'/'..name
                            end
                        end
                    end
                    return A.S.HTTP:JSONEncode(queue)
                end)
                writefile(A.folder..'/migration.json',A.S.HTTP:JSONEncode({complete=true}))
            end)
            assert(ok,'Could not preserve previous saves: '..tostring(err)..'. Old files are untouched; rerun to retry.')
        end
    end
    A.autoloadFile=A.folder..'/autoload.json'
    A.autoloadEnabled=(A.safeLoad(A.autoloadFile) or {}).enabled==true
    local saved=A.autoloadEnabled and (A.safeLoad(A.file) or A.safeLoad(A.file..'.bak')) or nil
    A.autoloadApplied=saved~=nil
    A.settings=A.validate(saved)
    function A.setAutoload(enabled)
        if type(writefile)~='function' or type(readfile)~='function' or type(makefolder)~='function' then
            A.status.Settings='File APIs unavailable; cannot set autoload.'
            A.log('Settings',A.status.Settings); return false
        end
        local ok,err=pcall(function()
            pcall(makefolder,A.folder)
            writefile(A.autoloadFile,A.S.HTTP:JSONEncode({enabled=enabled==true}))
            assert((A.safeLoad(A.autoloadFile) or {}).enabled==(enabled==true),'Autoload read-back failed')
        end)
        if ok then A.autoloadEnabled=enabled==true end
        A.status.Settings=ok and (enabled and 'Autoload enabled for saved settings.' or 'Autoload disabled.') or tostring(err)
        A.log('Settings',A.status.Settings)
        return ok
    end
    function A.finishStartup()
        A.setRunning(true)
    end
    function A.save()
        if type(writefile)~='function' or type(readfile)~='function' or type(makefolder)~='function' then
            A.status.Settings='File APIs unavailable; settings are session-only.'
            A.log('Settings',A.status.Settings); return false
        end
        local snapshot=Core.copy(A.settings)
        if not snapshot.saveSecrets then snapshot.webhookURL='' end
        local ok,err=pcall(function()
            pcall(makefolder,A.folder)
            local encoded=A.S.HTTP:JSONEncode(snapshot)
            -- Validate the complete new value before touching either saved copy.
            A.S.HTTP:JSONDecode(encoded)
            local prior=A.safeLoad(A.file)
            if prior then
                if not snapshot.saveSecrets then prior.webhookURL='' end
                writefile(A.file..'.bak',A.S.HTTP:JSONEncode(prior))
            end
            writefile(A.file,encoded)
            assert(A.safeLoad(A.file),'read-back failed')
        end)
        A.status.Settings=ok and 'Saved settings.' or ('Save failed: '..tostring(err))
        A.log('Settings',A.status.Settings)
        return ok
    end
    function A.load()
        local saved=A.safeLoad(A.file) or A.safeLoad(A.file..'.bak')
        if not saved then A.status.Settings='No valid settings file.'; A.log('Settings',A.status.Settings); return end
        A.setRunning(false); A.settings=A.validate(saved)
        if A.render then A.render(false) end
        if A.refreshUI then A.refreshUI() end
        A.setRunning(true)
        A.status.Settings='Loaded settings; enabled features are active.'; A.log('Settings',A.status.Settings)
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
        if A.guildCheckpoint then A.guildCheckpoint('unload') end
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
    A.outbox=A.safeLoad(A.folder..'/outbox.json') or {}
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
    function A.http(options)
        if not A.httpRequest then return false,'HTTP request API unavailable' end
        if transport.busy then return false,'HTTP already in flight' end
        options.Timeout=15
        A.httpBusy=true; transport.busy=true; local response
        task.spawn(function() response=table.pack(pcall(A.httpRequest,options)); A.httpBusy=false; transport.busy=false end)
        local deadline=os.clock()+15
        while A.alive and not response and os.clock()<deadline do task.wait(0.05) end
        if not response then return false,'HTTP timed out; waiting for transport to recover' end
        return table.unpack(response,1,response.n)
    end
    function A.notify(kind,message,force,attachment)
        local s=A.settings
        if not s.webhook then A.status.Webhook='Webhook disabled: enable it in this tab'; return end
        if not force and s.webhookEvents[kind]==false then return end
        if kind=='Disconnect' and not s.sendDisconnect then return end
        s.webhookURL=s.webhookURL:match('^%s*(.-)%s*$')
        if not s.webhookURL:match('^https://discord%.com/api/webhooks/%d+/[%w_%-]+')
            and not s.webhookURL:match('^https://discordapp%.com/api/webhooks/%d+/[%w_%-]+') then
            A.status.Webhook='Enter a Discord webhook URL'; return
        end
        if attachment then
            for _,entry in ipairs(A.outbox) do
                if entry.attachment and entry.attachment.key==attachment.key then
                    if persist() then return entry end
                    return
                end
            end
        end
        if #A.outbox>=50 then
            local discard
            for i,entry in ipairs(A.outbox) do if not entry.attachment then discard=i; break end end
            if not discard then A.status.Webhook='Upload queue full; local exports retained'; return end
            table.remove(A.outbox,discard)
        end
        local ping=s.ping and kind~='Test' and s.pingEvents[kind]~=false and s.pingId:match('^%d+$') and s.pingId or nil
        A.outbox[#A.outbox+1]={kind=kind,message=tostring(message):sub(1,1500),time=os.time(),attempt=0,
            target=fingerprint(s.webhookURL),ping=ping,attachment=attachment}
        local saved=persist(); A.webhookNext=kind=='Disconnect' and 0 or A.webhookNext
        A.status.Webhook='Queued '..kind..' ('..#A.outbox..' waiting)'
        if attachment and not saved then return end
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
        if entry.attachment then
            local file=entry.attachment
            local valid=type(file.path)=='string' and file.path:sub(1,#A.folder+14)==A.folder..'/guild-export-'
                and not file.path:find('..',1,true) and type(file.name)=='string' and file.name:match('^[%w_%-%.]+%.json$')
            local readOK,bytes=false,nil
            if valid and type(readfile)=='function' then readOK,bytes=pcall(readfile,file.path) end
            if not readOK or type(bytes)~='string' then
                A.status['Guild upload']='Upload failed: saved attachment unavailable; main JSON retained'
                if A.guildExportFailed then A.guildExportFailed(file.key) end
                A.log('Webhook',A.status['Guild upload']); table.remove(A.outbox,1); persist(); return
            end
            local boundary='AnimeSuite'..tostring(os.time())..tostring(math.random(100000,999999))
            while bytes:find(boundary,1,true) do boundary=boundary..'x' end
            contentType='multipart/form-data; boundary='..boundary
            data='--'..boundary..'\r\nContent-Disposition: form-data; name="payload_json"\r\nContent-Type: application/json\r\n\r\n'
                ..data..'\r\n--'..boundary..'\r\nContent-Disposition: form-data; name="files[0]"; filename="'..file.name
                ..'"\r\nContent-Type: application/json\r\n\r\n'..bytes..'\r\n--'..boundary..'--\r\n'
        end
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
        if entry.attachment then A.status['Guild upload']=A.status.Webhook..' (local JSON retained)' end
        if entry.attachment and (action=='stop' or (action~='done' and entry.attempt>=8 and status~=429)) then
            if A.guildExportFailed then A.guildExportFailed(entry.attachment.key) end
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
            if A.guildCheckpoint then A.guildCheckpoint('disconnect') end
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
        if not sent and ((A.settings.webhook and A.settings.sendDisconnect) or (A.guildSession and A.guildSession.active)) then
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
        local report={version='3.9',status=A.status.Rename,inventoryType=type(d.Pets),namedType=type(d.NamedPets),total=0,reasons={},rarities={},samples={}}
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
    local pending,retries={},{}
    A.renamePending=nil
    local function isConfirmed(id)
        local d=A.data()
        return d and type(d.NamedPets)=='table' and type(d.NamedPets[id])=='table'
    end
    local function finish(id,success,reason)
        if success then
            A.sessionNamed[id]=true; retries[id]=nil
            A.status.Rename='Named Astral: '..id
        else
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
        if A.S.UIS:GetFocusedTextBox() then A.status.Rename='Finish editing before naming pets'; return end
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
        for _,petId in ipairs(C.keys(d.Pets)) do
            total=total+1
            local canRename,skip=C.renameEligible(petId,d.Pets[petId],d.NamedPets or {},name,stats)
            if A.sessionNamed[petId] then canRename=false; skip='renamed this session' end
            if (retries[petId] or 0)>=3 then canRename=false; skip='3 unconfirmed attempts; use Retry' end
            if canRename then
                local cost=cfg:GetCost('Pet','Astral'); local balance=A.balance(cfg.ItemId)
                if type(cost)~='number' or cost<0 then A.status.Rename='Naming cost unavailable'; return end
                if balance<cost then
                    A.status.Rename=string.format('Need %s %s per Astral; have %s',tostring(cost),cfg.ItemId,tostring(balance)); return
                end
                if A.ready('rename:'..petId,25) then
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
        retries={}
        A.status.Rename='Retry enabled; checking unnamed Astral pets'
    end
    A.job('Renaming',1,function()
        if not A.settings.rename and not A.renamePending then return end
        local ok,err=pcall(renameStep)
        if not ok then A.status.Rename='Rename error: '..tostring(err); A.log('Rename',A.status.Rename) end
        if not A.renamePending and not tostring(A.status.Rename):find('^Named Astral:') then saveDiagnostic() end
    end)
end

end)()(A);

-- ===== farming =====
(function()
return function(A)
    local C=A.Core
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
            else hum:MoveTo(destination) end
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
            if not A.running or not A.settings[toggle] then stopMovement(); return end
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
                writefile(A.folder..'/'..kind:lower()..'-diagnostics.json',A.S.HTTP:JSONEncode({version='4.4',reason=message,
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

-- ===== activities =====
(function()
return function(A)
    local definitions={
        Tower={rank=400,config='TowerConfig',method='GetAllTowers',toggle='towerAutoJoin',selection='towerSelection'},
        TimeTrial={rank=300,config='TimeTrialConfig',method='GetAllTrials',toggle='trialAutoJoin',selection='trialJoinSelection'},
        Gate={rank=225,config='RaidConfig',method='GetAllRaids',toggle='gateAutoJoin',selection='gateSelection'},
        Raid={rank=200,config='RaidConfig',method='GetAllRaids',toggle='raidAutoJoin',selection='raidSelection'},
        Defense={rank=200,config='DefenseConfig',method='GetAllDefenses',toggle='defenseAutoJoin',selection='defenseSelection'},
        Dungeon={rank=250,config='DungeonConfig',method='GetAllDungeons',toggle='dungeonAutoJoin',selection='dungeonSelection'},
        BossRush={rank=100,config='BossRushConfig',method='GetAllRushes',toggle='bossRushAutoJoin',selection='bossRushSelection'}
    }
    local order={'Tower','TimeTrial','Dungeon','Gate','Raid','Defense','BossRush'}
    local protected={Tower=true,TimeTrial=true,Dungeon=true}
    local available,backoff={},{}
    local pending,leaving,locked,returning,waitingReason
    local raidInstance,raidKey
    for _,mode in ipairs(order) do available[mode]={} end
    function A.activityChoices(mode)
        local def=definitions[mode]; if not def then return {} end
        local cfg=A.config(def.config)
        local choices=cfg and type(cfg[def.method])=='function' and cfg[def.method](cfg) or {}
        if mode=='Gate' or mode=='Raid' then
            local filtered={}
            for key,value in pairs(choices) do
                if (value.GateOnly==true)==(mode=='Gate') then filtered[key]=value end
            end
            return filtered
        end
        return choices
    end
    local rankOrder={'S','A','B','C','D','E'}
    local rankWeight={S=6,A=5,B=4,C=3,D=2,E=1}
    function A.gateRankRows()
        local present={}; local rows={}
        for _,cfg in pairs(A.activityChoices('Gate')) do
            for _,rank in ipairs(type(cfg.GateRanks)=='table' and cfg.GateRanks or {}) do
                if type(rank)=='table' and type(rank.Rank)=='string' then present[rank.Rank]=true end
            end
        end
        for _,rank in ipairs(rankOrder) do if present[rank] then rows[#rows+1]={key=rank,label=rank} end end
        return rows
    end
    local function candidateKeys(mode,choices)
        if mode=='TimeTrial' then return A.Core.activityKeys(choices,mode) end
        local keys=A.Core.keys(choices)
        if mode=='Gate' then
            table.sort(keys,function(a,b)
                local left=available.Gate[a]; local right=available.Gate[b]
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
            if entries[key] and entries[key].GateOnly==true then mode='Gate' end
        end
        return mode~='World' and mode or nil,raw
    end
    local function enabled(mode,key)
        local def=definitions[mode]
        return A.settings[def.toggle] and A.settings[def.selection][key]==true
    end
    local function selectCandidate()
        waitingReason=nil
        for _,mode in ipairs(order) do
            local choices=A.settings[definitions[mode].toggle] and A.activityChoices(mode) or {}
            for _,key in ipairs(candidateKeys(mode,choices)) do
                if enabled(mode,key) and (backoff[mode..':'..key] or 0)<=os.clock() then
                    local entry=available[mode][key]
                    if mode=='Tower' then
                        local cfg=A.config('TowerConfig'); local util=A.util('TowerStateUtil'); local d=A.data()
                        local tower=choices[key]
                        if cfg and cfg.Enabled~=false and util and d and A.unlocked(tower.WorldId)
                            and util.GetCooldownRemaining(d,tower)<=0 then return mode,key,{} end
                    elseif mode=='Gate' then
                        if entry and entry.deadline>os.clock() then
                            if not entry.rank then waitingReason='Gate rank not provided; waiting for a ranked announcement'
                            elseif A.settings.gateRanks[entry.rank] then return mode,key,entry end
                        end
                    elseif mode~='Raid' and entry and entry.deadline>os.clock() then return mode,key,entry
                    elseif mode=='Raid' or mode=='Defense' then
                        local cfg=choices[key]
                        if cfg.GateOnly then waitingReason=mode..': portal-only entry; own-run creation unavailable'
                        elseif cfg.WorldId and not A.unlocked(cfg.WorldId) then
                            waitingReason=mode..': unlock World '..tostring(cfg.WorldId)
                        elseif not A.data() then waitingReason='Waiting for player data'
                        else
                            local cost=cfg.Cost
                            if type(cost)=='table' and A.balance(cost.ItemId)<(tonumber(cost.Amount) or 0) then
                                waitingReason=mode..': need '..tostring(cost.Amount)..' '..tostring(cost.ItemId)
                            else return mode,key,{action='Create'} end
                        end
                    end
                end
            end
        end
    end
    local function status(text) A.status.Activities=text; A.status['Trial join']=text end
    local function suspendFarm()
        A.watchTarget(nil)
        local c=A.player.Character; local h=c and c:FindFirstChildOfClass('Humanoid')
        if h then h:Move(Vector3.zero) end
    end
    function A.activityBlocksFarm()
        local mode=context()
        return mode~=nil or pending~=nil or leaving~=nil or locked~=nil or returning~=nil
    end
    local function sendJoin(mode,key,entry)
        if mode=='Gate' then return A.fire('RaidGateTeleport',key) end
        if mode=='Tower' then return A.fire('TowerJoin',{TowerKey=key}) end
        if mode=='Raid' then return A.fire('RaidJoin','Create',key,true) end
        if mode=='BossRush' then return A.fire('BossRushJoin','Join',key,entry.modeId or 'V1',true) end
        return A.fire(mode..'Join',entry.action or 'Join',key)
    end
    function A.coordinateActivities()
        if not A.alive or not A.running then return end
        local current,raw=context()
        local ctrl=A.client('TeleportController')
        local loading=ctrl and ctrl:IsLoading()
        if protected[current] and returning~=current then locked=current end
        if type(raw)=='string' and raw:match('^World:') and not A.inMode() and not loading then
            locked=nil; returning=nil; leaving=nil
        end
        if pending and not pending.accepted and not loading and not protected[current] then
            local nextMode=selectCandidate()
            if nextMode and definitions[nextMode].rank>definitions[pending.mode].rank then pending=nil end
        end
        if pending then
            if current==pending.mode then
                pending=nil; returning=nil
            elseif protected[current] and returning~=current then pending=nil
            elseif not loading and (not current or definitions[current]) then
                local entry=available[pending.mode][pending.key]
                local scheduled=pending.mode~='Raid' and pending.mode~='Tower' and pending.mode~='Defense'
                if not enabled(pending.mode,pending.key) or (scheduled and (not entry or entry.deadline<=os.clock()))
                    or (pending.mode=='Gate' and (not entry or not entry.rank or not A.settings.gateRanks[entry.rank] or entry.rank~=pending.entry.rank)) then
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
        if loading then return end
        local mode,key,entry=selectCandidate()
        if not mode then status(current and ('In '..current) or (waitingReason or 'Waiting for a selected activity')); return end
        local direct=mode=='Tower' or mode=='TimeTrial' or mode=='Dungeon'
        if leaving and not direct then status('Waiting for '..leaving..' exit confirmation'); return end
        if current then
            local def=definitions[current]
            if not def then status('Waiting for current mode to finish'); return end
            -- Finished protected runs may transfer next; unfinished ones stay locked above.
            if returning~=current and definitions[mode].rank<=def.rank then return end
            if not direct then
                if returning==current then status('Waiting for '..current..' return teleport'); return end
                leaving=current; suspendFarm(); status('Leaving '..current..' for '..mode)
                if not A.fire(current=='Gate' and 'RaidLeave' or current..'Leave') then leaving=nil; status('Leave bridge unavailable: '..current) end
                return
            end
        elseif returning then status('Waiting for '..returning..' return teleport'); return
        elseif A.inMode() then status('Waiting for current mode to finish'); return end
        if direct then leaving=nil end
        pending={mode=mode,key=key,entry=entry,at=os.clock(),lastSent=os.clock(),attempts=1}
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
        if mode~='Gate' then
        if mode~='Raid' then A.on(mode..'Announcement',function(p)
            if type(p)~='table' or p.NotifyKind~='GamemodeOpen' or p.GamemodeType~=mode or type(p.Key)~='string' then return end
            -- A raid gate announcement is a world gate teleport, not a joinable raid.
            if p.GateTeleport then return end
            local duration=tonumber(p.ExpiresIn) or 10
            if duration<=0 or duration~=duration then return end
            available[mode][p.Key]={deadline=os.clock()+math.min(duration,600),modeId=p.ModeId}
            A.coordinateActivities()
        end) end
        A.on(mode..'Ended',function()
            local current=context()
            local ended=mode=='Raid' and (current=='Gate' or locked=='Gate') and 'Gate' or mode
            if current==ended or locked==ended then locked=nil; returning=ended end
            if pending and pending.mode==mode then pending=nil end
            A.coordinateActivities()
        end)
        if mode~='Tower' then
            A.on(mode..'Join',function(accepted,reason)
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
        local rank=type(p.GateRank)=='string' and p.GateRank
            or (type(p.Name)=='string' and p.Name:match('Rank%s+([A-Z]+)'))
            or (type(p.Title)=='string' and p.Title:match('Rank%s+([A-Z]+)'))
        if not rankWeight[rank] then rank=nil end
        available.Gate[p.Key]={deadline=os.clock()+math.min(duration,600),rank=rank}
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
        if type(p)=='table' and p.Refused and pending and pending.mode=='Tower' then
            backoff['Tower:'..pending.key]=os.clock()+10; pending=nil
            A.status['Activity error']='Tower refused: '..tostring(p.Refused)
            status(A.status['Activity error'])
        end
    end)
    A.on('TimeTrialActiveStatus',function(_,p)
        if type(p)~='table' then return end
        available.TimeTrial={}
        if p.IsOpen==true then
            local keys=p.OpenTrialKeys or {[p.OpenTrialKey or '']=true}
            for key,value in pairs(keys) do
                if type(key)=='string' and value==true then available.TimeTrial[key]={deadline=math.huge} end
            end
        end
        A.coordinateActivities()
    end)
    A.connect(A.player:GetAttributeChangedSignal('VisibilityContext'),A.coordinateActivities)
    A.job('Activities',0.2,A.coordinateActivities)
end

end)()(A);

-- ===== guild_clock =====
(function()
return function(A)
    local G=A.GuildCore
    local lastClock,lastBeat=nil,0
    local suspended=false
    A.guildHeartbeatFile=A.folder..'/guild-heartbeat.json'
    local function finite(n) return type(n)=='number' and n==n and n>=0 and n<math.huge end
    function A.guildAccrue()
        local now=os.clock(); local s=A.guildSession
        if s and s.active and not suspended and lastClock then
            local delta=now-lastClock
            if delta>=0 and delta<=G.maxObservedInterval then
                s.activeTrackingSeconds=s.activeTrackingSeconds+delta
            elseif delta>G.maxObservedInterval then
                s.runtimeStallSeconds=(s.runtimeStallSeconds or 0)+delta
                if A.guildBreakObservation then A.guildBreakObservation() end
            end
        end
        lastClock=now
    end
    function A.guildRuntimeSeconds()
        local s=A.guildSession; if not s then return 0 end
        local delta=lastClock and os.clock()-lastClock or 0
        if not s.active or suspended or delta<0 or delta>G.maxObservedInterval then delta=0 end
        return s.activeTrackingSeconds+delta
    end
    function A.guildIsSuspended() return suspended end
    function A.guildHeartbeat(force,reason)
        local s=A.guildSession
        if not s or not s.active or (suspended and not force) then return end
        if not force and os.clock()-lastBeat<G.heartbeatSeconds then return end
        A.guildAccrue(); lastBeat=os.clock()
        local h={schemaVersion=1,sessionId=s.sessionId,generation=s.generation,ownerUserId=s.ownerUserId,
            gameId=s.gameId,active=true,activeTrackingSeconds=s.activeTrackingSeconds,
            lastHeartbeatAt=os.time(),lastFullSaveAt=s.lastSavedAt,exitReason=reason or false}
        local ok,err=pcall(function()
            local encoded=A.S.HTTP:JSONEncode(h)
            for _,suffix in ipairs({'','.bak'}) do
                writefile(A.guildHeartbeatFile..suffix,encoded)
                local check=A.safeLoad(A.guildHeartbeatFile..suffix)
                assert(check and check.sessionId==h.sessionId and check.lastHeartbeatAt==h.lastHeartbeatAt,'Heartbeat read-back failed')
            end
        end)
        if ok then s.lastHeartbeatAt=h.lastHeartbeatAt
        else A.status['Guild storage']='HEARTBEAT SAVE FAILED: '..tostring(err); A.log('Guild',A.status['Guild storage']) end
    end
    function A.guildAttachClock(restored)
        local s=A.guildSession; if not s then return end
        G.migrate(s); lastClock=os.clock(); lastBeat=0; suspended=false
        if restored and s.active then
            local best
            for _,suffix in ipairs({'','.bak'}) do
                local h=A.safeLoad(A.guildHeartbeatFile..suffix)
                if type(h)=='table' and h.schemaVersion==1 and h.sessionId==s.sessionId and h.generation==s.generation
                    and h.ownerUserId==s.ownerUserId and h.gameId==s.gameId and h.active==true
                    and finite(h.lastHeartbeatAt) and finite(h.activeTrackingSeconds)
                    and (not best or h.lastHeartbeatAt>best.lastHeartbeatAt) then best=h end
            end
            local prior=tonumber(s.lastHeartbeatAt) or tonumber(s.lastSavedAt)
            if best and best.lastHeartbeatAt>=(tonumber(s.lastSavedAt) or 0) then
                s.activeTrackingSeconds=math.max(s.activeTrackingSeconds,best.activeTrackingSeconds)
                prior=best.lastHeartbeatAt
            end
            if prior then
                local r={lastHeartbeatAt=prior,resumedAt=os.time(),gapSeconds=math.max(0,os.time()-prior),
                    previousLastSavedAt=s.lastSavedAt,exitReason=best and best.exitReason or false,
                    note='Gap after last recorded heartbeat excluded; this does not establish an exact crash time.'}
                G.append(s,'recoveries',r); s.pendingRecoveryNotice=r
                A.log('Guild','Restored active runtime; gap after '..os.date('!%Y-%m-%d %H:%M:%S UTC',prior)..' excluded.')
            end
        end
        if s.active then s.lastSessionStartedAt=os.time() end
        G.metrics(s,os.time())
    end
    function A.guildSuspend(reason)
        local s=A.guildSession; if not s or not s.active or suspended then return end
        A.guildAccrue(); suspended=true
        if A.guildBreakObservation then A.guildBreakObservation() end
        A.guildHeartbeat(true,reason); A.guildSave()
    end
    function A.guildResumeClock()
        suspended=false; lastClock=os.clock()
        if A.guildBreakObservation then A.guildBreakObservation() end
    end
end

end)()(A);

-- ===== guild =====
(function()
return function(A)
    local G,C=A.GuildCore,A.Core
    A.guildFile=A.folder..'/guild-weekly-tracking.json'
    local paths={A.guildFile,A.guildFile..'.bak',A.guildFile..'.tmp'}
    local previous,pending,nextPoll=nil,nil,0
    local saving=false
    local function loadSession()
        local best
        for _,path in ipairs(paths) do
            local s=A.safeLoad(path)
            if G.valid(s,A.player.UserId,game.GameId) and (not best or s.generation>best.generation
                or (s.generation==best.generation and s.revision>best.revision)) then best=s end
        end
        return best
    end
    A.guildSession=loadSession()
    function A.guildBreakObservation() previous=nil; pending=nil end
    A.guildAttachClock(true)
    function A.guildSave(candidate)
        if saving then return false end
        if type(writefile)~='function' or type(readfile)~='function' or type(makefolder)~='function' then
            A.status['Guild storage']='File APIs required; tracking cannot be persisted'; return false
        end
        local s=candidate or A.guildSession; if not s then return false end
        if not candidate then A.guildAccrue() end
        saving=true
        local snapshot=C.copy(s); G.metrics(snapshot,os.time())
        snapshot.revision=snapshot.revision+1; snapshot.lastSavedAt=os.time()
        snapshot.lastSavedAtISO=os.date('!%Y-%m-%dT%H:%M:%SZ',snapshot.lastSavedAt)
        local durable=false
        local ok,err=pcall(function()
            pcall(makefolder,A.folder)
            local encoded=A.S.HTTP:JSONEncode(snapshot)
            assert(G.valid(A.S.HTTP:JSONDecode(encoded),A.player.UserId,game.GameId),'Invalid tracking snapshot')
            -- Stage and verify before replacing the primary; both backups retain recoverable data.
            for _,path in ipairs({paths[3],paths[1],paths[2]}) do
                writefile(path,encoded)
                local saved=A.safeLoad(path)
                assert(G.valid(saved,A.player.UserId,game.GameId) and saved.sessionId==snapshot.sessionId
                    and saved.revision==snapshot.revision,'Read-back failed')
                durable=true
            end
        end)
        saving=false
        if durable then
            s.revision=snapshot.revision; s.lastSavedAt=snapshot.lastSavedAt; s.lastSavedAtISO=snapshot.lastSavedAtISO
        end
        if ok then
            A.status['Guild storage']='Saved '..s.lastSavedAtISO
        else A.status['Guild storage']=(durable and 'RECOVERY COPY SAVED; copy update failed: ' or 'SAVE FAILED: ')..tostring(err); A.log('Guild',A.status['Guild storage']) end
        return durable
    end
    function A.guildQueueExport()
        local s=A.guildSession
        if not s or s.active or s.finalSnapshotStatus=='pending' then return end
        if s.exportQueued then return end
        local name='GuildTracking_'..os.date('!%Y-%m-%d',s.startedAt)..'.json'
        local path=A.folder..'/guild-export-'..s.sessionId:gsub('[^%w%-_]','_')..'-'..s.generation..'.json'
        local ok,err=pcall(function()
            local snapshot=C.copy(s); G.metrics(snapshot,s.endedAt)
            local encoded=A.S.HTTP:JSONEncode(snapshot)
            writefile(path,encoded)
            assert(readfile(path)==encoded,'Export read-back failed')
        end)
        if not ok then A.status['Guild upload']='Export failed: '..tostring(err); A.log('Guild',A.status['Guild upload']); return end
        local message='Started: '..s.startedAtISO..'\nStopped: '..s.endedAtISO
            ..'\nACTIVE tracking: '..string.format('%.2f hours',s.activeTrackingSeconds/3600)
            ..'\nMembers: '..s.trackedMemberCount..'\nLast save: '..tostring(s.lastSavedAtISO)
        local entry=A.notify('GuildExport',message,true,{path=path,name=name,key=s.sessionId..':'..s.generation})
        if entry then s.exportQueued=true; A.guildSave(); A.status['Guild upload']='JSON upload queued'
        else A.status['Guild upload']='JSON kept locally. Enable webhook and enter its URL, then press Stop Tracking to retry.' end
    end
    local snapshotBusy=false
    function A.guildSendSnapshot()
        local s=A.guildSession
        if not s then A.status['Guild upload']='Start tracking before sending a snapshot'; return end
        if snapshotBusy then return end
        snapshotBusy=true
        local ok,err=pcall(function()
            assert(A.guildSave(),'Could not save tracker state; check storage status')
            local snapshot=C.copy(s); local now=os.time(); G.metrics(snapshot,now)
            snapshot.exportType='progressSnapshot'; snapshot.snapshotAt=now
            snapshot.snapshotAtISO=os.date('!%Y-%m-%dT%H:%M:%SZ',now)
            local key=s.sessionId..':'..s.generation..':snapshot:'..s.revision
            local path=A.folder..'/guild-export-'..s.sessionId:gsub('[^%w%-_]','_')..'-'..s.generation..'-snapshot-'..s.revision..'.json'
            local encoded=A.S.HTTP:JSONEncode(snapshot)
            writefile(path,encoded); assert(readfile(path)==encoded,'Snapshot read-back failed')
            local message='Progress snapshot — '..(s.active and 'tracking remains ON' or 'tracking is OFF')
                ..'\nCaptured: '..snapshot.snapshotAtISO
                ..'\nACTIVE tracking: '..string.format('%.2f hours',snapshot.activeTrackingSeconds/3600)
                ..'\nMembers: '..snapshot.trackedMemberCount
                ..'\nLast roster: '..(s.lastObservedAt and os.date('!%Y-%m-%dT%H:%M:%SZ',s.lastObservedAt) or 'unavailable')
            local entry=A.notify('GuildSnapshot',message,true,{path=path,
                name='GuildTracking_Progress_'..os.date('!%Y-%m-%d_%H-%M-%S',now)..'.json',key=key})
            A.status['Guild upload']=entry and 'Progress JSON queued; tracking state unchanged'
                or 'Snapshot saved locally. Enable webhook and enter its URL, then send again.'
        end)
        snapshotBusy=false
        if not ok then A.status['Guild upload']='Snapshot failed: '..tostring(err); A.log('Guild',A.status['Guild upload']) end
    end
    function A.guildExportFailed(key)
        local s=A.guildSession
        if s and not s.active and key==s.sessionId..':'..s.generation then
            s.exportQueued=false; s.exportRequested=false; A.guildSave()
        end
    end
    local function currentGuild() return G.id((A.data() or {}).GuildId) end
    local function sendRoster(kind)
        local id=currentGuild()
        if not id then A.status['Guild tracker']='Waiting for your guild/player data'; return false end
        if kind~='start' and A.guildSession and id~=G.id(A.guildSession.guildId) then
            previous=nil; A.status['Guild tracker']='Different guild detected; original session preserved'; return false
        end
        if pending then return false end
        if os.clock()<nextPoll and kind=='poll' then return false end
        pending={kind=kind,guildId=id,deadline=os.clock()+12,requestedAt=os.time()}
        nextPoll=os.clock()+G.pollSeconds
        local bridge=A.bridge('GuildRosterRequest')
        -- A read-only request; intentionally independent of the gameplay Automation toggle.
        local ok=bridge and pcall(bridge.Fire,bridge)
        if not ok then pending=nil; A.status['Guild tracker']='Guild roster request unavailable'; return false end
        return true
    end
    function A.guildStart()
        if pending then A.status['Guild tracker']='Waiting for the current roster request'; return end
        if type(writefile)~='function' or type(readfile)~='function' or type(makefolder)~='function' then
            A.status['Guild tracker']='Cannot start: persistent file APIs are missing'; return
        end
        A.status['Guild tracker']='Fetching a fresh baseline for the new session'
        sendRoster('start')
    end
    function A.guildStop()
        local s=A.guildSession
        if not s then return end
        if not s.active then s.exportRequested=true; A.guildQueueExport(); return end
        A.guildAccrue()
        s.exportRequested=true
        pending=nil; G.stop(s,os.time()); previous=nil
        A.guildSave(); A.status['Guild tracker']='Stopped; requesting final contribution snapshot'
        if not sendRoster('stop') then s.finalSnapshotStatus='unavailable'; A.guildSave(); A.guildQueueExport() end
    end
    function A.guildRefresh()
        if A.guildSession and A.guildSession.active then sendRoster('poll')
        else A.status['Guild tracker']='Finished results are frozen. Start Tracking begins a new session.' end
    end
    A.on('GuildRosterResult',function(payload)
        local request=pending
        if not request then return end
        local rows,err=G.roster(payload,request.guildId,A.player.UserId)
        if not rows then
            if type(payload)=='table' and payload.Live~=true then A.status['Guild tracker']=err end
            return
        end
        if currentGuild()~=request.guildId then pending=nil; previous=nil; return end
        if A.guildIsSuspended() and request.kind=='poll' then pending=nil; return end
        A.guildAccrue()
        pending=nil; local now=os.time(); local s=A.guildSession
        if request.kind=='start' then
            local guid
            local ok,value=pcall(function() return A.S.HTTP:GenerateGUID(false) end)
            guid=ok and value or (tostring(now)..'-'..tostring(math.random(100000,999999)))
            local fresh=G.new(rows,request.guildId,A.player.UserId,game.GameId,now,guid,(s and s.generation or 0)+1)
            local first=G.sample(fresh,rows,now,nil)
            if not A.guildSave(fresh) then A.status['Guild tracker']='New session could not be fully saved; inspect Guild storage'; return end
            A.guildSession=fresh; previous=first; s=fresh
            A.guildAttachClock(false); A.guildHeartbeat(true)
            A.status['Guild tracker']='Tracking started; existing contribution stored as the baseline'
        elseif request.kind=='stop' then
            if not s or s.active then return end
            G.finalSnapshot(s,rows,now)
            local saved=A.guildSave()
            A.status['Guild tracker']=saved and 'Tracking stopped; final snapshot saved' or 'Tracking stopped; final save failed (see Guild storage)'
            A.guildQueueExport()
        elseif s and s.active and G.id(s.guildId)==request.guildId then
            local changed
            previous,changed=G.sample(s,rows,now,previous)
            if changed then A.guildSave() end
            A.status['Guild tracker']='Tracking '..s.trackedMemberCount..' members; presence is sampled'
        end
    end)
    function A.guildCheckpoint(reason)
        if reason then A.guildSuspend(reason); return end
        if A.guildSession and A.guildSession.active then
            previous=nil; pending=nil
            A.guildHeartbeat(true); A.guildSave()
        end
    end
    A.connect(A.player.OnTeleport,function(state)
        if state==Enum.TeleportState.Started then A.guildSuspend('teleport')
        elseif state==Enum.TeleportState.Failed then A.guildResumeClock() end
    end)
    A.connect(A.S.Players.PlayerRemoving,function(player) if player==A.player then A.guildSuspend('departure') end end)
    A.job('Guild tracker',5,function()
        local s=A.guildSession
        if not A.alive then return end
        A.guildAccrue()
        if pending and os.clock()>pending.deadline then
            local kind=pending.kind; pending=nil; previous=nil
            A.status['Guild tracker']='Roster response timed out; no online time added for the gap'
            if kind=='stop' and s then s.finalSnapshotStatus='unavailable'; A.guildSave(); A.guildQueueExport() end
        end
        if not s or not s.active or A.guildIsSuspended() then return end
        if s.pendingRecoveryNotice then
            local r=s.pendingRecoveryNotice
            local entry=A.notify('Disconnect','Previous tracker last recorded heartbeat: '
                ..os.date('!%Y-%m-%d %H:%M:%S UTC',r.lastHeartbeatAt)..'\nResumed: '
                ..os.date('!%Y-%m-%d %H:%M:%S UTC',r.resumedAt)..'\nGap: '..r.gapSeconds
                ..' seconds (not counted). Exact crash time/cause is unknown.',true)
            if entry then s.pendingRecoveryNotice=false; A.guildSave() end
        end
        if s.lastObservedAt and os.time()-s.lastObservedAt>G.maxObservedInterval then
            for _,m in pairs(s.members) do if m.inGuild then m.onlineStatus='unknown' end end
        end
        A.guildHeartbeat(false)
        if not s.lastSavedAt or os.time()-s.lastSavedAt>=G.autosaveSeconds then A.guildSave() end
        sendRoster('poll')
    end,true)
    if A.guildSession then
        if A.guildSession.active then
            for _,m in pairs(A.guildSession.members) do m.onlineStatus='unknown' end
            A.status['Guild tracker']='Active saved session restored; waiting for a fresh roster'
        else
            A.status['Guild tracker']='Finished session loaded; statistics remain frozen'
            if A.guildSession.finalSnapshotStatus=='pending' then
                A.guildSession.finalSnapshotStatus='unavailableAfterRestart'; A.guildSave()
            end
            if A.guildSession.exportRequested and not A.guildSession.exportQueued then A.guildQueueExport() end
        end
    else A.status['Guild tracker']='No valid saved session; press Start Tracking when ready' end
    local function duration(seconds) return string.format('%dh %dm',math.floor(seconds/3600),math.floor(seconds/60)%60) end
    function A.guildSummary()
        local s=A.guildSession
        local text=s and s.active and 'TRACKING IS ON' or 'TRACKING IS OFF'
        if s then
            text=text..'\nTotal tracking time (active): '..duration(A.guildRuntimeSeconds())
        end
        local storage=A.status['Guild storage'] or ''
        local tracker=A.status['Guild tracker'] or ''
        if storage:find('FAILED',1,true) or storage:find('copy update failed',1,true) then
            text=text..'\nSave problem: '..storage
        elseif tracker:find('Cannot start:',1,true) then text=text..'\n'..tracker
        elseif not s and pending then text=text..'\nStarting...'
        elseif not s and tracker:find('timed out',1,true) then text=text..'\nCould not start. Press Start Tracking to retry.' end
        if A.status['Guild upload'] then text=text..'\n'..A.status['Guild upload'] end
        return text
    end
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
    local window=F:CreateWindow({Title='JoesAAS',SubTitle='4.4',TabWidth=touch and 92 or 150,
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
    for _,name in ipairs({'Farm','Modes','Pets','Guild Tracker','Webhook','Settings'}) do
        tabs[name]=window:AddTab({Title=name,Icon=''})
    end
    local sync=true; local bindings={}; local statuses={}
    local function guard(fn)
        return function(...)
            if sync or not A.alive then return end
            local ok,why=pcall(fn,...)
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
    local function input(tab,title,key,numeric)
        local option=tabs[tab]:AddInput(key,{Title=title,Default=tostring(A.settings[key]),Numeric=numeric==true,Finished=false})
        option:OnChanged(guard(function(value)
            if numeric then
                local n=tonumber(value)
                if not n or n~=n or n<0 or n==math.huge then return end
                A.settings[key]=n
            else A.settings[key]=tostring(value):match('^%s*(.-)%s*$') end
        end))
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
    toggle('Farm','Auto farm selected mobs','farm')
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
    note('Farm','Trial priority','Insane > Hard > Medium > Easy among selected trials currently open. An active trial always finishes first.')
    status('Modes','Activities')
    status('Modes','Activity error')
    note('Modes','Raid / Defense','Raid starts YOUR OWN run only; never joins other raids. Defense starts or joins an available run. Normal entry costs apply; errors appear above.')
    note('Modes','Activity priority','Tower > Time Trials > Dungeon > Gate > Raid / Defense > Boss Rush > mob farming. Tower, Trial and Dungeon runs finish or fail before switching. Gate can yield to a higher-priority mode. Raid wins a tie with Defense; an active run keeps its place.')
    note('Modes','Transfers','Tower, Trials and Dungeons use direct native entry. Gate and lower modes wait for normal exit. Gate and Tower stay at their join position.')
    note('Modes','Movement','Time Trials and Dungeons follow mobs with continuous anti-stuck steps. Tower opens your own tower. Turn off competing auto-join / movement in your other script to let this coordinator control switching.')
    for _,entry in ipairs({{'Tower','towerAutoJoin','towerSelection'},{'Dungeon','dungeonAutoJoin','dungeonSelection'},{'Gate','gateAutoJoin','gateSelection'},{'Raid','raidAutoJoin','raidSelection'},
        {'Defense','defenseAutoJoin','defenseSelection'},
        {'BossRush','bossRushAutoJoin','bossRushSelection'}}) do
        local mode,toggleKey,selectionKey=entry[1],entry[2],entry[3]
        dropdown('Modes',mode..' selection',selectionKey,function()
            return A.activityRows(mode)
        end,function(key) return A.settings[selectionKey][key]==true end,
        function(selected) A.settings[selectionKey]=selected; A.coordinateActivities() end,true)
        if mode=='Gate' then
            dropdown('Modes','Gate ranks','gateRanks',A.gateRankRows,
                function(key) return A.settings.gateRanks[key]==true end,
                function(selected) A.settings.gateRanks=selected; A.coordinateActivities() end,true)
            note('Modes','Gate rank priority','S > A > B > C > D > E among selected open Gates. Only ranks exposed by the game are listed.')
        end
        toggle('Modes',mode=='Raid' and 'Auto start my own Raid' or ('Auto join '..mode),toggleKey,A.coordinateActivities)
    end
    input('Pets','Name for unnamed Astral pets','petName')
    toggle('Pets','Auto rename Astral pets ONLY','rename')
    note('Pets','Astral naming','Only verified Astral rarity is eligible. Already named and percentage pets are skipped. Uses the normal Magicule cost. Check the status below for blockers.')
    status('Pets','Rename')
    status('Pets','Rename report')
    button('Pets','Retry unconfirmed renames',A.retryRenaming)
    button('Guild Tracker','Start Tracking',A.guildStart)
    button('Guild Tracker','Stop Tracking',A.guildStop)
    button('Guild Tracker','Send current JSON',A.guildSendSnapshot)
    local guildSummary=note('Guild Tracker','Tracking status',A.guildSummary())
    statuses[#statuses+1]=function() guildSummary:SetDesc(A.guildSummary()) end

    input('Webhook','Webhook URL','webhookURL'); input('Webhook','Discord user ID','pingId')
    toggle('Webhook','Enable webhook','webhook'); toggle('Webhook','Send disconnect notification','sendDisconnect')
    toggle('Webhook','Ping selected user','ping')
    multi('Webhook','Events to send','webhookEvents',choices({'Disconnect','Mode','Progress','Error','Inventory'}))
    multi('Webhook','Events to ping','pingEvents',choices({'Disconnect','Mode','Progress','Error','Inventory'}))
    toggle('Webhook','Save webhook URL locally with settings','saveSecrets')
    button('Webhook','Send test notification',function() A.notify('Test','Webhook test from JoesAAS',true) end)
    note('Webhook','Disconnect / recovery','A hard crash stops the sender. Guild tracking records a local heartbeat and reports the interruption after you rerun the script. Stop Tracking sends its JSON attachment here. Save the URL with settings and enable autoload to restore it after rejoining.')
    status('Webhook','Webhook'); status('Webhook','Disconnect')
    button('Settings','Save settings',function() A.save() end)
    button('Settings','Load settings',function() A.load() end)
    local auto=tabs.Settings:AddToggle('autoload',{Title='Autoload saved settings on launch',Default=A.autoloadEnabled})
    auto:OnChanged(guard(function(value) A.setAutoload(value); A.refreshUI() end))
    bindings[#bindings+1]=function()
        if auto.Value~=A.autoloadEnabled then auto:SetValue(A.autoloadEnabled) end
    end
    note('Settings','Save / Load / Autoload','Save writes the current configuration. Autoload restores that saved configuration next launch. Save again after changing options. Loaded or autoloaded ON features run immediately. Each feature uses its own toggle.')
    local savedStatus=note('Settings','Configuration','Ready')
    statuses[#statuses+1]=function()
        savedStatus:SetDesc('Autoload: '..(A.autoloadEnabled and 'enabled' or 'disabled'))
    end
    toggle('Settings','Black screen / disable 3D rendering','blackScreen',function(value) if A.render then A.render(value) end end)
    note('Settings','Controls',touch and 'Tap JoesAAS to hide/show; drag it to reposition. Use each feature’s own toggle. RESTORE enables rendering. Landscape gives the menus more room.'
        or 'Right Shift: minimize/show Fluent. F8: restore rendering. Rendering starts enabled.')
    note('Settings','Executor capabilities',
        'Save/load: '..((type(writefile)=='function' and type(readfile)=='function' and type(makefolder)=='function') and 'available' or 'file APIs missing')
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
        writefile(A.folder..'/diagnostics.json',A.S.HTTP:JSONEncode({version='3.9',rename=A.renameDiagnostics(),status=A.status,logs=A.logs,jobs=jobs,enabled=enabled,
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
    A.settings.blackScreen=false
    sync=false; A.refreshUI(); window:SelectTab(1)
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
