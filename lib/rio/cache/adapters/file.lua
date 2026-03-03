-- rio/lib/rio/cache/adapters/file.lua
-- File-based cache storage

local Base = require("rio.cache.adapters.base")
local string_utils = require("rio.utils.string")
local FileAdapter = setmetatable({}, Base)
FileAdapter.__index = FileAdapter

function FileAdapter:new(options)
    local obj = Base:new(options)
    obj.cache_dir = options.dir or "tmp/cache"
    os.execute("mkdir -p " .. obj.cache_dir)
    return setmetatable(obj, self)
end

local function get_file_path(self, key)
    -- Sanitize key to be a safe filename
    local safe_key = key:gsub("[^%w%-_]", "_")
    return self.cache_dir .. "/" .. safe_key .. ".cache"
end

function FileAdapter:set(key, value, ttl)
    local path = get_file_path(self, key)
    local file = io.open(path, "w")
    if file then
        local data = {
            value = value,
            expires_at = ttl and (os.time() + ttl) or nil
        }
        -- Use inspect to serialize (simple way for Lua tables)
        -- In a real scenario, we might use a more robust serializer
        file:write("return " .. string_utils.inspect(data))
        file:close()
        return true
    end
    return false
end

function FileAdapter:get(key)
    local path = get_file_path(self, key)
    local f = io.open(path, "r")
    if not f then return nil end
    f:close()

    local ok, data = pcall(dofile, path)
    if not ok or type(data) ~= "table" then return nil end

    -- Check expiration
    if data.expires_at and os.time() > data.expires_at then
        self:delete(key)
        return nil
    end

    return data.value
end

function FileAdapter:delete(key)
    local path = get_file_path(self, key)
    os.remove(path)
end

function FileAdapter:clear()
    os.execute("rm -f " .. self.cache_dir .. "/*.cache")
end

function FileAdapter:exists(key)
    local path = get_file_path(self, key)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

return FileAdapter
