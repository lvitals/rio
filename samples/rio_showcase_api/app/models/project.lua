local Project = require("rio.database.model"):extend({
    table_name = "projects",
    fillable = { "user_id", "name", "description" }
})

-- Relationships
Project:belongs_to("user")
Project:has_many("project_labels", { dependent = "destroy" })
Project:has_many("labels", { through = "project_labels" })

-- Validations
Project.validates = {
    user_id     = { presence = true, numericality = { only_integer = true } },
    name        = { presence = true, length = { minimum = 2, maximum = 150 } },
    description = { length = { maximum = 1000 } }
}

return Project
