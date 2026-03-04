local path_utils = require("rio.utils.path")

describe("Rio Path Utils", function()
    it("should safely join paths", function()
        assert.equals("/api/v1/users", path_utils.join("/api/v1", "/users"))
        assert.equals("/api/v1/users", path_utils.join("/api/v1/", "users"))
        assert.equals("/api/v1/users", path_utils.join("/api/v1/", "/users"))
    end)

    it("should normalize paths", function()
        assert.equals("/api/v1/users", path_utils.normalize("//api///v1//users//"))
        assert.equals("/hello", path_utils.normalize("hello"))
    end)

    it("should reject unsafe paths (path traversal)", function()
        assert.is_true(path_utils.is_safe("/assets/style.css"))
        assert.is_false(path_utils.is_safe("/assets/../../etc/passwd"))
        assert.is_false(path_utils.is_safe("/assets/style.css" .. string.char(0)))
    end)

    it("should compile route parameters", function()
        local pattern, names = path_utils.compile("/users/:id/posts/:post_id")
        
        assert.equals(2, #names)
        assert.equals("id", names[1])
        assert.equals("post_id", names[2])
        
        -- Test matching
        local match_id, match_post = string.match("/users/123/posts/456", pattern)
        assert.equals("123", match_id)
        assert.equals("456", match_post)
    end)
end)
