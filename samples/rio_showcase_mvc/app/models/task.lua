local Task = require("rio.database.model"):extend({
    table_name = "tasks",
    fillable = { "title", "description", "status" }
})

-- Define validations, relationships, etc. here
-- Task.validates = {
--     title = { presence = true }
-- }

return Task