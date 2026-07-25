local User = require("app.models.user")

-- Demonstrates API versioning: this controller backs "/api/v2/me" while
-- app/controllers/auth_controller.lua keeps backing "/api/v1/me". Same
-- underlying data, deliberately different response shape, so both versions
-- can evolve independently without breaking v1 clients. Namespacing the
-- controller as "V2::Auth" (see config/routes.lua) maps to this file
-- (app/controllers/v2/auth_controller.lua) by Rio's naming convention -
-- generated with: rio generate controller V2::Auth me --api
local AuthController = {}

AuthController.openapi = {
    me = {
        summary = "Current User Info (v2)",
        description = "V2 wraps the payload in a data/meta envelope and embeds the user's profile, instead of the flat shape returned by v1.",
        tags = { "Auth" },
        responses = {
            ["200"] = {
                description = "User information retrieved successfully",
                content = {
                    ["application/json"] = {
                        example = {
                            data = {
                                id = 1,
                                username = "admin",
                                email = "admin@rio.dev",
                                profile = {
                                    full_name = "Administrator",
                                    bio = "Rio showcase account"
                                },
                                created_at = "2024-03-04 12:00:00",
                                updated_at = "2024-03-04 12:00:00"
                            },
                            meta = {
                                api_version = "v2"
                            }
                        }
                    }
                }
            },
            ["401"] = {
                description = "Unauthorized - Missing or invalid token",
                content = {
                    ["application/json"] = {
                        example = { error = "Unauthorized" }
                    }
                }
            }
        }
    }
}

function AuthController:me(context)
    -- context.state.user contains the decoded JWT payload
    local user = User:find(context.state.user.sub)
    if not user then
        return context:json({ error = "Unauthorized" }, 401)
    end

    return context:json({
        data = {
            id = user.id,
            username = user.username,
            email = user.email,
            profile = user.profile,
            created_at = user.created_at,
            updated_at = user.updated_at
        },
        meta = {
            api_version = "v2"
        }
    })
end

return AuthController