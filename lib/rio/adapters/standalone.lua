-- lib/rio/adapters/standalone.lua
local url = require("net.url")

local M = {}
M.__index = M

function M.new(stream)
    local self = setmetatable({
        stream = stream
    }, M)
    
    local headers_obj = stream:get_headers()
    self.method = headers_obj:get(":method")
    
    local full_path = headers_obj:get(":path") or ""
    local parsed_url = url.parse(full_path)
    self.path = parsed_url.path or "/"
    self.query = parsed_url.query or {}
    
    self.headers = {}
    for k, v in headers_obj:each() do
        if k:sub(1,1) ~= ":" then
            self.headers[k:lower()] = v
        end
    end
    
    return self
end

function M:get_body()
    return self.stream:get_body_as_string()
end

function M:write_headers(headers, end_stream)
    return self.stream:write_headers(headers, end_stream)
end

function M:write_body(body)
    return self.stream:write_body_from_string(body)
end

function M:close()
    if self.stream.shutdown then self.stream:shutdown()
    elseif self.stream.close then self.stream:close() end
end

return M
