local User = require("app.models.user")
local AdminUsersController = {}

function AdminUsersController:index(ctx)
    local users = User:all()
    return ctx:view("admin_users/index", { users = users, title = "Manage Users" })
end

function AdminUsersController:show(ctx)
    local u = User:find(ctx.params.id)
    if not u then return ctx:text("User not found", 404) end
    return ctx:view("admin_users/show", { target_user = u })
end

function AdminUsersController:new(ctx)
    return ctx:view("admin_users/new", { target_user = User:new() })
end

function AdminUsersController:create(ctx)
    local data = ctx.body or {}
    -- Handle checkbox logic
    data.is_admin = (data.is_admin == "1" or data.is_admin == "on")
    
    local u = User:new(data)
    -- Explicitly pass confirmation for validation
    u.password_confirmation = data.password_confirmation
    
    if u:save() then
        return ctx:redirect("/admin/users/" .. u.id .. "?notice=User created successfully.")
    else
        return ctx:view("admin_users/new", { target_user = u })
    end
end

function AdminUsersController:edit(ctx)
    local u = User:find(ctx.params.id)
    if not u then return ctx:text("User not found", 404) end
    return ctx:view("admin_users/edit", { target_user = u })
end

function AdminUsersController:update(ctx)
    local u = User:find(ctx.params.id)
    if not u then return ctx:text("User not found", 404) end
    
    local data = ctx.body or {}
    data.is_admin = (data.is_admin == "1" or data.is_admin == "on")
    
    -- Only update password if provided
    if not data.password or data.password == "" then 
        data.password = nil 
        data.password_confirmation = nil
    else
        -- Pass confirmation for custom validation in model
        u.password_confirmation = data.password_confirmation
    end
    
    if u:update(data) then
        return ctx:redirect("/admin/users/" .. u.id .. "?notice=User updated successfully.")
    else
        return ctx:view("admin_users/edit", { target_user = u })
    end
end

function AdminUsersController:destroy(ctx)
    local u = User:find(ctx.params.id)
    if u then
        -- Prevent deleting yourself
        if tostring(u.id) == tostring(ctx.state.user.id) then
            return ctx:redirect("/admin/users?alert=You cannot delete yourself!")
        end
        u:delete()
        return ctx:redirect("/admin/users?notice=User deleted.")
    end
    return ctx:redirect("/admin/users")
end

return AdminUsersController
