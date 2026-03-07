-- rio/lib/rio/database/adapters/sqlite.lua
-- SQLite adapter for the Rio database manager.

local BaseAdapter = require("rio.database.adapters.base")
local SQLiteAdapter = {}
for k, v in pairs(BaseAdapter) do SQLiteAdapter[k] = v end
SQLiteAdapter.__index = SQLiteAdapter

function SQLiteAdapter:get_driver_name() return "sqlite3" end
function SQLiteAdapter:get_luasql_module() return "luasql.sqlite3" end

function SQLiteAdapter:connect()
    if not self.driver then self:initialize() end
    if not self.driver then return nil, "Driver not found" end
    
    local env_obj = self.driver.sqlite3()
    local db_file = self.config.database
    
    -- Ensure directory exists
    local dir = db_file:match("(.+)/")
    if dir then os.execute("mkdir -p " .. dir) end

    local conn, err = env_obj:connect(db_file)
    if not conn then
        if env_obj and env_obj.close then env_obj:close() end
        return nil, "Connection failed: " .. (err or "unknown error")
    end
    
    return conn, env_obj
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
    if value == nil then return "0" end -- In SQLite context, nil often means false/0 for boolean columns
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

-- Data manipulation
function SQLiteAdapter:query(sql, bindings)
    local conn, env = self:get_connection()
    if not conn then return nil, env end
    
    local final_sql = escape_params(conn, sql, bindings)
    local cur, err = conn:execute(final_sql)
    
    if not cur then
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
    local _, err = conn:execute(final_sql)
    if err then
        self:release_connection(conn, env)
        return nil, err
    end
    
    local cur_id = conn:execute("SELECT last_insert_rowid() as id")
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
function SQLiteAdapter:create_database(db_config)
    self.config = db_config
    local conn, env = self:connect()
    if conn then
        conn:close()
        if env and env.close then env:close() end
        print("✓ Database file ensured: " .. db_config.database)
        return true
    else
        return false, (env or "unknown error")
    end
end

function SQLiteAdapter:drop_database(db_config)
    if os.remove(db_config.database) then
        print("✓ Deleted: " .. db_config.database)
        return true
    else
        return false, "File not found"
    end
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
            MAX_POOL_SIZE = (cfg and cfg.pool) or 10
        }, SQLiteAdapter)
        instance:initialize()
    end
    if cfg then instance.config = cfg end
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

return M
