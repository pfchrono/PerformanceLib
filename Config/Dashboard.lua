-- =========================================================================
-- PERFORMANCE DASHBOARD - Real-Time Performance Monitoring UI
-- =========================================================================

local _, PerformanceLib = ...

if not PerformanceLib.Dashboard then
    PerformanceLib.Dashboard = {}
end

local Dashboard = PerformanceLib.Dashboard

local dashboardFrame
local updateTicker
local isVisible = false
local updateInterval = 1.0
local fpsSamples = {}
local maxSamples = 5

local function GetSmoothedFPS()
    local fps = GetFramerate()
    table.insert(fpsSamples, fps)
    while #fpsSamples > maxSamples do
        table.remove(fpsSamples, 1)
    end

    local total = 0
    for i = 1, #fpsSamples do
        total = total + fpsSamples[i]
    end
    return (#fpsSamples > 0) and (total / #fpsSamples) or fps
end

local function BuildFrame()
    if dashboardFrame then
        return dashboardFrame
    end

    local frame = CreateFrame("Frame", "PerformanceLibDashboard", UIParent, "BackdropTemplate")
    frame:SetSize(330, 430)
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -220)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -15)
    title:SetText("|cFF00B0F7PerformanceLib|r")
    frame.title = title

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function()
        Dashboard:Hide()
    end)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -40)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 15)

    local textFrame = CreateFrame("Frame", nil, scroll)
    textFrame:SetSize(275, 1)
    local text = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", textFrame, "TOPLEFT", 0, 0)
    text:SetWidth(275)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetText("Initializing...")
    scroll:SetScrollChild(textFrame)

    frame.scroll = scroll
    frame.text = text
    frame.textFrame = textFrame
    frame:Hide()

    dashboardFrame = frame
    return frame
end

local function FormatNumber(num)
    if num >= 1000000 then
        return ("%.2fM"):format(num / 1000000)
    elseif num >= 1000 then
        return ("%.2fK"):format(num / 1000)
    end
    return ("%.0f"):format(num)
end

function Dashboard:Update()
    if not dashboardFrame or not dashboardFrame:IsShown() then
        return
    end

    local fps = GetSmoothedFPS()
    local frameStats = PerformanceLib.GetFrameTimeStats and PerformanceLib:GetFrameTimeStats() or {}
    local eventStats = PerformanceLib.EventCoalescer and PerformanceLib.EventCoalescer.GetStats and PerformanceLib.EventCoalescer:GetStats() or {}
    local dirtyStats = PerformanceLib.DirtyFlagManager and PerformanceLib.DirtyFlagManager.GetStats and PerformanceLib.DirtyFlagManager:GetStats() or {}
    local poolStats = PerformanceLib.FramePoolManager and PerformanceLib.FramePoolManager.GetStats and PerformanceLib.FramePoolManager:GetStats() or {}

    local lines = {}
    lines[#lines + 1] = "|cFFFFD700=== Performance ===|r"
    lines[#lines + 1] = ("FPS: |cFF00FF00%.1f|r"):format(fps)
    lines[#lines + 1] = ("Frame Avg: |cFF00FF00%.2fms|r"):format(frameStats.avg or 0)
    lines[#lines + 1] = ("P95 / P99: |cFF00FF00%.2f / %.2f|r"):format(frameStats.P95 or 0, frameStats.P99 or 0)
    lines[#lines + 1] = ("Memory: |cFF00FF00%.2f MB|r"):format((collectgarbage("count") or 0) / 1024)
    lines[#lines + 1] = ""

    lines[#lines + 1] = "|cFFFFD700=== Event Coalescing ===|r"
    lines[#lines + 1] = ("Coalesced: |cFF00FF00%s|r"):format(FormatNumber(eventStats.totalCoalesced or 0))
    lines[#lines + 1] = ("Dispatched: |cFFFFFF00%s|r"):format(FormatNumber(eventStats.totalDispatched or 0))
    lines[#lines + 1] = ("Queued: |cFFAAAAAA%d|r"):format(eventStats.queuedEvents or 0)
    lines[#lines + 1] = ("Rejected: |cFFFF8800%s|r"):format(FormatNumber(eventStats.totalRejected or 0))
    lines[#lines + 1] = ("Savings: |cFF00FF00%.1f%%|r"):format(eventStats.savingsPercent or 0)
    lines[#lines + 1] = ""

    lines[#lines + 1] = "|cFFFFD700=== Dirty Flags ===|r"
    lines[#lines + 1] = ("Processed: |cFF00FF00%s|r"):format(FormatNumber(dirtyStats.framesProcessed or 0))
    lines[#lines + 1] = ("Batches: |cFFFFFF00%s|r"):format(FormatNumber(dirtyStats.batchesRun or 0))
    lines[#lines + 1] = ("Queued: |cFFAAAAAA%d|r"):format(dirtyStats.currentDirtyCount or 0)
    lines[#lines + 1] = ("Invalid: |cFFFF8800%s|r"):format(FormatNumber(dirtyStats.invalidFramesSkipped or 0))
    lines[#lines + 1] = ""

    lines[#lines + 1] = "|cFFFFD700=== Pools ===|r"
    lines[#lines + 1] = ("Created: |cFF00FF00%s|r"):format(FormatNumber(poolStats.totalCreated or 0))
    lines[#lines + 1] = ("Reused: |cFFFFFF00%s|r"):format(FormatNumber(poolStats.totalReused or 0))
    lines[#lines + 1] = ("Released: |cFFAAAAAA%s|r"):format(FormatNumber(poolStats.totalReleased or 0))
    lines[#lines + 1] = ""

    lines[#lines + 1] = "|cFFFFD700=== Systems ===|r"
    lines[#lines + 1] = ("EventBus: %s"):format(PerformanceLib.Architecture and PerformanceLib.Architecture.EventBus and "|cFF00FF00Active|r" or "|cFFFF0000Inactive|r")
    lines[#lines + 1] = ("EventCoalescer: %s"):format(PerformanceLib.EventCoalescer and "|cFF00FF00Active|r" or "|cFFFF0000Inactive|r")
    lines[#lines + 1] = ("DirtyFlagManager: %s"):format(PerformanceLib.DirtyFlagManager and "|cFF00FF00Active|r" or "|cFFFF0000Inactive|r")
    lines[#lines + 1] = ("FramePoolManager: %s"):format(PerformanceLib.FramePoolManager and "|cFF00FF00Active|r" or "|cFFFF0000Inactive|r")
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cFFAAAAAA(Drag to move)|r"

    dashboardFrame.text:SetText(table.concat(lines, "\n"))
    local textHeight = dashboardFrame.text:GetStringHeight()
    dashboardFrame.textFrame:SetHeight(math.max(textHeight + 10, 1))
end

function Dashboard:Show()
    local frame = BuildFrame()
    frame:Show()
    isVisible = true
    self:Update()

    if updateTicker then
        updateTicker:Cancel()
    end
    updateTicker = C_Timer.NewTicker(updateInterval, function()
        Dashboard:Update()
    end)
end

function Dashboard:Hide()
    if dashboardFrame then
        dashboardFrame:Hide()
    end
    isVisible = false
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end
end

function Dashboard:Toggle()
    if isVisible then
        self:Hide()
    else
        self:Show()
    end
end

function Dashboard:IsVisible()
    return isVisible
end

function Dashboard:SetUpdateInterval(interval)
    updateInterval = math.max(0.1, tonumber(interval) or 1.0)
    if isVisible then
        self:Show()
    end
end

function Dashboard:Initialize()
    if self._initialized then
        return
    end
    self._initialized = true
    BuildFrame()
end

return Dashboard
