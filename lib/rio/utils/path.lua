-- rio/utils/path.lua
-- Utilities for handling HTTP URL paths.

local string_utils = require("rio.utils.string")
local escape_lua_pattern = string_utils.escape_lua_pattern

local M = {}

-- Joins two paths safely
function M.join(a, b)
    a = a or ""
    b = b or ""
    
    -- Normalize a
    if a ~= "" and a:sub(-1) == "/" then
        a = a:sub(1, -2)
    end
    
    -- Normalize b
    if b ~= "" and b:sub(1, 1) ~= "/" then
        b = "/" .. b
    end
    
    -- Return result
    if a == "" then
        return (b == "" and "/" or b)
    end
    return a .. (b == "" and "" or b)
end

-- Compiles path template "/user/{id}" into Lua pattern and list of parameter names
-- Returns: pattern, names
function M.compile(template)
    if type(template) ~= "string" or template == "" then
        return "^/$", {}
    end
    
    if template == "/" then
        return "^/$", {}
    end

    local names, parts, segments = {}, {}, {}

    -- Collect segments without leading slash
    for seg in template:gsub("^/", ""):gmatch("[^/]+") do
        table.insert(segments, seg)
    end

    for i, seg in ipairs(segments) do
        -- Supports both {id} and :id
        local name = seg:match("^%{%s*([_%w]+)%s*%}$") or seg:match("^:([_%w]+)$")
        local is_last = (i == #segments)

        if name then
            table.insert(names, name)
            -- All params are mandatory for now
            table.insert(parts, "/([^/]+)")
        else
            -- Literal (escapes pattern metacharacters)
            table.insert(parts, "/" .. escape_lua_pattern(seg))
        end
    end

    local pat = "^" .. (#parts > 0 and table.concat(parts) or "/") .. "$"
    return pat, names
end

-- Validates if the path is safe (no path traversal)
function M.is_safe(path)
    if type(path) ~= "string" then return false end
    -- Rejects path traversal attempts
    if path:find("..", 1, true) then return false end
    -- Rejects null bytes manually for full compatibility (Lua 5.1+)
    local i = 1
    while true do
        local b = path:byte(i)
        if not b then break end
        if b == 0 then return false end
        i = i + 1
    end
    return true
end

-- Normalizes path by removing duplicate slashes
function M.normalize(path)
    if type(path) ~= "string" then return "/" end
    -- Remove duplicate slashes
    path = path:gsub("/+", "/")
    -- Ensures it starts with /
    if path:sub(1, 1) ~= "/" then
        path = "/" .. path
    end
    -- Remove trailing slash (unless it's just root)
    if path ~= "/" and path:sub(-1) == "/" then
        path = path:sub(1, -2)
    end
    return path
end

return M
