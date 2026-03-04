local User = require("app.models.user")

local M = {}

M.description = "Simple cookie-based session loader"

function M.create(options)
    return function(ctx, next_mw)
        local user_id = ctx:getCookie("user_id")
        
        if user_id then
            -- Convert to number just in case the ORM/DB driver is strict
            local user = User:find(tonumber(user_id) or user_id)
            if user then
                -- print("[Session] User found: " .. user.username)
                ctx.state.user = user
            else
                -- print("[Session] Cookie present but user not found for ID: " .. user_id)
            end
        end
        
        return next_mw()
    end
end

return M
