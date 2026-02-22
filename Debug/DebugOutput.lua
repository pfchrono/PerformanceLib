-- =========================================================================
-- DEBUG OUTPUT - Non-Intrusive Debug Message Router
-- =========================================================================
-- 3-tier debug message system with system-specific filtering and export.
-- TIER 1 (CRITICAL): Always shown in chat + panel
-- TIER 2 (INFO): Panel only (optional)
-- TIER 3 (DEBUG): System-specific only

local _, PerformanceLib = ...

if not PerformanceLib.DebugOutput then
    PerformanceLib.DebugOutput = {}
end

local DebugOutput = PerformanceLib.DebugOutput

DebugOutput.TIER_CRITICAL = 1
DebugOutput.TIER_INFO = 2
DebugOutput.TIER_DEBUG = 3

local messages = {}
local systemFilters = {}
local panel
local panelText
local panelVisible = false
local panelUpdateElapsed = 0

local function BuildPanel()
    if panel then
        return panel
    end

    panel = CreateFrame("Frame", "PerformanceLibDebugPanel", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(520, 340)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    panel:SetFrameStrata("DIALOG")
    panel.TitleText:SetText("PerformanceLib Dashboard")

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function()
        panel:Hide()
        panelVisible = false
    end)

    panelText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panelText:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -32)
    panelText:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 12)
    panelText:SetJustifyH("LEFT")
    panelText:SetJustifyV("TOP")

    panel:Hide()
    return panel
end

local function RefreshPanelText()
    if not panelText then
        return
    end

    local lines = {}
    local frameStats = PerformanceLib.GetFrameTimeStats and PerformanceLib:GetFrameTimeStats() or {}
    local eventStats = PerformanceLib.EventCoalescer and PerformanceLib.EventCoalescer.GetStats and PerformanceLib.EventCoalescer:GetStats() or {}
    local dirtyStats = PerformanceLib.DirtyFlagManager and PerformanceLib.DirtyFlagManager.GetStats and PerformanceLib.DirtyFlagManager:GetStats() or {}
    local poolStats = PerformanceLib.FramePoolManager and PerformanceLib.FramePoolManager.GetStats and PerformanceLib.FramePoolManager:GetStats() or {}

    lines[#lines + 1] = "Performance Summary"
    lines[#lines + 1] = ("Frame: avg %.2f ms | P95 %.2f | P99 %.2f"):format(frameStats.avg or 0, frameStats.P95 or 0, frameStats.P99 or 0)
    lines[#lines + 1] = ("Events: coalesced %d | dispatched %d | queued %d"):format(eventStats.totalCoalesced or 0, eventStats.totalDispatched or 0, eventStats.queuedEvents or 0)
    lines[#lines + 1] = ("Dirty: processed %d | batches %d | queued %d"):format(dirtyStats.framesProcessed or 0, dirtyStats.batchesRun or 0, dirtyStats.currentDirtyCount or 0)
    lines[#lines + 1] = ("Pools: created %d | reused %d | released %d"):format(poolStats.totalCreated or 0, poolStats.totalReused or 0, poolStats.totalReleased or 0)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Recent messages:"
    local startIndex = math.max(1, #messages - 20)
    for i = startIndex, #messages do
        local msg = messages[i]
        lines[#lines + 1] = ("[%s] %s: %s"):format(msg.timestamp, msg.system, msg.message)
    end

    if #messages == 0 then
        lines[#lines + 1] = "No messages yet."
    end

    panelText:SetText(table.concat(lines, "\n"))
end

---Output a debug message
---@param system string System name (e.g., "EventCoalescer")
---@param message string Message text
---@param tier integer Tier (1=CRITICAL, 2=INFO, 3=DEBUG)
function DebugOutput:Output(system, message, tier)
    tier = tier or DebugOutput.TIER_INFO
    
    -- Check system filter
    if tier == DebugOutput.TIER_DEBUG then
        if not systemFilters[system] then
            return  -- System not enabled for debug
        end
    end
    
    local timestamp = ("%.2f"):format(GetTime())
    local entry = {
        timestamp = timestamp,
        system = system,
        message = message,
        tier = tier
    }
    
    table.insert(messages, entry)
    
    -- Output to chat if CRITICAL
    if tier == DebugOutput.TIER_CRITICAL then
        print(("[%s] %s: %s"):format(timestamp, system, message))
    end
    
    -- Limited history (last 100 messages)
    if #messages > 100 then
        table.remove(messages, 1)
    end

    if panelVisible then
        RefreshPanelText()
    end
end

---Enable debug output for a system
---@param system string System name
function DebugOutput:EnableSystem(system)
    systemFilters[system] = true
end

---Disable debug output for a system
---@param system string System name
function DebugOutput:DisableSystem(system)
    systemFilters[system] = nil
end

---Get all debug messages
---@param systemFilter string Optional system to filter by
---@return table Messages
function DebugOutput:GetMessages(systemFilter)
    if not systemFilter then
        return messages
    end
    
    local filtered = {}
    for _, msg in ipairs(messages) do
        if msg.system == systemFilter then
            table.insert(filtered, msg)
        end
    end
    return filtered
end

---Clear all messages
function DebugOutput:Clear()
    messages = {}
end

---Export messages as JSON-like string
---@return string Exported data
function DebugOutput:Export()
    local lines = {}
    for _, msg in ipairs(messages) do
        table.insert(lines, ("[%s] %s: %s"):format(msg.timestamp, msg.system, msg.message))
    end
    return table.concat(lines, "\n")
end

---Show message panel (stub for UI)
function DebugOutput:ShowPanel()
    local widget = BuildPanel()
    widget:SetScript("OnUpdate", function(_, elapsed)
        if not panelVisible then
            return
        end
        panelUpdateElapsed = panelUpdateElapsed + elapsed
        if panelUpdateElapsed >= 0.5 then
            panelUpdateElapsed = 0
            RefreshPanelText()
        end
    end)
    widget:Show()
    panelVisible = true
    panelUpdateElapsed = 0
    RefreshPanelText()
end

---Toggle panel visibility
function DebugOutput:TogglePanel()
    if panelVisible then
        if panel then
            panel:Hide()
            panel:SetScript("OnUpdate", nil)
        end
        panelVisible = false
    else
        self:ShowPanel()
    end
end

return DebugOutput
