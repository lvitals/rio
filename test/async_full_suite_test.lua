require "test.spec_helper"
local ok_cq, cqueues = pcall(require, "cqueues")
if not ok_cq then
    -- Robust Mock for cqueues if not available
    cqueues = {
        new = function()
            return {
                wrap = function(self, fn) self.fn = fn end,
                loop = function(self) 
                    local co = coroutine.create(self.fn)
                    local ok, err = coroutine.resume(co)
                    if not ok then return false, err end
                    return true
                end
            }
        end,
        monotime = os.clock
    }
    package.loaded.cqueues = { poll = function() end }
end

local manager = require("rio.database.manager")
local Model = require("rio.database.model")
local ui = require("rio.utils.ui")
local colors = require("rio.utils.compat").colors
local etl = require("rio.utils.etl")

-- Helper to print results as SQL Table
local function print_sql_table(results, title)
    if title then ui.text("\n  " .. colors.bold .. colors.yellow .. "❯ " .. title .. colors.reset, "") end
    if not results or #results == 0 then
        ui.text(colors.gray .. "    (Empty result set)" .. colors.reset, "")
        return
    end

    local data = results
    if results[1] and type(results[1]) == "table" and not results[1][1] and next(results[1]) then
        -- Standard single result set
    elseif results[1] and type(results[1]) == "table" and results[1][1] then
        -- Multiple result sets (Multi-statement)
        for i, set in ipairs(results) do
            print_sql_table(set, "Result Set #" .. i)
        end
        return
    end

    local cols = {}
    for k, _ in pairs(data[1]) do table.insert(cols, k) end
    table.sort(cols)

    local widths = {}
    for _, col in ipairs(cols) do
        widths[col] = #col
        for _, row in ipairs(data) do
            local val = tostring(row[col] or "NULL")
            widths[col] = math.max(widths[col], #val)
        end
    end

    local header = "    |"
    local separator = "    +"
    for _, col in ipairs(cols) do
        header = header .. " " .. col .. string.rep(" ", widths[col] - #col) .. " |"
        separator = separator .. string.rep("-", widths[col] + 2) .. "+"
    end
    ui.text(separator, "")
    ui.text(header, "")
    ui.text(separator, "")

    for _, row in ipairs(data) do
        local line = "    |"
        for _, col in ipairs(cols) do
            local val = tostring(row[col] or "NULL")
            line = line .. " " .. val .. string.rep(" ", widths[col] - #val) .. " |"
        end
        ui.text(line, "")
    end
    ui.text(separator, "")
end

local User = Model:extend({
    table_name = "users",
    fillable = {"name", "email"}
})

local configs = {
    sqlite = { adapter = "sqlite", database = "test_full_async.db", pool = 5 },
    mysql = { adapter = "mysql", database = "test", username = "root", password = "123456", host = "127.0.0.1", pool = 5 },
    postgres = { adapter = "postgres", database = "postgres", username = "postgres", password = "postgres", host = "127.0.0.1", pool = 5 }
}

describe("Rio Framework Full Async API Suite", function()
    local function run_db_suite(adapter_name, config)
        it("should successfully execute full async suite for " .. adapter_name, function()
            local success = true
            ui.box("FULL ASYNC SUITE: " .. adapter_name:upper(), function()
                -- 1. Initialize and Check Connection
                local ok, err = pcall(manager.initialize, config)
                if not ok then
                    ui.warn("Skipping " .. adapter_name:upper() .. ": Driver or initialization failed.")
                    pending("Skipping " .. adapter_name:upper() .. ": Driver or initialization failed.")
                    return
                end

                -- Ping test
                local conn, c_err = manager.get_connection()
                if not conn then
                    ui.warn("Skipping " .. adapter_name:upper() .. ": Could not connect to database server.")
                    if c_err then ui.text("Details: " .. tostring(c_err), colors.gray) end
                    pending("Skipping " .. adapter_name:upper() .. ": Could not connect to database server.")
                    return
                end
                manager.release_connection(conn)

                local adapter = manager.get_adapter()
                local pk_def = adapter.get_pk_definition()
                local table_opts = adapter.get_table_options() or ""

                -- Setup Table
                ui.info("Preparing test table...")
                local dt_type = adapter.get_sql_type("datetime")
                local _, drop_err = pcall(manager.query, "DROP TABLE IF EXISTS users")
                local _, create_ok = pcall(manager.query, string.format("CREATE TABLE users (%s, name VARCHAR(255), email VARCHAR(255), created_at %s, updated_at %s) %s", pk_def, dt_type, dt_type, table_opts))
                
                if not create_ok then
                    ui.error("Failed to create test table for " .. adapter_name)
                    success = false
                    return
                end

                local cq = cqueues.new()
                
                local function bench(label, fn)
                    local start = cqueues.monotime()
                    local res, b_err = fn()
                    local duration = cqueues.monotime() - start
                    ui.status(label, res ~= nil, string.format("%.4f s", duration))
                    if not res and b_err then ui.error("Error: " .. tostring(b_err)); success = false end
                    return res
                end

                cq:wrap(function()
                    -- 1. db.async_query
                    bench("db.async_query", function()
                        local res, q_err = manager.async_query("SELECT 'Rio Framework' as name, 2026 as year")
                        if res then print_sql_table(res) end
                        return res, q_err
                    end)

                    -- 2. db.async_insert
                    local new_id = bench("db.async_insert", function()
                        return manager.async_insert("INSERT INTO users (name, email) VALUES (?, ?)", {"Leandro", "leandro@rio.io"})
                    end)

                    -- 3. Model:async_create
                    bench("Model:async_create", function()
                        local u, inst = User:async_create({name = "Async User", email = "async@rio.io"})
                        if u then print_sql_table({u._attributes}, "New User Attributes") end
                        return u, inst
                    end)

                    -- 4. Model:async_find
                    bench("Model:async_find", function()
                        if not new_id then return nil, "No user ID" end
                        local found = User:async_find(new_id)
                        if found then print_sql_table({found._attributes}, "Found User #" .. tostring(new_id)) end
                        return found
                    end)

                    -- 5. Model:async_all
                    bench("Model:async_all", function()
                        local all = User:async_all()
                        if not all then return nil, "Error fetching all users" end
                        local display = {}
                        for _, u in ipairs(all) do table.insert(display, u._attributes) end
                        print_sql_table(display, "All Users")
                        return all
                    end)

                    -- 6. Multi-Statement
                    if adapter_name ~= "sqlite" then
                        bench("Multi-Statement", function()
                            local sql = "INSERT INTO users (name, email) VALUES ('Multi 1', 'm1@rio.io'); SELECT COUNT(*) as total FROM users"
                            local res, m_err = manager.async_query(sql)
                            if res then print_sql_table(res, "Multi-Statement Results") end
                            return res, m_err
                        end)
                    end
                end)
                
                local ok, loop_err = cq:loop()
                if not ok then
                    print(colors.red .. "CQUEUES ERROR: " .. tostring(loop_err) .. colors.reset)
                    success = false
                end
                
                if success then
                    ui.success(adapter_name:upper() .. " suite finished.")
                end
            end)
            
            assert.is_true(success, "One or more tests failed in " .. adapter_name .. " suite")
        end)
    end

    run_db_suite("sqlite", configs.sqlite)
    run_db_suite("mysql", configs.mysql)
    run_db_suite("postgres", configs.postgres)
end)
