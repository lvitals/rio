local Profile = require("rio.database.model"):extend({
    table_name = "profiles",
    fillable = { "user_id", "full_name", "bio" }
})

-- Relationships
Profile:belongs_to("user")

-- Validations
Profile.validates = {
    user_id   = { presence = true, numericality = { only_integer = true } },
    full_name = { presence = true, length = { minimum = 3, maximum = 100 } },
    bio       = { length = { maximum = 500 } }
}

return Profile
