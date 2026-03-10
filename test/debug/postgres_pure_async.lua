local cqueues = require("cqueues")
local luasql = require("luasql.postgres")

local env = luasql.postgres()

-- Verify connection and pre-connect 5 sockets for the benchmark
print("Verifying database connectivity...")
local conns = {}
for i = 1, 5 do
    local conn, err = env:connect("postgres", "postgres", "123456", "127.0.0.1", 5432)
    if not conn then
        print("\n[SKIP] Database connection failed for socket " .. i .. ": " .. tostring(err))
        -- Cleanup any established connections
        for _, c in ipairs(conns) do c:close() end
        env:close()
        os.exit(0)
    end
    table.insert(conns, conn)
end
print("5 connections established and ready.")

local function run_async_query(id, conn)
    local fd = conn:getfd()
    print(string.format("[%d] Sending query on FD %d...", id, fd))
    
    -- PQsendQuery will be used via the C binding
    conn:send_query("SELECT pg_sleep(1)")
    
    local start_q = cqueues.monotime()
    while conn:is_busy() do
        -- Cooperative yield of 10ms to allow other coroutines to progress.
        -- This proven to be the key for real parallelism in the Postgres driver.
        cqueues.sleep(0.01) 
        conn:consume_input()
    end
    
    local res = conn:get_result()
    print(string.format("[%d] Completed in %.2fs!", id, cqueues.monotime() - start_q))
end

local cq = cqueues.new()
for i = 1, 5 do
    cq:wrap(function() run_async_query(i, conns[i]) end)
end

print("\n--- Starting Pure Asynchronous Parallel Benchmark ---")
local start = cqueues.monotime()
cq:loop()
local duration = cqueues.monotime() - start

-- Cleanup
for _, c in ipairs(conns) do c:close() end
env:close()

print("--------------------------------------------------")
print(string.format("Total execution time: %.2f seconds", duration))

if duration < 2 then
    print("\n✅ SUCCESS: Queries ran in parallel (took ~1s for 5x 1s queries).")
else
    print("\n❌ FAILURE: Queries ran sequentially (took >5s). Check C driver implementation.")
end
