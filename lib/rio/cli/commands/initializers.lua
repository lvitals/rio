-- rio/lib/rio/cli/commands/initializers.lua

local Command = require("rio.cli.command")

local M = {}

function M.run(ctx)
    ctx.ui.header("Application Initializers")

    local initializers_dir = "config/initializers"
    local initializers = ctx.files.list(initializers_dir, { mode = "file", pattern = "%.lua$" })
    local count = 0

    ctx.ui.box("Loaded Initializers", function()
        for _, file in ipairs(initializers) do
            local name = ctx.files.basename(file)
            if name then
                count = count + 1
                ctx.ui.row(string.format("%02d", count), name)
            end
        end

        if count == 0 then
            ctx.ui.info("No initializers found in config/initializers/")
        end
    end)

    if count > 0 then
        ctx.ui.line("Total: " .. count .. " initializer(s) found.", ctx.colors.dim)
    end
end

function M.command()
    return Command.new({
        name = "initializers",
        help = function(ctx)
            ctx.show_initializers_help()
        end,
        run = function(ctx)
            M.run(ctx)
            return true
        end
    })
end

return M
