-- rio/lib/rio/cli/commands/new.lua

local Command = require("rio.cli.command")

local M = {}

function M.command()
    return Command.new({
        name = "new",
        help = function(ctx)
            ctx.show_new_help()
        end,
        run = function(ctx, invocation)
            local project_name = nil
            local database_adapter = "none"
            local api_only = false

            for _, arg in ipairs(invocation.args) do
                local adapter = arg:match("^%-%-database=(.+)$")
                if adapter then
                    database_adapter = adapter
                elseif arg == "--api" then
                    api_only = true
                elseif not project_name then
                    project_name = arg
                else
                    ctx.ui.warn("Unknown project creation argument: " .. arg)
                end
            end

            if not project_name then
                ctx.ui.status("Project creation", false, "Project name is required.")
                ctx.show_new_help()
                return true
            end

            database_adapter = ctx.normalize_database_adapter(database_adapter, true)
            if not database_adapter then
                ctx.ui.status("Project creation", false, "Invalid database adapter")
                ctx.ui.line("Supported adapters: " .. ctx.db_drivers.supported_names() .. ", none", ctx.colors.dim)
                return true
            end

            ctx.new_project(project_name, database_adapter, api_only)
            return true
        end
    })
end

return M
