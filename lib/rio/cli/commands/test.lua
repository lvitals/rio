-- rio/lib/rio/cli/commands/test.lua

local Command = require("rio.cli.command")
local compat = require("rio.utils.compat")
local project_paths = require("rio.cli.project_paths")

local M = {}

local BUSTED_EXECUTABLE = "busted"
local BUSTED_OUTPUT_FORMAT = "utfTerminal"
local BUSTED_HELPER = "test/spec_helper.lua"
local DEFAULT_TEST_TARGET = "test/"
local DEFAULT_TEST_PATTERN = "_test.lua$"
local TEST_ENV = "test"
local FAST_HASH_ITERATIONS = "1"
local SHELL_COMMAND_SEPARATOR = " && "
local EXPORT_FORMAT = "export %s=%s"

local function shell_quote(value)
    return "'" .. tostring(value or ""):gsub("'", [['"'"']]) .. "'"
end

local function detect_executable_path(fallback_path)
    local handle = io.popen("luarocks path --bin 2>/dev/null", "r")
    if not handle then
        return fallback_path
    end

    local output = handle:read("*a")
    handle:close()

    local luarocks_path = output and output:match("export%s+PATH=['\"]([^'\"]+)['\"]")
    if luarocks_path and luarocks_path ~= "" then
        return luarocks_path
    end

    return fallback_path
end

local function quote_args(args)
    local quoted = {}
    for _, arg in ipairs(args or {}) do
        table.insert(quoted, shell_quote(arg))
    end
    return table.concat(quoted, " ")
end

local function default_busted_args()
    return {
        DEFAULT_TEST_TARGET,
        "--pattern=" .. DEFAULT_TEST_PATTERN
    }
end

local function build_command(options)
    local command_parts = {
        string.format(EXPORT_FORMAT, "LUA_PATH", shell_quote(options.lua_path)),
        string.format(EXPORT_FORMAT, "LUA_CPATH", shell_quote(options.lua_cpath)),
        string.format(EXPORT_FORMAT, "RIO_ENV", shell_quote(TEST_ENV)),
        string.format(EXPORT_FORMAT, "RIO_HASH_ITERATIONS", shell_quote(FAST_HASH_ITERATIONS)),
        string.format(EXPORT_FORMAT, "PATH", shell_quote(options.executable_path))
    }

    local busted_args = {
        BUSTED_EXECUTABLE,
        "--lua=" .. shell_quote(options.lua_bin),
        "--output=" .. shell_quote(BUSTED_OUTPUT_FORMAT),
        "--helper=" .. shell_quote(BUSTED_HELPER)
    }

    local test_args = options.test_args or {}
    if #test_args == 0 then
        test_args = default_busted_args()
    end

    table.insert(command_parts, table.concat(busted_args, " ") .. " " .. quote_args(test_args))
    return table.concat(command_parts, SHELL_COMMAND_SEPARATOR)
end

function M.run(ctx, test_args)
    ctx.ui.header("Running Rio tests with Busted")
    local effective_lua_path, effective_lua_cpath = ctx.get_lua_paths()
    local lua_path = table.concat({
        project_paths.lua_path(),
        ctx.framework_lib_path,
        effective_lua_path,
        package.path
    }, ";")
    local lua_cpath = table.concat({
        effective_lua_cpath,
        package.cpath
    }, ";")

    local executable_path = detect_executable_path(os.getenv("PATH") or "")

    local lua_bin = compat.get_lua_bin()
    local command = build_command({
        lua_path = lua_path,
        lua_cpath = lua_cpath,
        executable_path = executable_path,
        lua_bin = lua_bin,
        test_args = test_args
    })

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
