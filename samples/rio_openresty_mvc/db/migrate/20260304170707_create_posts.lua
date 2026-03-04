local Migration = require("rio.database.migrate").Migration

local CreatePosts = Migration:extend()

function CreatePosts:up()
    self:create_table("posts", function(t)
        t:string("title")
        t:text("body")
        t:boolean("published")
        t:float("price")
        t:integer("priority")
        t:timestamps()
    end)
end

function CreatePosts:down()
    self:drop_table("posts")
end

return CreatePosts