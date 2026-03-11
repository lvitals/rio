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
        local r, e = conn:get_result()
        if e then final_err = e end
        
        if r then
            if type(r) == "userdata" then
                local is_mysql = (self.get_driver_name and self:get_driver_name() == "mysql")
                while true do
                    local res = {}
                    if is_mysql and r.numrows then
                        local total = r:numrows()
                        for i = 1, total do
                            local row = r:fetch({}, "a")
                            if row then
                                local r_row = {}
                                for k, v in pairs(row) do r_row[k] = v end
                                table.insert(res, r_row)
                            end
                        end
                    else
                        local row = r:fetch({}, "a")
                        while row do
                            local r_row = {}
                            for k, v in pairs(row) do r_row[k] = v end
                            table.insert(res, r_row)
                            row = r:fetch({}, "a")
                        end
                    end
                    table.insert(parsed_results, res)
                    
                    if is_mysql and r.hasnextresult and r:hasnextresult() then
                        local has_next, next_err_code, next_err_msg = r:nextresult()
                        if not has_next then
                            if next_err_msg then final_err = next_err_msg end
                            break
                        end
                    else
                        -- Safely close if we are done or if the driver already auto-closed it
                        pcall(function() if r.close then r:close() end end)
                        break
                    end
                end
            else
                table.insert(parsed_results, { affected = r })
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

function BaseAdapter:async_insert(sql, bindings)
    -- Let's run execute_async, but we need the ID.
    -- If execute_async releases the connection, we can't get the ID reliably on SQLite.
    -- Let's do a direct approach for async_insert
    local conn, env = self:get_connection()
    if not conn then return nil, "No connection" end
    
    local final_sql = (self.escape_params and self:escape_params(conn, sql, bindings)) or sql
    local ok, err = conn:execute(final_sql)
    if not ok then
        self:release_connection(conn, env)
        return nil, err
    end

    local driver = self.get_driver_name and self:get_driver_name() or "sqlite"
    local id_query = "SELECT last_insert_rowid() as id"
    if driver == "mysql" then id_query = "SELECT LAST_INSERT_ID() as id"
    elseif driver == "postgres" then id_query = "SELECT lastval() as id" end

    local id_ok, cur = pcall(function() return conn:execute(id_query) end)
    local id = nil
    if id_ok and cur then
        if type(cur) == "number" then
            id = cur
        else
            local row = cur:fetch({}, "a")
            id = row and (row.id or row.ID or row[1])
            cur:close()
        end
    end

    self:release_connection(conn, env)
    return tonumber(id) or id
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
