package.path = "lib/?.lua;lib/?/init.lua;" .. package.path

local Command = require("rio.cli.command")
local Registry = require("rio.cli.registry")

describe("Rio CLI Registry", function()
    it("dispatches registered commands", function()
        local called = false
        local registry = Registry.new():register(Command.new({
            name = "hello",
            run = function()
                called = true
                return true
            end
        }))

        assert.is_true(registry:dispatch({ command = "hello" }, {}))
        assert.is_true(called)
    end)

    it("uses command aliases", function()
        local called = false
        local registry = Registry.new():register(Command.new({
            name = "generate",
            aliases = { "scaffold", "resource" },
            run = function()
                called = true
                return true
            end
        }))

        assert.is_true(registry:dispatch({ command = "scaffold" }, {}))
        assert.is_true(called)
    end)

    it("propagates command failure status and exit code", function()
        local registry = Registry.new():register(Command.new({
            name = "failing",
            run = function()
                return false, 23
            end
        }))

        local handled, ok, exit_code = registry:dispatch({ command = "failing" }, {})

        assert.is_true(handled)
        assert.is_false(ok)
        assert.equals(23, exit_code)
    end)

    it("registers every documented command family", function()
        local registry = Registry.with_defaults()
        for _, command in ipairs({
            "new", "server", "console", "runner", "routes", "test",
            "about", "stats", "initializers", "scaffold", "resource",
            "help", "generate", "destroy", "db", "tmp", "middleware",
            "mailbox", "ui"
        }) do
            assert.truthy(registry.commands[command], command .. " should be registered")
        end
    end)
end)
