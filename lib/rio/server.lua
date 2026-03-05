-- rio/lib/rio/server.lua
-- Main Server engine for the Rio framework.
-- Handles HTTP requests, Middlewares, Routing, and WebSocket Upgrades.

local router_lib = require("rio.core.router")
local context_lib = require("rio.core.context")
local response_lib = require("rio.core.response")
local cache_lib = require("rio.cache")
local compat = require("rio.utils.compat")
local string_utils = require("rio.utils.string")
local c = compat.colors

local Server = {}
Server.__index = Server

function Server.new(config)
    config = config or {}
    local cache_store = config.cache_store or "file"
    local perform_caching = config.perform_caching ~= false
    local adapter, options
    if not perform_caching then adapter = "null"; options = {}
    elseif type(cache_store) == "table" then adapter = cache_store[1]; options = cache_store[2] or {}
    else adapter = cache_store; options = { dir = config.cache_dir, namespace = config.app_name } end

    return setmetatable({
        router = router_lib.new(),
        middlewares = {},
        routes_meta = setmetatable({}, { __mode = "k" }),
        cache = cache_lib.new(adapter, options),
        config = config
    }, Server)
end

function Server:use(middleware, options)
    local h = nil
    if type(middleware) == "string" then
        local rio = require("rio")
        h = rio.middleware[middleware] or require("app.middleware." .. middleware)
    else
        h = middleware
    end

    -- Extract functional handler from middleware table/factory
    if type(h) == "table" then
        if h.basic then h = h.basic()
        elseif h.headers then h = h.headers()
        elseif h.create then h = h.create(self, options)
        elseif h.default then h = h.default() end
    end

    if type(h) == "function" then
        table.insert(self.middlewares, h)
    end
    return self
end

function Server:wrap(handler, ...)
    local local_mws = {...}
    local final_h = self:_to_handler(handler)
    if #local_mws == 0 then return final_h end
    
    return function(ctx)
        local idx = 1
        local function nxt()
            if idx > #local_mws then return final_h(ctx) end
            local mw = local_mws[idx]; idx = idx + 1
            return mw(ctx, nxt)
        end
        return nxt()
    end
end

function Server:_to_handler(handler)
    if type(handler) == "string" then
        local cn, an = handler:match("^([^#@]+)[#@]([^#@]+)$")
        if cn and an then
            local sh = function(ctx)
                local mod = string_utils.underscore(cn)
                if not mod:find("_controller$") then mod = mod .. "_controller" end
                local ctrl = require("app.controllers." .. mod)
                return ctrl[an](ctrl, ctx)
            end
            self.routes_meta[sh] = { controller = cn, action = an }
            return sh
        end
        if not handler:find("[#@]") then
            return function(wb, ctx)
                local mod_name = string_utils.underscore(handler)
                if not mod_name:find("_channel$") then mod_name = mod_name .. "_channel" end
                
                local ok, Chan = pcall(require, "app.channels." .. mod_name)
                if not ok then 
                    io.stderr:write("Channel Load Error: " .. tostring(Chan) .. "\n")
                    return wb:send_close() 
                end
                
                local inst = setmetatable({ wb = wb, ctx = ctx, _unsubs = {} }, { __index = Chan })
                function inst:stream_from(name)
                    local un = require("rio.cable").subscribe(name, wb)
                    table.insert(self._unsubs, un)
                end
                
                if inst.subscribed then pcall(inst.subscribed, inst) end
                while true do
                    local d, t = wb:recv_frame()
                    if not d then break end
                    if d ~= true and t == "text" then
                        local ok_j, m = pcall(require("rio.utils.compat").json.decode, d)
                        if ok_j and m.action and inst[m.action] then pcall(inst[m.action], inst, m.data) end
                    elseif t == "close" then break end
                end
                if inst.unsubscribed then pcall(inst.unsubscribed, inst) end
                for _, u in ipairs(inst._unsubs) do pcall(u) end
                return wb:send_close()
            end
        end
    end
    return handler
end

function Server:get(p, h) self.router:add_route("GET", p, self:_to_handler(h)); return self end
function Server:post(p, h) self.router:add_route("POST", p, self:_to_handler(h)); return self end
function Server:put(p, h) self.router:add_route("PUT", p, self:_to_handler(h)); return self end
function Server:patch(p, h) self.router:add_route("PATCH", p, self:_to_handler(h)); return self end
function Server:delete(p, h) self.router:add_route("DELETE", p, self:_to_handler(h)); return self end
function Server:ws(p, h) self.router:add_route("WS", p, self:_to_handler(h)); return self end

function Server:resources(name, cn)
    local controller = cn or (name .. "_controller")
    local function add(m, a, p) self[m](self, "/" .. name .. (p or ""), controller .. "@" .. a) end
    add("get", "index"); add("get", "new", "/new"); add("post", "create")
    add("get", "show", "/:id"); add("get", "edit", "/:id/edit")
    add("put", "update", "/:id"); add("patch", "update", "/:id"); add("delete", "destroy", "/:id")
    return self
end

function Server:group(prefix, fn)
    local proxy = setmetatable({
        _middlewares = {},
        use = function(s, mw) table.insert(s._middlewares, mw); return s end,
        get = function(s, p, h) self:get(prefix .. p, self:wrap(h, compat.unpack(s._middlewares))); return s end,
        post = function(s, p, h) self:post(prefix .. p, self:wrap(h, compat.unpack(s._middlewares))); return s end,
        put = function(s, p, h) self:put(prefix .. p, self:wrap(h, compat.unpack(s._middlewares))); return s end,
        patch = function(s, p, h) self:patch(prefix .. p, self:wrap(h, compat.unpack(s._middlewares))); return s end,
        delete = function(s, p, h) self:delete(prefix .. p, self:wrap(h, compat.unpack(s._middlewares))); return s end,
        resources = function(s, name, cn)
            local ctrl = cn or (name .. "_controller")
            local function add(m, a, p) s[m](s, "/" .. name .. (p or ""), ctrl .. "@" .. a) end
            add("get", "index"); add("get", "new", "/new"); add("post", "create")
            add("get", "show", "/:id"); add("get", "edit", "/:id/edit")
            add("put", "update", "/:id"); add("patch", "update", "/:id"); add("delete", "destroy", "/:id")
            return s
        end
    }, { __index = self })
    fn(proxy)
    return self
end

function Server:_process_request(adapter)
    require("rio.database.manager").clear_query_cache()
    local ctx = context_lib.new(adapter, self.config); ctx.app = self
    local upgrade = ctx:getHeader("upgrade")
    if upgrade and upgrade:lower() == "websocket" then
        local h = self.router:match("WS", ctx.path)
        if h and adapter.websocket_upgrade then return adapter:websocket_upgrade(h, ctx) end
    end
    
    local function run_handler()
        local index = 1
        local function next_mw()
            if index > #self.middlewares then
                local h, params, rp = self.router:match(ctx.method, ctx.path)
                if not h then return ctx:text("Not Found", 404) end
                ctx.route = rp; for k, v in pairs(params) do ctx.params[k] = v end
                return h(ctx)
            end
            local mw = self.middlewares[index]; index = index + 1
            return mw(ctx, next_mw)
        end
        return next_mw()
    end

    context_lib.set_body(ctx, adapter:get_body())
    
    -- Method Override Support
    if ctx.method == "POST" then
        local overriden = nil
        if ctx.body and ctx.body._method then overriden = tostring(ctx.body._method):upper()
        elseif ctx.query and ctx.query._method then overriden = tostring(ctx.query._method):upper() end
        if overriden == "PUT" or overriden == "PATCH" or overriden == "DELETE" then
            ctx.method = overriden
        end
    end

    local ok, res = pcall(run_handler)
    if not ok then io.stderr:write(c.red .. "Internal Error: " .. tostring(res) .. c.reset .. "\n"); ctx:text("Internal Error", 500)
    elseif type(res) == "string" then ctx:text(res) end
end

function Server:listen(port, host)
    local h = host or "0.0.0.0"; local p = port or 8080
    local ok, inst = pcall(compat.http_server.listen, {
        host = h, port = p, reuseaddr = true,
        onstream = function(_, stream) self:_process_request(require("rio.core.adapters.standalone").new(stream)) end
    })
    if not ok then return false end
    print(string.format("%sRio Framework%s listening on %shttp://%s:%d%s", c.bold .. c.green, c.reset, c.cyan, h, p, c.reset))
    if type(inst) == "table" and inst.loop then while true do pcall(inst.loop, inst); os.execute("sleep 0.1") end end
    return true
end

function Server:run(port, host)
    local cwd = os.getenv("PWD") or "."; package.path = cwd .. "/?.lua;" .. cwd .. "/?/init.lua;" .. package.path
    pcall(function() local mw = require("config.middlewares"); if type(mw) == "table" then for _, m in ipairs(mw) do self:use(m) end end end)
    pcall(function() require("config.routes")(self) end)
    return self:listen(port, host)
end

return Server
