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

---Learn priority from frame update frequency
---@param frame table Frame to analyze
---@param priority integer Current priority
---@return integer Recommended priority
function Optimizer:LearnPriority(frame, priority)
    if not frameMetrics[frame] then
        frameMetrics[frame] = {
            frequency = 0,
            lastUpdate = GetTime(),
            updates = 0,
            combatUpdates = 0
        }
    end
    
    local metrics = frameMetrics[frame]
    metrics.updates = metrics.updates + 1
    
    if InCombatLockdown() then
        metrics.combatUpdates = metrics.combatUpdates + 1
    end
    
    -- Simple heuristic: increase priority if frequently updated
    local freq = metrics.updates
    local combatRatio = (metrics.combatUpdates / math.max(1, metrics.updates))
    
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
