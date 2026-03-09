local DBManager = require("rio.database.manager")
local Model = require("rio.database.model")

DBManager.verbose = false -- Silence DB logs during tests

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

    it("should return cached results for identical queries", function()
        -- First query (Database hit)
        local u1 = User:all()
        assert.equals(1, #u1)
        assert.equals("Test User", u1[1].name)

        -- Change DB data directly without going through ORM
        DBManager.query("UPDATE users SET name = 'New Name' WHERE id = 1")

        -- Second query (Cache hit) - should still return old name
        local u2 = User:all()
        assert.equals("Test User", u2[1].name)
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

    describe("Performance Information", function()
        it("should demonstrate query speed improvement", function()
            -- Warm up / Initial hit
            User:all()
            
            -- Measure No Cache (bypass)
            DBManager.query_cache_enabled = false
            local start_no_cache = os.clock()
            for i=1, 100 do User:all() end
            local time_no_cache = os.clock() - start_no_cache

            -- Measure Cache Hit
            DBManager.query_cache_enabled = true
            local start_cache = os.clock()
            for i=1, 100 do User:all() end
            local time_cache = os.clock() - start_cache

            print("\n" .. string.rep("-", 40))
            print("QUERY CACHE PERFORMANCE INFO (Level 1)")
            print(string.format("  No Cache (100 queries): %.6fs", time_no_cache))
            print(string.format("  Cache Hit (100 queries): %.6fs", time_cache))
            if time_cache > 0 then
                print(string.format("  Speedup: %.1fx faster", time_no_cache / time_cache))
            end
            print(string.rep("-", 40) .. "\n")
            
            assert.is_true(time_cache < time_no_cache)
        end)
    end)
end)
