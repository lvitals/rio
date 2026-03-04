-- rio/utils/headers.lua
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
    
    -- Prevent browsers from sniffing MIME types away from the declared content-type.
    headers:upsert("X-Content-Type-Options", "nosniff")
    
    -- Prevent page from being embedded in frames/iframes on other sites.
    headers:upsert("X-Frame-Options", config.frame_options or "SAMEORIGIN")
    
    -- Enable browser XSS filtering (legacy, but still useful).
    headers:upsert("X-XSS-Protection", "1; mode=block")
    
    -- Control how much referrer information is sent with requests.
    headers:upsert("Referrer-Policy", config.referrer_policy or "strict-origin-when-cross-origin")
    
    -- Content Security Policy (CSP)
    -- Default is very strict, but can be extended via config.csp
    local csp = config.csp or "default-src 'self' 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'self'"
    headers:upsert("Content-Security-Policy", csp)

    -- Custom Headers from configuration
    if config.headers and type(config.headers) == "table" then
        for k, v in pairs(config.headers) do
            headers:upsert(k, tostring(v))
        end
    end
end

return M
