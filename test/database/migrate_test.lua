if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the \"busted\" test runner.")
    print("Usage: busted test/database/migrate_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local migrate = require("rio.database.migrate")
local DBManager = require("rio.database.manager")

describe("Rio Database Migrations", function()
    local mock_adapter
    local mock_conn

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
end)
