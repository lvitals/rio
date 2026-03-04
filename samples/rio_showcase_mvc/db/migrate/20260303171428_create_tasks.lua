local Migration = require("rio.database.migrate").Migration

local CreateTasks = Migration:extend()

function CreateTasks:up()
    self:create_table("tasks", function(t)
        t:string("title")
        t:text("description")
        t:string("status")
        t:timestamps()
    end)
end

function CreateTasks:down()
    self:drop_table("tasks")
end

return CreateTasks