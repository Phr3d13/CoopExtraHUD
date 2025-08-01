local ModConfigMenu = _G.ModConfigMenu
-- MCM.lua: Mod Config Menu logic for CoopExtraHUD
-- This file contains all MCM registration, option helpers, and overlay flag logic.
--
-- OVERLAY SYSTEM: Uses EID-style automatic overlay detection.
-- Overlays automatically appear when viewing relevant MCM tabs (HUD, Boundaries, Minimap)
-- with color-coded corner markers for each overlay type (red=boundary, cyan=minimap, green=HUD offset).

local M = {}


local config, configPresets, SaveConfig, LoadConfig, UpdateCurrentPreset, ExtraHUD

-- Called by main.lua to initialize MCM logic and return config tables/functions
function M.Init(args)
    -- args: { ExtraHUD = ..., config = ..., configPresets = ..., SaveConfig = ..., LoadConfig = ..., UpdateCurrentPreset = ... }
    ExtraHUD = args.ExtraHUD
    config = args.config
    configPresets = args.configPresets
    SaveConfig = args.SaveConfig
    LoadConfig = args.LoadConfig
    UpdateCurrentPreset = args.UpdateCurrentPreset
    
    -- Initialize the MCM tab tracking variable
    if ExtraHUD then
        ExtraHUD.MCMCompat_displayingTab = ""
    end
    
    local returnTable = {
        config = config,
        configPresets = configPresets,
        SaveConfig = SaveConfig,
        LoadConfig = LoadConfig,
        UpdateCurrentPreset = UpdateCurrentPreset,
        UpdateMCMOverlayDisplay = M.UpdateMCMOverlayDisplay,
    }
    
    return returnTable
end

local configMenuRegistered = false

-- MCM focus tracking for overlay system
function M.UpdateMCMOverlayDisplay()
    if not ModConfigMenu then
        return
    end
    
    if not ExtraHUD then
        return
    end
    
    -- Check if GetCurrentFocus exists
    if not ModConfigMenu.GetCurrentFocus then
        ExtraHUD.MCMCompat_displayingTab = ""
        return
    end
    
    -- Use the new GetCurrentFocus API to detect what's being hovered
    local focus = ModConfigMenu.GetCurrentFocus()
    if not focus then
        ExtraHUD.MCMCompat_displayingTab = ""
        return
    end
    
    if not focus.category or not focus.subcategory then
        ExtraHUD.MCMCompat_displayingTab = ""
        return
    end
    
    -- Check if we're in the CoopExtraHUD category
    if focus.category.Name == "CoopExtraHUD" then
        local subcategoryName = focus.subcategory.Name or ""
        
        -- Map subcategory names to overlay types
        if subcategoryName == "HUD" then
            ExtraHUD.MCMCompat_displayingTab = "hud_offset"
        elseif subcategoryName == "Boundaries" then
            ExtraHUD.MCMCompat_displayingTab = "boundary"
        elseif subcategoryName == "Minimap" then
            ExtraHUD.MCMCompat_displayingTab = "minimap"
        else
            ExtraHUD.MCMCompat_displayingTab = ""
        end
    else
        ExtraHUD.MCMCompat_displayingTab = ""
    end
end

function M.RegisterConfigMenu()
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
        Display = function()
            return "HUD Mode: " .. (config.hudMode and "Vanilla+" or "Updated")
        end,
        Info = "Choose between Updated (modern look) and Vanilla+ (classic look) HUD styles. Each mode has different default values for scale, spacing, and positioning.",
        OnChange = function(v)
            config.hudMode = v
            -- Apply preset values when toggled
            local preset = configPresets[v]
            if preset then
                for k, val in pairs(preset) do
                    config[k] = val
                end
            end
            -- Always set hideHudOnPause to false on preset switch
            config.hideHudOnPause = false
            SaveConfig()
            -- Invalidate caches so HUD updates immediately
            if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
        end,
    })

    -- Add reset to defaults option as a boolean toggle (workaround for no BUTTON type)
    local resetFlag = false
    ModConfigMenu.AddSetting(MOD, "Presets", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return resetFlag end,
        Display = function() return "Reset Current Preset to Defaults" end,
        Info = "Resets all display settings (scale, spacing, divider, offset, opacity) to their default values for the currently selected HUD mode.",
        OnChange = function(v)
            if v then
                local defaults = {
                    [false] = { scale = 0.4, xSpacing = 5, ySpacing = 5, dividerOffset = -20, dividerYOffset = 0, xOffset = 10, yOffset = -10, opacity = 0.8, hideHudOnPause = false },
                    [true]  = { scale = 0.6, xSpacing = 8, ySpacing = 8, dividerOffset = -16, dividerYOffset = 0, xOffset = 32, yOffset = 32, opacity = 0.85, hideHudOnPause = false }
                }
                local mode = config.hudMode
                for k, v in pairs(defaults[mode]) do
                    configPresets[mode][k] = v
                    config[k] = v
                end
                UpdateCurrentPreset()
                SaveConfig()
                resetFlag = false -- immediately reset toggle
                -- Invalidate caches so HUD updates immediately
                if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
            end
        end,
    })

    -- Add auto-adjust on resize option
    ModConfigMenu.AddSetting(MOD, "Presets", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return config.autoAdjustOnResize end,
        Display = function() return "Auto-Adjust on Resize: " .. (config.autoAdjustOnResize and "ON" or "OFF") end,
        Info = "Automatically adjusts HUD boundary position when the game window is resized to maintain relative positioning. Helps keep the HUD in the right place across different resolutions.",
        OnChange = function(v)
            config.autoAdjustOnResize = v
            UpdateCurrentPreset()
            SaveConfig()
            -- Invalidate caches so HUD updates immediately
            if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
        end,
    })

    -- Item Layout Mode
    ModConfigMenu.AddSetting(MOD, "Presets", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return config.itemLayoutMode == "2x2_grid" end,
        Display = function()
            return "Item Layout: " .. (config.itemLayoutMode == "2x2_grid" and "2x2 Grid" or "4 Across")
        end,
        Info = "Choose item arrangement style. '4 Across' displays items in horizontal rows (classic). '2x2 Grid' arranges items in 2x2 blocks for a more compact layout.",
        OnChange = function(v)
            config.itemLayoutMode = v and "2x2_grid" or "4_across"
            UpdateCurrentPreset()
            SaveConfig()
            -- Invalidate caches so HUD updates immediately
            if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
        end,
    })


    -- Head Category
    ModConfigMenu.AddSpace(MOD, "Head")
    ModConfigMenu.AddTitle(MOD, "Head", "Character Head Icons")

    -- Show Character Head Icons toggle (moved from Display)
    ModConfigMenu.AddSetting(MOD, "Head", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return config.showCharHeadIcons end,
        Display = function()
            return "Show Character Head Icons: " .. (config.showCharHeadIcons and "ON" or "OFF")
        end,
        Info = "If enabled, displays each player's character head icon (as seen in the coop join screen) next to their item row in the HUD.",
        OnChange = function(v)
            config.showCharHeadIcons = v; UpdateCurrentPreset(); SaveConfig();
            if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
        end,
    })

    -- Head Icon X Offset
    ModConfigMenu.AddSetting(MOD, "Head", {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return config.headIconXOffset or 0 end,
        Display = function()
            return "Head Icon X Offset: " .. (config.headIconXOffset or 0)
        end,
        Info = "Horizontal offset for the character head icon relative to its default position. Negative values move it left, positive values move it right.",
        OnChange = function(v)
            config.headIconXOffset = v; UpdateCurrentPreset(); SaveConfig();
            if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
        end,
        Minimum = -200, Maximum = 200, Step = 1,
    })

    -- Head Icon Y Offset
    ModConfigMenu.AddSetting(MOD, "Head", {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return config.headIconYOffset or 0 end,
        Display = function()
            return "Head Icon Y Offset: " .. (config.headIconYOffset or 0)
        end,
        Info = "Vertical offset for the character head icon relative to its default position. Negative values move it up, positive values move it down.",
        OnChange = function(v)
            config.headIconYOffset = v; UpdateCurrentPreset(); SaveConfig();
            if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
        end,
        Minimum = -200, Maximum = 200, Step = 1,
    })

    -- Display Category (renamed from Display Options)
    local addNum = function(name, cur, disp, min, max, step, onchg, info, category)
        ModConfigMenu.AddSetting(MOD, category or "Display", {
            Type = ModConfigMenu.OptionType.NUMBER,
            CurrentSetting = cur, Display = disp, 
            Info = info,
            OnChange = function(v) 
                onchg(v)
                -- Invalidate caches so HUD updates immediately
                if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
            end,
            Minimum = min, Maximum = max, Step = step,
        })
    end

    ModConfigMenu.AddSpace(MOD, "Display")
    ModConfigMenu.AddTitle(MOD, "Display", "Display")

    -- Scale and Opacity at the top
    addNum("scale", function() return math.floor(config.scale * 100) end,
        function()
            return "HUD Scale: " .. math.floor(config.scale * 100) .. "%"
        end,
        20, 100, 5, function(v) config.scale = v / 100; UpdateCurrentPreset(); SaveConfig() end,
        "Controls the overall size of all HUD elements. Smaller values make the HUD more compact.")
    addNum("opacity", function() return math.floor(config.opacity * 100) end,
        function()
            return "HUD Opacity: " .. math.floor(config.opacity * 100) .. "%"
        end,
        0, 100, 5, function(v) config.opacity = v / 100; UpdateCurrentPreset(); SaveConfig() end,
        "Controls the transparency of the HUD. Lower values make the HUD more see-through.")

    -- Spacing section
    ModConfigMenu.AddTitle(MOD, "Display", "Spacing")
    addNum("xSpacing", function() return config.xSpacing end,
        function()
            return "X Spacing: " .. config.xSpacing
        end,
        0, 50, 1, function(v) config.xSpacing = v; UpdateCurrentPreset(); SaveConfig() end,
        "Horizontal spacing between item icons. Higher values spread items further apart horizontally.")
    addNum("ySpacing", function() return config.ySpacing end,
        function()
            return "Y Spacing: " .. config.ySpacing
        end,
        0, 50, 1, function(v) config.ySpacing = v; UpdateCurrentPreset(); SaveConfig() end,
        "Vertical spacing between item rows. Higher values spread rows further apart vertically.")

    -- Divider section
    ModConfigMenu.AddTitle(MOD, "Display", "Divider")
    addNum("dividerOffset", function() return config.dividerOffset end,
        function()
            return "Divider X Offset: " .. config.dividerOffset
        end,
        -200, 200, 5, function(v) config.dividerOffset = v; UpdateCurrentPreset(); SaveConfig() end,
        "Horizontal offset of the divider line between players. Negative values move it left, positive values move it right.")
    addNum("dividerYOffset", function() return config.dividerYOffset end,
        function()
            return "Divider Y Offset: " .. config.dividerYOffset
        end,
        -200, 200, 5, function(v) config.dividerYOffset = v; UpdateCurrentPreset(); SaveConfig() end,
        "Vertical offset of the divider line between players. Negative values move it up, positive values move it down.")

    -- HUD Category (separate from Display for automatic overlay)
    ModConfigMenu.AddSpace(MOD, "HUD")
    ModConfigMenu.AddTitle(MOD, "HUD", "HUD Position")
    
    -- HUD X Offset setting (automatic overlay when on this tab)
    addNum("xOffset", function() return config.xOffset end,
        function()
            if ExtraHUD then ExtraHUD.MCMCompat_displayingTab = "HUD" end
            return "HUD X Offset: " .. config.xOffset
        end,
        -200, 200, 5, function(v) config.xOffset = v; UpdateCurrentPreset(); SaveConfig() end,
        "Overall horizontal position offset of the entire HUD. Negative values move it left, positive values move it right.", "HUD")
    
    -- HUD Y Offset setting (automatic overlay when on this tab)
    addNum("yOffset", function() return config.yOffset end,
        function()
            if ExtraHUD then ExtraHUD.MCMCompat_displayingTab = "HUD" end
            return "HUD Y Offset: " .. config.yOffset
        end,
        -200, 200, 5, function(v) config.yOffset = v; UpdateCurrentPreset(); SaveConfig() end,
        "Overall vertical position offset of the entire HUD. Negative values move it up, positive values move it down.", "HUD")

    -- Boundaries Category
    ModConfigMenu.AddSpace(MOD, "Boundaries")
    ModConfigMenu.AddTitle(MOD, "Boundaries", "HUD Boundary")
    
    local boundaryOptions = {
        { name = "Boundary X", key = "boundaryX", min = 0, max = 640, step = 1, info = "Left edge of the HUD boundary area. The HUD will be positioned within this boundary." },
        { name = "Boundary Y", key = "boundaryY", min = 0, max = 480, step = 1, info = "Top edge of the HUD boundary area. The HUD will be positioned within this boundary." },
        { name = "Boundary Width", key = "boundaryW", min = 32, max = 640, step = 1, info = "Width of the HUD boundary area. Make this larger to give the HUD more horizontal space." },
        { name = "Boundary Height", key = "boundaryH", min = 32, max = 480, step = 1, info = "Height of the HUD boundary area. Make this larger to give the HUD more vertical space." },
    }
    for _, opt in ipairs(boundaryOptions) do
        addNum(opt.key, function() return config[opt.key] end,
            function()
                if ExtraHUD then ExtraHUD.MCMCompat_displayingTab = "Boundaries" end
                return opt.name .. ": " .. config[opt.key]
            end,
            opt.min, opt.max, opt.step, function(v) config[opt.key] = v; UpdateCurrentPreset(); SaveConfig() end,
            opt.info, "Boundaries")
    end
    -- Minimap Category (separate from Boundaries for automatic overlay)
    ModConfigMenu.AddSpace(MOD, "Minimap")
    ModConfigMenu.AddTitle(MOD, "Minimap", "Minimap Avoidance Area")
    -- Add auto-align as a button-like toggle (like resetFlag)
    local minimapAutoAlignFlag = false
    ModConfigMenu.AddSetting(MOD, "Minimap", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return minimapAutoAlignFlag end,
        Display = function() return "Auto-Align Minimap (Top-Right)" end,
        Info = "Automatically sets the minimap position to the top-right corner of the screen. This helps ensure the HUD avoids the minimap correctly.",
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
    
    local minimapOptions = {
        { name = "Minimap X", key = "minimapX", min = 0, max = 640, step = 1, info = "Left edge of the minimap area. The HUD will avoid overlapping with this area." },
        { name = "Minimap Y", key = "minimapY", min = 0, max = 480, step = 1, info = "Top edge of the minimap area. The HUD will avoid overlapping with this area." },
        { name = "Minimap Width", key = "minimapW", min = 0, max = 640, step = 1, info = "Width of the minimap area that the HUD should avoid overlapping." },
        { name = "Minimap Height", key = "minimapH", min = 0, max = 480, step = 1, info = "Height of the minimap area that the HUD should avoid overlapping." },
    }
    for _, opt in ipairs(minimapOptions) do
        addNum(opt.key, function() return config[opt.key] end,
            function()
                if ExtraHUD then ExtraHUD.MCMCompat_displayingTab = "Minimap" end
                return opt.name .. ": " .. config[opt.key]
            end,
            opt.min, opt.max, opt.step, function(v) config[opt.key] = v; UpdateCurrentPreset(); SaveConfig() end,
            opt.info, "Minimap")
    end
    -- Debug Category (renamed from Debugging)
    ModConfigMenu.AddSpace(MOD, "Debug")
    ModConfigMenu.AddTitle(MOD, "Debug", "Debug")
    ModConfigMenu.AddSetting(MOD, "Debug", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return config.debugOverlay end,
        Display = function()
            return "Debug Overlay: " .. (config.debugOverlay and "ON" or "OFF")
        end,
        Info = "Shows visual overlays with colored corner markers indicating the HUD boundary (red), minimap area (cyan), and actual HUD position (green). Useful for positioning and troubleshooting.",
        OnChange = function(v)
            config.debugOverlay = v; UpdateCurrentPreset(); SaveConfig();
            if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
        end,
    })

    -- Temporary: Combo Divider Y Offset for Jacob+Esau block
    -- Combo Divider Offsets for Jacob+Esau block (Y and X grouped together)
    ModConfigMenu.AddSetting(MOD, "Debug", {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return config.comboDividerYOffset or 0 end,
        Display = function()
            return "Combo Divider Y Offset: " .. (config.comboDividerYOffset or 0)
        end,
        Info = "TEMPORARY: Adjusts the vertical offset (in pixels, scaled) of the horizontal divider between Jacob and Esau in the combo block. Use for fine-tuning.",
        OnChange = function(v)
            config.comboDividerYOffset = v; UpdateCurrentPreset(); SaveConfig();
            if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
        end,
        Minimum = -200, Maximum = 200, Step = 1,
    })
    ModConfigMenu.AddSetting(MOD, "Debug", {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return config.comboDividerXOffset or 0 end,
        Display = function()
            return "Combo Divider X Offset: " .. (config.comboDividerXOffset or 0)
        end,
        Info = "TEMPORARY: Adjusts the horizontal offset (in pixels, scaled) of the horizontal divider between Jacob and Esau in the combo block. Use for fine-tuning.",
        OnChange = function(v)
            config.comboDividerXOffset = v; UpdateCurrentPreset(); SaveConfig();
            if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
        end,
        Minimum = -200, Maximum = 200, Step = 1,
    })
    -- Gap between J&E's heads and first items
    ModConfigMenu.AddSetting(MOD, "Debug", {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return config.comboHeadToItemsGap or 8 end,
        Display = function()
            return "J&E Head-to-Items Gap: " .. (config.comboHeadToItemsGap or 8)
        end,
        Info = "TEMPORARY: Adjusts the gap (in pixels, scaled) between Jacob & Esau's heads and their first item row in the combo block.",
        OnChange = function(v)
            config.comboHeadToItemsGap = v; UpdateCurrentPreset(); SaveConfig();
            if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
        end,
        Minimum = 0, Maximum = 64, Step = 1,
    })
    -- Gap between Jacob's chunk and Esau's chunk
    ModConfigMenu.AddSetting(MOD, "Debug", {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return config.comboChunkGap or 8 end,
        Display = function()
            return "J&E Chunk-to-Chunk Gap: " .. (config.comboChunkGap or 8)
        end,
        Info = "TEMPORARY: Adjusts the gap (in pixels, scaled) between Jacob's item chunk and Esau's item chunk in the combo block.",
        OnChange = function(v)
            config.comboChunkGap = v; UpdateCurrentPreset(); SaveConfig();
            if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
        end,
        Minimum = -64, Maximum = 64, Step = 1,
    })

    -- J&E Scale adjuster (comboScale)
    ModConfigMenu.AddSetting(MOD, "Debug", {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return math.floor((config.comboScale or 1.0) * 100) end,
        Display = function()
            return "J&E Scale Adjuster: " .. math.floor((config.comboScale or 1.0) * 100) .. "%"
        end,
        Info = "TEMPORARY: Adjusts the scale of the entire Jacob+Esau combo block. 100% = normal, lower = smaller, higher = larger.",
        OnChange = function(v)
            config.comboScale = v / 100; UpdateCurrentPreset(); SaveConfig();
            if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
        end,
        Minimum = 50, Maximum = 200, Step = 5,
    })

    -- J&E Chunk Character Divider Y Offset (comboChunkDividerYOffset)
    ModConfigMenu.AddSetting(MOD, "Debug", {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function() return config.comboChunkDividerYOffset or 44 end,
        Display = function()
            return "J&E Chunk Divider Y Offset: " .. (config.comboChunkDividerYOffset or 0)
        end,
        Info = "TEMPORARY: Adjusts the vertical offset (in pixels, scaled) of the vertical divider between the Jacob+Esau combo block and the next player block. Only affects the divider after the J&E chunk.",
        OnChange = function(v)
            config.comboChunkDividerYOffset = v; UpdateCurrentPreset(); SaveConfig();
            if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
        end,
        Minimum = -200, Maximum = 200, Step = 1,
    })

    -- Add Hide HUD on Pause option to Display category
    ModConfigMenu.AddSetting(MOD, "Display", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return config.hideHudOnPause end,
        Display = function()
            return "Hide HUD When Paused: " .. (config.hideHudOnPause and "ON" or "OFF")
        end,
        Info = "If enabled, the CoopExtraHUD will be hidden when the game is paused.",
        OnChange = function(v)
            config.hideHudOnPause = v; UpdateCurrentPreset(); SaveConfig();
            if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
        end,
    })

    print("[CoopExtraHUD] Config menu registered.")
end

return M
