-- rio/lib/rio/cache/adapters/base.lua
-- Base class for cache adapters

local BaseAdapter = {}
BaseAdapter.__index = BaseAdapter

function BaseAdapter:new(options)
    return setmetatable({ options = options or {} }, self)
end

function BaseAdapter:get(key) error("Not implemented") end
function BaseAdapter:set(key, value, ttl) error("Not implemented") end
function BaseAdapter:delete(key) error("Not implemented") end
function BaseAdapter:clear() error("Not implemented") end
function BaseAdapter:exists(key) error("Not implemented") end

return BaseAdapter
