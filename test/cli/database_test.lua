if not describe then
    print("Usage: busted test/cli/database_test.lua")
    os.exit(1)
end

package.path = "lib/?.lua;lib/?/init.lua;" .. package.path

local database = require("rio.cli.database")
local drivers = require("rio.database.drivers")
local ui = require("rio.utils.ui")
local helpers = require("test.cli.helpers")
local lfs = require("lfs")

describe("Rio CLI Database Services", function()
    local quiet_ui = {
        status = function() end,
        line = function() end,
        warn = function() end,
        info = function() end,
        header = function() end,
        box = function(_, fn) if fn then fn() end end,
        row = function() end
    }

    local function build_db_core()
        return require("rio.cli.commands.db_core").new({
            ui = quiet_ui,
            colors = ui.colors,
            db_drivers = {},
            get_lua_paths = function() return package.path, package.cpath end,
            normalize_database_adapter = function(adapter) return adapter end,
            is_database_driver_available = function() return true end,
            ensure_database_driver_available = function() return true end,
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
    end

    local function with_temp_project(name, callback)
        local root = helpers.tmpdir(name)
        helpers.mkdir_p(root .. "/config")
        local original_dir = assert(lfs.currentdir())
        local original_package_path = package.path
        package.path = helpers.repo_root() .. "/lib/?.lua;" .. helpers.repo_root() .. "/lib/?/init.lua"
        local active_package_path = package.path

        local ok, err = xpcall(function()
            assert.truthy(lfs.chdir(root))
            callback(root, active_package_path)
        end, debug.traceback)

        assert.truthy(lfs.chdir(original_dir))
        package.path = original_package_path
        helpers.remove_tree(root)

        if not ok then error(err, 0) end
    end

    it("loads project database config and allows local requires when LuaRocks package.path omits the current directory", function()
        with_temp_project("rio_db_config", function(root)
            helpers.write(root .. "/config/database_defaults.lua", [[
return {
    adapter = "sqlite",
    database = "db/development.sqlite3"
}
]])
            helpers.write(root .. "/config/database.lua", [[
local defaults = require("config.database_defaults")

return {
    development = {
        adapter = defaults.adapter,
        database = defaults.database
    }
}
]])

            local db_core = build_db_core()
            local config = db_core.load_config()
            assert.equals("sqlite", config.development.adapter)
            assert.equals("db/development.sqlite3", config.development.database)
        end)
    end)

    it("restores package.path after loading database config", function()
        with_temp_project("rio_db_config_success", function(root, original_package_path)
            helpers.write(root .. "/config/database.lua", [[
return {
    development = {
        adapter = "sqlite",
        database = "db/development.sqlite3"
    }
}
]])

            local db_core = build_db_core()
            assert.truthy(db_core.load_config())
            assert.equals(original_package_path, package.path)
        end)
    end)

    it("restores package.path and reports load errors without starting setup", function()
        with_temp_project("rio_db_config_error", function(root, original_package_path)
            helpers.write(root .. "/config/database.lua", [[
error("configuration failure")
]])

            local db_core = build_db_core()
            assert.is_nil(db_core.load_config())

            assert.equals(original_package_path, package.path)
        end)
    end)

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

        local mysql_spec = {
            adapter = "mysql",
            label = "MySQL/MariaDB",
            module = "luasql.mysql",
            rock = "luasql-mysql",
            native_dependency = "MySQL headers",
            build_variables = {
                { name = "MYSQL_INCDIR", header = "mysql.h" }
            }
        }

        local db_core = require("rio.cli.commands.db_core").new({
            ui = ui,
            colors = ui.colors,
            db_drivers = {
                get = function()
                    return mysql_spec
                end,
                install_command = function(_, opts)
                    local command_parts = { "luarocks", "install", mysql_spec.rock }
                    for _, arg in ipairs(opts.extra_args or {}) do
                        table.insert(command_parts, arg)
                    end
                    return table.concat(command_parts, " ")
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

        helpers.capture_prints(function()
            db_core.install({ "mysql", "MYSQL_DIR=" .. include_root })
        end)
        os.execute = original_execute
        helpers.remove_tree(root)

        assert.truthy(executed_command)
        assert.truthy(executed_command:find("MYSQL_INCDIR=" .. mysql_include, 1, true))
        assert.is_nil(executed_command:find("MYSQL_DIR=", 1, true))
    end)
end)
