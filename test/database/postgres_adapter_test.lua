if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the 'busted' test runner.")
    print("Usage: busted " .. (arg and arg[0] or "test/database/postgres_adapter_test.lua"))
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local postgres = require("rio.database.adapters.postgres")
local cqueues = require("cqueues")

describe("Rio PostgreSQL Adapter", function()
    local config = {
        database = "postgres",
        username = "postgres",
        password = "123456",
        host = "127.0.0.1",
        port = 5432,
        pool = 5
    }

    setup(function()
        local ok, err = pcall(postgres.initialize, config)
        if not ok then
            print("\n[SKIP] PostgreSQL not available: " .. tostring(err))
            return
        end
        
        -- Clean and setup test table
        postgres.query("DROP TABLE IF EXISTS rio_pg_test")
        postgres.query("CREATE TABLE rio_pg_test (id SERIAL PRIMARY KEY, name VARCHAR(255))")
    end)

    it("should connect and provide diagnostic info", function()
        local conn, env = postgres.get_connection()
        assert.is_not_nil(conn)
        
        RioUI.box("PostgreSQL Connectivity Info", function()
            RioUI.status("Database Connection", true, config.database)
            RioUI.status("Driver Cooperative Mode", (conn.getfd ~= nil), "I/O Multiplexing active")
            RioUI.status("Cqueues Integration", (pcall(require, "cqueues")), "Ready for Event Loop")
        end)
        
        postgres.release_connection(conn, env)
    end)

    it("should perform basic CRUD operations", function()
        -- Insert
        local id1 = postgres.insert("INSERT INTO rio_pg_test (name) VALUES (?)", {"Alice"})
        local id2 = postgres.insert("INSERT INTO rio_pg_test (name) VALUES (?)", {"Bob"})
        assert.is_number(id1)
        assert.is_number(id2)

        -- Select
        local users = postgres.query("SELECT * FROM rio_pg_test ORDER BY name")
        assert.equals(2, #users)
        assert.equals("Alice", users[1].name)

        -- Update
        local affected = postgres.update("UPDATE rio_pg_test SET name = ? WHERE id = ?", {"Charlie", id1})
        assert.equals(1, affected.affected)

        -- Delete
        local del_affected = postgres.delete("DELETE FROM rio_pg_test WHERE id = ?", {id2})
        assert.equals(1, del_affected.affected)
    end)

    it("should support cooperative execution with cqueues", function()
        local cq = cqueues.new()
        local results = {}
        local count = 5

        for i = 1, count do
            cq:wrap(function()
                local res = postgres.query("SELECT pg_sleep(0.1), " .. i .. " as val")
                if res and res[1] then
                    results[i] = tonumber(res[1].val)
                end
            end)
        end

        cq:loop()
        
        for i = 1, count do
            assert.equals(i, results[i])
        end
    end)

    it("should escape values correctly", function()
        assert.equals("'O''Reilly'", postgres.escape_value("O'Reilly"))
        assert.equals("TRUE", postgres.escape_value(true))
        assert.equals("FALSE", postgres.escape_value(false))
        assert.equals("NULL", postgres.escape_value(nil))
    end)
end)
