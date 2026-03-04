local Model = require("rio.database.model")
local hash = require("rio.utils.hash")

local User = Model:extend({
    table_name = "users",
    fillable = { "username", "password", "email" }
})

User.hidden = { "password" }

-- Relationships
User:has_one("profile", { dependent = "destroy" })
User:has_many("projects", { dependent = "destroy" })

-- Validations
User.validates = {
    username = { presence = true, uniqueness = true },
    password = { presence = true, length = { minimum = 6 } },
    email    = { presence = true }
}

-- Hooks
function User:before_save()
    if self.password and (not self._exists or self.password ~= self._original.password) then
        self.password = hash.encrypt(self.password)
    end
end

return User
