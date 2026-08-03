package.path = "lib/?.lua;lib/?/init.lua;" .. package.path

local console = require("rio.cli.commands.console")

describe("Rio CLI Console", function()
    it("loads the configured console line editor", function()
        local module_name = assert(console.line_editor_module)
        local ok, line_editor = pcall(require, module_name)

        assert.is_true(ok)
        assert.is_table(line_editor)
        assert.truthy(line_editor.line or line_editor.bestline)
    end)
end)
