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

-- DIAGNOSTICS: Print CPATH and LuaSQL driver locations
if busted then
    busted.subscribe({ "suite", "start" }, function()
        print("\n" .. RioColor.bold .. "DEBUG: LUA_CPATH=" .. package.cpath .. RioColor.reset)
        local ok, sqlite = pcall(require, "luasql.sqlite3")
        if ok then
            print(RioColor.green .. "DEBUG: luasql.sqlite3 path=" .. (package.searchpath("luasql.sqlite3", package.cpath) or "not found") .. RioColor.reset)
        else
            print(RioColor.red .. "DEBUG: luasql.sqlite3 NOT LOADED" .. RioColor.reset)
        end
    end)
end

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



