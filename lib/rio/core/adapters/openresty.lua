-- lib/rio/adapters/openresty.lua
-- OpenResty adapter for the Rio framework.
-- Integrates with Nginx Lua module (ngx) and supports WebSockets.

local M = {}
M.__index = M

function M.new()
    local self = setmetatable({}, M)
    
    self.method = ngx.req.get_method()
    self.path = ngx.var.uri
    self.query = ngx.req.get_uri_args()
    self.headers = ngx.req.get_headers()
    
    return self
end

function M:get_body()
    ngx.req.read_body()
    return ngx.req.get_body_data()
end

function M:write_headers(headers, end_stream)
    ngx.status = tonumber(headers:get(":status") or 200)
    for k, v in headers:each() do
        if k:sub(1,1) ~= ":" then
            ngx.header[k] = v
        end
    end
    
    -- OpenResty automatically handles the stream end when the content_by_lua block ends
    -- or exit is called
    if end_stream then ngx.exit(ngx.status) end
    return true
end

function M:write_body(body)
    ngx.print(body)
    return true
end

-- Promotion to WebSocket protocol
function M:websocket_upgrade(handler, ctx)
    local server = require "resty.websocket.server"
    local wb, err = server:new{
        timeout = ctx.config.ws_timeout or 5000,
        max_payload_len = ctx.config.ws_max_payload_len or 65535,
    }

    if not wb then
        ngx.log(ngx.ERR, "Failed to upgrade to websocket: ", err)
        return ngx.exit(444)
    end

    -- Create a wrapper object that matches the Rio WebSocket Bridge (wb) API
    local wb_bridge = {
        wb = wb,
        recv_frame = function(self)
            local data, typ, err_code = self.wb:recv_frame()
            if not data then 
                if err_code == "timeout" then return true, "timeout", nil end
                return nil, nil, err_code 
            end
            return data, typ, err_code
        end,
        send_text = function(self, data) 
            return self.wb:send_text(data) 
        end,
        send_close = function(self) 
            return self.wb:send_close() 
        end
    }

    return handler(wb_bridge, ctx)
end

function M:close()
    -- OpenResty handles connection closure automatically
end

return M
