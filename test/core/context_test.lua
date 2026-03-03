-- tests/core/context_test.lua
local Context = require("rio.core.context")

describe("Rio Context", function()
    local ctx
    local mock_stream

    before_each(function()
        local headers = {
            get = function(self, k)
                if k == ":path" then return "/users/123?sort=desc" end
                if k == ":method" then return "GET" end
                return nil
            end,
            each = function() return function() return nil end end
        }
        mock_stream = {
            get_headers = function() return headers end
        }
        ctx = Context.new(mock_stream)
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
