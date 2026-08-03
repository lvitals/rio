require "test.spec_helper"
local compat = require("rio.utils.compat")
local cqueues = compat.cqueues

local manager = require("rio.database.manager")
local Model = require("rio.database.model")

local test_config = require("test.test_config")

local User = Model:extend({
    table_name = "users",
    fillable = {"name", "email"}
})

describe("Rio Framework Full Async API Suite", function()
    local function run_db_suite(adapter_name)
        it("should successfully execute full async suite for " .. adapter_name, function()
            -- Automated connectivity check and skip with context
            if test_config.skip_if_no_db(adapter_name, "Async Suite: " .. adapter_name) then return end
            
            local config = test_config.configs[adapter_name]
            local ok, err = pcall(manager.initialize, config)
            if not ok then error("Driver failed for " .. adapter_name .. ": " .. tostring(err)) end

            local adapter = manager.get_adapter()
            local pk_def = adapter.get_pk_definition()
            local table_opts = adapter.get_table_options() or ""
            local dt_type = adapter.get_sql_type("datetime")

            manager.query("DROP TABLE IF EXISTS users")
            local _, create_ok = pcall(manager.query, string.format("CREATE TABLE users (%s, name VARCHAR(255), email VARCHAR(255), created_at %s, updated_at %s) %s", pk_def, dt_type, dt_type, table_opts))
            if not create_ok then error("Failed to create table") end

            local results = {}
            local cq = cqueues.new()
            
            cq:wrap(function()
                local s = cqueues.monotime()
                local r, e = manager.async_query("SELECT 'Rio Framework' as name, 2026 as year")
                results.q1 = {res=r, err=e, dur=cqueues.monotime()-s}
                
                s = cqueues.monotime()
                local id, ie = manager.async_insert("INSERT INTO users (name, email) VALUES (?, ?)", {"Leandro", "leandro@rio.io"})
                results.q2 = {res=id, err=ie, dur=cqueues.monotime()-s}
                
                s = cqueues.monotime()
                local u, ie2 = User:async_create({name = "Async User", email = "async@rio.io"})
                results.q3 = {res=u, err=ie2, dur=cqueues.monotime()-s}
                
                s = cqueues.monotime()
                local found = User:async_find(id or 1)
                results.q4 = {res=found, dur=cqueues.monotime()-s}
                
                s = cqueues.monotime()
                local all = User:async_all()
                results.q5 = {res=all, dur=cqueues.monotime()-s}
                
                if adapter_name ~= "sqlite" then
                    s = cqueues.monotime()
                    local mres, merr = manager.async_query("INSERT INTO users (name, email) VALUES ('Multi 1', 'm1@rio.io'); SELECT COUNT(*) as total FROM users")
                    results.q6 = {res=mres, err=merr, dur=cqueues.monotime()-s}
                end
            end)
            
            local cq_ok = cq:loop()

            assert.is_true(cq_ok)
            assert.is_not_nil(results.q1.res)
            assert.is_nil(results.q1.err)
            assert.is_not_nil(results.q2.res)
            assert.is_not_nil(results.q3.res)
            assert.is_not_nil(results.q4.res)
            assert.is_not_nil(results.q5.res)

            if adapter_name ~= "sqlite" then
                assert.is_not_nil(results.q6.res)
            end
        end)
    end

    run_db_suite("sqlite")
    run_db_suite("mysql")
    run_db_suite("postgres")
end)
