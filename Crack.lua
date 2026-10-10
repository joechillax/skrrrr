if game.PlaceId ~= 137477934962022 and game.PlaceId ~= 104087083666671 then return end
game:GetService("GuiService"):SetGameplayPausedNotificationEnabled(false)
-- Crack the Egg: lobby + round progression, v17.
-- Source contracts: lobby 137477934962022 and round 104087083666671.
-- Save this exact file as CrackTheEgg.lua in the executor workspace for teleport resume.
-- Lobby walks; round travel uses cancellable tweens at sprint-equivalent speed.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Http = game:GetService("HttpService")
local Input = game:GetService("UserInputService")
local player = Players.LocalPlayer
assert(player, "CrackTheEgg must run on the client")
local env = (type(getgenv) == "function" and getgenv()) or _G
local KEY = "__CrackTheEgg_Lobby_v1"
local shared = env[KEY] or {calls = {}, modules = {}, goals = {}}
shared.goals = shared.goals or {}
shared.retired = shared.retired or {}
env[KEY] = shared
local function retryTeardown()
    for i = #shared.retired, 1, -1 do
        local retired = shared.retired[i]
        pcall(retired.Unload, retired, true)
        if #retired.connections == 0 and #retired.objects == 0 and not retired.cleanupPending then table.remove(shared.retired, i) end
    end
end
retryTeardown()
if shared.owner then
    local previous = shared.owner
    local ok, err = pcall(previous.Unload, previous, true)
    if not ok then warn("[CrackEgg] Previous cleanup: " .. tostring(err)) end
    if #previous.connections > 0 or #previous.objects > 0 or previous.cleanupPending then
        if not table.find(shared.retired, previous) then table.insert(shared.retired, previous) end
    end
end

local app = {alive = true, running = false, connections = {}, objects = {}, notes = {},
    status = {}, blocks = {}, failures = {}, cooldowns = {}, goals = shared.goals, retries = {},
    settings = {upgrades = true, reserve = 0, upgradeFocus = "Balanced",
        hatch = false, eggPolicy = "Finish nearest", craft = "Off", resume = false,
        farm = true, runUpgrades = true, chests = true, allowSingleChoice = false, sell = true, repeatRuns = true,
        difficulty = "Easy", partySize = 1, mineTravel = "Walk", collectTravel = "Walk",
        sellTravel = "Walk", chestTravel = "Walk", queueTravel = "Walk", shopTravel = "Walk"},
    refreshAt = 0, perks = nil, saveAt = nil, ui = {}, moduleErrors = {}}
shared.owner = app

-- Attempt every owned cleanup independently. A failed release remains retryable,
-- including when all listeners and UI have already been removed.
function app:cleanupOwned()
    local complete = true
    for _, name in ipairs({"releaseIdle", "release", "restoreSpeed", "restoreFlight"}) do
        if self[name] then
            local ok, result = pcall(self[name], self)
            if not ok or result == false then complete = false end
        end
    end
    self.cleanupPending = not complete
    return complete
end

-- Install teardown before creating listeners, tasks or UI. Failed steps stay retryable.
function app:Unload(replacing)
    self.running, self.alive = false, false
    if not replacing then
        self.settings.resume = false
        if self.save then pcall(self.save, self) end
    end
    self:cleanupOwned()
    for i = #self.connections, 1, -1 do
        local ok = pcall(function() self.connections[i]:Disconnect() end)
        if ok then table.remove(self.connections, i) end
    end
    for i = #self.objects, 1, -1 do
        local ok = pcall(function() self.objects[i]:Destroy() end)
        if ok then table.remove(self.objects, i)
        else pcall(function() if self.objects[i]:IsA("ScreenGui") then self.objects[i].Enabled = false end end) end
    end
    -- InvokeServer cannot retract a dispatched action. Receipts remain bounded in
    -- shared.calls; their eventual results are reconciled by the next instance.
    if shared.owner == self and #self.connections == 0 and #self.objects == 0 and not self.cleanupPending then
        shared.owner = nil
    end
    if (#self.connections > 0 or #self.objects > 0 or self.cleanupPending) and not table.find(shared.retired, self) then
        table.insert(shared.retired, self)
    end
end

function app:note(message)
    table.insert(self.notes, os.date("%H:%M:%S") .. " " .. tostring(message))
    if #self.notes > 60 then table.remove(self.notes, 1) end
end

local function connect(signal, callback)
    local c = signal:Connect(function(...)
        if app.alive and shared.owner == app then callback(...) end
    end)
    table.insert(app.connections, c)
    return c
end

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function choice(value, options, fallback)
    return table.find(options, value) and value or fallback
end

local policies = {"Keep equipped", "Finish nearest", "Highest tier"}
local focuses = {"Balanced", "Gems", "Shells", "Range"}

local difficulties = {"Easy", "Medium", "Hard"}
local savePath = "CrackTheEgg_Lobby_v1_" .. tostring(player.UserId) .. ".json"

local function decode(raw)
    if type(raw) ~= "string" then return nil end
    local ok, data = pcall(Http.JSONDecode, Http, raw)
    return ok and type(data) == "table" and data or nil
end

if type(readfile) == "function" then
    local ok, raw = pcall(readfile, savePath)
    local data = ok and decode(raw)
    if data and data.version == 1 and data.user == player.UserId then
        local s = data.settings
        if type(s) == "table" then
            for _, k in ipairs({"upgrades", "hatch", "resume", "farm", "runUpgrades", "chests", "allowSingleChoice", "sell", "repeatRuns"}) do
                if type(s[k]) == "boolean" then app.settings[k] = s[k] end
            end
            app.settings.reserve = finite(s.reserve) and math.clamp(math.floor(s.reserve), 0, 1e9) or 0
            app.settings.eggPolicy = choice(s.eggPolicy, policies, "Finish nearest")
            app.settings.upgradeFocus = choice(s.upgradeFocus, focuses, "Balanced")
            if type(s.craft) == "string" then app.settings.craft = s.craft end
            app.settings.difficulty = choice(s.difficulty, difficulties, "Easy")
            app.settings.partySize = finite(s.partySize) and math.clamp(math.floor(s.partySize), 1, 4) or 1
        end
    end
end

-- The user's correction supersedes movement policies and optional choice modes
-- saved by older versions. Keep only useful user selections in the compact UI.
for _, lane in ipairs({"mine", "collect", "sell", "chest", "shop"}) do app.settings[lane .. "Travel"] = "Tween" end
app.settings.queueTravel = "Walk"
app.settings.farm, app.settings.runUpgrades, app.settings.chests, app.settings.sell = true, true, true, true
app.settings.allowSingleChoice, app.settings.craft, app.settings.partySize = false, "Off", 1
-- New accounts default to AFK runs. A saved OFF selection stays OFF.

function app:save()
    self.saveAt = nil
    if type(writefile) ~= "function" or type(readfile) ~= "function" then
        self.saveStatus = "Settings: memory only (file APIs unavailable)"
        return false
    end
    local ok, result = pcall(function()
        local text = Http:JSONEncode({version = 1, user = player.UserId, settings = self.settings})
        writefile(savePath, text)
        return readfile(savePath) == text
    end)
    self.saveStatus = ok and result and "Settings saved and read back" or "Settings save/readback failed"
    if not (ok and result) then self:note(self.saveStatus) end
    return ok and result
end

local function changed()
    app.saveAt = os.clock() + 0.5
    app.refreshAt = 0
end

local function folderAt(path)
    local parent = RS
    for name in string.gmatch(path or "", "[^/]+") do
        parent = parent and parent:FindFirstChild(name)
    end
    return parent
end

local function remote(folder, name)
    local parent = folderAt(folder)
    local object = parent and parent:FindFirstChild(name)
    return object and object:IsA("RemoteFunction") and object or nil
end

local function module(folder, name)
    local parent = folderAt(folder)
    local object = parent and parent:FindFirstChild(name)
    if not object or not object:IsA("ModuleScript") then return nil, folder .. "." .. name .. " missing" end
    local key = folder .. "." .. name
    local record = shared.modules[key]
    if record and record.pending then
        return nil, key .. (record.object == object and " loading" or " replacement waiting for previous module load")
    end
    if record and record.object == object then
        if record.value then return record.value end
        if os.clock() < record.retry then return nil, key .. " failed: " .. tostring(record.err) end
    end
    record = {object = object, pending = true, retry = os.clock() + 10}
    shared.modules[key] = record
    task.spawn(function()
        local ok, result = pcall(require, object)
        record.pending = false
        if ok and type(result) == "table" then record.value = result else record.err = result end
    end)
    return nil, key .. " loading"
end

-- One outstanding invocation per lane. Timeouts retain ownership: never launch
-- replacement workers while a hung InvokeServer remains unresolved.
local function dispatch(lane, object, action, arguments, metadata)
    if shared.calls[lane] or not app.alive or not app.running then return false end
    local record = {owner = app, object = object, action = action, arguments = arguments,
        meta = metadata or {}, started = os.clock(), done = false}
    shared.calls[lane] = record
    if lane == "eggs" and (action == "Hatch" or action == "Craft") then
        shared.presentation = {action = action, at = os.clock()}
    end
    task.spawn(function()
        record.ok, record.result = pcall(object.InvokeServer, object, action, table.unpack(arguments))
        record.done = true -- Receipt only: no old-instance callbacks or lock release.
    end)
    return true
end

local function fail(key, fingerprint, reason)
    local item = app.failures[key]
    local count = item and item.fingerprint == fingerprint and item.count + 1 or 1
    app.failures[key] = {fingerprint = fingerprint, count = count, reason = reason,
        rejected = reason == "MiningResult rejected" or reason == "No MiningResult or target progress"
            or item and item.fingerprint == fingerprint and item.rejected == true}
    app.cooldowns[key] = os.clock() + math.min(30, 2 ^ count)
    if count >= 3 then app.blocks[key] = {fingerprint = fingerprint, reason = reason} end
    app:note(key .. ": " .. tostring(reason))
end

local function eligible(key, fingerprint)
    local block = app.blocks[key]
    if block and block.fingerprint ~= fingerprint then
        app.blocks[key], app.failures[key], app.cooldowns[key] = nil, nil, nil
        block = nil
    end
    if block then return false, block.reason end
    if (app.cooldowns[key] or 0) > os.clock() then return false, "retry backoff" end
    return true
end

local function success(key)
    app.failures[key], app.blocks[key], app.cooldowns[key] = nil, nil, nil
end

local function protected(egg)
    -- No lock schema was present in the export. Honor conventional flags if the
    -- live game supplies them; unrecognized inventory is never force-modified.
    return egg.Locked == true or egg.Favorited == true or egg.Favourite == true
        or egg.Favorite == true or egg.Protected == true
end

local function inventory()
    local eggs = decode(player:GetAttribute("EggStateJson"))
    local ingredients = decode(player:GetAttribute("IngredientsJson"))
    local crafted = decode(player:GetAttribute("CraftedJson"))
    if not eggs or type(eggs.Eggs) ~= "table" then return nil end
    local owned, byId = {}, {}
    for k, v in pairs(crafted or {}) do
        if type(v) == "string" then owned[v] = true
        elseif type(k) == "string" and v == true then owned[k] = true end
    end
    for _, egg in ipairs(eggs.Eggs) do
        if type(egg) == "table" and type(egg.Id) == "string" and egg.Id ~= "" then byId[egg.Id] = egg end
    end
    return {eggs = eggs.Eggs, byId = byId,
        equipped = type(eggs.Equipped) == "string" and eggs.Equipped or player:GetAttribute("EquippedEggId"),
        have = ingredients, owned = owned, craftedLoaded = crafted ~= nil,
        craftedEquipped = player:GetAttribute("CraftedClassId")}
end

local function normalizePerks(state, catalog)
    if type(state) ~= "table" or not finite(state.Gems) or type(state.Levels) ~= "table" then return nil end
    local levels = {}
    for _, id in ipairs({"BucketSize", "BucketRange", "GemValue", "ShellValue"}) do
        local def, level = catalog.ById[id], state.Levels[id]
        if type(def) ~= "table" or type(def.Prices) ~= "table" or type(def.Bonuses) ~= "table"
            or not finite(level) or level < 0 or level % 1 ~= 0 or level > #def.Prices then return nil end
        levels[id] = level
    end
    return {Gems = state.Gems, Levels = levels}
end

local function chooseUpgrade(state, catalog, settings)
    local best, bestScore
    local weights = {BucketRange = 1, GemValue = 1, ShellValue = 1}
    if settings.upgradeFocus == "Gems" then weights.GemValue = 4
    elseif settings.upgradeFocus == "Shells" then weights.ShellValue = 4
    elseif settings.upgradeFocus == "Range" then weights.BucketRange = 4 end
    for _, id in ipairs({"BucketRange", "GemValue", "ShellValue"}) do
        local level = state.Levels[id]
        local def = catalog.ById[id]
        local price, bonus = def.Prices[level + 1], def.Bonuses[level + 1]
        local fingerprint = tostring(level) .. ":" .. tostring(price) .. ":" .. tostring(settings.reserve)
        if finite(price) and price > 0 and finite(bonus) and price <= state.Gems - settings.reserve
            and eligible("buy:" .. id, fingerprint) then
            local current = level == 0 and 0 or def.Bonuses[level]
            if finite(current) then
                local score = ((100 + bonus) / (100 + current) - 1) * weights[id] / price
                if score > 0 and (not bestScore or score > bestScore) then
                    bestScore = score
                    best = {id = id, level = level, price = price, fingerprint = fingerprint}
                end
            end
        end
    end
    return best
end

local function chooseEgg(inv, rules, policy, now)
    local best, remaining
    for _, egg in ipairs(inv.eggs) do
        if type(egg) == "table" and type(egg.Id) == "string" and inv.byId[egg.Id] == egg
            and not protected(egg) and (egg.Ready == false or egg.Ready == nil) and finite(egg.Tier)
            and finite(egg.Stage) and finite(egg.Fed) and (tonumber(egg.FullUntil) or 0) <= now then
            local room = rules.Room(egg)
            if finite(room) and room > 0 then
                local better = not best
                if best and policy == "Highest tier" then
                    better = egg.Tier > best.Tier or (egg.Tier == best.Tier and room < remaining)
                elseif best then
                    better = room < remaining or (room == remaining and egg.Tier > best.Tier)
                end
                if better then best, remaining = egg, room end
            end
        end
    end
    return best
end

local function status(lane, message) app.status[lane] = message end

local function readReceipts(catalog)
    for lane, record in pairs(shared.calls) do
        if record.done then
            shared.calls[lane] = nil
            if record.owner ~= app or not app.running then
                app.perks = nil
                app.refreshAt = 0
                if record.action ~= "State" then
                    app.goals[lane] = {action = record.action, meta = record.meta, deadline = os.clock() + 8,
                        uncertain = record.action == "Hatch" or record.action == "Craft"}
                end
                app:note("Reconcile previous " .. record.action .. " receipt")
            elseif lane == "perks" then
                local result = record.result
                local nextState = record.ok and type(result) == "table" and catalog
                    and normalizePerks(result.State, catalog)
                app.perks = nextState or nil
                app.refreshAt = os.clock() + (nextState and 15 or 3)
                if record.action == "Buy" then
                    app.goals.perks = {action = "Buy", meta = record.meta, deadline = os.clock() + 8}
                elseif not nextState then
                    fail("perk-state", "state", record.ok and "Invalid State schema" or tostring(result))
                else success("perk-state") end
                if type(result) == "table" and result.Ok == false then app:note(result.Message or "Upgrade rejected") end
            else
                -- Reconcile the affected inventory/ownership, even after a refusal
                -- or connection exception. Never infer consumption from wallet deltas.
                local refused = record.ok and (record.result == false or type(record.result) == "table"
                    and (record.result.ok == false or record.result.Ok == false))
                app.goals.eggs = {action = record.action, meta = record.meta, deadline = os.clock() + 8,
                    uncertain = not refused}
                if not record.ok then app:note("Egg request interrupted: " .. tostring(record.result))
                elseif type(record.result) == "table" and (record.result.ok == false or record.result.Ok == false) then
                    app:note(record.result.message or record.result.reason or record.result.Reason or "Egg request refused")
                end
            end
        elseif os.clock() - record.started > 10 then
            status(lane, record.action .. " awaiting server; retries suspended")
        else status(lane, record.action .. " pending") end
    end
end

local function reconcile(lane, inv)
    local goal = app.goals[lane]
    if not goal then return false end
    local m, proved = goal.meta, false
    local key = m.key or goal.action
    if goal.action == "Buy" then
        proved = app.perks and app.perks.Levels[m.id] and app.perks.Levels[m.id] > m.level
        if not app.perks then app.refreshAt = math.min(app.refreshAt, os.clock()) end
    elseif inv then
        if goal.action == "Hatch" then proved = inv.byId[m.id] == nil
        elseif goal.action == "Equip" then proved = inv.equipped == m.id
        elseif goal.action == "Craft" then proved = inv.craftedLoaded and inv.owned[m.id] == true
        elseif goal.action == "EquipCrafted" then proved = inv.craftedEquipped == m.id end
    end
    if proved then
        success(key)
        app.goals[lane] = nil
        app:note("Confirmed " .. goal.action .. " " .. tostring(m.id))
        return false
    end
    if os.clock() >= goal.deadline then
        -- Spending requires a fresh authoritative State before retry. A missing
        -- State holds the goal; an interrupted request never becomes a new buy.
        if goal.action == "Buy" and not app.perks then
            status(lane, "Purchase outcome unknown; waiting for State")
            return true
        end
        if lane == "eggs" and not inv then
            status(lane, "Inventory unavailable; outcome unreconciled")
            return true
        end
        if lane == "eggs" and goal.uncertain and (goal.action == "Hatch" or goal.action == "Craft") then
            status(lane, "Consumption outcome unresolved; retries suspended")
            return true
        end
        fail(key, m.fingerprint, "No confirmed " .. goal.action .. " progress")
        app.goals[lane] = nil
        return false
    end
    status(lane, "Confirming " .. goal.action)
    return true
end

local function stepPerks(catalog)
    if not app.settings.upgrades and not app.goals.perks then status("perks", "Upgrades off") return end
    if shared.calls.perks then return end
    if not catalog or type(catalog.ById) ~= "table" then status("perks", "Upgrade catalog loading/unavailable") return end
    local object = remote("EggPlayerPerks", "Request")
    if not object then status("perks", "EggPlayerPerks.Request missing") return end
    if not app.perks or os.clock() >= app.refreshAt then
        local ready, reason = eligible("perk-state", "state")
        if ready then dispatch("perks", object, "State", {})
        else status("perks", "State blocked: " .. tostring(reason)) end
        return
    end
    if reconcile("perks") then return end
    if not app.settings.upgrades then status("perks", "Upgrades off") return end
    local target = chooseUpgrade(app.perks, catalog, app.settings)
    if not target then status("perks", "Maxed, reserved, unaffordable or backed off") return end
    dispatch("perks", object, "Buy", {target.id, target.level},
        {id = target.id, level = target.level, key = "buy:" .. target.id, fingerprint = target.fingerprint})
    status("perks", "Buying " .. target.id .. " for " .. target.price .. " gems")
end

local function stepEggs(rules, crafted, inv)
    if shared.calls.eggs then return end
    if not inv then status("eggs", "Egg inventory loading/unavailable") return end
    if reconcile("eggs", inv) then return end
    local object = remote("EggHatchery", "Request")
    if not object then status("eggs", "EggHatchery.Request missing") return end
    local now = workspace:GetServerTimeNow()
    if app.settings.hatch then
        local readyEgg
        for _, egg in ipairs(inv.eggs) do
            if type(egg) == "table" and inv.byId[egg.Id] == egg and egg.Ready == true and not protected(egg)
                and eligible("hatch:" .. egg.Id, "ready:" .. egg.Id) then
                if not readyEgg or (tonumber(egg.Tier) or 0) > (tonumber(readyEgg.Tier) or 0) then readyEgg = egg end
            end
        end
        if readyEgg then
            dispatch("eggs", object, "Hatch", {readyEgg.Id},
                {id = readyEgg.Id, key = "hatch:" .. readyEgg.Id, fingerprint = "ready:" .. readyEgg.Id})
            status("eggs", "Hatching ready egg")
            return
        end
    end
    local id = app.settings.craft
    local def = crafted and type(crafted.ById) == "table" and crafted.ById[id]
    if id ~= "Off" and not crafted then status("eggs", "Craft catalog loading/unavailable") return end
    if id ~= "Off" and not def then status("eggs", "Unknown selected recipe; choose a current perk") return end
    if def and inv.have and inv.craftedLoaded then
        local can = inv.owned[id] ~= true and type(def.Recipe) == "table" and next(def.Recipe) ~= nil
        local parts = {}
        for ingredient, count in pairs(def.Recipe or {}) do
            local have = inv.have[ingredient] or 0
            if not finite(count) or count <= 0 or not finite(have) then can = false
            elseif have < count then can = false end
            table.insert(parts, tostring(ingredient) .. "=" .. tostring(have))
        end
        table.sort(parts)
        local fingerprint = table.concat(parts, ";") .. ":" .. tostring(inv.owned[id])
        local key = "craft:" .. id
        if can and eligible(key, fingerprint) then
            dispatch("eggs", object, "Craft", {id}, {id = id, key = key, fingerprint = fingerprint})
            status("eggs", "Crafting selected " .. def.Name)
            return
        end
        key = "equip-crafted:" .. id
        fingerprint = tostring(inv.craftedEquipped) .. ":" .. id
        if inv.owned[id] and inv.craftedEquipped ~= id and eligible(key, fingerprint) then
            dispatch("eggs", object, "EquipCrafted", {id}, {id = id, key = key, fingerprint = fingerprint})
            status("eggs", "Equipping selected " .. def.Name)
            return
        end
    end
    if app.settings.eggPolicy ~= "Keep equipped" then
        if not rules or type(rules.Room) ~= "function" then status("eggs", "Egg growth rules unavailable") return end
        local egg = chooseEgg(inv, rules, app.settings.eggPolicy, now)
        if egg and inv.equipped ~= egg.Id then
            local key, fingerprint = "equip:" .. egg.Id, tostring(inv.equipped) .. ":" .. egg.Id
            if eligible(key, fingerprint) then
                dispatch("eggs", object, "Equip", {egg.Id}, {id = egg.Id, key = key, fingerprint = fingerprint})
                status("eggs", "Equipping growth egg T" .. tostring(egg.Tier))
                return
            end
        end
    end
    local current = inv.byId[inv.equipped]
    local message = current and ("Equipped T" .. tostring(current.Tier) .. "; growth requires round activity")
        or "No eligible growth egg"
    if id ~= "Off" and not inv.owned[id] then message ..= "; selected craft waiting for materials" end
    for _, block in pairs(app.blocks) do message = "Waiting: " .. tostring(block.reason) break end
    status("eggs", message)
end

local busyAttributes = {"DoorCutscene", "OnboardingOpen", "ClassMenuOpen", "ClassTransitionActive",
    "IntroCutscene", "WinCutscene", "PurchasePromptOpen", "AdminFreecam", "EggHatchOpen",
    "EggCraftOpen", "EggCardOpen", "EggStorageOpen", "EggRevealPending", "FirstWinPreviewPending"}

local function gate()
    if app.teleporting then return "Teleport in progress" end
    if game.PlaceId ~= 137477934962022 and game.PlaceId ~= 104087083666671 then
        return "Unsupported place " .. tostring(game.PlaceId)
    end
    if player:GetAttribute("ProfileReady") ~= true then return "Waiting for ProfileReady" end
    if player:GetAttribute("LoadingScreenFinished") ~= true then return "Waiting for loading screen" end
    if game:GetService("GuiService").MenuIsOpen then return "Roblox menu open" end
    for _, name in ipairs(busyAttributes) do
        if player:GetAttribute(name) == true then return "Waiting for " .. name end
    end
    if game.PlaceId == 104087083666671 then
        for _, name in ipairs({"SlimeCutscene", "BossCutscene", "UpgradeTreeOpen", "DeathMenuOpen", "SessionModalOpen"}) do
            if player:GetAttribute(name) == true then return "Waiting for " .. name end
        end
    end
    if (tonumber(player:GetAttribute("EggRevealBusyUntil")) or 0) > workspace:GetServerTimeNow() then
        return "Waiting for egg reveal"
    end
    local queue = player:GetAttribute("Queue")
    if player:GetAttribute("InQueue") == true or (queue ~= nil and queue ~= false and queue ~= "" and queue ~= 0) then
        return "In queue; progression paused"
    end
    return nil
end

function app:lobbyPreparation()
    local reason
    local inv = inventory()
    if shared.calls.eggs or self.goals.eggs then reason = "Settling egg request"
    elseif not inv then reason = "Waiting for egg inventory"
    else
        if self.settings.hatch then
            for _, egg in ipairs(inv.eggs) do
                if type(egg) == "table" and inv.byId[egg.Id] == egg and egg.Ready == true and not protected(egg)
                    and eligible("hatch:" .. egg.Id, "ready:" .. egg.Id) then reason = "Hatching ready eggs before queue" break end
            end
        end
        if not reason and self.settings.eggPolicy ~= "Keep equipped" then
            local rules = module("EggHatchery", "Rules")
            if not rules or type(rules.Room) ~= "function" then reason = "Loading growth rules before queue"
            else
                local egg = chooseEgg(inv, rules, self.settings.eggPolicy, workspace:GetServerTimeNow())
                if egg and inv.equipped ~= egg.Id and eligible("equip:" .. egg.Id, tostring(inv.equipped) .. ":" .. egg.Id) then
                    reason = "Equipping growth egg before queue"
                end
            end
        end
    end
    if not reason and self.settings.upgrades then
        local catalog = module("EggPlayerPerks", "Catalog")
        if shared.calls.perks or self.goals.perks then reason = "Settling lobby upgrade"
        elseif not self.perks or not catalog then reason = "Loading lobby upgrade State"
        elseif chooseUpgrade(self.perks, catalog, self.settings) then reason = "Buying useful lobby upgrades before queue" end
    end
    -- A hung inventory/spending invocation must not hold independent round play
    -- forever. Its unresolved outcome stays owned; never resubmit consumption.
    self.preparationAt = self.preparationAt or os.clock()
    if reason and os.clock() - self.preparationAt < 30 then return reason end
    if reason and not self.preparationBypass then
        self.preparationBypass = true
        self:note(reason .. "; preparation deadline reached, independent queue continues")
    end
    return nil
end

function app:Stop()
    self.running = false
    self.watch = nil
    self.settings.resume = false
    pcall(self.save, self)
    self:cleanupOwned()
    self:note("Stopped; dispatched requests may still settle")
end

function app:Start()
    if self.cleanupPending and not self:cleanupOwned() then
        self:note("Start waiting for owned input/movement cleanup")
        return
    end
    self.running = true
    if self.settings.repeatRuns then self.settings.resume = true self.saveAt = os.clock() + 0.5 end
    if self.settings.repeatRuns and self.queueResume then self:queueResume() end
    self.perks = nil
    self.refreshAt = 0
    -- Retain unresolved outcomes and target failure blocks across Stop/Start.
    self:note("Started progression")
end

-- Round RemoteEvents have their own receipts and resource owners. They never
-- share the yielding lobby invocation lanes.
do
    local state = shared.round or {pending = {}, ranks = nil, serial = 1000000,
        chests = {}, offers = {}, done = {}, targets = {}, parts = {}, leases = {}, stats = {hits = 0, collected = 0, chests = 0}}
    shared.round = state
    state.targetList = state.targetList or {}
    state.targetIds = state.targetIds or setmetatable({}, {__mode = "k"})
    state.targetSerial = state.targetSerial or 0
    local function targetId(obj)
        if not state.targetIds[obj] then
            state.targetSerial += 1
            state.targetIds[obj] = tostring(obj) .. "#" .. tostring(state.targetSerial)
        end
        return state.targetIds[obj]
    end
    local refs, installed, pathJob = {}, {}, shared.pathJob
    local function travelPolicy()
        return game.PlaceId == 104087083666671 and "Tween" or "Walk"
    end
    local function movementFingerprint(target, lane)
        local cached = state.targets[target]
        return targetId(target) .. ":" .. travelPolicy() .. ":" .. tostring(type(cached) == "table" and cached.geometry or "")
    end
    local function event(folder, name)
        local parent = folderAt(folder)
        local obj = parent and parent:FindFirstChild(name)
        return obj and obj:IsA("RemoteEvent") and obj or nil
    end
    local function send(obj, action, ...)
        if not obj or not app.running then return false end
        local ok, err = pcall(obj.FireServer, obj, action, ...)
        if not ok then app:note(action .. ": " .. tostring(err)) end
        return ok
    end
    local function character()
        local c = player.Character
        local root = c and c:FindFirstChild("HumanoidRootPart")
        local head = c and c:FindFirstChild("Head")
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        if not root or not head or not hum or hum.Health <= 0 then return nil end
        return c, root, head, hum
    end
    local function flightGround(position, target, config)
        local ground = config and config.EggGroundY or 0
        local params = RaycastParams.new()
        params.FilterType, params.RespectCanCollide = Enum.RaycastFilterType.Exclude, true
        local exclude = {player.Character}
        local egg = state.lab and state.lab:FindFirstChild("Egg")
        if egg then table.insert(exclude, egg) end
        if target and target ~= egg then table.insert(exclude, target) end
        local fx = workspace:FindFirstChild("EggLocalEffects")
        if fx then table.insert(exclude, fx) end
        params.FilterDescendantsInstances = exclude
        -- Probe above the native ground even when the character is below it.
        local origin = Vector3.new(position.X, ground + 24, position.Z)
        local floor = workspace:Raycast(origin, Vector3.new(0, -200, 0), params)
        if floor and floor.Normal.Y > 0.65 then return floor.Position.Y, true end
        return ground, false
    end
    function app:flightSafety(config)
        local _, root, _, hum = character()
        if not root then
            self:release()
            self:restoreSpeed()
            self.status.farm = "Character unavailable · checking death recovery"
            return true
        end
        local ground, observed = flightGround(root.Position, nil, config)
        if observed then self.safeFloor = {root = root, position = Vector3.new(root.Position.X,
            ground + hum.HipHeight + root.Size.Y * 0.5 + 0.25, root.Position.Z)} end
        local destroyY = workspace.FallenPartsDestroyHeight
        -- A shop roof/prop above the root isn't evidence that we fell below
        -- the arena. Keep the native arena baseline as the upper safety bound.
        local tooLow = root.Position.Y < math.min(ground, config.EggGroundY or ground) - 0.5
            or finite(destroyY) and root.Position.Y < destroyY + 40
        if not tooLow then return false end
        self:release(true)
        if not self:updateFlight(root) then return true end
        local safe = self.safeFloor
        local goal = observed and Vector3.new(root.Position.X, ground + hum.HipHeight + root.Size.Y * 0.5 + 0.25, root.Position.Z)
            or safe and safe.root == root and safe.position
        if not goal then
            local center = config.EggCenter
            goal = Vector3.new(center.X, ground + hum.HipHeight + root.Size.Y * 0.5 + 4, center.Z)
        end
        -- Void recovery is immediate: a long upward tween can lose the root
        -- to FallenPartsDestroyHeight before reaching its destination.
        root.CFrame = CFrame.new(goal)
        root.AssemblyLinearVelocity = Vector3.new()
        state.target, state.selectAt, state.approach, state.obstruction = nil, 0, nil, nil
        self.status.farm = "Recovered below arena · selecting new target"
        self:note("Recovered living character from below arena")
        return true
    end
    function app:restoreSpeed()
        local s = self.speed
        if s and shared.speed == s then
            local ok = pcall(function()
                if s.hum.Parent and s.hum.WalkSpeed == s.applied then s.hum.WalkSpeed = s.original end
            end)
            if not ok then return false end
            shared.speed = nil
        end
        self.speed = nil
        return true
    end
    function app:updateSpeed()
        local _, root, _, hum = character()
        if self.move and (not hum or self.move.root ~= root) then self:release() end
        if self.flight and (not hum or self.flight.root ~= root) then self:restoreFlight() end
        if not hum or not finite(hum.WalkSpeed) or hum.WalkSpeed <= 0 then self:restoreSpeed() return end
        local active = player:GetAttribute("SprintActive") == true
        local config = module("BreakTheEgg", "Config")
        local multiplier = config and config.SprintSpeedMultiplier or 1.5
        local s = self.speed
        if not s or s.hum ~= hum then
            self:restoreSpeed()
            local old = shared.speed
            local original = old and old.hum == hum and hum.WalkSpeed == old.applied and old.original or hum.WalkSpeed
            s = {hum = hum, original = original, active = active, owner = self}
            self.speed = s
            shared.speed = s
        elseif hum.WalkSpeed ~= s.applied then
            -- Replicated boots/VIP/stat changes replace the baseline; never
            -- multiply our own last override a second time.
            s.original, s.active = hum.WalkSpeed, active
        end
        s.applied = s.original * (s.active and 1 or multiplier)
        hum.WalkSpeed = s.applied
    end
    local function lease(family, enabled, aim)
        local held = state.leases[family]
        if enabled then
            local at = type(held) == "table" and held.at or held or 0
            if at <= os.clock() then
                local sent
                if family == "Bucket" then sent = send(refs.action, "ToolUse", family, true, aim)
                else sent = send(refs.action, "ToolUse", family, true) end
                if not sent then return false end
                state.leases[family] = {owner = app, object = refs.action, at = os.clock() + (family == "Bucket" and 0.1 or 0.25)}
            end
        elseif held and (type(held) == "table" and held.owner == app or type(held) ~= "table" and shared.owner == app) then
            -- A release is allowed after Stop; it retracts only this instance's hold.
            local obj = type(held) == "table" and held.object or refs.action
            local ok = pcall(function()
                if obj then
                    if family == "Bucket" then obj:FireServer("ToolUse", family, false, nil)
                    else obj:FireServer("ToolUse", family, false) end
                end
            end)
            if not ok then return false end
            state.leases[family] = nil
        end
        return true
    end
    function app:restoreFlight()
        local f = self.flight
        if not f then return true end
        if shared.flight ~= f then self.flight = nil return true end
        local complete = true
        if f.hover then
            local ok = pcall(f.hover.Destroy, f.hover)
            if ok then f.hover = nil else complete = false end
        end
        for part, original in pairs(f.parts) do
            local ok = pcall(function()
                if part.Parent and part.CanCollide == false then part.CanCollide = original end
            end)
            if ok then f.parts[part] = nil else complete = false end
        end
        if complete then self.flight, shared.flight = nil, nil end
        return complete
    end
    function app:updateFlight(root)
        if game.PlaceId ~= 104087083666671 or not self.running then return self:restoreFlight() end
        if self.flight and self.flight.root ~= root and not self:restoreFlight() then return false end
        local f = self.flight
        if not f then
            if shared.flight then return false end -- An older owner must finish restoration first.
            f = {root = root, parts = {}, owner = self}
            self.flight, shared.flight = f, f
        end
        for _, part in ipairs(player.Character:GetDescendants()) do
            if part:IsA("BasePart") then
                if f.parts[part] == nil then f.parts[part] = part.CanCollide end
                part.CanCollide = false
            end
        end
        if f.hover and f.hover.Parent ~= root then
            f.hover:Destroy()
            f.hover = nil
        end
        if not f.hover then
            local hover = Instance.new("BodyVelocity")
            f.hover = hover -- Record before setting properties so partial startup is recoverable.
            hover.Name = "CrackEggTravelHold"
            hover.MaxForce, hover.Velocity, hover.P = Vector3.new(1000000, 1000000, 1000000), Vector3.new(), 10000
            hover.Parent = root
            local velocity = root.AssemblyLinearVelocity
            if velocity then root.AssemblyLinearVelocity = Vector3.new() end
        end
        f.hover.MaxForce, f.hover.Velocity = Vector3.new(1000000, 1000000, 1000000), Vector3.new()
        return true
    end
    function app:release(keepFlight)
        -- Default release cancels travel/held tools, while active round hover
        -- persists. Explicit false permits native jump/knockback and teardown.
        if keepFlight == nil then
            local _, root = character()
            keepFlight = self.running and self.alive and not self.teleporting
                and game.PlaceId == 104087083666671 and root ~= nil
                and self.flight ~= nil and self.flight.root == root
        end
        local complete = true
        for _, family in ipairs({"Bucket", "Drill"}) do
            local ok, result = pcall(lease, family, false)
            if not ok or result == false then complete = false end
        end
        if self.move then
            local m = self.move
            local movementReleased = true
            if m.tween then
                local cancelled = pcall(m.tween.Cancel, m.tween)
                local destroyed = pcall(m.tween.Destroy, m.tween)
                if cancelled and destroyed then m.tween = nil else movementReleased = false end
            end
            local rotated = pcall(function()
                if m.rotationOwned and m.hum and m.hum.Parent and m.hum.AutoRotate == false then m.hum.AutoRotate = m.autoRotate end
            end)
            local stopped = pcall(function()
                if m.hum and m.hum.Parent and m.root and m.root.Parent then m.hum:MoveTo(m.root.Position) end
            end)
            if rotated and stopped and movementReleased then self.move = nil else complete = false end
        end
        if not keepFlight then
            local ok, restored = pcall(self.restoreFlight, self)
            if not ok or restored == false then complete = false end
        end
        return complete
    end
    local function move(lane, key, target, position, range, approach)
        local _, root, head, hum = character()
        if not root then return false, "Waiting for living character" end
        app:updateSpeed()
        local origin = (lane == "mine" or lane == "collect" or lane == "sell" or lane == "shop") and head.Position or root.Position
        if not hum.SeatPart and not hum.Sit and (origin - position).Magnitude <= range
            and (not approach or (root.Position - approach.goal).Magnitude <= 0.75) then
            if app.move then app:release() end
            return true
        end
        local policy = travelPolicy()
        local fingerprint = movementFingerprint(target, lane)
        if not eligible("move:" .. key, fingerprint) then return false, "Movement blocked; target made no progress" end
        local m = app.move
        if not m or m.key ~= key or m.target ~= target or m.root ~= root or m.policy ~= policy or m.fingerprint ~= fingerprint then
            app:release()
            m = {key = key, target = target, lane = lane, root = root, hum = hum, policy = policy, at = os.clock(),
                progressAt = os.clock(), last = root.Position, destination = position, retries = 0, fingerprint = fingerprint}
            app.move = m
        end
        if hum.SeatPart or hum.Sit then
            if m.tween then m.tween:Cancel() m.tween:Destroy() m.tween = nil end
            hum.Sit = false
            hum.Jump = true
            if os.clock() - m.at > 3 then
                fail("move:" .. key, fingerprint, "Seat release not confirmed")
                app:release()
            end
            return false, "Releasing seat"
        end
        local direction = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
        local destination = position + (direction.Magnitude > 0.1 and direction.Unit or Vector3.new(1, 0, 0)) * math.max(1, range * 0.45)
        if lane == "evade" then destination = position end
        if approach then destination = approach.goal end
        local directFlight = policy == "Tween" and (lane == "mine" or lane == "collect" or lane == "shop") and not approach
        m.air = directFlight or approach and approach.air or false
        if directFlight then
            -- Fly straight into real head/tool range in all three dimensions.
            -- Ground/platform projection must not erase an upper target's Y.
            local delta = head.Position - position
            local outward = delta.Magnitude > 0.01 and delta.Unit or Vector3.new(1, 0, 0)
            if lane == "collect" then
                local radial = Vector3.new(delta.X, 0, delta.Z)
                radial = radial.Magnitude > 0.01 and radial.Unit or Vector3.new(1, 0, 0)
                outward = (radial * 0.35 + Vector3.new(0, 0.75, 0)).Unit
            end
            destination = position + outward * math.max(2, range * 0.45) - (head.Position - root.Position)
            state.needScaffold = nil
        end
        -- Project the walking destination onto traversable ground.
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {player.Character, target}
        params.RespectCanCollide = true
        local floor = workspace:Raycast(destination + Vector3.new(0, 5, 0), Vector3.new(0, -24, 0), params)
        if floor and floor.Normal.Y > 0.65 then
            if not approach and not directFlight then destination = floor.Position + Vector3.new(0, hum.HipHeight + root.Size.Y * 0.5, 0) end
        else floor = nil end
        if policy == "Tween" then
            if root.Anchored then
                if os.clock() - m.at > 3 then
                    fail("move:" .. key, fingerprint, "Character root remains anchored")
                    app:release()
                end
                return false, "Character root anchored"
            end
            if not floor and not m.air then destination = Vector3.new(destination.X, root.Position.Y, destination.Z) end
            if lane ~= "evade" then
                local config = module("BreakTheEgg", "Config")
                local ground = lane == "shop" and config.EggGroundY or flightGround(destination, target, config)
                local minY = ground + hum.HipHeight + root.Size.Y * 0.5 + 0.25
                if destination.Y < minY then
                    destination = Vector3.new(destination.X, minY, destination.Z)
                    -- Arrival/contact must use the adjusted endpoint too.
                    if approach then approach.goal = destination end
                end
            end
            if not app:updateFlight(root) then return false, "Waiting for owned collision restoration" end
            if (root.Position - m.last).Magnitude >= 1 then m.last, m.progressAt = root.Position, os.clock() end
            if os.clock() - m.progressAt > 3 or os.clock() - m.at > 20 then
                fail("move:" .. key, fingerprint, "Tween did not reach tool range")
                if lane == "mine" or lane == "collect" then
                    app.cooldowns["hit:" .. targetId(target)] = os.clock() + 3
                    state.target, state.selectAt = nil, 0
                end
                app:release()
                return false, "Tween blocked; selecting another target"
            end
            local completed = m.tween and m.tween.PlaybackState ~= Enum.PlaybackState.Playing
            if not m.tween or completed or (destination - m.destination).Magnitude > 3 then
                if m.tween then
                    m.tween:Cancel()
                    m.tween:Destroy()
                    m.tween = nil
                end
                if not m.rotationOwned then
                    m.autoRotate, m.rotationOwned = hum.AutoRotate, true
                    hum.AutoRotate = false
                    hum:MoveTo(root.Position)
                end
                local distance = (destination - root.Position).Magnitude
                local duration = math.max(0.08, distance / math.max(1, hum.WalkSpeed))
                m.destination = destination
                local facing = Vector3.new(position.X, destination.Y, position.Z)
                if (facing - destination).Magnitude < 0.01 then
                    local forward = Vector3.new(destination.X - root.Position.X, 0, destination.Z - root.Position.Z)
                    facing = destination + (forward.Magnitude > 0.01 and forward.Unit or Vector3.new(0, 0, -1))
                end
                m.tween = game:GetService("TweenService"):Create(root,
                    TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
                    {CFrame = CFrame.lookAt(destination, facing)})
                m.tween:Play()
            end
            return false, (directFlight and "Flying to " or "Tween to ") .. lane .. " target"
        end
        do
            if (destination - m.destination).Magnitude > 3 then
                m.path, m.destination, m.commandAt = nil, destination, 0
            end
            if (root.Position - m.last).Magnitude >= 1 then
                m.last, m.progressAt = root.Position, os.clock()
            end
            if os.clock() - m.progressAt > 3 then
                m.retries += 1
                m.progressAt = os.clock()
                hum.Jump = true
                m.path = nil
                if m.retries >= 3 then
                    fail("move:" .. key, fingerprint, "Walk stuck after verified retries")
                    if lane == "mine" or lane == "collect" then
                        app.cooldowns["hit:" .. targetId(target)] = os.clock() + 3
                        state.target, state.selectAt = nil, 0
                    end
                    app:release()
                    return false, "Walk blocked"
                end
            end
            if pathJob and pathJob.done then
                if pathJob.owner == m and pathJob.ok and pathJob.destination
                    and (pathJob.destination - destination).Magnitude < 3 then m.path, m.waypoint = pathJob.points, 2 end
                pathJob, shared.pathJob = nil, nil
            end
            if not m.path and not pathJob then
                local job = {owner = m, started = os.clock(), destination = destination}
                pathJob = job
                shared.pathJob = job
                task.spawn(function()
                    job.ok = pcall(function()
                        local path = game:GetService("PathfindingService"):CreatePath({AgentCanJump = true, AgentRadius = 2})
                        path:ComputeAsync(root.Position, destination)
                        if path.Status ~= Enum.PathStatus.Success then error("no path") end
                        job.points = path:GetWaypoints()
                    end)
                    job.done = true
                end)
            end
            -- Keep issuing direct walking commands while ComputeAsync yields.
            -- An unresolved path must not stop movement or nearby attacks.
            if (m.commandAt or 0) <= os.clock() then
                local wp = m.path and m.path[m.waypoint]
                if wp and (root.Position - wp.Position).Magnitude < 3 then
                    m.waypoint += 1
                    wp = m.path[m.waypoint]
                end
                if wp and wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
                hum:MoveTo(wp and wp.Position or destination)
                m.commandAt = os.clock() + 0.4
            end
        end
        if os.clock() - m.at > 20 then
            fail("move:" .. key, fingerprint, "Arrival not confirmed")
            if lane == "mine" or lane == "collect" then
                app.cooldowns["hit:" .. targetId(target)] = os.clock() + 3
                state.target, state.selectAt = nil, 0
            end
            app:release()
        end
        return false, policy .. " to " .. lane .. " target"
    end
    local function queueReceipt(kind, detail)
        local p = state.pending.queue
        if not p then return end
        if kind == "error" or kind == "locked" then
            fail("queue", p.fingerprint, tostring(detail or kind))
            app.status.queue = tostring(detail or kind)
        else
            state.queueAccepted = p.difficulty
            success("queue")
        end
        state.pending.queue = nil
    end
    local function queueOccupied()
        local id = player:GetAttribute("Queue")
        return player:GetAttribute("InQueue") == true or id ~= nil and id ~= false and id ~= "" and id ~= 0
    end
    local function unlockedDifficulty()
        local requested = app.settings.difficulty
        if requested == "Hard" and player:GetAttribute("WonMedium") == true then return "Hard" end
        if requested ~= "Easy" and player:GetAttribute("WonEasy") == true then return "Medium" end
        return "Easy"
    end
    local function index(obj)
        if obj:IsA("Model") or obj:IsA("Folder") then
            -- Models often arrive before attributes; indexing each model once lets
            -- later replication become eligible without installing thousands of listeners.
            if not state.targets[obj] then
                state.targets[obj] = true
                table.insert(state.targetList, obj)
            end
        elseif obj:IsA("ProximityPrompt") and obj.Name == "SellPrompt" then
            state.parts[obj] = true
        elseif obj:IsA("BasePart") then
            local parent = obj.Parent
            while parent and parent ~= state.lab do
                local cached = state.targets[parent]
                if type(cached) == "table" then cached.faces = nil end
                parent = parent.Parent
            end
        end
    end
    local function actionReceipt(kind, a, b, c)
        if kind == "State" and type(a) == "table" then
            local ranks = {}
            for id, n in pairs(a) do if type(id) == "string" and finite(n) and n >= 0 then ranks[id] = n end end
            state.ranks, state.stateAt = ranks, os.clock()
            local p = state.pending.upgrade
            if p and (ranks[p.id] or 0) > 0 then state.pending.upgrade = nil success("run-buy:" .. p.id) end
        elseif kind == "MiningResult" then
            local blast = state.pending.blast
            if blast and blast.serial == a then
                state.pending.blast = nil
                if b == true then state.stats.explosives = (state.stats.explosives or 0) + 1
                else fail("explosive", blast.fingerprint, "Explosive rejected") end
                return
            end
            local p = state.pending.hit
            if p and p.serial == a then
                state.pending.hit = nil
                if b == true then
                    state.stats.hits += 1
                    local hp, quantity = p.target:GetAttribute("HP") or p.target:GetAttribute("Health"), p.target:GetAttribute("Quantity")
                    if not p.target.Parent or finite(p.hp) and finite(hp) and hp < p.hp
                        or finite(p.quantity) and (quantity or 0) < p.quantity
                        or not finite(p.hp) and not finite(p.quantity) then success(p.key) end
                else fail(p.key, p.fingerprint, "MiningResult rejected") end
            end
        elseif kind == "GunShopBought" and type(a) == "table" and a.Buyer == player.UserId then
            local p = state.pending.gunBuy
            if p and p.id == a.Gun and p.slot == a.Slot then p.received = true end
        elseif kind == "GunShopDenied" and type(a) == "table" then
            local p = state.pending.gunBuy
            -- Denials don't identify a buyer in this export. Retain ownership
            -- until a fresh shop snapshot or replicated gun resolves it.
            if p and p.id == a.Gun and p.slot == a.Slot then p.denied = true end
        elseif kind == "GunShot" and type(a) == "table" and a.Owner == player.UserId then
            local g = state.gun
            if g and g.shots[a.Id] then
                g.shots[a.Id] = nil
                state.stats.gunShots = (state.stats.gunShots or 0) + 1
            end
        elseif kind == "Collected" then
            if finite(b) and b > 0 then state.stats.collected += b end
        elseif kind == "WeakPoint" and type(a) == "table" then
            state.weak = not a.Clear and typeof(a.Position) == "Vector3" and a or nil
        elseif kind == "EggWon" then
            if not state.won then
                state.won = {data = a, at = os.clock()}
                state.stats.wins = (state.stats.wins or 0) + 1
            end
            app:release()
        elseif kind == "BossStruck" and a == player.UserId then
            state.stats.bossStrikes = (state.stats.bossStrikes or 0) + 1
            state.evadeGoal, state.evadeApproach = nil, nil
            state.knockUntil = os.clock() + 0.35
            app:release(false) -- Let the native knockback move the character, then replan.
        elseif kind == "LobbyReturned" then
            state.pending.returnLobby = nil
            state.won = nil
        elseif kind == "LobbyFailed" then
            state.pending.returnLobby = nil
            fail("return", "win", tostring(a))
        elseif kind == "Notice" then
            app:note("Game: " .. tostring(a))
        end
    end
    local function chestReceipt(kind, data)
        if type(data) ~= "table" then return end
        if kind == "Chests" then
            local records = {}
            for _, item in ipairs(data) do
                if type(item) == "table" and item.Id ~= nil and typeof(item.CFrame) == "CFrame" then records[item.Id] = item end
            end
            state.chests = records
        elseif kind == "Opened" and data.Id ~= nil then
            local p = state.pending.chest
            if p and p.id == data.Id and p.action == "Open" then
                p.startedAt = p.startedAt or os.clock()
                if app.move and app.move.lane == "chest" and app.move.key == "chest:" .. tostring(data.Id) then app:release() end
            end
        elseif (kind == "Offer" or kind == "Rerolled") and data.Id ~= nil and type(data.Offers) == "table" and finite(data.Revision) then
            local old = state.offers[data.Id]
            if not old or data.Revision >= old.Revision then state.offers[data.Id] = data end
            local p = state.pending.chest
            if p and p.id == data.Id and (p.action == "Open" or p.revision and data.Revision > p.revision) then
                state.pending.chest = nil
            end
        elseif (kind == "Chosen" or kind == "ChosenAll") and data.Id ~= nil then
            if state.done[data.Id] then return end -- Native ChosenAll also ignores an already-opened record.
            app.nativeClaim = nil
            local p = state.pending.chest
            state.done[data.Id] = true
            state.offers[data.Id] = nil
            state.stats.chests += 1
            if p and p.id == data.Id then
                state.pending.chest = nil
                success("chest:" .. tostring(data.Id))
                -- Direct Choose bypasses the picker's click animation. Abort only
                -- our picker after its matching authoritative result.
                if kind == "Chosen" and p.action == "Choose" then
                    local picker = module("BreakTheEgg/ChestCards", "ChestPicker")
                    if picker and type(picker.Abort) == "function" then pcall(picker.Abort) end
                end
            end
        elseif kind == "NeedProduct" then
            local p = state.pending.chest
            if p then
                fail("chest:" .. tostring(p.id), p.fingerprint, "Ownership not accepted; premium path stopped")
                state.pending.chest = nil
            end
        end
    end
    local function bind(obj, handler, field)
        local old = installed[field]
        if old and old.object ~= obj then
            local ok = pcall(old.connection.Disconnect, old.connection)
            if ok then
                local i = table.find(app.connections, old.connection)
                if i then table.remove(app.connections, i) end
            end
            installed[field] = nil
        end
        if obj and not installed[field] then
            local connection = connect(obj.OnClientEvent, function(...)
                if refs[field] == obj then handler(...) end
            end)
            installed[field] = {object = obj, connection = connection}
            return true
        end
        return false
    end
    local function refresh()
        local nextAction = event("BreakTheEgg", "Action")
        if nextAction ~= refs.action then state.ranks, state.stateAt = nil, nil end
        refs.action = nextAction
        refs.chest = event("BreakTheEgg", "RewardChests")
        refs.create = event("Remotes", "CreateParty")
        refs.exit = event("Remotes", "Exit")
        local workerActive = player:GetAttribute("WorkerActive")
        if state.lastWorkerActive == true and workerActive == false then state.workerEpoch = (state.workerEpoch or 0) + 1 end
        state.lastWorkerActive = workerActive
        refs.death = event("BreakTheEgg", "DeathChoice")
        local newAction = bind(refs.action, actionReceipt, "action")
        local newChest = bind(refs.chest, chestReceipt, "chest")
        if newAction then send(refs.action, "Sync") end
        if newChest then send(refs.chest, "Ready") end
        bind(refs.create, queueReceipt, "create")
        local lab = workspace:FindFirstChild("BreakTheEgg")
        local worldChanged = lab ~= state.lab
        if worldChanged or lab and installed.boundLab ~= lab then
            app:release(false)
            for _, field in ipairs({"labAdded", "labRemoving"}) do
                local connection = installed[field]
                if connection then
                    local ok = pcall(connection.Disconnect, connection)
                    if ok then
                        local i = table.find(app.connections, connection)
                        if i then table.remove(app.connections, i) end
                    end
                    installed[field] = nil
                end
            end
            if worldChanged then
                state.lab, state.targets, state.parts, state.targetList = lab, {}, {}, {}
                state.ranks, state.won, state.pending = nil, nil, {}
                state.chests, state.offers, state.done = {}, {}, {}
                state.workerAttempt, state.activity, state.hold, state.evadeGoal, state.bagSince, state.needScaffold = nil, nil, nil, nil, nil, nil
                state.evadeApproach, state.knockUntil, state.quakeFlight = nil, nil, nil
                state.gun, state.explosive, state.gunRoute = nil, nil, nil
                state.frontierAt, state.upperTarget, state.passiveVisit, state.passiveNextAt = nil, nil, nil, nil
                state.inspection, state.inspections = nil, nil
                state.approach, state.obstruction, state.saleRoute, state.saleRetryAt, state.salePreference = nil, nil, nil, nil, nil
                -- These keys name objects/tokens in the departed world, never a
                -- persistent purchase or inventory outcome.
                for key in pairs(app.failures) do
                    if string.sub(key, 1, 4) == "hit:" or string.sub(key, 1, 6) == "chest:"
                        or string.sub(key, 1, 5) == "move:" or key == "worker-deploy" or key == "sale" then success(key) end
                end
            end
            -- Listener ownership is per app even when shared world/pending
            -- outcomes survive reexecution. Never discard unresolved actions.
            installed.boundLab = lab
            if lab then
                for _, obj in ipairs(lab:GetDescendants()) do index(obj) end
                installed.labAdded = connect(lab.DescendantAdded, function(obj) if state.lab == lab then index(obj) end end)
                installed.labRemoving = connect(lab.DescendantRemoving, function(obj)
                    if state.lab == lab then state.targets[obj], state.parts[obj] = nil, nil end
                end)
                if refs.action and not newAction then send(refs.action, "Sync") end
                if refs.chest and not newChest then send(refs.chest, "Ready") end
            end
        end
        -- MinecartSeller creates SellAnchor/SellPrompt on workspace.Minecart,
        -- outside BreakTheEgg. Polling also covers late streaming/replacement.
        local cart = workspace:FindFirstChild("Minecart")
        local sellPrompt = cart and cart:FindFirstChild("SellPrompt", true)
        if state.nativeSellPrompt ~= sellPrompt then
            if state.nativeSellPrompt then state.parts[state.nativeSellPrompt] = nil end
            state.nativeSellPrompt = sellPrompt
        end
        if sellPrompt and sellPrompt:IsA("ProximityPrompt") then state.parts[sellPrompt] = true end
    end
    local function owns(family, config)
        local def = config.ToolById[family]
        return def and (not def.Unlock and family ~= "Gun" or player:GetAttribute("Owns_" .. family) == true)
    end
    local function equipped(family)
        local c = player.Character
        local tool = c and c:FindFirstChild(family)
        return player:GetAttribute("EquippedTool") == family and tool and tool:IsA("Tool") and tool:GetAttribute("EggTool") == family
            and (family ~= "Gun" or tool:GetAttribute("GunId") == player:GetAttribute("GunId"))
    end
    local function equip(family, config)
        local p = state.pending.equip
        if p then
            if equipped(p.family) and (p.family ~= "Gun" or p.gunId == player:GetAttribute("GunId")) then
                state.pending.equip = nil
                success("equip-tool:" .. p.family)
            elseif os.clock() - p.at > 4 then
                fail("equip-tool:" .. p.family, p.fingerprint, "Equipped tool not replicated")
                state.pending.equip = nil
            end
            if state.pending.equip then return false end
        end
        if equipped(family) then return true end
        if not owns(family, config) then return false end
        local drillReleased, bucketReleased = lease("Drill", false), lease("Bucket", false)
        if not drillReleased or not bucketReleased or state.leases.Drill or state.leases.Bucket then return false end
        local gunId = family == "Gun" and player:GetAttribute("GunId") or nil
        local gunCatalog = family == "Gun" and module("BreakTheEgg", "GunCatalog")
        if family == "Gun" and (not gunCatalog or not gunCatalog.Get(gunId)) then return false end
        local fingerprint = family .. ":" .. tostring(player.Character) .. ":" .. tostring(gunId)
        if eligible("equip-tool:" .. family, fingerprint) and send(refs.action, "Equip", family, gunId) then
            state.pending.equip = {at = os.clock(), family = family, fingerprint = fingerprint, gunId = gunId}
            if family == "Gun" then state.gunEquipAt = os.clock() end
        end
        return false
    end
    local function mechanics(family)
        local m = module("BreakTheEgg", "ToolMechanics")
        return m and m.ForPlayer(player, family) or nil
    end
    local function reach(family, config)
        if family == "Gun" then
            local catalog = module("BreakTheEgg", "GunCatalog")
            local gun = catalog and catalog.Get(player:GetAttribute("GunId"))
            return gun and gun.Range or 0
        end
        local value = player:GetAttribute("MiningReach")
        local base = finite(value) and value > 0 and value or config.Reach
        if family == "Bucket" then
            local bucket = player:GetAttribute("BucketReach")
            return finite(bucket) and bucket > 0 and bucket or base
        elseif family == "HandDrill" then
            local hand = player:GetAttribute("HandDrillReach")
            return finite(hand) and hand > 0 and hand or base
        end
        return base
    end
    local function power(family, tier, config, evolution, mode)
        local d = config.ToolById[family]
        if not d then return nil end
        local base = player:GetAttribute("PickaxeDamage") or config.BaseDamage
        local scale = evolution.DamageScale[family]
        local cooldown = player:GetAttribute("ToolCooldown_" .. family) or d.Cooldown
        local m = mechanics(family)
        if family == "Pickaxe" and tier == 3 then cooldown = math.max(0.1, math.min(cooldown, 0.12)) end
        if mode == "event" and family == "Pickaxe" then
            if m and m.Continuous then cooldown = math.max(cooldown, m.ScientistGap)
            elseif not m then cooldown -= d.HitDelay * math.min(1, cooldown / d.Cooldown) end
        end
        if mode == "guardian" or mode == "core" then cooldown = math.max(0.45, cooldown) end
        local total = base * (scale and scale[tier] or 1) / math.max(0.05, cooldown)
        if family == "Drill" then
            local duration = player:GetAttribute("DrillDuration") or 30
            local recharge = player:GetAttribute("DrillRecharge") or 20
            total *= tier == 3 and 1 or duration / (duration + recharge)
            if mode ~= "event" and mode ~= "guardian" and mode ~= "core" then total *= tier == 1 and 3 or 4 end
        elseif family == "Pickaxe" and tier == 2 and mode ~= "event" and mode ~= "guardian" and mode ~= "core" then total *= 1.3
        elseif family == "HandDrill" and tier == 3 and mode ~= "event" and mode ~= "guardian" and mode ~= "core" then total *= 1.5 end
        return total, cooldown, m
    end
    local function ownedGun()
        local catalog = module("BreakTheEgg", "GunCatalog")
        return player:GetAttribute("Owns_Gun") == true and catalog and catalog.Get(player:GetAttribute("GunId")) or nil
    end
    local function preferredGun(gun)
        return gun and (gun.Id == "Minigun" or gun.Id == "Vulcan")
    end
    local function flameOwned(config)
        return owns("HandDrill", config) and player:GetAttribute("Evolution_HandDrill") == 3
    end
    local function gunState(gun)
        local ammo = player:GetAttribute("GunAmmo")
        if not finite(ammo) then return nil end
        local g = state.gun
        if not g or g.id ~= gun.Id then
            g = {id = gun.Id, ammo = math.max(0, ammo), seenAmmo = ammo, shots = {}, nextAt = 0, burst = 0}
            state.gun = g
        end
        local now, reloadAt = workspace:GetServerTimeNow(), player:GetAttribute("GunReloadAt") or 0
        if g.reload and finite(reloadAt) and reloadAt > 0 then g.reload.observed = reloadAt end
        if g.reload and not g.reload.observed and os.clock() >= (g.reloadRetryAt or math.huge) and (g.reloadTries or 0) < 3 then
            g.reload = nil -- Bounded retries of the native idempotent reload, never a shot refill guess.
        end
        if g.reload and g.reload.observed and now >= g.reload.observed
            and ammo > 0 and (ammo > g.seenAmmo or ammo == (player:GetAttribute("GunMag") or gun.Magazine)) then
            g.ammo, g.reload, g.shots, g.burst, g.reloadTries = ammo, nil, {}, 0, 0
        elseif ammo ~= g.seenAmmo then
            -- A replicated refill can follow an unobserved short reload.
            g.ammo = ammo > g.seenAmmo and ammo or math.min(g.ammo, math.max(0, ammo))
            if ammo > g.seenAmmo then g.reload, g.shots, g.burst, g.reloadTries = nil, {}, 0, 0 end
        end
        g.seenAmmo = ammo
        for id, at in pairs(g.shots) do if os.clock() - at > 5 then g.shots[id] = nil end end
        return g
    end
    local function gunUsable()
        local gun = ownedGun()
        if not gun then return nil end
        local config = module("BreakTheEgg", "Config")
        if not preferredGun(gun) and config and flameOwned(config) then return nil end
        if gun and not equipped("Gun") then
            local fp = "Gun:" .. tostring(player.Character) .. ":" .. tostring(gun.Id)
            if not eligible("equip-tool:Gun", fp) then return nil end
        end
        if not module("BreakTheEgg", "GunBallistics") then return nil end
        local g = gun and gunState(gun)
        if not g then return nil end
        local reloadAt = player:GetAttribute("GunReloadAt") or 0
        if finite(reloadAt) and reloadAt > workspace:GetServerTimeNow() or g.reload then return nil end
        return gun -- An empty magazine is selected once to request native reload.
    end
    local function shopStock()
        local folder = folderAt("BreakTheEgg")
        if not folder or folder:GetAttribute("GunShopOpen") ~= true then return nil end
        local ids, prices = {}, {}
        for id in string.gmatch(tostring(folder:GetAttribute("GunShopSlots") or ""), "[^,]+") do table.insert(ids, id) end
        for price in string.gmatch(tostring(folder:GetAttribute("GunShopPrices") or ""), "[^,]+") do table.insert(prices, tonumber(price) or false) end
        local cash = folder:GetAttribute("TeamCashCents")
        if not finite(cash) then cash = player:GetAttribute("CashCents") end
        local serial, rolled = folder:GetAttribute("GunShopSerial"), folder:GetAttribute("GunShopRolledAt")
        if serial == nil or not finite(cash) or not finite(rolled) or workspace:GetServerTimeNow() < rolled + 1.25 then return nil end
        return folder, ids, prices, cash, serial
    end
    local function gunReserve()
        if preferredGun(ownedGun()) then return 0 end
        local _, ids, prices = shopStock()
        local catalog, reserve = module("BreakTheEgg", "GunCatalog"), nil
        for i, id in ipairs(ids or {}) do
            local price = prices[i]
            if catalog and preferredGun(catalog.Get(id)) and finite(price) and price >= 0 then reserve = math.min(reserve or price, price) end
        end
        return reserve or 0
    end
    local function buyGun(config)
        local function leaveShop()
            state.gunRoute = nil
            if app.move and app.move.key == "gun-shop" then app:release(true) end
        end
        local gun = ownedGun()
        local p = state.pending.gunBuy
        if p then
            if gun and gun.Id == p.id then
                state.pending.gunBuy, state.gunRoute = nil, nil
                state.stats.gunBuys = (state.stats.gunBuys or 0) + 1
                success("gun-buy")
                app.status.gun = "Owned gun: " .. gun.Name
            else
                local folder = folderAt("BreakTheEgg")
                if p.denied and folder and folder:GetAttribute("GunShopSerial") ~= p.serial then
                    fail("gun-buy", p.fingerprint, "Matching denial followed by refreshed stock")
                    state.pending.gunBuy, state.gunRoute = nil, nil
                else
                    app.status.gun = p.received and "Gun bought; waiting for ownership" or "Gun purchase unresolved; farming continues"
                    return false -- Never repeat uncertain spending or monopolize movement.
                end
            end
        end
        if preferredGun(gun) then leaveShop() app.status.gun = "Owned gun: " .. gun.Name return false end
        if not app.settings.farm or state.pending.upgrade then leaveShop() return false end
        local phase = state.lab:GetAttribute("BossPhase") or "Idle"
        if (state.combat or phase == "Wave" or phase == "Intermission" or phase == "Core") and not flameOwned(config) then leaveShop() return false end
        if (player:GetAttribute("EggTutorialStep") or 0) < 8 then leaveShop() return false end
        local folder, ids, prices, cash, serial = shopStock()
        local catalog, prompts = module("BreakTheEgg", "GunCatalog"), workspace:FindFirstChild("GunShopPrompts")
        if not folder or not catalog or not prompts then leaveShop() app.status.gun = "Waiting for cash gun stock/prompts" return false end
        if type(fireproximityprompt) ~= "function" then leaveShop() app.status.gun = "Auto-buy gun needs fireproximityprompt" return false end
        local _, root, head = character()
        if not root then return false end
        local best, score
        for i, id in ipairs(ids) do
            local def, price = catalog.Get(id), prices[i]
            local slot = prompts:FindFirstChild("Slot" .. i)
            local prompt = slot and slot:FindFirstChild("BuyPrompt", true)
            local anchor = prompt and prompt.Parent
            local point = anchor and anchor:IsA("Attachment") and anchor.WorldPosition or anchor and anchor:IsA("BasePart") and anchor.Position
            if anchor and anchor:IsA("Attachment") then anchor = anchor.Parent end
            if preferredGun(def) and finite(price) and price >= 0 and price <= cash and prompt and prompt:IsA("ProximityPrompt")
                and prompt.Enabled and prompt:GetAttribute("GunShopSlot") == i and anchor and anchor:IsA("BasePart") then
                local rate = catalog.CycleRate(id)
                local value = (def.FoeDamage or 1) * def.Pellets * rate * def.Magazine / (def.Magazine + rate * def.Reload)
                if not best or value > score then best, score = {id = id, slot = i, price = price, prompt = prompt, anchor = anchor, point = point}, value end
            end
        end
        if not best then leaveShop() app.status.gun = "Waiting for affordable Minigun/Vulcan restock · owned flamethrower fallback" return false end
        local fp = tostring(serial) .. ":" .. best.slot .. ":" .. best.id .. ":" .. best.price
        if not eligible("gun-buy", fp) then leaveShop() return false end
        local route = state.gunRoute
        if not route or route.fingerprint ~= fp or route.prompt ~= best.prompt then
            success("move:gun-shop") -- A new native stock/slot is a new route attempt.
            route = {fingerprint = fp, prompt = best.prompt, at = os.clock(), attempt = 0}
            state.gunRoute = route
        end
        local range = best.prompt.MaxActivationDistance
        if not finite(range) or range <= 0 then return false end
        if route.goal and not route.recovered and app.move and app.move.key == "gun-shop"
            and os.clock() - app.move.progressAt > 2 and not root.Anchored then
            -- One bounded recovery for a stalled owned tween; purchase still
            -- requires fresh stock, actual head distance and native LOS below.
            app:release(true)
            if app:updateFlight(root) then
                root.CFrame = CFrame.new(route.goal)
                root.AssemblyLinearVelocity = Vector3.new()
                route.recovered = true
            end
        end
        if (head.Position - best.point).Magnitude > range * 0.8 then
            if not route.goal or os.clock() - (route.goalAt or 0) > 2.5 or (route.point - best.point).Magnitude > 1 then
                route.attempt += 1
                local offset = head.Position - best.point
                local angle = route.attempt == 1 and math.atan2(offset.Z, offset.X) or route.attempt * math.pi * 0.5
                local radius = math.min(range * 0.35, 3)
                local headGoal = best.point + Vector3.new(math.cos(angle) * radius, math.min(2, range * 0.2), math.sin(angle) * radius)
                route.goal = headGoal - (head.Position - root.Position)
                route.goalAt, route.point = os.clock(), best.point
                if app.move and app.move.key == "gun-shop" then app:release(true) end
            end
        end
        local approach = route.goal and {goal = route.goal, air = true}
        local arrived, reason = move("shop", "gun-shop", best.anchor, best.point, range * 0.8, approach)
        if approach then route.goal = approach.goal end -- Retain the floor-safe endpoint for stalled recovery too.
        app.status.farm, app.status.gun = "Buying boss gun · " .. tostring(reason or best.id), "Buying " .. best.id .. " for " .. best.price .. " cents"
        if not arrived then
            if not app.move or os.clock() - route.at > 20 then
                fail("gun-buy", fp, "Gun shop travel timed out") state.gunRoute = nil
                if app.move and app.move.key == "gun-shop" then app:release() end
                return false
            end
            return true
        end
        -- Re-read shared cash and stock immediately before committing the prompt.
        local fresh, freshIds, freshPrices, freshCash, freshSerial = shopStock()
        if not fresh or freshSerial ~= serial or freshIds[best.slot] ~= best.id or freshPrices[best.slot] ~= best.price
            or freshCash < best.price or not best.prompt.Parent or not best.prompt.Enabled
            or (head.Position - best.point).Magnitude > range then state.gunRoute = nil return false end
        if best.prompt.RequiresLineOfSight then
            local params = RaycastParams.new()
            params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, {player.Character}
            local delta = best.point - head.Position
            local wall = workspace:Raycast(head.Position, delta, params)
            if wall and wall.Instance ~= best.anchor and (wall.Position - head.Position).Magnitude < delta.Magnitude - 0.5 then
                route.goal, route.goalAt = nil, 0
                if os.clock() - route.at > 12 then fail("gun-buy", fp, "Buy prompt line of sight obstructed") leaveShop() return false end
                -- Move to another real prompt side rather than waiting at a wall.
                local angle = (route.attempt + 1) * math.pi * 0.5
                route.attempt += 1
                route.point, route.goalAt = best.point, os.clock()
                route.goal = best.point + Vector3.new(math.cos(angle) * range * 0.4, 2, math.sin(angle) * range * 0.4) - (head.Position - root.Position)
                return true
            end
        end
        local bucketReleased, drillReleased = lease("Bucket", false), lease("Drill", false)
        if not bucketReleased or not drillReleased then return true end
        state.pending.gunBuy = {id = best.id, slot = best.slot, price = best.price, serial = serial, at = os.clock(), fingerprint = fp}
        local ok, err = pcall(fireproximityprompt, best.prompt, best.prompt.HoldDuration)
        if not ok then app:note("Gun buy prompt: " .. tostring(err) .. "; checking ownership before retry") end
        state.gunRoute = nil
        return true
    end
    local function upgradeScore(def, catalog, ranks)
        local before = catalog.Stats(ranks, player:GetAttribute("PickaxeTier"))
        local copy = table.clone(ranks)
        copy[def.Id] = 1
        local after = catalog.Stats(copy, player:GetAttribute("PickaxeTier"))
        local gain = 0
        if def.Tree == "weapons" then
            local guns = module("BreakTheEgg", "GunCatalog")
            if not ownedGun() or not guns then return 0 end
            local from, to = guns.Upgrades(ranks), guns.Upgrades(copy)
            for field, weight in pairs({Damage = 3, Rate = 2, Mag = 0.6, Shell = 1, Pierce = 0.7, Ricochet = 0.3, Explosive = 3}) do
                gain += math.max(0, to[field] - from[field]) / math.max(1, math.abs(from[field])) * weight
            end
            for field, weight in pairs({Reload = 1, Spread = 1}) do gain += math.max(0, from[field] / math.max(0.05, to[field]) - 1) * weight end
            return gain
        end
        if def.Family == "autoCollect" and player:GetAttribute("VIPOwned_vip_magnet") == true
            or def.Family == "chute" and player:GetAttribute("VIPOwned_vip_autoSell") == true then return 0 end
        for field, weight in pairs({Damage = 3, Reach = 0.5, HandReach = 0.5, ScoopRadius = 0.5, WalkSpeed = 0.2,
            DrillRadius = 0.5, DrillDuration = 0.4, WorkerMultiplier = 0.5, SaleBonus = 1, Fracture = 1, Teamwork = 1,
            BlastDamage = 1, BlastEdge = 0.4}) do
            if finite(after[field]) and finite(before[field]) then
                gain += math.max(0, after[field] - before[field]) / math.max(1, math.abs(before[field])) * weight
            end
        end
        for field, weight in pairs({ScoopCooldown = 1, DrillRecharge = 0.4, WorkerInterval = 0.5, Fuse = 0.5}) do
            if finite(after[field]) and finite(before[field]) then gain += math.max(0, before[field] / math.max(0.05, after[field]) - 1) * weight end
        end
        if after.AutoCollect and not before.AutoCollect then gain += 4 end
        if after.Chute and not before.Chute then gain += 2 end
        if def.Family == "capacity" then return 0 end -- User owns Infinite Bucket.
        if def.Family == "scaffold" then return 0 end -- Direct flight reaches upper targets without buying platforms.
        if def.Family == "handdrill" or def.Family == "drill" or def.Family == "worker" or def.Family == "dynamite" then gain += 2 end
        if finite(after.Tier) and after.Tier > before.Tier then
            local required = state.requiredLayer or 1
            gain += after.Tier <= required and 100 or 0.05
        end
        return gain
    end
    local function upgrades(config)
        if not app.settings.runUpgrades then return end
        if state.pending.gunBuy or state.gunRoute then app.status.upgrades = "Cash reserved for pending gun purchase" return end
        local catalog = module("BreakTheEgg", "UpgradeCatalog")
        if not catalog or not state.ranks then
            app.status.upgrades = "Waiting for round rank State"
            if (state.syncAt or 0) <= os.clock() then send(refs.action, "Sync") state.syncAt = os.clock() + 3 end
            return
        end
        local p = state.pending.upgrade
        if p then
            if (state.ranks[p.id] or 0) > 0 then state.pending.upgrade = nil success("run-buy:" .. p.id)
            elseif os.clock() - p.at >= 4 and not p.synced then
                p.synced = true
                p.reconcileAt = os.clock()
                send(refs.action, "Sync")
            elseif p.synced and (state.stateAt or 0) > p.reconcileAt then
                fail("run-buy:" .. p.id, p.fingerprint, "Fresh State shows purchase not owned")
                state.pending.upgrade = nil
            else app.status.upgrades = "Purchase pending authoritative State" end
            return
        end
        if (state.buyAt or 0) > os.clock() then return end
        local cash = player:GetAttribute("CashCents")
        if not finite(cash) then app.status.upgrades = "CashCents unavailable" return end
        local budget = math.max(0, cash - gunReserve())
        local best, score, cost, fingerprint
        for _, def in ipairs(catalog.Nodes) do
            local gateOpen = not def.Gate or def.Gate == catalog.WeaponGate and ownedGun()
                and folderAt("BreakTheEgg"):GetAttribute("GunShopOpen") == true
            if not def.Product and not def.ProductId and not def.premium and gateOpen
                and (def.Currency == nil or def.Currency == "cash") and (state.ranks[def.Id] or 0) <= 0
                and (def.StandalonePurchase or def.Id == catalog.PersonalStarterId or (state.ranks[catalog.PersonalStarterId] or 0) > 0)
                and catalog.Unlocked(def, state.ranks) then
                local price = catalog.PurchaseCost(def, cash, player:GetAttribute("EggTutorialStep"), false)
                local fp = tostring(price) .. ":" .. tostring(state.requiredLayer) .. ":" .. tostring(player:GetAttribute("EggTutorialStep"))
                local value = upgradeScore(def, catalog, state.ranks) / math.max(1, price)
                if finite(price) and price >= 0 and price <= budget and eligible("run-buy:" .. def.Id, fp)
                    and value > 0 and (not best or value > score) then best, score, cost, fingerprint = def, value, price, fp end
            end
        end
        if best and send(refs.action, "BuyUpgrade", best.Id) then
            state.pending.upgrade = {id = best.Id, at = os.clock(), fingerprint = fingerprint, cost = cost}
            state.buyAt = os.clock() + 0.2
            app.status.upgrades = "Buying " .. tostring(best.Name) .. " for " .. tostring(cost) .. " cents"
        else app.status.upgrades = "Useful round upgrades owned or waiting for cash" end
    end
    local function worker(config)
        -- Worker is an ON/OFF native action, not a repeatable attack. Activate
        -- an already owned worker once and reconcile WorkerActive before ever
        -- considering another toggle. It then mines/hauls alongside the player.
        if not owns("Worker", config) then app.status.worker = "Worker not owned" return false end
        local active = player:GetAttribute("WorkerActive")
        if active == true then
            state.workerAttempt = nil
            success("worker-deploy")
            app.status.worker = "Worker active · " .. tostring(player:GetAttribute("WorkerStatus") or "loading")
            return false
        end
        local c = player.Character
        local fp = tostring(c) .. ":" .. tostring(state.workerEpoch or 0)
        local p = state.workerAttempt
        if p and p.character ~= c then state.workerAttempt, p = nil, nil end
        if p then
            app.status.worker = os.clock() - p.at > 8 and "Worker toggle unresolved; independent farming continues" or "Worker activation pending"
            return false
        end
        if active ~= false then app.status.worker = "WorkerActive not replicated; no uncertain toggle" return false end
        if state.combat or (state.lab:GetAttribute("BossPhase") or "Idle") ~= "Idle"
            or (player:GetAttribute("EggTutorialStep") or 0) < 8 or state.pending.sale
            or state.pending.chest or state.pending.hit or not eligible("worker-deploy", fp) then return false end
        if not equip("Worker", config) then app.status.farm = "Equipping owned worker for deployment" return true end
        if send(refs.action, "Worker") then
            state.workerAttempt = {character = c, at = os.clock(), fingerprint = fp}
            app.status.worker = "Worker activation pending"
        else fail("worker-deploy", fp, "Worker action dispatch failed") end
        return true
    end
    local function targetParts(model)
        local cached = state.targets[model]
        if type(cached) == "table" and cached.part and cached.part.Parent and cached.part.CanQuery ~= false then return cached.part end
        local part = model:IsA("Model") and model.PrimaryPart
        if not part or part.CanQuery == false then
            part = nil
            for _, obj in ipairs(model:GetDescendants()) do
                if obj:IsA("BasePart") and obj.CanQuery ~= false then part = obj break end
            end
        end
        if part then state.targets[model] = {part = part} end
        return part
    end
    local function point(part, origin)
        local p = part.CFrame:PointToObjectSpace(origin)
        local half = part.Size * 0.5
        return part.CFrame:PointToWorldSpace(Vector3.new(math.clamp(p.X, -half.X, half.X),
            math.clamp(p.Y, -half.Y, half.Y), math.clamp(p.Z, -half.Z, half.Z)))
    end
    local function aim(model, origin)
        local primary = targetParts(model)
        if not primary then return nil end
        local cached = state.targets[model]
        if not cached.faces or os.clock() >= (cached.facesAt or 0) then
            cached.faces = {}
            local signature = {}
            for _, obj in ipairs(model:GetDescendants()) do
                if obj:IsA("BasePart") and obj.CanQuery ~= false then
                    table.insert(cached.faces, obj)
                    table.insert(signature, targetId(obj) .. ":" .. tostring(obj.Position) .. ":" .. tostring(obj.Size))
                end
            end
            cached.facesAt, cached.geometry = os.clock() + 1, table.concat(signature, ";")
        end
        local best, position, distance
        for _, face in ipairs(cached.faces) do
            if face.Parent and face.CanQuery ~= false then
                local p = point(face, origin)
                -- Aim inside the visible face instead of at a wedge's empty
                -- bounding-box corner. DropRoot is deliberately not queryable.
                p = p + (face.Position - p) * 0.15
                local d = (p - origin).Magnitude
                if not best or d < distance then best, position, distance = face, p, d end
            end
        end
        return best, position
    end
    local function refreshCombat()
        if (state.combatAt or 0) > os.clock() then return end
        state.combatAt, state.combat, state.enemies = os.clock() + 0.2, false, {}
        local world = state.lab and state.lab:FindFirstChild("WorldEvent")
        if world then
            -- Scientists must never depend on the rotating shell discovery
            -- cursor. This small event subtree is separate from egg geometry.
            for _, model in ipairs(world:GetDescendants()) do
                if model:IsA("Model") and (model:GetAttribute("Health") or 0) > 0
                    and (model:GetAttribute("EventScientist") == true
                    or model:GetAttribute("CreatureLimb") == true and model:GetAttribute("State") ~= "Retract") then
                    state.combat, state.enemies[model] = true, true
                    if not state.targets[model] then index(model) end
                end
            end
        end
    end
    local function ray(position, head, guardian, maxRange)
        local direction = position - head.Position
        if direction.Magnitude < 0.01 then return nil end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local excludes = {player.Character}
        local fx = workspace:FindFirstChild("EggLocalEffects")
        if fx then table.insert(excludes, fx) end
        params.FilterDescendantsInstances = excludes
        local directionWithMargin = direction.Unit * math.min(direction.Magnitude + 0.2, maxRange or math.huge)
        local result = workspace:Raycast(head.Position, directionWithMargin, params)
        if guardian then result = guardian.Raycast(state.lab:FindFirstChild("Egg"), player, head.Position, directionWithMargin, result) end
        return result
    end
    local function contact(target, position, head, range, guardian)
        local first = ray(position, head, guardian, range)
        local function matches(result)
            return result and (result.Position - head.Position).Magnitude <= range
                and (result.Instance == target or result.Instance:IsDescendantOf(target))
        end
        if matches(first) then return first end
        -- Mesh/wedge bounding boxes contain empty space. Probe actual part
        -- centers as well; every ray remains capped at native tool reach.
        local cached = state.targets[target]
        local tried = 0
        for _, face in ipairs(type(cached) == "table" and cached.faces or {}) do
            if face.Parent and face.CanQuery ~= false then
                local result = ray(face.Position, head, guardian, range)
                if matches(result) then return result end
                tried += 1
                if tried >= 4 then break end
            end
        end
        return first
    end
    local function approachPosition(target, position, head, root, hum, range, guardian)
        -- A short, bounded search for a verified attack ray. Distance alone
        -- cannot prove arrival: a wedge, guardian or wall may still block it.
        local offset = head.Position - root.Position
        local radial = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
        radial = radial.Magnitude > 0.1 and radial.Unit or Vector3.new(1, 0, 0)
        local params = RaycastParams.new()
        params.FilterType, params.RespectCanCollide = Enum.RaycastFilterType.Exclude, true
        params.FilterDescendantsInstances = {player.Character, target}
        local best, score
        for level = 1, 2 do
            for i = 0, 7 do
                local a = i * math.pi / 4
                local dir = Vector3.new(radial.X * math.cos(a) - radial.Z * math.sin(a), 0,
                    radial.X * math.sin(a) + radial.Z * math.cos(a))
                local goal = Vector3.new(position.X, level == 1 and root.Position.Y or position.Y - offset.Y, position.Z)
                    + dir * math.max(2, range * 0.65)
                local floor = workspace:Raycast(goal + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), params)
                local air = true
                if floor and floor.Normal.Y > 0.65 then
                    local grounded = floor.Position + Vector3.new(0, hum.HipHeight + root.Size.Y * 0.5, 0)
                    if (grounded + offset - position).Magnitude < range then goal, air = grounded, false end
                end
                if (goal - root.Position).Magnitude > 1.5 then
                    local result = contact(target, position, {Position = goal + offset}, range, guardian)
                    if result and (result.Instance == target or result.Instance:IsDescendantOf(target))
                        and (result.Position - goal - offset).Magnitude <= range
                        and (not result.Guardian or (result.Distance or 1) > 0.5) then
                        local value = (goal - root.Position).Magnitude + (air and 10 or 0)
                        if not score or value < score then best, score = {target = target, goal = goal, air = air, at = os.clock()}, value end
                    end
                end
            end
        end
        return best
    end
    local function hitFingerprint(target, family)
        local cached = state.targets[target]
        local geometry = target:GetAttribute("HP") ~= nil and type(cached) == "table" and cached.geometry or ""
        return tostring(target:GetAttribute("HP") or target:GetAttribute("Health")) .. ":"
            .. tostring(target:GetAttribute("Quantity")) .. ":" .. tostring(family) .. ":" .. tostring(player:GetAttribute("UnlockedLayer") or 1)
            .. ":" .. tostring(geometry)
    end
    local function hit(target, result, family, cooldown, eventTarget)
        if not result or not result.Instance then return false end
        local p = state.pending.hit
        if p then
            if not p.target.Parent or (finite(p.hp) and finite(p.target:GetAttribute("HP") or p.target:GetAttribute("Health"))
                and (p.target:GetAttribute("HP") or p.target:GetAttribute("Health")) < p.hp)
                or (finite(p.quantity) and (p.target:GetAttribute("Quantity") or 0) < p.quantity) then
                state.pending.hit = nil success(p.key)
            elseif os.clock() - p.at > 4 then
                fail(p.key, p.fingerprint, "No MiningResult or target progress")
                state.pending.hit = nil
            end
            if state.pending.hit then return false end
        end
        if (state.hitAt or 0) > os.clock() then return false end
        local ready = player:GetAttribute("ToolReadyAt_" .. family) or 0
        if workspace:GetServerTimeNow() < ready then return false end
        local key = "hit:" .. targetId(target)
        local hp = target:GetAttribute("HP") or target:GetAttribute("Health")
        local fp = hitFingerprint(target, family)
        if not eligible(key, fp) then return false end
        state.serial += 1
        local head = player.Character and player.Character:FindFirstChild("Head")
        local meta = eventTarget and head and {At = workspace:GetServerTimeNow(), Origin = head.Position} or nil
        if send(refs.action, "Hit", result.Instance, result.Position, state.serial, meta) then
            state.pending.hit = {serial = state.serial, at = os.clock(), target = target, key = key, fingerprint = fp, hp = hp, quantity = target:GetAttribute("Quantity")}
            state.hitAt = os.clock() + cooldown
            return true
        end
        return false
    end
    local function explosiveReady(config)
        if not owns("Dynamite", config) then return false end
        local now = workspace:GetServerTimeNow()
        local charges = player:GetAttribute("ToolCharges_Dynamite")
        local ready, reloadAt = player:GetAttribute("ToolReadyAt_Dynamite"), player:GetAttribute("ToolReloadAt_Dynamite") or 0
        if not finite(charges) or not finite(ready) or not finite(reloadAt) then
            app.status.explosive = "Waiting for native explosive charge/cooldown state"
            return false
        end
        local e = state.explosive
        if not e then e = {left = charges, seen = charges, nextAt = ready, reloadAt = reloadAt, seenReady = ready, seenReload = reloadAt} state.explosive = e end
        if ready ~= e.seenReady or reloadAt ~= e.seenReload then
            -- Replicated recharge incorporates Quick Reload and evolution/stat
            -- changes. It supersedes the conservative local dispatch estimate.
            e.nextAt, e.reloadAt = math.max(ready, (e.lastSent or -math.huge) + 0.2), reloadAt
            e.seenReady, e.seenReload = ready, reloadAt
        end
        if charges ~= e.seen then
            e.left = charges > e.seen and charges or math.min(e.left, charges)
            e.seen = charges
        end
        if now >= e.reloadAt and now >= e.nextAt and e.left == 0 and charges > 0 then e.left = charges end
        local p = state.pending.blast
        if p and os.clock() - p.at > 4 then state.pending.blast = nil end
        app.status.explosive = "Explosive charges=" .. e.left .. "; ready in " .. math.ceil(math.max(0, ready - now, e.nextAt - now)) .. "s"
        return not state.pending.blast and not state.pending.hit and e.left > 0 and now >= ready
            and now >= reloadAt and now >= e.nextAt and now >= (state.blastRetryAt or 0)
    end
    local function throwExplosive(target, result, config)
        if not explosiveReady(config) or not result or not result.Instance or not equipped("Dynamite") then return false end
        local _, _, head = character()
        if not head or (result.Position - head.Position).Magnitude > reach("Dynamite", config) then return false end
        local e, now = state.explosive, workspace:GetServerTimeNow()
        state.serial += 1
        local fp = hitFingerprint(target, "Dynamite")
        -- Own a separate receipt: a fuse or lost blast receipt must not block
        -- ordinary mining, collection, selling or emergency combat.
        state.pending.blast = {serial = state.serial, at = os.clock(), target = target, fingerprint = fp}
        if not send(refs.action, "Hit", result.Instance, result.Position, state.serial, nil) then state.pending.blast = nil return false end
        e.left = math.max(0, e.left - 1)
        e.lastSent = now
        local m = mechanics("Dynamite")
        local gap = math.max(0.2, m and m.UseGap or 0.3)
        local cooldown = player:GetAttribute("ToolCooldown_Dynamite") or config.ToolById.Dynamite.Cooldown
        e.nextAt = now + (e.left > 0 and gap or math.max(gap, cooldown))
        if e.left == 0 then e.reloadAt = e.nextAt end
        state.hitAt = os.clock() + 0.2
        return true
    end
    local function shoot(target, result, gun)
        local _, root, head = character()
        local ballistics = module("BreakTheEgg", "GunBallistics")
        local g = gunState(gun)
        if not root or not head or not g or not ballistics or not equipped("Gun") then return false end
        local now, reloadAt = workspace:GetServerTimeNow(), player:GetAttribute("GunReloadAt") or 0
        if g.reload or reloadAt > now then return false end
        if g.ammo <= 0 then
            if os.clock() >= (g.reloadRetryAt or 0) then
                if send(refs.action, "GunReload") then
                    g.reload = {at = os.clock()}
                    g.reloadTries = (g.reloadTries or 0) + 1
                    g.reloadRetryAt = os.clock() + math.max(3, gun.Reload + 1)
                end
            end
            return false
        end
        if os.clock() < g.nextAt or os.clock() - (state.gunEquipAt or -math.huge) < 0.16 + (gun.SpinUp or 0) then return false end
        if not result or (result.Position - head.Position).Magnitude > gun.Range
            or (result.Instance ~= target and not result.Instance:IsDescendantOf(target)) then return false end
        local direction = result.Position - head.Position
        if direction.Magnitude < 0.01 then return false end
        -- Aim from our actual head. Rotation changes no position, tween goal or
        -- evasion ownership, so firing cannot stop a dodge to chase an enemy.
        local facing = Vector3.new(direction.X, 0, direction.Z)
        if facing.Magnitude > 0.01 then root.CFrame = CFrame.lookAt(root.Position, root.Position + facing) end
        local folder = folderAt("BreakTheEgg")
        local spreadMul = folder and folder:GetAttribute("GunSpreadMul") or 1
        local dirs = ballistics.Spread(direction.Unit, gun.Spread * spreadMul, nil, gun.Pellets)
        local params = ballistics.Params(state.lab)
        local egg, guardian = state.lab:FindFirstChild("Egg"), module("BreakTheEgg", "LayerGuardian")
        local unlocked = player:GetAttribute("UnlockedLayer") or 1
        local foes = {}
        for obj in pairs(state.enemies or {}) do if obj.Parent and (obj:GetAttribute("Health") or 0) > 0 then table.insert(foes, obj) end end
        local claims = {}
        local pierce = gun.Class == "Explosive" and 1 or math.max(0, math.floor((gun.Pierce or 0) + (folder:GetAttribute("GunPierce") or 0))) + 1
        local bounces = gun.Class == "Explosive" and 0 or math.max(0, math.floor((gun.Ricochet or 0) + (folder:GetAttribute("GunRicochet") or 0)))
        for pellet, dir in ipairs(dirs) do
            local trace = ballistics.Trace(head.Position, dir, {Range = gun.Range, Bounces = bounces, Params = params,
                Guardian = egg and guardian and function(origin, delta, actual) return guardian.Raycast(egg, player, origin, delta, actual) end or nil,
                OnHit = function(actual)
                    local instance, parent = actual.Instance, actual.Instance and actual.Instance.Parent
                    if instance == egg or parent and parent:GetAttribute("EggCore") then return "stop" end
                    if parent and egg and parent:GetAttribute("HP") and parent:IsDescendantOf(egg) then
                        local layer = parent:GetAttribute("Layer") or 1
                        return (layer > unlocked or guardian.Covers(egg, layer, player)) and "stop" or "bounce"
                    end
                    return ballistics.Passable(instance) and "pass" or "bounce"
                end})
            local remaining, claimed = table.clone(foes), 0
            local foeParams = RaycastParams.new()
            foeParams.FilterType = Enum.RaycastFilterType.Include
            for segment = 1, #trace.Points - 1 do
                local from, to = trace.Points[segment], trace.Points[segment + 1]
                while claimed < pierce and #remaining > 0 and (to - from).Magnitude >= 0.05 do
                    foeParams.FilterDescendantsInstances = remaining
                    local actual = workspace:Spherecast(from, 0.5, (to - from).Unit * math.min(1000, (to - from).Magnitude), foeParams)
                    if not actual then break end
                    local index
                    for i, foe in ipairs(remaining) do if actual.Instance == foe or actual.Instance:IsDescendantOf(foe) then index = i break end end
                    if not index then break end
                    table.remove(remaining, index)
                    claimed += 1
                    table.insert(claims, {Part = actual.Instance, Point = actual.Position, Pellet = pellet, Segment = segment})
                    from = actual.Position
                end
                if claimed >= pierce then break end
            end
        end
        state.gunSerial = (state.gunSerial or 10000000) + 1
        if not send(refs.action, "Shoot", {Id = state.gunSerial, At = now, Gun = gun.Id, Origin = head.Position, Dirs = dirs, Claims = claims}) then return false end
        g.ammo -= 1
        g.shots[state.gunSerial] = os.clock()
        local rate = (folder:GetAttribute("GunRate") or 1) * gun.FireRate
        local interval = 1 / math.max(0.05, rate)
        if gun.Mode == "Burst" then
            g.burst = (g.burst > 0 and g.burst or gun.Burst) - 1
            if g.burst == 0 then interval = math.max(interval, gun.BurstGap) end
        end
        g.nextAt = os.clock() + interval
        return true
    end
    local function chests(config, evolution)
        if not app.settings.chests or not refs.chest then return false end
        -- Use the actual native button, including a picker opened before this
        -- script attached. Its callback already owns the correct token/revision.
        if player:GetAttribute("ChestPickerOpen") == true and player:GetAttribute("ClaimAllUpgrades") ~= false then
            local pg = player:FindFirstChildOfClass("PlayerGui")
            local gui = pg and pg:FindFirstChild("BlessingGui")
            local button = gui and gui:FindFirstChild("ClaimAll", true)
            if button and button:IsA("GuiButton") and gui.Enabled ~= false and button.Visible ~= false and type(firesignal) == "function" then
                local n = app.nativeClaim
                if not n or n.button ~= button then n = {button = button, tries = 0, at = 0} app.nativeClaim = n end
                if n.tries < 3 and n.at <= os.clock() then
                    n.tries, n.at = n.tries + 1, os.clock() + 1.5
                    local ok, err = pcall(firesignal, button.Activated)
                    if not ok then app:note("Native Claim All: " .. tostring(err)) end
                    app.status.chests = "Pressing native Claim All"
                elseif n.tries >= 3 and n.at <= os.clock() then
                    app.status.chests = "Native Claim All has not closed; waiting for chest receipt"
                end
                return true
            end
        else app.nativeClaim = nil end
        local p = state.pending.chest
        if p then
            if os.clock() - p.at > 5 and not p.resync then
                p.resync = true
                send(refs.chest, "Ready")
                app:note("Chest replay requested for token " .. tostring(p.id))
            end
            if p.action == "Open" and os.clock() - p.at > 9 then
                -- Opening is idempotent by token. Choices remain unresolved until
                -- Chosen/ChosenAll or a replaced revision; never blindly choose twice.
                fail("chest:" .. tostring(p.id), p.fingerprint, "Open did not produce an offer")
                state.pending.chest = nil
            end
            app.status.chests = p.action .. " pending for token " .. tostring(p.id)
            return p.action == "Open" and not p.startedAt
        end
        for id, offer in pairs(state.offers) do
            if not state.done[id] then
                local fp = tostring(offer.Revision) .. ":" .. tostring(player:GetAttribute("ClaimAllUpgrades"))
                if eligible("chest:" .. tostring(id), fp) then
                    local action, args = "ClaimAll", nil
                    if player:GetAttribute("ClaimAllUpgrades") ~= false then
                        args = table.pack(id, nil, offer.Revision)
                    else
                        app.status.chests = "Claim All ownership was rejected by replication"
                        return false
                    end
                    if args and send(refs.chest, action, table.unpack(args, 1, args.n)) then
                        state.pending.chest = {id = id, action = action, at = os.clock(), fingerprint = fp, revision = offer.Revision}
                        app.status.chests = "Claiming all chest rewards"
                        return false
                    end
                end
            end
        end
        local _, root = character()
        if not root then return false end
        local selected, distance
        for id, item in pairs(state.chests) do
            if not state.done[id] and not state.offers[id] and (not finite(item.ExpiresAt) or item.ExpiresAt > workspace:GetServerTimeNow()) then
                local d = (root.Position - item.CFrame.Position).Magnitude
                if eligible("chest:" .. tostring(id), "open") and (not selected or d < distance) then selected, distance = item, d end
            end
        end
        if selected then
            local folder = workspace:FindFirstChild("PersonalRewardChests")
            local model, prompt
            if folder then
                for _, child in ipairs(folder:GetChildren()) do
                    if child:GetAttribute("ChestToken") == selected.Id and child:GetAttribute("OwnerUserId") == player.UserId then
                        model, prompt = child, child:FindFirstChild("OpenUpgradeChest", true)
                        break
                    end
                end
            end
            if not model or not prompt then app.status.chests = "Chest model streaming/landing" return false end
            if not prompt.Enabled then app.status.chests = "Chest landing; prompt not ready" return false end
            local arrived, reason = move("chest", "chest:" .. tostring(selected.Id), model, selected.CFrame.Position, 9)
            app.status.chests = reason or "Opening landed chest"
            if arrived and send(refs.chest, "Open", selected.Id) then
                state.pending.chest = {id = selected.Id, action = "Open", at = os.clock(), fingerprint = "open"}
            end
            return true
        end
        app.status.chests = "No ready personal chests"
        return false
    end
    -- BossSceneHazards reads these same replicated records. At is impact time,
    -- so the warning begins at At-Warn, not At+Warn. No cosmetic FX scanning.
    local function flat(v) return Vector3.new(v.X, 0, v.Z) end
    local function number(a, k, default)
        return finite(a[k]) and a[k] or default
    end
    local function vector(v)
        return typeof(v) == "Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z)
    end
    local function hazards(config, boss, now)
        local list = {}
        local folder = state.lab:FindFirstChild("BossHazards")
        local defaults = boss.Hazard
        local height = state.lab:GetAttribute("BossEggHeight")
        if not finite(height) then height = boss.EggHeight(state.lab:GetAttribute("BossTier") or 1) end
        local function add(a, obj)
            local kind, at = a.Kind, a.At
            if not finite(at) then return end
            local def = defaults[kind == "Lane" and "Lanes" or kind == "Glob" and "Goo" or kind] or {}
            local h = {kind = kind, object = obj, at = at, warn = math.max(0, number(a, "Warn", def.Warn or def.Charge or 0))}
            h.duration = math.max(0, number(a, "Duration", def.Duration or 0))
            if kind == "Lane" and vector(a.From) and vector(a.To) then
                h.from, h.to, h.radius = flat(a.From), flat(a.To), math.max(0, number(a, "Width", def.Width or 7)) * 0.5
                h.finish = at + math.clamp(h.duration > 0 and h.duration or 0.45, 0.3, 2) + 0.2
            elseif (kind == "Glob" or kind == "Puddle" or kind == "Grab" or kind == "Slam") and vector(a.Point) then
                h.point, h.radius = flat(a.Point), math.max(0, number(a, "Radius", def.Radius or (kind == "Puddle" and defaults.Goo.Puddle or kind == "Slam" and boss.Slam.Radius or 5)))
                h.finish = kind == "Puddle" and number(a, "Until", at + (h.duration > 0 and h.duration or defaults.Goo.PuddleSeconds))
                    or kind == "Grab" and at + math.max(2.6, h.duration + 0.6)
                    or at + (kind == "Glob" and 0.9 or 0.35)
                if kind == "Grab" then h.radius = math.max(h.radius, defaults.Grab.WhipRadius) end
            elseif kind == "Quake" and vector(a.Center) then
                h.point = flat(a.Center)
                h.ground = math.max(config.EggGroundY, a.Center.Y)
                h.height = math.max(0, number(a, "Height", def.Height))
                h.r0 = math.max(0, number(a, "R0", height * boss.EggWidthRatio * 0.5 * 0.6))
                h.speed, h.max = math.max(1, number(a, "Speed", def.Speed)), math.max(0, number(a, "MaxRadius", def.MaxRadius))
                h.radius = math.max(0, number(a, "Thick", def.Thick)) * 0.5
                h.finish = at + math.max(0, (h.max - h.r0) / h.speed) + 0.4
            elseif kind == "Beam" and vector(a.Center) and finite(a.A0) and finite(a.A1) then
                h.point, h.a0, h.a1 = flat(a.Center), a.A0, a.A1
                h.radius, h.length = math.max(0, number(a, "Width", def.Width)) * 0.5, math.max(0, number(a, "Length", def.Length))
                h.duration = h.duration > 0 and h.duration or def.Duration
                h.finish = at + h.duration + 0.3
            else return end -- Blackout changes visibility, not safe geometry.
            if now >= at - h.warn - 0.15 and now <= h.finish then table.insert(list, h) end
        end
        if folder then for _, obj in ipairs(folder:GetChildren()) do add(obj:GetAttributes(), obj) end end
        local slamAt, slamPoint = state.lab:GetAttribute("BossSlamAt"), state.lab:GetAttribute("BossSlamPoint")
        if finite(slamAt) and vector(slamPoint) then
            add({Kind = "Slam", At = slamAt, Point = slamPoint, Radius = boss.Slam.Radius, Warn = boss.Slam.Warn}, state.lab)
        end
        state.hazardCount = #list
        -- Boss scientists can damage us without a floor warning. Keep outside
        -- the exported melee reach while discrete mining-tool hits continue.
        state.meleeCount = 0
        if state.lab:GetAttribute("BossPhase") == "Wave" then
            for enemy in pairs(state.enemies or {}) do
                local part = enemy.Parent and enemy:GetAttribute("EventScientist") == true
                    and (enemy:GetAttribute("Health") or 0) > 0 and targetParts(enemy)
                if part then
                    table.insert(list, {kind = "Melee", object = enemy, at = now, warn = 0,
                        point = flat(part.Position), radius = boss.WaveTuning.Reach, finish = math.huge})
                    state.meleeCount += 1
                end
            end
        end
        return list, height
    end
    local function segmentDistance(pos, from, to)
        local d = to - from
        local alpha = math.clamp((pos - from):Dot(d) / math.max(0.001, d:Dot(d)), 0, 1)
        return (pos - (from + d * alpha)).Magnitude
    end
    local function attackDuringEvasion(config, evolution, triggerOnly)
        local _, _, head = character()
        if not head then return end
        local family, score, cooldown
        -- Dodge travel releases held inputs. Use tools which can deliver a
        -- discrete strike while moving instead of selecting an unheld drill.
        for _, name in ipairs({"Pickaxe", "HandDrill"}) do
            if owns(name, config) then
                local value, interval = power(name, player:GetAttribute("Evolution_" .. name) or 1, config, evolution, "event")
                if value and interval and (not score or value > score) then family, score, cooldown = name, value, interval end
            end
        end
        if flameOwned(config) then
            family = "HandDrill"
            local _, interval = power(family, 3, config, evolution, "event")
            cooldown = interval
        end
        if not family then return false end
        local gun = gunUsable()
        if triggerOnly and not gun and not flameOwned(config) then return false end
        if gun then family, cooldown = "Gun", 0 end
        local best, result, distance
        for obj in pairs(state.enemies or {}) do
            if obj.Parent and (obj:GetAttribute("Health") or 0) > 0
                and eligible("hit:" .. targetId(obj), hitFingerprint(obj, family)) then
                local _, pos = aim(obj, head.Position)
                if pos and (pos - head.Position).Magnitude <= reach(family, config) then
                    local contactResult = contact(obj, pos, head, reach(family, config))
                    if contactResult and contactResult.Instance:IsDescendantOf(obj)
                        and (contactResult.Position - head.Position).Magnitude <= reach(family, config) then
                        local d = (contactResult.Position - head.Position).Magnitude
                        local priority = obj:GetAttribute("Variant") == "Medic" and 100 or 0
                        local value = priority - d
                        if not best or value > distance then best, result, distance = obj, contactResult, value end
                    end
                end
            end
        end
        if not best and (gun or state.lab:GetAttribute("BossPhase") == "Core") then
            for _, obj in ipairs(state.targetList) do
                if obj.Parent and obj:GetAttribute("EggCore") == true and (obj:GetAttribute("HP") or 0) > 0
                    and eligible("hit:" .. targetId(obj), hitFingerprint(obj, family)) then
                    local _, pos = aim(obj, head.Position)
                    local range = reach(family, config)
                    local actual = pos and contact(obj, pos, head, range)
                    if actual and actual.Instance:IsDescendantOf(obj) and (actual.Position - head.Position).Magnitude <= range then
                        best, result = obj, actual break
                    end
                end
            end
        end
        -- The evasion route keeps movement ownership. Attacking an enemy already
        -- in reach doesn't rotate or replace that route, or chase an unsafe one.
        if best then
            local hp = best:GetAttribute("HP") or best:GetAttribute("Health")
            local watch = state.triggerWatch
            if not watch or watch.target ~= best or watch.family ~= family or watch.hp ~= hp then
                state.triggerWatch = {target = best, family = family, hp = hp, at = os.clock()}
            elseif os.clock() - watch.at > 5 then
                fail("hit:" .. targetId(best), hitFingerprint(best, family), "Trigger target made no damage progress; trying another enemy")
                state.triggerWatch = nil
                return false
            end
            if equip(family, config) then
                if gun then shoot(best, result, gun) else hit(best, result, family, cooldown, best:GetAttribute("EggCore") ~= true) end
            end
            -- Keep combat equipment through spin-up/reload/receipt gaps. This
            -- owns equipment only; shop/dodge travel continues independently.
            return true
        end
        return false
    end
    local function clearance(h, position, at, margin, warning)
        if at > h.finish or at < h.at - (warning and h.warn or 0.1) then return math.huge end
        local pos = flat(position)
        if h.kind == "Lane" then return segmentDistance(pos, h.from, h.to) - h.radius - margin end
        if h.kind == "Quake" then
            if h.safeY and position.Y >= h.safeY then return math.huge end
            if at < h.at then return math.huge end
            local radius = h.r0 + (at - h.at) * h.speed
            if radius > h.max then return math.huge end
            return math.abs((pos - h.point).Magnitude - radius) - h.radius - margin
        end
        if h.kind == "Beam" then
            -- Reserve the entire advertised sweep. Staying beyond either edge
            -- is safer than chasing the currently displayed beam direction.
            local delta = pos - h.point
            local r = delta.Magnitude
            if r > h.length + margin then return r - h.length - margin end
            local middle = (h.a0 + h.a1) * 0.5
            local angle = math.atan2(delta.Z, delta.X)
            local offset = math.atan2(math.sin(angle - middle), math.cos(angle - middle))
            local gap = math.abs(offset) - math.abs(h.a1 - h.a0) * 0.5
            return gap <= 0 and -h.radius - margin or r * math.sin(math.min(math.pi * 0.5, gap)) - h.radius - margin
        end
        return (pos - h.point).Magnitude - h.radius - margin
    end
    local function quakeFlight(config, boss, root, hum, now, list)
        local q = state.quakeFlight
        if q and (q.root ~= root or now > q.finish) then q = nil end
        local contactAt = math.huge
        local margin = math.max(root.Size.X, root.Size.Z) * 0.5 + boss.HazardBody + 0.65
        for _, h in ipairs(list) do
            if h.kind == "Quake" then
                -- Keep the feet, not just the root, above the exported wave
                -- height. Retain this floor until the entire ring expires so
                -- a lateral exit cannot descend across a second crossing.
                h.safeY = h.ground + h.height + hum.HipHeight + root.Size.Y * 0.5 + 1.5
                if not q then q = {root = root, minY = h.safeY, finish = h.finish + 0.2,
                    y = root.Position.Y, progressAt = now} end
                q.minY, q.finish = math.max(q.minY, h.safeY), math.max(q.finish, h.finish + 0.2)
                local radius = (flat(root.Position) - h.point).Magnitude
                local arrival = h.at + math.max(0, (radius - h.r0 - h.radius - margin) / h.speed)
                local passed = h.at + (radius - h.r0 + h.radius + margin) / h.speed
                if radius <= h.max + margin and radius >= h.r0 - h.radius - margin and now <= passed then
                    contactAt = math.min(contactAt, arrival)
                end
            end
        end
        state.quakeFlight = q
        if not q then return nil end
        q.goalY = math.max(q.minY, q.goalY or root.Position.Y)
        if root.Position.Y > q.y + 0.1 then q.y, q.progressAt = root.Position.Y, now end
        local lift = q.minY - root.Position.Y
        if lift > 0 and (contactAt - now <= lift / math.max(1, hum.WalkSpeed) + 0.18 or now - q.progressAt > 0.35) then
            -- A late warning or frozen tween cannot wait for the ordinary
            -- three-second stall timeout. One bounded vertical correction
            -- reaches this wave's clearance; subsequent frames just hover.
            app:release()
            if app:updateFlight(root) then
                local goal = Vector3.new(root.Position.X, q.minY, root.Position.Z)
                root.CFrame = CFrame.lookAt(goal, goal + Vector3.new(0, 0, -1))
                root.AssemblyLinearVelocity = Vector3.new()
                q.y, q.progressAt = q.minY, now
                state.evadeGoal, state.evadeApproach = nil, nil
                state.stats.quakeLifts = (state.stats.quakeLifts or 0) + 1
            end
        end
        return q
    end
    local function evasion(config)
        local _, root, _, hum = character()
        if not root or root.Anchored or hum.PlatformStand then return false end
        local boss = module("BreakTheEgg", "BossConfig")
        if not boss then return false end
        if (state.knockUntil or 0) > os.clock() then
            app:release(false)
            app.status.farm = "Boss knockback · letting native motion settle"
            return true
        end
        local now = workspace:GetServerTimeNow()
        local list, height = hazards(config, boss, now)
        local margin = math.max(root.Size.X, root.Size.Z) * 0.5 + boss.HazardBody + 0.65
        local quake = quakeFlight(config, boss, root, hum, now, list)
        local function danger(pos, at, warning)
            local worst = math.huge
            for _, h in ipairs(list) do
                worst = math.min(worst, clearance(h, pos, at, margin, warning))
            end
            return worst
        end
        local center = flat(config.EggCenter)
        local bodyRadius = height * boss.EggWidthRatio * 0.5 + margin
        local startRadius = (flat(root.Position) - center).Magnitude
        local phase = state.lab:GetAttribute("BossPhase")
        local bodyActive = phase == "Wave" or phase == "Intermission"
        local need = danger(root.Position, now, true) < 0 or bodyActive and startRadius < bodyRadius
        local m = app.move
        if #list > 0 and m and m.lane == "evade" and state.evadeGoal and (root.Position - state.evadeGoal).Magnitude > 0.5 then need = true end
        if not need and m and m.lane ~= "evade" then
            local dest, speed = m.destination, math.max(1, hum.WalkSpeed)
            local d = dest - root.Position
            for i = 1, 12 do
                local dt = i * 0.1
                local pos = root.Position + d * math.min(1, dt * speed / math.max(0.01, d.Magnitude))
                if danger(pos, now + dt, true) < 0 then need = true break end
            end
        end
        if not need and quake then
            lease("Bucket", false) lease("Drill", false)
            local goal = Vector3.new(root.Position.X, math.max(root.Position.Y, quake.goalY), root.Position.Z)
            success("move:boss-quake")
            move("evade", "boss-quake", state.lab, goal, 0.05, {goal = goal, air = true})
            app:updateFlight(root)
            app.status.farm = "Dodging shockwave · flying above ring"
            return true
        end
        if not need then
            if app.move and app.move.lane == "evade" then app:release() end
            state.evadeGoal, state.evadeApproach = nil, nil
            return false
        end
        local params = RaycastParams.new()
        params.FilterType, params.RespectCanCollide = Enum.RaycastFilterType.Exclude, true
        local excludes = {player.Character}
        local eggBody = state.lab:FindFirstChild("Egg")
        if bodyActive and startRadius < bodyRadius and eggBody then table.insert(excludes, eggBody) end
        local fx = workspace:FindFirstChild("EggLocalEffects")
        if fx then table.insert(excludes, fx) end
        params.FilterDescendantsInstances = excludes
        local bodyNear = startRadius < bodyRadius + 35
        local function route(goal)
            -- Mining recovery may leave us well above ground. Find an actual
            -- floor and plan the descent rather than rejecting every exit.
            if quake then
                goal = Vector3.new(goal.X, math.max(root.Position.Y, quake.goalY), goal.Z)
            else
                local floor = workspace:Raycast(goal + Vector3.new(0, 5, 0), Vector3.new(0, -200, 0), params)
                if not floor or floor.Normal.Y < 0.65 then return nil end
                goal = floor.Position + Vector3.new(0, hum.HipHeight + root.Size.Y * 0.5, 0)
            end
            local delta = goal - root.Position
            local distance = delta.Magnitude
            local duration = distance / math.max(1, hum.WalkSpeed)
            local score, worst = distance, math.huge
            local previousRadius = startRadius
            for i = 1, 16 do
                local fraction = i / 16
                local pos = root.Position + delta * fraction
                local radius = (flat(pos) - center).Magnitude
                if bodyNear and radius < bodyRadius then
                    -- Being inside already must not prohibit escape. Require
                    -- continuous outward progress until the body is cleared.
                    if startRadius >= bodyRadius or radius < previousRadius + 0.01 then return nil end
                end
                previousRadius = radius
                local c = danger(pos, now + duration * fraction, false)
                worst = math.min(worst, c)
                -- Weight exposure by travel time. Fixed penalties per sample
                -- made long retreats look safer and abandoned attack range.
                if c < 0 then score += (500 + (-c) * 100) * duration / 16 end
            end
            if bodyNear and (flat(goal) - center).Magnitude < bodyRadius then return nil end
            -- Reject unsafe destinations even when every alternative scores
            -- poorly. Include the announced impact after arrival as well.
            for _, h in ipairs(list) do
                if clearance(h, goal, math.max(now + duration, h.at), margin, true) < 0 then return nil end
            end
            local wall = workspace:Raycast(root.Position, delta, params)
            if wall and wall.Normal.Y < 0.65 and (wall.Position - root.Position).Magnitude < distance - 0.5 then return nil end
            return score, worst, goal
        end
        local best, bestScore
        -- Keep a previously verified exit while it remains safe. This avoids
        -- alternating sides on symmetric warning geometry every heartbeat.
        local old = state.evadeGoal
        if old then
            local score, worst, goal = route(old)
            if score and worst >= 0 and danger(old, now, true) >= 0 then
                -- Recheck the complete route against current warnings/walls;
                -- keep this exit without rescanning 80 alternatives each tick.
                lease("Bucket", false) lease("Drill", false)
                local approach = {goal = goal, air = math.abs(goal.Y - root.Position.Y) > 4}
                state.evadeGoal, state.evadeApproach = goal, approach
                if not app.move then success("move:boss-evade") end
                local _, reason = move("evade", "boss-evade", state.lab, goal, 0.5, approach)
                app.status.farm = "Dodging boss · verified exit" .. (reason and " · " .. reason or "")
                return true
            end
        end
        for _, radius in ipairs({6, 10, 16, 24, 32, 48, 64}) do
            for i = 0, 15 do
                local angle = i * math.pi * 2 / 16
                local goal = root.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
                local score, _, grounded = route(goal)
                if score and (not bestScore or score < bestScore) then best, bestScore = grounded, score end
            end
        end
        lease("Bucket", false) lease("Drill", false)
        if not best then
            if quake then
                local goal = Vector3.new(root.Position.X, math.max(root.Position.Y, quake.goalY), root.Position.Z)
                state.evadeGoal, state.evadeApproach = nil, nil
                success("move:boss-quake")
                move("evade", "boss-quake", state.lab, goal, 0.05, {goal = goal, air = true})
                app:updateFlight(root)
                app.status.farm = "Shockwave flight · no clear lateral exit"
                return true
            end
            app:release()
            hum.Jump = true
            app.status.farm = "Boss danger · no verified floor exit; jumping"
            return true
        end
        local approach = {goal = best, air = math.abs(best.Y - root.Position.Y) > 4}
        state.evadeGoal, state.evadeApproach = best, approach
        success("move:boss-evade") -- A newly verified exit can recover an earlier frozen route.
        local _, reason = move("evade", "boss-evade", state.lab, best, 0.5, approach)
        app.status.farm = "Dodging boss · " .. tostring(#list) .. " warnings" .. (reason and " · " .. reason or "")
        return true
    end

    local function cartClickPart(cart, origin)
        -- MinecartSeller.CanClick raycasts to the submitted part's CENTRE,
        -- excluding only the character. A ray to a different face/corner does
        -- not establish that the server can accept that submitted instance.
        local parts = {}
        for _, part in ipairs(cart:GetDescendants()) do
            if part:IsA("BasePart") and part.CanQuery ~= false then table.insert(parts, part) end
        end
        table.sort(parts, function(a, b) return (a.Position - origin).Magnitude < (b.Position - origin).Magnitude end)
        local params = RaycastParams.new()
        params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, {player.Character}
        for i = 1, math.min(32, #parts) do
            local part, delta = parts[i], parts[i].Position - origin
            if delta.Magnitude < 0.01 then return part end
            local result = workspace:Raycast(origin, delta.Unit * (delta.Magnitude + 0.5), params)
            if result and result.Instance:IsDescendantOf(cart) then return part end
        end
    end
    local function cartApproach(cart, anchor, root, head, hum, range, rotation, needsRay)
        local offset = head.Position - root.Position
        local radial = Vector3.new(root.Position.X - anchor.Position.X, 0, root.Position.Z - anchor.Position.Z)
        radial = radial.Magnitude > 0.1 and radial.Unit or Vector3.new(1, 0, 0)
        local params = RaycastParams.new()
        params.FilterType, params.RespectCanCollide = Enum.RaycastFilterType.Exclude, true
        params.FilterDescendantsInstances = {player.Character, cart}
        local best, score
        for i = 0, 7 do
            local angle = (i + rotation) * math.pi / 4
            local direction = Vector3.new(radial.X * math.cos(angle) - radial.Z * math.sin(angle), 0,
                radial.X * math.sin(angle) + radial.Z * math.cos(angle))
            local goal = anchor.Position + direction * math.min(6, range * 0.45) - Vector3.new(0, offset.Y, 0)
            local floor = workspace:Raycast(goal + Vector3.new(0, 5, 0), Vector3.new(0, -14, 0), params)
            local air = true
            if floor and floor.Normal.Y > 0.65 then
                local grounded = floor.Position + Vector3.new(0, hum.HipHeight + root.Size.Y * 0.5, 0)
                if (grounded + offset - anchor.Position).Magnitude < range - 0.5 then goal, air = grounded, false end
            end
            if (goal - root.Position).Magnitude > 1 and (goal + offset - anchor.Position).Magnitude < range - 0.5
                and (not needsRay or cartClickPart(cart, goal + offset)) then
                local value = (goal - root.Position).Magnitude + (air and 5 or 0) + i * 0.01
                if not score or value < score then best, score = {target = cart, goal = goal, air = air, at = os.clock()}, value end
            end
        end
        return best
    end
    local function retrySale(route, method, delay)
        route.tries = math.min(8, (route.tries or 0) + 1)
        route.angle = ((route.angle or 0) + 1) % 8
        route.method = method or route.method
        route.reposition, route.approach, route.probeAt = true, nil, nil
        state.saleRoute, state.saleRetryAt = route, os.clock() + (delay or math.min(12, route.tries * 1.5))
        -- Eight reusable movement keys keep repeated failed sales bounded.
        -- A new position is a new attempt, rather than a permanent block on cashout.
        success("move:sale:" .. route.angle)
        app:release()
    end
    local function salePolicy(config)
        local _, _, head = character()
        local count = player:GetAttribute("ShellCount")
        if not head or not finite(count) then return false end
        if count <= 0 then state.bagSince = nil else state.bagSince = state.bagSince or os.clock() end
        if player:GetAttribute("VIPOwned_vip_autoSell") == true then
            app.status.sale = "Native Auto Sell active; no cart detour"
            return false
        end
        local urgent = false
        local dangerRange = math.max(reach("Pickaxe", config), owns("HandDrill", config) and reach("HandDrill", config) or 0) + 4
        for enemy in pairs(state.enemies or {}) do
            if enemy.Parent and (enemy:GetAttribute("Health") or 0) > 0 then
                local _, position = aim(enemy, head.Position)
                if position and (position - head.Position).Magnitude <= dangerRange then urgent = true break end
            end
        end
        if urgent or not app.settings.sell then return false end
        if state.pending.sale then return true end
        if (state.saleRetryAt or 0) > os.clock() then return false end
        local step = player:GetAttribute("EggTutorialStep")
        if count <= 0 or step == 1 or step == 2 then return false end
        local capacity = player:GetAttribute("Capacity")
        local infinite = player:GetAttribute("InfiniteBucket") == true or player:GetAttribute("PermanentInfiniteBucket") == true
        local full = not infinite and finite(capacity) and count >= capacity
        local due = full or count >= 8 or state.needSale or step == 3 and count >= 3
            or state.bagSince and os.clock() - state.bagSince >= 6
        local bucketMechanic = mechanics("Bucket")
        local range = bucketMechanic and bucketMechanic.FlingSellRange or 12
        local selected, distance
        local nativeCart = workspace:FindFirstChild("Minecart")
        for prompt in pairs(state.parts) do
            local anchor = prompt.Parent
            local cart = anchor and anchor.Parent
            if anchor and anchor:IsA("BasePart") and cart and cart == nativeCart
                and prompt.Enabled and cart:GetAttribute("SellBusy") ~= true then
                local d = (head.Position - anchor.Position).Magnitude
                if (not selected or d < distance) then selected, distance = prompt, d end
            elseif not anchor then state.parts[prompt] = nil end
        end
        -- A nearby idle cart can cash out a smaller batch while the bucket is
        -- already equipped, without another mining/bucket equipment switch.
        if selected and (due or equipped("Bucket") and distance <= range) then return true, selected, range end
        return false
    end
    local function inspectRemainingTop(config, guardian, root, head)
        local egg = state.lab:FindFirstChild("Egg")
        if not egg or egg:GetAttribute("EventCarried") or egg:GetAttribute("Completed") then return false end
        local candidate, surface, height
        for model in pairs(state.targets) do
            local hp, layer = model:GetAttribute("HP"), model:GetAttribute("Layer") or 1
            local rejection = app.failures["hit:" .. targetId(model)]
            local rejected = rejection and rejection.rejected == true and rejection.fingerprint == hitFingerprint(model, state.family)
            if model.Parent and finite(hp) and hp > 0 and not model:GetAttribute("EggCore") and model:IsDescendantOf(egg)
                and not rejected and layer <= (player:GetAttribute("UnlockedLayer") or 1) and not guardian.Covers(egg, layer, player) then
                for _, face in ipairs(model:GetDescendants()) do
                    if face:IsA("BasePart") and (not height or face.Position.Y > height) then
                        candidate, surface, height = model, face.Position, face.Position.Y
                    end
                end
            end
        end
        local guardianFailure = app.failures["hit:" .. targetId(egg)]
        local guardianRejected = guardianFailure and guardianFailure.rejected == true and guardianFailure.fingerprint == hitFingerprint(egg, state.family)
        if not candidate and not guardianRejected and (guardian.CanHit(egg, player) or guardian.CoreWaiting(egg, player)) then
            -- Sample the actual native guardian profile from above. This only
            -- chooses an inspection destination; attacks still need real LOS.
            local center = config.EggCenter
            local actual = guardian.Raycast(egg, player, center + Vector3.new(0, 64, 0), Vector3.new(0, -128, 0), nil)
            if actual and actual.Guardian and actual.Instance == egg then candidate, surface = egg, actual.Position end
        end
        if not candidate then return false end
        state.inspections = state.inspections or setmetatable({}, {__mode = "k"})
        local native = guardian.State(egg, player)
        local fp = tostring(candidate:GetAttribute("HP")) .. ":" .. tostring(surface) .. ":"
            .. tostring(player:GetAttribute("UnlockedLayer")) .. ":" .. tostring(egg:GetAttribute("ShellGeneration"))
            .. ":" .. tostring(native and native:GetAttribute("SlimeLayer"))
        local record = state.inspections[candidate]
        if not record or record.fingerprint ~= fp then record = {fingerprint = fp, tries = 0, nextAt = 0} state.inspections[candidate] = record end
        local route = state.inspection
        local continuing = route and route.target == candidate and route.fingerprint == fp
        if not continuing and (record.tries >= 3 or os.clock() < record.nextAt) then return false end
        if not route or route.target ~= candidate or route.fingerprint ~= fp then
            record.tries += 1
            local angle = (record.tries - 1) * math.pi * 2 / 3
            local goal = surface + Vector3.new(math.cos(angle) * 2, 3, math.sin(angle) * 2) - (head.Position - root.Position)
            route = {target = candidate, fingerprint = fp, at = os.clock(), goal = goal}
            state.inspection = route
            success("move:inspect-top")
        end
        local arrived, reason = move("mine", "inspect-top", candidate, surface, 5, {goal = route.goal, air = true})
        app.status.farm = "Inspecting remaining top surface · " .. tostring(reason or "rechecking native attack ray")
        if arrived then
            route.arrivedAt = route.arrivedAt or os.clock()
            local _, pos = aim(candidate, head.Position)
            pos = candidate == egg and surface or pos
            local actual = pos and contact(candidate, pos, head, reach(state.family or "Pickaxe", config), guardian)
            if actual and (actual.Instance == candidate or actual.Instance:IsDescendantOf(candidate))
                and (actual.Position - head.Position).Magnitude <= reach(state.family or "Pickaxe", config) then
                -- Rearm only after a new airborne position proves a valid ray.
                success("hit:" .. targetId(candidate)) success("move:target:" .. targetId(candidate))
                state.target, state.selectAt, state.inspection = nil, 0, nil
                record.nextAt = os.clock() + 15
                return true
            end
        end
        if os.clock() - route.at > 12 or route.arrivedAt and os.clock() - route.arrivedAt > 2 then
            record.nextAt, state.inspection = os.clock() + 15, nil
            if app.move and app.move.key == "inspect-top" then app:release() end
            return false
        end
        return true
    end
    local function farm(config, evolution)
        if not app.settings.farm or not state.lab or not refs.action then return end
        local _, root, head, hum = character()
        if not root then app.status.farm = "Waiting for living character" return end
        local guardian = module("BreakTheEgg", "LayerGuardian")
        local eventTarget = module("BreakTheEgg", "EggEventTarget")
        if not guardian or not eventTarget then app.status.farm = "Loading target rules" return end
        local eggGeometry = state.lab:FindFirstChild("Egg")
        local count, capacity = player:GetAttribute("ShellCount"), player:GetAttribute("Capacity")
        if not finite(count) then app.status.farm = "Waiting for ShellCount" return end
        local infinite = player:GetAttribute("InfiniteBucket") == true or player:GetAttribute("PermanentInfiniteBucket") == true
        local full = not infinite and finite(capacity) and count >= capacity
        local sale = state.pending.sale
        if sale then
            if count < sale.count then
                if sale.cart and sale.method then state.salePreference = {cart = sale.cart, method = sale.method} end
                state.pending.sale, state.saleRoute, state.saleRetryAt = nil, nil, nil
                state.stats.sales = (state.stats.sales or 0) + 1
                success("sale")
            else
                local started = sale.cart and sale.cart.Parent and sale.cart:GetAttribute("SellBusy") == true
                if started then sale.startedAt = sale.startedAt or os.clock() end
                local timeout = sale.startedAt and 12 or 4
                app.status.farm = (sale.startedAt and "Cart busy; waiting for bag decrease" or "Sale sent; waiting for bag decrease")
                    .. " · " .. tostring(sale.method or "Click")
                if os.clock() - sale.at > timeout then
                    state.pending.sale = nil
                    local route = state.saleRoute or {cart = sale.cart, tries = 0}
                    retrySale(route, sale.method == "Prompt" and "Click" or "Prompt")
                    app:note("Sale unchanged; retrying " .. route.method .. " from a different cart position")
                elseif not state.combat then return end
            end
        end
        local tutorialStep = player:GetAttribute("EggTutorialStep")
        local magnet = player:GetAttribute("VIPOwned_vip_magnet") == true
        local visit = state.passiveVisit
        if visit and (not visit.target.Parent or (visit.target:GetAttribute("Quantity") or 0) < visit.quantity) then
            state.passiveVisit, state.passiveNextAt, state.selectAt = nil, os.clock() + 8, 0
            if app.move and app.move.lane == "collect" then app:release(true) end
        end
        if magnet then state.passiveNextAt = state.passiveNextAt or os.clock() + 8 end
        local due, selected, range = salePolicy(config)
        if due and not state.pending.sale then
            if selected then
                local cart = selected.Parent.Parent
                local route = state.saleRoute
                if not route or route.cart ~= cart then
                    local known = state.salePreference
                    local method = known and known.cart == cart and known.method
                        or (type(fireproximityprompt) == "function" and "Prompt" or "Click")
                    route = {cart = cart, tries = 0, angle = 0, method = method}
                    state.saleRoute = route
                end
                if (state.saleRetryAt or 0) > os.clock() then
                    app.status.farm = "Sale retry cooling down · " .. math.ceil(state.saleRetryAt - os.clock()) .. "s"
                    return
                end
                if equip("Bucket", config) then
                    local bucketReleased, drillReleased = lease("Bucket", false), lease("Drill", false)
                    if not bucketReleased or not drillReleased or state.leases.Bucket or state.leases.Drill then
                        app.status.farm = "Releasing held tools before cashout"
                        return
                    end
                    if route.method == "Prompt" and type(fireproximityprompt) ~= "function" then route.method = "Click" end
                    route.angle = route.angle or (route.tries or 0) % 8
                    if route.approach and (not route.approach.anchor or os.clock() - route.approach.at > 10
                        or (selected.Parent.Position - route.approach.anchor).Magnitude > 1) then
                        route.approach = nil
                        if app.move and app.move.lane == "sell" then app:release() end
                    end
                    local clickPart = route.method == "Click" and cartClickPart(cart, head.Position) or nil
                    if math.abs(selected.Parent.Position.Y - head.Position.Y) > range * 0.8 then route.reposition = true end
                    if route.reposition or route.method == "Click" and not clickPart then
                        if (route.probeAt or 0) <= os.clock() and not route.approach then
                            route.probeAt = os.clock() + 1
                            route.approach = cartApproach(cart, selected.Parent, root, head, hum, range, route.angle, route.method == "Click")
                            if route.approach then
                                route.approach.anchor = selected.Parent.Position
                                success("move:sale:" .. route.angle)
                            end
                        end
                    end
                    local arrived, reason = move("sell", "sale:" .. route.angle, cart, selected.Parent.Position, range, route.approach)
                    app.status.farm = reason or "Selling eggshell bag"
                    if not arrived and not app.move then retrySale(route, nil, 2) return end
                    if arrived and selected.Enabled and cart:GetAttribute("SellBusy") ~= true
                        and (head.Position - selected.Parent.Position).Magnitude <= range then
                        local sent, method = false, route.method
                        if method == "Prompt" then sent = pcall(fireproximityprompt, selected) end
                        if not sent then
                            clickPart = cartClickPart(cart, head.Position)
                            if clickPart then sent, method = send(refs.action, "SellCart", clickPart), "Click" end
                        end
                        if sent then
                            state.pending.sale = {count = count, at = os.clock(), cart = cart, method = method}
                            state.needSale, route.approach, route.reposition = nil, nil, nil
                            app.status.farm = "Sale sent; waiting for bag decrease · " .. method
                        else
                            route.reposition = true
                            app.status.farm = "Cart click obstructed; finding another selling position"
                            if not route.approach then
                                retrySale(route, type(fireproximityprompt) == "function" and "Prompt" or "Click", 1)
                            end
                        end
                    end
                    return
                else app.status.farm = "Equipping bucket for sale" return end
            else app.status.farm = "No idle streamed sell cart" end
        end
        if state.pending.sale and due then return end
        if (state.selectAt or 0) <= os.clock() then
            state.selectAt = os.clock() + 0.25
            local target, part, position, score, mode = nil, nil, nil, nil, nil
            local unlocked = player:GetAttribute("UnlockedLayer") or 1
            local candidates = {}
            if (state.frontierAt or 0) <= os.clock() then
                local layer, upper, height, remaining = nil, nil, nil, 0
                local covered = {}
                for _, model in ipairs(state.targetList) do
                    local hp, level = model:GetAttribute("HP"), model:GetAttribute("Layer") or 1
                    local surface = model:IsA("Model") and model.PrimaryPart
                    if not surface and finite(hp) and hp > 0 then surface = targetParts(model) end
                    if model.Parent and finite(hp) and hp > 0 and not model:GetAttribute("EggCore")
                        and eggGeometry and model:IsDescendantOf(eggGeometry) and level <= unlocked and surface then
                        if covered[level] == nil then covered[level] = guardian.Covers(eggGeometry, level, player) end
                        if not covered[level] and not eggGeometry:GetAttribute("EventCarried") then
                            remaining += 1
                            if not layer or level < layer or level == layer and surface.Position.Y > height then
                                layer, upper, height = level, model, surface.Position.Y
                            end
                        end
                    end
                end
                state.frontierLayer, state.upperTarget, state.remainingChunks, state.frontierAt = layer, upper, remaining, os.clock() + 1
            end
            -- Nominate the highest outer chunk even when it occurs beyond this
            -- tick's bounded rotating discovery window. Compaction can't hide it.
            if state.upperTarget and state.upperTarget.Parent then candidates[state.upperTarget] = true end
            local overlap = OverlapParams.new()
            overlap.FilterType = Enum.RaycastFilterType.Include
            overlap.FilterDescendantsInstances = {state.lab}
            overlap.MaxParts = 128
            local miningRange = math.max(reach("Pickaxe", config), owns("HandDrill", config) and reach("HandDrill", config) or 0)
            for _, p2 in ipairs(workspace:GetPartBoundsInRadius(head.Position, math.max(24, miningRange, reach("Bucket", config)), overlap)) do
                local model = p2.Parent
                while model and model ~= state.lab do
                    if state.targets[model] then candidates[model] = true end
                    model = model.Parent
                end
            end
            -- Far discovery is incremental, never a full map scan per tick.
            for _ = 1, math.min(128, #state.targetList) do
                state.targetCursor = (state.targetCursor or 0) % #state.targetList + 1
                local model = state.targetList[state.targetCursor]
                if model.Parent then candidates[model] = true end
            end
            if state.target and state.target.Parent then candidates[state.target] = true end
            for model in pairs(state.enemies or {}) do candidates[model] = true end
            local bestRank
            local bucketMechanics = mechanics("Bucket")
            local fallingVacuum = bucketMechanics and bucketMechanics.Input == "Hold" and bucketMechanics.Shape == "Cone"
            for model in pairs(candidates) do
                if model.Parent then
                    local meaningful = model:GetAttribute("HP") ~= nil or model:GetAttribute("FloorShell") == true
                        or model:GetAttribute("EventScientist") == true or model:GetAttribute("CreatureLimb") == true
                    local p, pos
                    if meaningful then p, pos = aim(model, head.Position) end
                    if p then
                        local d = (pos - head.Position).Magnitude
                        local kind, utility
                        if model:GetAttribute("FloorShell") == true and not full and (model:GetAttribute("Quantity") or 0) > 0
                            and (model:GetAttribute("Settled") == true or fallingVacuum) then
                            kind, utility = magnet and "passive" or "collect", magnet and 0.5 or 3
                        elseif eventTarget.Find(p) == model then kind, utility = "event", model:GetAttribute("Variant") == "Medic" and 35 or 20
                        elseif finite(model:GetAttribute("HP")) and model:GetAttribute("HP") > 0 then
                            local layer = model:GetAttribute("Layer") or 1
                            if model:GetAttribute("EggCore") == true then kind, utility = "core", 30
                            elseif eggGeometry and layer <= unlocked and not guardian.Covers(eggGeometry, layer, player)
                                and not eggGeometry:GetAttribute("EventCarried") then
                                kind, utility = "mine", 1 + math.min(1, (player:GetAttribute("PickaxeDamage") or 10) / model:GetAttribute("HP"))
                            end
                        end
                        if tutorialStep == 1 and (kind == "collect" or kind == "passive") then kind = nil end
                        if tutorialStep == 2 and (kind == "collect" or kind == "passive") then utility = 50 end
                        if tutorialStep == 2 and kind ~= "collect" and kind ~= "passive" and kind ~= "event" then kind = nil end
                        if state.combat and kind ~= "event" then kind = nil end
                        if kind and eligible("hit:" .. targetId(model), hitFingerprint(model, state.family)) then
                            local rank = kind == "event" and (model:GetAttribute("EventScientist") == true and 3 or 2) or 1
                            if kind == "mine" then
                                if (model:GetAttribute("Layer") or 1) == state.frontierLayer then rank = 1.1 end
                                utility += math.max(0, pos.Y - (config.EggGroundY or 0)) * 0.4
                            elseif kind == "passive" then
                                local visitDue = tutorialStep == 2 or state.passiveVisit and state.passiveVisit.target == model
                                    or os.clock() >= (state.passiveNextAt or math.huge) and (state.passiveRetryAt or 0) <= os.clock()
                                rank = visitDue and 1.2 or 0
                            end
                            local value = utility / (1 + d * 0.04)
                            local visible = kind == "event" and contact(model, pos, head, miningRange)
                            local reachable = visible and visible.Instance:IsDescendantOf(model)
                                and (visible.Position - head.Position).Magnitude <= miningRange
                            -- Keep chunks/batches stable, but never pin a distant
                            -- NPC while a nearby visible scientist can be hit now.
                            if reachable then value += 200000
                            elseif model == state.target and kind == state.mode and kind ~= "event" then value += 100000 end
                            if kind == "mine" and model == state.upperTarget and (state.target ~= model or state.mode ~= "mine") then value += 200000 end
                            local movementReady = reachable or eligible("move:target:" .. targetId(model), movementFingerprint(model, (kind == "collect" or kind == "passive") and "collect" or "mine"))
                            if movementReady and (not target or rank > bestRank or rank == bestRank and value > score) then
                                target, part, position, score, mode, bestRank = model, p, pos, value, kind, rank
                            end
                        end
                    end
                else state.targets[model] = nil end
            end
            local egg2 = state.lab:FindFirstChild("Egg")
            local guardState = egg2 and guardian.State(egg2, player)
            state.requiredLayer = math.max(unlocked, guardState and guardState:GetAttribute("SlimeLayer") or 1,
                egg2 and egg2:GetAttribute("DeepestReachedLayer") or 1)
            state.target, state.part, state.position, state.mode = target, part, position, mode
        end
        local target, part, position, mode = state.target, state.part, state.position, state.mode
        -- Moving NPCs and client-animated drops invalidate old aim coordinates.
        if target and target.Parent then part, position = aim(target, head.Position) end
        local egg = state.lab:FindFirstChild("Egg")
        local guardianReady = egg and (guardian.CanHit(egg, player) or guardian.CoreWaiting(egg, player))
        if mode == "guardian" and not guardianReady then target, state.target = nil, nil end
        if not state.combat and tutorialStep ~= 2 and guardianReady then
            local surface = ray(config.EggCenter, head, guardian, 200)
            if not target and (not surface or surface.Instance ~= egg or not surface.Guardian) then
                local direction = config.EggCenter - head.Position
                -- Analytic native geometry supplies a route target behind an
                -- obstruction. Dispatch still needs a clear physical/native ray.
                if direction.Magnitude > 0.01 then
                    surface = guardian.Raycast(egg, player, head.Position, direction.Unit * 200, nil)
                end
            end
            -- The native guardian surface is the unlock target. Distant leftover
            -- chunks must not keep it behind an ordinary-target fallback.
            if surface and surface.Instance == egg and surface.Guardian
                and eligible("hit:" .. targetId(egg), hitFingerprint(egg, state.family)) then
                target, position, mode = egg, surface.Position, "guardian"
                state.target, state.position, state.mode = target, position, mode
            end
        end
        if not target or not target.Parent then
            if not state.combat and tutorialStep ~= 2 and inspectRemainingTop(config, guardian, root, head) then return end
            -- Active round hover survives empty scans and streaming delays.
            app:release()
            state.approach, state.obstruction = nil, nil
            lease("Bucket", false) lease("Drill", false)
            state.needSale = count > 0
            local phase = state.lab:GetAttribute("BossPhase") or "Idle"
            if tutorialStep == 2 and not state.combat then equip("Bucket", config) end
            app.status.farm = tutorialStep == 2 and "Tutorial: waiting for ready shells to collect" or state.combat and "Event target obstructed or cooling down; keeping mining tool" or full and "Bucket full; waiting for sale" or phase ~= "Idle" and ("Boss " .. phase .. ": waiting for damage target; evasion active") or "Waiting for eligible geometry/drops or layer unlock"
            return
        end
        state.hoverWaitAt = nil
        if mode == "passive" then
            local scoop = player:GetAttribute("ScoopRadius")
            scoop = finite(scoop) and scoop > 0 and scoop or config.ScoopRadius
            local center = target.PrimaryPart and target.PrimaryPart.Position or position
            local p = state.passiveVisit
            if not p or p.target ~= target then
                p = {target = target, quantity = target:GetAttribute("Quantity") or 0, at = os.clock()}
                state.passiveVisit = p
            end
            -- Shell Magnet works without a bucket: move the actual root into a
            -- conservative scoop-radius neighbourhood and observe real drops.
            if (root.Position - center).Magnitude <= scoop then
                if app.move then app:release(true) end
                lease("Bucket", false) lease("Drill", false)
                p.arrivedAt = p.arrivedAt or os.clock()
                app.status.farm = "In Shell Magnet range; waiting for native pickup"
                if os.clock() - p.arrivedAt > 1.5 then
                    fail("hit:" .. targetId(target), hitFingerprint(target, "Magnet"), "Native magnet pickup unchanged")
                    state.passiveVisit, state.target, state.selectAt = nil, nil, 0
                    state.passiveNextAt, state.passiveRetryAt = os.clock() + 8, os.clock() + 3
                end
            else
                local radial = root.Position - center
                local goal = center + (radial.Magnitude > 0.01 and radial.Unit or Vector3.new(0, 1, 0)) * math.max(0.3, scoop * 0.25)
                local approach = {target = target, goal = goal, air = true, at = os.clock()}
                local _, reason = move("collect", "target:" .. targetId(target), target, center, math.max(0.5, scoop * 0.5), approach)
                app.status.farm = "Flying into Shell Magnet range · " .. tostring(reason)
                if os.clock() - p.at > 20 or not app.move and (root.Position - center).Magnitude > scoop then
                    state.passiveVisit, state.target, state.selectAt = nil, nil, 0
                    state.passiveNextAt, state.passiveRetryAt = os.clock() + 8, os.clock() + 3
                end
            end
            return
        end
        if not part and mode ~= "guardian" or not position then state.target, state.selectAt = nil, 0 return end
        local family, cooldown = "Bucket", player:GetAttribute("ScoopCooldown") or config.ScoopCooldown
        if mode ~= "collect" then
            local best
            for _, candidate in ipairs({"Pickaxe", "HandDrill", "Drill"}) do
                if owns(candidate, config)
                    and (candidate ~= "Drill" or (player:GetAttribute("DrillFuel") or 30) > 0
                    and (player:GetAttribute("DrillCoolingUntil") or 0) <= workspace:GetServerTimeNow()) then
                    local value, cd = power(candidate, player:GetAttribute("Evolution_" .. candidate) or 1, config, evolution, mode)
                    if not best or value > best then family, cooldown, best = candidate, cd, value end
                end
            end
            if not best then app.status.farm = "No ready owned mining tool in range" app:release() return end
            if tutorialStep == 1 then family, cooldown = "Pickaxe", player:GetAttribute("ToolCooldown_Pickaxe") or config.ToolById.Pickaxe.Cooldown end
        end
        local gun = (mode == "event" or mode == "core") and gunUsable()
        if gun then family, cooldown = "Gun", 0 end
        if not gun and (mode == "event" or mode == "core") and flameOwned(config) then
            family = "HandDrill"
            local _, interval = power(family, 3, config, evolution, mode)
            cooldown = interval
        end
        local blastReady = mode == "mine" and tutorialStep ~= 1 and explosiveReady(config)
        local continuingBlast = mode == "mine" and equipped("Dynamite") and state.explosive and state.explosive.left > 0
            and (not state.pending.blast or os.clock() - state.pending.blast.at < 0.5)
            and state.explosive.nextAt <= workspace:GetServerTimeNow() + 0.4
            and (player:GetAttribute("ToolReadyAt_Dynamite") or math.huge) <= workspace:GetServerTimeNow() + 0.4
        if (blastReady or continuingBlast) and egg and target:IsDescendantOf(egg) and not target:GetAttribute("EggCore") then
            local blastContact = contact(target, position, head, reach("Dynamite", config), guardian)
            if blastContact and (blastContact.Position - head.Position).Magnitude <= reach("Dynamite", config)
                and (blastContact.Instance == target or blastContact.Instance:IsDescendantOf(target)) then family, cooldown = "Dynamite", 0.2 end
        end
        state.family = family
        if not equip(family, config) then app.status.farm = "Equipping " .. family return end
        local m = mechanics(family)
        local range = reach(family, config)
        local lane = mode == "collect" and "collect" or "mine"
        local rayGuardian = mode ~= "collect" and guardian or nil
        local result = contact(target, position, head, range, rayGuardian)
        if mode ~= "collect" and result and result.Instance ~= target and not result.Instance:IsDescendantOf(target) then
            local blocker = result.Instance
            while blocker and blocker ~= state.lab do
                local hp, layer = blocker:GetAttribute("HP"), blocker:GetAttribute("Layer") or 1
                if finite(hp) and hp > 0 and layer <= (player:GetAttribute("UnlockedLayer") or 1)
                    and egg and not guardian.Covers(egg, layer, player)
                    and eligible("hit:" .. targetId(blocker), hitFingerprint(blocker, family)) then
                    target, position, mode = blocker, result.Position, "mine"
                    state.target, state.position, state.mode, state.selectAt = target, position, mode, os.clock() + 0.25
                    break
                end
                blocker = blocker.Parent
            end
        end
        if mode == "event" and result and (result.Position - head.Position).Magnitude <= range then
            local actual = eventTarget.Find(result.Instance)
            if actual and eligible("hit:" .. targetId(actual), hitFingerprint(actual, family)) then
                target, position = actual, result.Position
                state.target, state.position, state.mode = target, position, "event"
            end
        end
        local ready = result and (result.Position - head.Position).Magnitude <= range
            and (result.Instance == target or result.Instance:IsDescendantOf(target))
        local approach = state.approach
        if approach and (approach.target ~= target or os.clock() - approach.at > 8
            or (approach.goal + head.Position - root.Position - position).Magnitude > range) then
            state.approach, approach = nil, nil
        end
        if approach and (root.Position - approach.goal).Magnitude > 0.75 then ready = false end
        if not ready and not approach then
            local obstructed = state.obstruction
            if not obstructed or obstructed.target ~= target or (root.Position - obstructed.last).Magnitude > 0.75 then
                obstructed = {target = target, last = root.Position, at = os.clock()}
                state.obstruction = obstructed
            end
            if (position - head.Position).Magnitude <= range + 2 or os.clock() - obstructed.at > 0.8 then
                if (obstructed.probeAt or 0) <= os.clock() then
                    obstructed.probeAt = os.clock() + 0.8
                    approach = approachPosition(target, position, head, root, hum, range, rayGuardian)
                    state.approach = approach
                    if not approach and (position - head.Position).Magnitude <= range + 2 then
                        fail("hit:" .. targetId(target), hitFingerprint(target, family), "No clear attack position; trying another target")
                        state.target, state.selectAt = nil, 0
                        app:release()
                        app.status.farm = "No clear attack ray; trying another target"
                        return
                    end
                end
            end
        end
        if ready then
            -- A valid native ray hit is the attack condition; a path waypoint
            -- or estimated mesh surface is not an additional prerequisite.
            if app.move then app:release() end
            state.obstruction = nil
        else
            local arrived, reason = move(lane, "target:" .. targetId(target), target, position, math.max(2, range - 1), approach)
            if not arrived then
                app.status.farm = mode .. " " .. string.format("%.1f/%.1f studs", (position - head.Position).Magnitude, range)
                    .. " · " .. tostring(reason)
                lease("Bucket", false) lease("Drill", false)
                return
            end
        end
        if not result or (result.Position - head.Position).Magnitude > range
            or (result.Instance ~= target and not result.Instance:IsDescendantOf(target)) then
            app.status.farm = "Target obstructed; selecting another surface"
            state.selectAt = 0
            state.targets[target] = true
            app.cooldowns["hit:" .. targetId(target)] = os.clock() + 1
            state.target, state.approach = nil, nil
            app:release()
            return
        end
        local measuredHP, measuredQuantity = target:GetAttribute("HP") or target:GetAttribute("Health"), target:GetAttribute("Quantity")
        local progress = tostring(measuredHP) .. ":" .. tostring(measuredQuantity)
        local watch = state.activity
        if not finite(measuredHP) and not finite(measuredQuantity) then
            state.activity = nil
        elseif not watch or watch.target ~= target or watch.progress ~= progress then
            state.activity = {target = target, progress = progress, at = os.clock()}
        elseif os.clock() - watch.at > 5 then
            fail("hit:" .. targetId(target), hitFingerprint(target, family), "Target made no damage/collection progress")
            state.target, state.selectAt, state.activity = nil, 0, nil
            lease("Bucket", false) lease("Drill", false)
            return
        end
        local weak = state.weak
        if mode == "mine" and weak and weak.Chunk == target and typeof(weak.Position) == "Vector3" and (weak.Position - head.Position).Magnitude <= range then
            local weakResult = ray(weak.Position, head)
            if weakResult and weakResult.Instance:IsDescendantOf(target) then result = weakResult end
        end
        if family == "Gun" then
            lease("Bucket", false) lease("Drill", false)
            shoot(target, result, gun)
        elseif family == "Dynamite" then
            lease("Bucket", false) lease("Drill", false)
            -- Re-check native coverage after movement/streaming before a blast.
            local layer = target:GetAttribute("Layer") or 1
            if mode == "mine" and egg and target:IsDescendantOf(egg) and not guardian.Covers(egg, layer, player)
                and not egg:GetAttribute("EventCarried") and not target:GetAttribute("EggCore") then throwExplosive(target, result, config) end
        elseif family == "Bucket" and m and m.Input == "Hold" then
            local delta = result.Position - root.Position
            local facing = Vector3.new(delta.X, 0, delta.Z)
            if facing.Magnitude > 0.01 then root.CFrame = CFrame.lookAt(root.Position, root.Position + facing) end
            local heldAim = m.Shape == "Cone" and (result.Position - head.Position).Unit or result.Position
            lease("Bucket", true, heldAim)
            lease("Drill", false)
            local fp = tostring(target:GetAttribute("Quantity"))
            local held = state.hold
            if not held or held.target ~= target or held.fingerprint ~= fp then
                state.hold = {target = target, fingerprint = fp, at = os.clock()}
            elseif os.clock() - held.at > 4 then
                fail("hit:" .. targetId(target), hitFingerprint(target, family), "Held bucket made no collection progress")
                lease("Bucket", false)
                state.target, state.selectAt, state.hold = nil, 0, nil
            end
        else
            state.hold = nil
            lease("Bucket", false)
            if family == "Drill" then lease("Drill", true) else lease("Drill", false) end
            hit(target, result, family, (mode == "guardian" or mode == "core") and math.max(0.45, cooldown) or cooldown, mode == "event")
        end
        app.status.farm = mode .. " with " .. family .. " · bag " .. tostring(count)
    end
    local function capture(config, evolution)
        local grabbed = player:GetAttribute("GrabbedLimb")
        local swallowed = player:GetAttribute("SwallowedUntil")
        local now = workspace:GetServerTimeNow()
        if finite(swallowed) and swallowed > now then
            app:release()
            app.status.farm = "Swallowed · waiting for native timed release"
            return true
        end
        if type(grabbed) ~= "string" or grabbed == "" then return false end
        if app.move then app:release() else lease("Bucket", false) end
        local _, _, head = character()
        if not head then return true end
        local world = state.lab:FindFirstChild("WorldEvent")
        local limbs = world and world:FindFirstChild("CreatureLimbs")
        local limb = limbs and limbs:FindFirstChild(grabbed)
        if not limb or (limb:GetAttribute("Health") or 0) <= 0 then
            app.status.farm = "Grabbed · awaiting limb replication/release"
            return true
        end
        local family, damage, cooldown
        for _, name in ipairs({"Pickaxe", "HandDrill", "Drill"}) do
            if owns(name, config) and (name ~= "Drill" or (player:GetAttribute("DrillFuel") or 0) > 0) then
                local value, interval = power(name, player:GetAttribute("Evolution_" .. name) or 1, config, evolution, "event")
                if value and interval and (not damage or value > damage) then family, damage, cooldown = name, value, interval end
            end
        end
        if family and equip(family, config) then
            local _, position = aim(limb, head.Position)
            local result = position and contact(limb, position, head, reach(family, config))
            if result and result.Instance:IsDescendantOf(limb) and (result.Position - head.Position).Magnitude <= reach(family, config) then
                if family == "Drill" then lease("Drill", true) end
                hit(limb, result, family, cooldown, true)
                app.status.farm = "Breaking grabbing limb with " .. family
            else app.status.farm = "Grabbed · limb outside native tool reach; awaiting release" end
        end
        return true
    end
    function app:recoverLobby(reason, emergency)
        if not self.running or not self.settings.repeatRuns or self.teleporting then return false end
        local now = os.clock()
        if (self.rejoinAt or 0) > now then return false end
        self.rejoinAt = now + 60
        -- Queue continuation first. A dead/void character must still escape
        -- when the executor cannot reload; keep that limitation visible.
        if not self.resumeQueued and not self:queueResume() then
            self.status.queue = self.afkError or "Auto-resume unavailable"
            if not emergency then return false end
            self:note("Emergency lobby return without automatic reload: " .. self.status.queue)
        end
        self:release()
        self:restoreSpeed()
        self:note("AFK recovery: " .. reason)
        self.status.farm, self.status.queue = "Recovering to lobby", "Recovering: " .. reason
        self.recoveryPending, self.teleporting = now, true
        if self.resumeQueued then self.afkError = nil end
        task.spawn(function()
            if not self.alive or shared.owner ~= self or not self.running then return end
            local ok, err = pcall(function() game:GetService("TeleportService"):Teleport(137477934962022, player) end)
            if not ok and self.alive and shared.owner == self then
                self.teleporting, self.recoveryPending = false, nil
                self:note("Lobby recovery failed: " .. tostring(err))
            end
        end)
        return true
    end
    function app:watchdog()
        if not self.settings.repeatRuns then return end
        local now = os.clock()
        if self.teleporting then
            if self.recoveryPending and now - self.recoveryPending > 40 then
                self.teleporting, self.recoveryPending = false, nil
                self:note("Recovery teleport did not start; retry after backoff")
            end
            return
        end
        local w = self.watch
        if not w or w.place ~= game.PlaceId then
            w = {place = game.PlaceId, at = now, checked = 0, health = setmetatable({}, {__mode = "k"})}
            self.watch = w
        end
        if now - w.checked < 2 then return end
        w.checked = now
        if game.PlaceId == 137477934962022 then
            local difficulty = unlockedDifficulty()
            if state.effectiveDifficulty ~= difficulty then
                state.effectiveDifficulty = difficulty
                if difficulty ~= self.settings.difficulty then self:note("Requested " .. self.settings.difficulty .. "; queueing unlocked " .. difficulty) end
            end
            if state.queueReset then
                if now - state.queueReset.at > 15 then self:recoverLobby("native queue exit/reposition unresolved") end
                return
            end
            local q = tostring(player:GetAttribute("QueueState")) .. ":" .. tostring(player:GetAttribute("Queue"))
            if q ~= w.queue then w.queue, w.at = q, now end
            -- Bounded local reset before abandoning an unaccepted pad.
            if now - w.at > 35 and not queueOccupied() and player:GetAttribute("QueueState") ~= "SettingUp"
                and player:GetAttribute("QueueState") ~= "Waiting" then
                if (state.padRetryAt or 0) <= now then
                    state.avoidPad, state.avoidPadUntil, state.padRetryAt = state.padTarget, now + 25, now + 35
                    self:release()
                    state.padStarted, state.padAt = nil, nil
                end
                if now - w.at > 120 then self:recoverLobby("lobby queue made no progress") end
            elseif now - w.at > 90 then
                -- QueueClient's Exit uses zero arguments in SettingUp/Waiting.
                -- Try its local recovery once; observe replicated exit before
                -- walking off the old pad or submitting another party.
                if not w.exitAttempted and refs.exit and (player:GetAttribute("QueueState") == "SettingUp" or player:GetAttribute("QueueState") == "Waiting") then
                    w.exitAttempted = true
                    local ok = pcall(refs.exit.FireServer, refs.exit)
                    if ok then
                        state.queueReset = {at = now, pad = state.padTarget}
                        self:release()
                        self:note("Queue stalled; native Exit sent, awaiting cleared queue")
                    else self:recoverLobby("queue Exit dispatch failed") end
                else self:recoverLobby("queue acceptance/transition stalled") end
            end
            return
        end
        if game.PlaceId ~= 104087083666671 then return end
        local lab = state.lab
        local fingerprint = tostring(player:GetAttribute("ShellCount")) .. ":" .. tostring(state.stats.collected)
            .. ":" .. tostring(player:GetAttribute("UnlockedLayer"))
            .. ":" .. tostring(player:GetAttribute("EggTutorialStep"))
            .. ":" .. tostring(state.stats.chests) .. ":" .. tostring(lab and lab:GetAttribute("BossPhase"))
            .. ":" .. tostring(lab and lab:GetAttribute("BossWave"))
        local egg = lab and lab:FindFirstChild("Egg")
        local guardian = module("BreakTheEgg", "LayerGuardian")
        local guardianState = egg and guardian and guardian.State(egg, player)
        fingerprint ..= ":" .. tostring(guardianState and guardianState:GetAttribute("SlimeLayer"))
            .. ":" .. tostring(guardianState and guardianState:GetAttribute("SlimeReactAt"))
        if fingerprint ~= w.fingerprint then w.fingerprint, w.at, w.resynced = fingerprint, now, false end
        local coreHP = lab and lab:GetAttribute("BossCoreHP")
        if finite(coreHP) then
            if finite(w.coreHP) and coreHP < w.coreHP then w.at, w.resynced = now, false end
            w.coreHP = coreHP
        end
        for obj in pairs(state.targets) do
            local hp = obj.Parent and (obj:GetAttribute("Health") or obj:GetAttribute("HP"))
            local old = w.health[obj]
            if finite(hp) then
                if finite(old) and hp < old then w.at, w.resynced = now, false end
                w.health[obj] = hp
            elseif old then w.health[obj], w.at, w.resynced = nil, now, false end
        end
        -- Presentation phases are finite; don't reset the timer every tick of
        -- an unchanged modal, which could otherwise pause farming forever.
        if now - w.at > 45 and not w.resynced then
            w.resynced = true
            self:release()
            state.target, state.selectAt = nil, 0
            send(refs.action, "Sync")
            send(refs.chest, "Ready")
            self:note("No round progress; resynchronizing targets and receipts")
        end
        if now - w.at > 150 then self:recoverLobby("round had no measurable progress for 150 seconds") end
        local _, _, _, hum = character()
        if not hum then
            w.deadAt = w.deadAt or now
            if not finite(player:GetAttribute("PersonalEndingAt")) and now - w.deadAt > 35 then self:recoverLobby("death/respawn did not transition", true) end
        else w.deadAt = nil end
        local ending = player:GetAttribute("PersonalEndingAt")
        if finite(ending) and workspace:GetServerTimeNow() - ending > 60 then self:recoverLobby("personal ending completed", true) end
    end

    local function tutorial(config)
        local step = player:GetAttribute("EggTutorialStep")
        local p = state.pending.tutorial
        if p then
            if step ~= p.step then state.pending.tutorial = nil success("tutorial:" .. tostring(p.step))
            elseif os.clock() - p.at > 4 then
                fail("tutorial:" .. tostring(step), tostring(step), "Tutorial stage did not advance")
                state.pending.tutorial = nil
            end
            return p.step == 7
        end
        if step == 4 or step == 6 then
            -- TutorialProgress.Action verifies the stage itself. These messages
            -- advance only its matching stage and don't require a UI toggle.
            if eligible("tutorial:" .. tostring(step), tostring(step)) and send(refs.action, "Tutorial", step == 4 and "TreeOpened" or "TreeClosed") then
                state.pending.tutorial = {step = step, at = os.clock()}
            end
        elseif step == 7 then
            local shop = workspace:FindFirstChild("Shop")
            local display = shop and shop:FindFirstChild("Handdrill")
            local anchor = display and display:FindFirstChild("ShopAttachment", true)
            if not anchor then app.status.farm = "Tutorial shop anchor missing/streaming" return false end
            local arrived, reason = move("shop", "tutorial-shop", display, anchor.WorldPosition, 12)
            app.status.farm = reason or "Completing required shop visit"
            if arrived and eligible("tutorial:7", "7") and send(refs.action, "Tutorial", "ShopVisited") then
                state.pending.tutorial = {step = 7, at = os.clock()}
            end
            return true
        end
        return false
    end
    local function repeatRound()
        if not app.settings.repeatRuns then return end
        if game:GetService("GuiService").MenuIsOpen or player:GetAttribute("PurchasePromptOpen") == true then return end
        local p = state.pending.returnLobby
        if p then
            app.status.queue = "ReturnLobby pending"
            if os.clock() - p.at > 15 then app.status.queue = "Lobby return unresolved; awaiting native result" end
            return
        end
        if game.PlaceId == 104087083666671 then
            local win = state.won
            local data = win and type(win.data) == "table" and win.data or nil
            local ready = win and os.clock() - win.at >= 4
            if data and finite(data.StartedAt) and finite(data.Duration) then
                ready = workspace:GetServerTimeNow() >= data.StartedAt + math.max(4, data.Duration)
            end
            if ready and eligible("return", "win") then
                if send(refs.action, "ReturnLobby") then state.pending.returnLobby = {at = os.clock()} end
            elseif player:GetAttribute("DeathMenuOpen") == true and player:GetAttribute("CanRevive") == true then
                if not state.pending.death then
                    if send(refs.death, "Continue") then state.pending.death = {at = os.clock()} end
                elseif os.clock() - state.pending.death.at > 10 then app.status.queue = "Death Continue unresolved; awaiting transition" end
            else state.pending.death = nil end
            return
        end
        local s = app.settings
        if state.queueReset then
            app.status.queue = "Recovering stalled queue · awaiting native exit"
            if queueOccupied() or player:GetAttribute("QueueState") == "SettingUp" or player:GetAttribute("QueueState") == "Waiting" then return end
            local p = state.queueReset
            local _, root = character()
            if p.pad and p.pad.Parent and root then
                if not p.goal then
                    local away = Vector3.new(root.Position.X - p.pad.Position.X, 0, root.Position.Z - p.pad.Position.Z)
                    p.goal = p.pad.Position + (away.Magnitude > 0.1 and away.Unit or Vector3.new(1, 0, 0))
                        * (math.max(p.pad.Size.X, p.pad.Size.Z) * 0.5 + 8)
                end
                local arrived, reason = move("queue", "queue-exit", p.pad, p.goal, 2)
                app.status.queue = reason or "Walking clear of previous queue pad"
                if not arrived then return end
            end
            state.avoidPad, state.avoidPadUntil = p.pad, os.clock() + 25
            state.queueReset, state.pending.queue, state.padStarted, state.padAt = nil, nil, nil, nil
            success("queue")
            return
        end
        local difficulty = unlockedDifficulty()
        local queueState = player:GetAttribute("QueueState")
        if queueState == "SettingUp" then
            local fp = difficulty .. ":" .. tostring(s.partySize) .. ":" .. tostring(player:GetAttribute("Queue"))
            if state.pending.queue then
                app.status.queue = "Waiting for queue acceptance"
                if os.clock() - state.pending.queue.at > 10 then app.status.queue = "CreateParty unresolved; no duplicate request" end
            elseif eligible("queue", fp) and refs.create and send(refs.create, s.partySize, difficulty) then
                state.pending.queue = {at = os.clock(), fingerprint = fp, difficulty = difficulty}
            end
            return
        end
        if queueOccupied() then
            app.status.queue = "Queued · accepted " .. tostring(state.queueAccepted or "awaiting acknowledgement")
            return
        end
        if gate() then return end
        local preparation = app:lobbyPreparation()
        if preparation then app.status.queue = preparation return end
        local _, root = character()
        if not root then return end
        local target, distance
        local occupied = {}
        for _, p2 in ipairs(Players:GetPlayers()) do
            local id = p2:GetAttribute("Queue")
            if id ~= nil and id ~= false and id ~= "" and id ~= 0 then occupied[id] = true end
        end
        for _, child in ipairs(workspace:GetChildren()) do
            local inner = child.Name == "SimulatorCircle" and child:FindFirstChild("InnerCylinder")
            if inner and inner:IsA("BasePart") and not occupied[child:GetAttribute("QueueId")]
                and not (state.avoidPad == inner and (state.avoidPadUntil or 0) > os.clock()) then
                local d = (inner.Position - root.Position).Magnitude
                if not target or d < distance then target, distance = inner, d end
            end
        end
        if not target then app.status.queue = "No free streamed SimulatorCircle" return end
        state.padTarget = target
        local arrived, reason = move("queue", "queue-pad", target, target.Position, 2)
        app.status.queue = reason or "On queue pad; waiting for SettingUp"
        -- No verified touch listener exists in the lobby dump. Geometry occupancy
        -- is native; don't fake touch or claim it works from across the map.
        if arrived and (state.padAt or 0) <= os.clock() then
            state.padAt = os.clock() + 5
            if os.clock() - (state.padStarted or os.clock()) > 15 then app.status.queue = "Pad occupancy not accepted; retrying route automatically" end
            state.padStarted = state.padStarted or os.clock()
        end
    end
    function app:stepRound()
        if game.PlaceId ~= 137477934962022 then self.preparationAt, self.preparationBypass = nil, nil end
        if game.PlaceId ~= 137477934962022 and game.PlaceId ~= 104087083666671 then self:release() self:restoreSpeed() return end
        if self.teleporting then self:release() self:restoreSpeed() return end
        refresh()
        repeatRound()
        if game.PlaceId ~= 104087083666671 then self:restoreFlight() if not gate() then self:updateSpeed() else self:restoreSpeed() end return end
        if not refs.action or not state.lab then self:release() self:restoreSpeed() self.status.farm = "Waiting for BreakTheEgg world + Action" return end
        local safetyConfig = module("BreakTheEgg", "Config")
        if safetyConfig and self:flightSafety(safetyConfig) then return end
        local blocked = gate()
        -- An existing native picker can continue under its own modal even if
        -- its Offer event happened before this script attached.
        local chestModal = blocked == "Waiting for SessionModalOpen" and player:GetAttribute("ChestPickerOpen") == true
        if blocked and not chestModal then self:release() self:restoreSpeed() self.status.farm = blocked return end
        local config = module("BreakTheEgg", "Config")
        local evolution = module("BreakTheEgg", "ToolEvolutions")
        local toolRules = module("BreakTheEgg", "ToolMechanics")
        if not config or not evolution or not toolRules then self.status.farm = "Loading native tool definitions" return end
        if (state.compactAt or 0) <= os.clock() then
            local list = {}
            for model in pairs(state.targets) do if model.Parent then table.insert(list, model) else state.targets[model] = nil end end
            state.targetList, state.targetCursor, state.compactAt = list, #list > 0 and (state.targetCursor or 0) % #list or 0, os.clock() + 5
            local liveFaults = {}
            for obj, id in pairs(state.targetIds) do
                if obj.Parent then liveFaults["hit:" .. id], liveFaults["move:target:" .. id] = true, true end
            end
            for key in pairs(self.failures) do
                if (string.sub(key, 1, 4) == "hit:" or string.sub(key, 1, 12) == "move:target:") and not liveFaults[key] then success(key) end
            end
        end
        self:updateSpeed()
        local _, flightRoot = character()
        if flightRoot and (state.knockUntil or 0) <= os.clock() then self:updateFlight(flightRoot) end
        refreshCombat()
        if not blocked and capture(config, evolution) then return end
        if (not blocked or chestModal) and evasion(config) then
            if not blocked then attackDuringEvasion(config, evolution) end
            return
        end
        local pickerOpen = player:GetAttribute("ChestPickerOpen") == true
        local saleFirst = not pickerOpen and not state.pending.chest and salePolicy(config)
        local chestOwnsMovement = (not state.combat or pickerOpen) and not saleFirst and chests(config, evolution)
        if chestOwnsMovement or player:GetAttribute("ChestPickerOpen") == true then lease("Bucket", false) lease("Drill", false) end
        if not blocked then
            local tutorialOwnsMovement = not state.combat and not chestOwnsMovement and app.settings.farm and tutorial(config)
            local gunOwnsMovement = not saleFirst and not tutorialOwnsMovement and not chestOwnsMovement and buyGun(config)
            -- Always reconcile delayed gun ownership even while cashout/modal
            -- owns movement; uncertain purchases stay singular across reloads.
            if state.pending.gunBuy and ownedGun() then buyGun(config) end
            upgrades(config)
            local triggerOwnsEquipment = not chestOwnsMovement and not tutorialOwnsMovement and not saleFirst
                and app.settings.farm and player:GetAttribute("ChestPickerOpen") ~= true and attackDuringEvasion(config, evolution, true)
            if not chestOwnsMovement and not tutorialOwnsMovement and not gunOwnsMovement and player:GetAttribute("ChestPickerOpen") ~= true then
                local workerOwnsEquipment = not triggerOwnsEquipment and not saleFirst and worker(config)
                if not triggerOwnsEquipment and not workerOwnsEquipment then farm(config, evolution) end
            end
        end
    end
    function app:physicsRound()
        if not self.running or self.teleporting or game.PlaceId ~= 104087083666671 or not state.lab or not refs.action then return end
        local _, root, _, hum = character()
        if not root or (state.knockUntil or 0) > os.clock() then return end
        if player:GetAttribute("SlimeCutscene") == true or player:GetAttribute("BossCutscene") == true then return end
        if self.flight then self:updateFlight(root) end
        -- Recheck imminent waves before physics, independent of the slower
        -- farming tick. Capture and native cutscenes keep their own movement.
        local grabbed, swallowed = player:GetAttribute("GrabbedLimb"), player:GetAttribute("SwallowedUntil")
        local blocked = gate()
        local chestModal = blocked == "Waiting for SessionModalOpen" and player:GetAttribute("ChestPickerOpen") == true
        if not root.Anchored and not hum.PlatformStand and (not blocked or chestModal)
            and not (type(grabbed) == "string" and grabbed ~= "")
            and not (finite(swallowed) and swallowed > workspace:GetServerTimeNow()) then
            local config, boss = module("BreakTheEgg", "Config"), module("BreakTheEgg", "BossConfig")
            if config and boss then
                local now = workspace:GetServerTimeNow()
                quakeFlight(config, boss, root, hum, now, hazards(config, boss, now))
            end
        end
        if blocked or not self.settings.farm or state.pending.chest or player:GetAttribute("ChestPickerOpen") == true
            or (player:GetAttribute("EggTutorialStep") or 0) < 8 or state.leases.Bucket then return end
        local config, evolution = module("BreakTheEgg", "Config"), module("BreakTheEgg", "ToolEvolutions")
        if config and evolution then attackDuringEvasion(config, evolution, true) end
    end
    function app:roundDiagnostics()
        local lines = {"Round accepted hits=" .. state.stats.hits .. "; shells=" .. state.stats.collected .. "; chest receipts=" .. state.stats.chests,
            "Worker: " .. tostring(self.status.worker or "not checked") .. "; Active=" .. tostring(player:GetAttribute("WorkerActive")),
            "Mining/collection travel: direct 3D flight with noclip and hover while attacking",
            "Difficulty requested=" .. self.settings.difficulty .. "; next unlocked=" .. unlockedDifficulty()
                .. "; acknowledged=" .. tostring(state.queueAccepted or "none"),
            "Pass attributes: InfiniteBucket=" .. tostring(player:GetAttribute("InfiniteBucket")) .. "; DoubleChest=" .. tostring(player:GetAttribute("DoubleChest"))
            .. "; ClaimAllUpgrades=" .. tostring(player:GetAttribute("ClaimAllUpgrades")),
            "Boss evasion: replicated slams/lanes/globs/puddles/grabs/beams + upward shockwave flight; active records=" .. tostring(state.hazardCount or 0)
                .. "; melee avoidance zones=" .. tostring(state.meleeCount or 0)
                .. "; native boss strikes=" .. tostring(state.stats.bossStrikes or 0) .. "; confirmed win receipts=" .. tostring(state.stats.wins or 0),
            "AFK watchdog=" .. tostring(self.watch and math.floor(os.clock() - self.watch.at) or 0) .. " seconds without measurable progress; resume queued=" .. tostring(self.resumeQueued == true)}
        local nativeCart = workspace:FindFirstChild("Minecart")
        table.insert(lines, "Confirmed cashouts=" .. tostring(state.stats.sales or 0)
            .. "; sale method=" .. tostring(state.saleRoute and state.saleRoute.method or "none")
            .. "; sale retry=" .. tostring(state.saleRoute and state.saleRoute.tries or 0))
        table.insert(lines, "Gun: " .. tostring(self.status.gun or "not checked") .. "; confirmed buys=" .. tostring(state.stats.gunBuys or 0)
            .. "; acknowledged shots=" .. tostring(state.stats.gunShots or 0) .. "; ammo=" .. tostring(state.gun and state.gun.ammo))
        table.insert(lines, tostring(self.status.explosive or "Explosives: waiting for owned ready charges")
            .. "; acknowledged throws=" .. tostring(state.stats.explosives or 0))
        table.insert(lines, "Shell Magnet=" .. tostring(player:GetAttribute("VIPOwned_vip_magnet"))
            .. "; Auto Sell=" .. tostring(player:GetAttribute("VIPOwned_vip_autoSell"))
            .. "; outer mining layer=" .. tostring(state.frontierLayer) .. "; eligible chunks remaining=" .. tostring(state.remainingChunks or 0))
        table.insert(lines, "Native sell cart=" .. tostring(nativeCart ~= nil)
            .. "; prompt ready=" .. tostring(state.nativeSellPrompt and state.nativeSellPrompt.Parent and state.nativeSellPrompt.Enabled == true)
            .. "; busy=" .. tostring(nativeCart and nativeCart:GetAttribute("SellBusy"))
            .. "; bag age=" .. tostring(state.bagSince and math.floor(os.clock() - state.bagSince) or 0) .. "s; batch threshold=8 / age=6s")
        local _, root, head, hum = character()
        if root then
            table.insert(lines, "Shockwave clearance Y=" .. tostring(state.quakeFlight and state.quakeFlight.minY or "inactive")
                .. "; hold until=" .. tostring(state.quakeFlight and state.quakeFlight.finish or "none")
                .. "; late/stalled vertical corrections=" .. tostring(state.stats.quakeLifts or 0))
            table.insert(lines, "Noclip/vertical hold=" .. tostring(self.flight ~= nil)
                .. "; alternate attack position=" .. tostring(state.approach and state.approach.goal or "none"))
            table.insert(lines, "Character root=" .. tostring(root.Position) .. "; head=" .. tostring(head.Position)
                .. "; WalkSpeed=" .. tostring(hum.WalkSpeed) .. "; root anchored=" .. tostring(root.Anchored))
            table.insert(lines, "Equipped=" .. tostring(player:GetAttribute("EquippedTool"))
                .. "; MiningReach=" .. tostring(player:GetAttribute("MiningReach"))
                .. "; BucketReach=" .. tostring(player:GetAttribute("BucketReach")))
            if state.target and state.target.Parent then
                local _, pos = aim(state.target, head.Position)
                table.insert(lines, "Target=" .. targetId(state.target) .. "; mode=" .. tostring(state.mode)
                    .. "; health=" .. tostring(state.target:GetAttribute("Health") or state.target:GetAttribute("HP"))
                    .. "; actual surface distance=" .. tostring(pos and (pos - head.Position).Magnitude))
            end
            if app.move then table.insert(lines, tostring(app.move.policy) .. " age=" .. math.floor(os.clock() - app.move.at)
                .. "; no movement for=" .. string.format("%.1f", os.clock() - app.move.progressAt)
                .. "; destination=" .. tostring(app.move.destination)) end
        end
        if pathJob then table.insert(lines, "Path age=" .. string.format("%.1f", os.clock() - pathJob.started) .. "; done=" .. tostring(pathJob.done)) end
        for lane, p in pairs(state.pending) do table.insert(lines, lane .. " pending age=" .. math.floor(os.clock() - p.at)) end
        return table.concat(lines, "\n")
    end
end

-- Finish only presentations opened by this script. Missing firesignal is a
-- specific terminal UI blocker; no physical input or premium-button guessing.
function app:presentations()
    if game:GetService("GuiService").MenuIsOpen or player:GetAttribute("PurchasePromptOpen") == true
        or player:GetAttribute("FirstWinPreviewPending") == true then return end
    local pg = player:FindFirstChildOfClass("PlayerGui")
    local cardGui = pg and pg:FindFirstChild("EggCardUI")
    local tierName = cardGui and cardGui:FindFirstChild("TierName", true)
    local root = cardGui and cardGui:FindFirstChild("Root")
    -- Native New mode's tier text ends in " Egg"; Detail mode says Equipped or
    -- In storage. Acknowledge new grants without closing a user's detail view.
    if root and root.Visible and tierName and type(tierName.Text) == "string" and string.sub(tierName.Text, -4) == " Egg" then
        local card = module("EggHatchery", "EggCard")
        if card and type(card._OK) == "function" and (self.retries.cardOK or 0) <= os.clock() then
            self.retries.cardOK = os.clock() + 3
            pcall(card._OK)
        end
    end
    local p = shared.presentation
    if not p then return end
    local gui = pg and pg:FindFirstChild(p.action == "Hatch" and "EggHatchCinematic" or "EggCraftReveal")
    if not gui then
        if os.clock() - p.at > 60 then shared.presentation = nil end
        return
    end
    if type(firesignal) ~= "function" then self.status.eggs = "Reward ready; press native Continue (firesignal unavailable)" return end
    if p.gui == gui and p.clicked then return end
    if p.action == "Hatch" and (p.tapAt or 0) <= os.clock() and (p.taps or 0) < 8 then
        local tap = gui:FindFirstChild("TapCatcher", true)
        if tap and tap.Visible and tap.Active then
            pcall(firesignal, tap.InputBegan, {UserInputType = Enum.UserInputType.MouseButton1})
            p.taps, p.tapAt = (p.taps or 0) + 1, os.clock() + 0.25
        end
    end
    local button = p.action == "Hatch" and gui:FindFirstChild("Continue", true) or nil
    if p.action == "Craft" then
        for _, obj in ipairs(gui:GetDescendants()) do
            if obj:IsA("TextLabel") and obj.Text == "CONTINUE" then
                local parent = obj.Parent
                while parent and parent ~= gui do
                    if parent:IsA("GuiButton") then button = parent break end
                    parent = parent.Parent
                end
            end
        end
    end
    if button and button.Visible and button.Active ~= false then
        local ok = pcall(firesignal, button.Activated)
        if ok then p.gui, p.clicked = gui, true end
    end
end

function app:queueResume()
    if not self.running or not self.settings.resume then return false end
    if not self:save() then return false end
    local queue = queue_on_teleport
    if type(queue) ~= "function" and type(syn) == "table" then queue = syn.queue_on_teleport end
    if type(queue) ~= "function" and type(fluxus) == "table" then queue = fluxus.queue_on_teleport end
    local missing = {}
    if type(queue) ~= "function" then table.insert(missing, "queue_on_teleport") end
    if type(readfile) ~= "function" then table.insert(missing, "readfile") end
    if type(loadstring) ~= "function" then table.insert(missing, "loadstring") end
    if #missing > 0 then
        self.afkError = "AFK resume API missing: " .. table.concat(missing, ", ")
        self:note(self.afkError)
        return false
    end
    local ok, source = pcall(readfile, "CrackTheEgg.lua")
    if not ok or type(source) ~= "string" or not string.find(source, "Crack the Egg: lobby + round progression, v17.", 1, true) then
        self:note("Teleport resume requires this exact script saved as CrackTheEgg.lua in executor workspace")
        self.afkError = "AFK resume: save v17 as CrackTheEgg.lua in executor workspace"
        return false
    end
    if self.resumeQueued then return true end
    local code = 'if game.PlaceId ~= 137477934962022 and game.PlaceId ~= 104087083666671 then return end\n'
        .. 'local f=loadstring(readfile("CrackTheEgg.lua")); if f then f() end'
    local queued, err = pcall(queue, code)
    if queued then self.resumeQueued, self.afkError = true, nil end
    if not queued then self:note("Teleport queue failed: " .. tostring(err)) end
    return queued
end

local function new(class, properties, parent)
    local obj = Instance.new(class)
    for k, value in pairs(properties or {}) do obj[k] = value end
    obj.Parent = parent
    return obj
end

local function buildUI()
    local gui = new("ScreenGui", {Name = "CrackEggProgression", ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 1000}, player:FindFirstChildOfClass("PlayerGui"))
    table.insert(app.objects, gui)
    local bounds = new("Frame", {Name = "Bounds", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1)}, gui)
    local window = new("Frame", {Name = "Window", Size = UDim2.fromOffset(320, 320),
        Position = UDim2.fromOffset(12, 45), BackgroundColor3 = Color3.fromRGB(23, 26, 33)}, bounds)
    new("UICorner", {CornerRadius = UDim.new(0, 8)}, window)
    local scale = new("UIScale", {}, window)
    new("TextLabel", {Size = UDim2.new(1, -16, 0, 32), Position = UDim2.fromOffset(8, 0),
        BackgroundTransparency = 1, Text = "Crack the Egg · v17", TextColor3 = Color3.new(1, 1, 1),
        TextSize = 16, Font = Enum.Font.GothamBold}, window)
    pcall(function() new("UIDragDetector", {BoundingUI = bounds}, window) end)
    local body = new("Frame", {Position = UDim2.fromOffset(10, 34), Size = UDim2.new(1, -20, 1, -44),
        BackgroundTransparency = 1}, window)
    new("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, body)
    local order = 0
    local function button(text, callback)
        order += 1
        local b = new("TextButton", {LayoutOrder = order, Size = UDim2.new(1, 0, 0, 29), Text = text,
            BackgroundColor3 = Color3.fromRGB(44, 53, 67), TextColor3 = Color3.new(1, 1, 1),
            TextSize = 13, Font = Enum.Font.Gotham, AutoButtonColor = true}, body)
        new("UICorner", {CornerRadius = UDim.new(0, 5)}, b)
        connect(b.Activated, callback)
        return b
    end
    local start = button("Start", function() if app.running then app:Stop() else app:Start() end end)
    order += 1
    local info = new("TextLabel", {LayoutOrder = order, Size = UDim2.new(1, 0, 0, 62),
        BackgroundTransparency = 1, Text = "Stopped", TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        TextColor3 = Color3.fromRGB(190, 199, 213), TextSize = 13, Font = Enum.Font.Gotham}, body)
    local repeatButton = button("", function()
        app.settings.repeatRuns = not app.settings.repeatRuns
        app.settings.resume = app.settings.repeatRuns
        changed()
    end)
    local difficultyButton = button("", function()
        app.settings.difficulty = difficulties[(table.find(difficulties, app.settings.difficulty) or 1) % #difficulties + 1]
        changed()
    end)
    local hatch = button("", function() app.settings.hatch = not app.settings.hatch changed() end)
    button("Hide · RightShift reopens", function() window.Visible = false end)
    button("Unload", function() app:Unload(false) end)
    local reopen = new("TextButton", {Name = "Reopen", Size = UDim2.fromOffset(48, 28), Position = UDim2.fromOffset(8, 8),
        Text = "Egg", TextSize = 13, BackgroundColor3 = Color3.fromRGB(44, 53, 67),
        TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.Gotham}, bounds)
    connect(reopen.Activated, function() window.Visible = not window.Visible end)
    connect(Input.InputBegan, function(event, processed)
        if not processed and event.KeyCode == Enum.KeyCode.RightShift then window.Visible = not window.Visible end
    end)
    local function resize()
        local size = bounds.AbsoluteSize
        if size.X <= 0 or size.Y <= 0 then return end
        scale.Scale = math.min(1, math.max(0.35, math.min((size.X - 20) / 320, (size.Y - 55) / 320)))
        window.Position = UDim2.fromOffset(10, math.min(42, math.max(0, size.Y - 320 * scale.Scale)))
    end
    connect(bounds:GetPropertyChangedSignal("AbsoluteSize"), resize)
    resize()
    app.ui = {gui = gui, window = window, start = start, info = info,
        hatch = hatch, repeatRuns = repeatButton, difficulty = difficultyButton}
end
function app:Diagnostics()
    local lines = {"Place: " .. tostring(game.PlaceId), "Round controller: " .. tostring(RS:FindFirstChild("BreakTheEgg") ~= nil),
        "Queue: " .. tostring(self.status.queue or "idle"),
        "No premium purchases, class rolls or inventory selling/deletion.",
        "Prompt API=" .. tostring(type(fireproximityprompt) == "function") .. "; touch API=" .. tostring(type(firetouchinterest) == "function")
            .. " (queue touch listener absent; no unverified touch call)",
        self:roundDiagnostics(), self.saveStatus or "Settings not saved yet"}
    for lane, r in pairs(shared.calls) do table.insert(lines, lane .. ": " .. r.action .. " age=" .. math.floor(os.clock() - r.started)) end
    for name, reason in pairs(self.moduleErrors) do table.insert(lines, name .. ": " .. tostring(reason)) end
    for key, block in pairs(self.blocks) do table.insert(lines, key .. ": " .. tostring(block.reason)) end
    for i = math.max(1, #self.notes - 10), #self.notes do table.insert(lines, self.notes[i]) end
    return table.concat(lines, "\n")
end

local function render()
    local ui, s = app.ui, app.settings
    if not ui.start then return end
    ui.start.Text = app.running and "Stop" or "Start"
    if not app.running then ui.info.Text = "Stopped · AFK runs / boss evasion / Claim All"
    elseif game.PlaceId == 104087083666671 then
        ui.info.Text = (app.status.farm or gate() or "Checking round") .. "\n" .. (app.status.chests or "Checking chests")
        if app.afkError then ui.info.Text = (app.status.farm or "Checking round") .. "\n" .. app.afkError end
    else
        ui.info.Text = gate() or ((app.status.perks or "Checking upgrades") .. "\n"
            .. (app.status.eggs or "Checking eggs") .. "\n" .. (app.status.queue or ""))
        if app.afkError then ui.info.Text = (app.status.queue or "Preparing lobby") .. "\n" .. app.afkError end
    end
    ui.repeatRuns.Text = "Repeat runs + resume: " .. (s.repeatRuns and "ON" or "OFF")
    ui.difficulty.Text = "Next difficulty: " .. s.difficulty
    ui.hatch.Text = "Hatch ready eggs: " .. (s.hatch and "ON" or "OFF")
end
local uiOK, uiError = pcall(buildUI)
if not uiOK then
    app:note("UI startup failed: " .. tostring(uiError))
    app:Unload(true)
    error("[CrackEgg] UI startup failed; reexecution is recoverable: " .. tostring(uiError))
end

connect(player.AttributeChanged, function(name)
    if name == "Gems" or string.sub(name, 1, 5) == "Perk_" then
        -- Replication is a wake-up signal, never a substitute for State before spending.
        app.refreshAt = 0
    end
end)
connect(player.CharacterAdded, function()
    app:release()
    app:restoreSpeed()
    app.perks = nil
    app.refreshAt = 0
end)
-- Idle input is scoped to this running instance and its matching release.
-- It uses neither farming clicks nor premium GUI buttons.
function app:releaseIdle()
    local held = self.idleHeld
    if held then
        local ok = pcall(held.user.Button2Up, held.user, Vector2.new(0, 0), held.frame)
        if not ok then return false end
        self.idleHeld = nil
    end
    return true
end
if player.Idled then
    connect(player.Idled, function()
        if not app.running or app.idleHeld or game:GetService("GuiService").MenuIsOpen then return end
        local camera = workspace.CurrentCamera
        if not camera then return end
        local ok, user = pcall(game.GetService, game, "VirtualUser")
        if not ok then app:note("Idle prevention unavailable: " .. tostring(user)) return end
        local held = {user = user, frame = camera.CFrame}
        app.idleHeld = held
        local pressed, err = pcall(function()
            user:CaptureController()
            user:Button2Down(Vector2.new(0, 0), held.frame)
        end)
        if not pressed then app:note("Idle prevention failed: " .. tostring(err)) app:cleanupOwned() return end
        task.delay(0.2, function() if app.idleHeld == held then app:releaseIdle() end end)
    end)
end
if player.OnTeleport then
    connect(player.OnTeleport, function(state)
        if state == Enum.TeleportState.Started then
            app:queueResume()
            app.teleporting = true
            app:release()
            app:restoreSpeed()
            app:releaseIdle()
        elseif state == Enum.TeleportState.Failed then
            app.teleporting, app.recoveryPending = false, nil
            app:note("Teleport failed; intended automation retained")
        end
    end)
end
local teleportService = game:GetService("TeleportService")
if teleportService.TeleportInitFailed then
    connect(teleportService.TeleportInitFailed, function(who, result, message)
        if who == player and app.teleporting then
            app.teleporting, app.recoveryPending = false, nil
            app:note("Teleport initialization failed: " .. tostring(message or result))
        end
    end)
end

local lastTick, lastRender, lastTeardown = 0, 0, 0
if RunService.PreSimulation then
    connect(RunService.PreSimulation, function()
        local ok, err = pcall(app.physicsRound, app)
        if not ok and (app.retries.physicsNote or 0) <= os.clock() then
            app:note("Physics contract error: " .. tostring(err))
            app.retries.physicsNote = os.clock() + 10
        end
    end)
end
connect(RunService.Heartbeat, function()
    local now = os.clock()
    if now - lastTick < 0.1 then return end
    lastTick = now
    if now - lastTeardown >= 5 then
        lastTeardown = now
        retryTeardown()
        if app.cleanupPending and not app.running then app:cleanupOwned() end
    end
    if app.saveAt and now >= app.saveAt then app:save() end
    local catalog, catalogErr
    if game.PlaceId == 137477934962022 then catalog, catalogErr = module("EggPlayerPerks", "Catalog") end
    app.moduleErrors.Catalog = catalogErr
    readReceipts(catalog)
    if app.running then
        local watchOK, watchErr = pcall(app.watchdog, app)
        if not watchOK and (app.retries.watchNote or 0) <= now then app:note("AFK watchdog: " .. tostring(watchErr)) app.retries.watchNote = now + 10 end
        local roundOK, roundErr = pcall(app.stepRound, app)
        if not roundOK and (app.retries.roundNote or 0) <= now then
            app:note("Round contract error: " .. tostring(roundErr))
            app.status.farm = "Round contract error; see diagnostics"
            app.retries.roundNote = now + 10
        end
        local presentOK, presentErr = pcall(app.presentations, app)
        if not presentOK and (app.retries.presentNote or 0) <= now then app:note(presentErr) app.retries.presentNote = now + 10 end
    end
    if app.running and game.PlaceId == 137477934962022 and not gate() then
        local ok, err = pcall(stepPerks, catalog)
        if not ok then status("perks", "Contract error; see diagnostics") fail("perk-state", "state", tostring(err)) end
        local rules, rulesErr = module("EggHatchery", "Rules")
        local crafted, craftErr = module("EggClassesShared", "CraftedClasses")
        app.moduleErrors.Rules, app.moduleErrors.CraftedClasses = rulesErr, craftErr
        local eggsOK, eggsErr = pcall(stepEggs, rules, crafted, inventory())
        if not eggsOK then
            status("eggs", "Inventory/contract error; see diagnostics")
            if (app.retries.errorNote or 0) <= now then app:note(eggsErr) app.retries.errorNote = now + 10 end
        end
    end
    if now - lastRender >= 0.25 then lastRender = now render() end
end)
if app.settings.resume then app:Start() end
render()
app:note("Ready. AFK repeat runs, boss warning evasion, scientist priority and Claim All. Lobby walk / round tween. Hatching remains opt-in.")
return app








