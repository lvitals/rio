-- rio/lib/rio/database/adapters/postgres.lua
-- PostgreSQL adapter for the Rio database manager using LuaSQL.

local BaseAdapter = require("rio.database.adapters.base")
local DB = require("rio.database.manager")
local PostgresAdapter = {}
for k, v in pairs(BaseAdapter) do PostgresAdapter[k] = v end
PostgresAdapter.__index = PostgresAdapter

function PostgresAdapter:new(config)
    local o = setmetatable(BaseAdapter:new(config), self)
    o.config = config
    return o
end

function PostgresAdapter:get_driver_name() return "postgres" end
function PostgresAdapter:get_luasql_module() return "luasql.postgres" end

function PostgresAdapter:connect()
    if not self.driver then self:initialize() end
    if not self.driver then return nil, "PostgreSQL driver 'luasql.postgres' not available." end
    
    local env_obj = self.driver.postgres()
    local conn, err = env_obj:connect(
        self.config.database,
        self.config.username,
        self.config.password,
        self.config.host,
        self.config.port
    )
    
    if not conn then
        if env_obj and env_obj.close then env_obj:close() end
        return nil, "Connection failed: " .. (err or "unknown error")
    end
    
    -- Apply charset/encoding
    local charset = self.config.charset or "UTF8"
    conn:execute(string.format("SET client_encoding TO '%s'", charset))
    
    return conn, env_obj
end

-- Private helper to handle parameter escaping for Postgres
local function escape_params(conn, sql, params)
    if not params or #params == 0 then return sql end
    local i = 1
    local escaped_sql = sql:gsub("%?", function()
        local param = params[i]
        i = i + 1
        if param == nil then return "NULL" end
        if type(param) == "number" then return tostring(param) end
        if type(param) == "boolean" then return param and "TRUE" or "FALSE" end
        -- luasql-postgres should have an escape method, but fallback to gsub just in case
        local esc = conn.escape and conn:escape(tostring(param)) or tostring(param):gsub("'", "''")
        return "'" .. esc .. "'"
    end)
    return escaped_sql
end

-- Data manipulation
function PostgresAdapter:query(sql, bindings)
    local conn, env = self:get_connection()
    if not conn then return nil, env end
    
    local final_sql = escape_params(conn, sql, bindings)
    local cur, err

    -- Cooperative execution via cqueues if supported
    local all_results = {}
    local final_err = nil

    if conn.getfd and conn.send_query then
        local ok, cq_err = pcall(require, "cqueues")
        if ok and type(cq_err) == "table" and cq_err.poll then
            local cqueues = cq_err
            local fd = conn:getfd()
            
            local send_ok, send_err = conn:send_query(final_sql)
            if not send_ok then
                self:release_connection(conn, env)
                return nil, send_err
            end

            local is_busy = true
            while is_busy do
                is_busy = conn:poll()
                if is_busy then
                    cqueues.poll(fd, "r", 0.01)
                end
            end
            
            while true do
                local r, e = conn:get_result()
                if r == nil and e == nil then break end
                if e and not final_err then final_err = e end
                if r then table.insert(all_results, r) end
            end
        else
            io.stdout:write(" [FALLBACK: NO CQUEUES] ")
            local r, e = conn:execute(final_sql)
            if r then table.insert(all_results, r) else final_err = e end
        end
    else
        io.stdout:write(" [FALLBACK: NO ASYNC DRIVER] ")
        local r, e = conn:execute(final_sql)
        if r then table.insert(all_results, r) else final_err = e end
    end
    
    if #all_results == 0 and final_err then
        self:release_connection(conn, env)
        return nil, final_err
    end
    
    local parsed_results = {}
    
    for _, result_item in ipairs(all_results) do
        if type(result_item) == "number" then
            table.insert(parsed_results, { affected = result_item })
        else
            local res = {}
            local row = result_item:fetch({}, "a")
            while row do
                local r = {}
                for k, v in pairs(row) do r[k] = v end
                table.insert(res, r)
                row = result_item:fetch({}, "a")
            end
            result_item:close()
            table.insert(parsed_results, res)
        end
    end
    
    self:release_connection(conn, env)
    
    if #parsed_results == 1 then
        return parsed_results[1]
    else
        return parsed_results
    end
end

function PostgresAdapter:insert(sql, bindings)
    local conn, env = self:get_connection()
    if not conn then return nil, env end

    -- Use the unified polling execute internal helper logic
    local function execute_with_poll(target_sql)
        local final_sql = escape_params(conn, target_sql, bindings)
        if conn.send_query and conn.getfd then
            local ok_cq, cqueues = pcall(require, "cqueues")
            if ok_cq and cqueues.poll then
                local fd = conn:getfd()
                conn:send_query(final_sql)
                local is_busy = true
                while is_busy do
                    is_busy = conn:poll()
                    if is_busy then cqueues.poll(fd, "r", 0.01) end
                end
                
                local all_res = {}
                local final_err = nil
                while true do
                    local r, e = conn:get_result()
                    if r == nil and e == nil then break end
                    if e and not final_err then final_err = e end
                    if r then table.insert(all_res, r) end
                end
                return all_res, final_err
            end
        end
        local r, e = conn:execute(final_sql)
        return r and {r} or nil, e
    end

    local res_list, err = execute_with_poll(sql)
    if not res_list then
        self:release_connection(conn, env)
        return nil, err
    end

    for _, res in ipairs(res_list) do
        if type(res) == "userdata" and res.close then res:close() end
    end

    -- GET ID using the SAME connection
    local cur_id, id_err = conn:execute("SELECT lastval() as id")
    local row = cur_id and cur_id:fetch({}, "a")
    local id = row and (row.id or row.ID or row[1])
    if cur_id and type(cur_id) == "userdata" then cur_id:close() end

    self:release_connection(conn, env)
    return id and tonumber(id)
end

function PostgresAdapter:update(sql, bindings) return self:query(sql, bindings) end
function PostgresAdapter:delete(sql, bindings) return self:query(sql, bindings) end

-- Rules specific to PostgreSQL
function PostgresAdapter:get_pk_definition() return "id SERIAL PRIMARY KEY" end
function PostgresAdapter:get_sql_type(lua_type, options)
    options = options or {}
    if lua_type == "string" then return "VARCHAR(" .. (options.limit or 255) .. ")"
    elseif lua_type == "text" then return "TEXT"
    elseif lua_type == "integer" then return "INTEGER"
    elseif lua_type == "float" then return "DOUBLE PRECISION"
    elseif lua_type == "decimal" then return string.format("DECIMAL(%d,%d)", options.precision or 10, options.scale or 2)
    elseif lua_type == "boolean" then return "BOOLEAN"
    elseif lua_type == "datetime" then return "TIMESTAMP"
    elseif lua_type == "date" then return "DATE"
    elseif lua_type == "time" then return "TIME" end
    return lua_type:upper()
end
function PostgresAdapter:get_table_options() return "" end
function PostgresAdapter:get_timestamp_default() return "DEFAULT CURRENT_TIMESTAMP" end

function PostgresAdapter.escape_value(value)
    if value == nil then return "NULL" end
    if type(value) == "number" then return tostring(value) end
    if type(value) == "boolean" then return value and "TRUE" or "FALSE" end
    return "'" .. tostring(value):gsub("'", "''") .. "'"
end

-- Database Management
function PostgresAdapter:create_database(db_config)
    local temp_cfg = {}
    for k,v in pairs(db_config) do temp_cfg[k] = v end
    temp_cfg.database = "postgres"
    
    local adapter = PostgresAdapter:new(temp_cfg)
    local conn, env = adapter:connect()
    if not conn then return false, (env or "unknown error") end
    local sql = string.format("CREATE DATABASE %s ENCODING '%s'", db_config.database, db_config.charset or "UTF8")
    local ok, exec_err = conn:execute(sql)
    conn:close()
    if env and env.close then env:close() end
    if not ok then 
        if tostring(exec_err):find("already exists") then 
            if DB and DB.verbose then print("✓ Already exists.") end
            return true 
        end
        return false, exec_err 
    end
    if DB and DB.verbose then print("✓ Created: " .. db_config.database) end
    return true
end

function PostgresAdapter:drop_database(db_config)
    if not self.driver then self:initialize() end
    local temp_cfg = {}
    for k,v in pairs(db_config) do temp_cfg[k] = v end
    temp_cfg.database = "postgres"
    self.config = temp_cfg
    local conn, env = self:connect()
    if not conn then return false, (env or "unknown error") end
    local ok, err = conn:execute(string.format("DROP DATABASE IF EXISTS %s", db_config.database))
    conn:close()
    if env and env.close then env:close() end
    return ok, err
end

function PostgresAdapter.disconnect()
    if instance and instance.pool then
        for _, conn in ipairs(instance.pool) do
            pcall(conn.close, conn)
        end
        instance.pool = {}
    end
    if instance and instance.env then
        pcall(instance.env.close, instance.env)
        instance.env = nil
    end
    instance = nil
end

-- Migration Tracking
function PostgresAdapter:ensure_migrations_table(conn)
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

function PostgresAdapter:get_last_batch(conn)
    local cur = conn:execute("SELECT MAX(batch) as max_batch FROM migrations")
    if not cur then return 0 end
    local row = cur:fetch({}, "a")
    local batch = (row and row.max_batch) and tonumber(row.max_batch) or 0
    if cur.close then cur:close() end
    return batch
end

function PostgresAdapter:get_executed_migrations(conn)
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

function PostgresAdapter:get_migrations_by_batch(conn, batch)
    local list = {}
    local cur = conn:execute(string.format("SELECT migration FROM migrations WHERE batch = %d ORDER BY id DESC", batch))
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

function PostgresAdapter:record_migration(conn, name, batch)
    return conn:execute(string.format("INSERT INTO migrations (migration, batch) VALUES ('%s', %d)", name:gsub("'", "''"), batch))
end

function PostgresAdapter:remove_migration_record(conn, name)
    return conn:execute(string.format("DELETE FROM migrations WHERE migration = '%s'", name:gsub("'", "''")))
end

-- Singleton Instance
local instance = nil
local function get_instance(cfg)
    if not instance then
        instance = setmetatable({
            config = cfg or {},
            driver = nil,
            connection_pool = {},
            pool_size = 0,
            MAX_POOL_SIZE = (cfg and cfg.pool) or 10
        }, PostgresAdapter)
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
function M.ensure_migrations_table(c) return get_instance():ensure_migrations_table(c) end
function M.get_last_batch(c) return get_instance():get_last_batch(c) end
function M.get_executed_migrations(c) return get_instance():get_executed_migrations(c) end
function M.get_migrations_by_batch(c, b) return get_instance():get_migrations_by_batch(c, b) end
function M.record_migration(c, n, b) return get_instance():record_migration(c, n, b) end
function M.remove_migration_record(c, n) return get_instance():remove_migration_record(c, n) end
function M.query(s, b) return get_instance():query(s, b) end
function M.insert(s, b) return get_instance():insert(s, b) end
function M.update(s, b) return get_instance():update(s, b) end
function M.delete(s, b) return get_instance():delete(s, b) end
function M.execute_async(sql, bindings) return get_instance():execute_async(sql, bindings) end

return M
