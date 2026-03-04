local User = require("app.models.user")
local AdminUsersController = require("app.controllers.admin_users_controller")

describe("AdminUsersController", function()
    -- Mock context helper
    local function mock_ctx(params, body, state_user_id)
        return {
            params = params or {},
            body = body or {},
            state = { user = { id = state_user_id or 999 } },
            view = function(self, path, data) return { type = "view", path = path, data = data } end,
            json = function(self, data, status) return { type = "json", data = data, status = status or 200 } end,
            redirect = function(self, url) return { type = "redirect", url = url } end,
            text = function(self, status, msg) return { type = "text", status = status, msg = msg } end
        }
    end

    before_each(function()
        local DBManager = require("rio.database.manager")
        DBManager.clear_query_cache()
        User:raw("DELETE FROM " .. User.table_name)
    end)

    it("should list users", function()
        User:create({ username = "test", password = "password123", password_confirmation = "password123", email = "t@t.com" })
        local ctx = mock_ctx()
        local res = AdminUsersController:index(ctx)
        
        assert.equals("view", res.type)
        assert.equals("admin_users/index", res.path)
        assert.is_table(res.data.users)
    end)

    it("should create a user", function()
        local body = { username = "newadmin", password = "password123", password_confirmation = "password123", email = "new@admin.com", is_admin = "1" }
        local ctx = mock_ctx({}, body)
        local res = AdminUsersController:create(ctx)
        
        assert.equals("redirect", res.type)
        
        local user = User:first()
        assert.is_not_nil(user)
        assert.equals("newadmin", user.username)
        -- SQLite handles true as 1
        assert.is_true(user.is_admin == true or user.is_admin == 1 or user.is_admin == "1")
    end)

    it("should prevent self-deletion", function()
        local user = User:create({ username = "admin", password = "password123", password_confirmation = "password123", email = "a@a.com" })
        local ctx = mock_ctx({ id = user.id }, {}, user.id) -- Mock logged in as the same user
        
        local res = AdminUsersController:destroy(ctx)
        
        assert.equals("redirect", res.type)
        assert.matches("alert=You cannot delete yourself", res.url)
    end)
    
    it("should allow deleting other users", function()
        local user = User:create({ username = "other", password = "password123", password_confirmation = "password123", email = "a@a.com" })
        local ctx = mock_ctx({ id = user.id }, {}, 999) -- Logged in as different ID
        
        local res = AdminUsersController:destroy(ctx)
        
        assert.equals("redirect", res.type)
        assert.matches("notice=User deleted", res.url)
    end)
end)
