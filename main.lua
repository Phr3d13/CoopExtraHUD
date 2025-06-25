local ExtraHUD = RegisterMod("CoopExtraHUD", 1)

-- Default config values
local config = {
    scale = 0.5,
    xSpacing = 6,
    ySpacing = 6,
    dividerOffset = -10,
    dividerYOffset = 0,
    xOffset = 20,
    yOffset = -25,
    opacity = 0.6,
    debugOverlay = false,
    mapYOffset = 100,
    hudMode = true, -- false = "Updated", true = "Vanilla+"
}

-- Preset configurations keyed by boolean hudMode
local configPresets = {
    [false] = { -- Updated
        scale = 0.4,
        xSpacing = 5,
        ySpacing = 5,
        dividerOffset = -20,
        dividerYOffset = 0,
        xOffset = 10,
        yOffset = -10,
        opacity = 0.8,
    },
    [true] = { -- Vanilla+
        scale = 0.5,
        xSpacing = 6,
        ySpacing = 6,
        dividerOffset = -10,
        dividerYOffset = 0,
        xOffset = 20,
        yOffset = -25,
        opacity = 0.6,
    }
}

local ICON_SIZE = 32
local COLUMNS = 2
local INTER_PLAYER_SPACING = 12

-- Sprite cache for item icons
local itemSpriteCache = {}

-- Helper to get or create a cached sprite for a collectible
local function GetItemSprite(itemId, gfxFile)
    if not itemSpriteCache[itemId] then
        local spr = Sprite()
        spr:Load("gfx/005.100_collectible.anm2", true)
        spr:ReplaceSpritesheet(1, gfxFile)
        spr:LoadGraphics()
        spr:Play("Idle", true)
        spr:SetFrame(0)
        itemSpriteCache[itemId] = spr
    end
    return itemSpriteCache[itemId]
end

-- Cached sprite for collectibles
local itemSprite = Sprite()
itemSprite:Load("gfx/005.100_collectible.anm2", true)

-- Simple direct tracking of player collectibles
local playerTrackedCollectibles = {}
-- New: Track pickup order per player
local playerPickupOrder = {}

-- Helper: record all current collectibles for all players (e.g. at game start or new player join)
local function TrackAllCurrentCollectibles()
    for i = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        playerTrackedCollectibles[i] = {}
        playerPickupOrder[i] = {}
        for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
            if player:HasCollectible(id) then
                playerTrackedCollectibles[i][id] = true
                table.insert(playerPickupOrder[i], id)
            end
        end
    end
end

-- On game start, track all current collectibles and pickup order
ExtraHUD:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, _)
    TrackAllCurrentCollectibles()
end)

-- On new player join, track their current collectibles and pickup order
local lastPlayerCount = 0
ExtraHUD:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    local curCount = Game():GetNumPlayers()
    if curCount > lastPlayerCount then
        for i = lastPlayerCount, curCount - 1 do
            local player = Isaac.GetPlayer(i)
            playerTrackedCollectibles[i] = {}
            playerPickupOrder[i] = {}
            for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
                if player:HasCollectible(id) then
                    playerTrackedCollectibles[i][id] = true
                    table.insert(playerPickupOrder[i], id)
                end
            end
        end
    end
    lastPlayerCount = curCount
end)

-- On pickup, add to tracked list and pickup order for the closest player
ExtraHUD:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, function(_, pickup)
    if pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE then
        if pickup:GetSprite():IsFinished("Collect") or pickup:IsDead() then
            local closestPlayer, minDist = nil, math.huge
            for i = 0, Game():GetNumPlayers() - 1 do
                local player = Isaac.GetPlayer(i)
                local dist = player.Position:Distance(pickup.Position)
                if dist < minDist then
                    minDist = dist
                    closestPlayer = i
                end
            end
            if closestPlayer ~= nil then
                local id = pickup.SubType
                playerTrackedCollectibles[closestPlayer] = playerTrackedCollectibles[closestPlayer] or {}
                playerPickupOrder[closestPlayer] = playerPickupOrder[closestPlayer] or {}
                playerTrackedCollectibles[closestPlayer][id] = true
                -- Only add to pickup order if not already present
                local already = false
                for _, v in ipairs(playerPickupOrder[closestPlayer]) do
                    if v == id then already = true break end
                end
                if not already then
                    table.insert(playerPickupOrder[closestPlayer], id)
                end
            end
        end
    end
end)

local debugLogs = {}
local function AddDebugLog(msg)
    table.insert(debugLogs, 1, msg)
    if #debugLogs > 5 then table.remove(debugLogs) end
end

-- Config serialization
local function SerializeConfig(tbl)
    local str = ""
    for k, v in pairs(tbl) do
        str = str .. k .. "=" .. tostring(v) .. ";"
    end
    return str
end

local function DeserializeConfig(data)
    local tbl = {}
    for k, v in string.gmatch(data, "([%w_]+)=([^;]+);") do
        if v == "true" then tbl[k] = true
        elseif v == "false" then tbl[k] = false
        else local num = tonumber(v); if num then tbl[k] = num else tbl[k] = v end
        end
    end
    return tbl
end

-- Helper to serialize/deserialize both config and presets
local function SerializeAllConfigs()
    local str = "[config]" .. SerializeConfig(config) .. "[preset_false]" .. SerializeConfig(configPresets[false]) .. "[preset_true]" .. SerializeConfig(configPresets[true])
    return str
end

local function DeserializeAllConfigs(data)
    local function extractSection(tag)
        return data:match("%["..tag.."%](.-)%["), data:match("%["..tag.."%](.-)%["..(tag=="preset_true" and "$" or ""))
    end
    local configStr = data:match("%[config%](.-)%[preset_false%]") or ""
    local presetFalseStr = data:match("%[preset_false%](.-)%[preset_true%]") or ""
    local presetTrueStr = data:match("%[preset_true%](.*)$") or ""
    return {
        config = DeserializeConfig(configStr),
        preset_false = DeserializeConfig(presetFalseStr),
        preset_true = DeserializeConfig(presetTrueStr)
    }
end

local function SaveConfig()
    ExtraHUD:SaveData(SerializeAllConfigs())
    AddDebugLog("[Config] Saved (with presets)")
end

local function LoadConfig()
    if ExtraHUD:HasData() then
        local all = DeserializeAllConfigs(ExtraHUD:LoadData())
        for k, v in pairs(all.config) do if config[k] ~= nil then config[k] = v end end
        for k, v in pairs(all.preset_false) do if configPresets[false][k] ~= nil then configPresets[false][k] = v end end
        for k, v in pairs(all.preset_true) do if configPresets[true][k] ~= nil then configPresets[true][k] = v end end
        AddDebugLog("[Config] Loaded (with presets)")
    else
        AddDebugLog("[Config] Default used")
    end
end

-- When a setting is changed, update the current preset as well
local function UpdateCurrentPreset()
    local preset = configPresets[config.hudMode]
    for k, v in pairs(config) do
        if preset[k] ~= nil then preset[k] = v end
    end
end

-- Render a single item icon (now uses cache)
local function RenderItemIcon(itemId, x, y, scale, opa)
    local ci = Isaac.GetItemConfig():GetCollectible(itemId)
    if not ci then return end
    local spr = GetItemSprite(itemId, ci.GfxFileName)
    spr.Scale = Vector(scale, scale)
    spr.Color = Color(1, 1, 1, opa)
    spr:Render(Vector(x, y), Vector.Zero, Vector.Zero)
end

local function DrawRect(x, y, w, h, col)
    Isaac.RenderScaledLine(Vector(x, y), Vector(x + w, y), col, 1)
    Isaac.RenderScaledLine(Vector(x, y + h), Vector(x + w, y + h), col, 1)
    Isaac.RenderScaledLine(Vector(x, y), Vector(x, y + h), col, 1)
    Isaac.RenderScaledLine(Vector(x + w, y), Vector(x + w, y + h), col, 1)
end

-- MiniMapi integration: get minimap bounding box if available
local function GetMiniMapiBounds()
    if not MiniMapAPI or not MiniMapAPI:GetCurrentMinimap() then return nil end
    local mm = MiniMapAPI:GetCurrentMinimap()
    -- Get minimap position and size (top-right corner)
    local pos = mm.Position or Vector(Isaac.GetScreenWidth() - 120, 20)
    local size = mm.Size or Vector(120, 120)
    -- Some versions use mm:GetScreenTopRight() or similar, fallback if needed
    if mm.GetScreenTopRight then
        pos = mm:GetScreenTopRight()
    end
    return { x = pos.X, y = pos.Y, w = size.X, h = size.Y }
end

-- Helper: get number of columns for a player's HUD block
local function getPlayerColumns(numItems)
    return COLUMNS
end

function ExtraHUD:PostRender()
    local game = Game()
    local screenW, screenH = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()

    if not game:GetRoom():IsClear() and game:GetLevel():GetStage() == LevelStage.STAGE4 then return end
    if config.scale <= 0 or config.opacity <= 0 then return end

    -- Detect if HUD is hidden (map open)
    local hudVisible = game:GetHUD():IsVisible()
    local yMapOffset = hudVisible and 0 or config.mapYOffset

    -- MiniMapi: get minimap bounds and adjust HUD X offset if needed
    local minimapBounds = GetMiniMapiBounds()
    local minimapPad = 10 -- extra padding from minimap

    -- Gather player data (from cache)
    local totalPlayers = game:GetNumPlayers()
    if totalPlayers == 0 then return end

    local playerIconData = {}
    local playerUntrackedData = {}
    for i = 0, totalPlayers - 1 do
        playerIconData[i + 1] = {}
        playerUntrackedData[i + 1] = {}
        local player = Isaac.GetPlayer(i)
        -- Build a set of owned collectibles
        local ownedSet = {}
        for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
            if player:HasCollectible(id) then
                ownedSet[id] = true
            end
        end
        -- Add items in pickup order first
        if playerPickupOrder[i] then
            for _, id in ipairs(playerPickupOrder[i]) do
                if ownedSet[id] then
                    table.insert(playerIconData[i + 1], id)
                    playerUntrackedData[i + 1][#playerIconData[i + 1]] = not playerTrackedCollectibles[i][id]
                    ownedSet[id] = nil
                end
            end
        end
        -- Add any remaining owned items (not in pickup order)
        for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
            if ownedSet[id] then
                table.insert(playerIconData[i + 1], id)
                playerUntrackedData[i + 1][#playerIconData[i + 1]] = not playerTrackedCollectibles[i][id]
            end
        end
    end

    -- Layout calculations
    local maxRows = 1
    local playerColumns = {}
    for i, items in ipairs(playerIconData) do
        local cols = getPlayerColumns(#items)
        playerColumns[i] = cols
        maxRows = math.max(maxRows, math.ceil(#items / cols))
    end

    local rawScale = config.scale
    local maxHeight = maxRows * (ICON_SIZE + config.ySpacing) - config.ySpacing
    local scale = rawScale
    if not config.hudMode then
        scale = math.min(rawScale, (screenH * 0.8) / maxHeight)
    end

    -- Calculate block width per player
    local blockWs = {}
    for i, items in ipairs(playerIconData) do
        local cols = playerColumns[i]
        blockWs[i] = (ICON_SIZE * cols * scale) + ((cols - 1) * config.xSpacing * scale)
    end
    local totalW = 0
    for i = 1, #blockWs do
        totalW = totalW + blockWs[i]
    end
    totalW = totalW + (#blockWs - 1) * INTER_PLAYER_SPACING * scale

    local startX = screenW - totalW - 10 + config.xOffset
    local totalH = maxHeight * scale
    local startY = (screenH - totalH) / 2 + config.yOffset + yMapOffset

    -- If minimap is present and would overlap, move HUD left
    if minimapBounds then
        local overlap = (startX + totalW) > (minimapBounds.x - minimapPad)
        if overlap then
            startX = minimapBounds.x - totalW - minimapPad
        end
    end

    -- Draw icons + dividers
    local curX = startX
    for i, items in ipairs(playerIconData) do
        local cols = playerColumns[i]
        local blockW = blockWs[i]
        local rows = math.ceil(#items / cols)
        for idx, itemId in ipairs(items) do
            -- Column-major order: fill left-to-right, then top-to-bottom (per player)
            local row = math.floor((idx - 1) / cols)
            local col = (idx - 1) % cols
            local x = curX + col * (ICON_SIZE + config.xSpacing) * scale
            local y = startY + row * (ICON_SIZE + config.ySpacing) * scale
            RenderItemIcon(itemId, x, y, scale, config.opacity)
            if playerUntrackedData[i][idx] and config.debugOverlay then
                Isaac.RenderScaledText("U", x + 2, y + 2, scale, scale, 1, 0, 0, 1)
            end
        end
        if i < #playerIconData then
            local dividerX = curX + blockW + (INTER_PLAYER_SPACING * scale) / 2 + config.dividerOffset
            local lineChar = "|"
            local dividerStep = ICON_SIZE * 0.375 * scale
            local lines = math.floor(totalH / dividerStep)
            for l = 0, lines do
                Isaac.RenderScaledText(lineChar, dividerX, startY + config.dividerYOffset + l * dividerStep, scale, scale, 1, 1, 1, config.opacity)
            end
        end
        curX = curX + blockW + INTER_PLAYER_SPACING * scale
    end

    -- Debug overlay
    if config.debugOverlay then
        Isaac.RenderText("[DEBUG overlay]", 10, 10, 1, 1, 1, 1)
        Isaac.RenderText("yMapOffset = " .. tostring(yMapOffset), 10, 25, 1, 1, 1, 1)
        for i, msg in ipairs(debugLogs) do
            Isaac.RenderText("[LOG] " .. msg, 10, 40 + i * 15, 1, 1, 1, 1)
        end
        DrawRect(startX, startY, totalW, totalH, Color(0, 1, 0, 0.5))
    end

    AddDebugLog("Rendered HUD; mapVisible=" .. tostring(hudVisible))
end

ExtraHUD:AddCallback(ModCallbacks.MC_POST_RENDER, ExtraHUD.PostRender)

local configMenuRegistered = false

local function RegisterConfigMenu()
    if configMenuRegistered then return end  -- Prevent duplicate registration
    configMenuRegistered = true

    if not ModConfigMenu then
        print("[CoopExtraHUD] MCM not found; skipping menu")
        return
    end

    local MOD = "CoopExtraHUD"

    -- Presets Category
    ModConfigMenu.AddSpace(MOD, "Presets")
    ModConfigMenu.AddTitle(MOD, "Presets", "Preset Options")

    ModConfigMenu.AddSetting(MOD, "Presets", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return config.hudMode end,
        Display = function() return "HUD Mode: " .. (config.hudMode and "Vanilla+" or "Updated") end,
        OnChange = function(v)
            config.hudMode = v
            -- Apply preset values when toggled
            local preset = configPresets[v]
            if preset then
                for k, val in pairs(preset) do
                    config[k] = val
                end
            end
            SaveConfig()
        end,
    })

    -- Add reset to defaults option as a boolean toggle (workaround for no BUTTON type)
    local resetFlag = false
    ModConfigMenu.AddSetting(MOD, "Presets", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return resetFlag end,
        Display = function() return "Reset Current Preset to Defaults" end,
        OnChange = function(v)
            if v then
                local defaults = {
                    [false] = { scale = 0.4, xSpacing = 5, ySpacing = 5, dividerOffset = -20, dividerYOffset = 0, xOffset = 10, yOffset = -10, opacity = 0.8 },
                    [true]  = { scale = 0.5, xSpacing = 6, ySpacing = 6, dividerOffset = -10, dividerYOffset = 0, xOffset = 20, yOffset = -25, opacity = 0.6 }
                }
                local mode = config.hudMode
                for k, v in pairs(defaults[mode]) do
                    configPresets[mode][k] = v
                    config[k] = v
                end
                UpdateCurrentPreset()
                SaveConfig()
                resetFlag = false -- immediately reset toggle
            end
        end,
    })

    -- General Category
    local addNum = function(name, cur, disp, min, max, step, onchg)
        ModConfigMenu.AddSetting(MOD, "General", {
            Type = ModConfigMenu.OptionType.NUMBER,
            CurrentSetting = cur, Display = disp, OnChange = onchg,
            Minimum = min, Maximum = max, Step = step,
        })
    end

    ModConfigMenu.AddSpace(MOD, "General")
    ModConfigMenu.AddTitle(MOD, "General", "Display Options")

    addNum("scale", function() return math.floor(config.scale * 100) end,
        function() return "HUD Scale: " .. math.floor(config.scale * 100) .. "%" end,
        20, 100, 5, function(v) config.scale = v / 100; UpdateCurrentPreset(); SaveConfig() end)

    addNum("xSpacing", function() return config.xSpacing end,
        function() return "X Spacing: " .. config.xSpacing end,
        0, 50, 1, function(v) config.xSpacing = v; UpdateCurrentPreset(); SaveConfig() end)

    addNum("ySpacing", function() return config.ySpacing end,
        function() return "Y Spacing: " .. config.ySpacing end,
        0, 50, 1, function(v) config.ySpacing = v; UpdateCurrentPreset(); SaveConfig() end)

    addNum("dividerOffset", function() return config.dividerOffset end,
        function() return "Divider X Offset: " .. config.dividerOffset end,
        -200, 200, 5, function(v) config.dividerOffset = v; UpdateCurrentPreset(); SaveConfig() end)

    addNum("dividerYOffset", function() return config.dividerYOffset end,
        function() return "Divider Y Offset: " .. config.dividerYOffset end,
        -200, 200, 5, function(v) config.dividerYOffset = v; UpdateCurrentPreset(); SaveConfig() end)

    addNum("xOffset", function() return config.xOffset end,
        function() return "HUD X Offset: " .. config.xOffset end,
        -200, 200, 5, function(v) config.xOffset = v; UpdateCurrentPreset(); SaveConfig() end)

    addNum("yOffset", function() return config.yOffset end,
        function() return "HUD Y Offset: " .. config.yOffset end,
        -200, 200, 5, function(v) config.yOffset = v; UpdateCurrentPreset(); SaveConfig() end)

    addNum("opacity", function() return math.floor(config.opacity * 100) end,
        function() return "HUD Opacity: " .. math.floor(config.opacity * 100) .. "%" end,
        0, 100, 5, function(v) config.opacity = v / 100; UpdateCurrentPreset(); SaveConfig() end)

    ModConfigMenu.AddSetting(MOD, "General", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return config.debugOverlay end,
        Display = function() return "Debug Overlay: " .. (config.debugOverlay and "On" or "Off") end,
        OnChange = function(v) config.debugOverlay = v; UpdateCurrentPreset(); SaveConfig() end,
    })

    print("[CoopExtraHUD] Config menu registered.")
end

ExtraHUD:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, _)
    LoadConfig()
    RegisterConfigMenu()
end)

ExtraHUD:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
    SaveConfig()
end)

-- Debug print flag
local DEBUG_PRINT = config.debugOverlay

-- Replace print statements with debug flag
local function DebugPrint(msg)
    if DEBUG_PRINT then print(msg) end
end

print("[CoopExtraHUD] Fully loaded with HUD mode support and configurable spacing!")
