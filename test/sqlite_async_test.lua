-- test/sqlite_async_test.lua
local luasql = require("luasql.sqlite3")
local env = luasql.sqlite3()
local conn = env:connect(":memory:")

print("--- Testing SQLite Async-like Methods ---")

local methods = {
    "getfd",
    "send_query",
    "consume_input",
    "is_busy",
    "get_result"
}

for _, method in ipairs(methods) do
    if type(conn[method]) == "function" then
        print(string.format("✅ Method conn:%s exists", method))
    else
        print(string.format("❌ Method conn:%s MISSING", method))
    end
end

-- Test getfd
local fd = conn:getfd()
print(string.format("FD returned: %d", fd))
if fd >= 0 then
    print("✅ getfd returned a valid descriptor")
else
    print("❌ getfd returned an invalid descriptor")
end

-- Test async flow: send_query -> get_result
print("\nTesting async flow (send_query -> get_result)...")

-- 1. Create table
local ok = conn:send_query("CREATE TABLE test (id INTEGER, name TEXT)")
if ok then
    local res = conn:get_result()
    print("Table created:", res)
end

-- 2. Insert data
ok = conn:send_query("INSERT INTO test VALUES (?, ?)", 1, "Rio Framework")
if ok then
    local affected = conn:get_result()
    print("Rows inserted:", affected)
end

-- 3. Select data
ok = conn:send_query("SELECT * FROM test")
if ok then
    local cur = conn:get_result()
    if type(cur) == "userdata" then
        print("✅ Query returned a cursor")
        local row = cur:fetch({}, "a")
        if row and row.id == 1 and row.name == "Rio Framework" then
            print("✅ Data retrieved successfully:", row.name)
        else
            print("❌ Data mismatch or fetch failed")
        end
        cur:close()
    else
        print("❌ get_result did not return a cursor for SELECT")
    end
end

conn:close()
env:close()
print("\n--- Test Finished ---")
