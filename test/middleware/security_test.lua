if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the \"busted\" test runner.")
    print("Usage: busted test/middleware/security_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local security = require("rio.middleware.security")
local compat = require("rio.utils.compat")

describe("Rio Security Middleware", function()
    local function mock_ctx(method, path)
        return {
            method = method or "GET",
            path = path or "/",
            response_headers = compat.new_headers(),
            app = { config = {} },
            error = function(self, status, msg, details, headers) 
                return { is_error = true, status = status, msg = msg, headers = headers }
            end
        }
    end

    it("should set security headers", function()
        local mw = security.headers()
        local ctx = mock_ctx()
        
        local res = mw(ctx, function() return "next_called" end)
        assert.equals("next_called", res)
        assert.equals("nosniff", ctx.response_headers:get("X-Content-Type-Options"))
    end)

    it("should allow safe methods in allowed_methods", function()
        local mw = security.allowed_methods({ "GET", "POST" })
        local ctx = mock_ctx("GET")
        
        local res = mw(ctx, function() return "next_called" end)
        assert.equals("next_called", res)
    end)

    it("should reject unsafe methods in allowed_methods", function()
        local mw = security.allowed_methods({ "GET", "POST" })
        local ctx = mock_ctx("DELETE")
        
        local res = mw(ctx, function() return "next_called" end)
        assert.is_table(res)
        assert.is_true(res.is_error)
        assert.equals(405, res.status)
        assert.equals("GET, POST", res.headers["Allow"])
    end)
end)
