local luasql = require("luasql.sqlite3")
local env = luasql.sqlite3()
local conn = env:connect("repro.sqlite3")

conn:execute("DROP TABLE IF EXISTS test")
conn:execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")

local cur = conn:execute("SELECT * FROM test WHERE id = 1")
print("Cursor for empty select: ", cur)
if cur then
    local row = cur:fetch(nil, "a") -- fetch without table
    print("Row 1 (no table): ", row, type(row))
    if row then
        local count = 0
        for k, v in pairs(row) do count = count + 1 end
        print("  Col count: ", count)
    end
    
    cur:close()
end

conn:close()
env:close()
os.remove("repro.sqlite3")
