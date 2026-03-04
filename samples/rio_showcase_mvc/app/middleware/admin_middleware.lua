local M = {}

M.description = "Ensures the user has administrator privileges"

function M.create(options)
    return function(ctx, next_mw)
        local user = ctx.state.user
        
        -- Robust check for admin: must exist AND have is_admin set to 1, true or "1"
        local is_admin = user and (
            user.is_admin == true or 
            user.is_admin == 1 or 
            user.is_admin == "1"
        )

        if not is_admin then
            -- print("[Security] Access denied to: " .. ctx.path .. " for user: " .. (user and user.username or "Guest"))
            
            -- If user is logged in but not admin, send to tasks
            if user then
                ctx:redirect("/tasks?alert=Access denied. Admin privileges required.")
            else
                -- If not logged in at all, send to login
                ctx:redirect("/login?alert=Please sign in as administrator.")
            end
            
            return false -- STOP the middleware chain and prevent controller execution
        end

        -- If admin, proceed to the next middleware or controller
        return next_mw()
    end
end

return M
