-- =========================================================================
-- FRAME POOL MANAGER - Object Pooling for Frames
-- =========================================================================
-- Manages pools of reusable frames to reduce GC pressure.
-- Supports pooling common frame types (Button, Frame, Texture, etc).

local _, PerformanceLib = ...

if not PerformanceLib.FramePoolManager then
    PerformanceLib.FramePoolManager = {}
end

local FramePoolManager = PerformanceLib.FramePoolManager

-- Pool storage: pools["FrameType"]["poolID"] = {acquired, available}
local pools = {}
local stats = {
    acquired = 0,
    released = 0,
    created = 0,
    reused = 0
}

---Initialize FramePoolManager
function FramePoolManager:Initialize()
    if self._initialized then return end
    self._initialized = true
    
    self._acquiredFrames = {}
end

---Get or create a pool for a frame type
---@param frameType string Frame type (e.g., "Button", "Frame")
---@param poolID string Optional pool identifier
---@return table Pool data {acquired, available}
function FramePoolManager:_GetPool(frameType, poolID)
    poolID = poolID or frameType
    
    if not pools[frameType] then
        pools[frameType] = {}
    end
    
    if not pools[frameType][poolID] then
        pools[frameType][poolID] = {
            acquired = {},
            available = {},
            frameType = frameType
        }
    end
    
    return pools[frameType][poolID]
end

---Acquire a frame from the pool
---@param frameType string Frame type (e.g., "Button", "Frame")
---@param parent table Parent frame
---@param poolID string Optional pool identifier
---@return table Acquired frame
function FramePoolManager:Acquire(frameType, parent, poolID)
    poolID = poolID or frameType
    
    local pool = self:_GetPool(frameType, poolID)
    local frame
    
    -- Try to get from available pool
    if #pool.available > 0 then
        frame = table.remove(pool.available)
        frame:SetParent(parent)
        frame:Show()
        stats.reused = stats.reused + 1
    else
        -- Create new frame
        frame = CreateFrame(frameType, nil, parent)
        stats.created = stats.created + 1
    end
    
    table.insert(pool.acquired, frame)
    self._acquiredFrames[frame] = poolID
    stats.acquired = stats.acquired + 1
    
    return frame
end

---Release a frame back to the pool
---@param frame table Frame to release
function FramePoolManager:Release(frame)
    if not frame or not self._acquiredFrames[frame] then
        return  -- Not from our pool
    end
    
    local poolID = self._acquiredFrames[frame]
    local frameType = frame:GetObjectType()
    local pool = self:_GetPool(frameType, poolID)
    
    -- Remove from acquired
    for i = #pool.acquired, 1, -1 do
        if pool.acquired[i] == frame then
            table.remove(pool.acquired, i)
            break
        end
    end
    
    -- Reset and hide frame
    frame:ClearAllPoints()
    frame:SetParent(UIParent)
    frame:Hide()
    
    -- Return to available pool
    table.insert(pool.available, frame)
    self._acquiredFrames[frame] = nil
    stats.released = stats.released + 1
end

---Release all frames in a pool
---@param frameType string Frame type
---@param poolID string Optional pool identifier
function FramePoolManager:ReleaseAll(frameType, poolID)
    poolID = poolID or frameType
    
    local pool = self:_GetPool(frameType, poolID)
    
    for _, frame in ipairs(pool.acquired) do
        frame:Hide()
        frame:ClearAllPoints()
        table.insert(pool.available, frame)
        self._acquiredFrames[frame] = nil
    end
    
    pool.acquired = {}
end

---Get pool statistics
---@param frameType string Optional specific frame type
---@return table Stats
function FramePoolManager:GetStats(frameType)
    if frameType then
        local poolStats = {}
        if pools[frameType] then
            for poolID, pool in pairs(pools[frameType]) do
                poolStats[poolID] = {
                    acquired = #pool.acquired,
                    available = #pool.available,
                    total = #pool.acquired + #pool.available
                }
            end
        end
        return poolStats
    else
        return {
            totalCreated = stats.created,
            totalAcquired = stats.acquired,
            totalReused = stats.reused,
            totalReleased = stats.released,
            pools = pools
        }
    end
end

---Print pool statistics
function FramePoolManager:PrintStats()
    print("|cFF00FF00Frame Pool Manager Stats:|r")
    print(("  Created: %d | Reused: %d | Acquired: %d | Released: %d"):format(stats.created, stats.reused, stats.acquired, stats.released))
    print("  |cFFFFFF00Pool Breakdown:|r")
    for frameType, typePools in pairs(pools) do
        for poolID, pool in pairs(typePools) do
            print(("    %s (%s): %d acquired, %d available"):format(
                frameType, poolID, #pool.acquired, #pool.available
            ))
        end
    end
end

-- Auto-initialize
FramePoolManager:Initialize()

return FramePoolManager
