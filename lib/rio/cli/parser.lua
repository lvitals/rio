-- rio/lib/rio/cli/parser.lua
-- Normalizes raw CLI args into a command invocation.

local M = {}

function M.parse(args, options)
    args = args or {}
    options = options or {}

    local invocation = {
        raw = args,
        full_command = args[1],
        command = nil,
        subcommand = nil,
        args = {},
        help = false
    }

    if not invocation.full_command then
        return invocation
    end

    local colon_pos = invocation.full_command:find(":", 1, true)
    if colon_pos then
        invocation.command = invocation.full_command:sub(1, colon_pos - 1)
        invocation.subcommand = invocation.full_command:sub(colon_pos + 1)
    else
        invocation.command = invocation.full_command
    end

    for i = 2, #args do
        local arg = args[i]
        if arg == "--help" or arg == "-h" then
            invocation.help = true
        else
            table.insert(invocation.args, arg)
        end
    end

    local shift_for = options.shift_subcommand_for or {}
    if shift_for[invocation.command] and not invocation.subcommand and #invocation.args > 0 then
        invocation.subcommand = table.remove(invocation.args, 1)
    end

    return invocation
end

return M
