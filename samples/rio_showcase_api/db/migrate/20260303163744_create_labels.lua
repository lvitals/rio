local Migration = require("rio.database.migrate").Migration

local CreateLabels = Migration:extend()

function CreateLabels:up()
    self:create_table("labels", function(t)
        t:string("name")
        t:string("color")
        t:timestamps()
    end)
end

function CreateLabels:down()
    self:drop_table("labels")
end

return CreateLabels