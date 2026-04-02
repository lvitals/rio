if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the \"busted\" test runner.")
    print("Usage: busted test/database/transaction_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local DBManager = require("rio.database.manager")

DBManager.verbose = false -- Silence DB logs during tests

describe("Database Transaction Management", function()
    local db_file = ":memory:"

    setup(function()
        DBManager.initialize({
            adapter = "sqlite",
            database = db_file,
            -- Important: SQLite with :memory: needs a pool to keep the DB alive across queries
            pool = 1 
        })

        DBManager.query("CREATE TABLE IF NOT EXISTS test_items (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)")
    end)

    before_each(function()
        DBManager.query("DELETE FROM test_items")
    end)

    it("should successfully commit a transaction when the callback succeeds", function()
        local callback = function()
            local insert_id = DBManager.insert("INSERT INTO test_items (name) VALUES (?)", {"Item 1"})
            if not insert_id then error("Failed to insert item") end
            return insert_id
        end

        local success_result, err = DBManager.transaction(callback)

        assert.is_not_nil(success_result)
        assert.is_nil(err)

        -- Verify the data was actually committed to the database
        local items = DBManager.query("SELECT name FROM test_items WHERE id = ?", {success_result})
        assert.equals(1, #items)
        assert.equals("Item 1", items[1].name)
    end)

    it("should rollback a transaction when an error is thrown within the callback", function()
        local callback = function()
            -- Insert an item that should be rolled back
            DBManager.insert("INSERT INTO test_items (name) VALUES (?)", {"Item to Rollback"})
            
            -- Simulate a failure
            error("Intentional error to trigger rollback")
        end

        local success_result, err = DBManager.transaction(callback)

        -- Expecting the transaction to fail and return an error
        assert.is_nil(success_result)
        assert.is_not_nil(err)
        assert.truthy(tostring(err.message):find("Intentional error to trigger rollback"))

        -- Verify the database is empty (the insert was rolled back)
        local items = DBManager.query("SELECT * FROM test_items")
        assert.equals(0, #items)
    end)
    
    it("should correctly pass arguments to the callback function", function()
        local callback = function(item_name)
            local insert_id = DBManager.insert("INSERT INTO test_items (name) VALUES (?)", {item_name})
            return insert_id
        end

        -- Pass "Argument Item" as an argument to the transaction
        local success_result, err = DBManager.transaction(callback, "Argument Item")

        assert.is_not_nil(success_result)
        
        local items = DBManager.query("SELECT name FROM test_items WHERE id = ?", {success_result})
        assert.equals("Argument Item", items[1].name)
    end)
end)