-- rio/lib/rio/database/adapters/sqlite.lua
-- SQLite adapter for the Rio database manager.

local BaseAdapter = require("rio.database.adapters.base")
local DB = require("rio.database.manager")
local SQLiteAdapter = {}
for k, v in pairs(BaseAdapter) do SQLiteAdapter[k] = v end
SQLiteAdapter.__index = SQLiteAdapter

function SQLiteAdapter:new(config)
    local o = setmetatable(BaseAdapter:new(config), self)
    o.config = config
    return o
end

function SQLiteAdapter:get_driver_name() return "sqlite3" end
function SQLiteAdapter:get_luasql_module() return "luasql.sqlite3" end

function SQLiteAdapter:initialize()
    if BaseAdapter.initialize(self) then
        -- SQLite environment can be shared if handled carefully
        if self.driver and self.driver.sqlite3 and not self.env then
            local ok, env = pcall(self.driver.sqlite3)
            if ok then self.env = env end
        end
    end
end

function SQLiteAdapter:connect(config)
    local cfg = config or self.config
    if not cfg then return nil, "Configuration missing" end

    if not self.driver then self:initialize() end
    if not self.driver then return nil, "Driver not found" end
    
    local db_file = cfg.database
    if not db_file then return nil, "Database file not specified" end

    -- For :memory: databases, we MUST use pooling and keep at least one connection
    local is_memory = (db_file == ":memory:")
    if is_memory and self.MAX_POOL_SIZE < 1 then
        self.MAX_POOL_SIZE = 1
    end

    -- Use shared environment if available, otherwise create a local one
    local env = self.env or (self.driver.sqlite3 and self.driver.sqlite3())
    if not env then return nil, "Failed to initialize LuaSQL SQLite environment" end

    -- Safely attempt to connect
    local ok, conn, err = pcall(function() return env:connect(db_file) end)
    
    -- If environment was closed (bad self), try to re-initialize it
    if not ok or (not conn and tostring(err):find("closed")) then
        if self.env then self.env = nil end
        env = self.driver.sqlite3()
        if self.config == cfg then self.env = env end
        ok, conn, err = pcall(function() return env:connect(db_file) end)
    end

    if not ok or not conn then
        if env and env ~= self.env and env.close then pcall(env.close, env) end
        return nil, "Connection failed: " .. (err or "unknown error")
    end
    
    -- Set busy timeout to handle concurrent access better
    pcall(function() 
        conn:execute("PRAGMA busy_timeout = 5000;")
    end)

    return conn, env
end

function SQLiteAdapter:release_connection(conn, env)
    if not conn then return end
    
    -- Always pool :memory: connections to keep data alive in SQLite
    local is_memory = (self.config and self.config.database == ":memory:")
    
    if is_memory or self.pool_size < self.MAX_POOL_SIZE then
        table.insert(self.connection_pool, {conn, env})
        self.pool_size = self.pool_size + 1
    else
        pcall(conn.close, conn)
        if env and env ~= self.env and env.close then
            pcall(env.close, env)
        end
    end
end

-- Rules
function SQLiteAdapter:get_pk_definition() return "id INTEGER PRIMARY KEY AUTOINCREMENT" end
function SQLiteAdapter:get_sql_type(lua_type, options)
    options = options or {}
    if lua_type == "string" then return "VARCHAR(" .. (options.limit or 255) .. ")"
    elseif lua_type == "text" then return "TEXT"
    elseif lua_type == "integer" then return "INTEGER"
    elseif lua_type == "float" then return "FLOAT"
    elseif lua_type == "decimal" then return string.format("DECIMAL(%d,%d)", options.precision or 10, options.scale or 2)
    elseif lua_type == "boolean" then return "BOOLEAN"
    elseif lua_type == "datetime" then return "DATETIME"
    elseif lua_type == "date" then return "DATE"
    elseif lua_type == "time" then return "TIME" end
    return lua_type:upper()
end
function SQLiteAdapter:get_table_options() return "" end
function SQLiteAdapter:get_timestamp_default() return "DEFAULT CURRENT_TIMESTAMP" end

function SQLiteAdapter.escape_value(value)
    if value == nil then return "NULL" end
    if type(value) == "number" then return tostring(value) end
    if type(value) == "boolean" then return value and "1" or "0" end
    return "'" .. tostring(value):gsub("'", "''") .. "'"
end

function SQLiteAdapter.parse_date(s)
    if not s or type(s) ~= "string" then return nil end
    local year, month, day, hour, min, sec = s:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
    if year then
        return os.time({year=year, month=month, day=day, hour=hour, min=min, sec=sec})
    end
    -- Support date only
    year, month, day = s:match("(%d+)-(%d+)-(%d+)")
    if year then
        return os.time({year=year, month=month, day=day})
    end
    return nil
end

-- Private helper to handle parameter escaping for SQLite
local function escape_params(conn, sql, params)
    if not params or #params == 0 then return sql end
    local i = 1
    local escaped_sql = sql:gsub("%%", "%%%%"):gsub("%?", function()
        local param = params[i]
        i = i + 1
        if param == nil then return "NULL" end
        if type(param) == "number" then return tostring(param) end
        if type(param) == "boolean" then return param and "1" or "0" end
        -- luasql-sqlite3 conn does not have escape method
        return "'" .. tostring(param):gsub("'", "''") .. "'"
    end)
    return escaped_sql
end

-- Private helper for cooperative execution
local function execute_cooperative(conn, sql)
    if conn.getfd and conn.send_query then
        local ok, cq_err = pcall(require, "cqueues")
        if ok and type(cq_err) == "table" and cq_err.poll then
            local cqueues = cq_err
            local fd = conn:getfd()
            
            local send_ok, send_err = conn:send_query(sql)
            if not send_ok then return nil, send_err end

            if fd >= 0 then cqueues.poll(fd, "r", 0) end
            return conn:get_result()
        end
    end
    return conn:execute(sql)
end

-- Data manipulation
function SQLiteAdapter:query(sql, bindings)
    local conn, env = self:get_connection()
    if not conn then return nil, env end
    
    local final_sql = escape_params(conn, sql, bindings)
    local cur, err = execute_cooperative(conn, final_sql)
    
    if not cur and err then
        self:release_connection(conn, env)
        return nil, err
    end
    
    if type(cur) == "number" then -- affected rows
        self:release_connection(conn, env)
        return { affected = cur }
    end
    
    -- Select results
    local res = {}
    local row = cur:fetch({}, "a")
    while row do
        local r = {}
        local has_data = false
        for k, v in pairs(row) do 
            r[k] = v
            has_data = true
        end
        if has_data then
            table.insert(res, r)
        end
        row = cur:fetch({}, "a")
    end
    cur:close()
    self:release_connection(conn, env)
    return res
end

function SQLiteAdapter:insert(sql, bindings)
    local conn, env = self:get_connection()
    if not conn then return nil, env end
    
    local final_sql = escape_params(conn, sql, bindings)
    local res, err = execute_cooperative(conn, final_sql)
    if err then
        self:release_connection(conn, env)
        return nil, err
    end
    
    local cur_id, id_err = execute_cooperative(conn, "SELECT last_insert_rowid() as id")
    local id = nil
    if type(cur_id) == "number" then
        id = cur_id
    elseif cur_id then
        local row = cur_id:fetch({}, "a")
        id = row and (row.id or row.ID or row[1])
        cur_id:close()
    end
    
    self:release_connection(conn, env)
    return id and tonumber(id)
end

function SQLiteAdapter:update(sql, bindings) return self:query(sql, bindings) end
function SQLiteAdapter:delete(sql, bindings) return self:query(sql, bindings) end

-- Migration Tracking
function SQLiteAdapter:ensure_migrations_table(conn)
    local sql = string.format([[
        CREATE TABLE IF NOT EXISTS migrations (
            %s,
            migration VARCHAR(255) NOT NULL UNIQUE,
            batch INTEGER NOT NULL,
            executed_at %s DEFAULT CURRENT_TIMESTAMP
        );
    ]], self:get_pk_definition(), self:get_sql_type("datetime"))
    return conn:execute(sql)
end

function SQLiteAdapter:get_last_batch(conn)
    local cur = conn:execute("SELECT MAX(batch) as max_batch FROM migrations")
    if not cur then return 0 end
    local row = cur:fetch({}, "a")
    local batch = (row and row.max_batch) and tonumber(row.max_batch) or 0
    cur:close()
    return batch
end

function SQLiteAdapter:get_executed_migrations(conn)
    local executed = {}
    local cur = conn:execute("SELECT migration FROM migrations")
    if cur then
        local row = cur:fetch({}, "a")
        while row do
            local name = row.migration or row.MIGRATION or row.Migration
            if name then executed[name] = true end
            row = cur:fetch({}, "a")
        end
        cur:close()
    end
    return executed
end

function SQLiteAdapter:get_migrations_by_batch(conn, batch)
    local list = {}
    local sql = string.format("SELECT migration FROM migrations WHERE batch = %d ORDER BY id DESC", batch)
    local cur = conn:execute(sql)
    if cur then
        local row = cur:fetch({}, "a")
        while row do
            local name = row.migration or row.MIGRATION or row.Migration
            if name then table.insert(list, name) end
            row = cur:fetch({}, "a")
        end
        cur:close()
    end
    return list
end

function SQLiteAdapter:record_migration(conn, name, batch)
    local sql = string.format("INSERT INTO migrations (migration, batch) VALUES ('%s', %d)", name:gsub("'", "''"), batch)
    return conn:execute(sql)
end

function SQLiteAdapter:remove_migration_record(conn, name)
    local sql = string.format("DELETE FROM migrations WHERE migration = '%s'", name:gsub("'", "''"))
    return conn:execute(sql)
end

-- Management
function SQLiteAdapter.disconnect()
    if instance then
        local is_memory = (instance.config and instance.config.database == ":memory:")
        
        if instance.connection_pool then
            local new_pool = {}
            for _, conn_pair in ipairs(instance.connection_pool) do
                local conn = conn_pair[1]
                local env = conn_pair[2]
                
                -- If it's memory, we keep one connection alive if possible
                if is_memory and #new_pool == 0 then
                    table.insert(new_pool, conn_pair)
                else
                    if conn and conn.close then pcall(conn.close, conn) end
                    if env and env ~= instance.env and env.close then pcall(env.close, env) end
                end
            end
            instance.connection_pool = new_pool
            instance.pool_size = #new_pool
        end
        
        -- Reset singleton unless it's memory and we need to keep the state
        if not is_memory then
            instance = nil
        end
    end
    collectgarbage("collect")
end

function SQLiteAdapter:create_database(db_config)
    local db_file = db_config.database
    if not db_file then return false, "No database file specified" end

    if db_file ~= ":memory:" then
        SQLiteAdapter.disconnect()
        local f, err = io.open(db_file, "a")
        if f then
            f:close()
            os.execute("chmod 664 " .. db_file .. " 2>/dev/null")
            return true
        else
            return false, (err or "Could not create database file")
        end
    end
    return true
end

function SQLiteAdapter:drop_database(db_config)
    local db_file = db_config.database
    if not db_file then return false, "No database file specified" end

    if db_file ~= ":memory:" then
        SQLiteAdapter.disconnect()
        local ok, err = os.remove(db_file)
        if ok then
            return true
        else
            if tostring(err):lower():find("no such file") then return true end
            return false, err
        end
    else
        -- For :memory:, dropping means clearing the pool to destroy the DB
        if instance and instance.connection_pool then
            for _, conn_pair in ipairs(instance.connection_pool) do
                local conn = conn_pair[1]
                if conn and conn.close then pcall(conn.close, conn) end
            end
            instance.connection_pool = {}
            instance.pool_size = 0
        end
    end
    return true
end

-- Adapter Instance Singleton
local instance = nil
local function get_instance(cfg)
    if not instance then
        instance = setmetatable({
            config = cfg or {},
            driver = nil,
            connection_pool = {},
            pool_size = 0,
            MAX_POOL_SIZE = (cfg and cfg.pool) or 0
        }, SQLiteAdapter)
        instance:initialize()
    else
        -- Update config if provided, but preserve internal state
        if cfg then 
            for k, v in pairs(cfg) do instance.config[k] = v end
            if cfg.pool then instance.MAX_POOL_SIZE = cfg.pool end
        end
    end
    return instance
end

-- Module Interface
local M = {}
function M.initialize(cfg) get_instance(cfg) end
function M.get_connection() return get_instance():get_connection() end
function M.release_connection(c, e) get_instance():release_connection(c, e) end
function M.create_database(cfg) return get_instance():create_database(cfg) end
function M.drop_database(cfg) return get_instance():drop_database(cfg) end
function M.get_pk_definition() return get_instance():get_pk_definition() end
function M.get_sql_type(t, o) return get_instance():get_sql_type(t, o) end
function M.get_table_options() return get_instance():get_table_options() end
function M.get_timestamp_default() return get_instance():get_timestamp_default() end
function M.escape_value(v) return get_instance().escape_value(v) end
function M.parse_date(s) return get_instance().parse_date(s) end
function M.ensure_migrations_table(c) return get_instance():ensure_migrations_table(c) end
function M.get_last_batch(c) return get_instance():get_last_batch(c) end
function M.get_executed_migrations(c) return get_instance():get_executed_migrations(c) end
function M.get_migrations_by_batch(c, b) return get_instance():get_migrations_by_batch(c, b) end
function M.record_migration(c, n, b) return get_instance():record_migration(c, n, b) end
function M.remove_migration_record(c, n) return get_instance():remove_migration_record(c, n) end

-- CRUD
function M.query(s, b) return get_instance():query(s, b) end
function M.insert(s, b) return get_instance():insert(s, b) end
function M.update(s, b) return get_instance():update(s, b) end
function M.delete(s, b) return get_instance():delete(s, b) end
function M.execute_async(sql, bindings) return get_instance():execute_async(sql, bindings) end

return M
