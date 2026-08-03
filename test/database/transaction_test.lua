local test_config = require("test.test_config")

-- Primary key clause per adapter (auto-increment integer named "id").
local PK_CLAUSE = {
    sqlite = "id INTEGER PRIMARY KEY AUTOINCREMENT",
    mysql = "id INT AUTO_INCREMENT PRIMARY KEY",
    postgres = "id SERIAL PRIMARY KEY",
}

-- Regression coverage for the connection-pinning fix: DB.transaction() used
-- to BEGIN/COMMIT/ROLLBACK via independent pool checkouts, so a transaction
-- could silently span more than one physical connection whenever the pool
-- held more than one (pool_size > 1). The original test only exercised
-- pool_size = 1 against sqlite, which hid the bug because there was only
-- ever one connection to hand out. Here we exercise pool_size 1, 2 and 10
-- against every supported adapter.
local ADAPTERS = { "sqlite", "mysql", "postgres" }
local POOL_SIZES = { 1, 2, 10 }

for _, adapter_name in ipairs(ADAPTERS) do
    for _, pool_size in ipairs(POOL_SIZES) do
        describe(string.format("Database Transaction Management [%s, pool=%d]", adapter_name, pool_size), function()
            local DBManager

            setup(function()
                if test_config.skip_if_no_db(adapter_name, "Transaction Test") then return end

                -- Force a fresh adapter singleton (and its connection pool)
                -- per pool_size, since the adapter module caches its instance
                -- (including MAX_POOL_SIZE) on first use.
                package.loaded["rio.database.manager"] = nil
                package.loaded["rio.database.adapters." .. adapter_name] = nil
                DBManager = require("rio.database.manager")
                DBManager.verbose = false

                local base_config = test_config.configs[adapter_name]
                local config = {}
                for k, v in pairs(base_config) do config[k] = v end
                config.pool = pool_size

                DBManager.initialize(config)
                DBManager.query("DROP TABLE IF EXISTS rio_tx_children")
                DBManager.query("DROP TABLE IF EXISTS rio_tx_items")
                DBManager.query(string.format("CREATE TABLE rio_tx_items (%s, name VARCHAR(255))", PK_CLAUSE[adapter_name]))
                DBManager.query(string.format(
                    "CREATE TABLE rio_tx_children (%s, item_id INTEGER, label VARCHAR(255))",
                    PK_CLAUSE[adapter_name]
                ))
            end)

            teardown(function()
                if test_config.skip_if_no_db(adapter_name, "Transaction Test") then return end
                DBManager.query("DROP TABLE IF EXISTS rio_tx_children")
                DBManager.query("DROP TABLE IF EXISTS rio_tx_items")
            end)

            before_each(function()
                if test_config.skip_if_no_db(adapter_name, "Transaction Test") then return end
                DBManager.query("DELETE FROM rio_tx_children")
                DBManager.query("DELETE FROM rio_tx_items")
            end)

            it("should commit and make the row visible through a brand-new query", function()
                if test_config.skip_if_no_db(adapter_name, "Transaction Test") then return end

                local callback = function()
                    local insert_id = DBManager.insert("INSERT INTO rio_tx_items (name) VALUES (?)", {"Item 1"})
                    if not insert_id then error("Failed to insert item") end
                    return insert_id
                end

                local success_result, err = DBManager.transaction(callback)

                assert.is_not_nil(success_result)
                assert.is_nil(err)

                -- This query is issued after the transaction wrapper has
                -- released its reserved connection back to the pool, so it
                -- may run on a different physical connection than the
                -- INSERT did. It must still see the committed row.
                local items = DBManager.query("SELECT name FROM rio_tx_items WHERE id = ?", {success_result})
                assert.equals(1, #items)
                assert.equals("Item 1", items[1].name)
            end)

            it("should roll back all changes when the callback errors", function()
                if test_config.skip_if_no_db(adapter_name, "Transaction Test") then return end

                local callback = function()
                    DBManager.insert("INSERT INTO rio_tx_items (name) VALUES (?)", {"Item to Rollback"})
                    error("Intentional error to trigger rollback")
                end

                local success_result, err = DBManager.transaction(callback)

                assert.is_nil(success_result)
                assert.is_not_nil(err)
                assert.truthy(tostring(err.message):find("Intentional error to trigger rollback", 1, true))

                local items = DBManager.query("SELECT * FROM rio_tx_items")
                assert.equals(0, #items)
            end)

            it("should pass arguments through to the callback", function()
                if test_config.skip_if_no_db(adapter_name, "Transaction Test") then return end

                local callback = function(item_name)
                    return DBManager.insert("INSERT INTO rio_tx_items (name) VALUES (?)", {item_name})
                end

                local success_result, err = DBManager.transaction(callback, "Argument Item")

                assert.is_not_nil(success_result)
                assert.is_nil(err)

                local items = DBManager.query("SELECT name FROM rio_tx_items WHERE id = ?", {success_result})
                assert.equals("Argument Item", items[1].name)
            end)

            it("should keep a parent+child insert pinned to one connection and visible after commit", function()
                if test_config.skip_if_no_db(adapter_name, "Transaction Test") then return end

                local callback = function()
                    local item_id = DBManager.insert("INSERT INTO rio_tx_items (name) VALUES (?)", {"Parent"})
                    if not item_id then error("Failed to insert parent") end

                    local child_id = DBManager.insert(
                        "INSERT INTO rio_tx_children (item_id, label) VALUES (?, ?)",
                        {item_id, "Child"}
                    )
                    if not child_id then error("Failed to insert child") end

                    return item_id, child_id
                end

                local item_id, err = DBManager.transaction(callback)
                assert.is_not_nil(item_id)
                assert.is_nil(err)

                local children = DBManager.query(
                    "SELECT label FROM rio_tx_children WHERE item_id = ?",
                    {item_id}
                )
                assert.equals(1, #children)
                assert.equals("Child", children[1].label)
            end)

            it("should reject a nested transaction on the same thread instead of silently sharing state", function()
                if test_config.skip_if_no_db(adapter_name, "Transaction Test") then return end

                local inner_err
                local _, outer_err = DBManager.transaction(function()
                    local _, e = DBManager.transaction(function() end)
                    inner_err = e
                    return true
                end)

                assert.is_nil(outer_err)
                assert.is_not_nil(inner_err)
            end)
        end)
    end
end
