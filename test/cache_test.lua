-- test/cache_test.lua
local cache_lib = require("rio.cache")

describe("Rio Cache System", function()
    describe("Memory Adapter", function()
        local cache

        before_each(function()
            cache = cache_lib.new("memory")
        end)

        it("should set and get values", function()
            cache:set("key1", "value1")
            assert.equals("value1", cache:get("key1"))
        end)

        it("should return nil for missing keys", function()
            assert.is_nil(cache:get("missing"))
        end)

        it("should handle TTL expiration", function()
            cache:set("expiring", "gone", -1) -- already expired
            assert.is_nil(cache:get("expiring"))
        end)

        it("should fetch values (cache miss)", function()
            local called = false
            local val = cache:fetch("fetch_key", function()
                called = true
                return "fetched"
            end)
            assert.is_true(called)
            assert.equals("fetched", val)
            assert.equals("fetched", cache:get("fetch_key"))
        end)

        it("should fetch values (cache hit)", function()
            cache:set("hit_key", "already_here")
            local called = false
            local val = cache:fetch("hit_key", function()
                called = true
                return "new"
            end)
            assert.is_false(called)
            assert.equals("already_here", val)
        end)

        it("should clear all data", function()
            cache:set("a", 1)
            cache:clear()
            assert.is_nil(cache:get("a"))
        end)
    end)

    describe("File Adapter", function()
        local cache
        local test_dir = "tmp/test_cache"

        before_each(function()
            cache = cache_lib.new("file", { dir = test_dir })
        end)

        after_each(function()
            cache:clear()
            os.execute("rm -rf " .. test_dir)
        end)

        it("should persist values to disk", function()
            cache:set("persistent", { a = 1, b = 2 })
            assert.is_true(cache:exists("persistent"))
            
            local val = cache:get("persistent")
            assert.is_table(val)
            assert.equals(1, val.a)
        end)
    end)

    describe("Null Adapter", function()
        local cache

        before_each(function()
            cache = cache_lib.new("null")
        end)

        it("should never return values", function()
            cache:set("key", "value")
            assert.is_nil(cache:get("key"))
            assert.is_false(cache:exists("key"))
        end)
    end)

    describe("Performance Information", function()
        it("should demonstrate speed improvement", function()
            local cache = cache_lib.new("memory")
            local key = "perf_test"
            local data = { some = "complex", table = "with", values = 123 }
            
            -- Measure No Cache (Simulated work)
            local start_no_cache = os.clock()
            local res_no_cache
            for i=1, 1000 do
                res_no_cache = { some = "complex", table = "with", values = 123 }
            end
            local time_no_cache = os.clock() - start_no_cache

            -- Measure Cache Hit
            cache:set(key, data)
            local start_cache = os.clock()
            local res_cache
            for i=1, 1000 do
                res_cache = cache:get(key)
            end
            local time_cache = os.clock() - start_cache

            print("\n" .. string.rep("-", 40))
            print("CACHE PERFORMANCE INFO (Level 2)")
            print(string.format("  No Cache (1k ops): %.6fs", time_no_cache))
            print(string.format("  Cache Hit (1k ops): %.6fs", time_cache))
            if time_cache > 0 then
                print(string.format("  Speedup: %.1fx faster", time_no_cache / time_cache))
            end
            print(string.rep("-", 40) .. "\n")
            
            assert.is_not_nil(res_cache)
        end)
    end)
end)
