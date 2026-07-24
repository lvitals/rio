-- rio/lib/rio/cli/commands/middleware.lua

local Command = require("rio.cli.command")
local string_utils = require("rio.utils.string")

local M = {}
local underscore = string_utils.underscore

local CORE_MIDDLEWARES = {
    logger = true,
    security = true,
    cors = true,
    auth = true,
    static = true
}

local function write(ctx, path, content)
    local ok = ctx.files.write(path, content)
    if not ok then
        print("Error: Could not open file for writing: " .. path)
    end
end

local function normalize_name(name)
    return name:match("([^/.]+)%.lua$") or name:match("([^/.]+)$") or name
end

function M.list(ctx)
    ctx.ui.header("Middleware")

    local effective_lua_path, effective_lua_cpath = ctx.get_lua_paths()
    local original_package_path = package.path
    local original_package_cpath = package.cpath

    package.path = "./?.lua;./app/?.lua;./app/?/init.lua;./config/?.lua;./lib/?.lua;" .. ctx.framework_lib_path .. ";" .. effective_lua_path .. ";" .. original_package_path
    package.cpath = effective_lua_cpath .. ";" .. original_package_cpath

    local function restore_paths()
        package.path = original_package_path
        package.cpath = original_package_cpath
    end

    local ok, rio = pcall(require, "rio")
    if not ok then
        ctx.ui.status("Middleware", false, "Could not load 'rio' framework: " .. tostring(rio))
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

    local ok_mw_config, middlewares_cfg = pcall(require, "config.middlewares")
    if ok_mw_config then
        local ok_mw, err_mw = pcall(function()
            for _, middleware_name in ipairs(middlewares_cfg) do
                app:use(middleware_name)
            end
        end)
        if not ok_mw then
            ctx.ui.warn("Error loading middlewares: " .. tostring(err_mw))
            ctx.ui.info("Check your config/middlewares.lua for errors.")
        end
    end

    local active_names = {}
    local active_rows = {}
    for _, mw_entry in ipairs(app.middlewares or {}) do
        local mw = mw_entry.handler
        local info = debug.getinfo(mw, "Sn")
        local name = mw_entry.name or "anonymous"
        local location = "unknown"

        if info then
            if info.short_src then
                local src = info.short_src
                local mw_file = src:match("rio/middleware/(.+)%.lua")
                if name == "anonymous" and mw_file then
                    name = mw_file
                elseif name == "anonymous" then
                    name = src:match("([^/]+)%.lua$") or src
                end
                location = string.format("%s:%d", src:match("([^/]+)$") or src, info.linedefined)
            end

            if name == "anonymous" and info.name and info.name ~= "" then
                name = info.name
            end
        end

        active_names[name] = true
        table.insert(active_rows, {
            name = name,
            source = "config/middlewares.lua",
            location = location
        })
    end

    local available = {}
    local framework_base = ctx.framework_lib_path:match("([^;]+)"):gsub("%?%.lua", ""):gsub("%?$", "")
    local core_mw_path = framework_base .. "rio/middleware"
    for _, file in ipairs(ctx.files.list(core_mw_path, { mode = "file", pattern = "%.lua$" })) do
        local mw_name = file:match("([^/\\]+)%.lua$")
        if mw_name then
            table.insert(available, { name = mw_name, type = "core" })
        end
    end

    for _, file in ipairs(ctx.files.list("app/middleware", { mode = "file", pattern = "%.lua$" })) do
        local mw_name = file:match("([^/\\]+)%.lua$")
        if mw_name then
            table.insert(available, { name = mw_name, type = "local" })
        end
    end

    table.sort(available, function(a, b) return a.name < b.name end)

    ctx.ui.box("Active Middleware Stack", function()
        if #active_rows == 0 then
            ctx.ui.info("No middleware defined.")
        else
            for _, row in ipairs(active_rows) do
                ctx.ui.row(row.name, row.source .. " (" .. row.location .. ")")
            end
        end
        ctx.ui.row("Total active", tostring(#active_rows))
    end)

    ctx.ui.box("Available Middlewares", function()
        if #available == 0 then
            ctx.ui.info("No core or local middleware found.")
            return
        end

        for _, mw in ipairs(available) do
            local status_text = active_names[mw.name] and "active" or "available"
            local type_text = mw.type == "core" and "rio" or "local"
            local description = ""
            local module_path = mw.type == "core" and ("rio.middleware." .. mw.name) or ("app.middleware." .. mw.name)
            local ok_load, mw_mod = pcall(require, module_path)
            if ok_load and type(mw_mod) == "table" and mw_mod.description then
                description = " - " .. mw_mod.description
            end
            ctx.ui.row(mw.name, type_text .. " / " .. status_text .. description)
        end
    end)

    ctx.ui.line("Enable with: rio middleware:use <name>", ctx.colors.dim)
    restore_paths()
end

function M.create_middleware(ctx, name)
    if CORE_MIDDLEWARES[name:lower()] then
        print(ctx.colors.red .. "Error: '" .. name .. "' is a reserved Rio core middleware name." .. ctx.colors.reset)
        print("Please choose a different name for your custom middleware.")
        return
    end

    local mw_dir = "app/middleware"
    ctx.files.ensure_dir(mw_dir)
    local file_path = mw_dir .. "/" .. underscore(name) .. ".lua"

    io.write(ctx.colors.cyan .. "Enter a brief description for this middleware: " .. ctx.colors.reset)
    local description = io.read()
    if not description or description == "" then
        description = "Custom middleware for " .. name
    end

    print(ctx.colors.cyan .. "Generating middleware: " .. ctx.colors.reset .. file_path)

    local content = [[
-- app/middleware/]] .. underscore(name) .. [[.lua

local M = {}

M.description = "]] .. description .. [["

function M.create(options)
    return function(ctx, next_fn)
        -- Pre-processing
        -- Example: print("Starting request...")

        local result, err = next_fn()

        -- Post-processing
        -- Example: print("Finished request.")

        return result, err
    end
end

return M
]]
    write(ctx, file_path, content)
    print(ctx.colors.green .. "Middleware '" .. name .. "' created successfully." .. ctx.colors.reset)
    print("To use it, run: " .. ctx.colors.bold .. "rio middleware:add " .. underscore(name) .. ctx.colors.reset)
end

function M.line_for(name)
    local core_mappings = {
        logger = "app:use(rio.middleware.logger.basic())",
        security = "app:use(rio.middleware.security.headers())",
        cors = "app:use(rio.middleware.cors.default())",
        auth = "app:use(rio.auth.basic())",
        static = "app:use(rio.middleware.static.serve(\"public\"))"
    }

    if core_mappings[name] then
        return core_mappings[name]
    end

    local local_mw_path = "app/middleware/" .. underscore(name) .. ".lua"
    local f = io.open(local_mw_path, "r")
    if f then
        f:close()
        return string.format("app:use(require(\"app.middleware.%s\"))", underscore(name))
    end

    return string.format("app:use(require(\"%s\"))", name)
end

function M.use(ctx, name)
    local config_file = "config/middlewares.lua"
    local f = io.open(config_file, "r")
    if not f then
        print(ctx.colors.red .. "Error: Could not find " .. config_file .. ctx.colors.reset)
        return
    end

    local content = f:read("*a")
    f:close()

    local mw_name = normalize_name(name)
    if content:find("\"" .. mw_name .. "\"", 1, true) or content:find("'" .. mw_name .. "'", 1, true) then
        print(ctx.colors.yellow .. "Notice: Middleware '" .. mw_name .. "' is already enabled." .. ctx.colors.reset)
        return
    end

    local head, body, tail = content:match("(return%s*{)(.-)(})")
    if not head then
        print(ctx.colors.yellow .. "Notice: config/middlewares.lua is using old format. Converting to list format..." .. ctx.colors.reset)
        write(ctx, config_file, "return {\n    \"logger\",\n    \"security\",\n    \"cors\",\n    \"" .. mw_name .. "\"\n}\n")
        print(ctx.colors.green .. "Successfully enabled '" .. mw_name .. "'." .. ctx.colors.reset)
        return
    end

    local new_body = body:gsub("%s*$", "")
    if new_body ~= "" and not new_body:match(",%s*$") then
        new_body = new_body .. ","
    end
    new_body = new_body .. "\n    \"" .. mw_name .. "\"\n"

    write(ctx, config_file, head .. new_body .. tail)
    print(ctx.colors.green .. "Successfully enabled '" .. mw_name .. "' in " .. config_file .. ctx.colors.reset)
end

function M.unuse(ctx, name)
    local config_file = "config/middlewares.lua"
    local f = io.open(config_file, "r")
    if not f then
        print(ctx.colors.red .. "Error: Could not find " .. config_file .. ctx.colors.reset)
        return
    end

    local content = f:read("*a")
    f:close()

    local mw_name = normalize_name(name)
    local new_content, count = content:gsub("[\n%s]*\"" .. mw_name .. "\"%s*,?", "")
    if count == 0 then
        new_content, count = content:gsub("[\n%s]*'" .. mw_name .. "'%s*,?", "")
    end

    if count == 0 then
        print(ctx.colors.yellow .. "Notice: Middleware '" .. mw_name .. "' not found." .. ctx.colors.reset)
        return
    end

    new_content = new_content:gsub(",%s*}", "\n}")
    write(ctx, config_file, new_content)
    print(ctx.colors.green .. "Successfully disabled '" .. mw_name .. "' in " .. config_file .. ctx.colors.reset)
end

function M.rm(ctx, name)
    local local_mw_path = "app/middleware/" .. underscore(name) .. ".lua"
    local f = io.open(local_mw_path, "r")
    if not f then
        print(ctx.colors.red .. "Error: Local middleware file not found: " .. local_mw_path .. ctx.colors.reset)
        return
    end
    f:close()

    io.write(ctx.colors.yellow .. "Are you sure you want to delete the file " .. local_mw_path .. "? (y/N): " .. ctx.colors.reset)
    local answer = io.read()
    if answer and (answer:lower() == "y" or answer:lower() == "yes") then
        M.unuse(ctx, name)
        if os.remove(local_mw_path) then
            print(ctx.colors.green .. "File deleted: " .. local_mw_path .. ctx.colors.reset)
        else
            print(ctx.colors.red .. "Error: Could not delete " .. local_mw_path .. ctx.colors.reset)
        end
    else
        print("Operation cancelled.")
    end
end

function M.command()
    return Command.new({
        name = "middleware",
        help = function(ctx)
            ctx.show_middleware_help()
        end,
        run = function(ctx, invocation)
            local subcommand = invocation.subcommand
            local name = invocation.args[1]

            if subcommand == "create" then
                if not name then
                    ctx.ui.status("Middleware", false, "'middleware:create' requires a name")
                    ctx.show_middleware_help()
                    return true
                end
                M.create_middleware(ctx, name)
            elseif subcommand == "use" or subcommand == "add" then
                if not name then
                    ctx.ui.status("Middleware", false, "'middleware:use' requires a name")
                    ctx.show_middleware_help()
                    return true
                end
                if subcommand == "add" then
                    ctx.ui.warn("'middleware:add' is deprecated. Use 'middleware:use' instead.")
                end
                M.use(ctx, name)
            elseif subcommand == "unuse" or subcommand == "remove" or subcommand == "delete" then
                if not name then
                    ctx.ui.status("Middleware", false, "'middleware:unuse' requires a name")
                    ctx.show_middleware_help()
                    return true
                end
                if subcommand == "remove" or subcommand == "delete" then
                    ctx.ui.warn("'middleware:" .. subcommand .. "' for disabling is deprecated. Use 'middleware:unuse' instead.")
                    ctx.ui.warn("If you want to delete the local file, use 'middleware:rm'.")
                end
                M.unuse(ctx, name)
            elseif subcommand == "rm" then
                if not name then
                    ctx.ui.status("Middleware", false, "'middleware:rm' requires a name")
                    ctx.show_middleware_help()
                    return true
                end
                M.rm(ctx, name)
            else
                M.list(ctx)
            end
            return true
        end
    })
end

return M
