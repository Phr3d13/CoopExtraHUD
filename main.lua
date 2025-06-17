local ExtraHUD = RegisterMod("CoopExtraHUD", 1)

-- Default config values
local config = {
    scale = 0.5,
    dividerOffset = -10,
    dividerYOffset = 0,
    xOffset = 20,
    yOffset = -25,
    opacity = 0.6,
    debugOverlay = false,
    mapYOffset = 100,
}

local ICON_SIZE = 32
local ICON_SPACING = 6
local COLUMNS = 2
local INTER_PLAYER_SPACING = 12

-- Cached sprite for collectibles
local itemSprite = Sprite()
itemSprite:Load("gfx/005.100_collectible.anm2", true)

-- Debug logs
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
        else local num = tonumber(v); if num then tbl[k] = num end
        end
    end
    return tbl
end

local function SaveConfig()
    ExtraHUD:SaveData(SerializeConfig(config))
    AddDebugLog("[Config] Saved")
end

local function LoadConfig()
    if ExtraHUD:HasData() then
        for k, v in pairs(DeserializeConfig(ExtraHUD:LoadData())) do
            if config[k] ~= nil then config[k] = v end
        end
        AddDebugLog("[Config] Loaded")
    else
        AddDebugLog("[Config] Default used")
    end
end

-- Render a single item icon
local function RenderItemIcon(itemId, x, y, scale, opa)
    local ci = Isaac.GetItemConfig():GetCollectible(itemId)
    if not ci then return end
    itemSprite:ReplaceSpritesheet(1, ci.GfxFileName)
    itemSprite:LoadGraphics()
    itemSprite:Play("Idle", true)
    itemSprite:SetFrame(0)
    itemSprite.Scale = Vector(scale, scale)
    itemSprite.Color = Color(1, 1, 1, opa)
    itemSprite:Render(Vector(x, y), Vector.Zero, Vector.Zero)
end

local function DrawRect(x, y, w, h, col)
    Isaac.RenderLine(Vector(x, y), Vector(x + w, y), col)
    Isaac.RenderLine(Vector(x, y + h), Vector(x + w, y + h), col)
    Isaac.RenderLine(Vector(x, y), Vector(x, y + h), col)
    Isaac.RenderLine(Vector(x + w, y), Vector(x + w, y + h), col)
end

function ExtraHUD:PostRender()
    local game, screenW, screenH = Game(), Isaac.GetScreenWidth(), Isaac.GetScreenHeight()

    if not game:GetRoom():IsClear() and game:GetLevel():GetStage() == LevelStage.STAGE4 then
        return
    end
    if config.scale <= 0 or config.opacity <= 0 then return end

    local yMapOffset = 0
    local baseMapHidden = not game:GetHUD():IsVisible()

    local minimapAvailable = type(MinimapAPI) == "table" and type(MinimapAPI.GetSetting) == "function"

    if minimapAvailable and MinimapAPI:GetSetting("Display") then
        local position = MinimapAPI:GetSetting("Position") or "TopRight"
        local scale = MinimapAPI:GetSetting("Scale") or 1
        local size = MinimapAPI:GetSetting("MapFrameSize") or Vector(64, 64)

        if position:lower():find("top") then
            yMapOffset = size.Y * scale + 10
        end
    elseif baseMapHidden then
        yMapOffset = config.mapYOffset
    end

    local totalPlayers = game:GetNumPlayers()
    if totalPlayers == 0 then return end
    local playerIconData = {}
    for i = 0, totalPlayers - 1 do
        local items = {}
        for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
            if Isaac.GetPlayer(i):HasCollectible(id) then table.insert(items, id) end
        end
        table.sort(items)
        playerIconData[i + 1] = items
    end

    local maxRows = 1
    for _, items in ipairs(playerIconData) do
        maxRows = math.max(maxRows, math.ceil(#items / COLUMNS))
    end

    local rawScale = config.scale
    local maxHeight = maxRows * (ICON_SIZE + ICON_SPACING) - ICON_SPACING
    local scale = math.min(rawScale, (screenH * 0.8) / maxHeight)

    local step = (ICON_SIZE + ICON_SPACING) * scale
    local blockW = (ICON_SIZE * COLUMNS * scale) + ((COLUMNS - 1) * ICON_SPACING * scale)
    local totalW = blockW * totalPlayers + (totalPlayers - 1) * INTER_PLAYER_SPACING * scale
    local startX = screenW - totalW - 10 + config.xOffset
    local totalH = maxHeight * scale
    local startY = (screenH - totalH) / 2 + config.yOffset + yMapOffset

    for i, items in ipairs(playerIconData) do
        local baseX = startX + (i - 1) * ((blockW) + INTER_PLAYER_SPACING * scale)
        for idx, itemId in ipairs(items) do
            local row, col = math.floor((idx - 1) / COLUMNS), (idx - 1) % COLUMNS
            RenderItemIcon(itemId, baseX + col * step, startY + row * step, scale, config.opacity)
        end
        if i < totalPlayers then
            local dividerX = baseX + blockW + (INTER_PLAYER_SPACING * scale) / 2 + config.dividerOffset
            local lineChar, ds = "|", ICON_SIZE * .375 * scale
            for l = 0, math.floor(totalH / ds) do
                Isaac.RenderScaledText(lineChar, dividerX, startY + config.dividerYOffset + l * ds, scale, scale, 1, 1, 1, config.opacity)
            end
        end
    end

    if config.debugOverlay then
        Isaac.RenderText("[DEBUG overlay]", 10, 10, 1, 1, 1, 1)
        Isaac.RenderText("yMapOffset = " .. tostring(yMapOffset), 10, 25, 1, 1, 1, 1)
        for i, msg in ipairs(debugLogs) do
            Isaac.RenderText("[LOG] " .. msg, 10, 40 + i * 15, 1, 1, 1, 1)
        end
        Isaac.RenderText("MinimapAPI: " .. tostring(minimapAvailable), 10, 60 + #debugLogs * 15, 1, 1, 1, 1)
        Isaac.RenderText("Final yMapOffset = " .. tostring(yMapOffset), 10, 75 + #debugLogs * 15, 1, 1, 1, 1)
        DrawRect(startX, startY, totalW, totalH, Color(0, 1, 0, 0.5))
    end

    AddDebugLog("Rendered HUD; mapVisible=" .. tostring(not baseMapHidden))
end

ExtraHUD:AddCallback(ModCallbacks.MC_POST_RENDER, ExtraHUD.PostRender)

local function RegisterConfigMenu()
    if not ModConfigMenu then
        print("[CoopExtraHUD] MCM not found; skipping menu")
        return
    end
    local MOD, SEC = "CoopExtraHUD", "Tweaks"
    ModConfigMenu.AddSpace(MOD, SEC)
    ModConfigMenu.AddTitle(MOD, SEC, "Tweaks and Adjustments")
    local addNum = function(name, cur, disp, min, max, step, onchg)
        ModConfigMenu.AddSetting(MOD, SEC, {
            Type = ModConfigMenu.OptionType.NUMBER,
            CurrentSetting = cur, Display = disp, OnChange = onchg,
            Minimum = min, Maximum = max, Step = step,
        })
    end

    addNum("scale", function() return math.floor(config.scale*100) end,
        function() return "HUD Scale: " .. math.floor(config.scale*100) .. "%" end,
        20, 100, 5, function(v) config.scale = v/100; SaveConfig() end)

    addNum("dividerOffset", function() return config.dividerOffset end,
        function() return "Divider X Offset: " .. config.dividerOffset end,
        -200,200,5, function(v) config.dividerOffset = v; SaveConfig() end)

    addNum("dividerYOffset", function() return config.dividerYOffset end,
        function() return "Divider Y Offset: " .. config.dividerYOffset end,
        -200,200,5, function(v) config.dividerYOffset = v; SaveConfig() end)

    addNum("xOffset", function() return config.xOffset end,
        function() return "HUD X Offset: " .. config.xOffset end,
        -200,200,5, function(v) config.xOffset = v; SaveConfig() end)

    addNum("yOffset", function() return config.yOffset end,
        function() return "HUD Y Offset: " .. config.yOffset end,
        -200,200,5, function(v) config.yOffset = v; SaveConfig() end)

    addNum("opacity", function() return math.floor(config.opacity*100) end,
        function() return "HUD Opacity: " .. math.floor(config.opacity*100) .. "%" end,
        0,100,5, function(v) config.opacity = v/100; SaveConfig() end)

    addNum("mapYOffset", function() return config.mapYOffset end,
        function() return "Map Y‑Offset: " .. config.mapYOffset .. " px" end,
        0, 300, 10, function(v) config.mapYOffset = v; SaveConfig() end)

    ModConfigMenu.AddSetting(MOD, SEC, {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return config.debugOverlay end,
        Display = function() return "Debug Overlay: " .. (config.debugOverlay and "On" or "Off") end,
        OnChange = function(v) config.debugOverlay = v; SaveConfig() end,
    })
    print("[CoopExtraHUD] Config menu registered.")
end

ExtraHUD:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, _)
    LoadConfig()
    if not ExtraHUD._configMenuRegistered then
        RegisterConfigMenu()
        ExtraHUD._configMenuRegistered = true
    end
end)

ExtraHUD:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
    SaveConfig()
end)

print("[CoopExtraHUD] Fully loaded with map-aware HUD shifting!")
