-- lib/rio/adapters/openresty.lua
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
    for k, v in headers:each() do
        if k == ":status" then
            ngx.status = tonumber(v)
        else
            ngx.header[k] = v
        end
    end
    -- In OpenResty, headers are sent automatically when body or exit is called
    if end_stream then ngx.exit(ngx.status) end
    return true
end

function M:write_body(body)
    ngx.print(body)
    return true
end

function M:close()
    -- OpenResty handles connection closure
end

return M
