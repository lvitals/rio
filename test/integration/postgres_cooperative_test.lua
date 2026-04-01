if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the 'busted' test runner.")
    print("Usage: busted test/integration/postgres_cooperative_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local cqueues = require("cqueues")
local postgres = require("rio.database.adapters.postgres")

describe("Rio PostgreSQL Cooperative Concurrency", function()
    local config = {
        database = "postgres",
        username = "postgres",
        password = "123456",
        host = "127.0.0.1",
        port = 5432,
        pool = 20
    }

    local has_db = false

    setup(function()
        local ok = pcall(postgres.initialize, config)
        if ok then
            local conn = postgres.get_connection()
            if conn then
                has_db = true
                postgres.release_connection(conn)
            end
        end
    end)

    it("should handle 10 parallel 1-second queries in ~1 second total", function()
        if not has_db then pending("No database connection"); return end
        local cq = cqueues.new()
        local num_queries = 10
        local completed = 0
        local start_time = cqueues.monotime()

        for i = 1, num_queries do
            cq:wrap(function()
                local res = postgres.query("SELECT pg_sleep(1), " .. i .. " as id")
                if res and res[1] and tonumber(res[1].id) == i then
                    completed = completed + 1
                end
            end)
        end

        assert.is_true(cq:loop())
        local duration = cqueues.monotime() - start_time

        assert.equals(num_queries, completed)
        assert.is_true(duration < 2, "Parallelism failed: took " .. duration .. "s")
    end)
end)
