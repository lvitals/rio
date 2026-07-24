if not describe then
    print("Usage: busted test/cli/context_test.lua")
    os.exit(1)
end

package.path = "lib/?.lua;lib/?/init.lua;" .. package.path

local context_builder = require("rio.cli.context")

describe("Rio CLI Context", function()
    it("builds the shared services required by command modules", function()
        local context = context_builder.build({
            framework_lib_path = "lib/?.lua;lib/?/init.lua",
            bin_path = "bin/rio"
        })

        for _, key in ipairs({
            "ui", "colors", "files", "get_lua_paths", "framework_lib_path",
            "bin_path", "is_port_free", "new_project", "db_drivers",
            "database_config", "normalize_database_adapter",
            "is_database_driver_available", "ensure_database_driver_available",
            "print_driver_install_hint", "get_db_connection", "camel_case",
            "create_dir_if_not_exists", "write_file_content", "file_exists",
            "is_api_only", "generate_channel", "generate_controller",
            "generate_model", "generate_migration", "generate_resource",
            "generate_scaffold"
        }) do
            assert.truthy(context[key], key .. " should be present")
        end
    end)

    it("exposes help callbacks for all help screens", function()
        local context = context_builder.build()
        for _, key in ipairs({
            "show_general_help", "show_db_help", "show_routes_help",
            "show_middleware_help", "show_new_help", "show_server_help",
            "show_console_help", "show_runner_help", "show_generate_help",
            "show_destroy_help", "show_test_help", "show_stats_help",
            "show_initializers_help", "show_about_help", "show_tmp_help",
            "show_mailbox_help"
        }) do
            assert.is_function(context[key], key .. " should be a function")
        end
    end)
end)
