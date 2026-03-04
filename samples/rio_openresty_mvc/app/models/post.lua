local Post = require("rio.database.model"):extend({
    table_name = "posts",
    fillable = { "title", "body", "published", "price", "priority" }
})

-- Define validations, relationships, etc. here
Post.validates = {
    title = {
        presence = true,
        length = { minimum = 3, maximum = 255 }
    },
    body = {
        presence = true
    },
    price = {
        numericality = {}
    },
    priority = {
        numericality = { only_integer = true, greater_than = 0 }
    }
}

return Post
