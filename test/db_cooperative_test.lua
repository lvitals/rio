-- LUA_CPATH should point to our compiled driver
package.path = "./lib/?.lua;./lib/?/init.lua;" .. package.path

local cqueues = require("cqueues")
local postgres = require("rio.database.adapters.postgres")

-- Official configuration used by Rio
local config = {
    database = "postgres",
    username = "postgres",
    password = "123456",
    host = "127.0.0.1",
    port = 5432,
    pool = 20
}

-- Initialize the adapter singleton in the framework
postgres.initialize(config)

-- Check if PostgreSQL is available before running the benchmark
print("Checking PostgreSQL connection...")
local test_conn, test_env = pcall(postgres.get_connection)
if not test_conn or not test_env then
    print("\n[SKIP] PostgreSQL service not found or connection failed.")
    print("Please ensure PostgreSQL is installed and running with the provided credentials.")
    print("Benchmark skipped.\n")
    os.exit(0)
end
postgres.release_connection(test_env, test_env) -- release the test connection
print("PostgreSQL connection verified.")

-- Pre-warm the connection pool
print("Pre-warming connection pool...")
local temp_conns = {}
for i = 1, 10 do
    local conn, env = postgres.get_connection()
    if conn then
        table.insert(temp_conns, {conn, env})
    end
end
for _, pair in ipairs(temp_conns) do
    postgres.release_connection(pair[1], pair[2])
end
print("Pool ready with " .. #temp_conns .. " connections.")

local cq = cqueues.new()
local num_queries = 10
local completed = 0

print("\n--- Rio Framework: Cooperative Database Benchmark ---")
print("Executing " .. num_queries .. " queries of 1 second concurrently...")

local start_time = cqueues.monotime()

for i = 1, num_queries do
    cq:wrap(function()
        -- Call query through the official module interface
        -- This will use the internal singleton configured above
        local res, err = postgres.query("SELECT pg_sleep(1), " .. i .. " as id")
        
        if res and res[1] then
            print(string.format("  [%d] Completed! Returned id = %s", i, tostring(res[1].id)))
            completed = completed + 1
        else
            print(string.format("  [%d] ERROR: %s", i, tostring(err)))
        end
    end)
end

-- Run loop until all coroutines finish
local ok, err = cq:loop()
if not ok then print("Loop Error:", err) end

local duration = cqueues.monotime() - start_time

print("--------------------------------------------------")
print(string.format("Total queries: %d", num_queries))
print(string.format("Success: %d", completed))
print(string.format("Total time: %.4f seconds", duration))

if completed == num_queries and duration < 2 then
    print("\n✅ ABSOLUTE SUCCESS! Database operated in cooperative parallel mode.")
    print("Rio Framework is now FULLY non-blocking, including database access!")
else
    print("\n❌ FAILURE: Concurrency was not achieved or connection errors occurred.")
end
