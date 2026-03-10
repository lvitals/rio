if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the 'busted' test runner.")
    print("Usage: busted " .. (arg and arg[0] or "test/high_concurrency_test.lua"))
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local cqueues = require("cqueues")
local http_request = require("http.request")
local rio = require("rio")
local Server = require("rio.server")

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
            cq = cq 
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
        local timeout = 15
        local deadline = cqueues.monotime() + timeout
        
        while (completed + errors_count) < REQUEST_COUNT and cqueues.monotime() < deadline do
            local ok, err = cq:step(0.1)
            if not ok then
                print("Event Loop Step Error: " .. tostring(err))
                break
            end
        end

        local end_time = cqueues.monotime()
        local duration = end_time - start_time

        print(string.format("\n  [Benchmark Performance]"))
        print(string.format("  Total Requests: %d", REQUEST_COUNT))
        print(string.format("  Successful:     %d", completed))
        print(string.format("  Errors:         %d", errors_count))
        print(string.format("  Time Elapsed:   %.4fs", duration))
        print(string.format("  Throughput:     %.2f req/s", completed / duration))
        
        if errors_count > 0 then
            print(string.format("  Last Recorded Error: %s", tostring(last_error)))
        end

        -- Cleanup
        app:close()

        assert.equals(REQUEST_COUNT, completed, "Some requests failed to process correctly")
        assert.is_true(duration < 3, "Throughput is too low for cooperative concurrency")
    end)
end)
