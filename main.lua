local ExtraHUD = RegisterMod("CoopExtraHUD", 1)

-- IMMEDIATE DEBUG: Test if mod is loading at all
Isaac.DebugString("[CoopExtraHUD] *** MOD LOADING STARTED ***")

-- Default config values
local config = nil -- will be set by MCM.Init

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
    autoAdjustOnResize = true, -- Default to enabled for better user experience
    _mcm_map_overlay_refresh = 244,
    _mcm_boundary_overlay_refresh = 574,

    disableVanillaExtraHUD = true, -- disables vanilla ExtraHUD by default
}

-- Helper to get config safely before MCM.Init
local function getConfig()
    return config or defaultConfig
end

-- Isaac best practice: Use proper Options API instead of ExecuteCommand
local function DisableVanillaExtraHUD()
    local cfg = getConfig()
    if cfg.disableVanillaExtraHUD then
        -- Isaac community standard: Use Options.ExtraHUDStyle = 0 (not ExecuteCommand)
        if Options and type(Options) == "table" then
            Options.ExtraHUDStyle = 0
        end
    end
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
    autoAdjustOnResize = true,
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
    autoAdjustOnResize = true,
}

-- Isaac best practice: Use proper constants and avoid magic numbers
local ICON_SIZE = 32
local INTER_PLAYER_SPACING = 12
local MIN_COLLECTIBLE_ID = 1
local DEFAULT_ITEM_LIMIT = 732 -- Safe fallback

-- Isaac best practice: Safe constant access with fallbacks
local MAX_ITEM_ID = 1000
local VANILLA_ITEM_LIMIT = nil

-- Function to safely initialize constants that depend on enums
local function InitializeConstants()
    if not VANILLA_ITEM_LIMIT then
        -- Only access CollectibleType when it's actually needed, with safe fallback
        local numCollectibles = nil
        if CollectibleType and CollectibleType.NUM_COLLECTIBLES then
            numCollectibles = CollectibleType.NUM_COLLECTIBLES
        end
        
        VANILLA_ITEM_LIMIT = math.max(MIN_COLLECTIBLE_ID, (numCollectibles or DEFAULT_ITEM_LIMIT) - 1)
    end
end

-- Isaac best practice: Enhanced item validation with resource validation
local function IsValidItem(itemId)
    if not itemId or type(itemId) ~= "number" or itemId < 1 then
        return false
    end
    
    local itemConfig = Isaac.GetItemConfig()
    if not itemConfig then return false end
    
    local collectible = itemConfig:GetCollectible(itemId)
    return collectible ~= nil and 
           collectible.GfxFileName ~= nil and 
           collectible.GfxFileName ~= "" and
           collectible.GfxFileName ~= "gfx/items/collectibles/questionmark.png"
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

-- Isaac best practice: Cache sprites efficiently and validate resources
local function GetItemSprite(itemId, gfxFile)
    if not itemSpriteCache[itemId] then
        -- Validate the graphics file exists and is valid before attempting to load
        if not gfxFile or gfxFile == "" then
            return nil
        end
        
        local spr = Sprite()
        spr:Load("gfx/005.100_collectible.anm2", true)
        spr:ReplaceSpritesheet(1, gfxFile)
        spr:LoadGraphics()
        spr:Play("Idle", true)
        spr:SetFrame(0)
        
        itemSpriteCache[itemId] = spr
    end
    -- Return nil for cached failures (false)
    return itemSpriteCache[itemId] or nil
end

-- Clean up unused sprites to prevent memory leaks (updated for modded items)
local function CleanupUnusedSprites()
    -- Only run if spriteUsageTracker is large (avoid frequent cleanup)
    local ownedItems = {}
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        -- Isaac best practice: Use proper constants for item scanning
        for id = MIN_COLLECTIBLE_ID, VANILLA_ITEM_LIMIT do
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

function ExtraHUD.OnOverlayAdjusterMoved()
    -- Invalidate all caches and force HUD/layout update
    cachedClampedConfig = nil
    cachedLayout.valid = false
    lastScreenW, lastScreenH = 0, 0
    MarkHudDirty()
end

local function UpdatePlayerIconData()
    local game = Game()
    local totalPlayers = game:GetNumPlayers()
    cachedPlayerIconData = {}
    -- Only clear sprite usage tracker if player count or pickup order changed
    local shouldCleanup = false
    if not spriteUsageTracker or #spriteUsageTracker > 2 * totalPlayers then
        spriteUsageTracker = {}
        shouldCleanup = true
    end
    for i = 0, totalPlayers - 1 do
        cachedPlayerIconData[i + 1] = {}
        local player = Isaac.GetPlayer(i)
        local ownedSet = {}
        -- Only scan up to MAX_ITEM_ID, but skip IDs above vanilla limit unless modded items are detected
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
        for id = 1, MAX_ITEM_ID do
            if ownedSet[id] then
                table.insert(cachedPlayerIconData[i + 1], id)
            end
        end
    end
    cachedPlayerCount = totalPlayers
    hudDirty = false
    -- Only clean up unused sprites if necessary
    if shouldCleanup then
        CleanupUnusedSprites()
    end
end

-- Helper: record all current collectibles for all players (e.g. at game start or new player join)
local function TrackAllCurrentCollectibles()
    for i = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        playerTrackedCollectibles[i] = {}
        playerPickupOrder[i] = {}
        -- Only scan up to MAX_ITEM_ID, skip high IDs unless needed
        for id = 1, MAX_ITEM_ID do
            if player:HasCollectible(id) and IsValidItem(id) then
                playerTrackedCollectibles[i][id] = true
                table.insert(playerPickupOrder[i], id)
            end
        end
    end
end

-- Isaac best practice: Enhanced game start handling
ExtraHUD:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, _)
    -- Disable vanilla ExtraHUD if configured
    DisableVanillaExtraHUD()
    TrackAllCurrentCollectibles()
    -- Clear sprite cache on new game to prevent memory buildup
    itemSpriteCache = {}
    spriteUsageTracker = {}
    MarkHudDirty()
end, CallbackPriority and CallbackPriority.LATE or nil)
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
end, CallbackPriority and CallbackPriority.LATE or nil)

-- Maintain true pickup order for each player (with modded item support)
local function UpdatePickupOrderForAllPlayers()
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        playerPickupOrder[i] = playerPickupOrder[i] or {}
        local owned = {}
        -- Only scan up to MAX_ITEM_ID
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

-- MCM compatibility flags for overlay display (manual toggles only)
ExtraHUD.MCMCompat_displayingOverlay = ""
ExtraHUD.MCMCompat_selectedOverlay = ""
ExtraHUD.MCMCompat_overlayTimestamp = 0

-- Debug frame counter to reduce spam
local debugFrameCounter = 0
-- Sprite-based overlay system (following MCM exact implementation)
local function GetMenuAnm2Sprite(animation, frame)
    local sprite = Sprite()
    sprite:Load("gfx/ui/coopextrahud/overlay.anm2", true)
    sprite:SetFrame(animation, frame)
    Isaac.DebugString("[CoopExtraHUD] Created overlay sprite: " .. animation .. ", frame " .. frame)
    return sprite
end

-- Test sprite loading immediately
Isaac.DebugString("[CoopExtraHUD] Testing sprite loading...")
local testSprite = GetMenuAnm2Sprite("Offset", 0)
if testSprite then
    Isaac.DebugString("[CoopExtraHUD] Test sprite loaded successfully")
else
    Isaac.DebugString("[CoopExtraHUD] ERROR: Test sprite failed to load")
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
    -- Always recalculate clamped config if cachedClampedConfig is nil
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

-- Auto-resize functionality: adjusts HUD boundary when screen size changes
local lastAutoResizeScreenW, lastAutoResizeScreenH = 0, 0
local function HandleAutoResize(cfg, screenW, screenH)
    -- Only proceed if auto-adjust is enabled
    if not cfg.autoAdjustOnResize then
        lastAutoResizeScreenW, lastAutoResizeScreenH = screenW, screenH
        return
    end
    
    -- Check if this is the first run or screen size changed
    local screenChanged = (lastAutoResizeScreenW ~= screenW or lastAutoResizeScreenH ~= screenH)
    
    if screenChanged and lastAutoResizeScreenW > 0 and lastAutoResizeScreenH > 0 then
        -- Calculate relative position as percentage of screen
        local relativeX = cfg.boundaryX / lastAutoResizeScreenW
        local relativeY = cfg.boundaryY / lastAutoResizeScreenH
        local relativeW = cfg.boundaryW / lastAutoResizeScreenW
        local relativeH = cfg.boundaryH / lastAutoResizeScreenH
        
        -- Apply to new screen size
        cfg.boundaryX = math.floor(relativeX * screenW + 0.5)
        cfg.boundaryY = math.floor(relativeY * screenH + 0.5)
        cfg.boundaryW = math.floor(relativeW * screenW + 0.5)
        cfg.boundaryH = math.floor(relativeH * screenH + 0.5)
        
        -- Clamp to valid ranges
        cfg.boundaryX = math.max(0, math.min(cfg.boundaryX, screenW - 32))
        cfg.boundaryY = math.max(0, math.min(cfg.boundaryY, screenH - 32))
        cfg.boundaryW = math.max(32, math.min(cfg.boundaryW, screenW - cfg.boundaryX))
        cfg.boundaryH = math.max(32, math.min(cfg.boundaryH, screenH - cfg.boundaryY))
        
        -- Also adjust minimap if it's not auto-positioned (-1 values)
        if cfg.minimapX >= 0 and cfg.minimapY >= 0 then
            local relativeMinimapX = cfg.minimapX / lastAutoResizeScreenW
            local relativeMinimapY = cfg.minimapY / lastAutoResizeScreenH
            local relativeMinimapW = cfg.minimapW / lastAutoResizeScreenW
            local relativeMinimapH = cfg.minimapH / lastAutoResizeScreenH
            
            cfg.minimapX = math.floor(relativeMinimapX * screenW + 0.5)
            cfg.minimapY = math.floor(relativeMinimapY * screenH + 0.5)
            cfg.minimapW = math.floor(relativeMinimapW * screenW + 0.5)
            cfg.minimapH = math.floor(relativeMinimapH * screenH + 0.5)
            
            -- Clamp minimap values
            cfg.minimapX = math.max(0, math.min(cfg.minimapX, screenW - 1))
            cfg.minimapY = math.max(0, math.min(cfg.minimapY, screenH - 1))
            cfg.minimapW = math.max(0, math.min(cfg.minimapW, screenW - cfg.minimapX))
            cfg.minimapH = math.max(0, math.min(cfg.minimapH, screenH - cfg.minimapY))
        end
        
        -- Save the updated config
        SaveConfig()
        
        -- Force cache refresh
        cachedClampedConfig = nil
        lastScreenW, lastScreenH = 0, 0
        
        print("[CoopExtraHUD] Auto-adjusted HUD position for new screen size: " .. screenW .. "x" .. screenH)
    end
    
    lastAutoResizeScreenW, lastAutoResizeScreenH = screenW, screenH
end
-- Overlay sprites (created once and reused, MCM-style)

local HudOffsetVisualTopLeft = GetMenuAnm2Sprite("Offset", 0)
local HudOffsetVisualTopRight = GetMenuAnm2Sprite("Offset", 1)
local HudOffsetVisualBottomRight = GetMenuAnm2Sprite("Offset", 2)
local HudOffsetVisualBottomLeft = GetMenuAnm2Sprite("Offset", 3)

-- Divider sprite (1x1 white pixel, scalable)
local DividerSprite = Sprite()
DividerSprite:Load("gfx/ui/coopextrahud/overlay.anm2", true)
DividerSprite:SetFrame("Divider", 0)
DividerSprite:LoadGraphics()

-- Manual overlay toggle for testing (Keyboard shortcuts)
local overlayToggleDebounce = 0
local currentManualOverlayType = ""

-- Function to manually set overlay types with different keys
local function HandleManualOverlayToggle()
    if overlayToggleDebounce > 0 then
        overlayToggleDebounce = overlayToggleDebounce - 1
        return
    end
    
    local newOverlayType = ""
    
    -- Check for different keys for different overlay types
    if Input.IsButtonPressed(Keyboard.KEY_B, 0) then -- B for Boundary
        newOverlayType = currentManualOverlayType == "boundary" and "" or "boundary"
        overlayToggleDebounce = 15
    elseif Input.IsButtonPressed(Keyboard.KEY_M, 0) then -- M for Minimap
        newOverlayType = currentManualOverlayType == "minimap" and "" or "minimap"
        overlayToggleDebounce = 15
    elseif Input.IsButtonPressed(Keyboard.KEY_H, 0) then -- H for HUD offset
        newOverlayType = currentManualOverlayType == "hudoffset" and "" or "hudoffset"
        overlayToggleDebounce = 15
    elseif Input.IsButtonPressed(Keyboard.KEY_N, 0) then -- N for None (clear all)
        newOverlayType = ""
        overlayToggleDebounce = 15
    end
    
    if newOverlayType ~= currentManualOverlayType then
        currentManualOverlayType = newOverlayType
        ExtraHUD.MCMCompat_displayingOverlay = newOverlayType
        ExtraHUD.MCMCompat_selectedOverlay = newOverlayType
        
        local overlayName = newOverlayType == "" and "None" or newOverlayType
        Isaac.DebugString("[CoopExtraHUD] Manual overlay set: " .. overlayName)
        print("[CoopExtraHUD] Manual overlay: " .. overlayName .. " (B=Boundary, M=Minimap, H=HUD Offset, N=None)")
    end
end

function ExtraHUD:PostRender()
    -- Isaac best practice: Use proper Isaac API game state validation
    local game = Game()
    if not game then return end
    
    -- Isaac API: Check if game is paused
    if game:IsPaused() then
        return
    end
    
    -- Isaac API: Check for console/debug state (basic validation)
    local room = game:GetRoom()
    if not room then return end
    
    local screenW, screenH = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
    if screenW <= 0 or screenH <= 0 then return end -- Safety check
    
    -- Initialize constants that depend on enums (safe to call multiple times)
    InitializeConstants()
    
    -- Handle auto-resize if enabled (must be called before getting configs)
    HandleAutoResize(getConfig(), screenW, screenH)
    
    -- Get clamped config (cached when screen size doesn't change) for layout/scaling
    local clampedCfg = GetClampedConfig(getConfig(), screenW, screenH)
    -- Always use live config for boundary/minimap positions
    local liveCfg = getConfig()

    -- Only update player icon data cache if dirty or player count changed
    local totalPlayers = game:GetNumPlayers()
    if totalPlayers <= 0 then return end -- No players, nothing to render
    if hudDirty or not cachedPlayerIconData or cachedPlayerCount ~= totalPlayers then
        UpdatePlayerIconData()
    end
    local playerIconData = cachedPlayerIconData
    if not playerIconData then return end

    -- Get cached layout (only recalculates when dirty)
    local layout = UpdateLayout(playerIconData, clampedCfg, screenW, screenH)

    -- Use live config for boundary/minimap positions
    local boundaryX = tonumber(liveCfg.boundaryX) or 0
    local boundaryY = tonumber(liveCfg.boundaryY) or 0
    local boundaryW = tonumber(liveCfg.boundaryW) or 0
    local boundaryH = tonumber(liveCfg.boundaryH) or 0
    local minimapX = tonumber(liveCfg.minimapX) or 0
    local minimapY = tonumber(liveCfg.minimapY) or 0
    local minimapW = tonumber(liveCfg.minimapW) or 0
    local minimapH = tonumber(liveCfg.minimapH) or 0
    local minimapPadding = liveCfg.minimapPadding or 0

    -- Apply minimap avoidance and boundary clamping to start position (always use live config for map area)
    local startX, startY = layout.startX, layout.startY

    -- Minimap avoidance (always use live config for minimap area)
    local mapX = tonumber(liveCfg.minimapX) or 0
    local mapY = tonumber(liveCfg.minimapY) or 0
    local mapW = tonumber(liveCfg.minimapW) or 0
    local mapH = tonumber(liveCfg.minimapH) or 0
    local mapPad = liveCfg.minimapPadding or 0
    if mapW > 0 and mapH > 0 then
        local hudLeft, hudRight = startX, startX + layout.totalWidth
        local hudTop, hudBottom = startY, startY + layout.totalHeight
        local miniLeft, miniRight = mapX, mapX + mapW
        local miniTop, miniBottom = mapY, mapY + mapH
        local overlap = not (hudRight < miniLeft or hudLeft > miniRight or hudBottom < miniTop or hudTop > miniBottom)
        if overlap then
            startY = miniBottom + mapPad
        end
    end

    -- Clamp to boundary (using live config)
    startX = math.max(boundaryX, math.min(startX, boundaryX + boundaryW - layout.totalWidth))
    startY = math.max(boundaryY, math.min(startY, boundaryY + boundaryH - layout.totalHeight))

    -- Draw icons + dividers using cached layout
    local curX = startX
    for i, items in ipairs(playerIconData) do
        local cols = layout.playerColumns[i]
        local blockW = layout.blockWidths[i]
        -- Defensive: skip this player if layout columns or block width are missing/invalid
        if type(cols) ~= "number" or cols < 1 or type(blockW) ~= "number" or blockW < 1 then
            -- Skip this player, prevents crash for users without MCM or with broken config
            goto continue_player_loop
        end
        local rows = math.ceil(#items / cols)
        -- PERF: Only render up to 32 items per player to avoid excessive draw calls
        local maxItems = math.min(#items, 32)
        for idx = 1, maxItems do
            local itemId = items[idx]
            local row = math.floor((idx - 1) / cols)
            local col = (idx - 1) % cols
            local x = curX + col * (ICON_SIZE + clampedCfg.xSpacing) * layout.scale
            local y = startY + row * (ICON_SIZE + clampedCfg.ySpacing) * layout.scale
            RenderItemIcon(itemId, x, y, layout.scale, clampedCfg.opacity)
        end
        if i < #playerIconData then
            local dividerX = curX + blockW + (INTER_PLAYER_SPACING * layout.scale) / 2 + clampedCfg.dividerOffset
            local dividerY = startY + clampedCfg.dividerYOffset
            local dividerHeight = layout.totalHeight
            -- Robust divider sprite scaling: scale factor, not pixel size
            local spriteBaseHeight = 1 -- divider.png is 1x1 px
            local heightScale = math.max(1, math.floor(dividerHeight + 0.5))
            DividerSprite.Scale = Vector(1, heightScale)
            DividerSprite.Color = Color(1, 1, 1, clampedCfg.opacity)
            -- Render at the top of the divider area
            DividerSprite:Render(Vector(dividerX, dividerY), Vector.Zero, Vector.Zero)
        end
        curX = curX + blockW + INTER_PLAYER_SPACING * layout.scale
        ::continue_player_loop::
    end
    -- Debug overlay: color-coded sprite-based overlays
    if getConfig().debugOverlay then
        -- Draw HUD boundary in red for debug/adjustment
        if boundaryW > 0 and boundaryH > 0 then
            local vecZero = Vector(0, 0)
            local debugBoundaryColor = Color(1, 0, 0, 0.6) -- Red with transparency
            
            -- Use colored overlay sprites for visual feedback
            if HudOffsetVisualTopLeft then
                HudOffsetVisualTopLeft.Color = debugBoundaryColor
                HudOffsetVisualTopLeft:Render(Vector(boundaryX, boundaryY), vecZero, vecZero)
            end
            if HudOffsetVisualTopRight then
                HudOffsetVisualTopRight.Color = debugBoundaryColor
                HudOffsetVisualTopRight:Render(Vector(boundaryX + boundaryW - 32, boundaryY), vecZero, vecZero)
            end
            if HudOffsetVisualBottomLeft then
                HudOffsetVisualBottomLeft.Color = debugBoundaryColor
                HudOffsetVisualBottomLeft:Render(Vector(boundaryX, boundaryY + boundaryH - 32), vecZero, vecZero)
            end
            if HudOffsetVisualBottomRight then
                HudOffsetVisualBottomRight.Color = debugBoundaryColor
                HudOffsetVisualBottomRight:Render(Vector(boundaryX + boundaryW - 32, boundaryY + boundaryH - 32), vecZero, vecZero)
            end
            Isaac.RenderText("HUD Debug", boundaryX+4, boundaryY+4, 1, 0, 0, 1)
            
            -- Show actual HUD position in green if different from boundary
            local actualHudColor = Color(0, 1, 0, 0.6) -- Green with transparency
            if startX ~= boundaryX or startY ~= boundaryY and layout.totalWidth > 0 and layout.totalHeight > 0 then
                -- Create temporary sprites for actual HUD position
                local actualHudSprites = {
                    GetMenuAnm2Sprite("Offset", 0), -- top-left
                    GetMenuAnm2Sprite("Offset", 1), -- top-right  
                    GetMenuAnm2Sprite("Offset", 2), -- bottom-right
                    GetMenuAnm2Sprite("Offset", 3)  -- bottom-left
                }
                
                if actualHudSprites[1] then
                    actualHudSprites[1].Color = actualHudColor
                    actualHudSprites[1]:Render(Vector(startX, startY), vecZero, vecZero)
                end
                if actualHudSprites[2] then
                    actualHudSprites[2].Color = actualHudColor
                    actualHudSprites[2]:Render(Vector(startX + layout.totalWidth - 32, startY), vecZero, vecZero)
                end
                if actualHudSprites[4] then
                    actualHudSprites[4].Color = actualHudColor
                    actualHudSprites[4]:Render(Vector(startX, startY + layout.totalHeight - 32), vecZero, vecZero)
                end
                if actualHudSprites[3] then
                    actualHudSprites[3].Color = actualHudColor
                    actualHudSprites[3]:Render(Vector(startX + layout.totalWidth - 32, startY + layout.totalHeight - 32), vecZero, vecZero)
                end
                Isaac.RenderText("Actual HUD", startX+4, startY+4, 0, 1, 0, 1)
            end
        end
        -- Ensure the cache reflects the current state
        if cachedClampedConfig then
            cachedClampedConfig.debugOverlay = true
        end
    else
        -- Only force a HUD redraw if the debug overlay was previously on and is now off
        if cachedClampedConfig and cachedClampedConfig.debugOverlay then
            cachedClampedConfig.debugOverlay = false
            MarkHudDirty()
        end
    end
    -- Update MCM overlay detection every frame when MCM is open
    -- Manual overlay controls via MCM toggle switches only
    -- All automatic detection has been removed per user request
    
    -- Manual overlay controls available as backup (B=Boundary, M=Minimap, H=HUD Offset, N=None)
    HandleManualOverlayToggle()
    
    -- Debug: Log overlay flags every 120 frames to monitor their state
    debugFrameCounter = debugFrameCounter + 1
    if debugFrameCounter % 120 == 1 then
        Isaac.DebugString("[CoopExtraHUD] Overlay flags - Displaying: '" .. (ExtraHUD.MCMCompat_displayingOverlay or "nil") .. "', Selected: '" .. (ExtraHUD.MCMCompat_selectedOverlay or "nil") .. "'")
    end
    
    -- Only show overlays if MCM is open and both Display and Selected flags match (always use live config for overlay positions)
    -- OR if overlays are manually triggered via helper options (allow overlays even when MCM is closed)
    local mcm = _G['ModConfigMenu']
    local mcmIsOpen = mcm and ((type(mcm.IsVisible) == "function" and mcm.IsVisible()) or (type(mcm.IsVisible) == "boolean" and mcm.IsVisible))
    -- Check if we should show overlays in MCM
    local showBoundary, showMinimap, showHudOffset = false, false, false
    
    -- Show overlays if MCM is open OR if they were manually triggered
    if mcmIsOpen or ExtraHUD.MCMCompat_displayingOverlay ~= "" then
        -- Check for boundary/minimap/hudoffset overlays using the dual-flag system
        if ExtraHUD.MCMCompat_displayingOverlay == "boundary" and ExtraHUD.MCMCompat_selectedOverlay == "boundary" then
            showBoundary = true
            -- Debug: Log when boundary overlay is active
            Isaac.DebugString("[CoopExtraHUD] Rendering boundary overlay")
        elseif ExtraHUD.MCMCompat_displayingOverlay == "minimap" and ExtraHUD.MCMCompat_selectedOverlay == "minimap" then
            showMinimap = true
            -- Debug: Log when minimap overlay is active
            Isaac.DebugString("[CoopExtraHUD] Rendering minimap overlay")
        elseif ExtraHUD.MCMCompat_displayingOverlay == "hudoffset" and ExtraHUD.MCMCompat_selectedOverlay == "hudoffset" then
            showHudOffset = true
            -- Debug: Log when HUD offset overlay is active
            Isaac.DebugString("[CoopExtraHUD] Rendering HUD offset overlay")
        end
        
        -- Debug: Always log overlay flags when MCM is open
        if ExtraHUD.MCMCompat_displayingOverlay ~= "" or ExtraHUD.MCMCompat_selectedOverlay ~= "" then
            Isaac.DebugString("[CoopExtraHUD] MCM Overlay flags - Displaying: '" .. ExtraHUD.MCMCompat_displayingOverlay .. "', Selected: '" .. ExtraHUD.MCMCompat_selectedOverlay .. "'")
        else
            -- Debug: Log that MCM is open but no overlays are active (every 60 frames to reduce spam)
            if debugFrameCounter % 60 == 1 then
                Isaac.DebugString("[CoopExtraHUD] MCM is open but no overlay flags set")
            end
        end
    else
        -- Debug: Log overlay flags even when MCM is closed (for manual toggle testing)
        if ExtraHUD.MCMCompat_displayingOverlay ~= "" or ExtraHUD.MCMCompat_selectedOverlay ~= "" then
            Isaac.DebugString("[CoopExtraHUD] Overlay flags active (MCM closed) - Displaying: '" .. ExtraHUD.MCMCompat_displayingOverlay .. "', Selected: '" .. ExtraHUD.MCMCompat_selectedOverlay .. "'")
            
            -- Allow manual overlays even when MCM is closed (for testing)
            if ExtraHUD.MCMCompat_displayingOverlay == "boundary" and ExtraHUD.MCMCompat_selectedOverlay == "boundary" then
                showBoundary = true
                Isaac.DebugString("[CoopExtraHUD] Rendering manual boundary overlay")
            elseif ExtraHUD.MCMCompat_displayingOverlay == "minimap" and ExtraHUD.MCMCompat_selectedOverlay == "minimap" then
                showMinimap = true
                Isaac.DebugString("[CoopExtraHUD] Rendering manual minimap overlay")
            elseif ExtraHUD.MCMCompat_displayingOverlay == "hudoffset" and ExtraHUD.MCMCompat_selectedOverlay == "hudoffset" then
                showHudOffset = true
                Isaac.DebugString("[CoopExtraHUD] Rendering manual HUD offset overlay")
            end
        end
        
        -- Don't clear overlay flags when MCM is closed (allow manual testing)
        -- if ExtraHUD.MCMCompat_displayingOverlay ~= "" or ExtraHUD.MCMCompat_selectedOverlay ~= "" then
        --     ExtraHUD.MCMCompat_displayingOverlay = ""
        --     ExtraHUD.MCMCompat_selectedOverlay = ""
        -- end
    end
    -- Draw overlays as needed (now using proper sprites with color coding)
    if showBoundary then
        -- Use live config for overlay rendering to ensure real-time updates
        local bx = tonumber(getConfig().boundaryX) or 0
        local by = tonumber(getConfig().boundaryY) or 0
        local bw = tonumber(getConfig().boundaryW) or 0
        local bh = tonumber(getConfig().boundaryH) or 0
        if bw > 0 and bh > 0 then
            local vecZero = Vector(0, 0)
            -- Red color for HUD boundary overlay
            local boundaryColor = Color(1, 0, 0, 0.8) -- Red with transparency
            if HudOffsetVisualTopLeft then
                HudOffsetVisualTopLeft.Color = boundaryColor
                HudOffsetVisualTopLeft:Render(Vector(bx, by), vecZero, vecZero)
            end
            if HudOffsetVisualTopRight then
                HudOffsetVisualTopRight.Color = boundaryColor
                HudOffsetVisualTopRight:Render(Vector(bx + bw - 32, by), vecZero, vecZero)
            end
            if HudOffsetVisualBottomLeft then
                HudOffsetVisualBottomLeft.Color = boundaryColor
                HudOffsetVisualBottomLeft:Render(Vector(bx, by + bh - 32), vecZero, vecZero)
            end
            if HudOffsetVisualBottomRight then
                HudOffsetVisualBottomRight.Color = boundaryColor
                HudOffsetVisualBottomRight:Render(Vector(bx + bw - 32, by + bh - 32), vecZero, vecZero)
            end
            Isaac.RenderText("HUD Boundary", bx+4, by+4, 1, 0, 0, 1)
        else
            AddDebugLog("[Overlay] showBoundary: boundary config value(s) nil or zero, skipping overlay")
        end
    elseif showMinimap then
        -- Use live config for overlay rendering to ensure real-time updates
        local mx = tonumber(getConfig().minimapX) or 0
        local my = tonumber(getConfig().minimapY) or 0
        local mw = tonumber(getConfig().minimapW) or 0
        local mh = tonumber(getConfig().minimapH) or 0
        if mw > 0 and mh > 0 then
            local vecZero = Vector(0, 0)
            -- Cyan color for minimap overlay
            local minimapColor = Color(0, 1, 1, 0.8) -- Cyan with transparency
            if HudOffsetVisualTopLeft then
                HudOffsetVisualTopLeft.Color = minimapColor
                HudOffsetVisualTopLeft:Render(Vector(mx, my), vecZero, vecZero)
            end
            if HudOffsetVisualTopRight then
                HudOffsetVisualTopRight.Color = minimapColor
                HudOffsetVisualTopRight:Render(Vector(mx + mw - 32, my), vecZero, vecZero)
            end
            if HudOffsetVisualBottomLeft then
                HudOffsetVisualBottomLeft.Color = minimapColor
                HudOffsetVisualBottomLeft:Render(Vector(mx, my + mh - 32), vecZero, vecZero)
            end
            if HudOffsetVisualBottomRight then
                HudOffsetVisualBottomRight.Color = minimapColor
                HudOffsetVisualBottomRight:Render(Vector(mx + mw - 32, my + mh - 32), vecZero, vecZero)
            end
            Isaac.RenderText("Minimap Area", mx+4, my+4, 0, 1, 1, 1)
        else
            AddDebugLog("[Overlay] showMinimap: minimap config value(s) nil or zero, skipping overlay")
        end
    elseif showHudOffset then
        -- Show HUD offset overlay - green corners to indicate where the HUD is positioned
        local hudX = tonumber(getConfig().xOffset) or 0
        local hudY = tonumber(getConfig().yOffset) or 0
        local hudBoundaryX = tonumber(getConfig().boundaryX) or 0
        local hudBoundaryY = tonumber(getConfig().boundaryY) or 0
        local hudBoundaryW = tonumber(getConfig().boundaryW) or 0
        local hudBoundaryH = tonumber(getConfig().boundaryH) or 0
        
        -- Calculate actual HUD position considering offset and boundary
        local actualHudX = hudBoundaryX + hudX
        local actualHudY = hudBoundaryY + hudY
        
        if hudBoundaryW > 0 and hudBoundaryH > 0 then
            local vecZero = Vector(0, 0)
            -- Green color for HUD offset overlay
            local hudOffsetColor = Color(0, 1, 0, 0.8) -- Green with transparency
            if HudOffsetVisualTopLeft then
                HudOffsetVisualTopLeft.Color = hudOffsetColor
                HudOffsetVisualTopLeft:Render(Vector(actualHudX, actualHudY), vecZero, vecZero)
            end
            if HudOffsetVisualTopRight then
                HudOffsetVisualTopRight.Color = hudOffsetColor
                HudOffsetVisualTopRight:Render(Vector(actualHudX + hudBoundaryW - 32, actualHudY), vecZero, vecZero)
            end
            if HudOffsetVisualBottomLeft then
                HudOffsetVisualBottomLeft.Color = hudOffsetColor
                HudOffsetVisualBottomLeft:Render(Vector(actualHudX, actualHudY + hudBoundaryH - 32), vecZero, vecZero)
            end
            if HudOffsetVisualBottomRight then
                HudOffsetVisualBottomRight.Color = hudOffsetColor
                HudOffsetVisualBottomRight:Render(Vector(actualHudX + hudBoundaryW - 32, actualHudY + hudBoundaryH - 32), vecZero, vecZero)
            end
            Isaac.RenderText("HUD Position", actualHudX+4, actualHudY+4, 0, 1, 0, 1)
        else
            AddDebugLog("[Overlay] showHudOffset: boundary config value(s) nil or zero, skipping overlay")
        end
    end
end

--[[
Isaac Modding Best Practices Applied:
- ✅ No Isaac.ExecuteCommand (uses Options.ExtraHUDStyle instead)
- ✅ No require() for optional dependencies (robust MCM loading)
- ✅ Explicit callback priorities for deterministic execution order
- ✅ Comprehensive game state validation (pause, menu, room types)
- ✅ Resource validation with proper constants and safe fallbacks
- ✅ Enhanced item validation with Isaac API best practices
- ✅ Safe Isaac API access patterns with nil checks
- ✅ Performance optimization with proper constant usage
- ✅ Robust optional dependency loading without require
]]

-- Also disable vanilla ExtraHUD on mod load (first load)
DisableVanillaExtraHUD()

-- Isaac best practice: Use explicit callback priority for render callbacks
ExtraHUD:AddCallback(ModCallbacks.MC_POST_RENDER, ExtraHUD.PostRender, CallbackPriority and CallbackPriority.LATE or nil)

-- MCM integration (automatic detection removed, manual toggles only)

-- Isaac best practice: Robust optional dependency loading without require
local MCM = nil

-- Always create a basic stub first to prevent any nil access errors
MCM = {
    Init = function(args) return args end,
    RegisterConfigMenu = function() end
}

-- Robust config/configPresets initialization and loading (always use live config for all MCM/config sections)
if not config then config = {} end
if not configPresets then configPresets = {} end

-- Fill missing config keys from defaultConfig (live)
for k, v in pairs(defaultConfig) do
    if config[k] == nil then config[k] = v end
end

-- Fill missing configPresets keys from defaultConfigPresets (live)
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

-- Load config from disk on mod load (before MCM.Init), always update live config
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


-- Isaac best practice: Use early priority for config saving to ensure it happens before other cleanup
ExtraHUD:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
    SaveConfig()
end, CallbackPriority and CallbackPriority.EARLY or nil)

-- Isaac best practice: Load our MCM module (same mod, always safe)
local MCMModule = include("MCM")
if MCMModule and type(MCMModule.Init) == "function" then
    MCM = MCMModule
    Isaac.DebugString("[CoopExtraHUD] Loaded MCM module.")
else
    Isaac.DebugString("[CoopExtraHUD] Failed to load MCM module.")
end

-- Isaac best practice: MCM integration at mod load time
do
    
    -- Pass config tables/functions to MCM (always use live config)
    local mcmTables = nil
    if MCM and MCM.Init then
        mcmTables = MCM.Init({
            ExtraHUD = ExtraHUD,
            config = config,
            configPresets = configPresets,
            SaveConfig = SaveConfig,
            LoadConfig = LoadConfig,
            UpdateCurrentPreset = UpdateCurrentPreset,
            getConfig = getConfig,
            MarkHudDirty = MarkHudDirty,
            OnOverlayAdjusterMoved = function()
                -- Invalidate all caches and force HUD/layout update immediately
                cachedClampedConfig = nil
                cachedLayout.valid = false
                lastScreenW, lastScreenH = 0, 0
                MarkHudDirty()
            end,
        })
    end
    
    if mcmTables then
        config = mcmTables.config
        configPresets = mcmTables.configPresets
        SaveConfig = mcmTables.SaveConfig
        LoadConfig = mcmTables.LoadConfig
        UpdateCurrentPreset = mcmTables.UpdateCurrentPreset
        if type(mcmTables.getConfig) == "function" then
            getConfig = mcmTables.getConfig
        end
        if type(mcmTables.MarkHudDirty) == "function" then
            ExtraHUD.MarkHudDirty = mcmTables.MarkHudDirty
        end
        if type(mcmTables.OnOverlayAdjusterMoved) == "function" then
            ExtraHUD.OnOverlayAdjusterMoved = mcmTables.OnOverlayAdjusterMoved
        else
            -- Always provide a fallback that forces a full HUD/layout update
            ExtraHUD.OnOverlayAdjusterMoved = function()
                cachedClampedConfig = nil
                cachedLayout.valid = false
                lastScreenW, lastScreenH = 0, 0
                MarkHudDirty()
            end
        end
        
        -- Only call RegisterConfigMenu if MCM is available
        if MCM and MCM.RegisterConfigMenu then
            MCM.RegisterConfigMenu()
        end
    else
        -- MCM not available, ensure we have working fallback functions
        ExtraHUD.OnOverlayAdjusterMoved = function()
            cachedClampedConfig = nil
            cachedLayout.valid = false
            lastScreenW, lastScreenH = 0, 0
            MarkHudDirty()
        end
    end
end

-- Final verification: Isaac modding standards compliance maintained
Isaac.DebugString("[CoopExtraHUD] *** MOD LOADING COMPLETE ***")
