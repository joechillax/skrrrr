task.wait(7)
-- ChestFarmAutoLoop.lua: put this complete file in the executor's auto-execute folder.
-- Revision 11: native SaveGear church prompt and confirmation, with pre-timer church bookmarks.
-- Hides the default Gameplay Paused popup after readiness; streaming pauses still apply.
-- Includes Discord ending reports, cached discovery, and Blinker / identified boss ranged dodging.
-- Continuous segmented depth travel; no healing, mining, selling, shops or team purchases.
-- Every fresh execution and queued teleport resume waits seven seconds first.
-- All additional readiness checks and recovery happen automatically.
local SOURCE = [======[
return function(source)
    local env = (getgenv and getgenv()) or _G
    local KEY = "__ChestFarmAutoLoop_20261009"
    local REVISION = 11
    local BUILD = "r11-native-church-save"
    local job = tostring(game.PlaceId) .. ":" .. tostring(game.JobId)
    local previous = env[KEY]
    if previous and previous.job == job and previous.thread
        and coroutine.status(previous.thread) ~= "dead"
        and ((previous.revision or 1) > REVISION
            or ((previous.revision or 1) == REVISION and previous.build == BUILD)) then
        return -- auto-execute and a queued resume may both arrive; only one owns this server.
    end
    if previous and previous.farm then
        pcall(previous.farm.dispose)
    end
    if previous and previous.thread and previous.thread ~= coroutine.running() then
        pcall(task.cancel, previous.thread)
    end
    if previous and previous.connections then
        for _, connection in ipairs(previous.connections) do pcall(function() connection:Disconnect() end) end
    end
    if previous and previous.gui then pcall(previous.gui.dispose); previous.gui = nil end
    local s = previous and previous.job == job and previous or {}
    if s.revision ~= REVISION or s.build ~= BUILD then s.queueArmed = nil end
    s.revision, s.build = REVISION, BUILD
    s.pauseNoticeHidden, s.pauseNoticeRetryAt, s.pauseNoticeWarned = nil, nil, nil
    s.job, s.owner, s.connections = job, {}, {}
    s.farm, s.teleporting, s.status = nil, false, nil
    s.signalsBound = false
    s.teleportSignalsBound, s.departureBound = false, false
    s.currencyBound, s.classBound = false, false
    s.achievementsLoading, s.itemCategoriesLoading, s.itemDatabaseLoading = false, false, false
    s.classResolverLoading = false
    env[KEY] = s
    local owner = s.owner
    local Players = game:GetService("Players")
    local RS = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local CollectionService = game:GetService("CollectionService")
    local TeleportService = game:GetService("TeleportService")
    local FRESH_SETTING = "ChestFarmAutoLoop_FreshRun"
    if not s.freshChecked then
        local ok, value = pcall(function() return TeleportService:GetTeleportSetting(FRESH_SETTING) end)
        if ok and value == true then s.forceFresh = true end
        s.freshChecked = true
    end
    local unpackValues = table.unpack or unpack
    local function pack(...) return { n = select("#", ...), ... } end
    local function now() return os.clock() end
    s.stats = s.stats or { started = now(), coreEarned = 0, coinEarned = 0, gems = 0,
        promptFires = 0, lootObserved = 0, badgeClaims = 0, chestProgress = 0 }
    s.chests = s.chests or {}
    s.stats.chestStarts = s.stats.chestStarts or 0
    s.claims = s.claims or {}
    s.gemSeen = s.gemSeen or setmetatable({}, { __mode = "k" })
    local function owned() return env[KEY] == s and s.owner == owner end
    local requestSlots = { "request", "rewardRequest", "classRequest", "skipRequest", "probeRequest", "equipmentRequest", "lootRequest", "lootQuery", "upgradeRequest" }
    local function requestSlot(kind)
        if kind == "claim-reward" or kind == "claim-vip" then return "rewardRequest" end
        if kind == "class-data" or kind == "select-class" then return "classRequest" end
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
    local URL = 'https://discord.com/api/webhooks/1551830162650435584/V_EItPsWyCQDQgEvZlAGjaH4XoKXchAD6UbPwEiiJ6mPUmiU-2cOlioFzvPW79KlZGgu?wait=true'
    local SETTING, FILE = 'EarthAutofarm_Reports_v1', 'EarthAutofarmReports.json'
    local ok, http = pcall(function() return game:GetService('HttpService') end)
    if not ok then http = nil end
    local function notice(message)
        if s.reportNotice ~= message then s.reportNotice = message; warn('[Earth Results] ' .. message) end
    end
    local function clock() return os.time() end
    local ledger = s.reportLedger
    if not ledger then
        local read, value = pcall(function() return api.TeleportService:GetTeleportSetting(SETTING) end)
        if read and type(value) == 'table' then ledger = value end
        local reader = env.readfile or readfile
        if not ledger and http and type(reader) == 'function' then
            local found, body = pcall(reader, FILE)
            if found then
                local decoded, data = pcall(function() return http:JSONDecode(body) end)
                if decoded and type(data) == 'table' then ledger = data end
            end
        end
    end
    ledger = type(ledger) == 'table' and ledger or {}
    ledger.records = type(ledger.records) == 'table' and ledger.records or {}
    s.reportLedger = ledger
    local function persist()
        pcall(function() api.TeleportService:SetTeleportSetting(SETTING, ledger) end)
        local writer = env.writefile or writefile
        if http and type(writer) == 'function' then
            pcall(function() writer(FILE, http:JSONEncode(ledger)) end)
        end
    end
    local function clean(text, limit)
        text = tostring(text):gsub('[%c]', ' '):gsub('[@`*_~|<>]', '')
        return text:sub(1, limit or 100)
    end
    local function finite(value)
        value = tonumber(value)
        return value and value == value and math.abs(value) < math.huge and value >= 0 and value or nil
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
    function R.observe(player, isPlanet, live)
        if not isPlanet then return end
        local run = s.reportRun
        if not run then
            run = {id = s.job, started = now(), gained = {}, cores = nil}
            s.reportRun = run
        end
        if run.ended then return end
        run.cores = finite(player:GetAttribute('CoresEarned')) or run.cores
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
        return {id = run.id, status = 'queued', attempts = 0, created = clock(), body = {
            username = 'Earth Autofarm',
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
        local record = payload(outcome, reason)
        if not record then return end
        s.reportRun.ended = true
        ledger.departure = nil
        enqueue(record)
        R.pump()
    end
    function R.departing(outcome, reason)
        local record = payload(outcome, reason)
        if record then ledger.departure = record; persist() end
    end
    function R.failedTeleport()
        if ledger.departure and ledger.departure.id == s.job then ledger.departure = nil; persist() end
    end
    function R.arrived(isLobby)
        local staged = ledger.departure
        if isLobby and staged and staged.id ~= s.job then
            ledger.departure = nil; enqueue(staged)
        end
    end
    function R.pump()
        local waiting = false
        for _, record in ipairs(ledger.records) do if record.status == 'queued' then waiting = true; break end end
        if not waiting then return end
        if not http then notice('HttpService unavailable; farming continues without Discord reports.'); return end
        local send = env.request or env.http_request or http_request or request
            or (env.syn and env.syn.request) or (syn and syn.request)
            or (env.http and env.http.request)
        if type(send) ~= 'function' then
            notice('Executor HTTP request API unavailable; results remain queued.'); return
        end
        for _, record in ipairs(ledger.records) do
            if record.status == 'queued' and clock() >= (record.retryAt or 0) then
                -- Persist before dispatch. An uncertain send is never blindly repeated after teleport/re-execution.
                record.status, record.sentAt = 'sending', clock()
                record.attempts = (record.attempts or 0) + 1
                persist()
                task.spawn(function()
                    local encoded, body = pcall(function() return http:JSONEncode(record.body) end)
                    if not encoded then record.status = 'failed'; persist(); notice('Result encoding failed.'); return end
                    -- Empty Lua tables encode ambiguously; use an explicit empty JSON array for mentions.
                    body = '{"allowed_mentions":{"parse":[]},' .. body:sub(2)
                    local sent, response = pcall(send, {Url = URL, Method = 'POST',
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
                    persist()
                end)
                return
            end
        end
    end
    return R
end
]=====]
    local reports = assert((loadstring or load)(REPORT_SOURCE, '@EarthResults'))()({
        state = s, env = env, now = now, TeleportService = TeleportService
    })
    local function reportDeparture()
        local player, model, humanoid, root = character()
        if player and player:GetAttribute('SavedExitTeleportLocked') == true then
            return 'EXTRACTED', 'Game saved-exit state confirmed; lobby arrival and saved item contents remain unverified.'
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
    local function restoreZoneOrigin()
        local _, model, _, root = character()
        if root and model == s.zoneOriginCharacter and s.zoneOrigin then
            pcall(function() root.CFrame = s.zoneOrigin end)
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
    local function armResume()
        if s.queueArmed then return end
        local queue = env.queue_on_teleport or env.queueonteleport or queue_on_teleport or queueonteleport
        if type(queue) ~= "function" then
            local synApi, fluxusApi = env.syn or syn, env.fluxus or fluxus
            queue = (type(synApi) == "table" and synApi.queue_on_teleport)
                or (type(fluxusApi) == "table" and fluxusApi.queue_on_teleport)
        end
        if type(queue) ~= "function" then
            if not s.queueNotice then
                s.queueNotice = true
                warn("[ChestFarm Auto] No queue-on-teleport API. Continuation depends on executor auto-execute running after each teleport.")
            end
            return
        end
        local resume = "task.wait(7)\nlocal source=" .. string.format("%q", source)
            .. "\nlocal loader=loadstring or load; local chunk,why=loader(source,'@ChestFarmAutoLoop'); assert(chunk,why); chunk()(source)"
        local ok, why = pcall(queue, resume)
        if ok then s.queueArmed = true
        elseif not s.queueNotice then s.queueNotice = true; warn("[ChestFarm Auto] Could not queue teleport resume: " .. tostring(why)) end
    end
    -- Transition calls remain serialized. Independent read/reward/skip calls have
    -- bounded slots so a stuck optional feature cannot lock the gameplay loop.
    local function request(kind, service, method, args, finished)
        local slot = requestSlot(kind)
        if s[slot] or now() < (s.requestBackoff[service .. "." .. method] or 0) then return false end
        if slot == "request" and (s.awaiting or now() < (s.nextAction or 0)) then return false end
        local rf = remote(service, method)
        if not rf then status("Waiting for " .. service .. "." .. method); return false end
        local token = { kind = kind, started = now(), callback = finished,
            method = service .. "." .. method, character = Players.LocalPlayer and Players.LocalPlayer.Character,
            farm = s.farm, owner = owner }
        s[slot] = token
        if slot == "request" then stopFarm(); armResume() end
        status("Requesting " .. method)
        task.spawn(function()
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
        s.classData = data
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
        for _, record in pairs(s.chests) do
            if record.attempted and record.model and not record.model.Parent and not record.removalRecorded then
                record.removalRecorded, record.retired = true, true
                s.stats.lootObserved, s.lastLootAt = s.stats.lootObserved + 1, now()
                print('[ChestFarm] Observed chest removal: ' .. record.model.Name)
            end
        end
        local cores = tonumber(player:GetAttribute("Cores"))
        local earned = tonumber(player:GetAttribute("CoresEarned"))
        if earned then
            if s.lastRunCores and not s.currencyBound then
                s.stats.coreEarned = s.stats.coreEarned + math.max(0, earned - s.lastRunCores)
            end
            s.lastRunCores = earned
        end
        if cores then
            s.lastCores = cores
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
                            record.sent = accepted(result)
                            record.retryAt = now() + 15
                        end) then return end
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
                    if token.callback and not staleLife then token.callback(token.result) end
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
                connect(signal, function(amount, _, isCore)
                    local key = isCore and "coreEarned" or "coinEarned"
                    s.stats[key] = s.stats[key] + math.max(0, tonumber(amount) or 0)
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
                    stopFarm(); armResume(); status("Teleport in progress")
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
                connect(departure, function() stopFarm(); armResume(); s.departureAt = now() end)
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
                s.zone, s.zoneOwned, s.startedZone, s.touchCandidate = nil, false, nil, nil
                s.partyToken = nil
                local c = controller("PartyCreateController")
                if c then c.StartRequest = nil end
                restoreZoneOrigin()
                task.delay(0.2, function() if owned() then restoreZoneTouches() end end)
            end)
        end
    end

    local FARM_SOURCE = [====[return function(ctx) local __farmConnect=ctx.connect; local __farmCheck=ctx.check; local __farmCapture=ctx.capture or function(_,fn)return fn end; return (function(...) return (function(p, V, N, Y, i, w, a, A, Q, x, b, M, t, f, u, h, j, K, q, B, J, v, e, W) e, B, J, M, q, K, h, W, u, j, b, Q, x, A, v, t, f = function(p, z) local i = K(z) local w = function(w) return B(p, { w, }, z, i) end return w end, function(B, w, Y, a) local r, UL, n, yL, xL, J, rL, y, d, QL, SL, qL, aL, WL, m, tL, OL, g, XL, X, R, D, jL, bL, YL, hL, P, iL, l, fL, gL, G, ML, v, CL, s, S, I, VL, uL, sL, h, H, IL, eL, vL, EL, wL, lL, K, GL, LL, f, o, E, NL, pL, mL, F, U, C, JL, AL, RL, KL, FL, cL, ZL, T, V, TL, zL, c, BL, O, HL, nL, k, Z, L, kL, dL while B do __farmCheck() if 8404549 > B then if B < 3481681 then if 2011092 > B then if B > 1064961 then if B < 1609571 then if 1429944 > B then if 1239341 > B then if B < 1072920 then V = 4388422 < 10995253 Q[J] = V B = 3322234 elseif 1085528 > B then B = X and 5601817 or 8311567 elseif 1160137 > B then d = p["table"] B = 8892653 V = d["insert"] d = V(O, g) else n = 14928581 >= 10257774 B = n and 4197832 or 4298790 end else if B < 1280438 then B = 10686391 elseif B < 1348147 then S = Q[Y[5]] g = S() S = Q[Y[6]] I = g < S B = I and 1793345 or 13638227 elseif B < 1400796 then B, V = p["C0hCoOBmSW4z"], { } else B = 16132387 end end else if B < 1505944 then if B < 1461734 then B = Q[Y[4]] K = p["string"] J = K["format"] v = b(v) E = Q[Y[5]] O = E() f = O * 100 K = { J("HP recovered (%.0f%%) - resuming.", f), } V = B(i(K)) B = Q[Y[6]] V = B() V, B = { }, p["1UvyrOAZFVpJ"] elseif B < 1485322 then V = { "locked", } B = p["cVcC1O7PYjIfh"] elseif 1497136 > B then Q[Y[20]] = Q[Y[20]] + 1 V = Q[Y[5]] n = g["Model"] H = n["Name"] B = 7368094 L = #d T = L .. " enemies nearby." n = ": " .. T U = H .. n r = "SKIP " .. U R = V(r) V = Q[Y[13]] R = V() else B = 10252446 end else if B < 1510312 then s = p["_G"] O = s["ScanX"] s = Q[Y[4]] B = 5335161 E = O <= s h = E elseif 1532646 > B then h = J B = W() Q[B] = h h = B B = W() Q[B] = f O = Q[h] E, f = O, B B = O and 14419034 or 5413919 elseif 1575133 > B then B = Q[Y[1]] J = p["Vector3"] v = J["zero"] B["AssemblyLinearVelocity"] = v B = Q[Y[1]] J = p["CFrame"] v = J["new"] K = Q[Y[4]] J = v(K) B["CFrame"] = J V, B = { }, p["ROxgz2l0i05Xr"] else V = W() Q[V] = m m = V V = Q[m] I = V["IsA"] I = I(V, "Model") B = I and 12336406 or 14876967 end end end else if 1817177 > B then if B > 1712184 then if 1726952 > B then d = p["task"] V = d["wait"] B = 11809829 d = V(0.15) elseif 1741176 > B then I = b(I) B = 2595611 elseif 1770548 > B then V = Q[Y[1]] B = V["Enabled"] V = { B, } B = p["XnvnjSt4Q3HERl"] else S = Q[Y[7]] g = S() I = not g B = I and 5773972 or 10007280 end else if B < 1657071 then B = { } Q[Y[2]] = B V = J % 35184372088832 Q[Y[4]] = V E = J % 255 B = 9771883 f = E + 2 Q[Y[5]] = f E = #v K[J] = "" s = "" m = E S = 1 g = 1 < 0 I = 1 - 1 elseif B < 1697108 then B = Q[Y[10]] J = Q[Y[11]] v[B] = J B = Q[Y[12]] J = { B(v), } V, B = { i(J), }, p["lh5PseQNXv0eU"] elseif 1703591 > B then B = 2638638 pL = C[1] o = pL else B = 11121287 end end else if 1918041 > B then if 1841386 > B then V = Q[J] B = V ~= "fR2yublGNor" B = B and 13124183 or 11317998 elseif B < 1868693 then I = p["math"] O = I["random"] I = W() Q[I] = O S = p["table"] O = S["concat"] r = p["table"] d, B = r, r and 6267227 or 3338712 elseif B < 1904569 then B = 14876967 else B = 7570852 end else if B < 1964428 then B = Q[Y[4]] V = B() B = 16500342 >= 3307824 V = { B, } B = p["OxSqrQUO0cliv"] elseif 2007693 > B then K = v["WaitForChild"] B = 12182679 K = K(v, "Humanoid", 5) J = K else B = p["_G"] v = 14380748 > 14527838 B["ChestFarm"] = v B = 13787160 end end end end else if 574474 > B then if B > 392133 then if B > 525443 then if 538447 > B then B = 8017606 O = f["Enabled"] E = not O V = E elseif 545901 > B then V = p["_G"] B = V["SafeMode"] B = B and 9609369 or 2274060 elseif B < 552440 then B = 2564830 else I = Q[J] S = 8217649 > 8562236 m = I == S B = m and 6453497 or 13662550 end else if 435026 > B then B = 2317164 K = v["MaxHealth"] J = K <= 0 V = J elseif B < 469246 then V = Q[Y[3]] B = 7493530 f = V("STOP after 40 empty scans.") V = p["_G"] E = 1917900 >= 16148366 V["ChestFarm"] = E elseif 497347 > B then B = 10686391 else B = W() Q[B] = s s = B m = Q[s] I = m["IsA"] I = I(m, "Model") B, X = I and 3736778 or 5826503, I end end else if B > 255903 then if 278661 > B then B = V and 13746815 or 10220335 elseif B < 297941 then B, X = 3425667, I elseif B < 336954 then B, V = p["DKU4gHLEVaxxF"], { V, } else V = p["task"] B = V["spawn"] v = Q[Y[6]] V = B(v) B = 4979985 end else if 87561 > B then B, X = 1079472, g elseif 174871 > B then J = Q[Y[3]] v = J % 32 E = Q[Y[3]] f = E - v h = f / 32 J = 13 - h f = Q[Y[4]] s = Q[Y[2]] X = 2 ^ J O = s / X E = f(O) h = E % 4294967296 f = 2 ^ v B = 7985072 K = h / f f = Q[Y[4]] s = K % 1 O = s * 4294967296 E = f(O) f = Q[Y[4]] O = f(K) h = E + O f = h % 65536 O = h - f E = O / 65536 s = f % 256 I = f % 256 m = f - I X = m / 256 m = E % 256 g = E % 256 S = E - g I = S / 256 O = { s, X, m, I, } Q[Y[1]] = O elseif 240527 > B then K = Q[Y[6]] B = 2698186 J = K == v V = J else V = p["task"] v = w[1] B = V["wait"] V = B(0.3) B = Q[Y[3]] V = B(v) B = p["_G"] J = 12333726 < 486718 B["SafeMode"] = J B, V = p["4eYXjxIQ9PybJ6"], { } end end end else if 855126 > B then if B < 697059 then if 602693 > B then v = p["_G"] V = v["SafeMode"] B = not V B = B and 12536449 or 2643329 elseif B < 610826 then K, O = K + f, not E V = h >= K V = O and V O = h <= K O = E and O V = O or V B = V and 4319611 B = B or 13056992 elseif B < 639260 then V = E or 20 f = V V = Q[Y[5]] s = p["string"] O = s["format"] m = Q[Y[4]] I = Q[Y[7]] s = { O("START scan x=%.0f -> %.0f, step %d", J, m, I), } B = 9272629 E = V(i(s)) else B = f and 6010191 or 6450991 end else if 727910 > B then B, V = p["lhdwuZDfJ7VLZ"], { } elseif 769576 > B then R = r k = R d[R] = k B = 15491759 elseif B < 812400 then B = Q[Y[1]] J = Q[Y[4]] h = p["Vector3"] K = h["new"] h = K(0, 5, 0) v = J + h B["CFrame"] = v V, B = { }, p["RdSTEnvwRUBHUu"] else B = 3322234 end end else if B < 964029 then if 918230 > B then D = YL B = 10850024 elseif B < 943575 then B = 1228690 elseif 950679 > B then r = g["Model"] R = r["Parent"] B, V = R and 5867209 or 8588739, R else d = Q[Y[8]] R = d() d = Q[Y[9]] V = R < d B = V and 14627229 or 947254 end else if B < 994143 then B = 15862886 elseif B < 1038942 then B = { } Q[Y[2]] = B v = Q[Y[3]] B = p["WbO1tKfqeZe9la"] V = v["Stepped"] J = u(595914, { Y[4], Y[5], Y[6], Y[1], Y[7], Y[8], }) v = __farmConnect v = v(V, J) Q[Y[1]] = v V = Q[Y[7]] J = V("NOCLIP ON (safe mode).") V = { } else B = 8311567 end end end end end else if B < 2651989 then if 2388112 > B then if 2279311 > B then if 2208252 > B then if 2058753 > B then K = Q[Y[9]] B = { } v, h = B, K B = 10880782 f = 1 E = 1 < 0 K = 1 - 1 elseif 2109309 > B then B = 2660989 f = J["Position"] K = f elseif 2158057 > B then V, B = { }, p["1Xf0UZsd8gWN4"] else V = Q[Y[23]] E = V() V = Q[Y[5]] B = p["lldyNIb4f3kX"] E = V("STOP scan.") V = { } end else if B < 2227270 then B = Q[Y[12]] V = B() V = { "ok", } B = p["JkeD1O4nCoQhL"] elseif B < 2241006 then V = { "no-prompt", } B = p["VFd2289VPIPG"] elseif 2258060 > B then h = Q[Y[7]] f = h() V = not f B = V and 11226927 or 13903632 else B = 8607109 <= 2123643 V = { B, } B = p["qBosAWrwunC3z"] end end else if B > 2321944 then if 2328078 > B then B, V = p["JTmUlsHdjaFoOP"], { } elseif 2341956 > B then O = 13017433 > 15527500 E["CanCollide"] = O B = 13155724 elseif B < 2366714 then B = 7156397 U = p["tonumber"] n = Q[I] H = U(n) r = H or 0 R = r < 0.5 g = R else B = Q[Y[1]] v = Q[Y[4]] B["CanCollide"] = v V, B = { }, p["n69OK5iqpzwjeG"] end else if 2298851 > B then Q[J] = H n = Q[J] B = n and 14924226 or 973955 elseif B < 2314885 then J = J + h V, E = K >= J, not f V = E and V E = J >= K E = f and E V = E or V B = V and 9369623 B = B or 8825855 elseif 2316897 > B then B = 1895623 else B = V and 3561277 or 7007230 end end end else if B < 2569018 then if B < 2443283 then if 2406107 > B then B = 5524880 K = Q[Y[1]] J = K["Character"] V = J elseif B < 2415278 then g = p["Instance"] S = g["new"] g = S("ScreenGui") g["Name"] = "ChestFarmMenu" d = 14164689 <= 12336477 g["ResetOnSpawn"] = d g["DisplayOrder"] = 999 d = I g["Parent"] = d d = p["Instance"] S = d["new"] d = S("Frame") d["Name"] = "Main" r = p["UDim2"] R = r["new"] r = R(0, 220, 0, 200) d["Size"] = r r = p["UDim2"] R = r["new"] r = R(0, 20, 0, 120) d["Position"] = r r = p["Color3"] R = r["fromRGB"] r = R(25, 25, 30) d["BackgroundColor3"] = r V = { } d["BorderSizePixel"] = 0 R = 11185489 > 5251094 d["Active"] = R iL = W() R = 14905430 > 1715190 d["Draggable"] = R R = g d["Parent"] = R R = p["Instance"] S = R["new"] R = S("UICorner", d) G = p["UDim"] r = G["new"] G = r(0, 8) R["CornerRadius"] = G R = p["Instance"] S = R["new"] R = S("TextLabel") G = p["UDim2"] r = G["new"] G = r(1, 0, 0, 28) R["Size"] = G VL = W() R["BackgroundTransparency"] = 1 R["Text"] = "\240\159\159\163 Chest Farm" U = p["Enum"] G = U["Font"] r = G["GothamBold"] R["Font"] = r R["TextSize"] = 15 G = p["Color3"] KL = W() r = G["fromRGB"] G = r(255, 255, 255) R["TextColor3"] = G BL = W() r = d R["Parent"] = r r = p["Instance"] S = r["new"] r = S("TextButton") S = W() Q[S] = r r = Q[S] r["Name"] = "Scan" r = Q[S] k = p["UDim2"] U = k["new"] k = U(1, -20, 0, 36) r["Size"] = k r = Q[S] k = p["UDim2"] U = k["new"] k = U(0, 10, 0, 36) r["Position"] = k r = Q[S] k = p["Color3"] U = k["fromRGB"] k = U(60, 90, 180) r["BackgroundColor3"] = k r = Q[S] r["Text"] = "SCAN: OFF" r = Q[S] l = p["Enum"] k = l["Font"] QL = W() U = k["GothamBold"] r["Font"] = U r = Q[S] r["TextSize"] = 15 r = Q[S] k = p["Color3"] U = k["fromRGB"] k = U(255, 255, 255) r["TextColor3"] = k r = Q[S] U = d r["Parent"] = U G = p["Instance"] r = G["new"] k = Q[S] G = r("UICorner", k) k = p["UDim"] U = k["new"] aL = W() k = U(0, 8) G["CornerRadius"] = k NL = W() G = p["Instance"] r = G["new"] G = r("TextLabel") r = W() Q[r] = G G = Q[r] G["Name"] = "Status" G = Q[r] l = p["UDim2"] k = l["new"] l = k(1, -20, 0, 118) G["Size"] = l G = Q[r] l = p["UDim2"] k = l["new"] l = k(0, 10, 0, 80) G["Position"] = l G = Q[r] G["BackgroundTransparency"] = 1 G = Q[r] G["Text"] = "Status: FARM \240\159\159\162\010Loot: 0 | Skip: 0\010Locked: 0\010Scan: -" G = Q[r] Z = p["Enum"] l = Z["Font"] vL = W() k = l["Gotham"] G["Font"] = k G = Q[r] G["TextSize"] = 13 G = Q[r] l = p["Color3"] wL = W() B = p["Wv58s2ycZEbA"] k = l["fromRGB"] l = k(200, 200, 200) G["TextColor3"] = l G = Q[r] P = W() k = 4535226 >= 3350811 G["TextWrapped"] = k G = Q[r] k = d Z = W() c = W() G["Parent"] = k zL = W() C = W() k = W() Q[k] = 80 Q[Z] = 0 Q[C] = 3 y = W() Q[y] = 0.02 Q[c] = 0.05 Q[P] = 3 Q[zL] = 0.1 Q[wL] = 0.3 Q[BL] = 0.6 Q[iL] = 100 Q[aL] = 0.4 Q[NL] = 150 Q[VL] = ctx.scanEnd or 36000 Q[QL] = 1200 Q[vL] = 0.6 Q[KL] = 0 l = W() Q[l] = 0 WL = W() Q[WL] = 0 JL = p["_G"] JL["ScanInfo"] = "-" eL = W() hL = q(3906543, { h, J, }) fL = x(7594730, { O, h, J, }) JL = W() Q[JL] = hL hL = W() bL = e(14923516, { h, J, }) Q[hL] = bL qL = e(8419400, { O, h, J, }) bL = W() Q[bL] = fL fL = W() Q[fL] = qL qL = W() uL = u(4085716, { fL, h, J, }) xL = W() AL = A(10832111, { xL, h, J, }) Q[qL] = uL uL = { } Q[xL] = uL tL = e(14695700, { O, h, J, xL, }) dL = __farmCapture(14099732, u(14099732, { C, Z, h, J, y, })) Q[eL] = nil uL = W() Q[uL] = tL tL = W() Q[tL] = AL AL = W() jL = A(9814636, { eL, xL, K, h, J, tL, hL, uL, }) y = b(y) Q[AL] = jL ML = Q[O] eL = b(eL) K = b(K) jL = ML["CharacterAdded"] ML = __farmConnect IL = q(10628738, { h, J, xL, }) ML = ML(jL, IL) ML = x(12898395, { fL, h, J, hL, }) jL = W() Q[jL] = ML IL = W() Q[IL] = nil EL = e(8056308, { O, h, J, IL, hL, }) ML = W() Q[ML] = EL EL = Q[ML] sL = Q[O] mL = sL["Character"] OL = EL(mL) OL = Q[O] EL = OL["CharacterAdded"] XL = j(5573090, { bL, h, J, JL, }) mL = j(248418, { h, J, ML, }) OL = __farmConnect OL = OL(EL, mL) OL = x(10439019, { h, J, r, KL, l, WL, }) mL = __farmCapture(13917854, x(13917854, { h, J, })) EL = W() Q[EL] = OL SL = __farmCapture(9164528, u(9164528, { bL, h, J, WL, JL, EL, })) OL = W() Q[OL] = mL gL = W() sL = __farmCapture(7185824, M(7185824, { h, J, O, })) uL = b(uL) mL = W() Q[mL] = sL sL = W() ML = b(ML) Q[sL] = XL HL = A(9382639, { h, J, S, EL, }) XL = W() rL = __farmCapture(2847902, t(2847902, { h, J, bL, iL, gL, AL, hL, qL, EL, })) Q[XL] = SL tL = b(tL) RL = __farmCapture(12562248, A(12562248, { h, J, bL, hL, qL, EL, })) O = b(O) Q[gL] = nil SL = W() Q[SL] = rL rL = W() r = b(r) Q[rL] = RL GL = __farmCapture(16446958, x(16446958, { SL, h, J, rL, qL, BL, bL, gL, aL, })) RL = W() Q[RL] = GL nL = __farmCapture(7136366, u(7136366, { h, J, bL, })) SL = b(SL) GL = W() UL = __farmCapture(16361397, t(16361397, { h, J, bL, jL, sL, JL, OL, GL, c, KL, hL, EL, })) Q[GL] = dL BL = b(BL) xL = b(xL) dL = W() Q[dL] = UL UL = W() Q[UL] = HL IL = b(IL) HL = W() Q[HL] = nL LL = __farmCapture(3369653, t(3369653, { h, J, HL, VL, hL, bL, NL, qL, wL, RL, zL, jL, EL, vL, XL, QL, JL, mL, k, l, dL, rL, UL, })) nL = W() Q[nL] = LL LL = __farmCapture(11145377, q(11145377, { h, J, hL, bL, qL, wL, RL, zL, XL, WL, P, mL, k, l, EL, dL, rL, })) RL = b(RL) qL = b(qL) mL = b(mL) TL = Q[S] iL = b(iL) k = b(k) cL = TL["MouseButton1Click"] yL = x(8779035, { h, J, rL, UL, EL, nL, hL, }) NL = b(NL) OL = b(OL) c = b(c) TL = __farmConnect QL = b(QL) TL = TL(cL, yL) cL = Q[UL] dL = b(dL) TL = cL() WL = b(WL) zL = b(zL) TL = p["task"] Z = b(Z) HL = b(HL) GL = b(GL) bL = b(bL) sL = b(sL) aL = b(aL) UL = b(UL) C = b(C) EL = b(EL) cL = TL["spawn"] TL = cL(LL) jL = b(jL) JL = b(JL) cL = Q[hL] fL = b(fL) P = b(P) rL = b(rL) l = b(l) nL = b(nL) wL = b(wL) XL = b(XL) gL = b(gL) VL = b(VL) S = b(S) J = b(J) h = b(h) vL = b(vL) KL = b(KL) AL = b(AL) TL = cL("Menu OK. Farm auto-ON. Click SCAN for track sweep. Auto-dismount + Safe Mode + NoClip + Leave-on-loot.") hL = b(hL) elseif 2417445 > B then m = 12039276 > 9625445 B = m and 10698099 or 7585355 else B = S and 11535100 or 1503389 end else if B < 2485214 then X = Q[Y[5]] g = Q[s] S = X(g) B = S and 11631822 or 12688007 elseif 2508870 > B then B = Q[Y[1]] v = B["GetPivot"] V = { v(B), } B, V = p["qWQmbQXX4VmQQ"], { i(V), } elseif B < 2539717 then v = "SAFE \226\155\145\239\184\143 REGEN" B = 11472810 else B = 3322234 end end else if B < 2628954 then if B < 2579635 then K = q(2503136, { v, }) B = p["pcall"] h = { B(K), } V, J = h[1], h[2] K = V V, B = K, K and 8389699 or 16373456 elseif B < 2590837 then J, f = K(v, J) B = J and 1512125 or 13161543 elseif 2608581 > B then X = b(X) B = 6799258 else B = 2313140 end else if 2637498 > B then B = 10960638 elseif B < 2640983 then Q[J] = o wL = Q[Z] zL = wL + 1 P = C[zL] pL = d + P B = 11103020 YL = pL % 256 d = YL zL = Q[l] P = R + zL pL = P % 256 R = pL else V = Q[Y[6]] B = p["xuh45HTvOBnL"] v = V() V = { } end end end end else if 3117455 > B then if 2798376 > B then if 2730807 > B then if 2660819 > B then B = O["IsA"] B = B(O, "ProximityPrompt") B = B and 13875691 or 11241139 elseif B < 2679587 then V = K B = K and 8462415 or 11740424 elseif B < 2700773 then B = 7982694 Q[Y[5]] = V else V = p["task"] B = V["wait"] O = Q[Y[5]] V = B(O) B = 2621551 end else if 2760663 > B then h = p["_G"] V = h["ChestFarm"] B = V and 8805998 or 7493530 elseif B < 2774834 then V = { nil, } B = p["X1u4FY0Xv9ejg"] elseif 2792143 > B then v = Q[Y[1]] V = #v B = V == 0 B = B and 12705080 or 7985072 else B = 9272629 E = b(E) O = p["task"] V = O["wait"] O = V(0.1) end end else if 3037073 > B then if 2823481 > B then B = Q[Y[2]] v = 5456053 <= 12466774 B["Anchored"] = v V, B = { }, p["6Z8TklukcUN5Yp"] elseif B < 2897029 then V = p["_G"] B = V["SafeMode"] B = B and 16291473 or 7145320 elseif B < 2990461 then f = p["task"] B = 9517195 V = f["wait"] E = Q[Y[11]] f = V(E) else B = p["pcall"] J = A(7154195, { v, Y[1], Y[2], }) V = B(J) B = 1443707 end else if B < 3061225 then s = O == 4 B = s and 3206321 or 6618969 elseif B < 3096488 then V, B = { }, 13089986 >= 12858857 Q[Y[1]] = B B = p["hC8xnOODsRvG5f"] else B = V and 6719882 or 1895623 end end end else if B < 3308872 then if B > 3201202 then if B < 3226294 then s = 9251678 ~= 15660190 Q[J] = s B = 3322234 elseif 3266444 > B then B = W() Q[B] = X X = B B = Q[X] m = B["IsA"] m = m(B, "ImageLabel") B = m and 11301941 or 2595611 elseif 3291065 > B then S = E["Destroy"] S = S(E) B = 2414939 else J = p["_G"] V = J["ChestFarm"] B = V and 13527837 or 11411361 end else if B < 3130757 then B = 8446674 elseif B < 3151075 then B = p["fireproximityprompt"] v = Q[Y[2]] J = Q[Y[1]] V = B(v, J) B = 2326724 elseif B < 3180862 then X = W() Q[X] = s s = X X = Q[s] m = X["IsA"] m = m(X, "Model") B = m and 13688621 or 7533310 else B = 15426340 end end else if B > 3359807 then if 3365503 > B then B = 11317998 elseif B < 3397660 then V = p["_G"] B = V["__ScanRunning"] B = B and 9209652 or 6018447 else B = X and 2467293 or 14047090 end else if 3330473 > B then B = 609472 elseif 3346558 > B then S = d B = d and 9943720 or 10846809 elseif B < 3356332 then n = d["Position"] H = n - K B = 4279473 U = H["Magnitude"] r = U else V, B = { }, p["Lx1k2m70xbRw"] end end end end end end else if 6452244 > B then if B < 5002297 then if B > 4289131 then if 4591274 > B then if B < 4338383 then if B < 4305007 then B, V = p["cvewqTlKNYEtsR"], { } elseif B < 4315418 then B, V = p["6UAZfjFIw6cdUn"], { } elseif 4323551 > B then O = K B = O == 0 B = B and 1841009 or 10275072 else f = p["table"] B = p["eBH4XbMCWxy0gp"] V = { K, } h = f["sort"] E = j(15617489, { Y[2], Y[3], }) f = h(K, E) h = Q[Y[6]] f = h() end else if 4363379 > B then r = I["Position"] R = r - v d = R["Magnitude"] g = d <= J S, B = g, 2419274 elseif 4409982 > B then I = p["pcall"] d = Q[Y[16]] R = { I(d, X), } S, g = R[1], R[2] I = not S B = I and 8141254 or 16741558 elseif 4511222 > B then V = { "gone", } B = p["uMfY4tfXu6SP"] else X = q(15881992, { }) B = p["tonumber"] v = Q[Y[4]] K = p["tostring"] O = p["pcall"] s = { O(X), } E = { i(s), } f = E[2] h = K(f) J = v(h, ":(%d*):") v = { J(), } V = B(i(v)) v = V J = Q[Y[5]] B, V = J and 232637 or 2698186, J end end else if 4816036 > B then if 4643202 > B then f = Q[Y[5]] E = f() f = Q[Y[8]] V = E < f B = V and 13079762 or 10337494 elseif 4702314 > B then h = p["_G"] K = h["SafeMode"] J, B = not K, 263389 V = J elseif B < 4754216 then V, B = { }, p["IhGdZqCInRyo6E"] else r = K B = K and 3354405 or 4279473 end else if B < 4912216 then B = p["ipairs"] O = Q[J] X = O["GetDescendants"] s = { X(O), } O = { B(i(s)), } E, f, B, V = O[3], O[2], 6799258, O[1] O = V elseif 4986626 > B then V, B = { }, p["09vyvCdicBke"] else V = Q[Y[6]] h = V() E = h B = h and 15826198 or 612181 end end end else if 4094091 > B then if B < 3888333 then if B < 3549486 then X = I U = p["string"] G = U["byte"] B = 9771883 U = G(v, X) G = Q[Y[6]] H = G() r = U + H R = r + O d = R % 256 O = d G = O + 1 r = h[G] R = s .. r s = R elseif B < 3649027 then V = { 0, } B = p["VoqoXUUhfI41g"] elseif 3803451 > B then I = Q[s] g = Q[Y[3]] B = 5826503 S = g["Character"] m = I ~= S X = m else v, B = "SCAN \240\159\159\162", 11472810 end else if 3936128 > B then v = w[1] B = v["FindFirstChild"] J = 10558898 <= 13967950 B = B(v, "LockGui", J) J = W() Q[J] = B V = Q[J] B = not V B = B and 12973837 or 13639824 elseif B < 4025715 then B = Q[Y[3]] V = B() J = V B, K = J and 2104420 or 2660989, J elseif 4088882 > B then B = Q[Y[1]] V = B() v = V J = not v V, B = J, J and 2317164 or 412308 else B = 7317359 S = X["Health"] I = S > 0 m = I end end else if B < 4217330 then if B < 4112262 then F = d == R H, B = F, 2284562 elseif B < 4147883 then E = 47443 > 15112444 f = K == E B, V = 9675773, f elseif 4182604 > B then V = p["_G"] O = 16365909 <= 2075258 V["__ScanRunning"] = O V = p["_G"] V["ScanInfo"] = "-" E = p["_G"] V = E["SafeMode"] B = V and 14545731 or 2201916 else n = Q[I] F = n(1, 6) p["l2"] = F T = p["l2"] n = T > 2 B = n and 16088627 or 13779644 end else if B < 4248660 then h, O = f(K, h) B = h and 2660649 or 2763073 elseif B < 4268556 then V = Q[Y[5]] d = p["math"] g = d["floor"] d = g(J) G = #O r = G .. " chests matched -> teleporting to loot..." g = ": " .. r S = d .. g B = 11809829 m = "x=" .. S X = V(m) V = p["ipairs"] S = { V(O), } m, X, I = S[2], S[1], S[3] elseif B < 4278046 then B = p["pcall"] K = x(12037862, { J, Y[2], Y[3], }) V = B(K) V = p["task"] B = V["wait"] V = B(0.3) B = 14648130 else V = r or 0 R = V V = R < h B = V and 12969050 or 9672953 end end end end else if B < 5687894 then if 5422812 > B then if 5326308 > B then if 5063590 > B then v = W() B = Q[Y[7]] V = B() Q[v] = V J = Q[v] V, B = J, J and 15498653 or 15479639 elseif 5185486 > B then B = V and 4787625 or 2316631 elseif 5286287 > B then B = 8446674 else B = Q[Y[3]] J = W() V = B() Q[J] = V V = Q[J] B = not V B = B and 11238578 or 12488785 end else if 5359122 > B then V = h B = 10533794 elseif 5385723 > B then V = Q[Y[5]] O = V("Scan COMPLETE (end of track).") V = p["_G"] E = b(E) V["ScanX"] = nil V = p["_G"] B, s = 4167377, 6425899 < 5921492 V["TrackScan"] = s elseif B < 5401141 then f = Q[v] B = 16262286 h = f["Model"] V = h else B = E and 14551240 or 6402229 end end else if 5498071 > B then if 5432517 > B then K, E = h(J, K) B = K and 9671719 or 727779 elseif B < 5439115 then V = Q[Y[1]] B = V["Visible"] V = { B, } B = p["IEFLEIqjsJWgG"] elseif 5470693 > B then B = 9974009 else YL = Q[J] D = YL B = YL and 14920708 or 10850024 end else if B < 5512268 then B = Q[Y[4]] J = B["Disconnect"] J = J(B) Q[Y[4]] = nil B = 7493453 elseif 5548985 > B then v = V B = not v B = B and 12685973 or 16764486 elseif 5587453 > B then v = w[1] B = Q[Y[1]] V = B() J = V K, B = J, J and 16150368 or 14840177 else d = p["table"] X = d["insert"] r = "Model" G = Q[s] U = "Pos" H = g["Position"] n = "Dist" L = J B = J and 9215071 or 15323556 end end end else if B < 6014319 then if 5865947 > B then if B < 5800237 then B = 7570852 elseif 5843594 > B then B = X and 7670050 or 7730409 elseif 5862685 > B then V = Q[Y[1]] B = V["ImageTransparency"] Q[Y[4]] = B B, V = p["QcryN30UksvW1"], { } else V = Q[Y[5]] B = p["NnJpb7cYe6Pitx"] v = V("NOCLIP OFF.") V = { } end else if B < 5877176 then r = Q[Y[17]] U = g["Model"] G = r(U) B, R = 8588739, not G V = R elseif B < 5895114 then B = Q[Y[3]] B["Text"] = "SCAN: ON" B = Q[Y[3]] J = p["Color3"] v = J["fromRGB"] J = v(50, 170, 80) B["BackgroundColor3"] = J B = 3358260 elseif 5956638 > B then B = J["Position"] V = { B, } B = p["oErei7iIakJZk"] else B = 15382206 ~= 1732140 V = { B, } B = p["3s66yN9YqskDjX"] end end else if B < 6224439 then if 6036789 > B then B = p["_G"] v = 6573172 ~= 7180641 B["__ScanRunning"] = v B = Q[Y[3]] V = B() v = V B = v["X"] V = v["Z"] J, K = B, V f = p["type"] s = p["_G"] O = s["ScanX"] E = f(O) h = E == "number" B, V = h and 7079558 or 10533794, h elseif 6098030 > B then B = { } Q[Y[3]] = B B = 4720807 elseif B < 6161291 then J = Q[Y[1]] K = J(1, 2) v = K == 1 B, V = v and 12543280 or 15089953, v else J = Q[v] V = J["Position"] K = p["Vector3"] J = K["new"] f = Q[Y[4]] K = J(0, f, 0) B = V + K Q[Y[5]] = B B = 7467180 K = u(6713366, { v, Y[1], Y[2], Y[5], }) V = p["pcall"] J = V(K) end else if 6334728 > B then B = 3338712 G = p["table"] r = G["unpack"] d = r elseif 6426610 > B then h = b(h) f = b(f) B = 2586064 else B = 16067697 <= 10469983 V = { B, } B = p["Qq0v6ujBlsZbq"] end end end end end else if B > 7493491 then if 7939647 > B then if B < 7690726 then if 7578103 > B then if 7513420 > B then h = p["_G"] E = 10435605 < 2621338 h["__FarmRunning"] = E f = p["_G"] h = f["SafeMode"] B = h and 8732236 or 13994701 elseif B < 7540370 then B = 11588539 s = b(s) elseif 7559141 > B then K = p["_G"] B = 12033068 J = K["TrackScan"] V = J else E = p["task"] B = 9517195 f = E["wait"] E = f(0.3) end else if 7587716 > B then B = 813689 elseif B < 7592403 then O = e(811111, { E, Y[1], Y[2], J, }) V = p["pcall"] f = V(O) B = 16697569 elseif B < 7632390 then V = Q[Y[1]] B = V["Character"] v = B V, B = v, v and 14441563 or 9156743 else B = Q[s] X = B["FindFirstChildOfClass"] X = X(B, "Humanoid") m, B = X, X and 4092048 or 7317359 end end else if 7750077 > B then if 7720906 > B then O = Q[J] V, B = O, 15877838 elseif 7738273 > B then s = b(s) B = 15175639 elseif 7747329 > B then B, V = 5115852, d else B = p["error"] J = Q[Y[8]] v = B(J, 0) B = 2013086 end else if B < 7810493 then E = Q[Y[8]] O = E() E = Q[Y[9]] V = O < E B = V and 10185824 or 11121287 elseif 7882976 > B then B = p["l2"] V = p["l1"] p["l1"] = B B = 9848414 p["l2"] = V v = Q[Y[1]] J = v() else B, V = p["8jjLAzI7BJkB"], { } end end end else if B < 8173600 then if B < 8047722 then if B < 7983883 then B = Q[Y[7]] B = B and 7748520 or 2013086 elseif 8001339 > B then J = Q[Y[1]] v = #J K = Q[Y[1]] J = K[v] K = Q[Y[1]] B = p["ZX6yV7ukgNyXk"] K[v] = nil V = { J, } elseif B < 8028371 then B = V and 2239952 or 9556308 else B = Q[Y[7]] V = B("Scan OFF.") B = 4979985 end else if 8075870 > B then v = w[1] B, V = v and 5524880 or 2397276, v elseif B < 8118343 then B, V = p["Bxf0u7wpGqjB3O"], { } elseif 8152929 > B then I = Q[Y[3]] G = p["tostring"] U = G(g) R = "Error: " .. U B = 16741558 d = I(R) else B = Q[Y[6]] V = B(h) B = V and 1479762 or 13153703 end end else if 8303169 > B then if B < 8198829 then n = T + n H, k = F >= n, not L H = k and H k = n >= F k = L and k H = k or H B = H and 13341767 B = B or 10720795 elseif 8228130 > B then B = 947254 elseif B < 8267985 then V = p["_G"] B = V["TrackScan"] B = B and 5887144 or 12835545 else I = 13415829 ~= 13658982 m = Q[J] X = m == I B = X and 16698363 or 11026002 end else if 8344028 > B then B = 14255469 elseif B < 8383094 then v = b(v) V = p["task"] B = V["wait"] J = Q[Y[9]] V = B(J) B = 539956 else V, B = J, 16373456 end end end end else if 7022655 > B then if B < 6716624 then if 6621656 > B then if B < 6467256 then B = 813689 elseif B < 6486990 then B = S and 10073132 or 1734600 elseif 6555966 > B then v = "IDLE" V = p["_G"] B = V["SafeMode"] B = B and 2514604 or 3295510 else X = O == 5 B = X and 8294771 or 9270560 end else if B < 6628322 then B = p["_G"] v = 16586065 > 5159535 B["__FarmRunning"] = v B = Q[Y[3]] V = B("START farm (auto). 0 boss attacks.") B = Q[Y[4]] V = B() v = V B, J = v and 9393565 or 14814348, v elseif 6637956 > B then B = V and 8946494 or 16600767 elseif B < 6678488 then V = K >= 40 B = V and 457745 or 2946156 else B = Q[Y[1]] J = p["Vector3"] v = J["zero"] B["AssemblyLinearVelocity"] = v B = Q[Y[1]] J = p["CFrame"] v = J["new"] K = Q[Y[4]] J = v(K) B["CFrame"] = J B = Q[Y[1]] v = 9911192 >= 1135751 B["Anchored"] = v V, B = { }, p["G3DMpVYdHgrh1"] end end else if 6784773 > B then if B < 6725347 then R = e(12343378, { m, }) V = p["pcall"] r = { V(R), } d = r[2] g = r[1] V = g B = g and 7746138 or 5115852 elseif B < 6731964 then B = 5123897 < 12371649 B = B and 12070566 or 3361354 elseif B < 6751702 then B = Q[Y[1]] v = B["GetPivot"] V = { v(B), } V, B = { i(V), }, p["bAVMmxXUq718L"] else B, V = 3109906, d end else if 6859784 > B then E, X = O(f, E) B = E and 3246268 or 14059071 elseif 6942689 > B then m = O == 7 B = m and 553034 or 11759325 elseif 6986149 > B then B = Q[Y[1]] J = p["Vector3"] v = J["zero"] B["AssemblyLinearVelocity"] = v B = Q[Y[1]] J = p["CFrame"] v = J["new"] K = Q[Y[4]] J = v(K) B["CFrame"] = J B, V = p["RwtE61klAG4OJ1"], { } else V = v["Health"] J = v["MaxHealth"] B = V / J V = { B, } B = p["ZRyE73FjfkWEl"] end end end else if B < 7177324 then if B > 7140843 then if B < 7149757 then B = p["_G"] v = 10190927 <= 15959612 B["SafeMode"] = v B = Q[Y[3]] v = W() V = B() Q[v] = V B = Q[v] B = B and 6181652 or 7467180 elseif 7155296 > B then B = Q[Y[1]] v = 5148967 > 13886589 B["Anchored"] = v B, V = p["rr3AVtVXlgOd3H"], { } elseif B < 7162611 then B, S = 6481016, g else B = Q[Y[4]] O = E["CanCollide"] B[E] = O B = 15503894 end else if B < 7048859 then V = Q[Y[12]] O = V() B = 15033315 O = p["Vector3"] V = O["new"] s = W() O = V(J, f, K) X = x(6965069, { E, Y[1], Y[2], s, }) Q[s] = O V = p["pcall"] O = V(X) V = p["_G"] g = p["math"] S = g["floor"] g = S(J) R = Q[Y[4]] S = "/" .. R I = g .. S X = "x=" .. I V["ScanInfo"] = X V = Q[Y[13]] O = V() O = p["task"] V = O["wait"] X = Q[Y[14]] O = V(X) V = { } O = V V = p["ipairs"] S = Q[Y[15]] g = { S(), } S = { V(i(g)), } I, X, m = S[3], S[1], S[2] elseif B < 7069598 then V = Q[Y[3]] B = 6643611 S = Q[Y[10]] I = S .. " LOCKED." X = ": 0 unlocked, " .. I s = K .. X E = "Scan " .. s f = V(E) elseif B < 7107962 then s = p["_G"] O = s["ScanX"] E = O >= J B, h = E and 1508500 or 5335161, E else B = p["workspace"] V = B["FindFirstChild"] V = V(B, "Drill") v = W() Q[v] = V B = Q[v] B = B and 2573206 or 3965714 end end else if 7368385 > B then if B < 7226134 then B, v, J = { }, w[1], w[2] K = B B = p["ipairs"] E = p["workspace"] s = E["GetDescendants"] O = { s(E), } E = { B(i(O)), } f, h, V = E[3], E[2], E[1] E, B = V, 15175639 elseif 7291901 > B then Q[Y[10]] = Q[Y[10]] + 1 B = Q[Y[11]] O = "Looted: " .. E V = B(O) B = 2214588 elseif B < 7342726 then B = m and 14090643 or 10252446 else B = 1719304 end else if B < 7417928 then B = Q[Y[1]] v = 9726848 <= 6852102 B["Sit"] = v B = Q[Y[1]] v = 12565162 > 7469799 B["Jump"] = v B, V = p["wBnPreVBeIxQw"], { } elseif B < 7480316 then V = Q[Y[6]] J = V() V = Q[Y[7]] h = p["string"] B = p["lwAtT0tu8hp4"] K = h["format"] v = b(v) O = Q[Y[8]] s = O() E = s * 100 O = Q[Y[4]] h = { K("HP %.0f%% - SAFE MODE, floated %d studs up + regen.", E, O), } J = V(i(h)) V = Q[Y[9]] J = V() V = { } else B = p["eGmuME7E1PCiR"] h = Q[K] V = { } J = h["Seated"] h = __farmConnect f = x(13175923, { Y[2], Y[3], K, Y[5], }) K = b(K) h = h(J, f) Q[Y[4]] = h end end end end end end end else if 12696543 > B then if 10706745 > B then if B > 9520376 then if B < 10040206 then if B < 9723828 then if B < 9609134 then if B < 9524972 then V = Q[Y[3]] B = 6643611 s = K .. ": no chest." E = "Scan " .. s f = V(E) elseif 9541347 > B then B = 4327491 s = b(s) elseif B < 9582603 then B = h["Name"] E = B B = Q[Y[8]] V = B(f) V = p["task"] B = V["wait"] O = Q[Y[9]] V = B(O) V = h["Parent"] B = not V B = B and 7266444 or 15396740 else B = Q[Y[1]] B = B and 13143497 or 2799061 end else if 9640544 > B then K = p["_G"] J = K["ChestFarm"] B, V = J and 12033068 or 7547431, J elseif B < 9672336 then B = E["IsA"] B = B(E, "BasePart") B = B and 8685938 or 13206972 elseif 9674363 > B then B = 2316631 else B = V and 13566339 or 4844448 end end else if B < 9900480 then if 9793259 > B then I, d = S + I, not g X = I <= m X = d and X d = I >= m d = g and d X = d or X B = X and 3537696 B = B or 11212642 elseif B < 9831525 then B = Q[Y[1]] B = B and 1385411 or 1014331 elseif B < 9866092 then B = 9807712 > 7991906 B = B and 7869353 or 4311225 else I = b(I) f = b(f) J = b(J) U = b(U) S = b(S) E = b(E) f = W() g = b(g) h = b(h) h = W() Q[h] = nil J = W() Q[J] = nil Q[f] = 2 E = p["math"] K = E["floor"] I = W() E = W() Q[E] = K O = W() B = 15491759 Q[O] = 0 K = { } Q[I] = K S = p["string"] G = 256 K = S["char"] g = p["table"] S = g["remove"] d = p["math"] g = d["random"] d = { } U = 1 L = 0 > 1 r = 1 - 1 end else if 9930455 > B then zL = C[2] wL = Q[c] P = zL == wL B, YL = 896564, P elseif 9958864 > B then g = W() Q[g] = S S = Q[I] H = x(11350692, { }) d = S(3, 65) S = W() R = 0 Q[S] = d d = 0 G = p["pcall"] U = { G(H), } B, r = 8182596, { i(U), } G = r[2] U = p["tonumber"] n = Q[h] T = p["tostring"] L = T(G) F = n(L, ":(%d*):") n = { F(), } H = U(i(n)) U = W() Q[U] = H n = Q[S] F = n T = 1 L = 1 < 0 n = 1 - 1 elseif B < 9990644 then B = 3322234 else B = 13638227 end end end else if 10388256 > B then if B > 10236390 then if B < 10254006 then B = 7730409 elseif B < 10265319 then s, X = E(O, s) B = s and 12051075 or 7570852 elseif 10306283 > B then V = O == 1 B = V and 15428175 or 11508942 else V = Q[Y[9]] f = V() h = f f = #h V = f == 0 B = V and 13499361 or 15073848 end else if 10086762 > B then B = 1832633 ~= 14580906 V = { B, } B = p["BznEIX98ywr4"] elseif B < 10143108 then B = Q[Y[1]] v = B["GetPivot"] V = { v(B), } B, V = p["lDeeEo6yF6105"], { i(V), } elseif B < 10203079 then E = Q[Y[10]] O = E() V = not O B = V and 16390245 or 1705064 else B = 11351942 end end else if B > 10659999 then if 10684917 > B then I = q(1553168, { m, Y[1], Y[2], s, }) V = p["pcall"] X = V(I) B = 12468205 elseif B < 10692245 then V = Q[Y[6]] X = V() m = W() Q[m] = X V = Q[m] B = V and 10683443 or 12468205 else B = 2415617 end else if B < 10486406 then v = q(6492964, { Y[1], Y[2], Y[3], Y[4], Y[5], Y[6], }) B = p["pcall"] V = B(v) B, V = p["C8xW3srj2hmH7G"], { } elseif B < 10581266 then B = V and 11980463 or 11058059 elseif B < 10632646 then V = p["task"] B = V["wait"] V = B(0.3) V = p["_G"] B = V["SafeMode"] B = B and 6055131 or 4720807 else E = W() V = Q[Y[6]] O = V() Q[E] = O O = Q[E] V = not O B = V and 13673125 or 7038080 end end end end else if B > 8988035 then if B > 9271594 then if B > 9388102 then if B < 9420920 then B = 14814348 h = v["CFrame"] J = h elseif B < 9482735 then h = Q[J] B = 15916683 K = h["Sit"] V = K else B = 2758254 end else if 9282971 > B then E = p["_G"] V = E["TrackScan"] B = V and 7751634 or 4167377 elseif B < 9331468 then G = Q[Y[4]] H = Q[m] B = 6770288 U = G(H) r = not U d = r elseif B < 9376131 then E = J O = e(13416371, { Y[2], v, }) B = p["pcall"] V = B(O) V = Q[Y[1]] B = E < V B = B and 2703360 or 2621551 else v = u(8241199, { Y[1], Y[2], Y[3], }) B = p["pcall"] V = B(v) B = Q[Y[4]] V = B() V, B = { }, p["GYtI41Jxun4G3"] end end else if B < 9212361 then if B < 9093159 then B = 12494533 V = Q[Y[5]] n = p["tostring"] F = n(r) U = "Error: " .. F G = V(U) elseif B < 9160635 then V, B = { V, }, p["25b8ashv5DvDU"] elseif 9187090 > B then B = Q[Y[1]] V = B() v = V J, B = v, v and 9254864 or 12787114 else B, V = p["lH1R8IdgHv7a"], { } end else if 9225413 > B then C = g["Position"] Z = C - J B = 15323556 l = Z["Magnitude"] L = l elseif B < 9245309 then B = Q[Y[1]] J = B["GetAttribute"] V = { J(B, "RuntimeChestModel"), } V, B = { i(V), }, p["iJdz7CyecOxTmZ"] elseif 9262712 > B then B = 12787114 h = v["Position"] J = h else X = O == 6 B = X and 11147024 or 6920310 end end end else if 8755635 > B then if 8613234 > B then if B < 8433037 then V = Q[Y[1]] B = V["Character"] v = B V, B = v, v and 11644916 or 301950 elseif B < 8454544 then s = 11335595 ~= 15169456 B = s and 3125004 or 2636358 elseif 8525577 > B then V, B = { V, }, p["EhRgH4HPnGbXl"] else B = V and 13497434 or 1719304 end else if 8644975 > B then B = p["ipairs"] f = v["GetDescendants"] h = { f(v), } f = { B(i(h)), } V = f[1] h, J, B, K = V, f[2], 5431705, f[3] elseif 8669079 > B then B = Q[Y[4]] V = B() B = 9490552 >= 13753759 V = { B, } B = p["owDBoXGHuXLGcW"] elseif B < 8709087 then s = Q[Y[4]] O = s[E] B = O == nil B = B and 7168825 or 15503894 else B = 13994701 h = Q[Y[17]] f = h() end end else if 8863244 > B then if B < 8792516 then B = p["_G"] K = p["_G"] J = K["TrackScan"] v = not J B["TrackScan"] = v V = p["_G"] B = V["TrackScan"] B = B and 2009098 or 16117330 elseif B < 8815926 then h = Q[Y[5]] f = h() h = Q[Y[6]] V = f < h B = V and 2242061 or 4602584 elseif 8832272 > B then B = p["3lkmPqUkNGuqPV"] v = b(v) V = { } else K = Q[v] B = 6632302 J = K["Sit"] V = J end else if B < 8890225 then B, V = p["ifjEJZLicOL6"], { K, } elseif 8900952 > B then B = 15033315 elseif 8927872 > B then B = 1228690 else J = x(7368676, { v, Y[2], Y[3], }) B = p["pcall"] V = B(J) V = p["task"] B = V["wait"] V = B(0.4) J = W() B = Q[Y[1]] V = B() Q[J] = V K = Q[J] V, B = K, K and 9448275 or 15916683 end end end end end else if B > 11561819 then if 12220698 > B then if B < 11784577 then if B > 11735221 then if 11738908 > B then E = h["Parent"] V, B = E, 16627728 elseif 11740452 > B then h = p["Vector3"] K = h["new"] B = 8462415 h = K(-740, 20, -771.5) V = h elseif 11749903 > B then pL = Q[J] o = pL B = pL and 1702118 or 2638638 else m = O == 8 B = m and 13638988 or 3322234 end else if 11610180 > B then O, s = f(E, O) B = O and 3165640 or 4327491 elseif B < 11638369 then B = 14255469 Q[Y[4]] = Q[Y[4]] + 1 elseif B < 11688983 then B = 301950 J = v["FindFirstChildOfClass"] J = J(v, "Humanoid") V = J else B = J["FindFirstChildOfClass"] B = B(J, "ProximityPrompt") K = B B = K and 13805553 or 3196084 end end else if B < 12044468 then if 11895146 > B then I, g = X(m, I) B = I and 15229519 or 10686391 elseif B < 12006765 then V = p["_G"] B = V["ScanX"] V = Q[Y[5]] J = B X = p["math"] s = X["floor"] X = s(J) B = 4993267 O = X .. "." f = "Resuming scan from x=" .. O h = V(f) elseif B < 12035465 then B = not V B = B and 8652220 or 13690062 else B = Q[Y[1]] v = 15822282 < 1452844 B["Sit"] = v B, V = p["XR2BYFSIa69d"], { } end else if 12060820 > B then S = p["_G"] I = S["ChestFarm"] m = not I B = m and 1913516 or 1310883 elseif B < 12126622 then B = 6730812 else K = W() Q[K] = J J = Q[K] B = not J B = B and 7896600 or 12526461 end end end else if B < 12491659 then if B > 12403608 then if B < 12466021 then B = Q[Y[1]] J = B["GetAttribute"] V = { J(B, "RuntimeChestModel"), } V, B = { i(V), }, p["ZGD0BKJ1M4ilP1"] elseif B < 12476961 then X = p["task"] m = b(m) B = 11480809 V = X["wait"] X = V(0.2) elseif 12487251 > B then r = g["Pos"] G = Q[s] R = r - G d = R["Magnitude"] R = Q[Y[16]] V = d <= R B = V and 1091584 or 8892653 else B = Q[Y[4]] V = B() B = p["pcall"] K = e(14380474, { J, Y[1], Y[2], v, }) V = B(K) V = p["task"] B = V["wait"] V = B(0.2) B = Q[Y[5]] V = B(20) K = V h, B = K, K and 12294651 or 15931243 end else if B < 12276684 then B = Q[Y[4]] V = B["Disconnect"] V = V(B) Q[Y[4]] = nil B = 5864685 elseif 12315528 > B then B = 15931243 E = K["Model"] h = E elseif B < 12339892 then g = A(12463838, { m, Y[2], Y[3], }) V = p["pcall"] d = { V(g), } I = d[1] S = d[2] B, V = I and 11530877 or 3109906, I else B = Q[Y[1]] v = B["GetPivot"] V = { v(B), } B, V = p["kUaum51oFTCD"], { i(V), } end end else if 12552764 > B then if 12510497 > B then B = 7368094 elseif 12531455 > B then B = Q[Y[4]] B = B and 5499656 or 7493453 elseif 12539864 > B then B = Q[Y[3]] V = B() B = Q[Y[4]] B = B and 12258718 or 5864685 else B = V and 4579964 or 7982694 end else if B < 12624110 then v = p["_G"] V = v["SafeMode"] B = not V B = B and 2114199 or 16123142 elseif B < 12686990 then B, V = p["0gPTcKIDXOuo"], { } else X = p["pcall"] d = q(6733117, { s, }) R = { X(d), } g = R[2] S = R[1] B, X = S and 58016 or 1079472, S end end end end else if B < 11219784 then if B < 10993320 then if B > 10839460 then if 10848416 > B then B = 9943720 d = p["unpack"] S = d elseif B < 10865403 then Q[J] = D B = 11103020 elseif 10920710 > B then K, O = f + K, not E J = h >= K J = O and J O = h <= K O = E and O J = O or J B = J and 15354854 B = B or 1692099 else B = 3322234 end else if 10718093 > B then B = Q[Y[1]] v = 16285521 < 11389691 B["Sit"] = v B = Q[Y[1]] v = 3946760 < 15849383 B["Jump"] = v V, B = { }, p["MjTCrsr1DbFlk5"] elseif B < 10735535 then F = Q[J] H, B = F, F and 4096134 or 2284562 elseif 10791193 > B then B = p["error"] V = B("Tamper Detected!") B, V = p["ffF6ZEW1874Cx"], { } else B = p["pairs"] K = Q[Y[1]] h = { B(K), } v, J, B, V = h[2], h[3], 2586064, h[1] K = V end end else if B < 11112153 then if B < 11042030 then B = 14668478 elseif B < 11058347 then V = p["_G"] B = 4993267 f = J V["ScanX"] = f elseif B < 11080828 then J = W() Q[J] = "fR2yublGNor" h = 8 B = 609472 f = 1 E = 1 < 0 K = 0 - 1 else k = b(k) Z = b(Z) c = b(c) y = b(y) l = b(l) B = 8182596 H = b(H) end else if B < 11133332 then O = Q[Y[8]] s = O() O = Q[Y[11]] V = s < O B = V and 13042276 or 15182894 elseif B < 11146200 then V = p["_G"] B = V["__FarmRunning"] B = B and 8095433 or 6624343 elseif B < 11179833 then X, B = 2488765 >= 9714369, 3322234 Q[J] = X else X = s K[J] = X B = 12765146 end end end else if 11381651 > B then if B < 11305973 then if B < 11232752 then B = 7493530 elseif 11239858 > B then V = { "no-hrp", } B = p["pgXHUPxDP4nr2L"] elseif 11271540 > B then B = 4236829 else I = e(5433329, { X, Y[1], Y[2], }) B = p["pcall"] m = B(I) I = W() g = t(5860685, { X, Y[1], Y[2], I, }) Q[I] = 0 B = p["pcall"] S = B(g) B, S = m and 13190025 or 6481016, m end else if B < 11314001 then J = e(9608899, { Y[8], v, Y[2], Y[3], }) B = p["pcall"] V = B(J) B = 8376489 elseif 11334345 > B then B = 10899469 < 9266332 Q[J] = B B = 3322234 elseif B < 11351317 then v = "VJWiAPUA" ^ 6071958 B = 896278 - v v = B B = "4RaSUD" / v V = { B, } B = p["rOOhwcq6SC46a"] else B, V = p["Z8huKCSaqP1gNV"], { } end end else if B < 11506722 then if B < 11442085 then K = p["_G"] J = K["TrackScan"] B = J and 3870124 or 11472810 elseif 11476809 > B then K = Q[Y[3]] h = "Text" E = "Status: " X = "\010Loot: " I = Q[Y[4]] g = " | Skip: " R = Q[Y[5]] G = "\010Locked (needs boss): " H = Q[Y[6]] F = "\010Scan: " T = p["tostring"] C = p["_G"] Z = C["ScanInfo"] k, B = Z, Z and 14978953 or 13776255 elseif 11492656 > B then V = Q[Y[7]] B = 2797691 J = J + V V = p["_G"] s = b(s) m = J V["ScanX"] = m else s = O == 3 B = s and 14387389 or 3039380 end else if 11519909 > B then V = O == 2 B = V and 1066369 or 11504503 elseif B < 11532988 then d = S B = S and 9293314 or 6770288 else S = p["table"] B = S["insert"] R = Q[s] U = Q[s] G = U["Name"] g = { ["Model"] = R, ["Name"] = G, } S = B(K, g) B = 1503389 end end end end end end else if B > 14552478 then if 15513252 > B then if B > 15083123 then if B < 15375797 then if B > 15195783 then if B < 15219096 then V = p["task"] B = V["wait"] V = B(0.1) K = Q[Y[3]] J = K["Sit"] V, B = J, J and 4683821 or 263389 elseif B < 15276537 then R = p["_G"] d = R["TrackScan"] V = not d B = V and 1249993 or 954104 elseif B < 15339205 then F = L or 0 R = { [r] = G, [U] = H, [n] = F, } d = X(K, R) d = #K X = d >= 60 B = X and 9526387 or 1063554 else J = K B = Q[Y[1]] O = B(0, 255) v[J] = O B = 10880782 end else if 15090705 > B then B = 12543280 J = Q[Y[2]] K = Q[Y[3]] v = J == K V = v elseif B < 15133548 then B, O = 666340, 16148928 > 7971927 E = K == O f = E elseif B < 15179266 then f, s = E(h, f) B = f and 513947 or 8887798 else O = Q[Y[4]] V = J > O B = V and 5383083 or 10636555 end end else if B > 15485699 then if B < 15495206 then r, k = r + U, not L R = r <= G R = k and R k = G <= r k = L and k R = k or R B = R and 728042 B = B or 1416181 elseif 15501273 > B then h = Q[v] B = 15479639 K = h["Anchored"] J = not K V = J else B = E["CanCollide"] B = B and 2329432 or 13155724 end else if 15411540 > B then Q[Y[10]] = Q[Y[10]] + 1 B = Q[Y[11]] X = E .. " - moving to next." O = "Fired " .. X V = B(O) B = 2214588 elseif 15427257 > B then B = p["ipairs"] E = v["GetDescendants"] f = { E(v), } E = { B(i(f)), } B, V, K = 4236829, E[1], E[2] f, h = V, E[3] elseif 15453907 > B then X = 13453595 <= 11371805 s = Q[J] V = s == X B = V and 551847 or 2564830 else B = V and 11310005 or 8376489 end end end else if 14862521 > B then if B > 14682089 then if B < 14755024 then V = Q[Y[1]] B = V["Character"] v = B B = not v B = B and 16304404 or 8637730 elseif 14827262 > B then V, B = J or nil, 2758254 J = W() Q[J] = V K = 0 elseif 14844126 > B then V = K or nil K, h = V, v or 1000000000 f = nil V = p["ipairs"] X = p["workspace"] B, I = 13325255, X["GetDescendants"] m = { I(X), } X = { V(i(m)), } O, s, E = X[2], X[3], X[1] else B = 10960638 end else if B < 14590472 then r = W() R = { } G = e(2786596, { r, O, f, E, }) U = W() Q[r] = R R = W() Q[R] = G G = { } Q[U] = G k = { } G = p["setmetatable"] C = Q[U] l = { ["__index"] = C, ["__metatable"] = nil, } E = b(E) L = G(k, l) G = x(15732229, { U, r, I, O, f, R, }) U = b(U) O = b(O) f = b(f) I = b(I) Q[h] = L r = b(r) R = b(R) Q[J] = G K = p["_G"] E = 14549158 ~= 1051495 K["ChestFarm"] = E K = p["_G"] E = 10710733 >= 11749749 K["__FarmRunning"] = E K = p["_G"] E = 6821869 >= 13798017 K["TrackScan"] = E K = p["_G"] E = 15672959 <= 14248414 K["__ScanRunning"] = E K = p["_G"] E = 10061407 <= 2332047 K["SafeMode"] = E K = p["game"] f = K["GetService"] f = f(K, "Players") K = p["game"] E = K["GetService"] E = E(K, "RunService") K = W() Q[K] = E E = f["LocalPlayer"] O = W() Q[O] = E E = Q[O] I = E["WaitForChild"] I = I(E, "PlayerGui") E = I["FindFirstChild"] E = E(I, "ChestFarmMenu") B = E and 3286621 or 2414939 elseif B < 14637679 then d = Q[Y[10]] R = d() V = not R B = V and 480747 or 8215062 elseif 14658304 > B then B = Q[Y[4]] V = B("Dismounted from train seat.") B = 9542109 >= 9164083 V = { B, } B = p["0rwQz9UDL0RUY"] else X = 14513727 <= 14646868 B = X and 15700987 or 5444901 end end else if B < 14951589 then if B < 14898837 then m = b(m) B = 13325255 elseif B < 14922112 then zL = C[1] wL = 13578987 < 3171962 P = zL == wL B, YL = P and 9917190 or 896564, P elseif 14923871 > B then v = w[1] B = p["print"] h = p["tostring"] f = h(v) J = "[ChestFarm] " .. f V = B(J) V, B = { }, p["3aFp6H2kIpMf"] else B = 9883770 end else if 15006134 > B then L = T(k) n = F .. L U = H .. n r = G .. U d = R .. r S = g .. d m = I .. S s = X .. m O = v .. s V = { } f = E .. O B = p["yfqip5pGGQ0s"] K[h] = f elseif 15053581 > B then I, g = X(m, I) B = I and 12485718 or 12725367 elseif B < 15075070 then K = 0 f = p["ipairs"] X = { f(h), } B, s, E, O = 10255566, X[3], X[1], X[2] else B = 10255566 S = p["task"] I = S["wait"] S = I(0.15) end end end end else if 16141377 > B then if B > 15899337 then if 16102978 > B then if 15923963 > B then B = V and 4276620 or 14648130 elseif 15965690 > B then V = h B = h and 16262286 or 5388364 elseif 16044382 > B then V = p["pcall"] G = Q[Y[21]] U = { V(G, g), } r = U[2] R = U[1] V = not R B = V and 9029576 or 12494533 else B = 8909251 n = p["tostring"] L = p["l1"] T = n(L) p["l2"] = T end else if 16120236 > B then B = Q[Y[3]] V = B() B = 13787160 elseif B < 16127764 then B = p["_G"] v = 8400462 > 11369163 B["SafeMode"] = v B = Q[Y[3]] V = B() v = W() Q[v] = V B = Q[v] B = B and 3034766 or 1443707 else G = #d R = g(1, G) r = S(d, R) G = Q[I] L = r - 1 U = K(L) G[r] = U U = #d G = U == 0 B = G and 14553716 or 16132387 end end else if 15779213 > B then if B < 15570049 then B = 9848414 elseif B < 15659238 then J, v = w[2], w[1] V = v["Dist"] K = J["Dist"] B = V < K V = { B, } B = p["mtiaCUJpuE0Y"] elseif 15716608 > B then B = 14668478 else J = w[2] B = Q[Y[1]] K = B B = K[J] v, B = w[1], B and 16460271 or 1622044 end else if 15844542 > B then B = 612181 X = h["Position"] s = X["Y"] E = s elseif 15870362 > B then n = e(15522610, { f, }) B = p["FWjKxfCjJw11Sz"] F = { n(), } V = { i(F), } elseif B < 15879915 then B = V and 7590077 or 16697569 else v = "Mtu6a" ^ 8082145 B = 10002513 - v v = B B = "Mlv3c" / v V = { B, } B = p["2DL6skadDaig"] end end end else if B < 16453614 then if B < 16332900 then if 16206327 > B then B = 14840177 f = J["Position"] K = f elseif 16276879 > B then h = V V = h B = h and 11737393 or 16627728 elseif 16297938 > B then V, B = { }, p["IowrNaajaJr4"] else B, V = p["F0BnYzFZ2IAu7"], { } end else if B < 16367426 then v = W() Q[v] = w[1] V = p["_G"] B = V["SafeMode"] B = B and 13311217 or 5317455 elseif B < 16381850 then B = V and 5903085 or 13558997 elseif B < 16418601 then E = b(E) B = 4167377 else B = Q[Y[1]] V = B() B = 539956 end end else if 16697966 > B then if 16530519 > B then B, V = p["cJEQGxSoyboGi3"], { J, } elseif B < 16614247 then B = 843278 < 350039 V = { B, } B = p["nODScTfBrCxeN"] elseif B < 16662648 then B = not V B = B and 4442481 or 8164605 else B = 7493530 V = p["_G"] E = b(E) O = 10471264 >= 11257300 V["ChestFarm"] = O end else if B < 16719960 then B = 9974009 elseif 16753022 > B then B = 15076293 else K = v["FindFirstChildOfClass"] K = K(v, "Humanoid") J, B = K, K and 12182679 or 2006289 end end end end end else if B < 13602283 then if B < 13154713 then if B > 13008056 then if B > 13091276 then if B < 13113487 then B, V = p["5tTQ3n7eSAIL"], { } elseif 13133840 > B then B = 6730812 elseif 13148600 > B then B = Q[Y[2]] J = p["CFrame"] v = J["new"] K = Q[Y[1]] J = v(K) B["CFrame"] = J B = 2799061 else B = Q[Y[7]] V = B(h) f = V E = not f B, V = E and 8017606 or 536939, E end else if 13043323 > B then V = Q[Y[5]] O = V("HP critically low - STOP scan.") E = b(E) V = p["_G"] B, s = 4167377, 15080741 < 4998865 V["TrackScan"] = s elseif B < 13050681 then J = Q[Y[3]] v = J * 201 V = v % 257 Q[Y[3]] = V J = Q[Y[3]] v = J ~= 1 B = v and 117106 or 13044370 elseif B < 13068377 then B = 985213 ~= 1245884 Q[J] = B h = p["string"] K = h["gmatch"] h = W() Q[h] = K f = W() K = u(10750275, { }) Q[f] = K E = W() K = 14836391 >= 16228214 Q[E] = K I = p["pcall"] g = u(3083071, { E, }) S = I(g) B = S and 14519565 or 1841764 else V = Q[Y[3]] f = V("HP critically low - STOP.") V = Q[Y[4]] f = V() E = W() Q[E] = f O = Q[E] V = O B = O and 7711403 or 15877838 end end else if B < 12811329 then if B < 12715223 then J = Q[Y[2]] v = J * 213 V = v + 27552854471197 B = V % 35184372088832 Q[Y[2]] = B B = 13044370 elseif B < 12745256 then X = #O V = X > 0 B = V and 4260492 or 11480809 elseif 12776130 > B then B, V = p["eYnfEpzQqGiE"], { J, } else V = J or nil J = V V = { } K = V Q[Y[4]] = 0 h = p["ipairs"] s = p["workspace"] m = s["GetDescendants"] X = { m(s), } s = { h(i(X)), } O, B, E, f = s[3], 11588539, s[2], s[1] end else if B < 12866970 then B = Q[Y[3]] B["Text"] = "SCAN: OFF" B = Q[Y[3]] J = p["Color3"] v = J["fromRGB"] J = v(60, 90, 180) B["BackgroundColor3"] = J B = 3358260 elseif 12933722 > B then v = W() B = Q[Y[1]] V = B() Q[v] = V J = Q[v] B, V = J and 8838690 or 6632302, J elseif B < 12971443 then G = Q[m] H = d["Position"] V = { ["Model"] = G, ["Pos"] = H, ["Dist"] = R, } r, f, B = R, V, 9672953 h = r else B = 9905388 > 10361310 V = { B, } B = p["Vkt3asvWbGux2S"] end end end else if B > 13379069 then if B < 13513599 then if B < 13441411 then V = Q[Y[1]] B = V > 0 B = B and 3136511 or 13701406 elseif 13481942 > B then J = Q[Y[1]] K = J B = 2313140 h = 1 f = 0 > 1 J = 1 - 1 elseif 13498397 > B then V = Q[Y[18]] R = g["Pos"] r = Q[Y[19]] d = V(R, r) R = #d V = R > 0 B = V and 1490883 or 16000138 else f = Q[Y[10]] K = K + 1 V = f > 0 B = V and 7059638 or 9523558 end else if B < 13543417 then B = 11472810 v = "FARM \240\159\159\162" elseif B < 13562668 then B = 3965714 else B = 11534791 <= 2942944 V = { B, } B = p["8Vi2d0IHEM4L"] end end else if B > 13198498 then if B < 13259094 then B = 5431705 elseif B < 13318236 then V = { "safe-mode", } B = p["00QpFOKfZ2vE"] elseif 13333511 > B then s, m = E(O, s) B = s and 1597098 or 13676734 else H = W() Q[H] = n l = p["math"] k = l["random"] l = k(1, 100) k = W() Q[k] = l l = Q[I] Z = l(0, 255) l = W() Q[l] = Z Z = Q[I] c = Q[k] C = Z(1, c) Z = W() Q[Z] = C y = Q[I] c = y(1, 2) C = c == 1 y = W() Q[y] = C pL = p["tostring"] zL = Q[I] wL = { zL(0, 10000), } P = pL(i(wL)) YL = P .. ":" D = ":" .. YL C = G["gsub"] C = C(G, ":(%d*):", D) c = W() YL = e(6140930, { I, H, S, h, J, U, y, c, k, Z, l, g, }) Q[c] = C D = p["pcall"] o = { D(YL), } C = { i(o), } D = Q[y] B = D and 5496486 or 11740481 end else if B < 13158633 then B = 13206972 elseif 13168733 > B then v = p["table"] B = v["clear"] J = Q[Y[1]] v = B(J) V, B = { }, p["AjQzPtRH2x0hdi"] elseif B < 13182974 then v = w[1] B = v and 15208673 or 11351942 else r = Q[X] R = r["Visible"] g, B = R, R and 2354480 or 7156397 end end end end else if B > 13910743 then if B > 14383931 then if B < 14507673 then if 14403211 > B then m = 11196116 < 14747332 X = Q[J] s = X == m B = s and 14848075 or 5255120 elseif B < 14430298 then s = Q[h] O = s["Parent"] B, E = 5413919, O elseif 14468672 > B then B = 9156743 J = v["FindFirstChild"] J = J(v, "HumanoidRootPart") V = J else Q[Y[14]] = Q[Y[14]] + 1 B = 15076293 I = Q[Y[3]] G = X["Model"] r = G["Name"] n = #m H = n .. " enemies nearby." G = ": " .. H R = r .. G g = "SKIP " .. R S = I(g) I = Q[Y[15]] S = I() end else if 14532648 > B then B = 1841764 elseif 14548485 > B then V = Q[Y[22]] E = V() B = 2201916 else O = x(2378948, { h, Y[2], Y[3], f, }) B = p["pcall"] E = B(O) B = 6402229 end end else if B < 14074857 then if B < 13956277 then v = w[1] B, J = v["FindFirstChild"], 9730207 ~= 744340 B = B(v, "Chest", J) J = B B = J and 11733050 or 15426340 elseif B < 14020895 then B = p["gybmiXPAaJOVmq"] h = Q[Y[15]] f = h() h = Q[Y[3]] J = b(J) V = { } f = h("STOP farm.") elseif 14053080 > B then B = 7533310 else B, f = h and 15091457 or 666340, h end else if 14095187 > B then S = q(10100393, { s, }) B = p["pcall"] g = { B(S), } I = g[2] m = g[1] S, B = m, m and 4349275 or 2419274 elseif 14177600 > B then v = W() Q[v] = w[1] V = Q[v] B = not V B = B and 13102791 or 13466451 elseif B < 14317971 then B = 14047090 else B = Q[Y[1]] J = p["Vector3"] v = J["zero"] B["AssemblyLinearVelocity"] = v B = Q[Y[1]] J = p["CFrame"] v = J["new"] f = Q[Y[4]] h = f["Pos"] E = p["Vector3"] f = E["new"] E = f(0, 3, 2) K = h + E f = Q[Y[4]] h = f["Pos"] J = v(K, h) B["CFrame"] = J B, V = p["K1E2RwOJCQrf"], { } end end end else if B > 13695734 then if B < 13783402 then if 13724110 > B then B = p["fireproximityprompt"] v = Q[Y[2]] V = B(v) B = 2326724 elseif 13761535 > B then B = p["pcall"] J = e(10715391, { Y[3], Y[1], Y[2], }) V = B(J) B = Q[Y[4]] V = B("Auto-dismounted from seat.") B = 10220335 elseif 13777949 > B then B = 14978953 k = "-" else B = 8909251 n = p["l2"] p["l1"] = n end else if 13796356 > B then B = Q[Y[4]] V = B() B = Q[Y[5]] V = B() V = p["_G"] B = V["TrackScan"] B = B and 371958 or 8039136 elseif B < 13840622 then V, B = { K, }, p["1RkMGpVmui10l5"] elseif 13889661 > B then B, V = p["zz6g49pAa9Eq"], { O, } else B = 4602584 end end else if 13667837 > B then if 13638607 > B then I = Q[Y[12]] g = X["Pos"] d = Q[Y[13]] S = I(g, d) m = S S = #m I = S > 0 B = I and 14495781 or 4377484 elseif B < 13639406 then m = 7495096 >= 8008796 Q[J] = m B = 3322234 elseif B < 13651187 then B = p["pcall"] h = e(1747752, { J, Y[1], Y[2], }) f = { B(h), } K = f[2] V = f[1] h = V V, B = h, h and 4128390 or 9675773 else B = 2415617 end else if B < 13674929 then O = p["task"] V = O["wait"] B = 2797691 O = V(1) elseif B < 13682677 then V, B = { f, }, p["PEko2nISRNoG"] elseif B < 13689341 then S = A(9235755, { s, Y[2], Y[3], }) X = p["pcall"] g = { X(S), } I, m = g[2], g[1] X, B = m, m and 293933 or 3425667 else V = Q[Y[5]] v = V() V = Q[Y[6]] B = v >= V B = B and 1922567 or 5011328 end end end end end end end end end B = #a return i(V) end, 0, function(p, z) local i = K(z) local w = function(w, Y, a, N, V, Q, v) return B(p, { w, Y, a, N, V, Q, v, }, z, i) end return w end, function(p, z) local i = K(z) local w = function(w, Y, a, N, V) return B(p, { w, Y, a, N, V, }, z, i) end return w end, function(p) for z = 1, #p, 1 do v[p[z]] = 1 + v[p[z]] end if w then local B = w(true) local i = a(B) i["__index"], i["__gc"], i["__len"] = p, h, function() return 2641646 end return B else return Y({ }, { ["__gc"] = h, ["__index"] = p, ["__len"] = function() return 2641646 end, }) end end, function(p) local z, B = 1, p[1] while B do v[B], z = v[B] - 1, 1 + z if 0 == v[B] then v[B], Q[B] = nil, nil end B = p[z] end end, function() J = 1 + J v[J] = 1 return J end, function(p, z) local i = K(z) local w = function(w, Y, a) return B(p, { w, Y, a, }, z, i) end return w end, function(p, z) local i = K(z) local w = function(w, Y, a, N, V, Q) return B(p, { w, Y, a, N, V, Q, }, z, i) end return w end, function(p) v[p] = v[p] - 1 if 0 == v[p] then v[p], Q[p] = nil, nil end end, { }, function(p, z) local i = K(z) local w = function(w, Y) return B(p, { w, Y, }, z, i) end return w end, function(p, z) local i = K(z) local w = function() return B(p, { }, z, i) end return w end, { }, function(p, z) local i = K(z) local w = function(w, Y, a, N) return B(p, { w, Y, a, N, }, z, i) end return w end, function(p, z) local i = K(z) local w = function(...) return B(p, { ..., }, z, i) end return w end return (f(11058636, { }))(i(V)) end)(ctx.env, { ..., }, select, setmetatable, unpack or table["unpack"], newproxy, getmetatable) end)() end]====]
    local FEATURE_SOURCE = [=====[return function(api)
    local s, now, controller = api.state, api.now, api.controller
    local F = {}
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
    function M.hover(ctx)
        -- Local anchoring can stop the assembly's normal physics replication.
        -- Balance gravity while keeping the character unanchored and movable.
        ctx.root.Anchored = false
        if ctx.root.AssemblyLinearVelocity then ctx.root.AssemblyLinearVelocity = Vector3.zero end
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
    local function streamAhead(ctx, position)
        if ctx.streamRequest then
            local token = ctx.streamRequest
            if now() - token.started > 8 and token.thread and coroutine.status(token.thread) ~= 'dead' then
                pcall(task.cancel, token.thread)
                if coroutine.status(token.thread) ~= 'dead' then return end
            end
            if not token.done and (not token.thread or coroutine.status(token.thread) ~= 'dead') then return end
            ctx.streamRequest = nil
        end
        if now() < (ctx.streamAt or 0) or ctx.streamUnsupported then return end
        local read, method = pcall(function() return api.Players.LocalPlayer.RequestStreamAroundAsync end)
        if not read or type(method) ~= 'function' then ctx.streamUnsupported = true; return end
        ctx.streamAt = now() + 2
        local token = {started = now()}; ctx.streamRequest = token
        token.thread = task.spawn(function()
            local ok, why = pcall(method, api.Players.LocalPlayer, position, 3)
            token.done, token.ok = true, ok
            if ctx.active and ctx.streamRequest == token and not ok then
                ctx.streamError = tostring(why)
            end
        end)
    end
    function M.prefetchAt(ctx, position) streamAhead(ctx, position) end
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
        M.cancel(ctx)
        if ctx.hoverConnection then pcall(function() ctx.hoverConnection:Disconnect() end); ctx.hoverConnection = nil end
        if ctx.hoverForce then pcall(function() ctx.hoverForce:Destroy() end); ctx.hoverForce = nil end
        if ctx.hoverAttachment then pcall(function() ctx.hoverAttachment:Destroy() end); ctx.hoverAttachment = nil end
        local token = ctx.streamRequest
        if token and token.thread and coroutine.status(token.thread) ~= 'dead' then pcall(task.cancel, token.thread) end
        ctx.streamRequest = nil
    end
    return M
end

end)()
    local movement = buildMovement(api)
    F.travelDepth, F.cancelTravel = movement.travel, movement.cancel
    F.syncRoute, F.initializeRoute, F.travelRoute = movement.syncRoute, movement.initializeRoute, movement.travelRoute
    F.hover = movement.hover
    local DEFAULTS = { smartLoot = false, extraction = false, minutes = 10 }
    local SETTINGS = 'EarthAutofarm_Settings_v7'
    local FILE = 'EarthAutofarmSettings.json'
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
        -- Old loot/mining/chest flags never opt the user into either new option.
        return { chest = true, smartLoot = data.smartLoot == true, extraction = data.extraction == true,
            minutes = clamp(data.minutes, 0, 180, DEFAULTS.minutes), schema = 11 }
    end
    local loaded = s.config
    if not loaded then
        local ok, value = pcall(function() return api.TeleportService:GetTeleportSetting(SETTINGS) end)
        if ok and type(value) == 'table' then loaded = value end
        local reader = api.env.readfile or readfile
        local http = getService('HttpService')
        if not loaded and type(reader) == 'function' and http then
            local read, text = pcall(reader, FILE)
            if read then local decoded, data = pcall(function() return http:JSONDecode(text) end); if decoded then loaded = data end end
        end
    end
    s.config = validate(loaded)
    local cfg = s.config
    local function persist()
        pcall(function() api.TeleportService:SetTeleportSetting(SETTINGS, cfg) end)
        local writer = api.env.writefile or writefile
        local http = getService('HttpService')
        if type(writer) == 'function' and http then
            pcall(function() writer(FILE, http:JSONEncode(cfg)) end)
        end
    end
    local function status(text)
        if s.featureStatus ~= text then
            s.featureStatus, s.featureStatusAt = text, now()
            print('[Earth Autofarm] ' .. text)
        end
    end
    function F.change(key, value)
        if DEFAULTS[key] == nil then return end
        if key == 'minutes' then cfg.minutes = clamp(value, 0, 180, cfg.minutes)
        elseif type(value) == 'boolean' then cfg[key] = value else return end
        persist()
        if key == 'smartLoot' and not value and s.farm then s.farm.smartLootWindow = nil end
        -- An option change never resets chest progress or replaces a live farm.
        status('Chest farm running; optional settings updated')
        if s.gui then pcall(s.gui.update) end
    end
    function F.extractionEnabled() return cfg.extraction end
    function F.extractionReady()
        return cfg.extraction and s.lootStarted ~= nil and now() - s.lootStarted >= cfg.minutes * 60
    end
    function F.smartLootEnabled() return cfg.smartLoot end
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
    local existing = parent:FindFirstChild('EarthAutofarmPanel')
    if existing then existing:Destroy() end
    ui.screen = make('ScreenGui', parent, { Name = 'EarthAutofarmPanel', ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 1500, IgnoreGuiInset = false })
    local panel = make('Frame', ui.screen, { Name = 'Panel', AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -20, 0, 30), Size = UDim2.new(0, 410, 0, 396),
        BackgroundColor3 = color.bg, BorderSizePixel = 0, Active = true })
    rounded(panel, 16)
    make('UIStroke', panel, { Color = color.edge, Thickness = 1 })
    local scale = make('UIScale', panel, { Scale = 1 })
    local header = make('Frame', panel, { Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1, Active = true })
    local mark = label(header, 'E', 18, 16, 32, 32, 22, color.accent, true)
    mark.TextXAlignment = Enum.TextXAlignment.Center
    label(header, 'EARTH / AUTOFARM', 62, 13, 260, 23, 17, color.text, true)
    label(header, 'Chest farm starts automatically.', 62, 36, 270, 16, 11, color.muted)
    local minimize = make('TextButton', header, { Text = '−', Font = bold, TextSize = 24,
        TextColor3 = color.muted, BackgroundTransparency = 1, Position = UDim2.new(1, -46, 0, 13),
        Size = UDim2.new(0, 32, 0, 34), AutoButtonColor = false })
    local body = make('Frame', panel, { Position = UDim2.new(0, 0, 0, 64),
        Size = UDim2.new(1, 0, 0, 332), BackgroundTransparency = 1 })
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
    local smart = row(1, 'Smart loot items', 'Useful gear upgrades, Shards and Void Crystals', 0)
    local church = row(2, 'Church extraction', 'Search and return after the minimum time', 80)
    local minimum = row(3, 'Minimum run time', 'Only applies when Church extraction is ON', 160)
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
        local button = make('TextButton', parentBox, { Position = UDim2.new(1, -71, 0, 16),
            Size = UDim2.new(0, 57, 0, 29), Font = bold, TextSize = 11, BorderSizePixel = 0,
            AutoButtonColor = false })
        rounded(button, 8)
        bind(button.Activated, function() api.change(key, not cfg[key]) end)
        return button
    end
    local switches = { smartLoot = toggle(smart, 'smartLoot'), extraction = toggle(church, 'extraction') }
    local status = make('Frame', body, { Position = UDim2.new(0, 16, 0, 240), Size = UDim2.new(1, -32, 0, 85),
        BackgroundTransparency = 1 })
    ui.stage = label(status, 'Waiting for readiness…', 0, 0, 378, 31, 12, color.accent, true)
    ui.stats = label(status, '', 0, 34, 378, 37, 11, color.muted)
    local collapsed = false
    bind(minimize.Activated, function()
        collapsed = not collapsed; body.Visible = not collapsed
        panel.Size = UDim2.new(0, 410, 0, collapsed and 64 or 396); minimize.Text = collapsed and '+' or '−'
    end)
    local UIS = api.getService('UserInputService')
    if UIS then
        local dragging, origin, initial
        bind(header.InputBegan, function(inputObject)
            if inputObject.UserInputType == Enum.UserInputType.MouseButton1 or inputObject.UserInputType == Enum.UserInputType.Touch then
                dragging, origin, initial = true, inputObject.Position, panel.Position
            end
        end)
        bind(UIS.InputEnded, function(inputObject)
            if inputObject.UserInputType == Enum.UserInputType.MouseButton1 or inputObject.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)
        bind(UIS.InputChanged, function(inputObject)
            if dragging and (inputObject.UserInputType == Enum.UserInputType.MouseMovement or inputObject.UserInputType == Enum.UserInputType.Touch) then
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
        minutes.TextEditable = cfg.extraction
        minutes.TextTransparency = cfg.extraction and 0 or 0.55
        local elapsed = math.max(0, api.now() - (s.lootStarted or api.now()))
        local ctx = s.farm
        local optionalActive = cfg.extraction and (s.runExhausted or elapsed >= cfg.minutes * 60)
            or cfg.smartLoot and (s.lootRequest or ctx and (ctx.featureHold or ctx.gearPickup))
            or s.featureStatusAt and api.now() - s.featureStatusAt < 3
        ui.stage.Text = optionalActive and s.featureStatus or s.status or 'Waiting for readiness…'
        local h = api.player.Character and api.player.Character:FindFirstChildOfClass('Humanoid')
        local health = h and h.MaxHealth > 0 and math.floor(100 * h.Health / h.MaxHealth) or 0
        local bag = s.sackSize and string.format('%s/%s', s.sackSize, s.sackCapacity or '?') or '—'
        ui.stats.Text = string.format('%02d:%02d elapsed   ·   HP %d%%   ·   Sack %s\n%d chest removals   ·   %d Cores observed',
            math.floor(elapsed / 60), math.floor(elapsed % 60), health, bag, s.stats.lootObserved or 0, s.stats.coreEarned or 0)
        if cfg.smartLoot then
            ui.stats.Text = ui.stats.Text .. string.format('\n%d loot pickups · %s', s.stats.smartPickups or 0, s.smartLootStatus or 'Checking loose items')
        end
        local camera = workspace.CurrentCamera
        if camera then scale.Scale = math.min(1, math.max(0.55, math.min((camera.ViewportSize.Y - 60) / 396, (camera.ViewportSize.X - 40) / 410))) end
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
    local function children(item) return item and item:GetChildren() or {} end
    function F.enemies()
        local result, seen = {}, {}
        local function add(npc)
            if npc and npc.Parent and npc:IsA('Model') and not seen[npc] then
                seen[npc] = true; result[#result + 1] = npc
            end
        end
        for _, npc in ipairs(children(workspace:FindFirstChild('Npc'))) do add(npc) end
        -- DungeonUIController discovers dungeon bosses through NpcManager.Parent.
        for _, manager in ipairs(tagged('NpcManager')) do add(manager.Parent) end
        return result
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
    F.promptPosition = position
    function F.chestFallbackAllowed(item)
        while item and item ~= workspace do
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
        return true
    end
    function F.chestLootWindow(ctx, point)
        if cfg.smartLoot then
            ctx.smartLootWindow = { position = point, untilAt = now() + 1.5, expires = now() + 7 }
            s.smartLootStatus = 'Waiting for chest drops'
        end
    end
    function F.smartLootPending(ctx)
        local window = ctx.smartLootWindow
        if not cfg.smartLoot or window and now() >= window.untilAt then ctx.smartLootWindow = nil; return false end
        return window ~= nil
    end
    local function tools(ctx)
        local list, seen = {}, {}
        for _, container in ipairs({ ctx.character, api.Players.LocalPlayer:FindFirstChild('Backpack') }) do
            for _, tool in ipairs(children(container)) do
                if tool:IsA('Tool') then list[#list + 1] = tool; seen[id(tool)] = true end
            end
        end
        -- ToolController equips a Tool=true Model named item+UserId. It is owned gear,
        -- even when its backpack Tool is absent; avoid counting a retained proxy twice.
        for _, model in ipairs(children(ctx.character)) do
            if model:IsA('Model') and attr(model, 'Tool') == true and not seen[id(model)] then
                list[#list + 1] = model; seen[id(model)] = true
            end
        end
        return list
    end
    -- ToolStack uses MedicalStackCount for relics as well as stacked medical tools.
    local RELICS = {RareShard = true, EpicShard = true, LegendaryShard = true, MythicShard = true, VoidCrystal = true}
    local function isRelic(item) return RELICS[id(item)] == true or attr(item, 'Class') == 'Relic' end
    local function stackCount(item)
        local count = item:GetAttribute('MedicalStackCount')
        return type(count) == 'number' and count == count and count > 0 and count < math.huge and math.max(1, math.floor(count)) or 1
    end
    local function inventoryCount(ctx, name)
        local total = 0
        for _, tool in ipairs(tools(ctx)) do if id(tool) == name then total = total + stackCount(tool) end end
        return total
    end
    local function hasRoom(ctx, item)
        return #tools(ctx) < 6 or RELICS[id(item)] == true and inventoryCount(ctx, id(item)) > 0
    end
    F.isRelic, F.stackCount, F.hasRoom = isRelic, stackCount, hasRoom
    local function weaponValue(item)
        local damage = tonumber(attr(item, 'Damage')) or 0
        local speed = tonumber(attr(item, 'AttackSpeed')) or 1
        if damage ~= damage or damage == math.huge or damage < 0 then return 0 end
        if speed ~= speed or speed == math.huge or speed <= 0 then speed = 1 end
        return damage * speed
    end
    local function findTool(ctx, class)
        local best, score
        for _, tool in ipairs(tools(ctx)) do
            local name = id(tool)
            local candidate = attr(tool, 'Class')
            if name == 'Champions_Hammer' then candidate = 'Pickaxe' end
            if name == 'Sword_Executioner' then candidate = 'Sword' end
            if candidate == class or class == 'ItemBag' and (name == 'Large_Sack' or name == 'ItemBag') then
                local value = class == 'ItemBag' and (tonumber(attr(tool, 'MaxSize')) or (name == 'Large_Sack' and 20 or 10))
                    or weaponValue(tool)
                if not best or value > score then best, score = tool, value end
            end
        end
        return best
    end
    local function activeFor(ctx, tool)
        local c = controller('ToolController')
        local active = c and c.ActiveTool
        if active and not active._Destroyed and active.Tool and active.Tool.Parent == ctx.character then
            local name = id(tool)
            if active.Tool == tool or active.DisplayTool == tool or active.Tool.Name == name
                or active.Tool.Name == name .. tostring(api.Players.LocalPlayer.UserId) then return active end
        end
    end
    local function equip(ctx, tool)
        if not tool or not tool.Parent then return nil end
        local active = activeFor(ctx, tool)
        if active then s.equipRecords[tool] = nil; return active end
        if tool.Parent == ctx.character then return nil end
        local record = s.equipRecords[tool]
        if record and (record.pending or record.accepted or now() < (record.retryAt or 0)) then return nil end
        record = record or {}; s.equipRecords[tool] = record
        local issued = api.request('equip-weapon', 'ToolService', 'EquipTool', api.pack(tool), function(result)
            record.pending = nil
            record.accepted, record.retryAt = api.accepted(result), now() + 3
        end)
        if issued then record.pending = true end
    end
    local function wait(ctx, seconds)
        ctx.featurePulse = now()
        ctx.check(); task.wait(seconds or 0.1); ctx.check()
        ctx.featurePulse = now()
        if ctx.pendingThreat and ctx.pendingThreat.expires > now()
            and ctx.featureOperation ~= 'dodge' then
            error('__EARTH_DEFENSE_RETRY', 0)
        end
        if ctx.featureOperation == 'gear' and not cfg.smartLoot
            or (ctx.featureOperation == 'extract' or ctx.featureOperation == 'discovery' or ctx.featureOperation == 'church-search') and not F.extractionReady() then
            error('__EARTH_MODE_CHANGED', 0)
        end
    end
    local function safeToWork(ctx)
        return ctx.active and not s.request and not s.awaiting and not s.teleporting and not s.departureAt
            and not workspace:GetAttribute('InCutScene') and not workspace:GetAttribute('InfiniteRebasing')
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
        ctx.featureHold, ctx.featureOperation, ctx.equipIntent = nil, nil, nil
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
        if not safeToWork(ctx) then return false end
        return api.request('loot-action', service, method, api.pack(argument), callback)
    end
    function F.isChurchSavePrompt(item)
        -- UIController's native FramePrompt handler opens the frame whose name
        -- equals the prompt Name. SaveGear is not a ReturnToLobby prompt.
        return item and item.Parent and descendant(item, workspace) and item:IsA('ProximityPrompt')
            and item.Name == 'SaveGear' and F.chestFallbackAllowed(item) and not F.skipLootArea(item)
            and (tag(item, 'FramePrompt') or ancestry(item, 'church') or ancestry(item, 'altar'))
    end
    local function rememberChurch(ctx, item)
        local point = position(item)
        if not point then return end
        local band = tonumber(workspace:GetAttribute('InfiniteDepthOffsetMeters')) or 0
        local key = string.format('%.1f:%.1f:%.1f:%s', point.X, point.Y, point.Z, tostring(band))
        s.churchMemories = s.churchMemories or {}
        for _, record in ipairs(s.churchMemories) do
            if record.key == key then record.seen = now(); return end
        end
        s.churchMemories[#s.churchMemories + 1] = {key = key, position = point, band = band, seen = now()}
        if #s.churchMemories > 12 then table.remove(s.churchMemories, 1) end
    end
    function F.observeChurch(ctx)
        if not cfg.extraction or now() < (ctx.churchObserveAt or 0) then return end
        ctx.churchObserveAt = now() + 1
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
        if ctx.featureIndex and now() < (ctx.indexAt or 0) and not next(ctx.indexPending or {}) then return ctx.featureIndex end
        local refresh = not ctx.featureIndex or now() >= (ctx.fullIndexAt or 0)
        local data, seen = { church = {} }, {}
        local function classify(item)
            if not item or not item.Parent or not item:IsA('ProximityPrompt') or seen[item] or F.skipLootArea(item) then return end
            local action = (tostring(item.ActionText or '') .. ' ' .. item.Name):lower()
            if F.isChurchSavePrompt(item) or (ancestry(item, 'church') or ancestry(item, 'altar')) and F.chestFallbackAllowed(item)
                and (action:find('lobby', 1, true) or action:find('extract', 1, true) or action:find('return', 1, true)) then
                seen[item] = true; data.church[#data.church + 1] = item
                if cfg.extraction then rememberChurch(ctx, item) end
            end
        end
        for _, item in ipairs(ctx.featureIndex and ctx.featureIndex.church or {}) do classify(item) end
        if refresh then
            local queue, cursor, processed = {workspace}, 1, 0
            while cursor <= #queue do
                local parent = queue[cursor]; cursor = cursor + 1
                for _, item in ipairs(parent:GetChildren()) do
                    classify(item); queue[#queue + 1] = item; processed = processed + 1
                    if processed % 100 == 0 then wait(ctx, 0.03) end
                end
            end
            ctx.fullIndexAt = now() + 30
        end
        for item in pairs(ctx.indexPending or {}) do classify(item) end
        -- Tags can arrive after DescendantAdded. Query the small native registry
        -- independently of a full workspace refresh.
        for _, item in ipairs(tagged('FramePrompt')) do classify(item) end
        ctx.indexPending = {}
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
    local function firePrompt(ctx, prompt)
        if not prompt or not prompt.Parent or prompt.Enabled == false then return false end
        if not F.chestFallbackAllowed(prompt) then return false end
        local ready = prompt:GetAttribute('DungeonDoorReady')
        if ready == false then return false end
        if not move(ctx, prompt, Vector3.new(0, 0, 2)) then return false end
        local paused = api.Players.LocalPlayer.GameplayPaused
        local point = position(prompt)
        local radius = tonumber(prompt.MaxActivationDistance) or 10
        if paused or not point or (point - ctx.root.Position).Magnitude > radius then
            status('Prompt waiting for loaded content and its actual activation range'); return false
        end
        local original = prompt.HoldDuration
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
        if not ok then status('Prompt action failed: ' .. tostring(why)) end
        return ok
    end
    function F.prompt(ctx, prompt) return firePrompt(ctx, prompt) end
    local rarity = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Secret = 7 }
    local function armorSlot(item)
        local slot = attr(item, 'ArmorType')
        if slot == 'Helmet' then slot = 'Head' elseif slot == 'Chestplate' then slot = 'Chest' elseif slot == 'Pants' then slot = 'Legs' end
        if slot == 'Head' or slot == 'Chest' or slot == 'Legs' or slot == 'Boots' then return slot end
    end
    local function armorBetter(ctx, item)
        local slot = armorSlot(item); if not slot then return false end
        local armor = tonumber(attr(item, 'Armor')) or 0
        local current = tonumber(ctx.character:GetAttribute(slot)) or 0
        local speed = tonumber(attr(item, 'SpeedBoost')) or 0
        local existingSpeed = 0
        for _, equipped in ipairs(children(ctx.character)) do
            if equipped:GetAttribute('ArmorName') and armorSlot(equipped) == slot then existingSpeed = tonumber(equipped:GetAttribute('SpeedBoost')) or 0 end
        end
        return armor > current or armor == current and slot == 'Boots' and speed > existingSpeed
    end
    local function weaponBetter(ctx, item)
        local class = attr(item, 'Class')
        if class ~= 'Sword' and class ~= 'Pickaxe' and class ~= 'ItemBag' then return false end
        local current = findTool(ctx, class)
        if not current then return true end
        local value = class == 'ItemBag' and (tonumber(attr(item, 'MaxSize')) or 0) or weaponValue(item)
        local existing = class == 'ItemBag' and (tonumber(attr(current, 'MaxSize')) or 0) or weaponValue(current)
        return value > existing or value == existing and (rarity[attr(item, 'Rarity')] or 0) > (rarity[attr(current, 'Rarity')] or 0)
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
    local function upgradeGear(ctx)
        if not cfg.smartLoot then return false end
        F.smartLootPending(ctx)
        local pending = ctx.gearPickup
        if pending then
            if gearReceipt(ctx, pending) then
                ctx.gearPickup = nil; ctx.itemRetry[pending.item] = math.huge
                s.stats.smartPickups = (s.stats.smartPickups or 0) + 1
                s.smartLootStatus = 'Confirmed ' .. pending.id
                status('Gear pickup confirmed: ' .. pending.id)
            elseif now() - pending.started < 5 or not pending.settled then
                s.smartLootStatus = 'Awaiting inventory receipt: ' .. pending.id
                -- A bounded settle window has ended; never repeat an uncertain interaction.
                return false
            else
                ctx.itemRetry[pending.item] = now() + 300; ctx.gearPickup = nil
                s.smartLootStatus = 'No pickup receipt: ' .. pending.id
                status('No gear receipt for ' .. pending.id .. '; skipping that item for 5 minutes')
            end
        end
        if s.lootRequest then return false end
        local items = worldItems()
        local target = nearest(ctx, items, function(item)
            return isRelic(item) and F.freeWorldItemAllowed(item)
                and now() >= (ctx.itemRetry[item] or 0) and hasRoom(ctx, item)
        end, 180)
        target = target or nearest(ctx, items, function(item)
            return F.freeWorldItemAllowed(item) and (armorBetter(ctx, item) or weaponBetter(ctx, item))
                and now() >= (ctx.itemRetry[item] or 0)
                and (#tools(ctx) < 6 or armorSlot(item))
        end, 180)
        if not target then
            if not ctx.smartLootWindow then
                local nearby = nearest(ctx, items, nil, 180)
                local blocked = nearest(ctx, items, function(item)
                    return F.freeWorldItemAllowed(item) and (isRelic(item) or weaponBetter(ctx, item))
                        and not hasRoom(ctx, item)
                end, 180)
                s.smartLootStatus = blocked and 'Toolbar full; useful loot skipped'
                    or nearby and 'No eligible upgrades nearby' or 'No loose gear nearby'
            end
            return false
        end
        if not acquire(ctx, 'gear') then s.smartLootStatus = 'Waiting for chest movement to yield'; return false end
        status((isRelic(target) and 'Collecting a relic: ' or 'Equipping a useful upgrade: ') .. id(target))
        s.smartLootStatus = 'Picking up ' .. id(target)
        if not move(ctx, target) then release(ctx); return false end
        local record = { item = target, id = id(target), slot = armorSlot(target), inventory = {}, started = now(),
            relic = isRelic(target), beforeCount = inventoryCount(ctx, id(target)) }
        for _, item in ipairs(tools(ctx)) do record.inventory[item] = true end
        for _, item in ipairs(children(ctx.character)) do record.inventory[item] = true end
        ctx.gearPickup = record; ctx.itemRetry[target] = now() + 300
        if ctx.smartLootWindow then
            ctx.smartLootWindow.untilAt = math.min(ctx.smartLootWindow.expires, now() + 2)
        end
        local issued = operation(ctx, 'InteractionService', 'Interact', target, function(result)
            record.settled = true
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
        release(ctx); return issued
    end
    local function bag(ctx)
        local tool = findTool(ctx, 'ItemBag'); if not tool then return nil end
        ctx.equipIntent = tool
        local active = equip(ctx, tool)
        if active then
            s.sackSize, s.sackCapacity = tonumber(active.Size), tonumber(active.MaxSize)
            if not ctx.bagObserver or ctx.bagObserver.active ~= active then
                if ctx.bagObserver and ctx.bagObserver.active.UpdateSackSize == ctx.bagObserver.wrapper then
                    ctx.bagObserver.active.UpdateSackSize = ctx.bagObserver.original
                end
                local original = active.UpdateSackSize
                if type(original) == 'function' then
                    local wrapper = function(self, quantity, ...)
                        local result = original(self, quantity, ...)
                        if self == active and type(quantity) == 'number' then
                            ctx.bagConfirmed = active; s.sackSize, s.sackCapacity = quantity, active.MaxSize
                        end
                        return result
                    end
                    ctx.bagObserver = { active = active, original = original, wrapper = wrapper }
                    active.UpdateSackSize = wrapper
                    -- This is the same request used by the native bag initialization.
                    if active.Execute then active.Execute:Fire({ 'GetStoredItems' }) end
                end
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
            ctx.collectedResources = (ctx.collectedResources or 0) + 1
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
        active.Execute:Fire({ 'Drop' }); wait(ctx, 0.35)
        ctx.sackDrop.item = newlyDropped(ctx.sackDrop.snapshot, ctx)
        return ctx.sackDrop.item
    end
    local function npcHealth(npc)
        local h = npc:FindFirstChildOfClass('Humanoid')
        return h and h.Health or tonumber(npc:GetAttribute('FuelLeechHealth')) or 0
    end
    local function finite(value)
        return type(value) == 'number' and value == value and math.abs(value) < math.huge
    end
    local function auraModule(name)
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
    function F.usePendant(ctx)
        -- Only an already-owned pendant; use its native lifecycle/cooldown handler.
        if ctx.featureHold or ctx.currentChest or not safeToWork(ctx) then return false end
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
                if npc:IsA('Model') and not isPlayer and npc:GetAttribute('NpcFaction') ~= 'FriendlyCompanion' then
                    local point = bounds.GetModelHitPosition(npc, { Position = ctx.root.Position })
                    if point and (point - ctx.root.Position).Magnitude <= range then add(npc) end
                end
            end
        end
        return targets
    end
    function F.swing(ctx, active)
        ctx.check()
        if not active or active._Destroyed or not active.Tool or active.Tool.Parent ~= ctx.character then return false end
        local c = controller('ToolController')
        if not c or c.ActiveTool ~= active or not safeToWork(ctx) or not readyAction(active) then return false end
        if type(active.CanUseAction) ~= 'function' or type(active.RecordUseCooldown) ~= 'function' then return false end
        local class, hammer = auraClass(active)
        if class ~= 'Sword' and class ~= 'Pickaxe' then return false end
        if hammer and (active.InputDown or active.PendingAttackType) then return false end
        local interval
        if type(active.GetAttackInterval) == 'function' then interval = active:GetAttackInterval(hammer and 'Weak' or nil)
        else
            local speed = auraModule('AttackSpeed')
            if speed and type(speed.GetInterval) == 'function' then interval = speed.GetInterval(active.AttackSpeed or 0) end
        end
        if not finite(interval) or interval <= 0 then return false end
        local impactDelay
        if hammer then
            local timing = auraModule('ChampionHammerTiming')
            if not timing or type(timing.GetLightImpactDelay) ~= 'function' then return false end
            impactDelay = timing.GetLightImpactDelay(interval)
        end
        local signal = active.Execute
        if not signal or type(signal.Fire) ~= 'function' then return false end
        -- Refresh after any yielding native-module lookup; a previous snapshot can be stale.
        local targets = F.auraTargets(ctx, active)
        if #targets == 0 then return false end
        ctx.check()
        if c.ActiveTool ~= active or active.Tool.Parent ~= ctx.character or not safeToWork(ctx) or not readyAction(active) then return false end
        local payload = hammer and { 'Swing', targets, 'Weak', impactDelay, workspace:GetServerTimeNow() } or { 'Swing', targets }
        local before = {}
        for _, target in ipairs(targets) do before[target] = auraHealth(target) or 0 end
        local count
        pcall(function() count = #signal:GetConnections() end)
        local route = 'CustomTool.Execute'
        if count == 0 then
            local knit = s.knit
            local ok, service = pcall(function() return knit.GetService('ToolService') end)
            if not ok or not service or not service.Update or type(service.Update.Fire) ~= 'function' then
                status('Aura signal has no listener; waiting for native ToolService.Update'); return false
            end
            service.Update:Fire(payload); route = 'ToolService.Update (listener fallback)'
        else signal:Fire(payload) end
        active.LastSwing = now() + interval
        if hammer then active.AttackLockedUntil = active.LastSwing end
        active:RecordUseCooldown(active.LastSwing)
        ctx.lastAura = { time = now(), route = route, count = #targets, class = class }
        for _, target in ipairs(targets) do
            if not tag(target, 'Ore') then F.afterAttack(ctx, target, class, before[target]) end
        end
        return true
    end
    function F.weaponClass(ctx, target)
        if ctx.pickaxeTargets and ctx.pickaxeTargets[target] then return 'Pickaxe' end
    end
    function F.afterAttack(ctx, target, class, before)
        if class ~= 'Sword' or not target or not target.Parent then return end
        local record = ctx.damageChecks[target] or { failures = 0 }
        ctx.damageChecks[target] = record
        if record.before and npcHealth(target) >= record.before then record.failures = record.failures + 1 else record.failures = 0 end
        record.before = before
        if record.failures >= 3 and findTool(ctx, 'Pickaxe') then
            ctx.pickaxeTargets[target] = true
            status('Sword attacks show no health change; trying an owned pickaxe')
        end
    end
    function F.watcher(ctx)
        if now() >= (ctx.watcherSearchAt or 0) then
            ctx.watcherSearchAt = now() + 0.15
            ctx.watcher = nearest(ctx, tagged('Watcher'), function(item) return npcHealth(item) > 0 and item:GetAttribute('Category') ~= 'Corpse' end, 400)
        end
        local closest = ctx.watcher
        if closest and (not closest.Parent or npcHealth(closest) <= 0) then closest = nil end
        ctx.watcher = closest
        if closest and workspace.CurrentCamera then
            local eyes = closest:FindFirstChild('Eyes', true) or part(closest)
            if eyes then
                local camera = workspace.CurrentCamera
                ctx.watcherCamera = camera
                ctx.cameraBeforeWatcher = ctx.cameraBeforeWatcher or camera.CFrame
                camera.CFrame = CFrame.lookAt(camera.CFrame.Position, eyes.Position)
                ctx.watcherFrame = camera.CFrame
            end
        elseif ctx.cameraBeforeWatcher then
            local camera = ctx.watcherCamera
            if camera and camera.CFrame == ctx.watcherFrame then camera.CFrame = ctx.cameraBeforeWatcher end
            ctx.cameraBeforeWatcher, ctx.watcherFrame = nil, nil
        end
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
    function F.observeThreat(ctx)
        if not F.enabled() or not safeToWork(ctx) then return nil end
        F.bindShots(ctx)
        ctx.attackCues = ctx.attackCues or setmetatable({}, {__mode = 'k'})
        if ctx.pendingThreat and now() >= ctx.pendingThreat.expires then
            ctx.pendingThreat, ctx.defenseAbort = nil, nil
        end
        if ctx.pendingThreat then return ctx.pendingThreat end
        if now() < (ctx.blinkerObserveAt or 0) then return nil end
        ctx.blinkerObserveAt = now() + 0.1
        for _, manager in ipairs(tagged('NpcManager')) do
            ctx.cueConnections = ctx.cueConnections or setmetatable({}, {__mode = 'k'})
            if not ctx.cueConnections[manager] and type(manager.GetAttributeChangedSignal) == 'function' then
                ctx.cueConnections[manager] = true
                local function changed()
                    ctx.blinkerObserveAt = 0
                    -- Queue the cue synchronously; movement belongs to the defense worker.
                    pcall(F.observeThreat, ctx)
                end
                ctx.connect(manager:GetAttributeChangedSignal('ForceAnimation'), changed)
                ctx.connect(manager:GetAttributeChangedSignal('ForceAnimationNonce'), changed)
            end
            local npc = manager.Parent
            local name = npc and (npc:GetAttribute('RealName') or npc.Name)
            if (name == 'Blinker' or manager:GetAttribute('IsBoss') == true) and npcHealth(npc) > 0
                and npc:GetAttribute('NpcFaction') ~= 'FriendlyCompanion' then
                local animation, nonce = manager:GetAttribute('ForceAnimation'), manager:GetAttribute('ForceAnimationNonce')
                local point = position(npc)
                local token = tostring(animation) .. ':' .. tostring(nonce)
                local ranged = type(animation) == 'string' and animation:lower():match('shoot')
                    or type(animation) == 'string' and animation:lower():match('projectile')
                    or type(animation) == 'string' and animation:lower():match('cast')
                if ((name == 'Blinker' and animation == 'Attack') or (manager:GetAttribute('IsBoss') == true and ranged))
                    and point and (point - ctx.root.Position).Magnitude <= 120
                    and ctx.attackCues[manager] ~= token then
                    -- NpcManagerComponent uses Blinker Attack as its launch cue.
                    ctx.pendingThreat = {npc = npc, origin = point, kind = name == 'Blinker' and 'Blinker cast' or 'boss ranged cast',
                        source = manager, token = token, expires = now() + 0.6}
                    if ctx.currentChest then ctx.defenseAbort = true end
                    return ctx.pendingThreat
                end
            end
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
            if clear then
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
        local active = bag(ctx)
        if not active or ctx.bagConfirmed ~= active then
            status('Return waits for confirmed sack contents'); return false
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
        pcall(function() api.TeleportService:SetTeleportSetting('ChestFarmAutoLoop_FreshRun', true) end)
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
        s.churchSave = record
        local issued = api.request('church-save', 'PlayerService', 'SaveGear', api.pack(), function(result)
            record.settled, record.accepted = true, result[1] and not not result[2]
            record.retryAt = now() + 15
            if record.accepted then
                status('Church SaveGear accepted; awaiting the game saved-exit state')
            else status('Church SaveGear rejected; retrying the native church flow after 15 seconds') end
        end)
        if not issued then s.churchSave = nil; status('Church save request not ready; retrying without a duplicate'); return false end
        record.issued = true
        status('Confirming church SaveGear; awaiting server reply')
        -- The transition request is owned by the supervisor, survives a worker
        -- replacement, and blocks overlapping lobby/start/save requests.
        return true
    end
    local function revisitChurch(ctx)
        if not F.extractionReady() or now() < (ctx.churchRevisitAt or 0) or s.churchSave then return false end
        local band = tonumber(workspace:GetAttribute('InfiniteDepthOffsetMeters')) or 0
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
        wait(ctx, 0.5)
        ctx.indexAt, ctx.fullIndexAt = 0, 0
        release(ctx); return true
    end
    local function extract(ctx, data)
        if not F.extractionReady() then return false end
        if savedChurchState() then return true end
        local save = s.churchSave
        if save then
            if not save.settled then status('Church SaveGear reply pending; no duplicate save is sent'); return false end
            if save.accepted then status('Church save accepted; waiting for server exit confirmation'); return false end
            if now() < (save.retryAt or 0) then return false end
            s.churchSave = nil
        end
        local prompt = nearest(ctx, data.church, function(item)
            return item.Enabled ~= false and F.chestFallbackAllowed(item)
        end)
        if not prompt then
            if revisitChurch(ctx) then return true end
            status(s.runExhausted and 'No church SaveGear prompt loaded; available tunnel exhausted, waiting for server content'
                or 'Minimum time met; looking for native church SaveGear prompts')
            if now() >= (ctx.churchNoticeAt or 0) then
                ctx.churchNoticeAt = now() + 30
                print('[Earth Church] No eligible prompt loaded; remembered churches=' .. tostring(#(s.churchMemories or {}))
                    .. ', route exhausted=' .. tostring(s.runExhausted == true) .. '. Ordinary return does not save loot.')
            end
            return false
        end
        if now() < (ctx.extractAt or 0) or now() < (ctx.packRetryAt or 0) then return false end
        if s.lootRequest then status('Church return waits for the outstanding item reply; chest work continues'); return false end
        if not acquire(ctx, 'extract') then return false end
        if not packForReturn(ctx, data) then
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
        if not F.extractionReady() or not s.runExhausted or now() < (ctx.discoveryAt or 0) then return false end
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
        movement.cleanup(ctx)
        if not ctx.active and ctx.defenseThread and ctx.defenseThread ~= coroutine.running() then pcall(task.cancel, ctx.defenseThread) end
        release(ctx); ctx.combatTarget = nil
        pcall(function() if ctx.swingEdit and ctx.swingEdit.signal.Fire == ctx.swingEdit.wrapper then ctx.swingEdit.signal.Fire = ctx.swingEdit.original end end)
        pcall(function() if ctx.dragEdit and ctx.dragEdit.controller.ResolveLockedTargetPosition == ctx.dragEdit.wrapper then
            ctx.dragEdit.controller.ResolveLockedTargetPosition = ctx.dragEdit.original
        end end)
        pcall(function() if ctx.dragController and ctx.dragController.LockedTarget == ctx.draggedItem then ctx.dragController:ReleaseLockedTarget() end end)
        for prompt, duration in pairs(ctx.instantPrompts or {}) do pcall(function() if prompt.Parent then prompt.HoldDuration = duration end end) end
        local camera = ctx.watcherCamera
        pcall(function() if camera and camera.CFrame == ctx.watcherFrame and ctx.cameraBeforeWatcher then camera.CFrame = ctx.cameraBeforeWatcher end end)
        if ctx.watcherBinding and not ctx.active then pcall(function() api.RunService:UnbindFromRenderStep(ctx.watcherBinding) end) end
        ctx.swingEdit, ctx.dragEdit, ctx.instantPrompts = nil, nil, nil
        pcall(function() if ctx.bagObserver and ctx.bagObserver.active.UpdateSackSize == ctx.bagObserver.wrapper then
            ctx.bagObserver.active.UpdateSackSize = ctx.bagObserver.original
        end end)
        ctx.bagObserver = nil
        s.pendingSackDrop = ctx.sackDrop
    end
    function F.watchdog(ctx)
        if ctx.active then F.startDefense(ctx) end
        if not ctx.active or not ctx.initialized or not ctx.featureThread then return end
        local worker = ctx.featureThread
        local dead = coroutine.status(worker) == 'dead'
        if not dead and (not ctx.featureHold or now() - (ctx.featurePulse or now()) < 20) then return end
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
        F.cleanup(ctx)
        ctx.featureThread = nil
        ctx.featureRecoveries = (ctx.featureRecoveries or 0) + 1
        status('Recovered optional worker; preserving chest route')
        F.runWorker(ctx)
    end
    function F.start(ctx)
        s.equipRecords = s.equipRecords or setmetatable({}, { __mode = 'k' })
        s.lootStarted = s.lootStarted or now()
        s.sackSize, s.sackCapacity = nil, nil
        ctx.itemRetry, ctx.damageChecks, ctx.pickaxeTargets = {}, {}, {}
        ctx.sackDrop = s.pendingSackDrop
        ctx.safePosition = ctx.root.Position
        if workspace.DescendantAdded then
            ctx.connect(workspace.DescendantAdded, function(item)
                if item:IsA('ProximityPrompt') and cfg.extraction then
                    ctx.indexPending = ctx.indexPending or {}; ctx.indexPending[item] = true
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
                    ctx.check()
                    F.watcher(ctx)
                    if not safeToWork(ctx) then release(ctx); return end
                    if not ctx.defenseThread and F.dodge(ctx) then return end
                    if ctx.dodgeUntil and now() < ctx.dodgeUntil then return end
                    if ctx.pendantAttempt and now() - ctx.pendantAttempt.started < 5 then release(ctx); return end
                    if not cfg.smartLoot and not cfg.extraction then release(ctx); return end
                    F.observeChurch(ctx)
                    if (cfg.smartLoot or F.extractionReady()) and not s.itemDatabase then
                        status('Waiting for item definitions before smart loot / church packing'); return
                    end
                    -- Church return takes priority as soon as the minimum time is met.
                    if F.extractionReady() then
                        local data = index(ctx)
                        if extract(ctx, data) then return end
                        if not s.churchSave and discover(ctx) then return end
                    elseif cfg.extraction and s.runExhausted then
                        status(string.format('Chest route complete; church extraction unlocks in %.0fs', cfg.minutes * 60 - (now() - s.lootStarted)))
                    end
                    if cfg.smartLoot then
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
    local features

    local function startCombat(ctx, player, model, humanoid, root)
        if ctx.combatThread then return end
        s.equipRecords = s.equipRecords or setmetatable({}, { __mode = "k" })
        local combat = { equipRecords = s.equipRecords, nextAttack = 0 }
        ctx.combat = combat
        local function notice(message)
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
        local function nearestHostile(radius)
            local npcFolder = workspace:FindFirstChild("Npc")
            local target, targetPart, distance
            for _, npc in ipairs(features and features.enemies() or (npcFolder and npcFolder:GetChildren() or {})) do
                if npc:IsA("Model") and npc:GetAttribute("NpcFaction") ~= "FriendlyCompanion" then
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
                if ok and threat then combat.holdUntil, combat.burstUntil = nil, nil; return end
            end
            local scene = controller("CutSceneController")
            if workspace:GetAttribute("InCutScene") or workspace:GetAttribute("InfiniteRebasing")
                or (scene and (scene.CurrentCutScene or scene.AbortingCutScene))
                or s.request or s.awaiting or s.departureAt
                or ctx.featureHold then
                combat.holdUntil, combat.burstUntil = nil, nil
                return
            end
            if ctx.dodgeUntil and now() < ctx.dodgeUntil then return end
            if features and features.dodge(ctx) then return end
            if features and features.usePendant(ctx) then return end
            if now() >= (combat.inventoryAt or 0) or not combat.selected
                or not combat.selected.tool.Parent or (combat.selected.tool.Parent ~= model and combat.selected.tool.Parent ~= child(player, "Backpack")) then
                combat.selected, combat.inventoryAt = bestWeapon(), now() + 1
            end
            local selected = combat.selected
            local preferClass = features and features.weaponClass(ctx, ctx.combatTarget or combat.target)
            if preferClass then
                local preferred = features.findTool(ctx, preferClass)
                if preferred then selected = weapon(preferred); combat.selected = selected end
            end
            if not selected then notice("No supported weapon found; checking inventory automatically"); return end
            if selected.priority == 0 then notice("Weapon has no available ammunition; checking for alternatives"); return end
            local c = controller("ToolController")
            if not c then notice("Waiting for the native ToolController"); return end
            local active = c.ActiveTool
            local ready = active and not active._Destroyed and active.Tool and active.Tool.Parent == model
                and (active.Tool == selected.tool or (active.DisplayTool == selected.tool))
            -- The native equipped representation can be a separate model named item+UserId.
            if not ready and active and not active._Destroyed and active.Tool and active.Tool.Parent == model then
                ready = active.Tool.Name == selected.id or active.Tool.Name == selected.id .. tostring(player.UserId)
            end
            if not ready then
                local record = combat.equipRecords[selected.tool]
                if selected.tool.Parent == model then notice("Waiting for the equipped weapon's native attack handler"); return end
                if record and record.accepted then
                    notice("Equip request accepted; waiting for replicated equipment confirmation")
                    return -- EquipTool toggles equipment; an uncertain accepted action must not be resent.
                end
                if record and now() < (record.retryAt or 0) then return end
                record = record or {}; combat.equipRecords[selected.tool] = record
                if request("equip-weapon", "ToolService", "EquipTool", pack(selected.tool), function(result)
                    record.accepted, record.retryAt = accepted(result), now() + 3
                end) then notice("Equipping " .. selected.tool.Name) end
                return
            end
            combat.equipRecords[selected.tool] = nil
            notice("Always-on aura ready: " .. selected.tool.Name)
            if now() < combat.nextAttack then return end
            if humanoid.SeatPart or humanoid.Sit then return end
            local radius = selected.melee and features.weaponRange(active, selected.tool) or 80
            local auraTargets = selected.melee and features and features.auraTargets(ctx, active)
            local target, part = nearestHostile(radius)
            if ctx.combatTarget and ctx.combatTarget.Parent then
                local desiredPart = ctx.combatTarget:FindFirstChild("HumanoidRootPart") or ctx.combatTarget.PrimaryPart
                if desiredPart and (desiredPart.Position - root.Position).Magnitude <= radius then target, part = ctx.combatTarget, desiredPart end
            end
            if not target and (not auraTargets or #auraTargets == 0) then
                combat.holdUntil, combat.burstUntil, combat.target = nil, nil, nil; return
            end
            if type(active.CanUseAction) == "function" and not active:CanUseAction() then return end
            local cooldown = math.max(tonumber(active.LastSwing) or 0, tonumber(active.AttackLockedUntil) or 0, tonumber(active.Debounce) or 0)
            if now() < cooldown then combat.nextAttack = cooldown; return end
            local method = selected.melee and active.Swing or active.Shoot
            if not selected.melee and type(method) ~= "function" then notice("Waiting for a supported native attack method"); return end
            if not selected.melee then
                if ctx.watcher then return end -- Keep actual camera attention on a one-hit threat.
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
            local ok, why
            if selected.melee and features then ok, why = pcall(features.swing, ctx, active, auraTargets)
            else ok, why = pcall(method, active) end
            combat.restoreAim()
            if not ok then error(why, 0) end
            if selected.melee and why ~= true then return end
            if not selected.melee and features then features.afterAttack(ctx, target, selected.class, healthBefore) end
            local endsAt = math.max(tonumber(active.LastSwing) or 0, tonumber(active.AttackLockedUntil) or 0, tonumber(active.Debounce) or 0)
            combat.nextAttack = math.max(now() + 0.1, endsAt)
            if target and endsAt > now() then
                if combat.target ~= target then combat.target, combat.burstUntil = target, now() + 6 end
                -- A threat gets a bounded defensive burst before movement can resume.
                combat.holdUntil = math.min(endsAt, combat.burstUntil or now())
            end
        end
        ctx.combatThread = task.spawn(function()
            while ctx.active and owned() and s.farm == ctx do
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
            TeleportService = TeleportService })
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
            flags = {}, threads = {}, connections = {}, savedParts = {}, started = now() }
        features.initializeRoute(ctx)
        s.farm = ctx
        ctx.helpers = {}
        local taskApi = {}
        local function readWorld()
            while ctx.worldReading do ctx.check(); ctx.awaitCombat(); task.wait(0.03) end
            if not ctx.worldObjects or now() >= (ctx.worldRefreshAt or 0) then
                ctx.worldReading = true
                local ok, objects = pcall(function()
                    local list, queue, cursor, seen = {}, {workspace}, 1, {[workspace] = true}
                    while cursor <= #queue do
                        local parent = queue[cursor]; cursor = cursor + 1
                        for _, child in ipairs(parent:GetChildren()) do
                            if not seen[child] then
                                seen[child] = true; list[#list + 1] = child; queue[#queue + 1] = child
                                if #list % 100 == 0 then ctx.check(); ctx.awaitCombat(); task.wait(0.03) end
                            end
                        end
                    end
                    return list
                end)
                ctx.worldReading = nil
                if not ok then error(objects, 0) end
                ctx.worldObjects, ctx.worldRefreshAt = objects, now() + (workspace.DescendantAdded and 30 or 2)
            end
            local list, seen = {}, {}
            for _, item in ipairs(ctx.worldObjects) do
                if item.Parent then list[#list + 1] = item; seen[item] = true end
            end
            for item in pairs(ctx.worldPending or {}) do
                if item.Parent and not seen[item] then list[#list + 1] = item end
            end
            ctx.worldPending, ctx.worldObjects = {}, list
            return list
        end
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
                    if not ctx.candidates or ctx.chestsDirty or now() >= (ctx.cacheAt or 0) then
                        readWorld()
                        ctx.candidates = fn(...)
                        ctx.cacheAt, ctx.chestsDirty = now() + (workspace.DescendantAdded and 30 or 2), false
                    end
                    local list = {}
                    for _, entry in ipairs(ctx.candidates) do
                        if entry.Model.Parent and not features.skipLootArea(entry.Model)
                            and features.chestFallbackAllowed(entry.Model) then
                            local record = chestRecord(entry)
                            if not record.locked and not record.retired and now() >= (record.retryAt or 0)
                                and not ((record.failures or 0) >= 3 and entry.Pos.X < (s.routeScanX or entry.Pos.X) - 300) then
                                entry.Dist = (entry.Pos - root.Position).Magnitude
                                table.insert(list, entry)
                            end
                        end
                    end
                    table.sort(list, function(a, b) return a.Dist < b.Dist end)
                    return list
                end
            elseif id == 16361397 then
                wrapped = function(entry, ...)
                    if features.skipLootArea(entry.Model) or not features.chestFallbackAllowed(entry.Model) then return "skipped" end
                    if ctx.awaitCombat then ctx.awaitCombat() end
                    if not features.chestEnabled() and coroutine.running() ~= ctx.featureThread then return "disabled" end
                    local record = chestRecord(entry)
                    if record.locked or record.retired or now() < (record.retryAt or 0) then return "locked" end
                    local attempts = s.stats.promptFires
                    ctx.currentChest = record
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
            if coroutine.running() == ctx.featureThread and (ctx.defenseMoving or now() < (ctx.dodgeUntil or 0)) then
                error('__EARTH_DEFENSE_RETRY', 0)
            end
        end
        function ctx.awaitCombat()
            while ctx.active and ((ctx.combat and now() < (ctx.combat.holdUntil or 0) and coroutine.running() ~= ctx.featureThread)
                or (ctx.featureHold and coroutine.running() ~= ctx.featureThread)
                or (features.smartLootPending(ctx) and coroutine.running() ~= ctx.featureThread)
                or ctx.defenseMoving
                or (ctx.dodgeUntil and now() < ctx.dodgeUntil)) do
                ctx.routeParked = true
                ctx.check()
                task.wait(0.05)
            end
            if coroutine.running() ~= ctx.featureThread then ctx.routeParked = nil end
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
        ctx.env.workspace = setmetatable({GetDescendants = function() return ctx.worldObjects or readWorld() end},
            {__index = function(_, key)
                local value = workspace[key]
                if type(value) == 'function' then return function(_, ...) return value(workspace, ...) end end
                return value
            end})
        function ctx.prepareChestPrompt(prompt)
            ctx.check()
            if not prompt.Parent or prompt.Enabled == false then return false end
            local target = features.promptPosition(prompt) or (ctx.currentChest and ctx.currentChest.entry.Pos)
            if not target then
                print('[ChestFarm] Waiting for a chest prompt position to load'); return false
            end
            local radius = tonumber(prompt.MaxActivationDistance) or 12
            if radius <= 0 then return false end
            features.hover(ctx)
            local offset = math.min(2, radius / 4)
            local destination = target + Vector3.new(0, offset, offset)
            if ((root.CFrame.Position or root.Position) - destination).Magnitude > 0.5 then
                root.CFrame = CFrame.new(destination)
            end
            taskApi.wait(0.15) -- Let the unanchored character's new position propagate.
            local deadline = now() + 2
            while player.GameplayPaused == true and now() < deadline do taskApi.wait(0.1) end
            if player.GameplayPaused == true or ((root.CFrame.Position or root.Position) - target).Magnitude > radius then
                print('[ChestFarm] Chest prompt not ready: loading pause or character outside activation range')
                return false
            end
            return true
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
                taskApi.wait(math.max(0.03, duration + 0.05))
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
            restoreZoneOrigin()
            restoreZoneTouches()
            -- Do not assume membership changed until ExitedZone/controller state confirms it.
            s.zoneExitAt = now()
            waitTransition("exit-zone", zone, 12)
        end)
    end
    local function lobby(player, model, humanoid, root)
        stopFarm()
        if not alive(player, model, humanoid, root) then status("Waiting for lobby character"); return end
        for _, method in ipairs({ "TouchedZone", "CreatedZone", "ExitZone" }) do
            if not remote("TeleportManagerService", method) then status("Waiting for lobby action " .. method); return end
        end
        local c = configureParty()
        if not c or not s.signalsBound then status("Waiting for lobby controller and zone signals"); return end
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
        local zone = c.Zone or s.zone
        if zone and zone.Parent then
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
                    pcall(function() TeleportService:SetTeleportSetting(FRESH_SETTING, false) end)
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
        if not selected then status("Waiting for an empty PartyZone"); return end
        if now() < (s.nextAction or 0) then return end
        -- Keep the actual character inside the zone, matching the normal touch path.
        -- Disable local touch callbacks while entering, so only the explicit verified request is sent.
        if s.zoneOriginCharacter ~= model then s.zoneOrigin, s.zoneOriginCharacter = root.CFrame, model end
        s.touchParts = s.touchParts or {}
        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                if s.touchParts[part] == nil then s.touchParts[part] = part.CanTouch end
                part.CanTouch = false
            end
        end
        root.CFrame = selected.CFrame * CFrame.new(0, selected.Size.Y / 2 + 3, 0)
        s.touchCandidate, s.touchAt = selected, now()
        request("create", "TeleportManagerService", "TouchedZone", pack(selected), function(result)
            if not result[1] or result[2] == false then s.touchCandidate = nil
            elseif s.touchCandidate == selected then s.touchAt = now() end
        end)
    end
    local function returnToLobby()
        request("return", "TeleportManagerService", "TeleportToLobby", pack(true), function(result)
            if accepted(result) then waitTransition("return") end
        end)
    end
    local function recoverDeath(player, model)
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
        s.heartbeat = now()
        local player, model, humanoid, root = character()
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
            s.deadSince, s.drillMissingSince, s.everReady = nil, nil, false
            s.lootStarted, s.extractionAttempt, s.extractionAttemptAt = nil, nil, nil
            s.churchSave, s.churchMemories = nil, nil
            if not features.enabled() then stopFarm(); status("Both farm modes are off"); return end
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
            s.deathCoinIdentity, s.deathCoinProbeAt, s.deathCoins = nil, nil, nil
        end
        if player:GetAttribute('SavedExitTeleportLocked') == true then
            stopFarm()
            if not s.forceFresh then
                s.forceFresh = true
                pcall(function() TeleportService:SetTeleportSetting(FRESH_SETTING, true) end)
            end
            local savedUI = controller('DeathScreenController')
            if player:GetAttribute('SavedExitRetryAvailable') == true and not (savedUI and savedUI.SavedExitRetryRequest) then
                request('saved-return', 'PlayerService', 'SaveGear', pack(), function(result)
                    if accepted(result) then waitTransition('saved-return') end
                end)
            else status('Game saved-exit state confirmed; waiting for lobby transfer') end
            return
        end
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
        if s.runExhausted and (not features.extractionEnabled()
            or s.seatBlockedSince and now() - s.seatBlockedSince >= 30) then
            s.returnReason = s.seatBlockedSince and 'Seat recovery started a fresh chest run' or 'Chest route exhausted; starting a fresh run'
            s.forceFresh = true
            local ok = pcall(function() TeleportService:SetTeleportSetting(FRESH_SETTING, true) end)
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
        if ctx then features.watchdog(ctx) end
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
    armResume()
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
local entry, why = loader(SOURCE, "@ChestFarmAutoLoop")
assert(entry, why)
entry()(SOURCE)
