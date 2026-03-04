local Post = require("app.models.post")

describe("Post Model Validations", function()
    it("should be invalid without title", function()
        local post = Post:new({ body = "Some body" })
        local success = post:validate()
        assert.is_false(success)
        assert.is_true(post.errors:any())
        assert.is_not_nil(post.errors:on("title")[1])
    end)

    it("should be invalid with short title", function()
        local post = Post:new({ title = "Hi", body = "Some body" })
        local success = post:validate()
        assert.is_false(success)
        assert.is_true(post.errors:any())
        assert.is_not_nil(post.errors:on("title")[1])
    end)

    it("should be invalid without body", function()
        local post = Post:new({ title = "My Post" })
        local success = post:validate()
        assert.is_false(success)
        assert.is_true(post.errors:any())
        assert.is_not_nil(post.errors:on("body")[1])
    end)

    it("should be invalid if price is not a number", function()
        local post = Post:new({ title = "My Post", body = "Some body", price = "not a number" })
        local success = post:validate()
        assert.is_false(success)
        assert.is_true(post.errors:any())
        assert.is_not_nil(post.errors:on("price")[1])
    end)

    it("should be invalid if priority is not a positive integer", function()
        local post = Post:new({ title = "My Post", body = "Some body", priority = -5 })
        local success = post:validate()
        assert.is_false(success)
        assert.is_true(post.errors:any())
        assert.is_not_nil(post.errors:on("priority")[1])
    end)

    it("should be valid with all required fields correctly filled", function()
        local post = Post:new({ 
            title = "Valid Title", 
            body = "This is a valid body content",
            price = 10.5,
            priority = 1
        })
        local success = post:validate()
        assert.is_true(success)
        assert.is_false(post.errors:any())
    end)
end)
