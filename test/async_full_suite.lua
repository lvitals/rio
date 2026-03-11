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
    -- Mocking poll in package.loaded for the adapters
    package.loaded.cqueues = { poll = function() end }
end
local manager = require("rio.database.manager")
local Model = require("rio.database.model")
local ui = require("rio.utils.ui")
local colors = require("rio.utils.compat").colors
local etl = require("rio.utils.etl")

-- Helper to print results as SQL Table
local function print_sql_table(results, title)
    if title then print("\n  " .. colors.bold .. colors.yellow .. "❯ " .. title .. colors.reset) end
    if not results or #results == 0 then
        print(colors.gray .. "    (Empty result set)" .. colors.reset)
        return
    end

    -- Handle single result or array of result sets
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

    -- Get column names
    local cols = {}
    for k, _ in pairs(data[1]) do table.insert(cols, k) end
    table.sort(cols)

    -- Calculate widths
    local widths = {}
    for _, col in ipairs(cols) do
        widths[col] = #col
        for _, row in ipairs(data) do
            local val = tostring(row[col] or "NULL")
            widths[col] = math.max(widths[col], #val)
        end
    end

    -- Print Header
    local header = "    |"
    local separator = "    +"
    for _, col in ipairs(cols) do
        header = header .. " " .. col .. string.rep(" ", widths[col] - #col) .. " |"
        separator = separator .. string.rep("-", widths[col] + 2) .. "+"
    end
    print(separator)
    print(header)
    print(separator)

    -- Print Rows
    for _, row in ipairs(data) do
        local line = "    |"
        for _, col in ipairs(cols) do
            local val = tostring(row[col] or "NULL")
            line = line .. " " .. val .. string.rep(" ", widths[col] - #val) .. " |"
        end
        print(line)
    end
    print(separator)
end

-- Helper to print JSON
local function print_json(data, title)
    if etl and etl.to_json then
        if title then print("    " .. colors.gray .. title .. colors.reset) end
        print("    " .. colors.cyan .. etl.to_json(data) .. colors.reset)
    end
end

-- Define Model
local User = Model:extend({
    table_name = "users",
    fillable = {"name", "email"}
})

local configs = {
    sqlite = { adapter = "sqlite", database = "test_full_async.db", pool = 5 },
    mysql = { adapter = "mysql", database = "test", username = "root", password = "123456", host = "127.0.0.1", pool = 5 },
    postgres = { adapter = "postgres", database = "postgres", username = "postgres", password = "postgres", host = "127.0.0.1", pool = 5 }
}

local function run_db_suite(adapter_name, config)
    ui.box("FULL ASYNC SUITE: " .. adapter_name:upper(), function()
        -- 1. Initialize and Check Connection
        local ok, err = pcall(manager.initialize, config)
        if not ok then
            ui.warn("Skipping " .. adapter_name:upper() .. ": Driver or initialization failed.")
            return
        end

        -- Ping test
        local conn, c_err = manager.get_connection()
        if not conn then
            ui.warn("Skipping " .. adapter_name:upper() .. ": Could not connect to database server.")
            if c_err then ui.text("Details: " .. tostring(c_err), colors.gray) end
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
            return
        end

        local function bench(label, fn)
            local start = cqueues.monotime()
            local res, b_err = fn()
            local duration = cqueues.monotime() - start
            ui.status(label, res ~= nil, string.format("%.4f s", duration))
            if not res and b_err then ui.error("Error: " .. tostring(b_err)) end
            return res
        end

        -- 1. db.async_query
        bench("db.async_query", function()
            local res, q_err = manager.async_query("SELECT 'Rio Framework' as name, 2026 as year")
            if res then 
                print_sql_table(res) 
                print_json(res, "JSON Output:")
            end
            return res, q_err
        end)

        -- 2. db.async_insert
        local new_id = bench("db.async_insert", function()
            return manager.async_insert("INSERT INTO users (name, email) VALUES (?, ?)", {"Leandro", "leandro@rio.io"})
        end)

        -- 3. Model:async_create
        local user = bench("Model:async_create", function()
            local u, c_err = User:async_create({name = "Async User", email = "async@rio.io"})
            if u then 
                print_sql_table({u._attributes}, "New User Attributes") 
                print_json(u._attributes, "JSON Output:")
            end
            return u, c_err
        end)

        -- 4. Model:async_find
        bench("Model:async_find", function()
            local found = User:async_find(new_id)
            if found then 
                print_sql_table({found._attributes}, "Found User #" .. tostring(new_id)) 
                print_json(found._attributes, "JSON Output:")
            end
            return found
        end)

        -- 5. Model:async_all
        bench("Model:async_all", function()
            local all = User:async_all()
            local display = {}
            for _, u in ipairs(all) do table.insert(display, u._attributes) end
            print_sql_table(display, "All Users")
            print_json(display, "JSON Output (All):")
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

        ui.success(adapter_name:upper() .. " suite finished.")
    end)
end

local cq = cqueues.new()
cq:wrap(function()
    -- Run one by one for clear output
    run_db_suite("sqlite", configs.sqlite)
    run_db_suite("mysql", configs.mysql)
    run_db_suite("postgres", configs.postgres)
end)

local ok, loop_err = cq:loop()
if not ok then
    print(colors.red .. "CQUEUES ERROR: " .. tostring(loop_err) .. colors.reset)
end
