-- rio/utils/headers.lua
-- Utilities for handling HTTP headers.

local string_utils = require("rio.utils.string")
local trim = string_utils.trim

local M = {}

-- Extracts a Bearer token from an Authorization header.
function M.get_bearer(headers)
    if type(headers) ~= "table" then return nil end
    
    local auth = headers["authorization"]
    if not auth or auth == "" then return nil end
    
    local scheme, token = auth:match("^(%S+)%s+(.+)$")
    if not scheme or scheme:lower() ~= "bearer" then
        return nil
    end
    
    return trim(token)
end

-- Validates that a header value is safe to send (prevents header injection).
function M.is_safe_value(value)
    if type(value) ~= "string" then return false end
    -- Rejects CRLF and null bytes, which can be used in header injection attacks.
    return not value:find("[\r\n\0]")
end

return M
