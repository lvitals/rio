-- rio/lib/rio/database/manager.lua
-- Database Abstraction Layer Manager

local M = {}

local loaded_config = nil
local active_adapter_name = nil
local active_adapter = nil

-- Configuration
M.query_cache_enabled = true
M.query_cache = {}
M.verbose = true -- If true, prints initialization and query info

function M.clear_query_cache()
    M.query_cache = {}
end

local function is_mutating_sql(sql)
    local statement = tostring(sql or ""):match("^%s*(%S+)")
    if not statement then return false end
    statement = statement:lower()
    return statement == "insert"
        or statement == "update"
        or statement == "delete"
        or statement == "replace"
        or statement == "truncate"
        or statement == "create"
        or statement == "alter"
        or statement == "drop"
end

-- Loads the database configuration and initializes the correct adapter.
function M.initialize(config)
    if not config then
        error("Database configuration is missing.")
    end

    loaded_config = config
    active_adapter_name = config.adapter
    
    if not active_adapter_name then
        error("No database adapter specified in configuration.")
    end

    -- Dynamically require the adapter.
    local ok, adapter_module = pcall(require, "rio.database.adapters." .. active_adapter_name)
    if not ok then
        error("Failed to load database adapter: " .. tostring(adapter_module))
    end
    
    active_adapter = adapter_module
    
    -- Initialize the adapter with its specific configuration.
    active_adapter.initialize(config)
    
    -- Test connection (non-fatal, just for feedback)
    local conn, env = active_adapter.get_connection()
    if conn then
        active_adapter.release_connection(conn, env)
        -- Feedback based on verbosity
        if M.verbose then
            print("Database manager initialized with adapter: " .. active_adapter_name)
        end
    end
end

-- Checks if the manager has been initialized.
local function ensure_initialized()
    if not active_adapter then
        -- Attempt to auto-initialize by loading the default config
        local ok, config = pcall(require, "config.database")
        if ok and config then
            local env = os.getenv("RIO_ENV") or "development"
            local env_config = config[env]
            if env_config then
                M.initialize(env_config)
            else
                error("No database configuration found for environment: " .. env)
            end
        else
            error("Database manager has not been initialized. Call manager.initialize(config) first.")
        end
    end
end

local function format_error_obj(err)
    local env = os.getenv("RIO_ENV") or "development"
    local err_str = tostring(err):lower()
    
    -- Create a structured error object
    local error_data = {
        message = tostring(err),
        env = env,
        type = "DatabaseError",
        suggestion = "An error occurred with your database connection or query.",
        command = nil
    }

    -- 1. Missing Table Error
    if err_str:match("no such table") or 
       err_str:match("relation \".*\" does not exist") or 
       err_str:match("table '.*' doesn't exist") then
        
        local table_name = err_str:match("table ([%w_%.]+)") or 
                         err_str:match("relation \"([%w_%.]+)\"") or 
                         err_str:match("table '([%w_%.]+)'") or "the table"

        error_data.suggestion = "The table '" .. table_name .. "' was not found in your '" .. env .. "' database."
        error_data.command = "RIO_ENV=" .. env .. " rio db:migrate"

    -- 2. Missing Database Error
    elseif err_str:match("database \".*\" does not exist") or 
           err_str:match("unknown database") or
           err_str:match("unable to open database file") or
           err_str:match("database file does not exist") then
        
        error_data.suggestion = "The database for the '" .. env .. "' environment does not exist."
        error_data.command = "RIO_ENV=" .. env .. " rio db:create"
    
    -- 3. Connection/Auth Error
    elseif err_str:match("authentication failed") or 
           err_str:match("access denied") or
           err_str:match("connection refused") then
        
        error_data.suggestion = "Check your credentials in 'config/database.lua' for the '" .. env .. "' environment and ensure the database server is running."
    end

    -- Add a __tostring metamethod for terminal/standard output
    setmetatable(error_data, {
        __tostring = function(t)
            if os.getenv("RIO_ENV") == "test" or _G.RIO_ENV == "test" then
                return "DatabaseError: " .. t.message
            end
            return "RIO DATABASE ERROR [" .. t.env:upper() .. "]\n" ..
                   t.message .. "\n\n" ..
                   "Suggestion:\n" ..
                   t.suggestion .. (t.command and ("\n\nRun this command:\n$ " .. t.command) or "")
        end
    })

    return error_data
end

-- Internal helper to wrap adapter calls with helpful error messages
local function wrap_adapter_call(method_name, ...)
    if not active_adapter then
        -- Attempt to auto-initialize
        local ok_cfg, db_config_file = pcall(require, "config.database")
        if ok_cfg and db_config_file then
            local env = os.getenv("RIO_ENV") or "development"
            local env_config = db_config_file[env]
            if env_config then
                M.initialize(env_config)
            end
        end
    end

    if not active_adapter then
        return nil, format_error_obj("Database manager has not been initialized.")
    end

    if not active_adapter[method_name] then
        local error_data = {
            message = string.format("The selected database adapter (%s) does not implement the '%s' method.", active_adapter_name or "unknown", method_name),
            env = os.getenv("RIO_ENV") or "development",
            type = "AdapterError",
            suggestion = "This might be a bug in the adapter or an unsupported feature for this database type."
        }
        setmetatable(error_data, {
            __tostring = function(t)
                if os.getenv("RIO_ENV") == "test" or _G.RIO_ENV == "test" then
                    return "AdapterError: " .. t.message
                end
                return "RIO ADAPTER ERROR\n" ..
                       t.message .. "\n\n" ..
                       "Suggestion:\n" ..
                       t.suggestion
            end
        })
        return nil, error_data
    end

    local res, err = active_adapter[method_name](...)
    if not res and err then
        local sql, bindings = ...
        if M.verbose and sql then
            print(string.format("%s-- DATABASE ERROR QUERY --%s", "\27[31m", "\27[0m"))
            print("SQL: " .. tostring(sql))
            if bindings and type(bindings) == "table" and #bindings > 0 then
                local b_strs = {}
                for i, v in ipairs(bindings) do table.insert(b_strs, tostring(v)) end
                print("Bindings: [" .. table.concat(b_strs, ", ") .. "]")
            end
            print(string.rep("-", 40))
        end
        return nil, format_error_obj(err)
    end
    return res
end

-- Gets the name of the active adapter
function M.get_adapter_name()
    return active_adapter_name
end

-- Gets the active adapter module
function M.get_adapter()
    ensure_initialized()
    return active_adapter
end

-- Executes a raw query.
function M.query(sql, bindings)
    local res, err = wrap_adapter_call("query", sql, bindings)
    if res and is_mutating_sql(sql) then M.clear_query_cache() end
    return res, err
end

-- Executes a raw query asynchronously.
function M.execute_async(sql, bindings)
    return wrap_adapter_call("execute_async", sql, bindings)
end

-- Alias for execute_async
function M.async_query(sql, bindings)
    return M.execute_async(sql, bindings)
end

-- Executes an insert query asynchronously and returns the last inserted ID.
function M.async_insert(sql, bindings, options)
    M.clear_query_cache()
    return wrap_adapter_call("async_insert", sql, bindings, options)
end

-- Executes an update query asynchronously and returns the number of affected rows.
function M.async_update(sql, bindings)
    M.clear_query_cache()
    return wrap_adapter_call("async_update", sql, bindings)
end

-- Executes a delete query asynchronously and returns the number of affected rows.
function M.async_delete(sql, bindings)
    M.clear_query_cache()
    return wrap_adapter_call("async_delete", sql, bindings)
end

-- Executes an insert query and returns the last inserted ID.
function M.insert(sql, bindings, options)
    M.clear_query_cache()
    return wrap_adapter_call("insert", sql, bindings, options)
end

-- Executes an update query and returns the number of affected rows.
function M.update(sql, bindings)
    M.clear_query_cache()
    return wrap_adapter_call("update", sql, bindings)
end

-- Executes a delete query and returns the number of affected rows.
function M.delete(sql, bindings)
    M.clear_query_cache()
    return wrap_adapter_call("delete", sql, bindings)
end

-- Gets a connection from the pool.
function M.get_connection()
    ensure_initialized()
    local conn, err = active_adapter.get_connection()
    if not conn and err then
        return nil, format_error_obj(err)
    end
    return conn, err
end

-- Releases a connection back to the pool.
function M.release_connection(conn)
    if active_adapter then
        active_adapter.release_connection(conn)
    end
end

-- Creates the database if supported by the adapter
function M.create_database(config)
    if not active_adapter then
        -- Load adapter dynamically if not initialized
        local adapter_name = config.adapter
        local ok, adapter_module = pcall(require, "rio.database.adapters." .. adapter_name)
        if ok then 
            active_adapter = adapter_module
            active_adapter_name = adapter_name
        end
    end
    
    if active_adapter and active_adapter.create_database then
        return active_adapter.create_database(config)
    end
    return nil, "Database adapter does not support direct creation."
end

-- Closes all connections in the pool
function M.disconnect()
    if active_adapter and active_adapter.disconnect then
        active_adapter.disconnect()
    end
end

-- Drops the database if supported by the adapter
function M.drop_database(config)
    -- Ensure pool is closed before dropping (critical for SQLite)
    M.disconnect()

    if not active_adapter then
        local adapter_name = config.adapter
        local ok, adapter_module = pcall(require, "rio.database.adapters." .. adapter_name)
        if ok then 
            active_adapter = adapter_module
            active_adapter_name = adapter_name
        end
    end

    if active_adapter and active_adapter.drop_database then
        return active_adapter.drop_database(config)
    end
    return nil, "Database adapter does not support direct dropping."
end

-- Transaction management
function M.begin()
    ensure_initialized()
    return active_adapter.query("BEGIN TRANSACTION")
end

function M.commit()
    ensure_initialized()
    return active_adapter.query("COMMIT")
end

function M.rollback()
    ensure_initialized()
    return active_adapter.query("ROLLBACK")
end

-- Transaction management with automatic commit/rollback.
-- Executes a given function within a database transaction.
-- If the function succeeds, the transaction is committed.
-- If the function returns an error or throws an exception, the transaction is rolled back.
-- Arguments:
--   callback_fn: The function to execute within the transaction. It will receive additional arguments passed to M.transaction.
--   ...: Additional arguments to pass to the callback_fn.
-- Returns:
--   The result of the callback_fn on success, or nil and an error object on failure.
function M.transaction(callback_fn, ...)
    ensure_initialized() -- Ensure the manager is initialized

    if not active_adapter.reserve_connection then
        return nil, format_error_obj("The active database adapter does not support pinned transactions.")
    end

    -- Reserve a single physical connection for the entire transaction. Every
    -- query/insert/update/delete the callback performs on this coroutine
    -- transparently reuses this same connection (see BaseAdapter:get_connection),
    -- so BEGIN, the callback's statements, and COMMIT/ROLLBACK are guaranteed
    -- to run on one connection instead of drifting across the pool.
    local conn, err_reserve = active_adapter.reserve_connection()
    if not conn then
        return nil, format_error_obj(err_reserve or "Unable to reserve a database connection for transaction.")
    end

    local ok_begin, err_begin = active_adapter.query("BEGIN")
    if not ok_begin then
        active_adapter.release_reserved(true)
        return nil, format_error_obj(err_begin)
    end

    -- Execute the callback function within the transaction
    local ok_call, result_or_err = pcall(callback_fn, ...) -- Pass additional args to callback

    if ok_call then
        -- If callback succeeded, commit the transaction on the SAME connection
        local ok_commit, err_commit = active_adapter.query("COMMIT")
        if not ok_commit then
            -- If commit fails, attempt to rollback (defensively, in case the
            -- connection is left in an aborted transaction state) before
            -- returning it to the pool.
            active_adapter.release_reserved(true)
            return nil, format_error_obj(err_commit)
        end
        active_adapter.release_reserved(false)
        M.clear_query_cache()
        -- Return the result of the callback function
        return result_or_err
    else
        -- If callback failed, rollback the transaction on the SAME connection
        local ok_rollback, err_rollback = active_adapter.query("ROLLBACK")
        active_adapter.release_reserved(not ok_rollback)
        if not ok_rollback then
            -- Log or format the rollback error if significant, but prioritize the original error from callback
            print("Warning: Error during transaction rollback: " .. tostring(err_rollback))
        end
        -- Return the error from the callback function, wrapped by format_error_obj
        return nil, format_error_obj(result_or_err)
    end
end

return M
