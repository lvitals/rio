-- rio/lib/rio/cache/adapters/null.lua
-- Null cache storage (does nothing)

local Base = require("rio.cache.adapters.base")
local NullAdapter = setmetatable({}, Base)
NullAdapter.__index = NullAdapter

function NullAdapter:new(options)
    return setmetatable(Base:new(options), self)
end

function NullAdapter:set(key, value, ttl) return true end
function NullAdapter:get(key) return nil end
function NullAdapter:delete(key) end
function NullAdapter:clear() end
function NullAdapter:exists(key) return false end

return NullAdapter
