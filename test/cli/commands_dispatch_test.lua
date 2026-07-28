if not describe then
    print("Usage: busted test/cli/commands_dispatch_test.lua")
    os.exit(1)
end

package.path = "lib/?.lua;lib/?/init.lua;" .. package.path

local helpers = require("test.cli.helpers")

local function fake_ui()
    return {
        status = function() end,
        line = function() end,
        warn = function() end,
        info = function() end,
        header = function() end,
        box = function(_, fn) if fn then fn() end end,
        row = function() end
    }
end

local function fake_context()
    local calls = {}
    local context = {
        ui = fake_ui(),
        colors = {},
        db_drivers = {
            supported_names = function() return "sqlite3, mysql, mariadb, postgresql" end
        },
        is_api_only = function() return false end
    }

    for _, name in ipairs({
        "show_general_help", "show_db_help", "show_routes_help",
        "show_middleware_help", "show_new_help", "show_server_help",
        "show_console_help", "show_runner_help", "show_generate_help",
        "show_destroy_help", "show_test_help", "show_stats_help",
        "show_initializers_help", "show_about_help", "show_tmp_help",
        "show_mailbox_help"
    }) do
        context[name] = function()
            calls[name] = (calls[name] or 0) + 1
        end
    end

    return context, calls
end

describe("Rio CLI Command Dispatch", function()
    it("routes help command targets to the expected help screen", function()
        local context, calls = fake_context()
        local command = require("rio.cli.commands.help").command()

        command:execute({ command = "help", args = { "db:migrate" } }, context)
        command:execute({ command = "help", args = { "routes" } }, context)
        command:execute({ command = "help", args = { "missing" } }, context)

        assert.equals(1, calls.show_db_help)
        assert.equals(1, calls.show_routes_help)
        assert.equals(1, calls.show_general_help)
    end)

    it("preserves documented db subcommand dispatch", function()
        package.loaded["rio.cli.commands.db"] = nil
        package.loaded["rio.cli.commands.db_core"] = {
            new = function()
                local calls = {}
                local core = {
                    calls = calls,
                    drivers = function() table.insert(calls, "drivers") end,
                    install = function() table.insert(calls, "install") end,
                    uninstall = function() table.insert(calls, "uninstall") end,
                    create = function() table.insert(calls, "create") end,
                    drop = function() table.insert(calls, "drop") end,
                    migrate = function() table.insert(calls, "migrate") end,
                    rollback = function() table.insert(calls, "rollback") end,
                    status = function() table.insert(calls, "status") end,
                    version = function() table.insert(calls, "version") end,
                    prepare = function() table.insert(calls, "prepare") end,
                    setup = function() table.insert(calls, "setup") end,
                    reset = function() table.insert(calls, "reset") end,
                    seed = function() table.insert(calls, "seed") end,
                    ["seed:replant"] = function() table.insert(calls, "seed:replant") end,
                    ["cache:clear"] = function() table.insert(calls, "cache:clear") end,
                    ["system:change"] = function() table.insert(calls, "system:change") end
                }
                return core
            end
        }

        local command = require("rio.cli.commands.db").command()
        local context = fake_context()
        for _, subcommand in ipairs({
            "drivers", "install", "uninstall", "create", "drop", "migrate",
            "rollback", "status", "version", "prepare", "setup", "reset",
            "seed", "seed:replant", "cache:clear", "system:change"
        }) do
            assert.is_true(command:execute({
                command = "db",
                subcommand = subcommand,
                args = {}
            }, context))
        end

        assert.same({
            "drivers", "install", "uninstall", "create", "drop", "migrate",
            "rollback", "status", "version", "prepare", "setup", "reset",
            "seed", "seed:replant", "cache:clear", "system:change"
        }, context.__db_core.calls)

        package.loaded["rio.cli.commands.db"] = nil
        package.loaded["rio.cli.commands.db_core"] = nil
    end)

    it("dispatches generator aliases without changing public commands", function()
        local context = fake_context()
        local called = {}
        context.generate_scaffold = function(name, fields, api_only)
            called.scaffold = { name, fields, api_only }
        end
        context.generate_resource = function(name, fields, api_only)
            called.resource = { name, fields, api_only }
        end

        local command = require("rio.cli.commands.generate").command()
        command:execute({ command = "scaffold", args = { "Post", "title:string" } }, context)
        command:execute({ command = "resource", args = { "User", "--api" } }, context)

        assert.equals("Post", called.scaffold[1])
        assert.same({ "title:string" }, called.scaffold[2])
        assert.is_false(called.scaffold[3])
        assert.equals("User", called.resource[1])
        assert.is_true(called.resource[3])
    end)

    it("keeps cli.run as a thin dispatcher", function()
        local command_ok
        local exit_code
        local output = helpers.capture_prints(function()
            command_ok, exit_code = require("rio.cli").run({ "unknown" }, "lib/?.lua;lib/?/init.lua", "bin/rio")
        end)

        assert.is_false(command_ok)
        assert.equals(1, exit_code)
        assert.truthy(output:find("Unknown command 'unknown'", 1, true))
        assert.truthy(output:find("RIO FRAMEWORK CLI", 1, true))
    end)

    it("returns a non-zero process status for unknown commands", function()
        local result = helpers.run(helpers.shell_quote(helpers.bin_path()) .. " unknown")

        assert.is_false(result.ok)
        assert.equals(1, result.code)
        assert.truthy(result.output:find("Unknown command 'unknown'", 1, true))
    end)

    it("returns busted failures from the rio executable", function()
        local command = helpers.shell_quote(helpers.bin_path())
            .. " test "
            .. helpers.shell_quote("test/fixtures/failing_spec.lua")
        local result = helpers.run(command)

        assert.is_false(result.ok)
        assert.equals(1, result.code)
        assert.truthy(result.output:find("1 failure", 1, true))
    end)
end)
