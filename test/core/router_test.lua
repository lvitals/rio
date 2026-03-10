if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the \"busted\" test runner.")
    print("Usage: busted test/core/router_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

-- tests/core/router_test.lua
local Router = require("rio.core.router")

describe("Rio Router", function()
    local router

    before_each(function()
        router = Router.new()
    end)

    it("should register and match basic routes", function()
        router:get("/hello", "HomeController@index")
        
        local handler, params = router:match("GET", "/hello")
        assert.is_not_nil(handler)
        local match = handler(params)
        assert.equals("HomeController", match.controller)
        assert.equals("index", match.action)
    end)

    it("should handle dynamic parameters", function()
        router:get("/users/:id", "UserController@show")
        
        local handler, params = router:match("GET", "/users/123")
        assert.is_not_nil(handler)
        local match = handler(params)
        assert.equals("UserController", match.controller)
        assert.equals("show", match.action)
        assert.equals("123", params.id)
    end)

    it("should handle nested dynamic parameters", function()
        router:get("/posts/:post_id/comments/:id", "CommentController@show")
        
        local match, params = router:match("GET", "/posts/45/comments/7")
        assert.equals("45", params.post_id)
        assert.equals("7", params.id)
    end)

    it("should return nil for non-matching routes", function()
        router:get("/home", "Home@index")
        local match = router:match("GET", "/about")
        assert.is_nil(match)
    end)

    it("should distinguish methods", function()
        router:get("/data", "Data@show")
        router:post("/data", "Data@store")
        
        local handler_get, params_get = router:match("GET", "/data")
        local handler_post, params_post = router:match("POST", "/data")
        
        local match_get = handler_get(params_get)
        local match_post = handler_post(params_post)
        
        assert.equals("show", match_get.action)
        assert.equals("store", match_post.action)
    end)
end)
