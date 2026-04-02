-- test/test_config.lua
-- Centralized Database Configuration for Rio Framework Tests

local manager = require("rio.database.manager")

local M = {}

-- DEFAULT TEST CONFIGURATIONS
-- You can override these via environment variables if needed.
M.configs = {
    sqlite = { 
        adapter = "sqlite", 
        database = os.getenv("RIO_TEST_SQLITE_DB") or "test_rio.db", 
        pool = 5 
    },
    mysql = { 
        adapter = "mysql", 
        database = os.getenv("RIO_TEST_MYSQL_DB") or "test", 
        username = os.getenv("RIO_TEST_MYSQL_USER") or "root", 
        password = os.getenv("RIO_TEST_MYSQL_PASS") or "123456", 
        host     = os.getenv("RIO_TEST_MYSQL_HOST") or "127.0.0.1", 
        pool = 5 
    },
    postgres = { 
        adapter = "postgres", 
        database = os.getenv("RIO_TEST_POSTGRES_DB") or "postgres", 
        username = os.getenv("RIO_TEST_POSTGRES_USER") or "postgres", 
        password = os.getenv("RIO_TEST_POSTGRES_PASS") or "postgres", 
        host     = os.getenv("RIO_TEST_POSTGRES_HOST") or "127.0.0.1", 
        pool = 5 
    }
}

-- Cache for connectivity checks
local connectivity_cache = {}

--- Verifies if a database configuration is valid and reachable.
-- @param adapter_name The key in M.configs (sqlite, mysql, postgres)
-- @return boolean, string (true if connected, false + error message otherwise)
function M.check_connection(adapter_name)
    if connectivity_cache[adapter_name] ~= nil then
        return connectivity_cache[adapter_name].ok, connectivity_cache[adapter_name].err
    end

    local config = M.configs[adapter_name]
    if not config then
        return false, "Configuration not found for " .. tostring(adapter_name)
    end

    -- For SQLite, we just check if we can initialize the manager
    -- For others, we try to get a real connection
    local ok, err = pcall(manager.initialize, config)
    if not ok then
        local msg = string.format("Driver/Initialization failed for %s: %s", adapter_name, tostring(err))
        connectivity_cache[adapter_name] = { ok = false, err = msg }
        return false, msg
    end

    local conn, c_err = manager.get_connection()
    if not conn then
        local msg = string.format("Connection failed for %s. Ensure the database is running and credentials in 'test/test_config.lua' are correct.", adapter_name)
        connectivity_cache[adapter_name] = { ok = false, err = msg }
        return false, msg
    end

    manager.release_connection(conn)
    connectivity_cache[adapter_name] = { ok = true }
    return true
end

--- Helper to skip a test if a database is not available
-- @param adapter_name The adapter to check (sqlite, mysql, postgres)
-- @param test_context Optional name of the test or suite for better error reporting
function M.skip_if_no_db(adapter_name, test_context)
    local ok, err = M.check_connection(adapter_name)
    if not ok then
        local context_prefix = test_context and ("[" .. test_context .. "] ") or ""
        local full_msg = context_prefix .. err
        
        -- Try to use Busted's global pending function if available
        local p = _G.pending or (getfenv and getfenv(2).pending)
        if p then
            p(full_msg)
        else
            print("  [SKIP] " .. full_msg)
        end
        return true
    end
    return false
end

return M
