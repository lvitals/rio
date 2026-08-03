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

    it("should exercise ActiveRecord model behavior end to end", function()
        local user = User:new({
            username = "leandro",
            name = "Leandro",
            email = "leandro@example.com",
            age = 30,
            password = "secret_password"
        })

        assert.is_true(user:save())
        assert.is_not_nil(user.id)

        local invalid_user = User:new({
            username = "leandro",
            email = "invalid",
            age = "abc",
            password = "123"
        })

        assert.is_false(invalid_user:save())
        assert.is_true(invalid_user.errors:any())

        local found = User:find(user.id)
        assert.is_not_nil(found)
        assert.equals("leandro", found.username)
        assert.is_true(User:exists({ username = "leandro" }))
        assert.equals(1, User:count())

        local post = user.posts:create({ title = "Report Post" })
        assert.is_not_nil(post)
        assert.is_not_nil(post.id)
        assert.equals(1, user.posts:count())
        assert.equals("leandro", post.user.username)

        User.attributes = { "id", "username", "name", "age", "email" }
        local data = user:toTable()
        assert.equals("leandro", data.username)
        assert.equals("Leandro", data.name)
        assert.equals("leandro@example.com", data.email)
        assert.is_nil(data.password)

        user:delete()
        assert.is_nil(User:find(user.id))
        assert.equals(1, tonumber(DBManager.query("SELECT COUNT(*) as c FROM users")[1].c))

        assert.is_true(User:new({
            username = "user2",
            email = "u2@ex.com",
            age = 20,
            password = "password"
        }):save())
        assert.equals(20.0, User:avg("age"))
        assert.equals(20, User:sum("age"))
    end)
end)
