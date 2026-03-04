local Label = require("rio.database.model"):extend({
    table_name = "labels",
    fillable = { "name", "color" }
})

-- Relationships
Label:has_many("project_labels", { dependent = "destroy" })
Label:has_many("projects", { through = "project_labels" })

-- Validations
Label.validates = {
    name  = { presence = true, uniqueness = true, length = { minimum = 1, maximum = 50 } },
    color = { presence = true, length = { minimum = 4, maximum = 7 } } -- Hex format #RGB or #RRGGBB
}

return Label
