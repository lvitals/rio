-- rio/lib/rio/cli/commands/test.lua

local Command = require("rio.cli.command")
local compat = require("rio.utils.compat")
local shell = require("rio.cli.shell")
local test_command = require("rio.cli.commands.test_command")

local M = {}

function M.run(ctx, test_args)
    ctx.ui.header("Running Rio tests with Busted")
    local effective_lua_path, effective_lua_cpath = ctx.get_lua_paths()

    local command = test_command.build({
        framework_lua_path = ctx.framework_lib_path,
        effective_lua_path = effective_lua_path,
        original_lua_path = package.path,
        effective_lua_cpath = effective_lua_cpath,
        original_lua_cpath = package.cpath,
        executable_path = test_command.detect_executable_path(os.getenv("PATH") or ""),
        lua_bin = compat.get_lua_bin(),
        test_args = test_args
    })

    local ok, exit_code = shell.execute(command)
    if not ok then
        return false, exit_code
    end

    return true, 0
end

function M.command()
    return Command.new({
        name = "test",
        help = function(ctx)
            ctx.show_test_help()
        end,
        run = function(ctx, invocation)
            return M.run(ctx, invocation.args)
        end
    })
end

return M
