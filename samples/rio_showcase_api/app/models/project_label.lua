local ProjectLabel = require("rio.database.model"):extend({
    table_name = "project_labels",
    fillable = { "project_id", "label_id" }
})

-- Relationships
ProjectLabel:belongs_to("project")
ProjectLabel:belongs_to("label")

-- Validations
ProjectLabel.validates = {
    project_id = { presence = true, numericality = { only_integer = true } },
    label_id   = { presence = true, numericality = { only_integer = true } }
}

return ProjectLabel
