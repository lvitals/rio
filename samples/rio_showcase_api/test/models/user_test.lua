local User = require("app.models.user")

describe("User Model", function()
    it("should exist", function()
        assert.is_table(User)
    end)
end)