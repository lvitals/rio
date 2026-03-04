-- config/routes.lua
local Home = require("app.controllers.home_controller")
local Auth = require("app.controllers.auth_controller")
local Stats = require("app.controllers.stats_controller")
local auth_mw = require("rio.auth")

return function(app)
    -- Public routes
    app:get("/", function(ctx) Home:index(ctx) end)
    
    -- Format: "ControllerName@actionName" enables auto-documentation
    app:post("/auth/login", "Auth@login")

    -- Protected API Group
    local authenticate = auth_mw.jwt({ secret = "rio-showcase-secret" })

    app:group("/api", function(api)
        api:use(authenticate)
        
        -- Identity
        api:get("/me", "Auth@me")
        
        -- Statistics (Demonstrates Cache)
        api:get("/stats", "Stats@index")
        
        -- CRUDs
        api:resources("users")
        api:resources("projects")
        api:resources("labels")
    end)
end
