local Migration = require("rio.database.migrate").Migration

local CreateProjects = Migration:extend()

function CreateProjects:up()
    self:create_table("projects", function(t)
        t:references("user")
        t:string("name")
        t:text("description")
        t:timestamps()
    end)
end

function CreateProjects:down()
    self:drop_table("projects")
end

return CreateProjects