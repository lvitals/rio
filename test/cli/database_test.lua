if not describe then
    print("Usage: busted test/cli/database_test.lua")
    os.exit(1)
end

package.path = "lib/?.lua;lib/?/init.lua;" .. package.path

local database = require("rio.cli.database")
local drivers = require("rio.database.drivers")
local ui = require("rio.utils.ui")
local helpers = require("test.cli.helpers")

describe("Rio CLI Database Services", function()
    it("normalizes documented adapter aliases", function()
        local service = database.new({
            ui = ui,
            colors = ui.colors,
            files = require("rio.cli.files"),
            get_lua_paths = function() return package.path, package.cpath end
        })

        assert.equals("sqlite", service:normalize_adapter("sqlite3"))
        assert.equals("mysql", service:normalize_adapter("mariadb"))
        assert.equals("postgres", service:normalize_adapter("postgresql"))
        assert.equals("none", service:normalize_adapter("none", true))
        assert.is_nil(service:normalize_adapter("none", false))
    end)

    it("keeps driver metadata portable across operating systems", function()
        for _, spec in ipairs(drivers.all()) do
            assert.is_string(spec.native_dependency)
            for _, variable in ipairs(spec.build_variables or {}) do
                assert.is_nil(variable.candidates)
                assert.is_string(variable.name)
                if variable.header then
                    assert.is_string(variable.header)
                end
            end
        end
    end)

    it("rewrites MYSQL_DIR include paths to MYSQL_INCDIR for LuaRocks", function()
        local root = helpers.tmpdir("rio_mysql_header")
        local include_root = root .. "/include"
        local mysql_include = include_root .. "/mysql"
        helpers.mkdir_p(mysql_include)
        helpers.write(mysql_include .. "/mysql.h", "/* fake header */")

        local executed_command
        local original_execute = os.execute
        os.execute = function(command)
            executed_command = command
            return false
        end

        local db_core = require("rio.cli.commands.db_core").new({
            ui = ui,
            colors = ui.colors,
            db_drivers = {
                get = function()
                    return {
                        adapter = "mysql",
                        label = "MySQL/MariaDB",
                        module = "luasql.mysql",
                        rock = "luasql-mysql",
                        native_dependency = "MySQL headers",
                        build_variables = {
                            { name = "MYSQL_INCDIR", header = "mysql.h" }
                        }
                    }
                end,
                install_command = function(_, opts)
                    return "luarocks install luasql-mysql " .. table.concat(opts.extra_args or {}, " ")
                end,
                infer_tree_from_cpath = function() return nil end,
                supported_names = function() return "mysql" end
            },
            get_lua_paths = function() return package.path, package.cpath end,
            normalize_database_adapter = function(adapter) return adapter == "mysql" and "mysql" or nil end,
            is_database_driver_available = function() return false end,
            ensure_database_driver_available = function() return false end,
            print_driver_install_hint = function() end,
            create_dir_if_not_exists = function() end,
            write_file_content = function() end,
            file_exists = function(path)
                return helpers.exists(path)
            end,
            database_config = {
                generate = function() return "" end
            }
        })

        db_core.install({ "mysql", "MYSQL_DIR=" .. include_root })
        os.execute = original_execute
        helpers.remove_tree(root)

        assert.truthy(executed_command)
        assert.truthy(executed_command:find("MYSQL_INCDIR=" .. mysql_include, 1, true))
        assert.is_nil(executed_command:find("MYSQL_DIR=", 1, true))
    end)
end)
