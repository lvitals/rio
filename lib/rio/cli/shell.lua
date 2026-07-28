-- rio/lib/rio/cli/shell.lua
-- POSIX shell helpers used by CLI commands.

local M = {}

local COMMAND_SEPARATOR = " && "
local ENV_EXPORT_FORMAT = "export %s=%s"
local STDERR_REDIRECT = " 2>&1"

function M.quote(value)
    return "'" .. tostring(value or ""):gsub("'", [['"'"']]) .. "'"
end

function M.quote_args(args)
    local quoted = {}
    for _, arg in ipairs(args or {}) do
        table.insert(quoted, M.quote(arg))
    end
    return table.concat(quoted, " ")
end

function M.export(name, value)
    assert(tostring(name):match("^[A-Z_][A-Z0-9_]*$"), "invalid environment variable name")
    return string.format(ENV_EXPORT_FORMAT, name, M.quote(value))
end

function M.join_commands(commands)
    return table.concat(commands or {}, COMMAND_SEPARATOR)
end

function M.status_code(ok, exit_type, code)
    if ok == true then return 0 end
    if type(ok) == "number" then
        if ok > 255 then
            return math.floor(ok / 256)
        end
        return ok
    end
    if exit_type == "signal" and type(code) == "number" then
        return 128 + code
    end
    if type(code) == "number" then return code end
    return 1
end

function M.execute(command)
    local ok, exit_type, code = os.execute(command)
    local status_code = M.status_code(ok, exit_type, code)
    return status_code == 0, status_code
end

function M.capture(command)
    local handle = assert(io.popen(command .. STDERR_REDIRECT, "r"))
    local output = handle:read("*a")
    local ok, exit_type, code = handle:close()
    local status_code = M.status_code(ok, exit_type, code)
    return {
        ok = status_code == 0,
        code = status_code,
        output = output or ""
    }
end

return M
