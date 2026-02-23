-- =========================================================================
-- EVENT COALESCER - Event Batching & Priority System
-- =========================================================================

local _, PerformanceLib = ...

if not PerformanceLib.EventCoalescer then
    PerformanceLib.EventCoalescer = {}
end

local EventCoalescer = PerformanceLib.EventCoalescer

EventCoalescer.PRIORITY_CRITICAL = 1
EventCoalescer.PRIORITY_HIGH = 2
EventCoalescer.PRIORITY_MEDIUM = 3
EventCoalescer.PRIORITY_LOW = 4

local DEFAULT_DELAY = 0.05
local MAX_DELAY = 0.5
local MAX_BUDGET_DEFERS_BY_PRIORITY = {
    [1] = 0,
    [2] = 5,
    [3] = 7,
    [4] = 9,
}
local MAX_DEFER_WINDOW_BY_PRIORITY = {
    [1] = 0.0,
    [2] = 0.35,
    [3] = 0.45,
    [4] = 0.55,
}

local COALESCE_INTERVALS = {
    [1] = 0.000,
    [2] = 0.010,
    [3] = 0.030,
    [4] = 0.050,
}

local registeredEvents = {}
local queuedEvents = {}
local lastDispatchTime = {}

local stats = {
    totalCoalesced = 0,
    totalDispatched = 0,
    totalRejected = 0,
    budgetDefers = 0,
    emergencyFlushes = 0,
    immediateCritical = 0,
    perEvent = {},
    rejectedCounts = {},
    batchSizes = {},
}

local function EnsureEventStats(event)
    if not stats.perEvent[event] then
        stats.perEvent[event] = { coalesced = 0, dispatched = 0 }
    end
    if not stats.batchSizes[event] then
        stats.batchSizes[event] = { min = 999999, max = 0, total = 0, count = 0 }
    end
end

local function DispatchToBus(event, ...)
    if PerformanceLib.Architecture and PerformanceLib.Architecture.EventBus then
        PerformanceLib.Architecture.EventBus:Dispatch(event, ...)
    end
end

function EventCoalescer:Initialize()
    if self._initialized then
        return
    end
    self._initialized = true
    self._enabled = true
    self._frame = CreateFrame("Frame")
    self._frame:SetScript("OnUpdate", function()
        self:ProcessQueue()
    end)
end

function EventCoalescer:CoalesceEvent(eventName, delay, callback, priority)
    if type(eventName) ~= "string" or type(callback) ~= "function" then
        return false
    end

    delay = math.max(0.0, math.min(MAX_DELAY, tonumber(delay) or DEFAULT_DELAY))
    priority = math.max(1, math.min(4, tonumber(priority) or EventCoalescer.PRIORITY_MEDIUM))

    if not registeredEvents[eventName] then
        registeredEvents[eventName] = {
            callbacks = {},
            delay = delay,
            priority = priority,
            pendingArgs = nil,
            coalesceCount = 0,
            lastFire = 0,
            firstQueuedAt = 0,
            deferCount = 0,
            scheduled = false,
        }
    end

    local data = registeredEvents[eventName]
    data.delay = delay
    data.priority = priority

    for i = 1, #data.callbacks do
        if data.callbacks[i] == callback then
            return true
        end
    end

    table.insert(data.callbacks, callback)
    EnsureEventStats(eventName)
    return true
end

function EventCoalescer:UncoalesceEvent(eventName, callback)
    local data = registeredEvents[eventName]
    if not data then
        return false
    end
    for i = #data.callbacks, 1, -1 do
        if data.callbacks[i] == callback then
            table.remove(data.callbacks, i)
            return true
        end
    end
    return false
end

function EventCoalescer:SetEventDelay(eventName, delay)
    local data = registeredEvents[eventName]
    if not data then
        return false
    end
    data.delay = math.max(0.01, math.min(MAX_DELAY, tonumber(delay) or DEFAULT_DELAY))
    return true
end

function EventCoalescer:GetEventDelay(eventName)
    local data = registeredEvents[eventName]
    return data and data.delay or DEFAULT_DELAY
end

function EventCoalescer:GetCoalescedEvents()
    local list = {}
    for eventName in pairs(registeredEvents) do
        table.insert(list, eventName)
    end
    return list
end

local function RecordBatch(eventName, size)
    EnsureEventStats(eventName)
    local b = stats.batchSizes[eventName]
    b.min = math.min(b.min, size)
    b.max = math.max(b.max, size)
    b.total = b.total + size
    b.count = b.count + 1
end

function EventCoalescer:_DispatchRegistered(eventName)
    local data = registeredEvents[eventName]
    if not data or data.coalesceCount <= 0 then
        return false
    end

    local canAfford = true
    if PerformanceLib.FrameTimeBudget and PerformanceLib.FrameTimeBudget.CanAfford then
        canAfford = PerformanceLib.FrameTimeBudget:CanAfford(data.priority, 0.5)
    end

    local now = GetTime()
    if not canAfford then
        data.deferCount = (data.deferCount or 0) + 1
        stats.budgetDefers = stats.budgetDefers + 1

        local maxDefers = MAX_BUDGET_DEFERS_BY_PRIORITY[data.priority] or 5
        local maxWindow = MAX_DEFER_WINDOW_BY_PRIORITY[data.priority] or 0.35
        local waitedTooLong = data.firstQueuedAt > 0 and (now - data.firstQueuedAt) >= maxWindow
        if data.priority ~= EventCoalescer.PRIORITY_CRITICAL and data.deferCount < maxDefers and not waitedTooLong then
            return false
        end
        if data.priority ~= EventCoalescer.PRIORITY_CRITICAL then
            stats.emergencyFlushes = stats.emergencyFlushes + 1
        end
    end

    local args = data.pendingArgs or {}
    for i = 1, #data.callbacks do
        local ok, err = pcall(data.callbacks[i], unpack(args))
        if not ok and PerformanceLib.DebugOutput and PerformanceLib.DebugOutput.Output then
            PerformanceLib.DebugOutput:Output("EventCoalescer", "Registered callback error: " .. tostring(err), 1)
        end
    end

    stats.totalDispatched = stats.totalDispatched + 1
    stats.perEvent[eventName].dispatched = stats.perEvent[eventName].dispatched + 1
    RecordBatch(eventName, data.coalesceCount)
    data.lastFire = now
    data.pendingArgs = nil
    data.coalesceCount = 0
    data.firstQueuedAt = 0
    data.deferCount = 0
    data.scheduled = false
    return true
end

function EventCoalescer:QueueEvent(eventName, priorityOrArg, ...)
    if not self._enabled then
        if type(priorityOrArg) == "number" then
            DispatchToBus(eventName, ...)
        else
            DispatchToBus(eventName, priorityOrArg, ...)
        end
        return true
    end

    local registered = registeredEvents[eventName]
    if registered then
        if type(priorityOrArg) == "number" then
            registered.pendingArgs = { ... }
        else
            registered.pendingArgs = { priorityOrArg, ... }
        end
        registered.coalesceCount = registered.coalesceCount + 1
        if registered.coalesceCount == 1 then
            registered.firstQueuedAt = GetTime()
            registered.deferCount = 0
        end

        EnsureEventStats(eventName)
        stats.totalCoalesced = stats.totalCoalesced + 1
        stats.perEvent[eventName].coalesced = stats.perEvent[eventName].coalesced + 1

        if registered.priority == EventCoalescer.PRIORITY_CRITICAL then
            stats.immediateCritical = stats.immediateCritical + 1
            self:_DispatchRegistered(eventName)
            return true
        end

        local since = GetTime() - (registered.lastFire or 0)
        if since >= registered.delay then
            self:_DispatchRegistered(eventName)
        elseif not registered.scheduled then
            registered.scheduled = true
            C_Timer.After(math.max(0, registered.delay - since), function()
                self:_DispatchRegistered(eventName)
            end)
        end
        return true
    end

    local priority = EventCoalescer.PRIORITY_MEDIUM
    local args
    if type(priorityOrArg) == "number" then
        priority = math.max(1, math.min(4, priorityOrArg))
        args = { ... }
    else
        args = { priorityOrArg, ... }
    end

    EnsureEventStats(eventName)

    if priority == EventCoalescer.PRIORITY_CRITICAL then
        DispatchToBus(eventName, unpack(args))
        stats.totalDispatched = stats.totalDispatched + 1
        stats.perEvent[eventName].dispatched = stats.perEvent[eventName].dispatched + 1
        RecordBatch(eventName, 1)
        return true
    end

    if not queuedEvents[eventName] then
        queuedEvents[eventName] = { priority = priority, args = {}, count = 0 }
    end
    table.insert(queuedEvents[eventName].args, args)
    queuedEvents[eventName].count = queuedEvents[eventName].count + 1
    stats.totalCoalesced = stats.totalCoalesced + 1
    stats.perEvent[eventName].coalesced = stats.perEvent[eventName].coalesced + 1
    return true
end

function EventCoalescer:ProcessQueue()
    local now = GetTime()

    for eventName, data in pairs(queuedEvents) do
        local lastTime = lastDispatchTime[eventName] or 0
        local interval = COALESCE_INTERVALS[data.priority] or 0.03
        if now - lastTime >= interval then
            for i = 1, #data.args do
                DispatchToBus(eventName, unpack(data.args[i]))
            end
            stats.totalDispatched = stats.totalDispatched + data.count
            stats.perEvent[eventName].dispatched = stats.perEvent[eventName].dispatched + data.count
            RecordBatch(eventName, data.count)
            queuedEvents[eventName] = nil
            lastDispatchTime[eventName] = now
        end
    end

    for eventName in pairs(registeredEvents) do
        self:_DispatchRegistered(eventName)
    end
end

function EventCoalescer:SetEnabled(enabled)
    self._enabled = enabled and true or false
end

function EventCoalescer:SetCoalesceInterval(priority, interval)
    if priority >= 1 and priority <= 4 then
        COALESCE_INTERVALS[priority] = math.max(0, tonumber(interval) or COALESCE_INTERVALS[priority])
    end
end

function EventCoalescer:DispatchEvent(eventName, ...)
    DispatchToBus(eventName, ...)
end

function EventCoalescer:Flush()
    for eventName, data in pairs(queuedEvents) do
        for i = 1, #data.args do
            DispatchToBus(eventName, unpack(data.args[i]))
        end
        stats.totalDispatched = stats.totalDispatched + data.count
        stats.perEvent[eventName].dispatched = stats.perEvent[eventName].dispatched + data.count
        RecordBatch(eventName, data.count)
        queuedEvents[eventName] = nil
    end

    for eventName in pairs(registeredEvents) do
        self:_DispatchRegistered(eventName)
    end
end

function EventCoalescer:GetStats()
    local queuedCount = 0
    for _ in pairs(queuedEvents) do
        queuedCount = queuedCount + 1
    end

    local batchSizes = {}
    for eventName, eventBatch in pairs(stats.batchSizes) do
        batchSizes[eventName] = {
            min = eventBatch.min == 999999 and 0 or eventBatch.min,
            max = eventBatch.max,
            avg = eventBatch.count > 0 and (eventBatch.total / eventBatch.count) or 0,
            count = eventBatch.count,
        }
    end

    local savingsPercent = 0
    if stats.totalCoalesced > 0 then
        local saved = stats.totalCoalesced - stats.totalDispatched
        savingsPercent = (saved / stats.totalCoalesced) * 100
    end

    return {
        totalCoalesced = stats.totalCoalesced,
        totalDispatched = stats.totalDispatched,
        totalRejected = stats.totalRejected,
        budgetDefers = stats.budgetDefers,
        emergencyFlushes = stats.emergencyFlushes,
        immediateCritical = stats.immediateCritical,
        queuedEvents = queuedCount,
        savingsPercent = savingsPercent,
        perEvent = stats.perEvent,
        rejectedCounts = stats.rejectedCounts,
        batchSizes = batchSizes,
    }
end

function EventCoalescer:ResetStats()
    stats.totalCoalesced = 0
    stats.totalDispatched = 0
    stats.totalRejected = 0
    stats.budgetDefers = 0
    stats.emergencyFlushes = 0
    stats.immediateCritical = 0
    stats.perEvent = {}
    stats.rejectedCounts = {}
    stats.batchSizes = {}
end

EventCoalescer:Initialize()

return EventCoalescer
