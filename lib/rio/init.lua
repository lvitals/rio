-- rio/lib/rio/init.lua
-- Main entry point for the Rio framework.

local Server = require("rio.server")

-- Middlewares
local cors = require("rio.middleware.cors")
local security = require("rio.middleware.security")
local auth = require("rio.auth")
local logger = require("rio.middleware.logger")
local static = require("rio.middleware.static")
local openapi = require("rio.middleware.openapi")

-- Core
local response = require("rio.core.response")
local cache = require("rio.cache")
local cable = require("rio.cable")

-- Utils
local string_utils = require("rio.utils.string")
local path_utils = require("rio.utils.path")
local headers_utils = require("rio.utils.headers")
local etl_utils = require("rio.utils.etl")

-- Public API for the framework
local Rio = {
    -- Framework version
    VERSION = "0.1.14",

    -- Create a new application
    new = Server.new,
    
    -- Middlewares
    middleware = {
        cors = cors,
        security = security,
        auth = auth,
        logger = logger,
        static = static,
        openapi = openapi
    },
    
    -- Auth utilities
    auth = auth,
    
    -- Cache system
    cache = cache,

    -- Action Cable-like system
    cable = cable,
    broadcast = cable.broadcast,
    
    -- Core utilities
    response = response,
    
    -- Utilities
    utils = {
        string = string_utils,
        path = path_utils,
        headers = headers_utils,
        etl = etl_utils
    }
}

-- Metatable for direct use, e.g., `local app = require("rio")()`
setmetatable(Rio, {
    __call = function(_, ...)
        return Server.new(...)
    end
})

return Rio
