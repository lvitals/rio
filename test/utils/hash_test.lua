-- tests/utils/hash_test.lua
local hash = require("rio.utils.hash")

describe("Hash Utility", function()
    it("should hash and verify passwords", function()
        local password = "my_secure_password"
        local hashed = hash.make(password)
        
        assert.is_string(hashed)
        -- Rio PBKDF2 format is iterations$salt$hash
        assert.is_not_nil(hashed:match("^%d+%$%x+%$%x+$"))
        
        assert.is_true(hash.check(password, hashed))
        assert.is_false(hash.check("wrong_password", hashed))
    end)
end)
