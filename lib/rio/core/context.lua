-- rio/lib/rio/core/context.lua
-- Context object that encapsulates a lua-http stream.

local http_headers_ok, http_headers = pcall(require, "http.headers")
local url = require("net.url")
local compat = require("rio.utils.compat")
local json = compat.json
local response = require("rio.core.response")
local headers_utils = require("rio.utils.headers")

local M = {}

-- Helper to convert lua-http headers object to a simple Lua table.
local function headers_to_table(headers_obj)
    local tbl = {}
    if not headers_obj then return tbl end
    for key, value in headers_obj:each() do
        tbl[string.lower(key)] = value
    end
    return tbl
end

-- Creates a new context for a request.
function M.new(stream, config)
    local req_headers_obj = assert(stream:get_headers())
    local req_path = req_headers_obj:get(":path") or ""
    
    local parsed_url = url.parse(req_path)
    local path = parsed_url.path or "/"
    local query = parsed_url.query or {}

    local ctx = {
        -- Core objects
        stream = stream,
        config = config or {},
        
        -- Request properties
        method = req_headers_obj:get(":method"),
        path = path,
        query = query,
        headers = headers_to_table(req_headers_obj),
        
        -- Response headers to be built by middlewares
        response_headers = http_headers_ok and http_headers.new() or compat.new_headers(),
        
        -- Placeholders for router and body
        route = nil,
        params = {},
        raw_body = nil,
        body = nil,
        
        -- State for middlewares
        state = {},

        -- Flash messages (simulated via query params for now)
        notice = query.notice,
        alert = query.alert
    }
    
    -- Convenience method to set a response header
    function ctx:setHeader(key, value)
        self.response_headers:append(key, value)
    end

    -- Convenience response methods
    function ctx:json(obj, status, extra_headers)
        -- Merge headers before sending
        for k, v in pairs(extra_headers or {}) do self:setHeader(k, v) end
        
        -- Detect format from Accept header, fallback to config
        local accept = self:getHeader("accept") or ""
        local format = self.config.api_format or "json"
        
        -- print("DEBUG: ctx:json format from config:", self.config.api_format)
        -- print("DEBUG: ctx:json resolved format:", format)

        if accept:find("application/vnd.api+json", 1, true) then
            format = "jsonapi"
        elseif accept:find("application/json", 1, true) then
            format = "json"
        end

        return response.json(self.stream, status or 200, obj, self.response_headers, format)
    end
    
    function ctx:text(str, status, extra_headers)
        for k, v in pairs(extra_headers or {}) do self:setHeader(k, v) end
        return response.text(self.stream, status or 200, str, self.response_headers)
    end
    
    function ctx:html(html, status, extra_headers)
        for k, v in pairs(extra_headers or {}) do self:setHeader(k, v) end
        return response.html(self.stream, status or 200, html, self.response_headers)
    end
    
    function ctx:error(status, message, details, extra_headers)
        for k, v in pairs(extra_headers or {}) do self:setHeader(k, v) end
        return response.error(self.stream, status, message, details, self.response_headers, self.config)
    end
    
    function ctx:raw(status, body, extra_headers)
        for k, v in pairs(extra_headers or {}) do self:setHeader(k, v) end
        return response.raw(self.stream, status, body, self.response_headers)
    end

    function ctx:redirect(location, status)
        self:setHeader("Location", location)
        return response.redirect(self.stream, status, self.response_headers)
    end
    
    function ctx:no_content()
        return response.no_content(self.stream, self.response_headers)
    end
    
    function ctx:view(view_path, data, status, extra_headers)
        local view_data = data or {}
        -- Automatically include notice/alert in view data
        view_data.notice = view_data.notice or self.notice
        view_data.alert = view_data.alert or self.alert
        
        for k, v in pairs(extra_headers or {}) do self:setHeader(k, v) end
        return response.view(self.stream, status or 200, view_path, view_data, self.response_headers)
    end
    
    -- Helper to get a single header
    function ctx:getHeader(name)
        return (name and self.headers[string.lower(name)]) or nil
    end
    
    -- Helper to get Bearer token
    function ctx:getBearer()
        return headers_utils.get_bearer(self.headers)
    end
    
    return ctx
end

-- Sets and parses the body on the context object.
function M.set_body(ctx, raw_body)
    ctx.raw_body = raw_body
    ctx.body = raw_body -- Default to raw body

    if not raw_body or raw_body == "" then
        ctx.body = nil
        return
    end

    local ct = ctx:getHeader("content-type") or ""
    if ct:find("application/json", 1, true) or ct:find("application/vnd.api+json", 1, true) then
        local ok, data = pcall(json.decode, raw_body)
        if ok then
            ctx.body = data
        else
            -- Keep raw body, maybe log an error or set a flag
            print("Warning: Failed to parse JSON body.")
        end
    elseif ct:find("application/x-www-form-urlencoded", 1, true) then
        -- Use net.url to parse form data
        -- net.url.parseQuery returns a table of parameters
        local query_table = url.parseQuery(raw_body)
        ctx.body = query_table or {}
    end
end

return M
