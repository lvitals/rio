if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the \"busted\" test runner.")
    print("Usage: busted test/utils/jwt_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

-- tests/utils/jwt_test.lua
local jwt = require("rio.utils.jwt")

describe("JWT Utility", function()
    local secret = "test_secret_key"
    local payload = { user_id = 123, role = "admin" }

    it("should sign and verify a token", function()
        local token = jwt.sign(payload, secret)
        assert.is_string(token)
        
        local ok, decoded = jwt.verify(token, secret)
        assert.is_true(ok)
        assert.equals(123, decoded.user_id)
        assert.equals("admin", decoded.role)
    end)

    it("should return error for invalid signature", function()
        local token = jwt.sign(payload, secret)
        local ok, err = jwt.verify(token, "wrong_secret")
        assert.is_false(ok)
        assert.equals("invalid signature", err)
    end)

    it("should return error for expired token", function()
        local expired_payload = { user_id = 1 }
        local token = jwt.sign(expired_payload, secret, { expiresIn = -10 }) -- already expired
        local ok, err = jwt.verify(token, secret)
        assert.is_false(ok)
        assert.equals("token expired", err)
    end)
    
    it("should decode without verification", function()
        local token = jwt.sign(payload, secret)
        local header, decoded = jwt.decode(token)
        assert.is_table(header)
        assert.equals("HS256", header.alg)
        assert.equals(123, decoded.user_id)
    end)
end)
