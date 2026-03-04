local Migration = require("rio.database.migrate").Migration

local AddAdminToUsers = Migration:extend()

function AddAdminToUsers:up()
    self:change_table("users", function(t)
        t:boolean("is_admin", { default = false })
    end)
end

function AddAdminToUsers:down()
    self:remove_column("users", "is_admin")
end

return AddAdminToUsers
