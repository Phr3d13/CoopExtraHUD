-- MCM.lua: Mod Config Menu logic for CoopExtraHUD
-- This file contains all MCM registration, option helpers, and overlay flag logic.

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
        Display = function() return "HUD Mode: " .. (config.hudMode and "Vanilla+" or "Updated") end,
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

    -- Display Category (renamed from Display Options)
    local addNum = function(name, cur, disp, min, max, step, onchg, info)
        ModConfigMenu.AddSetting(MOD, "Display", {
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
        function() return "HUD Scale: " .. math.floor(config.scale * 100) .. "%" end,
        20, 100, 5, function(v) config.scale = v / 100; UpdateCurrentPreset(); SaveConfig() end,
        "Controls the overall size of all HUD elements. Smaller values make the HUD more compact.")
    addNum("opacity", function() return math.floor(config.opacity * 100) end,
        function() return "HUD Opacity: " .. math.floor(config.opacity * 100) .. "%" end,
        0, 100, 5, function(v) config.opacity = v / 100; UpdateCurrentPreset(); SaveConfig() end,
        "Controls the transparency of the HUD. Lower values make the HUD more see-through.")

    -- Spacing section
    ModConfigMenu.AddTitle(MOD, "Display", "Spacing")
    addNum("xSpacing", function() return config.xSpacing end,
        function() return "X Spacing: " .. config.xSpacing end,
        0, 50, 1, function(v) config.xSpacing = v; UpdateCurrentPreset(); SaveConfig() end,
        "Horizontal spacing between item icons. Higher values spread items further apart horizontally.")
    addNum("ySpacing", function() return config.ySpacing end,
        function() return "Y Spacing: " .. config.ySpacing end,
        0, 50, 1, function(v) config.ySpacing = v; UpdateCurrentPreset(); SaveConfig() end,
        "Vertical spacing between item rows. Higher values spread rows further apart vertically.")

    -- Divider section
    ModConfigMenu.AddTitle(MOD, "Display", "Divider")
    addNum("dividerOffset", function() return config.dividerOffset end,
        function() return "Divider X Offset: " .. config.dividerOffset end,
        -200, 200, 5, function(v) config.dividerOffset = v; UpdateCurrentPreset(); SaveConfig() end,
        "Horizontal offset of the divider line between players. Negative values move it left, positive values move it right.")
    addNum("dividerYOffset", function() return config.dividerYOffset end,
        function() return "Divider Y Offset: " .. config.dividerYOffset end,
        -200, 200, 5, function(v) config.dividerYOffset = v; UpdateCurrentPreset(); SaveConfig() end,
        "Vertical offset of the divider line between players. Negative values move it up, positive values move it down.")

    -- Offset section
    ModConfigMenu.AddTitle(MOD, "Display", "Offset")
    addNum("xOffset", function() return config.xOffset end,
        function() return "HUD X Offset: " .. config.xOffset end,
        -200, 200, 5, function(v) config.xOffset = v; UpdateCurrentPreset(); SaveConfig() end,
        "Overall horizontal position offset of the entire HUD. Negative values move it left, positive values move it right.")
    addNum("yOffset", function() return config.yOffset end,
        function() return "HUD Y Offset: " .. config.yOffset end,
        -200, 200, 5, function(v) config.yOffset = v; UpdateCurrentPreset(); SaveConfig() end,
        "Overall vertical position offset of the entire HUD. Negative values move it up, positive values move it down.")

    -- Boundaries Category
    ModConfigMenu.AddSpace(MOD, "Boundaries")
    -- Add Helper title and Clear Overlay Helper at the very top of Boundaries
    ModConfigMenu.AddTitle(MOD, "Boundaries", "Helper")
    ModConfigMenu.AddSetting(MOD, "Boundaries", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return false end,
        Display = function() return "Clear Overlay Helper" end,
        Info = "Clears any currently displayed overlay helpers. Use this if an overlay gets stuck on screen.",
        OnChange = function(v)
            if v and ExtraHUD then
                ExtraHUD.MCMCompat_displayingOverlay = ""
                ExtraHUD.MCMCompat_selectedOverlay = ""
                SaveConfig()
            end
        end,
    })
    ModConfigMenu.AddSpace(MOD, "Boundaries")
    ModConfigMenu.AddTitle(MOD, "Boundaries", "HUD Boundary")
    -- HUD Boundary section: all settings (no OnUpdate/OnLeave needed)
    -- Overlay flag logic: only show overlay if BOTH Display and OnSelect match
    -- Dual-flag overlay logic: display and selected must both match for overlay to show
    local function setBoundaryOverlayDisplayFlag()
        if ExtraHUD then
            ExtraHUD.MCMCompat_displayingOverlay = "boundary"
        end
    end
    local function setMinimapOverlayDisplayFlag()
        if ExtraHUD then
            ExtraHUD.MCMCompat_displayingOverlay = "minimap"
        end
    end
    local function setBoundaryOverlayFlag()
        if ExtraHUD then
            ExtraHUD.MCMCompat_selectedOverlay = "boundary"
        end
        config._mcm_boundary_overlay_refresh = (config._mcm_boundary_overlay_refresh or 0) + 1
    end
    local function setMinimapOverlayFlag()
        if ExtraHUD then
            ExtraHUD.MCMCompat_selectedOverlay = "minimap"
        end
        config._mcm_map_overlay_refresh = (config._mcm_map_overlay_refresh or 0) + 1
    end
    local function clearOverlayFlag()
        if ExtraHUD then
            ExtraHUD.MCMCompat_selectedOverlay = nil
        end
    end

    -- Extra: Clear overlay flag when switching category, tab, or option (robust for all MCM versions)
    -- 1. Category change
    if ModConfigMenu.AddCategoryCallback then
        ModConfigMenu.AddCategoryCallback(MOD, function()
            clearOverlayFlag()
        end)
    end
    if ModConfigMenu.AddTabCallback then
        ModConfigMenu.AddTabCallback(MOD, function()
            clearOverlayFlag()
        end)
    end
    -- 3. Option change: patch all OnSelect/OnLeave for all settings in Display category
    -- This ensures that leaving any option (not just boundary/minimap) clears the overlay flag
    local oldAddSetting = ModConfigMenu.AddSetting
    ModConfigMenu.AddSetting = function(mod, category, setting)
        if mod == MOD and category == "Display" then
            local origOnSelect = setting.OnSelect
            local origOnLeave = setting.OnLeave
            local isOverlayOption = false
            if setting.Display and type(setting.Display) == "function" then
                local disp = setting.Display()
                if disp:find("Boundary") or disp:find("Minimap") then
                    isOverlayOption = true
                end
            end
            setting.OnSelect = function(...)
                if origOnSelect then origOnSelect(...) end
                if not isOverlayOption then
                    clearOverlayFlag()
                end
            end
            setting.OnLeave = function(...)
                if origOnLeave then origOnLeave(...) end
                clearOverlayFlag()
            end
        end
        return oldAddSetting(mod, category, setting)
    end

    -- Force clear overlay flag on every frame while in MCM unless a boundary/minimap option is actively selected
    -- This is a workaround for MCM not always calling OnLeave reliably
    if ModConfigMenu.AddUpdateCallback then
        ModConfigMenu.AddUpdateCallback(MOD, function()
            -- If the selected overlay is set, but the currently focused option is not a boundary/minimap option, clear it
            local shouldClear = false
            if ExtraHUD and ExtraHUD.MCMCompat_selectedOverlay then
                local mcm = _G.ModConfigMenu
                local cur = mcm and mcm.CurrentSetting and mcm.CurrentSetting[MOD] and mcm.CurrentSetting[MOD]["Display"]
                if cur and cur.Display and type(cur.Display) == "function" then
                    local disp = cur.Display()
                    if not (disp:find("Boundary") or disp:find("Minimap")) then
                        shouldClear = true
                    end
                else
                    shouldClear = true
                end
            end
            if ExtraHUD and ExtraHUD.MCMCompat_selectedOverlay and shouldClear then
                clearOverlayFlag()
            end
        end)
    end
    -- Ensure OnLeave = clearOverlayFlag for all boundary overlay options
    local boundaryOptions = {
        { name = "Boundary X", key = "boundaryX", min = 0, max = 3840, step = 1, info = "Left edge of the HUD boundary area. The HUD will be positioned within this boundary." },
        { name = "Boundary Y", key = "boundaryY", min = 0, max = 2160, step = 1, info = "Top edge of the HUD boundary area. The HUD will be positioned within this boundary." },
        { name = "Boundary Width", key = "boundaryW", min = 32, max = 3840, step = 1, info = "Width of the HUD boundary area. Make this larger to give the HUD more horizontal space." },
        { name = "Boundary Height", key = "boundaryH", min = 32, max = 2160, step = 1, info = "Height of the HUD boundary area. Make this larger to give the HUD more vertical space." },
    }
    for _, opt in ipairs(boundaryOptions) do
        ModConfigMenu.AddSetting(MOD, "Boundaries", {
            Type = ModConfigMenu.OptionType.NUMBER,
            CurrentSetting = function() return config[opt.key] end,
            Display = function()
                return opt.name .. ": " .. config[opt.key]
            end,
            Info = opt.info,
            OnChange = function(v)
                config[opt.key] = v; UpdateCurrentPreset(); SaveConfig();
                if ExtraHUD then
                    ExtraHUD.MCMCompat_displayingOverlay = "boundary"
                    ExtraHUD.MCMCompat_selectedOverlay = "boundary"
                    -- Invalidate caches so overlay updates immediately
                    if ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
                end
            end,
            OnSelect = function(...)
                if ExtraHUD then
                    ExtraHUD.MCMCompat_displayingOverlay = "boundary"
                    ExtraHUD.MCMCompat_selectedOverlay = "boundary"
                end
            end,
            OnLeave = function(...)
                if ExtraHUD then
                    ExtraHUD.MCMCompat_displayingOverlay = ""
                    ExtraHUD.MCMCompat_selectedOverlay = ""
                end
            end,
            Minimum = opt.min, Maximum = opt.max, Step = opt.step,
        })
    end
    -- Minimap Avoidance section
    ModConfigMenu.AddSpace(MOD, "Boundaries")
    ModConfigMenu.AddTitle(MOD, "Boundaries", "Minimap Avoidance Area")
    -- Add auto-align as a button-like toggle (like resetFlag)
    local minimapAutoAlignFlag = false
    ModConfigMenu.AddSetting(MOD, "Boundaries", {
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
    -- Minimap Avoidance section: all settings (no OnUpdate/OnLeave needed)
    -- setMinimapOverlayFlag is now defined above with correct overlay type
    -- Ensure OnLeave = clearOverlayFlag for all minimap overlay options
    local minimapOptions = {
        { name = "Minimap X", key = "minimapX", min = 0, max = 3840, step = 1, info = "Left edge of the minimap area. The HUD will avoid overlapping with this area." },
        { name = "Minimap Y", key = "minimapY", min = 0, max = 2160, step = 1, info = "Top edge of the minimap area. The HUD will avoid overlapping with this area." },
        { name = "Minimap Width", key = "minimapW", min = 0, max = 3840, step = 1, info = "Width of the minimap area that the HUD should avoid overlapping." },
        { name = "Minimap Height", key = "minimapH", min = 0, max = 2160, step = 1, info = "Height of the minimap area that the HUD should avoid overlapping." },
    }
    for _, opt in ipairs(minimapOptions) do
        ModConfigMenu.AddSetting(MOD, "Boundaries", {
            Type = ModConfigMenu.OptionType.NUMBER,
            CurrentSetting = function() return config[opt.key] end,
            Display = function()
                return opt.name .. ": " .. config[opt.key]
            end,
            Info = opt.info,
            OnChange = function(v)
                config[opt.key] = v; UpdateCurrentPreset(); SaveConfig();
                if ExtraHUD then
                    ExtraHUD.MCMCompat_displayingOverlay = "minimap"
                    ExtraHUD.MCMCompat_selectedOverlay = "minimap"
                    -- Invalidate caches so overlay updates immediately
                    if ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
                end
            end,
            OnSelect = function(...)
                if ExtraHUD then
                    ExtraHUD.MCMCompat_displayingOverlay = "minimap"
                    ExtraHUD.MCMCompat_selectedOverlay = "minimap"
                end
            end,
            OnLeave = function(...)
                if ExtraHUD then
                    ExtraHUD.MCMCompat_displayingOverlay = ""
                    ExtraHUD.MCMCompat_selectedOverlay = ""
                end
            end,
            Minimum = opt.min, Maximum = opt.max, Step = opt.step,
        })
    end
    -- Debug Category (renamed from Debugging)
    ModConfigMenu.AddSpace(MOD, "Debug")
    ModConfigMenu.AddTitle(MOD, "Debug", "Debug")
    ModConfigMenu.AddSetting(MOD, "Debug", {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function() return config.debugOverlay end,
        Display = function() return "Debug Overlay: " .. (config.debugOverlay and "ON" or "OFF") end,
        Info = "Shows visual overlays with colored corner markers indicating the HUD boundary (red), minimap area (cyan), and actual HUD position (green). Useful for positioning and troubleshooting.",
        OnChange = function(v)
            config.debugOverlay = v; UpdateCurrentPreset(); SaveConfig();
            if ExtraHUD and ExtraHUD.OnOverlayAdjusterMoved then ExtraHUD.OnOverlayAdjusterMoved() end
        end,
    })

    print("[CoopExtraHUD] Config menu registered.")
end

return M
