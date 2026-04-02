if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the 'busted' test runner.")
    print("Usage: busted " .. (arg and arg[0] or "test/database/mysql_adapter_test.lua"))
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local mysql = require("rio.database.adapters.mysql")
local cqueues = require("cqueues")
local test_config = require("test.test_config")

describe("Rio MySQL Adapter", function()
    local adapter_name = "mysql"
    local config = test_config.configs[adapter_name]

    setup(function()
        if test_config.check_connection(adapter_name) then
            mysql.initialize(config)
            -- Ensure test table exists
            mysql.query("DROP TABLE IF EXISTS rio_mysql_busted_test")
            mysql.query("CREATE TABLE rio_mysql_busted_test (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255))")
        end
    end)

    teardown(function()
        if test_config.check_connection(adapter_name) then
            mysql.query("DROP TABLE IF EXISTS rio_mysql_busted_test")
        end
    end)

    it("should connect and provide diagnostic info", function()
        if test_config.skip_if_no_db(adapter_name, "MySQL Adapter") then return end
        local conn, env = mysql.get_connection()
        assert.is_not_nil(conn)
        
        RioUI.box("MySQL/MariaDB Connectivity Info", function()
            RioUI.status("Database Connection", true, config.database)
            RioUI.status("Driver Async Mode", (conn.poll ~= nil), "MariaDB Non-blocking API active")
            RioUI.status("Cqueues Integration", (pcall(require, "cqueues")), "Ready for Event Loop")
        end)
        
        mysql.release_connection(conn, env)
    end)

    it("should perform basic CRUD operations", function()
        if test_config.skip_if_no_db(adapter_name, "MySQL Adapter") then return end
        -- Insert
        local id1 = mysql.insert("INSERT INTO rio_mysql_busted_test (name) VALUES (?)", {"Alice"})
        local id2 = mysql.insert("INSERT INTO rio_mysql_busted_test (name) VALUES (?)", {"Bob"})
        assert.is_number(id1)
        assert.is_number(id2)
        assert.is_true(id2 > id1)

        -- Select
        local users = mysql.query("SELECT * FROM rio_mysql_busted_test ORDER BY name")
        assert.equals(2, #users)
        assert.equals("Alice", users[1].name)
        assert.equals("Bob", users[2].name)

        -- Update
        local affected = mysql.update("UPDATE rio_mysql_busted_test SET name = ? WHERE id = ?", {"Charlie", id1})
        assert.equals(1, affected.affected)

        -- Delete
        local del_affected = mysql.delete("DELETE FROM rio_mysql_busted_test WHERE id = ?", {id2})
        assert.equals(1, del_affected.affected)
        
        local final_users = mysql.query("SELECT count(*) as total FROM rio_mysql_busted_test")
        assert.equals(1, tonumber(final_users[1].total))
    end)

    it("should support cooperative execution with cqueues", function()
        if test_config.skip_if_no_db(adapter_name, "MySQL Adapter") then return end
        local cq = cqueues.new()
        local results = {}
        local count = 5

        for i = 1, count do
            cq:wrap(function()
                local res = mysql.query("SELECT " .. i .. " as val")
                results[i] = tonumber(res[1].val)
            end)
        end

        assert.is_true(cq:loop())
        
        for i = 1, count do
            assert.equals(i, results[i])
        end
    end)

    it("should handle SQL errors gracefully", function()
        if test_config.skip_if_no_db(adapter_name, "MySQL Adapter") then return end
        local res, err = mysql.query("SELECT * FROM non_existent_table_mysql")
        assert.is_nil(res)
        assert.is_string(err)
    end)
    
    it("should escape values correctly", function()
        if test_config.skip_if_no_db(adapter_name, "MySQL Adapter") then return end
        assert.equals("'O''Reilly'", mysql.escape_value("O'Reilly"))
        assert.equals("1", mysql.escape_value(true))
        assert.equals("0", mysql.escape_value(false))
        assert.equals("NULL", mysql.escape_value(nil))
    end)
end)
