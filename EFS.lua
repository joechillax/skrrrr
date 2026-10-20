-- Egg Farm Automation 3.1.13 | Rayfield | Teleport-only | Place 122156343392096
local Core=(function()
-- Pure planning and transaction logic. Bundled into the canonical release by build.cjs.
local Core = {}
function Core.copy(x)
    if type(x) ~= "table" then return x end
    local y = {}; for k,v in pairs(x) do y[k]=Core.copy(v) end; return y
end
local NEG = -math.huge
function Core.log(x)
    if type(x)=="number" then return x>0 and math.log10(x) or NEG end
    return type(x)=="table" and type(x[1])=="number" and x[1]>0 and math.log10(x[1])+x[2] or NEG
end
function Core.add(a,b)
    if a<b then a,b=b,a end
    if a==NEG then return NEG end
    return a + (a-b>16 and 0 or math.log10(1+10^(b-a)))
end
function Core.sub(a,b)
    if a<=b then return NEG end
    return a + math.log10(1-10^(b-a))
end
function Core.bn(n)
    if n==NEG then return {0,0} end
    local e=math.floor(n); return {10^(n-e),e}
end
function Core.trainAmount(wanted)
    -- Numeric quantities exposed by the native L_Heroes selector. Custom
    -- prerequisite deltas and binary-search results are planning targets only.
    for _,amount in ipairs({10000,1000,100,25,10,1}) do
        if wanted>=amount then return amount end
    end
    return 0
end
local function ceilLog(n)
    if n==-math.huge or n>=15 then return n end
    local x=10^n;return Core.log(math.ceil(x-math.abs(x)*1e-14))
end
function Core.multiplierLog(id,level)
    if tonumber(id)==1 or level<200 then return 0 end
    local i=tonumber(id); local k=math.floor(level/25); local r=level%25
    local count=k-7; local base=i>=51 and 1000 or (i>=46 and 4.5 or 4)
    local result=count*math.log10(base)
    if i<46 then
        local tens=math.floor(math.min(k,math.floor((8000-r)/25))/40)
        result+=tens*math.log10(10/base)
    end
    if i>25 then
        local f=math.max(8,math.ceil((525-r)/25)); local t=math.min(k,math.floor((725-r)/25))
        result+=math.max(0,t-f+1)*math.log10(5/base)
    end
    return result
end
function Core.new(M)
    local B,H=M.BigNum,M.HeroesData
    local P={}
    function P.unlocked(d)
        local a={}
        for id,h in pairs(d.heroes or {}) do
            local def=H.Stats[id]
            if def then for k,enabled in pairs(h.upgrades or {}) do
                local u=enabled and def.Upgrades[tonumber(k)]
                if u and u.ability then a[tostring(u.ability)]=true end
            end end
        end
        return a
    end
    function P.cost(d,id,from,to)
        local base=H.Stats[id].BaseCost
        if id=="1" and from<16 then
            -- Native special-case iterates each level; callers split this small interval.
            return B.Mul(H.Cost(base,from,to,d.eastereggs["4"]),B.fromNum(M.GetVitalityDiscount(d)))
        end
        if id=="1" then base={2,1} end
        local growth=base[2]>=108000 and 1.22 or 1.07
        local v=B.Sub(Core.bn(to*math.log10(growth)),Core.bn(from*math.log10(growth)))
        v=B.Floor(B.Div(B.Mul(base,v),B.fromNum(growth-1)))
        v=B.Mul(v,{2,0})
        if d.eastereggs["4"] then v=B.Mul(v,B.fromNum(1+M.EggsData["4"].effect(d.eastereggs["4"]))) end
        return B.Mul(v,B.fromNum(M.GetVitalityDiscount(d)))
    end
    function P.maxLevels(d,id,from,budget,ceiling)
        local hi=1
        local limit=math.min(ceiling or 1e9,id=="1" and from<16 and 16-from or 1e9)
        while hi<limit and B.Compare(P.cost(d,id,from,from+hi),budget)~= ">" do
            hi=math.min(limit,hi*2)
        end
        local lo=0
        while lo<hi do
            local mid=math.floor((lo+hi+1)/2)
            if B.Compare(P.cost(d,id,from,from+mid),budget) ~= ">" then lo=mid else hi=mid-1 end
        end
        return lo
    end
    local function effect(cat,id,level,...)
        if not level or not cat[id] then return 0 end
        if cat==M.EggsData and id=="22" then
            -- The low-level export compares FormatMoney's string result to numbers.
            -- Reconstruct its bounded summation without that decompiler artifact.
            if B.Compare(level,{1.01,2})~="<" then return B.Add({2.04,1},B.Mul({1.5,-1},B.Sub(level,{1,2}))) end
            local n=math.floor(level[1]*10^level[2]+0.5);local sum=0
            for i=1,math.min(100,n) do sum+=0.25-math.floor(i/10)*0.01 end
            return B.fromNum(sum)
        end
        return cat[id].effect(level,...)
    end
    function P.output(d,s,gear)
        gear=gear or {}; local ee=d.eastereggs or {}; local pe=d.phoenixeggs or {}; local ae=d.ascensioneggs or {}
        local global,eggmod,clickmod,critmod,critchance=0,0,NEG,NEG,0
        local totals,hm={},{}
        for id,h in pairs(d.heroes or {}) do
            local def=H.Stats[id]
            if def and h.level>0 then
                local damage=Core.log(def.BaseDPS)+math.log10(h.level)+Core.multiplierLog(id,h.level)
                for k,enabled in pairs(h.upgrades or {}) do
                    local u=enabled and def.Upgrades[tonumber(k)]
                    if u then
                        if u.personalModifier then damage+=Core.log(u.personalModifier) end
                        if u.globalModifier then global+=Core.log(u.globalModifier) end
                        if u.eggModifier then eggmod+=Core.log(u.eggModifier) end
                        if u.clickModifier then clickmod=Core.add(clickmod,Core.log(u.clickModifier)) end
                        if u.criticalChance then critchance+=u.criticalChance end
                        if u.criticalModifier then critmod=Core.add(critmod,Core.log(u.criticalModifier)) end
                        if u.heroModifier then local x=u.heroModifier; hm[x.hero]=(hm[x.hero] or 0)+Core.log(x.modifier) end
                    end
                end
                local trophy=(d.inventory.trophies or {})[id]
                if trophy then
                    local bonus=Core.add(Core.log(M.TrophyBonus),Core.log(effect(M.EggsData,"20",ee["20"])))
                    damage+=Core.add(0,bonus+math.log10(trophy))
                end
                totals[id]=damage
            end
        end
        local dps=NEG
        for id,x in pairs(totals) do if id~="1" then dps=Core.add(dps,x+(hm[id] or 0)) end end
        local common=global+Core.add(Core.add(0,Core.log(d.blackeggs)-1),Core.log(effect(M.EggsData,"1",ee["1"])))
        if s.passes and s.passes["Double Damage"] then common+=math.log10(2) end
        local active=s.abilities or {}
        dps+=common+math.log10(1.05)*(d.exploits or 0)
        if active["2"] then dps+=Core.log(active["2"].effect) end
        if s.idle then dps+=Core.add(0,Core.log(effect(M.EggsData,"22",ee["22"]))) end
        if s.combo and s.combo.clicks>=3 then dps+=Core.add(0,Core.log(effect(M.EggsData,"21",ee["21"]))+math.log10(s.combo.clicks)) end
        local click=Core.add((totals["1"] or NEG)+common,dps+clickmod)
        click+=Core.add(0,Core.log(effect(M.EggsData,"12",ee["12"])))
        if active["7"] then click+=Core.log(active["7"].effect) end
        click=Core.add(click,s.passes and s.passes["Double Damage"] and math.log10(2) or 0)
        local shared=math.log10(1+effect(M.Eggs2Data,"2",pe["2"]))+math.log10(1+math.min(500,effect(M.Eggs3Data,"4",ae["4"])))
        dps+=shared; click+=shared
        local tier=gear.weaponTier or 0
        click+=math.log10(1+(M.WeaponCooldown[tier] or 0))
        dps=ceilLog(dps);click=ceilLog(click)
        critchance+=math.max(0,(gear.trailTier or 1)-1)*0.02
        if active["3"] then critchance+=active["3"].effect end
        local crit=Core.add(1,critmod)+Core.add(0,Core.log(effect(M.EggsData,"8",ee["8"])))
        local expected=Core.add(0,Core.sub(crit,0)+Core.log(math.clamp(critchance,0,1)))
        local cps=math.max(1,s.cps or 1)+(gear.wingsTier or 0)+(active["1"] and active["1"].effect or 0)+(s.passes and s.passes["Pet Chick"] and 2 or 0)
        local damageRate=Core.add(dps,click+math.log10(cps)+expected)
        local total=damageRate
        if active["4"] then eggmod+=Core.log(active["4"].effect) end
        eggmod+=math.log10(1+math.min(9,effect(M.Eggs3Data,"6",ae["6"])))
        eggmod+=Core.add(0,Core.log(effect(M.EggsData,"9",ee["9"])))
        eggmod+=math.log10(1+9*effect(M.EggsData,"5",ee["5"]))
        local unlocked=P.unlocked(d); local uptime=1
        for id in pairs(unlocked) do
            local def=M.AbilitiesData[id]
            if def and id~="8" and id~="9" then
                local durations={ ["1"]="14",["2"]="16",["3"]="17",["4"]="19",["5"]="18",["7"]="15" }
                local duration=30+100*effect(M.EggsData,durations[id],ee[durations[id]])
                local importance=({["1"]=10/cps,["2"]=1,["3"]=1,["4"]=1,["5"]=1,["6"]=0.05,["7"]=2})[id] or 0
                local cd=def.cooldown*(1-(gear.cooldownCoverage and gear.cooldownCoverage[id] or 0))
                uptime+=math.min(1,duration/math.max(1,cd))*importance
            end
        end
        total+=math.log10(uptime)
        local kills=math.max(2,M.GetChickensRequired(d)); local boss=M.GetBossHealth(d)
        local timer=M.GetBossTimer(d)
        local discount=(1+effect(M.EggsData,"4",ee["4"]))*M.GetVitalityDiscount(d)
        local utility=total+eggmod-math.log10(kills)*0.8-math.log10(boss)*0.2-math.log10(math.max(1e-12,discount))
        -- A longer boss window has value only while a heal is a real bottleneck.
        if d.level.current%5==0 then utility+=math.log10(timer)*0.2 end
        return utility,total,{dps=dps,click=click,cps=cps,expectedCrit=expected,damageRate=damageRate}
    end
    local combatEffects={ ["1"]=10,["2"]=2,["3"]=0.5,["7"]=3 }
    function P.damageRate(d,s,gear,clicking,unbuffed)
        local session=table.clone(s)
        session.abilities=table.clone(s.abilities or {})
        if unbuffed then for id in pairs(combatEffects) do session.abilities[id]=nil end end
        local _,_,stats=P.output(d,session,gear)
        -- No speculative ability uptime, egg income or purchase utility enters
        -- the boss calculation. Only passive DPS and real farm attack capacity.
        return Core.add(stats.dps,clicking and stats.click+math.log10(stats.cps)+stats.expectedCrit or NEG)
    end
    function P.killSeconds(hp,rate)
        if hp==NEG then return 0 end
        if rate==NEG then return math.huge end
        return 10^math.clamp(hp-rate,-12,300)
    end
    function P.bossPlan(d,s,gear,hp,window,clicking,ready,decoyActive)
        gear=gear or {};local coverage=gear.cooldownCoverage or {}
        window=math.min(30,window)
        local normal=P.damageRate(d,s,gear,clicking,true)
        local current=P.damageRate(d,s,gear,clicking,false)
        local plan={normalSeconds=P.killSeconds(hp,normal),currentSeconds=P.killSeconds(hp,current),window=window}
        if plan.normalSeconds<=window then plan.reason="easy";return plan end
        if plan.currentSeconds<=window then plan.reason="active-enough";return plan end
        if window<=0.5 then plan.reason="heal-imminent";return plan end
        local candidates={}
        for _,id in ipairs({"1","2","3","7"}) do if ready[id] then table.insert(candidates,id) end end
        local best
        local function evaluate(ids,boosted)
            local nextS=table.clone(s);nextS.abilities=table.clone(s.abilities or {})
            local cost=0
            for _,id in ipairs(ids) do
                nextS.abilities[id]={effect=combatEffects[id]*(id==boosted and 2 or 1)}
                cost+=M.AbilitiesData[id].cooldown*(1-(coverage[id] or 0))
            end
            local useDecoy=boosted~=nil and not decoyActive
            if useDecoy then cost+=M.AbilitiesData["8"].cooldown*(1-(coverage["8"] or 0)) end
            local seconds=P.killSeconds(hp,P.damageRate(d,nextS,gear,clicking,false))
            local actions=#ids+(useDecoy and 1 or 0)
            if seconds+actions*0.25<=window and (not best or cost<best.cost or cost==best.cost and actions<best.actions or cost==best.cost and actions==best.actions and seconds<best.seconds) then
                best={ids=table.clone(ids),boosted=boosted,useDecoy=useDecoy,cost=cost,seconds=seconds,actions=actions}
            end
        end
        for mask=1,2^#candidates-1 do
            local ids={}
            for index,id in ipairs(candidates) do if math.floor(mask/2^(index-1))%2==1 then table.insert(ids,id) end end
            if not decoyActive then evaluate(ids,nil) end
            if decoyActive or ready["8"] then for _,id in ipairs(ids) do evaluate(ids,id) end end
        end
        if not best then plan.reason="too-weak";return plan end
        best.first=best.boosted
        if not best.first then
            local firstRate=NEG
            for _,id in ipairs(best.ids) do
                local one=table.clone(s);one.abilities=table.clone(s.abilities or {});one.abilities[id]={effect=combatEffects[id]}
                local rate=P.damageRate(d,one,gear,clicking,false)
                if rate>firstRate then firstRate=rate;best.first=id end
            end
        end
        plan.reason="burst";plan.burst=best
        return plan
    end
    local function roundHeroTerms(terms,clickAttackFactor)
        terms["rounding:passive"]=nil;terms["rounding:click"]=nil
        local passiveTotal,clickTotal=NEG,NEG
        for name,value in pairs(terms) do
            if name:sub(1,8)=="passive:" then passiveTotal=Core.add(passiveTotal,value) else clickTotal=Core.add(clickTotal,value) end
        end
        local passiveRounding=Core.sub(ceilLog(passiveTotal),passiveTotal)
        if passiveRounding~=NEG then terms["rounding:passive"]=passiveRounding end
        if clickAttackFactor then
            local rawClick=clickTotal-clickAttackFactor
            local clickRounding=Core.sub(ceilLog(rawClick),rawClick)
            if clickRounding~=NEG then terms["rounding:click"]=clickRounding+clickAttackFactor end
        end
        local total=NEG;for _,value in pairs(terms) do total=Core.add(total,value) end
        return total,{clickAttackFactor=clickAttackFactor,passiveLog=passiveTotal,clickLog=clickAttackFactor and clickTotal-clickAttackFactor or NEG}
    end
    -- Keep additive hero contributions separate. Subtracting two complete team
    -- totals would erase a real cheap gain beside a hero thousands of exponents
    -- stronger. These normal-damage terms exclude temporary combat skills.
    function P.heroDamageTerms(d,s,gear,clicking)
        gear=gear or {};s=s or {};local ee=d.eastereggs or {}
        local raw,heroMods={},{ };local global,clickmod,critmod,critchance=0,NEG,NEG,0
        for id,h in pairs(d.heroes or {}) do
            local def=H.Stats[id]
            if def and h.level>0 then
                local damage=Core.log(def.BaseDPS)+math.log10(h.level)+Core.multiplierLog(id,h.level)
                for k,enabled in pairs(h.upgrades or {}) do
                    local u=enabled and def.Upgrades[tonumber(k)]
                    if u then
                        if u.personalModifier then damage+=Core.log(u.personalModifier) end
                        if u.globalModifier then global+=Core.log(u.globalModifier) end
                        if u.clickModifier then clickmod=Core.add(clickmod,Core.log(u.clickModifier)) end
                        if u.criticalChance then critchance+=u.criticalChance end
                        if u.criticalModifier then critmod=Core.add(critmod,Core.log(u.criticalModifier)) end
                        if u.heroModifier then local x=u.heroModifier;heroMods[x.hero]=(heroMods[x.hero] or 0)+Core.log(x.modifier) end
                    end
                end
                local trophy=(d.inventory.trophies or {})[id]
                if trophy then
                    local bonus=Core.add(Core.log(M.TrophyBonus),Core.log(effect(M.EggsData,"20",ee["20"])))
                    damage+=Core.add(0,bonus+math.log10(trophy))
                end
                raw[id]=damage
            end
        end
        local common=global+Core.add(Core.add(0,Core.log(d.blackeggs)-1),Core.log(effect(M.EggsData,"1",ee["1"])))
        local double=s.passes and s.passes["Double Damage"]
        if double then common+=math.log10(2) end
        local passive=common+math.log10(1.05)*(d.exploits or 0)
        if s.idle then passive+=Core.add(0,Core.log(effect(M.EggsData,"22",ee["22"]))) end
        if s.combo and s.combo.clicks>=3 then passive+=Core.add(0,Core.log(effect(M.EggsData,"21",ee["21"]))+math.log10(s.combo.clicks)) end
        local shared=math.log10(1+effect(M.Eggs2Data,"2",(d.phoenixeggs or {})["2"]))+math.log10(1+math.min(500,effect(M.Eggs3Data,"4",(d.ascensioneggs or {})["4"])))
        local terms={};local clickFactor,clickAttackFactor
        if clicking~=false then
            critchance+=math.max(0,(gear.trailTier or 1)-1)*0.02
            local crit=Core.add(1,critmod)+Core.add(0,Core.log(effect(M.EggsData,"8",ee["8"])))
            local expected=Core.add(0,Core.sub(crit,0)+Core.log(math.clamp(critchance,0,1)))
            local cps=math.max(1,s.cps or 1)+(gear.wingsTier or 0)+(s.passes and s.passes["Pet Chick"] and 2 or 0)
            clickAttackFactor=math.log10(cps)+expected
            clickFactor=clickAttackFactor+math.log10(1+(M.WeaponCooldown[gear.weaponTier or 0] or 0))
            terms["click:base"]=shared+clickFactor+(double and math.log10(2) or 0)
        end
        local clickEgg=Core.add(0,Core.log(effect(M.EggsData,"12",ee["12"])))
        for id,value in pairs(raw) do
            if id~="1" then
                local contribution=value+(heroMods[id] or 0)+passive+shared
                terms["passive:"..id]=contribution
                if clickFactor and clickmod~=NEG then terms["click:"..id]=contribution+clickmod+clickEgg+clickFactor end
            elseif clickFactor then terms["click:1"]=value+common+shared+clickEgg+clickFactor end
        end
        -- Native damage rounds the complete passive and per-click values up.
        -- Separate residual terms preserve that early-game rounding without
        -- collapsing the independent hero terms used for huge-number deltas.
        local total,metadata=roundHeroTerms(terms,clickAttackFactor)
        return terms,total,metadata
    end
    local function trainingChange(id,from,to,personalChange)
        return math.log10(to/from)+Core.multiplierLog(id,to)-Core.multiplierLog(id,from)+(personalChange or 0)
    end
    function P.trainDamageTerms(before,id,from,to,metadata,personalChange)
        local terms=table.clone(before)
        local change=trainingChange(id,from,to,personalChange)
        for _,name in ipairs({"passive:"..id,"click:"..id}) do if terms[name] then terms[name]+=change end end
        local total,nextMetadata=roundHeroTerms(terms,metadata.clickAttackFactor)
        return terms,total,nextMetadata
    end
    function P.heroGain(before,after)
        local gain,loss=NEG,NEG
        for name,value in pairs(after) do
            local old=before[name] or NEG
            gain=Core.add(gain,Core.sub(value,old));loss=Core.add(loss,Core.sub(old,value))
        end
        for name,value in pairs(before) do if after[name]==nil then loss=Core.add(loss,value) end end
        if gain~=NEG and loss~=NEG and math.abs(gain-loss)<1e-12 then return NEG,false end
        return Core.sub(gain,loss),loss>gain
    end
    function P.trainDamageGain(before,id,from,to,metadata,personalChange)
        local passive,click=before["passive:"..id],before["click:"..id]
        if passive and metadata.passiveLog<15 or click and metadata.clickLog<15 then
            return P.heroGain(before,P.trainDamageTerms(before,id,from,to,metadata,personalChange))
        end
        -- Once final ceilings are a no-op, only this hero's two additive terms
        -- can change. No team traversal or projection allocation is necessary.
        local change=trainingChange(id,from,to,personalChange)
        if change<0 then return NEG,passive~=nil or click~=nil end
        local gain=NEG
        if passive then gain=Core.add(gain,Core.sub(passive+change,passive)) end
        if click then gain=Core.add(gain,Core.sub(click+change,click)) end
        return gain,false
    end
    function P.nextHire(d)
        for n=1,54 do
            local id=tostring(n)
            if H.Stats[id] and ((d.heroes[id] or {}).level or 0)<1 then return id end
        end
    end
    function P.heroes(d,s,gear,options)
        options=options or {};local clicking=options.clicking~=false
        local nextHire=options.hire~=false and P.nextHire(d) or nil
        local diagnostic={nextHire=nextHire,hireCandidates=0}
        local choices={};local before,current,metadata=P.heroDamageTerms(d,s,gear,clicking)
        local weakBudget=B.Mul(d.eggs,{5,-3})
        if options.weakBudget and B.Compare(options.weakBudget,weakBudget)=="<" then weakBudget=options.weakBudget end
        local threshold=current+math.log10(0.005);local seen={};local costs={};local upgradeCosts={}
        local function trainCost(id,from,to)
            local row=costs[id];if not row then row={};costs[id]=row end
            if not row[to] then row[to]=P.cost(d,id,from,to) end
            return row[to]
        end
        local function upgradeCost(id,k)
            local key=id..":"..k
            if not upgradeCosts[key] then upgradeCosts[key]=H.UpgradeCost(H.Stats[id].BaseCost,k) end
            return upgradeCosts[key]
        end
        local function offer(id,projectedAmount,upgrade,plannedUpgrade,reason)
            local h=d.heroes[id];local base=h and h.level or 0
            local amount=not upgrade and (base==0 and 1 or Core.trainAmount(projectedAmount)) or nil
            if not upgrade and amount<1 then return end
            local key=id..":"..tostring(upgrade)..":"..tostring(amount)..":"..tostring(plannedUpgrade)..":"..tostring(projectedAmount)
            if seen[key] then return end
            local cost=upgrade and upgradeCost(id,upgrade) or trainCost(id,base,base+amount)
            local commitment=upgrade and cost or trainCost(id,base,base+projectedAmount)
            if plannedUpgrade then commitment=B.Add(commitment,upgradeCost(id,plannedUpgrade)) end
            if Core.log(cost)==NEG or B.Compare(d.eggs,commitment)=="<" then return end
            local gain,decreases
            local u=(upgrade or plannedUpgrade) and H.Stats[id].Upgrades[upgrade or plannedUpgrade]
            local personalOnly=not u or not (u.globalModifier or u.clickModifier or u.criticalChance or u.criticalModifier or u.heroModifier)
            if h and base>0 and personalOnly then
                local personalChange=u and u.personalModifier and Core.log(u.personalModifier) or 0
                gain,decreases=P.trainDamageGain(before,id,base,upgrade and base or base+projectedAmount,metadata,personalChange)
            else
                local nextData=table.clone(d);nextData.heroes=table.clone(d.heroes)
                local nextHero=h and table.clone(h) or {level=0,upgrades={}}
                nextHero.upgrades=table.clone(nextHero.upgrades or {});nextData.heroes[id]=nextHero
                if upgrade then nextHero.upgrades[tostring(upgrade)]=true else nextHero.level+=projectedAmount end
                if plannedUpgrade then nextHero.upgrades[tostring(plannedUpgrade)]=true end
                local after=P.heroDamageTerms(nextData,s,gear,clicking)
                gain,decreases=P.heroGain(before,after)
            end
            if decreases then return end
            local contribution=Core.add(before["passive:"..id] or NEG,before["click:"..id] or NEG)
            -- Compare complete investments by productive gain per egg, rather
            -- than letting the presence of an upgrade, hire or prerequisite
            -- override a much better damage milestone. A permanent native egg
            -- multiplier improves growth without being mislabeled as DPS.
            local incomeFactor=u and u.eggModifier and Core.log(u.eggModifier) or 0
            local growthGain=gain
            if incomeFactor>0 then
                growthGain=Core.add(gain+incomeFactor,current+Core.sub(incomeFactor,0))
            end
            local bootstrap=base==0 and id=="1" and not next(d.heroes) and not plannedUpgrade
            local weak=not bootstrap and (growthGain==NEG or contribution<threshold and growthGain<threshold)
            if weak and B.Compare(commitment,weakBudget)==">" then return end
            local priority=bootstrap and 2 or 1
            -- Ability unlocks and already-capped modifiers retain a bounded
            -- utility allowance. They cannot displace a productive purchase
            -- with invented damage or a higher purchase-type priority.
            local score=growthGain-Core.log(commitment)
            if growthGain==NEG then reason=u and u.ability and "ability unlock (weak pool)" or "utility (weak pool)"
            elseif incomeFactor>0 then reason="egg income per egg" end
            seen[key]=true
            table.insert(choices,{id=id,amount=amount,upgrade=upgrade,cost=cost,commitmentCost=commitment,plannedUpgrade=plannedUpgrade,targetLevel=not upgrade and base+projectedAmount or nil,priority=priority,score=score,gainLog=gain,growthGainLog=growthGain,incomeFactorLog=incomeFactor,currentDpsLog=current,contributionLog=contribution,weak=weak,baseLevel=base,reason=reason or "damage per egg"})
            if base==0 then diagnostic.hireCandidates+=1 end
        end
        for id,def in pairs(H.Stats) do
            local h=d.heroes[id];local level=h and h.level or 0
            if level<1 then
                if id~=nextHire then continue end
                diagnostic.cost=trainCost(id,0,1)
                offer(id,1,nil,nil,"hire")
                -- A future team/crit/ability unlock can make the next hero
                -- worthwhile even when their first level has little damage.
                -- Reserve the whole path; the native first request is only 1.
                for k,u in pairs(def.Upgrades or {}) do
                    local required=u.requiredLevel or math.max(10,(k-1)*25)
                    offer(id,required,nil,k,"hire for upgrade")
                end
            else
                local budget=B.Mul(d.eggs,{1,-1});local offered=false
                for _,amount in ipairs({1,10,25,100,1000,10000}) do
                    if B.Compare(trainCost(id,level,level+amount),budget)~='>' then offer(id,amount,nil,nil,"training");offered=true end
                end
                if not offered and B.Compare(trainCost(id,level,level+1),d.eggs)~='>' then offer(id,1,nil,nil,"training") end
                if id~="1" then
                    local next25=level<200 and 200 or (math.floor(level/25)+1)*25
                    offer(id,next25-level,nil,nil,"next damage multiplier")
                    if tonumber(id)<46 and level<8000 then offer(id,(math.floor(level/1000)+1)*1000-level,nil,nil,"next 1000-level multiplier") end
                end
                for k,u in pairs(def.Upgrades or {}) do
                    if not (h.upgrades or {})[tostring(k)] then
                        local required=u.requiredLevel or math.max(10,(k-1)*25)
                        if level>=required then offer(id,nil,k,nil,"upgrade")
                        else offer(id,required-level,nil,k,"upgrade prerequisite") end
                    end
                end
            end
        end
        table.sort(choices,function(a,b)
            if a.priority~=b.priority then return a.priority>b.priority end
            if a.score~=b.score then return a.score>b.score end
            if a.score==NEG and Core.log(a.commitmentCost)~=Core.log(b.commitmentCost) then return Core.log(a.commitmentCost)<Core.log(b.commitmentCost) end
            if a.weak~=b.weak then return not a.weak end
            if a.id~=b.id then return tonumber(a.id)<tonumber(b.id) end
            if a.upgrade~=b.upgrade then return (a.upgrade or 1e9)<(b.upgrade or 1e9) end
            if a.amount~=b.amount then return (a.amount or 0)>(b.amount or 0) end
            return (a.targetLevel or 0)<(b.targetLevel or 0)
        end)
        return choices,diagnostic
    end
    -- Injected immediately before Core.new's return P. Egg plans use the native
    -- catalogs and are pure: callers must confirm replicated levels after send.
    local function eggBN(x)
        if type(x)=="number" then
            if x~=x or x<0 or x==math.huge then return nil end
            return B.fromNum(x)
        end
        if type(x)~="table" or type(x[1])~="number" or type(x[2])~="number" or x[1]~=x[1] or x[2]~=x[2] or x[1]<0 or math.abs(x[1])==math.huge or math.abs(x[2])==math.huge then return nil end
        return x
    end
    local function eggPositive(x) local n=eggBN(x);return n and B.Compare(n,{0,0})==">" end
    local function goldLevel(x)
        return type(x)=="number" and x==x and x>=0 and x<1e9 and x==math.floor(x) and x or 0
    end
    local function waterFactor(d)
        local level=goldLevel((d.phoenixeggs or {})["1"])
        -- Native effect is 1-(1-.95^level); direct power avoids cancellation.
        return .95^level
    end
    function P.blackCost(d,id,amount)
        local def=M.EggsData[id];local before=eggBN((d.eastereggs or {})[id]);amount=eggBN(amount)
        if not def or not before or not amount or not eggPositive(amount) then return nil end
        local after=B.Add(before,amount)
        local raw=id=="1" and amount or B.Sub(def.cost(after),def.cost(before))
        if not eggBN(raw) or not eggPositive(raw) then return nil end
        local cost=raw
        if (d.phoenixeggs or {})["1"]~=nil then cost=B.Floor(B.Mul(raw,B.fromNum(waterFactor(d)))) end
        if not eggBN(cost) then return nil end
        return B.Compare(cost,{1,0})=="<" and {1,0} or cost
    end
    local function eggChance(d,id,phoenix)
        local level=(d.eastereggs or {})[id]
        return level and effect(M.EggsData,id,level,(d.phoenixeggs or {})[phoenix]) or 0
    end
    local function expectedEggUtility(d,s,gear,fertilizer)
        local value,_,stats=P.output(d,s,gear)
        if value==NEG or value~=value or value==math.huge then return nil end
        -- The generic output model includes ordinary egg drops, discounts,
        -- trophies, crits, boss mechanics and ability durations. Add the native
        -- special-spawn economy without claiming a measured future spawn rate.
        local zone=math.max(0,math.floor(((d.level or {}).current or 1)/500))
        local mutation=math.clamp(.05+eggChance(d,"6","5"),.05,1)
        local chance=math.clamp(math.exp(-.006*zone)*.01*(1+eggChance(d,"7","8")),.01,1)
        local newton=Core.add(0,Core.log(effect(M.EggsData,"2",(d.eastereggs or {})["2"])))
        value+=.4*math.log10(mutation/.05)
        value+=.4*Core.add(Core.log(1-chance),math.log10(chance)+1+newton)
        if fertilizer then
            value+=.2*Core.add(0,Core.log(effect(M.EggsData,"3",(d.eastereggs or {})["3"])))
        end
        return value,stats
    end
    function P.blackEggs(d,s,gear,options)
        options=options or {};local plans={};local wallet=eggBN(d.blackeggs)
        if not wallet or not eggPositive(wallet) then return plans end
        local fertilizer=P.unlocked(d)["5"]
        local baseline,baselineStats=expectedEggUtility(d,s,gear,fertilizer);if not baseline then return plans end
        local hasCombatBuff=false
        for _,id in ipairs({"1","2","3","7"}) do if (s.abilities or {})[id] then hasCombatBuff=true;break end end
        local beforeRate=hasCombatBuff and P.damageRate(d,s,gear,options.clicking~=false,true) or (options.clicking==false and baselineStats.dps or baselineStats.damageRate)
        local owned=0;for _ in pairs(d.eastereggs or {}) do owned+=1 end
        local hatch=M.EggsData.HatchCost[owned+1]
        local seen={};local units={{1,0},{1,1},{2.5,1},{1,2},{1,3},{1,4}}
        -- Pure gain/cost always favors tiny steps on concave effects. Add a
        -- one-percent-wallet planning overhead per request, so time spent
        -- dispatching and waiting for replication has a bounded growth value.
        -- This is a heuristic score, never an extra debit or spending budget.
        local requestOverhead=B.Mul(wallet,{1,-2})
        local combatOnly={ ["1"]=true,["8"]=true,["12"]=true,["20"]=true,["21"]=true,["22"]=true }
        local function offer(id,amount,action)
            if options.blocked and options.blocked[id] then return end
            local before=(d.eastereggs or {})[id]
            if not M.EggsData[id] or action~="Hatch" and action~="Enhance" then return end
            if action=="Hatch" and before or action=="Enhance" and not eggBN(before) then return end
            local cost=action=="Hatch" and hatch and B.fromNum(hatch) or P.blackCost(d,id,amount)
            if not cost or not eggPositive(cost) or B.Compare(cost,wallet)==">" then return end
            local after=action=="Hatch" and {1,0} or B.Add(before,amount)
            if not eggBN(after) or B.Compare(after,{1,111000})~="<" then return end
            local key=id..":"..action..":"..tostring(after[1])..":"..tostring(after[2]);if seen[key] then return end;seen[key]=true
            local nextData=table.clone(d);nextData.eastereggs=table.clone(d.eastereggs or {})
            nextData.eastereggs[id]=after;nextData.blackeggs=B.Sub(wallet,cost)
            local score,stats=expectedEggUtility(nextData,s,gear,fertilizer)
            if not score or score<=baseline+1e-12 then return end
            -- Retaining BE itself gives +10% damage per egg. A damage-only
            -- purchase must beat that banked bonus after its full debit.
            if combatOnly[id] then
                local rate=hasCombatBuff and P.damageRate(nextData,s,gear,options.clicking~=false,true) or (options.clicking==false and stats.dps or stats.damageRate)
                if rate~=rate or rate<beforeRate-1e-10 or options.clicking==false and rate<=beforeRate then return end
            end
            local gain=score-baseline
            table.insert(plans,{kind="black",id=id,action=action,amount=action=="Enhance" and amount or nil,cost=cost,before=before,after=after,
                score=math.log10(gain)-Core.log(B.Add(cost,requestOverhead)),roiScore=math.log10(gain)-Core.log(cost),gain=gain,
                reason=(action=="Hatch" and "Unlock " or "Improve ")..M.EggsData[id].title.."; smart batch"})
        end
        if options.exact then
            offer(options.exact.id,options.exact.amount,options.exact.action)
            return plans
        end
        for n=1,22 do
            local id=tostring(n);local def=M.EggsData[id];local before=eggBN((d.eastereggs or {})[id])
            if def and not before then if hatch then offer(id,nil,"Hatch") end
            elseif def and before then
                for _,amount in ipairs(units) do offer(id,amount,"Enhance") end
                -- Native Custom accepts BN amounts. Reassess after each batch;
                -- include smaller budget fractions as well as supported units.
                -- This avoids both a 10,000-level ceiling and unit-only queues.
                for _,fraction in ipairs(waterFactor(d)>0 and {.005,.01,.02,.05,.1,.2} or {}) do
                    local budget=B.Div(B.Mul(wallet,B.fromNum(fraction)),B.fromNum(waterFactor(d)))
                    local ok,target=pcall(function()
                        if id=="1" then return B.Add(before,B.Floor(budget)) end
                        if def.max then return def.max(B.Add(budget,def.cost(before))) end
                        -- Turtle's cost is monotone but has no exported max.
                        if id=="21" then
                            local total=B.Add(budget,def.cost(before));local estimate=B.Pow(B.Div(total,{4,-1}),.4)
                            local lo,hi=0,1
                            for _=1,48 do local mid=(lo+hi)/2;if B.Compare(def.cost(B.Mul(estimate,B.fromNum(mid))),total)==">" then hi=mid else lo=mid end end
                            return B.Floor(B.Mul(estimate,B.fromNum(lo)))
                        end
                    end)
                    if ok and eggBN(target) and B.Compare(target,before)==">" then
                        local amount=B.Floor(B.Sub(target,before));if eggPositive(amount) then offer(id,amount,"Enhance") end
                    end
                end
            end
        end
        table.sort(plans,function(a,b) if a.score~=b.score then return a.score>b.score end;if a.id~=b.id then return tonumber(a.id)<tonumber(b.id) end;return Core.log(a.cost)<Core.log(b.cost) end)
        return plans
    end
    function P.blackQuote(d,s,gear,purchase,options)
        return P.blackEggs(d,s,gear,{clicking=not options or options.clicking~=false,exact=purchase})[1]
    end
    function P.blackAllocation(d,s,gear,options)
        options=options or {}
        local wallet=eggBN(d.blackeggs)
        if not wallet or not eggPositive(wallet) then return {entries={},totalCost={0,0},steps=0} end
        local initial=Core.copy(d);local shadow=Core.copy(d)
        -- Leave a tiny rounding margin so summing/reordering native BN prices
        -- cannot make the final merged request exceed the remaining wallet.
        local budget=wallet
        if B.Compare(wallet,{1,1})~="<" then
            local margin=B.Mul(wallet,{1,-12})
            if B.Compare(margin,{1,0})=="<" then margin={1,0} end
            budget=B.Sub(wallet,margin)
        end
        local groups,hatches,order={},{},{}
        local total,steps={0,0},0
        local function yieldStep(phase,step)
            return not options.yieldStep or options.yieldStep(phase,step)~=false
        end
        -- These are simulated decisions, never server purchases. Reprice each
        -- accumulated egg from its original level: Water flooring means the
        -- native price of a merged request can differ from many small requests.
        for step=1,128 do
            if not yieldStep("allocate",step) then return nil end
            local selected,nextTotal,newGroupCost
            for _,p in ipairs(P.blackEggs(shadow,s,gear,options)) do
                if p.action=="Hatch" then
                    nextTotal=B.Add(total,p.cost)
                else
                    local group=groups[p.id]
                    local base=group and group.before or shadow.eastereggs[p.id]
                    local pricing=table.clone(initial);pricing.eastereggs={[p.id]=base}
                    newGroupCost=P.blackCost(pricing,p.id,B.Floor(B.Sub(p.after,base)))
                    nextTotal=newGroupCost and B.Add(B.Sub(total,group and group.cost or {0,0}),newGroupCost)
                end
                if nextTotal and B.Compare(nextTotal,budget)~='>' then selected=p;break end
            end
            if not selected then break end
            local p=selected;steps=step;total=nextTotal
            if p.action=="Hatch" then
                table.insert(hatches,{id=p.id,action="Hatch"})
            else
                local group=groups[p.id]
                if not group then
                    group={id=p.id,action="Enhance",before=Core.copy(shadow.eastereggs[p.id])}
                    groups[p.id]=group;table.insert(order,group)
                end
                group.after=Core.copy(p.after);group.cost=Core.copy(newGroupCost)
                group.amount=B.Floor(B.Sub(group.after,group.before))
            end
            shadow.eastereggs[p.id]=Core.copy(p.after)
            shadow.blackeggs=B.Sub(wallet,total)
            if not eggPositive(shadow.blackeggs) then break end
        end
        -- Choose an executable order for the merged requests. Every complete
        -- request must still improve the model after its actual full debit.
        -- A hatch and its one merged Enhance remain separate native actions.
        local remaining={}
        for _,p in ipairs(hatches) do table.insert(remaining,p) end
        for _,p in ipairs(order) do table.insert(remaining,p) end
        local checked=Core.copy(initial);local entries={};local spent={0,0}
        for step=1,44 do
            if #remaining==0 then break end
            if not yieldStep("order",step) then return nil end
            local best,index
            for i,p in ipairs(remaining) do
                local quote=P.blackQuote(checked,s,gear,p,options)
                if quote and (not best or quote.score>best.score) then best,index=quote,i end
            end
            if not best then break end
            best.reason=(best.action=="Hatch" and "Unlock " or "Allocate ")..M.EggsData[best.id].title.."; custom allocation"
            table.insert(entries,best);table.remove(remaining,index)
            checked.eastereggs[best.id]=Core.copy(best.after)
            checked.blackeggs=B.Sub(checked.blackeggs,best.cost);spent=B.Add(spent,best.cost)
        end
        return {entries=entries,totalCost=spent,remaining=Core.copy(checked.blackeggs),steps=steps}
    end
    function P.goldWealth(d)
        local total=eggBN(d.goldeggs) or {0,0}
        for id,level in pairs(d.phoenixeggs or {}) do
            local def=M.Eggs2Data[id];level=goldLevel(level)
            if def and level>0 then local cost=def.cost(level);if eggBN(cost) then total=B.Add(total,cost) end end
        end
        return total
    end
    function P.goldTargets(d)
        local wealth=P.goldWealth(d);local n=math.floor(10^math.min(9,Core.log(wealth))+.0000001)
        local target={ ["1"]=0,["2"]=0,["3"]=0,["4"]=0,["5"]=0,["6"]=0,["7"]=0,["8"]=0 }
        if n<7 then target["3"]=math.max(0,math.floor((math.sqrt(1+8*n)-1)/2));return target end
        if n<15 then
            local base=n<10 and 6 or 10;target["3"]=n<10 and 3 or 4
            local extra=n-base
            for _,id in ipairs({"2","5","1","4"}) do if extra>0 then target[id]=1;extra-=1 end end
            return target
        end
        -- Sparse stage anchors summarize the guide's Earth-first allocation.
        -- Interpolate by assigning spare capacity to Earth, using current native
        -- cumulative costs. No existing investment is sold or refunded.
        local anchors={
            {15,0,0,5,0,0,0},{40,2,1,7,3,1,1},{119,2,2,13,6,1,1},
            {305,4,4,22,8,1,1},{995,13,4,40,12,1,1},{2500,22,3,61,26,1,1},
            {7098,21,4,109,41,1,3},{16069,46,5,164,53,1,6},{25496,55,14,204,76,1,14}
        }
        local anchor=anchors[1];for _,row in ipairs(anchors) do if n>=row[1] then anchor=row else break end end
        target["1"],target["2"],target["3"],target["4"],target["5"],target["8"]=anchor[2],anchor[3],anchor[4],anchor[5],anchor[6],anchor[7]
        local reserved=0
        for _,id in ipairs({"1","2","4","5","6","7","8"}) do
            local level=math.max(target[id],goldLevel((d.phoenixeggs or {})[id]));if id=="1" then level=math.min(150,level) end
            local cost=M.Eggs2Data[id].cost(level);local log=Core.log(cost);reserved+=log==NEG and 0 or 10^math.min(12,log)
        end
        target["3"]=math.max(target["3"],math.floor((math.sqrt(1+8*math.max(0,n-reserved))-1)/2+.0000001))
        target["1"]=math.min(150,target["1"])
        return target
    end
    function P.goldEggs(d,s,gear,options)
        local plans={};local wallet=eggBN(d.goldeggs)
        if not wallet or not eggPositive(wallet) then return plans end
        local target=P.goldTargets(d);local owned=d.phoenixeggs or {}
        -- Commit to the next Earth target before spending its coins on filler.
        -- This makes a fresh ten-GE first rebirth reach Earth 4 exactly.
        local order={"3","1","4","5","8","2"}
        for rank,id in ipairs(order) do
            local before=goldLevel(owned[id]);local goal=target[id] or 0
            if id=="1" then goal=math.min(150,goal) end
            if goal>before then
                if id=="4" and before>0 and M.GetChickensRequired(d)<=2 then continue end
                local def=M.Eggs2Data[id];local amount,cost
                -- The native first-unlock menu forces amount 1. For existing
                -- eggs, choose the largest supported batch that is affordable,
                -- rather than blocking an affordable +1 behind a costly +1000.
                for _,batch in ipairs(before==0 and {1} or {1000,100,25,10,1}) do
                    if goal-before>=batch then
                        local candidate=def.incrementalCost(before,before+batch)
                        if eggBN(candidate) and eggPositive(candidate) and B.Compare(candidate,wallet)~='>' then amount,cost=batch,candidate;break end
                    end
                end
                if amount then
                    table.insert(plans,{kind="gold",id=id,action="Boost",amount=amount,cost=cost,before=before,after=before+amount,target=goal,score=100-rank,reason="Stage allocation: "..def.title.." toward level "..goal})
                    -- Sending one plan and replanning after its actual level
                    -- change preserves every shared-wallet limit.
                    return plans
                elseif id=="3" then return plans end
            end
        end
        return plans
    end

    -- Injected inside Core.new. Native requirements/rewards are separate from
    -- conservative timing/benefit heuristics; the runtime owns authorization,
    -- authoritative data, one-at-a-time dispatch, confirmation and cooldowns.
    local function resetBN(x)
        return type(x)=="table" and type(x[1])=="number" and x[1]>=0 and x[1]<math.huge
            and type(x[2])=="number" and x[2]==x[2] and math.abs(x[2])<math.huge
    end
    local function resetSeconds(x)
        return type(x)=="number" and x==x and x<math.huge and math.max(0,x) or 0
    end
    local function resetTotalLevels(d)
        local total=0
        for _,hero in pairs(d.heroes or {}) do
            local level=type(hero)=="table" and hero.level
            if type(level)=="number" and level==level and level>=0 and level<math.huge then total+=level end
        end
        return total
    end
    function P.retirePayout(d,additionalLevels)
        local pending=resetBN(d and d.blackeggspending) and d.blackeggspending or {0,0}
        local total=resetTotalLevels(d or {})+math.max(0,tonumber(additionalLevels) or 0)
        return B.Add(pending,B.fromNum(math.floor(total/2000)))
    end
    function P.retireUnlockCost(d)
        local queen=tonumber((d.heroes["20"] or {}).level) or 0
        if queen>=150 then return {0,0} end
        if queen>=1 then return P.cost(d,"20",queen,150) end
        -- Native hiring follows the catalog and requires one level at a time.
        -- Price the complete unlock before reserving the progression controller.
        local cost=P.cost(d,"20",0,150)
        for n=1,19 do
            local id=tostring(n)
            if H.Stats[id] and (tonumber((d.heroes[id] or {}).level) or 0)<1 then
                cost=B.Add(cost,P.cost(d,id,0,1))
            end
        end
        return cost
    end
    function P.rebirthTarget(d)
        if (tonumber(d.superprestige) or 0)<=0 then return 10 end
        -- Guide projections use total earned Gold Eggs, not rebirth count.
        -- The lower, unassisted Dracula branch avoids requiring a manual push.
        local earned=resetBN(d.goldeggsearned) and Core.log(d.goldeggsearned) or -math.huge
        local stages={
            {10,30},{40,40},{80,39},{119,38},{157,39},{196,43},
            {239,45},{250,55},{305,69},{374,111},{485,165},{650,335}
        }
        local target=30
        for _,stage in ipairs(stages) do
            if earned+1e-12>=math.log10(stage[1]) then target=stage[2] else break end
        end
        if earned>=math.log10(985)-1e-12 then
            -- Beyond the published projected table, require a meaningful new
            -- payout rather than repeating the level-301 unlock indefinitely.
            -- This 35% extrapolation is a heuristic, not a native mechanic.
            target=math.max(335,math.ceil(0.35*10^math.min(earned,12)))
        end
        return target
    end
    function P.resetPlan(d,s,metrics)
        metrics=metrics or {}
        if type(d)~="table" or type(d.level)~="table" or type(d.heroes)~="table" then return nil,"Waiting for progression data" end
        if not resetBN(d.blackeggspending) or not resetBN(d.blackeggs) or not resetBN(d.goldeggspending) then
            return nil,"Waiting for native reset reward balances"
        end
        local runSeconds=resetSeconds(metrics.runSeconds)
        local stalledSeconds=resetSeconds(metrics.stalledSeconds)
        local wall=metrics.wall==true
        local first=(tonumber(d.superprestige) or 0)<=0
        local target=P.rebirthTarget(d)
        local ge=Core.log(d.goldeggspending)
        local rebirthReady=(tonumber(d.level.highest) or 0)>=301
        local allowRebirth=metrics.allowRebirth~=false and metrics.autoRebirth~=false
        local allowRetire=metrics.allowRetire~=false and metrics.autoRetire~=false
        if allowRebirth and rebirthReady and ge+1e-12>=math.log10(target) then
            if runSeconds<300 then return nil,"Observing this run before the ready rebirth (5 active minutes)" end
            return {kind="rebirth",reason="Reached the stage Gold Egg target",payout=Core.copy(d.goldeggspending),targetGE=target}
        end
        if runSeconds<180 then return nil,"Observing this run before retirement (3 active minutes)" end
        local queen=tonumber((d.heroes["20"] or {}).level) or 0
        local missing=math.max(0,150-queen)
        local payout=P.retirePayout(d,missing)
        -- Common native damage factor = 1 + bankBE/10 + Good Knight effect.
        -- Express it in BE units so the benefit gate includes existing buffs.
        local baseline=B.Add(d.blackeggs,{1,1})
        local knight=(d.eastereggs or {})["1"]
        if knight and M.EggsData and M.EggsData["1"] then
            local ok,bonus=pcall(M.EggsData["1"].effect,knight)
            if not ok or not resetBN(bonus) then return nil,"Unable to model the current retirement damage bonus" end
            baseline=B.Add(baseline,B.Mul(bonus,{1,1}))
        end
        local benefit=Core.log(payout)-Core.log(baseline)
        local meaningful=Core.log(payout)>=0 and benefit+1e-12>=math.log10(0.25)
        local retirementHold
        if allowRetire and wall and stalledSeconds>=90 and meaningful then
            if queen<150 then
                local unlockCost=P.retireUnlockCost(d)
                if not resetBN(d.eggs) or not resetBN(unlockCost) or B.Compare(d.eggs,unlockCost)=="<" then
                    retirementHold="Retirement unlock needs more White Eggs; keep farming"
                else
                    return {kind="prepareRetire",reason="Fund Queen Elizabeth II level 150 for a worthwhile retirement",payout=payout,
                        targetHero="20",targetLevel=150,additionalLevels=missing,benefitLog=benefit,targetGE=target}
                end
            else
                return {kind="retire",reason="Sustained wall; retirement adds at least 25% to the bank damage factor",payout=payout,
                    benefitLog=benefit,targetGE=target}
            end
        end
        -- A long, genuine wall can make a smaller rebirth better than waiting
        -- forever. A worthwhile retirement gets priority over this fallback.
        local fallback=first and 7 or math.max(5,math.ceil(target*0.5))
        local fallbackStall=first and 600 or 900
        local fallbackRun=first and 900 or 1800
        if allowRebirth and rebirthReady and wall and stalledSeconds>=fallbackStall and runSeconds>=fallbackRun
            and ge+1e-12>=math.log10(fallback) then
            return {kind="rebirth",reason="Persistent wall; use a smaller positive Gold Egg payout",payout=Core.copy(d.goldeggspending),
                targetGE=target,fallbackGE=fallback}
        end
        if not wall then return nil,"Progress is still advancing; keep farming" end
        if stalledSeconds<90 then return nil,"Allowing upgrades and boss recovery time (90 seconds without progress)" end
        if retirementHold then return nil,retirementHold end
        if not meaningful then return nil,"Retirement needs at least 25% of the bank/Good Knight damage factor, or a Gold Egg target" end
        return nil,"Waiting for an enabled progression reset target"
    end

    return P
end
-- Never interpret dispatch as success. Uncertain increments are quarantined by their precondition.
function Core.ledger(clock,log)
    local T={pending={},uncertain={},done=0}
    function T:available(lane,key,stamp)
        return not self.pending[lane] and self.uncertain[key]~=stamp
    end
    function T:begin(lane,key,stamp,predicate,send)
        if not self:available(lane,key,stamp) then return false end
        local op={key=key,stamp=stamp,at=clock(),predicate=predicate}
        self.pending[lane]=op
        local ok,err=pcall(send)
        if not ok then log("Dispatch error "..key..": "..tostring(err)) end
        return true
    end
    function T:poll(d,s)
        for lane,op in pairs(self.pending) do
            local ok,yes=pcall(op.predicate,d,s)
            local details
            if op.describe and (ok and yes or clock()-op.at>12) then local valid,result=pcall(op.describe,d,s);if valid then details=result end end
            if ok and yes then
                self.pending[lane]=nil; self.uncertain[op.key]=nil; if yes==true then self.done+=1 end
                if details then log("Confirmed "..details) end
            elseif clock()-op.at>12 then
                self.pending[lane]=nil; self.uncertain[op.key]=op.stamp
                log("Unconfirmed "..op.key..(details and ": "..details or "").."; same precondition quarantined")
            end
        end
    end
    return T
end


return Core
end)()
local NATIVE_PROGRESS_TOKEN="回小住位妻回平妻要抄か住ニが平も小ネネ回ネ抄激ても"
local NATIVE_WEAPON_TOKEN="219629d5067eddcdce55ed7968e9b53f"
local NATIVE_PLAY_TOKEN="回小住位妻回ぱ平妻要要抄か住小が平 "
-- Egg Farm Simulator [REBORN], source contract: FullDump 2026-10-18.
-- Run this complete file on the client in place 122156343392096.
local env=(getgenv and getgenv()) or _G
local KEY="EggFarmAutomation"
local previous=env[KEY]
local resumePrevious=previous and type(previous.settings)=="table" and Core.copy(previous.settings)
local resumeHeroBudget=previous and type(previous.heroBudget)=="table" and Core.copy(previous.heroBudget)
local resumeAutoReset=previous and type(previous.autoResetState)=="table" and Core.copy(previous.autoResetState)
local resumeTrophyBuy=previous and type(previous.trophyBuyAttempt)=="table" and Core.copy(previous.trophyBuyAttempt)
local resumeEventHistory=previous and type(previous.eventHistory)=="table" and Core.copy(previous.eventHistory)
local resumeWatch=previous and previous.alive and type(previous.progressionWatch)=="table" and Core.copy(previous.progressionWatch)
if resumeWatch then resumeWatch.pausedAt=resumeWatch.pausedAt or os.clock() end
local resumeEventInvites=previous and previous.eventInvites
local resumeEventPending=previous and previous.eventJoinPending and table.clone(previous.eventJoinPending)
local resumeEventActive=resumeEventHistory and previous and previous.eventWasActive
local resumeRocketWatch=previous and previous.alive and previous.rocketWatch and table.clone(previous.rocketWatch)
local resumeRocketNotice=previous and previous.alive and previous.rocketNotice and table.clone(previous.rocketNotice)
if previous and previous.Unload then
    previous.replacing=true
    local ok,done=pcall(function() return previous:Unload() end)
    if not ok or not done then warn("Egg Farm: previous cleanup incomplete; reexecute to retry."); return end
end
local A={alive=true,running=false,connections={},tasks={},cleanup={},logs={},settings={},status="Loading native contracts",next={},farm=nil,data=nil,session=nil,movement=nil,stats={hits=0}}
A.progressionWatch=resumeWatch
A.eventInvites=resumeEventInvites
A.eventJoinPending=resumeEventPending
A.eventWasActive=resumeEventActive
A.rocketWatch=resumeRocketWatch;A.rocketNotice=resumeRocketNotice
env[KEY]=A
function A:log(message)
    table.insert(self.logs,os.date("!%H:%M:%S").." "..message)
    if #self.logs>70 then table.remove(self.logs,1) end
end
function A:cancelMovement(owner)
    if not owner or self.movement and self.movement.owner==owner then self.movement=nil end
end
function A:setDiamondPriority(busy)
    busy=busy==true
    if busy==self.diamondPriority then return end
    self.diamondPriority=busy
    if busy then
        self.diamondPauseAt=os.clock()
        self:cancelMovement("combat");self:cancelMovement("claim");self:cancelMovement("meat")
        if self.collecting then self.collecting.meat=nil end
    else
        -- Deliberate collection time is not failed farming.
        local duration=self.diamondPauseAt and os.clock()-self.diamondPauseAt or 0
        if self.fight then
            self.fight.progressAt+=duration
            if self.fight.blockUntil then self.fight.blockUntil+=duration end
        end
        if self.lastFarmProgress then self.lastFarmProgress+=duration end
        if self.retreat then self.retreat.at+=duration end
        self.diamondPauseAt=nil;self:cancelMovement("diamond")
    end
end
function A:halt()
    if self.clearBlackAllocation then self:clearBlackAllocation() end
    if self.startupClaim then self.claimNote="Startup claim canceled" end
    self.startupClaim=false;self.claimAttempt=nil
    self:setDiamondPriority(false)
    if self.finishEventJoin then self:finishEventJoin("Disabled") end
    if self.flushEventHistory then self:flushEventHistory() end
    self.running=false;self:cancelMovement();self.collecting={};self.retreat=nil;self.decoyFor=nil;self.lastAbility=nil
    self.progressionIntent=nil;self.progressionWatch=nil;self.heroGoal=nil
end
function A:Stop()
    for key in pairs(self.settings) do self.settings[key]=false end
    if self.syncPerformance then self:syncPerformance() end
    self:halt()
    self.uiSync=true
    for _,control in pairs(self.controls or {}) do pcall(function() control:Set(false) end) end
    self.uiSync=false
    self.status="All features disabled";if self.save then self:save() end
end
function A:Unload()
    self:halt();self.alive=false
    if self.save then self:save() end -- Stop this instance without erasing saved preferences.
    local failed={}
    for i,thread in pairs(self.tasks) do
        local ok=thread==coroutine.running() or coroutine.status(thread)=="dead" or pcall(task.cancel,thread); if ok then self.tasks[i]=nil else table.insert(failed,"task "..i) end
    end
    for i,c in pairs(self.connections) do
        local ok=pcall(function() c:Disconnect() end); if ok then self.connections[i]=nil else table.insert(failed,"connection "..i) end
    end
    for i,fn in pairs(self.cleanup) do
        local ok=pcall(fn); if ok then self.cleanup[i]=nil else table.insert(failed,"cleanup "..i) end
    end
    if #failed>0 then self:log("Retry cleanup: "..table.concat(failed,", ")); return false end
    if env[KEY]==self then env[KEY]=nil end
    return true
end
function A:connect(signal,callback)
    local c=signal:Connect(function(...) if self.alive then callback(...) end end)
    table.insert(self.connections,c); return c
end
function A:due(key,period)
    local now=os.clock(); if (self.next[key] or 0)>now then return false end
    self.next[key]=now+period; return true
end
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local Input=game:GetService("UserInputService")
local Http=game:GetService("HttpService")
local player=Players.LocalPlayer
if not player or game.PlaceId~=122156343392096 then
    A:log("Wrong game or non-client context"); warn("Egg Farm: run on the client in place 122156343392096."); A:Unload(); return
end
-- This small standard Roblox GUI does not depend on Rayfield, HTTP, GetObjects,
-- CoreGui access or gethui. It makes menu startup failures visible on phones.
function A:closeStartupPanel()
    local panel=self.startupPanel;self.startupPanel=nil
    if not panel then return end
    for _,connection in ipairs(panel.connections) do connection:Disconnect() end
    panel.gui:Destroy()
end
function A:setUiStage(stage,problem)
    self.uiStage=stage
    if problem then self.uiError=tostring(problem);self:log("Menu startup: "..self.uiError) end
    local panel=self.startupPanel
    if panel then
        panel.message.Text=problem and ("Menu failed: "..stage.."\n"..self.uiError.."\nCopy error, then reexecute to retry.") or stage
        panel.copy.Visible=problem~=nil
        panel.dismiss.Visible=problem~=nil
    end
end
do
    local ok,err=pcall(function()
        local parent=player:FindFirstChildOfClass("PlayerGui")
        assert(parent,"PlayerGui is not available")
        local gui=Instance.new("ScreenGui");gui.Name="EggFarmStartup";gui.ResetOnSpawn=false;gui.DisplayOrder=10000
        local panel={gui=gui,connections={}};A.startupPanel=panel
        local frame=Instance.new("Frame");frame.Name="Panel";frame.Position=UDim2.new(.05,0,.12,0);frame.Size=UDim2.new(.9,0,0,174)
        frame.BackgroundColor3=Color3.fromRGB(28,28,32);frame.BorderSizePixel=0;frame.Parent=gui
        local title=Instance.new("TextLabel");title.Name="Title";title.Position=UDim2.fromOffset(10,6);title.Size=UDim2.new(1,-20,0,24)
        title.BackgroundTransparency=1;title.Text="Egg Farm — starting menu";title.TextColor3=Color3.new(1,1,1);title.TextSize=16;title.Parent=frame
        local message=Instance.new("TextBox");message.Name="Status";message.Position=UDim2.fromOffset(10,36);message.Size=UDim2.new(1,-20,0,92)
        message.BackgroundTransparency=1;message.Text="Starting script…";message.TextColor3=Color3.new(1,1,1);message.TextSize=12
        message.TextWrapped=true;message.MultiLine=true;message.ClearTextOnFocus=false;message.TextXAlignment=Enum.TextXAlignment.Left;message.TextYAlignment=Enum.TextYAlignment.Top;message.Parent=frame
        panel.message=message
        local copy=Instance.new("TextButton");copy.Name="CopyError";copy.Position=UDim2.new(0,10,1,-37);copy.Size=UDim2.new(.5,-15,0,28)
        copy.Text="Copy error";copy.TextSize=14;copy.Visible=false;copy.Parent=frame;panel.copy=copy
        local close=Instance.new("TextButton");close.Name="Dismiss";close.Position=UDim2.new(.5,5,1,-37);close.Size=UDim2.new(.5,-15,0,28)
        close.Text="Dismiss";close.TextSize=14;close.Visible=false;close.Parent=frame;panel.dismiss=close
        table.insert(panel.connections,copy.Activated:Connect(function()
            if not A.alive then return end
            if A.copyDebugDetails then
                local copied=A:copyDebugDetails()
                if copied then copy.Text="Copied" else copy.Text="Select text above to copy" end
            end
        end))
        table.insert(panel.connections,close.Activated:Connect(function() A:closeStartupPanel() end))
        gui.Parent=parent
    end)
    if not ok then A:closeStartupPanel();warn("Egg Farm startup panel: "..tostring(err)) end
end
table.insert(A.cleanup,function() A:closeStartupPanel() end)
A:setUiStage("Reading saved settings")

local defaults={farm=false,progress=false,diamonds=false,hireHeroes=false,heroes=false,equipment=false,abilities=false,rewards=false,quest=false,boss=false,boxes=false,autoRetire=false,autoRebirth=false,blackEggs=false,goldEggs=false,trophyBoxes=false,fpsBoost=false,disable3D=false}
local performanceKeys={fpsBoost=true,disable3D=true}
if resumeEventHistory then resumeEventHistory.schema=1;resumeEventHistory.place=game.PlaceId;resumeEventHistory.user=player.UserId end
local legacyFilename="EggFarmAutomation_122156343392096_"..player.UserId..".json"
local filename="EFS Files/"..legacyFilename
local SESSION_KEY="EggFarmAutomationSettings_122156343392096_"..player.UserId
-- Resolve capabilities instead of assuming a particular Delta/desktop build.
-- No downloaded executor code, global shims or platform-specific file paths.
function A:executorApis(name)
    local direct={readfile=readfile,writefile=writefile,isfile=isfile,delfile=delfile,
        isfolder=isfolder,makefolder=makefolder,loadstring=loadstring,
        getconnections=getconnections,firesignal=firesignal,request=request,http_request=http_request,
        identifyexecutor=identifyexecutor,getexecutorname=getexecutorname,getfenv=getfenv,setfenv=setfenv}
    local found={}
    local function add(fn) if type(fn)=="function" and not table.find(found,fn) then table.insert(found,fn) end end
    add(direct[name]);add(env[name])
    if name=="request" then
        add(http_request);add(env.http_request)
        for _,namespace in ipairs({http or false,syn or false,env.http or false,env.syn or false}) do
            if type(namespace)=="table" then add(namespace.request) end
        end
    end
    return found
end
function A:executorApi(name) return self:executorApis(name)[1] end
function A:prepareUiChunk(chunk)
    if not Input.TouchEnabled then self.uiMount="Executor GUI parent";return chunk end
    local parent=player:FindFirstChildOfClass("PlayerGui")
    local inspect,bind=self:executorApi("getfenv"),self:executorApi("setfenv")
    if not parent or not inspect or not bind then
        self.uiMount="Executor GUI parent; chunk environment override unavailable";return chunk
    end
    local ok,err=pcall(function()
        local original=inspect(chunk)
        -- The override belongs only to this compiled Rayfield chunk. It does not
        -- replace Delta's global gethui or alter the pinned library source.
        local overlay=setmetatable({gethui=function() return parent end},{__index=original})
        bind(chunk,overlay)
    end)
    self.uiMount=ok and "PlayerGui (mobile)" or "Executor GUI parent; environment override denied"
    if not ok then self:log("Mobile menu parent override unavailable: "..tostring(err)) end
    return chunk
end
function A:executorDetails()
    local identify=self:executorApi("identifyexecutor") or self:executorApi("getexecutorname")
    local name="Unknown executor"
    if identify then
        local ok,label,version=pcall(identify)
        if ok and type(label)=="string" then name=label:sub(1,60)..(type(version)=="string" and " "..version:sub(1,30) or "") end
    end
    local disk=self:executorApi("readfile") and self:executorApi("writefile")
    local handlers=self:executorApi("getconnections")~=nil
    return name..(Input.TouchEnabled and "; touch controls" or "; keyboard controls")
        .."; file APIs "..(disk and "available" or "missing").."; Join introspection "..(handlers and "available" or "missing")
        .."; UI HTTP "..(self.httpTransport or "not loaded")
end
function A:fetchUi(url)
    local ok,body=pcall(function() return game:HttpGet(url) end)
    if ok and type(body)=="string" and body:find("RayfieldLibrary",1,true) then self.httpTransport="HttpGet";return body end
    for _,send in ipairs(self:executorApis("request")) do
        local sent,response=pcall(send,{Url=url,Method="GET"})
        if sent and type(response)=="table" then
            local status=tonumber(response.StatusCode or response.Status)
            local content=response.Body
            if response.Success~=false and (not status or status>=200 and status<300)
                and type(content)=="string" and content:find("RayfieldLibrary",1,true) then
                self.httpTransport="executor request";return content
            end
        end
    end
    error("Unable to download the pinned menu through HttpGet or executor request; check Delta HTTP access")
end

-- All executor output stays in one relative workspace folder. Migration is
-- limited to this account's four known filenames; other files are untouched.
A.storageFolder="EFS Files"
A.storageNote="EFS Files; checking executor folder support"
local function storageAvailable()
    if not A.storageReady then A.storageNote="EFS Files" end
    A.storageReady=true;return true
end
local function readDestination(name,readfile,isfile)
    local ok,bytes=pcall(readfile,name)
    if not ok and type(isfile)=="function" then
        local checked,exists=pcall(isfile,name)
        if not checked or exists then return false,nil,true end
    end
    return ok,bytes,false
end
function A:ensureStorage()
    local isfolder,makefolder,readfile=self:executorApi("isfolder"),self:executorApi("makefolder"),self:executorApi("readfile")
    if type(isfolder)=="function" then
        local ok,exists=pcall(isfolder,self.storageFolder)
        if ok and exists then return storageAvailable() end
    end
    if type(makefolder)=="function" then
        local ok,result=pcall(makefolder,self.storageFolder)
        if ok and result~=false then
            if type(isfolder)~="function" then return storageAvailable() end
            local checked,exists=pcall(isfolder,self.storageFolder)
            if checked and exists then return storageAvailable() end
        end
    end
    -- An existing folder remains usable on executors missing folder queries.
    if type(isfolder)~="function" and type(readfile)=="function" then
        for _,file in ipairs({filename,filename..".bak"}) do if pcall(readfile,file) then return storageAvailable() end end
    end
    self.storageReady=false;self.storageNote="EFS Files folder unavailable; existing files retained"
    return false
end
function A:migrateLegacyFile(source,target,covered)
    local readfile,writefile=self:executorApi("readfile"),self:executorApi("writefile")
    local isfile,delfile=self:executorApi("isfile"),self:executorApi("delfile")
    local prefix="EggFarmAutomation_122156343392096_"..player.UserId
    local allowed=source==prefix..".json" or source==prefix..".json.bak"
        or source==prefix.."_health.json" or source==prefix.."_events.json"
    if not allowed or target~=self.storageFolder.."/"..source then return false end
    if type(readfile)~="function" or type(writefile)~="function" or not self:ensureStorage() then return false end
    local found,bytes=pcall(readfile,source)
    if not found then return true end
    local exists,current,blocked=readDestination(target,readfile,isfile)
    if blocked then self.storageNote="EFS Files; destination unreadable, original retained";return false end
    local destination=target
    local decision=exists and current~=bytes and covered and covered(bytes,current)
    if decision=="keep" then self.storageNote="EFS Files; newer legacy save retained until next load";return false end
    if exists and current~=bytes and decision~=true then
        -- Preserve differing diagnostics or damaged settings under a bounded
        -- archive name, without overwriting the active copy or another archive.
        destination=nil
        for n=1,9 do
            local candidate=self.storageFolder.."/Legacy_"..n.."_"..source
            local present,saved,locked=readDestination(candidate,readfile,isfile)
            if not locked and (not present or saved==bytes) then destination=candidate;exists=present;current=saved;break end
        end
        if not destination then self.storageNote="EFS Files; legacy archive slots full, original retained";return false end
    end
    local ok=pcall(function()
        if not exists then writefile(destination,bytes);assert(readfile(destination)==bytes,"Migration readback mismatch") end
        if type(delfile)~="function" then error("Delete API unavailable; old copy retained") end
        assert(readfile(source)==bytes,"Legacy file changed during migration")
        local saved=readfile(destination)
        assert(saved==(decision==true and current or bytes),"Destination changed during migration")
        assert(delfile(source)~=false,"Legacy cleanup failed")
    end)
    self.storageNote=ok and "EFS Files; legacy files migrated" or "EFS Files; legacy cleanup pending, original retained"
    return ok
end

local function budgetText(n)
    return n[1]==0 and "0" or string.format("%.5ge%.0f",n[1],n[2])
end
local function validHeroBudget(x)
    if type(x)~="table" or type(x.run)~="string" or #x.run<1 or #x.run>120 or type(x.spent)~="table" then return end
    local m,e=x.spent[1],x.spent[2]
    if type(m)~="number" or type(e)~="number" or m~=m or e~=e or m<0 or m>=10 or math.abs(e)>1e12 then return end
    return {run=x.run,spent={m,e}}
end
local function validSettings(x)
    if type(x)~="table" or (x.schema~=2 and x.schema~=3 and x.schema~=4 and x.schema~=5 and x.schema~=6 and x.schema~=7) or x.place~=game.PlaceId or x.user~=player.UserId or type(x.settings)~="table" then return end
    local result=table.clone(defaults)
    for k in pairs(defaults) do if type(x.settings[k])=="boolean" then result[k]=x.settings[k] end end
    if x.settings.hireHeroes==nil and x.schema<5 then result.hireHeroes=x.settings.heroes==true end
    local revision=type(x.revision)=="number" and x.revision>=0 and x.revision<1e12 and math.floor(x.revision) or 0
    return result,revision,validHeroBudget(x.heroBudget),x.autoResetState
end
local function validAutoReset(x)
    if type(x)~="table" or type(x.run)~="string" or #x.run>120 or not x.run:match("^%d+:%d+:%d+$") then return end
    if x.kind~="retire" and x.kind~="rebirth" then return end
    for _,key in ipairs({"before","highest","current","queen","at"}) do
        local n=x[key];if type(n)~="number" or n~=n or n<0 or n>1e15 then return end
    end
    local function count(value,fallback)
        if value==nil then return fallback end
        if type(value)~="number" or value~=value or value%1~=0 or value<0 or value>3 then return 3 end
        return value
    end
    local attempts=math.max(1,count(x.attempts,1))
    local retires=count(x.retireAttempts,x.kind=="retire" and attempts or 0)
    local rebirths=count(x.rebirthAttempts,x.kind=="rebirth" and attempts or 0)
    if x.kind=="retire" then retires=math.max(retires,attempts) else rebirths=math.max(rebirths,attempts) end
    return {run=x.run,kind=x.kind,before=x.before,highest=x.highest,current=x.current,queen=x.queen,at=x.at,
        attempts=x.kind=="retire" and retires or rebirths,retireAttempts=retires,rebirthAttempts=rebirths,
        confirmed=x.confirmed==true,rebuilt=x.rebuilt==true}
end
A.settings=table.clone(defaults);A.settingsRevision=-1
do local readfile=A:executorApi("readfile")
if readfile then for _,file in ipairs({filename,filename..".bak",legacyFilename,legacyFilename..".bak"}) do
    local ok,result=pcall(function() return Http:JSONDecode(readfile(file)) end)
    if ok then local settings,revision,budget,autoReset=validSettings(result)
        if settings and revision>A.settingsRevision then A.settings=settings;A.settingsRevision=revision;A.heroBudget=budget;A.autoResetState=validAutoReset(autoReset) end
    end
end end end
do local settings,revision,budget,autoReset=validSettings(env[SESSION_KEY])
    if settings and revision>A.settingsRevision then A.settings=settings;A.settingsRevision=revision;A.heroBudget=budget;A.autoResetState=validAutoReset(autoReset) end
end
if resumePrevious then for k in pairs(defaults) do if type(resumePrevious[k])=="boolean" then A.settings[k]=resumePrevious[k] end end end
if validHeroBudget(resumeHeroBudget) then A.heroBudget=validHeroBudget(resumeHeroBudget) end
if validAutoReset(resumeAutoReset) then A.autoResetState=validAutoReset(resumeAutoReset) end
A.trophyBuyAttempt=resumeTrophyBuy
function A:refreshRunning()
    self.running=false;for key,on in pairs(self.settings) do if on and not performanceKeys[key] then self.running=true;break end end
end
A:refreshRunning()
A.startupClaim=true -- One execution-time initialization, independent of gameplay toggles.
function A:setFeature(key,enabled)
    if defaults[key]==nil or not self.alive then return end
    self.settings[key]=enabled==true
    if key=="autoRetire" or key=="autoRebirth" then
        self.progressionIntent=nil
        if not self.settings.autoRetire and not self.settings.autoRebirth and self.progressionWatch then
            self.progressionWatch.pausedAt=self.progressionWatch.pausedAt or os.clock()
        end
    end
    if not enabled then
        if key=="blackEggs" and self.clearBlackAllocation then self:clearBlackAllocation() end
        if key=="heroes" then self.heroGoal=nil end
        if key=="hireHeroes" then self.heroHireNote="Disabled" end
        local owners={farm="combat",boss="boss",quest="quest",diamonds="diamond"}
        if owners[key] then self:cancelMovement(owners[key]) end
        if key=="farm" then
            if not self.startupClaim then self:cancelMovement("claim");self.claimAttempt=nil end
            self:cancelMovement("meat");if self.collecting then self.collecting.meat=nil end
        end
        if key=="quest" and not self.settings.diamonds or key=="diamonds" and not self.settings.quest then self:cancelMovement("house") end
        if key=="diamonds" then if self.collecting then self.collecting.diamonds=nil end;self:setDiamondPriority(false) end
        if key=="progress" then self.retreat=nil end
        if key=="abilities" then self.lastAbility=nil;self.decoyFor=nil;self.abilityNote="Disabled" end
        if key=="boxes" then self.boxNote="Disabled" end
        if key=="trophyBoxes" then self.trophyBuyNote="Disabled" end
        if key=="boss" and self.finishEventJoin then self:finishEventJoin("Disabled") end
    end
    if performanceKeys[key] and self.syncPerformance then self:syncPerformance() end
    self:refreshRunning();self:save()
    if self.bindMenus then self:bindMenus() end
end
function A:enableFullAutomation()
    if not self.alive then return end
    self.uiSync=true
    for key in pairs(defaults) do if key~="trophyBoxes" and not performanceKeys[key] then self.settings[key]=true;local control=self.controls and self.controls[key];if control then control:Set(true) end end end
    self.uiSync=false;self.progressionIntent=nil;self:refreshRunning();self:save()
    self:log("Full automation enabled: farming, purchases, retirement and rebirth; ascension stays manual")
end
function A:saveWarning(message)
    self.persistence=message
    if self.lastSaveWarning~=message then self.lastSaveWarning=message;self:log(message);warn("Egg Farm settings: "..message) end
    if self.uiReady and self.rayfield and self.rayfield.Notify and self.notifiedSaveFailure~=message then
        self.notifiedSaveFailure=message
        pcall(function() self.rayfield:Notify({Title="Settings could not save to disk",Content=message..". Your choices are kept for this session.",Duration=8}) end)
    end
end
function A:save()
    self.saveAt=nil
    if self.saving then self.saveAgain=true;return false end
    self.settingsRevision=math.max(0,self.settingsRevision or 0)+1
    local snapshot={};for key in pairs(defaults) do snapshot[key]=self.settings[key]==true end
    local record={schema=7,place=game.PlaceId,user=player.UserId,revision=self.settingsRevision,settings=snapshot,heroBudget=validHeroBudget(self.heroBudget),autoResetState=validAutoReset(self.autoResetState)}
    env[SESSION_KEY]=record
    local readfile,writefile=self:executorApi("readfile"),self:executorApi("writefile")
    if type(writefile)~="function" or type(readfile)~="function" then self:saveWarning("Executor file APIs unavailable; session restore only");return false end
    if not self:ensureStorage() then
        self:saveWarning("EFS Files folder unavailable; session restore only")
        if self.alive then self.saveAt=os.clock()+5 end
        return false
    end
    self.saving=true
    local ok,err=pcall(function()
        local encoded=Http:JSONEncode(record)
        local oldOK,old=pcall(readfile,filename)
        if oldOK then local decodedOK,decoded=pcall(function() return Http:JSONDecode(old) end)
            if decodedOK and validSettings(decoded) then writefile(filename..".bak",old) end
        end
        writefile(filename,encoded);assert(readfile(filename)==encoded,"Settings readback mismatch")
        -- Keep both copies current so a damaged primary cannot resurrect features
        -- that the user explicitly turned off with Disable All.
        writefile(filename..".bak",encoded);assert(readfile(filename..".bak")==encoded,"Backup readback mismatch")
    end)
    self.saving=false
    if ok then
        self.persistence="Autosaved and verified";self.lastSaveWarning=nil;self.notifiedSaveFailure=nil
        local function covered(source,target)
            local sourceOK,sourceRecord=pcall(function() return Http:JSONDecode(source) end)
            local targetOK,targetRecord=pcall(function() return Http:JSONDecode(target) end)
            local sourceSettings,sourceRevision,targetSettings,targetRevision
            if sourceOK then sourceSettings,sourceRevision=validSettings(sourceRecord) end
            if targetOK then targetSettings,targetRevision=validSettings(targetRecord) end
            if sourceSettings and targetSettings then return sourceRevision<=targetRevision and true or "keep" end
            return false
        end
        self:migrateLegacyFile(legacyFilename,filename,covered)
        self:migrateLegacyFile(legacyFilename..".bak",filename..".bak",covered)
    else self:saveWarning(tostring(err));if self.alive then self.saveAt=os.clock()+5 end end
    if self.saveAgain then self.saveAgain=nil;if self.alive then self.saveAt=os.clock() end end
    return ok
end
A:save() -- Migrate old settings and establish automatic persistence before loading UI.
-- Client visual overrides only. No gameplay instances, callbacks or remotes removed.
local lighting
pcall(function() lighting=game:GetService("Lighting") end)
local visuals={records=setmetatable({},{__mode="k"}),pending=setmetatable({},{__mode="k"}),stack={},active=false,changed=0,denied=0}
A.visuals=visuals
local partRules={Material=Enum.Material.Plastic,Reflectance=0,CastShadow=false}
local effectRules={Enabled=false}
local particleRules={Enabled=false,Rate=0}
local textureRules={Texture=""}
local meshRules={TextureId=""}
local meshPartRules={TextureID=""}
local function override(object,rules)
    for property,forced in pairs(rules) do
        local ok,current=pcall(function() return object[property] end)
        if ok and current~=nil and current~=forced then
            local record=visuals.records[object]
            local written=pcall(function() object[property]=forced end)
            if written then
                if not record then record={original={},forced={}};visuals.records[object]=record end
                if record.original[property]==nil then record.original[property]=current end
                record.forced[property]=forced;visuals.changed+=1
            else visuals.denied+=1 end
        end
    end
end
local function applyVisual(object)
    if not visuals.active then return end
    if object:IsA("BasePart") then
        override(object,partRules)
        if object:IsA("MeshPart") then override(object,meshPartRules) end
    elseif object:IsA("ParticleEmitter") then
        override(object,particleRules)
        pcall(function() object:Clear() end)
    elseif object:IsA("Trail") or object:IsA("Beam") or object:IsA("Fire") or object:IsA("Smoke")
        or object:IsA("Sparkles") or object:IsA("PostEffect") or object:IsA("Light") then
        override(object,effectRules)
    elseif object:IsA("Decal") or object:IsA("Texture") then override(object,textureRules)
    elseif object:IsA("SpecialMesh") then override(object,meshRules) end
end
local function stopVisuals()
    visuals.active=false;visuals.stack={};table.clear(visuals.pending)
    local failures=0
    for object,record in pairs(visuals.records) do
        for property,original in pairs(record.original) do
            -- A game/user change after our override owns its current value.
            local readOK,current=pcall(function() return object[property] end)
            if readOK and current==record.forced[property] then
                local restored=pcall(function() object[property]=original end)
                if not restored then failures+=1 else record.original[property]=nil end
            else record.original[property]=nil end
        end
        if not next(record.original) then visuals.records[object]=nil end
    end
    return failures==0
end
local function startVisuals()
    if visuals.active then return end
    visuals.active=true;visuals.changed=0;visuals.denied=0
    -- Walk incrementally instead of keeping a complete world descendant array.
    visuals.stack={{items={workspace,lighting},index=1,count=lighting and 2 or 1}}
    if lighting then override(lighting,{GlobalShadows=false}) end
    local terrain=workspace:FindFirstChildOfClass("Terrain")
    if terrain then override(terrain,{WaterWaveSize=0,WaterWaveSpeed=0,WaterReflectance=0,Decoration=false}) end
    pcall(function()
        local userSettings=UserSettings():GetService("UserGameSettings")
        override(userSettings,{SavedQualityLevel=Enum.SavedQualitySetting.QualityLevel1})
    end)
end
function A:updatePerformanceNote()
    self.performanceNote=visuals.active and ("FPS boost active; "..visuals.changed.." visual overrides"
        ..(#visuals.stack>0 and "; applying initial pass" or "")
        ..(visuals.denied>0 and "; "..visuals.denied.." unsupported writes skipped" or ""))
        or (next(visuals.records) and "Some visual restores failed; retry Restore Graphics" or "Visual changes disabled")
end
function A:performanceStep()
    if not visuals.active or #visuals.stack==0 and not next(visuals.pending) then return end
    for _=1,120 do
        local pending=next(visuals.pending)
        if pending then
            visuals.pending[pending]=nil
            if pending.Parent then pcall(applyVisual,pending) end
            continue
        end
        local frame=visuals.stack[#visuals.stack]
        if not frame then break end
        if frame.index>frame.count then table.remove(visuals.stack)
        else
            local object=frame.items[frame.index];frame.items[frame.index]=nil;frame.index+=1
            if object then
                pcall(applyVisual,object)
                local ok,children=pcall(function() return object:GetChildren() end)
                if ok and #children>0 then table.insert(visuals.stack,{items=children,index=1,count=#children}) end
            end
        end
    end
    self:updatePerformanceNote()
end
local function render(enabled)
    local ok,result=pcall(function() return Run:Set3dRenderingEnabled(enabled) end)
    return ok and result~=false
end
function A:syncPerformance()
    if self.settings.fpsBoost then startVisuals() else stopVisuals() end
    if self.settings.disable3D and not self.renderApplied then
        local ok,prior=pcall(function() return Run:Is3dRenderingEnabled() end)
        if ok and type(prior)=="boolean" then self.renderOriginal=prior else self.renderOriginal=true end
        if render(false) then self.renderApplied=true;self.renderNote=Input.TouchEnabled and "Disabled; 3-finger tap restores view and menu" or "Disabled; GUI and automation active; F8 restores view"
        else
            self.settings.disable3D=false;self.renderNote="Unavailable: executor rejected the 3D rendering API"
            local control=self.controls and self.controls.disable3D
            if control then self.uiSync=true;pcall(function() control:Set(false) end);self.uiSync=false end
        end
    elseif not self.settings.disable3D and self.renderApplied then
        if render(true) then self.renderApplied=false;self.renderOriginal=nil;self.renderNote="Enabled"
        else self.renderNote="Restore failed; use Restore Graphics, F8 or a 3-finger tap to retry" end
    elseif not self.renderApplied and not self.renderNote then self.renderNote="Unchanged; no rendering override" end
    self:updatePerformanceNote()
end
function A:restoreGraphics()
    if not self.alive then return end
    self.settings.fpsBoost=false;self.settings.disable3D=false
    self:syncPerformance()
    -- An explicit rescue action also restores rendering changed by another tool.
    if render(true) then self.renderApplied=false;self.renderOriginal=nil;self.renderNote="Enabled" end
    self.uiSync=true
    for _,key in ipairs({"fpsBoost","disable3D"}) do
        local control=self.controls and self.controls[key];if control then pcall(function() control:Set(false) end) end
    end
    self.uiSync=false;self:refreshRunning();self:save()
end
for _,root in ipairs(lighting and {workspace,lighting} or {workspace}) do
    A:connect(root.DescendantAdded,function(object) if visuals.active then visuals.pending[object]=true end end)
end
A:connect(Run.Heartbeat,function() A:performanceStep() end)
function A:restoreView()
    if not self.alive then return end
    self.settings.disable3D=false;self:syncPerformance()
    if render(true) then self.renderApplied=false;self.renderOriginal=nil;self.renderNote="Enabled" end
    if self.controls and self.controls.disable3D then
        self.uiSync=true;pcall(function() self.controls.disable3D:Set(false) end);self.uiSync=false
    end
    self:refreshRunning();self:save()
end
A:connect(Input.InputBegan,function(input)
    if input.KeyCode==Enum.KeyCode.F8 and not Input:GetFocusedTextBox() then
        A:restoreView()
    end
end)
-- TouchTap covers taps on UI as well as the world. This rescue intentionally
-- remains available when the game/UI consumed the gesture or the menu is hidden.
if Input.TouchEnabled then
    A:connect(Input.TouchTap,function(positions)
        if type(positions)~="table" or #positions~=3 or Input:GetFocusedTextBox() then return end
        A:restoreView()
        if A.rayfield and type(A.rayfield.SetVisibility)=="function" then pcall(function() A.rayfield:SetVisibility(true) end) end
    end)
end
table.insert(A.cleanup,function()
    local restored=stopVisuals()
    if A.renderApplied then
        if render(A.renderOriginal~=false) then A.renderApplied=false;A.renderOriginal=nil
        else error("3D restore failed; retry Unload") end
    end
    if not restored then error("Visual restore failed; retry Unload") end
end)
A:syncPerformance()
-- A rejected saved rendering preference is cleared, rather than displayed as active.
if A.settings.disable3D==false and A.renderNote:find("Unavailable",1,true) then A:save() end

-- Official Rayfield, pinned and inspected. The library owns dragging and reopening.
local RAYFIELD_URL="https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/61a839fb9941c195cfea614d13313a5ca433fcbb/source.lua"
A.controls={}
function A:debugDetails()
    local detail={"Egg Farm 3.1.13",tostring(self.status or "Waiting for startup")}
    local goal=self.heroGoal
    local goalText=type(goal)=="table" and ("Hero "..tostring(goal.id or "?").." toward level "..tostring(goal.targetLevel or "?")..(goal.upgrade and "; upgrade "..tostring(goal.upgrade) or "")) or tostring(goal or "None")
    local fields={
        {"Executor",self:executorDetails()},
        {"Menu startup",(self.uiStage or "Starting")..(self.uiError and "; "..self.uiError or "")},
        {"Menu parent",self.uiMount or "Not mounted"},
        {"Settings",self.persistence or "Pending"},
        {"Files",self.storageNote or "EFS Files"},
        {"Data source",self.receivedDataEvent and "Server Data event" or "Native cache; waiting for the next server update"},
        {"Runtime health",self.healthNote or "Waiting for the first sample"},
        {"Performance",self.performanceNote or "Visual changes disabled"},
        {"3D rendering",self.renderNote or "Enabled"},
        {"Farm claim",self.claimNote or "Waiting for startup"},
        {"Stage progression",self.stageNote or "Waiting for stage data"},
        {"Heroes",self.heroNote or "Idle"},
        {"Hiring",self.heroHireNote or "Waiting for hero data"},
        {"Hero goal",goalText},
        {"Weak hero budget",self.heroBudgetNote or "Waiting for authoritative eggs"},
        {"Abilities",self.abilityNote or "Idle"},
        {"Boxes",self.boxNote or "Idle"},
        {"Trophy Box buying",self.trophyBuyNote or "Disabled"},
        {"Event",self.eventNote or "Waiting for invitation"},
        {"Rocket boarding",self.rocketNote or "Waiting for a live rocket countdown"},
        {"Event history",self.eventHistoryDetails and self:eventHistoryDetails() or "Starting event monitor"},
        {"Event history file",self.eventHistoryDisk or "No new event records to save"},
        {"Progression",self.progressionNote or "Automatic resets disabled"},
        {"Reset recovery",self.resetRetryNote or "No unconfirmed reset"},
        {"Egg spending",self.eggNote or "Disabled"},
        {"Reset",self.resetNote or "No request"},
        {"Diamonds",self.diamondNote or "No blocker"},
        {"Quest",self.questNote or "Idle"}
    }
    for _,field in ipairs(fields) do table.insert(detail,field[1]..": "..tostring(field[2])) end
    if type(self.logs)=="table" then for _,line in ipairs(self.logs) do table.insert(detail,tostring(line)) end end
    if self.eventHistory then
        table.insert(detail,"Recent event observations:")
        for _,entry in ipairs(self.eventHistory.entries) do
            table.insert(detail,os.date("!%Y-%m-%d %H:%M:%S UTC",entry.at).." "..entry.action.." ["..entry.kind.."] "..entry.detail)
        end
    end
    return table.concat(detail,"\n")
end
function A:copyDebugDetails()
    local detail=self:debugDetails()
    local clipboardFunctions={}
    local function add(fn) if type(fn)=="function" and not table.find(clipboardFunctions,fn) then table.insert(clipboardFunctions,fn) end end
    add(setclipboard);add(toclipboard);add(set_clipboard)
    add(env.setclipboard);add(env.toclipboard);add(env.set_clipboard)
    for _,copy in ipairs(clipboardFunctions) do
        local ok,result=pcall(copy,detail)
        if ok and result~=false then
            if self.rayfield and type(self.rayfield.Notify)=="function" then pcall(function() self.rayfield:Notify({Title="Debug details copied",Content="Paste the copied details into chat.",Duration=5}) end) end
            return true,detail
        end
    end
    local shown=false
    if self.debugOptionsTab then
        shown=pcall(function()
            local paragraph={Title="Debug details",Content=detail}
            if self.debugParagraph then self.debugParagraph:Set(paragraph)
            else self.debugParagraph=self.debugOptionsTab:CreateParagraph(paragraph) end
        end)
    end
    pcall(warn,detail)
    if self.rayfield and type(self.rayfield.Notify)=="function" then pcall(function()
        self.rayfield:Notify({Title="Debug details",Content=shown and "Clipboard unavailable. Scroll down in Options to read the details." or "Clipboard unavailable. Full details were printed to the executor console.",Duration=8})
    end) end
    return false,detail
end
table.insert(A.cleanup,function()
    if A.uiOverride and env.DISABLE_RAYFIELD_REQUESTS==true then env.DISABLE_RAYFIELD_REQUESTS=A.uiOverride.original end
    A.uiOverride=nil
    if A.rayfield then A.rayfield:Destroy();A.rayfield=nil end
end)
local uiTask=task.spawn(function()
    local original=env.DISABLE_RAYFIELD_REQUESTS
    local ownsOverride=false
    local ok,err=pcall(function()
        A:setUiStage("Downloading pinned Rayfield menu")
        local compile=A:executorApi("loadstring")
        assert(type(compile)=="function","Your executor must support loadstring for Rayfield")
        local source=A:fetchUi(RAYFIELD_URL)
        assert(type(source)=="string" and source:find("RayfieldLibrary",1,true),"Rayfield download returned unexpected content")
        A:setUiStage("Compiling Rayfield")
        local chunk,compileError=compile(source,"Rayfield-pinned")
        assert(type(chunk)=="function",compileError or "Compiler did not return a function")
        A:prepareUiChunk(chunk)
        A:setUiStage("Loading Rayfield interface asset")
        A.uiOverride={original=original};env.DISABLE_RAYFIELD_REQUESTS=true;ownsOverride=true
        local library=chunk()
        if env.DISABLE_RAYFIELD_REQUESTS==true then env.DISABLE_RAYFIELD_REQUESTS=original end;ownsOverride=false;A.uiOverride=nil
        assert(type(library)=="table" and type(library.CreateWindow)=="function","Rayfield did not return its library")
        A.rayfield=library
        if not A.alive then A.rayfield:Destroy();A.rayfield=nil;return end
        A.uiSync=true
        A:setUiStage("Creating Egg Farm window")
        local window=A.rayfield:CreateWindow({
            Name="Egg Farm",LoadingTitle="Egg Farm",LoadingSubtitle="Automation",
            ShowText="Egg Farm",Theme="Default",ToggleUIKeybind=Enum.KeyCode.RightControl,
            DisableRayfieldPrompts=true,DisableBuildWarnings=false,
            ConfigurationSaving={Enabled=false},Discord={Enabled=false},KeySystem=false
        })
        local farmTab=window:CreateTab("Farm",0)
        local upgradesTab=window:CreateTab("Upgrades",0)
        local optionsTab=window:CreateTab("Options",0)
        A.debugOptionsTab=optionsTab
        local function toggle(tab,key,label)
            A.controls[key]=tab:CreateToggle({Name=label,CurrentValue=A.settings[key],Flag="EggFarm2_"..key,
                Callback=function(enabled) if A.alive and not A.uiSync then A:setFeature(key,enabled) end end})
        end
        farmTab:CreateSection("Turn each feature on or off")
        farmTab:CreateButton({Name="Enable Full Automation — Through Rebirth",Callback=function() A:enableFullAutomation() end})
        toggle(farmTab,"farm","Farm Chickens + Collect Meat — Loop Teleport")
        toggle(farmTab,"progress","Auto Next Level / Boss Recovery")
        toggle(farmTab,"diamonds","Collect Diamonds First — Pause Chicken Farming")
        toggle(farmTab,"hireHeroes","Auto Hire Heroes — Prioritize All Affordable Hires")
        toggle(farmTab,"heroes","Smart Heroes — Efficient Progression")
        toggle(farmTab,"equipment","Equip Best Owned Gear")
        toggle(farmTab,"abilities","Smart Abilities — Save Combat Skills for Hard Bosses")
        toggle(farmTab,"rewards","Claim Achievement Rewards")
        toggle(farmTab,"quest","Complete Pumpkin Quest")
        toggle(farmTab,"boss","Auto Join + Fight Event Boss — Loop Teleport")
        upgradesTab:CreateSection("Owned boxes")
        toggle(upgradesTab,"boxes","Open All Owned Boxes")
        upgradesTab:CreateSection("Diamond purchases — saved choice")
        toggle(upgradesTab,"trophyBoxes","Auto Buy Trophy Boxes — Spend Diamonds")
        upgradesTab:CreateSection("Smart progression — saved automatic choices")
        toggle(upgradesTab,"autoRetire","Smart Auto Retire — Prepare Heroes at a Progress Wall")
        toggle(upgradesTab,"autoRebirth","Smart Auto Rebirth — Gold Egg Targets")
        toggle(upgradesTab,"blackEggs","Smart Spend Black Eggs — Damage + Progression")
        toggle(upgradesTab,"goldEggs","Smart Spend Gold Eggs — Stage Allocation")
        upgradesTab:CreateSection("Manual actions — each click resets progression")
        upgradesTab:CreateButton({Name="Retire — Queen Elizabeth II Level 150",Callback=function() A:performReset("retire") end})
        upgradesTab:CreateButton({Name="Rebirth — Beat Level 300",Callback=function() A:performReset("rebirth") end})
        upgradesTab:CreateButton({Name="Ascend — Beat Level 50,000",Callback=function() A:performReset("ascend") end})
        if Input.TouchEnabled then
            optionsTab:CreateParagraph({Title="Mobile controls",Content="Tap Show Egg Farm to reopen the menu. Tap the screen with three fingers to restore 3D and show the menu; farming stays enabled."})
        end
        optionsTab:CreateSection("Performance — saved choices")
        toggle(optionsTab,"fpsBoost","FPS Boost — Low Graphics + Reduce Effects")
        toggle(optionsTab,"disable3D",Input.TouchEnabled and "Disable 3D Rendering — 3-Finger Tap Restores View" or "Disable 3D Rendering — F8 Restores View")
        optionsTab:CreateButton({Name="Restore Graphics + 3D Rendering",Callback=function() A:restoreGraphics() end})
        optionsTab:CreateSection("Controller")
        optionsTab:CreateButton({Name="Disable All Features",Callback=function() A:Stop() end})
        optionsTab:CreateButton({Name="Copy Debug Details",Callback=function() A:copyDebugDetails() end})
        optionsTab:CreateButton({Name="Unload",Callback=function() A:Unload() end})
        A.uiSync=false;A.uiReady=true
        if type(A.rayfield.SetVisibility)=="function" then pcall(function() A.rayfield:SetVisibility(true) end) end
        A:setUiStage("Menu ready");A:closeStartupPanel()
        if A.lastSaveWarning then A:saveWarning(A.lastSaveWarning) end
    end)
    if ownsOverride and env.DISABLE_RAYFIELD_REQUESTS==true then env.DISABLE_RAYFIELD_REQUESTS=original end
    A.uiOverride=nil
    if not ok and A.alive then
        A.uiReady=false;A.uiSync=false;A.uiFailed=true;A.status="Menu startup failed; see on-screen error"
        if A.rayfield then local cleaned=pcall(function() A.rayfield:Destroy() end);if cleaned then A.rayfield=nil end end
        A:cancelMovement();A:setUiStage(A.uiStage or "Starting Rayfield",err)
        warn("Egg Farm: Rayfield failed to load: "..tostring(err)..". Reexecute to retry.")
    end
end)
table.insert(A.tasks,uiTask)
table.insert(A.tasks,task.delay(40,function()
    if A.alive and not A.uiReady and not A.uiFailed then
        if coroutine.status(uiTask)~="dead" then pcall(task.cancel,uiTask) end
        if A.uiOverride and env.DISABLE_RAYFIELD_REQUESTS==true then env.DISABLE_RAYFIELD_REQUESTS=A.uiOverride.original end
        A.uiOverride=nil
        A.uiFailed=true;A:cancelMovement();A.status="Menu startup timed out; see on-screen error"
        A:setUiStage(A.uiStage or "Starting Rayfield","Timed out after 40 seconds. Reexecute to retry.")
        warn("Egg Farm: Rayfield startup timed out. Reexecute to retry.")
    end
end))

if not A.alive then return A end
local M,P,Events
A.ledger=Core.ledger(os.clock,function(message) A:log(message) end)
-- Five-minute, bounded diagnostics. These are client-wide memory readings,
-- not a measurement of memory attributable to this script alone.
local HEALTH_FILE=filename:gsub("%.json$","_health.json")
A:migrateLegacyFile(legacyFilename:gsub("%.json$","_health.json"),HEALTH_FILE)
local function entryCount(t)
    local count=0;for _ in pairs(t or {}) do count+=1 end;return count
end
function A:sampleHealth()
    if not self.alive then return end
    local writefile=self:executorApi("writefile")
    local function reading(fn)
        local ok,n=pcall(fn)
        if ok and type(n)=="number" and n==n and n>=0 and n<math.huge then return n end
    end
    local sample={at=os.time(),uptime=math.floor(os.clock()-(self.loadedAt or os.clock())),
        connections=0,tasks=0,pending=entryCount(self.ledger.pending),uncertain=entryCount(self.ledger.uncertain),
        logs=#self.logs,invitations=entryCount(self.eventInvites),pickups=entryCount(self.collectBackoff)}
    for _,connection in pairs(self.connections) do if connection.Connected then sample.connections+=1 end end
    for _,connection in pairs(self.menuConnections) do if connection.Connected then sample.connections+=1 end end
    if self.startupPanel then for _,connection in ipairs(self.startupPanel.connections) do if connection.Connected then sample.connections+=1 end end end
    for _,thread in pairs(self.tasks) do if coroutine.status(thread)~="dead" then sample.tasks+=1 end end
    if self.blackPlanning and self.blackPlanning.thread and coroutine.status(self.blackPlanning.thread)~="dead" then sample.tasks+=1 end
    local trackingOK,tracking=pcall(function() return game:GetService("Stats").MemoryTrackingEnabled end)
    if trackingOK and type(tracking)=="boolean" then sample.memoryTracking=tracking end
    if sample.memoryTracking~=false then sample.clientMB=reading(function() return game:GetService("Stats"):GetTotalMemoryUsageMb() end) end
    sample.luaMB=reading(function() return gcinfo()/1024 end)
    sample.instances=reading(function() return game:GetService("Stats").InstanceCount end)
    local history=self.health or {samples={}};self.health=history
    history.first=history.first or sample;table.insert(history.samples,sample)
    if #history.samples>24 then table.remove(history.samples,1) end
    local function memory(n) return n and string.format("%.1f MB",n) or "unavailable" end
    self.healthNote="Client "..memory(sample.clientMB)..(sample.memoryTracking==false and " (memory tracking disabled)" or "").."; Lua heap "..memory(sample.luaMB)
        .."; controller connections "..sample.connections..", tasks "..sample.tasks..", pending "..sample.pending
        .."; first client reading "..memory(history.first.clientMB)
    if type(writefile)=="function" and self:ensureStorage() then
        local ok=pcall(function()
            writefile(HEALTH_FILE,Http:JSONEncode({schema=1,place=game.PlaceId,user=player.UserId,
                first=history.first,samples=history.samples}))
        end)
        history.disk=ok and "Saved" or "Write unavailable"
    else history.disk="File API unavailable" end
end

-- Small, per-player audit of actual event observations. No GUI instances,
-- callbacks, inventory snapshots or unbounded log history are persisted.
local EVENT_HISTORY_FILE=filename:gsub("%.json$","_events.json")
local LEGACY_EVENT_HISTORY_FILE=legacyFilename:gsub("%.json$","_events.json")
local eventCounters={invite="seen",attempt="attempts",confirmed="joined",timeout="timeouts",empty_launch="emptyLaunches"}
local eventActions={invite=true,attempt=true,boarding=true,confirmed=true,timeout=true,empty_launch=true,ended=true,
    blocked=true,unmatched=true,announcement=true,reward=true,cancelled=true,dispatch_error=true}
local function validEventHistory(record)
    if type(record)~="table" or record.schema~=1 or record.place~=game.PlaceId or record.user~=player.UserId then return end
    local clean={entries={}}
    for _,field in pairs(eventCounters) do
        local n=record[field]
        clean[field]=type(n)=="number" and n==n and n>=0 and n<1e12 and math.floor(n) or 0
    end
    local auto=record.autoJoined
    clean.autoJoined=type(auto)=="number" and auto==auto and auto>=0 and auto<1e12 and math.min(clean.joined,math.floor(auto)) or 0
    local entries=type(record.entries)=="table" and record.entries or {}
    for index=math.max(1,#entries-39),#entries do
        local entry=entries[index]
        if type(entry)=="table" and eventActions[entry.action] and type(entry.at)=="number" and entry.at==entry.at
            and entry.at>=0 and entry.at<=os.time()+86400 and type(entry.kind)=="string" and type(entry.detail)=="string" then
            table.insert(clean.entries,{at=entry.at,action=entry.action,kind=entry.kind:sub(1,40),detail=entry.detail:sub(1,600),automatic=entry.automatic==true})
            if #clean.entries>40 then table.remove(clean.entries,1) end
        end
    end
    if type(record.lastJoinedAt)=="number" and record.lastJoinedAt==record.lastJoinedAt and record.lastJoinedAt>=0 and record.lastJoinedAt<=os.time()+86400 then clean.lastJoinedAt=record.lastJoinedAt end
    return clean
end
A.eventHistory=validEventHistory(resumeEventHistory)
do local readfile=A:executorApi("readfile")
if not A.eventHistory and type(readfile)=="function" then
    local latest=-1
    for _,file in ipairs({EVENT_HISTORY_FILE,LEGACY_EVENT_HISTORY_FILE}) do
        local ok,record=pcall(function() return Http:JSONDecode(readfile(file)) end)
        local valid=ok and validEventHistory(record)
        if valid then
            local at=valid.lastJoinedAt or 0
            for _,entry in ipairs(valid.entries) do at=math.max(at,entry.at) end
            if at>latest then A.eventHistory=valid;latest=at;if file==LEGACY_EVENT_HISTORY_FILE then A.eventHistoryDirty=os.clock()+1 else A.eventHistoryDirty=nil end end
        end
    end
end end
A.eventHistory=A.eventHistory or {entries={},seen=0,attempts=0,joined=0,autoJoined=0,timeouts=0,emptyLaunches=0}
A:migrateLegacyFile(LEGACY_EVENT_HISTORY_FILE,EVENT_HISTORY_FILE)
function A:eventHistoryDetails()
    local h=self.eventHistory
    if not h then return "No event history yet" end
    local last=h.lastJoinedAt and os.date("!%Y-%m-%d %H:%M:%S UTC",h.lastJoinedAt) or "none recorded"
    return "Invitations "..h.seen.."; attempts "..h.attempts.."; confirmed entries "..h.joined.." (after automatic attempt "..tostring(h.autoJoined or 0)..")"
        .."; timeouts "..h.timeouts.."; empty launches "..h.emptyLaunches.."; last entry "..last
end
function A:flushEventHistory()
    if not self.eventHistoryDirty then return end
    self.eventHistoryDirty=nil
    local writefile=self:executorApi("writefile")
    if type(writefile)~="function" or not self:ensureStorage() then self.eventHistoryDisk="Session only; EFS Files storage unavailable";return end
    local h=self.eventHistory
    local ok=pcall(function()
        writefile(EVENT_HISTORY_FILE,Http:JSONEncode({schema=1,place=game.PlaceId,user=player.UserId,entries=h.entries,
            seen=h.seen,attempts=h.attempts,joined=h.joined,autoJoined=h.autoJoined or 0,timeouts=h.timeouts,emptyLaunches=h.emptyLaunches,lastJoinedAt=h.lastJoinedAt}))
    end)
    self.eventHistoryDisk=ok and "Saved to "..EVENT_HISTORY_FILE or "Event history write failed"
    if not ok then self.eventHistoryDirty=os.clock()+30 end
end
function A:recordEvent(action,kind,detail,automatic)
    if not eventActions[action] then return end
    local h=self.eventHistory
    local field=eventCounters[action];if field then h[field]+=1 end
    local entry={at=os.time(),action=action,kind=tostring(kind or "Event"):sub(1,40),detail=tostring(detail or ""):sub(1,600),automatic=automatic==true}
    if action=="confirmed" then h.lastJoinedAt=entry.at;if automatic then h.autoJoined=(h.autoJoined or 0)+1 end end
    table.insert(h.entries,entry);if #h.entries>40 then table.remove(h.entries,1) end
    self.eventHistoryDirty=self.eventHistoryDirty or os.clock()+1
    self:log("Event "..action.." ["..entry.kind.."] "..entry.detail)
end
function A:eventMessage(verb,...)
    if verb~="Announcement" and verb~="Server" and verb~="Notification" then return end
    local pieces={}
    for _,value in ipairs({...}) do if type(value)=="string" then table.insert(pieces,value:sub(1,300)) end end
    local text=table.concat(pieces," "):sub(1,600);local lower=text:lower()
    local kind=lower:find("pumpkin",1,true) and "Pumpkin" or lower:find("alien",1,true) and "Alien"
        or (lower:find("egg rocket",1,true) or lower:find("eggrocket",1,true)) and "Egg Rocket"
    if not kind then return end
    local action=lower:find("without any passengers",1,true) and "empty_launch"
        or (lower:find("reward",1,true) or lower:find("defeated",1,true)) and "reward" or "announcement"
    self:recordEvent(action,kind,"Native "..verb..": "..text)
    if kind=="Egg Rocket" and self.rocketMessage then self:rocketMessage(text,action) end
end

-- Suppress only responses to our purchases. Native E/Train and deliberate
-- menu navigation remain manual; purchases yield while a manual panel is open.
local MENU_FAMILIES={Heroes="heroes",Upgrades="heroes",Hatch="black",Boost="gold",Boost3="platinum",Deal="shop",Prestige="reset",Superprestige="reset",Ascension="reset",Respec="reset",Refund="reset"}
A.menuConnections={}
A.manualFrames=setmetatable({},{__mode="k"});A.manualFamilyUntil={}
table.insert(A.cleanup,function()
    for _,c in ipairs(A.menuConnections) do c:Disconnect() end
    A.menuConnections={};A.menuRoot=nil
end)
function A:manualMenuOpen(family)
    if (self.manualInputUntil or 0)>os.clock() then return true,"native input" end
    for frame,owner in pairs(self.manualFrames) do
        if frame.Parent and frame.Visible and (not family or owner==family) then return true,frame.Name end
    end
    for owner,untilTime in pairs(self.manualFamilyUntil) do if (not family or owner==family) and untilTime>os.clock() then return true,"menu navigation" end end
    return false
end
function A:recordManualMenu(frame,name)
    local family=MENU_FAMILIES[name]
    -- The native upgrade response can open this panel after our quiet window.
    -- Visibility alone is not evidence that the player requested manual control.
    if name~="Upgrades" or self:manualMenuOpen(family) then self.manualFrames[frame]=family end
end
function A:manualMenuIntent()
    self.manualInputUntil=os.clock()+1
    -- Adopt an already-visible automatic panel as soon as the user interacts.
    if self.bindMenus then self:bindMenus() end
end
function A:quietMenu(name)
    -- Our direct Train/Hire calls do not set the native u1 reopen flag.
    if name=="Heroes" then return false end
    local family=MENU_FAMILIES[name]
    if not family or self:manualMenuOpen(family) then return false end
    if not Input:GetFocusedTextBox() and (Input:IsKeyDown(Enum.KeyCode.E) or Input:IsKeyDown(Enum.KeyCode.ButtonY)) then
        self.manualInputUntil=os.clock()+1;return false
    end
    return ((self.quietUntil or {})[family] or 0)>os.clock()
end
A:connect(Input.InputBegan,function(input,processed)
    if not processed and not Input:GetFocusedTextBox() and (input.KeyCode==Enum.KeyCode.E or input.KeyCode==Enum.KeyCode.ButtonY) then
        A:manualMenuIntent()
    elseif input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        local gui=player:FindFirstChildOfClass("PlayerGui");local pos=input.Position
        if not gui or not pos then return end
        for _,object in ipairs(gui:GetGuiObjectsAtPosition(pos.X,pos.Y)) do
            local current=object
            while current and current~=gui do
                if current==A.menuRoot or current.Name=="Gui" and current.Parent==gui then A:manualMenuIntent();return end
                current=current.Parent
            end
        end
    end
end)
function A:bindMenus()
    local gui=player:FindFirstChildOfClass("PlayerGui")
    local menus=gui and gui:FindFirstChild("Menus")
    if self.menuRoot~=menus then
        for _,c in ipairs(self.menuConnections) do c:Disconnect() end
        self.menuConnections={};self.menuRoot=menus;self.menuFrames={};self.menuLinks={}
        self.manualFrames=setmetatable({},{__mode="k"});self.manualFamilyUntil={}
    end
    if not menus then return end
    self.menuFrames=self.menuFrames or {}
    for _,name in ipairs({"Heroes","Upgrades","Hatch","Boost","Boost3","Deal","Boxes","Prestige","Superprestige","Ascension","Respec","Refund"}) do
        local frame=menus:FindFirstChild(name)
        if frame and self.menuFrames[name]~=frame then
            local old=self.menuLinks and self.menuLinks[name]
            if old then old:Disconnect();local at=table.find(self.menuConnections,old);if at then table.remove(self.menuConnections,at) end end
            self.menuFrames[name]=frame
            local c=frame:GetPropertyChangedSignal("Visible"):Connect(function()
                if not self.alive or not frame.Parent then return end
                if frame.Visible then
                    if self:quietMenu(name) then frame.Visible=false
                    else self:recordManualMenu(frame,name) end
                elseif self.manualFrames[frame] then
                    self.manualFrames[frame]=nil;self.manualFamilyUntil[MENU_FAMILIES[name]]=os.clock()+0.35
                end
            end)
            self.menuLinks=self.menuLinks or {};self.menuLinks[name]=c;table.insert(self.menuConnections,c)
        end
        if frame and frame.Visible then
            if self:quietMenu(name) then frame.Visible=false else self:recordManualMenu(frame,name) end
        end
    end
end
function A:remote(name,...)
    if not self.alive or not self.running and not (name=="Turing" and self.startupClaim) then return end
    local family=name=="Heroes" and "heroes" or name=="EasterEggs" and "black" or name=="PhoenixEggs" and "gold" or nil
    if name=="Heroes" and select(1,...)~="Upgrade" then family=nil end
    if family then self.quietUntil=self.quietUntil or {};self.quietUntil[family]=os.clock()+15;self:bindMenus() end
    local remote=Events and Events:FindFirstChild(name)
    if not remote or not remote:IsA("RemoteEvent") then error("Missing native remote: "..name) end
    remote:FireServer(...)
end
function A:character()
    local c=player.Character; local h=c and c:FindFirstChildOfClass("Humanoid"); local root=c and c:FindFirstChild("HumanoidRootPart")
    if h and root and h.Health>0 then return c,h,root end
    return nil
end
function A:teleport(target,owner,priority,range,hug,point,facingPoint)
    local c,h,root=self:character();if not c or not target or not target.Parent then return false end
    local now=os.clock();local previous=self.movement
    if previous and previous.owner~=owner and previous.priority>priority and now-previous.updated<0.25 then return false end
    if h.Sit or h.SeatPart then h.Sit=false;h:ChangeState(Enum.HumanoidStateType.Jumping) end
    local dest=point or target.Position
    local contact=owner=="meat" or owner=="diamond"
    local goal=point or dest+Vector3.new(0,0.5,2.25)
    if contact then goal=dest+Vector3.new(0,math.min(0.25,target.Size.Y*0.15),0) end
    local distance=(root.Position-dest).Magnitude
    local close=distance<=range
    if contact then close=Vector3.new(root.Position.X-dest.X,0,root.Position.Z-dest.Z).Magnitude<0.5 and math.abs(root.Position.Y-dest.Y)<=(h.HipHeight or 2)+root.Size.Y end
    self.movement={owner=owner,priority=priority,target=target,updated=now,character=c}
    -- Refresh the target's CURRENT position even when already in range.
    if self:due("teleport-"..owner,0.08) and (hug or not close) then
        local facing=facingPoint or dest
        if contact then facing=goal+Vector3.new(0,0,-1) end
        root.CFrame=CFrame.lookAt(goal,facing)
        root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero
    end
    return close -- only an observation before this dispatch can establish arrival
end
local function value(part,name)
    local v=part and part:FindFirstChild(name); return v and v.Value
end
local function health(part)
    if not part or not part.Parent or not part:IsA("BasePart") then return nil end
    if part:GetAttribute("Depleted")==true or part:GetAttribute("Dead")==true then return -math.huge end
    local v=value(part,"Health") or value(part,"Life")
    if type(v)=="string" then local ok,n=pcall(M.BigNum.Decode,v); return ok and Core.log(n) or nil end
    if type(v)=="number" then return Core.log(v) end
    return nil
end
function A:scan()
    -- Weak instance keys alone do not bound records whose objects remain alive.
    for _,field in ipairs({"collectBackoff","claimBackoff"}) do
        for object,untilTime in pairs(self[field] or {}) do
            if not object.Parent or untilTime<=os.clock() then self[field][object]=nil end
        end
    end
    local oldFarm=self.farm
    local farms=workspace:FindFirstChild("Farms")
    self.farm=nil
    self.farms=farms and farms:GetChildren() or {}
    for _,farm in ipairs(self.farms) do if value(farm,"Owner")==player then self.farm=farm; break end end
    if self.farm then
        if self.startupClaim then self:log("Farm ownership confirmed");self.status="Farm ready" end
        self.startupClaim=false;self.claimAttempt=nil;self.claimNote="Farm ownership confirmed";self:cancelMovement("claim")
    end
    if oldFarm~=self.farm then self:setDiamondPriority(false);self.collecting={};self:cancelMovement() end
    local candidates={}
    local template=RS:FindFirstChild("Meat"); local center=self.farm and self.farm:FindFirstChild("Hatch")
    if center and template then
        local position=center.Position+center.CFrame.LookVector*24
        for _,child in ipairs(workspace:GetChildren()) do
            if child.Name==template.Name and child:IsA("BasePart") and (child.Position-position).Magnitude<15 then table.insert(candidates,child) end
        end
    end
    self.meats=candidates
end
local function claimBridge(farm)
    local bridges=farm:FindFirstChild("Bridges")
    local bridge=bridges and bridges:FindFirstChild("Bridge")
    local hatch=farm:FindFirstChild("Hatch")
    if not bridge or not hatch or not hatch:IsA("BasePart") then return end
    local parts,collision={},{}
    if bridge:IsA("BasePart") then table.insert(parts,bridge) end
    for _,part in ipairs(bridge:GetDescendants()) do
        if part:IsA("BasePart") then
            table.insert(parts,part)
            if part.Name=="PlanksCollision" then table.insert(collision,part) end
        end
    end
    if #collision>0 then parts=collision end
    local anchor,area=nil,0
    for _,part in ipairs(parts) do
        local footprint=part.Size.X*part.Size.Z
        if footprint>area then anchor,area=part,footprint end
    end
    if anchor then return bridge,anchor,hatch,parts end
end
local function bridgeRoute(bridge,anchor,hatch,parts,clearance)
    local cf=anchor.CFrame
    local minX,maxX,minZ,maxZ=math.huge,-math.huge,math.huge,-math.huge
    for _,part in ipairs(parts) do
        for _,x in ipairs({-0.5,0.5}) do for _,y in ipairs({-0.5,0.5}) do for _,z in ipairs({-0.5,0.5}) do
            local corner=cf:PointToObjectSpace(part.CFrame:PointToWorldSpace(Vector3.new(part.Size.X*x,part.Size.Y*y,part.Size.Z*z)))
            minX=math.min(minX,corner.X);maxX=math.max(maxX,corner.X)
            minZ=math.min(minZ,corner.Z);maxZ=math.max(maxZ,corner.Z)
        end end end
    end
    local centerX,centerZ=(minX+maxX)/2,(minZ+maxZ)/2
    local toward=cf:PointToObjectSpace(hatch.Position)
    local outsideX=math.max(0,math.abs(toward.X-centerX)-(maxX-minX)/2)
    local outsideZ=math.max(0,math.abs(toward.Z-centerZ)-(maxZ-minZ)/2)
    local alongX=maxX-minX>maxZ-minZ
    if math.max(outsideX,outsideZ)>0.5 then alongX=outsideX>outsideZ end
    local a=cf:PointToWorldSpace(Vector3.new(alongX and minX or centerX,0,alongX and centerZ or minZ))
    local b=cf:PointToWorldSpace(Vector3.new(alongX and maxX or centerX,0,alongX and centerZ or maxZ))
    -- Hatch indicates which side is INSIDE the farm. It is never a claim target.
    if (a-hatch.Position).Magnitude<(b-hatch.Position).Magnitude then a,b=b,a end
    local span=b-a;if span.Magnitude<1 then return end
    local direction=span.Unit
    local outside=a-direction*3;local inside=b+direction*3
    local count=math.ceil((inside-outside).Magnitude/1.25)
    local points={}
    for i=0,count do
        local position=outside+(inside-outside)*(i/count)
        local surface,nearest=nil,math.huge
        for _,part in ipairs(parts) do
            local p=part.CFrame:PointToObjectSpace(position)
            local x,z=math.clamp(p.X,-part.Size.X/2,part.Size.X/2),math.clamp(p.Z,-part.Size.Z/2,part.Size.Z/2)
            local distance=(p.X-x)^2+(p.Z-z)^2
            if distance<nearest then
                nearest=distance
                surface=part.CFrame:PointToWorldSpace(Vector3.new(x,part.Size.Y/2,z))
            end
        end
        table.insert(points,Vector3.new(position.X,surface.Y+clearance,position.Z))
    end
    local geometry={};for _,part in ipairs(parts) do geometry[part]={frame=part.CFrame,size=part.Size} end
    return {bridge=bridge,anchor=anchor,geometry=geometry,partCount=#parts,hatch=hatch,inside=hatch.Position,points=points,direction=direction,step=1}
end
function A:claimFarm()
    if player:FindFirstChild("Alien") then self.claimNote="Waiting for event return before claiming";self:cancelMovement("claim");self.claimAttempt=nil;return end
    local character,humanoid,root=self:character();if not root then self.claimNote="Waiting for character before claiming";return end
    local farms=workspace:FindFirstChild("Farms")
    if not farms then self.claimNote="Waiting for Farms to load";self:cancelMovement("claim");self.claimAttempt=nil;return end
    local list=farms:GetChildren()
    for _,farm in ipairs(list) do if value(farm,"Owner")==player then self:scan();return true end end
    local function vacant(farm)
        if farm.Parent~=farms then return end
        local owner=farm:FindFirstChild("Owner")
        local sign=farm:FindFirstChild("Sign");local gui=sign and sign:FindFirstChild("Gui");local label=gui and gui:FindFirstChild("Owner")
        return owner and owner.Value==nil and label and label.Text=="Vacant"
    end
    local now=os.clock();self.claimBackoff=self.claimBackoff or setmetatable({},{__mode="k"})
    local state=self.claimAttempt
    if state then
        local bridge,anchor,hatch,parts=claimBridge(state.farm)
        local changed=not parts or #parts~=state.partCount
        if parts then for _,part in ipairs(parts) do
            local old=state.geometry[part]
            if not old or old.frame~=part.CFrame or old.size~=part.Size then changed=true;break end
        end end
        if not vacant(state.farm) or bridge~=state.bridge or anchor~=state.anchor or hatch~=state.hatch or changed or (hatch.Position-state.inside).Magnitude>0.5 then self.claimAttempt=nil;self:cancelMovement("claim")
        elseif now-state.at>=#state.points*0.25+5 then
            self.claimBackoff[state.farm]=now+8;self.claimAttempt=nil;self:cancelMovement("claim")
            self:log("Bridge crossing unconfirmed; trying another vacant farm")
        end
    end
    local available={}
    local vacantCount=0;local streamedCount=0
    if not self.claimAttempt then for _,farm in ipairs(list) do
        if vacant(farm) then
            vacantCount+=1
            local bridge,anchor,hatch,parts=claimBridge(farm)
            if anchor then
                streamedCount+=1
                if (self.claimBackoff[farm] or 0)<=now then
                    local leg=character:FindFirstChild("Left Leg")
                    local clearance=(humanoid.HipHeight or 2)+root.Size.Y/2+(leg and leg.Size.Y or 0)
                    local route=bridgeRoute(bridge,anchor,hatch,parts,clearance)
                    if route then route.farm=farm;table.insert(available,route) end
                end
            end
        end
    end
        table.sort(available,function(a,b) return (a.points[1]-root.Position).Magnitude<(b.points[1]-root.Position).Magnitude end)
        if available[1] then self.claimAttempt=available[1];self.claimAttempt.at=now end
    end
    state=self.claimAttempt
    if state then
        local point=state.points[state.step]
        local delta=point and root.Position-point
        -- Ground collision and gravity can move a correctly reached root more
        -- than one stud vertically between dispatch and the next claim tick.
        -- Keep forward arrival tight, with a separate bounded height tolerance.
        if point and state.sentAt and now-state.sentAt>=0.08
            and Vector3.new(delta.X,0,delta.Z).Magnitude<=0.75 and math.abs(delta.Y)<=2.5 then
            state.step+=1;state.sentAt=nil;point=state.points[state.step]
        end
        if point then
            delta=root.Position-point
            local horizontal=Vector3.new(delta.X,0,delta.Z).Magnitude
            self:teleport(state.anchor,"claim",10,1,true,point,point+state.direction)
            state.sentAt=state.sentAt or now
            self.claimNote=string.format("Crossing vacant farm bridge %d/%d; horizontal %.2f, vertical %.2f studs; waiting for ownership",
                state.step,#state.points,horizontal,math.abs(delta.Y))
        else self.claimNote="Bridge crossed; waiting for server ownership" end
    else
        self.claimNote=vacantCount==0 and "No vacant farm loaded; waiting for a vacancy" or (streamedCount==0 and "Waiting for vacant farm bridge geometry to load" or "Waiting to retry unconfirmed bridge crossings")
    end
    self.status=self.claimNote
    return false
end
function A:tier(category,name)
    local items=RS:FindFirstChild("Items"); local cat=items and items:FindFirstChild(category); local def=cat and cat:FindFirstChild(name)
    return def and tonumber(value(def,"Tier")) or nil
end
function A:gear(d)
    local using=d.using or {}; local w=(d.inventory.weapons or {})[using.weapons]
    local tier=w and self:tier("Weapons",w[1]) or 0
    local coverage={}; if w then for _,id in pairs(w[2] or {}) do coverage[tostring(id)]=M.WeaponCooldown[tier] or 0 end end
    return {weaponTier=tier,wingsTier=self:tier("Wings",using.wings or "") or 0,trailTier=self:tier("Trails",using.trails or "") or 1,cooldownCoverage=coverage}
end
local function owned(category,item)
    if category=="Weapons" then return type(item)=="table" and type(item[1])=="string" and type(item[2])=="table" and (tonumber(item[3]) or 1)>0 end
    return type(item)=="number" and item>0
end
function A:equip(d,s)
    local baseline=self:gear(d)
    for _,category in ipairs({"Wings","Trails","Weapons"}) do
        local field=string.lower(category); local current=d.using[field]; local best,score=nil,P.output(d,s,baseline)
        for id,item in pairs(d.inventory[field] or {}) do
            local name=category=="Weapons" and type(item)=="table" and item[1] or tostring(id)
            local tier=type(name)=="string" and self:tier(category,name)
            if tier and id~=current and owned(category,item) then
                local g=Core.copy(baseline)
                if category=="Weapons" then
                    g.weaponTier=tier; g.cooldownCoverage={}
                    for _,ability in pairs(item[2] or {}) do g.cooldownCoverage[tostring(ability)]=M.WeaponCooldown[tier] or 0 end
                else g[category=="Wings" and "wingsTier" or "trailTier"]=tier end
                local nextScore=P.output(d,s,g)
                if nextScore>score+1e-10 then score=nextScore; best=id end
            end
        end
        if best then
            local id=best; local stamp=tostring(current).."->"..tostring(id)
            self.ledger:begin("equip-"..field,"equip-"..field,stamp,function(nextD) return nextD.using[field]==id or tostring(nextD.using[field])==tostring(id) end,function() self:remote("Items","Use",category,tostring(id)) end)
        end
    end
end
function A:syncHeroBudget(d)
    local run=table.concat({d.prestige or 0,d.superprestige or 0,d.ascension or 0},":")
    if not self.heroBudget or self.heroBudget.run~=run then
        self.heroBudget={run=run,spent={0,0}};self:save()
    end
    return self.heroBudget
end
function A:heroWeakAllowance(d,balance,futureWeak)
    local state=self:syncHeroBudget(d)
    local cap=M.BigNum.Mul(balance,{5,-3})
    local committed=M.BigNum.Add(state.spent,futureWeak or {0,0})
    self.heroBudgetNote=budgetText(state.spent).." eggs debited; cap now "..budgetText(cap).." (0.5%); pending packages included"
    if M.BigNum.Compare(cap,committed)~='>' then return {0,0} end
    -- Also keep the new debit inside 0.5% of the wallet AFTER that purchase.
    return M.BigNum.Div(M.BigNum.Sub(cap,committed),{1.005,0})
end
-- Hiring has its own toggle, cadence and transaction lane. The DPS planner
-- handles already-owned heroes only and cannot spend a pending hire's eggs.
function A:hireHeroes(d,s)
    if not self.settings.hireHeroes then self.heroHireNote="Disabled";return end
    local ready,reason=self:progressionReady(d,s)
    if not ready then self.heroHireNote=reason;return end
    if self.progressionIntent or self.progressionSettling or self.ledger.pending.reset or self.ledger.pending.prepare then
        self.heroHireNote="Waiting for progression reset/preparation";return
    end
    if not self.farm or not self.farm:FindFirstChild("Owner") or self.farm.Owner.Value~=player then self.heroHireNote="Waiting for owned farm placement";return end
    if self.ledger.pending.hire then self.heroHireNote="Hire requested; waiting for actual ownership confirmation";return end
    local id=P.nextHire(d)
    if not id then self.heroHireNote="All catalog heroes hired";return end
    local title=M.HeroesData.Stats[id].Title;local cost=P.cost(d,id,0,1);local balance=d.eggs
    -- Hiring outranks future training commitments, while requests already sent
    -- retain their actual costs. No additional upgrade lane is consumed.
    for lane,op in pairs(self.ledger.pending) do
        if lane:sub(1,5)=="hero-" then balance=M.BigNum.Sub(balance,op.cost or {0,0}) end
    end
    self.heroHireNote="Next hire: "..title.."; first level "..budgetText(cost).." eggs"
    if M.BigNum.Compare(cost,balance)==">" then self.heroHireNote..="; waiting for unreserved eggs";return end
    local key="hero-"..id.."-train";local stamp="0:nil";local retry=false
    if self.ledger.uncertain[key]==stamp then
        local attempt=(self.hireAttempts or {})[id]
        if not attempt or attempt.count>=3 or os.clock()-attempt.at<30 or (self.lastDataAt or -math.huge)<=attempt.at then
            self.heroHireNote..="; unconfirmed "..tostring(attempt and attempt.count or 1).."/3; waiting for fresh data and retry delay";return
        end
        retry=true
    end
    local ok,position=pcall(M.GetFarmHeroPos,self.farm,tonumber(id))
    if not ok or position==nil then self.heroHireNote..="; waiting for native placement";return end
    if self.data~=d or self.session~=s or ((d.heroes[id] or {}).level or 0)>0 then return end
    if retry then self.ledger.uncertain[key]=nil end
    local began=self.ledger:begin("hire",key,stamp,function(nextD)
        return ((nextD.heroes[id] or {}).level or 0)>=1
    end,function()
        self.hireAttempts=self.hireAttempts or {};local prior=self.hireAttempts[id]
        self.hireAttempts[id]={count=(prior and prior.count or 0)+1,at=os.clock()}
        self:remote("Heroes","Train",id,{position},1)
    end)
    if began then
        local op=self.ledger.pending.hire;op.cost=cost;op.reserveCost=cost
        op.describe=function(nextD) return "hire "..title.." level 0 -> "..tostring((nextD.heroes[id] or {}).level or 0) end
        self.heroHireNote="Hire requested: "..title.."; waiting for actual ownership confirmation"
        self:log("Hire "..title.." 1 [independent priority hiring]")
    end
    return began
end

function A:buyHeroes(d,s)
    local manual,menuName=self:manualMenuOpen()
    if manual then self.heroNote="Paused for manual "..tostring(menuName or "purchase menu");return end
    if self.ledger.pending.reset or self.progressionSettling then self.heroNote="Waiting for progression reset";return end
    if self.progressionIntent or self.ledger.pending.prepare then self.heroNote="Saving White Eggs for retirement preparation";return end
    local run=table.concat({d.prestige or 0,d.superprestige or 0,d.ascension or 0},":")
    local goal=self.heroGoal
    if goal then
        local h=d.heroes[goal.id] or {};local completed=goal.upgrade and (h.upgrades or {})[tostring(goal.upgrade)]==true
            or not goal.upgrade and (h.level or 0)>=goal.targetLevel
        if goal.run~=run or completed then self.heroGoal=nil;goal=nil
        elseif self.ledger.pending["hero-"..goal.id] then
            self.heroNote="Finishing "..M.HeroesData.Stats[goal.id].Title.." toward level "..goal.targetLevel.."; waiting for confirmation";return
        elseif self.ledger.uncertain["hero-"..goal.id.."-train"] or goal.upgrade and self.ledger.uncertain["hero-"..goal.id.."-u"..goal.upgrade] then
            self:log("Release hero target after an unconfirmed request");self.heroGoal=nil;goal=nil
        end
    end
    -- Independent hero lanes prevent one delayed/rejected hero from stopping
    -- every other hero. Reserve all outstanding costs against the live wallet.
    local balance=d.eggs;local pending=0;local futureWeak={0,0}
    for lane,op in pairs(self.ledger.pending) do if lane:sub(1,5)=="hero-" or lane=="hire" then
        local reserved=op.reserveCost or op.cost or {0,0}
        if lane~="hire" then pending+=1 end;balance=M.BigNum.Sub(balance,reserved)
        if op.weak and M.BigNum.Compare(reserved,op.cost or {0,0})=='>' then futureWeak=M.BigNum.Add(futureWeak,M.BigNum.Sub(reserved,op.cost or {0,0})) end
    end end
    if pending>=3 then self.heroNote="Waiting for "..pending.." hero purchases to be accepted";return end
    if Core.log(balance)==-math.huge then self.heroNote="Waiting for eggs; pending hero costs reserved";return end
    local budget=table.clone(d);budget.eggs=balance
    local weakAllowance=self:heroWeakAllowance(d,balance,futureWeak)
    local power=d.powerups or {};local auto=power.autoattack
    local clicking=self.settings.farm==true or power.autoclick==true or type(power.autoclick)=="number" and power.autoclick>0 or type(auto)=="table" and (auto.bought or 0)+(auto.duration or 3600)>os.time()
    local choicesList=P.heroes(budget,s,self:gear(d),{clicking=clicking,weakBudget=weakAllowance,hire=false})
    local utilityTurn=false
    if goal then
        local continuation={}
        for _,choice in ipairs(choicesList) do
            if choice.id==goal.id and (goal.upgrade and (choice.upgrade==goal.upgrade or choice.plannedUpgrade==goal.upgrade)
                or not goal.upgrade and not choice.upgrade and not choice.plannedUpgrade and choice.targetLevel==goal.targetLevel) then
                table.insert(continuation,choice)
            end
        end
        if #continuation>0 then choicesList=continuation
        else self:log("Release hero target: remaining path is no longer affordable or worthwhile");self.heroGoal=nil;goal=nil end
    end
    if not goal and os.clock()>=(self.next.heroUtility or 0) then
        -- A small shared allowance can unlock useful owned-hero abilities.
        for index,choice in ipairs(choicesList) do
            local u=(choice.upgrade or choice.plannedUpgrade) and M.HeroesData.Stats[choice.id].Upgrades[choice.upgrade or choice.plannedUpgrade]
            local key="hero-"..choice.id..(choice.upgrade and "-u"..choice.upgrade or "-train")
            local stamp=tostring(choice.baseLevel)..":"..tostring(choice.upgrade and ((d.heroes[choice.id] or {}).upgrades or {})[tostring(choice.upgrade)])
            if choice.weak and u and u.ability and self.ledger:available("hero-"..choice.id,key,stamp) then
                table.remove(choicesList,index);table.insert(choicesList,1,choice);utilityTurn=true;break
            end
        end
    end
    self.buyOptions=#choicesList
    if not self.settings.hireHeroes then self.heroHireNote="Disabled" end
    self.heroNote=#choicesList==0 and "No affordable upgrade/DPS purchase; weak training shares a 0.5% budget" or "Evaluating owned-hero upgrades and training"
    local heldPending,heldUnconfirmed,heldUtility=0,0,false
    for _,choice in ipairs(choicesList) do
        if not goal and choice.weak and choice.growthGainLog==-math.huge and os.clock()<(self.next.heroUtility or 0) then heldUtility=true;continue end
        local id=choice.id; local base=choice.baseLevel
        local key="hero-"..id..(choice.upgrade and "-u"..choice.upgrade or "-train")
        local stamp=tostring(base)..":"..tostring(choice.upgrade and (d.heroes[id].upgrades or {})[tostring(choice.upgrade)])
        local lane="hero-"..id
        if base<1 then continue end
        if self.ledger:available(lane,key,stamp) then
            -- Recheck balance and identity immediately before dispatch.
            if M.BigNum.Compare(balance,choice.commitmentCost or choice.cost)=="<" or M.BigNum.Compare(self.data.eggs,choice.commitmentCost or choice.cost)=="<" or ((self.data.heroes[id] or {}).level or 0)~=base then return end
            if choice.weak and M.BigNum.Compare(choice.commitmentCost or choice.cost,weakAllowance)==">" then continue end
            local began=self.ledger:begin(lane,key,stamp,function(nextD)
                local h=nextD.heroes[id]
                return h and (choice.upgrade and (h.upgrades or {})[tostring(choice.upgrade)]==true or not choice.upgrade and h.level>=base+choice.amount)
            end,function()
                if choice.weak then
                    self.heroBudget.spent=M.BigNum.Add(self.heroBudget.spent,choice.cost)
                    self.heroBudgetNote=budgetText(self.heroBudget.spent).." eggs debited; shared 0.5% allowance"
                    self:save() -- Charge before dispatch, including outcomes that arrive late.
                end
                if choice.upgrade then self:remote("Heroes","Upgrade",id,choice.upgrade)
                else self:remote("Heroes","Train",id,nil,choice.amount) end
            end)
            local op=self.ledger.pending[lane]
            if not began or not op then self.heroNote="Hero request unconfirmed; spend remains reserved conservatively";return end
            op.cost=choice.cost;op.reserveCost=choice.commitmentCost or choice.cost;op.weak=choice.weak==true
            op.describe=function(nextD)
                local hero=nextD.heroes[id] or {};local title=M.HeroesData.Stats[id].Title
                if choice.upgrade then return title.." upgrade "..choice.upgrade.." owned="..tostring((hero.upgrades or {})[tostring(choice.upgrade)]==true) end
                return title.." +"..choice.amount.."; level "..base.." -> "..tostring(hero.level or 0).." (expected "..(base+choice.amount)..")"
            end
            local note=(choice.upgrade and "Upgrade " or "Train ")..M.HeroesData.Stats[id].Title.." "..tostring(choice.upgrade or choice.amount)
            if choice.plannedUpgrade then note..=" toward level "..choice.targetLevel.." / "..M.HeroesData.Stats[id].Upgrades[choice.plannedUpgrade].title end
            note..=utilityTurn and " [bounded utility allowance]" or choice.incomeFactorLog and choice.incomeFactorLog>0 and " [damage + egg income value]" or choice.weak and " [shared weak budget]" or " [best productive gain/egg]"
            if utilityTurn or choice.weak and choice.growthGainLog==-math.huge then self.next.heroUtility=os.clock()+10 end
            if choice.targetLevel and (choice.plannedUpgrade or choice.targetLevel>base+(choice.amount or 0)) then
                self.heroGoal={run=run,id=id,targetLevel=choice.targetLevel,upgrade=choice.plannedUpgrade}
                note..=" [committed target "..choice.targetLevel.."]"
            end
            self.heroNote=note;self:log(note);return
        elseif self.ledger.pending[lane] then heldPending+=1
        else heldUnconfirmed+=1 end
    end
    if heldUnconfirmed>0 then self.heroNote="Unconfirmed purchase preconditions remain quarantined; "..heldPending.." pending choices"
    elseif heldPending>0 then self.heroNote="Waiting for current hero purchase confirmations"
    elseif heldUtility then self.heroNote="Waiting for the utility interval or an affordable productive purchase"
    elseif #choicesList>0 then self.heroNote="No currently eligible native hero request" end
end
local function signature(t)
    local parts={}; for k,v in pairs(t or {}) do table.insert(parts,tostring(k).."="..(type(v)=="table" and "{"..signature(v).."}" or tostring(v))) end
    table.sort(parts); return table.concat(parts,";")
end
function A:rewards(d)
    local ready=false;local levels={};for id,a in pairs(d.achievements) do levels[id]=a.level end;local before=signature(levels)
    for id,def in pairs(M.AchievementsData) do
        local a=d.achievements[id]; local level=a and a.level or 1
        if a and def.levels[level] and math.floor((a.progress or 0)+0.5)>=def.levels[level].value then ready=true end
    end
    if ready then self.ledger:begin("rewards","rewards",before,function(nextD)
        for id,a in pairs(nextD.achievements) do if a.level>(levels[id] or 1) then return true end end;return false
    end,function() self:remote("Achievements","ClaimAll") end) end
end
function A:skipBoxAnimation()
    if not self.alive or not self.settings.boxes or self.ledger.pending.reset then return end
    local gui=player:FindFirstChildOfClass("PlayerGui");local menus=gui and gui:FindFirstChild("Menus")
    local slider
    if menus then for _,candidate in ipairs(menus:GetChildren()) do if candidate.Name=="Slider" then
        slider=slider or candidate
        local wrapper=candidate:FindFirstChild("Wrapper");local confirm=candidate:FindFirstChild("Confirm")
        if candidate:IsA("GuiObject") and wrapper and wrapper:FindFirstChild("List") and confirm and confirm:IsA("GuiButton") and confirm.Visible then
            -- Lootbox.Run's own Skip handler destroys Confirm; its roll loop
            -- finishes normally and leaves the native two-second reward reveal.
            confirm:Destroy();self:log("Skipped box opening roll")
        end
    end end end
    return slider
end
local function trophyBoxCount(d,tier)
    local count=0
    for _,owned in ipairs((d.inventory or {}).boxes or {}) do if owned==tier then count+=1 end end
    return count
end
function A:observeTrophyPurchase(d)
    local attempt=self.trophyBuyAttempt
    if attempt and trophyBoxCount(d,attempt.tier)>attempt.before then self.trophyBuyAttempt=nil end
end
function A:buyTrophyBox(d,s)
    if not self.settings.trophyBoxes then return false end
    local ready,note=self:progressionReady(d,s)
    if not ready then self.trophyBuyNote=note;return false end
    if self.ledger.pending.reset or self.progressionIntent then self.trophyBuyNote="Waiting for progression reset/preparation";return false end
    local settled,reason=self:resetSettlement(d)
    if not settled then self.trophyBuyNote=reason;return false end
    self:observeTrophyPurchase(d)
    if self.trophyBuyAttempt then
        self.trophyBuyNote="Trophy Box purchase unconfirmed; waiting for inventory before spending again";return false
    end
    if self.ledger.pending.boxes then self.trophyBuyNote="Waiting for the current box action";return false end
    local gui=player:FindFirstChildOfClass("PlayerGui");local menus=gui and gui:FindFirstChild("Menus")
    if menus and menus:FindFirstChild("Slider") then self.trophyBuyNote="Waiting for box opening to finish";return false end
    local catalog=M.BoxData;local tier
    for id,name in pairs(catalog and catalog.Name or {}) do
        if name=="Trophy" then
            if tier then self.trophyBuyNote="Ambiguous Trophy Box catalog";return false end
            tier=id
        end
    end
    local price=tier and catalog.Price and catalog.Price[tier]
    local balance=d.diamonds
    if type(tier)~="number" or type(price)~="number" or price~=price or price<=0 or price>=math.huge
        or type(balance)~="number" or balance~=balance or balance<0 or balance>=math.huge then
        self.trophyBuyNote="Waiting for a valid Trophy Box price and diamond balance";return false
    end
    if balance<price then self.trophyBuyNote="Saving diamonds: "..balance.." / "..price.." for a Trophy Box";return false end
    local before=trophyBoxCount(d,tier);local stamp=tostring(tier)..":"..before
    if not self.ledger:available("boxes","trophy-box-buy",stamp) then self.trophyBuyNote="Trophy Box request unconfirmed; waiting for inventory";return false end
    self.trophyBuyAttempt={tier=tier,before=before,at=os.clock()}
    local sent=self.ledger:begin("boxes","trophy-box-buy",stamp,function(nextD)
        return trophyBoxCount(nextD,tier)>before
    end,function() self:remote("Boxes","Buy",tier) end)
    if sent then
        local op=self.ledger.pending.boxes;op.cost=price;op.kind="trophy-purchase"
        op.describe=function(nextD) return "Trophy Box purchase; tier "..tier..", cost "..price.." diamonds; owned "..before.." -> "..trophyBoxCount(nextD,tier) end
        self.trophyBuyNote="Buying one Trophy Box for "..price.." diamonds; waiting for inventory"
        self:log(self.trophyBuyNote)
    else self.trophyBuyAttempt=nil end
    return sent
end

function A:openBoxes(d)
    if not self.settings.boxes or self.ledger.pending.reset then return end
    self:observeTrophyPurchase(d)
    if self.settings.trophyBoxes and self.trophyBuyAttempt then self.boxNote="Waiting for Trophy Box purchase inventory";return end
    local slider=self:skipBoxAnimation()
    if self.ledger.pending.boxes then self.boxNote="Waiting for box consumption or the native open result";return end
    if self:manualMenuOpen() then self.boxNote="Paused while you use a native purchase menu";return end
    if slider then self.boxNote="Waiting for the game's box animation to finish";return end
    local boxes=(d.inventory or {}).boxes or {};local before=#boxes;local stamp=signature(boxes)
    for index,tier in ipairs(boxes) do
        local protected=false
        for _,key in ipairs({"locked","favorites","favorited"}) do
            local flags=d[key];local category=type(flags)=="table" and (flags.Boxes or flags.boxes)
            if type(category)=="table" and (category[index]==true or category[tostring(index)]==true or table.find(category,index)) then protected=true end
        end
        if type(tier)=="number" and tier>0 and not protected then
            local receipt=self.boxReceipts or 0
            if self.ledger:begin("boxes","boxes",stamp,function(nextD)
                return #((nextD.inventory or {}).boxes or {})<before or (self.boxReceipts or 0)>receipt
            end,function() self:remote("Items","Use","Boxes",tostring(index)) end) then
                self.ledger.pending.boxes.describe=function(nextD)
                    return "box "..index.." (tier "..tier.."); owned remaining="..#((nextD.inventory or {}).boxes or {})
                end
                self.boxNote="Opening owned box "..index.." (tier "..tier..")"
            else self.boxNote="Box request unconfirmed; waiting for inventory to change" end
            return -- Reread native array indices after each accepted open.
        end
    end
    self.boxNote=before==0 and "No owned boxes" or "No unprotected owned boxes"
end
local function pickupReady(entry)
    return entry.item.Parent and entry.part.Parent and entry.part.CanTouch~=false and (tonumber(entry.part.Transparency) or 0)<1
end
function A:collect(kind,entries,d,s)
    self.collecting=self.collecting or {};self.collectBackoff=self.collectBackoff or setmetatable({},{__mode="k"})
    local state=self.collecting[kind];local now=os.clock()
    if state then
        local gone=not state.item.Parent or not state.part.Parent or (tonumber(state.part.Transparency) or 0)>=1
        local raised=kind=="meat" and (s.cps or 1)>state.before
        local listed=false;for _,entry in ipairs(entries) do if entry.item==state.item and entry.part==state.part then listed=true;break end end
        if gone or raised or not listed or state.part.CanTouch==false then
            self.collecting[kind]=nil;self:cancelMovement(kind=="meat" and "meat" or "diamond")
        elseif now-state.at>2 then
            self.collectBackoff[state.item]=now+8;self.collecting[kind]=nil;self:cancelMovement(kind=="meat" and "meat" or "diamond");self:log(kind.." contact not accepted; trying another pickup")
        else
            self:teleport(state.part,kind=="meat" and "meat" or "diamond",kind=="meat" and 20 or 25,5,true);return true
        end
    end
    local _,_,root=self:character();if not root then return end
    table.sort(entries,function(a,b) return (a.part.Position-root.Position).Magnitude<(b.part.Position-root.Position).Magnitude end)
    for _,entry in ipairs(entries) do
        if pickupReady(entry) and (self.collectBackoff[entry.item] or 0)<=now then
            self.collecting[kind]={item=entry.item,part=entry.part,at=now,before=kind=="meat" and (s.cps or 1) or d.diamonds}
            self:teleport(entry.part,kind=="meat" and "meat" or "diamond",kind=="meat" and 20 or 25,5,true);return true
        end
    end
    return false
end
function A:pickup(d,s)
    if not self.settings.farm or self.diamondPriority then return end
    if (s.cps or 1)>=10 then if self.collecting then self.collecting.meat=nil end;self:cancelMovement("meat");return end
    if player:FindFirstChild("Alien") then return end
    local entries={};for _,part in ipairs(self.meats or {}) do if part.Parent then table.insert(entries,{item=part,part=part}) end end
    self:collect("meat",entries,d,s)
end
function A:diamonds(d,s)
    if not self.settings.diamonds or player:FindFirstChild("Alien") then self:setDiamondPriority(false);return end
    local folder=self.farm and self.farm:FindFirstChild("Diamonds")
    local entries={}
    if folder then for _,item in ipairs(folder:GetChildren()) do
        local part=item:IsA("BasePart") and item or item:FindFirstChild("Handle") or item:FindFirstChildWhichIsA("BasePart",true)
        if part and part:IsA("BasePart") then table.insert(entries,{item=item,part=part}) end
    end end
    self.diamondNote=not folder and "Farm Diamonds container not loaded" or (#entries==0 and "No farm diamonds ready" or nil)
    local remaining=0;for _,entry in ipairs(entries) do if pickupReady(entry) then remaining+=1 end end
    local busy=self:collect("diamonds",entries,d,s)
    self:setDiamondPriority(busy or remaining>0)
    if self.diamondPriority then
        self.status=busy and "Collecting diamonds; chicken farming paused" or "Waiting to retry diamonds; chicken farming paused"
    elseif not self.settings.quest then self:house(d) end
end
function A:questAction(key,stamp,predicate,verb,arg)
    return self.ledger:begin("quest",key,stamp,predicate,function() self:remote("Quest",verb,arg) end)
end
function A:quest(d)
    local q=d.quest or {stage=0,collected={}}
    local stage=tonumber(q.stage) or 0
    if stage==0 then self:questAction("quest-start","0",function(x) return x.quest and x.quest.stage>=1 end,"Advance"); return end
    if stage==1 then self:questAction("quest-ack","1",function(x) return x.quest and x.quest.stage>=2 end,"Acknowledge"); return end
    if stage<3 then
        local parts={}; local _,_,root=self:character(); if not root then return end
        for id=1,5 do
            if not (q.collected or {})[tostring(id)] then
                local model=workspace:FindFirstChild("Pumpkin"..id); local part=model and model:FindFirstChild("Pumpkin")
                if part and part:IsA("BasePart") then table.insert(parts,{id=id,part=part}) end
            end
        end
        table.sort(parts,function(a,b) return (a.part.Position-root.Position).Magnitude<(b.part.Position-root.Position).Magnitude end)
        for _,x in ipairs(parts) do
            if self.ledger:available("quest","pumpkin-"..x.id,"uncollected") then
                if self:teleport(x.part,"quest",30,16,false) then
                    self:questAction("pumpkin-"..x.id,"uncollected",function(nextD) return nextD.quest and (nextD.quest.collected or {})[tostring(x.id)]==true end,"Collect",x.id)
                end
                break
            end
        end
        self.questNote=#parts==0 and "Waiting for uncollected pumpkins to stream" or "Pumpkins: "..tostring(stage)
        return
    end
    if not d.pumpkinBossQuestClaimed then self.questNote=self.settings.boss and "Pumpkins complete; waiting for the Pumpkin Boss invitation" or "Pumpkins complete; enable Auto Join + Fight Event Boss";return end
    if not q.thanked then self:questAction("quest-thanks","unthanked",function(x) return x.quest and x.quest.thanked end,"Thanked"); return end
    self:house(d)
end
function A:house(d)
    local q=d.quest or {};if (tonumber(q.stage) or 0)<3 or not q.thanked or not d.pumpkinBossQuestClaimed then return end
    local bg=workspace:FindFirstChild("Background"); local model=bg and bg:FindFirstChild("Model"); local scaled=model and model:FindFirstChild("ScaledModel"); local farm=scaled and scaled:FindFirstChild("Farm")
    if not farm then self.questNote="Waiting for quest house to stream"; return end
    local door=farm:FindFirstChild("Door"); door=door and door:FindFirstChild("Main")
    local exit=farm:FindFirstChild("ExitDoor"); exit=exit and exit:FindFirstChild("Main")
    local inside=farm:FindFirstChild("Inside",true); local diamond
    for _,child in ipairs(farm:GetChildren()) do if child.Name=="Model" then diamond=child:FindFirstChild("Diamond"); if diamond then break end end end
    local _,_,root=self:character(); if not root then return end
    if inside and (root.Position-inside.Position).Magnitude<12 then self.houseInside=true end
    if door and (root.Position-door.Position).Magnitude<12 then self.houseInside=false end
    local inHouse=self.houseInside==true
    if d.houseDiamondClaimed then
        if inHouse and exit and self:teleport(exit,"house",40,12,false) then self:questAction("house-exit","inside",function()
            local _,_,r=A:character(); local spawnPart=workspace:FindFirstChild("Spawn")
            if r and spawnPart and (r.Position-spawnPart.Position).Magnitude<12 then A.houseInside=false; return true end
            return false
        end,"ExitHouse") end
        self.questNote="Halloween rewards collected"; return
    end
    if inHouse then
        if diamond and self:teleport(diamond,"house",40,12,false) then self:questAction("house-diamond","unclaimed",function(x) return x.houseDiamondClaimed==true end,"CollectHouseDiamond") end
    elseif door and self:teleport(door,"house",40,12,false) then
        self:questAction("house-enter","outside",function()
            local _,_,r=A:character(); if r and inside and (r.Position-inside.Position).Magnitude<12 then A.houseInside=true; return true end; return false
        end,"EnterHouse")
    end
end
-- Accept a real, visible event invitation through its existing button handlers.
-- The entry remote is absent from both supplied dumps; never invent one.
do
    local affirmative={join=true,yes=true,accept=true,confirm=true,fight=true,enter=true,participate=true,
        ["yes join"]=true,["join event"]=true,["join battle"]=true,["join boss"]=true,["join fight"]=true,["join invasion"]=true,
        ["join the fight"]=true,["join boss battle"]=true,["join boss fight"]=true,["yes please"]=true}
    local excluded={"trade","purchase","buy","shop","sale","robux","spend","cost","costs","retire","rebirth","ascend","obby","obstacle","group","clan","discord"}
    local function words(text)
        return (tostring(text or ""):lower():gsub("<[^>]*>"," "):gsub("[%c%p]"," "):gsub("%s+"," "):match("^%s*(.-)%s*$"))
    end
    local function kindOf(text)
        if text:find("%f[%a]pumpkin%f[%A]") then return "Pumpkin" end
        if text:find("%f[%a]alien%f[%A]") then return "Alien" end
        if text:find("%f[%a]egg rocket%f[%A]") or text:find("%f[%a]eggrocket%f[%A]") then return "Egg Rocket" end
        if text:find("boss battle",1,true) or text:find("boss fight",1,true) or text:find("event boss",1,true) or text:find("boss event",1,true) then return "Event Boss" end
    end
    local function visible(object,root)
        local current=object
        while current and current~=root do
            if current:IsA("GuiObject") and not current.Visible then return false end
            if current:IsA("ScreenGui") and not current.Enabled then return false end
            if current.Name=="Rayfield" or current.Name=="EggFarmAutomation" then return false end
            current=current.Parent
        end
        return current==root
    end
    local function textOf(object)
        return (object:IsA("TextLabel") or object:IsA("TextButton")) and object.Text or ""
    end
    local function buttonLabel(button,root)
        local pieces={textOf(button)}
        for _,child in ipairs(button:GetDescendants()) do
            if visible(child,root) then table.insert(pieces,textOf(child)) end
        end
        local distinct,seen={},{}
        for _,piece in ipairs(pieces) do local text=words(piece)
            if text~="" and not seen[text] then seen[text]=true;table.insert(distinct,text) end
        end
        local label=table.concat(distinct," ")
        label=label:gsub("%s+%d+%s+%d+$",""):gsub("%s+%d+%s*seconds?$","")
            :gsub("%s+%d+%s*secs?$",""):gsub("%s+%d+%s*s$",""):gsub("%s*%d+$","")
        if label=="" then label=words(button.Name) end
        return label
    end
    local function invitation(button,root)
        if not visible(button,root) or button.Active==false or button.Interactable==false then return end
        local label=buttonLabel(button,root)
        local positive=affirmative[label]
        if not positive and not (label:find("^yes%f[%A]") or label:find("^join%f[%A]") or label:find("^enter%f[%A]") or label:find("^participate%f[%A]")) then return end
        local scope=button.Parent
        for _=1,5 do
            if not scope or scope==root then break end
            -- Do not combine the title of one panel with a button in another.
            if not scope:IsA("GuiObject") and not (scope:IsA("ScreenGui") and button.Parent==scope) then break end
            local pieces={textOf(scope)};local buttons,labels=0,0
            for _,child in ipairs(scope:GetDescendants()) do
                if visible(child,root) then
                    if child:IsA("GuiButton") then buttons+=1 end
                    local text=textOf(child)
                    if text~="" then labels+=1;table.insert(pieces,text) end
                end
            end
            if buttons>4 or labels>18 then break end
            local text=words(table.concat(pieces," "))
            local kind=kindOf(text)
            local asks=text:find("%f[%a]join%f[%A]") or text:find("participat") or text:find("would you like to fight",1,true) or text:find("want to fight",1,true)
            local blocked=false
            for _,word in ipairs(excluded) do if text:find("%f[%a]"..word.."%f[%A]") then blocked=true;break end end
            local direct={textOf(scope)}
            for _,child in ipairs(scope:GetChildren()) do
                if visible(child,root) then table.insert(direct,textOf(child)) end
            end
            local context=words(table.concat(direct," "));local name=words(scope.Name)
            local namedModal=name:find("prompt",1,true) or name:find("invit",1,true) or name:find("popup",1,true) or name:find("dialog",1,true) or name:find("notification",1,true)
            local localTopic=kindOf(context)
            local evidence={text=table.concat(pieces," "):sub(1,450),label=label}
            if kind and asks and not blocked and (localTopic or namedModal) then
                if positive then return kind,evidence end
                evidence.kind=kind;return nil,evidence
            end
            -- Record a generic event question without guessing what event it
            -- joins. Its text will remain available after the popup disappears.
            if not kind and asks and not blocked and namedModal and text:find("%f[%a]event%f[%A]") then return nil,evidence end
            scope=scope.Parent
        end
    end
    local function promptPath(button)
        local names={};local object=button
        for _=1,7 do if not object then break end;table.insert(names,1,object.Name);object=object.Parent end
        return table.concat(names,"."):sub(1,180)
    end
    local function entryWindow(text)
        local lower=tostring(text or ""):lower()
        local seconds=tonumber(lower:match("(%d+)%s*seconds?")) or tonumber(lower:match("(%d+)%s*secs?")) or tonumber(lower:match("(%d+)%s*s%f[%A]"))
        local minutes=tonumber(lower:match("(%d+)%s*minutes?"))
        local m,s=lower:match("(%d+):(%d%d)")
        local countdown=seconds or minutes and minutes*60 or m and (tonumber(m)*60+tonumber(s)) or 0
        return math.clamp(math.max(60,countdown+30),60,180)
    end
    local function property(object,name)
        local ok,result=pcall(function() return object[name] end)
        if ok then return result end
    end
    local function dispatchFor(button)
        local inspect=A:executorApi("getconnections")
        local fire=A:executorApi("firesignal")
        if type(inspect)~="function" then return nil,"Executor needs getconnections to identify the native Join handler" end
        local dispatches={}
        for _,name in ipairs({"MouseButton1Down","MouseButton1Click","Activated"}) do
            local signal=property(button,name)
            local ok,connections=pcall(inspect,signal)
            local callbacks={}
            if ok and type(connections)=="table" then for _,connection in ipairs(connections) do
                if property(connection,"Enabled")~=false and property(connection,"Connected")~=false then
                    local callback=property(connection,"Function");local trigger=property(connection,"Fire")
                    if type(fire)=="function" or type(trigger)=="function" or type(callback)=="function" then
                        table.insert(callbacks,{connection=connection,trigger=trigger,callback=callback})
                    end
                end
            end end
            if #callbacks>0 then table.insert(dispatches,{signal=signal,name=name,callbacks=callbacks}) end
        end
        if #dispatches==0 then return nil,"Waiting for the invitation's native Join handler" end
        return function(alive)
            for _,dispatch in ipairs(dispatches) do
                if not alive() then break end
                local position=button.AbsolutePosition
                local args=dispatch.name=="MouseButton1Down" and {position.X,position.Y} or dispatch.name=="Activated" and {nil,1} or {}
                if type(fire)=="function" then fire(dispatch.signal,table.unpack(args,1,dispatch.name=="Activated" and 2 or #args))
                else for _,entry in ipairs(dispatch.callbacks) do
                    if not alive() then break end
                    if type(entry.trigger)=="function" then entry.trigger(entry.connection,table.unpack(args,1,dispatch.name=="Activated" and 2 or #args))
                    else entry.callback(table.unpack(args,1,dispatch.name=="Activated" and 2 or #args)) end
                end end
            end
        end
    end
    function A:finishEventJoin(message)
        local pending=self.eventJoinPending
        if pending then
            if pending.method=="circle" then self:cancelMovement("boarding") end
            if message=="Disabled" and not self.replacing then self:recordEvent("cancelled",pending.kind,"Event automation stopped while entry was pending") end
            local elapsed=os.clock()-pending.at
            if self.fight then
                self.fight.progressAt+=elapsed
                if self.fight.blockUntil then self.fight.blockUntil+=elapsed end
            end
            if self.lastFarmProgress then self.lastFarmProgress+=elapsed end
            if self.retreat then self.retreat.at+=elapsed end
        end
        self.eventJoinPending=nil
        if message=="Disabled" then self.rocketWatch=nil;self.rocketNotice=nil;self:cancelMovement("boarding");self.rocketNote="Disabled" end
        if message then self.eventNote=message end
    end
    function A:eventJoin()
        if not self.alive then return end
        self.eventInvites=self.eventInvites or setmetatable({},{__mode="k"})
        local roots={player:FindFirstChildOfClass("PlayerGui")}
        local ok,core=pcall(function() return game:GetService("CoreGui") end)
        if ok and core then table.insert(roots,core) end
        for button,record in pairs(self.eventInvites) do
            if not button.Parent or not visible(button,record.root) then self.eventInvites[button]=nil end
        end
        local participant=player:FindFirstChild("Alien")
        if participant then
            if self.eventJoinPending then self:log(self.eventJoinPending.kind.." event entry confirmed by game") end
            if not self.eventWasActive then
                local automatic=self.eventJoinPending~=nil
                self:recordEvent("confirmed",automatic and self.eventJoinPending.kind or "Event Boss",
                    (automatic and (self.eventJoinPending.method=="circle" and "After automatic rocket boarding; " or "After automatic Join attempt; ") or "Observed existing/manual entry; ").."game created Player.Alien participation marker",automatic)
                self:finishEventJoin();self:setDiamondPriority(false);self:cancelMovement();self.collecting={};self.fight=nil;self.retreat=nil;self.claimAttempt=nil
            end
            self.eventWasActive=true
            self.rocketWatch=nil;self.rocketNotice=nil;self.rocketNote="Participation confirmed by game"
            local arena=workspace:FindFirstChild("Alien")
            self.eventNote=not self.settings.boss and "In event; automatic fighting disabled" or arena and arena:FindFirstChild("Chicken") and "Joined; fighting event boss" or "Joined; waiting for arena boss"
            return
        elseif self.eventWasActive then
            self:recordEvent("ended","Event Boss","Game removed Player.Alien; enabled farm features may resume")
            self.eventWasActive=nil;self.fight=nil;self:cancelMovement("boss");self.lastFarmProgress=os.clock()
            self:log("Event ended; resuming enabled farm features")
        end
        if not self.settings.boss then self:finishEventJoin("Disabled");return end
        if self:boardRocket() then return end
        if self.eventJoinPending then
            local pending=self.eventJoinPending
            if os.clock()<(pending.deadline or pending.at+60) then self.status="Waiting for event entry confirmation";return end
            self:recordEvent("timeout",pending.kind,"Join action did not produce Player.Alien before its boarding deadline")
            self:log("Event entry unconfirmed; this invitation will not be clicked again")
            self:finishEventJoin("Join unconfirmed; waiting for a new invitation")
        end
        if not self:character() then self.eventNote="Waiting for character before joining";return end
        if not self:due("event-invite",0.5) then return end
        local candidates={}
        for _,root in ipairs(roots) do
            local readOK,descendants=pcall(function() return root:GetDescendants() end)
            if readOK then for _,button in ipairs(descendants) do
                if button:IsA("GuiButton") then
                    local kind,evidence=invitation(button,root)
                    if kind then table.insert(candidates,{button=button,root=root,kind=kind,evidence=evidence})
                    elseif evidence then
                        local record=self.eventInvites[button]
                        if not record then
                            self.eventInvites[button]={root=root,open=true,unmatched=true}
                            self:recordEvent("unmatched",evidence.kind or "Unknown event",promptPath(button).." | "..evidence.label.." | "..evidence.text)
                        end
                    end
                end
            end end
        end
        if #candidates~=1 then
            self.eventNote=#candidates>1 and "Multiple event invitations; waiting for an unambiguous Join button" or "Waiting for an Alien / Pumpkin / Egg Rocket invitation"
            for _,candidate in ipairs(candidates) do
                local record=self.eventInvites[candidate.button]
                if not record then
                    record={root=candidate.root,open=true};self.eventInvites[candidate.button]=record
                    self:recordEvent("invite",candidate.kind,promptPath(candidate.button).." | "..candidate.evidence.text)
                end
                if record.blocker~=self.eventNote then record.blocker=self.eventNote;self:recordEvent("blocked",candidate.kind,self.eventNote) end
            end
            return
        end
        local candidate=candidates[1];local button=candidate.button
        local record=self.eventInvites[button]
        if not record or not record.open or record.unmatched then
            record={root=candidate.root,open=true};self.eventInvites[button]=record
            self:recordEvent("invite",candidate.kind,promptPath(button).." | "..candidate.evidence.label.." | "..candidate.evidence.text)
        end
        if record.attempted then self.eventNote="Invitation already answered; waiting for entry or a new invitation";return end
        local blocker=self.ledger.pending.reset and "Waiting for the reset result" or self.progressionSettling and "Waiting for the new run to settle"
        if blocker then
            self.eventNote=blocker
            if record.blocker~=blocker then record.blocker=blocker;self:recordEvent("blocked",candidate.kind,blocker) end
            return
        end
        local dispatch,reason=dispatchFor(button)
        if not dispatch then
            self.eventNote=reason
            if record.blocker~=reason then record.blocker=reason;self:recordEvent("blocked",candidate.kind,reason) end
            return
        end
        record.attempted=true
        self.eventJoinPending={at=os.clock(),kind=candidate.kind,deadline=os.clock()+entryWindow(candidate.evidence.text)}
        self:recordEvent("attempt",candidate.kind,"Invoked native button handler; waiting for actual participation")
        self:cancelMovement();self.claimAttempt=nil;self.eventNote="Joining "..candidate.kind.." event; awaiting game confirmation"
        self.status="Waiting for event entry confirmation";self:log("Accepting visible "..candidate.kind.." event invitation")
        local sent,err=pcall(dispatch,function()
            return self.alive and self.settings.boss and not player:FindFirstChild("Alien") and visible(button,candidate.root)
        end)
        if not sent then self.eventNote="Join handler error; awaiting entry without repeating";self:recordEvent("dispatch_error",candidate.kind,tostring(err)) end
    end
end

-- User-observed entry path: stand in workspace.Alien.Rocket.Circle at launch.
-- Countdown evidence schedules movement; only Player.Alien confirms entry.
do
    local function seconds(text)
        local clean=tostring(text or ""):gsub("<[^>]*>",""):lower():match("^%s*(.-)%s*$")
        local n=tonumber(clean:match("^(%d+)$"))
        local m,s=clean:match("^(%d+):(%d%d)$")
        if not n and m and tonumber(s)<60 then n=tonumber(m)*60+tonumber(s) end
        if not n and (clean:find("launch",1,true) or clean:find("depart",1,true)) then
            n=tonumber(clean:match("(%d+)%s*seconds?")) or tonumber(clean:match("(%d+)%s*secs?"))
        end
        if n and n>=0 and n<=180 then return n end
    end
    local function timerVisible(object,rocket)
        local current=object
        while current and current~=rocket do
            if current:IsA("GuiObject") and not current.Visible then return false end
            if (current:IsA("BillboardGui") or current:IsA("SurfaceGui") or current:IsA("ScreenGui")) and not current.Enabled then return false end
            current=current.Parent
        end
        return current==rocket
    end
    local function readTimer(rocket)
        -- Scan only this rocket, with a hard node limit; no world/GUI sweep.
        local queue={rocket};local at=1;local number,timer
        while at<=#queue and at<=128 do
            local object=queue[at];at+=1
            if (object:IsA("TextLabel") or object:IsA("TextButton")) and timerVisible(object,rocket) then
                local n=seconds(object.Text)
                if n then
                    if number and number~=n then return nil,nil,"Ambiguous rocket countdown labels" end
                    number=n;timer=object
                end
            end
            for _,child in ipairs(object:GetChildren()) do if #queue<128 then table.insert(queue,child) end end
        end
        return number,timer
    end
    function A:rocketMessage(text,action)
        if action=="empty_launch" then
            self.rocketNotice=nil
            if self.rocketWatch then self.rocketWatch.closed=true end
            if self.eventJoinPending and self.eventJoinPending.method=="circle" then self:finishEventJoin("Rocket left without passengers; waiting for the next launch") end
            self.rocketNote="Rocket left without passengers; waiting for the next countdown"
            return
        end
        local lower=text:lower()
        -- Only an explicit native Egg Rocket launch announcement can substitute
        -- for the world timer. Rewards and unrelated numbers cannot schedule it.
        if not lower:find("launch",1,true) or lower:find("launched",1,true) or lower:find("without",1,true) then return end
        local n=seconds(lower)
        if n and n>0 then self.rocketNotice={at=os.clock(),launchAt=os.clock()+n} end
    end
    function A:boardRocket()
        local now=os.clock()
        local pending=self.eventJoinPending
        local watch=self.rocketWatch
        local arena=workspace:FindFirstChild("Alien")
        local rocket=arena and arena:FindFirstChild("Rocket")
        local circle=rocket and rocket:FindFirstChild("Circle")
        local n,timer,problem
        if rocket and self:due("rocket-countdown",0.2) then
            n,timer,problem=readTimer(rocket)
            local notice=self.rocketNotice
            local newTimer=n and n>0 and (not watch or watch.rocket~=rocket
                or n>(watch.seconds or n)+3)
            local newNotice=(not n or n==0) and notice and now<=notice.launchAt+30 and (not watch or watch.noticeAt~=notice.at)
            if newTimer or newNotice then
                if pending and pending.method=="circle" then
                    self:recordEvent("timeout","Egg Rocket","Previous boarding did not confirm before a new rocket countdown")
                    self:finishEventJoin();pending=nil
                end
                watch={rocket=rocket,circle=circle,launchAt=newNotice and notice.launchAt or now+n,seconds=n,timer=timer,
                    changedAt=now,noticeAt=newNotice and notice.at or nil}
                self.rocketWatch=watch
            elseif watch and watch.rocket==rocket and n and watch.seconds~=n and not watch.closed then
                watch.launchAt=math.min(watch.launchAt,now+n);watch.seconds=n;watch.timer=timer;watch.changedAt=now
            end
        end
        if not watch then
            self.rocketNote=problem or "Waiting for a live countdown at workspace.Alien.Rocket"
            return false
        end
        if watch.closed or now>=watch.launchAt+30 then
            self.rocketNote="Boarding window ended; waiting for the next rocket countdown"
            return false
        end
        local remaining=watch.launchAt-now
        if remaining>5 then
            self.rocketNote="Launch in "..math.ceil(remaining).."s; enter circle at 5s"
            return false
        end
        if not watch.attempted and not watch.noticeAt and (watch.seconds or 0)>5 and now-(watch.changedAt or now)>3 then
            self.rocketNote="Rocket countdown stopped updating; waiting for live launch evidence"
            return false
        end
        if watch.attempted and not (pending and pending.method=="circle") then return false end
        if self.ledger.pending.reset or self.progressionSettling then
            self.rocketNote="Boarding blocked while a progression reset settles"
            return false
        end
        circle=circle or watch.circle
        if not circle or not circle.Parent or not circle:IsA("BasePart") then
            self.rocketNote=pending and pending.method=="circle" and "Circle removed; holding position for participation confirmation" or "Rocket countdown seen; waiting for Rocket.Circle"
            if pending and pending.method=="circle" then self.status=self.rocketNote;return true end
            return false
        end
        local _,humanoid,root=self:character()
        if not root then self.rocketNote="Waiting for respawn to board the rocket";return pending and pending.method=="circle" or false end
        if not watch.attempted then
            watch.attempted=true
            if not pending then
                pending={at=now,kind="Egg Rocket"};self.eventJoinPending=pending
                self:recordEvent("attempt","Egg Rocket","Physical boarding attempt; awaiting launch and Player.Alien")
            end
            pending.method="circle";pending.deadline=watch.launchAt+30
            self:recordEvent("boarding","Egg Rocket","Entering workspace.Alien.Rocket.Circle in the last five seconds; holding through launch")
            self:cancelMovement();self.claimAttempt=nil;self:setDiamondPriority(false);self.collecting={}
        end
        -- Place the root over the circle's center with feet at its upper face.
        -- An explicit point avoids the ordinary combat offset leaving small pads.
        local point=circle.Position+Vector3.new(0,circle.Size.Y*0.5+root.Size.Y*0.5+(humanoid.HipHeight or 2),0)
        self:teleport(circle,"boarding",60,1,true,point,point+Vector3.new(0,0,-1))
        self.rocketNote=remaining>0 and "Holding inside rocket circle; launch in "..math.ceil(remaining).."s" or "Holding rocket circle; awaiting Player.Alien confirmation"
        self.eventNote=self.rocketNote;self.status=self.rocketNote
        return true
    end
end

function A:combat(d,s)
    local _,_,root=self:character(); if not root then self.status="Waiting for character respawn"; return end
    local arena=player:FindFirstChild("Alien")
    local alien=workspace:FindFirstChild("Alien"); local boss=alien and alien:FindFirstChild("Chicken")
    if arena and not boss then self.status="Joined event; waiting for arena boss";return end
    local inArena=arena~=nil and boss~=nil
    if not inArena and self.diamondPriority then return end
    if inArena and not self.settings.boss then return end
    if not inArena and not self.settings.farm then if self.settings.boss then self.status=self.eventNote or "Waiting for an event invitation" end;return end
    if not self.farm and not inArena then self:claimFarm();return end
    local chicken=inArena and boss or (self.farm and self.farm:FindFirstChild("Chicken"))
    local hp=health(chicken)
    if hp==nil or hp==-math.huge then self.status=inArena and "Waiting for arena result" or "Waiting for a live farm chicken"; return end
    local state=self.fight
    if not state or state.target~=chicken then
        state={target=chicken,health=hp,progressAt=state and state.progressAt or (self.lastFarmProgress or os.clock()),mana=value(chicken,"Mana")}; self.fight=state
    elseif hp<state.health then
        state.progressAt=os.clock(); self.stats.hits+=1; self.lastFarmProgress=os.clock(); state.blockUntil=nil
    elseif hp>state.health+1e-10 and d.level.current%5==0 then state.healed=true end
    local mana=value(chicken,"Mana")
    if type(mana)=="number" and type(state.mana)=="number" and mana<state.mana then state.healed=true end
    state.mana=mana
    state.health=hp
    if not self:teleport(chicken,inArena and "boss" or "combat",inArena and 50 or 10,inArena and 10 or 7.5,true) then
        self.status="Following chicken"; return
    end
    if not inArena then
        local distance=(root.Position-chicken.Position).Magnitude
        for _,farm in ipairs(self.farms or {}) do
            local other=farm~=self.farm and farm:FindFirstChild("Chicken")
            if other and value(farm,"Owner") and (other.Position-root.Position).Magnitude<distance then self.status="Another farm is the nearest attack target; move closer to your chicken";return end
        end
    end
    if state.blockUntil and os.clock()<state.blockUntil then self.status="No observed damage; waiting for upgrades or target recovery"; return end
    if os.clock()-state.progressAt>12 then
        if not state.blockUntil then state.blockUntil=os.clock()+5; self:log("No damage from target; bounded attack probes only"); return end
    end
    self.status=inArena and "Fighting event boss; reward and return handled by game" or "Farming level "..d.level.current.."  ·  "..d.level.progress.."/"..d.level.maxprogress
    local power=d.powerups or {}
    if power.autoclick==true or type(power.autoclick)=="number" and power.autoclick>0 or type(power.autoattack)=="table" and (power.autoattack.bought or 0)+(power.autoattack.duration or 3600)>os.time() then return end
    local gear=self:gear(d)
    local rate=math.max(1,s.cps or 1)+gear.wingsTier+((s.abilities or {})["1"] and s.abilities["1"].effect or 0)+(s.passes and s.passes["Pet Chick"] and 2 or 0)
    if self:due("attack",1/math.max(1,rate)) then
        self:remote("Weapon",inArena and "alien" or "self",NATIVE_WEAPON_TOKEN)
        if state.blockUntil then state.blockUntil=os.clock()+5 end
    end
end
-- Native stage transitions have bounded recovery, and boss retries use actual
-- ordinary combat output rather than egg income or speculative skill uptime.
function A:progress(d,s)
    if not self.alive or not self.running or not self.settings.progress then self.stageNote="Disabled";return end
    if self.diamondPriority then self.stageNote="Paused for diamonds";return end
    if self.eventJoinPending or player:FindFirstChild("Alien") then self.stageNote="Paused for event entry / combat";return end
    if self.ledger.pending.reset or self.progressionSettling or self.progressionIntent then self.stageNote="Paused for progression reset";return end
    if self.startupClaim then self.stageNote="Waiting for farm ownership";return end
    local l=d.level;local now=os.clock()
    local run=table.concat({d.prestige or 0,d.superprestige or 0,d.ascension or 0},":")
    local attempt=self.stageAttempts
    if not attempt or attempt.run~=run or attempt.level~=l.current then
        -- A changed native level proves that an old transition is no longer
        -- awaiting unchanged-state recovery. Never reuse its retry counter.
        if attempt and attempt.run~=run or self.ledger.uncertain.stage and self.ledger.uncertain.stage~=tostring(l.current) then self.ledger.uncertain.stage=nil end
        attempt={run=run,level=l.current,count=0};self.stageAttempts=attempt
    end
    if self.observedLevel~=l.current or self.observedProgress~=l.progress then self.lastFarmProgress=now;self.observedLevel=l.current;self.observedProgress=l.progress end
    local function normalRate(data,session)
        local power=data.powerups or {};local auto=power.autoattack
        local clicking=self.settings.farm==true or power.autoclick==true or type(power.autoclick)=="number" and power.autoclick>0 or type(auto)=="table" and (auto.bought or 0)+(auto.duration or 3600)>os.time()
        return P.damageRate(data,session,self:gear(data),clicking,true)
    end
    local target=self.farm and self.farm:FindFirstChild("Chicken")
    local hp=health(target);local mana=value(target,"Mana")
    local watch=self.stageWatch
    if not watch or watch.level~=l.current or watch.target~=target then watch={level=l.current,target=target};self.stageWatch=watch end
    if hp and watch.health and hp>watch.health+1e-10 or type(mana)=="number" and type(watch.mana)=="number" and mana<watch.mana then watch.healed=true end
    watch.health=hp;watch.mana=mana
    local ready=l.progress>=l.maxprogress or l.current%5==0 and l.progress==1 or l.current<l.highest
    if self.retreat then
        local rate=normalRate(d,s)
        if now-self.retreat.at>=8 and rate>-math.huge and rate>=self.retreat.output+math.log10(1.5) then self.retreat=nil
        else self.stageNote="Funding upgrades below boss; waiting for 1.5x normal damage";self.status="Funding upgrades below boss";return end
    end
    local verb=ready and "Next Level" or l.current%5==0 and l.current>1 and (watch.healed or self.fight and self.fight.healed) and "Previous Level" or nil
    if not verb then self.stageNote="Waiting for native stage completion";return end
    if self.ledger.pending.stage then self.stageNote="Waiting for native stage confirmation";return end
    local base=l.current;local stamp=tostring(base)
    local uncertain=self.ledger.uncertain.stage==stamp
    if uncertain then
        -- A tracker may be absent after an older script supplied the uncertain
        -- request. Count it conservatively as the first request, starting a new
        -- delay rather than immediately replaying it.
        if attempt.count==0 then attempt.count=1;attempt.at=now;attempt.verb=verb end
        if attempt.verb~=verb then self.stageNote="Stage request unconfirmed; native transition readiness changed";return end
        if attempt.count>=3 then self.stageNote="Stage request unconfirmed after 3 attempts; use the native level control";return end
        if now-(attempt.at or now)<30 then self.stageNote="Stage unconfirmed; delayed retry "..(attempt.count+1).."/3";return end
        if (self.lastDataAt or -math.huge)<=(attempt.at or now) then self.stageNote="Stage unconfirmed; waiting for a newer native data event";return end
    elseif attempt.count>=3 then
        self.stageNote="Stage request limit reached; waiting for native level change";return
    end
    -- Recheck the controller's current server pair immediately before dispatch.
    -- A delayed retry may not act on an earlier table passed by a caller.
    if self.data~=d or self.session~=s or d.level.current~=base then self.stageNote="Waiting for the latest received stage snapshot";return end
    local stillReady=d.level.progress>=d.level.maxprogress or base%5==0 and d.level.progress==1 or base<d.level.highest
    local stillVerb=stillReady and "Next Level" or base%5==0 and base>1 and (watch.healed or self.fight and self.fight.healed) and "Previous Level" or nil
    if stillVerb~=verb then self.stageNote="Native stage readiness changed before dispatch";return end
    if uncertain then self.ledger.uncertain.stage=nil end
    local began=self.ledger:begin("stage","stage",stamp,function(nextD)
        if nextD.level.current~=base then
            if self.settings.progress and verb=="Previous Level" and nextD.level.current<base then self.retreat={at=os.clock(),output=normalRate(nextD,self.session)} end
            self.stageNote="Native stage change confirmed";return true
        end
        return false
    end,function()
        attempt.count+=1;attempt.at=os.clock();attempt.verb=verb
        self:remote("Progress",NATIVE_PROGRESS_TOKEN,verb)
    end)
    if not began then
        if uncertain then self.ledger.uncertain.stage=stamp end
        self.stageNote="Waiting for an eligible native stage request";return
    end
    self.stageNote=verb.." requested ("..attempt.count.."/3); waiting for native level change"
    self:log(self.stageNote)
end

function A:observeRun(d)
    if not (self.session.loaded or d.username==player.DisplayName or self.lastDataAt) then return end
    local key=table.concat({d.prestige or 0,d.superprestige or 0,d.ascension or 0},":")
    if self.runKey and self.runKey~=key then
        self:clearBlackAllocation()
        self:setDiamondPriority(false)
        self:cancelMovement();self.fight=nil;self.retreat=nil;self.lastAbility=nil;self.decoyFor=nil
        self.collecting={};self.collectBackoff=setmetatable({},{__mode="k"})
        self.observedLevel=nil;self.observedProgress=nil;self.stageWatch=nil
        self.progressionWatch=nil;self.progressionIntent=nil;self.heroGoal=nil
        self.hireAttempts={}
        self.lastFarmProgress=os.clock()
        self.ledger.pending={reset=self.ledger.pending.reset};self.ledger.uncertain={}
        self:scan();self:log("New progression run; rebuilding from current ownership and catalogs")
    end
    self.runKey=key
    self:syncHeroBudget(d)
end
function A:resetMessage(message)
    self.resetNote=message;self:log(message)
    if self.rayfield and self.rayfield.Notify then
        pcall(function() self.rayfield:Notify({Title="Progression",Content=message,Duration=7}) end)
    end
end
function A:performReset(kind,automatic)
    if not self.alive then return end
    local definitions={
        retire={verb="Prestige",counter="prestige",label="Retire"},
        rebirth={verb="Super Prestige",counter="superprestige",label="Rebirth"},
        ascend={verb="Ascension",counter="ascension",label="Ascend"}
    }
    local action=definitions[kind];if not action then return end
    if not self.ready or not self.uiReady or not self.data or not self.session then self:resetMessage("Player data is still loading");return end
    if self.ledger.pending.reset then self:resetMessage("Waiting for the previous reset result");return end
    local d=self.data -- Latest paired server snapshot, or the startup native cache.
    if not (self.session.loaded or d.username==player.DisplayName or self.lastDataAt) then self:resetMessage("Waiting for authoritative player data");return end
    if player:FindFirstChild("Alien") then self:resetMessage("Leave the event boss before resetting");return end
    if self.eventJoinPending then self:resetMessage("Wait for event entry before resetting");return end
    if kind=="retire" and ((d.heroes["20"] or {}).level or 0)<150 then self:resetMessage("Retire requires Queen Elizabeth II at level 150");return end
    if kind=="rebirth" and d.level.highest<301 then self:resetMessage("Rebirth requires beating level 300");return end
    if kind=="ascend" and d.level.highest<50001 then self:resetMessage("Ascend requires beating level 50,000");return end
    local remote=Events and Events:FindFirstChild("Prestige")
    if not remote or not remote:IsA("RemoteEvent") then self:resetMessage("The game's Prestige remote is unavailable");return end
    local nextState,priorState
    if automatic then
        if self.saving then self.progressionNote="Waiting for settings persistence before reset";return false end
        if kind=="ascend" or not self.settings[kind=="retire" and "autoRetire" or "autoRebirth"] then return false end
        local loaded=self:progressionReady(d,self.session);if not loaded then return false end
        local run=table.concat({d.prestige or 0,d.superprestige or 0,d.ascension or 0},":")
        local eligible,note=self:resetRetryReady(d,kind)
        if not eligible then self.resetRetryNote=note;return false end
        local plan,hold=P.resetPlan(d,self.session,self:resetMetrics(d,self.session))
        if not plan or plan.kind~=kind then self.progressionNote=hold or "Reset eligibility changed before dispatch";return false end
        if next(self.ledger.pending) or self:manualMenuOpen() or self.diamondPriority then return false end
        priorState=self.autoResetState
        local prior=priorState and priorState.run==run and priorState
        local retires=prior and (prior.retireAttempts or (prior.kind=="retire" and (prior.attempts or 1) or 0)) or 0
        local rebirths=prior and (prior.rebirthAttempts or (prior.kind=="rebirth" and (prior.attempts or 1) or 0)) or 0
        if kind=="retire" then retires+=1 else rebirths+=1 end
        nextState={run=run,kind=kind,before=d[action.counter] or 0,highest=d.level.highest,current=d.level.current,
            queen=(d.heroes["20"] or {}).level or 0,at=os.time(),confirmed=false,rebuilt=false,
            attempts=kind=="retire" and retires or rebirths,retireAttempts=retires,rebirthAttempts=rebirths}
    end
    local before=d[action.counter] or 0;local key="reset-"..action.verb
    -- Only a fully revalidated automatic recovery or an explicit manual click
    -- can reopen this exact reset lane. Other uncertain transactions stay held.
    local priorUncertain=self.ledger.uncertain[key]
    self.ledger.uncertain[key]=nil
    self:setDiamondPriority(false);self:cancelMovement();self.collecting={};self.lastAbility=nil;self.decoyFor=nil;self.heroGoal=nil
    self.resetRequest={counter=action.counter,before=before,label=action.label,automatic=automatic==true}
    self:clearBlackAllocation()
    local session=self.session;local cancelled
    local began=self.ledger:begin("reset",key,tostring(before),function(x) return (x[action.counter] or 0)>before end,function()
        if automatic then
            self.autoResetState=nextState
            self:save() -- Record each bounded attempt before native dispatch.
            local ready=self:progressionReady(d,session)
            local plan=ready and P.resetPlan(d,session,self:resetMetrics(d,session))
            local pause=self.diamondPriority or self:manualMenuOpen() or not self.settings[kind=="retire" and "autoRetire" or "autoRebirth"]
            if table.concat({d.prestige or 0,d.superprestige or 0,d.ascension or 0},":")~=nextState.run
                or (d[action.counter] or 0)~=before then pause=true end
            if priorState and priorState.run==nextState.run and (not self.receivedDataEvent
                or os.clock()-(self.lastDataAt or -math.huge)>10) then pause=true end
            for lane in pairs(self.ledger.pending) do if lane~="reset" then pause=true end end
            if not ready or pause or not plan or plan.kind~=kind then
                -- Nothing was sent, so this reservation is not an attempt.
                cancelled=true;self.autoResetState=priorState;self:save();return
            end
        end
        self.resetRetryNote=nextState and ("Waiting for "..kind.." attempt "..nextState.attempts.."/3 confirmation") or "Manual reset requested"
        self:resetMessage(action.label.." requested"..(nextState and " (attempt "..nextState.attempts.."/3)" or "").."; waiting for the game")
        remote:FireServer(action.verb,false) -- Native no-refund action; works with all toggles off.
    end)
    if not began or cancelled then
        if cancelled then self.ledger.pending.reset=nil;self.resetRequest=nil;self.resetNote="Reset canceled before dispatch; current eligibility changed" end
        if not began then self.resetRequest=nil end
        self.ledger.uncertain[key]=priorUncertain;return false
    end
    return true
end
function A:observeReset(d)
    local request=self.resetRequest;if not request then return end
    if (d[request.counter] or 0)>request.before then
        self.resetRequest=nil;self:resetMessage(request.label.." confirmed")
    elseif not self.ledger.pending.reset then
        self.resetRequest=nil;self:resetMessage(request.label.." was not confirmed. Check the game before clicking again.")
    end
end
-- A single controller owns reset preparation and BE/GE transactions.
local function progressionRun(d)
    return table.concat({d.prestige or 0,d.superprestige or 0,d.ascension or 0},":")
end
function A:resetRetryReady(d,kind)
    local state=self.autoResetState
    if not state or state.run~=progressionRun(d) then return true,"No unconfirmed reset in this run" end
    kind=kind=="prepareRetire" and "retire" or kind
    local attempts=state[kind=="retire" and "retireAttempts" or "rebirthAttempts"]
        or (state.kind==kind and (state.attempts or 1) or 0)
    if state.confirmed or state.rebuilt or (d.level.highest or 0)<state.highest
        or ((d.heroes["20"] or {}).level or 0)<state.queen then
        return false,"Reset data may be rebuilding; waiting for matching native counters"
    end
    if attempts>=3 then return false,kind.." unconfirmed after 3 attempts this run; manual retry remains available" end
    local delay=state.attempts and state.attempts>=2 and 120 or 60
    local remaining=math.max(0,state.at+delay-os.time())
    if remaining>0 then return false,"Unconfirmed "..state.kind.."; recovery check in "..remaining.."s (next "..kind.." attempt "..(attempts+1).."/3)" end
    local observation=self.resetRetryObservation
    if not observation or observation.state~=state then
        -- A restart cannot convert an old module-cache copy into a new server
        -- acknowledgement. Require a complete event after arming recovery.
        self.resetRetryObservation={state=state,sequence=self.dataSequence or 0,at=os.clock()}
        return false,"Reset recovery armed; waiting for a fresh server Data event"
    end
    if not self.receivedDataEvent or (self.dataSequence or 0)<=observation.sequence
        or (self.lastDataAt or -math.huge)<observation.at or os.clock()-(self.lastDataAt or -math.huge)>10 then
        return false,"Reset recovery waiting for a fresh server Data event"
    end
    return true,"Fresh server data received; rechecking "..kind.." eligibility (attempt "..(attempts+1).."/3)"
end
function A:progressionReady(d,s)
    if not self.alive or not self.ready or not self.uiReady or not self.running then return false,"Automation is not ready" end
    if type(d)~="table" or type(s)~="table" or not (s.loaded or d.username==player.DisplayName or self.lastDataAt) then
        return false,"Waiting for authoritative player data"
    end
    -- Both the server event and DataHandler's cache contain native data, but
    -- their tables need not share identity. Use one paired source throughout
    -- this controller; only a superseded controller snapshot is stale.
    if self.data~=d or self.session~=s then return false,"Waiting for the latest received data snapshot" end
    if self.startupClaim then return false,"Waiting for farm ownership" end
    if player:FindFirstChild("Alien") or self.eventJoinPending then return false,"Waiting for the event to finish" end
    if self:manualMenuOpen() then return false,"Paused while you use a native menu" end
    return true
end
function A:resetSettlement(d)
    local state=self.autoResetState
    if not state or state.run==progressionRun(d) then return true end
    if not state.confirmed then
        state.confirmed=true;state.at=os.time();self:save()
    end
    -- A counter update can precede the actual rebuilt heroes/stage. A timer
    -- alone is insufficient evidence that a new run has settled.
    if not state.rebuilt and ((d.level.current or 0)<state.current or (d.level.highest or 0)<state.highest
        or ((d.heroes["20"] or {}).level or 0)<state.queen) then
        state.rebuilt=true;self:save()
    end
    if not state.rebuilt then return false,"Waiting for rebuilt stage/hero data after reset" end
    if os.time()-state.at<15 then return false,"Allowing the new run to settle" end
    return true
end
function A:resetMetrics(d,s)
    local now=os.clock();local run=progressionRun(d);local w=self.progressionWatch
    local frontier=d.level.current>=d.level.highest
    local progress=tonumber(d.level.progress) or 0
    if not w or w.run~=run then
        w={run=run,startedAt=now,lastAdvanceAt=now,highest=d.level.highest,frontierProgress=frontier and progress or 0};self.progressionWatch=w
    end
    if w.pausedAt then
        local elapsed=math.max(0,now-w.pausedAt);w.startedAt+=elapsed;w.lastAdvanceAt+=elapsed;w.pausedAt=nil
    end
    if d.level.highest~=w.highest then
        w.highest=d.level.highest;w.frontierProgress=frontier and progress or 0;w.lastAdvanceAt=now
    elseif frontier and progress>(w.frontierProgress or 0) then
        -- Kills toward the next stage are progress too. Repeated lower-stage
        -- farming and partial damage on a healing boss cannot refresh this.
        w.frontierProgress=progress;w.lastAdvanceAt=now
    end
    local wall=false
    if self.settings.farm and self.settings.progress and self.farm and self.farm:FindFirstChild("Owner")
        and self.farm.Owner.Value==player and self:character() then
        local target=self.farm:FindFirstChild("Chicken");local hp=health(target)
        local healed=self.retreat~=nil or self.fight and self.fight.healed or self.stageWatch and self.stageWatch.healed
        if healed then wall=true
        elseif hp and hp~=-math.huge and d.level.current>=d.level.highest-1 then
            local rate=P.damageRate(d,s,self:gear(d),true,true)
            wall=P.killSeconds(hp,rate)>30
        end
    end
    return {runSeconds=now-w.startedAt,stalledSeconds=now-w.lastAdvanceAt,wall=wall,
        autoRetire=self.settings.autoRetire,autoRebirth=self.settings.autoRebirth}
end
function A:prepareRetirement(d,plan)
    local intent=self.progressionIntent;local B=M.BigNum
    if self.ledger.pending.prepare then return true end
    local queen=(d.heroes["20"] or {}).level or 0
    local id,amount,cost;local essential=queen<150
    if queen<150 then
        if queen<1 then
            -- A native hire is a single level, in roster order. Jumping straight
            -- to Queen with a bulk training quantity leaves ownership unchanged.
            id=P.nextHire(d)
            if not id or tonumber(id)>20 then self.progressionNote="Waiting for the native retirement hero roster";return true end
            amount=1;cost=P.cost(d,id,0,1)
        else
            id="20";local affordable=P.maxLevels(d,id,queen,d.eggs,150-queen)
            amount=Core.trainAmount(affordable)
            if amount<1 then self.progressionNote="Saving White Eggs for Queen Elizabeth II level 150";return true end
            cost=P.cost(d,id,queen,queen+amount)
        end
        if B.Compare(d.eggs,cost)=="<" then self.progressionNote="Saving White Eggs to hire "..M.HeroesData.Stats[id].Title;return true end
    elseif plan.kind=="retire" then
        intent.prepSweepAt=intent.prepSweepAt or os.clock()
        if (intent.prepCount or 0)>=10 or os.clock()-intent.prepSweepAt>=25 then return false end
        -- These otherwise-lost White Eggs serve a different objective from
        -- normal DPS farming. Bound this final sweep separately from the
        -- essential unlock, and never hire additional workers for this sweep.
        local best=-math.huge
        for heroId in pairs(M.HeroesData.Stats) do
            local level=(d.heroes[heroId] or {}).level or 0
            if level<1 then continue end
            local n=Core.trainAmount(P.maxLevels(d,heroId,level,d.eggs,10000))
            if n>0 then
                local price=P.cost(d,heroId,level,level+n)
                local score=math.log10(n)-Core.log(price)
                if score>best then id,amount,cost,best=heroId,n,price,score end
            end
        end
        if not id then return false end
    else return false end
    local base=(d.heroes[id] or {}).level or 0
    local stamp=progressionRun(d)..":"..base
    local key="retirement-prep-"..id
    if not self.ledger:available("prepare",key,stamp) then
        if essential then self.progressionNote="Retirement unlock request unconfirmed; waiting for "..M.HeroesData.Stats[id].Title.." state";return true end
        return false
    end
    local path
    if base==0 then
        if not self.farm then self.progressionNote="Waiting for farm placement before hiring "..M.HeroesData.Stats[id].Title;return true end
        local ok,position=pcall(M.GetFarmHeroPos,self.farm,tonumber(id))
        if not ok or position==nil then self.progressionNote="Waiting for native hero placement for "..M.HeroesData.Stats[id].Title;return true end
        path={position}
    end
    local began=self.ledger:begin("prepare",key,stamp,function(nextD)
        return ((nextD.heroes[id] or {}).level or 0)>=base+amount
    end,function() self:remote("Heroes","Train",id,path,amount) end)
    if began then
        if not essential then intent.prepCount=(intent.prepCount or 0)+1 end
        local op=self.ledger.pending.prepare;op.cost=cost;op.reserveCost=cost
        op.describe=function(nextD) return "retirement preparation "..M.HeroesData.Stats[id].Title.." level "..base.." -> "..tostring((nextD.heroes[id] or {}).level or 0) end
        self.progressionNote="Preparing retirement: "..M.HeroesData.Stats[id].Title.." +"..amount
        self:log(self.progressionNote)
    end
    return began
end
function A:autoProgression(d,s)
    if not self.settings.autoRetire and not self.settings.autoRebirth then
        if self.progressionWatch then self.progressionWatch.pausedAt=self.progressionWatch.pausedAt or os.clock() end
        self.progressionIntent=nil;return false
    end
    local ready,reason=self:progressionReady(d,s)
    if not ready or self.diamondPriority then
        if self.progressionWatch then self.progressionWatch.pausedAt=self.progressionWatch.pausedAt or os.clock() end
        self.progressionIntent=nil;self.progressionNote=self.diamondPriority and "Collecting diamonds before any reset" or reason;return false
    end
    if self.ledger.pending.reset then self.progressionNote="Waiting for reset confirmation";return true end
    local settled,note=self:resetSettlement(d)
    if not settled then self.progressionIntent=nil;self.progressionNote=note;return true end
    local metrics=self:resetMetrics(d,s)
    local plan,hold=P.resetPlan(d,s,metrics)
    local recovery,recoveryNote=self:resetRetryReady(d,plan and plan.kind or (self.settings.autoRetire and "retire" or "rebirth"))
    self.resetRetryNote=recoveryNote
    if not plan then
        self.progressionIntent=nil
        local queen=(d.heroes["20"] or {}).level or 0
        local details={tostring(hold)}
        if self.settings.autoRetire then
            details[#details+1]="Retire observation "..math.floor(metrics.runSeconds).." / 180s, no progress "..math.floor(metrics.stalledSeconds).." / 90s"
            details[#details+1]="Queen "..queen.." / 150, payout "..budgetText(P.retirePayout(d)).." BE"
            if queen<150 then details[#details+1]="Unlock cost "..budgetText(P.retireUnlockCost(d)).." White Eggs" end
        end
        if self.settings.autoRebirth then details[#details+1]="Rebirth "..budgetText(d.goldeggspending or {0,0}).." / "..P.rebirthTarget(d).." Gold Eggs; rebirth observation "..math.floor(metrics.runSeconds).." / 300s" end
        if not recovery then details[#details+1]=recoveryNote end
        self.progressionNote=table.concat(details,"; ");return false
    end
    if not recovery then self.progressionIntent=nil;self.progressionNote=recoveryNote;return false end
    local intent=self.progressionIntent
    if not intent or intent.run~=progressionRun(d) or intent.kind~=plan.kind and not (intent.kind=="prepareRetire" and plan.kind=="retire") then
        intent={run=progressionRun(d),kind=plan.kind,at=os.clock(),prepAt=os.clock(),prepCount=0};self.progressionIntent=intent
        self.heroGoal=nil
        self:log("Progression plan: "..plan.reason)
    end
    intent.kind=plan.kind
    for lane in pairs(self.ledger.pending) do
        if lane~="prepare" then self.progressionNote="Waiting for outstanding purchases/stage changes before reset";return true end
    end
    if self.ledger.pending.prepare then self.progressionNote="Waiting for retirement preparation result";return true end
    if plan.kind=="prepareRetire" or plan.kind=="retire" then
        if self:prepareRetirement(d,plan) then return true end
        if plan.kind=="prepareRetire" then return true end
    end
    intent.drainedAt=intent.drainedAt or os.clock()
    if os.clock()-intent.drainedAt<3 then self.progressionNote="Settling purchases before "..plan.kind;return true end
    -- Recompute eligibility after every preparation purchase. performReset
    -- independently reads the latest received pair and enabled toggle at dispatch.
    if self:performReset(plan.kind,true) then self.progressionIntent=nil;return true end
    self.progressionNote="Reset not dispatched; waiting for native eligibility";return true
end
function A:clearBlackAllocation()
    local job=self.blackPlanning;self.blackPlanning=nil;self.blackAllocation=nil
    if job and job.thread and coroutine.status(job.thread)~="dead" then pcall(task.cancel,job.thread) end
end
function A:beginBlackAllocation(d,s,gear,clicking)
    if self.blackPlanning or os.clock()<(self.blackPlanRetryAt or 0) then return end
    local snapshot,session,equipment=Core.copy(d),Core.copy(s),Core.copy(gear)
    local job={run=progressionRun(d),water=(d.phoenixeggs or {})["1"],levels=Core.copy(d.eastereggs or {})}
    local blocked={}
    for n=1,22 do
        local id=tostring(n);local level=job.levels[id] or {0,0}
        if self.ledger.uncertain["egg-black-"..id]==job.run..":"..budgetText(level) then blocked[id]=true end
    end
    self.blackPlanning=job;self.eggNote="Calculating a complete Black Egg allocation in background"
    job.thread=task.spawn(function()
        task.wait() -- Publish the task before its first computation/cancellation.
        local ok,result=pcall(P.blackAllocation,snapshot,session,equipment,{clicking=clicking,blocked=blocked,yieldStep=function(phase,step)
            if self.blackPlanning~=job or not self.alive or not self.settings.blackEggs
                or self.ledger.pending.reset or self.progressionIntent or progressionRun(self.data or snapshot)~=job.run then return false end
            self.eggNote="Calculating Black Egg allocation: "..phase.." "..step
            task.wait()
            return self.blackPlanning==job and self.alive and self.settings.blackEggs
        end})
        if self.blackPlanning~=job then return end
        self.blackPlanning=nil
        if not ok or not result then
            self.blackPlanRetryAt=os.clock()+2;self.eggNote="Black Egg allocation interrupted; will recalculate"
            if not ok then self:log("Black Egg planner: "..tostring(result)) end
            return
        end
        if not self.alive or not self.settings.blackEggs or progressionRun(self.data or snapshot)~=job.run then return end
        if #result.entries==0 then
            self.blackPlanRetryAt=os.clock()+2;self.eggNote="Black Eggs: no worthwhile affordable allocation";return
        end
        self.blackAllocation={run=job.run,water=job.water,expected=job.levels,entries=result.entries,index=1}
        self.eggNote="Black Egg allocation ready: "..#result.entries.." purchases, cost "..budgetText(result.totalCost).." BE"
        self:log(self.eggNote)
    end)
end
function A:nextBlackPurchase(d,s,gear,clicking)
    local q=self.blackAllocation;local B=M.BigNum
    local function restart(reason)
        self:clearBlackAllocation();self.eggNote=reason
        self:beginBlackAllocation(d,s,gear,clicking)
        return nil
    end
    if not q then self:beginBlackAllocation(d,s,gear,clicking);return nil end
    if q.run~=progressionRun(d) or q.water~=(d.phoenixeggs or {})["1"] then return restart("Recalculating Black Eggs after reset/discount change") end
    if q.inFlight then
        local p=q.inFlight
        local owned=(d.eastereggs or {})[p.id]
        if not owned or B.Compare(owned,p.after)~="=" then return restart("Recalculating after an unconfirmed or changed egg result") end
        q.expected[p.id]=Core.copy(p.after);q.inFlight=nil;q.index+=1
    end
    for id,level in pairs(q.expected) do
        local actual=(d.eastereggs or {})[id]
        if not actual or B.Compare(actual,level)~="=" then return restart("Recalculating after native egg levels changed") end
    end
    for id in pairs(d.eastereggs or {}) do if not q.expected[id] then return restart("Recalculating after native egg ownership changed") end end
    if q.index>#q.entries then
        self.blackAllocation=nil;self.eggNote="Black Egg allocation completed"
        self:beginBlackAllocation(d,s,gear,clicking);return nil
    end
    -- Reprice the ENTIRE outstanding allocation against the real wallet, not
    -- just its next item. A manual purchase must not make the tail unfunded.
    local pricing=table.clone(d);pricing.eastereggs=Core.copy(d.eastereggs or {})
    local remaining={0,0};local ownedCount=0;for _ in pairs(pricing.eastereggs) do ownedCount+=1 end
    for i=q.index,#q.entries do
        local p=q.entries[i];local cost
        if p.action=="Hatch" then
            local price=M.EggsData.HatchCost[ownedCount+1]
            cost=price and B.fromNum(price);ownedCount+=1
        else cost=P.blackCost(pricing,p.id,p.amount) end
        if not cost then return restart("Recalculating an invalid Black Egg allocation") end
        remaining=B.Add(remaining,cost);pricing.eastereggs[p.id]=Core.copy(p.after)
    end
    if B.Compare(remaining,d.blackeggs)==">" then return restart("Recalculating Black Eggs for the current wallet") end
    local entry=q.entries[q.index]
    local plan=P.blackQuote(d,s,gear,entry,{clicking=clicking})
    if not plan then return restart("Recalculating Black Eggs after the modeled benefit changed") end
    plan.reason=(plan.action=="Hatch" and "Unlock " or "Allocate ")..M.EggsData[plan.id].title.."; custom allocation "..q.index.."/"..#q.entries
    return plan,q
end
function A:spendEggs(d,s,kind)
    local enabled=kind=="black" and self.settings.blackEggs or kind=="gold" and self.settings.goldEggs
    if not enabled then return false end
    local ready,reason=self:progressionReady(d,s)
    if not ready then self.eggNote=reason;return false end
    if self.ledger.pending.reset or self.progressionIntent then self.eggNote="Waiting for progression reset/preparation";return false end
    local settled,note=self:resetSettlement(d);if not settled then self.eggNote=note;return false end
    if self.ledger.pending.eggs then
        self.eggNote=(self.ledger.pending.eggs.summary or "Egg purchase").."; waiting for confirmation";return false
    end
    local power=d.powerups or {};local auto=power.autoattack
    local clicking=self.settings.farm==true or power.autoclick==true or type(power.autoclick)=="number" and power.autoclick>0
        or type(auto)=="table" and (auto.bought or 0)+(auto.duration or 3600)>os.time()
    local plans,allocation
    if kind=="black" then
        local plan;plan,allocation=self:nextBlackPurchase(d,s,self:gear(d),clicking)
        if not plan then return false end
        plans={plan}
    else plans=P.goldEggs(d,s,self:gear(d)) end
    local B=M.BigNum
    for _,plan in ipairs(plans or {}) do
        local before=plan.before;local key="egg-"..kind.."-"..plan.id
        local run=progressionRun(d)
        local stamp=run..":"..(kind=="black" and budgetText(before or {0,0}) or tostring(before or 0))
        if not self.ledger:available("eggs",key,stamp) then
            if allocation then self:clearBlackAllocation();self.eggNote="Recalculating around an unconfirmed egg request" end
            continue
        end
        local wallet=kind=="black" and d.blackeggs or d.goldeggs
        if B.Compare(plan.cost,wallet)==">" then continue end
        local began=self.ledger:begin("eggs",key,stamp,function(nextD)
            if progressionRun(nextD)~=run then return false end
            local owned=kind=="black" and (nextD.eastereggs or {})[plan.id] or (nextD.phoenixeggs or {})[plan.id]
            if kind=="black" then
                return owned and B.Compare(owned,plan.action=="Hatch" and {1,0} or B.Add(before,plan.amount))~="<"
            end
            return type(owned)=="number" and owned>=(before or 0)+plan.amount
        end,function()
            if kind=="gold" then self:remote("PhoenixEggs","Boost",plan.id,plan.amount)
            elseif plan.action=="Hatch" then self:remote("EasterEggs","Hatch",plan.id)
            else self:remote("EasterEggs","Enhance",plan.id,plan.amount) end
        end)
        if began then
            if allocation then allocation.inFlight=plan end
            local op=self.ledger.pending.eggs;op.cost=plan.cost;op.kind=kind;op.id=plan.id
            local quantity=kind=="black" and plan.action=="Hatch" and "1" or kind=="black" and budgetText(plan.amount) or tostring(plan.amount)
            local spend=budgetText(plan.cost)
            op.describe=function() return kind.." egg "..plan.id.." "..plan.action.." +"..quantity.."; cost "..spend end
            self.eggNote=(kind=="black" and "Black" or "Gold").." Egg: "..(plan.reason or plan.action).." ("..plan.id.."); +"..quantity..", cost "..spend
            op.summary=self.eggNote
            self:log(self.eggNote);return true
        end
    end
    self.eggNote=(kind=="black" and "Black" or "Gold").." Eggs: saving for a worthwhile affordable upgrade";return false
end

function A:abilities(d,s)
    if not self.settings.abilities then return end
    local character,_,root=self:character()
    if not root or root.Position.Y>5000 then self.abilityNote="Waiting for a character in the native ability area";return end
    if self.ledger.pending.ability or self.ledger.pending.reset then self.abilityNote="Waiting for the previous ability or reset result";return end
    local unlocked=P.unlocked(d); local active=s.abilities or {}; local cd=d.cooldowns or {}
    local damageSkills={ ["1"]=true,["2"]=true,["3"]=true,["7"]=true }
    local function ready(id)
        return unlocked[id] and (tonumber(cd[id]) or 0)<=os.time() and not active[id] and self.ledger:available("ability","ability-"..id,tostring(tonumber(cd[id]) or 0))
    end
    local function cooldownOthers(cooldowns,except)
        local t={};for id,time in pairs(cooldowns) do if id~=except then t[id]=time end end;return signature(t)
    end
    local function send(id)
        local before=tonumber(cd[id]) or 0;local exploits=d.exploits or 0;local hadDecoy=character:FindFirstChild("Decoy")~=nil
        local sent=self.ledger:begin("ability","ability-"..id,tostring(before),function(nextD,nextS)
            return (tonumber((nextD.cooldowns or {})[id]) or 0)>before or (nextS.abilities or {})[id]~=nil
                or id=="6" and (nextD.exploits or 0)>exploits
                or id=="8" and not hadDecoy and character.Parent~=nil and character:FindFirstChild("Decoy")~=nil
        end,function() self:remote("Abilities",id) end)
        if sent then
            self.lastAbility={id=id,before=before,at=os.clock(),others=cooldownOthers(cd,id)}
            self.ledger.pending.ability.describe=function(nextD)
                return M.AbilitiesData[id].title.."; cooldown="..tostring((nextD.cooldowns or {})[id] or 0)
            end
            self:log("Use "..M.AbilitiesData[id].title.." | "..tostring(self.abilityNote))
        end
        return sent
    end
    -- Reset a just-used combat cooldown before another ability can become the
    -- native 'last ability'. Unrelated/manual cooldown changes invalidate it.
    local last=self.lastAbility
    if ready("9") and last and damageSkills[last.id] and os.clock()-last.at<15 and cooldownOthers(cd,last.id)==last.others and (tonumber(cd[last.id]) or 0)-os.time()>30 then
        self.abilityNote="Hamburger: restore "..M.AbilitiesData[last.id].title.." for a later boss";send("9");return
    end
    local target=self.farm and self.farm:FindFirstChild("Chicken");local hp=health(target)
    local boss=target and hp and hp~=-math.huge and d.level.current%5==0 and d.level.progress~=1 and not player:FindFirstChild("Alien")
    local canFight=boss and not self.diamondPriority and not self.ledger.pending.stage and not self.startupClaim
        and (root.Position-target.Position).Magnitude<=8
        and not (self.movement and self.movement.owner~="combat" and self.movement.priority>10)
    local queued=self.decoyFor
    local matching=queued and queued.target==target and queued.level==d.level.current
    local decoyActive=active["8"]~=nil or character:FindFirstChild("Decoy")~=nil
        or matching and (tonumber(cd["8"]) or 0)>queued.before
    local plan
    if canFight then
        local timer=M.GetBossTimer(d);local mana,maxMana=value(target,"Mana"),value(target,"MaxMana")
        if type(maxMana)=="number" and maxMana>0 then timer=math.min(timer,maxMana) end
        if type(mana)=="number" then timer=math.max(0,timer-math.max(0,mana)) end
        local available={};for id in pairs(M.AbilitiesData) do available[id]=ready(id) end
        plan=P.bossPlan(d,s,self:gear(d),hp,timer,self.settings.farm,available,decoyActive)
        local normal=plan.normalSeconds>1e8 and "very long" or string.format("%.1fs",plan.normalSeconds)
        self.abilityNote="Boss normal kill "..normal.." / window "..string.format("%.1fs",plan.window).."; "..plan.reason
    else self.abilityNote="Saving combat skills for a hard farm boss" end
    -- Complete a still-valid Decoy/combat pair before the economy rotation.
    if queued then
        self.decoyFor=nil
        if matching and decoyActive and plan and plan.burst then send(plan.burst.first);return end
    end
    if ready("6") then self.abilityNote="Exploit is ready; permanent damage is not held for bosses";send("6");return end
    if plan and plan.burst then
        if plan.burst.useDecoy then
            local before=tonumber(cd["8"]) or 0
            if send("8") then self.decoyFor={target=target,level=d.level.current,before=before} end
        else send(plan.burst.first) end
        return
    end
    for _,id in ipairs({"4","5"}) do if ready(id) then
        self.abilityNote="Economy ability ready; combat cooldowns remain reserved";send(id);return
    end end
end
local bootstrap=task.spawn(function()
    local ok,err=pcall(function()
    local deadline=os.clock()+20
    repeat Events=RS:FindFirstChild("Events"); if Events and RS:FindFirstChild("Modules") and RS:FindFirstChild("Settings") then break end; task.wait(0.1) until not A.alive or os.clock()>deadline
    if not A.alive then return end
    assert(Events and Events:FindFirstChild("Data"),"Events.Data missing after 20 seconds")
    M={}
    for _,name in ipairs({"BigNum","GetFarmHeroPos","GetVitalityDiscount","GetChickensRequired","GetBossHealth","GetBossTimer"}) do M[name]=require(RS.Modules:FindFirstChild(name) or error("Missing module "..name)) end
    for _,name in ipairs({"HeroesData","EggsData","Eggs2Data","Eggs3Data","AchievementsData","AbilitiesData","TrophyBonus","WeaponCooldown","BoxData"}) do M[name]=require(RS.Settings:FindFirstChild(name) or error("Missing catalog "..name)) end
    M.DataHandler=require(RS.Modules.DataHandler); P=Core.new(M)
    A:connect(Events.Data.OnClientEvent,function(d,s,tags)
        if type(d)=="table" and type(s)=="table" then
            -- Server payloads are authoritative without comparing their object
            -- identity with the module cache. Keep data/session from one event.
            A.data,A.session=d,s;A.lastDataAt=os.clock();A.receivedDataEvent=true;A.dataSequence=(A.dataSequence or 0)+1
        end
        local families={upgrade="heroes"}
        for _,tag in pairs(type(tags)=="table" and tags or {}) do
            local family=families[tag]
            if family and ((A.quietUntil or {})[family] or 0)>os.clock() then A.quietUntil[family]=os.clock()+2;A:bindMenus() end
        end
    end)
    A:connect(player.CharacterAdded,function() A:setDiamondPriority(false);A:cancelMovement();A.claimAttempt=nil;A.fight=nil;A.collecting={};A.lastAbility=nil;A.decoyFor=nil;A.next.attack=0 end)
    local turing=Events:FindFirstChild("Turing")
    if turing then A:connect(turing.OnClientEvent,function() A.turing=true;A.playSequence=(A.playSequence or 0)+1 end) end
    local boxes=Events:FindFirstChild("Boxes")
    if boxes then A:connect(boxes.OnClientEvent,function(verb)
        if verb=="Open" then A.boxReceipts=(A.boxReceipts or 0)+1 end
    end) end
    local messages=Events:FindFirstChild("Messages")
    if messages then A:connect(messages.OnClientEvent,function(verb,...) A:eventMessage(verb,...) end) end
    if not A.receivedDataEvent then A.data,A.session=M.DataHandler.Get("data"),M.DataHandler.Get("session") end
    A.loadedAt=os.clock()
    A.ready=true;A:refreshRunning();A.lastFarmProgress=os.clock();A:log("Native catalogs loaded; teleport-only control ready");A.status=A.uiFailed and "Menu startup failed; see on-screen error" or "Ready"
    end)
    if not ok and A.alive then A.status="Native startup failed; see Details";A:log(tostring(err)) end
end)
table.insert(A.tasks,bootstrap)
local function guarded(name,fn)
    local ok,err=pcall(fn)
    if not ok and A:due("error-"..name,5) then A:log(name..": "..tostring(err)) end
end
A:connect(Run.Heartbeat,function()
    if A.saveAt and os.clock()>=A.saveAt then A:save() end
    if A.eventHistoryDirty and os.clock()>=A.eventHistoryDirty then A:flushEventHistory() end
    if A.ready and A:due("health",300) then guarded("health",function() A:sampleHealth() end) end
    if A.ready and A:due("sync",1) then
        -- The cache bootstraps an already-running client until the first Data
        -- event. Afterwards polling must not overwrite a newer event pair.
        if not A.receivedDataEvent then
            local d,s=M.DataHandler.Get("data"),M.DataHandler.Get("session")
            if type(d)=="table" and type(s)=="table" then A.data,A.session=d,s end
        end
        A:scan();A:bindMenus()
    end
    local d,s=A.data,A.session
    if A.ready and d and s then
        A:observeRun(d)
        A.ledger:poll(d,s)
        A:observeReset(d)
        if A.autoResetState then
            local settled,note=A:resetSettlement(d);A.progressionSettling=not settled
            if not settled then A.progressionNote=note;A:cancelMovement() end
        else A.progressionSettling=false end
        if (A.running or A.startupClaim) and A.uiReady then
            local gui=player:FindFirstChildOfClass("PlayerGui"); local t=gui and gui:FindFirstChild("Turing"); local panel=t and t:FindFirstChild("Turing")
            A.turing=panel and panel.Visible or false
            if not A.turing and (s.loaded or d.username==player.DisplayName or A.lastDataAt) then
                guarded("event invitation",function() A:eventJoin() end)
            end
            if A.turing then
                A.status="Confirming the game's Play prompt"
                if panel:FindFirstChild("Play") and A.playSent~=(A.playSequence or 0) then
                    A.playSent=A.playSequence or 0
                    guarded("Play",function() A:remote("Turing",NATIVE_PLAY_TOKEN);panel.Visible=false end)
                end
            elseif not (s.loaded or d.username==player.DisplayName or A.lastDataAt) then A.status="Waiting for authoritative player data"
            elseif A.progressionSettling then A.status=A.progressionNote
            else
                local inEvent=player:FindFirstChild("Alien")~=nil
                local joining=A.eventJoinPending~=nil
                if inEvent and A.settings.boss and not A.ledger.pending.reset then guarded("event combat",function() A:combat(d,s) end) end
                if not joining and not inEvent and A.startupClaim and A:due("claim",0.1) then guarded("claim",function() A:claimFarm() end) end
                if not A.startupClaim then
                -- Reconcile the small owned-farm folder first, before any farm action.
                if not joining and not inEvent then
                if A.settings.diamonds and not A.ledger.pending.reset then guarded("diamonds",function() A:diamonds(d,s) end) end
                if (A.settings.autoRetire or A.settings.autoRebirth) and A:due("auto progression",1) then guarded("auto progression",function() A:autoProgression(d,s) end) end
                if A.settings.progress and not A.progressionIntent and A:due("progress",0.15) then guarded("progress",function() A:progress(d,s) end) end
                if not A.ledger.pending.reset then
                    if A.settings.farm and A:due("pickup",0.1) then guarded("pickup",function() A:pickup(d,s) end) end
                    if A.settings.farm or A.settings.boss then guarded("combat",function() A:combat(d,s) end) end
                    if A.settings.quest and not A.diamondPriority and A:due("quest",0.2) then guarded("quest",function() A:quest(d) end) end
                end
                end
                if not A.ledger.pending.reset then
                    if not joining and A.settings.abilities and A:due("abilities",0.25) then guarded("abilities",function() A:abilities(d,s) end) end
                    if not A.progressionIntent then
                        if not joining and not inEvent and A.settings.hireHeroes and A:due("hiring",0.05) then guarded("hiring",function() A:hireHeroes(d,s) end) end
                        if A.settings.equipment and A:due("gear",1) then guarded("gear",function() A:equip(d,s) end) end
                        if A.settings.heroes and A:due("heroes",0.25) then guarded("heroes",function() A:buyHeroes(d,s) end) end
                        if A.settings.rewards and A:due("rewards",1) then guarded("rewards",function() A:rewards(d) end) end
                        if A.settings.trophyBoxes and A:due("trophy boxes",0.5) then guarded("trophy boxes",function() A:buyTrophyBox(d,s) end) end
                        if A.settings.boxes and A:due("boxes",0.5) then guarded("boxes",function() A:openBoxes(d) end) end
                        if A:due("egg spending",0.25) then guarded("egg spending",function()
                            if A.settings.goldEggs then A:spendEggs(d,s,"gold") end
                            if A.settings.blackEggs then A:spendEggs(d,s,"black") end
                        end) end
                    end
                end
                if A.ledger.uncertain.stage==tostring(d.level.current) then A.status="Stage change unconfirmed; see Details" end
                end
            end
        end
        if A.progressionWatch and (not A.uiReady or not A.settings.autoRetire and not A.settings.autoRebirth or A.diamondPriority or A.eventJoinPending or player:FindFirstChild("Alien") or A.startupClaim or A:manualMenuOpen()) then
            A.progressionWatch.pausedAt=A.progressionWatch.pausedAt or os.clock()
        end
    end
    if A.movement and os.clock()-A.movement.updated>0.5 then A:cancelMovement() end

end)
table.insert(A.tasks,task.delay(21,function()
    if A.alive and not A.ready then A.status="Native startup failed or timed out; see Details / reexecute"; A:log("Startup did not finish; no gameplay dispatched") end
end))
return A
