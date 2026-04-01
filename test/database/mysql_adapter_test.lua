if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the 'busted' test runner.")
    print("Usage: busted " .. (arg and arg[0] or "test/database/mysql_adapter_test.lua"))
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local mysql = require("rio.database.adapters.mysql")
local cqueues = require("cqueues")

describe("Rio MySQL Adapter", function()
    local config = {
        database = "test",
        username = "root",
        password = "123456",
        host = "127.0.0.1",
        pool = 5
    }

    local has_db = false

    setup(function()
        local ok = pcall(mysql.initialize, config)
        if ok then
            local conn = mysql.get_connection()
            if conn then
                has_db = true
                mysql.release_connection(conn)
                -- Ensure test table exists
                mysql.query("DROP TABLE IF EXISTS rio_mysql_busted_test")
                mysql.query("CREATE TABLE rio_mysql_busted_test (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255))")
            end
        end
    end)

    teardown(function()
        if has_db then
            mysql.query("DROP TABLE IF EXISTS rio_mysql_busted_test")
        end
    end)

    it("should connect and provide diagnostic info", function()
        if not has_db then pending("No database connection"); return end
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
        if not has_db then pending("No database connection"); return end
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
        if not has_db then pending("No database connection"); return end
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
        if not has_db then pending("No database connection"); return end
        local res, err = mysql.query("SELECT * FROM non_existent_table_mysql")
        assert.is_nil(res)
        assert.is_string(err)
    end)
    
    it("should escape values correctly", function()
        if not has_db then pending("No database connection"); return end
        assert.equals("'O''Reilly'", mysql.escape_value("O'Reilly"))
        assert.equals("1", mysql.escape_value(true))
        assert.equals("0", mysql.escape_value(false))
        assert.equals("NULL", mysql.escape_value(nil))
    end)
end)
