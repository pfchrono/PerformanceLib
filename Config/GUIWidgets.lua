-- =========================================================================
-- GUI WIDGETS - Helper UI Components
-- =========================================================================
-- Utility functions for creating common GUI elements.
-- Addon authors can extend these for their own UI framework.

local _, PerformanceLib = ...

if not PerformanceLib.Config then
    PerformanceLib.Config = {}
end

local GUIWidgets = {}

---Create a labeled checkbox widget
---@return table Widget with SetValue/GetValue/SetCallback methods
function GUIWidgets:CreateCheckBox(parent, label)
    local widget = {label = label, value = false}
    
    function widget:SetValue(value)
        self.value = value
    end
    
    function widget:GetValue()
        return self.value
    end
    
    function widget:SetCallback(event, callback)
        self.callbacks = self.callbacks or {}
        self.callbacks[event] = callback
    end
    
    function widget:Trigger(event, ...)
        if self.callbacks and self.callbacks[event] then
            self.callbacks[event](...)
        end
    end
    
    return widget
end

---Create a slider widget
---@return table Widget with SetValue/GetValue methods
function GUIWidgets:CreateSlider(parent, label, minValue, maxValue, step)
    local widget = {
        label = label,
        value = (minValue + maxValue) / 2,
        min = minValue,
        max = maxValue,
        step = step or 1
    }
    
    function widget:SetValue(value)
        self.value = math.max(self.min, math.min(self.max, value))
    end
    
    function widget:GetValue()
        return self.value
    end
    
    function widget:SetCallback(event, callback)
        self.callbacks = self.callbacks or {}
        self.callbacks[event] = callback
    end
    
    function widget:Trigger(event, ...)
        if self.callbacks and self.callbacks[event] then
            self.callbacks[event](...)
        end
    end
    
    return widget
end

---Create a color picker widget
---@return table Widget
function GUIWidgets:CreateColorPicker(parent, label)
    local widget = {label = label, r = 1, g = 1, b = 1, a = 1}
    
    function widget:SetColor(r, g, b, a)
        self.r = r or 1
        self.g = g or 1
        self.b = b or 1
        self.a = a or 1
    end
    
    function widget:GetColor()
        return self.r, self.g, self.b, self.a
    end
    
    function widget:SetCallback(event, callback)
        self.callbacks = self.callbacks or {}
        self.callbacks[event] = callback
    end
    
    return widget
end

return GUIWidgets
