if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the \"busted\" test runner.")
    print("Usage: busted test/utils/env_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

-- tests/utils/env_test.lua
local Env = require("rio.utils.env")

describe("Env Utility", function()
    before_each(function()
        Env.clear_cache()
    end)

    it("should get environment variables from global RIO_ENV", function()
        _G.RIO_ENV = "testing"
        assert.equals("testing", _G.RIO_ENV)
        assert.is_true(Env.is("testing"))
    end)

    it("should return default values for missing keys", function()
        assert.equals("my_default", Env.get("TOTALLY_RANDOM_KEY_123", "my_default"))
    end)

    it("should detect environment via Env.is", function()
        _G.RIO_ENV = "production"
        assert.is_true(Env.is("production"))
        assert.is_false(Env.is("development"))
    end)

    it("should handle boolean auto-casting from environment", function()
        -- Manually mock environment for test
        if not M then M = Env end
        M._cache = { IS_ACTIVE = "true", IS_DISABLED = "false" }
        
        assert.is_true(Env.get("IS_ACTIVE"))
        assert.is_false(Env.get("IS_DISABLED"))
    end)
end)
