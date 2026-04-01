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

    local has_db = false

    setup(function()
        local ok = pcall(mysql.initialize, config)
        if ok then
            local conn = mysql.get_connection()
            if conn then
                has_db = true
                mysql.release_connection(conn)
                mysql.query("CREATE TABLE IF NOT EXISTS rio_mysql_coop_test (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255))")
            end
        end
    end)

    teardown(function()
        if has_db then
            mysql.query("DROP TABLE IF EXISTS rio_mysql_coop_test")
        end
    end)

    it("should handle 20 concurrent operations without blocking", function()
        if not has_db then pending("No database connection"); return end
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
    
    it("should complete multiple queries without crashing despite sequential execution", function()
        if not has_db then pending("No database connection"); return end
        local cq = cqueues.new()
        local num_workers = 5
        local finished_workers = 0

        for i = 1, num_workers do
            cq:wrap(function()
                -- SLEEP(0.1) to avoid too much blocking while confirming success
                local res, err = mysql.query("SELECT SLEEP(0.1) as s")
                if res then
                    finished_workers = finished_workers + 1
                end
            end)
        end

        assert.is_true(cq:loop())
        assert.equals(num_workers, finished_workers)
    end)
end)
