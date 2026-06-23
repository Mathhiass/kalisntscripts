-- Stop previous instance
if _G.MiniWarStop then
    _G.MiniWarStop()
end

_G.MiniWarRunning = true

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local LocalPlayer = Players.LocalPlayer

-- === GET BRIDGE FUNCTION ===
local GetBridge = require(ReplicatedStorage.util.GetBridge)
local BuildingsConfig = require(ReplicatedStorage.shared.config.BuildingsConfig)
local ClientData = require(ReplicatedStorage.client.modules.ClientData)
local ShopsConfig = require(ReplicatedStorage.shared.config.ShopsConfig)

-- === CONFIGURATION ===
local CONFIG = {
    AUTO_BUY_ENABLED = false,
    AUTO_COLLECT_ENABLED = false,
    AUTO_SELL_ALL = false,
    BUY_DELAY = 0.05,          
    COLLECT_DELAY = 0.3,       
    CAPTURE_DELAY = 60,
    LOOP_INTERVAL = 10,        
    SHOP_CATEGORIES = {"Farm", "House", "Military", "Decor"}, 
    USE_ITEM_WHITELIST = false, 
    ITEMS_TO_BUY = {},
    CAPTURE_SETTINGS = {
        ["KingOfTheHill"] = {Enabled = false, Army = {"1"}, TargetIndex = "1"},
        ["Garnison"] = {Enabled = false, Army = {"1"}, TargetIndex = "1"},
        ["Camp"] = {Enabled = false, Army = {"1"}, TargetIndex = "1"},
        ["MilitaryBase"] = {Enabled = false, Army = {"1"}, TargetIndex = "1"},
        ["City"] = {Enabled = false, Army = {"1"}, TargetIndex = "1"},
        ["WaterRig"] = {Enabled = false, Army = {"1"}, TargetIndex = "1"},
        ["Lab"] = {Enabled = false, Army = {"1"}, TargetIndex = "1"}
    }
}

-- === GATHER AVAILABLE ITEMS FOR UI ===
local categoryItems = {
    Farm = {},
    House = {},
    Military = {},
    Decor = {},
    BlackMarket = {}
}

for itemName, config in pairs(BuildingsConfig) do
    if not config.dontDisplayInShop then
        local category = config.ShopType or config.Type
        if category == "Farm" or category == "House" or category == "Military" or category == "Decor" then
            table.insert(categoryItems[category], itemName)
        end
    end
end

if ShopsConfig.BlackMarket then
    for _, bmItem in pairs(ShopsConfig.BlackMarket) do
        table.insert(categoryItems.BlackMarket, bmItem.name)
    end
end

for _, items in pairs(categoryItems) do
    table.sort(items)
end

-- === UI INITIALIZATION ===
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Kali Hub",
    SubTitle = "by kalisnt",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

-- === TABS ===
local Tabs = {
    Home = Window:AddTab({ Title = "Home", Icon = "home" }),
    Farm = Window:AddTab({ Title = "Auto Farm", Icon = "leaf" }),
    Shop = Window:AddTab({ Title = "Shop", Icon = "shopping-cart" }),
    Teleport = Window:AddTab({ Title = "Teleport", Icon = "map-pin" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local HomeTab = Tabs.Home
local FarmTab = Tabs.Farm
local ShopTab = Tabs.Shop
local TeleportTab = Tabs.Teleport

-- ==========================
-- 1. HOME TAB (STATS)
-- ==========================
local StatsParagraph = HomeTab:AddParagraph({
    Title = "Live Server Statistics",
    Content = "Loading data..."
})

local ShopTimersParagraph = ShopTab:AddParagraph({
    Title = "Shop Timers",
    Content = "Loading timers..."
})

-- Calculate FPS
local currentFPS = 0
local fpsConnection = RunService.Heartbeat:Connect(function(dt)
    currentFPS = math.round(1 / dt)
end)

task.spawn(function()
    while _G.MiniWarRunning do
        local ping = 0
        pcall(function()
            ping = math.round(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
        end)
        
        local serverTime = math.round(workspace.DistributedGameTime)
        local hours = math.floor(serverTime / 3600)
        local mins = math.floor((serverTime % 3600) / 60)
        local secs = serverTime % 60
        local timeString = string.format("%02d:%02d:%02d", hours, mins, secs)

        StatsParagraph:SetDesc(string.format("FPS: %d\nPing: %d ms\nServer Uptime: %s", currentFPS, ping, timeString))
        
        -- Shop Timers Update
        local normalShopRestock = "Unknown"
        local blackMarketRestock = "Unknown"
        local state = ClientData.playerProducer:getState()
        local shopsStock = state.player.shopsStock
        
        if shopsStock then
            if shopsStock["Farm"] and shopsStock["Farm"].nextRestock then
                local timeLeft = math.max(0, math.round(shopsStock["Farm"].nextRestock - workspace:GetServerTimeNow()))
                local mins = math.floor(timeLeft / 60)
                local secs = timeLeft % 60
                normalShopRestock = string.format("%02d:%02d", mins, secs)
            end
            
            if shopsStock["BlackMarket"] and shopsStock["BlackMarket"].nextRestock then
                local timeLeft = math.max(0, math.round(shopsStock["BlackMarket"].nextRestock - workspace:GetServerTimeNow()))
                local mins = math.floor(timeLeft / 60)
                local secs = timeLeft % 60
                blackMarketRestock = string.format("%02d:%02d", mins, secs)
            end
        end
        
        ShopTimersParagraph:SetDesc(string.format("Normal Shops Restock In: %s\nBlack Market Update In: %s", normalShopRestock, blackMarketRestock))
        
        task.wait(1)
    end
end)

-- ==========================
-- 2. AUTO FARM TAB
-- ==========================
FarmTab:AddToggle("AutoCollectToggle", {
   Title = "Auto Collect Resources",
   Default = false,
   Callback = function(Value)
        CONFIG.AUTO_COLLECT_ENABLED = Value
   end
})

FarmTab:AddToggle("AutoSellAllToggle", {
   Title = "Auto Sell All Crops (Ignore Price)",
   Default = false,
   Callback = function(Value)
        CONFIG.AUTO_SELL_ALL = Value
   end
})

FarmTab:AddSection("Smart Auto Sell (By Percentage)")
local SmartAutoSellStatus = FarmTab:AddParagraph({
    Title = "Smart Auto Sell Status",
    Content = "Loading..."
})

local lastToggleTick = 0
local SmartAutoSellToggle = FarmTab:AddToggle("SmartAutoSellToggle", {
   Title = "Smart Auto Sell (Bypass Gamepass)",
   Default = false,
   Callback = function(Value)
        pcall(function()
            local player = ClientData.playerProducer:getState().player
            if (player.autoSellEnabled == true) ~= Value then
                lastToggleTick = tick()
                GetBridge("ToggleAutoSell"):Fire()
            end
        end)
   end
})

local AutoSellSlider = FarmTab:AddSlider("AutoSellPercentSlider", {
    Title = "Smart Auto Sell Min Percentage",
    Min = -100,
    Max = 100,
    Default = 0,
    Rounding = 0,
    Callback = function(Value)
        pcall(function()
            local absoluteValue = Value + 100
            GetBridge("SetAutoSellMinPercent"):Fire(absoluteValue)
        end)
    end
})

-- Mobile-friendly input (Textbox) for direct percentage entry
FarmTab:AddTextbox("AutoSellPercentInput", {
    Title = "Smart Auto Sell Min % (Mobile)",
    Placeholder = "-100 to 100",
    Default = "0",
    Callback = function(Text)
        local num = tonumber(Text)
        if num then
            if num < -100 then num = -100 end
            if num > 100 then num = 100 end
            pcall(function()
                local absoluteValue = num + 100
                GetBridge("SetAutoSellMinPercent"):Fire(absoluteValue)
            end)
            -- Also update the slider to reflect the entered value
            local slider = FarmTab:GetSlider("AutoSellPercentSlider")
            if slider then slider:SetValue(num) end
        end
    end
})

local MarketPricesParagraph = FarmTab:AddParagraph({
    Title = "Live Market Prices",
    Content = "Loading prices..."
})

task.spawn(function()
    while _G.MiniWarRunning do
        pcall(function()
            local player = ClientData.playerProducer:getState().player
            local status = player.autoSellEnabled and "ON" or "OFF"
            local percent = player.autoSellMinPercent or 0
            local diff = percent - 100
            local formattedPercent = diff > 0 and ("+" .. diff .. "%") or (diff .. "%")
            SmartAutoSellStatus:SetDesc("Current Settings: " .. formattedPercent)
            
            if (player.autoSellEnabled == true) ~= SmartAutoSellToggle.Value then
                if tick() - lastToggleTick > 0.5 then
                    lastToggleTick = tick()
                    GetBridge("ToggleAutoSell"):Fire()
                end
            end
            
            local gameData = ClientData.gameProducer:getState()
            if gameData and gameData.market and gameData.market.stock then
                local stock = gameData.market.stock
                local marketText = ""
                local items = {}
                for itemName, stockVal in pairs(stock) do
                    local percentage = math.round((stockVal or 1) * 100)
                    local diff = percentage - 100
                    local formattedStr = diff > 0 and ("+" .. diff .. "%") or (diff .. "%")
                    table.insert(items, {name = itemName, val = formattedStr})
                end
                table.sort(items, function(a, b) return a.name < b.name end)
                
                for _, item in ipairs(items) do
                    marketText = marketText .. item.name .. ": " .. item.val .. "\n"
                end
                
                if marketText == "" then marketText = "No market data available" end
                MarketPricesParagraph:SetDesc(marketText)
            end
        end)
        task.wait(1)
    end
end)

-- ==========================
-- 3. SHOP TAB
-- ==========================
ShopTab:AddToggle("AutoBuyToggle", {
   Title = "Auto Buy",
   Default = false,
   Callback = function(Value)
        CONFIG.AUTO_BUY_ENABLED = Value
   end
})

ShopTab:AddToggle("UseWhitelistToggle", {
   Title = "Use Whitelist (Buy Selected Only)",
   Default = false,
   Callback = function(Value)
        CONFIG.USE_ITEM_WHITELIST = Value
   end
})

ShopTab:AddSlider("BuyDelaySlider", {
   Title = "Buy Delay",
   Min = 0,
   Max = 1,
   Default = 0.05,
   Rounding = 2,
   Callback = function(Value)
        CONFIG.BUY_DELAY = Value
   end
})

local function handleWhitelistChange(category, selectedOptions)
    for _, item in ipairs(categoryItems[category]) do
        CONFIG.ITEMS_TO_BUY[item] = nil
    end
    for item, isSelected in pairs(selectedOptions) do
        if isSelected then
            CONFIG.ITEMS_TO_BUY[item] = true
        end
    end
end

ShopTab:AddSection("Factory Items")
ShopTab:AddDropdown("FactoryDropdown", {
   Title = "Select Factory Items", Values = categoryItems.Farm, Multi = true, Default = {},
   Callback = function(Options) handleWhitelistChange("Farm", Options) end
})

ShopTab:AddSection("House Items")
ShopTab:AddDropdown("HousesDropdown", {
   Title = "Select House Items", Values = categoryItems.House, Multi = true, Default = {},
   Callback = function(Options) handleWhitelistChange("House", Options) end
})

ShopTab:AddSection("Military Items")
ShopTab:AddDropdown("MilitaryDropdown", {
   Title = "Select Military Items", Values = categoryItems.Military, Multi = true, Default = {},
   Callback = function(Options) handleWhitelistChange("Military", Options) end
})

ShopTab:AddSection("Special Items")
ShopTab:AddDropdown("SpecialDropdown", {
   Title = "Select Special/Decor Items", Values = categoryItems.Decor, Multi = true, Default = {},
   Callback = function(Options) handleWhitelistChange("Decor", Options) end
})

ShopTab:AddSection("Black Market Items")
ShopTab:AddDropdown("BlackMarketDropdown", {
   Title = "Select Black Market Items", Values = categoryItems.BlackMarket, Multi = true, Default = {},
   Callback = function(Options) handleWhitelistChange("BlackMarket", Options) end
})

-- ==========================
-- 4. TELEPORT TAB
-- ==========================
local function teleportTo(cframe)
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        LocalPlayer.Character.HumanoidRootPart.CFrame = cframe
    end
end

local function getTeleportCFrame(instance)
    if instance:IsA("Model") then
        if instance.PrimaryPart then
            return instance.PrimaryPart.CFrame
        else
            return instance:GetPivot()
        end
    elseif instance:IsA("BasePart") then
        return instance.CFrame
    end
    return nil
end

TeleportTab:AddSection("Manual Teleports")

local selectedTeleportPlayer = nil
local PlayerTeleportDropdown = TeleportTab:AddDropdown("PlayerTeleportDropdown", {
    Title = "Select Player",
    Values = {},
    Multi = false,
    Default = nil,
    Callback = function(Value)
        selectedTeleportPlayer = Value
    end
})

TeleportTab:AddButton({
    Title = "Teleport to Player",
    Callback = function()
        if selectedTeleportPlayer then
            local targetPlayer = Players:FindFirstChild(selectedTeleportPlayer)
            if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
                teleportTo(targetPlayer.Character.HumanoidRootPart.CFrame + Vector3.new(0, 3, 0))
            end
        end
    end
})

task.spawn(function()
    while _G.MiniWarRunning do
        local playerNames = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                table.insert(playerNames, p.Name)
            end
        end
        pcall(function() PlayerTeleportDropdown:SetValues(playerNames) end)
        task.wait(5)
    end
end)

local selectedPlot = nil
local plotNames = {}
local plotMap = {}

for _, p in ipairs(Players:GetPlayers()) do
    local tag = ("%s-Plot"):format(p.Name)
    local plots = CollectionService:GetTagged(tag)
    if #plots > 0 then
        table.insert(plotNames, p.Name .. "'s Plot")
        plotMap[p.Name .. "'s Plot"] = plots[1]
    end
end

local PlotTeleportDropdown = TeleportTab:AddDropdown("PlotTeleportDropdown", {
    Title = "Select Plot",
    Values = plotNames,
    Multi = false,
    Default = nil,
    Callback = function(Value)
        selectedPlot = Value
    end
})

TeleportTab:AddButton({
    Title = "Teleport to Plot",
    Callback = function()
        if selectedPlot and plotMap[selectedPlot] then
            local cf = getTeleportCFrame(plotMap[selectedPlot])
            if cf then
                teleportTo(cf + Vector3.new(0, 10, 0))
            end
        end
    end
})

local selectedCapturePoint = nil
local capturePointNames = {}
local capturePointMap = {}

local normalBases = CollectionService:GetTagged("CapturePoint")
local raidBases = CollectionService:GetTagged("CapturePointKingOfTheHill")

for _, base in ipairs(normalBases) do
    local bType = base:GetAttribute("baseType") or "Unknown"
    local name = bType .. " (" .. base.Name .. ")"
    table.insert(capturePointNames, name)
    capturePointMap[name] = base
end
for _, base in ipairs(raidBases) do
    local name = "Raid Base (" .. base.Name .. ")"
    table.insert(capturePointNames, name)
    capturePointMap[name] = base
end

table.sort(capturePointNames)

local CapturePointDropdown = TeleportTab:AddDropdown("CapturePointDropdown", {
    Title = "Select Map Building/Base",
    Values = capturePointNames,
    Multi = false,
    Default = nil,
    Callback = function(Value)
        selectedCapturePoint = Value
    end
})

TeleportTab:AddButton({
    Title = "Teleport to Map Building",
    Callback = function()
        if selectedCapturePoint and capturePointMap[selectedCapturePoint] then
            local cf = getTeleportCFrame(capturePointMap[selectedCapturePoint])
            if cf then
                teleportTo(cf + Vector3.new(0, 10, 0))
            end
        end
    end
})

local autoCapture -- Forward declare to trigger instantly on UI change

local function createCaptureUI(tab, displayName, internalName)
    tab:AddSection(displayName)
    tab:AddToggle("CaptureToggle_" .. internalName, {
        Title = "Auto Capture " .. displayName,
        Default = false,
        Callback = function(Value)
            CONFIG.CAPTURE_SETTINGS[internalName].Enabled = Value
            if Value and type(autoCapture) == "function" then
                task.spawn(autoCapture)
            end
        end
    })
    tab:AddDropdown("CaptureArmy_" .. internalName, {
        Title = "Armies to Send",
        Values = {"1", "2", "3", "4"},
        Multi = true,
        Default = {"1"},
        Callback = function(Value)
            local selectedArmies = {}
            for army, isSelected in pairs(Value) do
                if isSelected then table.insert(selectedArmies, army) end
            end
            CONFIG.CAPTURE_SETTINGS[internalName].Army = selectedArmies
            
            if CONFIG.CAPTURE_SETTINGS[internalName].Enabled and type(autoCapture) == "function" then
                task.spawn(autoCapture)
            end
        end
    })
    
    if internalName ~= "KingOfTheHill" and internalName ~= "City" then
        tab:AddDropdown("CaptureTarget_" .. internalName, {
            Title = "Specific Target",
            Values = {"1", "2", "3", "4", "5", "6", "Random"},
            Multi = false,
            Default = "1",
            Callback = function(Value)
                CONFIG.CAPTURE_SETTINGS[internalName].TargetIndex = Value
                if CONFIG.CAPTURE_SETTINGS[internalName].Enabled and type(autoCapture) == "function" then
                    task.spawn(autoCapture)
                end
            end
        })
    end
end

createCaptureUI(TeleportTab, "Raid Base (King of the Hill)", "KingOfTheHill")
createCaptureUI(TeleportTab, "Garrison", "Garnison")
createCaptureUI(TeleportTab, "Camp", "Camp")
createCaptureUI(TeleportTab, "Military Base", "MilitaryBase")
createCaptureUI(TeleportTab, "City", "City")
createCaptureUI(TeleportTab, "Oil Rig", "WaterRig")
createCaptureUI(TeleportTab, "Lab", "Lab")

-- === CONFIGURATION SAVING ===
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})

InterfaceManager:SetFolder("MiniWarHub")
SaveManager:SetFolder("MiniWarHub/configs")

InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)
SaveManager:LoadAutoloadConfig()

-- === MOBILE TOGGLE ===
local CoreGui = game:GetService("CoreGui")
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "KaliHubMobileToggle"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
    ScreenGui.Parent = CoreGui
end)
if ScreenGui.Parent == nil then
    ScreenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Parent = ScreenGui
ToggleBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
ToggleBtn.Position = UDim2.new(0.5, -25, 0, 20)
ToggleBtn.Size = UDim2.new(0, 50, 0, 50)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.Text = "KH"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.TextSize = 20
ToggleBtn.AutoButtonColor = false

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0.5, 0)
UICorner.Parent = ToggleBtn

local UIStroke = Instance.new("UIStroke")
UIStroke.Color = Color3.fromRGB(100, 100, 255)
UIStroke.Thickness = 2
UIStroke.Parent = ToggleBtn

local dragging, dragInput, dragStart, startPos
ToggleBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = ToggleBtn.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)
ToggleBtn.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
game:GetService("UserInputService").InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        ToggleBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

ToggleBtn.MouseButton1Click:Connect(function()
    local vim = game:GetService("VirtualInputManager")
    vim:SendKeyEvent(true, Enum.KeyCode.LeftControl, false, game)
    task.wait()
    vim:SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
end)

-- === STATE MANAGEMENT ===
_G.MiniWarStop = function()
    _G.MiniWarRunning = false
    if fpsConnection then fpsConnection:Disconnect() end
    if ScreenGui then ScreenGui:Destroy() end
    Window:Destroy()
end

-- === AUTO-BUY FUNCTION ===
local function autoBuy()
    if not CONFIG.AUTO_BUY_ENABLED then return end
    
    local state = ClientData.playerProducer:getState()
    local shopsStock = state.player.shopsStock
    
    -- Normal Shop Items
    for _, category in ipairs(CONFIG.SHOP_CATEGORIES) do
        local shopData = shopsStock[category]
        if shopData and shopData.stock then
            for itemName, stockCount in pairs(shopData.stock) do
                if stockCount > 0 then
                    local shouldBuy = true
                    if CONFIG.USE_ITEM_WHITELIST and not CONFIG.ITEMS_TO_BUY[itemName] then
                        shouldBuy = false
                    end
                    
                    if shouldBuy then
                        for i = 1, stockCount do
                            pcall(function()
                                GetBridge("BuyFromShop"):Fire({
                                    shop = category,
                                    item = itemName
                                })
                            end)
                            if CONFIG.BUY_DELAY > 0 then
                                task.wait(CONFIG.BUY_DELAY)
                            else
                                task.wait()
                            end
                        end
                    end
                end
            end
        end
    end

    -- Black Market Items
    for _, itemName in ipairs(categoryItems.BlackMarket) do
        local shouldBuy = true
        if CONFIG.USE_ITEM_WHITELIST and not CONFIG.ITEMS_TO_BUY[itemName] then
            shouldBuy = false
        end
        
        if shouldBuy then
            pcall(function()
                GetBridge("BuyFromBlackMarketShop"):Fire({
                    shop = "BlackMarket",
                    item = itemName
                })
            end)
            task.wait(CONFIG.BUY_DELAY)
        end
    end
end

-- === AUTO-COLLECT FUNCTION ===
local function autoCollect()
    if not CONFIG.AUTO_COLLECT_ENABLED then return end
    
    local plotTag = ("%s-Plot"):format(LocalPlayer.Name)
    local plots = CollectionService:GetTagged(plotTag)
    
    if #plots == 0 then return end
    local plot = plots[1]
    
    for _, building in ipairs(plot:GetDescendants()) do
        if building:IsA("Model") or building:IsA("BasePart") then
            local resourcesToCollect = building:GetAttribute("ResourcesToCollect")
            
            if resourcesToCollect and resourcesToCollect > 0 then
                pcall(function()
                    GetBridge("CollectResources"):Fire(building)
                end)
                task.wait(CONFIG.COLLECT_DELAY)
            end
        end
    end
end

-- === AUTO-CAPTURE FUNCTION ===
local lastCaptureTick = 0

autoCapture = function()
    local sentTroops = false
    
    -- Raid Bases
    local raidSettings = CONFIG.CAPTURE_SETTINGS["KingOfTheHill"]
    if raidSettings.Enabled then
        local raidBases = CollectionService:GetTagged("CapturePointKingOfTheHill")
        for _, base in ipairs(raidBases) do
            for _, armyStr in ipairs(raidSettings.Army) do
                local success = pcall(function()
                    GetBridge("SendTroopsToPoint"):Fire({
                        armyIndex = tonumber(armyStr),
                        capturePoint = base
                    })
                end)
                if success then
                    sentTroops = true
                    task.wait(0.5)
                end
            end
        end
    end
    
    -- Normal Bases
    local normalBases = CollectionService:GetTagged("CapturePoint")
    local basesByType = {}
    for _, base in ipairs(normalBases) do
        local bType = base:GetAttribute("baseType")
        if bType then
            if not basesByType[bType] then basesByType[bType] = {} end
            table.insert(basesByType[bType], base)
        end
    end
    
    for bType, bases in pairs(basesByType) do
        local settings = CONFIG.CAPTURE_SETTINGS[bType]
        if settings and settings.Enabled then
            table.sort(bases, function(a, b) return a.Name < b.Name end)
            
            local targetBase = nil
            if settings.TargetIndex == "Random" then
                targetBase = bases[math.random(1, #bases)]
            else
                local idx = tonumber(settings.TargetIndex) or 1
                targetBase = bases[idx] or bases[1]
            end
            
            if targetBase then
                for _, armyStr in ipairs(settings.Army) do
                    local success = pcall(function()
                        GetBridge("SendTroopsToPoint"):Fire({
                            armyIndex = tonumber(armyStr),
                            capturePoint = targetBase
                        })
                    end)
                    if success then
                        sentTroops = true
                        task.wait(0.5)
                    end
                end
            end
        end
    end
    
    if sentTroops then
        lastCaptureTick = tick()
    end
end

-- === AUTO SELL FUNCTION ===
local function autoSellAll()
    if not CONFIG.AUTO_SELL_ALL then return end
    pcall(function()
        GetBridge("SellAll"):Fire()
    end)
end

-- === MAIN LOOP ===
task.spawn(function()
    while _G.MiniWarRunning do
        pcall(function()
            autoBuy()
            task.wait(1)
            autoCollect()
            task.wait(0.5)
            autoSellAll()
            
            if (tick() - lastCaptureTick) >= CONFIG.CAPTURE_DELAY then
                autoCapture()
            end
        end)
        task.wait(CONFIG.LOOP_INTERVAL)
    end
end)
