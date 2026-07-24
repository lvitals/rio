-- rio/lib/rio/cli/commands/mailbox.lua

local Command = require("rio.cli.command")

local M = {}

function M.install()
    print("Mailbox installation not yet implemented in the new architecture.")
end

function M.ingress(provider)
    print("Mailbox ingress for " .. provider .. " not yet implemented.")
end

function M.run(ctx, subcommand)
    if subcommand == "install" then
        M.install()
    elseif subcommand == "ingress:exim" then
        M.ingress("Exim")
    elseif subcommand == "ingress:postfix" then
        M.ingress("Postfix")
    elseif subcommand == "ingress:qmail" then
        M.ingress("Qmail")
    else
        ctx.ui.line("Usage: rio mailbox:install | mailbox:ingress:<provider>", ctx.colors.yellow)
    end
end

function M.command()
    return Command.new({
        name = "mailbox",
        help = function(ctx)
            ctx.show_mailbox_help()
        end,
        run = function(ctx, invocation)
            M.run(ctx, invocation.subcommand)
            return true
        end
    })
end

return M
