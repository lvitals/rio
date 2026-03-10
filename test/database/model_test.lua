if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the \"busted\" test runner.")
    print("Usage: busted test/database/model_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local Model = require("rio.database.model")
local DBManager = require("rio.database.manager")

DBManager.verbose = false -- Silence DB logs during tests

describe("Rio ActiveRecord Model", function()
    local User, Post
    local db_file = "test_db.sqlite3"

    setup(function()
        os.remove(db_file)
        DBManager.initialize({
            adapter = "sqlite",
            database = db_file
        })

        -- Create tables
        DBManager.query([[
            CREATE TABLE users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE,
                name TEXT,
                email TEXT,
                age INTEGER,
                password TEXT,
                created_at DATETIME,
                updated_at DATETIME,
                deleted_at DATETIME
            )
        ]])

        DBManager.query([[
            CREATE TABLE posts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER,
                title TEXT,
                content TEXT,
                created_at DATETIME,
                updated_at DATETIME
            )
        ]])
    end)

    teardown(function()
        os.remove(db_file)
    end)

    before_each(function()
        DBManager.query("DELETE FROM users")
        DBManager.query("DELETE FROM posts")

        User = Model:extend({
            table_name = "users",
            fillable = { "username", "name", "email", "age", "password" },
            hidden = { "password" },
            soft_deletes = true,
            validates = {
                username = { presence = true, uniqueness = true },
                email = { format = { with = "@" }, presence = true },
                age = { numericality = { only_integer = true } }
            }
        })

        Post = Model:extend({
            table_name = "posts",
            fillable = { "user_id", "title", "content" }
        })

        User:has_many("posts", { model = "app.models.post" })
        Post:belongs_to("user", { model = "app.models.user" })

        -- Inject for relationship testing
        package.loaded["app.models.post"] = Post
        package.loaded["app.models.user"] = User
    end)

    describe("CRUD & Hooks", function()
        it("should create and save a new model", function()
            local user = User:new({ username = "tester", name = "Test", email = "t@e.com", password = "pass" })
            local ok = user:save()
            assert.is_true(ok)
            assert.is_not_nil(user.id)
        end)

        it("should handle hooks correctly", function()
            local hook_called = false
            function User:before_create() hook_called = true end
            
            local user = User:create({ username = "hook", email = "h@e.com" })
            assert.is_true(hook_called)
        end)
    end)

    describe("Validations", function()
        it("should fail validation for empty required fields", function()
            local user = User:new({ username = "" })
            local ok = user:save()
            assert.is_false(ok)
            assert.is_true(user.errors:any())
        end)

        it("should handle format validations", function()
            local user = User:new({ username = "u1", email = "invalid" })
            assert.is_false(user:save())
            assert.is_table(user.errors:on("email"))
        end)
    end)

    describe("Relationships", function()
        it("should handle 1:N has_many relationships", function()
            local user = User:create({ username = "owner", email = "o@e.com" })
            user.posts:create({ title = "P1", content = "C1" })
            user.posts:create({ title = "P2", content = "C2" })
            
            assert.equals(2, user.posts:count())
        end)

        it("should handle belongs_to inverse relationship", function()
            local user = User:create({ username = "u1", email = "u@e.com" })
            local post = user.posts:create({ title = "P1" })
            
            local found_post = Post:find(post.id)
            assert.is_not_nil(found_post.user)
            assert.equals("u1", found_post.user.username)
        end)
    end)

    describe("Soft Delete", function()
        it("should hide models after deletion", function()
            local user = User:create({ username = "gone", email = "g@e.com" })
            user:delete()
            
            assert.is_nil(User:find(user.id))
            assert.equals(0, User:count())
        end)
    end)
end)
