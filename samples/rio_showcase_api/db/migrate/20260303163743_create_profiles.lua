local Migration = require("rio.database.migrate").Migration

local CreateProfiles = Migration:extend()

function CreateProfiles:up()
    self:create_table("profiles", function(t)
        t:references("user", { has_one = true })
        t:string("full_name")
        t:text("bio")
        t:timestamps()
    end)
end

function CreateProfiles:down()
    self:drop_table("profiles")
end

return CreateProfiles