# PerformanceLib — Enhancement TODO

> Generated from codebase analysis + research into modern WoW retail (11.0+) addon
> patterns (WeakAuras 2.12.4+, ElvUI, Plater). Organized into four waves that can be
> implemented and tested independently. Start with Wave 1 — it fixes correctness bugs
> with zero risk of regression.

---

## Wave 1 — P0: Critical Correctness Bugs [COMPLETED]

These are logic errors or unfulfilled design contracts. Tackle first.

---

### TODO-01 · EventBus handler error isolation [COMPLETED]
**File:** `Core/Architecture.lua`
**Lines:** 65–71 (`EventBus:Dispatch`)

**Problem:** No `pcall` around handler calls. One failing handler aborts all
subsequent handlers in the same dispatch cycle.

**Design:**
```lua
-- Replace raw calls (lines 65-71) with:
for _, entry in ipairs(self._handlers[event]) do
    local ok, err
    if entry.context then
        ok, err = pcall(entry.handler, entry.context, ...)
    else
        ok, err = pcall(entry.handler, ...)
    end
    if not ok then
        local ctx = entry.context and tostring(entry.context) or "nil"
        local msg = "EventBus error [" .. tostring(event) .. "] ctx=" .. ctx .. ": " .. tostring(err)
        if PerformanceLib and PerformanceLib.DebugOutput then
            PerformanceLib.DebugOutput:Output("EventBus", msg, 1)
        else
            print(msg)
        end
    end
end
```

**Test:** Register a handler we can trigger that calls `error("test")`, dispatch that event, confirm 
subsequent handlers still fire and the error message appears in chat/debug panel. [COMPLETED]

---

### TODO-02 · EventBus duplicate registration guard [COMPLETED]
**File:** `Core/Architecture.lua`
**Lines:** 40–43 (`EventBus:Register`, before the `table.insert`)

**Problem:** Same `{handler, context}` pair can be inserted multiple times — causes
double-dispatch on reload or addon init races.

**Design:**
```lua
-- Add before table.insert at line 40:
for _, entry in ipairs(self._handlers[event]) do
    if entry.handler == handler and entry.context == context then
        return  -- already registered, skip duplicate
    end
end
table.insert(self._handlers[event], { handler = handler, context = context })
```

**Test:** Call `EventBus:Register` twice with identical args; dispatch the event once;
confirm handler fires exactly once. [COMPLETED]
---

### TODO-03 · DirtyPriorityOptimizer — add time-windowed frequency counter [COMPLETED]
**File:** `ML/DirtyPriorityOptimizer.lua`
**Lines:** 22–54 (`Optimizer:LearnPriority`)

**Problem:** `metrics.updates` accumulates forever. After ~100 frames every active frame
always passes `freq > 100`, making the optimizer return the same priority regardless of
current activity. Header doc claims "5-minute rolling window" — not implemented.
`stats.learned` is also never incremented.

**Design:**
```lua
-- At frame entry creation, add three new fields:
frameMetrics[frame] = {
    -- existing fields...
    windowStart    = GetTime(),  -- when current 5-min window began
    windowUpdates  = 0,          -- updates in current window
    windowCombat   = 0,          -- combat updates in current window
}
stats.learned = stats.learned + 1  -- FIX: was never incremented

-- At top of LearnPriority body, after incrementing metrics.updates:
local now = GetTime()
if now - metrics.windowStart >= 300 then
    -- reset rolling window
    metrics.windowStart   = now
    metrics.windowUpdates = 0
    metrics.windowCombat  = 0
end
metrics.windowUpdates = metrics.windowUpdates + 1
if InCombatLockdown() then metrics.windowCombat = metrics.windowCombat + 1 end

-- Change threshold to use windowed counters instead of cumulative:
local freq       = metrics.windowUpdates
local combatRatio = metrics.windowCombat / math.max(1, metrics.windowUpdates)
```

**Test:** Let the optimizer run for several hundred frames, then call `GetRecommendations`.
Priorities should vary with actual update frequency rather than always hitting max. [COMPLETED]

---

### TODO-04 · Preset validation on boot [COMPLETED]
**File:** `PerformanceLib.lua`
**Lines:** 121–163 (`PerfLib:SetPreset`), boot call at ~line 614

**Problem:** Line 150 `if settings[preset] then` silently skips all configuration when
SavedVariables contains a corrupt/invalid preset name. No warning; subsystems run with
compiled-in defaults.

**Design:**
```lua
-- Add after line 124 (after the preset="" guard):
local VALID_PRESETS = { Low = true, Medium = true, High = true, Ultra = true }
if not VALID_PRESETS[preset] then
    PerfLib:Output(
        "|cFFFF8800PerformanceLib: Unknown preset '" .. tostring(preset)
        .. "', defaulting to Medium.|r"
    )
    preset = "Medium"
    self.db.presets = preset
end
```

**Test:** Corrupt `PerformanceLIBDB.presets = "invalid"` in SavedVariables, reload,
confirm a warning appears and the Medium preset is applied. [COMPLETED]

---

## Wave 2 — P1: High-Value WoW API Integration + UX [COMPLETED]

---

### TODO-05 · PerformanceProfiler — sampling rate + buffer-full warning [COMPLETED]
**File:** `Debug/PerformanceProfiler.lua`
**Lines:** 15–17 (constants), 37–41 (`StartProfiling`), 54–55 (record guard)

**Problem:** No sampling; `MAX_EVENTS = 10000` fills in minutes during high-event combat.
Buffer-full drops are silent — the user never knows data is being lost.

**Design:**
```lua
-- Add at top (after local declarations):
local samplingRate    = 1.0   -- 1.0 = record all events, 0.1 = 10%
local bufferFullWarned = false

-- In StartProfiling, add:
bufferFullWarned = false

-- Replace silent drop guard in RecordEvent:
if not isRecording then return end
if math.random() > samplingRate then return end
if #timeline >= MAX_EVENTS then
    if not bufferFullWarned then
        bufferFullWarned = true
        Output(
            "|cFFFF8800Profiler: buffer full (" .. MAX_EVENTS
            .. " events). Call :SetSamplingRate(0.1) to extend capture.|r",
            1
        )
    end
    return
end

-- New public method:
function Profiler:SetSamplingRate(rate)
    samplingRate    = math.max(0.001, math.min(1.0, tonumber(rate) or 1.0))
    bufferFullWarned = false
end
```

**References:**
- Default `1.0` preserves exact existing behavior — safe to ship.
- `SetSamplingRate(0.1)` extends a 10K-event buffer to ~10x longer sessions.
[Test: `/perflib profile sample <rate>`, `/perflib profile start|stop|analyze`, and buffer-full one-time warning under high-event load.] [COMPLETED]

---

### TODO-06 · Dashboard — GetNetStats() latency display [COMPLETED]
**File:** `Config/Dashboard.lua`
**Lines:** ~130 (inside `Dashboard:Update`, after the Memory line)

**Problem:** Dashboard shows FPS/frame-time but has no network latency info.
`GetNetStats()` is a standard WoW API returning `(bandwidthIn, bandwidthOut, lagHome, lagWorld)`.

**Design:**
```lua
-- Add upvalue at file top:
local GetNetStats = GetNetStats

-- In Dashboard:Update, add a Network section after the blank line at ~130:
lines[#lines + 1] = "|cFFFFD700=== Network ===|r"
local _, _, lagHome, lagWorld = GetNetStats()
lagHome  = lagHome  or 0
lagWorld = lagWorld or 0
local lagColor = lagHome < 50 and "|cFF00FF00" or (lagHome < 150 and "|cFFFFFF00" or "|cFFFF0000")
lines[#lines + 1] = ("Home: %s%dms|r  World: %dms"):format(lagColor, lagHome, lagWorld)
lines[#lines + 1] = ""
```

**References:**
- [GetNetStats API](https://wowpedia.fandom.com/wiki/API_GetNetStats) — updates ~30s,
  useful for trending not real-time.
- Color thresholds: green < 50ms, yellow 50–150ms, red > 150ms (standard community values).
[Test: `/perflib ui` shows Network section with Home/World latency and expected color behavior.] [COMPLETED]

---

### TODO-07 · Dashboard — position persistence [COMPLETED]
**File:** `Config/Dashboard.lua`
**Lines:** 41 (hardcoded `SetPoint`), 47 (`OnDragStop`)

**Problem:** Frame always starts at `TOPRIGHT -20 -220`. Users can drag it but position
resets on every reload. `PerformanceLIBDB` is already the SavedVariables table.

**Design:**
```lua
-- Replace line 41 with:
local db = PerformanceLIBDB or {}
if db.dashPos then
    frame:SetPoint(db.dashPos.point, UIParent, db.dashPos.relPoint, db.dashPos.x, db.dashPos.y)
else
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -220)
end

-- Replace line 47 (OnDragStop) with:
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    local db = PerformanceLIBDB or {}
    db.dashPos = { point = point, relPoint = relPoint, x = x, y = y }
    PerformanceLIBDB = db
end)
```

**Test:** Open dashboard, drag to new location, `/reload`, confirm it restores to the
dragged position. [COMPLETED]

---

### TODO-08 · Dashboard — replace collectgarbage with gcinfo() [COMPLETED]
**File:** `Config/Dashboard.lua`
**Line:** 129

**Problem:** `collectgarbage("count")` triggers a GC traversal every second.
`gcinfo()` returns approximate memory in KB without a traversal pass.

**References:**
- [gcinfo()](https://wowpedia.fandom.com/wiki/Lua_functions) — WoW-available, cheaper.
- Community guidance: ignore memory unless on extremely low-end system; CPU is bottleneck.

**Change:**
```lua
-- Line 129, before:
("Memory: |cFF00FF00%.2f MB|r"):format((collectgarbage("count") or 0) / 1024)
-- After:
("Memory: |cFF00FF00%.2f MB|r"):format(gcinfo() / 1024)
```
[Test: Dashboard memory metric continues to render and update via `/perflib ui`.] [COMPLETED]

---

## Wave 3 — P2: Architecture Hardening

---

### TODO-09 · Upvalue caching in hot-path files
**Files:** `Core/EventCoalescer.lua`, `Core/DirtyFlagManager.lua`, `Core/FrameTimeBudget.lua`

**Problem:** All three files run code every frame but repeatedly look up globals like
`GetTime`, `math.max`, `table.insert`, etc. Locals are stack-stored; globals require an
`_ENV` table lookup each call.

**Design:** Add this block after `local _, PerformanceLib = ...` in each file:
```lua
-- Upvalue cache: reduce global table lookups on hot paths
local GetTime      = GetTime
local math_max     = math.max
local math_min     = math.min
local math_floor   = math.floor
local math_ceil    = math.ceil
local table_insert = table.insert
local table_remove = table.remove
local pcall        = pcall
local unpack       = unpack or table.unpack
```
Then replace all usages of these globals throughout each file with the local names.

**References:**
- [Wowpedia: Lua Performance](https://wowpedia.fandom.com/wiki/Lua_functions) — "Cache
  frequently used globals as upvalues for performance-critical functions."
- Community standard for any OnUpdate-driven code.

**Scope:** ~10 lines added per file + ~25 name replacements across all three. No logic changes.

---

### TODO-10 · FrameTimeBudget — use `elapsed` directly in OnUpdate
**File:** `Core/FrameTimeBudget.lua`
**Lines:** ~112–124 (`TrackFrameTime` + its `SetScript` call)

**Problem:** `TrackFrameTime` ignores the engine-provided `elapsed` parameter and
calls `GetTime()` twice to compute delta. The engine's `elapsed` is already the precise
delta since the last OnUpdate — redundant calls.

**Design:**
```lua
-- Thread elapsed through OnUpdate:
self._frame:SetScript("OnUpdate", function(_, elapsed)
    self:TrackFrameTime(elapsed)
end)

-- Update TrackFrameTime signature:
function FrameTimeBudget:TrackFrameTime(elapsed)
    if not elapsed or elapsed <= 0 then return end
    local deltaTime = math_min(elapsed, 0.5) * 1000  -- ms, guard against outliers
    -- replace lastFrameTime subtraction with deltaTime
    ...
end
```

**Note:** `math.min(elapsed, 0.5)` protects history from loading-screen resumption spikes
where `elapsed` can be several seconds. Behavior is otherwise identical.

---

### TODO-11 · MLOptimizer — real transition-table learning
**Files:** `ML/MLOptimizer.lua`, `Core/EventCoalescer.lua`

**Problem:** `Train()` is a no-op. `stats.accuracy` is never computed. All predictions
rely on manually-registered sequences; the system never self-learns from gameplay.

**Design — MLOptimizer.lua:**
```lua
-- Add locals:
local _lastEvent = nil
local _observedTransitions = {}  -- [fromEvent][toEvent] = count
local _predictionHistory   = {}  -- rolling window for accuracy

-- New method: called from EventCoalescer after each dispatch
function MLOptimizer:ObserveEvent(eventName)
    if _lastEvent and eventName then
        if not _observedTransitions[_lastEvent] then
            _observedTransitions[_lastEvent] = {}
        end
        _observedTransitions[_lastEvent][eventName] =
            (_observedTransitions[_lastEvent][eventName] or 0) + 1
    end
    _lastEvent = eventName
end

-- Update Train() to normalize transition counts into probabilities and
-- merge into eventSequences (observed data takes precedence).
-- Compute stats.accuracy as correct/total over last 50 predictions.
-- Add auto-training ticker:
C_Timer.NewTicker(300, function() MLOptimizer:Train() end)
```

**Design — EventCoalescer.lua (hook in `_DispatchRegistered` after successful dispatch):**
```lua
-- Add after successful dispatch:
if PerformanceLib.MLOptimizer and PerformanceLib.MLOptimizer.ObserveEvent then
    PerformanceLib.MLOptimizer:ObserveEvent(eventName)
end
```

**Approach rationale:** A Markov-style transition table (observed frequency of A→B
transitions) is the appropriate "ML for Lua" approach — no external libraries, deterministic,
interpretable, and produces useful `PredictNextEvent` results.

---

### TODO-12 · Example docs — RegisterUnitEvent pattern
**File:** `Documentation/EXAMPLE_ADDON.lua`

**Problem:** Example registers `frame:RegisterEvent("UNIT_HEALTH")` which fires for
all 40+ raid members. `RegisterUnitEvent` fires only for specified units — major CPU win.

**Design:**
```lua
-- Replace:
frame:RegisterEvent("UNIT_HEALTH")
frame:RegisterEvent("UNIT_MAXHEALTH")
frame:RegisterEvent("UNIT_NAME_UPDATE")

-- With:
-- NOTE: RegisterUnitEvent fires ONLY for the listed units, unlike RegisterEvent
-- which fires for all 40+ raid members. This is the WeakAuras 2.12.4+ recommended
-- pattern for UNIT_* events (major CPU win in raid environments).
frame:RegisterUnitEvent("UNIT_HEALTH",      "player", "target")
frame:RegisterUnitEvent("UNIT_MAXHEALTH",   "player", "target")
frame:RegisterUnitEvent("UNIT_NAME_UPDATE", "player", "target")
```

**References:**
- [WeakAuras GitHub issue #1185](https://github.com/WeakAuras/WeakAuras2/issues/1185) —
  documents the RegisterUnitEvent change in WA 2.12.4 and the performance rationale.

---

## Wave 4 — P3: Polish

---

### TODO-13 · Dashboard — color-coded FPS + P95, budget defers stat
**File:** `Config/Dashboard.lua`
**Lines:** ~126–128 (FPS/P95 lines) and ~134–137 (Event Coalescing section)

**Design:**
```lua
-- Color-coded FPS (replace line 126):
local fpsColor = fps >= 55 and "|cFF00FF00" or (fps >= 30 and "|cFFFFFF00" or "|cFFFF0000")
lines[#lines + 1] = ("FPS: %s%.1f|r"):format(fpsColor, fps)

-- Color-coded P95 (replace line 128):
local p95 = frameStats.P95 or 0
local p95Color = p95 < 16.67 and "|cFF00FF00" or (p95 < 25 and "|cFFFFFF00" or "|cFFFF0000")
lines[#lines + 1] = ("P95/P99: %s%.2f|r / %.2fms"):format(p95Color, p95, frameStats.P99 or 0)

-- Add to Event Coalescing section:
lines[#lines + 1] = ("Defers: |cFFAAAAAA%d|r  Emergency: |cFFFF8800%d|r"):format(
    eventStats.budgetDefers or 0, eventStats.emergencyFlushes or 0)
```

---

### TODO-14 · DirtyFlagManager — elapsed-based tick throttle
**File:** `Core/DirtyFlagManager.lua`

**Problem:** `ProcessDirty` calls `GetTime()` on every OnUpdate to check interval.
With upvalue caching from TODO-09 this is already cheaper, but accumulating `elapsed`
avoids the call entirely.

**Design:** Thread `elapsed` from OnUpdate. Accumulate in a local `accumulatedElapsed`.
Skip `ProcessDirty` call if `accumulatedElapsed < minTickInterval`; reset accumulator
when processing runs. Do this after TODO-09 upvalue work is committed to same file.

---

## References & Sources

| Topic | Source |
|-------|--------|
| `GetNetStats()` API | https://wowpedia.fandom.com/wiki/API_GetNetStats |
| `GetFramerate()` API | https://wowpedia.fandom.com/wiki/API_GetFramerate |
| `RegisterUnitEvent` | https://github.com/WeakAuras/WeakAuras2/issues/1185 |
| OnUpdate best practices | https://wowpedia-archive.fandom.com/wiki/Using_OnUpdate_correctly |
| Table recycling / GC | https://wowpedia.fandom.com/wiki/HOWTO:_Use_Tables_Without_Generating_Extra_Garbage |
| Upvalue optimization | https://wowpedia.fandom.com/wiki/Lua_functions |
| Lua resource pooling | https://wowpedia.fandom.com/wiki/Resource_pooling |
| Mystler's WoW perf guide | https://gist.github.com/Mystler/3b6ef587bc0440959e4fee6d9c69c062 |
| AddonUsage profiler | https://www.curseforge.com/wow/addons/addon-usage |
| `gcinfo()` | https://wowpedia.fandom.com/wiki/Lua_functions |

---

## Quick Reference — All TODOs

| ID | Wave | File(s) | Description | Risk |
|----|------|---------|-------------|------|
| TODO-01 | 1 | Architecture.lua | pcall in EventBus:Dispatch [COMPLETED] | None |
| TODO-02 | 1 | Architecture.lua | Dedup in EventBus:Register [COMPLETED] | None |
| TODO-03 | 1 | DirtyPriorityOptimizer.lua | 5-min time-windowed frequency [COMPLETED] | Low |
| TODO-04 | 1 | PerformanceLib.lua | Preset validation + fallback [COMPLETED] | None |
| TODO-05 | 2 | PerformanceProfiler.lua | Sampling rate + buffer warning [COMPLETED] | None |
| TODO-06 | 2 | Dashboard.lua | GetNetStats() latency section [COMPLETED] | None |
| TODO-07 | 2 | Dashboard.lua | Position persistence [COMPLETED] | Negligible |
| TODO-08 | 2 | Dashboard.lua | gcinfo() instead of collectgarbage [COMPLETED] | None |
| TODO-09 | 3 | EventCoalescer/DirtyFlag/FrameTime | Upvalue caching | None |
| TODO-10 | 3 | FrameTimeBudget.lua | Use elapsed in TrackFrameTime | Low |
| TODO-11 | 3 | MLOptimizer.lua + EventCoalescer | Transition-table learning | Low |
| TODO-12 | 3 | EXAMPLE_ADDON.lua | RegisterUnitEvent docs | None |
| TODO-13 | 4 | Dashboard.lua | Color-coded FPS/P95 + defers stat | None |
| TODO-14 | 4 | DirtyFlagManager.lua | elapsed-based tick throttle | Low |




