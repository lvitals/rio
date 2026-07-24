-- rio/lib/rio/cli/context.lua

local compat = require("rio.utils.compat")
local ui = require("rio.utils.ui")
local files = require("rio.cli.files")
local help = require("rio.cli.help")
local project = require("rio.cli.project")
local database_service = require("rio.cli.database")
local generator_service = require("rio.cli.generator_service")
local ports = require("rio.cli.ports")

local M = {}

local function merge(target, source)
    for key, value in pairs(source or {}) do
        target[key] = value
    end
    return target
end

local function build_help_context(database)
    return {
        ui = ui,
        colors = ui.colors,
        db_drivers = database.db_drivers
    }
end

local function build_help_callbacks(help_context)
    return {
        show_general_help = function() help.general(help_context) end,
        show_middleware_help = function() help.middleware(help_context) end,
        show_generate_help = function() help.generate(help_context) end,
        show_destroy_help = function() help.destroy(help_context) end,
        show_test_help = function() help.test(help_context) end,
        show_db_help = function() help.db(help_context) end,
        show_new_help = function() help.new(help_context) end,
        show_routes_help = function() help.routes(help_context) end,
        show_console_help = function() help.console(help_context) end,
        show_stats_help = function() help.stats(help_context) end,
        show_about_help = function() help.about(help_context) end,
        show_initializers_help = function() help.initializers(help_context) end,
        show_mailbox_help = function() help.mailbox(help_context) end,
        show_tmp_help = function() help.tmp(help_context) end,
        show_server_help = function() help.server(help_context) end,
        show_runner_help = function() help.runner(help_context) end
    }
end

function M.build(options)
    options = options or {}

    local framework_lib_path = options.framework_lib_path or ""
    local bin_path = options.bin_path or "rio"
    local function get_lua_paths()
        return compat.get_runtime_paths(framework_lib_path)
    end

    local database = database_service.new({
        ui = ui,
        colors = ui.colors,
        files = files,
        get_lua_paths = get_lua_paths
    })
    local generators = generator_service.new({
        ui = ui,
        colors = ui.colors,
        files = files
    })

    local context = {
        ui = ui,
        colors = ui.colors,
        files = files,
        get_lua_paths = get_lua_paths,
        framework_lib_path = framework_lib_path,
        bin_path = bin_path,
        is_port_free = ports.is_free,
        new_project = function(project_name, database_adapter, api_only)
            project.create({
                files = files,
                ui = ui,
                generate_database_content = function(adapter, name, config)
                    return database:generate_database_content(adapter, name, config)
                end,
                is_database_driver_available = function(adapter)
                    return database:is_driver_available(adapter)
                end,
                print_driver_install_hint = function(adapter)
                    return database:print_install_hint(adapter)
                end
            }, project_name, database_adapter, api_only)
        end
    }

    merge(context, build_help_callbacks(build_help_context(database)))
    merge(context, database:context())
    merge(context, generators:context())

    return context
end

return M
