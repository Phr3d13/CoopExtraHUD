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
    -- HUD boundary (screen clamp)
    boundaryX = 0,
    boundaryY = 0,
    boundaryW = 1920,
    boundaryH = 1080,
    -- User-defined minimap area to avoid
    minimapX = 1760, -- example default for 1920x1080 top-right
    minimapY = 0,
    minimapW = 160,
    minimapH = 160,
    minimapPadding = 2, -- user-configurable vertical padding below minimap
    -- Fallback: always show overlays in MCM
    alwaysShowOverlayInMCM = false,
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
        scale = 0.6,
        xSpacing = 8,
        ySpacing = 8,
        dividerOffset = -16,
        dividerYOffset = 0,
        xOffset = 32,
        yOffset = 32, -- Changed from -32 to 32 for visible top anchor
        opacity = 0.85,
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

-- Debug log table and function (must be defined before any usage)
local debugLogs = {}
local function AddDebugLog(msg)
    -- Suppress all debug logging to log.txt except for MCM function list (handled separately)
    table.insert(debugLogs, 1, msg)
    if #debugLogs > 5 then table.remove(debugLogs) end
    -- No Isaac.DebugString(msg) here
end

-- HUD cache and update functions (must be defined before any usage)
local cachedPlayerIconData = nil
local cachedPlayerCount = 0
local hudDirty = true

local function MarkHudDirty()
    hudDirty = true
end

local function UpdatePlayerIconData()
    local game = Game()
    local totalPlayers = game:GetNumPlayers()
    cachedPlayerIconData = {}
    for i = 0, totalPlayers - 1 do
        cachedPlayerIconData[i + 1] = {}
        local player = Isaac.GetPlayer(i)
        local ownedSet = {}
        for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
            if player:HasCollectible(id) then
                ownedSet[id] = true
            end
        end
        if playerPickupOrder[i] then
            for _, id in ipairs(playerPickupOrder[i]) do
                if ownedSet[id] then
                    table.insert(cachedPlayerIconData[i + 1], id)
                    ownedSet[id] = nil
                end
            end
        end
        for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
            if ownedSet[id] then
                table.insert(cachedPlayerIconData[i + 1], id)
            end
        end
    end
    cachedPlayerCount = totalPlayers
    hudDirty = false
end

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
    MarkHudDirty()
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
        MarkHudDirty()
    end
    lastPlayerCount = curCount
end)

-- Maintain true pickup order for each player
local function UpdatePickupOrderForAllPlayers()
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        playerPickupOrder[i] = playerPickupOrder[i] or {}
        local owned = {}
        -- Mark all currently owned collectibles
        for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
            if player:HasCollectible(id) then
                owned[id] = true
                -- If not already in order, add to end
                local found = false
                for _, v in ipairs(playerPickupOrder[i]) do
                    if v == id then found = true break end
                end
                if not found then
                    table.insert(playerPickupOrder[i], id)
                end
            end
        end
        -- Remove any collectibles from order that are no longer owned
        local j = 1
        while j <= #playerPickupOrder[i] do
            if not owned[playerPickupOrder[i][j]] then
                table.remove(playerPickupOrder[i], j)
            else
                j = j + 1
            end
        end
    end
end

-- On player effect update, update pickup order and mark HUD dirty
ExtraHUD:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, function(_, player)
    UpdatePickupOrderForAllPlayers()
    MarkHudDirty()
end)

-- On pickup, just mark HUD dirty (no need to update playerTrackedCollectibles/playerPickupOrder here)
ExtraHUD:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, function(_, pickup)
    if pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE then
        if pickup:GetSprite():IsFinished("Collect") or pickup:IsDead() then
            MarkHudDirty()
        end
    end
end)

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
    MarkHudDirty()
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

-- MiniMapAPI integration: get minimap bounding box if available
local function GetMiniMapiBounds()
    local mmapi = _G["MiniMapAPI"] or _G["MinimapAPI"] or _G["MiniMapAPICompat"]
    if not mmapi then return nil end
    if not mmapi.GetScreenTopRight or not mmapi.GetScreenSize then return nil end
    local pos = mmapi.GetScreenTopRight()
    local size = mmapi.GetScreenSize()
    if not pos or not size or not pos.X or not pos.Y or not size.X or not size.Y then
        return nil
    end
    return { x = pos.X, y = pos.Y, w = size.X, h = size.Y }
end

-- Extra debug: log all global keys containing 'mini'
local function LogMiniGlobals()
    local found = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:lower():find("mini") then
            table.insert(found, k .. " (" .. tostring(type(v)) .. ")")
        end
    end
    return table.concat(found, ", ")
end

-- Helper: get number of columns for a player's HUD block
local function getPlayerColumns(numItems)
    return COLUMNS
end

-- Only one set of HUD cache and update functions, defined here:
-- REMOVE any duplicate definitions of cachedPlayerIconData, cachedPlayerCount, hudDirty, MarkHudDirty, UpdatePlayerIconData below this point!

-- Patch: mark HUD dirty on all relevant events
local oldTrackAllCurrentCollectibles = TrackAllCurrentCollectibles
TrackAllCurrentCollectibles = function(...)
    oldTrackAllCurrentCollectibles(...)
    MarkHudDirty()
end

local oldPostUpdate = ExtraHUD["MC_POST_UPDATE_callback"]
ExtraHUD["MC_POST_UPDATE_callback"] = function(...)
    if oldPostUpdate then oldPostUpdate(...) end
    MarkHudDirty()
end

local oldPickupUpdate = ExtraHUD["MC_POST_PICKUP_UPDATE_callback"]
ExtraHUD["MC_POST_PICKUP_UPDATE_callback"] = function(...)
    if oldPickupUpdate then oldPickupUpdate(...) end
    MarkHudDirty()
end

-- Also mark HUD dirty on config changes
local oldUpdateCurrentPreset = UpdateCurrentPreset
UpdateCurrentPreset = function(...)
    oldUpdateCurrentPreset(...)
    MarkHudDirty()
end

-- Helper: log to log.txt
local function LogToFile(msg)
    Isaac.DebugString("[CoopExtraHUD] " .. msg)
end

local currentOverlayType = "boundary" -- "boundary" or "minimap"
local overlayTimer = 0 -- frames to show overlay after change

function ExtraHUD:PostRender()
    local game = Game()
    local screenW, screenH = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
    -- Defensive: ensure all config values are not nil before use
    config.boundaryX = config.boundaryX or 0
    config.boundaryY = config.boundaryY or 0
    config.boundaryW = config.boundaryW or screenW
    config.boundaryH = config.boundaryH or screenH
    config.minimapX = config.minimapX or 0
    config.minimapY = config.minimapY or 0
    config.minimapW = config.minimapW or 0
    config.minimapH = config.minimapH or 0
    config.minimapPadding = config.minimapPadding or 0
    config.xOffset = config.xOffset or 0
    config.yOffset = config.yOffset or 0
    config.scale = config.scale or 1
    config.opacity = config.opacity or 1
    config.xSpacing = config.xSpacing or 0
    config.ySpacing = config.ySpacing or 0
    config.dividerOffset = config.dividerOffset or 0
    config.dividerYOffset = config.dividerYOffset or 0
    -- Clamp boundary to screen size (allow full range)
    config.boundaryW = math.max(32, math.min(config.boundaryW, screenW))
    config.boundaryH = math.max(32, math.min(config.boundaryH, screenH))
    config.boundaryX = math.max(0, math.min(config.boundaryX, screenW - 1))
    config.boundaryY = math.max(0, math.min(config.boundaryY, screenH - 1))
    -- Clamp minimap area to screen
    config.minimapW = math.max(0, math.min(config.minimapW, screenW))
    config.minimapH = math.max(0, math.min(config.minimapH, screenH))
    config.minimapX = math.max(0, math.min(config.minimapX, screenW - 1))
    config.minimapY = math.max(0, math.min(config.minimapY, screenH - 1))
    local hudVisible = game:GetHUD():IsVisible()
    local isPaused = game:IsPaused()
    local yMapOffset = (not hudVisible and isPaused) and config.mapYOffset or 0
    -- Only update player icon data cache if dirty or player count changed
    local totalPlayers = game:GetNumPlayers()
    if hudDirty or not cachedPlayerIconData or cachedPlayerCount ~= totalPlayers then
        UpdatePlayerIconData()
    end
    local playerIconData = cachedPlayerIconData
    if not playerIconData then return end
    -- Layout calculations (always recalculate every frame for boundary clamp)
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
    local totalH = maxHeight * scale
    -- Improved boundary anchoring logic
    local startX, startY
    if config.hudMode then
        -- Vanilla+: anchor to top-right of boundary, plus offsets
        startX = config.boundaryX + config.boundaryW - totalW + config.xOffset
        startY = config.boundaryY + config.yOffset
    else
        -- Updated: center vertically in boundary, right-aligned
        startX = config.boundaryX + config.boundaryW - totalW + config.xOffset
        startY = config.boundaryY + ((config.boundaryH - totalH) / 2) + config.yOffset
    end
    -- Minimap avoidance: if HUD would overlap minimap area, move HUD below minimap (with padding)
    local minimapX = tonumber(config.minimapX) or 0
    local minimapY = tonumber(config.minimapY) or 0
    local minimapW = tonumber(config.minimapW) or 0
    local minimapH = tonumber(config.minimapH) or 0
    local minimapPadding = tonumber(config.minimapPadding) or 0
    if minimapW > 0 and minimapH > 0 then
        local hudLeft = startX
        local hudRight = startX + totalW
        local hudTop = startY
        local hudBottom = startY + totalH
        local miniLeft = minimapX
        local miniRight = minimapX + minimapW
        local miniTop = minimapY
        local miniBottom = minimapY + minimapH
        local overlap = not (hudRight < miniLeft or hudLeft > miniRight or hudBottom < miniTop or hudTop > miniBottom)
        if overlap then
            startY = miniBottom + minimapPadding
        end
    end
    -- Clamp to boundary (prevent going outside)
    if startX < config.boundaryX then startX = config.boundaryX end
    if startY < config.boundaryY then startY = config.boundaryY end
    if startX + totalW > config.boundaryX + config.boundaryW then
        startX = config.boundaryX + config.boundaryW - totalW
    end
    if startY + totalH > config.boundaryY + config.boundaryH then
        startY = config.boundaryY + config.boundaryH - totalH
    end
    -- Draw icons + dividers
    local curX = startX
    for i, items in ipairs(playerIconData) do
        local cols = playerColumns[i]
        local blockW = blockWs[i]
        local rows = math.ceil(#items / cols)
        for idx, itemId in ipairs(items) do
            local row = math.floor((idx - 1) / cols)
            local col = (idx - 1) % cols
            local x = curX + col * (ICON_SIZE + config.xSpacing) * scale
            local y = startY + row * (ICON_SIZE + config.ySpacing) * scale
            RenderItemIcon(itemId, x, y, scale, config.opacity)
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
    -- Debug overlay: only draw the HUD boundary border, no text or callback names
    if config.debugOverlay then
        -- Draw a lineart border for the HUD boundary for debug/adjustment (NO TEXT)
        local bx = tonumber(config.boundaryX) or 0
        local by = tonumber(config.boundaryY) or 0
        local bw = tonumber(config.boundaryW) or 0
        local bh = tonumber(config.boundaryH) or 0
        if bw > 0 and bh > 0 then
            for i=0,bw,32 do
                Isaac.RenderText("-", bx+i, by, 1, 1, 1, 1)
                Isaac.RenderText("-", bx+i, by+bh-8, 1, 1, 1, 1)
            end
            for j=0,bh,32 do
                Isaac.RenderText("|", bx, by+j, 1, 1, 1, 1)
                Isaac.RenderText("|", bx+bw-8, by+j, 1, 1, 1, 1)
            end
        end
    end
    -- Show overlays only when relevant MCM setting is being adjusted or hovered
    local mcm = _G['ModConfigMenu']
    local showBoundary = false
    local showMinimap = false
    local mcmIsVisible = false
    local inDisplaySection = false
    local mcmHideHud = false
    -- Overlay logic: manual toggles always force overlays, regardless of menu section
    if config.showBoundaryOverlayManual then
        showBoundary = true
    elseif config.showMinimapOverlayManual then
        showMinimap = true
    -- Fallback: always show overlays in MCM if enabled and MCM is loaded and visible (function or boolean)
    elseif config.alwaysShowOverlayInMCM and mcm and mcm.IsVisible and ((type(mcm.IsVisible) == "function" and mcm.IsVisible()) or (type(mcm.IsVisible) == "boolean" and mcm.IsVisible)) then
        if currentOverlayType == "boundary" then showBoundary = true end
        if currentOverlayType == "minimap" then showMinimap = true end
    elseif mcmIsVisible and not mcmHideHud and inDisplaySection then
        if currentOverlayType == "boundary" then showBoundary = true end
        if currentOverlayType == "minimap" then showMinimap = true end
    end
    -- Draw overlays as needed (text/lines only, sprite code removed)
    if showBoundary then
        local bx = tonumber(config.boundaryX) or 0
        local by = tonumber(config.boundaryY) or 0
        local bw = tonumber(config.boundaryW) or 0
        local bh = tonumber(config.boundaryH) or 0
        if bw > 0 and bh > 0 then
            Isaac.RenderText("[NO SPRITE]", bx+4, by+4, 1, 0, 0, 1)
            for i=0,bw,32 do
                Isaac.RenderText("-", bx+i, by, 1, 0, 0, 1)
                Isaac.RenderText("-", bx+i, by+bh-8, 1, 0, 0, 1)
            end
            for j=0,bh,32 do
                Isaac.RenderText("|", bx, by+j, 1, 0, 0, 1)
                Isaac.RenderText("|", bx+bw-8, by+j, 1, 0, 0, 1)
            end
        else
            AddDebugLog("[Overlay] showBoundary: boundary config value(s) nil or zero, skipping overlay")
        end
    elseif showMinimap then
        local mx = tonumber(config.minimapX) or 0
        local my = tonumber(config.minimapY) or 0
        local mw = tonumber(config.minimapW) or 0
        local mh = tonumber(config.minimapH) or 0
        if mw > 0 and mh > 0 then
            Isaac.RenderText("[NO SPRITE]", mx+4, my+4, 1, 0, 0, 1)
            for i=0,mw,32 do
                Isaac.RenderText("-", mx+i, my, 1, 0, 0, 1)
                Isaac.RenderText("-", mx+i, my+mh-8, 1, 0, 0, 1)
            end
            for j=0,mh,32 do
                Isaac.RenderText("|", mx, my+j, 1, 0, 0, 1)
                Isaac.RenderText("|", mx+mw-8, my+j, 1, 0, 0, 1)
            end
        else
            AddDebugLog("[Overlay] showMinimap: minimap config value(s) nil or zero, skipping overlay")
        end
    end
    AddDebugLog("Rendered HUD; mapVisible=" .. tostring(hudVisible))
end

ExtraHUD:AddCallback(ModCallbacks.MC_POST_RENDER, ExtraHUD.PostRender)

local configMenuRegistered = false
local mcmActiveSetting = nil -- Track which MCM setting is active for overlay

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
                    [true]  = { scale = 0.6, xSpacing = 8, ySpacing = 8, dividerOffset = -16, dividerYOffset = 0, xOffset = 32, yOffset = 32, opacity = 0.85 }
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

    -- Display Category (renamed from Display Options)
    local addNum = function(name, cur, disp, min, max, step, onchg)
        ModConfigMenu.AddSetting(MOD, "Display", {
            Type = ModConfigMenu.OptionType.NUMBER,
            CurrentSetting = cur, Display = disp, OnChange = onchg,
            Minimum = min, Maximum = max, Step = step,
        })
    end

    ModConfigMenu.AddSpace(MOD, "Display")
    ModConfigMenu.AddTitle(MOD, "Display", "Display")

    -- Scale and Opacity at the top
    addNum("scale", function() return math.floor(config.scale * 100) end,
        function() return "HUD Scale: " .. math.floor(config.scale * 100) .. "%" end,
        20, 100, 5, function(v) config.scale = v / 100; UpdateCurrentPreset(); SaveConfig() end)
    addNum("opacity", function() return math.floor(config.opacity * 100) end,
        function() return "HUD Opacity: " .. math.floor(config.opacity * 100) .. "%" end,
        0, 100, 5, function(v) config.opacity = v / 100; UpdateCurrentPreset(); SaveConfig() end)

    -- Spacing section
    ModConfigMenu.AddTitle(MOD, "Display", "Spacing")
    addNum("xSpacing", function() return config.xSpacing end,
        function() return "X Spacing: " .. config.xSpacing end,
        0, 50, 1, function(v) config.xSpacing = v; UpdateCurrentPreset(); SaveConfig() end)
    addNum("ySpacing", function() return config.ySpacing end,
        function() return "Y Spacing: " .. config.ySpacing end,
        0, 50, 1, function(v) config.ySpacing = v; UpdateCurrentPreset(); SaveConfig() end)

    -- Divider section
    ModConfigMenu.AddTitle(MOD, "Display", "Divider")
    addNum("dividerOffset", function() return config.dividerOffset end,
        function() return "Divider X Offset: " .. config.dividerOffset end,
        -200, 200, 5, function(v) config.dividerOffset = v; UpdateCurrentPreset(); SaveConfig() end)
    addNum("dividerYOffset", function() return config.dividerYOffset end,
        function() return "Divider Y Offset: " .. config.dividerYOffset end,
        -200, 200, 5, function(v) config.dividerYOffset = v; UpdateCurrentPreset(); SaveConfig() end)

    -- Offset section
    ModConfigMenu.AddTitle(MOD, "Display", "Offset")
    addNum("xOffset", function() return config.xOffset end,
        function() return "HUD X Offset: " .. config.xOffset end,
        -200, 200, 5, function(v) config.xOffset = v; UpdateCurrentPreset(); SaveConfig() end)
    addNum("yOffset", function() return config.yOffset end,
        function() return "HUD Y Offset: " .. config.yOffset end,
        -200, 200, 5, function(v) config.yOffset = v; UpdateCurrentPreset(); SaveConfig() end)

    -- HUD Boundary section
    ModConfigMenu.AddSpace(MOD, "Display")
    ModConfigMenu.AddTitle(MOD, "Display", "HUD Boundary")
    -- Fallback overlay option for users with MCM callback issues
    ModConfigMenu.AddSetting(MOD, "Display", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return config.alwaysShowOverlayInMCM or false end,
        Display = function() return "Always Show Overlays in MCM (Fallback): " .. ((config.alwaysShowOverlayInMCM and "On") or "Off") end,
        OnChange = function(v) config.alwaysShowOverlayInMCM = v; SaveConfig() end,
    })
    ModConfigMenu.AddSetting(MOD, "Display", {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return config.boundaryX end,
        Display = function() return "Boundary X: " .. config.boundaryX end,
        OnChange = function(v)
            config.boundaryX = v; UpdateCurrentPreset(); SaveConfig();
            currentOverlayType = "boundary"
        end,
        Minimum = 0, Maximum = 3840, Step = 1,
        OnUpdate = function()
            AddDebugLog("[MCM] OnUpdate: boundaryX (setting mcmActiveSetting = 'boundary')")
            mcmActiveSetting = "boundary"
        end,
        OnLeave = function()
            AddDebugLog("[MCM] OnLeave: boundaryX (clearing mcmActiveSetting if 'boundary')")
            if mcmActiveSetting == "boundary" then mcmActiveSetting = nil end
        end,
    })
    ModConfigMenu.AddSetting(MOD, "Display", {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return config.boundaryY end,
        Display = function() return "Boundary Y: " .. config.boundaryY end,
        OnChange = function(v)
            config.boundaryY = v; UpdateCurrentPreset(); SaveConfig();
            currentOverlayType = "boundary"
        end,
        Minimum = 0, Maximum = 2160, Step = 1,
        OnUpdate = function()
            AddDebugLog("[MCM] OnUpdate: boundaryY (setting mcmActiveSetting = 'boundary')")
            mcmActiveSetting = "boundary"
        end,
        OnLeave = function()
            AddDebugLog("[MCM] OnLeave: boundaryY (clearing mcmActiveSetting if 'boundary')")
            if mcmActiveSetting == "boundary" then mcmActiveSetting = nil end
        end,
    })
    ModConfigMenu.AddSetting(MOD, "Display", {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return config.boundaryW end,
        Display = function() return "Boundary Width: " .. config.boundaryW end,
        OnChange = function(v)
            config.boundaryW = v; UpdateCurrentPreset(); SaveConfig();
            currentOverlayType = "boundary"
        end,
        Minimum = 32, Maximum = 3840, Step = 1,
        OnUpdate = function()
            AddDebugLog("[MCM] OnUpdate: boundaryW (setting mcmActiveSetting = 'boundary')")
            mcmActiveSetting = "boundary"
        end,
        OnLeave = function()
            AddDebugLog("[MCM] OnLeave: boundaryW (clearing mcmActiveSetting if 'boundary')")
            if mcmActiveSetting == "boundary" then mcmActiveSetting = nil end
        end,
    })
    ModConfigMenu.AddSetting(MOD, "Display", {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return config.boundaryH end,
        Display = function() return "Boundary Height: " .. config.boundaryH end,
        OnChange = function(v)
            config.boundaryH = v; UpdateCurrentPreset(); SaveConfig();
            currentOverlayType = "boundary"
        end,
        Minimum = 32, Maximum = 2160, Step = 1,
        OnUpdate = function()
            AddDebugLog("[MCM] OnUpdate: boundaryH (setting mcmActiveSetting = 'boundary')")
            mcmActiveSetting = "boundary"
        end,
        OnLeave = function()
            AddDebugLog("[MCM] OnLeave: boundaryH (clearing mcmActiveSetting if 'boundary')")
            if mcmActiveSetting == "boundary" then mcmActiveSetting = nil end
        end,
    })
    -- Minimap Avoidance section
    ModConfigMenu.AddSpace(MOD, "Display")
    ModConfigMenu.AddTitle(MOD, "Display", "Minimap Avoidance Area")
    -- Add auto-align as a button-like toggle (like resetFlag)
    local minimapAutoAlignFlag = false
    ModConfigMenu.AddSetting(MOD, "Display", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return minimapAutoAlignFlag end,
        Display = function() return "Auto-Align Minimap (Top-Right)" end,
        OnChange = function(v)
            if v then
                config.minimapX = -1
                config.minimapY = -1
                UpdateCurrentPreset()
                SaveConfig()
                minimapAutoAlignFlag = false -- immediately reset toggle
            end
        end,
    })
    ModConfigMenu.AddSetting(MOD, "Display", {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return config.minimapX end,
        Display = function() return "Minimap X: " .. config.minimapX end,
        OnChange = function(v)
            config.minimapX = v; UpdateCurrentPreset(); SaveConfig();
            currentOverlayType = "minimap"
        end,
        Minimum = 0, Maximum = 3840, Step = 1,
        OnUpdate = function()
            AddDebugLog("[MCM] OnUpdate: minimapX (setting mcmActiveSetting = 'minimap')")
            mcmActiveSetting = "minimap"
        end,
        OnLeave = function()
            AddDebugLog("[MCM] OnLeave: minimapX (clearing mcmActiveSetting if 'minimap')")
            if mcmActiveSetting == "minimap" then mcmActiveSetting = nil end
        end,
    })
    ModConfigMenu.AddSetting(MOD, "Display", {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return config.minimapY end,
        Display = function() return "Minimap Y: " .. config.minimapY end,
        OnChange = function(v)
            config.minimapY = v; UpdateCurrentPreset(); SaveConfig();
            currentOverlayType = "minimap"
        end,
        Minimum = 0, Maximum = 2160, Step = 1,
        OnUpdate = function()
            AddDebugLog("[MCM] OnUpdate: minimapY (setting mcmActiveSetting = 'minimap')")
            mcmActiveSetting = "minimap"
        end,
        OnLeave = function()
            AddDebugLog("[MCM] OnLeave: minimapY (clearing mcmActiveSetting if 'minimap')")
            if mcmActiveSetting == "minimap" then mcmActiveSetting = nil end
        end,
    })
    ModConfigMenu.AddSetting(MOD, "Display", {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return config.minimapW end,
        Display = function() return "Minimap Width: " .. config.minimapW end,
        OnChange = function(v)
            config.minimapW = v; UpdateCurrentPreset(); SaveConfig();
            currentOverlayType = "minimap"
        end,
        Minimum = 0, Maximum = 3840, Step = 1,
        OnUpdate = function()
            AddDebugLog("[MCM] OnUpdate: minimapW (setting mcmActiveSetting = 'minimap')")
            mcmActiveSetting = "minimap"
        end,
        OnLeave = function()
            AddDebugLog("[MCM] OnLeave: minimapW (clearing mcmActiveSetting if 'minimap')")
            if mcmActiveSetting == "minimap" then mcmActiveSetting = nil end
        end,
    })
    ModConfigMenu.AddSetting(MOD, "Display", {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return config.minimapH end,
        Display = function() return "Minimap Height: " .. config.minimapH end,
        OnChange = function(v)
            config.minimapH = v; UpdateCurrentPreset(); SaveConfig();
            currentOverlayType = "minimap"
        end,
        Minimum = 0, Maximum = 2160, Step = 1,
        OnUpdate = function()
            AddDebugLog("[MCM] OnUpdate: minimapH (setting mcmActiveSetting = 'minimap')")
            mcmActiveSetting = "minimap"
        end,
        OnLeave = function()
            AddDebugLog("[MCM] OnLeave: minimapH (clearing mcmActiveSetting if 'minimap')")
            if mcmActiveSetting == "minimap" then mcmActiveSetting = nil end
        end,
    })
    -- Debug Category (renamed from Debugging)
    ModConfigMenu.AddSpace(MOD, "Debug")
    ModConfigMenu.AddTitle(MOD, "Debug", "Debug")
    ModConfigMenu.AddSetting(MOD, "Debug", {
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

print("[CoopExtraHUD] Fully loaded with HUD mode support and configurable spacing and boundary!")
