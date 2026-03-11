-- benchmark_adapters.lua
-- Asynchronous Performance Benchmark for Rio Database Adapters

local cqueues = require("cqueues")
local condition = require("cqueues.condition")
local db_manager = require("rio.database.manager")
local ui = require("rio.utils.ui")

local NUM_QUERIES = 2000 -- Total queries
local CONCURRENCY = 50   -- Match the pool size to avoid starvation

local configs = {
    sqlite = { adapter = "sqlite", database = ":memory:", pool = 50 },
    postgres = { adapter = "postgres", database = "postgres", username = "postgres", password = "123456", host = "localhost", pool = 50 },
    mysql = { adapter = "mysql", database = "test", username = "root", password = "123456", host = "127.0.0.1", pool = 50 }
}

local function run_benchmark(adapter_name, config)
    ui.header("Benchmarking: " .. adapter_name:upper())
    
    local ok, err = pcall(db_manager.initialize, config)
    if not ok then
        ui.error("Failed to initialize " .. adapter_name .. ": " .. tostring(err))
        return
    end

    local cq = cqueues.new()
    local errors = 0
    local completed = 0
    local cv = condition.new()
    local active_coroutines = 0

    local start_time = cqueues.monotime()

    -- A worker function that keeps pulling tasks until we reach NUM_QUERIES
    local function worker()
        while true do
            if completed >= NUM_QUERIES then break end
            
            -- Simulate work
            local res, q_err = db_manager.execute_async("SELECT 1 as val")
            if not res then errors = errors + 1 end
            
            completed = completed + 1
        end
    end

    -- Start only CONCURRENCY number of workers
    for i = 1, CONCURRENCY do
        cq:wrap(worker)
    end

    local success, cq_err = cq:loop()
    local end_time = cqueues.monotime()

    if not success then
        ui.error("Cqueues loop error: " .. tostring(cq_err))
    end

    local total_time = end_time - start_time
    local throughput = NUM_QUERIES / total_time

    ui.box(adapter_name:upper() .. " Performance", function()
        ui.status("Total Queries", true, tostring(NUM_QUERIES))
        ui.status("Concurrency", true, tostring(CONCURRENCY) .. " workers")
        ui.status("Total Time", true, string.format("%.4f s", total_time))
        ui.status("Throughput", true, string.format("%.2f req/s", throughput))
        if errors > 0 then
            ui.status("Errors", false, tostring(errors))
        else
            ui.status("Errors", true, "0")
        end
    end)
    print("")
end

print("\n" .. ui.colors.cyan .. ui.colors.bold .. "=== RIO FRAMEWORK ASYNC ADAPTERS BENCHMARK ===" .. ui.colors.reset .. "\n")

run_benchmark("sqlite", configs.sqlite)
run_benchmark("postgres", configs.postgres)
run_benchmark("mysql", configs.mysql)

print(ui.colors.green .. "Benchmark completed successfully." .. ui.colors.reset)
