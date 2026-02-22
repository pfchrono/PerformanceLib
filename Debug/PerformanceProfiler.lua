-- =========================================================================
-- PERFORMANCE PROFILER - Timeline & Bottleneck Analysis
-- =========================================================================
-- Records gameplay timeline and detects performance bottlenecks.
-- Max 10000 events, P50/P95/P99 metrics, event breakdown.

local _, PerformanceLib = ...

if not PerformanceLib.PerformanceProfiler then
    PerformanceLib.PerformanceProfiler = {}
end

local Profiler = PerformanceLib.PerformanceProfiler

local MAX_EVENTS = 10000
local timeline = {}
local isRecording = false
local startTime = 0
local stats = {
    fpsMin = 0,
    fpsMax = 0,
    fpsAvg = 0,
    events = 0,
    eventBreakdown = {}
}

---Start recording profiling data
function Profiler:StartProfiling()
    isRecording = true
    timeline = {}
    startTime = GetTime()
    stats.events = 0
    stats.eventBreakdown = {}
    print("|cFF00FF00Performance profiling started|r")
end

---Stop recording
function Profiler:StopProfiling()
    isRecording = false
    print("|cFF00FF00Performance profiling stopped - recorded " .. #timeline .. " events|r")
end

---Record a profile event
---@param eventName string Event identifier
---@param duration number Duration in ms
function Profiler:RecordEvent(eventName, duration)
    if not isRecording or #timeline >= MAX_EVENTS then
        return
    end
    
    table.insert(timeline, {
        time = GetTime() - startTime,
        event = eventName,
        duration = duration
    })
    
    stats.events = stats.events + 1
    
    -- Track event breakdown
    if not stats.eventBreakdown[eventName] then
        stats.eventBreakdown[eventName] = {count = 0, totalTime = 0}
    end
    stats.eventBreakdown[eventName].count = stats.eventBreakdown[eventName].count + 1
    stats.eventBreakdown[eventName].totalTime = stats.eventBreakdown[eventName].totalTime + duration
end

---Analyze recorded profile data
---@return table Analysis results
function Profiler:Analyze()
    if #timeline == 0 then
        print("|cFFFF0000No profile data recorded|r")
        return {}
    end
    
    local durations = {}
    for _, event in ipairs(timeline) do
        table.insert(durations, event.duration)
    end
    table.sort(durations)
    
    local avg = 0
    for _, d in ipairs(durations) do
        avg = avg + d
    end
    avg = avg / #durations
    
    local P50 = durations[math.ceil(#durations * 0.50)]
    local P95 = durations[math.ceil(#durations * 0.95)]
    local P99 = durations[math.ceil(#durations * 0.99)]
    
    print("|cFF00FF00Profile Analysis:|r")
    print(("  Total Events: %d | Duration: %.1f sec"):format(#timeline, timeline[#timeline].time))
    print(("  Avg: %.2f ms | Min: %.2f ms | Max: %.2f ms"):format(avg, durations[1], durations[#durations]))
    print(("  P50: %.2f ms | P95: %.2f ms | P99: %.2f ms"):format(P50, P95, P99))
    print("|cFFFFFF00Top Events:|r")
    
    local sortedEvents = {}
    for event, data in pairs(stats.eventBreakdown) do
        table.insert(sortedEvents, {event = event, count = data.count, time = data.totalTime})
    end
    table.sort(sortedEvents, function(a, b) return a.time > b.time end)
    
    for i = 1, math.min(5, #sortedEvents) do
        local e = sortedEvents[i]
        print(("    %s: %d calls, %.2f ms total"):format(e.event, e.count, e.time))
    end
    
    return {
        totalEvents = #timeline,
        duration = timeline[#timeline] and timeline[#timeline].time or 0,
        avg = avg,
        P50 = P50,
        P95 = P95,
        P99 = P99,
        eventBreakdown = stats.eventBreakdown
    }
end

---Get timeline data
---@return table Timeline events
function Profiler:GetTimeline()
    return timeline
end

---Export timeline as string
---@return string Exported data
function Profiler:Export()
    local lines = {"Event,Time,Duration"}
    for _, event in ipairs(timeline) do
        table.insert(lines, ("%s,%.4f,%.4f"):format(event.event, event.time, event.duration))
    end
    return table.concat(lines, "\n")
end

---Get statistics
---@return table Stats
function Profiler:GetStats()
    return {
        isRecording = isRecording,
        eventCount = #timeline,
        maxEvents = MAX_EVENTS,
        eventBreakdown = stats.eventBreakdown
    }
end

return Profiler
