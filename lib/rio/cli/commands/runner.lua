-- rio/lib/rio/cli/commands/runner.lua

local Command = require("rio.cli.command")

local M = {}

local function parse_options(args, ui)
    local options = {}
    local code_or_file = nil
    local script_args = {}
    local i = 1

    while i <= #args do
        local arg = args[i]
        if not code_or_file then
            if arg == "-e" or arg == "--environment" then
                i = i + 1
                options.environment = args[i]
            elseif arg:match("^%-%-environment=(.+)$") then
                options.environment = arg:match("^%-%-environment=(.+)$")
            elseif arg == "--skip-executor" then
                options.skip_executor = true
            elseif arg:match("^%-") then
                ui.warn("Unknown runner option: " .. arg)
            else
                code_or_file = arg
            end
        else
            table.insert(script_args, arg)
        end
        i = i + 1
    end

    return options, code_or_file, script_args
end

function M.run(ctx, runner_options, code_or_file, script_args)
    runner_options = runner_options or {}

    local ok_project = io.open("config/application.lua", "r")
    if ok_project then
        ok_project:close()
    else
        print(ctx.colors.red .. "Error: Not an Rio project. 'rio runner' must be run from the project root." .. ctx.colors.reset)
        return
    end

    if not code_or_file then
        print(ctx.colors.red .. "Error: No code or file provided to 'rio runner'." .. ctx.colors.reset)
        return
    end

    local env = runner_options.environment or os.getenv("RIO_ENV") or "development"
    local skip_executor = runner_options.skip_executor or false

    local effective_lua_path, effective_lua_cpath = ctx.get_lua_paths()
    _G.RIO_ENV = env
    package.path = effective_lua_path
    package.cpath = effective_lua_cpath

    if not skip_executor then
        local models = {}
        for _, path in ipairs(ctx.files.list("app/models", { mode = "file", pattern = "%.lua$" })) do
            local model = ctx.files.basename(path):match("(.+)%.lua$")
            if model then
                table.insert(models, model)
            end
        end

        local bootstrap_content = {
            "-- Runner bootstrap",
            "package.path = './app/?.lua;./app/?/init.lua;./config/?.lua;./lib/?.lua;' .. '" .. ctx.framework_lib_path .. ";' .. package.path",
            "local rio = require('rio')",
            "local db_manager = require('rio.database.manager')",
            "local ok_db_config, db_config = pcall(require, 'config.database')",
            "",
            "-- Initialize Database",
            "local env = '" .. env .. "'",
            "_G.RIO_ENV = env",
            "if ok_db_config and db_config[env] then db_manager.initialize(db_config[env]) end",
            "",
            "-- Set global 'arg' table for the runner script",
            "arg = " .. (function()
                local parts = {}
                for i, arg in ipairs(script_args or {}) do
                    table.insert(parts, "[" .. i .. "] = \"" .. arg:gsub("\"", "\\\"") .. "\"")
                end
                return "{" .. table.concat(parts, ", ") .. "}"
            end)(),
            "",
            "-- Load Models into global scope",
        }

        for _, model in ipairs(models) do
            local string_utils = require("rio.utils.string")
            local class_name = string_utils.camel_case(model)
            table.insert(bootstrap_content, string.format("pcall(function() %s = require('app.models.%s') end)", class_name, model))
        end

        table.insert(bootstrap_content, [[
-- App object for route testing
local ok_app_config, app_config = pcall(require, "config.application")
if not ok_app_config or type(app_config) ~= "table" then
    app_config = { server = { port = 8080, host = "0.0.0.0" } }
end
app = rio.new(app_config)
local ok_routes, routes_fn = pcall(require, "config.routes")
if ok_routes then routes_fn(app) end

-- Pretty print helper
function pp(val)
    local string_utils = require("rio.utils.string")
    local mt = getmetatable(val)
    if mt and mt.__tostring then
        print(tostring(val))
    else
        print(string_utils.inspect(val))
    end
end
]])

        local chunk, err = load(table.concat(bootstrap_content, "\n"))
        if chunk then
            local status, result = pcall(chunk)
            if not status then
                print(ctx.colors.red .. "Error during application bootstrap: " .. tostring(result) .. ctx.colors.reset)
                return
            end
        else
            print(ctx.colors.red .. "Error loading application environment: " .. tostring(err) .. ctx.colors.reset)
            return
        end
    else
        _G.arg = script_args
    end

    local f = io.open(code_or_file, "r")
    if f then
        local file_content = f:read("*a")
        f:close()
        local runner_chunk, runner_err = load(file_content, "@" .. code_or_file)
        if runner_chunk then
            local status, result = pcall(runner_chunk)
            if not status then
                print(ctx.colors.red .. "Error executing file '" .. code_or_file .. "': " .. tostring(result) .. ctx.colors.reset)
            end
        else
            print(ctx.colors.red .. "Error loading file '" .. code_or_file .. "': " .. tostring(runner_err) .. ctx.colors.reset)
        end
    else
        local runner_chunk, runner_err = load(code_or_file, "=(runner)")
        if runner_chunk then
            local status, result = pcall(runner_chunk)
            if not status then
                print(ctx.colors.red .. "Error executing code: " .. tostring(result) .. ctx.colors.reset)
            end
        else
            print(ctx.colors.red .. "Error loading code: " .. tostring(runner_err) .. ctx.colors.reset)
        end
    end
end

function M.command()
    return Command.new({
        name = "runner",
        help = function(ctx)
            ctx.show_runner_help()
        end,
        run = function(ctx, invocation)
            local options, code_or_file, script_args = parse_options(invocation.args, ctx.ui)
            M.run(ctx, options, code_or_file, script_args)
            return true
        end
    })
end

return M
