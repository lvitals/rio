-- app.lua
-- Main application entry point for the Rio framework.

-- Load project configuration
local ok_config, config = pcall(require, "config.application")
if not ok_config then config = {} end

-- Initialize and run the application
local rio = require("rio")
local app = rio.new(config)

-- Start the server (automatically loads DB, Middlewares, Initializers, and Routes)
app:run()
