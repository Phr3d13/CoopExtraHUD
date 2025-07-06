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

local function SerializeAllConfigs()
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
    end
end

local function LoadConfig()
    if ExtraHUD:HasData() then
        local data = ExtraHUD:LoadData()
        local all = DeserializeAllConfigs(data)
        for k, v in pairs(all.config or {}) do config[k] = v end
        for k, v in pairs(all.preset_false or {}) do configPresets[false][k] = v end
        for k, v in pairs(all.preset_true or {}) do configPresets[true][k] = v end
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









-- Dual-flag overlay logic (set by MCM.lua)
ExtraHUD.MCMCompat_displayingOverlay = ""
ExtraHUD.MCMCompat_selectedOverlay = ""

function ExtraHUD:PostRender()
    local game = Game()
    local screenW, screenH = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
    -- Defensive: ensure all config values are not nil before use
    local cfg = getConfig()
    cfg.boundaryX = cfg.boundaryX or 0
    cfg.boundaryY = cfg.boundaryY or 0
    cfg.boundaryW = cfg.boundaryW or screenW
    cfg.boundaryH = cfg.boundaryH or screenH
    cfg.minimapX = cfg.minimapX or 0
    cfg.minimapY = cfg.minimapY or 0
    cfg.minimapW = cfg.minimapW or 0
    cfg.minimapH = cfg.minimapH or 0
    cfg.minimapPadding = cfg.minimapPadding or 0
    cfg.xOffset = cfg.xOffset or 0
    cfg.yOffset = cfg.yOffset or 0
    cfg.scale = cfg.scale or 1
    cfg.opacity = cfg.opacity or 1
    cfg.xSpacing = cfg.xSpacing or 0
    cfg.ySpacing = cfg.ySpacing or 0
    cfg.dividerOffset = cfg.dividerOffset or 0
    cfg.dividerYOffset = cfg.dividerYOffset or 0
    -- Clamp boundary to screen size (allow full range)
    cfg.boundaryW = math.max(32, math.min(cfg.boundaryW, screenW))
    cfg.boundaryH = math.max(32, math.min(cfg.boundaryH, screenH))
    cfg.boundaryX = math.max(0, math.min(cfg.boundaryX, screenW - 1))
    cfg.boundaryY = math.max(0, math.min(cfg.boundaryY, screenH - 1))
    -- Clamp minimap area to screen
    cfg.minimapW = math.max(0, math.min(cfg.minimapW, screenW))
    cfg.minimapH = math.max(0, math.min(cfg.minimapH, screenH))
    cfg.minimapX = math.max(0, math.min(cfg.minimapX, screenW - 1))
    cfg.minimapY = math.max(0, math.min(cfg.minimapY, screenH - 1))
    local hudVisible = game:GetHUD():IsVisible()
    local isPaused = game:IsPaused()
    local yMapOffset = (not hudVisible and isPaused) and cfg.mapYOffset or 0
    -- Only update player icon data cache if dirty or player count changed
    local totalPlayers = game:GetNumPlayers()
    if hudDirty or not cachedPlayerIconData or cachedPlayerCount ~= totalPlayers then
        UpdatePlayerIconData()
    end
    local playerIconData = cachedPlayerIconData
    if not playerIconData then return end
    -- Layout calculations (always recalculate every frame for boundary clamp)
local function getPlayerColumns(itemCount)
    local maxCols = 4
    -- Calculate columns by dividing itemCount by 8, rounding up, capped at maxCols
    local cols = math.ceil(itemCount / 8)
    if cols > maxCols then
        cols = maxCols
    elseif cols < 1 then
        cols = 1
    end
    return cols
end

local maxRows = 1
local playerColumns = {}

-- Calculate columns and max rows needed
for i, items in ipairs(playerIconData) do
    local itemCount = #items
    local cols = getPlayerColumns(itemCount)
    playerColumns[i] = cols
    local rows = math.ceil(itemCount / cols)
    maxRows = math.max(maxRows, rows)
end

local rawScale = cfg.scale

-- Calculate max height with current columns before scaling
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
    local blockWs = {}
    for i, items in ipairs(playerIconData) do
        local cols = playerColumns[i]
        blockWs[i] = (ICON_SIZE * cols * scale) + ((cols - 1) * cfg.xSpacing * scale)
    end
    local totalW = 0
    for i = 1, #blockWs do
        totalW = totalW + blockWs[i]
    end
    totalW = totalW + (#blockWs - 1) * INTER_PLAYER_SPACING * scale
    local totalH = maxHeight * scale
    -- Improved boundary anchoring logic
    local startX, startY
    if cfg.hudMode then
        -- Vanilla+: anchor to top-right of boundary, plus offsets
        startX = cfg.boundaryX + cfg.boundaryW - totalW + cfg.xOffset
        startY = cfg.boundaryY + cfg.yOffset
    else
        -- Updated: center vertically in boundary, right-aligned
        startX = cfg.boundaryX + cfg.boundaryW - totalW + cfg.xOffset
        startY = cfg.boundaryY + ((cfg.boundaryH - totalH) / 2) + cfg.yOffset
    end
    -- Minimap avoidance: if HUD would overlap minimap area, move HUD below minimap (with padding)
    local minimapX = tonumber(cfg.minimapX) or 0
    local minimapY = tonumber(cfg.minimapY) or 0
    local minimapW = tonumber(cfg.minimapW) or 0
    local minimapH = tonumber(cfg.minimapH) or 0
    local minimapPadding = tonumber(cfg.minimapPadding) or 0
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
    if startX < cfg.boundaryX then startX = cfg.boundaryX end
    if startY < cfg.boundaryY then startY = cfg.boundaryY end
    if startX + totalW > cfg.boundaryX + cfg.boundaryW then
        startX = cfg.boundaryX + cfg.boundaryW - totalW
    end
    if startY + totalH > cfg.boundaryY + cfg.boundaryH then
        startY = cfg.boundaryY + cfg.boundaryH - totalH
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
            local x = curX + col * (ICON_SIZE + cfg.xSpacing) * scale
            local y = startY + row * (ICON_SIZE + cfg.ySpacing) * scale
            RenderItemIcon(itemId, x, y, scale, cfg.opacity)
        end
        if i < #playerIconData then
            local dividerX = curX + blockW + (INTER_PLAYER_SPACING * scale) / 2 + cfg.dividerOffset
            local lineChar = "|"
            local dividerStep = ICON_SIZE * 0.375 * scale
            local lines = math.floor(totalH / dividerStep)
            for l = 0, lines do
                Isaac.RenderScaledText(lineChar, dividerX, startY + cfg.dividerYOffset + l * dividerStep, scale, scale, 1, 1, 1, cfg.opacity)
            end
        end
        curX = curX + blockW + INTER_PLAYER_SPACING * scale
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
    -- Draw overlays as needed (text/lines only, sprite code removed)
    if showBoundary then
        local bx = tonumber(cfg.boundaryX) or 0
        local by = tonumber(cfg.boundaryY) or 0
        local bw = tonumber(cfg.boundaryW) or 0
        local bh = tonumber(cfg.boundaryH) or 0
        if bw > 0 and bh > 0 then
            Isaac.RenderText("Boundary", bx+4, by+4, 1, 0, 0, 1)
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
        local mx = tonumber(cfg.minimapX) or 0
        local my = tonumber(cfg.minimapY) or 0
        local mw = tonumber(cfg.minimapW) or 0
        local mh = tonumber(cfg.minimapH) or 0
        if mw > 0 and mh > 0 then
            Isaac.RenderText("Map", mx+4, my+4, 1, 0, 0, 1)
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

-- MCM logic is now in MCM.lua

-- MCM integration
local MCM = require("MCM")



-- Ensure config and configPresets are initialized before MCM.Init

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
