-- rio/lib/rio/middleware/cors.lua
-- Middleware for CORS (Cross-Origin Resource Sharing) configuration.

local response_lib = require("rio.core.response")

local M = {}

M.description = "Handles Cross-Origin Resource Sharing (CORS) headers."

-- Helper to add CORS headers to the context's response headers.
local function set_cors_headers(ctx, options)
    options = options or {}
    ctx:setHeader("Access-Control-Allow-Origin", options.origin or "*")
    ctx:setHeader("Access-Control-Allow-Methods", options.methods or "GET,POST,PUT,PATCH,DELETE,OPTIONS")
    ctx:setHeader("Access-Control-Allow-Headers", options.headers or "Content-Type, Authorization")
    
    if options.credentials then
        ctx:setHeader("Access-Control-Allow-Credentials", "true")
    end
    
    if options.max_age then
        ctx:setHeader("Access-Control-Max-Age", tostring(options.max_age))
    end
end

-- Creates a CORS middleware with configurable options.
function M.create(options)
    options = options or {}
    
    return function(ctx, next)
        set_cors_headers(ctx, options)
        
        -- Respond immediately to preflight OPTIONS requests.
        if ctx.method == "OPTIONS" then
            return ctx:no_content()
        end
        
        return next()
    end
end

-- Default permissive CORS middleware for development.
function M.default()
    return M.create({
        origin = "*",
        methods = "GET,POST,PUT,PATCH,DELETE,OPTIONS,HEAD",
        headers = "Content-Type, Authorization",
        credentials = false
    })
end

-- Strict CORS middleware for production, requires a list of allowed origins.
function M.strict(allowed_origins)
    return function(ctx, next)
        local origin = ctx:getHeader("origin")
        
        local allowed = false
        if origin and type(allowed_origins) == "table" then
            for _, allowed_origin in ipairs(allowed_origins) do
                if origin == allowed_origin then
                    allowed = true
                    break
                end
            end
        elseif origin and type(allowed_origins) == "string" then
            allowed = (origin == allowed_origins)
        end
        
        if allowed then
            set_cors_headers(ctx, {
                origin = origin,
                methods = "GET,POST,PUT,PATCH,DELETE,OPTIONS",
                headers = "Content-Type, Authorization",
                credentials = true,
                max_age = 86400
            })
        end
        
        -- For preflight OPTIONS requests, respond based on whether the origin is allowed.
        if ctx.method == "OPTIONS" then
            if allowed then
                return ctx:no_content()
            else
                return ctx:error(403, "CORS: Origin not allowed")
            end
        end
        
        -- For actual requests, block if the origin is present but not allowed.
        if origin and not allowed then
            return ctx:error(403, "CORS: Origin not allowed")
        end
        
        return next()
    end
end

return M
