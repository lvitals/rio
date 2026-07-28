-- rio/lib/rio/testing/warning_registry.lua

local WarningRegistry = {}
WarningRegistry.__index = WarningRegistry

function WarningRegistry.new()
    return setmetatable({ order = {}, items = {} }, WarningRegistry)
end

function WarningRegistry:add(key, message, detail)
    key = tostring(key or message or "warning")
    local item = self.items[key]
    if item then
        item.count = item.count + 1
        return item
    end

    item = {
        key = key,
        message = tostring(message or key),
        detail = detail,
        count = 1
    }
    self.items[key] = item
    table.insert(self.order, key)
    return item
end

function WarningRegistry:all()
    local result = {}
    for _, key in ipairs(self.order) do
        table.insert(result, self.items[key])
    end
    return result
end

function WarningRegistry:count()
    return #self.order
end

return WarningRegistry
