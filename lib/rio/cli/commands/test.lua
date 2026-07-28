-- rio/lib/rio/cli/commands/test.lua

local Command = require("rio.cli.command")
local compat = require("rio.utils.compat")
local shell = require("rio.cli.shell")
local test_command = require("rio.cli.commands.test_command")
local reporter = require("rio.testing.reporter")
local terminal_formatter = require("rio.testing.formatters.terminal")

local M = {}

local function rio_version()
    local ok, rio = pcall(require, "rio")
    if ok and rio and rio.VERSION then
        return rio.VERSION
    end
    return "unknown"
end

local function print_json(summary)
    local ok, cjson = pcall(require, "cjson")
    if not ok then
        ok, cjson = pcall(require, "cjson.safe")
    end
    if ok and cjson and cjson.encode then
        if cjson.encode_empty_table_as_object then
            pcall(cjson.encode_empty_table_as_object, false)
        end
        summary.raw_output = nil
        print(cjson.encode(summary))
    else
        print([[{"status":"error","message":"lua-cjson is required for --format=json"}]])
    end
end

function M.run(ctx, test_args)
    local options, busted_args = test_command.parse_args(test_args)
    local effective_lua_path, effective_lua_cpath = ctx.get_lua_paths()
    local output_format
    if not options.verbose then
        output_format = test_command.captured_output_format()
    end

    local command = test_command.build({
        framework_lua_path = ctx.framework_lib_path,
        effective_lua_path = effective_lua_path,
        original_lua_path = package.path,
        effective_lua_cpath = effective_lua_cpath,
        original_lua_cpath = package.cpath,
        executable_path = test_command.detect_executable_path(os.getenv("PATH") or ""),
        lua_bin = compat.get_lua_bin(),
        test_args = busted_args,
        output_format = output_format
    })

    if options.debug then
        ctx.ui.info(command, "Command")
    end

    if options.verbose then
        ctx.ui.header("Running Rio tests with Busted")
        local ok, exit_code = shell.execute(command)
        if not ok then
            return false, exit_code
        end
        return true, 0
    end

    if options.format ~= "json" and not options.quiet then
        terminal_formatter.header({
            version = rio_version(),
            lua_version = _VERSION,
            environment = "test"
        })
    end

    local result = shell.capture(command)
    local summary = reporter.build(result.output, result.code)

    if options.format == "json" then
        print_json(summary)
    else
        terminal_formatter.render(summary, { quiet = options.quiet })
    end

    if not result.ok then
        return false, result.code
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
