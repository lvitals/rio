if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the 'busted' test runner.")
    print("Usage: busted test/integration/mysql_cooperative_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local cqueues = require("cqueues")
local mysql = require("rio.database.adapters.mysql")

describe("Rio MySQL/MariaDB Cooperative Concurrency", function()
    local config = {
        database = "test",
        username = "root",
        password = "123456",
        host = "127.0.0.1",
        pool = 10
    }

    setup(function()
        local ok = pcall(mysql.initialize, config)
        if not ok then
            print("\n[SKIP] MySQL not available for cooperative test.")
            return
        end
        mysql.query("CREATE TABLE IF NOT EXISTS rio_mysql_coop_test (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255))")
    end)

    teardown(function()
        mysql.query("DROP TABLE IF EXISTS rio_mysql_coop_test")
    end)

    it("should handle 20 concurrent operations without blocking", function()
        local cq = cqueues.new()
        local num_queries = 20
        local completed = 0

        for i = 1, num_queries do
            cq:wrap(function()
                local id = mysql.insert("INSERT INTO rio_mysql_coop_test (name) VALUES (?)", {"User " .. i})
                local res = mysql.query("SELECT * FROM rio_mysql_coop_test WHERE id = ?", {id})
                
                if res and res[1] and tonumber(res[1].id) == id then
                    completed = completed + 1
                end
            end)
        end

        assert.is_true(cq:loop())
        assert.equals(num_queries, completed)
    end)
end)
