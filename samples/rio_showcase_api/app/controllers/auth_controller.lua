local User = require("app.models.user")
local auth = require("rio.auth")
local hash = require("rio.utils.hash")

local AuthController = {}

AuthController.openapi = {
    login = {
        summary = "User Login",
        description = "Authenticates a user and returns a JWT token",
        request_body = {
            content = {
                ["application/json"] = {
                    example = {
                        username = "admin",
                        password = "password123"
                    }
                }
            }
        },
        responses = {
            ["200"] = {
                description = "Authentication successful",
                content = {
                    ["application/json"] = {
                        example = {
                            access_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
                            user = {
                                id = 1,
                                username = "admin",
                                email = "admin@rio.dev"
                            }
                        }
                    }
                }
            },
            ["401"] = {
                description = "Invalid credentials",
                content = {
                    ["application/json"] = {
                        example = { error = "Invalid username or password" }
                    }
                }
            }
        }
    }
}

function AuthController:login(ctx)
    local username = ctx.body.username
    local password = ctx.body.password

    if not username or not password then
        return ctx:json({ error = "Credentials required" }, 400)
    end

    local user = User:where("username", username):first()

    if user and hash.verify(password, user.password) then
        local token = auth.generate_access_token({ 
            sub = tostring(user.id), 
            username = user.username 
        }, { secret = "rio-showcase-secret" })
        
        return ctx:json({ 
            access_token = token,
            user = user
        })
    end

    return ctx:json({ error = "Invalid username or password" }, 401)
end

function AuthController:me(ctx)
    -- ctx.state.user contains the decoded JWT payload
    local user = User:find(ctx.state.user.sub)
    return ctx:json({ 
        user = user,
        jwt_payload = ctx.state.user
    })
end

return AuthController
