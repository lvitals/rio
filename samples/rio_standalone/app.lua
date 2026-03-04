-- app.lua
-- Main entry point for the Rio Standalone application

local rio = require("rio")
local config = require("config.application")

-- Create and bootstrap the application
local app = rio.new(config)

-- Start the server
app:run()
