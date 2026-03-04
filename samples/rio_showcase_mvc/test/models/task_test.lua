local Task = require("app.models.task")

describe("Task Model", function()
    it("should exist", function()
        assert.is_table(Task)
    end)
end)