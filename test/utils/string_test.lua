if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the \"busted\" test runner.")
    print("Usage: busted test/utils/string_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

-- tests/utils/string_test.lua
local Str = require("rio.utils.string")

describe("Rio String Utils", function()
    it("should snake_case strings", function()
        assert.equals("user_profile", Str.snake_case("UserProfile"))
        assert.equals("user_profile", Str.snake_case("user_profile"))
        assert.equals("my_custom_class", Str.snake_case("MyCustomClass"))
    end)

    it("should camel_case strings", function()
        -- Note: Rio's current implementation produces PascalCase
        assert.equals("UserProfile", Str.camel_case("user_profile"))
        assert.equals("MyCustomClass", Str.camel_case("my_custom_class"))
    end)

    it("should pluralize strings (basic)", function()
        assert.equals("users", Str.pluralize("user"))
        assert.equals("categories", Str.pluralize("category"))
        assert.equals("tasks", Str.pluralize("task"))
    end)

    it("should singularize strings (basic)", function()
        assert.equals("user", Str.singularize("users"))
        assert.equals("category", Str.singularize("categories"))
        assert.equals("task", Str.singularize("tasks"))
    end)
end)
