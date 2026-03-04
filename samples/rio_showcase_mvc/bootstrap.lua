-- samples/rio_showcase_mvc/bootstrap.lua
local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*/)") or "./"

-- Injects local framework's lib/ into package.path
package.path = script_dir .. "../../lib/?.lua;" .. 
               script_dir .. "../../lib/?/init.lua;" ..
               package.path

-- Prepend current project paths
package.path = script_dir .. "?.lua;" .. 
               script_dir .. "app/?.lua;" .. 
               script_dir .. "app/?/init.lua;" .. 
               package.path

print("Rio Showcase MVC environment bootstrapped.")
