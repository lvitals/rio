-- rio/lib/rio/testing/warning_registry.lua

local WarningRegistry = {}
WarningRegistry.__index = WarningRegistry

function WarningRegistry.new()
    return setmetatable({ order = {}, items = {} }, WarningRegistry)
end

function WarningRegistry:add(key, message, detail)
    local spec
    if type(key) == "table" then
        spec = key
        key = spec.key
        message = spec.message
        detail = spec.detail
    end

    key = tostring(key or message or "warning")
    local item = self.items[key]
    if item then
        item.count = item.count + 1
        if not item.detail and detail then
            item.detail = detail
        end
        return item
    end

    item = {
        key = key,
        message = tostring(message or key),
        detail = detail,
        category = spec and spec.category or nil,
        subject = spec and spec.subject or nil,
        reason = spec and spec.reason or nil,
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
