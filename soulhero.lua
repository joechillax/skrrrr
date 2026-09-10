local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local HttpS = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

-- ======================================================================
-- SCRIPT SETTINGS
-- ======================================================================
local INITIAL_WAIT = 2
local REBIRTH_CHECK_COOLDOWN = 1
local AUTO_BUY_COOLDOWN = 10

task.wait(INITIAL_WAIT)

-- Configuration Folder Setup
local fName = "FarmingConfigs"
if makefolder and not isfolder(fName) then
    pcall(makefolder, fName)
end

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
    Name = "Auto Farming GUI",
    LoadingTitle = "Loading Script...",
    LoadingSubtitle = "Initializing interface...",
    ConfigurationSaving = {
        Enabled = false, -- Handled by our custom config system
    },
    KeySystem = false,
})

-- Create Tabs
local MainTab = Window:CreateTab("Automation", nil)
local ConfigTab = Window:CreateTab("Configuration", nil)

-- ======================================================================
-- FEATURE VARIABLES
-- ======================================================================
local autoRebirthEnabled = false
local targetRebirthStage = 0
local autoBuyNodesEnabled = false

-- ======================================================================
-- AUTOMATION UI
-- ======================================================================
MainTab:CreateSection("Auto Rebirth")

MainTab:CreateInput({
    Name = "Target Stage for Rebirth",
    PlaceholderText = "Enter stage number...",
    RemoveTextAfterFocusLost = false,
    Callback = function(text)
        targetRebirthStage = tonumber(text) or 0
    end,
})

local AutoRebirthToggle = MainTab:CreateToggle({
    Name = "Enable Auto Rebirth",
    CurrentValue = false,
    Flag = "AutoRebirthToggle",
    Callback = function(value)
        autoRebirthEnabled = value
    end,
})

MainTab:CreateSection("Auto Upgrades")

local AutoBuyToggle = MainTab:CreateToggle({
    Name = "Enable Auto Buy Skill Nodes",
    CurrentValue = false,
    Flag = "AutoBuyToggle",
    Callback = function(value)
        autoBuyNodesEnabled = value
    end,
})

-- ======================================================================
-- AUTOMATION LOOPS
-- ======================================================================
-- Auto Rebirth Loop
task.spawn(function()
    while task.wait(REBIRTH_CHECK_COOLDOWN) do
        if autoRebirthEnabled and targetRebirthStage > 0 then
            local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
            if leaderstats then
                local stageVal = leaderstats:FindFirstChild("Stage")
                -- Check if the current stage meets or exceeds the target
                if stageVal and tonumber(stageVal.Value) and tonumber(stageVal.Value) >= targetRebirthStage then
                    pcall(function()
                        local event = Workspace:FindFirstChild("Network") and Workspace.Network:FindFirstChild("AttemptRebirth-RemoteFunction")
                        if event then
                            event:InvokeServer()
                        end
                    end)
                end
            end
        end
    end
end)

-- Auto Buy Skill Tree Nodes Loop
task.spawn(function()
    while task.wait(AUTO_BUY_COOLDOWN) do
        if autoBuyNodesEnabled then
            pcall(function()
                local event = Workspace:FindFirstChild("Network") and Workspace.Network:FindFirstChild("MaxBuySkillTreeNodes-RemoteFunction")
                if event then
                    event:InvokeServer()
                end
            end)
        end
    end
end)

-- ======================================================================
-- CONFIGURATION SYSTEM
-- ======================================================================
local tCfg = "Config"
local sCfg = "Config"

ConfigTab:CreateSection("Configuration Profiles")

ConfigTab:CreateInput({
    Name = "Config name",
    PlaceholderText = "Enter profile name...",
    RemoveTextAfterFocusLost = false,
    Callback = function(text)
        if text and text ~= "" then
            tCfg = text
        end
    end,
})

local CDrp = ConfigTab:CreateDropdown({
    Name = "Config list",
    Options = { "Config" },
    CurrentOption = { "Config" },
    MultipleOptions = false,
    Callback = function(option)
        if option and option[1] then
            sCfg = option[1]
        end
    end,
})

local function refreshConfigList()
    local profiles = {}

    pcall(function()
        if listfiles then
            for _, filePath in ipairs(listfiles(fName)) do
                local name = filePath:match("([^/\\]+)%.json$")
                if name then
                    table.insert(profiles, name)
                end
            end
        end
    end)

    if #profiles == 0 then
        table.insert(profiles, "Config")
    else
        table.sort(profiles)
    end

    CDrp:Refresh(profiles, true)
end

local function saveConfig(name)
    if not writefile then return end

    pcall(function()
        writefile(fName .. "/" .. name .. ".json", HttpS:JSONEncode({
            Stage = targetRebirthStage,
            Rebirth = autoRebirthEnabled,
            BuyNodes = autoBuyNodesEnabled,
        }))
    end)
end

local function loadConfig(name)
    if not readfile or not isfile then return end

    pcall(function()
        local path = fName .. "/" .. name .. ".json"
        if not isfile(path) then return end

        local data = HttpS:JSONDecode(readfile(path))

        -- Apply settings to variables and UI
        if data.Stage ~= nil then
            targetRebirthStage = data.Stage
            -- Rayfield doesn't natively support setting Input text after creation,
            -- but the variable is updated for the loop to use.
        end

        if data.Rebirth ~= nil then
            AutoRebirthToggle:Set(data.Rebirth)
        end

        if data.BuyNodes ~= nil then
            AutoBuyToggle:Set(data.BuyNodes)
        end
    end)
end

local function activeConfigName()
    if sCfg ~= "Config" then
        return sCfg
    end
    return tCfg
end

ConfigTab:CreateButton({
    Name = "Create config",
    Callback = function()
        saveConfig(tCfg)
        task.wait(0.2)
        refreshConfigList()
        Rayfield:Notify({Title = "Config", Content = "Created: " .. tCfg, Duration = 2})
    end,
})

ConfigTab:CreateButton({
    Name = "Load config",
    Callback = function()
        local name = activeConfigName()
        loadConfig(name)
        Rayfield:Notify({Title = "Config", Content = "Loaded: " .. name, Duration = 2})
    end,
})

ConfigTab:CreateButton({
    Name = "Overwrite config",
    Callback = function()
        local name = activeConfigName()
        saveConfig(name)
        Rayfield:Notify({Title = "Config", Content = "Overwrote: " .. name, Duration = 2})
    end,
})

ConfigTab:CreateButton({
    Name = "Refresh list",
    Callback = function()
        refreshConfigList()
        Rayfield:Notify({Title = "Config", Content = "List refreshed.", Duration = 1})
    end,
})

local aLbl = ConfigTab:CreateParagraph({
    Title = "Set as autoload",
    Content = "Current autoload: none",
})

ConfigTab:CreateButton({
    Name = "Set as autoload",
    Callback = function()
        local name = activeConfigName()
        pcall(function()
            if writefile then
                writefile(fName .. "/Autoload.txt", name)
                aLbl:Set({
                    Title = "Set as autoload",
                    Content = "Current autoload: " .. name,
                })
                Rayfield:Notify({Title = "Config", Content = name .. " set to Autoload.", Duration = 2})
            end
        end)
    end,
})

-- Autoload Check on Startup
task.spawn(function()
    task.wait(1.5)
    refreshConfigList()

    pcall(function()
        if isfile and readfile and isfile(fName .. "/Autoload.txt") then
            local autoloadName = readfile(fName .. "/Autoload.txt")

            if autoloadName and autoloadName ~= "" then
                aLbl:Set({
                    Title = "Set as autoload",
                    Content = "Current autoload: " .. autoloadName,
                })
                loadConfig(autoloadName)
            end
        end
    end)
end)
