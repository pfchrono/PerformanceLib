-- =========================================================================
-- README - PerformanceLib Documentation
-- =========================================================================

# PerformanceLib - Performance System Library for WoW Addons

A comprehensive, production-ready performance library for World of Warcraft addon developers. PerformanceLib provides battle-tested systems from UnhaltedUnitFrames, extracted as a reusable library.

## Features

### Core Systems
- **EventCoalescer**: Batch high-frequency WoW events with priority-based dispatch (4-tier system)
- **FrameTimeBudget**: Adaptive frame time throttling with P50/P95/P99 percentile tracking
- **DirtyFlagManager**: Intelligent frame update batching with adaptive batch sizing
- **FramePoolManager**: Object pooling to reduce GC pressure (tested 60-75% GC reduction)
- **IndicatorPooling**: Specialized lifecycle management for temporary indicators

### ML & Optimization Systems
- **DirtyPriorityOptimizer**: ML-based priority learning from gameplay patterns (5-minute windows)
- **MLOptimizer**: Transition-table (Markov-style) event learning with observed dispatch training

### Debug & Monitoring
- **DebugOutput**: Non-intrusive 3-tier debug message routing
- **PerformanceProfiler**: Real-time timeline recording with bottleneck detection
- **DebugPanel**: Built-in UI for monitoring all metrics

## Recent Enhancements (Waves 3-4)

- **Hot-path upvalue caching** in core per-frame systems (`EventCoalescer`, `DirtyFlagManager`, `FrameTimeBudget`)
- **FrameTimeBudget elapsed tracking** now uses engine-provided `elapsed` directly
- **MLOptimizer live learning** now records observed event transitions and computes rolling prediction accuracy
- **Example addon unit-scoped registration** now uses `RegisterUnitEvent` for `UNIT_*` examples
- **Dashboard telemetry polish**:
  - color-coded `FPS`, `P95`, and `P99`
  - added `Defers` and `Emergency` coalescer counters
- **DirtyFlagManager tick throttle optimization** using elapsed accumulation instead of per-tick wall-clock interval checks

Validation highlights from test runs:
- Stable frame budget and percentile behavior under sustained combat/event load
- No dropped/deferred frame-budget regressions observed in Wave 4 validation
- Coalescing/dirty pipelines remained stable while exposing clearer dashboard diagnostics

## Quick Start

### 1. Initialize the Library

```lua
-- In your addon's ADDON_LOADED event
local PerfLib = PerformanceLib
PerfLib:Initialize("MyAddonName")
PerfLib:SetPreset("Medium")  -- Low/Medium/High/Ultra
```

### 2. Use EventCoalescer for Batching

```lua
-- Instead of processing every WoW event immediately:
-- OLD: Frame:RegisterEvent("UNIT_HEALTH")
-- NEW: Register once for coalescing
local eventHandler = function(unit, health)
    -- Called in batches, not on every event
end

-- Queue events with priority
PerfLib:QueueEvent("UNIT_HEALTH", PerfLib.EventCoalescer.PRIORITY_HIGH, unit, health)
```

### 3. Mark Frames as Dirty Instead of Updating Immediately

```lua
-- OLD: frame:Update() on every event
-- NEW: Mark dirty and batch process
PerfLib:MarkFrameDirty(frame, 2)  -- Priority HIGH (2)
-- DirtyFlagManager batches these updates automatically
```

### 4. Use Frame Pooling

```lua
-- OLD: local btn = CreateFrame("Button", ...)
-- NEW: Use pooling
local btn = PerfLib:AcquireFrame("Button", parentFrame)
-- ... use button ...
-- When done:
PerfLib:ReleaseFrame(btn)  -- Returns to pool for reuse
```

### 5. Monitor Performance

```lua
-- Toggle dashboard
PerfLib:ToggleDashboard()

-- Get statistics
local stats = PerfLib:GetFrameTimeStats()
print("Current FPS:", 1000 / stats.avg)
print("P99 Frame Time:", stats.P99 .. "ms")

-- Profile specific operations
PerfLib:StartProfiling()
-- ... do work ...
PerfLib:StopProfiling()  -- Shows analysis
```

## Performance Gains

Typical results from UnhaltedUnitFrames:
- **EventCoalescer**: 60-70% callback reduction
- **DirtyFlagManager**: 50-60% faster frame updates
- **FramePoolManager**: 60-75% GC reduction
- **Overall**: 45-85% total performance improvement with zero HIGH frame spikes (P99 < 25ms)

## API Reference

### Library Methods

```lua
PerfLib:Initialize(addonName)              -- Initialize all systems
PerfLib:SetEnabled(boolean)                -- Enable/disable library
PerfLib:SetPreset(presetName)              -- Set Low/Medium/High/Ultra preset
PerfLib:QueueEvent(event, priority, ...)   -- Queue an event
PerfLib:MarkFrameDirty(frame, priority)    -- Mark frame for batched update
PerfLib:GetFrameTimeStats()                -- Get frame time metrics
PerfLib:AcquireFrame(type, parent, poolID) -- Get frame from pool
PerfLib:ReleaseFrame(frame)                -- Return frame to pool
PerfLib:ShowDashboard()                    -- Show performance dashboard
PerfLib:ToggleDashboard()                  -- Toggle dashboard visibility
PerfLib:Debug(system, message, tier)       -- Log debug message
PerfLib:GetVersion()                       -- Get library version
```

### Event Coalescing

Priority Levels:
- **CRITICAL (1)**: Immediate dispatch (health, power, combat state)
- **HIGH (2)**: 10ms batching (auras, max values)
- **MEDIUM (3)**: 30ms batching (threat, status updates)
- **LOW (4)**: 50ms batching (cosmetic, portrait updates)

```lua
PerfLib:QueueEvent("UNIT_HEALTH", PerfLib.EventCoalescer.PRIORITY_HIGH, unit)
```

### Frame Dirty Marking

Priority Levels (inverse of events):
- **CRITICAL (4)**: Process first
- **HIGH (3)**: Process second
- **MEDIUM (2)**: Process third
- **LOW (1)**: Process last

```lua
PerfLib:MarkFrameDirty(frame, PerfLib.DirtyFlagManager.PRIORITY_HIGH)
```

### Frame Pooling

```lua
-- Acquire different frame types
local button = PerfLib:AcquireFrame("Button", parentFrame, "AuraButtons")
local indicator = PerfLib:AcquireFrame("Frame", parentFrame, "Indicators")

-- Release back when done
PerfLib:ReleaseFrame(button)
PerfLib:ReleaseFrame(indicator)
```

## Slash Commands

```
/perflib ui          -- Toggle dashboard
/perflib ui show|hide -- Explicitly show/hide dashboard
/perflib dash        -- Alias for /perflib ui
/perflib stats       -- Print current performance stats
/perflib version     -- Show version
/perflib preset LOW  -- Change preset (Low/Medium/High/Ultra)
/perflib profile start|stop   -- Toggle profiling
/perflib profile sample <0.001-1.0> -- Set profiler sampling rate
/perflib profile analyze [scope] -- Analyze profile diagnostics
/perflib analyze [scope] -- Shortcut (all|eventbus|frame|dirty|pool|profile)
/perflib help        -- Show help
```

## Integration Examples

### Addon Using All Systems

```lua
local addon = CreateFrame("Frame")

addon:RegisterEvent("ADDON_LOADED")
addon:SetScript("OnEvent", function(self, event, name)
    if name ~= "MyAddon" then return end
    
    -- Initialize library
    PerformanceLib:Initialize("MyAddon")
    PerformanceLib:SetPreset("High")
    
    -- Set up event handling
    self.eventHandler = function(unit, health)
        -- Handle event (called in batches)
        MyAddonFrames:UpdateHealth(unit, health)
    end
    
    -- Register for event batching
    self:RegisterEvent("UNIT_HEALTH")
end)

addon:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_HEALTH" then
        -- Queue instead of processing immediately
        PerformanceLib:QueueEvent(event, PerformanceLib.EventCoalescer.PRIORITY_HIGH, ...)
    end
end)

-- Periodically check performance
addon:SetScript("OnUpdate", function(self, elapsed)
    self.checkTimer = (self.checkTimer or 0) + elapsed
    if self.checkTimer >= 5 then
        local stats = PerformanceLib:GetFrameTimeStats()
        if stats.P99 > 25 then
            print("WARNING: High frame time detected:", stats.P99 .. "ms")
        end
        self.checkTimer = 0
    end
end)
```

## License

PerformanceLib is licensed under the MIT license, same as UnhaltedUnitFrames.

## Support & Contributions

For issues, questions, or contributions, please refer to the UnhaltedUnitFrames project.
