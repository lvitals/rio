local User = require("app.models.user")
local AuthController = require("app.controllers.auth_controller")

describe("AuthController", function()
    -- Mock context helper
    local function mock_ctx(params, body, state)
        return {
            params = params or {},
            body = body or {},
            state = state or {},
            view = function(self, path, data) return { type = "view", path = path, data = data } end,
            json = function(self, data, status) return { type = "json", data = data, status = status or 200 } end,
            redirect = function(self, url) return { type = "redirect", url = url } end,
            text = function(self, status, msg) return { type = "text", status = status, msg = msg } end,
            setCookie = function(self, name, value, opts) self.cookie = value end,
            getCookie = function(self, name) return self.cookie end
        }
    end

    before_each(function()
        local DBManager = require("rio.database.manager")
        DBManager.clear_query_cache()
        User:raw("DELETE FROM " .. User.table_name)
    end)

    it("should show login view if not logged in", function()
        local ctx = mock_ctx()
        local res = AuthController:new(ctx)
        assert.equals("view", res.type)
        assert.equals("auth/login", res.path)
    end)

    it("should redirect to tasks if already logged in", function()
        local ctx = mock_ctx({}, {}, { user = { id = 1, username = "test" } })
        local res = AuthController:new(ctx)
        assert.equals("redirect", res.type)
        assert.equals("/tasks", res.url)
    end)

    it("should authenticate valid user", function()
        User:raw("DELETE FROM " .. User.table_name)
        
        local user, instance = User:create({ username = "testuser", password = "password123", password_confirmation = "password123", email = "test@example.com", is_admin = false })
        
        local ctx = mock_ctx({}, { username = "testuser", password = "password123" })
        local res = AuthController:create(ctx)
        
        assert.equals("redirect", res.type)
        assert.matches("/tasks", res.url)
    end)

    it("should reject invalid credentials", function()
        User:raw("DELETE FROM " .. User.table_name)
        User:create({ username = "testuser", password = "password123", password_confirmation = "password123", email = "test@example.com", is_admin = false })
        
        local ctx = mock_ctx({}, { username = "testuser", password = "wrong" })
        local res = AuthController:create(ctx)
        
        assert.equals("view", res.type)
        assert.equals("auth/login", res.path)
        assert.is_not_nil(res.data.alert)
    end)

    it("should clear session on logout", function()
        local ctx = mock_ctx()
        local res = AuthController:destroy(ctx)
        
        assert.equals("redirect", res.type)
        assert.matches("/login", res.url)
        assert.equals("", ctx.cookie)
    end)
end)
