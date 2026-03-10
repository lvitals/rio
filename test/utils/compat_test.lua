if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the \"busted\" test runner.")
    print("Usage: busted test/utils/compat_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

-- test/utils/compat_test.lua
local compat = require("rio.utils.compat")
local crypto = require("rio.utils.crypto")

describe("Rio Compatibility Layer", function()
    it("should provide consistent SHA256 hashes", function()
        local msg = "hello"
        local hash = crypto.sha256(msg)
        local hex = (hash:gsub(".", function(c) return string.format("%02x", c:byte()) end))
        assert.equals("2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", hex)
    end)

    it("should provide a working unpack function", function()
        local t = {1, 2, 3}
        local a, b, c = compat.unpack(t)
        assert.equals(1, a)
        assert.equals(2, b)
        assert.equals(3, c)
    end)

    it("should provide JSON encoding/decoding fallback", function()
        local data = { name = "Rio", active = true }
        local encoded = compat.json.encode(data)
        assert.is_string(encoded)
        assert.is_not_nil(encoded:find("Rio"))
        
        local decoded = compat.json.decode(encoded)
        assert.equals("Rio", decoded.name)
        assert.is_true(decoded.active)
    end)

    it("should provide bitwise operator fallbacks", function()
        assert.equals(0x0F, compat.band(0xFF, 0x0F))
        assert.equals(0xFF, compat.bor(0xF0, 0x0F))
        assert.equals(0x0F, compat.bxor(0xFF, 0xF0))
        assert.equals(16, compat.lshift(1, 4))
        assert.equals(1, compat.rshift(16, 4))
    end)

    it("should detect the correct Lua binary", function()
        local lua_bin = compat.get_lua_bin()
        assert.is_string(lua_bin)
        assert.is_not_nil(lua_bin:find("lua"))
    end)
end)
