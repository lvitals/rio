if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the \"busted\" test runner.")
    print("Usage: busted test/middleware/cors_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

-- tests/middleware/cors_test.lua
local cors = require("rio.middleware.cors")

describe("CORS Middleware", function()
    local function mock_context()
        return {
            headers = {},
            method = "GET",
            setHeader = function(self, k, v) self.headers[k] = v end,
            getHeader = function(self, k) return self.headers[k:lower()] or self.headers[k] end,
            no_content = function(self) self.status = 204; return self end
        }
    end

    it("should add default CORS headers", function()
        local ctx = mock_context()
        local handler = cors.default()
        
        handler(ctx, function() end)
        
        assert.equals("*", ctx.headers["Access-Control-Allow-Origin"])
        assert.is_not_nil(ctx.headers["Access-Control-Allow-Methods"])
    end)

    it("should handle OPTIONS preflight", function()
        local ctx = mock_context()
        ctx.method = "OPTIONS"
        local handler = cors.default()
        
        local next_called = false
        handler(ctx, function() next_called = true end)
        
        assert.equals(204, ctx.status)
        assert.is_false(next_called)
    end)
end)
