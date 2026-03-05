-- lib/rio/cable.lua
-- Action Cable-like Pub/Sub engine for Rio.
-- Manages subscriptions and message broadcasting across connections.

local compat = require("rio.utils.compat")
local json = compat.json

local M = {}

-- Global connection registry for Standalone mode (persistent in-process)
if _G._RIO_WS_REGISTRY == nil then
    _G._RIO_WS_REGISTRY = {} -- { ["stream_name"] = { [wb_object] = true, ... } }
end
local registry = _G._RIO_WS_REGISTRY

-- Broadcasts a message to all subscribers of a specific stream.
function M.broadcast(stream_name, data)
    local payload = json.encode(data)
    
    -- 1. OpenResty support (Pub/Sub via shared dict)
    if ngx and ngx.shared and ngx.shared.rio_cable then
        local dict = ngx.shared.rio_cable
        local version = dict:incr("version", 1, 0)
        dict:set("msg:" .. version, json.encode({stream = stream_name, data = data}), 10)
        return true
    end

    -- 2. Standalone support (Direct delivery to registered objects)
    if registry[stream_name] then
        for wb, _ in pairs(registry[stream_name]) do
            local ok = pcall(function() wb:send_text(payload) end)
            if not ok then registry[stream_name][wb] = nil end
        end
    end
    return true
end

-- Subscribes a connection to a specific stream.
function M.subscribe(stream_name, wb)
    if not registry[stream_name] then registry[stream_name] = {} end
    registry[stream_name][wb] = true
    
    return function()
        if registry[stream_name] then
            registry[stream_name][wb] = nil
        end
    end
end

return M
