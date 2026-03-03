-- rio/lib/rio/cache.lua
-- Unified cache interface for Rio Framework

local Cache = {}
Cache.__index = Cache

function Cache.new(adapter_name, options)
    adapter_name = adapter_name or "file"
    local ok, Adapter = pcall(require, "rio.cache.adapters." .. adapter_name)
    if not ok then
        error("Could not load cache adapter: " .. adapter_name .. " (" .. tostring(Adapter) .. ")")
    end

    return setmetatable({
        adapter = Adapter:new(options)
    }, Cache)
end

-- Tries to get from cache, if missing executes callback and stores result
function Cache:fetch(key, ttl, callback)
    local value = self:get(key)
    if value ~= nil then return value end

    if type(ttl) == "function" and callback == nil then
        callback = ttl
        ttl = nil
    end

    value = callback()
    if value ~= nil then
        self:set(key, value, ttl)
    end
    return value
end

function Cache:get(key) return self.adapter:get(key) end
function Cache:set(key, value, ttl) return self.adapter:set(key, value, ttl) end
function Cache:delete(key) return self.adapter:delete(key) end
function Cache:clear() return self.adapter:clear() end
function Cache:exists(key) return self.adapter:exists(key) end

return Cache
