-- rio/lib/rio/cli/commands/ui.lua

local Command = require("rio.cli.command")

local M = {}

local function run_showcase(ctx)
    ctx.ui.header("Rio UI Showcase")
    ctx.ui.box("Core Diagnostics", function()
        ctx.ui.status("Server Module", true, "Loaded")
        ctx.ui.status("Database Driver", true, "Connected (MariaDB)")
        ctx.ui.status("Event Loop", true, "cqueues detected")
        ctx.ui.info("Testing a very long informational message that might need truncation in smaller terminal windows to prevent breaking the box borders.")
    end)

    ctx.ui.header("Individual Components")
    ctx.ui.status("Stand-alone Status", true, "Success outside box")
    ctx.ui.info("Stand-alone Info message")
    ctx.ui.status("Failed Operation", false, "Example error message")
end

function M.command()
    return Command.new({
        name = "ui",
        run = function(ctx, invocation)
            if invocation.subcommand == "test" then
                run_showcase(ctx)
                return true
            end

            ctx.ui.status("UI command", false, "Unknown subcommand '" .. tostring(invocation.subcommand or "") .. "'")
            ctx.ui.line("Usage: rio ui:test", ctx.colors.yellow)
            return true
        end
    })
end

return M
