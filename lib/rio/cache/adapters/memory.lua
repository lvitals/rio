-- rio/lib/rio/cache/adapters/memory.lua
-- In-memory cache storage (RAM)

local Base = require("rio.cache.adapters.base")
local MemoryAdapter = setmetatable({}, Base)
MemoryAdapter.__index = MemoryAdapter

function MemoryAdapter:new(options)
    local obj = Base:new(options)
    obj.data = {}
    return setmetatable(obj, self)
end

function MemoryAdapter:set(key, value, ttl)
    self.data[key] = {
        value = value,
        expires_at = ttl and (os.time() + ttl) or nil
    }
    return true
end

function MemoryAdapter:get(key)
    local item = self.data[key]
    if not item then return nil end

    if item.expires_at and os.time() > item.expires_at then
        self.data[key] = nil
        return nil
    end

    return item.value
end

function MemoryAdapter:delete(key)
    self.data[key] = nil
end

function MemoryAdapter:clear()
    self.data = {}
end

function MemoryAdapter:exists(key)
    return self.data[key] ~= nil
end

return MemoryAdapter
