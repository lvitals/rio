local ProjectsController = require("app.controllers.projects_controller")

describe("ProjectsController", function()
    it("should exist", function()
        assert.is_table(ProjectsController)
    end)
end)