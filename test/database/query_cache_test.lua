if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the \"busted\" test runner.")
    print("Usage: busted test/database/query_cache_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local DBManager = require("rio.database.manager")
local Model = require("rio.database.model")
local RioUI = _G.RioUI or require("rio.utils.ui")

DBManager.verbose = false -- Silence DB logs during tests

local QUERY_CACHE_BENCHMARK_ITERATIONS =
    tonumber(os.getenv("RIO_TEST_QUERY_CACHE_ITERATIONS")) or 500

describe("ActiveRecord Query Cache", function()
    local User

    before_each(function()
        -- Reset DB Manager state
        DBManager.query_cache_enabled = true
        DBManager.clear_query_cache()

        -- Initialize a temporary database
        DBManager.initialize({
            adapter = "sqlite",
            database = ":memory:"
        })

        -- Create test table if not exists and clean it
        DBManager.query("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT)")
        DBManager.query("DELETE FROM users")
        DBManager.query("INSERT INTO users (id, name) VALUES (1, 'Test User')")

        User = Model:extend({
            table_name = "users",
            fillable = { "name" }
        })
    end)

    it("should return cached results for identical queries until a mutation runs", function()
        -- First query (Database hit)
        local u1 = User:all()
        assert.equals(1, #u1)
        assert.equals("Test User", u1[1].name)

        -- Mutations through DB.query also invalidate the query cache.
        DBManager.query("UPDATE users SET name = 'New Name' WHERE id = 1")

        local u2 = User:all()
        assert.equals("New Name", u2[1].name)
    end)

    it("should fetch new data after clearing cache", function()
        User:all()
        DBManager.query("UPDATE users SET name = 'Updated' WHERE id = 1")
        
        DBManager.clear_query_cache()
        
        local u = User:all()
        assert.equals("Updated", u[1].name)
    end)

    it("should bypass cache if disabled", function()
        DBManager.query_cache_enabled = false
        
        User:all()
        DBManager.query("UPDATE users SET name = 'No Cache' WHERE id = 1")
        
        local u = User:all()
        assert.equals("No Cache", u[1].name)
    end)

    it("should avoid repeated database queries for identical cached reads", function()
        local original_query = DBManager.query
        local select_count = 0

        DBManager.query = function(sql, bindings)
            if tostring(sql or ""):lower():match("^%s*select") then
                select_count = select_count + 1
            end

            return original_query(sql, bindings)
        end

        local ok, err = xpcall(function()
            local first = User:all()
            local second = User:all()

            assert.equals(1, #first)
            assert.equals(1, #second)
            assert.equals("Test User", first[1].name)
            assert.equals("Test User", second[1].name)
            assert.equals(1, select_count)
        end, debug.traceback)

        DBManager.query = original_query

        if not ok then
            error(err, 0)
        end
    end)

    describe("Performance Information", function()
        it("should report query cache timing information", function()
            -- Warm up / Initial hit
            User:all()
            
            -- Measure No Cache (bypass)
            DBManager.query_cache_enabled = false
            local start_no_cache = os.clock()
            for _ = 1, QUERY_CACHE_BENCHMARK_ITERATIONS do User:all() end
            local time_no_cache = os.clock() - start_no_cache

            -- Measure Cache Hit
            DBManager.query_cache_enabled = true
            local start_cache = os.clock()
            for _ = 1, QUERY_CACHE_BENCHMARK_ITERATIONS do User:all() end
            local time_cache = os.clock() - start_cache

            RioUI.box("Query Cache Performance (Level 1)", function()
                RioUI.status(
                    string.format("No Cache (%d queries)", QUERY_CACHE_BENCHMARK_ITERATIONS),
                    true,
                    string.format("%.6fs", time_no_cache)
                )
                RioUI.status(
                    string.format("Cache Hit (%d queries)", QUERY_CACHE_BENCHMARK_ITERATIONS),
                    true,
                    string.format("%.6fs", time_cache)
                )
                if time_cache > 0 then
                    RioUI.status("Speedup Factor", true, string.format("%.1fx faster", time_no_cache / time_cache))
                end
            end)
            
            assert.is_true(time_no_cache >= 0)
            assert.is_true(time_cache >= 0)
        end)
    end)
end)
