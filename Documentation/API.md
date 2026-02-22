## PerformanceLib - Complete API Reference

### Library Initialization

```lua
-- Initialize the library (call in ADDON_LOADED event)
PerformanceLib:Initialize("YourAddonName")

-- Set performance preset
PerformanceLib:SetPreset("Medium")  -- Options: Low, Medium, High, Ultra

-- Enable/disable the entire library
PerformanceLib:SetEnabled(true)

-- Check if enabled
if PerformanceLib:IsEnabled() then
    print("Library is active")
end
```

### Event Coalescing

Priority levels:
- `EventCoalescer.PRIORITY_CRITICAL (1)` - Immediate dispatch
- `EventCoalescer.PRIORITY_HIGH (2)` - 10ms batching
- `EventCoalescer.PRIORITY_MEDIUM (3)` - 30ms batching  
- `EventCoalescer.PRIORITY_LOW (4)` - 50ms batching

```lua
-- Queue an event for batching
PerformanceLib:QueueEvent("UNIT_HEALTH", PerformanceLib.EventCoalescer.PRIORITY_HIGH, unit, health)

-- Manually flush queued events
PerformanceLib.EventCoalescer:Flush()

-- Get statistics
local stats = PerformanceLib.EventCoalescer:GetStats()
print("Coalesced:", stats.totalCoalesced, "Dispatched:", stats.totalDispatched)

-- Reset statistics
PerformanceLib.EventCoalescer:ResetStats()
```

### Frame Dirty Marking

Mark frames for batched updates instead of updating immediately.

Priority levels:
- `DirtyFlagManager.PRIORITY_CRITICAL (4)` - Process first
- `DirtyFlagManager.PRIORITY_HIGH (3)` - Process second
- `DirtyFlagManager.PRIORITY_MEDIUM (2)` - Process third
- `DirtyFlagManager.PRIORITY_LOW (1)` - Process last

```lua
-- Mark a frame as dirty
PerformanceLib:MarkFrameDirty(frame, PerformanceLib.DirtyFlagManager.PRIORITY_HIGH)

-- Get current dirty count
local dirtyCount = PerformanceLib.DirtyFlagManager:GetDirtyCount()

-- Print statistics
PerformanceLib.DirtyFlagManager:PrintStats()
```

### Frame Time Budget

Monitor frame time and defer operations if over budget.

Priority levels:
- `FrameTimeBudget.PRIORITY_CRITICAL (1)` - Always execute
- `FrameTimeBudget.PRIORITY_HIGH (2)` - 75% of budget
- `FrameTimeBudget.PRIORITY_MEDIUM (3)` - 60% of budget
- `FrameTimeBudget.PRIORITY_LOW (4)` - 40% of budget

```lua
-- Check if an operation can afford its cost
if PerformanceLib.FrameTimeBudget:CanAfford(priority, costInMs) then
    DoExpensiveOperation()
else
    -- Defer the operation
    PerformanceLib.FrameTimeBudget:DeferUpdate(DoExpensiveOperation, priority)
end

-- Get frame time statistics
local stats = PerformanceLib:GetFrameTimeStats()
print("Avg FPS:", 1000 / stats.avg)
print("P99:", stats.P99 .. "ms")

-- Set target frame time
PerformanceLib.FrameTimeBudget:SetTargetFrameTime(16.67)  -- 60 FPS

-- Print statistics
PerformanceLib.FrameTimeBudget:PrintStatistics()

-- Reset tracking
PerformanceLib.FrameTimeBudget:ResetStatistics()
```

### Frame Pooling

Reuse frames instead of creating/destroying them.

```lua
-- Acquire a frame from the pool
local button = PerformanceLib:AcquireFrame("Button", parentFrame, "MyPoolID")

-- Use the button
button:SetText("Click Me")

-- When done, release back to pool
PerformanceLib:ReleaseFrame(button)

-- Check pool statistics
PerformanceLib.FramePoolManager:PrintStats()

-- Release all frames in a pool
PerformanceLib.FramePoolManager:ReleaseAll("Button", "MyPoolID")
```

### Indicator Pooling

Manage temporary indicator lifecycles (auras, debuffs, etc).

```lua
-- Create a new indicator pool
local function createAuraButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(20, 20)
    return btn
end

local function resetAuraButton(btn)
    btn:SetParent(UIParent)
    btn:ClearAllPoints()
end

PerformanceLib.IndicatorPooling:CreatePool("AuraButtons", createAuraButton, resetAuraButton)

-- Acquire an indicator
local auraBtn = PerformanceLib.IndicatorPooling:AcquireIndicator("AuraButtons", parentFrame)

-- Release back
PerformanceLib.IndicatorPooling:ReleaseIndicator("AuraButtons", auraBtn)

-- Release all from pool
PerformanceLib.IndicatorPooling:ReleaseAllFromPool("AuraButtons")

-- Get statistics
local stats = PerformanceLib.IndicatorPooling:GetStats()
```

### Performance Monitoring

Track and optimize performance in real-time.

```lua
-- Start profiling
PerformanceLib:StartProfiling()

-- ... do gameplay ...

-- Stop and analyze
PerformanceLib:StopProfiling()  -- Prints analysis to chat

-- Or get timeline for custom analysis
local timeline = PerformanceLib.PerformanceProfiler:GetTimeline()
local analysis = PerformanceLib.PerformanceProfiler:Analyze()

-- Export timeline data
local csvData = PerformanceLib.PerformanceProfiler:Export()
```

### Dashboard & Debug Output

Monitor performance visually and log diagnostics.

```lua
-- Show performance dashboard
PerformanceLib:ShowDashboard()

-- Toggle it on/off
PerformanceLib:ToggleDashboard()

-- Log debug messages
PerformanceLib:Debug("MySystem", "Something happened", PerformanceLib.DebugOutput.TIER_INFO)

-- Enable debug for specific system
PerformanceLib.DebugOutput:EnableSystem("EventCoalescer")

-- Get all debug messages
local messages = PerformanceLib.DebugOutput:GetMessages("EventCoalescer")

-- Export debug logs
local log = PerformanceLib.DebugOutput:Export()
```

### Utility Functions

```lua
-- Get library version
local version = PerformanceLib:GetVersion()

-- Get addon that initialized the library
local initiator = PerformanceLib:GetInitiator()

-- Print comprehensive statistics to chat
PerformanceLib.Dashboard:PrintStats()
```

### Complete Integration Example

```lua
local MyAddon = {}

function MyAddon:Initialize()
    -- Init library
    PerformanceLib:Initialize("MyAddon")
    PerformanceLib:SetPreset("High")
    
    -- Track events
    self.eventRegistry = {}
end

function MyAddon:OnHealthUpdate(unit, health)
    -- Mark frames dirty instead of updating immediately
    local frame = self:GetUnitFrame(unit)
    if frame then
        PerformanceLib:MarkFrameDirty(frame, 2)  -- HIGH priority
    end
end

function MyAddon:OnExpensiveOperation(data)
    -- Check budget before doing expensive work
    if PerformanceLib.FrameTimeBudget:CanAfford(3, 5) then
        self:ProcessData(data)
    else
        -- Defer if frame time exceeded
        PerformanceLib.FrameTimeBudget:DeferUpdate(
            function() self:ProcessData(data) end,
            3  -- MEDIUM priority
        )
    end
end

-- In ADDON_LOADED:
-- MyAddon:Initialize()

return MyAddon
```

## Performance Benchmarks

Expected improvements (based on UnhaltedUnitFrames results):

| System | Improvement |
|--------|------------|
| EventCoalescer | 60-70% callback reduction |
| DirtyFlagManager | 50-60% faster updates |
| FramePoolManager | 60-75% GC reduction |
| Combined | 45-85% overall improvement |

Frame time targets:
- P50: 16.7ms (60 FPS)
- P95: <20ms  
- P99: <25ms
- Zero HIGH severity spikes (>33ms)

## Common Patterns

### Pattern 1: Event Batching

```lua
-- Register to coalesced event stream
PerformanceLib.Architecture.EventBus:Register("UNIT_HEALTH", function(unit, health)
    -- This is called in batches, not on every event
    UpdateHealthBar(unit, health)
end)

-- Queue events instead of processing immediately
function OnRawEvent(event, unit, health)
    PerformanceLib:QueueEvent(event, 2, unit, health)
end
```

### Pattern 2: Batched Frame Updates

```lua
-- Instead of updating every frame immediately:
function OnEventHandler(unit)
    frame:Update()  -- EXPENSIVE
end

-- Use dirty marking:
function OnEventHandler(unit)
    PerformanceLib:MarkFrameDirty(frame, 2)
end

-- Frames update in batches automatically
```

### Pattern 3: Memory Efficient Pooling

```lua
-- Don't create/destroy buttons on every aura update
-- Create a pool once:
function CreateAuraPool()
    local createFunc = function(parent)
        return CreateFrame("Button", nil, parent)
    end
    
    PerformanceLib.IndicatorPooling:CreatePool("AuraButtons", createFunc)
end

-- Then reuse auras:
function UpdateAuras(unit)
    for i, aura in ipairs(GetAuras(unit)) do
        local btn = PerformanceLib.IndicatorPooling:AcquireIndicator("AuraButtons", parent)
        btn:SetScript("OnClick", function() RemoveAura(aura) end)
        -- ... configure button ...
    end
end
```

This provides a complete reference for addon developers integrating PerformanceLib!
