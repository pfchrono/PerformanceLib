-- =========================================================================
-- ML OPTIMIZER - Neural Network-Based Event Prediction
-- =========================================================================
-- Advanced ML system for predicting event patterns and optimizing coalescing delays.
-- This is a stub that addon authors can expand with their own ML implementations.

local _, PerformanceLib = ...

if not PerformanceLib.MLOptimizer then
    PerformanceLib.MLOptimizer = {}
end

local MLOptimizer = PerformanceLib.MLOptimizer

-- Simplified ML tracking
local eventSequences = {}
local stats = {
    patterns = 0,
    predictions = 0,
    accuracy = 0,
    trained = false
}

---Register an event sequence for learning
---@param event string Event name
---@param followupEvent string Next likely event
---@param probability number Probability (0-1)
function MLOptimizer:RegisterSequence(event, followupEvent, probability)
    if not eventSequences[event] then
        eventSequences[event] = {}
    end
    
    eventSequences[event][followupEvent] = probability
    stats.patterns = stats.patterns + 1
end

---Predict next event based on current event
---@param currentEvent string Current event
---@return string|nil Predicted next event
---@return number Probability
function MLOptimizer:PredictNextEvent(currentEvent)
    if not eventSequences[currentEvent] then
        return nil, 0
    end
    
    local best = nil
    local bestProb = 0
    
    for event, prob in pairs(eventSequences[currentEvent]) do
        if prob > bestProb then
            best = event
            bestProb = prob
        end
    end
    
    if best then
        stats.predictions = stats.predictions + 1
    end
    
    return best, bestProb
end

---Get learned patterns
---@return table Patterns
function MLOptimizer:GetPatterns()
    return eventSequences
end

---Train the ML system (stub for addon implementation)
function MLOptimizer:Train()
    stats.trained = true
    return stats
end

---Get ML statistics
---@return table Stats
function MLOptimizer:GetStats()
    return {
        patterns = stats.patterns,
        predictions = stats.predictions,
        accuracy = stats.accuracy,
        trained = stats.trained
    }
end

return MLOptimizer
