-- samples/rio_showcase_api/bootstrap.lua
-- Initializes the Rio environment and loads configurations.

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*/)") or "./"

-- Injects local framework's lib/ into package.path
-- Since we are in samples/rio_showcase_api/, the framework is at ../../lib/
package.path = script_dir .. "../../lib/?.lua;" .. 
               script_dir .. "../../lib/?/init.lua;" ..
               package.path

-- Prepend current project app/ and config/ paths
package.path = script_dir .. "?.lua;" .. 
               script_dir .. "app/?.lua;" .. 
               script_dir .. "app/?/init.lua;" .. 
               package.path

print("Rio Showcase API environment bootstrapped.")
