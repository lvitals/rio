-- rio/lib/rio/utils/env.lua
-- Utility for environment variables and .env file loading.

local M = {}

-- Loads .env file and returns a table with variables
function M.load(file_path)
    file_path = file_path or ".env"
    local env_vars = {}
    
    local f = io.open(file_path, "r")
    if not f then
        return env_vars -- Returns empty if file does not exist
    end

    for line in f:lines() do
        -- Remove whitespace
        line = line:match("^%s*(.-)%s*$")
        
        -- Ignore empty lines and comments
        if line ~= "" and not line:match("^#") then
            -- Parse KEY=VALUE
            local key, value = line:match("^([^=]+)=(.*)$")
            if key and value then
                -- Remove spaces from key
                key = key:match("^%s*(.-)%s*$")
                -- Remove quotes from value if they exist
                value = value:match('^"(.-)"$') or value:match("^'(.-)'$") or value
                env_vars[key] = value
            end
        end
    end
    f:close()
    return env_vars
end

-- Gets environment variable value (first from .env, then from system)
function M.get(key, default)
    -- Load .env on first call
    if not M._cache then
        M._cache = M.load()
    end

    -- Priority: .env > system > default
    local val = M._cache[key] or os.getenv(key) or default

    -- Auto-cast booleans
    if val == "true" then return true
    elseif val == "false" then return false
    end

    return val
end

-- Checks if the current environment matches the specified one
function M.is(env_name)
    local current = _G.RIO_ENV or os.getenv("RIO_ENV") or "development"
    return current == env_name
end

-- Clears cache (useful for tests)
function M.clear_cache()
    M._cache = nil
end

return M
