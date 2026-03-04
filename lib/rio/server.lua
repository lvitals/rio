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
    
    -- Cache Configuration (Rails-style)
    local cache_store = config.cache_store or "file"
    local perform_caching = config.perform_caching ~= false
    
    local adapter, options
    if not perform_caching then
        adapter = "null"
        options = {}
    elseif type(cache_store) == "table" then
        adapter = cache_store[1]
        options = cache_store[2] or {}
    else
        adapter = cache_store
        options = {}
    end
    
    return setmetatable({
        router = router_lib.new(),
        middlewares = {},
        routes_meta = setmetatable({}, { __mode = "k" }), -- Route metadata storage
        cache = cache_lib.new(adapter, options),
        error_handler = nil,
        not_found_handler = nil,
        config = config or {
            max_body_size = 10 * 1024 * 1024 -- 10MB
        }
    }, Server)
end

-- Adds a global middleware
function Server:use(middleware, options)
    local handler = nil
    local name = "anonymous"

    if type(middleware) == "string" then
        name = middleware
        -- 1. Try Rio Core
        local rio = require("rio")
        local core_mw = rio.middleware[middleware]
        if core_mw then
            if type(core_mw) == "table" then
                -- Auto-call standard initializers
                if core_mw.basic and middleware ~= "auth" then handler = core_mw.basic() -- auth.basic requires a validator
                elseif core_mw.headers then handler = core_mw.headers()
                elseif core_mw.default then handler = core_mw.default()
                elseif core_mw.create then handler = core_mw.create(self, options)
                end
            elseif type(core_mw) == "function" then
                handler = core_mw
            end
        end

        -- 2. Try Local Middleware (app/middleware/name.lua)
        if not handler then
            local ok, local_mw = pcall(require, "app.middleware." .. middleware)
            if ok then 
                if type(local_mw) == "table" and local_mw.create then
                    handler = local_mw.create(options)
                else
                    handler = local_mw
                end
            end
        end

        -- 3. Try Direct Require
        if not handler then
            local ok, direct_mw = pcall(require, middleware)
            if ok then handler = direct_mw end
        end

        if not handler then
            error("Could not resolve middleware: " .. middleware)
        end
    elseif type(middleware) == "function" then
        handler = middleware
    else
        error("Middleware must be a function or a string name")
    end
    
    -- Capture where this middleware was added
    local info = debug.getinfo(2, "Sl")
    local caller_source = "unknown"
    if info then
        caller_source = string.format("%s:%d", info.short_src:match("([^/]+)$") or info.short_src, info.currentline)
    end
    
    table.insert(self.middlewares, {
        handler = handler,
        source = caller_source,
        name = name
    })
    return self
end

-- Loads multiple middlewares from a list
function Server:load_middlewares(list)
    if type(list) == "table" then
        for _, mw in ipairs(list) do
            if type(mw) == "table" then
                self:use(mw[1], mw[2]) -- handle { "name", { options } }
            else
                self:use(mw)
            end
        end
    elseif type(list) == "function" then
        list(self)
    end
    return self
end

-- Sets a custom error handler
function Server:on_error(handler)
    self.error_handler = handler
    return self
end

-- Sets a custom 404 handler
function Server:on_not_found(handler)
    self.not_found_handler = handler
    return self
end

-- Routing methods
local function wrap_handler_with_meta(self, method, path, handler)
    if type(handler) == "string" then
        local controller_name, action_name = handler:match("([^@]+)@([^@]+)")
        if controller_name and action_name then
            local full_controller_module = "app.controllers." .. controller_name:lower():gsub("controller$", "") .. "_controller"
            local simple_handler = function(ctx)
                local ok, controller = pcall(require, full_controller_module)
                if not ok then return ctx:text("Controller not found: " .. full_controller_module, 500) end
                if not controller[action_name] then return ctx:text("Action not found: " .. action_name, 404) end
                return controller[action_name](controller, ctx)
            end
            
            -- Store metadata for reflection
            self.routes_meta[simple_handler] = {
                controller = controller_name,
                action = action_name
            }
            handler = simple_handler
        end
    end
    self.router:add_route(method:upper(), path, handler)
    return self
end

function Server:get(path, handler) return wrap_handler_with_meta(self, "GET", path, handler) end
function Server:post(path, handler) return wrap_handler_with_meta(self, "POST", path, handler) end
function Server:put(path, handler) return wrap_handler_with_meta(self, "PUT", path, handler) end
function Server:patch(path, handler) return wrap_handler_with_meta(self, "PATCH", path, handler) end
function Server:delete(path, handler) return wrap_handler_with_meta(self, "DELETE", path, handler) end
function Server:options(path, handler) return wrap_handler_with_meta(self, "OPTIONS", path, handler) end
function Server:head(path, handler) return wrap_handler_with_meta(self, "HEAD", path, handler) end

function Server:resources(name, controller_name)
    local controller_module_name = "app.controllers." .. (controller_name or (name .. "_controller"))
    local simple_controller_name = (controller_name or (name .. "_controller"))
    
    -- Capture source location of the resources() call
    local info = debug.getinfo(2, "Sl")
    local source_loc = "unknown"
    if info and info.short_src then
        source_loc = string.format("%s:%d", info.short_src, info.currentline)
    end

    -- Function to safely call a controller method if it exists
    local function call_controller_method(method_name, ctx)
        local ok_require, controller = pcall(require, controller_module_name)
        if not ok_require then
            return ctx:text("Error: Could not load controller '" .. controller_module_name .. "': " .. tostring(controller), 500)
        end
        
        if controller[method_name] then
            return controller[method_name](controller, ctx)
        else
            return ctx:text("Action '" .. method_name .. "' not found in controller '" .. controller_module_name .. "'", 404)
        end
    end

    -- Helper to add route with metadata
    local function add_route(method, path, action)
        local h = function(ctx) return call_controller_method(action, ctx) end
        self.routes_meta[h] = {
            controller = simple_controller_name,
            action = action,
            source = source_loc
        }
        self[method](self, path, h)
    end

    -- Define standard RESTful routes
    add_route("get", "/" .. name, "index")
    
    if not self.config.api_only then
        add_route("get", "/" .. name .. "/new", "new")
    end

    add_route("post", "/" .. name, "create")
    add_route("get", "/" .. name .. "/:id", "show")
    
    if not self.config.api_only then
        add_route("get", "/" .. name .. "/:id/edit", "edit")
    end

    add_route("put", "/" .. name .. "/:id", "update")
    add_route("patch", "/" .. name .. "/:id", "update")
    add_route("delete", "/" .. name .. "/:id", "destroy")
    
    return self
end

-- Helper to wrap a handler with middlewares
function Server:wrap(handler, ...)
    local mws = {...}
    if #mws == 0 then return handler end
    
    local wrapped = function(ctx)
        local index = 1
        
        local function next_mw()
            if index > #mws then
                return handler(ctx)
            end
            
            local mw = mws[index]
            index = index + 1
            
            -- If it's a string, try to resolve it (like self:use)
            -- For now, we assume they are functions
            return mw(ctx, next_mw)
        end
        
        return next_mw()
    end
    
    -- Propagate metadata for CLI route listing
    if type(handler) == "function" and self.routes_meta and self.routes_meta[handler] then
        self.routes_meta[wrapped] = self.routes_meta[handler]
    end
    
    return wrapped
end

-- Route prefixing
function Server:prefix(p) self.router:set_prefix(p) return self end
function Server:clear_prefix() self.router:clear_prefix() return self end

function Server:group(prefix, fn)
    local old_router = self.router
    local group_prefix = prefix or ""
    
    -- Create a proxy for the server that captures routes and applies the group prefix and middlewares
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
        resources = function(p, name, controller_name)
            local controller_module_name = "app.controllers." .. (controller_name or (name .. "_controller"))
            local simple_controller_name = (controller_name or (name .. "_controller"))
            
            -- Capture source location of the resources() call
            local info = debug.getinfo(2, "Sl")
            local source_loc = "unknown"
            if info and info.short_src then
                source_loc = string.format("%s:%d", info.short_src, info.currentline)
            end

            local function call_controller_method(method_name, ctx)
                local ok_require, controller = pcall(require, controller_module_name)
                if not ok_require then return ctx:text("Error: Could not load controller '" .. controller_module_name .. "': " .. tostring(controller), 500) end
                if controller[method_name] then return controller[method_name](controller, ctx)
                else return ctx:text("Action '" .. method_name .. "' not found in controller '" .. controller_module_name .. "'", 404) end
            end

            local function add_route(method, path, action)
                local h = function(ctx) return call_controller_method(action, ctx) end
                self.routes_meta[h] = {
                    controller = simple_controller_name,
                    action = action,
                    source = source_loc
                }
                p[method](p, "/" .. name .. path, h)
            end

            -- path passed to add_route is relative to /resource_name
            add_route("get", "", "index")
            
            if not self.config.api_only then
                add_route("get", "/new", "new")
            end

            add_route("post", "", "create")
            add_route("get", "/:id", "show")
            
            if not self.config.api_only then
                add_route("get", "/:id/edit", "edit")
            end

            add_route("put", "/:id", "update")
            add_route("patch", "/:id", "update")
            add_route("delete", "/:id", "destroy")
            return p
        end
    }, { __index = self })

    local ok, err = pcall(fn, proxy)
    if not ok then error(err) end
    return self
end

-- Executes the middleware chain for a given context
local function run_middlewares(middlewares, ctx, index)
    index = index or 1
    if index > #middlewares then
        return true -- End of chain
    end
    
    local middleware = middlewares[index].handler
    
    local next_fn = function()
        -- If headers were already sent by the current middleware, stop here
        if ctx.stream and ctx.stream.headers_sent then return false end
        return run_middlewares(middlewares, ctx, index + 1)
    end
    
    -- pcall to catch errors inside middleware
    local ok, result = pcall(middleware, ctx, next_fn)
    
    if not ok then
        return false, result -- Actual error occurred
    end
    
    -- If middleware returns false explicitly, or headers were sent, stop the chain
    -- But return true to indicate NO ERROR occurred (just stop)
    if result == false or (ctx.stream and ctx.stream.headers_sent) then
        return "stop", nil
    end
    
    return true
end

-- Main request handler logic
function Server:_handle_request(stream)
    local ctx = context_lib.new(stream, self.config)
    ctx.app = self -- Injetar referência ao app para acesso ao cache, etc.
    
    -- Function to ensure stream is closed before returning
    local function finish()
        pcall(function() 
            -- Try shutdown first (standard for lua-http streams)
            if stream.shutdown then stream:shutdown() 
            elseif stream.close then stream:close() end
        end)
    end

    -- Run global middlewares
    local ok, err = run_middlewares(self.middlewares, ctx)

    if ok == false then
        if self.error_handler then
             pcall(self.error_handler, ctx, err)
        end
        if not stream.headers_sent then
            response_lib.error(stream, 500, "Middleware error", tostring(err))
        end
        finish()
        return
    end

    -- If middleware stopped the chain (ok == "stop") or headers were sent, finish
    if ok == "stop" or stream.headers_sent then
        finish()
        return
    end

    -- Read and set body synchronously before routing to support _method override
    local raw_body = stream:get_body_as_string()
    context_lib.set_body(ctx, raw_body)

    -- Support for _method override in forms (standard Rails behavior)
    if ctx.method == "POST" and type(ctx.body) == "table" and ctx.body._method then
        ctx.method = ctx.body._method:upper()
    end
    
    -- Find the route
    local handler, params, route_path = self.router:match(ctx.method, ctx.path)
    
    -- Handle 404 Not Found
    if not handler then
        if self.not_found_handler then
            pcall(self.not_found_handler, ctx)
        else
            response_lib.error(stream, 404, "Route not found")
        end
        finish()
        return
    end
    
    -- Update context with route info
    ctx.route = route_path
    for k, v in pairs(params) do
      ctx.params[k] = v
    end

    -- Execute the route handler
    local handler_ok, result = pcall(handler, ctx)

    if not handler_ok then
        -- Log the error to terminal (will use __tostring for structured DB errors)
        io.stderr:write(string.format("\n[ERROR] Handler execution failed: %s\n", tostring(result)))
        
        if self.error_handler then
            pcall(self.error_handler, ctx, result)
        else
            response_lib.error(stream, 500, "Handler error", result, nil, self.config)
        end
        finish()
        return
    end
    
    -- If handler returned data and response wasn't sent, send it now
    if not stream.headers_sent then
        if result ~= nil then -- Only send if the handler explicitly returned something
            if type(result) == "table" then
                ctx:json(result, 200)
            else
                ctx:text(tostring(result), 200)
            end
        end
    end
    
    finish()
end

-- Starts the HTTP server
function Server:listen(port, host)
    host = host or self.config.server.host or "0.0.0.0"
    port = port or self.config.server.port or 8080
    
    local ok, my_server = pcall(compat.http_server.listen, {
        host = host,
        port = port,
        reuseaddr = true,
        onstream = function(_, stream)
            xpcall(
                function() self:_handle_request(stream) end,
                function(err)
                    print("PANIC: Unhandled Error: " .. tostring(err))
                    debug.traceback()
                    if not stream.headers_sent then
                        response_lib.error(stream, 500, "Internal Server Error", err, nil, self.config)
                    end
                end
            )
        end,
        onerror = function(server, context, op, err, errno)
            if errno == 98 or tostring(err):find("Address already in use") then
                io.stderr:write("Error: Address already in use\n")
                os.exit(1)
            end
            -- Only print other errors to avoid spamming
            print(string.format("HTTP Server Error: operation=%s, context=%s, error=%s, errno=%s", op, tostring(context), tostring(err), tostring(errno)))
        end
    })

    if not ok then
        io.stderr:write("Error starting server: " .. tostring(my_server) .. "\n")
        os.exit(1)
    end

    print(string.format("Rio server listening on http://%s:%d", host, port))
    
    -- Graceful shutdown (via compat.signal)
    compat.signal.signal(compat.signal.SIGINT, function(signum)
        print("\nShutting down server...")
        if type(my_server) == "table" and my_server.close then my_server:close() end
        print("Server shutdown.")
        os.exit(128 + (signum or 0))
    end)
    
    if type(my_server) == "table" and my_server.loop then
        local loop_ok, loop_err = pcall(function() return my_server:loop() end)
        if not loop_ok then return false, loop_err end
    end
    
    return true
end

-- Sets a server configuration value
function Server:set(key, value)
    self.config[key] = value
    return self
end

-- Bootstrap the application following Rio conventions
function Server:bootstrap()
    local app = self
    local config = self.config

    -- 1. Initialize Database
    local ok_db, db_config = pcall(require, "config.database")
    if ok_db then
        local env = os.getenv("RIO_ENV") or config.environment or "development"
        local env_db_config = db_config[env]
        if env_db_config then
            local db_manager = require("rio.database.manager")
            db_manager.initialize(env_db_config)
            
            -- Configure Query Cache
            if config.query_cache == false then
                db_manager.query_cache_enabled = false
            end
        end
    end

    -- 2. Load Middlewares
    -- Auto-insert query_cache middleware at the top if enabled
    if config.query_cache ~= false then
        app:use(require("rio.middleware.query_cache"))
    end

    local ok_mw, middlewares_cfg = pcall(require, "config.middlewares")
    if ok_mw then
        app:load_middlewares(middlewares_cfg)
    end

    -- 3. Load Initializers
    -- Use a simple ls to find initializers
    local handle = io.popen("ls config/initializers/*.lua 2>/dev/null")
    if handle then
        for file in handle:lines() do
            local initializer_name = file:match("([^/]+)%.lua$")
            if initializer_name then
                pcall(require, "config.initializers." .. initializer_name)
            end
        end
        handle:close()
    end

    -- 4. Load Routes
    local ok_routes, routes_fn = pcall(require, "config.routes")
    if ok_routes and type(routes_fn) == "function" then
        routes_fn(app)
    end

    return self
end

-- Helper to bootstrap and start the server in one call
function Server:run(port, host)
    self:bootstrap()
    
    local p = port or os.getenv("RIO_PORT") or self.config.server.port or 8080
    local h = host or os.getenv("RIO_BINDING") or self.config.server.host or "0.0.0.0"
    
    return self:listen(p, h)
end

return Server
