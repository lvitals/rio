-- rio/lib/rio/server.lua
-- HTTP Server for the Rio Framework.

local router_lib = require("rio.core.router")
local context_lib = require("rio.core.context")
local response_lib = require("rio.core.response")
local cache_lib = require("rio.cache")
local compat = require("rio.utils.compat")

local Server = {}
Server.__index = Server

-- Creates a new server instance
function Server.new(config)
    config = config or {}
    local cache_store = config.cache_store or "file"
    local perform_caching = config.perform_caching ~= false
    
    local adapter, options
    if not perform_caching then adapter = "null"; options = {}
    elseif type(cache_store) == "table" then adapter = cache_store[1]; options = cache_store[2] or {}
    else adapter = cache_store; options = {} end
    
    return setmetatable({
        router = router_lib.new(),
        middlewares = {},
        routes_meta = setmetatable({}, { __mode = "k" }),
        cache = cache_lib.new(adapter, options),
        error_handler = nil,
        not_found_handler = nil,
        config = config or { max_body_size = 10 * 1024 * 1024 }
    }, Server)
end

-- Adds a global middleware
function Server:use(middleware, options)
    local handler = nil
    local name = "anonymous"

    if type(middleware) == "string" then
        name = middleware
        local rio = require("rio")
        local core_mw = rio.middleware[middleware]
        if core_mw then
            if type(core_mw) == "table" then
                if core_mw.basic and middleware ~= "auth" then handler = core_mw.basic()
                elseif core_mw.headers then handler = core_mw.headers()
                elseif core_mw.default then handler = core_mw.default()
                elseif core_mw.create then handler = core_mw.create(self, options)
                end
            else
                handler = core_mw
            end
        end

        if not handler then
            local ok, local_mw = pcall(require, "app.middleware." .. middleware)
            if ok then 
                if type(local_mw) == "table" and local_mw.create then handler = local_mw.create(self, options)
                else handler = local_mw end
            end
        end

        if not handler then
            local ok, direct_mw = pcall(require, middleware)
            if ok then handler = direct_mw end
        end

        if not handler then error("Could not resolve middleware: " .. middleware) end
    elseif type(middleware) == "function" then
        handler = middleware
    else
        error("Middleware must be a function or a string name")
    end
    
    local info = debug.getinfo(2, "Sl")
    local caller_source = info and string.format("%s:%d", info.short_src:match("([^/]+)$") or info.short_src, info.currentline) or "unknown"
    
    table.insert(self.middlewares, {
        handler = handler,
        name = name,
        source = caller_source
    })
    return self
end

function Server:load_middlewares(list)
    if type(list) == "table" then
        for _, mw in ipairs(list) do
            if type(mw) == "table" then self:use(mw[1], mw[2])
            else self:use(mw) end
        end
    elseif type(list) == "function" then
        list(self)
    end
    return self
end

function Server:on_error(handler) self.error_handler = handler; return self end
function Server:on_not_found(handler) self.not_found_handler = handler; return self end

-- Routing methods
function Server:_to_handler(handler)
    if type(handler) == "string" then
        local controller_name, action_name = handler:match("^(.*)@(.*)$")
        if controller_name and action_name then
            local simple_handler = function(ctx)
                local controller = require("app.controllers." .. controller_name:lower())
                return controller[action_name](controller, ctx)
            end
            
            self.routes_meta[simple_handler] = { controller = controller_name, action = action_name }
            return simple_handler
        end
    end
    return handler
end

local function add_route_with_meta(self, method, path, handler)
    handler = self:_to_handler(handler)
    self.router:add_route(method:upper(), path, handler)
    return self
end

function Server:get(path, handler) return add_route_with_meta(self, "GET", path, handler) end
function Server:post(path, handler) return add_route_with_meta(self, "POST", path, handler) end
function Server:put(path, handler) return add_route_with_meta(self, "PUT", path, handler) end
function Server:patch(path, handler) return add_route_with_meta(self, "PATCH", path, handler) end
function Server:delete(path, handler) return add_route_with_meta(self, "DELETE", path, handler) end

function Server:resources(name, controller_name)
    local controller_module_name = (controller_name or (name .. "_controller"))
    local simple_controller_name = controller_module_name:gsub("_controller$", ""):gsub("^app%.controllers%.", "")
    simple_controller_name = simple_controller_name:sub(1,1):upper() .. simple_controller_name:sub(2)

    local function add_route(method, action, path)
        local handler_str = simple_controller_name .. "@" .. action
        self[method](self, "/" .. name .. (path or ""), handler_str)
    end

    add_route("get", "index")
    if not self.config.api_only then add_route("get", "new", "/new") end
    add_route("post", "create")
    add_route("get", "show", "/:id")
    if not self.config.api_only then add_route("get", "edit", "/:id/edit") end
    add_route("put", "update", "/:id")
    add_route("patch", "update", "/:id")
    add_route("delete", "destroy", "/:id")
    return self
end

-- Helper to wrap a handler with middlewares
function Server:wrap(handler, ...)
    local mws = {...}
    handler = self:_to_handler(handler)
    if #mws == 0 then return handler end
    
    local wrapped = function(ctx)
        local index = 1
        local function next_mw()
            if index > #mws then return handler(ctx) end
            local mw = mws[index]
            index = index + 1
            return mw(ctx, next_mw)
        end
        return next_mw()
    end
    
    if type(handler) == "function" and self.routes_meta and self.routes_meta[handler] then
        self.routes_meta[wrapped] = self.routes_meta[handler]
    end
    return wrapped
end

function Server:group(prefix, fn)
    local group_prefix = prefix or ""
    local proxy = setmetatable({
        _middlewares = {},
        use = function(p, mw) table.insert(p._middlewares, mw) return p end,
        get = function(p, path, handler) 
            self:get(group_prefix .. path, self:wrap(handler, compat.unpack(p._middlewares))) 
            return p 
        end,
        post = function(p, path, handler) 
            self:post(group_prefix .. path, self:wrap(handler, compat.unpack(p._middlewares))) 
            return p 
        end,
        put = function(p, path, handler) 
            self:put(group_prefix .. path, self:wrap(handler, compat.unpack(p._middlewares))) 
            return p 
        end,
        patch = function(p, path, handler) 
            self:patch(group_prefix .. path, self:wrap(handler, compat.unpack(p._middlewares))) 
            return p 
        end,
        delete = function(p, path, handler) 
            self:delete(group_prefix .. path, self:wrap(handler, compat.unpack(p._middlewares))) 
            return p 
        end,
        group = function(p, sub_prefix, sub_fn)
            self:group(group_prefix .. sub_prefix, function(sub_proxy)
                -- Inherit middlewares from parent group
                for _, mw in ipairs(p._middlewares) do sub_proxy:use(mw) end
                sub_fn(sub_proxy)
            end)
            return p
        end,
        resources = function(p, name, controller_name)
            local res_controller = controller_name or (name .. "_controller")
            local add_res_route = function(method, action, path)
                local handler_str = res_controller .. "@" .. action
                p[method](p, "/" .. name .. (path or ""), handler_str)
            end
            add_res_route("get", "index")
            if not self.config.api_only then add_res_route("get", "new", "/new") end
            add_res_route("post", "create")
            add_res_route("get", "show", "/:id")
            if not self.config.api_only then add_res_route("get", "edit", "/:id/edit") end
            add_res_route("put", "update", "/:id")
            add_res_route("patch", "update", "/:id")
            add_res_route("delete", "destroy", "/:id")
            return p
        end
    }, { __index = self })

    local ok, err = pcall(fn, proxy)
    if not ok then error(err) end
    return self
end

-- Core Request Processing (Generic)
function Server:_process_request(adapter)
    local ctx = context_lib.new(adapter, self.config)
    ctx.app = self

    local function run_handler()
        local index = 1
        local function next_mw()
            if index > #self.middlewares then
                local handler, params, route_path = self.router:match(ctx.method, ctx.path)
                if not handler then
                    if self.not_found_handler then return self.not_found_handler(ctx) end
                    return ctx:text("Not Found", 404)
                end
                ctx.route = route_path
                for k, v in pairs(params) do ctx.params[k] = v end
                return handler(ctx)
            end
            local mw = self.middlewares[index].handler
            index = index + 1
            return mw(ctx, next_mw)
        end
        return next_mw()
    end

    context_lib.set_body(ctx, adapter:get_body())

    local ok, result = pcall(run_handler)
    if not ok then
        if self.error_handler then pcall(self.error_handler, ctx, result)
        else ctx:text("Internal Error: " .. tostring(result), 500) end
    end
end

-- Server Entry Points
function Server:handle_ngx()
    local adapter_name = self.config.adapter or "openresty"
    local adapter = require("rio.core.adapters." .. adapter_name).new()
    return self:_process_request(adapter)
end

function Server:listen(port, host)
    local h = host or os.getenv("RIO_BINDING") or self.config.server and self.config.server.host or "0.0.0.0"
    local p = port or tonumber(os.getenv("RIO_PORT")) or self.config.server and self.config.server.port or 8080
    local adapter_module = "rio.core.adapters." .. (self.config.adapter or "standalone")
    
    local ok, instance = pcall(compat.http_server.listen, {
        host = h, port = p, reuseaddr = true,
        onstream = function(_, stream)
            local adapter = require(adapter_module).new(stream)
            self:_process_request(adapter)
        end
    })

    if not ok then
        io.stderr:write("Error starting server: " .. tostring(instance) .. "\n")
        return false
    end

    print(string.format("Rio server listening on http://%s:%d", h, p))
    
    compat.signal.signal(compat.signal.SIGINT, function()
        if type(instance) == "table" and instance.close then instance:close() end
        os.exit(0)
    end)
    
    if type(instance) == "table" and instance.loop then
        instance:loop()
    end
    
    return true
end

function Server:bootstrap()
    local ok_db, db_config = pcall(require, "config.database")
    if ok_db then
        local env = os.getenv("RIO_ENV") or self.config.environment or "development"
        if db_config[env] then require("rio.database.manager").initialize(db_config[env]) end
    end
    local ok_mw, mw_cfg = pcall(require, "config.middlewares")
    if ok_mw then self:load_middlewares(mw_cfg) end
    local ok_routes, routes_fn = pcall(require, "config.routes")
    if ok_routes and type(routes_fn) == "function" then routes_fn(self) end
    return self
end

function Server:run(port, host)
    self:bootstrap()
    return self:listen(port, host)
end

return Server
