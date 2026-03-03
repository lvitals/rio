-- rio/lib/rio/middleware/security.lua
-- Security-related middlewares for the Rio framework.

local response = require("rio.core.response")

local M = {}

M.description = "Enhances application security by setting essential HTTP headers."

-- Adds standard security headers to every response.
function M.headers()
    return function(ctx, next)
        response.set_security_headers(ctx.response_headers)
        return next()
    end
end

-- Simple in-memory rate limiting middleware.
function M.rate_limit(options)
    options = options or {}
    local window = options.window or 60 -- seconds
    local max_requests = options.max_requests or 100
    local requests = {} -- {ip: {count, reset}}
    
    return function(ctx, next)
        -- TODO: Find a reliable way to get IP from lua-http stream.
        local ip = ctx:getHeader("x-forwarded-for") or 
                   ctx:getHeader("x-real-ip") or
                   "unknown"
        
        local now = os.time()
        local record = requests[ip]
        
        if not record or now > record.reset then
            requests[ip] = { count = 1, reset = now + window }
        else
            record.count = record.count + 1
            if record.count > max_requests then
                local retry_after = tostring(record.reset - now)
                ctx:setHeader("Retry-After", retry_after)
                return ctx:error(429, "Too Many Requests", nil, { ["Retry-After"] = retry_after })
            end
        end
        
        ctx:setHeader("X-RateLimit-Limit", tostring(max_requests))
        ctx:setHeader("X-RateLimit-Remaining", tostring(max_requests - requests[ip].count))
        ctx:setHeader("X-RateLimit-Reset", tostring(requests[ip].reset))
        
        return next()
    end
end

-- Middleware to limit the maximum size of a request body.
function M.body_size_limit(max_size)
    max_size = max_size or 10 * 1024 * 1024 -- 10MB
    
    return function(ctx, next)
        local cl = ctx:getHeader("content-length")
        
        if cl then
            local size = tonumber(cl)
            if size and size > max_size then
                return ctx:error(413, "Payload Too Large")
            end
        end
        
        return next()
    end
end

-- Middleware to protect against path traversal attacks.
function M.path_traversal()
    return function(ctx, next)
        if ctx.path:find("%.%.", 1, true) then
            return ctx:error(400, "Invalid Path")
        end
        return next()
    end
end

-- Middleware to validate that the request uses an allowed HTTP method.
function M.allowed_methods(methods)
    local allowed = {}
    for _, m in ipairs(methods or {}) do
        allowed[m:upper()] = true
    end
    
    return function(ctx, next)
        if not allowed[ctx.method] then
            local allow_header = table.concat(methods, ", ")
            return ctx:error(405, "Method Not Allowed", nil, { Allow = allow_header })
        end
        
        return next()
    end
end

return M
