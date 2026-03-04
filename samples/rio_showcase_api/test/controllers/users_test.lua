local UsersController = require("app.controllers.users_controller")

describe("UsersController", function()
    it("should exist", function()
        assert.is_table(UsersController)
    end)
end)