-- rio/lib/rio/auth.lua
-- Authentication utilities and middlewares for the Rio framework.

local jwt = require("rio.utils.jwt")
local env = require("rio.utils.env")
-- local b64 = require("enc_b64") -- No longer directly used here, its functionality is in rio.utils.jwt

local M = {}

M.description = "Provides various authentication methods (Bearer, Basic, API Key, JWT)."

-- Middleware for simple Bearer Token authentication.
function M.bearer(validator)
    if type(validator) ~= "function" then
        error("validator must be a function")
    end
    
    return function(ctx, next)
        local token = ctx:getBearer()
        
        if not token then
            return ctx:error(401, "Missing or invalid authorization header")
        end
        
        -- Validate token using the provided function
        local ok, user_or_error = validator(token, ctx)
        
        if not ok then
            return ctx:error(401, user_or_error or "Unauthorized")
        end
        
        ctx.state.user = user_or_error
        
        return next()
    end
end

-- Middleware for Basic HTTP Authentication.
function M.basic(validator)
    if type(validator) ~= "function" then
        error("validator must be a function")
    end
    
    return function(ctx, next)
        local auth_header = ctx:getHeader("authorization")
        local auth_err_headers = { ["WWW-Authenticate"] = 'Basic realm="Access"' }

        if not auth_header then
            return ctx:error(401, "Missing authorization header", nil, auth_err_headers)
        end
        
        local scheme, credentials = auth_header:match("^(%S+)%s+(.+)$")
        
        if not scheme or scheme:lower() ~= "basic" then
            return ctx:error(401, "Invalid authorization scheme", nil, auth_err_headers)
        end
        
        -- TODO: Implement pure Lua Base64 decoding for basic auth credentials.
        -- For now, credentials are not decoded. This is INSECURE for production.
        local decoded = credentials -- Placeholder for actual Base64 decode
        local username, password = decoded:match("^([^:]+):(.+)$")
        
        if not username or not password then
            return ctx:error(401, "Invalid credentials format", nil, auth_err_headers)
        end
        
        -- Validate credentials
        local ok, user_or_error = validator(username, password, ctx)
        
        if not ok then
            return ctx:error(401, user_or_error or "Invalid credentials", nil, auth_err_headers)
        end
        
        ctx.state.user = user_or_error
        
        return next()
    end
end

-- Middleware for API Key authentication in a custom header.
function M.api_key(header_name, validator)
    header_name = header_name or "x-api-key"
    
    if type(validator) ~= "function" then
        error("validator must be a function")
    end
    
    return function(ctx, next)
        local key = ctx:getHeader(header_name)
        
        if not key or key == "" then
            return ctx:error(401, "Missing API key")
        end
        
        local ok, user_or_error = validator(key, ctx)
        
        if not ok then
            return ctx:error(401, user_or_error or "Invalid API key")
        end
        
        ctx.state.user = user_or_error
        
        return next()
    end
end

-- Middleware for JWT authentication.
function M.jwt(options)
    options = options or {}
    
    local secret = options.secret or env.get("JWT_SECRET")
    if not secret or secret == "" then
        error("JWT secret is required. Set JWT_SECRET in .env or pass as an option.")
    end
    
    local verify_options = {
        issuer = options.issuer,
        audience = options.audience
    }
    
    return function(ctx, next)
        local token = ctx:getBearer()
        
        if not token then
            return ctx:error(401, "Missing or invalid authorization header")
        end
        
        local ok, payload_or_error = jwt.verify(token, secret, verify_options)
        
        if not ok then
            return ctx:error(401, payload_or_error or "Invalid token")
        end
        
        local user = (options.getUserFromPayload and options.getUserFromPayload(payload_or_error, ctx)) or payload_or_error
        
        ctx.state.jwt_payload = payload_or_error
        ctx.state.user = user
        
        return next()
    end
end

-- Helper to generate a JWT.
function M.generate_token(payload, options)
    options = options or {}
    local secret = options.secret or env.get("JWT_SECRET")
    
    if not secret or secret == "" then
        error("JWT secret is required.")
    end
    
    return jwt.sign(payload, secret, options)
end

-- Helper to generate a standard access token.
function M.generate_access_token(payload, options)
    options = options or {}
    options.expiresIn = options.expiresIn or (15 * 60) -- 15 minutes
    return M.generate_token(payload, options)
end

-- Helper to generate a pair of access and refresh tokens.
function M.generate_token_pair(user_payload, options)
    options = options or {}
    local secret = options.secret or env.get("JWT_SECRET")
    
    if not secret or secret == "" then
        error("JWT secret is required.")
    end
    
    local access_expires = options.access_expires_in or (15 * 60) -- 15 min
    local refresh_expires = options.refresh_expires_in or (30 * 24 * 60 * 60) -- 30 days
    
    local access_token = jwt.create_access_token(user_payload, secret, access_expires)
    local refresh_token = jwt.create_refresh_token(user_payload, secret, refresh_expires)
    
    return {
        access_token = access_token,
        refresh_token = refresh_token,
        token_type = "Bearer",
        expires_in = access_expires
    }
end

-- Helper to verify a token outside of middleware.
function M.verify_token(token, options)
    options = options or {}
    local secret = options.secret or env.get("JWT_SECRET")
    
    if not secret or secret == "" then
        error("JWT secret is required.")
    end
    
    return jwt.verify(token, secret, options)
end

-- Helper to decode a token without verification (for debugging).
function M.decode_token(token)
    return jwt.decode(token)
end

return M
