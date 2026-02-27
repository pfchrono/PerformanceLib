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
local VALID_PRESETS = { Low = true, Medium = true, High = true, Ultra = true }

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

    if not VALID_PRESETS[preset] then
        PerfLib:Output(
            "|cFFFF8800PerformanceLib: Unknown preset '" .. tostring(preset) .. "', defaulting to Medium.|r"
        )
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
        PerfLib:Output("|cFFFF0000PerformanceLib: Dashboard UI unavailable.|r")
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

---Set an output sink for user-facing library output.
---@param sink function|nil Callback signature: function(context, message, system, tier)
---@param context any Optional callback context
function PerfLib:SetOutputSink(sink, context)
    if type(sink) == "function" then
        self._outputSink = sink
        self._outputContext = context
    else
        self._outputSink = nil
        self._outputContext = nil
    end
end

---Emit user-facing output through sink; fallback to chat.
---@param message string
---@param system string|nil
---@param tier integer|nil
function PerfLib:Output(message, system, tier)
    local text = tostring(message or "")
    system = system or "PerformanceLib"
    tier = tier or 2

    if type(self._outputSink) == "function" then
        local ok = pcall(self._outputSink, self._outputContext or self, text, system, tier)
        if ok then
            return
        end
    end

    _G.print(text)
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
    PerfLib:Output("|cFF00FF00PerformanceLib Commands:|r")
    PerfLib:Output("  /perflib ui - Toggle dashboard UI")
    PerfLib:Output("  /perflib ui show|hide - Explicitly show/hide dashboard")
    PerfLib:Output("  /perflib dash - Alias for /perflib ui")
    PerfLib:Output("  /libperf ui|dash - Aliases")
    PerfLib:Output("  /perflib stats - Print current performance stats")
    PerfLib:Output("  /perflib version - Show version and initializer")
    PerfLib:Output("  /perflib preset <Low|Medium|High|Ultra> - Set preset")
    PerfLib:Output("  /perflib profile start - Start profiler capture")
    PerfLib:Output("  /perflib profile stop - Stop profiler capture")
    PerfLib:Output("  /perflib profile analyze [scope] - Print diagnostic findings")
    PerfLib:Output("  /perflib analyze [scope] - Shortcut (scope: all|eventbus|frame|dirty|pool|profile)")
    PerfLib:Output("  /perflib test eventbus - Run EventBus self-tests (isolation + dedupe)")
    PerfLib:Output("  /perflib test dirtypriority - Run DirtyPriorityOptimizer frequency-window test")
    PerfLib:Output("  /perflib test preset - Run preset-validation fallback test")
    PerfLib:Output("  /perflib help - Show this help")
end

local function PrintStats()
    local frameStats = PerfLib.GetFrameTimeStats and PerfLib:GetFrameTimeStats() or {}
    local eventStats = PerfLib.EventCoalescer and PerfLib.EventCoalescer.GetStats and PerfLib.EventCoalescer:GetStats() or {}
    local dirtyStats = PerfLib.DirtyFlagManager and PerfLib.DirtyFlagManager.GetStats and PerfLib.DirtyFlagManager:GetStats() or {}
    local poolStats = PerfLib.FramePoolManager and PerfLib.FramePoolManager.GetStats and PerfLib.FramePoolManager:GetStats() or {}
    local coalescerEnabled = PerfLib.EventCoalescer and PerfLib.EventCoalescer._enabled
    local dirtyEnabled = PerfLib.DirtyFlagManager and PerfLib.DirtyFlagManager._enabled

    PerfLib:Output("|cFF00FF00PerformanceLib Stats:|r")
    PerfLib:Output(("  Frame Avg: %.2f ms | P95: %.2f | P99: %.2f"):format(frameStats.avg or 0, frameStats.P95 or 0, frameStats.P99 or 0))
    PerfLib:Output(("  Events: coalesced=%d dispatched=%d queued=%d"):format(eventStats.totalCoalesced or 0, eventStats.totalDispatched or 0, eventStats.queuedEvents or 0))
    PerfLib:Output(("  Events detail: defers=%d emergencyFlush=%d immediateCritical=%d"):format(eventStats.budgetDefers or 0, eventStats.emergencyFlushes or 0, eventStats.immediateCritical or 0))
    PerfLib:Output(("  Dirty: processed=%d batches=%d queued=%d invalid=%d"):format(dirtyStats.framesProcessed or 0, dirtyStats.batchesRun or 0, dirtyStats.currentDirtyCount or 0, dirtyStats.invalidFramesSkipped or 0))
    PerfLib:Output(("  Pools: created=%d reused=%d released=%d"):format(poolStats.totalCreated or 0, poolStats.totalReused or 0, poolStats.totalReleased or 0))
    PerfLib:Output(("  Systems: coalescer=%s dirty=%s"):format(coalescerEnabled and "on" or "off", dirtyEnabled and "on" or "off"))
    if (eventStats.totalCoalesced or 0) == 0 and (eventStats.totalDispatched or 0) == 0 then
        PerfLib:Output("  Note: event stats stay at 0 until an addon calls PerformanceLib:QueueEvent(...).")
    end
    if (poolStats.totalCreated or 0) == 0 and (poolStats.totalReused or 0) == 0 then
        PerfLib:Output("  Note: pool stats stay at 0 until an addon uses PerformanceLib:AcquireFrame()/ReleaseFrame().")
    end
end

local function RunEventBusIsolationTest()
    local bus = PerfLib.Architecture and PerfLib.Architecture.EventBus
    if not bus or not bus.Register or not bus.Unregister or not bus.Dispatch then
        PerfLib:Output("|cFFFF0000EventBus test failed: EventBus unavailable.|r")
        return false
    end

    local eventName = "PERFLIB_TEST_EVENTBUS_ISOLATION"
    local firstHandlerRan = false
    local secondHandlerRan = false
    local errorLogged = false

    local originalDebugOutput = PerfLib.DebugOutput
    PerfLib.DebugOutput = {
        Output = function(_, system, message)
            if system == "EventBus" and type(message) == "string" and message:find("EventBus error [" .. eventName .. "]", 1, true) then
                errorLogged = true
            end
        end
    }

    local function failingHandler()
        firstHandlerRan = true
        error("test")
    end

    local function survivingHandler()
        secondHandlerRan = true
    end

    bus:Register(eventName, failingHandler)
    bus:Register(eventName, survivingHandler)

    local dispatchOk, dispatchErr = pcall(bus.Dispatch, bus, eventName)

    bus:Unregister(eventName, failingHandler)
    bus:Unregister(eventName, survivingHandler)
    PerfLib.DebugOutput = originalDebugOutput

    local passed = dispatchOk and firstHandlerRan and secondHandlerRan and errorLogged
    if passed then
        PerfLib:Output("|cFF00FF00EventBus test passed: handler errors were isolated, dispatch continued, and error output was captured.|r")
    else
        PerfLib:Output(("|cFFFF0000EventBus test failed: dispatchOk=%s first=%s second=%s errorLogged=%s err=%s|r"):format(
            tostring(dispatchOk),
            tostring(firstHandlerRan),
            tostring(secondHandlerRan),
            tostring(errorLogged),
            tostring(dispatchErr)
        ))
    end

    return passed
end

local function RunEventBusDuplicateRegistrationTest()
    local bus = PerfLib.Architecture and PerfLib.Architecture.EventBus
    if not bus or not bus.Register or not bus.Unregister or not bus.Dispatch then
        PerfLib:Output("|cFFFF0000EventBus dedupe test failed: EventBus unavailable.|r")
        return false
    end

    local eventName = "PERFLIB_TEST_EVENTBUS_DEDUPE"
    local callCount = 0

    local function handler()
        callCount = callCount + 1
    end

    bus:Register(eventName, handler)
    bus:Register(eventName, handler)

    local dispatchOk, dispatchErr = pcall(bus.Dispatch, bus, eventName)

    bus:Unregister(eventName, handler)

    local passed = dispatchOk and callCount == 1
    if passed then
        PerfLib:Output("|cFF00FF00EventBus dedupe test passed: duplicate registration was ignored and handler fired once.|r")
    else
        PerfLib:Output(("|cFFFF0000EventBus dedupe test failed: dispatchOk=%s callCount=%s err=%s|r"):format(
            tostring(dispatchOk),
            tostring(callCount),
            tostring(dispatchErr)
        ))
    end

    return passed
end

local dirtyPriorityTestFrame
local dirtyPriorityTestRunning = false

local function RunDirtyPriorityOptimizerWindowTest()
    local optimizer = PerfLib.DirtyPriorityOptimizer
    if not optimizer or not optimizer.LearnPriority or not optimizer.GetRecommendations then
        PerfLib:Output("|cFFFF0000DirtyPriority test failed: optimizer unavailable.|r")
        return false
    end

    if dirtyPriorityTestRunning then
        PerfLib:Output("|cFFFFFF00DirtyPriority test already running; wait for completion.|r")
        return false
    end

    dirtyPriorityTestRunning = true

    if optimizer.Reset then
        optimizer:Reset()
    end

    local totalFrames = 420
    local ticks = 0
    local hotFrame = {}
    local warmFrame = {}
    local coldFrame = {}

    if not dirtyPriorityTestFrame then
        dirtyPriorityTestFrame = CreateFrame("Frame")
    end

    dirtyPriorityTestFrame:SetScript("OnUpdate", function(self)
        ticks = ticks + 1

        optimizer:LearnPriority(hotFrame, 2)            -- every frame
        if ticks % 4 == 0 then
            optimizer:LearnPriority(warmFrame, 2)       -- medium frequency
        end
        if ticks % 30 == 0 then
            optimizer:LearnPriority(coldFrame, 2)       -- low frequency
        end

        if ticks < totalFrames then
            return
        end

        self:SetScript("OnUpdate", nil)
        dirtyPriorityTestRunning = false

        local recs = optimizer:GetRecommendations() or {}
        local hotRec, warmRec, coldRec
        local unique = {}
        for i = 1, #recs do
            local row = recs[i]
            unique[row.recommendation] = true
            if row.frame == hotFrame then
                hotRec = row.recommendation
            elseif row.frame == warmFrame then
                warmRec = row.recommendation
            elseif row.frame == coldFrame then
                coldRec = row.recommendation
            end
        end

        local uniqueCount = 0
        for _ in pairs(unique) do
            uniqueCount = uniqueCount + 1
        end

        local ordered = hotRec and warmRec and coldRec and (hotRec >= warmRec and warmRec >= coldRec)
        local varied = uniqueCount > 1
        local passed = ordered and varied

        if passed then
            PerfLib:Output(("|cFF00FF00DirtyPriority test passed: priorities varied after %d frames (hot=%s warm=%s cold=%s).|r"):format(
                totalFrames, tostring(hotRec), tostring(warmRec), tostring(coldRec)
            ))
        else
            PerfLib:Output(("|cFFFF0000DirtyPriority test failed: expected hot>=warm>=cold with variation after %d frames; got hot=%s warm=%s cold=%s unique=%d.|r"):format(
                totalFrames, tostring(hotRec), tostring(warmRec), tostring(coldRec), uniqueCount
            ))
        end
    end)

    PerfLib:Output("|cFFFFFF00DirtyPriority test started: collecting ~420 frames of activity...|r")
    return true
end

local function RunPresetValidationFallbackTest()
    local savedSink = PerfLib._outputSink
    local savedSinkContext = PerfLib._outputContext
    local warningSeen = false

    local observed = {
        coalesce2 = nil,
        coalesce3 = nil,
        coalesce4 = nil,
        batchSize = nil,
        budgetTarget = nil,
    }

    local ec = subsystems.EventCoalescer
    local dirty = subsystems.DirtyFlagManager
    local frameBudget = subsystems.FrameTimeBudget

    local oldEC = ec and ec.SetCoalesceInterval or nil
    local oldDirty = dirty and dirty.SetBatchSize or nil
    local oldBudget = frameBudget and frameBudget.SetTargetFrameTime or nil
    local originalPreset = PerfLib.db and PerfLib.db.presets or "Medium"

    if ec then
        ec.SetCoalesceInterval = function(_, priority, interval)
            if priority == 2 then
                observed.coalesce2 = interval
            elseif priority == 3 then
                observed.coalesce3 = interval
            elseif priority == 4 then
                observed.coalesce4 = interval
            end
        end
    end

    if dirty then
        dirty.SetBatchSize = function(_, size)
            observed.batchSize = size
        end
    end

    if frameBudget then
        frameBudget.SetTargetFrameTime = function(_, value)
            observed.budgetTarget = value
        end
    end

    PerfLib:SetOutputSink(function(_, message)
        if type(message) == "string" and message:find("Unknown preset", 1, true) then
            warningSeen = true
        end
    end)

    PerfLib:SetPreset("invalid")

    local function approxEqual(a, b)
        return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.0001
    end

    local mediumApplied =
        approxEqual(observed.coalesce2, 0.015) and
        approxEqual(observed.coalesce3, 0.030) and
        approxEqual(observed.coalesce4, 0.045) and
        observed.batchSize == 10 and
        approxEqual(observed.budgetTarget, 16.67)

    local fallbackPreset = PerfLib.db.presets
    local passed = warningSeen and fallbackPreset == "Medium" and mediumApplied

    if ec then
        ec.SetCoalesceInterval = oldEC
    end
    if dirty then
        dirty.SetBatchSize = oldDirty
    end
    if frameBudget then
        frameBudget.SetTargetFrameTime = oldBudget
    end

    PerfLib:SetOutputSink(savedSink, savedSinkContext)

    local restorePreset = VALID_PRESETS[originalPreset] and originalPreset or "Medium"
    PerfLib:SetPreset(restorePreset)

    if passed then
        PerfLib:Output("|cFF00FF00Preset test passed: invalid preset emitted warning and fell back to Medium settings.|r")
    else
        PerfLib:Output(("|cFFFF0000Preset test failed: warning=%s preset=%s mediumApplied=%s c2=%s c3=%s c4=%s batch=%s budget=%s|r"):format(
            tostring(warningSeen),
            tostring(fallbackPreset),
            tostring(mediumApplied),
            tostring(observed.coalesce2),
            tostring(observed.coalesce3),
            tostring(observed.coalesce4),
            tostring(observed.batchSize),
            tostring(observed.budgetTarget)
        ))
    end

    return passed
end

local function BuildTopEventRows(perEventStats, limit)
    local rows = {}
    for eventName, info in pairs(perEventStats or {}) do
        local coalesced = (info and info.coalesced) or 0
        local dispatched = (info and info.dispatched) or 0
        rows[#rows + 1] = {
            event = eventName,
            coalesced = coalesced,
            dispatched = dispatched,
            saved = math.max(0, coalesced - dispatched),
        }
    end
    table.sort(rows, function(a, b)
        if a.saved ~= b.saved then
            return a.saved > b.saved
        end
        return (a.coalesced + a.dispatched) > (b.coalesced + b.dispatched)
    end)
    local out = {}
    local maxRows = math.min(limit or 5, #rows)
    for i = 1, maxRows do
        out[#out + 1] = rows[i]
    end
    return out
end

function PerfLib:AnalyzePerformance(scope)
    local frameStats = self.GetFrameTimeStats and self:GetFrameTimeStats() or {}
    local eventStats = self.EventCoalescer and self.EventCoalescer.GetStats and self.EventCoalescer:GetStats() or {}
    local dirtyStats = self.DirtyFlagManager and self.DirtyFlagManager.GetStats and self.DirtyFlagManager:GetStats() or {}
    local poolStats = self.FramePoolManager and self.FramePoolManager.GetStats and self.FramePoolManager:GetStats() or {}
    local profilerStats = self.PerformanceProfiler and self.PerformanceProfiler.GetStats and self.PerformanceProfiler:GetStats() or {}
    local profilerAnalysis = {}

    scope = (scope or "all"):lower()
    local function includes(name)
        return scope == "all" or scope == name
    end

    local findings = {}
    local recommendations = {}
    local function addFinding(text)
        findings[#findings + 1] = text
    end
    local function addRecommendation(text)
        recommendations[#recommendations + 1] = text
    end

    if includes("frame") then
        local avg = frameStats.avg or 0
        local p95 = frameStats.P95 or 0
        local p99 = frameStats.P99 or 0
        addFinding(("Frame budget: avg=%.2fms p95=%.2f p99=%.2f dropped=%d deferred=%d"):format(
            avg,
            p95,
            p99,
            frameStats.droppedCallbacks or 0,
            frameStats.deferredCount or 0
        ))
        if avg > 16.67 or p95 > 20 then
            addRecommendation("Frame pressure is high: use /perflib preset Medium or Low and increase coalescing intervals for noisy events.")
        elseif avg < 12 and p95 < 16 then
            addRecommendation("Frame headroom is healthy: consider tighter coalescing intervals only for latency-sensitive events.")
        end
    end

    if includes("eventbus") then
        local coalesced = eventStats.totalCoalesced or 0
        local dispatched = eventStats.totalDispatched or 0
        local queued = eventStats.queuedEvents or 0
        local savings = eventStats.savingsPercent or 0
        local defers = eventStats.budgetDefers or 0
        local emergency = eventStats.emergencyFlushes or 0

        local immediateCritical = eventStats.immediateCritical or 0
        addFinding(("EventBus/coalescer: coalesced=%d dispatched=%d queued=%d savings=%.1f%% defers=%d emergencyFlush=%d immediateCritical=%d"):format(
            coalesced, dispatched, queued, savings, defers, emergency, immediateCritical
        ))

        local top = BuildTopEventRows(eventStats.perEvent, 5)
        if #top > 0 then
            for i = 1, #top do
                local row = top[i]
                addFinding(("Top event %d: %s (coalesced=%d dispatched=%d saved=%d)"):format(
                    i, row.event, row.coalesced, row.dispatched, row.saved
                ))
            end
        end

        if coalesced == 0 and dispatched == 0 then
            addRecommendation("No coalescer traffic detected: route high-frequency events through PerformanceLib:QueueEvent(...) and register handlers in EventBus.")
        end
        if coalesced > 50 and savings < 20 then
            addRecommendation("Low coalescing savings: increase event delays (SetEventDelay) for spammy events or lower their priority.")
        end
        if defers > math.max(20, dispatched * 0.25) then
            addRecommendation("High budget defers: reduce MEDIUM/LOW event volume, increase delay, or lower dirty batch size to reduce frame spikes.")
        end
        if emergency > math.max(10, dispatched * 0.10) then
            addRecommendation("Emergency flushes are high: raise delays on noisy HIGH/MEDIUM events and reserve priority 1 for true critical state changes.")
        end
    end

    if includes("dirty") then
        addFinding(("Dirty manager: processed=%d batches=%d queued=%d invalid=%d blocks=%d decays=%d"):format(
            dirtyStats.framesProcessed or 0,
            dirtyStats.batchesRun or 0,
            dirtyStats.currentDirtyCount or 0,
            dirtyStats.invalidFramesSkipped or 0,
            dirtyStats.processingBlocks or 0,
            dirtyStats.priorityDecays or 0
        ))
        if (dirtyStats.invalidFramesSkipped or 0) > 0 then
            addRecommendation("Dirty manager skipped invalid frames: validate frame references before MarkFrameDirty calls.")
        end
        if (dirtyStats.processingBlocks or 0) > 10 then
            addRecommendation("Dirty processing re-entry blocks are high: avoid recursive updates and batch UpdateAllElements calls.")
        end
    end

    if includes("pool") then
        addFinding(("Frame pools: created=%d reused=%d acquired=%d released=%d"):format(
            poolStats.totalCreated or 0,
            poolStats.totalReused or 0,
            poolStats.totalAcquired or 0,
            poolStats.totalReleased or 0
        ))
        local created = poolStats.totalCreated or 0
        local reused = poolStats.totalReused or 0
        local acquired = poolStats.totalAcquired or 0
        local released = poolStats.totalReleased or 0
        local churn = math.min(acquired, released)
        if churn >= 10 and created > 0 and reused < math.max(5, created * 0.25) then
            addRecommendation("Pooling reuse is low: ensure temporary frames/indicators are released via ReleaseFrame/ReleaseIndicator.")
        elseif created > 0 and released == 0 then
            addFinding("Pool lifecycle note: frames appear long-lived (created with no releases), so low reuse may be expected.")
        end
    end

    if includes("profile") then
        profilerAnalysis = self.PerformanceProfiler and self.PerformanceProfiler.Analyze and self.PerformanceProfiler:Analyze() or {}
        addFinding(("Profiler: recording=%s events=%d"):format(
            (profilerStats.isRecording and "true" or "false"),
            profilerStats.eventCount or 0
        ))
        if profilerAnalysis and profilerAnalysis.totalEvents and profilerAnalysis.totalEvents > 0 then
            addFinding(("Profiler summary: total=%d duration=%.2fs avg=%.2fms p95=%.2f p99=%.2f"):format(
                profilerAnalysis.totalEvents or 0,
                profilerAnalysis.duration or 0,
                profilerAnalysis.avg or 0,
                profilerAnalysis.P95 or 0,
                profilerAnalysis.P99 or 0
            ))
        end
        if (profilerStats.eventCount or 0) == 0 then
            addRecommendation("No profile timeline captured yet: run /perflib profile start, reproduce combat scenario, then /perflib profile analyze.")
        end
    end

    PerfLib:Output("|cFF00FF00PerformanceLib Analyze (" .. scope .. "):|r")
    if #findings == 0 then
        PerfLib:Output("  No findings available for this scope.")
    else
        for i = 1, #findings do
            PerfLib:Output("  " .. findings[i])
        end
    end

    if #recommendations > 0 then
        PerfLib:Output("|cFFFFFF00Recommendations:|r")
        for i = 1, #recommendations do
            PerfLib:Output(("  %d. %s"):format(i, recommendations[i]))
        end
    end

    return {
        scope = scope,
        findings = findings,
        recommendations = recommendations,
        frame = frameStats,
        eventbus = eventStats,
        dirty = dirtyStats,
        pool = poolStats,
        profile = profilerAnalysis,
    }
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
        PerfLib:Output("|cFF00FF00PerformanceLib v" .. PerfLib:GetVersion() .. "|r - Initialized by: " .. PerfLib:GetInitiator())
    elseif cmd == "preset" then
        local preset = msg:match("preset%s+(%w+)")
        if preset then
            PerfLib:SetPreset(preset)
            PerfLib:Output("|cFF00FF00PerformanceLib preset set to: " .. preset .. "|r")
        else
            PerfLib:Output("|cFFFFFF00Usage: /perflib preset <Low|Medium|High|Ultra>|r")
        end
    elseif cmd == "profile" then
        local subcmd = msg:match("profile%s+(%w+)")
        local scope = msg:match("profile%s+%w+%s+(%w+)")
        if subcmd == "start" then
            PerfLib:StartProfiling()
            PerfLib:Output("|cFF00FF00Performance profiling started|r")
        elseif subcmd == "stop" then
            PerfLib:StopProfiling()
            PerfLib:Output("|cFF00FF00Performance profiling stopped|r")
        elseif subcmd == "analyze" then
            PerfLib:AnalyzePerformance(scope or "all")
        else
            PerfLib:Output("|cFFFFFF00Usage: /perflib profile <start|stop|analyze> [all|eventbus|frame|dirty|pool|profile]|r")
        end
    elseif cmd == "analyze" then
        local scope = msg:match("analyze%s+(%w+)")
        PerfLib:AnalyzePerformance(scope or "all")
    elseif cmd == "test" then
        if arg == "eventbus" then
            local isolationPassed = RunEventBusIsolationTest()
            local dedupePassed = RunEventBusDuplicateRegistrationTest()
            if isolationPassed and dedupePassed then
                PerfLib:Output("|cFF00FF00EventBus self-tests passed.|r")
            else
                PerfLib:Output("|cFFFF0000EventBus self-tests failed. See messages above.|r")
            end
        elseif arg == "dirtypriority" then
            RunDirtyPriorityOptimizerWindowTest()
        elseif arg == "preset" then
            RunPresetValidationFallbackTest()
        else
            PerfLib:Output("|cFFFFFF00Usage: /perflib test <eventbus|dirtypriority|preset>|r")
        end
    elseif cmd == "help" then
        PrintHelp()
    else
        PerfLib:Output("|cFFFF0000Unknown command:|r " .. tostring(cmd))
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
