local Migration = require("rio.database.migrate").Migration

local CreateUsers = Migration:extend()

function CreateUsers:up()
    self:create_table("users", function(t)
        t:string("username")
        t:string("password")
        t:string("email")
        t:timestamps()
    end)
end

function CreateUsers:down()
    self:drop_table("users")
end

return CreateUsers