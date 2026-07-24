-- rio/lib/rio/cli/commands/db.lua

local Command = require("rio.cli.command")
local db_core = require("rio.cli.commands.db_core")

local M = {}

local function core(ctx)
    if not ctx.__db_core then
        ctx.__db_core = db_core.new({
            ui = ctx.ui,
            colors = ctx.colors,
            db_drivers = ctx.db_drivers,
            get_lua_paths = ctx.get_lua_paths,
            normalize_database_adapter = ctx.normalize_database_adapter,
            is_database_driver_available = ctx.is_database_driver_available,
            ensure_database_driver_available = ctx.ensure_database_driver_available,
            print_driver_install_hint = ctx.print_driver_install_hint,
            create_dir_if_not_exists = ctx.create_dir_if_not_exists,
            write_file_content = ctx.write_file_content,
            file_exists = ctx.file_exists,
            database_config = ctx.database_config
        })
    end
    return ctx.__db_core
end

function M.command()
    return Command.new({
        name = "db",
        help = function(ctx)
            ctx.show_db_help()
        end,
        run = function(ctx, invocation)
            local subcommand = invocation.subcommand
            if not subcommand then
                ctx.ui.status("Database command", false, "Subcommand is required")
                ctx.show_db_help()
                return true
            end

            local handler = core(ctx)[subcommand]
            if not handler then
                ctx.ui.status("Database command", false, "Unknown subcommand '" .. subcommand .. "'")
                ctx.show_db_help()
                return true
            end

            handler(invocation.args)
            return true
        end
    })
end

return M
