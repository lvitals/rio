local Project = require("app.models.project")

describe("Project Model", function()
    it("should exist", function()
        assert.is_table(Project)
    end)
end)