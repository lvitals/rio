-- lib/rio/adapters/standalone.lua
local url = require("net.url")

local M = {}
M.__index = M

function M.new(stream)
    local headers_obj = stream:get_headers()
    local self = setmetatable({
        stream = stream,
        headers_obj = headers_obj
    }, M)
    
    self.method = headers_obj:get(":method")
    local full_path = headers_obj:get(":path") or ""
    local parsed_url = url.parse(full_path)
    self.path = parsed_url.path or "/"
    self.query = parsed_url.query or {}
    
    self.headers = {}
    for k, v in headers_obj:each() do
        if k:sub(1,1) ~= ":" then self.headers[k:lower()] = v end
    end
    return self
end

function M:get_body() return self.stream:get_body_as_string() end
function M:write_headers(headers, end_stream) return self.stream:write_headers(headers, end_stream) end
function M:write_body(body) return self.stream:write_body_from_string(body) end

function M:websocket_upgrade(handler, ctx)
    local websocket = require("http.websocket")
    local ws = websocket.new_from_stream(self.stream, self.headers_obj)
    
    local ok, err = ws:accept()
    if not ok then 
        io.stderr:write("Handshake Error: " .. tostring(err) .. "\n")
        return nil, err 
    end

    local wb = {
        ws = ws,
        recv_frame = function(self)
            -- No Standalone (lua-http), receive() bloqueia até ter dados
            local data, typ, err_code = self.ws:receive()
            if not data then return nil, nil, typ end
            
            -- Map to Rio string types
            local types = { [1] = "text", [2] = "binary", [8] = "close" }
            return data, types[typ] or typ, err_code
        end,
        send_text = function(self, data) 
            return self.ws:send(data, 1) 
        end,
        send_close = function(self) 
            pcall(self.ws.close, self.ws) 
        end
    }

    local status, res = pcall(handler, wb, ctx)
    if not status then io.stderr:write("Handler Error: " .. tostring(res) .. "\n") end
    return res
end

function M:close() if self.stream then pcall(self.stream.shutdown, self.stream) end end

return M
