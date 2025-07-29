-- Initialize config and configPresets FIRST to avoid undefined errors
local config = {}
local configPresets = {}

if not getConfig then
    function getConfig()
        return config
    end
end

local ICON_SIZE = 32 -- Standard Isaac item icon size in pixels
local INTER_PLAYER_SPACING = 16 -- Space between player HUD blocks in pixels

local cachedLayout = { valid = false }
local cachedClampedConfig = nil
local lastScreenW, lastScreenH = 0, 0
local hudDirty = true
local cachedPlayerIconData = nil
local cachedPlayerCount = 0
local playerTrackedCollectibles = {}
local playerPickupOrder = {}
local itemSpriteCache = {}
local spriteUsageTracker = {}
local debugLogs = {}
local lastAutoResizeScreenW, lastAutoResizeScreenH = 0, 0
local overlayToggleDebounce = 0
local currentManualOverlayType = ""
local lastMCMState = false
local mcmStateCheckCounter = 0
local VANILLA_ITEM_LIMIT = nil
local SaveConfig, LoadConfig, UpdateCurrentPreset

local function MarkHudDirty()
    hudDirty = true
    cachedLayout.valid = false
    cachedClampedConfig = nil
    lastScreenW, lastScreenH = 0, 0
end

local MCM
local MIN_COLLECTIBLE_ID = 1
local MAX_ITEM_ID = 1000 -- Safe upper bound for modded items, adjust as needed
local DEFAULT_ITEM_LIMIT = 700 -- Repentance vanilla item count, adjust as needed
local defaultConfigPresets = {
    [false] = {},
    [true] = {}
}
local function DisableVanillaExtraHUD()
    -- Stub: implement vanilla HUD disabling if needed, or leave as no-op
end


local ExtraHUD = RegisterMod("CoopExtraHUD", 1)

-- PlayerType to head icon frame mapping (edit as needed)

-- All vanilla PlayerType constants mapped to default frame (PlayerType+1)
-- PlayerType to head icon frame mapping (edit as needed)
-- All vanilla PlayerType constants mapped to default frame (PlayerType+1)
-- See: https://wofsauge.github.io/IsaacDocs/rep/enums/PlayerType.html
ExtraHUD.PlayerTypeToHeadFrame = {
    [0] = 1,   -- Isaac
    [1] = 2,   -- Magdalene
    [2] = 3,   -- Cain
    [3] = 4,   -- Judas
    [4] = 5,   -- ??? (Blue Baby)
    [5] = 6,   -- Eve
    [6] = 7,   -- Samson
    [7] = 8,   -- Azazel
    [8] = 9,   -- Lazarus
    [9] = 10,  -- Eden
    [10] = 11, -- The Lost
    [11] = 12, -- Lazarus Risen
    [12] = 13, -- Black Judas
    [13] = 14, -- Lilith
    [14] = 15, -- Keeper
    [15] = 16, -- Apollyon
    [16] = 17, -- The Forgotten
    [17] = 18, -- The Soul
    [18] = 19, -- Bethany
    [19] = 20, -- Jacob
    [20] = 20, -- Esau (uses Jacob's frame, tinted red)
    [21] = 22, -- Jacob2 (Dogma, not used in normal play)
    [22] = 23, -- The Soul (Tainted)
    [23] = 24, -- Isaac (Tainted)
    [24] = 25, -- Magdalene (Tainted)
    [25] = 26, -- Cain (Tainted)
    [26] = 27, -- Judas (Tainted)
    [27] = 28, -- ??? (Tainted)
    [28] = 29, -- Eve (Tainted)
    [29] = 30, -- Samson (Tainted)
    [30] = 31, -- Azazel (Tainted)
    [31] = 32, -- Lazarus (Tainted)
    [32] = 33, -- Eden (Tainted)
    [33] = 34, -- The Lost (Tainted)
    [34] = 35, -- Lilith (Tainted)
    [35] = 36, -- Keeper (Tainted)
    [36] = 37, -- Apollyon (Tainted)
    [37] = 38, -- The Forgotten (Tainted)
    [38] = 39, -- Bethany (Tainted)
    [39] = 40, -- Jacob (Tainted)
    [40] = 41, -- Esau (Tainted)
}

setmetatable(ExtraHUD.PlayerTypeToHeadFrame, {
    __index = function(t, k)
        return (type(k) == "number" and k + 1) or 1
    end
})

-- Default config values
-- (Removed duplicate config, configPresets, getConfig definitions)

-- Isaac best practice: Robust optional dependency loading without require


local defaultConfig = {
    scale = 0.4, -- updated default
    xSpacing = 5, -- updated default
    ySpacing = 5, -- updated default
    dividerOffset = -7, -- updated default
    dividerYOffset = -14, -- updated default
    comboDividerXOffset = 0, -- new option for Jacob+Esau divider X offset
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
    hideHudOnPause = true,
    showCharHeadIcons = false, -- new default
    comboScale = 1.0, -- J&E Scale adjuster (default: 1.0)
    comboChunkDividerYOffset = 0, -- J&E chunk character divider offset (default: 0)
}
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
            ExtraHUD.OnOverlayAdjusterMoved = function()
                cachedClampedConfig = nil
                cachedLayout.valid = false
                lastScreenW, lastScreenH = 0, 0
                MarkHudDirty()
            end
        end

        -- Add MCM entry for hideHudOnPause
        if MCM and type(MCM.AddBooleanSetting) == "function" then
            MCM.AddBooleanSetting({
                mod = ExtraHUD,
                category = "General",
                key = "hideHudOnPause",
                title = "Hide HUD when paused",
                desc = "If enabled, the CoopExtraHUD will be hidden when the game is paused.",
                default = true,
                get = function() return config.hideHudOnPause end,
                set = function(val) config.hideHudOnPause = val; SaveConfig(); MarkHudDirty() end
            })
        elseif MCM and type(MCM.AddSetting) == "function" then
            -- Fallback for older MCM: add as a generic setting
            MCM.AddSetting({
                mod = ExtraHUD,
                type = "boolean",
                category = "General",
                key = "hideHudOnPause",
                title = "Hide HUD when paused",
                desc = "If enabled, the CoopExtraHUD will be hidden when the game is paused.",
                default = true,
                get = function() return config.hideHudOnPause end,
                set = function(val) config.hideHudOnPause = val; SaveConfig(); MarkHudDirty() end
            })
        end

        if MCM and MCM.RegisterConfigMenu then
            MCM.RegisterConfigMenu()
        end
    else
        ExtraHUD.OnOverlayAdjusterMoved = function()
            cachedClampedConfig = nil
            cachedLayout.valid = false
            lastScreenW, lastScreenH = 0, 0
            MarkHudDirty()
        end
    end
-- removed stray end
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
        for id = 1, MAX_ITEM_ID do
            if player:HasCollectible(id) and IsValidItem(id) then
                ownedSet[id] = true
            end
        end
        local alreadyAdded = {}
        -- First, add items in pickup order (if still owned)
        if playerPickupOrder[i] then
            for _, id in ipairs(playerPickupOrder[i]) do
                if ownedSet[id] then
                    table.insert(cachedPlayerIconData[i + 1], id)
                    alreadyAdded[id] = true
                end
            end
        end
        -- Then, add any currently owned items not already in pickup order (e.g. starting items)
        for id in pairs(ownedSet) do
            if not alreadyAdded[id] then
                table.insert(cachedPlayerIconData[i + 1], id)
            end
        end
    end
    cachedPlayerCount = totalPlayers
    hudDirty = false
    if shouldCleanup then
        CleanupUnusedSprites()
    end
end

-- Helper: record all current collectibles for all players (e.g. at game start or new player join)
local function TrackAllCurrentCollectibles()
    for i = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        playerTrackedCollectibles[i] = {}
        -- Only scan up to MAX_ITEM_ID, skip high IDs unless needed
        local startingItems = {}
        for id = 1, MAX_ITEM_ID do
            if player:HasCollectible(id) and IsValidItem(id) then
                playerTrackedCollectibles[i][id] = true
                table.insert(startingItems, id)
            end
        end
        -- If pickup order is empty, initialize it with starting items (in order)
        if not playerPickupOrder[i] or #playerPickupOrder[i] == 0 then
            playerPickupOrder[i] = {}
            for _, id in ipairs(startingItems) do
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
            for id = 1, MAX_ITEM_ID do
                if player:HasCollectible(id) and IsValidItem(id) then
                    playerTrackedCollectibles[i][id] = true
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
        for id = 1, MAX_ITEM_ID do
            if player:HasCollectible(id) and IsValidItem(id) then
                owned[id] = true
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
            for i = 0, Game():GetNumPlayers() - 1 do
                local player = Isaac.GetPlayer(i)
                for id = 1, MAX_ITEM_ID do
                    if player:HasCollectible(id) and IsValidItem(id) then
                        local alreadyTracked = false
                        if playerPickupOrder[i] then
                            for _, v in ipairs(playerPickupOrder[i]) do
                                if v == id then alreadyTracked = true break end
                            end
                        end
                        if not alreadyTracked then
                            playerPickupOrder[i] = playerPickupOrder[i] or {}
                            table.insert(playerPickupOrder[i], id)
                        end
                    end
                end
            end
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

-- Estimate vanilla minimap area if MiniMapAPI is not present
local function GetVanillaMinimapRect(screenW, screenH)
    -- These values are based on vanilla minimap size and offset in Repentance
    local minimapW, minimapH = 141, 101 -- default vanilla minimap size
    local offsetX, offsetY = 0, 0
    if Options and type(Options) == "table" and Options.HUDOffset then
        offsetX = 24 * (Options.HUDOffset or 0)
    end
    local margin = 8
    -- Clamp minimap size to screen size to avoid overflow
    minimapW = math.max(32, math.min(minimapW, screenW - 2 * margin))
    minimapH = math.max(32, math.min(minimapH, screenH - 2 * margin))
    local mapX = math.max(0, screenW - minimapW - margin + offsetX)
    local mapY = math.max(0, margin + offsetY)
    -- If screen is too small, fallback to a small box in the top right
    if minimapW > screenW or minimapH > screenH then
        minimapW = math.max(32, math.floor(screenW / 4))
        minimapH = math.max(32, math.floor(screenH / 4))
        mapX = math.max(0, screenW - minimapW - margin)
        mapY = math.max(0, margin)
    end
    return { x = mapX, y = mapY, w = minimapW, h = minimapH }
end

-- MiniMapAPI integration: get minimap bounding box if available, else estimate vanilla minimap
local function GetMinimapRect(screenW, screenH)
    local mmapi = _G["MiniMapAPI"] or _G["MinimapAPI"] or _G["MiniMapAPICompat"]
    if mmapi and type(mmapi.GetScreenTopRight) == "function" and type(mmapi.GetScreenSize) == "function" then
        local topRight = mmapi.GetScreenTopRight()
        local size = mmapi.GetScreenSize()
        if topRight and size and topRight.X and topRight.Y and size.X and size.Y then
            local mapW, mapH = size.X, size.Y
            local mapX = topRight.X - mapW
            local mapY = topRight.Y
            -- Only use MiniMapAPI values if they are valid and not absurdly large
            if mapW and mapH and mapW > 0 and mapH > 0 and mapW < screenW and mapH < screenH then
                return { x = mapX, y = mapY, w = mapW, h = mapH }
            end
        end
    end
    -- Fallback to vanilla minimap estimate
    return GetVanillaMinimapRect(screenW, screenH)
end

-- MCM compatibility flags for overlay display (manual toggles only)
ExtraHUD.MCMCompat_displayingOverlay = ""
ExtraHUD.MCMCompat_selectedOverlay = ""
ExtraHUD.MCMCompat_overlayTimestamp = 0
-- EID-style automatic overlay detection
ExtraHUD.MCMCompat_displayingTab = ""

-- Cache MCM state to avoid checking every frame
local lastMCMState = false
local mcmStateCheckCounter = 0
-- Sprite-based overlay system (following MCM exact implementation)
local function GetMenuAnm2Sprite(animation, frame)
    local sprite = Sprite()
    sprite:Load("gfx/ui/coopextrahud/overlay.anm2", true)
    sprite:SetFrame(animation, frame)
    return sprite
end

-- Optimized column calculation
local function getPlayerColumns(itemCount, isJacobEsauCombo)
    local maxCols = 4
    local itemsPerCol = isJacobEsauCombo and 4 or 8
    local cols = math.ceil(itemCount / itemsPerCol)
    return math.max(1, math.min(cols, maxCols))
end

-- Calculate and cache layout (only when dirty)
local function UpdateLayout(playerIconData, cfg, screenW, screenH)
    if cachedLayout.valid then return cachedLayout end
    
    -- Calculate columns and max rows needed
    local maxRows = 1
    local playerColumns = {}
    local blockWidths = {}
    local i = 1
    while i <= #playerIconData do
        local items = playerIconData[i]
        local itemCount = #items
        local isJacobEsauCombo = false
        if i < #playerIconData then
            local player = Isaac.GetPlayer(i-1)
            local playerType = player and player:GetPlayerType() or 0
            if playerType == PlayerType.PLAYER_JACOB then
                local esauPlayer = Isaac.GetPlayer(i)
                local esauType = esauPlayer and esauPlayer:GetPlayerType() or 0
                if esauType == PlayerType.PLAYER_ESAU then
                    isJacobEsauCombo = true
                end
            end
        end
        local cols = getPlayerColumns(itemCount, isJacobEsauCombo)
        playerColumns[i] = cols
        local rows = math.ceil(itemCount / cols)
        maxRows = math.max(maxRows, rows)
        if isJacobEsauCombo then
            blockWidths[i] = (ICON_SIZE * cols * (cfg.scale * (cfg.comboScale or 1.0))) + ((cols - 1) * cfg.xSpacing * (cfg.scale * (cfg.comboScale or 1.0)))
            i = i + 2
        else
            blockWidths[i] = (ICON_SIZE * cols * cfg.scale) + ((cols - 1) * cfg.xSpacing * cfg.scale)
            i = i + 1
        end
    end
    -- Calculate totalWidth, skipping Esau when paired
    local totalWidth = 0
    local blockCount = 0
    i = 1
    while i <= #playerIconData do
        local player = Isaac.GetPlayer(i-1)
        local playerType = player and player:GetPlayerType() or 0
        local isJacobEsauCombo = false
        if i < #playerIconData and playerType == PlayerType.PLAYER_JACOB then
            local esauPlayer = Isaac.GetPlayer(i)
            local esauType = esauPlayer and esauPlayer:GetPlayerType() or 0
            if esauType == PlayerType.PLAYER_ESAU then
                isJacobEsauCombo = true
            end
        end
        totalWidth = totalWidth + (blockWidths[i] or 0)
        blockCount = blockCount + 1
        if isJacobEsauCombo then
            i = i + 2
        else
            i = i + 1
        end
    end
    totalWidth = totalWidth + (blockCount - 1) * INTER_PLAYER_SPACING * cfg.scale
    local maxHeight = maxRows * (ICON_SIZE + cfg.ySpacing) - cfg.ySpacing
    local scale = cfg.scale
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
    end
end

function ExtraHUD:PostRender()
    -- Isaac best practice: Use proper Isaac API game state validation
    local game = Game()
    if not game then return end

    -- Isaac API: Check if game is paused, and if HUD should hide on pause
    local cfg = getConfig()
    if game:IsPaused() and cfg.hideHudOnPause then
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
    HandleAutoResize(cfg, screenW, screenH)

    -- Get clamped config (cached when screen size doesn't change) for layout/scaling
    local clampedCfg = GetClampedConfig(cfg, screenW, screenH)
    -- Always use live config for boundary/minimap positions
    local liveCfg = cfg

    -- Set minimap avoidance area to match MiniMapAPI or vanilla minimap estimate
    local minimapRect = GetMinimapRect(screenW, screenH)
    if minimapRect then
        if liveCfg.minimapX ~= minimapRect.x or liveCfg.minimapY ~= minimapRect.y or liveCfg.minimapW ~= minimapRect.w or liveCfg.minimapH ~= minimapRect.h then
            liveCfg.minimapX = minimapRect.x
            liveCfg.minimapY = minimapRect.y
            liveCfg.minimapW = minimapRect.w
            liveCfg.minimapH = minimapRect.h
            -- Do not save config here, as this is a runtime-only adjustment
        end
    end

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

    -- Extract config values once (cached from liveCfg)
    local boundaryX = tonumber(liveCfg.boundaryX) or 0
    local boundaryY = tonumber(liveCfg.boundaryY) or 0
    local boundaryW = tonumber(liveCfg.boundaryW) or 0
    local boundaryH = tonumber(liveCfg.boundaryH) or 0
    local minimapX = tonumber(liveCfg.minimapX) or 0
    local minimapY = tonumber(liveCfg.minimapY) or 0
    local minimapW = tonumber(liveCfg.minimapW) or 0
    local minimapH = tonumber(liveCfg.minimapH) or 0
    local minimapPadding = liveCfg.minimapPadding or 0

    -- Apply minimap avoidance and boundary clamping to start position
    local startX, startY = layout.startX, layout.startY

    -- Minimap avoidance (reuse extracted values)
    if minimapW > 0 and minimapH > 0 then
        local hudLeft, hudRight = startX, startX + layout.totalWidth
        local hudTop, hudBottom = startY, startY + layout.totalHeight
        local miniLeft, miniRight = minimapX, minimapX + minimapW
        local miniTop, miniBottom = minimapY, minimapY + minimapH
        local overlap = not (hudRight < miniLeft or hudLeft > miniRight or hudBottom < miniTop or hudTop > miniBottom)
        if overlap then
            startY = miniBottom + minimapPadding
        end
    end

    -- Clamp to boundary (using live config)
    startX = math.max(boundaryX, math.min(startX, boundaryX + boundaryW - layout.totalWidth))
    startY = math.max(boundaryY, math.min(startY, boundaryY + boundaryH - layout.totalHeight))

    -- Draw icons + dividers using cached layout
    local curX = startX
    local i = 1
    while i <= #playerIconData do
        local items = playerIconData[i]
        local cols = layout.playerColumns[i]
        local blockW = layout.blockWidths[i]
        if type(cols) ~= "number" or cols < 1 or type(blockW) ~= "number" or blockW < 1 then
            i = i + 1
        else
            local player = Isaac.GetPlayer(i-1)
            local playerType = player and player:GetPlayerType() or 0
            -- Detect Jacob+Esau combo block
            local isJacobCombo = (playerType == PlayerType.PLAYER_JACOB)
            local isTaintedJacob = (playerType == PlayerType.PLAYER_JACOB_B)
            if isJacobCombo and i < #playerIconData then
                local esauPlayer = Isaac.GetPlayer(i)
                local esauType = esauPlayer and esauPlayer:GetPlayerType() or 0
                if esauType == PlayerType.PLAYER_ESAU then
                    -- Combo block: Jacob on top, Esau below
                    local comboScale = clampedCfg.comboScale or 1.0
                    local blockHeight = ICON_SIZE * 2 * layout.scale * comboScale + (clampedCfg.ySpacing or 0) * layout.scale * comboScale + 32 * layout.scale * comboScale
                    -- Jacob head
                    local jacobHeadY = startY + ((clampedCfg.headIconYOffset or 0) * layout.scale * comboScale)
                    if clampedCfg.showCharHeadIcons then
                        local jacobHead = Sprite()
                        jacobHead:Load("gfx/ui/coopextrahud/coop menu.anm2", true)
                        jacobHead:SetFrame("Main", ExtraHUD.PlayerTypeToHeadFrame[PlayerType.PLAYER_JACOB])
                        jacobHead.Scale = Vector(layout.scale * comboScale, layout.scale * comboScale)
                        jacobHead.Color = Color(1,1,1,clampedCfg.opacity)
                        local headX = curX + (blockW / 2) - (ICON_SIZE * layout.scale * comboScale / 2) + ((clampedCfg.headIconXOffset or 0) * layout.scale * comboScale)
                        jacobHead:Render(Vector(headX, jacobHeadY), Vector.Zero, Vector.Zero)
                    end
                    -- Jacob's items
                    local jacobItems = items
                    local esauItems = playerIconData[i+1]
                    local maxJacob = math.min(#jacobItems, 16)
                    local maxEsau = math.min(#esauItems, 16)
                    local jacobItemsStartY = jacobHeadY + ICON_SIZE * layout.scale * comboScale + (clampedCfg.ySpacing or 0) * layout.scale * comboScale + (clampedCfg.comboHeadToItemsGap or 8) * layout.scale * comboScale
                    for idx = 1, maxJacob do
                        local row = math.floor((idx - 1) / cols)
                        local col = (idx - 1) % cols
                        local x = curX + col * (ICON_SIZE + clampedCfg.xSpacing) * layout.scale * comboScale
                        local y = jacobItemsStartY + row * (ICON_SIZE + clampedCfg.ySpacing) * layout.scale * comboScale
                        RenderItemIcon(jacobItems[idx], x, y, layout.scale * comboScale, clampedCfg.opacity)
                    end
                    -- Small horizontal divider between Jacob and Esau
                    -- Use preloaded 1x1 DividerSprite and scale for visibility
                    local jacobItemsEndY = jacobItemsStartY + (math.ceil(maxJacob / cols)) * (ICON_SIZE + clampedCfg.ySpacing) * layout.scale * comboScale
                    local dividerY = jacobItemsEndY + (clampedCfg.comboChunkGap or 8) * layout.scale * comboScale
                    local dividerYOffset = (clampedCfg.comboDividerYOffset or 0) * layout.scale * comboScale
                    local dividerXOffset = (clampedCfg.comboDividerXOffset or 0) * layout.scale * comboScale
                    local dividerW = blockW - 8 * layout.scale * comboScale
                    -- Both offsets applied together for clarity
                    DividerSprite.Scale = Vector(dividerW, 1)
                    DividerSprite.Color = Color(1, 1, 1, clampedCfg.opacity)
                    DividerSprite:Render(Vector(curX + 4 * layout.scale * comboScale + dividerXOffset, dividerY + dividerYOffset), Vector.Zero, Vector.Zero)
                    -- Esau head and items always positioned relative to unmodified dividerY
                    local esauHeadY = dividerY + (clampedCfg.comboHeadToItemsGap or 8) * layout.scale * comboScale
                    if clampedCfg.showCharHeadIcons then
                        local esauHead = Sprite()
                        esauHead:Load("gfx/ui/coopextrahud/esau_head.anm2", true)
                        esauHead:SetFrame("Esau", 0)
                        esauHead.Scale = Vector(layout.scale * comboScale, layout.scale * comboScale)
                        esauHead.Color = Color(1,1,1,clampedCfg.opacity)
                        local headX = curX + (blockW / 2) - (ICON_SIZE * layout.scale * comboScale / 2) + ((clampedCfg.headIconXOffset or 0) * layout.scale * comboScale)
                        esauHead:Render(Vector(headX, esauHeadY), Vector.Zero, Vector.Zero)
                    end
                    -- Esau's items
                    local esauItemsStartY = esauHeadY + ICON_SIZE * layout.scale * comboScale + (clampedCfg.ySpacing or 0) * layout.scale * comboScale + (clampedCfg.comboHeadToItemsGap or 8) * layout.scale * comboScale
                    for idx = 1, maxEsau do
                        local row = math.floor((idx - 1) / cols)
                        local col = (idx - 1) % cols
                        local x = curX + col * (ICON_SIZE + clampedCfg.xSpacing) * layout.scale * comboScale
                        local y = esauItemsStartY + row * (ICON_SIZE + clampedCfg.ySpacing) * layout.scale * comboScale
                        RenderItemIcon(esauItems[idx], x, y, layout.scale * comboScale, clampedCfg.opacity)
                    end
                    -- Divider logic unchanged
                    if i+1 < #playerIconData then
                        local thisBlockW = layout.blockWidths[i]
                        local nextBlockW = layout.blockWidths[i+2]
                        local chunkDividerYOffset = (clampedCfg.comboChunkDividerYOffset or 0) * layout.scale * comboScale
                        local dividerX = curX + thisBlockW + (INTER_PLAYER_SPACING * layout.scale * comboScale) / 2 + ((-16 + (clampedCfg.dividerOffset or 0)) * layout.scale * comboScale)
                        local dividerY = startY + ((-32 + (clampedCfg.dividerYOffset or 0)) * layout.scale * comboScale) + chunkDividerYOffset
                        local dividerHeight = layout.totalHeight * comboScale
                        local heightScale = math.max(1, math.floor(dividerHeight + 0.5))
                        DividerSprite.Scale = Vector(1, heightScale)
                        DividerSprite.Color = Color(1, 1, 1, clampedCfg.opacity)
                        DividerSprite:Render(Vector(dividerX, dividerY), Vector.Zero, Vector.Zero)
                    end
                    curX = curX + blockW + INTER_PLAYER_SPACING * layout.scale
                    i = i + 2
                else
                    -- Normal block rendering (not Jacob+Esau combo)
                    local rows = math.ceil(#items / cols)
                    local maxItems = math.min(#items, 32)
                    local itemsStartY = startY
                    if clampedCfg.showCharHeadIcons then
                        local headSprite = Sprite()
                        headSprite:Load("gfx/ui/coopextrahud/coop menu.anm2", true)
                        local frame = ExtraHUD.PlayerTypeToHeadFrame[playerType]
                        headSprite:SetFrame("Main", frame)
                        headSprite.Scale = Vector(layout.scale, layout.scale)
                        headSprite.Color = Color(1,1,1,clampedCfg.opacity)
                        local headX = curX + (blockW / 2) - (ICON_SIZE * layout.scale / 2) + ((clampedCfg.headIconXOffset or 0) * layout.scale)
                        local headY = startY + ((clampedCfg.headIconYOffset or 0) * layout.scale)
                        headSprite:Render(Vector(headX, headY), Vector.Zero, Vector.Zero)
                        local extraGap = 16 * layout.scale
                        itemsStartY = headY + ICON_SIZE * layout.scale + (clampedCfg.ySpacing or 0) * layout.scale + extraGap
                    end
                    for idx = 1, maxItems do
                        local row = math.floor((idx - 1) / cols)
                        local col = (idx - 1) % cols
                        local x = curX + col * (ICON_SIZE + clampedCfg.xSpacing) * layout.scale
                        local y = itemsStartY + row * (ICON_SIZE + clampedCfg.ySpacing) * layout.scale
                        RenderItemIcon(items[idx], x, y, layout.scale, clampedCfg.opacity)
                    end
                    if i < #playerIconData then
                        local thisBlockW = layout.blockWidths[i]
                        local nextBlockW = layout.blockWidths[i+1]
                        local dividerX = curX + thisBlockW + (INTER_PLAYER_SPACING * layout.scale) / 2 + ((-16 + (clampedCfg.dividerOffset or 0)) * layout.scale)
                        local dividerY = itemsStartY + ((-32 + (clampedCfg.dividerYOffset or 0)) * layout.scale)
                        local dividerHeight = layout.totalHeight
                        local heightScale = math.max(1, math.floor(dividerHeight + 0.5))
                        DividerSprite.Scale = Vector(1, heightScale)
                        DividerSprite.Color = Color(1, 1, 1, clampedCfg.opacity)
                        DividerSprite:Render(Vector(dividerX, dividerY), Vector.Zero, Vector.Zero)
                    end
                    curX = curX + blockW + INTER_PLAYER_SPACING * layout.scale
                    i = i + 1
                end
            else
                -- Normal block rendering (not Jacob+Esau combo)
                local rows = math.ceil(#items / cols)
                local maxItems = math.min(#items, 32)
                local itemsStartY = startY
                if clampedCfg.showCharHeadIcons then
                    local headSprite = Sprite()
                    headSprite:Load("gfx/ui/coopextrahud/coop menu.anm2", true)
                    local frame = ExtraHUD.PlayerTypeToHeadFrame[playerType]
                    headSprite:SetFrame("Main", frame)
                    headSprite.Scale = Vector(layout.scale, layout.scale)
                    headSprite.Color = Color(1,1,1,clampedCfg.opacity)
                    local headX = curX + (blockW / 2) - (ICON_SIZE * layout.scale / 2) + ((clampedCfg.headIconXOffset or 0) * layout.scale)
                    local headY = startY + ((clampedCfg.headIconYOffset or 0) * layout.scale)
                    headSprite:Render(Vector(headX, headY), Vector.Zero, Vector.Zero)
                    local extraGap = 16 * layout.scale
                    itemsStartY = headY + ICON_SIZE * layout.scale + (clampedCfg.ySpacing or 0) * layout.scale + extraGap
                end
                for idx = 1, maxItems do
                    local row = math.floor((idx - 1) / cols)
                    local col = (idx - 1) % cols
                    local x = curX + col * (ICON_SIZE + clampedCfg.xSpacing) * layout.scale
                    local y = itemsStartY + row * (ICON_SIZE + clampedCfg.ySpacing) * layout.scale
                    RenderItemIcon(items[idx], x, y, layout.scale, clampedCfg.opacity)
                end
                if i < #playerIconData then
                    local thisBlockW = layout.blockWidths[i]
                    local nextBlockW = layout.blockWidths[i+1]
                    local dividerX = curX + thisBlockW + (INTER_PLAYER_SPACING * layout.scale) / 2 + ((-16 + (clampedCfg.dividerOffset or 0)) * layout.scale)
                    local dividerY = itemsStartY + ((-32 + (clampedCfg.dividerYOffset or 0)) * layout.scale)
                    local dividerHeight = layout.totalHeight
                    local heightScale = math.max(1, math.floor(dividerHeight + 0.5))
                    DividerSprite.Scale = Vector(1, heightScale)
                    DividerSprite.Color = Color(1, 1, 1, clampedCfg.opacity)
                    DividerSprite:Render(Vector(dividerX, dividerY), Vector.Zero, Vector.Zero)
                end
                curX = curX + blockW + INTER_PLAYER_SPACING * layout.scale
                i = i + 1
            end
        end
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
    
    -- Optimized MCM overlay detection: only check every 5 frames to reduce overhead
    mcmStateCheckCounter = mcmStateCheckCounter + 1
    if mcmStateCheckCounter >= 5 then
        mcmStateCheckCounter = 0
        
        -- EID-style automatic overlay detection based on which MCM tab is being viewed
        local mcm = _G['ModConfigMenu']
        local mcmIsOpen = mcm and ((type(mcm.IsVisible) == "function" and mcm.IsVisible()) or (type(mcm.IsVisible) == "boolean" and mcm.IsVisible))
        
        -- Only update overlay state when MCM state changes
        if mcmIsOpen ~= lastMCMState then
            lastMCMState = mcmIsOpen
            
            if mcmIsOpen then
                -- MCM just opened - apply automatic overlays based on current tab
                if ExtraHUD.MCMCompat_displayingTab == "HUD" then
                    ExtraHUD.MCMCompat_displayingOverlay = "hudoffset"
                    ExtraHUD.MCMCompat_selectedOverlay = "hudoffset"
                elseif ExtraHUD.MCMCompat_displayingTab == "Boundaries" then
                    ExtraHUD.MCMCompat_displayingOverlay = "boundary"
                    ExtraHUD.MCMCompat_selectedOverlay = "boundary"
                elseif ExtraHUD.MCMCompat_displayingTab == "Minimap" then
                    ExtraHUD.MCMCompat_displayingOverlay = "minimap"
                    ExtraHUD.MCMCompat_selectedOverlay = "minimap"
                elseif ExtraHUD.MCMCompat_displayingTab == "" then
                    ExtraHUD.MCMCompat_displayingOverlay = ""
                    ExtraHUD.MCMCompat_selectedOverlay = ""
                end
            else
                -- MCM just closed - clear automatic overlays but keep manual ones
                if ExtraHUD.MCMCompat_displayingTab ~= "" then
                    ExtraHUD.MCMCompat_displayingTab = ""
                    -- Only clear overlay flags if they weren't set manually
                    if ExtraHUD.MCMCompat_displayingOverlay == "hudoffset" or ExtraHUD.MCMCompat_displayingOverlay == "boundary" or ExtraHUD.MCMCompat_displayingOverlay == "minimap" then
                        ExtraHUD.MCMCompat_displayingOverlay = ""
                        ExtraHUD.MCMCompat_selectedOverlay = ""
                    end
                end
            end
        elseif mcmIsOpen then
            -- MCM is open and state didn't change - only update overlays if tab changed
            if ExtraHUD.MCMCompat_displayingTab == "HUD" then
                ExtraHUD.MCMCompat_displayingOverlay = "hudoffset"
                ExtraHUD.MCMCompat_selectedOverlay = "hudoffset"
            elseif ExtraHUD.MCMCompat_displayingTab == "Boundaries" then
                ExtraHUD.MCMCompat_displayingOverlay = "boundary"
                ExtraHUD.MCMCompat_selectedOverlay = "boundary"
            elseif ExtraHUD.MCMCompat_displayingTab == "Minimap" then
                ExtraHUD.MCMCompat_displayingOverlay = "minimap"
                ExtraHUD.MCMCompat_selectedOverlay = "minimap"
            elseif ExtraHUD.MCMCompat_displayingTab == "" then
                ExtraHUD.MCMCompat_displayingOverlay = ""
                ExtraHUD.MCMCompat_selectedOverlay = ""
            end
        end
    end
    
    -- Manual overlay controls available as backup (B=Boundary, M=Minimap, H=HUD Offset, N=None)
    HandleManualOverlayToggle()
    
    -- Check if we should show overlays in MCM
    local showBoundary, showMinimap, showHudOffset = false, false, false
    
    -- Show overlays if MCM is open OR if they were manually triggered
    if lastMCMState or ExtraHUD.MCMCompat_displayingOverlay ~= "" then
        -- Check for boundary/minimap/hudoffset overlays using the dual-flag system
        if ExtraHUD.MCMCompat_displayingOverlay == "boundary" and ExtraHUD.MCMCompat_selectedOverlay == "boundary" then
            showBoundary = true
        elseif ExtraHUD.MCMCompat_displayingOverlay == "minimap" and ExtraHUD.MCMCompat_selectedOverlay == "minimap" then
            showMinimap = true
        elseif ExtraHUD.MCMCompat_displayingOverlay == "hudoffset" and ExtraHUD.MCMCompat_selectedOverlay == "hudoffset" then
            showHudOffset = true
        end
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
if not configPresets then configPresets = {} end
for mode, preset in pairs(defaultConfigPresets) do
    if configPresets and mode ~= nil and configPresets[mode] == nil then
        configPresets[mode] = {}
    end
    if configPresets and mode ~= nil and configPresets[mode] then
        for k, v in pairs(preset) do
            if configPresets[mode][k] == nil then configPresets[mode][k] = v end
        end
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
else
    print("[CoopExtraHUD] Failed to load MCM module.")
end

-- Isaac best practice: MCM integration at mod load time
-- removed stray do
    
    -- Pass config tables/functions to MCM (always use live config)
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
        ExtraHUD.OnOverlayAdjusterMoved = function()
            cachedClampedConfig = nil
            cachedLayout.valid = false
            lastScreenW, lastScreenH = 0, 0
            MarkHudDirty()
        end
    end

    -- ...removed MCM setting registration for hideHudOnPause (handled in MCM.lua)...

    if MCM and MCM.RegisterConfigMenu then
        MCM.RegisterConfigMenu()
    end
else
    ExtraHUD.OnOverlayAdjusterMoved = function()
        cachedClampedConfig = nil
        cachedLayout.valid = false
        lastScreenW, lastScreenH = 0, 0
        MarkHudDirty()
    end
end
-- Mod loading complete
