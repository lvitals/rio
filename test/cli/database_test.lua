if not describe then
    print("Usage: busted test/cli/database_test.lua")
    os.exit(1)
end

package.path = "lib/?.lua;lib/?/init.lua;" .. package.path

local database = require("rio.cli.database")
local drivers = require("rio.database.drivers")
local ui = require("rio.utils.ui")

describe("Rio CLI Database Services", function()
    it("normalizes documented adapter aliases", function()
        local service = database.new({
            ui = ui,
            colors = ui.colors,
            files = require("rio.cli.files"),
            get_lua_paths = function() return package.path, package.cpath end
        })

        assert.equals("sqlite", service:normalize_adapter("sqlite3"))
        assert.equals("mysql", service:normalize_adapter("mariadb"))
        assert.equals("postgres", service:normalize_adapter("postgresql"))
        assert.equals("none", service:normalize_adapter("none", true))
        assert.is_nil(service:normalize_adapter("none", false))
    end)

    it("keeps driver metadata portable across operating systems", function()
        for _, spec in ipairs(drivers.all()) do
            assert.is_string(spec.native_dependency)
            for _, variable in ipairs(spec.build_variables or {}) do
                assert.is_nil(variable.candidates)
                assert.is_string(variable.name)
                assert.is_string(variable.header)
            end
        end
    end)
end)
