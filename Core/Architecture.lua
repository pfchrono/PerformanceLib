-- =========================================================================
-- ARCHITECTURE - Base Utilities & Patterns
-- =========================================================================
-- Provides foundational utilities for the library:
--  - Event bus (global event dispatcher)
--  - Safe value handling (WoW 12.0.0 secret values)
--  - Table utilities
--  - Configuration patterns

local _, PerformanceLib = ...

if not PerformanceLib.Architecture then
    PerformanceLib.Architecture = {}
end

local Arch = PerformanceLib.Architecture

-- =========================================================================
-- EVENT BUS (Singleton Event Dispatcher)
-- =========================================================================

if not Arch.EventBus then
    Arch.EventBus = {
        _handlers = {},
        _aliases = {}
    }
end

local EventBus = Arch.EventBus

---Register a handler for an event
---@param event string Event name
---@param handler function Callback function
---@param context any Optional context (used as 'self')
function EventBus:Register(event, handler, context)
    if not self._handlers[event] then
        self._handlers[event] = {}
    end
    
    table.insert(self._handlers[event], {
        handler = handler,
        context = context
    })
end

---Unregister a handler
---@param event string Event name
---@param handler function Handler to remove
function EventBus:Unregister(event, handler)
    if not self._handlers[event] then return end
    
    for i = #self._handlers[event], 1, -1 do
        if self._handlers[event][i].handler == handler then
            table.remove(self._handlers[event], i)
        end
    end
end

---Dispatch an event to all registered handlers
---@param event string Event name
---@param ... any Arguments to pass to handlers
function EventBus:Dispatch(event, ...)
    if not self._handlers[event] then return end

    for _, entry in ipairs(self._handlers[event]) do
        local ok, err
        if entry.context then
            ok, err = pcall(entry.handler, entry.context, ...)
        else
            ok, err = pcall(entry.handler, ...)
        end

        if not ok then
            local ctx = entry.context and tostring(entry.context) or "nil"
            local msg = "EventBus error [" .. tostring(event) .. "] ctx=" .. ctx .. ": " .. tostring(err)
            if PerformanceLib and PerformanceLib.DebugOutput then
                PerformanceLib.DebugOutput:Output("EventBus", msg, 1)
            else
                print(msg)
            end
        end
    end
end

-- =========================================================================
-- SAFE VALUE HANDLING (WoW 12.0.0+)
-- =========================================================================

local IsSecretValue = issecretvalue or function() return false end
local GetCurveValueAtTime = C_CurveUtil and C_CurveUtil.GetCurveValueAtTime or function() return 0 end

---Check if a value is secret (WoW 12.0.0+)
---@param value any Value to check
---@return boolean True if value is secret
function Arch.IsSecretValue(value)
    return IsSecretValue(value)
end

---Safely handle secret values, providing visualization curves
---@param secretValue any The secret value
---@param fallback number|string Fallback if unable to visualize
---@return number|string Safe visualization value
function Arch.SafeValue(secretValue, fallback)
    if not IsSecretValue(secretValue) then
        return secretValue
    end
    
    -- Use curve-based visualization for secret values
    local curveID = 1
    local progress = (GetTime() % 1.0)
    local visualValue = GetCurveValueAtTime(curveID, progress)
    
    return visualValue or fallback or 0
end

---Compare two values safely (handles secret values)
---@param value1 any First value
---@param value2 any Second value
---@return boolean True if equal or both secret
function Arch.SafeCompare(value1, value2)
    local v1Secret = IsSecretValue(value1)
    local v2Secret = IsSecretValue(value2)
    
    if v1Secret or v2Secret then
        return v1Secret == v2Secret
    end
    
    return value1 == value2
end

-- =========================================================================
-- TABLE UTILITIES
-- =========================================================================

---Deep copy a table
---@param tbl table Table to copy
---@param depth integer Maximum recursion depth (default: 10)
---@return table Copy of table
function Arch.DeepCopy(tbl, depth)
    if type(tbl) ~= "table" then return tbl end
    
    depth = depth or 10
    if depth <= 0 then return {} end
    
    local result = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            result[k] = Arch.DeepCopy(v, depth - 1)
        else
            result[k] = v
        end
    end
    
    return result
end

---Merge two tables (source into dest, source takes precedence)
---@param dest table Destination table
---@param source table Source table
---@return table Merged table
function Arch.MergeTables(dest, source)
    if type(source) ~= "table" then return dest end
    
    for k, v in pairs(source) do
        if type(v) == "table" and type(dest[k]) == "table" then
            Arch.MergeTables(dest[k], v)
        else
            dest[k] = v
        end
    end
    
    return dest
end

---Filter a table by predicate
---@param tbl table Table to filter
---@param predicate function(key, value) -> boolean
---@return table Filtered table
function Arch.FilterTable(tbl, predicate)
    local result = {}
    for k, v in pairs(tbl) do
        if predicate(k, v) then
            result[k] = v
        end
    end
    return result
end

---Get table size (key count)
---@param tbl table Table to measure
---@return integer Number of keys
function Arch.TableSize(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- =========================================================================
-- FRAME STATE & DIRTY FLAGS
-- =========================================================================

---Create a frame state object for tracking changes
---@param frameType string Frame type (e.g., "Button", "Frame")
---@return table State object with dirty flag tracking
function Arch.CreateFrameState()
    return {
        isDirty = false,
        stamp = {},
        priority = 3,
        lastUpdate = GetTime()
    }
end

---Check if value changed and update stamp
---@param state table State object
---@param key string Property key
---@param value any New value
---@return boolean True if changed
function Arch.StampChanged(state, key, value)
    if state.stamp[key] ~= value then
        state.stamp[key] = value
        return true
    end
    return false
end

-- =========================================================================
-- CONFIGURATION PATTERNS
-- =========================================================================

---Resolve configuration with fallback chain
---@param chain table|nil Config chain: {profile, unit, global}
---@param key string Key to resolve
---@param default any Default value
---@return any Resolved value
function Arch.ResolveConfig(chain, key, default)
    if not chain then return default end
    
    if type(chain) == "table" then
        -- Try each in order: profile -> unit -> global
        for _, cfg in ipairs(chain) do
            if cfg and cfg[key] ~= nil then
                return cfg[key]
            end
        end
    end
    
    return default
end

-- =========================================================================
-- MODULE EXPORT
-- =========================================================================

return Arch

