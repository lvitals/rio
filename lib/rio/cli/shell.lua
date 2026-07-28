-- rio/lib/rio/cli/shell.lua
-- POSIX shell helpers used by CLI commands.

local M = {}

local COMMAND_SEPARATOR = " && "
local ENV_EXPORT_FORMAT = "export %s=%s"

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

function M.status_code(ok, _, code)
    if ok == true then return 0 end
    if type(ok) == "number" then return ok end
    if type(code) == "number" then return code end
    return 1
end

function M.execute(command)
    local ok, exit_type, code = os.execute(command)
    local status_code = M.status_code(ok, exit_type, code)
    return status_code == 0, status_code
end

return M
