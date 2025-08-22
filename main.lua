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
local hudDirty = true
local cachedPlayerIconData = nil
local cachedPlayerCount = 0
local playerTrackedCollectibles = {}
local playerPickupOrder = {}
local itemSpriteCache = {}
local spriteUsageTracker = {}

-- Character head sprite cache to prevent memory leaks from creating sprites every frame
local characterHeadSpriteCache = {}

local lastAutoResizeScreenW, lastAutoResizeScreenH = 0, 0
local overlayToggleDebounce = 0
local currentManualOverlayType = ""
local lastMCMState = false
local lastDisplayingTab = ""
local VANILLA_ITEM_LIMIT = nil
local SaveConfig, LoadConfig, UpdateCurrentPreset
local mcmTables = nil -- MCM integration variable

local function MarkHudDirty()
    hudDirty = true
    cachedLayout.valid = false
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
        -- Use frame 0 as placeholder for modded characters (question mark head)
        return (type(k) == "number" and 0) or 1
    end
})

-- Default config values
-- (Removed duplicate config, configPresets, getConfig definitions)

-- Isaac best practice: Robust optional dependency loading without require


local defaultConfig = {
    scale = 0.32, -- updated from user's optimized settings
    xSpacing = 0, -- updated default
    ySpacing = 0, -- updated default
    dividerOffset = 0, -- updated default
    dividerYOffset = 0, -- updated default
    comboDividerXOffset = 0, -- zeroed since positioning now handled by baseGap calculation
    comboDividerYOffset = 0, -- zeroed since positioning now handled by baseGap calculation
    xOffset = 0, -- updated default
    yOffset = 0, -- updated default
    opacity = 0.6, -- updated default
    mapYOffset = 100,
    hudMode = true,
    boundaryX = 284, -- updated from user's optimized settings
    boundaryY = 50, -- updated from user's optimized settings
    boundaryW = 196, -- updated from user's optimized settings
    boundaryH = 170, -- updated from user's optimized settings
    minimapX = 331, -- updated from user's optimized settings
    minimapY = 8, -- updated from user's optimized settings
    minimapW = 141, -- updated default
    minimapH = 101, -- updated default
    minimapPadding = 2,
    alwaysShowOverlayInMCM = false,
    hideHudOnPause = false, -- updated from user's optimized settings
    showCharHeadIcons = true, -- new default
    itemLayoutMode = "2x2_grid", -- updated from user's optimized settings
    comboScale = 1.0, -- updated from user's optimized settings
    comboChunkGap = -20, -- updated from user's optimized settings
    comboChunkDividerYOffset = 0, -- zeroed since positioning now handled by baseGap calculation
    comboHeadToItemsGap = 20, -- updated from user's optimized settings
    autoAdjustOnResize = true, -- updated from user's optimized settings
    debugOverlay = false, -- updated from user's optimized settings
    disableVanillaExtraHUD = true, -- updated from user's optimized settings
    maxItemsPerPlayer = 32, -- updated from user's optimized settings
    moddedItemScanLimit = 1000, -- updated from user's optimized settings
    headIconXOffset = 0, -- updated from user's optimized settings
    headIconYOffset = 0, -- updated from user's optimized settings
    iconOffsetX = 1, -- updated from user's optimized settings
    iconOffsetY = 24, -- updated from user's optimized settings
    dividerXOffset = 0, -- updated from user's optimized settings
    horizontalDividerXOffset = 0, -- updated from user's optimized settings
    horizontalDividerYOffset = 0, -- updated from user's optimized settings
}

-- Isaac best practice: Load our MCM module (same mod, always safe)
local MCMModule = include("MCM")
if MCMModule and type(MCMModule.Init) == "function" then
    MCM = MCMModule
else
    print("[CoopExtraHUD] Failed to load MCM module.")
end

-- Initialize config with default values before MCM.Init
for k, v in pairs(defaultConfig) do
    if config[k] == nil then config[k] = v end
end

-- Initialize configPresets with default values
if not configPresets[false] then configPresets[false] = {} end
if not configPresets[true] then configPresets[true] = {} end

-- Define config functions before MCM.Init (they need SerializeAllConfigs and DeserializeAllConfigs)
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
local function SaveConfigLocal()
    if config then
        ExtraHUD:SaveData(SerializeAllConfigs())
        MarkHudDirty()
    end
end

local function LoadConfigLocal()
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

local function UpdateCurrentPresetLocal()
    -- Optionally update configPresets based on current config/hudMode
    -- (implement as needed)
end

-- Assign these before MCM.Init
SaveConfig = SaveConfigLocal
LoadConfig = LoadConfigLocal
UpdateCurrentPreset = UpdateCurrentPresetLocal

    -- Pass config tables/functions to MCM (always use live config)
    if MCM and MCM.Init then
        local initResult = MCM.Init({
            ExtraHUD = ExtraHUD,
            config = config,
            configPresets = configPresets,
            SaveConfig = SaveConfig,
            LoadConfig = LoadConfig,
            UpdateCurrentPreset = UpdateCurrentPreset,
            getConfig = getConfig,
            MarkHudDirty = MarkHudDirty,
            OnOverlayAdjusterMoved = function()
                cachedLayout.valid = false
                MarkHudDirty()
            end,
        })
        mcmTables = initResult
    else
        print("[CoopExtraHUD] MCM.Init not available")
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
                cachedLayout.valid = false
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
            cachedLayout.valid = false
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
    if not collectible then return false end
    
    -- Basic validation
    local hasValidGfx = collectible.GfxFileName ~= nil and 
                       collectible.GfxFileName ~= "" and
                       collectible.GfxFileName ~= "gfx/items/collectibles/questionmark.png"
    
    return hasValidGfx
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

-- Isaac best practice: Cache character head sprites to prevent memory leaks
local function GetCharacterHeadSprite(playerType, isEsau)
    local cacheKey = isEsau and "esau" or tostring(playerType)
    
    if not characterHeadSpriteCache[cacheKey] then
        local sprite = Sprite()
        
        -- Repentogon enhancement: Try to use modded character's official coop menu sprite
        if REPENTOGON and EntityConfig and not isEsau then
            local playerConfig = EntityConfig.GetPlayer(playerType)
            if playerConfig then
                local coopSprite = playerConfig:GetModdedCoopMenuSprite()
                if coopSprite then
                    -- Create our own sprite instance to avoid modifying the shared mod sprite
                    local characterName = playerConfig:GetName()
                    if characterName and characterName ~= "" then
                        -- Load the same anm2 file as the modded sprite but in our own instance
                        sprite:Load(coopSprite:GetFilename(), true)
                        sprite:Play(characterName, true)
                        sprite:LoadGraphics()
                        characterHeadSpriteCache[cacheKey] = sprite
                        return sprite
                    end
                end
            end
        end
        
        -- Original fallback system (always works, with or without Repentogon)
        if isEsau then
            -- Special handling for Esau
            sprite:Load("gfx/ui/coopextrahud/esau_head.anm2", true)
            sprite:SetFrame("Esau", 0)
        else
            -- Regular character heads
            sprite:Load("gfx/ui/coopextrahud/coop menu.anm2", true)
            local frame = ExtraHUD.PlayerTypeToHeadFrame[playerType] or 0 -- Frame 0 for unknown characters
            sprite:SetFrame("Main", frame)
        end
        
        sprite:LoadGraphics()
        characterHeadSpriteCache[cacheKey] = sprite
    end
    
    return characterHeadSpriteCache[cacheKey]
end

-- Clean up unused sprites to prevent memory leaks (updated for modded items)
local function CleanupUnusedSprites()
    -- Initialize constants if not already done
    InitializeConstants()
    
    -- Only run cleanup if we have a significant number of cached sprites
    local cacheSize = 0
    for _ in pairs(itemSpriteCache) do
        cacheSize = cacheSize + 1
    end
    
    -- Don't cleanup if cache is small (avoid frequent cleanup overhead)
    if cacheSize < 50 then
        return
    end
    
    -- Build set of currently owned items across all players
    local ownedItems = {}
    local game = Game()
    if not game then return end
    
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player then
            -- Check vanilla items (using safe range)
            local maxItem = VANILLA_ITEM_LIMIT or DEFAULT_ITEM_LIMIT
            for id = MIN_COLLECTIBLE_ID, maxItem do
                if player:HasCollectible(id) then
                    ownedItems[id] = true
                end
            end
            
            -- Also check modded items by scanning the cache itself
            -- This ensures we don't accidentally remove sprites for modded items
            for itemId, _ in pairs(itemSpriteCache) do
                if itemId > maxItem and player:HasCollectible(itemId) then
                    ownedItems[itemId] = true
                end
            end
        end
    end
    
    -- Remove sprites for items no longer owned by any player
    local removedCount = 0
    for itemId, _ in pairs(itemSpriteCache) do
        if not ownedItems[itemId] then
            itemSpriteCache[itemId] = nil
            if spriteUsageTracker then
                spriteUsageTracker[itemId] = nil
            end
            removedCount = removedCount + 1
        end
    end
    
    -- Cleanup complete (removed unused item sprites)
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
end

-- Expose MarkHudDirty for MCM to call when config changes
ExtraHUD.MarkHudDirty = MarkHudDirty

function ExtraHUD.OnOverlayAdjusterMoved()
    -- Invalidate caches and force HUD/layout update
    cachedLayout.valid = false
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
        
        -- Build complete ordered list: starting items first, then pickup order
        local orderedItems = {}
        local alreadyAdded = {}
        
        -- First, add any starting items that aren't in pickup order (these are oldest)
        for id in pairs(ownedSet) do
            local inPickupOrder = false
            if playerPickupOrder[i] then
                for _, pickupId in ipairs(playerPickupOrder[i]) do
                    if pickupId == id then
                        inPickupOrder = true
                        break
                    end
                end
            end
            if not inPickupOrder then
                table.insert(orderedItems, id)
                alreadyAdded[id] = true
            end
        end
        
        -- Then, add items in pickup order (if still owned) - these are newer
        if playerPickupOrder[i] then
            for _, id in ipairs(playerPickupOrder[i]) do
                if ownedSet[id] and not alreadyAdded[id] then
                    table.insert(orderedItems, id)
                    alreadyAdded[id] = true
                end
            end
        end
        
        -- Set the final ordered list
        cachedPlayerIconData[i + 1] = orderedItems
    end
    cachedPlayerCount = totalPlayers
    hudDirty = false
    if shouldCleanup then
        CleanupUnusedSprites()
    end
end

-- Helper: record all current collectibles for all players (e.g. at game start or new player join)
local function TrackAllCurrentCollectibles()
    local game = Game()
    local totalPlayers = game:GetNumPlayers()
    
    for i = 0, totalPlayers - 1 do
        local player = Isaac.GetPlayer(i)
        if player then
            -- Ensure tracking tables exist
            if not playerTrackedCollectibles[i] then
                playerTrackedCollectibles[i] = {}
            end
            
            -- Only scan up to MAX_ITEM_ID, skip high IDs unless needed
            for id = 1, MAX_ITEM_ID do
                if player:HasCollectible(id) and IsValidItem(id) then
                    playerTrackedCollectibles[i][id] = true
                end
            end
            
            -- Only initialize pickup order if it doesn't exist (fresh start)
            if not playerPickupOrder[i] then
                playerPickupOrder[i] = {}
                -- For new tracking, add all current items as starting items
                local startingItems = {}
                for id = 1, MAX_ITEM_ID do
                    if player:HasCollectible(id) and IsValidItem(id) then
                        table.insert(startingItems, id)
                    end
                end
                for _, id in ipairs(startingItems) do
                    table.insert(playerPickupOrder[i], id)
                end
            end
        end
    end
    
    -- Update cached player count to match current state
    cachedPlayerCount = totalPlayers
end

-- Isaac best practice: Enhanced game start handling
ExtraHUD:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, _)
    -- Disable vanilla ExtraHUD if configured
    DisableVanillaExtraHUD()
    
    -- Reset startup tracking
    gameStartupFrames = 0
    lastPlayerCount = 0
    
    -- Force clear all caches to ensure fresh state
    cachedPlayerIconData = nil
    cachedPlayerCount = 0
    hudDirty = true
    cachedLayout.valid = false
    
    -- Clear pickup tracking for fresh game start
    playerTrackedCollectibles = {}
    playerPickupOrder = {}
    
    TrackAllCurrentCollectibles()
    -- Clear sprite cache on new game to prevent memory buildup
    itemSpriteCache = {}
    spriteUsageTracker = {}
    characterHeadSpriteCache = {}
    MarkHudDirty()
end, CallbackPriority and CallbackPriority.LATE or nil)

-- Forward declarations for pickup order functions
local UpdatePickupOrderForPlayer, UpdatePickupOrderForAllPlayers

-- Maintain pickup order integrity (cleanup function - removes lost items, doesn't reorder)
local function UpdatePickupOrderForPlayer(playerIndex)
    local game = Game()
    if not game then return end
    
    local player = Isaac.GetPlayer(playerIndex)
    if not player then return end
    
    playerPickupOrder[playerIndex] = playerPickupOrder[playerIndex] or {}
    playerTrackedCollectibles[playerIndex] = playerTrackedCollectibles[playerIndex] or {}
    
    -- Build current owned items set (limit to reasonable range for performance)
    local owned = {}
    local maxRange = math.min(MAX_ITEM_ID, 500) -- Limit range for performance
    
    for id = 1, maxRange do
        if player:HasCollectible(id) and IsValidItem(id) then
            owned[id] = true
        end
    end
    
    -- Remove any collectibles from order that are no longer owned
    local j = 1
    while j <= #playerPickupOrder[playerIndex] do
        local itemId = playerPickupOrder[playerIndex][j]
        if not owned[itemId] then
            table.remove(playerPickupOrder[playerIndex], j)
            playerTrackedCollectibles[playerIndex][itemId] = nil
        else
            j = j + 1
        end
    end
    
    -- Only add items that we somehow missed (starting items, game reload, etc.)
    -- These will be added at the end, preserving the true pickup order for items we tracked
    for id = 1, maxRange do
        if owned[id] and not playerTrackedCollectibles[playerIndex][id] then
            -- Check if it's already in pickup order (safety check)
            local found = false
            for _, itemId in ipairs(playerPickupOrder[playerIndex]) do
                if itemId == id then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(playerPickupOrder[playerIndex], id)
            end
            playerTrackedCollectibles[playerIndex][id] = true
        end
    end
end

-- Legacy wrapper - now only updates when actually needed
local function UpdatePickupOrderForAllPlayers()
    local game = Game()
    if not game then return end
    
    for i = 0, game:GetNumPlayers() - 1 do
        UpdatePickupOrderForPlayer(i)
    end
end

local lastPlayerCount = 0
local gameStartupFrames = 0 -- Track frames since game start for initialization timing

-- Periodic cleanup timing
local pickupOrderUpdateDebounce = 0

-- Combined MC_POST_UPDATE: handle player count changes and periodic cleanup
ExtraHUD:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    local curCount = Game():GetNumPlayers()
    
    -- Initialize lastPlayerCount if nil
    if not lastPlayerCount then
        lastPlayerCount = 0
    end
    
    -- Handle new players joining (optimized) - also handle case where player count decreases then increases
    if curCount > lastPlayerCount or curCount ~= cachedPlayerCount then
        -- Ensure we track all current players, not just new ones
        for i = 0, curCount - 1 do
            if not playerTrackedCollectibles[i] then
                playerTrackedCollectibles[i] = {}
            end
            if not playerPickupOrder[i] then
                playerPickupOrder[i] = {}
                -- Initialize pickup order for new players - scan items in deterministic order
                local player = Isaac.GetPlayer(i)
                if player then
                    local startingItems = {}
                    for id = 1, MAX_ITEM_ID do
                        if player:HasCollectible(id) and IsValidItem(id) then
                            playerTrackedCollectibles[i][id] = true
                            table.insert(startingItems, id)
                        end
                    end
                    -- Initialize pickup order with starting items (in numerical order for consistency)
                    for _, id in ipairs(startingItems) do
                        table.insert(playerPickupOrder[i], id)
                    end
                end
            end
        end
        -- Force immediate cache invalidation and update
        cachedPlayerIconData = nil
        hudDirty = true
        cachedLayout.valid = false
        MarkHudDirty()
        lastPlayerCount = curCount
        Isaac.ConsoleOutput("[CoopExtraHUD] Player count changed to " .. curCount .. ", forcing HUD update\n")
    end
    
    -- Periodic cleanup: run maintenance every 60 frames to remove lost items
    if REPENTOGON and Game().GetFrameCount then
        local currentFrame = Game():GetFrameCount()
        if currentFrame % 60 == 0 then
            UpdatePickupOrderForAllPlayers()
        end
        -- Also check for new items every 10 frames as backup
        if currentFrame % 10 == 0 then
            local itemsChanged = false
            for i = 0, curCount - 1 do
                local player = Isaac.GetPlayer(i)
                if player then
                    for id = 1, math.min(MAX_ITEM_ID, 500) do
                        if player:HasCollectible(id) and IsValidItem(id) then
                            playerTrackedCollectibles[i] = playerTrackedCollectibles[i] or {}
                            playerPickupOrder[i] = playerPickupOrder[i] or {}
                            if not playerTrackedCollectibles[i][id] then
                                table.insert(playerPickupOrder[i], id)
                                playerTrackedCollectibles[i][id] = true
                                itemsChanged = true
                                -- Debug: backup detection found new item
                                local playerType = player:GetPlayerType()
                                local playerName = "Player " .. (i+1)
                                if playerType == PlayerType.PLAYER_JACOB then
                                    playerName = "Jacob (P" .. (i+1) .. ")"
                                elseif playerType == PlayerType.PLAYER_ESAU then
                                    playerName = "Esau (P" .. (i+1) .. ")"
                                end
                                if Isaac.GetItemConfig():GetCollectible(id) then
                                    local itemName = Isaac.GetItemConfig():GetCollectible(id).Name
                                    Isaac.ConsoleOutput("[CoopExtraHUD] Backup detection: " .. playerName .. " has new item: " .. itemName .. " (ID: " .. id .. ")\n")
                                end
                            end
                        end
                    end
                end
            end
            if itemsChanged then
                cachedPlayerIconData = nil
                hudDirty = true
                cachedLayout.valid = false
                MarkHudDirty()
            end
        end
    else
        -- Fallback: scan for new items every 30 frames and mark HUD dirty if any are found
        if pickupOrderUpdateDebounce <= 0 then
            local anyPlayerChanged = false
            local game = Game()
            local curCount = game:GetNumPlayers()
            for i = 0, curCount - 1 do
                local player = Isaac.GetPlayer(i)
                local playerChanged = false
                if player then
                    for id = 1, math.min(MAX_ITEM_ID, 500) do
                        if player:HasCollectible(id) and IsValidItem(id) then
                            playerTrackedCollectibles[i] = playerTrackedCollectibles[i] or {}
                            playerPickupOrder[i] = playerPickupOrder[i] or {}
                            if not playerTrackedCollectibles[i][id] then
                                table.insert(playerPickupOrder[i], id)
                                playerTrackedCollectibles[i][id] = true
                                playerChanged = true
                            end
                        end
                    end
                end
                if playerChanged then
                    anyPlayerChanged = true
                end
            end
            if anyPlayerChanged then
                cachedPlayerIconData = nil
                hudDirty = true
                cachedLayout.valid = false
                MarkHudDirty()
            end
            UpdatePickupOrderForAllPlayers()
            pickupOrderUpdateDebounce = 30 -- Run scan every 30 frames
        else
            pickupOrderUpdateDebounce = pickupOrderUpdateDebounce - 1
        end
    end
end, CallbackPriority and CallbackPriority.LATE or nil)

-- Real-time pickup order tracking - record actual pickup events

-- REPENTOGON: Use MC_POST_ADD_COLLECTIBLE for instant item tracking
ExtraHUD:AddCallback(ModCallbacks.MC_POST_ADD_COLLECTIBLE, function(_, collectibleId, _, _, _, _, player)
    if collectibleId and collectibleId > 0 and IsValidItem(collectibleId) and player ~= nil then
        local playerObj = player
        local playerIndex = nil
        if type(playerObj) == "userdata" and type(playerObj.GetPlayerIndex) == "function" then
            playerIndex = playerObj:GetPlayerIndex()
        elseif type(playerObj) == "number" then
            playerIndex = playerObj
        end
        if playerIndex ~= nil and type(playerIndex) == "number" and playerIndex >= 0 then
            playerPickupOrder[playerIndex] = playerPickupOrder[playerIndex] or {}
            playerTrackedCollectibles[playerIndex] = playerTrackedCollectibles[playerIndex] or {}
            if not playerTrackedCollectibles[playerIndex][collectibleId] then
                table.insert(playerPickupOrder[playerIndex], collectibleId)
                playerTrackedCollectibles[playerIndex][collectibleId] = true
                cachedPlayerIconData = nil
                hudDirty = true
                cachedLayout.valid = false
                MarkHudDirty()
                -- Log pickup to game log file
                local playerType = Isaac.GetPlayer(playerIndex):GetPlayerType()
                local playerName = "Player " .. (playerIndex+1)
                if playerType == PlayerType.PLAYER_JACOB then
                    playerName = "Jacob (P" .. (playerIndex+1) .. ")"
                elseif playerType == PlayerType.PLAYER_ESAU then
                    playerName = "Esau (P" .. (playerIndex+1) .. ")"
                end
                if Isaac.GetItemConfig():GetCollectible(collectibleId) then
                    local itemName = Isaac.GetItemConfig():GetCollectible(collectibleId).Name
                    Isaac.ConsoleOutput("[CoopExtraHUD] " .. playerName .. " picked up: " .. itemName .. " (ID: " .. collectibleId .. ")\n")
                end
            end
        end
    end
end)


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

-- Common function to render a player's items block
local function RenderPlayerBlock(playerType, items, chunkX, currentRowY, cols, blockW, layout, cfg)
    local maxItems = math.min(#items, 32)
    local itemsStartY = currentRowY
    
    -- Render head icon if enabled
    if cfg.showCharHeadIcons then
        local isEsau = (playerType == PlayerType.PLAYER_ESAU)
        local headSprite = GetCharacterHeadSprite(playerType, isEsau)
        if headSprite then
            headSprite.Scale = Vector(layout.scale, layout.scale)
            headSprite.Color = Color(1, 1, 1, cfg.opacity)
            local headX = chunkX + (blockW / 2) - (ICON_SIZE * layout.scale / 2) + ((cfg.headIconXOffset or 0) * layout.scale)
            local headY = currentRowY + ((cfg.headIconYOffset or 0) * layout.scale)
            headSprite:Render(Vector(headX, headY), Vector.Zero, Vector.Zero)
            local extraGap = 16 * layout.scale
            itemsStartY = headY + ICON_SIZE * layout.scale + (cfg.ySpacing or 0) * layout.scale + extraGap
        end
    end
    
    -- Render items in grid
    for idx = 1, maxItems do
        local itemId = items[idx]
        if itemId then
            local itemRow = math.floor((idx - 1) / cols)
            local itemCol = (idx - 1) % cols
            local x = chunkX + itemCol * (ICON_SIZE + cfg.xSpacing) * layout.scale
            local y = itemsStartY + itemRow * (ICON_SIZE + cfg.ySpacing) * layout.scale
            RenderItemIcon(itemId, x, y, layout.scale, cfg.opacity)
        end
    end
    
    -- Return the bottom Y position of this block
    local itemRows = math.ceil(maxItems / cols)
    return itemsStartY + itemRows * (ICON_SIZE + cfg.ySpacing) * layout.scale
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
    -- MiniMapAPI detection first
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
    
    -- Standard fallback to vanilla minimap estimate
    return GetVanillaMinimapRect(screenW, screenH)
end

-- MCM compatibility flags for overlay display (manual toggles only)
ExtraHUD.MCMCompat_displayingOverlay = ""
ExtraHUD.MCMCompat_selectedOverlay = ""
ExtraHUD.MCMCompat_overlayTimestamp = 0
-- EID-style automatic overlay detection
ExtraHUD.MCMCompat_displayingTab = ""

-- MCM integration variable (declared at module level above - don't redeclare here)
-- Sprite-based overlay system (following MCM exact implementation)
local function GetMenuAnm2Sprite(animation, frame)
    local sprite = Sprite()
    sprite:Load("gfx/ui/coopextrahud/overlay.anm2", true)
    sprite:SetFrame(animation, frame)
    return sprite
end

-- Optimized column calculation with layout mode support
local function getPlayerColumns(itemCount, isJacobEsauCombo, layoutMode)
    layoutMode = layoutMode or "4_across" -- Default to current behavior
    
    -- This function determines columns for items within each player's chunk
    -- Layout mode doesn't affect this - it affects player chunk arrangement
    local maxCols = 4
    local itemsPerCol = isJacobEsauCombo and 4 or 8
    local cols = math.ceil(itemCount / itemsPerCol)
    return math.max(1, math.min(cols, maxCols))
end

-- Calculate player chunk arrangement based on layout mode
local function calculatePlayerChunkLayout(playerCount, layoutMode)
    layoutMode = layoutMode or "4_across"
    
    if layoutMode == "2x2_grid" then
        -- Arrange player chunks in 2x2 grid format
        if playerCount <= 1 then
            return 1, 1 -- 1 column, 1 row
        elseif playerCount <= 2 then
            return 2, 1 -- 2 columns, 1 row
        elseif playerCount <= 4 then
            return 2, 2 -- 2 columns, 2 rows
        else
            -- For more than 4 players, extend vertically
            local rows = math.ceil(playerCount / 2)
            return 2, rows
        end
    else
        -- Original "4_across" layout - all players in one row
        return playerCount, 1
    end
end

-- Calculate and cache layout (only when dirty)
local function UpdateLayout(playerIconData, cfg, screenW, screenH)
    if cachedLayout.valid then return cachedLayout end
    
    -- Calculate player chunk arrangement
    local actualPlayerCount = 0
    local i = 1
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
        actualPlayerCount = actualPlayerCount + 1
        if isJacobEsauCombo then
            i = i + 2
        else
            i = i + 1
        end
    end
    
    local chunkCols, chunkRows = calculatePlayerChunkLayout(actualPlayerCount, cfg.itemLayoutMode)
    
    -- Calculate columns and dimensions for each player block
    local maxRows = 1
    local playerColumns = {}
    local blockWidths = {}
    local blockHeights = {}
    i = 1
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
        
        local blockW = (ICON_SIZE * cols * cfg.scale) + ((cols - 1) * cfg.xSpacing * cfg.scale)
        blockWidths[i] = blockW
        
        -- Calculate block height (including head icons if enabled)
        if isJacobEsauCombo then
            -- Special height calculation for Jacob & Esau combo blocks
            local jacobItems = playerIconData[i] or {}
            local esauItems = playerIconData[i+1] or {}
            local jacobRows = math.ceil(#jacobItems / cols)
            local esauRows = math.ceil(#esauItems / cols)
            
            local blockH = 0
            -- Jacob head icon (if enabled)
            if cfg.showCharHeadIcons then
                blockH = blockH + ICON_SIZE * cfg.scale + 16 * cfg.scale -- head icon + gap
            end
            -- Jacob items height
            blockH = blockH + jacobRows * (ICON_SIZE + cfg.ySpacing) * cfg.scale - cfg.ySpacing * cfg.scale
            -- Divider gap between Jacob and Esau
            blockH = blockH + (cfg.comboChunkGap or 8) * cfg.scale + 2 * cfg.scale -- divider height
            -- Esau head icon (if enabled)  
            if cfg.showCharHeadIcons then
                blockH = blockH + ICON_SIZE * cfg.scale + 16 * cfg.scale -- head icon + gap
            end
            -- Esau items height
            blockH = blockH + esauRows * (ICON_SIZE + cfg.ySpacing) * cfg.scale - cfg.ySpacing * cfg.scale
            
            blockHeights[i] = blockH
        else
            -- Normal player block height calculation
            local blockH = rows * (ICON_SIZE + cfg.ySpacing) * cfg.scale - cfg.ySpacing * cfg.scale
            if cfg.showCharHeadIcons then
                blockH = blockH + ICON_SIZE * cfg.scale + 16 * cfg.scale -- head icon + gap
            end
            blockHeights[i] = blockH
        end
        
        if isJacobEsauCombo then
            i = i + 2
        else
            i = i + 1
        end
    end
    
    -- Calculate dimensions based on chunk arrangement
    local maxChunkWidth = 0
    local totalChunkHeight = 0
    
    -- Find the maximum width needed per row
    local chunkIndex = 1
    for row = 1, chunkRows do
        local rowWidth = 0
        local rowHeight = 0
        for col = 1, chunkCols do
            if chunkIndex <= actualPlayerCount then
                -- Find the corresponding playerIconData index
                local playerDataIndex = 1
                local currentChunk = 1
                i = 1
                while i <= #playerIconData and currentChunk < chunkIndex do
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
                    currentChunk = currentChunk + 1
                    if isJacobEsauCombo then
                        i = i + 2
                    else
                        i = i + 1
                    end
                    playerDataIndex = i
                end
                
                if playerDataIndex <= #playerIconData then
                    rowWidth = rowWidth + (blockWidths[playerDataIndex] or 0)
                    if col < chunkCols and chunkIndex < actualPlayerCount then
                        rowWidth = rowWidth + INTER_PLAYER_SPACING * cfg.scale
                    end
                    rowHeight = math.max(rowHeight, blockHeights[playerDataIndex] or 0)
                end
                chunkIndex = chunkIndex + 1
            end
        end
        maxChunkWidth = math.max(maxChunkWidth, rowWidth)
        totalChunkHeight = totalChunkHeight + rowHeight
        if row < chunkRows then
            totalChunkHeight = totalChunkHeight + INTER_PLAYER_SPACING * cfg.scale
        end
    end
    
    local totalWidth = maxChunkWidth
    local totalHeight = totalChunkHeight
    local scale = cfg.scale
    
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
    cachedLayout.blockHeights = blockHeights
    cachedLayout.chunkCols = chunkCols
    cachedLayout.chunkRows = chunkRows
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
local lastScreenW, lastScreenH = 0, 0
local cachedClampedConfig = nil

-- Clamp config values - now with reduced caching for better live updates
local function GetClampedConfig(cfg, screenW, screenH)
    -- Always recalculate clamped config if cachedClampedConfig is nil (invalidated by MarkHudDirty)
    -- or if screen size changed
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
    clamped.itemLayoutMode = clamped.itemLayoutMode or "4_across"
    
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
        
        -- Force layout refresh
        MarkHudDirty()
        
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

    -- Get fresh config for better real-time responsiveness
    local cfg = getConfig()
    
    -- Simple minimap detection - no complex caching
    local minimapRect = GetMinimapRect(screenW, screenH)
    if minimapRect then
        cfg.minimapX = minimapRect.x
        cfg.minimapY = minimapRect.y
        cfg.minimapW = minimapRect.w
        cfg.minimapH = minimapRect.h
        -- Runtime-only adjustment, don't save
    end

    -- Only update player icon data cache if dirty or player count changed
    local totalPlayers = game:GetNumPlayers()
    if totalPlayers <= 0 then return end -- No players, nothing to render
    
    -- Track startup frames for initialization timing
    gameStartupFrames = gameStartupFrames + 1
    
    -- Backup initialization check: ensure we have valid data even if game start callback was insufficient
    if not cachedPlayerIconData or not playerTrackedCollectibles or not playerPickupOrder then
        hudDirty = true
        cachedPlayerIconData = nil
        cachedLayout.valid = false
        TrackAllCurrentCollectibles()
    end
    
    -- Additional check: ensure all current players are properly tracked
    for i = 0, totalPlayers - 1 do
        if not playerTrackedCollectibles[i] or not playerPickupOrder[i] then
            hudDirty = true
            cachedPlayerIconData = nil
            cachedLayout.valid = false
            TrackAllCurrentCollectibles()
            Isaac.ConsoleOutput("[CoopExtraHUD] Found untracked player " .. i .. ", forcing update\n")
            break
        end
    end
    
    -- Check for player count mismatch and force update if needed
    if cachedPlayerCount ~= totalPlayers then
        hudDirty = true
        cachedPlayerIconData = nil
        cachedLayout.valid = false
        Isaac.ConsoleOutput("[CoopExtraHUD] Player count mismatch detected (" .. (cachedPlayerCount or 0) .. " vs " .. totalPlayers .. "), forcing update\n")
    end
    
    -- Force update for first few frames to ensure proper initialization
    if gameStartupFrames <= 5 then
        hudDirty = true
    end
    
    if hudDirty or not cachedPlayerIconData or cachedPlayerCount ~= totalPlayers then
        UpdatePlayerIconData()
    end
    local playerIconData = cachedPlayerIconData
    if not playerIconData then return end

    -- Get cached layout (only recalculates when dirty) - use simplified config
    local layout = UpdateLayout(playerIconData, cfg, screenW, screenH)

    -- Extract config values once
    local boundaryX = tonumber(cfg.boundaryX) or 0
    local boundaryY = tonumber(cfg.boundaryY) or 0
    local boundaryW = tonumber(cfg.boundaryW) or 0
    local boundaryH = tonumber(cfg.boundaryH) or 0
    local minimapX = tonumber(cfg.minimapX) or 0
    local minimapY = tonumber(cfg.minimapY) or 0
    local minimapW = tonumber(cfg.minimapW) or 0
    local minimapH = tonumber(cfg.minimapH) or 0
    local minimapPadding = cfg.minimapPadding or 0

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

    -- Draw icons + dividers using 2D grid layout
    -- Calculate actual player count (accounting for Jacob+Esau combos)
    local actualPlayerCount = 0
    local playerIndex = 0
    while playerIndex < totalPlayers do
        local player = Isaac.GetPlayer(playerIndex)
        local playerType = player and player:GetPlayerType() or 0
        local isJacobEsauCombo = false
        if playerIndex + 1 < totalPlayers and playerType == PlayerType.PLAYER_JACOB then
            local esauPlayer = Isaac.GetPlayer(playerIndex + 1)
            local esauType = esauPlayer and esauPlayer:GetPlayerType() or 0
            if esauType == PlayerType.PLAYER_ESAU then
                isJacobEsauCombo = true
            end
        end
        actualPlayerCount = actualPlayerCount + 1
        if isJacobEsauCombo then
            playerIndex = playerIndex + 2
        else
            playerIndex = playerIndex + 1
        end
    end
    
    local chunkIndex = 1
    local currentRowY = startY
    local currentPlayerIndex = 0 -- Track actual player index (0-based)
    
    for row = 1, layout.chunkRows do
        local chunkX = startX
        local rowMaxHeight = 0
        
        for col = 1, layout.chunkCols do
            if chunkIndex > actualPlayerCount or currentPlayerIndex >= totalPlayers then break end
            
            -- Get the current player and items
            local items = playerIconData[currentPlayerIndex + 1] -- playerIconData is 1-indexed
            local cols = layout.playerColumns[currentPlayerIndex + 1]
            local blockW = layout.blockWidths[currentPlayerIndex + 1]
            local blockH = layout.blockHeights[currentPlayerIndex + 1]
            
            if type(cols) ~= "number" or cols < 1 or type(blockW) ~= "number" or blockW < 1 then
                chunkIndex = chunkIndex + 1
                currentPlayerIndex = currentPlayerIndex + 1
            else
                local player = Isaac.GetPlayer(currentPlayerIndex)
                local playerType = player and player:GetPlayerType() or 0
                
                -- Check for Jacob+Esau combo
                local isJacobCombo = (playerType == PlayerType.PLAYER_JACOB) and 
                                     (currentPlayerIndex + 1 < totalPlayers)
                
                if isJacobCombo then
                    local esauPlayer = Isaac.GetPlayer(currentPlayerIndex + 1)
                    local esauType = esauPlayer and esauPlayer:GetPlayerType() or 0
                    
                    if esauType == PlayerType.PLAYER_ESAU then
                        -- Jacob+Esau combo rendering
                        local jacobItems = items
                        local esauItems = playerIconData[currentPlayerIndex + 2] -- +2 because playerIconData is 1-indexed
                        
                        -- Render Jacob block
                        local jacobEndY = RenderPlayerBlock(PlayerType.PLAYER_JACOB, jacobItems, 
                                                          chunkX, currentRowY, cols, blockW, layout, cfg)
                        
                        -- Render horizontal divider
                        -- Position divider with better default spacing that reduces need for manual adjustment
                        local baseGap = 4 * layout.scale -- Base gap between Jacob items and divider
                        local dividerY = jacobEndY + baseGap
                        local dividerYOffset = (cfg.comboDividerYOffset or 0) * layout.scale
                        local dividerXOffset = (cfg.comboDividerXOffset or 0) * layout.scale
                        -- Make horizontal divider shorter - use actual item width instead of full block width
                        local actualItemWidth = cols * ICON_SIZE * layout.scale + (cols - 1) * (cfg.xSpacing or 0) * layout.scale
                        local dividerW = math.max(ICON_SIZE * layout.scale, actualItemWidth * 0.8) -- 80% of item width, minimum one icon width
                        -- Center the divider horizontally within the block
                        local dividerX = chunkX + (blockW - dividerW) / 2 + dividerXOffset
                        DividerSprite.Scale = Vector(dividerW, 1)
                        DividerSprite.Color = Color(1, 1, 1, cfg.opacity)
                        DividerSprite:Render(Vector(dividerX, dividerY + dividerYOffset), Vector.Zero, Vector.Zero)
                        
                        -- Render Esau block
                        -- Position Esau content with minimal gap after divider for tighter layout
                        local esauStartY = dividerY + baseGap
                        RenderPlayerBlock(PlayerType.PLAYER_ESAU, esauItems, 
                                        chunkX, esauStartY, cols, blockW, layout, cfg)
                        
                        rowMaxHeight = math.max(rowMaxHeight, blockH)
                        currentPlayerIndex = currentPlayerIndex + 2
                    else
                        -- Normal Jacob (without Esau)
                        RenderPlayerBlock(playerType, items, chunkX, currentRowY, cols, blockW, layout, cfg)
                        rowMaxHeight = math.max(rowMaxHeight, blockH)
                        currentPlayerIndex = currentPlayerIndex + 1
                    end
                else
                    -- Normal player rendering
                    RenderPlayerBlock(playerType, items, chunkX, currentRowY, cols, blockW, layout, cfg)
                    rowMaxHeight = math.max(rowMaxHeight, blockH)
                    currentPlayerIndex = currentPlayerIndex + 1
                end
                
                -- Add vertical dividers between chunks in the same row (but not after the last chunk)
                if col < layout.chunkCols and chunkIndex < actualPlayerCount then
                    local dividerX = chunkX + blockW + (INTER_PLAYER_SPACING * layout.scale) / 2 + ((-16 + (cfg.dividerOffset or 0)) * layout.scale)
                    local dividerY = currentRowY + ((-44 + (cfg.dividerYOffset or 0)) * layout.scale)
                    -- Make vertical divider shorter - exclude head icon area and add padding
                    local headIconHeight = cfg.showCharHeadIcons and (ICON_SIZE * layout.scale + 16 * layout.scale) or 0
                    local dividerStartPadding = headIconHeight + 8 * layout.scale -- Start below head icon with padding
                    local dividerEndPadding = 8 * layout.scale -- End padding from bottom
                    local dividerHeight = math.max(ICON_SIZE * layout.scale, rowMaxHeight - dividerStartPadding - dividerEndPadding)
                    local heightScale = math.max(1, math.floor(dividerHeight + 0.5))
                    DividerSprite.Scale = Vector(1, heightScale)
                    DividerSprite.Color = Color(1, 1, 1, cfg.opacity)
                    DividerSprite:Render(Vector(dividerX, dividerY + dividerStartPadding), Vector.Zero, Vector.Zero)
                end
                
                chunkX = chunkX + blockW + INTER_PLAYER_SPACING * layout.scale
                chunkIndex = chunkIndex + 1
            end
        end
        
        currentRowY = currentRowY + rowMaxHeight + INTER_PLAYER_SPACING * layout.scale
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
    end
    
    -- MCM overlay detection: check every frame for better responsiveness
    -- Update MCM focus tracking for overlay detection
    if mcmTables and mcmTables.UpdateMCMOverlayDisplay then
        mcmTables.UpdateMCMOverlayDisplay()
    end
    
    -- Debug: Track overlay tab changes
    local currentDisplayingTab = ExtraHUD.MCMCompat_displayingTab or ""
    
    -- EID-style automatic overlay detection based on which MCM tab is being viewed
    local mcm = _G['ModConfigMenu']
    local mcmIsOpen = mcm and ((type(mcm.IsVisible) == "function" and mcm.IsVisible()) or (type(mcm.IsVisible) == "boolean" and mcm.IsVisible))
    
    -- Only update overlay state when MCM state changes
    if mcmIsOpen ~= lastMCMState then
        lastMCMState = mcmIsOpen
        
        if mcmIsOpen then
            -- MCM just opened - apply automatic overlays based on current tab
            if ExtraHUD.MCMCompat_displayingTab == "hud_offset" then
                ExtraHUD.MCMCompat_displayingOverlay = "hudoffset"
                ExtraHUD.MCMCompat_selectedOverlay = "hudoffset"
            elseif ExtraHUD.MCMCompat_displayingTab == "boundary" then
                ExtraHUD.MCMCompat_displayingOverlay = "boundary"
                ExtraHUD.MCMCompat_selectedOverlay = "boundary"
            elseif ExtraHUD.MCMCompat_displayingTab == "minimap" then
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
        if ExtraHUD.MCMCompat_displayingTab == "hud_offset" then
            ExtraHUD.MCMCompat_displayingOverlay = "hudoffset"
            ExtraHUD.MCMCompat_selectedOverlay = "hudoffset"
        elseif ExtraHUD.MCMCompat_displayingTab == "boundary" then
            ExtraHUD.MCMCompat_displayingOverlay = "boundary"
            ExtraHUD.MCMCompat_selectedOverlay = "boundary"
        elseif ExtraHUD.MCMCompat_displayingTab == "minimap" then
            ExtraHUD.MCMCompat_displayingOverlay = "minimap"
            ExtraHUD.MCMCompat_selectedOverlay = "minimap"
        elseif ExtraHUD.MCMCompat_displayingTab == "" then
            ExtraHUD.MCMCompat_displayingOverlay = ""
            ExtraHUD.MCMCompat_selectedOverlay = ""
        end
    end
    
    -- Update last tab state
    if ExtraHUD.MCMCompat_displayingTab ~= lastDisplayingTab then
        lastDisplayingTab = ExtraHUD.MCMCompat_displayingTab
    end
    
    -- Manual overlay controls available as backup (B=Boundary, M=Minimap, H=HUD Offset, N=None)
    HandleManualOverlayToggle()
    
    -- Check if we should show overlays in MCM
    local showBoundary, showMinimap, showHudOffset = false, false, false
    
    -- Show overlays if MCM is open OR if they were manually triggered
    if lastMCMState or ExtraHUD.MCMCompat_displayingOverlay ~= "" then
        -- Simplified overlay detection - single flag system for better reliability
        if ExtraHUD.MCMCompat_displayingOverlay == "boundary" then
            showBoundary = true
        elseif ExtraHUD.MCMCompat_displayingOverlay == "minimap" then
            showMinimap = true
        elseif ExtraHUD.MCMCompat_displayingOverlay == "hudoffset" then
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
        end
    end
end

-- Also disable vanilla ExtraHUD on mod load (first load)
DisableVanillaExtraHUD()

-- Debug function to manually test overlay helpers (call from console)
function ExtraHUD.TestOverlayHelpers(overlayType)
    overlayType = overlayType or "boundary"
    ExtraHUD.MCMCompat_displayingOverlay = overlayType
    ExtraHUD.MCMCompat_selectedOverlay = overlayType
    print("[CoopExtraHUD] Testing overlay: " .. overlayType .. " (press N to clear)")
end

-- Isaac best practice: Use explicit callback priority for render callbacks
ExtraHUD:AddCallback(ModCallbacks.MC_POST_RENDER, ExtraHUD.PostRender, CallbackPriority and CallbackPriority.LATE or nil)

-- Isaac best practice: Use early priority for config saving to ensure it happens before other cleanup
ExtraHUD:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
    SaveConfig()
end, CallbackPriority and CallbackPriority.EARLY or nil)

-- Load saved config on startup
LoadConfig()
