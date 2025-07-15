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
        ExtraHUD.MCMCompat_displayingEIDTab = ""
    end
    
    return {
        config = config,
        configPresets = configPresets,
        SaveConfig = SaveConfig,
        LoadConfig = LoadConfig,
        UpdateCurrentPreset = UpdateCurrentPreset,
    }
end

local configMenuRegistered = false

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
            -- Clear overlay when viewing categories that don't need helpers
            if ExtraHUD then
                ExtraHUD.MCMCompat_displayingEIDTab = ""
                -- Immediately clear overlay flags too
                ExtraHUD.MCMCompat_displayingOverlay = ""
                ExtraHUD.MCMCompat_selectedOverlay = ""
            end
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
            -- Clear overlay when viewing categories that don't need helpers
            if ExtraHUD then
                ExtraHUD.MCMCompat_displayingEIDTab = ""
                -- Immediately clear overlay flags too
                ExtraHUD.MCMCompat_displayingOverlay = ""
                ExtraHUD.MCMCompat_selectedOverlay = ""
            end
            return "HUD Scale: " .. math.floor(config.scale * 100) .. "%" 
        end,
        20, 100, 5, function(v) config.scale = v / 100; UpdateCurrentPreset(); SaveConfig() end,
        "Controls the overall size of all HUD elements. Smaller values make the HUD more compact.")
    addNum("opacity", function() return math.floor(config.opacity * 100) end,
        function() 
            -- Clear overlay when viewing categories that don't need helpers
            if ExtraHUD then
                ExtraHUD.MCMCompat_displayingEIDTab = ""
                -- Immediately clear overlay flags too
                ExtraHUD.MCMCompat_displayingOverlay = ""
                ExtraHUD.MCMCompat_selectedOverlay = ""
            end
            return "HUD Opacity: " .. math.floor(config.opacity * 100) .. "%" 
        end,
        0, 100, 5, function(v) config.opacity = v / 100; UpdateCurrentPreset(); SaveConfig() end,
        "Controls the transparency of the HUD. Lower values make the HUD more see-through.")

    -- Spacing section
    ModConfigMenu.AddTitle(MOD, "Display", "Spacing")
    addNum("xSpacing", function() return config.xSpacing end,
        function() 
            -- Clear overlay when viewing categories that don't need helpers
            if ExtraHUD then
                ExtraHUD.MCMCompat_displayingEIDTab = ""
                -- Immediately clear overlay flags too
                ExtraHUD.MCMCompat_displayingOverlay = ""
                ExtraHUD.MCMCompat_selectedOverlay = ""
            end
            return "X Spacing: " .. config.xSpacing 
        end,
        0, 50, 1, function(v) config.xSpacing = v; UpdateCurrentPreset(); SaveConfig() end,
        "Horizontal spacing between item icons. Higher values spread items further apart horizontally.")
    addNum("ySpacing", function() return config.ySpacing end,
        function() 
            -- Clear overlay when viewing categories that don't need helpers
            if ExtraHUD then
                ExtraHUD.MCMCompat_displayingEIDTab = ""
                -- Immediately clear overlay flags too
                ExtraHUD.MCMCompat_displayingOverlay = ""
                ExtraHUD.MCMCompat_selectedOverlay = ""
            end
            return "Y Spacing: " .. config.ySpacing 
        end,
        0, 50, 1, function(v) config.ySpacing = v; UpdateCurrentPreset(); SaveConfig() end,
        "Vertical spacing between item rows. Higher values spread rows further apart vertically.")

    -- Divider section
    ModConfigMenu.AddTitle(MOD, "Display", "Divider")
    addNum("dividerOffset", function() return config.dividerOffset end,
        function() 
            -- Clear overlay when viewing categories that don't need helpers
            if ExtraHUD then
                ExtraHUD.MCMCompat_displayingEIDTab = ""
                -- Immediately clear overlay flags too
                ExtraHUD.MCMCompat_displayingOverlay = ""
                ExtraHUD.MCMCompat_selectedOverlay = ""
            end
            return "Divider X Offset: " .. config.dividerOffset 
        end,
        -200, 200, 5, function(v) config.dividerOffset = v; UpdateCurrentPreset(); SaveConfig() end,
        "Horizontal offset of the divider line between players. Negative values move it left, positive values move it right.")
    addNum("dividerYOffset", function() return config.dividerYOffset end,
        function() 
            -- Clear overlay when viewing categories that don't need helpers
            if ExtraHUD then
                ExtraHUD.MCMCompat_displayingEIDTab = ""
                -- Immediately clear overlay flags too
                ExtraHUD.MCMCompat_displayingOverlay = ""
                ExtraHUD.MCMCompat_selectedOverlay = ""
            end
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
            -- Auto-show HUD offset overlay when adjusting these settings
            if ExtraHUD then
                ExtraHUD.MCMCompat_displayingEIDTab = "HUD"
            end
            return "HUD X Offset: " .. config.xOffset 
        end,
        -200, 200, 5, function(v) config.xOffset = v; UpdateCurrentPreset(); SaveConfig() end,
        "Overall horizontal position offset of the entire HUD. Negative values move it left, positive values move it right.", "HUD")
    
    -- HUD Y Offset setting (automatic overlay when on this tab)
    addNum("yOffset", function() return config.yOffset end,
        function() 
            -- Auto-show HUD offset overlay when adjusting these settings
            if ExtraHUD then
                ExtraHUD.MCMCompat_displayingEIDTab = "HUD"
            end
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
                -- Auto-show boundary overlay when adjusting boundary settings
                if ExtraHUD then
                    ExtraHUD.MCMCompat_displayingEIDTab = "Boundaries"
                end
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
                -- Auto-show minimap overlay when adjusting minimap settings
                if ExtraHUD then
                    ExtraHUD.MCMCompat_displayingEIDTab = "Minimap"
                end
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
            -- Clear overlay when viewing categories that don't need helpers
            if ExtraHUD then
                ExtraHUD.MCMCompat_displayingEIDTab = ""
                -- Immediately clear overlay flags too
                ExtraHUD.MCMCompat_displayingOverlay = ""
                ExtraHUD.MCMCompat_selectedOverlay = ""
            end
            return "Debug Overlay: " .. (config.debugOverlay and "ON" or "OFF") 
        end,
        Info = "Shows visual overlays with colored corner markers indicating the HUD boundary (red), minimap area (cyan), and actual HUD position (green). Useful for positioning and troubleshooting.",
        OnChange = function(v)
            config.debugOverlay = v; UpdateCurrentPreset(); SaveConfig();
            if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
        end,
    })

    print("[CoopExtraHUD] Config menu registered.")
end

return M
