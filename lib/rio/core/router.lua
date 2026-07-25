-- rio/lib/rio/core/router.lua
local path_utils = require("rio.utils.path")

local M = {}
local METHODS = {"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD", "WS"}

local Router = {}
Router.__index = Router

function M.new()
    local routes = {}
    for _, method in ipairs(METHODS) do routes[method] = {} end
    return setmetatable({ routes = routes, _prefix_stack = {}, _scope_stack = {} }, Router)
end

local function merge_meta(...)
    local out = {}
    for i = 1, select("#", ...) do
        local meta = select(i, ...)
        if type(meta) == "table" then
            for k, v in pairs(meta) do out[k] = v end
        end
    end
    return out
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
    local meta = merge_meta(self:get_current_scope_meta(), options)
    
    table.insert(self.routes[method], {
        pattern = pattern,
        names = names,
        handler = handler,
        path = fullPath,
        meta = meta
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

function Router:set_prefix(prefix, meta)
    self._base_prefix = prefix or ""
    self._base_meta = meta or {}
end
function Router:clear_prefix()
    self._base_prefix = ""
    self._base_meta = {}
end
function Router:push_prefix(prefix) return self:push_scope(prefix) end
function Router:pop_prefix() return self:pop_scope() end

function Router:push_scope(prefix, meta)
    table.insert(self._prefix_stack, prefix or "")
    table.insert(self._scope_stack, meta or {})
    return self
end

function Router:pop_scope()
    table.remove(self._prefix_stack)
    table.remove(self._scope_stack)
    return self
end

function Router:get_current_prefix()
    local acc = self._base_prefix or ""
    for _, p in ipairs(self._prefix_stack) do acc = path_utils.join(acc, p) end
    return acc
end

function Router:get_current_scope_meta()
    local acc = merge_meta(self._base_meta)
    for _, meta in ipairs(self._scope_stack) do
        acc = merge_meta(acc, meta)
    end
    return acc
end

return M
