if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the \"busted\" test runner.")
    print("Usage: busted test/database/migrate_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local migrate = require("rio.database.migrate")
local DBManager = require("rio.database.manager")
local helpers = require("test.cli.helpers")
local lfs = require("lfs")
local project_paths = require("rio.cli.project_paths")

describe("Rio Database Migrations", function()
    local mock_adapter
    local mock_conn

    local function write_migration(root, basename, body)
        local file = root .. "/db/migrate/" .. basename .. ".lua"
        helpers.write(file, body)
        local migration_name = file:match("([^/\\]+)%.lua$")
        return migration_name, "db.migrate." .. migration_name
    end

    before_each(function()
        mock_adapter = {
            get_sql_type = function(t, opts) 
                if t == "string" then return "VARCHAR(255)" end
                return t:upper()
            end,
            get_pk_definition = function() return "id INTEGER PRIMARY KEY" end,
            get_timestamp_default = function() return "CURRENT_TIMESTAMP" end,
            get_table_options = function() return "" end,
            query = function(self, sql) self.last_sql = sql; return true end
        }
        mock_conn = {
            execute = function(self, sql) self.last_sql = sql; return true end
        }
        -- Force inject mock adapter into DBManager for testing
        DBManager.get_adapter = function() return mock_adapter end
    end)

    it("should generate correct CREATE TABLE SQL via BaseMigration", function()
        local mig = migrate.Migration:new(mock_conn, "sqlite")
        
        -- Override conn execute to capture SQL
        local captured_sql = ""
        mock_conn.execute = function(_, sql) captured_sql = sql; return true end

        mig:create_table("test_table", function(t)
            t:integer("id")
            t:string("name")
            t:timestamps()
        end)

        assert.truthy(captured_sql:find("CREATE TABLE IF NOT EXISTS test_table"))
        assert.truthy(captured_sql:find("id INTEGER"))
        assert.truthy(captured_sql:find("name VARCHAR"))
        assert.truthy(captured_sql:find("created_at DATETIME"))
    end)

    it("should handle manual down migration", function()
        local migration = migrate.Migration:extend()
        function migration:down() return "DROP TABLE manual" end
        
        local inst = migration:new(mock_conn, "sqlite")
        local sql = inst:down()
        assert.equals("DROP TABLE manual", sql)
    end)

    it("loads migration files through the db.migrate namespace", function()
        local root = helpers.tmpdir("rio_migration_namespace")
        helpers.mkdir_p(root .. "/db/migrate")
        local migration_action = "create"
        local migration_table = "widgets"
        local migration_basename = migration_action .. "_" .. migration_table
        local create_table_sql = "CREATE TABLE " .. migration_table .. " (id INTEGER PRIMARY KEY)"

        local migration_name, module_name = write_migration(root, migration_basename, string.format([[
local Migration = require("rio.database.migrate").Migration

local MigrationUnderTest = Migration:extend()

function MigrationUnderTest:up()
    return %q
end

return MigrationUnderTest
]], create_table_sql))

        local original_dir = assert(lfs.currentdir())
        local original_package_path = package.path
        local original_get_connection = DBManager.get_connection
        local original_get_adapter_name = DBManager.get_adapter_name
        local original_get_adapter = DBManager.get_adapter
        package.loaded[module_name] = nil

        local executed_sql
        local recorded_name
        local ok, err = xpcall(function()
            assert.truthy(lfs.chdir(root))
            package.path = project_paths.lua_path() .. ";" .. project_paths.lua_path(helpers.repo_root()) .. ";" .. package.path

            local conn = {
                execute = function(_, sql)
                    executed_sql = sql
                    return true
                end,
                commit = function() end
            }
            local adapter = {
                ensure_migrations_table = function() return true end,
                get_last_batch = function() return 0 end,
                get_executed_migrations = function() return {} end,
                record_migration = function(_, name)
                    recorded_name = name
                end
            }

            DBManager.get_connection = function() return conn end
            DBManager.get_adapter_name = function() return "sqlite" end
            DBManager.get_adapter = function() return adapter end

            migrate.Migrate.run()

            assert.equals(create_table_sql, executed_sql)
            assert.equals(migration_name, recorded_name)
        end, debug.traceback)

        DBManager.get_connection = original_get_connection
        DBManager.get_adapter_name = original_get_adapter_name
        DBManager.get_adapter = original_get_adapter
        package.loaded[module_name] = nil
        assert.truthy(lfs.chdir(original_dir))
        package.path = original_package_path
        helpers.remove_tree(root)

        if not ok then error(err, 0) end
    end)
end)
