-- rio/lib/rio/database/migrate.lua - Migration system
-- Compatible with Lua 5.1 and LuaSQL (SQLite, MySQL, PostgreSQL)

local DB = require("rio.database.manager")

-- Colors for output
local colors = {
    reset = "\27[0m",
    red = "\27[31m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    dim = "\27[2m"
}

local function print_header(text)
    if DB.verbose then print("\n" .. colors.blue .. "🌙 " .. text .. colors.reset .. "\n") end
end

local function print_success(text)
    if DB.verbose then print(colors.green .. "✓ " .. text .. colors.reset) end
end

local function print_error(text)
    print(colors.red .. "✗ " .. text .. colors.reset)
end

local function print_info(text)
    if DB.verbose then print(colors.yellow .. "ℹ " .. text .. colors.reset) end
end

local function print_debug(text)
    if DB.verbose then print(colors.dim .. "  " .. text .. colors.reset) end
end

local Migrate = {}

-- Executes pending migrations
function Migrate.run()
    print_header("Running Migrations")
    
    local conn, err = DB:get_connection()
    if not conn then
        print_error(tostring(err or "Failed to connect to the database."))
        return
    end
    
    local adapter_name = DB.get_adapter_name and DB.get_adapter_name() or "sqlite"
    local adapter = DB.get_adapter()
    
    -- Ensure migrations tracking mechanism exists (Table in SQL, Collection in NoSQL, etc)
    local _, err = adapter.ensure_migrations_table(conn)
    if err then
        print_error("Error creating migrations table: " .. tostring(err))
        return
    end
    
    -- Next batch
    local current_batch = adapter.get_last_batch(conn) + 1
    
    -- Executed migrations
    local executed = adapter.get_executed_migrations(conn)
    
    -- List files
    local handle = io.popen('ls db/migrate/*.lua 2>/dev/null | sort')
    if not handle then
        print_info("No migrations found in db/migrate/")
        return
    end
    local files_str = handle:read("*a")
    handle:close()
    
    if not files_str or files_str == "" then
        print_info("No migrations found in db/migrate/")
        return
    end
    
    local pending = 0
    for file in files_str:gmatch("[^\r\n]+") do
        local name = file:match("db/migrate/(.+)%.lua$")
        if name and not executed[name] then
            repeat -- Emulate continue
                pending = pending + 1
                print(colors.yellow .. "→ Migrating: " .. name .. colors.reset)
                
                local ok, mod = pcall(require, file:gsub("%.lua$", ""):gsub("/", "."))
                if not ok then
                    print_error("  Error loading: " .. tostring(mod))
                    break
                end
                
                local mig_inst = mod:new(conn, adapter_name)
                local sql = mig_inst:up()
                
                if type(sql) == "string" and sql ~= "" then
                    local res_ex, err_ex = conn:execute(sql)
                    if not res_ex then
                        print_error("  Execution failed: " .. tostring(err_ex))
                        break
                    end
                end
                
                -- Record execution in history
                adapter.record_migration(conn, name, current_batch)
                if conn.commit then conn:commit() end
                
                print_success("  Migrated successfully!")
            until true
        end
    end
    
    if pending == 0 then
        print_info("Nothing to migrate.")
    else
        print("")
        print_success(string.format("Total: %d migration(s) executed", pending))
    end
end

-- Rollback
function Migrate.rollback()
    print_header("Rolling Back Migrations")
    local conn, err = DB:get_connection()
    if not conn then
        print_error(tostring(err or "Failed to connect to the database."))
        return
    end
    local adapter_name = DB.get_adapter_name and DB.get_adapter_name() or "sqlite"
    local adapter = DB.get_adapter()

    local last_batch = adapter.get_last_batch(conn)
    if last_batch == 0 then
        print_info("No migrations to rollback.")
        return
    end

    local migrations_in_batch = adapter.get_migrations_by_batch(conn, last_batch)
    
    local rolled = 0
    for _, name in ipairs(migrations_in_batch) do
        repeat
            print(colors.yellow .. "→ Rolling back: " .. name .. colors.reset)
            local ok, mod = pcall(require, "db.migrate." .. name)
            if not ok then print_error("  Error loading: " .. tostring(mod)); break end
            
            local mig_inst = mod:new(conn, adapter_name)
            local sql = mig_inst:down()
            
            if type(sql) == "string" and sql ~= "" then
                local res_ex, err_ex = conn:execute(sql)
                if not res_ex then print_error("  Rollback failed: " .. tostring(err_ex)); break end
            end
            
            -- Remove from history record
            adapter.remove_migration_record(conn, name)
            if conn.commit then conn:commit() end
            rolled = rolled + 1
            print_success("  Rolled back successfully!")
        until true
    end
    print_success(string.format("Total: %d migration(s) rolled back", rolled))
end

-- Status
function Migrate.status()
    print_header("Migration Status")
    local conn, err = DB:get_connection()
    if not conn then
        print_error(tostring(err or "Failed to connect to the database."))
        return
    end
    local adapter = DB.get_adapter()

    local executed = adapter.get_executed_migrations(conn)
    local handle = io.popen('ls db/migrate/*.lua 2>/dev/null | sort')
    local files_str = handle and handle:read("*a") or ""
    if handle then handle:close() end
    
    print(string.format("%-10s %s", "Status", "Migration"))
    print(string.rep("-", 80))
    for file in files_str:gmatch("[^\r\n]+") do
        local name = file:match("db/migrate/(.+)%.lua$")
        if name then
            if executed[name] then print(string.format("%sUp%s   %s", colors.green, colors.reset, name))
            else print(string.format("%sDown%s %s", colors.red, colors.reset, name)) end
        end
    end
end

-- Get current version
function Migrate.version()
    local conn, err = DB:get_connection()
    if not conn then
        print_error(tostring(err or "Failed to connect to the database."))
        return nil
    end
    local adapter = DB.get_adapter()

    -- Try to get the last executed migration name
    local executed = adapter.get_executed_migrations(conn)
    local last_version = "0"
    
    -- Sort names to find the latest (timestamps)
    local names = {}
    for name, _ in pairs(executed) do
        table.insert(names, name)
    end
    table.sort(names)
    
    if #names > 0 then
        local latest = names[#names]
        -- Usually migration names start with YYYYMMDDHHMMSS
        last_version = latest:match("^(%d+)") or latest
    end
    
    return last_version
end

-- Create database
function Migrate.create(db_config)
    print("Creating database...")
    if not db_config then return end
    local ok, err = DB.create_database(db_config)
    if ok then print_success("Database created successfully.")
    else print_error("Error creating database: " .. tostring(err)) end
    return ok
end

-- Drop database
function Migrate.drop(db_config)
    print("Dropping database...")
    if not db_config then return end
    local ok, err = DB.drop_database(db_config)
    if ok then print_success("Database dropped successfully.")
    else print_error("Error dropping database: " .. tostring(err)) end
    return ok
end

-- Seed database
function Migrate.seed()
    print_header("Seeding Database")
    local conn, err = DB:get_connection()
    if not conn then
        print_error(tostring(err or "Failed to connect to the database."))
        return
    end
    
    local ok, err_req = pcall(require, "db.seeds")
    if ok then print_success("Database seeded successfully.")
    else print_error("Error seeding database: " .. tostring(err_req)) end
end

-- Setup: Create + Migrate + Seed
function Migrate.setup(db_config)
    print_header("Setting up Database")
    Migrate.create(db_config)
    Migrate.run()
    Migrate.seed()
    print("\n" .. colors.green .. "Database setup complete." .. colors.reset)
end

-- Reset: Drop + Setup
function Migrate.reset(db_config)
    print_header("Resetting Database")
    Migrate.drop(db_config)
    Migrate.setup(db_config)
end

function Migrate.exec(args)
    local cmd = args[1] or "status"
    if cmd == "migrate" or cmd == "up" then Migrate.run()
    elseif cmd == "rollback" or cmd == "down" then Migrate.rollback()
    elseif cmd == "status" then Migrate.status()
    elseif cmd == "seed" then Migrate.seed()
    elseif cmd == "create" then 
        local ok, config = pcall(require, "config.database")
        local env = os.getenv("RIO_ENV") or "development"
        if ok and config[env] then Migrate.create(config[env]) end
    elseif cmd == "drop" then
        local ok, config = pcall(require, "config.database")
        local env = os.getenv("RIO_ENV") or "development"
        if ok and config[env] then Migrate.drop(config[env]) end
    elseif cmd == "setup" then
        local ok, config = pcall(require, "config.database")
        local env = os.getenv("RIO_ENV") or "development"
        if ok and config[env] then Migrate.setup(config[env]) end
    elseif cmd == "reset" then
        local ok, config = pcall(require, "config.database")
        local env = os.getenv("RIO_ENV") or "development"
        if ok and config[env] then Migrate.reset(config[env]) end
    end
end

-- BaseMigration Class
local BaseMigration = {}
BaseMigration.__index = BaseMigration

function BaseMigration:up() end
function BaseMigration:down() end

function BaseMigration:extend()
    local cls = setmetatable({}, self)
    cls.__index = cls
    return cls
end

function BaseMigration:new(conn, adapter_name)
    local o = setmetatable({}, self)
    o.conn = conn
    o.adapter_name = adapter_name or "sqlite"
    o.adapter = DB.get_adapter()
    return o
end

function BaseMigration:get_sql_type(lua_type, options)
    return self.adapter.get_sql_type(lua_type, options)
end

function BaseMigration:create_table(name, callback)
    if DB.verbose then print("BaseMigration: Creating table: " .. name) end
    local cols = {}
    
    -- PK from adapter
    table.insert(cols, self.adapter.get_pk_definition())

    local t = {}
    local mig = self
    function t.string(_, n, o) table.insert(cols, n .. " " .. mig:get_sql_type("string", o)) end
    function t.text(_, n) table.insert(cols, n .. " " .. mig:get_sql_type("text")) end
    function t.integer(_, n) table.insert(cols, n .. " " .. mig:get_sql_type("integer")) end
    function t.float(_, n) table.insert(cols, n .. " " .. mig:get_sql_type("float")) end
    function t.decimal(_, n, o) table.insert(cols, n .. " " .. mig:get_sql_type("decimal", o)) end
    function t.boolean(_, n) table.insert(cols, n .. " " .. mig:get_sql_type("boolean")) end
    function t.datetime(_, n) table.insert(cols, n .. " " .. mig:get_sql_type("datetime")) end
    function t.date(_, n) table.insert(cols, n .. " " .. mig:get_sql_type("date")) end
    function t.time(_, n) table.insert(cols, n .. " " .. mig:get_sql_type("time")) end
    function t.timestamps(_)
        local typ = mig:get_sql_type("datetime")
        table.insert(cols, "created_at " .. typ .. " DEFAULT CURRENT_TIMESTAMP")
        local up_sql = "updated_at " .. typ .. " " .. mig.adapter.get_timestamp_default()
        table.insert(cols, up_sql)
    end
    function t.references(_, n, o)
        local col = n:match("_id$") and n or (n .. "_id")
        table.insert(cols, col .. " " .. mig:get_sql_type("integer"))
        if o and o.polymorphic then table.insert(cols, n .. "_type VARCHAR(255)") end
    end

    callback(t)
    local sql = "CREATE TABLE IF NOT EXISTS " .. name .. " (\n  " .. table.concat(cols, ",\n  ") .. "\n)"
    sql = sql .. self.adapter.get_table_options() .. ";"
    
    print_debug("Generated SQL:\n" .. sql)
    local ok, err = self.conn:execute(sql)
    if not ok then error("Error creating table '" .. name .. "': " .. tostring(err)) end
    if DB.verbose then print_success("  Table created successfully.") end
end

function BaseMigration:add_column(table_name, col_name, col_type, options)
    local typ_sql = self:get_sql_type(col_type, options)
    local sql = string.format("ALTER TABLE %s ADD COLUMN %s %s;", table_name, col_name, typ_sql)
    print_debug("Executing SQL: " .. sql)
    local ok, err = self.conn:execute(sql)
    if not ok then error("Error adding column: " .. tostring(err)) end
    if DB.verbose then print_success("  Column '" .. col_name .. "' added.") end
end

function BaseMigration:remove_column(table_name, col_name)
    local sql = string.format("ALTER TABLE %s DROP COLUMN %s;", table_name, col_name)
    print_debug("Executing SQL: " .. sql)
    local ok, err = self.conn:execute(sql)
    if not ok then error("Error removing column: " .. tostring(err)) end
    if DB.verbose then print_success("  Column '" .. col_name .. "' removed.") end
end

function BaseMigration:drop_table(name)
    self.conn:execute("DROP TABLE IF EXISTS " .. name .. ";")
    if DB.verbose then print_success("  Table '" .. name .. "' dropped.") end
end

function BaseMigration:change_table(name, callback)
    if DB.verbose then print("BaseMigration: Changing table: " .. name) end
    local mig = self
    local t = {}
    function t.string(_, n, o) mig:add_column(name, n, "string", o) end
    function t.text(_, n) mig:add_column(name, n, "text") end
    function t.integer(_, n) mig:add_column(name, n, "integer") end
    function t.float(_, n) mig:add_column(name, n, "float") end
    function t.decimal(_, n, o) mig:add_column(name, n, "decimal", o) end
    function t.boolean(_, n) mig:add_column(name, n, "boolean") end
    function t.datetime(_, n) mig:add_column(name, n, "datetime") end
    function t.date(_, n) mig:add_column(name, n, "date") end
    function t.time(_, n) mig:add_column(name, n, "time") end
    function t.references(_, n, o)
        mig:add_column(name, n:match("_id$") and n or (n .. "_id"), "integer")
        if o and o.polymorphic then mig:add_column(name, n .. "_type", "string") end
    end
    callback(t)
end

return {
    Migrate = Migrate,
    Migration = BaseMigration
}
