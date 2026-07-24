-- rio/lib/rio/cli/commands/tmp.lua

local Command = require("rio.cli.command")

local M = {}

local TMP_DIRS = { "tmp/cache", "tmp/sockets", "tmp/pids", "tmp/screenshots" }

local function stop_server_by_pid(pid_path)
    local f = io.open(pid_path, "r")
    if f then
        local pid = f:read("*a"):gsub("%s+", "")
        f:close()
        if pid and pid ~= "" then
            print("Stopping server with PID " .. pid .. "...")
            os.execute("kill -- -" .. pid .. " 2>/dev/null || kill " .. pid .. " 2>/dev/null")
            os.execute("sleep 1")
        end
        os.remove(pid_path)
    end
end

local function clear_dir(path)
    print("Clearing " .. path .. "...")
    if path == "tmp/pids" then
        local handle = io.popen("ls tmp/pids/*.pid 2>/dev/null")
        if handle then
            for pid_file in handle:lines() do
                stop_server_by_pid(pid_file)
            end
            handle:close()
        end
    else
        os.execute("rm -rf " .. path .. "/*")
    end
end

local function create_tmp_dirs()
    print("Creating tmp directories...")
    for _, dir in ipairs(TMP_DIRS) do
        os.execute("mkdir -p " .. dir)
        print("  Created " .. dir)
    end
end

function M.run(ctx, subcommand)
    if subcommand == "create" then
        create_tmp_dirs()
    elseif subcommand == "clear" then
        clear_dir("tmp/cache")
        clear_dir("tmp/sockets")
        clear_dir("tmp/screenshots")
        clear_dir("tmp/pids")
    elseif subcommand == "cache:clear" then
        clear_dir("tmp/cache")
    elseif subcommand == "sockets:clear" then
        clear_dir("tmp/sockets")
    elseif subcommand == "screenshots:clear" then
        clear_dir("tmp/screenshots")
    elseif subcommand == "pids:clear" then
        clear_dir("tmp/pids")
    else
        ctx.ui.status("Temporary files", false, "Unknown subcommand '" .. tostring(subcommand or "") .. "'")
        ctx.show_tmp_help()
    end
end

function M.command()
    return Command.new({
        name = "tmp",
        help = function(ctx)
            ctx.show_tmp_help()
        end,
        run = function(ctx, invocation)
            if not invocation.subcommand then
                ctx.ui.status("Temporary files", false, "Subcommand is required")
                ctx.show_tmp_help()
                return true
            end
            M.run(ctx, invocation.subcommand)
            return true
        end
    })
end

return M
