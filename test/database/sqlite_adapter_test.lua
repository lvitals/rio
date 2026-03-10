if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the 'busted' test runner.")
    print("Usage: busted " .. (arg and arg[0] or "test/database/sqlite_adapter_test.lua"))
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local sqlite = require("rio.database.adapters.sqlite")
local cqueues = require("cqueues")

describe("Rio SQLite Adapter", function()
    local config = {
        database = ":memory:",
        pool = 5
    }

    setup(function()
        sqlite.initialize(config)
    end)

    it("should connect and execute simple queries", function()
        local res = sqlite.query("SELECT 1 as val")
        assert.is_table(res)
        assert.equals(1, tonumber(res[1].val))
    end)

    it("should perform basic CRUD operations", function()
        -- Create
        sqlite.query("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")
        
        -- Insert
        local id1 = sqlite.insert("INSERT INTO users (name) VALUES (?)", {"Alice"})
        local id2 = sqlite.insert("INSERT INTO users (name) VALUES (?)", {"Bob"})
        assert.is_number(id1)
        assert.is_number(id2)
        assert.is_true(id2 > id1)

        -- Select
        local users = sqlite.query("SELECT * FROM users ORDER BY name")
        assert.equals(2, #users)
        assert.equals("Alice", users[1].name)
        assert.equals("Bob", users[2].name)

        -- Update
        local affected = sqlite.update("UPDATE users SET name = ? WHERE id = ?", {"Charlie", id1})
        assert.equals(1, affected.affected)

        -- Delete
        local del_affected = sqlite.delete("DELETE FROM users WHERE id = ?", {id2})
        assert.equals(1, del_affected.affected)
        
        local final_users = sqlite.query("SELECT count(*) as total FROM users")
        assert.equals(1, tonumber(final_users[1].total))
    end)

    it("should support cooperative execution with cqueues", function()
        local cq = cqueues.new()
        local results = {}
        local count = 5

        for i = 1, count do
            cq:wrap(function()
                local res = sqlite.query("SELECT " .. i .. " as val")
                results[i] = tonumber(res[1].val)
            end)
        end

        assert.is_true(cq:loop())
        
        for i = 1, count do
            assert.equals(i, results[i])
        end
    end)

    it("should handle SQL errors gracefully", function()
        local res, err = sqlite.query("SELECT * FROM non_existent_table")
        assert.is_nil(res)
        assert.is_string(err)
    end)
    
    it("should escape values correctly", function()
        assert.equals("'O''Reilly'", sqlite.escape_value("O'Reilly"))
        assert.equals("1", sqlite.escape_value(true))
        assert.equals("0", sqlite.escape_value(false))
        assert.equals("NULL", sqlite.escape_value(nil))
    end)
end)
