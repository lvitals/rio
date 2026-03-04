local User = require("app.models.user")
local UsersController = {}

function UsersController:index(ctx)
    local users = User:all()
    return ctx:json(users)
end

function UsersController:show(ctx)
    local user = User:find(ctx.params.id)
    if not user then return ctx:json({ error = "User not found" }, 404) end
    return ctx:json(user)
end

function UsersController:create(ctx)
    local user = User:new(ctx.body)
    if user:save() then
        return ctx:json(user, 201)
    else
        return ctx:json({ errors = user.errors:all() }, 422)
    end
end

function UsersController:update(ctx)
    local user = User:find(ctx.params.id)
    if not user then return ctx:json({ error = "User not found" }, 404) end
    if user:update(ctx.body) then
        return ctx:json(user)
    else
        return ctx:json({ errors = user.errors:all() }, 422)
    end
end

function UsersController:destroy(ctx)
    local user = User:find(ctx.params.id)
    if user then 
        user:delete()
        return ctx:json({ message = "User deleted successfully" })
    end
    return ctx:json({ error = "User not found" }, 404)
end

return UsersController
