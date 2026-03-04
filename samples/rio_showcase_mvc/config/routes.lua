-- config/routes.lua
local Home = require("app.controllers.home_controller")
local Auth = require("app.controllers.auth_controller")
local AdminUsers = require("app.controllers.admin_users_controller")
local session_mw = require("app.middleware.session_middleware")
local admin_mw = require("app.middleware.admin_middleware")

return function(app)
    -- Load session globally
    app:use(session_mw.create())

    -- Public routes
    app:get("/", "Home@index")
    app:get("/login", "Auth@new")
    app:post("/login", "Auth@create")
    app:get("/logout", "Auth@destroy")

    -- Authentication Filter (Basic protection)
    local function authenticate(ctx, next_mw)
        if not ctx.state.user then
            ctx:redirect("/login?alert=Please sign in to access this page.")
            return false
        end
        return next_mw()
    end

    -- User/Protected Group
    app:group("", function(protected)
        protected:use(authenticate)
        protected:resources("tasks")

        -- Admin Sub-group (Using the new formal middleware)
        protected:group("/admin", function(admin)
            admin:use(admin_mw.create())
            admin:resources("users", "admin_users_controller")
        end)
    end)
end
