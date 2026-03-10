if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the \"busted\" test runner.")
    print("Usage: busted test/core/cache_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

-- test/spec/cache_ttl_test.lua
local rio = require("rio")
local posix = require("posix.signal")

describe("Rio Application Cache (Level 2) with TTL", function()
    local app_memory, app_file

    setup(function()
        -- Application with memory cache
        app_memory = rio.new({
            cache_store = "memory",
            perform_caching = true
        })

        -- Application with file cache
        app_file = rio.new({
            cache_store = "file",
            perform_caching = true
        })
    end)

    it("should work with memory cache and TTL", function()
        local key = "test_memory_ttl"
        local call_count = 0
        local function get_data()
            call_count = call_count + 1
            return "data_" .. call_count
        end

        -- First call: MISS, stores in cache
        local val1 = app_memory.cache:fetch(key, 1, get_data)
        assert.equals("data_1", val1)
        assert.equals(1, call_count)

        -- Second call (immediate): HIT, uses cache
        local val2 = app_memory.cache:fetch(key, 1, get_data)
        assert.equals("data_1", val2)
        assert.equals(1, call_count)

        -- Wait for TTL to expire
        RioUI.info("Waiting 2 seconds for memory cache TTL...")
        os.execute("sleep 2")

        -- Third call (after sleep): MISS, cache expired, executes callback
        local val3 = app_memory.cache:fetch(key, 1, get_data)
        assert.equals("data_2", val3)
        assert.equals(2, call_count)
    end)

    it("should work with file cache and TTL", function()
        local key = "test_file_ttl"
        local call_count = 0
        local function get_data()
            call_count = call_count + 1
            return "data_" .. call_count
        end

        -- Clean up just in case
        app_file.cache:delete(key)

        -- First call: MISS
        local val1 = app_file.cache:fetch(key, 1, get_data)
        assert.equals("data_1", val1)
        assert.equals(1, call_count)

        -- Second call (immediate): HIT
        local val2 = app_file.cache:fetch(key, 1, get_data)
        assert.equals("data_1", val2)
        assert.equals(1, call_count)

        -- Wait for TTL
        RioUI.info("Waiting 2 seconds for file cache TTL...")
        os.execute("sleep 2")

        -- Third call: MISS
        local val3 = app_file.cache:fetch(key, 1, get_data)
        assert.equals("data_2", val3)
        assert.equals(2, call_count)
    end)

    it("should store and retrieve tables correctly in file cache", function()
        local key = "test_table_file"
        local my_table = { name = "Rio", features = { "mvc", "api", "cache" }, version = 0.1 }
        
        app_file.cache:set(key, my_table, 60)
        local retrieved = app_file.cache:get(key)
        
        assert.is_table(retrieved)
        assert.equals("Rio", retrieved.name)
        assert.equals("mvc", retrieved.features[1])
        assert.equals(0.1, retrieved.version)
    end)
end)
