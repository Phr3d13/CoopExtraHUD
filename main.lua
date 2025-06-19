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
        else local num = tonumber(v); if num then tbl[k] = num else tbl[k] = v end
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
    local game = Game()
    local screenW, screenH = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()

    if not game:GetRoom():IsClear() and game:GetLevel():GetStage() == LevelStage.STAGE4 then return end
    if config.scale <= 0 or config.opacity <= 0 then return end

    -- Detect if HUD is hidden (map open)
    local hudVisible = game:GetHUD():IsVisible()
    local yMapOffset = hudVisible and 0 or config.mapYOffset

    -- Gather player data
    local totalPlayers = game:GetNumPlayers()
    if totalPlayers == 0 then return end

    local playerIconData = {}

    if not config.hudMode then
        -- Vanilla+ behavior
        local vanillaPlayers = math.min(totalPlayers, 2)
        for i = 0, vanillaPlayers - 1 do
            local items = {}
            for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
                if Isaac.GetPlayer(i):HasCollectible(id) then table.insert(items, id) end
            end
            playerIconData[i + 1] = items
        end
        if totalPlayers > 2 then
            for i = 2, totalPlayers - 1 do
                local items = {}
                for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
                    if Isaac.GetPlayer(i):HasCollectible(id) then table.insert(items, id) end
                end
                playerIconData[i + 1] = items
            end
        end
    else
        -- Updated behavior (all players)
        for i = 0, totalPlayers - 1 do
            local items = {}
            for id = 1, CollectibleType.NUM_COLLECTIBLES - 1 do
                if Isaac.GetPlayer(i):HasCollectible(id) then table.insert(items, id) end
            end
            playerIconData[i + 1] = items
        end
    end

    -- Layout calculations
    local maxRows = 1
    for _, items in ipairs(playerIconData) do
        maxRows = math.max(maxRows, math.ceil(#items / COLUMNS))
    end

    local rawScale = config.scale
    local maxHeight = maxRows * (ICON_SIZE + config.ySpacing) - config.ySpacing
    local scale = math.min(rawScale, (screenH * 0.8) / maxHeight)

    local stepX = (ICON_SIZE + config.xSpacing) * scale
    local stepY = (ICON_SIZE + config.ySpacing) * scale
    local blockW = (ICON_SIZE * COLUMNS * scale) + ((COLUMNS - 1) * config.xSpacing * scale)
    local totalW = blockW * totalPlayers + (totalPlayers - 1) * INTER_PLAYER_SPACING * scale
    local startX, startY
    local totalH = maxHeight * scale

    if config.hudMode then
        -- Updated: center vertically on right side
        startX = screenW - totalW - 10 + config.xOffset
        startY = (screenH - totalH) / 2 + config.yOffset + yMapOffset
    else
        -- Vanilla+: right justified, just below map
        startX = screenW - totalW - 10 + config.xOffset
        -- Position Y just below the map UI:
        -- Isaac’s map height is roughly 100 px, use yOffset as fine adjust
        startY = screenH - totalH - 100 + config.yOffset + yMapOffset
    end

    -- Draw icons + dividers
    for i, items in ipairs(playerIconData) do
        local baseX = startX + (i - 1) * (blockW + INTER_PLAYER_SPACING * scale)
        for idx, itemId in ipairs(items) do
            local row, col = math.floor((idx - 1) / COLUMNS), (idx - 1) % COLUMNS
            RenderItemIcon(itemId, baseX + col * stepX, startY + row * stepY, scale, config.opacity)
        end
        if i < totalPlayers then
            local dividerX = baseX + blockW + (INTER_PLAYER_SPACING * scale) / 2 + config.dividerOffset
            local lineChar = "|"
            local dividerStep = ICON_SIZE * 0.375 * scale
            local lines = math.floor(totalH / dividerStep)
            for l = 0, lines do
                Isaac.RenderScaledText(lineChar, dividerX, startY + config.dividerYOffset + l * dividerStep, scale, scale, 1, 1, 1, config.opacity)
            end
        end
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

local function RegisterConfigMenu()
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

    -- Reset Presets button
ModConfigMenu.AddSetting(MOD, "Presets", {
    Type = ModConfigMenu.OptionType.BOOLEAN,
    CurrentSetting = function() return false end,  -- always show as false (off)
    Display = function() return "Reset Presets to Defaults" end,
    OnChange = function(v)
        if v then
            -- Reset presets to original defaults
            configPresets[false] = {
                scale = 0.4,
                xSpacing = 5,
                ySpacing = 5,
                dividerOffset = -20,
                dividerYOffset = 0,
                xOffset = 10,
                yOffset = -10,
                opacity = 0.8,
            }
            configPresets[true] = {
                scale = 0.5,
                xSpacing = 6,
                ySpacing = 6,
                dividerOffset = -10,
                dividerYOffset = 0,
                xOffset = 20,
                yOffset = -25,
                opacity = 0.6,
            }
            -- Re-apply current preset config values to config table
            local preset = configPresets[config.hudMode]
            if preset then
                for k, val in pairs(preset) do
                    config[k] = val
                end
            end
            SaveConfig()
            print("[CoopExtraHUD] Presets reset to defaults")

            -- Reset toggle to false so it can be triggered again later
            ModConfigMenu.SetSetting(MOD, "Presets", "ResetPresets", false)
        end
    end,
    Identifier = "ResetPresets"
})

    -- General Category
    ModConfigMenu.AddSpace(MOD, "General")
    ModConfigMenu.AddTitle(MOD, "General", "Display Options")

    local addNum = function(name, cur, disp, min, max, step, onchg)
        ModConfigMenu.AddSetting(MOD, "General", {
            Type = ModConfigMenu.OptionType.NUMBER,
            CurrentSetting = cur, Display = disp, OnChange = onchg,
            Minimum = min, Maximum = max, Step = step,
        })
    end

    addNum("scale", function() return math.floor(config.scale * 100) end,
        function() return "HUD Scale: " .. math.floor(config.scale * 100) .. "%" end,
        20, 100, 5, function(v) config.scale = v / 100; SaveConfig() end)

    addNum("xSpacing", function() return config.xSpacing end,
        function() return "X Spacing: " .. config.xSpacing end,
        0, 50, 1, function(v) config.xSpacing = v; SaveConfig() end)

    addNum("ySpacing", function() return config.ySpacing end,
        function() return "Y Spacing: " .. config.ySpacing end,
        0, 50, 1, function(v) config.ySpacing = v; SaveConfig() end)

    addNum("dividerOffset", function() return config.dividerOffset end,
        function() return "Divider X Offset: " .. config.dividerOffset end,
        -200, 200, 5, function(v) config.dividerOffset = v; SaveConfig() end)

    addNum("dividerYOffset", function() return config.dividerYOffset end,
        function() return "Divider Y Offset: " .. config.dividerYOffset end,
        -200, 200, 5, function(v) config.dividerYOffset = v; SaveConfig() end)

    addNum("xOffset", function() return config.xOffset end,
        function() return "HUD X Offset: " .. config.xOffset end,
        -200, 200, 5, function(v) config.xOffset = v; SaveConfig() end)

    addNum("yOffset", function() return config.yOffset end,
        function() return "HUD Y Offset: " .. config.yOffset end,
        -200, 200, 5, function(v) config.yOffset = v; SaveConfig() end)

    addNum("opacity", function() return math.floor(config.opacity * 100) end,
        function() return "HUD Opacity: " .. math.floor(config.opacity * 100) .. "%" end,
        0, 100, 5, function(v) config.opacity = v / 100; SaveConfig() end)

    addNum("mapYOffset", function() return config.mapYOffset end,
        function() return "Map Y-Offset: " .. config.mapYOffset .. " px" end,
        0, 300, 10, function(v) config.mapYOffset = v; SaveConfig() end)

    ModConfigMenu.AddSetting(MOD, "General", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return config.debugOverlay end,
        Display = function() return "Debug Overlay: " .. (config.debugOverlay and "On" or "Off") end,
        OnChange = function(v) config.debugOverlay = v; SaveConfig() end,
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

print("[CoopExtraHUD] Fully loaded with HUD mode support and configurable spacing!")
