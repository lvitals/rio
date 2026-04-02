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

local test_config = require("test.test_config")

local NUM_QUERIES = 2000 -- Total queries
local CONCURRENCY = 50   -- Match the pool size to avoid starvation

describe("Rio Framework Async Adapters Benchmark", function()

    local function run_benchmark(adapter_name, multi_statement)
        local mode_label = multi_statement and "(Multi-Statement)" or "(Single Statement)"
        it("should benchmark " .. adapter_name .. " throughput " .. mode_label, function()
            -- Unified pre-check with test context
            if test_config.skip_if_no_db(adapter_name, "Benchmark: " .. adapter_name .. " " .. mode_label) then return end
            
            local config = test_config.configs[adapter_name]
            -- Set pool to CONCURRENCY for benchmark
            config.pool = CONCURRENCY
            
            local ok, err = pcall(db_manager.initialize, config)
            if not ok then error("Driver failed: " .. tostring(err)) end

            local cq = cqueues.new()
            local errors = 0
            local completed = 0
            
            -- Pre-warm pool: ensure all workers have a connection ready
            local warm_cq = cqueues.new()
            for i = 1, CONCURRENCY do
                warm_cq:wrap(function()
                    local conn, env = db_manager.get_connection()
                    db_manager.release_connection(conn, env)
                end)
            end
            warm_cq:loop()

            local start_time = cqueues.monotime()

            -- A worker function that keeps pulling tasks until we reach NUM_QUERIES
            local statements_per_req = multi_statement and 2 or 1
            local total_workload = NUM_QUERIES * statements_per_req
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
            local throughput_req = NUM_QUERIES / total_time
            local throughput_stmt = total_workload / total_time

            ui.box(adapter_name:upper() .. " PERFORMANCE " .. mode_label, function()
                ui.status("Total Requests", true, tostring(NUM_QUERIES))
                ui.status("Statements/Req", true, tostring(statements_per_req))
                ui.status("Total Workload", true, tostring(total_workload) .. " results")
                ui.status("Concurrency", true, tostring(CONCURRENCY) .. " workers")
                ui.status("Total Time", true, string.format("%.4f s", total_time))
                ui.status("Throughput (Req/s)", true, string.format("%.2f", throughput_req))
                ui.status("Throughput (Stmt/s)", true, string.format("%.2f", throughput_stmt))
                if errors > 0 then
                    ui.status("Errors", false, tostring(errors))
                else
                    ui.status("Errors", true, "0")
                end
            end)
            
            assert.equals(0, errors, adapter_name .. " encountered errors during benchmark")
        end)
    end

    run_benchmark("sqlite", false)
    run_benchmark("postgres", false)
    run_benchmark("postgres", true)
    run_benchmark("mysql", false)
    run_benchmark("mysql", true)

end)
