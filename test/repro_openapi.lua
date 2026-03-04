-- test/repro_openapi.lua
local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*/)") or "./"

-- Setup environment like Showcase API
package.path = script_dir .. "../lib/?.lua;" .. 
               script_dir .. "../lib/?/init.lua;" ..
               script_dir .. "../samples/rio_showcase_api/?.lua;" ..
               script_dir .. "../samples/rio_showcase_api/app/?.lua;" ..
               script_dir .. "../samples/rio_showcase_api/app/?/init.lua;" ..
               package.path

local rio = require("rio")
local openapi = require("rio.middleware.openapi")

-- Mock App
local app = rio.new({
    api_only = true,
    api_versions = { "v1", "v2" }
})

-- Load routes
local routes_fn = require("samples.rio_showcase_api.config.routes")
routes_fn(app)

print("App bootstrapped. Routes matched: " .. #app.router.routes.GET + #app.router.routes.POST)

-- Create middleware instance
local mw = openapi.create(app)

-- Mock context for /openapi.json?v=v1
local ctx = {
    path = "/openapi.json",
    query = { v = "v1" },
    json = function(self, data)
        print("SUCCESS: JSON specification generated!")
        return true
    end
}

local ok, err = pcall(mw, ctx, function() end)
if not ok then
    print("FAILED: " .. tostring(err))
end
