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
    -- Demonstrates API versioning: same "/me" path as V1, but backed by its
    -- own namespaced controller ("V2::Auth" -> app/controllers/v2/auth_controller.lua)
    -- returning a different response shape (data/meta envelope + embedded profile).
    -- Visit /docs and switch the version dropdown (or /openapi.json?v=v1 vs
    -- ?v=v2) to see both documented side by side.
    app:group("/api/v2", function(v2)
        v2:use(authenticate)

        -- Identity (v2 returns a data/meta envelope with embedded profile)
        v2:get("/me", "V2::Auth@me")

        -- CRUDs (still reusing the V1 controller/format for brevity)
        v2:resources("projects")
    end)
end
