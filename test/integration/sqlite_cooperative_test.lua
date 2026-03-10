if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the 'busted' test runner.")
    print("Usage: busted test/integration/sqlite_cooperative_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local cqueues = require("cqueues")
local sqlite = require("rio.database.adapters.sqlite")

describe("Rio SQLite Cooperative Concurrency", function()
    local config = {
        database = "/tmp/rio_test_sqlite_coop.db",
        pool = 5
    }

    setup(function()
        os.remove(config.database)
        sqlite.initialize(config)
        local conn, env = sqlite.get_connection()
        conn:execute("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)")
        sqlite.release_connection(conn, env)
    end)

    teardown(function()
        os.remove(config.database)
    end)

    it("should handle 100 concurrent operations without blocking", function()
        local cq = cqueues.new()
        local num_queries = 100
        local completed = 0

        for i = 1, num_queries do
            cq:wrap(function()
                local id = sqlite.insert("INSERT INTO users (name) VALUES (?)", {"User " .. i})
                local res = sqlite.query("SELECT * FROM users WHERE id = ?", {id})
                
                if res and res[1] and tonumber(res[1].id) == id then
                    completed = completed + 1
                end
            end)
        end

        assert.is_true(cq:loop())
        assert.equals(num_queries, completed)
    end)
end)
