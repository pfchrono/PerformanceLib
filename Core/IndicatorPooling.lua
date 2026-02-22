-- =========================================================================
-- INDICATOR POOLING - Indicator Lifecycle Management
-- =========================================================================
-- Specialized pooling for temporary indicator frames (auras, debuffs, etc).
-- Manages creation, reuse, and cleanup of indicator visual elements.

local _, PerformanceLib = ...

if not PerformanceLib.IndicatorPooling then
    PerformanceLib.IndicatorPooling = {}
end

local IndicatorPooling = PerformanceLib.IndicatorPooling

-- Pool registry
local indicatorPools = {}
local stats = {
    poolsCreated = 0,
    indicatorsAcquired = 0,
    indicatorsReleased = 0
}

---Create a new indicator pool
---@param poolName string Unique pool identifier
---@param createFunction function(parent) -> frame that creates indicator frames
---@param resetFunction function(frame) that resets frame for reuse (optional)
---@return table Pool object
function IndicatorPooling:CreatePool(poolName, createFunction, resetFunction)
    if indicatorPools[poolName] then
        return indicatorPools[poolName]
    end
    
    local pool = {
        name = poolName,
        createFunc = createFunction,
        resetFunc = resetFunction,
        acquired = {},
        available = {},
        stats = {acquired = 0, released = 0, created = 0}
    }
    
    indicatorPools[poolName] = pool
    stats.poolsCreated = stats.poolsCreated + 1
    
    return pool
end

---Acquire an indicator from a pool
---@param poolName string Pool identifier
---@param parent table Parent frame
---@return table Acquired indicator frame
function IndicatorPooling:AcquireIndicator(poolName, parent)
    local pool = indicatorPools[poolName]
    if not pool then
        error("IndicatorPooling: Unknown pool " .. tostring(poolName))
    end
    
    local indicator
    
    -- Try to get from available
    if #pool.available > 0 then
        indicator = table.remove(pool.available)
        if pool.resetFunc then
            pool.resetFunc(indicator)
        end
        indicator:SetParent(parent)
        indicator:Show()
    else
        -- Create new
        indicator = pool.createFunc(parent)
        pool.stats.created = pool.stats.created + 1
    end
    
    table.insert(pool.acquired, indicator)
    pool.stats.acquired = pool.stats.acquired + 1
    stats.indicatorsAcquired = stats.indicatorsAcquired + 1
    
    return indicator
end

---Release an indicator back to its pool
---@param poolName string Pool identifier
---@param indicator table Indicator to release
function IndicatorPooling:ReleaseIndicator(poolName, indicator)
    local pool = indicatorPools[poolName]
    if not pool then return end
    
    -- Remove from acquired
    for i = #pool.acquired, 1, -1 do
        if pool.acquired[i] == indicator then
            table.remove(pool.acquired, i)
            break
        end
    end
    
    -- Reset state
    indicator:ClearAllPoints()
    indicator:Hide()
    
    -- Return to available
    table.insert(pool.available, indicator)
    pool.stats.released = pool.stats.released + 1
    stats.indicatorsReleased = stats.indicatorsReleased + 1
end

---Release all indicators from a specific pool
---@param poolName string Pool identifier
function IndicatorPooling:ReleaseAllFromPool(poolName)
    local pool = indicatorPools[poolName]
    if not pool then return end
    
    for _, indicator in ipairs(pool.acquired) do
        indicator:Hide()
        indicator:ClearAllPoints()
        table.insert(pool.available, indicator)
    end
    
    pool.acquired = {}
end

---Release all indicators from all pools
function IndicatorPooling:ReleaseAll()
    for poolName, pool in pairs(indicatorPools) do
        self:ReleaseAllFromPool(poolName)
    end
end

---Get pool statistics
---@param poolName string Optional specific pool
---@return table Stats
function IndicatorPooling:GetStats(poolName)
    if poolName then
        local pool = indicatorPools[poolName]
        if pool then
            return pool.stats
        end
        return {}
    else
        local allStats = {
            totalPoolsCreated = stats.poolsCreated,
            totalIndicatorsAcquired = stats.indicatorsAcquired,
            totalIndicatorsReleased = stats.indicatorsReleased,
            poolBreakdown = {}
        }
        
        for name, pool in pairs(indicatorPools) do
            allStats.poolBreakdown[name] = {
                acquired = #pool.acquired,
                available = #pool.available,
                stats = pool.stats
            }
        end
        
        return allStats
    end
end

---Print pool statistics
function IndicatorPooling:PrintStats()
    print("|cFF00FF00Indicator Pooling Stats:|r")
    print(("  Pools Created: %d | Acquired: %d | Released: %d"):format(
        stats.poolsCreated, stats.indicatorsAcquired, stats.indicatorsReleased
    ))
    print("  |cFFFFFF00Pool Breakdown:|r")
    for poolName, pool in pairs(indicatorPools) do
        print(("    %s: %d acquired, %d available (created: %d)"):format(
            poolName, #pool.acquired, #pool.available, pool.stats.created
        ))
    end
end

return IndicatorPooling
