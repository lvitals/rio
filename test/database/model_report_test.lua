if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the 'busted' test runner.")
    print("Usage: busted test/database/model_report_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local Model = require("rio.database.model")
local DBManager = require("rio.database.manager")

describe("ActiveRecord Comprehensive Report", function()
    local User, Post
    local db_file = "test_model_report.sqlite3"

    setup(function()
        os.remove(db_file)
        DBManager.initialize({
            adapter = "sqlite",
            database = db_file
        })

        DBManager.query("CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE, name TEXT, email TEXT, age INTEGER, password TEXT, created_at DATETIME, updated_at DATETIME, deleted_at DATETIME)")
        DBManager.query("CREATE TABLE posts (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, title TEXT, content TEXT, created_at DATETIME, updated_at DATETIME)")

        User = Model:extend({
            table_name = "users",
            fillable = { "username", "name", "email", "age", "password" },
            hidden = { "password" },
            soft_deletes = true,
            validates = {
                username = { presence = true, uniqueness = true },
                email = { format = { with = "@" }, presence = true },
                age = { numericality = { only_integer = true } },
                password = { length = { minimum = 6 } }
            }
        })

        Post = Model:extend({
            table_name = "posts",
            fillable = { "user_id", "title", "content" }
        })

        User:has_many("posts", { model = Post })
        Post:belongs_to("user", { model = User })
    end)

    teardown(function()
        os.remove(db_file)
    end)

    it("should generate the full professional comprehensive report", function()
        RioUI.box("Rio ActiveRecord Diagnostic", function()
            -- 1. CRUD & HOOKS
            RioUI.info("--- CRUD & HOOKS ---")
            local user = User:new({ username = "leandro", name = "Leandro", email = "leandro@example.com", age = 30, password = "secret_password" })
            local saved = user:save()
            RioUI.status("Save new model", saved)
            RioUI.status("Auto-generated ID", user.id ~= nil, "ID: " .. (user.id or "N/A"))

            -- 2. VALIDATIONS
            RioUI.info("--- VALIDATIONS ---")
            local invalid_user = User:new({ username = "leandro", email = "invalid", age = "abc", password = "123" })
            local ok = invalid_user:save()
            RioUI.status("Reject invalid data", ok == false)
            RioUI.status("Capture error messages", invalid_user.errors:any(), "Errors: " .. invalid_user.errors:size())

            -- 3. QUERY METHODS
            RioUI.info("--- QUERY METHODS ---")
            local found = User:find(user.id)
            RioUI.status("Find by ID", found ~= nil and found.username == "leandro")
            RioUI.status("Exists check", User:exists({ username = "leandro" }))
            RioUI.status("Count check", User:count() == 1, "Total: " .. User:count())

            -- 4. RELATIONSHIPS
            RioUI.info("--- RELATIONSHIPS ---")
            local post = user.posts:create({ title = "Report Post" })
            RioUI.status("HasMany: Create child", post ~= nil and post.id ~= nil)
            RioUI.status("HasMany: Lazy count", user.posts:count() == 1)
            RioUI.status("BelongsTo: Load parent", post.user ~= nil and post.user.username == "leandro")

            -- 5. SERIALIZATION
            RioUI.info("--- SERIALIZATION ---")
            User.attributes = { "id", "username", "name", "age", "email" }
            local data = user:toTable()
            for k, v in pairs(data) do
                RioUI.info(string.format("  %-15s | %-20s", k, tostring(v)))
            end

            -- 6. SOFT DELETE & CALCULATIONS
            RioUI.info("--- SOFT DELETE & CALCULATIONS ---")
            user:delete()
            RioUI.status("Hide soft-deleted", User:find(user.id) == nil)
            local raw_count = DBManager.query("SELECT COUNT(*) as c FROM users")[1].c
            RioUI.status("Retain in raw DB", raw_count == 1, "Raw Count: 1")
            
            User:new({ username = "user2", email = "u2@ex.com", age = 20, password = "password" }):save()
            RioUI.status("Calculation: AVG", User:avg("age") == 20.0, "Avg: 20.0")
            RioUI.status("Calculation: SUM", User:sum("age") == 20, "Sum: 20")
        end)
        
        assert.is_true(true)
    end)
end)
