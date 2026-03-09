-- rio/lib/rio/utils/headers.lua
-- Utilities for handling HTTP headers.

local string_utils = require("rio.utils.string")
local trim = string_utils.trim

local M = {}

-- Extracts a Bearer token from an Authorization header.
function M.get_bearer(headers)
    local auth = headers["authorization"]
    if not auth then return nil end
    return auth:match("^Bearer%s+(.+)$")
end

-- Validates that a header value is safe to send (prevents header injection).
function M.is_safe_value(value)
    if type(value) ~= "string" then return false end
    -- Rejects CRLF and null bytes, which can be used in header injection attacks.
    return not value:find("[\r\n\0]")
end

-- Sets standard security headers on a headers object.
-- @param headers The headers object to modify
-- @param config Optional configuration table (usually app.config.security)
function M.set_security_headers(headers, config)
    if not headers or type(headers) ~= "table" then return end
    config = config or {}
    
    -- IMPORTANT: Header names MUST be lowercase for HTTP/2 (lua-http)
    headers:upsert("x-content-type-options", "nosniff")
    headers:upsert("x-frame-options", config.frame_options or "SAMEORIGIN")
    headers:upsert("x-xss-protection", "1; mode=block")
    headers:upsert("referrer-policy", config.referrer_policy or "strict-origin-when-cross-origin")
    
    local csp = config.csp or "default-src 'self' 'unsafe-inline'; img-src * data: http: https:; frame-src *; frame-ancestors 'self'"
    headers:upsert("content-security-policy", csp)

    -- Custom Headers from configuration
    if config.headers and type(config.headers) == "table" then
        for k, v in pairs(config.headers) do
            headers:upsert(k:lower(), tostring(v))
        end
    end
end

return M
