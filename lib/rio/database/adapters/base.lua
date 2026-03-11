-- rio/lib/rio/database/adapters/base.lua
-- Base adapter defining the interface for Rio database adapters.

local BaseAdapter = {}
BaseAdapter.__index = BaseAdapter

function BaseAdapter:new(config)
    local o = setmetatable({
        config = config or {},
        driver = nil,
        driver_available = false,
        connection_pool = {},
        pool_size = 0,
        MAX_POOL_SIZE = (config and config.pool) or 10
    }, self)
    return o
end

-- Must be implemented by subclasses
function BaseAdapter:get_driver_name() error("Not implemented") end
function BaseAdapter:get_luasql_module() error("Not implemented") end

function BaseAdapter:initialize()
    local ok, mod = pcall(require, self:get_luasql_module())
    if not ok then
        self.driver_available = false
        print(string.format("⚠️  Driver '%s' not found. Please run: luarocks install %s", self:get_luasql_module(), self:get_luasql_module():gsub("%.", "-")))
    else
        self.driver = mod
        self.driver_available = true
    end
    return self.driver_available
end

-- Connection management
function BaseAdapter:connect() error("Not implemented") end

function BaseAdapter:get_connection()
    if self.pool_size > 0 then
        local conn_pair = table.remove(self.connection_pool)
        self.pool_size = self.pool_size - 1
        return conn_pair[1], conn_pair[2]
    end
    return self:connect()
end

function BaseAdapter:release_connection(conn, env_obj)
    if not conn then return end
    if self.pool_size < self.MAX_POOL_SIZE then
        table.insert(self.connection_pool, {conn, env_obj})
        self.pool_size = self.pool_size + 1
    else
        conn:close()
        if env_obj and env_obj.close then env_obj:close() end
    end
end

-- SQL Syntax & Types (Centralized from migrate.lua)
function BaseAdapter:get_pk_definition()
    return "id INTEGER PRIMARY KEY AUTOINCREMENT"
end

function BaseAdapter:get_sql_type(lua_type, options)
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

function BaseAdapter:get_table_options()
    return ""
end

function BaseAdapter:get_timestamp_default()
    return "DEFAULT CURRENT_TIMESTAMP"
end

function BaseAdapter:get_now_sql()
    return "CURRENT_TIMESTAMP"
end

-- Database Management
function BaseAdapter:create_database(db_config) error("Not implemented") end
function BaseAdapter:drop_database(db_config) error("Not implemented") end

-- SQL Execution
function BaseAdapter:execute_async(sql, bindings)
    local conn, env_obj = self:get_connection()
    if not conn then return nil, "No connection" end

    local final_sql = self.escape_params and self.escape_params(conn, sql, bindings) or sql
    -- Fallback to synchronous if driver doesn't support async
    if not conn.send_query then
        local res, err = self:query(sql, bindings)
        self:release_connection(conn, env_obj)
        return res, err
    end

    local ok, err = conn:send_query(final_sql)
    if not ok then 
        self:release_connection(conn, env_obj)
        return nil, err 
    end

    -- Cooperative polling
    local is_busy = true
    local status = 0
    while is_busy do
        -- For MySQL/MariaDB, poll expects the last status
        is_busy, status = conn:poll(status)
        if is_busy then
            local fd = conn:getfd()
            if fd and coroutine.running() then
                self:wait_for_connection(fd)
            end
        end
    end

    local cur = conn:get_result()
    self:release_connection(conn, env_obj)

    if cur and type(cur) == "userdata" then
        -- Auto-fetch logic identical to query()
        local res = {}
        local row = cur:fetch({}, "a")
        while row do
            local r = {}
            for k, v in pairs(row) do r[k] = v end
            table.insert(res, r)
            row = cur:fetch({}, "a")
        end
        cur:close()
        return res
    end

    return cur
end

function BaseAdapter:wait_for_connection(fd)
    -- Integration with cqueues/copas
    -- This should be specialized by the runtime if needed
    local ok, cqueues = pcall(require, "cqueues")
    if ok and type(cqueues) == "table" and cqueues.poll then
        cqueues.poll(fd, "r")
    end
end

-- Migration Tracking (The "Repository" pattern)
-- This allows NoSQL to store history in collections/keys instead of tables
function BaseAdapter:ensure_migrations_table(conn) error("Not implemented") end
function BaseAdapter:get_last_batch(conn) error("Not implemented") end
function BaseAdapter:get_executed_migrations(conn) error("Not implemented") end
function BaseAdapter:get_migrations_by_batch(conn, batch) error("Not implemented") end
function BaseAdapter:record_migration(conn, name, batch) error("Not implemented") end
function BaseAdapter:remove_migration_record(conn, name) error("Not implemented") end

return BaseAdapter
