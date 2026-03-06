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
    local h = nil; local n = "anonymous"
    if type(middleware) == "string" then
        n = middleware; local rio = require("rio"); local cmw = rio.middleware[middleware]
        if cmw then
            if type(cmw) == "table" then
                if cmw.basic then h = cmw.basic()
                elseif cmw.headers then h = cmw.headers()
                elseif cmw.create then h = cmw.create(self, options)
                elseif cmw.default then h = cmw.default() end
            else h = cmw end
        end
        if not h then local ok, lmw = pcall(require, "app.middleware." .. middleware); if ok then h = lmw end end
    elseif type(middleware) == "function" then h = middleware end
    if h then table.insert(self.middlewares, { handler = h, name = n }) end
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
            if type(mw) == "table" and mw.handler then return mw.handler(ctx, nxt)
            else return mw(ctx, nxt) end
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
                local base = handler:gsub("[Cc]hannel$", ""):lower()
                local ok, Chan = pcall(require, "app.channels." .. base .. "_channel")
                if not ok then 
                    io.stderr:write(c.red .. "Channel Error: " .. tostring(Chan) .. c.reset .. "\n")
                    return wb:send_close() 
                end
                local inst = setmetatable({ wb = wb, ctx = ctx, _unsubs = {} }, { __index = Chan })
                function inst:stream_from(name)
                    local un = require("rio.cable").subscribe(name, self.wb)
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
    self.router:push_prefix(prefix)
    local proxy = setmetatable({
        _mws = {},
        use = function(s, mw) table.insert(s._mws, mw); return s end,
        get = function(s, p, h) self:get(p, self:wrap(h, compat.unpack(s._mws))); return s end,
        post = function(s, p, h) self:post(p, self:wrap(h, compat.unpack(s._mws))); return s end,
        put = function(s, p, h) self:put(p, self:wrap(h, compat.unpack(s._mws))); return s end,
        patch = function(s, p, h) self:patch(p, self:wrap(h, compat.unpack(s._mws))); return s end,
        delete = function(s, p, h) self:delete(p, self:wrap(h, compat.unpack(s._mws))); return s end,
        resources = function(s, name, cn)
            local function radd(m, a, p) s[m](s, "/" .. name .. (p or ""), (cn or (name .. "_controller")) .. "@" .. a) end
            radd("get", "index"); radd("get", "new", "/new"); radd("post", "create")
            radd("get", "show", "/:id"); radd("get", "edit", "/:id/edit")
            radd("put", "update", "/:id"); radd("patch", "update", "/:id"); radd("delete", "destroy", "/:id")
            return s
        end
    }, { __index = self })
    fn(proxy)
    self.router:pop_prefix()
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
    local function run()
        local index = 1
        local function nxt()
            if index > #self.middlewares then
                local h, params, rp = self.router:match(ctx.method, ctx.path)
                if not h then return ctx:text("Not Found", 404) end
                ctx.route = rp; for k, v in pairs(params) do ctx.params[k] = v end
                return h(ctx)
            end
            local m = self.middlewares[index]; index = index + 1; return m.handler(ctx, nxt)
        end
        return nxt()
    end
    context_lib.set_body(ctx, adapter:get_body())
    if ctx.method == "POST" then
        local ov = nil
        if ctx.body and ctx.body._method then ov = tostring(ctx.body._method):upper()
        elseif ctx.query and ctx.query._method then ov = tostring(ctx.query._method):upper() end
        if ov == "PUT" or ov == "PATCH" or ov == "DELETE" then ctx.method = ov end
    end
    local ok, res = pcall(run)
    if not ok then io.stderr:write(c.red .. "Internal Error: " .. tostring(res) .. c.reset .. "\n"); ctx:text("Internal Error", 500)
    elseif type(res) == "string" then ctx:text(res) end
end

function Server:handle_ngx()
    local adapter = require("rio.core.adapters.openresty").new()
    return self:_process_request(adapter)
end

function Server:listen(port, host)
    local h = host or os.getenv("RIO_BINDING") or (self.config.server and self.config.server.host) or "0.0.0.0"
    local p = tonumber(port or os.getenv("RIO_PORT") or (self.config.server and self.config.server.port)) or 8080
    local ok, inst = pcall(compat.http_server.listen, {
        host = h, port = p, reuseaddr = true,
        onstream = function(_, stream) self:_process_request(require("rio.core.adapters.standalone").new(stream)) end
    })
    if not ok then return false end
    print(string.format("%sRio Framework%s listening on %shttp://%s:%d%s", c.bold .. c.green, c.reset, c.cyan, h, p, c.reset))
    if type(inst) == "table" and inst.loop then while true do pcall(inst.loop, inst); os.execute("sleep 0.1") end end
    return true
end

function Server:bootstrap()
    local ok_db, db_config = pcall(require, "config.database")
    if ok_db then
        local env = os.getenv("RIO_ENV") or self.config.environment or "development"
        if db_config[env] then require("rio.database.manager").initialize(db_config[env]) end
    end
    local ok_mw, mw_cfg = pcall(require, "config.middlewares")
    if ok_mw then for _, m in ipairs(mw_cfg) do self:use(m) end end
    local ok_routes, routes_fn = pcall(require, "config.routes")
    if ok_routes then routes_fn(self) end
    return self
end

function Server:run(port, host)
    local cwd = os.getenv("PWD") or "."; package.path = cwd .. "/?.lua;" .. cwd .. "/?/init.lua;" .. package.path
    self:bootstrap()
    return self:listen(port, host)
end

return Server
