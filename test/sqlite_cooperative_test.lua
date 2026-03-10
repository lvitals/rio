-- test/sqlite_cooperative_test.lua
package.path = "./lib/?.lua;./lib/?/init.lua;" .. package.path

local cqueues = require("cqueues")
local sqlite = require("rio.database.adapters.sqlite")

local config = {
    database = "/tmp/rio_test_async.db",
    pool = 5
}

-- Cleanup old test DB
os.remove(config.database)

sqlite.initialize(config)

-- Create table
local conn, env = sqlite.get_connection()
conn:execute("CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)")
sqlite.release_connection(conn, env)

local cq = cqueues.new()
local num_queries = 100
local completed = 0

print("\n--- Rio Framework: SQLite Cooperative Test ---")
print("Executing " .. num_queries .. " operations concurrently via cqueues...")

local start_time = cqueues.monotime()

for i = 1, num_queries do
    cq:wrap(function()
        -- Test Insert
        local id = sqlite.insert("INSERT INTO users (name) VALUES (?)", {"User " .. i})
        
        -- Test Query
        local res, err = sqlite.query("SELECT * FROM users WHERE id = ?", {id})
        
        if res and res[1] and res[1].id == id then
            -- print(string.format("  [%d] Completed! Inserted ID %d and verified.", i, id))
            completed = completed + 1
        else
            print(string.format("  [%d] ERROR: %s", i, tostring(err or "Data mismatch")))
        end
    end)
end

local ok, err = cq:loop()
if not ok then print("Loop Error:", err) end

local duration = cqueues.monotime() - start_time

print("--------------------------------------------------")
print(string.format("Total operations: %d", num_queries))
print(string.format("Success: %d", completed))
print(string.format("Total time: %.4f seconds", duration))

if completed == num_queries then
    print("\n✅ SUCCESS! SQLite adapter worked perfectly with cqueues flow.")
else
    print("\n❌ FAILURE: Some operations failed.")
end

-- Final Cleanup
os.remove(config.database)
