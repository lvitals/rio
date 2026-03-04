local Post = require("app.models.post")
local PostsController = require("app.controllers.posts_controller")

describe("PostsController", function()
    -- Mock context helper
    local function mock_ctx(params, body)
        return {
            params = params or {},
            body = body or {},
            view = function(self, path, data) return { type = "view", path = path, data = data } end,
            json = function(self, data, status) return { type = "json", data = data, status = status or 200 } end,
            redirect = function(self, url) return { type = "redirect", url = url } end,
            text = function(self, status, msg) return { type = "text", status = status, msg = msg } end
        }
    end

    before_each(function()
        -- Clean database before each test
        Post:raw("DELETE FROM " .. Post.table_name)
    end)

    it("should list posts", function()
        Post:create({ title = "Test title", priority = 1, body = "Test body", published = true, price = 1 })
        local ctx = mock_ctx()
        local res = PostsController:index(ctx)
        assert.equals("view", res.type)
        assert.equals("posts/index", res.path)
        assert.is_table(res.data.posts)
        assert.equals(1, #res.data.posts)
    end)

    it("should show a post", function()
        local item = Post:create({ title = "Test title", priority = 1, body = "Test body", published = true, price = 1 })
        local ctx = mock_ctx({ id = item.id })
        local res = PostsController:show(ctx)
        assert.equals("view", res.type)
        assert.equals("posts/show", res.path)
        assert.equals(tonumber(item.id), tonumber(res.data.post.id))
    end)

    it("should create a post", function()
        local ctx = mock_ctx({}, { title = "Test title", priority = 1, body = "Test body", published = true, price = 1 })
        local res = PostsController:create(ctx)
        assert.equals("redirect", res.type)
        
        local item = Post:first()
        assert.is_not_nil(item)
    end)

    it("should update a post", function()
        local item = Post:create({ title = "Test title", priority = 1, body = "Test body", published = true, price = 1 })
        local ctx = mock_ctx({ id = item.id }, { title = "Test title", priority = 1, body = "Test body", published = true, price = 1 })
        local res = PostsController:update(ctx)
        assert.equals("redirect", res.type)
    end)

    it("should destroy a post", function()
        local item = Post:create({ title = "Test title", priority = 1, body = "Test body", published = true, price = 1 })
        local ctx = mock_ctx({ id = item.id })
        local res = PostsController:destroy(ctx)
        assert.equals("redirect", res.type)
        
        assert.is_nil(Post:find(item.id))
    end)
end)
