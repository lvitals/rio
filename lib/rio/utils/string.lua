-- rio/utils/string.lua
-- String manipulation and security utilities.

local M = {}

-- Escapes Lua patterns to avoid pattern injection
function M.escape_lua_pattern(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("%%", "%%%%")
             :gsub("%^", "%%^")
             :gsub("%$", "%%$")
             :gsub("%(", "%%(")
             :gsub("%)", "%%)")
             :gsub("%.", "%%.")
             :gsub("%[", "%%[")
             :gsub("%]", "%%]")
             :gsub("%*", "%%*")
             :gsub("%+", "%%+")
             :gsub("%-", "%%-")
             :gsub("%?", "%%?"))
end

-- Removes leading and trailing whitespace
function M.trim(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$")
end

-- Validates if string is safe (no dangerous control characters)
function M.is_safe(s)
    if type(s) ~= "string" then return false end
    -- Rejects control characters except \t, \r, \n
    -- Using %z instead of \0 for null byte in patterns.
    return not s:find("[%z-\8\11-\12\14-\31\127]")
end

-- Sanitizes string by removing dangerous characters
function M.sanitize(s)
    if type(s) ~= "string" then return "" end
    -- Using %z instead of \0 for null byte in patterns.
    return s:gsub("[%z-\8\11-\12\14-\31\127]", "")
end

-- Limits string size (DoS protection)
function M.limit(s, max_len)
    if type(s) ~= "string" then return "" end
    max_len = max_len or 8192
    if #s > max_len then
        return s:sub(1, max_len)
    end
    return s
end

-- Converts string to camelCase/PascalCase
function M.camel_case(s)
    if type(s) ~= "string" then return "" end
    s = s:gsub("_(%l)", string.upper)
    s = s:gsub("^(%l)", string.upper)
    return s
end

-- Converts string to snake_case
function M.underscore(s)
    if type(s) ~= "string" then return "" end
    s = s:gsub("([A-Z]+)([A-Z][a-z])", "%1_%2")
    s = s:gsub("([a-z%d])([A-Z])", "%1_%2")
    return s:lower()
end
M.snake_case = M.underscore

-- Simple English pluralization
function M.pluralize(s)
    if type(s) ~= "string" then return "" end
    -- If already ends in 's', assume plural (simple check)
    if s:sub(-1) == "s" then return s end
    
    if s:sub(-1) == "y" and not s:match("[aeiou]y$") then
        return s:sub(1, -2) .. "ies"
    elseif s:sub(-2) == "sh" or s:sub(-2) == "ch" or s:sub(-1) == "x" or s:sub(-1) == "z" then
        return s .. "es"
    else
        return s .. "s"
    end
end

-- Simple English singularization
function M.singularize(s)
    if type(s) ~= "string" then return "" end
    if s:sub(-3) == "ies" then
        return s:sub(1, -4) .. "y"
    elseif s:sub(-2) == "es" then
        return s:sub(1, -3)
    elseif s:sub(-1) == "s" then
        return s:sub(1, -2)
    end
    return s
end

-- Trunca uma string com reticências
function M.truncate(s, length)
    length = length or 30
    if #s > length then
        return s:sub(1, length - 3) .. "..."
    end
    return s
end

-- Inspect a table and return a string representation (pretty print)
function M.inspect(tbl, indent)
    if type(tbl) ~= "table" then return tostring(tbl) end
    indent = indent or 0
    local spacing = string.rep("  ", indent)
    local result = "{\n"
    
    for k, v in pairs(tbl) do
        local key = type(k) == "string" and ("[\"" .. k .. "\"]") or ("[" .. tostring(k) .. "]")
        local value = ""
        if type(v) == "table" then
            local mt = getmetatable(v)
            if mt and mt.__tostring then
                value = tostring(v)
            elseif indent < 5 then -- limit depth
                value = M.inspect(v, indent + 1)
            else
                value = "{ ... }"
            end
        elseif type(v) == "string" then
            value = "\"" .. v:gsub("\n", "\\n") .. "\""
        else
            value = tostring(v)
        end
        result = result .. spacing .. "  " .. key .. " = " .. value .. ",\n"
    end
    
    return result .. spacing .. "}"
end

-- Secure string comparison to prevent timing attacks
function M.constant_time_equals(a, b)
    local compat = require("lib.rio.utils.compat")
    local bor, bxor = compat.bor, compat.bxor
    if type(a) ~= "string" or type(b) ~= "string" then
        return false
    end
    if #a ~= #b then
        return false
    end
    local result = 0
    for i = 1, #a do
        result = bor(result, bxor(a:byte(i), b:byte(i)))
    end
    return result == 0
end

return M
