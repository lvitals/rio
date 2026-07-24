-- rio/lib/rio/cli/commands/help.lua

local Command = require("rio.cli.command")

local M = {}

local HELP_HANDLERS = {
    about = "show_about_help",
    console = "show_console_help",
    db = "show_db_help",
    destroy = "show_destroy_help",
    generate = "show_generate_help",
    initializers = "show_initializers_help",
    mailbox = "show_mailbox_help",
    middleware = "show_middleware_help",
    new = "show_new_help",
    routes = "show_routes_help",
    runner = "show_runner_help",
    server = "show_server_help",
    stats = "show_stats_help",
    test = "show_test_help",
    tmp = "show_tmp_help"
}

local function normalize_help_target(target)
    if not target or target == "" then
        return nil
    end
    return target:match("^([^:]+)") or target
end

local function show_target_help(ctx, target)
    local command_name = normalize_help_target(target)
    if not command_name then
        ctx.show_general_help()
        return
    end

    local handler_name = HELP_HANDLERS[command_name]
    local handler = handler_name and ctx[handler_name]
    if handler then
        handler()
        return
    end

    ctx.ui.status("Help", false, "No help available for command '" .. tostring(target) .. "'")
    ctx.show_general_help()
end

function M.command()
    return Command.new({
        name = "help",
        run = function(ctx, invocation)
            show_target_help(ctx, invocation.args[1])
            return true
        end
    })
end

return M
