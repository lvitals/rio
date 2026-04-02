require "test.spec_helper"
local manager = require("rio.database.manager")
local test_config = require("test.test_config")

describe("Rio Framework - Unified Async Database API", function()
    
    local function test_async_query(adapter_name)
        it("should execute async queries successfully via " .. adapter_name .. " adapter", function()
            -- Initialize adapter using centralized config with context
            if test_config.skip_if_no_db(adapter_name, "Unified Async: " .. adapter_name) then return end
            local config = test_config.configs[adapter_name]
            manager.initialize(config)

            -- Determine SQL based on database type for sleep simulation
            local sql = "SELECT 'Async OK' as msg"
            if adapter_name == "postgres" then
                sql = "SELECT pg_sleep(0.1), 'Postgres Async OK' as msg"
            elseif adapter_name == "mysql" then
                sql = "SELECT sleep(0.1), 'MySQL Async OK' as msg"
            end

            -- Execute Async
            local res, err = manager.execute_async(sql)
            
            -- Validations
            assert.is_nil(err)
            assert.is_table(res)
            
            if adapter_name ~= "sqlite" then
                local label = adapter_name == "mysql" and "MySQL" or "Postgres"
                assert.are.equal(label .. " Async OK", res[1].msg)
            else
                assert.are.equal("Async OK", res[1].msg)
            end
        end)
    end

    -- 1. SQLite3 (Non-blocking FD simulation)
    describe("SQLite3 Adapter", function()
        test_async_query("sqlite")
    end)

    -- 2. PostgreSQL (Native non-blocking)
    describe("PostgreSQL Adapter", function()
        test_async_query("postgres")
    end)

    -- 3. MySQL/MariaDB (Native non-blocking)
    describe("MySQL Adapter", function()
        test_async_query("mysql")
    end)

end)
