local Migration = require("rio.database.migrate").Migration

local CreateProjectLabels = Migration:extend()

function CreateProjectLabels:up()
    self:create_table("project_labels", function(t)
        t:references("project")
        t:references("label")
        t:timestamps()
    end)
end

function CreateProjectLabels:down()
    self:drop_table("project_labels")
end

return CreateProjectLabels