-- =========================================================================
-- FRAME TIME BUDGET - Adaptive Frame Time Throttling
-- =========================================================================
-- Tracks frame time and allows operations to check if they can afford
-- expensive updates based on current frame time vs target.
--
-- Maintains O(1) incremental averaging with P50/P95/P99 percentiles.
-- Defers non-critical operations when frame time exceeds budget.

local _, PerformanceLib = ...

if not PerformanceLib.FrameTimeBudget then
    PerformanceLib.FrameTimeBudget = {}
end

local FrameTimeBudget = PerformanceLib.FrameTimeBudget

FrameTimeBudget.PRIORITY_CRITICAL = 1
FrameTimeBudget.PRIORITY_HIGH = 2
FrameTimeBudget.PRIORITY_MEDIUM = 3
FrameTimeBudget.PRIORITY_LOW = 4

local MAX_DEFERRED_QUEUE = 200
local HISTOGRAM_BUCKETS = 6

-- Frame time tracking
local frameTimeHistory = {}
local frameTimeHistoryIdx = 1
local HISTORY_SIZE = 100
local lastFrameTime = nil
local runningTotal = 0
local frameCount = 0
local historyCount = 0

-- Percentile tracking (lazy evaluated)
local percentiles = {
    P50 = 0,
    P95 = 0,
    P99 = 0,
}
local lastPercentileCalc = 0

-- Deferred queues by priority
local deferredQueues = {
    {}, -- CRITICAL
    {}, -- HIGH
    {}, -- MEDIUM
    {}, -- LOW
}
local deferredQueueHeads = { 1, 1, 1, 1 }
local deferredPendingCount = 0

-- Statistics
local stats = {
    avg = 0,
    min = math.huge,
    max = 0,
    droppedCallbacks = 0,
    deferredCount = 0,
    histogram = {}
}

local function DeferredQueueLength(priority)
    local queue = deferredQueues[priority]
    local head = deferredQueueHeads[priority]
    if not queue or not head or head > #queue then
        return 0
    end
    return (#queue - head + 1)
end

local function CompactDeferredQueue(priority)
    local queue = deferredQueues[priority]
    local head = deferredQueueHeads[priority]
    if not queue or not head then
        return
    end
    if head <= 1 then
        return
    end
    if head > #queue then
        deferredQueues[priority] = {}
        deferredQueueHeads[priority] = 1
        return
    end

    local compact = {}
    local write = 1
    for i = head, #queue do
        local item = queue[i]
        if item ~= nil then
            compact[write] = item
            write = write + 1
        end
    end
    deferredQueues[priority] = compact
    deferredQueueHeads[priority] = 1
end

---Initialize FrameTimeBudget
function FrameTimeBudget:Initialize()
    if self._initialized then return end
    self._initialized = true
    
    -- Initialize history array
    for i = 1, HISTORY_SIZE do
        frameTimeHistory[i] = 0
    end
    
    self._targetFrameTime = 16.67 -- 60 FPS
    self._frame = CreateFrame("Frame")
    self._frame:SetScript("OnUpdate", function() self:TrackFrameTime() end)
end

---Track frame time and update statistics O(1)
function FrameTimeBudget:TrackFrameTime()
    local currentTime = GetTime()
    if not lastFrameTime then
        lastFrameTime = currentTime
        return
    end

    local deltaTime = (currentTime - lastFrameTime) * 1000 -- ms
    lastFrameTime = currentTime
    
    -- O(1) incremental averaging
    local oldSample = frameTimeHistory[frameTimeHistoryIdx] or 0
    if historyCount >= HISTORY_SIZE then
        runningTotal = runningTotal - oldSample
    else
        historyCount = historyCount + 1
    end
    frameTimeHistory[frameTimeHistoryIdx] = deltaTime
    runningTotal = runningTotal + deltaTime
    frameCount = frameCount + 1
    frameTimeHistoryIdx = frameTimeHistoryIdx + 1
    
    if frameTimeHistoryIdx > HISTORY_SIZE then
        frameTimeHistoryIdx = 1
    end
    
    -- Maintain running avg
    stats.avg = runningTotal / math.max(1, historyCount)
    stats.min = math.min(stats.min, deltaTime)
    stats.max = math.max(stats.max, deltaTime)
    
    -- Lazy percentile calculation (every 30 frames)
    if frameCount % 30 == 0 then
        self:CalculatePercentiles()
    end
    
    -- Update histogram
    self:UpdateHistogram(deltaTime)
    
    -- Process deferred callbacks if time permits
    self:ProcessDeferred()
end

---Calculate P50, P95, P99 percentiles (lazy)
function FrameTimeBudget:CalculatePercentiles()
    local sorted = {}
    local len = historyCount
    if len == 0 then
        return
    end
    
    for i = 1, len do
        sorted[i] = frameTimeHistory[i]
    end
    
    table.sort(sorted)
    
    percentiles.P50 = sorted[math.ceil(len * 0.5)]
    percentiles.P95 = sorted[math.ceil(len * 0.95)]
    percentiles.P99 = sorted[math.ceil(len * 0.99)]
end

---Update histogram distribution
---@param frameTime number Frame time in ms
function FrameTimeBudget:UpdateHistogram(frameTime)
    local bucket
    if frameTime < 5 then bucket = 1
    elseif frameTime < 10 then bucket = 2
    elseif frameTime < 15 then bucket = 3
    elseif frameTime < 20 then bucket = 4
    elseif frameTime < 30 then bucket = 5
    else bucket = 6
    end
    
    if not stats.histogram[bucket] then
        stats.histogram[bucket] = 0
    end
    stats.histogram[bucket] = stats.histogram[bucket] + 1
end

---Check if current budget allows an operation
---@param priority integer Priority (1-4)
---@param estimatedCost number Estimated cost in ms
---@return boolean True if can afford
function FrameTimeBudget:CanAfford(priority, estimatedCost)
    if priority == FrameTimeBudget.PRIORITY_CRITICAL then
        return true  -- Always afford critical
    end
    
    -- Threshold based on priority
    local threshold
    if priority == FrameTimeBudget.PRIORITY_HIGH then
        threshold = self._targetFrameTime * 0.75
    elseif priority == FrameTimeBudget.PRIORITY_MEDIUM then
        threshold = self._targetFrameTime * 0.60
    else -- LOW
        threshold = self._targetFrameTime * 0.40
    end
    
    return (stats.avg + estimatedCost) <= threshold
end

---Defer an operation if budget exceeded
---@param callback function Operation to defer
---@param priority integer Priority level
---@param context any Optional context
---@return boolean True if deferred, false if executed immediately
function FrameTimeBudget:DeferUpdate(callback, priority, context)
    priority = priority or FrameTimeBudget.PRIORITY_MEDIUM
    
    if self:CanAfford(priority, 0.5) then
        -- Execute immediately if we can afford it
        local ok, err = pcall(callback, context)
        if not ok then
            PerformanceLib:Debug("FrameTimeBudget", "Callback error: " .. tostring(err), 1)
        end
        return false
    end
    
    -- Defer the operation
    if DeferredQueueLength(priority) >= MAX_DEFERRED_QUEUE then
        -- Drop LOW priority callbacks if queue full
        if priority == FrameTimeBudget.PRIORITY_LOW then
            stats.droppedCallbacks = stats.droppedCallbacks + 1
            return false
        end
    end
    
    table.insert(deferredQueues[priority], {callback = callback, context = context})
    deferredPendingCount = deferredPendingCount + 1
    stats.deferredCount = stats.deferredCount + 1
    return true
end

---Process deferred callbacks
function FrameTimeBudget:ProcessDeferred()
    local processed = 0
    
    -- Process in priority order
    for priority = FrameTimeBudget.PRIORITY_CRITICAL, FrameTimeBudget.PRIORITY_LOW do
        if not self:CanAfford(priority, 1) then
            break  -- Stop if budget exceeded
        end
        
        local queue = deferredQueues[priority]
        local head = deferredQueueHeads[priority]
        while DeferredQueueLength(priority) > 0 do
            local item = queue[head]
            queue[head] = nil
            head = head + 1
            deferredQueueHeads[priority] = head
            deferredPendingCount = math.max(0, deferredPendingCount - 1)

            local ok, err = pcall(item.callback, item.context)
            if not ok then
                PerformanceLib:Debug("FrameTimeBudget", "Deferred callback error: " .. tostring(err), 1)
            end
            processed = processed + 1
            
            if processed >= 5 then
                return  -- Limit batch size
            end
        end

        if DeferredQueueLength(priority) == 0 then
            deferredQueues[priority] = {}
            deferredQueueHeads[priority] = 1
        elseif deferredQueueHeads[priority] > 32 and deferredQueueHeads[priority] > math.floor(#deferredQueues[priority] / 2) then
            CompactDeferredQueue(priority)
        end
    end
end

---Set target frame time (ms)
---@param targetMs number Target milliseconds (16.67 for 60 FPS)
function FrameTimeBudget:SetTargetFrameTime(targetMs)
    self._targetFrameTime = targetMs or 16.67
end

---Get statistics
---@return table Stats object
function FrameTimeBudget:GetStatistics()
    return {
        avg = stats.avg,
        min = stats.min,
        max = stats.max,
        P50 = percentiles.P50,
        P95 = percentiles.P95,
        P99 = percentiles.P99,
        histogram = stats.histogram,
        deferredCount = deferredPendingCount,
        droppedCallbacks = stats.droppedCallbacks
    }
end

---Print statistics to chat
function FrameTimeBudget:PrintStatistics()
    local s = self:GetStatistics()
    print("|cFF00FF00Frame Time Budget Stats:|r")
    print(("  Avg: %.2f ms | Min: %.2f ms | Max: %.2f ms"):format(s.avg, s.min, s.max))
    print(("  P50: %.2f ms | P95: %.2f ms | P99: %.2f ms"):format(s.P50, s.P95, s.P99))
    print(("  Deferred: %d | Dropped: %d"):format(s.deferredCount, s.droppedCallbacks))
end

---Reset statistics
function FrameTimeBudget:ResetStatistics()
    stats.avg = 0
    stats.min = math.huge
    stats.max = 0
    stats.droppedCallbacks = 0
    stats.deferredCount = 0
    stats.histogram = {}
    runningTotal = 0
    frameCount = 0
    historyCount = 0
    frameTimeHistoryIdx = 1
    for i = 1, HISTORY_SIZE do
        frameTimeHistory[i] = 0
    end
    for i = 1, 4 do
        deferredQueues[i] = {}
        deferredQueueHeads[i] = 1
    end
    deferredPendingCount = 0
    lastFrameTime = nil
end

-- Auto-initialize
FrameTimeBudget:Initialize()

return FrameTimeBudget
