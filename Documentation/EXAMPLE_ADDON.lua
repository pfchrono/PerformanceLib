-- =========================================================================
-- EXAMPLE ADDON - Using PerformanceLib
-- =========================================================================
-- This is an example addon that demonstrates how to use PerformanceLib.
-- Copy this as a template for your own addon.
--
-- File: ExamplePerformantAddon.lua

local addon = CreateFrame("Frame")
addon.name = "ExamplePerformantAddon"
addon.frames = {}
addon.inCombat = false

-- =========================================================================
-- INITIALIZATION
-- =========================================================================

addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_REGEN_DISABLED")
addon:RegisterEvent("PLAYER_REGEN_ENABLED")
addon:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and ... == "ExamplePerformantAddon" then
        self:OnAddonLoaded()
    elseif event == "PLAYER_REGEN_DISABLED" then
        self.inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.inCombat = false
    end
end)

function addon:OnAddonLoaded()
    print("ExamplePerformantAddon: Initializing with PerformanceLib")
    
    -- Initialize PerformanceLib
    PerformanceLib:Initialize(self.name)
    PerformanceLib:SetPreset("High")
    
    -- Create example unit frames
    self:CreateUnitFrames()
    
    -- Register event handler with batching
    self:RegisterEventHandlers()
    
    -- Show initial message
    print("|cFF00FF00ExamplePerformantAddon ready!|r")
    print("|cFFFFFF00Type /perflib help for dashboard commands|r")
end

-- =========================================================================
-- UNIT FRAME CREATION
-- =========================================================================

function addon:CreateUnitFrames()
    -- Create frames for player, target
    for _, unit in ipairs({"player", "target"}) do
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetSize(200, 50)
        
        if unit == "player" then
            frame:SetPoint("LEFT", 20, 0)
        else
            frame:SetPoint("RIGHT", -20, 0)
        end
        
        -- Health bar
        frame.healthBar = CreateFrame("StatusBar", nil, frame)
        frame.healthBar:SetAllPoints()
        frame.healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        frame.healthBar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
        
        -- Health text
        frame.healthText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.healthText:SetPoint("CENTER", frame, "CENTER")
        
        -- Store frame
        self.frames[unit] = frame
        frame.unit = unit
        
        -- Mark for initial update
        PerformanceLib:MarkFrameDirty(frame, PerformanceLib.DirtyFlagManager.PRIORITY_HIGH)
    end
end

-- =========================================================================
-- EVENT HANDLING WITH COALESCING
-- =========================================================================

function addon:RegisterEventHandlers()
    -- Register only for relevant units (player/target) to avoid raid-wide UNIT_* spam.
    local frame = CreateFrame("Frame")
    frame:RegisterUnitEvent("UNIT_HEALTH", "player", "target")
    frame:RegisterUnitEvent("UNIT_MAXHEALTH", "player", "target")
    frame:RegisterUnitEvent("UNIT_NAME_UPDATE", "player", "target")
    
    frame:SetScript("OnEvent", function(self, event, unit, ...)
        addon:OnEvent(event, unit, ...)
    end)
end

function addon:OnEvent(event, unit, ...)
    if event == "UNIT_HEALTH" then
        -- Queue event with HIGH priority (minimal batching)
        PerformanceLib:QueueEvent(
            event,
            PerformanceLib.EventCoalescer.PRIORITY_HIGH,
            unit
        )
        
        -- Mark frame dirty for batched update
        if self.frames[unit] then
            PerformanceLib:MarkFrameDirty(
                self.frames[unit],
                PerformanceLib.DirtyFlagManager.PRIORITY_HIGH
            )
        end
        
    elseif event == "UNIT_MAXHEALTH" then
        -- Queue with MEDIUM priority
        PerformanceLib:QueueEvent(
            event,
            PerformanceLib.EventCoalescer.PRIORITY_MEDIUM,
            unit
        )
        if self.frames[unit] then
            PerformanceLib:MarkFrameDirty(
                self.frames[unit],
                PerformanceLib.DirtyFlagManager.PRIORITY_MEDIUM
            )
        end
        
    elseif event == "UNIT_NAME_UPDATE" then
        -- Queue with LOW priority (cosmetic)
        PerformanceLib:QueueEvent(
            event,
            PerformanceLib.EventCoalescer.PRIORITY_LOW,
            unit
        )
    end
end

-- =========================================================================
-- FRAME UPDATES
-- =========================================================================

-- Add update method that will be called by DirtyFlagManager
function CreateUpdateMethod(frame)
    frame.Update = function(self)
        local unit = self.unit
        local healthCurrent = UnitHealth(unit)
        local healthMax = UnitHealthMax(unit)
        
        if healthMax > 0 then
            self.healthBar:SetValue(healthCurrent / healthMax)
        end
        
        self.healthText:SetText(healthCurrent .. "/" .. healthMax)
    end
    
    return frame
end

for unit, frame in pairs(addon.frames) do
    CreateUpdateMethod(frame)
end

-- =========================================================================
-- PERFORMANCE MONITORING
-- =========================================================================

addon:SetScript("OnUpdate", function(self, elapsed)
    -- Check performance periodically
    self.perfCheckTimer = (self.perfCheckTimer or 0) + elapsed
    if self.perfCheckTimer >= 5 then
        self:CheckPerformance()
        self.perfCheckTimer = 0
    end
end)

function addon:CheckPerformance()
    local stats = PerformanceLib:GetFrameTimeStats()
    
    -- Alert if performance degrades
    if stats.P99 and stats.P99 > 25 then
        print("|cFFFF0000Performance Warning: P99 = " .. ("%.1f"):format(stats.P99) .. "ms|r")
    end
    
    -- Optional debug output
    if self.debugEnabled then
        print(("FPS: %.1f | P50: %.1f | P99: %.1f"):format(
            1000 / stats.avg,
            stats.P50,
            stats.P99
        ))
    end
end

-- =========================================================================
-- SLASH COMMANDS
-- =========================================================================

SLASH_EXAMPLEADDON1 = "/exampleaddon"
SlashCmdList["EXAMPLEADDON"] = function(msg)
    local cmd = msg:lower():match("^(%w+)")
    
    if cmd == "debug" then
        addon.debugEnabled = not addon.debugEnabled
        print("Debug mode:", addon.debugEnabled and "ON" or "OFF")
    elseif cmd == "stats" then
        local stats = PerformanceLib:GetFrameTimeStats()
        print("|cFF00FF00Performance Stats:|r")
        print(("  Avg: %.2f ms"):format(stats.avg))
        print(("  P99: %.2f ms"):format(stats.P99))
        local eventStats = PerformanceLib.EventCoalescer:GetStats()
        print(("  Events Coalesced: %d"):format(eventStats.totalCoalesced))
    elseif cmd == "perf" then
        PerformanceLib:ToggleDashboard()
    elseif cmd == "help" then
        print("|cFF00FF00ExamplePerformantAddon Commands:|r")
        print("  /exampleaddon debug - Toggle debug output")
        print("  /exampleaddon stats - Show performance stats")
        print("  /exampleaddon perf - Toggle performance dashboard")
        print("  /exampleaddon help - Show this help")
    end
end

print("ExamplePerformantAddon loaded!")
