-- Anime Suite 3.1 | standalone source | September 2026
-- Built against the supplied client export. See AnimeSuite-README.md for limits and validation.
-- Fluent UI from dawid-scripts/Fluent. Autoload is opt-in; each feature uses its own toggle.
local environment = (type(getgenv) == "function" and getgenv()) or _G
local previous = environment.AnimeSuite
if previous and type(previous.stop) == "function" then pcall(previous.stop) end
if game.GameId ~= 10502841145 then
    warn("Anime Suite: this build targets the exported game's universe, not this experience.")
    return
end
local A = {}
environment.AnimeSuite = A
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
function Core.priorities(list)
    local valid={Damage=true,Drop=true,Luck=true,Power=true,XP=true,Yen=true}
    local out, seen={},{}
    for _,v in ipairs(list or {}) do
        if valid[v] and not seen[v] then out[#out+1]=v; seen[v]=true end
    end
    for _,v in ipairs({'Damage','Drop','Luck','Power','XP','Yen'}) do
        if not seen[v] then out[#out+1]=v end
    end
    return out
end
-- Round robin: after one accepted purchase in a stat, advance to the next.
-- Locked/unaffordable categories are skipped, never cause a busy loop.
function Core.pick(candidates, order, cursor, treeCursor)
    if #order==0 then return nil,cursor end
    cursor=((tonumber(cursor) or 1)-1)%#order+1
    for offset=0,#order-1 do
        local index=(cursor+offset-1)%#order+1
        local bucket={}
        for _,c in ipairs(candidates) do
            if c.stat==order[index] and c.eligible then bucket[#bucket+1]=c end
        end
        table.sort(bucket,function(a,b)
            if a.tree~=b.tree then return a.tree<b.tree end
            if a.cost~=b.cost then return a.cost<b.cost end
            return a.key<b.key
        end)
        if #bucket>0 then
            local chosen=bucket[1]
            for _,c in ipairs(bucket) do
                if c.tree>(treeCursor or '') then chosen=c; break end
            end
            return chosen,index%#order+1
        end
    end
    return nil,cursor
end
function Core.stat(node, order)
    for _,stat in ipairs(order) do
        if node.Perks and node.Perks[stat] then return stat end
    end
    local keys=Core.keys(node.Perks)
    return keys[1] or 'Other'
end
function Core.treeCandidates(trees,data,balances,parse,order,unlocked,blocked)
    local candidates={}
    for treeName,tree in pairs(trees) do
        if not tree.WorldId or unlocked(tree.WorldId) then
            local owned=(data.SkillTree or {})[treeName] or {}
            for key,node in pairs(tree.Upgrades or {}) do
                if not owned[key] and (not node.Parent or owned[node.Parent]) then
                    local price=node.Price or {}
                    local cost=parse(price.Amount)
                    local currency=price.Name
                    candidates[#candidates+1]={tree=treeName,key=key,node=node,cost=cost,
                        currency=currency,stat=Core.stat(node,order),
                        eligible=currency~=nil and cost>=0 and (balances(currency) or 0)>=cost
                            and not blocked(treeName..'/'..key)}
                end
            end
        end
    end
    return candidates
end
function Core.renameEligible(id,pet,named,target,petStats)
    if type(id)~='string' or type(pet)~='table' then return false end
    if not petStats or type(petStats.GetRarity)~='function' or petStats.GetRarity(pet)~='Astral' then return false end
    -- Any existing named entry is protected, including older formats.
    if named[id]~=nil and named[id]~=false then return false end
    if (type(pet.CustomName)=='string' and pet.CustomName:match('%S')) or pet.Renamed==true then return false end
    if pet.Name==target then return false end
    if petStats and petStats.IsDynamicById and petStats.IsDynamicById(pet.PetId) then return false end
    return true
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
    A.alive=true; A.running=false; A.epoch=0; A.started=os.clock(); A.spendPaused=false
    A.defaults={version=2,world='0',mobsByWorld={},target='Nearest',farm=false,autoQuest=false,
        sideQuest=false,globalQuest=false,promotionTasks=false,buyWorlds=false,
        rank=false,promote=false,chests=false,claimQuest=false,
        trees=false,priority={'Damage','Drop','Luck','Power','XP','Yen'},
        treeSelection={},evolutions=false,evolutionSelection={},specializations=false,specialSelection={},
        rename=false,petName='',bestPets=false,bestLoadout=false,loadoutStat='Damage',bestAvatar=false,
        achievements=false,rewards=false,levelRewards=false,welcomeRewards=false,
        progression=false,progressionSelection={},
        towerJoin=false,towerFarm=false,towerKey='',towerLeaveOther=false,towerTarget='Nearest',
        trialJoin=false,trialFarm=false,trialKey='',trialLeaveOther=false,trialTarget='Nearest',
        modePriority={'Tower','TimeTrial'},towerBankFloor=80,
        gacha=false,gachaKey='',eggs=false,eggKey='',
        webhook=false,webhookURL='',pingId='',ping=false,sendDisconnect=true,
        webhookEvents={Disconnect=true,Mode=true,Progress=true,Error=true,Inventory=true},
        pingEvents={Disconnect=true,Error=true,Mode=false,Progress=false,Inventory=false},blackScreen=false,
        moveStyle='Walk',distance=5,saveSecrets=false}
    A.folder='AnimeSuite_'..tostring(game.GameId)..'_'..tostring(A.player.UserId)
    A.file=A.folder..'/settings.json'
    function A.log(kind,text)
        text=tostring(text)
        if A.settings and A.settings.webhookURL~='' then
            text=text:gsub('https://[^%s]+/api/webhooks/[^%s]+','[webhook redacted]')
        end
        local line=os.date('%H:%M:%S')..' ['..kind..'] '..text
        A.logs[#A.logs+1]=line; if #A.logs>150 then table.remove(A.logs,1) end
        print('[Anime Suite] '..line)
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
        s.priority=Core.priorities(s.priority)
        for _,k in ipairs({'distance','towerBankFloor'}) do
            local n=tonumber(s[k]); s[k]=(n and n==n and n<math.huge) and math.max(0,n) or A.defaults[k]
        end
        s.distance=math.clamp(s.distance,2,20)
        if not Core.contains({'Nearest','Highest HP','Lowest HP'},s.target) then s.target='Nearest' end
        if not Core.contains({'Walk','Teleport'},s.moveStyle) then s.moveStyle='Walk' end
        for _,k in ipairs({'treeSelection','evolutionSelection','specialSelection','progressionSelection','webhookEvents','pingEvents'}) do
            for id,v in pairs(s[k]) do if type(id)~='string' or type(v)~='boolean' then s[k][id]=nil end end
        end
        local order={}
        for _,v in ipairs(s.modePriority) do
            if Core.contains({'Tower','TimeTrial'},v) and not Core.contains(order,v) then order[#order+1]=v end
        end
        for _,v in ipairs({'Tower','TimeTrial'}) do if not Core.contains(order,v) then order[#order+1]=v end end
        for world,selection in pairs(s.mobsByWorld) do
            if type(world)~='string' or type(selection)~='table' then s.mobsByWorld[world]=nil else
                for id,value in pairs(selection) do if type(id)~='string' or type(value)~='boolean' then selection[id]=nil end end
            end
        end
        for _,key in ipairs({'trialTarget','towerTarget'}) do
            if not Core.contains({'Nearest','Highest HP','Lowest HP'},s[key]) then s[key]='Nearest' end
        end
        if not Core.contains({'Damage','Power','Yen','XP','Drop','Luck','CritChance','CritDamage','ShinyChance','Kill'},s.loadoutStat) then s.loadoutStat='Damage' end
        s.modePriority=order; s.version=2; return s
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
    A.inflight={}
    function A.invoke(name,...)
        if not A.alive or not A.running then return false,'Automation paused' end
        local f=A.Library.Network.Functions:FindFirstChild(name)
        if not f or not f:IsA('RemoteFunction') then return false,'Unavailable: '..name end
        if A.inflight[name] then return false,'Request already in flight: '..name end
        local args=table.pack(...); local result
        A.inflight[name]=true
        task.spawn(function()
            result=table.pack(pcall(f.InvokeServer,f,table.unpack(args,1,args.n)))
            A.inflight[name]=nil
        end)
        local deadline=os.clock()+10
        while A.alive and not result and os.clock()<deadline do task.wait(0.05) end
        if not result then A.spendPaused=true; return false,'Timeout; spending paused until Resume spending' end
        return table.unpack(result,1,result.n)
    end
    function A.request(event,resultEvent,...)
        local b=A.bridge(resultEvent); if not b then return false,'Missing response '..resultEvent end
        local sentArgs=table.pack(...)
        local response; local connection=b:Connect(function(accepted,reason,payload,...)
            if accepted==true and type(payload)=='table' then
                if event=='NameRenameRequest' and payload.UniqueId~=sentArgs[1].UniqueId then return end
                if event=='EvolutionRequest' and payload.EvolutionKey~=sentArgs[1] then return end
                if event=='ProgressionUpgrade' and payload.ProgressionKey~=sentArgs[1] then return end
                if event=='Upgrades2Request' and payload.SystemKey~=sentArgs[1] then return end
                if event=='GachaRoll' and payload.GachaKey~=sentArgs[1][1]
                    and not (payload.Gachas and payload.Gachas[sentArgs[1][1]]) then return end
            end
            response=table.pack(accepted,reason,payload,...)
        end)
        A.connections[#A.connections+1]=connection
        local ok=A.fire(event,...); local deadline=os.clock()+(event=='NameRenameRequest' and 20 or 10)
        while ok and A.alive and not response and os.clock()<deadline do task.wait(0.05) end
        connection:Disconnect()
        for i=#A.connections,1,-1 do if A.connections[i]==connection then table.remove(A.connections,i); break end end
        if not ok then return false,'Send failed' end
        if not response then
            A.spendPaused=true
            return false,'Response timeout' 
        end
        return true,table.unpack(response,1,response.n)
    end
    function A.job(name,interval,fn,always)
        A.tasks[name]={name=name,interval=interval,fn=fn,always=always,next=0,busy=false,failures=0}
    end
    function A.setRunning(value)
        A.running=value; A.epoch=A.epoch+1
        A.status.Gameplay=value and 'Ready: each feature uses its own toggle' or 'Stopped or disconnected; rerun after reconnecting'
        if not value then
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
        or (type(syn)=='table' and syn.request)
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
        if not s.webhook or (not force and s.webhookEvents[kind]==false) then return end
        if kind=='Disconnect' and not s.sendDisconnect then return end
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
        if attachment and not saved then return end
        return A.outbox[#A.outbox]
    end
    A.job('Webhook delivery',1,function()
        if not A.alive or not A.settings.webhook or #A.outbox==0 or os.clock()<A.webhookNext or transport.busy then return end
        local entry=A.outbox[1]
        if type(entry)~='table' or type(entry.message)~='string' or entry.target~=fingerprint(A.settings.webhookURL) then
            table.remove(A.outbox,1); persist(); return
        end
        local payload={content=entry.ping and ('<@'..entry.ping..'>') or '',
            allowed_mentions={parse={},users=entry.ping and {entry.ping} or {}},
            embeds={{title='Anime Suite / '..tostring(entry.kind),description=entry.message,
                footer={text='Place '..tostring(game.PlaceId)..' | event '..tostring(entry.time)}}}}
        local contentType='application/json'; local data=A.S.HTTP:JSONEncode(payload)
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
            if status==401 or status==403 or status==404 then A.settings.webhook=false end
        elseif entry.attempt>=8 and status~=429 then
            table.remove(A.outbox,1); A.status.Webhook='Failed after 8 attempts; event dropped'
        else
            A.webhookNext=os.clock()+delay; A.status.Webhook='Retry in '..math.ceil(delay)..'s (HTTP '..tostring(status)..')'
        end
        if action~='done' then
            local detail=type(response)=='table' and tostring(response.Body or ''):sub(1,500) or tostring(response):sub(1,500)
            A.status.Webhook=A.status.Webhook..' | '..detail
            A.log('Webhook',A.status.Webhook)
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
    A.catalog={worlds={},enemies={},trees={},evolutions={},specializations={},progressions={},modes={}}
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
        local tree=A.config('SkillTree'); cat.trees={}
        -- Catalogs are read-only here; copying every nested upgrade creates needless allocation.
        for key,value in pairs(tree and tree.List or {}) do cat.trees[key]=value end
        local treeRoot=A.Library.Config:FindFirstChild('SkillTree')
        if treeRoot then
            for _,child in ipairs(treeRoot:GetChildren()) do
                if child:IsA('ModuleScript') and not cat.trees[child.Name] then
                    local ok,new=pcall(require,child)
                    if ok and type(new)=='table' and type(new.Upgrades)=='table' then cat.trees[child.Name]=new end
                end
            end
        end
        local evo=A.config('EvolutionConfig'); cat.evolutions=evo and evo.Evolutions or {}
        local specs=A.config('Upgrades2Config'); cat.specializations=specs and specs:GetAllSystems() or {}
        local prog=A.config('ProgressionConfig'); cat.progressions=prog and prog.Progressions or {}
        for mode,info in pairs({Tower={'TowerConfig','GetAllTowers'},TimeTrial={'TimeTrialConfig','GetAllTrials'}}) do
            local cfg=A.config(info[1]); cat.modes[mode]=cfg and cfg[info[2]] and cfg[info[2]](cfg) or {}
        end
        if A.settings.towerKey=='' then
            local keys=C.keys(cat.modes.Tower)
            if #keys==1 then A.settings.towerKey=tostring(keys[1]) end
        end
        A.status.Discovery=string.format('%d worlds / %d enemies / %d trees',#C.keys(cat.worlds),#C.keys(cat.enemies),#C.keys(cat.trees))
        if A.refreshUI then A.refreshUI() end
    end
    A.discover()
    A.job('Discovery',30,function()
        for _,key in ipairs({'farm','autoQuest','sideQuest','globalQuest','promotionTasks','buyWorlds',
            'trees','evolutions','specializations','progression','towerJoin','towerFarm','trialJoin','trialFarm'}) do
            if A.settings[key] then A.discover(); return end
        end
    end)
    A.on('WorldChanged',function(id) A.status.World=tostring(id) end)
end

end)()(A);

-- ===== spending =====
(function()
return function(A)
    local C=A.Core
    A.treeCursor=1; A.treeLast=''; A.blockedNodes={}; A.unknownStats={}; A.specState={}
    A.sessionNamed={}; A.spendCursor=1
    local function result(label,ok,accepted,reason)
        if not ok or accepted==false then
            A.status.Spending=label..': '..tostring(reason or accepted)
            return false
        end
        A.status.Spending=label..' accepted'; return true
    end
    local function treeStep()
        if not A.settings.trees then return false end
        local d=A.data(); local order=C.copy(A.settings.priority); local trees={}
        for key,tree in pairs(A.catalog.trees) do
            if A.settings.treeSelection[key]~=false then trees[key]=tree end
            for _,node in pairs(tree.Upgrades or {}) do
                local stat=C.stat(node,A.settings.priority)
                if not C.contains(order,stat) and not C.contains(A.unknownStats,stat) then
                    table.insert(A.unknownStats,math.random(#A.unknownStats+1),stat)
                end
            end
        end
        for _,stat in ipairs(A.unknownStats) do order[#order+1]=stat end
        local candidates=C.treeCandidates(trees,d,A.balance,A.number,order,A.unlocked,
            function(k) return (A.blockedNodes[k] or 0)>os.clock() end)
        local chosen,nextCursor=C.pick(candidates,order,A.treeCursor,A.treeLast)
        if not chosen then A.status.Trees='Waiting for eligible, affordable nodes'; return false end
        local ok,accepted,reason=A.invoke('UnlockSkillTreeUpgrade',chosen.tree,chosen.key)
        if result(chosen.tree..' / '..chosen.key,ok,accepted,reason) then
            A.treeCursor=nextCursor; A.treeLast=chosen.tree
            A.blockedNodes[chosen.tree..'/'..chosen.key]=os.clock()+15
            A.status.Trees='Bought '..chosen.stat..': '..chosen.key
        else A.blockedNodes[chosen.tree..'/'..chosen.key]=os.clock()+30 end
        return true
    end
    local function evolveStep()
        if not A.settings.evolutions then return false end
        local cfg=A.config('EvolutionConfig'); local d=A.data()
        for _,key in ipairs(C.keys(A.catalog.evolutions)) do
            local item=A.catalog.evolutions[key]
            if A.settings.evolutionSelection[key]~=false then
                local level=cfg:GetLevel(d,key); local cost=cfg:GetCost(key,level)
                if cost and A.balance(item.Cost.ItemId)>=cost and A.ready('evo:'..key,8) then
                    result('Evolution '..key,A.request('EvolutionRequest','EvolutionResult',key)); return true
                end
            end
        end
        return false
    end
    local function applySpec(payload)
        if type(payload)~='table' then return end
        local function apply(key,sys)
            if type(key)~='string' or type(sys)~='table' then return end
            A.specState[key]=A.specState[key] or {}
            for _,row in ipairs(sys.Upgrades or {}) do
                if type(row)=='table' and type(row.Multiplier)=='string' then
                    local prior=A.specState[key][row.Multiplier]
                    local copy=sys.KillProgress==true and C.copy(prior or {}) or {}
                    for field,value in pairs(row) do copy[field]=C.copy(value) end
                    A.specState[key][row.Multiplier]=copy
                end
            end
        end
        if type(payload.Systems)=='table' then
            for key,sys in pairs(payload.Systems) do apply(key,sys) end
        elseif payload.SystemKey then apply(payload.SystemKey,payload) end
        A.specReceived=os.clock()
    end
    A.on('Upgrades2Data',applySpec); A.on('Upgrades2Updated',applySpec)
    A.on('Upgrades2Result',function(_,_,payload) applySpec(payload) end)
    local function specStep()
        if not A.settings.specializations then return false end
        if A.ready('specializationData',5) then A.fire('Upgrades2Data') end
        if not A.specReceived then A.status.Specializations='Waiting for Upgrades2Data response'; return false end
        local selected,eligible=0,0
        for _,sys in ipairs(C.keys(A.specState)) do
            for _,key in ipairs(C.keys(A.specState[sys])) do
                local row=A.specState[sys][key]
                if A.settings.specialSelection[sys..'/'..key]~=false then
                    selected=selected+1
                    if row.CanUpgrade==true then eligible=eligible+1 end
                    if row.CanUpgrade==true and A.ready('spec:'..sys..'/'..key,5) then
                        A.status.Specializations='Requesting '..sys..' / '..key
                        local ok,accepted,reason=A.request('Upgrades2Request','Upgrades2Result',sys,key)
                        result('Specialization '..key,ok,accepted,reason)
                        A.status.Specializations=accepted==true and ok and ('Upgraded '..sys..' / '..key)
                            or ('Upgrade failed: '..tostring(reason or accepted))
                        A.fire('Upgrades2Data')
                        return true
                    end
                end
            end
        end
        A.status.Specializations=selected==0 and 'No selected upgrades in received state'
            or eligible>0 and 'Waiting for upgrade cooldown'
            or 'Server reports no selected upgrade ready (requirements / max level)'
        return false
    end
    local function renameStep()
        if not A.settings.rename then return false end
        if A.S.UIS:GetFocusedTextBox() then A.status.Rename='Finish editing before naming pets'; return false end
        local cfg=A.config('NamedConfig'); local stats=A.util('PetStatsUtil'); local d=A.data()
        if not cfg or not stats or type(stats.GetRarity)~='function' then
            A.status.Rename='Naming configuration unavailable'; return false
        end
        if cfg.WorldId and not A.unlocked(cfg.WorldId) then
            A.status.Rename='Unlock naming world '..tostring(cfg.WorldId)..' first'; return false
        end
        local name=cfg:Normalize(A.settings.petName)
        local valid,reason=cfg:Validate(name)
        if not valid then A.status.Rename=cfg:GetErrorMessage(reason); return false end
        local eligible=0
        for _,id in ipairs(C.keys(d.Pets)) do
            local pet=d.Pets[id]
            if not A.sessionNamed[id] and C.renameEligible(id,pet,d.NamedPets or {},name,stats) then
                eligible=eligible+1
                local cost=cfg:GetCost('Pet','Astral')
                local balance=A.balance(cfg.ItemId)
                if type(cost)~='number' or cost<0 then A.status.Rename='Naming cost unavailable'; return false end
                if balance<cost then
                    A.status.Rename=string.format('Need %s %s per Astral; have %s',tostring(cost),cfg.ItemId,tostring(balance))
                    return false
                end
                if A.ready('rename:'..id,20) then
                    local ok,accepted,why,payload=A.request('NameRenameRequest','NameRenameResult',{Kind='Pet',UniqueId=id,Name=name})
                    if ok and accepted==true and type(payload)=='table' and payload.UniqueId==id then
                        A.sessionNamed[id]=true
                        A.status.Rename='Named Astral: '..tostring(payload.Name or name)
                    else
                        A.status.Rename='Rename failed: '..tostring(why or accepted or 'unconfirmed response')
                        A.log('Rename',A.status.Rename)
                    end
                    return true
                end
            end
        end
        A.status.Rename=eligible>0 and 'Waiting for Astral rename retry cooldown' or 'No eligible unnamed Astral pets'
        return false
    end
    local function worldStep()
        if not A.settings.buyWorlds then return false end
        local ids=C.keys(A.catalog.worlds); table.sort(ids,function(a,b) return tonumber(a)<tonumber(b) end)
        for _,id in ipairs(ids) do
            local w=A.catalog.worlds[id]
            if not A.unlocked(id) then
                if A.balance('WorldToken')>=A.number(w.Price or 1) and A.ready('buyworld:'..id,20) then
                    A.fire('BuyWorld',tonumber(id)); A.status.Spending='Requested unlock: '..w.Name; return true
                end
                return false
            end
        end
        return false
    end
    local function progressionStep()
        if not A.settings.progression then return false end
        local d=A.data()
        for _,key in ipairs(C.keys(A.catalog.progressions)) do
            local cfg=A.catalog.progressions[key]
            local entry=(d.ActiveProgressions or {})[key]
            local level=type(entry)=='table' and tonumber(entry.Level) or tonumber(entry) or 0
            local worldConfig=A.config('WorldConfig')
            local requiredWorld=worldConfig and worldConfig.GetWorldBySystemKey and worldConfig:GetWorldBySystemKey('Progression',key)
            if A.settings.progressionSelection[key]~=false and not (d.AutoProgressions or {})[key] and level<(cfg.MaxLevel or 0)
                and (not requiredWorld or tostring(A.currentWorld())==tostring(requiredWorld))
                and cfg.ItemCost and A.balance(cfg.ItemCost.ItemId)>=A.number(cfg.ItemCost.Amount)
                and A.ready('progression:'..key,5) then
                result('Progression '..key,A.request('ProgressionUpgrade','ProgressionResult',key)); return true
            end
        end
        return false
    end
    function A.rollGacha(key)
        local cfg=A.config('GachaConfig'); local g=cfg and cfg.Gachas[key]
        if not g or not g.ItemCost or A.balance(g.ItemCost.ItemId)<A.number(g.ItemCost.Amount) then return false end
        if not A.ready('gacha:'..key,4) then return false end
        result('Gacha '..key,A.request('GachaRoll','GachaResult',{key})); return true
    end
    local function gachaStep()
        local key=A.objectiveGacha or (A.settings.gacha and A.settings.gachaKey)
        return key and key~='' and A.rollGacha(key) or false
    end
    local function eggStep()
        local key=A.objectiveEgg or (A.settings.eggs and A.settings.eggKey)
        if not key or key=='' then return false end
        local d=A.data(); local cfg=A.config('EggsData'); local egg=cfg and cfg[key]
        if not egg then return false end
        local native=A.client('PetRollController')
        if native and native.IsAutoOpening and native:IsAutoOpening() then A.status.Eggs='Game auto-open is already active'; return false end
        if #C.keys(d.Pets)>=(tonumber(d.MaxPets) or 75) then
            A.status.Eggs='Inventory full; paused opening'
            if A.ready('fullNotify',300) then A.notify('Inventory','Pet inventory is full. Egg opening paused.') end
            return false
        end
        if A.balance('Yen')<A.number(egg.Price) or not A.ready('egg:'..key,5) then return false end
        -- Empty auto-actions deliberately avoid deleting or locking pets.
        A.fire('OpenEgg',key,{}); A.status.Eggs='Requested egg '..key; return true
    end
    local workers={treeStep,evolveStep,specStep,renameStep,worldStep,progressionStep,gachaStep,eggStep}
    local names={'Trees','Evolution','Specializations','Rename','World unlock','Progression','Gacha','Eggs'}
    local retryAt={}
    A.job('Spending',2,function()
        local blocked=not A.data() and 'Waiting for player data'
            or A.spendPaused and 'A request timed out. Check its result, then use Upgrades: Resume spending after a timeout'
            or A.pendingMode and 'Waiting for mode entry to finish'
        if blocked then
            A.status.Spending=blocked
            if A.settings.rename then A.status.Rename=blocked end
            return
        end
        -- All spenders share this single non-overlapping worker.
        for offset=0,#workers-1 do
            local i=(A.spendCursor+offset-1)%#workers+1
            if (retryAt[i] or 0)<=os.clock() then
                local ok,worked=pcall(workers[i])
                if not ok then
                    retryAt[i]=os.clock()+30
                    A.status[names[i]]='Error: '..tostring(worked)
                    A.log(names[i],worked)
                elseif worked then A.spendCursor=i%#workers+1; return end
                -- An uncertain purchase still blocks further spending until explicitly resumed.
                if A.spendPaused or not A.alive or not A.running then return end
            end
        end
    end)
end

end)()(A);

-- ===== farming =====
(function()
return function(A)
    local C=A.Core
    A.activeMode=nil; A.modeState={}; A.pendingMode=nil; A.modeEnded={}
    A.modeMeta={Tower={prefix='tower',folder='TowerArenas'},TimeTrial={prefix='trial',folder='TimeTrialArenas'},
        Raid={folder='RaidArenas'},Defense={folder='DefenseArenas'},
        Dungeon={folder='DungeonArenas'},BossRush={folder='BossRushArenas'},NinjaExam={folder='NinjaExamArenas'}}
    for mode in pairs(A.modeMeta) do
        A.on(mode..'MapReady',function(key)
            A.activeMode=mode; A.activeArena=type(key)=='string' and key or nil
            A.pendingMode=nil
            if mode=='Tower' then A.status['Tower request']='Server confirmed tower map ready'; A.log('Tower',A.status['Tower request']) end
            A.notify('Mode',mode..' map ready')
        end)
        A.on(mode..'State',function(payload)
            local wire=A.util('GamemodeStateWireUtil')
            local state=wire and wire.Merge(mode..'State',payload) or payload
            if type(state)~='table' then return end
            if state.Refused then
                A.status.Mode=mode..': '..tostring(state.Refused); A.pendingMode=nil
                if mode=='Tower' then A.status['Tower request']='Server rejected: '..tostring(state.Refused); A.log('Tower',A.status['Tower request']) end
                A.cooldowns['join:'..mode]=os.clock()+30; return
            end
            A.modeState[mode]=state
            local arena=state.InstanceKey or state.TrialKey
            if arena and A.modeEnded[mode]~=arena then
                A.activeMode=mode; A.activeArena=arena; A.pendingMode=nil
                if mode=='Tower' then A.status['Tower request']='Server state: '..tostring(state.Phase or 'active') end
            end
        end)
        A.on(mode..'Ended',function(payload)
            A.modeEnded[mode]=type(payload)=='table' and payload.InstanceKey or nil
            if A.activeMode==mode then A.activeMode=nil; A.activeArena=nil end
            A.modeState[mode]=nil; A.pendingMode=nil
            A.cooldowns['join:'..mode]=os.clock()+10
            A.notify('Mode',mode..' ended')
        end)
    end
    function A.inMode()
        local ctrl=A.client('TeleportController')
        return A.activeMode~=nil or (ctrl and ctrl:IsInGamemode()) or false
    end
    function A.travel(world)
        if not world or tostring(A.currentWorld())==tostring(world) then A.worldTransition=nil; return true end
        A.worldTransition=world
        A.watchTarget(nil)
        if A.rangeOwned then A.fire('RangeToggle',false); A.rangeOwned=false end
        if A.inMode() or A.pendingMode then return false end
        if not A.unlocked(world) then A.status.Farm='World locked: '..tostring(world); return false end
        local ctrl=A.client('TeleportController')
        if ctrl and ctrl.IsLoading and ctrl:IsLoading() then return false end
        if A.ready('travel',5) then A.fire('RequestChangeWorld',tonumber(world)) end
        return false
    end
    local function resolveEnemy(name)
        for key,e in pairs(A.catalog.enemies) do
            if key==name or e.Name==name or e.ModelName==name then return key,e end
        end
    end
    function A.objectiveFrom(raw)
        local kind=raw.Type
        if kind=='PlayerLevel' or kind=='PlayerRank' then
            local world=A.unlocked(A.settings.world) and A.settings.world or A.currentWorld()
            return {world=world,mob='*',rank=kind=='PlayerRank',label=kind=='PlayerRank' and 'Train and rank up' or 'Farm experience'}
        elseif kind=='Defeat' then
            if raw.Mob=='*' then return {world=A.currentWorld(),mob='*',label='Defeat enemies'} end
            local id,e=resolveEnemy(raw.Mob)
            if e and A.unlocked(e.World) then return {world=e.World,mob=id,label='Defeat '..(e.Name or id)} end
        elseif kind=='GachaRoll' then
            local key=raw.Gacha or raw.GachaKey or raw.Key
            local config=A.config('GachaConfig'); local g=config and config.Gachas[key]
            if g and g.ItemCost and A.balance(g.ItemCost.ItemId)>=A.number(g.ItemCost.Amount) then
                return {gacha=key,label='Roll '..key}
            end
        elseif kind=='PetSummon' then
            local key=raw.World or raw.Egg
            local egg=(A.config('EggsData') or {})[key]
            if egg and A.balance('Yen')>=A.number(egg.Price) then return {egg=key,label='Open '..key} end

        end
        return nil
    end
    function A.questPlan()
        local s,d=A.settings,A.data(); if not d then return nil end
        A.objectiveGacha=nil; A.objectiveEgg=nil; A.objectiveRank=nil
        if s.globalQuest then
            local util=A.util('GlobalQuestStateUtil'); local cfg=A.config('GlobalQuestConfig')
            local state=util and util.BuildState(d)
            if state and state.Unlocked then
                for _,row in ipairs(state.Quests or {}) do
                    if row.Pinned and not row.Claimed and not row.Complete and not row.Locked then
                        local raw=cfg:GetAll()[row.Index]; local plan=raw and A.objectiveFrom(raw)
                        if plan then plan.label='Pinned global: '..plan.label; return plan end
                    end
                end
            end
        end
        if s.promotionTasks then
            local util=A.util('PromotionRankStateUtil'); local cfg=A.config('PromotionRankConfig')
            local state=util and util.BuildState(d)
            if state then
                local missions=cfg:GetMissions(d.PromotionRank or 0)
                for _,row in ipairs(state.Missions or {}) do
                    if not row.Complete then
                        local raw=missions[row.Index]; local plan=raw and A.objectiveFrom(raw)
                        if plan then plan.label='Promotion: '..plan.label; return plan end
                    end
                end
            end
        end
        if s.autoQuest then
            local cfg=A.config('QuestConfig')
            local state=cfg and cfg:BuildState(d.QuestIndex or 1,d.QuestProgress or {})
            if state and state.HasQuest then
                if state.Complete then
                    if A.ready('questCollect',5) then A.fire('QuestCollect') end
                else
                    for _,row in ipairs(state.Requirements or {}) do
                        if row.Current<row.Required then
                            local _,enemy=resolveEnemy(row.EnemyId)
                            if enemy and A.unlocked(enemy.World) then
                                return {world=enemy.World,mob=row.EnemyId,label=state.QuestName}
                            end
                        end
                    end
                end
            end
        end
        if s.sideQuest then
            local cfg=A.config('SideQuestConfig')
            for _,key in ipairs(C.keys(cfg and cfg.Quests)) do
                local q=cfg.Quests[key]; local progress=(d.SideQuests or {})[key] or {}
                if not progress.Claimed and A.unlocked(q.World) then
                    if not progress.Accepted or A.number((progress.Progress or {})[q.EnemyId])>=(q.RequiredKills or 0) then
                        if A.ready('sideQuest:'..key,15) then A.fire('SideQuestAcceptRequest',key) end
                    end
                    return {world=q.World,mob=q.EnemyId,label=q.Title}
                end
            end
        end
        return nil
    end
    function A.modeAvailable(mode,key)
        local cfg=(A.catalog.modes[mode] or {})[key]
        if not cfg then return false,'Select a '..mode..' first' end
        if cfg.WorldId and not A.unlocked(cfg.WorldId) then return false,'Unlock world '..tostring(cfg.WorldId) end
        if cfg.GateOnly then return false,'Gate-only entry' end
        if mode=='Tower' then
            local util=A.util('TowerStateUtil')
            local remaining=util and util.GetCooldownEndsAt(A.data(),cfg)-os.time() or 0
            if remaining>0 then return false,'Tower cooldown: '..math.ceil(remaining)..'s' end
        end
        local cost=cfg.Cost or cfg.ItemCost
        if type(cost)=='table' and cost.ItemId and A.balance(cost.ItemId)<A.number(cost.Amount) then return false,'Insufficient '..cost.ItemId end
        return true
    end
    function A.join(mode,key)
        if mode~='Tower' and mode~='TimeTrial' then return false end
        if not A.running then A.status.Mode='Script stopped or disconnected'; return false end
        if A.pendingMode or A.inMode() then A.status.Mode='Waiting for the current mode or entry request'; return false end
        local available,reason=A.modeAvailable(mode,key)
        if not available then A.status.Mode=reason; return false end
        local cfg=A.catalog.modes[mode][key]
        local cost=cfg.Cost or cfg.ItemCost
        local paidEntry=type(cost)=='table' and cost.ItemId and A.number(cost.Amount)>0
        -- A free tower does not depend on the purchasing worker or its timeout recovery.
        local spending=A.tasks.Spending
        if paidEntry and A.spendPaused then A.status.Mode='Spending paused; paid entry is waiting'; return false end
        if paidEntry and spending and spending.busy then A.status.Mode='Waiting for the current upgrade request'; return false end
        if not A.ready('join:'..mode,20) then A.status.Mode='Waiting before retrying entry'; return false end
        A.pendingMode={mode=mode,key=key,untilTime=os.clock()+20}
        if mode=='Tower' then
            -- This is the station's OPEN request. Joining another owner uses Action='Join' + InstanceKey.
            A.status['Tower request']='Sending own-tower request: '..key
            if not A.fire('TowerJoin',{TowerKey=key}) then
                A.pendingMode=nil; A.status.Mode='Tower open request failed to send'
                A.status['Tower request']=A.status.Mode; A.log('Tower',A.status.Mode); return false
            end
            if A.pendingMode then A.status['Tower request']='Sent TowerJoin {TowerKey='..key..'}; waiting for server' end
            A.log('Tower',A.status['Tower request'])
        elseif mode=='TimeTrial' then
            local ctrl=A.client('TimeTrialController')
            if ctrl and ctrl.OnEnter then ctrl:OnEnter(key) else A.fire('TimeTrialJoin','Join',key) end
        end
        A.status.Mode=(mode=='Tower' and 'Opening your own tower: ' or 'Entering trial: ')..key; return true
    end
    local function towerLanding()
        local state=A.modeState.Tower
        if not state or state.Phase~='Landing' or state.Decided then return end
        if not A.ready('towerLanding',3) then return end
        local options=state.Options or {}; local pick=options[1]
        local rune=A.config('RuneConfig')
        for _,stat in ipairs(A.settings.priority) do
            for _,key in ipairs(options) do
                local item=rune and rune:GetAttribute(key)
                if key==stat or (item and (item.Multiplier==stat or item.Stat==stat)) then pick=key; break end
            end
            if pick and pick~=options[1] then break end
        end
        if pick then A.fire('TowerLandingChoice',{Action='pick',Sigil=pick}) end
        local floor=tonumber(state.Floor) or 0
        A.fire('TowerLandingChoice',{Action=floor>=A.settings.towerBankFloor and 'bank' or 'climb'})
    end
    A.plan=nil
    function A.replan()
        A.plan=(A.chestPlan and A.chestPlan()) or A.questPlan()
        local p=A.plan or {}
        A.objectiveGacha=p.gacha; A.objectiveEgg=p.egg; A.objectiveRank=p.rank
        A.status.Objective=p.label or 'Waiting for an affordable supported objective, or using selected mobs'
    end
    A.job('Objectives',2,function()
        if not A.data() then return end
        A.replan()
        if A.pendingMode and os.clock()>A.pendingMode.untilTime then
            A.status.Mode='Entry request timed out: '..A.pendingMode.key; A.log('Mode',A.status.Mode)
            if A.pendingMode.mode=='Tower' then A.status['Tower request']='Request sent; no confirming server response within 20 seconds' end
            A.pendingMode=nil
        end
        if A.pendingMode then return end
        if A.activeMode=='Tower' and A.settings.towerFarm then towerLanding() end
        local wanted,key,blocked
        for _,mode in ipairs(A.settings.modePriority) do
            local prefix=A.modeMeta[mode].prefix
            local selected=A.settings[prefix..'Key']
            if A.settings[prefix..'Join'] then
                local available,reason=A.modeAvailable(mode,selected)
                if available then wanted=mode; key=selected; break end
                blocked=blocked or reason
            end
        end
        if not wanted then if blocked then A.status.Mode=blocked end; return end
        if A.inMode() then
            if A.activeMode and A.activeMode~=wanted then
                local prefix=A.modeMeta[wanted].prefix
                if A.settings[prefix..'LeaveOther'] and A.ready('leaveMode',15) then
                    A.fire(A.activeMode..'Leave'); A.status.Mode='Waiting to leave '..A.activeMode
                end
            end
            return
        end
        A.join(wanted,key)
    end)
    function A.findEnemies(world,mode)
        local folders={}
        if mode then
            local root=workspace:FindFirstChild(A.modeMeta[mode].folder)
            if root then
                for _,arena in ipairs(root:GetChildren()) do
                    if not A.activeArena or arena.Name==A.activeArena then
                        local f=arena:FindFirstChild('Enemies'); if f then folders[#folders+1]=f end
                    end
                end
            end
        else
            local root=workspace:FindFirstChild('Worlds')
            local w=root and root:FindFirstChild(tostring(world))
            local f=w and w:FindFirstChild('Enemies'); if f then folders[#folders+1]=f end
        end
        local items={}; local char=A.player.Character; local hrp=char and char:FindFirstChild('HumanoidRootPart')
        if not hrp then return items end
        local ctrl=A.client('EnemyController'); local big=A.util('BigNum')
        local mob=A.plan and A.plan.mob or '*'
        for _,folder in ipairs(folders) do
            for _,enemy in ipairs(folder:GetChildren()) do
                local humanoid=enemy:FindFirstChildOfClass('Humanoid')
                local part=enemy:FindFirstChild('HumanoidRootPart')
                local id,info=resolveEnemy(enemy.Name)
                local selection=A.settings.mobsByWorld[tostring(world)] or {}
                local allowed=mode~=nil or (A.plan and A.plan.mob and (mob=='*' or mob==id or mob==enemy.Name))
                    or (not (A.plan and A.plan.mob) and (next(selection)==nil or selection[id]==true))
                local visible=not mode or not ctrl or ctrl:IsGamemodeEnemyVisibleLocally(enemy)
                if allowed and visible and part and humanoid and humanoid.Health>0
                    and enemy:GetAttribute('EnemyDead')~=true and enemy:GetAttribute('IsClientVisualClone')~=true
                    and not A.S.Players:GetPlayerFromCharacter(enemy) and (id or mode) then
                    local health=math.log10(math.max(humanoid.Health,1e-300))
                    local real=enemy:GetAttribute('HealthReal')
                    if real and big then local ok,v=pcall(function() return big.Log10(big.Decode(real)) end); if ok then health=v end end
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
        if not target then return end
        local function died()
            if not A.alive or not A.running then return end
            A.watchTarget(nil)
            task.defer(function()
                if A.alive and A.running and A.runJob then
                    A.replan()
                    A.runJob(A.tasks.Farm)
                end
            end)
        end
        local hum=target:FindFirstChildOfClass('Humanoid')
        if hum then A.targetConnections[#A.targetConnections+1]=hum.Died:Connect(died) end
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
        if A.plan and A.plan.chest then
            A.watchTarget(nil)
            if A.rangeOwned then A.fire('RangeToggle',false); A.rangeOwned=false end
            A.visitChest(A.plan,hum,hrp); return
        end
        local mode=A.activeMode; local enabled=A.settings.farm or (A.plan and A.plan.mob~=nil)
        local targetMode=A.settings.target
        if A.inMode() then
            if not mode then A.status.Farm='Waiting for active mode state'; return end
            local prefix=A.modeMeta[mode].prefix
            enabled=prefix and A.settings[prefix..'Farm']
            targetMode=(prefix and A.settings[prefix..'Target']) or targetMode
        end
        if not enabled or A.pendingMode then
            A.watchTarget(nil)
            if A.rangeOwned then A.fire('RangeToggle',false); A.rangeOwned=false; hum:Move(Vector3.zero) end
            return
        end
        if A.plan and (A.plan.gacha or A.plan.egg) then return end
        local world=A.plan and A.plan.world or A.settings.world
        if not mode and not A.travel(world) then return end
        local ctrl=A.client('TeleportController'); if ctrl and ctrl:IsLoading() then return end
        local items=A.findEnemies(world,mode)
        local chosen
        for _,item in ipairs(items) do if item.model==A.currentTarget then chosen=item; break end end
        chosen=chosen or C.chooseTarget(items,targetMode)
        if not chosen then A.watchTarget(nil); A.status.Farm='Waiting for a live matching enemy'; return end
        A.watchTarget(chosen.model)
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

-- ===== extras =====
(function()
return function(A)
    local C=A.Core
    A.job('Rewards and equipment',5,function()
        local s,d=A.settings,A.data(); if not d then return end
        if s.rank or A.objectiveRank then
            local cfg=A.config('RankConfig'); local nextRank=cfg and cfg.Ranks[(tonumber(d.Rank) or 0)+1]
            if nextRank and A.number(d.Power)>=A.number(nextRank.Requirement) and A.ready('rank',8) then A.fire('RankUp') end
        end
        if s.promote then
            local util=A.util('PromotionRankStateUtil'); local state=util and util.BuildState(d)
            if state and state.CanPromote and A.ready('promote',8) then A.fire('PromotionRankPromote') end
        end

        if s.claimQuest and A.ready('questCollect',5) then
            local cfg=A.config('QuestConfig'); local state=cfg and cfg:BuildState(d.QuestIndex or 1,d.QuestProgress or {})
            if state and state.Complete then A.fire('QuestCollect') end
        end
        if s.globalQuest and A.ready('globalClaims',15) then
            local util=A.util('GlobalQuestStateUtil'); local state=util and util.BuildState(d)
            for _,row in ipairs(state and state.Quests or {}) do
                if row.Pinned and row.Complete and not row.Claimed then A.fire('GlobalQuestClaim',row.Index); break end
            end
        end
        if s.bestLoadout then
            if A.ready('loadout',20) then A.fire('EquipBestLoadout',s.loadoutStat) end
            A.status.Equipment='Full loadout controls equipment; individual best options yield'
        else
            if s.bestPets and A.ready('petsBest',20) then A.fire('EquipBest') end
            if s.bestAvatar and A.ready('avatarBest',15) then
                local cfg=A.config('AvatarsData') or {}; local best,bestValue=nil,-1
                for key,owned in pairs(d.Avatars or {}) do
                    local item=cfg[key]
                    if owned and item and tonumber(item.Multiplier) and item.Multiplier>bestValue then
                        best=key; bestValue=item.Multiplier
                    end
                end
                if best and d.EquippedAvatarBuff~=best then A.fire('EquipAvatarBuff',best) end
            end
        end
        if s.achievements and A.ready('achievements',30) then A.fire('ClaimAllAchievements') end
        if s.rewards and A.ready('timeRewards',30) then
            A.invoke('ClaimAllTimeRewards')
            if A.running and A.alive then A.invoke('ClaimAllDailyRewards') end
        end
        if s.welcomeRewards and A.ready('welcomeRewards',60) then A.fire('ClaimWelcomeRewards') end
        if s.levelRewards then
            local cfg=A.config('LevelRewardsConfig')
            for _,reward in ipairs(cfg and cfg.Rewards or {}) do
                if (tonumber(d.Level) or 0)>=reward.Level and not (d.ClaimedLevelRewards or {})[tostring(reward.Level)]
                    and A.ready('levelReward:'..reward.Level,30) then
                    A.fire('ClaimLevelReward',reward.Level); break
                end
            end
        end
    end)
    A.lastChest={}; A.on('ChestState',function(payload)
        if type(payload)=='table' then for k,v in pairs(payload) do A.lastChest[k]=tonumber(v) or 0 end end
    end)
    function A.chestPlan()
        if not A.settings.chests or A.inMode() then return nil end
        local cfg=A.config('ChestConfig'); local d=A.data(); if not cfg or not d or not A.unlocked(cfg.WorldId) then return nil end
        for _,key in ipairs(C.keys(cfg.Chests)) do
            local chest=cfg.Chests[key]
            local last=math.max(A.number(d[chest.LastClaimKey]),A.lastChest[key] or 0)
            if last+chest.Cooldown<=workspace:GetServerTimeNow() and (A.cooldowns['chest:'..key] or 0)<=os.clock() then
                local eligible=true
                if chest.RequiresGroup then
                    if A.groupMember==nil then
                        local gameCfg=A.config('GameConfig'); local ok,v=pcall(A.player.IsInGroup,A.player,gameCfg.GroupId)
                        if ok then A.groupMember=v else eligible=false end
                    end
                    eligible=A.groupMember==true
                end
                if eligible then return {chest=key,world=cfg.WorldId,model=chest.ModelName,label='Claim '..key..' chest'} end
            end
        end
    end
    function A.visitChest(plan,hum,hrp)
        if not A.travel(plan.world) then return end
        local worlds=workspace:FindFirstChild('Worlds'); local w=worlds and worlds:FindFirstChild(tostring(plan.world))
        local map=w and w:FindFirstChild('Map'); local folder=map and (map:FindFirstChild('Chests') or map:FindFirstChild('Chest'))
        local model=folder and folder:FindFirstChild(plan.model)
        if not model then A.status.Farm='Waiting for chest map'; return end
        local position=model:IsA('Model') and model:GetPivot().Position or model:IsA('BasePart') and model.Position
        if not position then return end
        if (position-hrp.Position).Magnitude>6 then
            if A.settings.moveStyle=='Teleport' then hrp.CFrame=CFrame.new(position+Vector3.new(0,3,0)) else hum:MoveTo(position) end
        elseif A.ready('chest:'..plan.chest,60) then
            A.fire('ChestClaim',plan.chest); A.plan=nil
        end
    end
    local lastRank,lastPromotion
    A.job('Progress events',5,function()
        local d=A.data(); if not d then return end
        if lastRank and d.Rank~=lastRank then A.notify('Progress','Rank changed to '..tostring(d.Rank)) end
        if lastPromotion and d.PromotionRank~=lastPromotion then A.notify('Progress','Promotion changed to '..tostring(d.PromotionRank)) end
        lastRank=d.Rank; lastPromotion=d.PromotionRank
    end,true)
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
    local window=F:CreateWindow({Title='Anime Suite',SubTitle='3.1',TabWidth=touch and 92 or 150,
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
        A.touchGui=Instance.new('ScreenGui'); A.touchGui.Name='AnimeSuiteTouchControls'
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
        local suite=touchButton('SUITE',-122,function()
            if not suppressTap then window:Minimize() end
        end)
        suite.Size=UDim2.fromOffset(110,46); suite.Text='SUITE'; suite.TextSize=15
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
    for _,name in ipairs({'Farm','Quests','Modes','Upgrades','Pets','Rewards','Guild Tracker','Webhook','Settings'}) do
        tabs[name]=window:AddTab({Title=name,Icon=''})
    end
    local sync=true; local bindings={}; local statuses={}
    local function guard(fn)
        return function(...)
            if sync or not A.alive then return end
            local ok,why=pcall(fn,...)
            if not ok then A.log('UI',why); F:Notify({Title='Anime Suite',Content=tostring(why),Duration=6}) end
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
    local function optionsFrom(map)
        local out={}
        for _,key in ipairs(C.keys(map)) do
            local v=map[key]; local name=type(v)=='table' and (v.Name or v.DisplayName or v.Title) or key
            out[#out+1]={key=tostring(key),label=tostring(name or key)..' ['..tostring(key)..']'}
        end
        return out
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
            function(id) A.settings[key]=id; A.watchTarget(nil); A.refreshUI() end)
    end
    local function multi(tab,title,key,provider)
        dropdown(tab,title,key,provider,function(id) return A.settings[key][id]~=false end,function(selected)
            for id,value in pairs(selected) do A.settings[key][id]=value end
        end,true)
        button(tab,'Include all '..title:lower()..' / future entries',function() A.settings[key]={}; A.refreshUI() end)
    end
    local function priority(tab,title,key,values)
        for i=1,#values do
            dropdown(tab,title..' '..i,key..i,choices(values),function(id) return A.settings[key][i]==id end,function(id)
                local list=A.settings[key]
                for j,v in ipairs(list) do if v==id then list[j],list[i]=list[i],list[j]; break end end
                A.treeCursor=1; A.refreshUI()
            end)
        end
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
            if tostring(e.World)==A.settings.world then out[#out+1]={key=key,label=(e.Name or key)..' ['..key..']'} end
        end
        table.sort(out,function(a,b) return a.label<b.label end); return out
    end,function(id)
        local selected=A.settings.mobsByWorld[A.settings.world] or {}
        return next(selected)==nil or selected[id]==true
    end,function(selected)
        -- Explicit false values distinguish selecting none from the initial all-mobs setting.
        local saved=A.settings.mobsByWorld[A.settings.world] or {}
        for id,value in pairs(selected) do saved[id]=value end
        A.settings.mobsByWorld[A.settings.world]=saved; A.watchTarget(nil)
    end,true)
    button('Farm','Select all mobs / include future mobs in this world',function()
        A.settings.mobsByWorld[A.settings.world]={}; A.watchTarget(nil); A.refreshUI()
    end)
    choose('Farm','Target order','target',choices({'Nearest','Highest HP','Lowest HP'}))
    choose('Farm','Movement','moveStyle',choices({'Walk','Teleport'}))
    toggle('Farm','Auto farm selected mobs','farm'); toggle('Farm','Auto buy worlds (World Tokens)','buyWorlds')
    note('Farm','World handling','Joins through the normal world system before combat. Death triggers immediate retargeting. Selections are saved separately per world.')
    status('Farm','Farm'); status('Farm','Discovery')
    for _,row in ipairs({{'Auto world quests','autoQuest'},{'Auto side quests','sideQuest'},
        {'Auto pinned global quests','globalQuest'},{'Auto promotion objectives','promotionTasks'},
        {'Claim completed world quests','claimQuest'},{'Auto promote when eligible','promote'},{'Auto rank up','rank'}}) do
        toggle('Quests',row[1],row[2])
    end
    note('Quests','Objectives','Ready chests, pinned globals, promotion, world quests, side quests, then selected mobs. Defeat, level/rank, gacha and egg objectives are supported. Other objectives use normal play.')
    status('Quests','Objective')
    for _,mode in ipairs({'Tower','TimeTrial'}) do
        local prefix=A.modeMeta[mode].prefix
        choose('Modes',mode,prefix..'Key',function() return optionsFrom(A.catalog.modes[mode]) end)
        toggle('Modes',mode=='Tower' and 'Auto open MY OWN tower' or 'Auto join TimeTrial',prefix..'Join')
        toggle('Modes','Auto farm '..mode,prefix..'Farm')
        choose('Modes',mode..' target order',prefix..'Target',choices({'Nearest','Highest HP','Lowest HP'}))
        toggle('Modes','Leave another mode for '..mode,prefix..'LeaveOther')
    end
    button('Modes','Open my tower now',function() A.join('Tower',A.settings.towerKey) end)
    input('Modes','Tower: bank rune at floor','towerBankFloor',true)
    priority('Modes','Mode priority','modePriority',{'Tower','TimeTrial'})
    note('Modes','Coordination','Existing runs finish unless leave-another-mode is enabled. Leaving can abandon rewards. Normal entry costs and cooldowns apply.')
    status('Modes','Mode')
    status('Modes','Tower request')
    toggle('Upgrades','Auto skill trees','trees')
    multi('Upgrades','Skill trees','treeSelection',function() return optionsFrom(A.catalog.trees) end)
    priority('Upgrades','Stat priority','priority',{'Damage','Drop','Luck','Power','XP','Yen'})
    note('Upgrades','Fair upgrade order','Buys one affordable, unlocked node per stat turn, then moves to the next stat. Unknown stats use a shuffled order.')
    status('Upgrades','Trees')
    toggle('Upgrades','Auto evolutions','evolutions')
    multi('Upgrades','Evolutions','evolutionSelection',function() return optionsFrom(A.catalog.evolutions) end)
    toggle('Upgrades','Auto specializations / professions','specializations')
    status('Upgrades','Specializations')
    multi('Upgrades','Specializations','specialSelection',function()
        local out={}
        for _,key in ipairs(C.keys(A.catalog.specializations)) do
            local sys=A.catalog.specializations[key]
            for _,up in ipairs(sys.UpgradeList or {}) do
                out[#out+1]={key=key..'/'..up.Key,label=(sys.Name or key)..' - '..(up.DisplayName or up.Key)..' ['..key..'/'..up.Key..']'}
            end
        end
        return out
    end)
    toggle('Upgrades','Auto token progressions','progression')
    multi('Upgrades','Progressions','progressionSelection',function() return optionsFrom(A.catalog.progressions) end)
    button('Upgrades','Resume spending after a timeout',function()
        if next(A.inflight) then A.log('Spending','A request is still in flight; wait before resuming.')
        else A.spendPaused=false; A.log('Spending','Spending resumed.') end
    end)
    status('Upgrades','Spending')
    input('Pets','Name for unnamed Astral pets','petName')
    toggle('Pets','Auto rename Astral pets ONLY','rename')
    note('Pets','Astral naming','Only verified Astral rarity is eligible. Existing names, matching names and percentage pets are skipped. Uses the normal Magicule cost. Check the status below for blockers.')
    status('Pets','Rename')
    toggle('Pets','Auto equip best pets','bestPets'); toggle('Pets','Auto equip best avatar','bestAvatar')
    toggle('Pets','Auto equip best complete loadout','bestLoadout')
    choose('Pets','Loadout stat','loadoutStat',choices({'Damage','Power','Yen','XP','Drop','Luck','CritChance','CritDamage','ShinyChance','Kill'}))
    choose('Pets','Gacha','gachaKey',function() return optionsFrom((A.config('GachaConfig') or {}).Gachas) end)
    toggle('Pets','Auto selected gacha','gacha')
    choose('Pets','Egg','eggKey',function() return optionsFrom(A.config('EggsData')) end)
    toggle('Pets','Auto selected egg','eggs')
    note('Pets','Equipment and rolls','Complete loadout takes priority over separate equipment actions. Eggs pause at capacity and while native auto-open is active. No auto-delete actions are sent.')
    status('Pets','Eggs')
    for _,row in ipairs({{'Auto daily / group chests','chests'},{'Auto claim achievements','achievements'},
        {'Auto time and daily rewards','rewards'},{'Auto level rewards','levelRewards'},{'Auto welcome rewards','welcomeRewards'}}) do
        toggle('Rewards',row[1],row[2])
    end
    note('Rewards','Chests','Visits ready chests in their world and claims within range. Group chest requires existing membership.')
    button('Guild Tracker','Start Tracking',A.guildStart)
    button('Guild Tracker','Stop Tracking',A.guildStop)
    local guildSummary=note('Guild Tracker','Tracking status',A.guildSummary())
    statuses[#statuses+1]=function() guildSummary:SetDesc(A.guildSummary()) end

    input('Webhook','Webhook URL','webhookURL'); input('Webhook','Discord user ID','pingId')
    toggle('Webhook','Enable webhook','webhook'); toggle('Webhook','Send disconnect notification','sendDisconnect')
    toggle('Webhook','Ping selected user','ping')
    multi('Webhook','Events to send','webhookEvents',choices({'Disconnect','Mode','Progress','Error','Inventory'}))
    multi('Webhook','Events to ping','pingEvents',choices({'Disconnect','Mode','Progress','Error','Inventory'}))
    toggle('Webhook','Save webhook URL locally with settings','saveSecrets')
    button('Webhook','Send test notification',function() A.notify('Test','Webhook test from Anime Suite',true) end)
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
    note('Settings','Controls',touch and 'Tap SUITE to hide/show; drag it to reposition. Use each feature’s own toggle. RESTORE enables rendering. Landscape gives the menus more room.'
        or 'Right Shift: minimize/show Fluent. F8: restore rendering. Rendering starts enabled.')
    note('Settings','Executor capabilities',
        'Save/load: '..((type(writefile)=='function' and type(readfile)=='function' and type(makefolder)=='function') and 'available' or 'file APIs missing')
        ..' | Webhook HTTP: '..(A.httpRequest and 'available' or 'request API missing')
        ..'. Rendering availability is checked when you use it.')
    status('Settings','Settings')
    status('Settings','Gameplay')
    button('Settings','Refresh catalogs',function() A.discover(); A.refreshUI() end)
    button('Settings','Write diagnostics',function()
        assert(type(writefile)=='function','File API unavailable')
        pcall(makefolder,A.folder)
        local jobs,enabled={},{}
        for name,job in pairs(A.tasks) do jobs[name]={busy=job.busy,failures=job.failures,nextIn=math.max(0,job.next-os.clock())} end
        for key,value in pairs(A.settings) do if type(value)=='boolean' then enabled[key]=value end end
        writefile(A.folder..'/diagnostics.json',A.S.HTTP:JSONEncode({version='3.1',status=A.status,logs=A.logs,jobs=jobs,enabled=enabled,
            running=A.running,activeMode=A.activeMode,spendingPaused=A.spendPaused,
            worlds=#C.keys(A.catalog.worlds),enemies=#C.keys(A.catalog.enemies),trees=C.keys(A.catalog.trees)}))
        A.log('Diagnostics','Saved '..A.folder..'/diagnostics.json')
    end)
    button('Settings','Unload',A.stop); status('Settings','Rendering')
    A.overlay=Instance.new('ScreenGui'); A.overlay.Name='AnimeSuiteBlackScreen'
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
    warn("Anime Suite startup failed: " .. tostring(bootError))
end
