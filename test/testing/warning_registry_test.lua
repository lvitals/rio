if not describe then
    print("Usage: busted test/testing/warning_registry_test.lua")
    os.exit(1)
end

package.path = "./?.lua;./?/init.lua;lib/?.lua;lib/?/init.lua;" .. package.path

local WarningRegistry = require("rio.testing.warning_registry")

describe("Rio testing warning registry", function()
    it("deduplicates warnings by stable cause key", function()
        local registry = WarningRegistry.new()

        registry:add({
            key = "database.mysql.unavailable",
            category = "database",
            subject = "MySQL",
            reason = "driver unavailable",
            detail = "missing `luasql.mysql`"
        })
        registry:add({
            key = "database.mysql.unavailable",
            category = "database",
            subject = "MySQL",
            reason = "driver unavailable",
            detail = "connection failed"
        })

        local warnings = registry:all()

        assert.equals(1, registry:count())
        assert.equals(1, #warnings)
        assert.equals(2, warnings[1].count)
        assert.equals("MySQL", warnings[1].subject)
        assert.equals("missing `luasql.mysql`", warnings[1].detail)
    end)
end)
