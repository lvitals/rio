-- config/routes.lua
local Home = require("app.controllers.home_controller")
local Auth = require("app.controllers.auth_controller")
local Stats = require("app.controllers.stats_controller")
local auth_mw = require("rio.auth")

return function(app)
    -- Public routes
    app:get("/", "Home@index")
    
    -- Format: "ControllerName@actionName" enables auto-documentation
    app:post("/auth/login", "Auth@login")

    -- Protected API Group
    local authenticate = auth_mw.jwt({ secret = "rio-showcase-secret" })

    -- API V1
    app:group("/api/v1", function(v1)
        v1:use(authenticate)
        
        -- Identity
        v1:get("/me", "Auth@me")
        
        -- Statistics
        v1:get("/stats", "Stats@index")
        
        -- CRUDs
        v1:resources("users")
        v1:resources("projects")
        v1:resources("labels")
    end)

    -- API V2 (Example)
    app:group("/api/v2", function(v2)
        v2:use(authenticate)
        
        -- Identity (V2 might return more data or different format)
        v2:get("/me", "Auth@me")
        
        -- CRUDs
        v2:resources("projects")
    end)
end
