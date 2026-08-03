-- rio/test/database/dependent_deletion_test.lua
require("rio.utils.tests").setup()
local Model = require("rio.database.model")
local DB = require("rio.database.manager")

describe("ORM Dependent Deletion", function()
    local User, Post, Profile

    before_each(function()
        -- Setup in-memory database
        DB.initialize({ adapter = "sqlite", database = ":memory:" })
        
        -- Create tables if not exists
        DB.query("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT)")
        DB.query("CREATE TABLE IF NOT EXISTS posts (id INTEGER PRIMARY KEY, user_id INTEGER, title TEXT)")
        DB.query("CREATE TABLE IF NOT EXISTS profiles (id INTEGER PRIMARY KEY, user_id INTEGER, bio TEXT)")
        DB.query("CREATE TABLE IF NOT EXISTS comments (id INTEGER PRIMARY KEY, post_id INTEGER, content TEXT)")

        -- Clean tables
        DB.query("DELETE FROM users")
        DB.query("DELETE FROM posts")
        DB.query("DELETE FROM profiles")
        DB.query("DELETE FROM comments")

        -- Define Models globally in the describe scope so they are found by require simulation
        User = Model:extend({ table_name = "users", timestamps = false })
        Post = Model:extend({ table_name = "posts", timestamps = false })
        Profile = Model:extend({ table_name = "profiles", timestamps = false })
        Comment = Model:extend({ table_name = "comments", timestamps = false })

        -- Setup relationships with dependent: "destroy"
        User:has_many("posts", { model = Post, dependent = "destroy" })
        User:has_one("profile", { model = Profile, dependent = "destroy" })
        Post:has_many("comments", { model = Comment, dependent = "destroy" })
        
        Post:belongs_to("user", { model = User })
        Profile:belongs_to("user", { model = User })
        Comment:belongs_to("post", { model = Post })
    end)

    it("should delete associated has_many records when parent is deleted", function()
        local user = User:create({ name = "John Doe" })
        Post:create({ user_id = user.id, title = "Post 1" })
        Post:create({ user_id = user.id, title = "Post 2" })

        assert.equals(2, Post:count())

        -- Delete user
        user:delete()

        assert.equals(0, User:count())
        assert.equals(0, Post:count(), "Posts should have been deleted by dependent: destroy")
    end)

    it("should delete associated has_one record when parent is deleted", function()
        local user = User:create({ name = "Jane Doe" })
        Profile:create({ user_id = user.id, bio = "My bio" })

        assert.equals(1, Profile:count())

        -- Delete user
        user:delete()

        assert.equals(0, User:count())
        assert.equals(0, Profile:count(), "Profile should have been deleted by dependent: destroy")
    end)

    it("should NOT delete associated records if dependent: destroy is NOT set", function()
        -- Temporarily remove dependent option for this test
        local old_meta = User._relations.posts.metadata
        User._relations.posts.metadata = { type = "has_many", dependent = nil }

        local user = User:create({ name = "Independent" })
        Post:create({ user_id = user.id, title = "I should survive" })

        assert.equals(1, Post:count())

        -- Delete user
        user:delete()

        assert.equals(0, User:count())
        assert.equals(1, Post:count(), "Post should NOT have been deleted")

        -- Restore meta
        User._relations.posts.metadata = old_meta
    end)

    it("should handle recursive dependent deletion", function()
        local user = User:create({ name = "Grandfather" })
        local post = Post:create({ user_id = user.id, title = "Father Post" })
        Comment:create({ post_id = post.id, content = "Grandchild comment" })

        assert.equals(1, Comment:count())

        -- Delete user (should trigger post delete, which triggers comment delete)
        user:delete()

        assert.equals(0, User:count())
        assert.equals(0, Post:count())
        assert.equals(0, Comment:count(), "Comment should have been deleted via recursive chain")
    end)

end)
