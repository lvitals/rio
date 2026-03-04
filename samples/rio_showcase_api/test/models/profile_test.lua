local Profile = require("app.models.profile")

describe("Profile Model", function()
    it("should exist", function()
        assert.is_table(Profile)
    end)
end)