local luasql = require("luasql.postgres")
local env = luasql.postgres()
print("PostgreSQL Driver loaded successfully.")

-- Check for connection before proceeding
local conn, err = env:connect("postgres", "postgres", "123456", "127.0.0.1", 5432)
if not conn then
    print("\n[SKIP] PostgreSQL connection failed: " .. tostring(err))
    print("Ensure PostgreSQL is running with the correct credentials.\n")
    os.exit(0)
end
print("Database connection established.")

local cur = conn:execute("SELECT 1 as test")
local row = cur:fetch({}, "a")
print("Test query result: " .. tostring(row.test))

-- Verify the presence of our custom cooperative methods
if conn.getfd and conn.send_query then
    print("✅ COOPERATIVE METHODS DETECTED! (getfd, send_query)")
else
    print("❌ ERROR: Cooperative methods NOT found in the loaded driver.")
end

conn:close()
env:close()
print("Debug finished.")
