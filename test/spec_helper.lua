-- tests/spec_helper.lua
-- Framework Test Helper

-- Ensure the local lib directory is in the LUA_PATH
local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*/)") or "./"

package.path = script_dir .. "../lib/?.lua;" .. 
               script_dir .. "../lib/?/init.lua;" ..
               package.path

-- Initialize Rio tests (if needed for assertions)
local rio_tests = require("rio.utils.tests")
_G.assert = require("luassert")
