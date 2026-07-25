-- rio/lib/rio/database/adapters/base.lua
-- Base adapter defining the interface for Rio database adapters.

local BaseAdapter = {}
BaseAdapter.__index = BaseAdapter

local ok_drivers, driver_registry = pcall(require, "rio.database.drivers")
local ok_ui, ui = pcall(require, "rio.utils.ui")

local function warn_missing_driver(message)
    if ok_ui and ui and ui.warn then
        ui.warn(message)
    else
        print(message)
    end
end

-- Identifies the current coroutine (or the main thread) so that a connection
-- reserved for a transaction is only visible to the thread that opened it.
-- In Lua 5.1, coroutine.running() returns nil on the main thread; in 5.2+ it
-- returns a distinct main-thread object, which already works as a unique key.
local function current_thread_key()
    return coroutine.running() or "__main__"
end

local function normalize_insert_id(value)
    if value == nil then return nil end
    return tonumber(value) or value
end

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

function BaseAdapter:normalize_insert_id(value)
    return normalize_insert_id(value)
end

function BaseAdapter:validate_column_identifier(identifier)
    if type(identifier) ~= "string" or not identifier:match("^[_%a][_%w]*$") then
        return nil, "Invalid column identifier: " .. tostring(identifier)
    end
    return identifier
end

function BaseAdapter:get_insert_primary_key(options)
    local primary_key = (options and options.primary_key) or "id"
    return self:validate_column_identifier(primary_key)
end

function BaseAdapter:append_returning_clause(sql, column)
    if sql:upper():find("%f[%w]RETURNING%f[%W]") then return sql end
    local body = sql:gsub("%s*;%s*$", "")
    return body .. " RETURNING " .. column
end

function BaseAdapter:get_explicit_primary_key_value(options)
    if options and options.primary_key_value ~= nil then
        return self:normalize_insert_id(options.primary_key_value)
    end
    return nil
end

function BaseAdapter:read_returned_insert_id(row, primary_key)
    if not row then return nil end
    return row[primary_key] or row[primary_key:upper()] or row[1]
end

-- Must be implemented by subclasses
function BaseAdapter:get_driver_name() error("Not implemented") end
function BaseAdapter:get_luasql_module() error("Not implemented") end

function BaseAdapter:initialize()
    local ok, mod = pcall(require, self:get_luasql_module())
    if not ok then
        self.driver_available = false
        local spec = ok_drivers and driver_registry.get_by_module(self:get_luasql_module()) or nil
        if spec then
            warn_missing_driver(string.format(
                "Database driver '%s' is not installed. Run: rio db:install %s",
                spec.module,
                spec.adapter
            ))
        else
            warn_missing_driver(string.format("Database driver '%s' is not installed.", self:get_luasql_module()))
        end
    else
        self.driver = mod
        self.driver_available = true
    end
    return self.driver_available
end

-- Connection management
function BaseAdapter:connect() error("Not implemented") end

function BaseAdapter:get_connection()
    local key = current_thread_key()
    if self._reserved and self._reserved[key] then
        local r = self._reserved[key]
        return r.conn, r.env
    end
    if self.pool_size > 0 then
        local conn_pair = table.remove(self.connection_pool)
        self.pool_size = self.pool_size - 1
        return conn_pair[1], conn_pair[2]
    end
    return self:connect()
end

-- Returns a connection directly to the pool (or closes it if the pool is
-- full), bypassing any active transaction reservation. Only meant to be
-- called by release_connection() and release_reserved().
function BaseAdapter:_pool_release(conn, env_obj)
    if not conn then return end
    if self.pool_size < self.MAX_POOL_SIZE then
        table.insert(self.connection_pool, {conn, env_obj})
        self.pool_size = self.pool_size + 1
    else
        conn:close()
        if env_obj and env_obj.close then env_obj:close() end
    end
end

function BaseAdapter:release_connection(conn, env_obj)
    if not conn then return end
    local key = current_thread_key()
    if self._reserved and self._reserved[key] and self._reserved[key].conn == conn then
        -- This connection is pinned to an in-progress transaction on the
        -- current coroutine/thread; keep it checked out until the
        -- transaction wrapper explicitly releases it via release_reserved().
        return
    end
    self:_pool_release(conn, env_obj)
end

-- Reserves a single connection for the duration of a transaction on the
-- current coroutine/thread. Every get_connection()/release_connection() call
-- made by that same thread (directly or through query/insert/update/delete)
-- will transparently reuse this exact connection until release_reserved() is
-- called, guaranteeing BEGIN/.../COMMIT all run on one physical connection.
function BaseAdapter:reserve_connection()
    local key = current_thread_key()
    self._reserved = self._reserved or {}
    if self._reserved[key] then
        return nil, "A database transaction is already active on this thread"
    end
    local conn, env = self:get_connection()
    if not conn then return nil, env end
    self._reserved[key] = { conn = conn, env = env }
    return conn, env
end

-- Ends the reservation started by reserve_connection() and returns the
-- connection to the pool. If rollback_if_open is true, a defensive ROLLBACK
-- is issued first so a connection is never pooled while sitting inside an
-- aborted or otherwise unfinished transaction.
function BaseAdapter:release_reserved(rollback_if_open)
    local key = current_thread_key()
    if not self._reserved then return end
    local r = self._reserved[key]
    self._reserved[key] = nil
    if not r then return end
    if rollback_if_open then
        local ok, rolled_back = pcall(function() return r.conn:execute("ROLLBACK") end)
        if not ok or not rolled_back then
            if r.conn and r.conn.close then pcall(r.conn.close, r.conn) end
            if r.env and r.env.close then pcall(r.env.close, r.env) end
            return
        end
    end
    self:_pool_release(r.conn, r.env)
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

    local initial_status, err = conn:send_query(final_sql)
    if initial_status == nil and err then 
        self:release_connection(conn, env_obj)
        return nil, err 
    end

    -- Cooperative polling
    local status = type(initial_status) == "number" and initial_status or 0
    local is_busy = (status ~= 0)
    if type(initial_status) == "boolean" then is_busy = initial_status end

    while is_busy do
        -- For MySQL/MariaDB, poll expects the last status
        is_busy, status = conn:poll(status)
        if is_busy then
            local fd = conn:getfd()
            if fd and coroutine.running() then
                self:wait_for_connection(fd)
            elseif not coroutine.running() then
                -- Fallback to prevent tight-loops if executed synchronously without yielding
                local ok_cq, cq = pcall(require, "cqueues")
                if ok_cq and cq.poll and fd then cq.poll(fd, "r", 0.01) end
            end
        end
    end

    local all_results = {}
    local final_err = nil
    local parsed_results = {}
    
    if self.get_driver_name and self:get_driver_name() == "postgres" then
        while true do
            local r, e = conn:get_result()
            if r == nil and e == nil then break end
            if e and not final_err then final_err = e end
            if r then table.insert(all_results, r) end
        end
        
        -- Parse Postgres results
        for _, cur in ipairs(all_results) do
            if cur and type(cur) == "userdata" then
                local res = {}
                local row = cur:fetch({}, "a")
                while row do
                    local r = {}
                    for k, v in pairs(row) do r[k] = v end
                    table.insert(res, r)
                    row = cur:fetch({}, "a")
                end
                cur:close()
                table.insert(parsed_results, res)
            else
                table.insert(parsed_results, { affected = cur })
            end
        end
        
    else
        -- MySQL and SQLite behavior
        local is_mysql = (self.get_driver_name and self:get_driver_name() == "mysql")
        if is_mysql then
            while true do
                local r, e = conn:get_result()
                if e then
                    final_err = e
                    break
                end
                if r == nil then break end
                
                if type(r) == "userdata" then
                    local res = {}
                    local row = r:fetch({}, "a")
                    while row do
                        local r_row = {}
                        for k, v in pairs(row) do r_row[k] = v end
                        table.insert(res, r_row)
                        row = r:fetch({}, "a")
                    end
                    r:close()
                    table.insert(parsed_results, res)
                else
                    table.insert(parsed_results, { affected = r })
                end
                

            end
        else
            -- SQLite or others
            local r, e = conn:get_result()
            if e then final_err = e end
            if r then
                if type(r) == "userdata" then
                    local res = {}
                    local row = r:fetch({}, "a")
                    while row do
                        local r_row = {}
                        for k, v in pairs(row) do r_row[k] = v end
                        table.insert(res, r_row)
                        row = r:fetch({}, "a")
                    end
                    r:close()
                    table.insert(parsed_results, res)
                else
                    table.insert(parsed_results, { affected = r })
                end
            end
        end
    end

    self:release_connection(conn, env_obj)

    if #parsed_results == 0 and final_err then
        return nil, final_err
    end

    if #parsed_results == 1 then
        return parsed_results[1]
    else
        return parsed_results
    end
end

function BaseAdapter:async_query(sql, bindings)
    local res, err, conn, env = self:execute_async(sql, bindings)
    -- We do not release connection here if execute_async already releases it!
    -- Wait, execute_async releases the connection before returning. Let's make sure:
    -- Ah, in the current execute_async it says:
    -- self:release_connection(conn, env_obj)
    -- return parsed_results[1] or parsed_results
    -- So conn is already released!
    return res, err
end

function BaseAdapter:async_insert(sql, bindings, options)
    return self:insert(sql, bindings, options)
end

function BaseAdapter:async_update(sql, bindings)
    return self:async_query(sql, bindings)
end

function BaseAdapter:async_delete(sql, bindings)
    return self:async_update(sql, bindings)
end

function BaseAdapter:wait_for_connection(fd)
    -- Integration with cqueues/copas
    -- This should be specialized by the runtime if needed
    local ok, cqueues = pcall(require, "cqueues")
    if ok and type(cqueues) == "table" and cqueues.poll then
        -- Force a yield to allow other coroutines to progress
        if cqueues.sleep then cqueues.sleep(0) end
        -- Poll only for reading with a small timeout to prevent 100% CPU tight loops 
        -- when waiting for the server response, allowing other coroutines to run.
        cqueues.poll(fd, "r", 0.01)
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
