package.path = "lib/?.lua;lib/?/init.lua;" .. package.path

local parser = require("rio.cli.parser")

describe("Rio CLI Parser", function()
    it("returns an empty invocation when no command is provided", function()
        local invocation = parser.parse({})
        assert.is_nil(invocation.command)
        assert.same({}, invocation.args)
        assert.is_false(invocation.help)
    end)

    it("splits colon commands without losing nested subcommands", function()
        local invocation = parser.parse({ "db:system:change", "--to=postgresql" })
        assert.equals("db", invocation.command)
        assert.equals("system:change", invocation.subcommand)
        assert.same({ "--to=postgresql" }, invocation.args)
    end)

    it("detects help flags and removes them from args", function()
        local invocation = parser.parse({ "server", "--port=3000", "--help" })
        assert.equals("server", invocation.command)
        assert.is_true(invocation.help)
        assert.same({ "--port=3000" }, invocation.args)
    end)

    it("supports space-separated subcommands for generate and destroy", function()
        local generate = parser.parse({ "generate", "model", "Post" }, {
            shift_subcommand_for = { generate = true }
        })
        assert.equals("generate", generate.command)
        assert.equals("model", generate.subcommand)
        assert.same({ "Post" }, generate.args)

        local destroy = parser.parse({ "destroy", "controller", "Posts" }, {
            shift_subcommand_for = { destroy = true }
        })
        assert.equals("destroy", destroy.command)
        assert.equals("controller", destroy.subcommand)
        assert.same({ "Posts" }, destroy.args)
    end)
end)
