-- =========================================================================
-- PerformanceLib - Performance System Library for WoW Addon Developers
-- =========================================================================
-- A comprehensive library providing:
--  - Event coalescing (batch high-frequency WoW events)
--  - Frame time budgeting (throttle updates based on frame time)
--  - Dirty flag batching (update only changed frames)
--  - Frame pooling (reuse frames instead of destroying)
--  - Indicator pooling (manage temporary indicator lifecycles)
--  - ML-based optimization (learn optimal priority/timing from gameplay)
--  - Debug profiling & dashboard (monitor performance in real-time)
--
-- Requires: WoW 12.0.0 (Retail)
-- License: MIT (same as UnhaltedUnitFrames)

local MAJOR_VERSION = 1
local MINOR_VERSION = 0
local PATCH_VERSION = 0

local addonName, addonTable = ...
local PerformanceLib = addonTable or _G.PerformanceLib or {}
if type(PerformanceLib) ~= "table" then
    PerformanceLib = {}
end
_G.PerformanceLib = PerformanceLib

-- =========================================================================
-- INITIALIZATION
-- =========================================================================

if not PerformanceLIBDB then
    PerformanceLIBDB = {
        enabled = true,
        presets = "Medium",
        debug = {
            enabled = false,
            systems = {}
        }
    }
end

-- Singleton namespace (shared with all loaded module files)
local PerfLib = PerformanceLib

-- =========================================================================
-- SUBSYSTEM REGISTRY
-- =========================================================================

local subsystems = {
    EventCoalescer = PerfLib.EventCoalescer,
    FrameTimeBudget = PerfLib.FrameTimeBudget,
    DirtyFlagManager = PerfLib.DirtyFlagManager,
    FramePoolManager = PerfLib.FramePoolManager,
    IndicatorPooling = PerfLib.IndicatorPooling,
    DirtyPriorityOptimizer = PerfLib.DirtyPriorityOptimizer,
    MLOptimizer = PerfLib.MLOptimizer,
    DebugOutput = PerfLib.DebugOutput,
    Dashboard = PerfLib.Dashboard,
    PerformanceProfiler = PerfLib.PerformanceProfiler,
}

-- =========================================================================
-- LIBRARY API
-- =========================================================================

---Initialize PerformanceLib and all subsystems
---@param initiator string The addon name initializing the library
---@return table Returns self for chaining
function PerfLib:Initialize(initiator)
    if self._initialized then
        return self
    end

    self._initialized = true
    self._initiator = initiator
    self.db = PerformanceLIBDB

    -- Core subsystems (always initialized)
    self.EventCoalescer = subsystems.EventCoalescer or {}
    self.FrameTimeBudget = subsystems.FrameTimeBudget or {}
    self.DirtyFlagManager = subsystems.DirtyFlagManager or {}
    self.FramePoolManager = subsystems.FramePoolManager or {}
    self.IndicatorPooling = subsystems.IndicatorPooling or {}

    -- ML subsystems (optional)
    self.DirtyPriorityOptimizer = subsystems.DirtyPriorityOptimizer or {}
    self.MLOptimizer = subsystems.MLOptimizer or {}

    -- Debug subsystems (optional)
    self.DebugOutput = subsystems.DebugOutput or {}
    self.Dashboard = subsystems.Dashboard or {}
    self.PerformanceProfiler = subsystems.PerformanceProfiler or {}

    if self.Dashboard and self.Dashboard.Initialize then
        pcall(self.Dashboard.Initialize, self.Dashboard)
    end

    return self
end

---Enable or disable the entire library
---@param enable boolean Enable/disable flag
function PerfLib:SetEnabled(enable)
    self.db.enabled = enable
    if subsystems.EventCoalescer and subsystems.EventCoalescer.SetEnabled then
        subsystems.EventCoalescer:SetEnabled(enable)
    end
    if subsystems.DirtyFlagManager and subsystems.DirtyFlagManager.SetEnabled then
        subsystems.DirtyFlagManager:SetEnabled(enable)
    end
end

---Check if library is enabled
---@return boolean True if enabled
function PerfLib:IsEnabled()
    return self.db.enabled
end

---Set performance preset (Low/Medium/High/Ultra)
---@param preset string One of: "Low", "Medium", "High", "Ultra"
function PerfLib:SetPreset(preset)
    if not preset or preset == "" then
        preset = "Medium"
    end
    self.db.presets = preset

    local settings = {
        Low = {
            coalesceInterval = 0.050,
            batchSize = 2,
            budgetTarget = 25.00,
        },
        Medium = {
            coalesceInterval = 0.030,
            batchSize = 10,
            budgetTarget = 16.67,
        },
        High = {
            coalesceInterval = 0.020,
            batchSize = 20,
            budgetTarget = 14.00,
        },
        Ultra = {
            coalesceInterval = 0.010,
            batchSize = 40,
            budgetTarget = 10.00,
        },
    }

    if settings[preset] then
        local cfg = settings[preset]
        if subsystems.EventCoalescer and subsystems.EventCoalescer.SetCoalesceInterval then
            subsystems.EventCoalescer:SetCoalesceInterval(2, math.max(0.005, cfg.coalesceInterval * 0.5))
            subsystems.EventCoalescer:SetCoalesceInterval(3, cfg.coalesceInterval)
            subsystems.EventCoalescer:SetCoalesceInterval(4, math.max(cfg.coalesceInterval, cfg.coalesceInterval * 1.5))
        end
        if subsystems.DirtyFlagManager and subsystems.DirtyFlagManager.SetBatchSize then
            subsystems.DirtyFlagManager:SetBatchSize(cfg.batchSize)
        end
        if subsystems.FrameTimeBudget and subsystems.FrameTimeBudget.SetTargetFrameTime then
            subsystems.FrameTimeBudget:SetTargetFrameTime(cfg.budgetTarget)
        end
    end
end

---Queue an event with optional priority (integrates with EventCoalescer)
---@param event string Event name
---@param priority integer 1=CRITICAL, 2=HIGH, 3=MEDIUM, 4=LOW
---@param ... any Event data
function PerfLib:QueueEvent(event, priority, ...)
    if not self.EventCoalescer or not self.EventCoalescer.QueueEvent then
        return
    end
    self.EventCoalescer:QueueEvent(event, priority or 3, ...)
end

---Mark a frame as dirty (needs update) - integrates with DirtyFlagManager
---@param frame table Frame object
---@param priority integer Frame update priority
function PerfLib:MarkFrameDirty(frame, priority)
    if not self.DirtyFlagManager or not self.DirtyFlagManager.MarkDirty then
        return
    end
    self.DirtyFlagManager:MarkDirty(frame, priority or 3)
end

---Get current frame time metrics (from FrameTimeBudget)
---@return table Stats with keys: avg, P50, P95, P99, fps, histogram
function PerfLib:GetFrameTimeStats()
    if not self.FrameTimeBudget or not self.FrameTimeBudget.GetStatistics then
        return {}
    end
    return self.FrameTimeBudget:GetStatistics()
end

---Acquire a frame from the pool (replaces CreateFrame for pooled types)
---@param frameName string Frame object type name (e.g., "Button", "Frame")
---@param parent table Parent frame
---@param poolType string Optional pool identifier (default: frameName)
---@return table Acquired frame from pool
function PerfLib:AcquireFrame(frameName, parent, poolType)
    if not self.FramePoolManager or not self.FramePoolManager.Acquire then
        return CreateFrame(frameName, nil, parent)
    end
    return self.FramePoolManager:Acquire(frameName, parent, poolType)
end

---Release a frame back to the pool
---@param frame table Frame to release
function PerfLib:ReleaseFrame(frame)
    if not self.FramePoolManager or not self.FramePoolManager.Release then
        frame:Hide()
        return
    end
    self.FramePoolManager:Release(frame)
end

---Start performance profiling (timeline recording)
function PerfLib:StartProfiling()
    if self.PerformanceProfiler and self.PerformanceProfiler.StartProfiling then
        self.PerformanceProfiler:StartProfiling()
    end
end

---Stop performance profiling and analyze results
function PerfLib:StopProfiling()
    if self.PerformanceProfiler and self.PerformanceProfiler.StopProfiling then
        return self.PerformanceProfiler:StopProfiling()
    end
end

---Open the real-time performance dashboard
function PerfLib:ShowDashboard()
    if not self.db.debug.enabled then
        self.db.debug.enabled = true
    end
    if self.Dashboard and self.Dashboard.Show then
        self.Dashboard:Show()
    elseif self.DebugOutput and self.DebugOutput.ShowPanel then
        self.DebugOutput:ShowPanel()
    end
end

---Toggle the performance dashboard visibility
function PerfLib:ToggleDashboard()
    if self.Dashboard and self.Dashboard.Toggle then
        self.Dashboard:Toggle()
    elseif self.DebugOutput and self.DebugOutput.TogglePanel then
        self.DebugOutput:TogglePanel()
    elseif self.DebugOutput and self.DebugOutput.ShowPanel then
        self.DebugOutput:ShowPanel()
    else
        print("|cFFFF0000PerformanceLib: Dashboard UI unavailable.|r")
    end
end

---Log a debug message to the debug panel
---@param system string System name (e.g., "EventCoalescer")
---@param message string Message to log
---@param tier integer Tier level (1=CRITICAL, 2=INFO, 3=DEBUG)
function PerfLib:Debug(system, message, tier)
    if not self.DebugOutput or not self.DebugOutput.Output then
        return
    end
    self.DebugOutput:Output(system, message, tier or 2)
end

---Get the version string
---@return string Version (e.g., "1.0.0")
function PerfLib:GetVersion()
    return ("%d.%d.%d"):format(MAJOR_VERSION, MINOR_VERSION, PATCH_VERSION)
end

---Get the name of the addon that initialized the library
---@return string Initiator addon name
function PerfLib:GetInitiator()
    return self._initiator or "Unknown"
end

-- =========================================================================
-- SLASH COMMANDS
-- =========================================================================

SLASH_PERFLIB1 = "/perflib"
SLASH_PERFLIB2 = "/libperf"

local function PrintHelp()
    print("|cFF00FF00PerformanceLib Commands:|r")
    print("  /perflib ui - Toggle dashboard UI")
    print("  /perflib ui show|hide - Explicitly show/hide dashboard")
    print("  /perflib dash - Alias for /perflib ui")
    print("  /libperf ui|dash - Aliases")
    print("  /perflib stats - Print current performance stats")
    print("  /perflib version - Show version and initializer")
    print("  /perflib preset <Low|Medium|High|Ultra> - Set preset")
    print("  /perflib profile start - Start profiler capture")
    print("  /perflib profile stop - Stop profiler capture")
    print("  /perflib help - Show this help")
end

local function PrintStats()
    local frameStats = PerfLib.GetFrameTimeStats and PerfLib:GetFrameTimeStats() or {}
    local eventStats = PerfLib.EventCoalescer and PerfLib.EventCoalescer.GetStats and PerfLib.EventCoalescer:GetStats() or {}
    local dirtyStats = PerfLib.DirtyFlagManager and PerfLib.DirtyFlagManager.GetStats and PerfLib.DirtyFlagManager:GetStats() or {}
    local poolStats = PerfLib.FramePoolManager and PerfLib.FramePoolManager.GetStats and PerfLib.FramePoolManager:GetStats() or {}
    local coalescerEnabled = PerfLib.EventCoalescer and PerfLib.EventCoalescer._enabled
    local dirtyEnabled = PerfLib.DirtyFlagManager and PerfLib.DirtyFlagManager._enabled

    print("|cFF00FF00PerformanceLib Stats:|r")
    print(("  Frame Avg: %.2f ms | P95: %.2f | P99: %.2f"):format(frameStats.avg or 0, frameStats.P95 or 0, frameStats.P99 or 0))
    print(("  Events: coalesced=%d dispatched=%d queued=%d"):format(eventStats.totalCoalesced or 0, eventStats.totalDispatched or 0, eventStats.queuedEvents or 0))
    print(("  Dirty: processed=%d batches=%d queued=%d invalid=%d"):format(dirtyStats.framesProcessed or 0, dirtyStats.batchesRun or 0, dirtyStats.currentDirtyCount or 0, dirtyStats.invalidFramesSkipped or 0))
    print(("  Pools: created=%d reused=%d released=%d"):format(poolStats.totalCreated or 0, poolStats.totalReused or 0, poolStats.totalReleased or 0))
    print(("  Systems: coalescer=%s dirty=%s"):format(coalescerEnabled and "on" or "off", dirtyEnabled and "on" or "off"))
    if (eventStats.totalCoalesced or 0) == 0 and (eventStats.totalDispatched or 0) == 0 then
        print("  Note: event stats stay at 0 until an addon calls PerformanceLib:QueueEvent(...).")
    end
    if (poolStats.totalCreated or 0) == 0 and (poolStats.totalReused or 0) == 0 then
        print("  Note: pool stats stay at 0 until an addon uses PerformanceLib:AcquireFrame()/ReleaseFrame().")
    end
end

SlashCmdList["PERFLIB"] = function(msg)
    msg = msg or ""
    local lower = msg:lower()
    local cmd, arg = lower:match("^(%w+)%s*(%w*)")

    if not cmd or cmd == "" then
        PrintHelp()
    elseif cmd == "ui" or cmd == "dash" then
        if arg == "show" then
            PerfLib:ShowDashboard()
        elseif arg == "hide" then
            if PerfLib.Dashboard and PerfLib.Dashboard.Hide then
                PerfLib.Dashboard:Hide()
            elseif PerfLib.DebugOutput and PerfLib.DebugOutput.TogglePanel then
                PerfLib.DebugOutput:TogglePanel()
            end
        else
            PerfLib:ToggleDashboard()
        end
    elseif cmd == "stats" then
        PrintStats()
    elseif cmd == "version" then
        print("|cFF00FF00PerformanceLib v" .. PerfLib:GetVersion() .. "|r - Initialized by: " .. PerfLib:GetInitiator())
    elseif cmd == "preset" then
        local preset = msg:match("preset%s+(%w+)")
        if preset then
            PerfLib:SetPreset(preset)
            print("|cFF00FF00PerformanceLib preset set to: " .. preset .. "|r")
        else
            print("|cFFFFFF00Usage: /perflib preset <Low|Medium|High|Ultra>|r")
        end
    elseif cmd == "profile" then
        local subcmd = msg:match("profile%s+(%w+)")
        if subcmd == "start" then
            PerfLib:StartProfiling()
            print("|cFF00FF00Performance profiling started|r")
        elseif subcmd == "stop" then
            PerfLib:StopProfiling()
            print("|cFF00FF00Performance profiling stopped|r")
        else
            print("|cFFFFFF00Usage: /perflib profile <start|stop>|r")
        end
    elseif cmd == "help" then
        PrintHelp()
    else
        print("|cFFFF0000Unknown command:|r " .. tostring(cmd))
        PrintHelp()
    end
end

-- =========================================================================
-- INITIALIZATION BOOT
-- =========================================================================

-- Auto-initialize on first load
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
    if addon == addonName then
        PerfLib:Initialize("PerformanceLib")
        if not PerfLib.db.presets or PerfLib.db.presets == "" then
            PerfLib:SetPreset("Medium")
        else
            PerfLib:SetPreset(PerfLib.db.presets)
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Make library globally accessible
_G.PerformanceLib = PerfLib
