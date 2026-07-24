-- rio/lib/rio/cli/commands/server.lua

local Command = require("rio.cli.command")
local compat = require("rio.utils.compat")

local M = {}

local function parse_options(args, ui)
    local options = {}
    local i = 1
    while i <= #args do
        local arg = args[i]
        if arg == "-p" or arg == "--port" then
            i = i + 1
            options.port = args[i]
        elseif arg:match("^%-%-port=(.+)$") then
            options.port = arg:match("^%-%-port=(.+)$")
        elseif arg == "-b" or arg == "--binding" then
            i = i + 1
            options.binding = args[i]
        elseif arg:match("^%-%-binding=(.+)$") then
            options.binding = arg:match("^%-%-binding=(.+)$")
        elseif arg == "-e" or arg == "--environment" then
            i = i + 1
            options.environment = args[i]
        elseif arg:match("^%-%-environment=(.+)$") then
            options.environment = arg:match("^%-%-environment=(.+)$")
        elseif arg == "-d" or arg == "--daemon" then
            options.daemon = true
        elseif arg == "--pid" then
            i = i + 1
            options.pid = args[i]
        elseif arg:match("^%-%-pid=(.+)$") then
            options.pid = arg:match("^%-%-pid=(.+)$")
        else
            ui.warn("Unknown server option: " .. arg)
        end
        i = i + 1
    end
    return options
end

function M.run(ctx, server_options)
    server_options = server_options or {}

    local initial_port = tonumber(server_options.port) or 8080
    local host = server_options.binding or "0.0.0.0"
    local environment = server_options.environment or "development"
    local current_port = initial_port

    local effective_lua_path, effective_lua_cpath = ctx.get_lua_paths()
    local lua_bin = compat.get_lua_bin()
    local command_template = "LUA_PATH='%s' " ..
                             "LUA_CPATH='%s' " ..
                             "RIO_ENV='%s' " ..
                             "RIO_BINDING='%s' " ..
                             "RIO_PORT='%s' " ..
                             lua_bin .. " app.lua"

    while true do
        if server_options.daemon then
            print(ctx.colors.cyan .. "Starting Rio server in background on port " .. current_port .. "..." .. ctx.colors.reset)
            local log_dir = "log"
            ctx.create_dir_if_not_exists(log_dir)
            local command = string.format(command_template, effective_lua_path, effective_lua_cpath, environment, host, current_port)
            command = command .. " > " .. log_dir .. "/rio_server.log 2>&1 & echo $!"

            local handle = io.popen(command)
            local pid = handle:read("*a"):gsub("%s+", "")
            handle:close()

            if pid and pid ~= "" then
                if server_options.pid then
                    local pid_dir = server_options.pid:match("(.+)/[^/]+$")
                    if pid_dir then ctx.create_dir_if_not_exists(pid_dir) end
                    local f = io.open(server_options.pid, "w")
                    if f then
                        f:write(pid)
                        f:close()
                    end
                end

                os.execute("sleep 1")

                if not ctx.is_port_free(current_port, host) then
                    print(ctx.colors.green .. "Server started in background on port " .. current_port .. " (PID: " .. pid .. ")" .. ctx.colors.reset)
                    return
                end

                print(ctx.colors.red .. "Error: Server failed to start on port " .. current_port .. ctx.colors.reset)
                return
            end

            print(ctx.colors.red .. "Error: Failed to capture PID" .. ctx.colors.reset)
            return
        end

        if not ctx.is_port_free(current_port, host) then
            print("\n" .. ctx.colors.yellow .. "⚠️  Port " .. current_port .. " is already in use by another process on " .. host .. "." .. ctx.colors.reset)

            math.randomseed(os.time())
            local next_port = math.random(8000, 9999)

            io.write(ctx.colors.bold .. "Would you like to start another instance on a random port (" .. next_port .. ")? (y/N): " .. ctx.colors.reset)
            local answer = io.read()

            if answer and (answer:lower() == "y" or answer:lower() == "yes") then
                current_port = next_port
            else
                print("Exiting...")
                return
            end
        else
            local command = string.format(command_template, effective_lua_path, effective_lua_cpath, environment, host, current_port)
            os.execute(command)
            return
        end
    end
end

function M.command()
    return Command.new({
        name = "server",
        help = function(ctx)
            ctx.show_server_help()
        end,
        run = function(ctx, invocation)
            M.run(ctx, parse_options(invocation.args, ctx.ui))
            return true
        end
    })
end

return M
