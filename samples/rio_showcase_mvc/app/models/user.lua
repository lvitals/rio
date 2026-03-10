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
        length = { minimum = 6 } 
    },
    email = { presence = true }
}

-- Custom validation for password confirmation
function User:validate()
    -- Run standard validations first (from Model base class)
    local ok = Model.validate(self)
    
    -- Custom presence for password: only required if NEW record
    if not self._exists and (not self.password or self.password == "") then
        self.errors:add("password", "is required")
        ok = false
    end

    -- Only validate confirmation if password is being set/changed
    -- We check if self.password exists and is DIFFERENT from the original hash
    local is_password_dirty = self.password and (not self._exists or self.password ~= self._original.password)
    
    if is_password_dirty and (self.password_confirmation or not self._exists) then
        if self.password ~= self.password_confirmation then
            self.errors:add("password_confirmation", "does not match password")
            ok = false
        end
    end
    
    return ok
end

return User
