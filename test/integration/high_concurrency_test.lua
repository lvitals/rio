local cqueues = require("cqueues")
local http_request = require("http.request")
local Server = require("rio.server")
local metrics = require("rio.testing.metrics")

-- Pre-load internal modules to avoid path resolution issues during high-concurrency coroutines
require("rio.database.manager")
require("rio.cable")
require("rio.core.adapters.standalone")

describe("Rio Framework High Concurrency Benchmark", function()
    local port, host
    local REQUEST_COUNT = 1000 -- Scale for benchmark

    setup(function()
        host = "127.0.0.1"
        port = 9091
    end)

    it("should handle " .. REQUEST_COUNT .. " concurrent requests using a shared event loop", function()
        local cq = cqueues.new()
        
        -- Server with shared cqueues controller for true cooperative concurrency
        local app = Server.new({ 
            perform_caching = false,
            app_name = "BenchmarkApp",
            cq = cq,
            quiet = true
        })
        
        -- Setup simple routes
        app:get("/ping", function(ctx)
            return ctx:text("pong", 200)
        end)

        app:get("/echo/:msg", function(ctx)
            return ctx:text(ctx.params.msg, 200)
        end)

        app:post("/data", function(ctx)
            local name = (ctx.body and ctx.body.name) or "unknown"
            return ctx:json({ received = name }, 201)
        end)

        local completed = 0
        local errors_count = 0
        local last_error = nil

        -- 1. Bootstrap and listen (registers to shared 'cq')
        app:bootstrap()
        app:listen(port, host)

        -- 2. Dispatch multiple request types in parallel
        local start_time = cqueues.monotime()
        
        for i = 1, REQUEST_COUNT do
            cq:wrap(function()
                local req
                local expected_body
                local target_port = port
                
                -- Mixed requests: 60% GET /ping, 20% GET /echo, 20% POST /data
                local r_type = i % 10
                if r_type < 6 then
                    req = http_request.new_from_uri(string.format("http://%s:%d/ping", host, target_port))
                    expected_body = "pong"
                elseif r_type < 8 then
                    local msg = "benchmark_" .. i
                    req = http_request.new_from_uri(string.format("http://%s:%d/echo/%s", host, target_port, msg))
                    expected_body = msg
                else
                    req = http_request.new_from_uri(string.format("http://%s:%d/data", host, target_port))
                    req.headers:upsert(":method", "POST")
                    req.headers:upsert("content-type", "application/x-www-form-urlencoded")
                    req:set_body("name=rio_benchmark_user_" .. i)
                    expected_body = '{"received":"rio_benchmark_user_' .. i .. '"}'
                end

                local headers, stream = req:go(10)
                
                if headers then
                    local body, _ = stream:get_body_as_string()
                    if body and (body == expected_body or body:find(expected_body, 1, true)) then
                        completed = completed + 1
                    else
                        errors_count = errors_count + 1
                        last_error = string.format("Mismatch at req %d. Expected: %s, Got: %s", i, expected_body, tostring(body))
                    end
                    stream:shutdown()
                else
                    errors_count = errors_count + 1
                    last_error = "Connection failed: " .. tostring(stream)
                end
            end)
        end

        -- 3. Run the shared loop until completion
        local timeout = tonumber(os.getenv("RIO_TEST_HTTP_TIMEOUT") or "30")
        local deadline = cqueues.monotime() + timeout
        
        while (completed + errors_count) < REQUEST_COUNT and cqueues.monotime() < deadline do
            local ok, err = cq:step(0.1)
            if not ok then
                last_error = "Event Loop Step Error: " .. tostring(err)
                errors_count = errors_count + 1
                break
            end
        end

        local end_time = cqueues.monotime()
        local duration = end_time - start_time

        -- Cleanup
        app:close()

        assert.equals(0, errors_count, tostring(last_error or "Requests completed with errors"))
        assert.equals(REQUEST_COUNT, completed, tostring(last_error or "Some requests failed to process correctly"))

        metrics.record(
            "HIGH CONCURRENCY BENCHMARK",
            "Throughput",
            string.format("%.2f req/s", completed / duration)
        )
    end)
end)
