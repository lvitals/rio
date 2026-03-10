-- rio/lib/rio/database/adapters/mysql.lua
-- MySQL adapter for the Rio database manager.

local BaseAdapter = require("rio.database.adapters.base")
local DB = require("rio.database.manager")
local MySQLAdapter = {}
for k, v in pairs(BaseAdapter) do MySQLAdapter[k] = v end
MySQLAdapter.__index = MySQLAdapter

function MySQLAdapter:new(config)
    local o = setmetatable(BaseAdapter:new(config), self)
    o.config = config
    return o
end

function MySQLAdapter:get_driver_name() return "mysql" end
function MySQLAdapter:get_luasql_module() return "luasql.mysql" end

function MySQLAdapter:connect()
    if not self.driver then self:initialize() end
    if not self.driver then return nil, "MySQL driver not available." end
    
    local env_obj = self.driver.mysql()
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
    
    conn:execute("SET NAMES " .. (self.config.charset or "utf8mb4"))
    return conn, env_obj
end

-- Private helper to handle parameter escaping for MySQL
local function escape_params(conn, sql, params)
    if not params or #params == 0 then return sql end
    local i = 1
    local escaped_sql = sql:gsub("%?", function()
        local param = params[i]
        i = i + 1
        if param == nil then return "NULL" end
        if type(param) == "number" then return tostring(param) end
        if type(param) == "boolean" then return param and "1" or "0" end
        local esc = conn.escape and conn:escape(tostring(param)) or tostring(param):gsub("'", "''")
        return "'" .. esc .. "'"
    end)
    return escaped_sql
end

-- Data manipulation
function MySQLAdapter:query(sql, bindings)
    local conn, env = self:get_connection()
    if not conn then return nil, env end
    
    local final_sql = escape_params(conn, sql, bindings)
    local cur, err

    -- Cooperative execution via cqueues and MariaDB async API
    if conn.getfd and conn.send_query and conn.query_cont then
        local ok, cq_err = pcall(require, "cqueues")
        if ok and type(cq_err) == "table" and cq_err.poll then
            local cqueues = cq_err
            local fd = conn:getfd()
            
            -- Start query
            local status, ret = conn:send_query(final_sql)
            
            -- Loop through statuses if needed (MariaDB async state machine)
            while status ~= 0 do
                local mode = "r"
                if status == 2 then mode = "w" end -- MYSQL_WAIT_WRITE
                
                -- Wait for socket with a safety timeout
                cqueues.poll(fd, mode, 0.01)
                
                -- Continue query
                status, ret = conn:query_cont(status)
            end

            if ret ~= 0 then
                self:release_connection(conn, env)
                return nil, "error executing async query"
            end
            
            local res, res_err = conn:get_result()
            if res_err then
                self:release_connection(conn, env)
                return nil, res_err
            end
            cur = res
        else
            cur, err = conn:execute(final_sql)
        end
    else
        cur, err = conn:execute(final_sql)
    end
    
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
        for k, v in pairs(row) do r[k] = v end
        table.insert(res, r)
        row = cur:fetch({}, "a")
    end
    cur:close()
    self:release_connection(conn, env)
    return res
end

function MySQLAdapter:insert(sql, bindings)
    local conn, env = self:get_connection()
    if not conn then return nil, env end
    
    local final_sql = escape_params(conn, sql, bindings)
    local _, err = conn:execute(final_sql)
    if err then
        self:release_connection(conn, env)
        return nil, err
    end
    
    local cur_id = conn:execute("SELECT LAST_INSERT_ID() as id")
    local row = cur_id and cur_id:fetch({}, "a")
    local id = row and tonumber(row.id)
    if cur_id then cur_id:close() end
    
    self:release_connection(conn, env)
    return id
end

function MySQLAdapter:update(sql, bindings) return self:query(sql, bindings) end
function MySQLAdapter:delete(sql, bindings) return self:query(sql, bindings) end

-- Rules specific to MySQL
function MySQLAdapter:get_pk_definition()
    return "id INT AUTO_INCREMENT PRIMARY KEY"
end

function MySQLAdapter:get_sql_type(lua_type, options)
    options = options or {}
    if lua_type == "string" then return "VARCHAR(" .. (options.limit or 255) .. ")"
    elseif lua_type == "text" then return "TEXT"
    elseif lua_type == "integer" then return "INT"
    elseif lua_type == "float" then return "FLOAT"
    elseif lua_type == "decimal" then return string.format("DECIMAL(%d,%d)", options.precision or 10, options.scale or 2)
    elseif lua_type == "boolean" then return "TINYINT(1)"
    elseif lua_type == "datetime" then return "DATETIME"
    elseif lua_type == "date" then return "DATE"
    elseif lua_type == "time" then return "TIME" end
    return lua_type:upper()
end

function MySQLAdapter:get_table_options()
    local engine = self.config.engine or "InnoDB"
    local charset = self.config.charset or "utf8mb4"
    return string.format(" ENGINE=%s DEFAULT CHARSET=%s", engine, charset)
end

function MySQLAdapter:get_timestamp_default()
    return "DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP"
end

function MySQLAdapter.escape_value(value)
    if value == nil then return "NULL" end
    if type(value) == "number" then return tostring(value) end
    if type(value) == "boolean" then return value and "1" or "0" end
    return "'" .. tostring(value):gsub("'", "''") .. "'"
end

-- Database Management
function MySQLAdapter:create_database(db_config)
    local master_cfg = {}
    for k, v in pairs(db_config) do master_cfg[k] = v end
    master_cfg.database = "" -- Connect without specific DB
    
    local adapter = MySQLAdapter:new(master_cfg)
    local conn, env = adapter:connect()
    if not conn then return false, (env or "unknown error") end
    
    local charset = db_config.charset or "utf8mb4"
    local sql = string.format("CREATE DATABASE IF NOT EXISTS %s CHARACTER SET %s", db_config.database, charset)
    local ok, exec_err = conn:execute(sql)
    conn:close()
    if env and env.close then env:close() end
    
    if not ok then return false, exec_err end
    if DB and DB.verbose then print("✓ MySQL database '" .. db_config.database .. "' ensured.") end
    return true
end

function MySQLAdapter:drop_database(db_config)
    if not self.driver then self:initialize() end
    local env_obj = self.driver.mysql()
    local conn, err = env_obj:connect(
        "", -- Connect without a specific database
        db_config.username,
        db_config.password,
        db_config.host,
        db_config.port
    )
    
    if not conn then
        if env_obj and env_obj.close then env_obj:close() end
        return false, "Connection failed: " .. (err or "unknown error")
    end
    
    local sql = string.format("DROP DATABASE IF EXISTS %s", db_config.database)
    local ok, exec_err = conn:execute(sql)
    conn:close()
    if env_obj and env_obj.close then env_obj:close() end
    
    if not ok then return false, exec_err end
    print("✓ MySQL database '" .. db_config.database .. "' dropped.")
    return true
end

function MySQLAdapter.disconnect()
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
function MySQLAdapter:ensure_migrations_table(conn)
    local pk_def = self:get_pk_definition()
    local dt = self:get_sql_type("datetime")
    local sql = string.format([[
        CREATE TABLE IF NOT EXISTS migrations (
            %s,
            migration VARCHAR(255) NOT NULL UNIQUE,
            batch INTEGER NOT NULL,
            executed_at %s DEFAULT CURRENT_TIMESTAMP
        );
    ]], pk_def, dt)
    return conn:execute(sql)
end

function MySQLAdapter:get_last_batch(conn)
    local cur = conn:execute("SELECT MAX(batch) as max_batch FROM migrations")
    if not cur then return 0 end
    local row = cur:fetch({}, "a")
    local max_batch = (row and row.max_batch) and tonumber(row.max_batch) or 0
    cur:close()
    return max_batch
end

function MySQLAdapter:get_executed_migrations(conn)
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

function MySQLAdapter:get_migrations_by_batch(conn, batch)
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

function MySQLAdapter:record_migration(conn, name, batch)
    local sql = string.format("INSERT INTO migrations (migration, batch) VALUES ('%s', %d)", name:gsub("'", "''"), batch)
    return conn:execute(sql)
end

function MySQLAdapter:remove_migration_record(conn, name)
    local sql = string.format("DELETE FROM migrations WHERE migration = '%s'", name:gsub("'", "''"))
    return conn:execute(sql)
end

-- Singleton instance logic
local instance = nil
local function get_instance(cfg)
    if not instance then
        instance = setmetatable({
            config = cfg or {},
            driver = nil,
            connection_pool = {},
            pool_size = 0,
            MAX_POOL_SIZE = (cfg and cfg.pool) or 10
        }, MySQLAdapter)
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

-- CRUD
function M.query(s, b) return get_instance():query(s, b) end
function M.insert(s, b) return get_instance():insert(s, b) end
function M.update(s, b) return get_instance():update(s, b) end
function M.delete(s, b) return get_instance():delete(s, b) end

return M
