if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the 'busted' test runner.")
    print("Usage: busted test/integration/postgres_cooperative_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local cqueues = require("cqueues")
local postgres = require("rio.database.adapters.postgres")
local test_config = require("test.test_config")

local DEFAULT_QUERY_DELAY_SECONDS = 1
local DEFAULT_QUERY_MULTIPLIER = 2
local DEFAULT_SEQUENTIAL_DURATION_FRACTION = 0.75

local function positive_number(value, fallback)
    local number = tonumber(value)
    if number and number > 0 then
        return number
    end
    return fallback
end

describe("Rio PostgreSQL Cooperative Concurrency", function()
    local adapter_name = "postgres"
    local config = test_config.configs[adapter_name]

    setup(function()
        if test_config.check_connection(adapter_name) then
            postgres.initialize(config)
        end
    end)

    it("should complete parallel delayed queries successfully", function()
        if test_config.skip_if_no_db(adapter_name, "PostgreSQL Cooperative") then return end
        local cq = cqueues.new()
        local pool_size = positive_number(config.pool, 1)
        local query_multiplier = positive_number(
            os.getenv("RIO_TEST_POSTGRES_CONCURRENCY_MULTIPLIER"),
            DEFAULT_QUERY_MULTIPLIER
        )
        local query_delay = positive_number(
            os.getenv("RIO_TEST_POSTGRES_QUERY_DELAY"),
            DEFAULT_QUERY_DELAY_SECONDS
        )
        local sequential_fraction = positive_number(
            os.getenv("RIO_TEST_POSTGRES_SEQUENTIAL_FRACTION"),
            DEFAULT_SEQUENTIAL_DURATION_FRACTION
        )
        local num_queries = math.max(1, math.floor(pool_size * query_multiplier))
        local sequential_duration = num_queries * query_delay
        local max_cooperative_duration = sequential_duration * sequential_fraction
        local completed = 0
        local start_time = cqueues.monotime()

        for i = 1, num_queries do
            cq:wrap(function()
                local res = postgres.query(
                    string.format("SELECT pg_sleep(%.6f), %d as id", query_delay, i)
                )
                if res and res[1] and tonumber(res[1].id) == i then
                    completed = completed + 1
                end
            end)
        end

        assert.is_true(cq:loop())
        local duration = cqueues.monotime() - start_time

        assert.equals(num_queries, completed)
        assert.is_true(
            duration < max_cooperative_duration,
            string.format(
                "Expected cooperative execution below %.4fs, got %.4fs. Sequential estimate: %.4fs.",
                max_cooperative_duration,
                duration,
                sequential_duration
            )
        )
        print(string.format(
            "PostgreSQL cooperative query duration: %.4fs (sequential estimate %.4fs)",
            duration,
            sequential_duration
        ))
    end)
end)
