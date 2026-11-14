-- =========================================================================
-- DIRTY FLAG MANAGER - Frame Batch Update Coordinator
-- =========================================================================
-- Tracks "dirty" frames that need updates and batches them with
-- adaptive batch sizing based on frame time budget.
--
-- Features:
--  - Priority-based processing (critical → low)
--  - Adaptive batch sizing (2-16 frames based on budget)
--  - Processing lock prevents re-entry
--  - Frame validation before processing

local _, PerformanceLib = ...

-- Upvalue cache: reduce global table lookups on hot paths
local GetTime = GetTime
local math_max = math.max
local math_min = math.min
local math_floor = math.floor
local math_ceil = math.ceil
local table_insert = table.insert
local table_remove = table.remove
local pcall = pcall
local unpack = unpack or table.unpack

if not PerformanceLib.DirtyFlagManager then
    PerformanceLib.DirtyFlagManager = {}
end

local DirtyFlagManager = PerformanceLib.DirtyFlagManager

DirtyFlagManager.PRIORITY_CRITICAL = 4   -- Process first
DirtyFlagManager.PRIORITY_HIGH = 3
DirtyFlagManager.PRIORITY_MEDIUM = 2
DirtyFlagManager.PRIORITY_LOW = 1        -- Process last

-- Dirty frame tracking by priority.
-- Each queue is consumed from the front (queue[head] = nil), which leaves nil holes, and the
-- length operator is undefined on tables with holes in Lua 5.1 - it may report 0 for a queue
-- that still holds frames. Heads and tails are therefore tracked explicitly; never use #queue.
local dirtyFrames = {
    {}, -- LOW
    {}, -- MEDIUM
    {}, -- HIGH
    {}, -- CRITICAL
}
local dirtyHeads = { 1, 1, 1, 1 }
local dirtyTails = { 0, 0, 0, 0 }
-- frame -> priority it is currently queued at. Gives O(1) dedup and lets a queue entry be
-- recognised as stale (the frame was re-queued at a higher priority, or already processed).
local pendingPriority = {}
local totalDirtyCount = 0

-- Statistics
local stats = {
    framesProcessed = 0,
    batchesRun = 0,
    invalidFramesSkipped = 0,
    priorityDecays = 0,
    processingBlocks = 0,
    budgetOverrides = 0
}

-- State
local isProcessing = false
local lastDecayTime = GetTime()
local accumulatedElapsed = 0
local batchSize = 10

local COMPACT_MIN_HEAD = 64
local DECAY_INTERVAL = 5

-- Longest a queue may be held back by the frame-time budget, in seconds (by dirty priority)
local MAX_DEFER_WINDOW = {
    [1] = 0.25, -- LOW
    [2] = 0.15, -- MEDIUM
    [3] = 0.08, -- HIGH
    [4] = 0,    -- CRITICAL (never deferred)
}
local deferredSince = {}

local function Push(priority, frame)
    local tail = dirtyTails[priority] + 1
    dirtyTails[priority] = tail
    dirtyFrames[priority][tail] = frame
end

local function ResetQueue(priority)
    dirtyHeads[priority] = 1
    dirtyTails[priority] = 0
end

---Slide the live part of a queue back to index 1 so a queue that never fully drains
---does not grow without bound.
local function CompactQueue(priority)
    local queue = dirtyFrames[priority]
    local head = dirtyHeads[priority]
    local tail = dirtyTails[priority]
    if head <= 1 then
        return
    end
    local write = 0
    for i = head, tail do
        local frame = queue[i]
        queue[i] = nil
        if frame ~= nil then
            write = write + 1
            queue[write] = frame
        end
    end
    dirtyHeads[priority] = 1
    dirtyTails[priority] = write
end

local function HasPendingDirty()
    return totalDirtyCount > 0
end

local function OnUpdate(_, elapsed)
    DirtyFlagManager:ProcessDirty(false, elapsed)
end

function DirtyFlagManager:_SetProcessingActive(active)
    if not self._frame then
        return
    end
    active = active and true or false
    if self._processingActive == active then
        return
    end
    self._processingActive = active
    self._frame:SetScript("OnUpdate", active and OnUpdate or nil)
end

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

    self:_SetProcessingActive(false)
end

---Mark a frame as dirty (needs update)
---@param frame table Frame object
---@param priority integer Priority level (1-4)
---@return boolean queued False when the frame was refused (manager disabled or no frame)
function DirtyFlagManager:MarkDirty(frame, priority)
    if not self._enabled or not frame then return false end

    priority = math_max(1, math_min(4, math_floor(tonumber(priority) or 2)))

    local current = pendingPriority[frame]
    if current then
        if current >= priority then
            return true  -- Already queued at this priority or better
        end
        -- Upgrade: the entry in the lower queue is now stale and is skipped when reached
    else
        totalDirtyCount = totalDirtyCount + 1
    end

    pendingPriority[frame] = priority
    Push(priority, frame)
    self:_SetProcessingActive(true)
    return true
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

---Run the cheapest update handler a frame offers. A plain function (not a closure) so
---processing a frame allocates nothing.
local function UpdateDirtyFrame(frame)
    -- Prefer incremental handlers first to avoid forcing
    -- frame-wide refreshes on dirty bursts.
    if frame.Update then
        frame:Update()
    elseif frame.sufUnitType or frame.__isSimpleUnitFrames then
        -- Avoid broad refresh fallbacks for SUF-owned frames.
        if frame.UpdateHealth then
            frame:UpdateHealth()
        elseif frame.UpdatePower then
            frame:UpdatePower()
        end
    elseif frame.UpdateAllElements then
        frame:UpdateAllElements("PerformanceLib_Dirty")
    elseif frame.UpdateAll then
        frame:UpdateAll()
    elseif frame.UpdateHealth then
        frame:UpdateHealth()
    end
end

---Move every waiting frame up one priority level so low-priority frames cannot starve.
local function DecayPriorities()
    -- Highest source first, so a frame climbs exactly one level per decay
    for priority = 3, 1, -1 do
        local queue = dirtyFrames[priority]
        for i = dirtyHeads[priority], dirtyTails[priority] do
            local frame = queue[i]
            queue[i] = nil
            if frame ~= nil and pendingPriority[frame] == priority then
                pendingPriority[frame] = priority + 1
                Push(priority + 1, frame)
            end
        end
        ResetQueue(priority)
    end
    stats.priorityDecays = stats.priorityDecays + 1
end

---Process all dirty frames
---@param forceFlush boolean Force process all frames immediately
---@param elapsed number|nil Elapsed time from OnUpdate
function DirtyFlagManager:ProcessDirty(forceFlush, elapsed)
    if type(elapsed) == "number" and elapsed > 0 then
        accumulatedElapsed = accumulatedElapsed + elapsed
    end

    if not self._enabled or isProcessing then
        if isProcessing then
            stats.processingBlocks = stats.processingBlocks + 1
        end
        if not self._enabled then
            self:_SetProcessingActive(false)
        end
        return
    end

    isProcessing = true

    local frameTimeBudget = PerformanceLib.FrameTimeBudget
    local adaptiveBatch = batchSize
    local minTickInterval = 0.0

    -- Adapt batch size based on frame time budget
    if frameTimeBudget and frameTimeBudget.GetLoadSample then
        local avg, p95 = frameTimeBudget:GetLoadSample()
        avg, p95 = avg or 0, p95 or 0
        if avg > 18 or p95 > 28 then
            adaptiveBatch = math_max(2, math_floor(batchSize / 4))
            minTickInterval = 0.030
        elseif avg > 16 or p95 > 24 then
            adaptiveBatch = math_max(2, math_floor(batchSize / 3))
            minTickInterval = 0.024
        elseif avg > 14 or p95 > 20 then
            adaptiveBatch = math_max(2, math_floor(batchSize / 2))
            minTickInterval = 0.018
        elseif avg < 11 and p95 < 16 then
            adaptiveBatch = math_min(16, batchSize * 2)
            minTickInterval = 0.0
        end
    end

    if not forceFlush and minTickInterval > 0 and accumulatedElapsed < minTickInterval then
        isProcessing = false
        return
    end
    accumulatedElapsed = 0

    local now = GetTime()

    -- Process by priority (high to low)
    for priority = 4, 1, -1 do
        local queue = dirtyFrames[priority]
        local head = dirtyHeads[priority]
        -- Frames queued while this pass runs (an update handler marking a frame dirty) wait
        -- for the next pass, so a forced flush cannot loop forever.
        local limit = dirtyTails[priority]
        local processed = 0

        -- Budget gate. FrameTimeBudget ranks priorities the other way round (1 = critical),
        -- so translate before asking. A queue the budget keeps refusing is processed anyway
        -- once it has waited MAX_DEFER_WINDOW, so a low frame rate delays updates but never
        -- starves them.
        local allowed = true
        if head > limit then
            deferredSince[priority] = nil
        elseif not forceFlush and priority ~= DirtyFlagManager.PRIORITY_CRITICAL
            and frameTimeBudget and frameTimeBudget.CanAfford
            and not frameTimeBudget:CanAfford(5 - priority, 1) then
            local since = deferredSince[priority]
            if not since then
                deferredSince[priority] = now
                allowed = false
            elseif now - since < MAX_DEFER_WINDOW[priority] then
                allowed = false
            else
                stats.budgetOverrides = stats.budgetOverrides + 1
            end
        end
        if allowed then
            deferredSince[priority] = nil
        else
            limit = head - 1
        end

        while head <= limit and (forceFlush or processed < adaptiveBatch) do
            local frame = queue[head]
            queue[head] = nil
            head = head + 1
            dirtyHeads[priority] = head

            -- Skip stale entries (frame was upgraded to a higher queue)
            if frame ~= nil and pendingPriority[frame] == priority then
                pendingPriority[frame] = nil
                totalDirtyCount = math_max(0, totalDirtyCount - 1)

                if self:_ValidateFrame(frame) then
                    local ok, err = pcall(UpdateDirtyFrame, frame)
                    if not ok then
                        PerformanceLib:Debug("DirtyFlagManager", "Frame update error: " .. tostring(err), 1)
                    end

                    stats.framesProcessed = stats.framesProcessed + 1
                    processed = processed + 1
                else
                    stats.invalidFramesSkipped = stats.invalidFramesSkipped + 1
                end
            end
        end

        if dirtyHeads[priority] > dirtyTails[priority] then
            ResetQueue(priority)
        elseif dirtyHeads[priority] > COMPACT_MIN_HEAD then
            CompactQueue(priority)
        end

        if processed > 0 then
            stats.batchesRun = stats.batchesRun + 1
        end
    end

    -- Priority decay (raise waiting frames over time to prevent starvation)
    if now - lastDecayTime > DECAY_INTERVAL then
        if HasPendingDirty() then
            DecayPriorities()
        end
        lastDecayTime = now
    end

    isProcessing = false
    if not HasPendingDirty() then
        self:_SetProcessingActive(false)
    end
end

---Set enabled state
---@param enabled boolean
function DirtyFlagManager:SetEnabled(enabled)
    self._enabled = enabled and true or false
    if not self._enabled then
        self:_SetProcessingActive(false)
    elseif HasPendingDirty() then
        self:_SetProcessingActive(true)
    end
end

---Set batch size
---@param size integer Frames per batch
function DirtyFlagManager:SetBatchSize(size)
    batchSize = math_max(2, size)
end

---Get dirty frame count
---@return integer Total dirty frames
function DirtyFlagManager:GetDirtyCount()
    return totalDirtyCount
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
        budgetOverrides = stats.budgetOverrides,
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
