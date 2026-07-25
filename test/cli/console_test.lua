if not describe then
    print("Usage: busted test/cli/console_test.lua")
    os.exit(1)
end

package.path = "lib/?.lua;lib/?/init.lua;" .. package.path

local function read_file(path)
    local file = assert(io.open(path, "r"))
    local content = file:read("*a")
    file:close()
    return content
end

describe("Rio CLI Console", function()
    it("uses bestline as the console line editor", function()
        local console = read_file("lib/rio/cli/commands/console.lua")
        local dev_rockspec = read_file("rio-dev-1.rockspec")
        local release_rockspec = read_file("rio-0.1.21-1.rockspec")
        local removed_module = "line" .. "noise"

        assert.truthy(console:find('require, "bestline"', 1, true))
        assert.truthy(dev_rockspec:find('"bestline"', 1, true))
        assert.truthy(release_rockspec:find('"bestline"', 1, true))

        assert.is_nil(console:find(removed_module, 1, true))
        assert.is_nil(dev_rockspec:find(removed_module, 1, true))
        assert.is_nil(release_rockspec:find(removed_module, 1, true))
    end)
end)
