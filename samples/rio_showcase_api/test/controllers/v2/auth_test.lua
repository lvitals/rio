local AuthController = require("app.controllers.v2/auth_controller")

describe("AuthController", function()
    it("should exist", function()
        assert.is_table(AuthController)
    end)
end)