-- rio/lib/rio/cli/project.lua
-- Project scaffolding for `rio new`.

local string_utils = require("rio.utils.string")

local M = {}

local function write(ctx, path, content)
    local ok = ctx.files.write(path, content)
    if not ok then
        print("Error: Could not open file for writing: " .. path)
    end
end

function M.create(ctx, project_name, database_adapter, api_only)
    print("Creating new Rio project: " .. project_name .. (api_only and " (API-only)" or ""))

    ctx.files.ensure_dir(project_name)

    write(ctx, project_name .. "/app.lua", [[
-- app.lua
-- Main application entry point for the Rio framework.

-- Load project configuration
local ok_config, config = pcall(require, "config.application")
if not ok_config then config = {} end

-- Initialize and run the application
local rio = require("rio")
local app = rio.new(config)

-- Start the server (automatically loads DB, Middlewares, Initializers, and Routes)
app:run()
]])
    write(ctx, project_name .. "/bootstrap.lua", [[
-- bootstrap.lua
-- Initializes the Rio environment and loads configurations.
-- This file is typically required by app.lua.
]])
    write(ctx, project_name .. "/README.md", "# " .. project_name .. "\n\nAn Rio project.")

    local app_dir = project_name .. "/app"
    ctx.files.ensure_dir(app_dir)
    ctx.files.ensure_dir(app_dir .. "/controllers")
    ctx.files.ensure_dir(app_dir .. "/mailers")
    ctx.files.ensure_dir(app_dir .. "/models")

    local home_controller_content = [[
local HomeController = {}

function HomeController:index(ctx)
]]
    if api_only then
        home_controller_content = home_controller_content .. [[
    return ctx:json({ message = "Welcome to Rio API" })
]]
    else
        home_controller_content = home_controller_content .. [[
    ctx:view("home/index")
]]
    end
    home_controller_content = home_controller_content .. [[
end

return HomeController
]]
    write(ctx, app_dir .. "/controllers/home_controller.lua", home_controller_content)

    if not api_only then
        ctx.files.ensure_dir(app_dir .. "/views")
        ctx.files.ensure_dir(app_dir .. "/views/home")
        write(ctx, app_dir .. "/views/home/index.etl", [[
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to Rio!</title>
</head>
<body>
    <h1>Welcome to Rio!</h1>
    <p>This is your new Rio application.</p>
</body>
</html>
]])
    end

    local config_dir = project_name .. "/config"
    ctx.files.ensure_dir(config_dir)
    ctx.files.ensure_dir(config_dir .. "/initializers")

    local app_name_human = string_utils.camel_case(project_name)
    local api_version_content = api_only and [[
    api_version = "v1",
    api_versions = { "v1" },
]] or ""

    local application_content = string.format([[
-- config/application.lua
-- Application-wide configurations for the Rio framework.

return {
    server = {
        port = 8080,
        host = "0.0.0.0"
    },
    environment = "development",
    api_only = %s,
    title = "%s API",
    description = "Auto-generated documentation for %s",
%s
    version = "1.0.0",
    api_format = "json", -- Options: "json", "jsonapi"

    -- Documentation settings
    -- openapi_path = "/docs",           -- Changes the UI path from /docs to your preference
    -- openapi_json_path = "/openapi.json" -- Changes the JSON spec path
}
]], tostring(api_only), app_name_human, app_name_human, api_version_content)
    write(ctx, config_dir .. "/application.lua", application_content)

    local middlewares_content = [[
-- config/middlewares.lua
--
-- This file is used to configure the application's middleware stack.
--
return {
    "logger",
    "security",
    "cors"]]

    if api_only then
        middlewares_content = middlewares_content .. ",\n    \"openapi\""
    end
    middlewares_content = middlewares_content .. "\n}\n"
    write(ctx, config_dir .. "/middlewares.lua", middlewares_content)

    local database_content = ctx.generate_database_content(database_adapter, project_name)
    if database_adapter == "none" or database_content == "" then
        database_content = string.format([[
-- config/database.lua
-- Database configurations for the Rio framework.
-- No database adapter selected.
-- To enable a database, uncomment and configure one of the examples below,
-- or run 'rio new <project_name> --database=<adapter>'.
-- Or simply run 'rio db:setup' to configure it interactively.
--
-- Example for SQLite:
-- return {
--     development = {
--         adapter = "sqlite",
--         database = "db/development.sqlite3"
--     },
--     test = {
--         adapter = "sqlite",
--         database = "db/test.sqlite3"
--     },
--     production = {
--         adapter = "sqlite",
--         database = "db/production.sqlite3"
--     }
-- }
--
-- Example for PostgreSQL:
-- return {
--     development = {
--         adapter = "postgres",
--         host = "localhost",
--         port = 5432,
--         username = "rio_dev",
--         password = "password",
--         database = "%s_development"
--     }
-- }
--
-- Example for MySQL:
-- return {
--     development = {
--         adapter = "mysql",
--         host = "127.0.0.1",
--         port = 3306,
--         username = "root",
--         password = "password",
--         database = "%s_development"
--     }
-- }
return {}
]], project_name, project_name)
    end
    write(ctx, config_dir .. "/database.lua", database_content)
    write(ctx, config_dir .. "/routes.lua", [[
-- config/routes.lua
-- Defines the application's routes using the Rio router.

return function(app)
    -- Format: "ControllerName@actionName" enables auto-documentation
    app:get("/", "Home@index")
end
]])

    local db_dir = project_name .. "/db"
    ctx.files.ensure_dir(db_dir)
    ctx.files.ensure_dir(db_dir .. "/migrate")
    write(ctx, db_dir .. "/seeds.lua", [[
-- db/seeds.lua
-- This file is used to seed the database with initial data.
-- Example:
-- local Product = require("app.models.product")
-- Product:create({ name = "Default Product", price = 100 })
]])

    local lib_dir = project_name .. "/lib"
    ctx.files.ensure_dir(lib_dir)
    ctx.files.ensure_dir(lib_dir .. "/tasks")

    ctx.files.ensure_dir(project_name .. "/log")
    ctx.files.ensure_dir(project_name .. "/public")

    local test_dir = project_name .. "/test"
    ctx.files.ensure_dir(test_dir)
    ctx.files.ensure_dir(test_dir .. "/controllers")
    ctx.files.ensure_dir(test_dir .. "/fixtures")
    ctx.files.ensure_dir(test_dir .. "/models")

    write(ctx, test_dir .. "/spec_helper.lua", [[
-- test/spec_helper.lua
-- Standard Rio Test Helper

-- 1. Automagically find the Rio framework relative to the current project
local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*/)") or "./"

-- Injects local framework's lib/ into package.path with high precedence
package.path = script_dir .. "../../lib/?.lua;" ..
               script_dir .. "../../lib/?/init.lua;" ..
               package.path

-- 2. Load the Rio testing engine
local rio_tests = require("rio.utils.tests")

-- 3. Setup the environment (paths, busted, database, assertions)
rio_tests.setup()
]])

    ctx.ui.alert_title("success", "project", project_name .. (api_only and " (API-only)" or "") .. " created successfully!")
    if database_adapter ~= "none" and not ctx.is_database_driver_available(database_adapter) then
        ctx.print_driver_install_hint(database_adapter)
    end
    ctx.ui.info("To run your application, navigate to the project directory and run: lua app.lua or rio server")
end

return M
