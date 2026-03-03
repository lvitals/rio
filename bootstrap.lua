-- rio/bootstrap.lua
-- Sets up the environment and package paths for the Rio application.

-- This function is a robust way to get the directory of the currently running script.
local function get_script_dir()
    local info = debug.getinfo(2, "S")
    local path = info.source
    if path:sub(1, 1) == "@" then
        path = path:sub(2)
    end
    return path:match("(.*[/\\])") or ""
end

-- Assumes bootstrap.lua is in the project root.
local project_root = get_script_dir()

-- Add project directories to the package path to allow for clean requires.
-- This allows `require("rio.server")` instead of `require("lib.rio.server")`
-- and `require("app.controllers.my_controller")` instead of `require("app.controllers.my_controller")`
package.path = package.path ..
    ";" .. project_root .. "lib/?.lua" ..
    ";" .. project_root .. "lib/?/init.lua" ..
    ";" .. project_root .. "?.lua" ..
    ";" .. project_root .. "?/init.lua"

-- A global function for easy debugging.
function p(...)
    print(require("inspect").inspect(...))
end

print("Rio environment bootstrapped.")
