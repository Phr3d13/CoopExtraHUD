local ExtraHUD = RegisterMod("CoopExtraHUD", 1)

-- Default config values
local config = nil -- will be set by MCM.Init

-- Temporary default config for early access (before MCM.Init)
local defaultConfig = {
    scale = 0.4, -- updated default
    xSpacing = 5, -- updated default
    ySpacing = 5, -- updated default
    dividerOffset = -7, -- updated default
    dividerYOffset = -14, -- updated default
    xOffset = 0, -- updated default
    yOffset = 0, -- updated default
    opacity = 0.6, -- updated default
    mapYOffset = 100,
    hudMode = true,
    boundaryX = 215, -- updated default
    boundaryY = 49, -- updated default
    boundaryW = 270, -- updated default
    boundaryH = 184, -- updated default
    minimapX = 344, -- updated default
    minimapY = 0, -- updated default
    minimapW = 141, -- updated default
    minimapH = 101, -- updated default
    minimapPadding = 2,
    alwaysShowOverlayInMCM = false,
    debugOverlay = false,
    _mcm_map_overlay_refresh = 244,
    _mcm_boundary_overlay_refresh = 574,
}

-- Helper to get config safely before MCM.Init
local function getConfig()
    return config or defaultConfig
end

-- Preset configurations keyed by boolean hudMode
local configPresets = nil -- will be set by MCM.Init

local defaultConfigPresets = {}
defaultConfigPresets[false] = { -- Updated
    xSpacing = 5,
    dividerOffset = -20,
    opacity = 0.8,
    ySpacing = 5,
    dividerYOffset = 0,
    scale = 0.4,
    yOffset = -10,
    xOffset = 10,
}
defaultConfigPresets[true] = { -- Vanilla+
    xSpacing = 8,
    dividerOffset = -16,
    opacity = 0.85,
    ySpacing = 8,
    dividerYOffset = 0,
    scale = 0.6,
    yOffset = 32,
    xOffset = 32,
}

local ICON_SIZE = 32
local INTER_PLAYER_SPACING = 12

-- Configuration for modded item support
local MAX_ITEM_ID = 4000 -- Scan up to item ID 4000 to catch most modded items
local VANILLA_ITEM_LIMIT = CollectibleType.NUM_COLLECTIBLES - 1

-- Helper function to check if an item exists and is valid
local function IsValidItem(itemId)
    local itemConfig = Isaac.GetItemConfig():GetCollectible(itemId)
    return itemConfig ~= nil and itemConfig.GfxFileName ~= nil and itemConfig.GfxFileName ~= ""
end

-- Debug log table and function (must be defined before any usage)
local debugLogs = {}
local function AddDebugLog(msg)
    -- Suppress all debug logging to log.txt except for MCM function list (handled separately)
    table.insert(debugLogs, 1, msg)
    if #debugLogs > 5 then table.remove(debugLogs) end
    -- No Isaac.DebugString(msg) here
end

-- Sprite cache for item icons with cleanup tracking
local itemSpriteCache = {}
local spriteUsageTracker = {} -- Track which sprites are currently in use

-- Helper to get or create a cached sprite for a collectible (with modded item support)
local function GetItemSprite(itemId, gfxFile)
    if not itemSpriteCache[itemId] then
        local spr = Sprite()
        -- Try to load the sprite, with error handling for modded items
        local success = pcall(function()
            spr:Load("gfx/005.100_collectible.anm2", true)
            spr:ReplaceSpritesheet(1, gfxFile)
            spr:LoadGraphics()
            spr:Play("Idle", true)
            spr:SetFrame(0)
        end)
        
        if not success then
            -- If loading fails (e.g., missing modded item graphics), create a fallback
            AddDebugLog("[Sprite] Failed to load graphics for item " .. itemId .. ", using fallback")
            -- You could return nil here to skip rendering this item, or create a "missing" sprite
            return nil
        end
        
        itemSpriteCache[itemId] = spr
    end
    -- Mark this sprite as recently used
    spriteUsageTracker[itemId] = true
    return itemSpriteCache[itemId]
end

-- Clean up unused sprites to prevent memory leaks (updated for modded items)
local function CleanupUnusedSprites()
    -- Get all currently owned items across all players (including modded items)
    local ownedItems = {}
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        for id = 1, MAX_ITEM_ID do
            if player:HasCollectible(id) and IsValidItem(id) then
                ownedItems[id] = true
            end
        end
    end
    
    -- Remove sprites for items no longer owned by any player
    for itemId, _ in pairs(itemSpriteCache) do
        if not ownedItems[itemId] then
            itemSpriteCache[itemId] = nil
            spriteUsageTracker[itemId] = nil
        end
    end
end

-- Simple direct tracking of player collectibles
local playerTrackedCollectibles = {}
-- Track pickup order per player
local playerPickupOrder = {}

-- HUD cache and update functions (must be defined before any usage)
local cachedPlayerIconData = nil
local cachedPlayerCount = 0
local hudDirty = true

-- Layout cache to avoid recalculating every frame
local cachedLayout = {
    playerColumns = {},
    blockWidths = {},
    totalWidth = 0,
    totalHeight = 0,
    maxRows = 1,
    scale = 1,
    startX = 0,
    startY = 0,
    valid = false
}

local function MarkHudDirty()
    hudDirty = true
    cachedLayout.valid = false
    -- Also clear config cache to pick up new values immediately
    cachedClampedConfig = nil
    -- Force screen size cache to refresh so config changes are picked up
    lastScreenW, lastScreenH = 0, 0
end

-- Expose MarkHudDirty for MCM to call when config changes
ExtraHUD.MarkHudDirty = MarkHudDirty

local function UpdatePlayerIconData()
    local game = Game()
    local totalPlayers = game:GetNumPlayers()
    cachedPlayerIconData = {}
    
    -- Clear sprite usage tracker before building new data
    spriteUsageTracker = {}
    
    for i = 0, totalPlayers - 1 do
        cachedPlayerIconData[i + 1] = {}
        local player = Isaac.GetPlayer(i)
        local ownedSet = {}
        
        -- Check both vanilla and modded items
        for id = 1, MAX_ITEM_ID do
            if player:HasCollectible(id) and IsValidItem(id) then
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
        
        -- Add any remaining owned items that weren't in the pickup order
        for id = 1, MAX_ITEM_ID do
            if ownedSet[id] then
                table.insert(cachedPlayerIconData[i + 1], id)
            end
        end
    end
    cachedPlayerCount = totalPlayers
    hudDirty = false
    
    -- Clean up unused sprites after updating player data
    CleanupUnusedSprites()
end

-- Helper: record all current collectibles for all players (e.g. at game start or new player join)
local function TrackAllCurrentCollectibles()
    for i = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        playerTrackedCollectibles[i] = {}
        playerPickupOrder[i] = {}
        for id = 1, MAX_ITEM_ID do
            if player:HasCollectible(id) and IsValidItem(id) then
                playerTrackedCollectibles[i][id] = true
                table.insert(playerPickupOrder[i], id)
            end
        end
    end
end

-- On game start, track all current collectibles and pickup order
ExtraHUD:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, _)
    TrackAllCurrentCollectibles()
    -- Clear sprite cache on new game to prevent memory buildup
    itemSpriteCache = {}
    spriteUsageTracker = {}
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
            for id = 1, MAX_ITEM_ID do
                if player:HasCollectible(id) and IsValidItem(id) then
                    playerTrackedCollectibles[i][id] = true
                    table.insert(playerPickupOrder[i], id)
                end
            end
        end
        MarkHudDirty()
    end
    lastPlayerCount = curCount
end)

-- Maintain true pickup order for each player (with modded item support)
local function UpdatePickupOrderForAllPlayers()
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        playerPickupOrder[i] = playerPickupOrder[i] or {}
        local owned = {}
        -- Mark all currently owned collectibles (including modded ones)
        for id = 1, MAX_ITEM_ID do
            if player:HasCollectible(id) and IsValidItem(id) then
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


-- Config serialization (optimized with table.concat)
local function SerializeConfig(tbl)
    local parts = {}
    for k, v in pairs(tbl) do
        table.insert(parts, k .. "=" .. tostring(v) .. ";")
    end
    return table.concat(parts)
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

local function SerializeAllConfigs()
    if not config or not configPresets or not configPresets[false] or not configPresets[true] then
        return ""
    end
    local str = "[config]" .. SerializeConfig(config) .. "[preset_false]" .. SerializeConfig(configPresets[false]) .. "[preset_true]" .. SerializeConfig(configPresets[true])
    return str
end

local function DeserializeAllConfigs(data)
    local configStr = data:match("%[config%](.-)%[preset_false%]") or ""
    local presetFalseStr = data:match("%[preset_false%](.-)%[preset_true%]") or ""
    local presetTrueStr = data:match("%[preset_true%](.*)$") or ""
    return {
        config = DeserializeConfig(configStr),
        preset_false = DeserializeConfig(presetFalseStr),
        preset_true = DeserializeConfig(presetTrueStr)
    }
end

-- Save/load helpers using Isaac's mod data API
local function SaveConfig()
    if config then
        ExtraHUD:SaveData(SerializeAllConfigs())
        -- Clear caches when config changes
        cachedClampedConfig = nil
        MarkHudDirty()
    end
end

local function LoadConfig()
    if ExtraHUD:HasData() then
        local data = ExtraHUD:LoadData()
        local all = DeserializeAllConfigs(data)
        if all and all.config and config then
            for k, v in pairs(all.config) do config[k] = v end
        end
        if all and all.preset_false and configPresets and configPresets[false] then
            for k, v in pairs(all.preset_false) do configPresets[false][k] = v end
        end
        if all and all.preset_true and configPresets and configPresets[true] then
            for k, v in pairs(all.preset_true) do configPresets[true][k] = v end
        end
    end
end

local function UpdateCurrentPreset()
    -- Optionally update configPresets based on current config/hudMode
    -- (implement as needed)
end

-- Assign these before MCM.Init
SaveConfig = SaveConfig
LoadConfig = LoadConfig
UpdateCurrentPreset = UpdateCurrentPreset

-- Render a single item icon (now uses cache with nil checks for modded items)
local function RenderItemIcon(itemId, x, y, scale, opa)
    local ci = Isaac.GetItemConfig():GetCollectible(itemId)
    if not ci then return end
    local spr = GetItemSprite(itemId, ci.GfxFileName)
    if not spr then return end -- Skip rendering if sprite failed to load (modded item issue)
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

-- Dual-flag overlay logic (set by MCM.lua)
ExtraHUD.MCMCompat_displayingOverlay = ""
ExtraHUD.MCMCompat_selectedOverlay = ""

-- Sprite-based overlay system (following MCM exact implementation)
local function GetMenuAnm2Sprite(animation, frame)
    local sprite = Sprite()
    sprite:Load("gfx/ui/coopextrahud/overlay.anm2", true)
    sprite:SetFrame(animation, frame)
    return sprite
end

-- Optimized column calculation
local function getPlayerColumns(itemCount)
    local maxCols = 4
    local cols = math.ceil(itemCount / 8)
    return math.max(1, math.min(cols, maxCols))
end

-- Calculate and cache layout (only when dirty)
local function UpdateLayout(playerIconData, cfg, screenW, screenH)
    if cachedLayout.valid then return cachedLayout end
    
    -- Calculate columns and max rows needed
    local maxRows = 1
    local playerColumns = {}
    
    for i, items in ipairs(playerIconData) do
        local itemCount = #items
        local cols = getPlayerColumns(itemCount)
        playerColumns[i] = cols
        local rows = math.ceil(itemCount / cols)
        maxRows = math.max(maxRows, rows)
    end
    
    local rawScale = cfg.scale
    local maxHeight = maxRows * (ICON_SIZE + cfg.ySpacing) - cfg.ySpacing
    local scale = rawScale
    
    if not cfg.hudMode then
        -- Scale down if HUD would exceed 80% of screen height
        if maxHeight * rawScale > screenH * 0.8 then
            scale = (screenH * 0.8) / maxHeight
            scale = math.min(scale, rawScale)
        end
    end
    
    -- Calculate block width per player
    local blockWidths = {}
    for i, items in ipairs(playerIconData) do
        local cols = playerColumns[i]
        blockWidths[i] = (ICON_SIZE * cols * scale) + ((cols - 1) * cfg.xSpacing * scale)
    end
    
    local totalWidth = 0
    for i = 1, #blockWidths do
        totalWidth = totalWidth + blockWidths[i]
    end
    totalWidth = totalWidth + (#blockWidths - 1) * INTER_PLAYER_SPACING * scale
    local totalHeight = maxHeight * scale
    
    -- Calculate start position
    local startX, startY
    if cfg.hudMode then
        startX = cfg.boundaryX + cfg.boundaryW - totalWidth + cfg.xOffset
        startY = cfg.boundaryY + cfg.yOffset
    else
        startX = cfg.boundaryX + cfg.boundaryW - totalWidth + cfg.xOffset
        startY = cfg.boundaryY + ((cfg.boundaryH - totalHeight) / 2) + cfg.yOffset
    end
    
    -- Cache the results
    cachedLayout.playerColumns = playerColumns
    cachedLayout.blockWidths = blockWidths
    cachedLayout.totalWidth = totalWidth
    cachedLayout.totalHeight = totalHeight
    cachedLayout.maxRows = maxRows
    cachedLayout.scale = scale
    cachedLayout.startX = startX
    cachedLayout.startY = startY
    cachedLayout.valid = true
    
    return cachedLayout
end

-- Cache for clamped config values
local cachedClampedConfig = nil
local lastScreenW, lastScreenH = 0, 0

-- Clamp config values only when screen size changes
local function GetClampedConfig(cfg, screenW, screenH)
    if cachedClampedConfig and lastScreenW == screenW and lastScreenH == screenH then
        return cachedClampedConfig
    end
    
    local clamped = {}
    -- Copy and clamp all values
    for k, v in pairs(cfg) do clamped[k] = v end
    
    -- Clamp boundary to screen size
    clamped.boundaryW = math.max(32, math.min(clamped.boundaryW or screenW, screenW))
    clamped.boundaryH = math.max(32, math.min(clamped.boundaryH or screenH, screenH))
    clamped.boundaryX = math.max(0, math.min(clamped.boundaryX or 0, screenW - 1))
    clamped.boundaryY = math.max(0, math.min(clamped.boundaryY or 0, screenH - 1))
    
    -- Clamp minimap area to screen
    clamped.minimapW = math.max(0, math.min(clamped.minimapW or 0, screenW))
    clamped.minimapH = math.max(0, math.min(clamped.minimapH or 0, screenH))
    clamped.minimapX = math.max(0, math.min(clamped.minimapX or 0, screenW - 1))
    clamped.minimapY = math.max(0, math.min(clamped.minimapY or 0, screenH - 1))
    
    -- Ensure other values have defaults
    clamped.minimapPadding = clamped.minimapPadding or 0
    clamped.xOffset = clamped.xOffset or 0
    clamped.yOffset = clamped.yOffset or 0
    clamped.scale = clamped.scale or 1
    clamped.opacity = clamped.opacity or 1
    clamped.xSpacing = clamped.xSpacing or 0
    clamped.ySpacing = clamped.ySpacing or 0
    clamped.dividerOffset = clamped.dividerOffset or 0
    clamped.dividerYOffset = clamped.dividerYOffset or 0
    
    cachedClampedConfig = clamped
    lastScreenW, lastScreenH = screenW, screenH
    return clamped
end

-- Overlay sprites (created once and reused, MCM-style)
local HudOffsetVisualTopLeft = GetMenuAnm2Sprite("Offset", 0)
local HudOffsetVisualTopRight = GetMenuAnm2Sprite("Offset", 1) 
local HudOffsetVisualBottomRight = GetMenuAnm2Sprite("Offset", 2)
local HudOffsetVisualBottomLeft = GetMenuAnm2Sprite("Offset", 3)

function ExtraHUD:PostRender()
    local game = Game()
    local screenW, screenH = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
    
    -- Get clamped config (cached when screen size doesn't change)
    local cfg = GetClampedConfig(getConfig(), screenW, screenH)
    
    -- Only update player icon data cache if dirty or player count changed
    local totalPlayers = game:GetNumPlayers()
    if hudDirty or not cachedPlayerIconData or cachedPlayerCount ~= totalPlayers then
        UpdatePlayerIconData()
    end
    local playerIconData = cachedPlayerIconData
    if not playerIconData then return end
    
    -- Get cached layout (only recalculates when dirty)
    local layout = UpdateLayout(playerIconData, cfg, screenW, screenH)
    
    -- Apply minimap avoidance and boundary clamping to start position
    local startX, startY = layout.startX, layout.startY
    
    -- Minimap avoidance (only if minimap is configured)
    if cfg.minimapW > 0 and cfg.minimapH > 0 then
        local hudLeft, hudRight = startX, startX + layout.totalWidth
        local hudTop, hudBottom = startY, startY + layout.totalHeight
        local miniLeft, miniRight = cfg.minimapX, cfg.minimapX + cfg.minimapW
        local miniTop, miniBottom = cfg.minimapY, cfg.minimapY + cfg.minimapH
        
        local overlap = not (hudRight < miniLeft or hudLeft > miniRight or hudBottom < miniTop or hudTop > miniBottom)
        if overlap then
            startY = miniBottom + cfg.minimapPadding
        end
    end
    
    -- Clamp to boundary
    startX = math.max(cfg.boundaryX, math.min(startX, cfg.boundaryX + cfg.boundaryW - layout.totalWidth))
    startY = math.max(cfg.boundaryY, math.min(startY, cfg.boundaryY + cfg.boundaryH - layout.totalHeight))
    
    -- Draw icons + dividers using cached layout
    local curX = startX
    for i, items in ipairs(playerIconData) do
        local cols = layout.playerColumns[i]
        local blockW = layout.blockWidths[i]
        local rows = math.ceil(#items / cols)
        
        for idx, itemId in ipairs(items) do
            local row = math.floor((idx - 1) / cols)
            local col = (idx - 1) % cols
            local x = curX + col * (ICON_SIZE + cfg.xSpacing) * layout.scale
            local y = startY + row * (ICON_SIZE + cfg.ySpacing) * layout.scale
            RenderItemIcon(itemId, x, y, layout.scale, cfg.opacity)
        end
        
        if i < #playerIconData then
            local dividerX = curX + blockW + (INTER_PLAYER_SPACING * layout.scale) / 2 + cfg.dividerOffset
            local lineChar = "|"
            local dividerStep = ICON_SIZE * 0.375 * layout.scale
            local lines = math.floor(layout.totalHeight / dividerStep)
            for l = 0, lines do
                Isaac.RenderScaledText(lineChar, dividerX, startY + cfg.dividerYOffset + l * dividerStep, layout.scale, layout.scale, 1, 1, 1, cfg.opacity)
            end
        end
        curX = curX + blockW + INTER_PLAYER_SPACING * layout.scale
    end
    -- Debug overlay: only draw the HUD boundary border, no text or callback names
    if cfg.debugOverlay then
        -- Draw a lineart border for the HUD boundary for debug/adjustment (NO TEXT)
        local bx = tonumber(cfg.boundaryX) or 0
        local by = tonumber(cfg.boundaryY) or 0
        local bw = tonumber(cfg.boundaryW) or 0
        local bh = tonumber(cfg.boundaryH) or 0
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
    -- Only show overlays if MCM is open and both Display and Selected flags match
    local mcm = _G['ModConfigMenu']
    local mcmIsOpen = mcm and ((type(mcm.IsVisible) == "function" and mcm.IsVisible()) or (type(mcm.IsVisible) == "boolean" and mcm.IsVisible))
    local showBoundary, showMinimap = false, false
    if mcmIsOpen then
        if ExtraHUD.MCMCompat_displayingOverlay == "boundary" and ExtraHUD.MCMCompat_selectedOverlay == "boundary" then
            showBoundary = true
        elseif ExtraHUD.MCMCompat_displayingOverlay == "minimap" and ExtraHUD.MCMCompat_selectedOverlay == "minimap" then
            showMinimap = true
        end
    else
        -- Always clear overlay flags when MCM is closed
        if ExtraHUD.MCMCompat_displayingOverlay ~= "" or ExtraHUD.MCMCompat_selectedOverlay ~= "" then
            ExtraHUD.MCMCompat_displayingOverlay = ""
            ExtraHUD.MCMCompat_selectedOverlay = ""
        end
    end
    -- Draw overlays as needed (now using proper sprites)
    if showBoundary then
        -- Use current config directly for overlay rendering to ensure real-time updates
        local currentConfig = getConfig()
        local bx = tonumber(currentConfig.boundaryX) or 0
        local by = tonumber(currentConfig.boundaryY) or 0
        local bw = tonumber(currentConfig.boundaryW) or 0
        local bh = tonumber(currentConfig.boundaryH) or 0
        if bw > 0 and bh > 0 then
            local vecZero = Vector(0, 0)
            
            -- Render corner sprites at boundary corners (MCM-style) with nil checks
            if HudOffsetVisualTopLeft then
                HudOffsetVisualTopLeft:Render(Vector(bx, by), vecZero, vecZero)
            end
            if HudOffsetVisualTopRight then
                HudOffsetVisualTopRight:Render(Vector(bx + bw - 32, by), vecZero, vecZero)
            end
            if HudOffsetVisualBottomLeft then
                HudOffsetVisualBottomLeft:Render(Vector(bx, by + bh - 32), vecZero, vecZero)
            end
            if HudOffsetVisualBottomRight then
                HudOffsetVisualBottomRight:Render(Vector(bx + bw - 32, by + bh - 32), vecZero, vecZero)
            end
            
            -- Optional: Add text label
            Isaac.RenderText("Boundary", bx+4, by+4, 1, 0, 0, 1)
        else
            AddDebugLog("[Overlay] showBoundary: boundary config value(s) nil or zero, skipping overlay")
        end
    elseif showMinimap then
        -- Use current config directly for overlay rendering to ensure real-time updates
        local currentConfig = getConfig()
        local mx = tonumber(currentConfig.minimapX) or 0
        local my = tonumber(currentConfig.minimapY) or 0
        local mw = tonumber(currentConfig.minimapW) or 0
        local mh = tonumber(currentConfig.minimapH) or 0
        if mw > 0 and mh > 0 then
            local vecZero = Vector(0, 0)
            
            -- Render corner sprites at minimap area corners (MCM-style) with nil checks
            if HudOffsetVisualTopLeft then
                HudOffsetVisualTopLeft:Render(Vector(mx, my), vecZero, vecZero)
            end
            if HudOffsetVisualTopRight then
                HudOffsetVisualTopRight:Render(Vector(mx + mw - 32, my), vecZero, vecZero)
            end
            if HudOffsetVisualBottomLeft then
                HudOffsetVisualBottomLeft:Render(Vector(mx, my + mh - 32), vecZero, vecZero)
            end
            if HudOffsetVisualBottomRight then
                HudOffsetVisualBottomRight:Render(Vector(mx + mw - 32, my + mh - 32), vecZero, vecZero)
            end
            
            -- Optional: Add text label
            Isaac.RenderText("Map", mx+4, my+4, 1, 0, 0, 1)
        else
            AddDebugLog("[Overlay] showMinimap: minimap config value(s) nil or zero, skipping overlay")
        end
    end
end

ExtraHUD:AddCallback(ModCallbacks.MC_POST_RENDER, ExtraHUD.PostRender)

-- MCM integration
local MCM = require("MCM")

-- Robust config/configPresets initialization and loading
if not config then config = {} end
if not configPresets then configPresets = {} end

-- Fill missing config keys from defaultConfig
for k, v in pairs(defaultConfig) do
    if config[k] == nil then config[k] = v end
end

-- Fill missing configPresets keys from defaultConfigPresets
for mode, preset in pairs(defaultConfigPresets) do
    if configPresets[mode] == nil then configPresets[mode] = {} end
    for k, v in pairs(preset) do
        if configPresets[mode][k] == nil then configPresets[mode][k] = v end
    end
end

-- Initialize function placeholders
if not SaveConfig then SaveConfig = function() end end
if not LoadConfig then LoadConfig = function() end end
if not UpdateCurrentPreset then UpdateCurrentPreset = function() end end

-- Load config from disk on mod load (before MCM.Init)
if ExtraHUD and ExtraHUD.HasData and ExtraHUD:HasData() then
    local data = ExtraHUD:LoadData()
    local all = DeserializeAllConfigs(data)
    if all and all.config then
        for k, v in pairs(all.config) do config[k] = v end
    end
    if all and all.preset_false then
        for k, v in pairs(all.preset_false) do configPresets[false][k] = v end
    end
    if all and all.preset_true then
        for k, v in pairs(all.preset_true) do configPresets[true][k] = v end
    end
end

ExtraHUD:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, _)
    -- Pass config tables/functions to MCM
    local mcmTables = MCM.Init({
        ExtraHUD = ExtraHUD,
        config = config,
        configPresets = configPresets,
        SaveConfig = SaveConfig,
        LoadConfig = LoadConfig,
        UpdateCurrentPreset = UpdateCurrentPreset,
    })
    config = mcmTables.config
    configPresets = mcmTables.configPresets
    SaveConfig = mcmTables.SaveConfig
    LoadConfig = mcmTables.LoadConfig
    UpdateCurrentPreset = mcmTables.UpdateCurrentPreset
    MCM.RegisterConfigMenu()
end)

ExtraHUD:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
    SaveConfig()
end)



print("[CoopExtraHUD] Fully loaded with HUD mode support and configurable spacing and boundary!")
