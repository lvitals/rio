local headers_utils = require("rio.utils.headers")
local compat = require("rio.utils.compat")

describe("Rio Headers Utils", function()
    it("should extract bearer token", function()
        local headers = { authorization = "Bearer secret.token.123" }
        local token = headers_utils.get_bearer(headers)
        assert.equals("secret.token.123", token)
    end)

    it("should validate safe header values", function()
        assert.is_true(headers_utils.is_safe_value("application/json"))
        assert.is_true(headers_utils.is_safe_value("Bearer token"))
        
        -- Prevent header injection (CRLF)
        assert.is_false(headers_utils.is_safe_value("value\r\nInjected: true"))
        assert.is_false(headers_utils.is_safe_value("value\0nullbyte"))
    end)

    it("should set standard security headers", function()
        local headers = compat.new_headers()
        headers_utils.set_security_headers(headers)
        
        assert.equals("nosniff", headers:get("X-Content-Type-Options"))
        assert.equals("SAMEORIGIN", headers:get("X-Frame-Options"))
        assert.equals("1; mode=block", headers:get("X-XSS-Protection"))
        assert.truthy(headers:get("Content-Security-Policy"))
    end)
    
    it("should allow custom security headers config", function()
        local headers = compat.new_headers()
        headers_utils.set_security_headers(headers, {
            frame_options = "DENY",
            csp = "default-src 'none'"
        })
        
        assert.equals("DENY", headers:get("X-Frame-Options"))
        assert.equals("default-src 'none'", headers:get("Content-Security-Policy"))
    end)
end)
