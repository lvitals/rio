-- test/spec_helper.lua
-- Professional Rio Framework Test Helper

-- Ensure the local lib directory is in the LUA_PATH
local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*/)") or "./"

package.path = script_dir .. "../lib/?.lua;" .. 
               script_dir .. "../lib/?/init.lua;" ..
               package.path

-- Load official UI utilities
local RioUI_Lib = require("rio.utils.ui")
_G.RioUI = RioUI_Lib
_G.RioColor = RioUI_Lib.colors

-- Initialize Rio tests (if needed for assertions)
local rio_tests = require("rio.utils.tests")
_G.assert = require("luassert")

-- Silence Rio Framework noisy internal logs during tests unless DEBUG is set
local DBManager = require("rio.database.manager")
DBManager.verbose = os.getenv("RIO_DEBUG") == "true"

-- Pretty Print suite headers
local original_describe = _G.describe
_G.describe = function(name, fn)
    RioUI.header(name)
    return original_describe(name, fn)
end

-- Hook into Busted lifecycle
if busted then
    busted.subscribe({ "suite", "start" }, function()
        print("\n" .. RioColor.bold .. RioColor.blue .. "╔" .. string.rep("═", 68) .. "╗" .. RioColor.reset)
        print(RioColor.bold .. RioColor.blue .. "║" .. RioColor.yellow .. "  RIO FRAMEWORK" .. RioColor.white .. " :: " .. RioColor.cyan .. "PRE-FLIGHT TEST SUITE RUNNING" .. string.rep(" ", 19) .. RioColor.blue .. "║" .. RioColor.reset)
        print(RioColor.bold .. RioColor.blue .. "╚" .. string.rep("═", 68) .. "╝" .. RioColor.reset)
    end)

    busted.subscribe({ "suite", "end" }, function()
        print("\n" .. RioColor.bold .. RioColor.green .. "╔" .. string.rep("═", 68) .. "╗" .. RioColor.reset)
        print(RioColor.bold .. RioColor.green .. "║" .. RioColor.white .. "  CONGRATULATIONS!" .. RioColor.green .. " ALL Rio TESTS COMPLETED SUCCESSFULLY!  " .. RioColor.green .. "║" .. RioColor.reset)
        print(RioColor.bold .. RioColor.green .. "╚" .. string.rep("═", 68) .. "╝" .. RioColor.reset .. "\n")
    end)
end



