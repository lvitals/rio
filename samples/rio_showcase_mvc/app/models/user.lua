local Model = require("rio.database.model")
local hash = require("rio.utils.hash")

local User = Model:extend({
    table_name = "users",
    fillable = { "username", "password", "email", "is_admin" }
})

-- Hooks
function User:before_save()
    if self.password and (not self._exists or self.password ~= self._original.password) then
        self.password = hash.encrypt(self.password)
    end
end

-- Validations
User.validates = {
    username = { presence = true, uniqueness = true },
    password = { 
        presence = { message = "is required" }, 
        length = { minimum = 6 } 
    },
    email = { presence = true }
}

-- Custom validation for password confirmation
function User:validate()
    -- Run standard validations first
    local ok = self.class.class.__index.validate(self)
    
    -- Only validate confirmation if password is being set/changed
    if self.password and self.password ~= "" and self.password_confirmation then
        if self.password ~= self.password_confirmation then
            self.errors:add("password_confirmation", "does not match password")
            ok = false
        end
    elseif not self._exists and not self.password_confirmation then
        -- Required on creation
        self.errors:add("password_confirmation", "can't be blank")
        ok = false
    end
    
    return ok
end

return User
