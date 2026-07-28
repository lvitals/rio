-- rio/lib/rio/cli/commands/test_command.lua
-- Builds the shell command used by `rio test`.

local shell = require("rio.cli.shell")
local project_paths = require("rio.cli.project_paths")

local M = {}

local BUSTED_EXECUTABLE = "busted"
local DEFAULT_BUSTED_OUTPUT_FORMAT = "utfTerminal"
local CAPTURED_BUSTED_OUTPUT_FORMAT = "json"
local BUSTED_HELPER = "test/spec_helper.lua"
local DEFAULT_TEST_TARGET = "test/"
local DEFAULT_TEST_PATTERN = "_test.lua$"
local TEST_ENV = "test"
local FAST_HASH_ITERATIONS = "1"
local DETECT_LUAROCKS_PATH_COMMAND = "eval \"$(luarocks path --bin 2>/dev/null)\" && printf '%s' \"$PATH\""
local SUPPORTED_FORMATS = {
    terminal = true,
    json = true
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function append_lua_paths(paths)
    local resolved = {}
    for _, path in ipairs(paths or {}) do
        if path and path ~= "" then
            table.insert(resolved, tostring(path))
        end
    end
    return table.concat(resolved, ";")
end

function M.default_args()
    return {
        DEFAULT_TEST_TARGET,
        "--pattern=" .. DEFAULT_TEST_PATTERN
    }
end

function M.parse_args(args)
    local options = {
        format = "terminal",
        verbose = false,
        quiet = false,
        debug = false
    }
    local busted_args = {}

    for _, arg in ipairs(args or {}) do
        if arg == "--verbose" then
            options.verbose = true
        elseif arg == "--quiet" then
            options.quiet = true
        elseif arg == "--debug" then
            options.debug = true
            options.verbose = true
        elseif tostring(arg):match("^%-%-format=") then
            options.format = tostring(arg):match("^%-%-format=(.*)$") or options.format
        else
            table.insert(busted_args, arg)
        end
    end

    if options.format == "" or not SUPPORTED_FORMATS[options.format] then
        return nil, nil, "Unknown test format: " .. tostring(options.format)
    end

    if options.verbose then
        if options.format ~= "terminal" then
            return nil, nil, "--format=" .. options.format .. " cannot be combined with --verbose"
        end
        options.quiet = false
    end

    return options, busted_args
end

function M.detect_executable_path(fallback_path, capture)
    capture = capture or io.popen
    fallback_path = fallback_path or ""

    local handle = capture(DETECT_LUAROCKS_PATH_COMMAND, "r")
    if not handle then
        return fallback_path
    end

    local detected_path = trim(handle:read("*a"))
    local ok = handle:close()

    if ok and detected_path and detected_path ~= "" then
        return detected_path
    end

    return fallback_path
end

function M.build(options)
    options = options or {}

    local test_args = options.test_args or {}
    if #test_args == 0 then
        test_args = M.default_args()
    end

    local lua_path = append_lua_paths({
        project_paths.lua_path(),
        options.framework_lua_path,
        options.effective_lua_path,
        options.original_lua_path
    })

    local lua_cpath = append_lua_paths({
        options.effective_lua_cpath,
        options.original_lua_cpath
    })

    local command_parts = {
        shell.export("LUA_PATH", lua_path),
        shell.export("LUA_CPATH", lua_cpath),
        shell.export("RIO_ENV", TEST_ENV),
        shell.export("RIO_HASH_ITERATIONS", FAST_HASH_ITERATIONS),
        shell.export("PATH", options.executable_path or "")
    }

    local busted_args = {
        BUSTED_EXECUTABLE,
        "--lua=" .. shell.quote(options.lua_bin or "lua"),
        "--output=" .. shell.quote(options.output_format or DEFAULT_BUSTED_OUTPUT_FORMAT),
        "--helper=" .. shell.quote(BUSTED_HELPER)
    }

    table.insert(command_parts, table.concat(busted_args, " ") .. " " .. shell.quote_args(test_args))
    return shell.join_commands(command_parts)
end

function M.output_format_for(options)
    if options and options.verbose then
        return nil
    end

    return CAPTURED_BUSTED_OUTPUT_FORMAT
end

return M
