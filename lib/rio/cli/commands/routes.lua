-- rio/lib/rio/cli/commands/routes.lua

local Command = require("rio.cli.command")

local M = {}

local function parse_options(args, ui)
    local options = {}
    local i = 1
    while i <= #args do
        local arg = args[i]
        if arg == "-c" or arg == "--controller" then
            i = i + 1
            options.controller = args[i]
        elseif arg:match("^%-%-controller=(.+)$") then
            options.controller = arg:match("^%-%-controller=(.+)$")
        elseif arg == "-g" or arg == "--grep" then
            i = i + 1
            options.grep = args[i]
        elseif arg:match("^%-%-grep=(.+)$") then
            options.grep = arg:match("^%-%-grep=(.+)$")
        elseif arg == "-E" or arg == "--expanded" then
            options.expanded = true
        else
            ui.warn("Unknown routes option: " .. arg)
        end
        i = i + 1
    end
    return options
end

local function extract_controller_action(source, line_num)
    if not source or source:sub(1, 1) ~= "@" then return "unknown" end
    local path = source:sub(2)
    local f = io.open(path, "r")
    if not f then return "unknown" end

    local current_line = 0
    local content = nil
    for line in f:lines() do
        current_line = current_line + 1
        if current_line == line_num then
            content = line
            break
        end
    end
    f:close()

    if content then
        local ctrl, action = content:match("([%w_]+Controller)[%.:]([%w_]+)")
        if ctrl and action then
            return ctrl .. "#" .. action
        end

        local c, a = content:match("([A-Z][%w_]+)[%.:]([%w_]+)")
        if c and a then
            return c .. "#" .. a
        end
    end
    return "anonymous"
end

local function collect_routes(app, options, original_package_path)
    local route_list = {}
    local methods = {"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"}

    for _, method in ipairs(methods) do
        local routes = app.router.routes[method] or {}
        for _, route in ipairs(routes) do
            local info = debug.getinfo(route.handler, "S")
            local line = debug.getinfo(route.handler, "l").currentline
            local source_loc = ""
            local controller_action = "anonymous"

            if type(route.handler) == "function" and app.routes_meta and app.routes_meta[route.handler] then
                local meta = app.routes_meta[route.handler]
                if meta.controller and meta.action then
                    controller_action = meta.controller .. "#" .. meta.action
                end
                if meta.source then
                    source_loc = meta.source
                end
            end

            if (source_loc == "" or controller_action == "anonymous") and info and info.source then
                local short_src = info.short_src
                if short_src:find(original_package_path, 1, true) then
                    short_src = "..." .. short_src:sub(-30)
                end

                if source_loc == "" then
                    source_loc = string.format("%s:%d", short_src, line)
                end

                if controller_action == "anonymous" then
                    controller_action = extract_controller_action(info.source, line)
                end
            end

            local entry = {
                prefix = route.name or "",
                verb = method,
                uri = route.path,
                controller = controller_action,
                source = source_loc
            }

            local include = true
            if options.controller then
                local search = options.controller:lower()
                include = entry.controller:lower():find(search, 1, true) ~= nil
            end

            if options.grep and include then
                local search = options.grep:lower()
                include = entry.verb:lower():find(search, 1, true)
                    or entry.uri:lower():find(search, 1, true)
                    or entry.controller:lower():find(search, 1, true)
                    or entry.prefix:lower():find(search, 1, true)
            end

            if include then
                table.insert(route_list, entry)
            end
        end
    end

    return route_list
end

local function render_routes(ctx, route_list, expanded)
    if expanded then
        for i, route in ipairs(route_list) do
            ctx.ui.box("Route " .. i, function()
                ctx.ui.row("Prefix", route.prefix ~= "" and route.prefix or "-")
                ctx.ui.row("Verb", route.verb)
                ctx.ui.row("URI Pattern", route.uri)
                ctx.ui.row("Controller#Action", route.controller)
                ctx.ui.row("Source Location", route.source ~= "" and route.source or "-")
            end)
        end
        ctx.ui.line("Total routes: " .. #route_list, ctx.colors.dim)
        return
    end

    ctx.ui.box("Defined Routes", function()
        local function fit(value, width)
            value = tostring(value or "")
            if #value <= width then return value end
            if width <= 3 then return value:sub(1, width) end
            return value:sub(1, width - 3) .. "..."
        end

        local fmt = "%-8s  %-6s  %-30s  %-24s"
        ctx.ui.text(string.format(fmt, "Prefix", "Verb", "URI Pattern", "Controller#Action"), ctx.colors.bold .. ctx.colors.white)
        ctx.ui.text(string.format(fmt, string.rep("-", 8), string.rep("-", 6), string.rep("-", 30), string.rep("-", 24)), ctx.colors.dim)

        for _, r in ipairs(route_list) do
            ctx.ui.text(string.format(
                fmt,
                fit(r.prefix ~= "" and r.prefix or "-", 8),
                fit(r.verb, 6),
                fit(r.uri, 30),
                fit(r.controller, 24)
            ), ctx.colors.white)
        end
    end)
    ctx.ui.line("Total routes: " .. #route_list, ctx.colors.dim)
end

function M.run(ctx, options)
    options = options or {}
    ctx.ui.header("Routes")

    local effective_lua_path, effective_lua_cpath = ctx.get_lua_paths()
    local original_package_path = package.path
    local original_package_cpath = package.cpath

    if not ctx.files.exists("config/routes.lua") then
        local cwd = ctx.files.current_dir() or "."

        ctx.ui.status("Routes", false, "config/routes.lua was not found")
        ctx.ui.box("Project Directory", function()
            ctx.ui.row("Current directory", cwd)
            ctx.ui.row("Expected file", "config/routes.lua")
        end)
        ctx.ui.line("Run this command from a Rio project root, or create one with: rio new <project_name>", ctx.colors.dim)
        return
    end

    package.path = "./?.lua;./app/?.lua;./app/?/init.lua;./config/?.lua;./lib/?.lua;" .. ctx.framework_lib_path .. ";" .. effective_lua_path .. ";" .. original_package_path
    package.cpath = effective_lua_cpath .. ";" .. original_package_cpath

    local function restore_paths()
        package.path = original_package_path
        package.cpath = original_package_cpath
    end

    local ok, rio = pcall(require, "rio")
    if not ok then
        ctx.ui.status("Routes", false, "Could not load 'rio' framework: " .. tostring(rio))
        restore_paths()
        return
    end

    local ok_config, application_config = pcall(require, "config.application")
    if not ok_config or type(application_config) ~= "table" then
        application_config = { server = { port = 8080, host = "0.0.0.0" }, environment = "development" }
    end

    local app = rio.new({
        server = application_config.server or { port = 8080, host = "0.0.0.0" },
        environment = application_config.environment or "development"
    })

    local ok_routes, routes_fn = pcall(require, "config.routes")
    if not ok_routes then
        ctx.ui.status("Routes", false, "Could not load config/routes.lua")
        ctx.ui.info(tostring(routes_fn):match("^[^\n]+") or tostring(routes_fn))
        restore_paths()
        return
    end

    local ok_exec, err_exec = pcall(routes_fn, app)
    if not ok_exec then
        ctx.ui.status("Routes", false, "Error executing config/routes.lua")
        ctx.ui.info(tostring(err_exec))
        restore_paths()
        return
    end

    local route_list = collect_routes(app, options, original_package_path)
    if #route_list == 0 then
        ctx.ui.status("Routes", false, "No routes found matching your criteria")
        restore_paths()
        return
    end

    render_routes(ctx, route_list, options.expanded)
    restore_paths()
end

function M.command()
    return Command.new({
        name = "routes",
        help = function(ctx)
            ctx.show_routes_help()
        end,
        run = function(ctx, invocation)
            M.run(ctx, parse_options(invocation.args, ctx.ui))
            return true
        end
    })
end

return M
