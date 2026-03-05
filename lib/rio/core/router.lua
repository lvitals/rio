-- rio/lib/rio/core/router.lua
local path_utils = require("rio.utils.path")

local M = {}
local METHODS = {"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD", "WS"}

local Router = {}
Router.__index = Router

function M.new()
    local routes = {}
    for _, method in ipairs(METHODS) do routes[method] = {} end
    return setmetatable({ routes = routes, _prefix_stack = {} }, Router)
end

function Router:add_route(method, path, handler, options)
    method = method:upper()
    if not self.routes[method] then self.routes[method] = {} end
    
    -- If handler is a string like "Controller#action" or "Controller@action", wrap it
    if type(handler) == "string" then
        local controller, action = handler:match("^([^#@]+)[#@]([^#@]+)$")
        if controller and action then
            local original_handler = handler
            handler = function(params)
                return { controller = controller, action = action, _original = original_handler, params = params }
            end
        end
    end

    local prefix = self:get_current_prefix()
    local fullPath = path_utils.normalize(path_utils.join(prefix, path))
    local pattern, names = path_utils.compile(fullPath)
    
    table.insert(self.routes[method], {
        pattern = pattern,
        names = names,
        handler = handler,
        path = fullPath,
        meta = options or {}
    })
    return self
end

function Router:match(method, path)
    method = method:upper()
    local list = self.routes[method] or {}
    for _, route in ipairs(list) do
        local caps = {path:match(route.pattern)}
        if #caps > 0 then
            local params = {}
            for i, name in ipairs(route.names) do params[name] = caps[i] end
            return route.handler, params, route.path
        end
    end
    return nil
end

for _, m in ipairs(METHODS) do
    Router[m:lower()] = function(self, path, handler, options)
        return self:add_route(m, path, handler, options)
    end
end

function Router:set_prefix(prefix) self._base_prefix = prefix or "" end
function Router:clear_prefix() self._base_prefix = "" end
function Router:push_prefix(prefix) table.insert(self._prefix_stack, prefix or "") end
function Router:pop_prefix() table.remove(self._prefix_stack) end

function Router:get_current_prefix()
    local acc = self._base_prefix or ""
    for _, p in ipairs(self._prefix_stack) do acc = path_utils.join(acc, p) end
    return acc
end

return M
