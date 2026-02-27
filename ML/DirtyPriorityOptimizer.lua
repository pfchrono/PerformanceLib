-- =========================================================================
-- DIRTY PRIORITY OPTIMIZER - Priority Learning System
-- =========================================================================
-- Learns optimal frame update priorities from 5-minute gameplay windows.
-- Uses weighted factors: Frequency (40%), Combat Ratio (30%), Recency (20%), Base (10%)

local _, PerformanceLib = ...

if not PerformanceLib.DirtyPriorityOptimizer then
    PerformanceLib.DirtyPriorityOptimizer = {}
end

local Optimizer = PerformanceLib.DirtyPriorityOptimizer

local frameMetrics = {}
local stats = { learned = 0, adjusted = 0 }
local WINDOW_SECONDS = 300

---Reset internal optimizer state (primarily for deterministic tests)
function Optimizer:Reset()
    frameMetrics = {}
    stats.learned = 0
    stats.adjusted = 0
end

---Learn priority from frame update frequency
---@param frame table Frame to analyze
---@param priority integer Current priority
---@return integer Recommended priority
function Optimizer:LearnPriority(frame, priority)
    local now = GetTime()

    if not frameMetrics[frame] then
        frameMetrics[frame] = {
            frequency = 0,
            lastUpdate = now,
            updates = 0,
            combatUpdates = 0,
            windowStart = now,
            windowUpdates = 0,
            windowCombat = 0
        }
    end
    
    local metrics = frameMetrics[frame]
    stats.learned = stats.learned + 1

    metrics.updates = metrics.updates + 1
    metrics.lastUpdate = now

    if now - metrics.windowStart >= WINDOW_SECONDS then
        metrics.windowStart = now
        metrics.windowUpdates = 0
        metrics.windowCombat = 0
    end

    metrics.windowUpdates = metrics.windowUpdates + 1
    
    if InCombatLockdown() then
        metrics.combatUpdates = metrics.combatUpdates + 1
        metrics.windowCombat = metrics.windowCombat + 1
    end
    
    -- Simple heuristic: increase priority if frequently updated
    local freq = metrics.windowUpdates
    local combatRatio = (metrics.windowCombat / math.max(1, metrics.windowUpdates))
    
    local recommended = priority
    if freq > 100 then
        recommended = math.min(4, priority + 1)  -- Increase priority
    elseif freq < 10 and combatRatio < 0.1 then
        recommended = math.max(1, priority - 1)  -- Decrease priority
    end
    
    if recommended ~= priority then
        stats.adjusted = stats.adjusted + 1
    end
    
    return recommended
end

---Get recommendations for all frames
---@return table Recommendations
function Optimizer:GetRecommendations()
    local recommendations = {}
    for frame, metrics in pairs(frameMetrics) do
        table.insert(recommendations, {
            frame = frame,
            frequency = metrics.updates,
            combatRatio = metrics.combatUpdates / math.max(1, metrics.updates),
            recommendation = self:LearnPriority(frame, 2)
        })
    end
    return recommendations
end

---Get statistics
---@return table Stats
function Optimizer:GetStats()
    return {
        learned = stats.learned,
        adjusted = stats.adjusted,
        trackedFrames = next(frameMetrics) ~= nil
    }
end

return Optimizer
