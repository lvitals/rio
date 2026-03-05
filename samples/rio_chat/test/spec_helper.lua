-- test/spec_helper.lua
-- Standard Rio Test Helper

-- 1. Automagically find the Rio framework relative to the current project
local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*/)") or "./"

-- Injects local framework's lib/ into package.path with high precedence
package.path = script_dir .. "../../lib/?.lua;" .. 
               script_dir .. "../../lib/?/init.lua;" ..
               package.path

-- 2. Load the Rio testing engine
local rio_tests = require("rio.utils.tests")

-- 3. Setup the environment (paths, busted, database, assertions)
rio_tests.setup()
