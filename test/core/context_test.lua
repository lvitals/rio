if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the \"busted\" test runner.")
    print("Usage: busted test/core/context_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

-- tests/core/context_test.lua
local Context = require("rio.core.context")

describe("Rio Context", function()
    local ctx
    local mock_stream

    before_each(function()
        local headers_obj = {
            get = function(self, k)
                if k == ":path" then return "/users/123?sort=desc" end
                if k == ":method" then return "GET" end
                return nil
            end,
            each = function() return function() return nil end end
        }
        mock_adapter = {
            method = "GET",
            path = "/users/123",
            query = { sort = "desc" },
            headers = {},
            get_headers = function() return headers_obj end
        }
        ctx = Context.new(mock_adapter)
        ctx.params = { id = "123" } -- Injected by router in real life
    end)

    it("should extract basic request info", function()
        assert.equals("GET", ctx.method)
        assert.equals("/users/123", ctx.path)
        assert.equals("123", ctx.params.id)
        assert.equals("desc", ctx.query.sort)
    end)

    it("should set and retrieve custom data via state", function()
        ctx.state.user_id = 42
        assert.equals(42, ctx.state.user_id)
    end)
end)
