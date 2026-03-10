-- test/sqlite_benchmark_test.lua
package.path = "./lib/?.lua;./lib/?/init.lua;" .. package.path

local cqueues = require("cqueues")
local sqlite = require("rio.database.adapters.sqlite")

local config = {
    database = "/tmp/rio_benchmark.db",
    pool = 10
}

os.remove(config.database)
sqlite.initialize(config)

-- Setup
local conn, env = sqlite.get_connection()
conn:execute("CREATE TABLE test (id INTEGER, val TEXT)")
sqlite.release_connection(conn, env)

local cq = cqueues.new()
local num_queries = 10
local completed = 0

print("\n--- Rio Framework: SQLite Cooperative Benchmark ---")
print("Executing " .. num_queries .. " concurrent tasks...")

local start_time = cqueues.monotime()

for i = 1, num_queries do
    cq:wrap(function()
        -- Simulate some work before query
        cqueues.sleep(0.5)
        
        local res = sqlite.query("SELECT " .. i .. " as id")
        
        -- Simulate some work after query
        cqueues.sleep(0.5)
        
        if res and res[1] and tonumber(res[1].id) == i then
            completed = completed + 1
        end
    end)
end

cq:loop()
local duration = cqueues.monotime() - start_time

print("--------------------------------------------------")
print(string.format("Total tasks: %d", num_queries))
print(string.format("Success: %d", completed))
print(string.format("Total time: %.4f seconds", duration))

if completed == num_queries and duration < 2 then
    print("\n✅ SUCCESS! SQLite operations integrated with cqueues loop.")
else
    print("\n❌ FAILURE: Concurrency issues or errors.")
end

os.remove(config.database)
