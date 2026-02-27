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

-- Learned/registered transition probabilities used by prediction.
local eventSequences = {}
-- Manually registered seed sequences.
local manualSequences = {}
-- Observed transition counts from live dispatches.
local observedTransitions = {}
-- Rolling prediction correctness history (1=true, 0=false).
local predictionHistory = {}
local PREDICTION_HISTORY_MAX = 50
local pendingPrediction = nil
local lastObservedEvent = nil
local trainingTicker = nil

local stats = {
    patterns = 0,
    predictions = 0,
    predictionsEvaluated = 0,
    predictionsCorrect = 0,
    accuracy = 0,
    trained = false,
    observedTransitions = 0,
    trainingRuns = 0,
}

local function CountPatterns(sequences)
    local count = 0
    for _, followups in pairs(sequences) do
        for _ in pairs(followups) do
            count = count + 1
        end
    end
    return count
end

local function PushPredictionResult(correct)
    predictionHistory[#predictionHistory + 1] = correct and 1 or 0
    if #predictionHistory > PREDICTION_HISTORY_MAX then
        table.remove(predictionHistory, 1)
    end

    local total = #predictionHistory
    local hit = 0
    for i = 1, total do
        hit = hit + predictionHistory[i]
    end

    stats.predictionsEvaluated = total
    stats.predictionsCorrect = hit
    stats.accuracy = total > 0 and (hit / total) or 0
end

local function EnsureTrainingTicker()
    if trainingTicker or not (C_Timer and C_Timer.NewTicker) then
        return
    end
    trainingTicker = C_Timer.NewTicker(300, function()
        MLOptimizer:Train()
    end)
end

---Register an event sequence for learning
---@param event string Event name
---@param followupEvent string Next likely event
---@param probability number Probability (0-1)
function MLOptimizer:RegisterSequence(event, followupEvent, probability)
    if type(event) ~= "string" or event == "" or type(followupEvent) ~= "string" or followupEvent == "" then
        return false
    end
    probability = math.max(0, math.min(1, tonumber(probability) or 0))

    if not manualSequences[event] then
        manualSequences[event] = {}
    end
    manualSequences[event][followupEvent] = probability

    if not eventSequences[event] then
        eventSequences[event] = {}
    end
    eventSequences[event][followupEvent] = probability
    stats.patterns = CountPatterns(eventSequences)
    return true
end

---Observe a dispatched event and learn transition frequencies.
---@param eventName string
function MLOptimizer:ObserveEvent(eventName)
    if type(eventName) ~= "string" or eventName == "" then
        return
    end

    if pendingPrediction then
        PushPredictionResult(pendingPrediction == eventName)
        pendingPrediction = nil
    end

    if lastObservedEvent then
        if not observedTransitions[lastObservedEvent] then
            observedTransitions[lastObservedEvent] = {}
        end
        local row = observedTransitions[lastObservedEvent]
        row[eventName] = (row[eventName] or 0) + 1
    end

    lastObservedEvent = eventName
end

---Predict next event based on current event
---@param currentEvent string Current event
---@return string|nil Predicted next event
---@return number Probability
function MLOptimizer:PredictNextEvent(currentEvent)
    if type(currentEvent) ~= "string" or currentEvent == "" then
        return nil, 0
    end
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
        pendingPrediction = best
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
    local merged = {}

    -- Start from manual registrations.
    for eventName, followups in pairs(manualSequences) do
        merged[eventName] = merged[eventName] or {}
        for nextEvent, prob in pairs(followups) do
            merged[eventName][nextEvent] = prob
        end
    end

    -- Normalize observed transitions into probabilities and let observed
    -- data override manual entries for the same transition.
    local observedPatternCount = 0
    for eventName, row in pairs(observedTransitions) do
        local total = 0
        for _, count in pairs(row) do
            total = total + count
        end
        if total > 0 then
            merged[eventName] = merged[eventName] or {}
            for nextEvent, count in pairs(row) do
                merged[eventName][nextEvent] = count / total
                observedPatternCount = observedPatternCount + 1
            end
        end
    end

    eventSequences = merged
    stats.patterns = CountPatterns(eventSequences)
    stats.observedTransitions = observedPatternCount
    stats.trainingRuns = stats.trainingRuns + 1
    stats.trained = true
    EnsureTrainingTicker()
    return stats
end

---Get ML statistics
---@return table Stats
function MLOptimizer:GetStats()
    return {
        patterns = stats.patterns,
        predictions = stats.predictions,
        predictionsEvaluated = stats.predictionsEvaluated,
        predictionsCorrect = stats.predictionsCorrect,
        accuracy = stats.accuracy,
        trained = stats.trained,
        observedTransitions = stats.observedTransitions,
        trainingRuns = stats.trainingRuns,
    }
end

EnsureTrainingTicker()

return MLOptimizer
