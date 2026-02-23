-- =========================================================================
-- DIRTY FLAG MANAGER - Frame Batch Update Coordinator
-- =========================================================================
-- Tracks "dirty" frames that need updates and batches them with
-- adaptive batch sizing based on frame time budget.
--
-- Features:
--  - Priority-based processing (critical → low)
--  - Adaptive batch sizing (2-20 frames based on budget)
--  - Processing lock prevents re-entry
--  - Frame validation before processing

local _, PerformanceLib = ...

if not PerformanceLib.DirtyFlagManager then
    PerformanceLib.DirtyFlagManager = {}
end

local DirtyFlagManager = PerformanceLib.DirtyFlagManager

DirtyFlagManager.PRIORITY_CRITICAL = 4   -- Process first
DirtyFlagManager.PRIORITY_HIGH = 3
DirtyFlagManager.PRIORITY_MEDIUM = 2
DirtyFlagManager.PRIORITY_LOW = 1        -- Process last

-- Dirty frame tracking by priority
local dirtyFrames = {
    {}, -- CRITICAL
    {}, -- HIGH
    {}, -- MEDIUM
    {}, -- LOW
}

-- Statistics
local stats = {
    framesProcessed = 0,
    batchesRun = 0,
    invalidFramesSkipped = 0,
    priorityDecays = 0,
    processingBlocks = 0
}

-- State
local isProcessing = false
local lastProcessTime = GetTime()
local lastTickTime = 0
local batchSize = 10

---Initialize DirtyFlagManager
function DirtyFlagManager:Initialize()
    if self._initialized then return end
    self._initialized = true
    
    self._enabled = true
    self._frame = CreateFrame("Frame")
    self._frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self._frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self._frame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
            DirtyFlagManager:ProcessDirty(true)  -- Force flush on combat change
        end
    end)
    
    self._frame:SetScript("OnUpdate", function()
        DirtyFlagManager:ProcessDirty()
    end)
end

---Mark a frame as dirty (needs update)
---@param frame table Frame object
---@param priority integer Priority level (1-4)
function DirtyFlagManager:MarkDirty(frame, priority)
    if not self._enabled or not frame then return end
    
    priority = math.max(1, math.min(4, priority or 2))
    
    -- Add to priority queue if not already present
    for _, existingFrame in ipairs(dirtyFrames[priority]) do
        if existingFrame == frame then
            return  -- Already marked
        end
    end
    
    table.insert(dirtyFrames[priority], frame)
end

---Validate frame before processing
---@param frame table Frame to validate
---@return boolean True if valid and ready for processing
function DirtyFlagManager:_ValidateFrame(frame)
    if type(frame) ~= "table" then
        return false
    end
    
    if not frame.UpdateAll and not frame.Update and not frame.UpdateAllElements and not (frame.UpdateHealth or frame.UpdatePower) then
        return false
    end
    
    if frame.GetObjectType and not pcall(frame.GetObjectType, frame) then
        return false
    end
    
    return true
end

---Process all dirty frames
---@param forceFlush boolean Force process all frames immediately
function DirtyFlagManager:ProcessDirty(forceFlush)
    if not self._enabled or isProcessing then
        if isProcessing then
            stats.processingBlocks = stats.processingBlocks + 1
        end
        return
    end
    
    isProcessing = true
    
    local now = GetTime()
    local frameTimeBudget = PerformanceLib.FrameTimeBudget
    local budgetStats = frameTimeBudget and frameTimeBudget.GetStatistics and frameTimeBudget:GetStatistics() or nil
    local adaptiveBatch = batchSize
    local minTickInterval = 0.0
    
    -- Adapt batch size based on frame time budget
    if budgetStats then
        local avg = budgetStats.avg or 0
        local p95 = budgetStats.P95 or 0
        if avg > 18 or p95 > 28 then
            adaptiveBatch = math.max(2, math.floor(batchSize / 4))
            minTickInterval = 0.030
        elseif avg > 16 or p95 > 24 then
            adaptiveBatch = math.max(2, math.floor(batchSize / 3))
            minTickInterval = 0.024
        elseif avg > 14 or p95 > 20 then
            adaptiveBatch = math.max(2, math.floor(batchSize / 2))
            minTickInterval = 0.018
        elseif avg < 11 and p95 < 16 then
            adaptiveBatch = math.min(16, batchSize * 2)
            minTickInterval = 0.0
        end
    end

    if not forceFlush and minTickInterval > 0 and (now - lastTickTime) < minTickInterval then
        isProcessing = false
        return
    end
    
    -- Process by priority (high to low)
    for priority = 4, 1, -1 do
        local queue = dirtyFrames[priority]
        local processed = 0
        
        while #queue > 0 and (forceFlush or processed < adaptiveBatch) do
            local frame = table.remove(queue, 1)
            
            if self:_ValidateFrame(frame) then
                local ok, err = pcall(function()
                    if frame.UpdateAll then
                        frame:UpdateAll()
                    elseif frame.Update then
                        frame:Update()
                    elseif frame.UpdateAllElements then
                        frame:UpdateAllElements("PerformanceLib_Dirty")
                    elseif frame.UpdateHealth then
                        frame:UpdateHealth()
                    end
                end)
                
                if not ok then
                    PerformanceLib:Debug("DirtyFlagManager", "Frame update error: " .. tostring(err), 1)
                end
                
                stats.framesProcessed = stats.framesProcessed + 1
                processed = processed + 1
            else
                stats.invalidFramesSkipped = stats.invalidFramesSkipped + 1
            end
        end
        
        if processed > 0 then
            stats.batchesRun = stats.batchesRun + 1
        end
        
        -- Stop if budget exceeded
        if frameTimeBudget and frameTimeBudget.CanAfford then
            if not frameTimeBudget:CanAfford(priority, 1) then
                break
            end
        end
    end
    
    -- Priority decay (reduce priority over time to prevent starvation)
    if now - lastProcessTime > 5 then
        for priority = 1, 3 do
            for _, frame in ipairs(dirtyFrames[priority]) do
                table.insert(dirtyFrames[priority + 1], frame)
            end
            dirtyFrames[priority] = {}
        end
        stats.priorityDecays = stats.priorityDecays + 1
        lastProcessTime = now
    end
    
    lastTickTime = now
    isProcessing = false
end

---Set enabled state
---@param enabled boolean
function DirtyFlagManager:SetEnabled(enabled)
    self._enabled = enabled
end

---Set batch size
---@param size integer Frames per batch
function DirtyFlagManager:SetBatchSize(size)
    batchSize = math.max(2, size)
end

---Get dirty frame count
---@return integer Total dirty frames
function DirtyFlagManager:GetDirtyCount()
    local total = 0
    for _, queue in ipairs(dirtyFrames) do
        total = total + #queue
    end
    return total
end

---Get statistics
---@return table Stats object
function DirtyFlagManager:GetStats()
    return {
        framesProcessed = stats.framesProcessed,
        batchesRun = stats.batchesRun,
        invalidFramesSkipped = stats.invalidFramesSkipped,
        priorityDecays = stats.priorityDecays,
        processingBlocks = stats.processingBlocks,
        currentDirtyCount = self:GetDirtyCount()
    }
end

---Print statistics to chat
function DirtyFlagManager:PrintStats()
    local s = self:GetStats()
    print("|cFF00FF00Dirty Flag Manager Stats:|r")
    print(("  Frames Processed: %d | Batches: %d"):format(s.framesProcessed, s.batchesRun))
    print(("  Invalid Skipped: %d | Priority Decays: %d"):format(s.invalidFramesSkipped, s.priorityDecays))
    print(("  Current Dirty: %d | Processing Blocks: %d"):format(s.currentDirtyCount, s.processingBlocks))
end

-- Auto-initialize
DirtyFlagManager:Initialize()

return DirtyFlagManager
