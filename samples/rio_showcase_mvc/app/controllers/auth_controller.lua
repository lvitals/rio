local User = require("app.models.user")
local hash = require("rio.utils.hash")

local AuthController = {}

-- GET /login
function AuthController:new(ctx)
    if ctx.state.user then return ctx:redirect("/tasks") end
    return ctx:view("auth/login", { title = "Login" })
end

-- POST /login
function AuthController:create(ctx)
    local username = ctx.body.username
    local password = ctx.body.password

    local user = User:where("username", username):first()

    if user and hash.verify(password, user.password) then
        -- Simple session simulation using a cookie
        ctx:setCookie("user_id", tostring(user.id), { path = "/", http_only = true })
        return ctx:redirect("/tasks?notice=Welcome back, " .. user.username .. "!")
    end

    return ctx:view("auth/login", { 
        alert = "Invalid username or password",
        username = username
    })
end

-- DELETE /logout
function AuthController:destroy(ctx)
    ctx:setCookie("user_id", "", { path = "/", max_age = 0 })
    return ctx:redirect("/login?notice=Logged out successfully.")
end

return AuthController
