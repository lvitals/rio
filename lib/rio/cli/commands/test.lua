-- rio/lib/rio/cli/commands/test.lua

local Command = require("rio.cli.command")
local compat = require("rio.utils.compat")

local M = {}

function M.run(ctx, test_args)
    ctx.ui.header("Running Rio tests with Busted")
    local effective_lua_path, effective_lua_cpath = ctx.get_lua_paths()
    local project_lua_path = "./?.lua;./?/init.lua;./lib/?.lua;./lib/?/init.lua"

    local home = os.getenv("HOME") or os.getenv("USERPROFILE") or "."
    local busted_path_addition = home .. "/.luarocks/bin"

    local command_args_str = table.concat(test_args or {}, " ")
    if command_args_str == "" then
        command_args_str = "test/ --pattern=\"_test.lua$\""
    end

    local lua_bin = compat.get_lua_bin()
    local command = string.format(
        "export LUA_PATH='%s;%s;%s;%s' && export LUA_CPATH='%s;%s' && export RIO_ENV='test' && export RIO_HASH_ITERATIONS='1' && export PATH='%s:%s' && busted --lua=%s --output=utfTerminal --helper=test/spec_helper.lua %s",
        project_lua_path,
        ctx.framework_lib_path,
        effective_lua_path,
        package.path,
        effective_lua_cpath,
        package.cpath,
        busted_path_addition,
        os.getenv("PATH") or "",
        lua_bin,
        command_args_str
    )

    os.execute(command)
end

function M.command()
    return Command.new({
        name = "test",
        help = function(ctx)
            ctx.show_test_help()
        end,
        run = function(ctx, invocation)
            M.run(ctx, invocation.args)
            return true
        end
    })
end

return M
