package.path = "lib/?.lua;lib/?/init.lua;" .. package.path

local helpers = require("test.cli.helpers")

local bin = helpers.shell_quote(helpers.bin_path())

local function rio(args, cwd)
    return helpers.run(bin .. " " .. args, cwd)
end

local function assert_success(result)
    assert.is_true(result.ok, result.output)
end

describe("Rio CLI Functional Commands", function()
    it("shows general help and unknown command errors through rio.ui", function()
        local help = rio("")
        assert_success(help)
        assert.truthy(help.output:find("RIO FRAMEWORK CLI", 1, true))

        local unknown = rio("unknown")
        assert.is_false(unknown.ok)
        assert.equals(1, unknown.code)
        assert.truthy(unknown.output:find("Unknown command 'unknown'", 1, true))
        assert.truthy(unknown.output:find("RIO FRAMEWORK CLI", 1, true))
    end)

    it("provides help for every documented command family", function()
        for _, args in ipairs({
            "new --help",
            "server --help",
            "console --help",
            "runner --help",
            "routes --help",
            "test --help",
            "about --help",
            "stats --help",
            "initializers --help",
            "generate --help",
            "destroy --help",
            "db --help",
            "tmp --help",
            "middleware --help",
            "mailbox --help",
            "help db"
        }) do
            local result = rio(args)
            assert_success(result)
            assert.truthy(result.output:find("Usage: rio", 1, true), args)
        end
    end)

    it("recognizes documented database subcommands without executing destructive operations", function()
        for _, args in ipairs({
            "db:create --help",
            "db:drop --help",
            "db:drivers --help",
            "db:install sqlite --help",
            "db:uninstall sqlite --help",
            "db:remove sqlite --help",
            "db:migrate --help",
            "db:rollback --help",
            "db:status --help",
            "db:version --help",
            "db:setup --help",
            "db:reset --help",
            "db:prepare --help",
            "db:seed --help",
            "db:seed:replant --help",
            "db:cache:clear --help",
            "db:system:change --help"
        }) do
            local result = rio(args)
            assert_success(result)
            assert.truthy(result.output:find("DATABASE MANAGEMENT", 1, true), args)
        end

        local drivers = rio("db:drivers")
        assert_success(drivers)
        assert.truthy(drivers.output:find("DATABASE DRIVERS", 1, true))
    end)

    it("prints a friendly routes error outside a Rio project", function()
        local result = rio("routes", "/tmp")
        assert_success(result)
        assert.truthy(result.output:find("config/routes.lua was not found", 1, true))
        assert.is_nil(result.output:find("module 'config.routes' not found", 1, true))
    end)

    it("runs read-only project commands against the MVC sample", function()
        local sample = helpers.repo_root() .. "/samples/rio_showcase_mvc"

        local routes = rio("routes", sample)
        assert_success(routes)
        assert.truthy(routes.output:find("Total routes: 20", 1, true))

        local middleware = rio("middleware", sample)
        assert_success(middleware)
        assert.truthy(middleware.output:find("ACTIVE MIDDLEWARE STACK", 1, true))

        local runner = rio("runner --skip-executor " .. helpers.shell_quote("print(\"runner-ok\")"), sample)
        assert_success(runner)
        assert.truthy(runner.output:find("runner-ok", 1, true))

        local about = rio("about --help", sample)
        assert_success(about)
        assert.truthy(about.output:find("ENVIRONMENT INFO", 1, true))
    end)

    it("creates a project and exercises generators, destructors, tmp, middleware and mailbox safely", function()
        local root = helpers.tmpdir("rio_cli_functional")
        local project_name = "cli_app"
        local project_root = root .. "/" .. project_name

        local created = rio("new " .. project_name .. " --database=none", root)
        assert_success(created)
        assert.is_true(helpers.exists(project_root .. "/config/routes.lua"))

        for _, args in ipairs({
            "generate controller Reports index show",
            "generate model Product name:string",
            "generate migration AddSkuToProducts sku:string",
            "generate channel Chat",
            "generate resource Category title:string --api",
            "generate scaffold Task title:string --api",
            "scaffold AliasThing name:string --api",
            "resource AliasItem title:string --api"
        }) do
            local result = rio(args, project_root)
            assert_success(result)
        end

        assert.is_true(helpers.exists(project_root .. "/app/controllers/reports_controller.lua"))
        assert.is_true(helpers.exists(project_root .. "/app/models/product.lua"))
        assert.is_true(helpers.exists(project_root .. "/app/channels/chat_channel.lua"))

        helpers.mkdir_p(project_root .. "/app/middleware")
        helpers.write(project_root .. "/app/middleware/audit_middleware.lua", [[
return {
    name = "audit",
    description = "Audit trail",
    call = function(_, next) return next() end
}
]])

        for _, args in ipairs({
            "tmp:create",
            "tmp:cache:clear",
            "tmp:sockets:clear",
            "tmp:screenshots:clear",
            "tmp:pids:clear",
            "tmp:clear",
            "middleware",
            "middleware:use audit",
            "middleware:unuse audit",
            "mailbox:install",
            "mailbox:ingress:exim",
            "mailbox:ingress:postfix",
            "mailbox:ingress:qmail",
            "stats",
            "initializers",
            "about --help",
            "destroy controller Reports",
            "destroy model Product",
            "destroy migration AddSkuToProducts"
        }) do
            local result = rio(args, project_root)
            assert_success(result)
        end

        assert.is_false(helpers.exists(project_root .. "/app/controllers/reports_controller.lua"))
        assert.is_false(helpers.exists(project_root .. "/app/models/product.lua"))

        helpers.remove_tree(root)
    end)

    it("keeps ui:test available for rio.ui diagnostics", function()
        local result = rio("ui:test")
        assert_success(result)
        assert.truthy(result.output:find("RIO UI SHOWCASE", 1, true))
    end)
end)
