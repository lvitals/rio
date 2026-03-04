-- rio/lib/rio/core/context.lua
-- Generic Context object that wraps a Web Server Adapter.

local http_headers_ok, http_headers = pcall(require, "http.headers")
local compat = require("rio.utils.compat")
local json = compat.json
local response = require("rio.core.response")
local headers_utils = require("rio.utils.headers")
local url = require("net.url")

local M = {}

-- Creates a new context from an adapter.
function M.new(adapter, config)
    local ctx = {
        -- Core objects
        adapter = adapter,
        config = config or {},
        
        -- Request properties
        method = adapter.method,
        path = adapter.path,
        query = adapter.query or {},
        headers = adapter.headers or {},
        
        -- Response headers
        response_headers = http_headers_ok and http_headers.new() or compat.new_headers(),
        
        -- Placeholders
        route = nil,
        params = {},
        raw_body = nil,
        body = nil,
        state = {},

        -- Flash messages
        notice = adapter.query and adapter.query.notice,
        alert = adapter.query and adapter.query.alert
    }

    ctx.req = ctx
    ctx.res = ctx
    
    function ctx:setHeader(key, value) self.response_headers:append(key, value) end

    function ctx:setCookie(name, value, options)
        options = options or {}
        local cookie = name .. "=" .. (value or "")
        if options.path then cookie = cookie .. "; Path=" .. options.path end
        if options.domain then cookie = cookie .. "; Domain=" .. options.domain end
        if options.max_age then cookie = cookie .. "; Max-Age=" .. options.max_age end
        if options.http_only then cookie = cookie .. "; HttpOnly" end
        if options.secure then cookie = cookie .. "; Secure" end
        if options.same_site then cookie = cookie .. "; SameSite=" .. options.same_site end
        self:setHeader("Set-Cookie", cookie)
    end

    function ctx:getCookie(name)
        local cookie_header = self:getHeader("cookie")
        if not cookie_header then return nil end
        for k, v in cookie_header:gmatch("([^%s=;]+)=([^;]*)") do
            if k == name then return v:gsub("^%s*(.-)%s*$", "%1") end
        end
        return nil
    end

    -- Response helpers
    function ctx:json(obj, status)
        return response.json(self.adapter, status or 200, obj, self.response_headers)
    end
    
    function ctx:text(str, status)
        return response.text(self.adapter, status or 200, str, self.response_headers)
    end
    
    function ctx:html(html, status)
        return response.html(self.adapter, status or 200, html, self.response_headers)
    end
    
    function ctx:view(view_path, data, status)
        local view_data = data or {}
        for k, v in pairs(self.state) do if view_data[k] == nil then view_data[k] = v end end
        view_data.notice = view_data.notice or self.notice
        view_data.alert = view_data.alert or self.alert
        view_data.request_path = self.path
        return response.view(self.adapter, status or 200, view_path, view_data, self.response_headers)
    end
    
    function ctx:redirect(location, status)
        self:setHeader("Location", location)
        return response.redirect(self.adapter, status or 302, self.response_headers)
    end

    function ctx:getHeader(name) return self.headers[string.lower(name)] end
    function ctx:getBearer() return headers_utils.get_bearer(self.headers) end
    
    return ctx
end

-- Sets and parses the body on the context object.
function M.set_body(ctx, raw_body)
    ctx.raw_body = raw_body
    ctx.body = raw_body
    if not raw_body or raw_body == "" then ctx.body = nil; return end

    local ct = ctx:getHeader("content-type") or ""
    if ct:find("json", 1, true) or ct:find("application/vnd.api+json", 1, true) then
        local ok, data = pcall(json.decode, raw_body)
        if ok then ctx.body = data end
    elseif ct:find("application/x-www-form-urlencoded", 1, true) then
        local query_table = url.parseQuery(raw_body)
        ctx.body = query_table or {}
    end
end

return M
