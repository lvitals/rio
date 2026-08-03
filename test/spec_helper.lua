-- test/spec_helper.lua

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
require("rio.utils.tests")
_G.assert = require("luassert")

-- Silence Rio Framework noisy internal logs during tests unless DEBUG is set
local DBManager = require("rio.database.manager")
DBManager.verbose = os.getenv("RIO_DEBUG") == "true"
