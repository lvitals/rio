-- test/benchmark_adapters_test.lua
-- Asynchronous Performance Benchmark for Rio Database Adapters
-- 
-- DESCRIPTION:
-- This test evaluates the non-blocking throughput of the database adapters.
-- It fires thousands of concurrent queries using cqueues workers to ensure 
-- the event loop is never blocked and the connection pool handles high loads properly.

require "test.spec_helper"
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

describe("Rio Framework Async Adapters Benchmark", function()

    local function run_benchmark(adapter_name, config, multi_statement)
        local mode_label = multi_statement and "(Multi-Statement)" or "(Single Statement)"
        it("should benchmark " .. adapter_name .. " throughput " .. mode_label, function()
            local ok, err = pcall(db_manager.initialize, config)
            
            -- Perform a ping to verify credentials and network before throwing 2000 concurrent errors
            local ping_ok, ping_err = pcall(function()
                return db_manager.query("SELECT 1")
            end)

            if not ok or not ping_ok or (type(ping_err) == "string" and ping_err:match("error")) or ping_err == nil then
                ui.box(adapter_name:upper() .. " PERFORMANCE " .. mode_label, function()
                    ui.status("Status", false, "Skipped (Connection/Auth Failed)")
                end)
                pending("Database connection or authentication failed, skipping benchmark")
                return
            end

            local cq = cqueues.new()
            local errors = 0
            local completed = 0
            
            local start_time = cqueues.monotime()

            -- A worker function that keeps pulling tasks until we reach NUM_QUERIES
            local sql = multi_statement and "SELECT 1 as val; SELECT 2 as val;" or "SELECT 1 as val"
            local function worker()
                while true do
                    if completed >= NUM_QUERIES then break end
                    
                    -- Simulate work
                    local res, q_err = db_manager.execute_async(sql)
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

            assert.is_true(success, "Cqueues loop error: " .. tostring(cq_err))

            local total_time = end_time - start_time
            local throughput = NUM_QUERIES / total_time

            ui.box(adapter_name:upper() .. " PERFORMANCE " .. mode_label, function()
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
            
            assert.equals(0, errors, adapter_name .. " encountered errors during benchmark")
        end)
    end

    run_benchmark("sqlite", configs.sqlite, false)
    run_benchmark("postgres", configs.postgres, false)
    run_benchmark("postgres", configs.postgres, true)
    run_benchmark("mysql", configs.mysql, false)
    run_benchmark("mysql", configs.mysql, true)

end)