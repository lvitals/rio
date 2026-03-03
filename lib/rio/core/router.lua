-- rio/lib/rio/core/router.lua
-- HTTP routing system with support for dynamic parameters.

local path_utils = require("rio.utils.path")

local M = {}

-- Supported HTTP methods
local METHODS = {"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"}

local Router = {}
Router.__index = Router

-- Creates a new router instance
function M.new()
    local routes = {}
    for _, method in ipairs(METHODS) do
        routes[method] = {}
    end
    
    return setmetatable({
        routes = routes,
        _base_prefix = "",
        _prefix_stack = {}
    }, Router)
end

-- Adds a route
function Router:add_route(method, path, handler)
    -- If handler is a string like "Controller@action", wrap it
    if type(handler) == "string" then
        local controller, action = handler:match("([^@]+)@([^@]+)")
        if not controller then error("Invalid handler format: " .. handler) end
        local original_handler = handler
        handler = function(ctx)
            return { controller = controller, action = action, _original = original_handler }
        end
    end

    if type(handler) ~= "function" then
        error("Handler must be a function or 'Controller@action' string")
    end
    
    -- Validate path
    if not path_utils.is_safe(path) then
        error("Unsafe path: " .. tostring(path))
    end
    
    -- Calculate current prefix
    local prefix = self:get_current_prefix()
    local fullPath = path_utils.join(prefix, path)
    fullPath = path_utils.normalize(fullPath)
    
    -- Compile path
    local pattern, names = path_utils.compile(fullPath)
    
    table.insert(self.routes[method], {
        pattern = pattern,
        names = names,
        handler = handler,
        path = fullPath
    })
end

-- Convenience methods
for _, method in ipairs(METHODS) do
    Router[method:lower()] = function(self, path, handler)
        return self:add_route(method, path, handler)
    end
end

-- Searches for matching route
function Router:match(method, path)
    local list = self.routes[method] or {}
    
    for _, route in ipairs(list) do
        local caps = {path:match(route.pattern)}
        if #caps > 0 then
            local params = {}
            for i, name in ipairs(route.names) do
                local v = caps[i]
                if v == "" then v = nil end
                params[name] = v
            end
            return route.handler, params, route.path
        end
    end
    
    return nil
end

-- Defines global prefix
function Router:set_prefix(prefix)
    self._base_prefix = prefix or ""
end

-- Clears global prefix
function Router:clear_prefix()
    self._base_prefix = ""
end

-- Adds temporary prefix (group)
function Router:push_prefix(prefix)
    table.insert(self._prefix_stack, prefix or "")
end

-- Removes temporary prefix
function Router:pop_prefix()
    table.remove(self._prefix_stack)
end

-- Calculates current prefix (base + stack)
function Router:get_current_prefix()
    local acc = self._base_prefix or ""
    for _, p in ipairs(self._prefix_stack) do
        acc = path_utils.join(acc, p)
    end
    return acc
end

return M
