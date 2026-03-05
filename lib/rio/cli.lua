local cli = {}

local compat = require("rio.utils.compat")
local load = compat.load
local unpack = compat.unpack

local socket_ok, socket = pcall(require, "socket")

local colors = {
    reset = "\27[0m",
    red = "\27[31m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    magenta = "\27[35m",
    cyan = "\27[36m",
    white = "\27[37m",
    bold = "\27[1m",
    dim = "\27[2m"
}

cli.colors = colors

--- Checks if a port is free for binding (listening)
-- @param port The port number to check (e.g., 8080)
-- @param host Optional, defaults to "127.0.0.1" (localhost only)
-- @return boolean true if the port is free, false if in use
local function is_port_free(port, host)
    if not socket_ok then return true end -- Assume free if we can't check
    host = host or "0.0.0.0"
    
    -- Check if something is actually LISTENING on that port.
    -- If we can connect, it's definitely busy and we should suggest another port.
    local test_socket = socket.tcp()
    test_socket:settimeout(0.2)
    local test_host = (host == "0.0.0.0") and "127.0.0.1" or host
    local conn_ok = test_socket:connect(test_host, port)
    test_socket:close()

    if conn_ok then
        return false -- Busy: Another server is actively listening
    end

    -- If no one is listening, we consider it free.
    -- Lingering connections (CLOSE_WAIT/TIME_WAIT) will be handled by 
    -- SO_REUSEADDR when the real server starts.
    return true
end

local rio_framework_lib_path_global = "" -- Declare globally at the top
local rio_bin_path_global = "rio" -- Default to just 'rio' in PATH

local function get_lua_paths() 
    return compat.get_runtime_paths(rio_framework_lib_path_global)
end

local string_utils = require("rio.utils.string")
local camel_case = string_utils.camel_case
local underscore = string_utils.underscore
local pluralize = string_utils.pluralize

local function create_dir_if_not_exists(path)
    os.execute("mkdir -p " .. path)
end

local function write_file_content(path, content)
    local file = io.open(path, "w")
    if file then
        file:write(content)
        file:close()
    else
        print("Error: Could not open file for writing: " .. path)
    end
end

local function set_executable_permission(path)
    os.execute("chmod +x " .. path)
end

-- Helper to parse fields and handle shell expansion/complex options
local function parse_fields(fields)
    local definitions = {}
    local order = {}

    for _, field in ipairs(fields) do
        local name, type_info = field:match("([^:]+):(.+)")
        if name and type_info then
            if not definitions[name] then
                table.insert(order, name)
                definitions[name] = { options = {} }
            end
            
            local col = definitions[name]
            local base_type = type_info:match("^([%a_]+)")
            local options_str = type_info:match("{([^}]+)}") or type_info:match("^[%a_]+(.*)$")
            
            if not col.type then col.type = base_type end

            if options_str and options_str ~= "" then
                local p, s = options_str:match("^(%d+),?(%d*)$")
                if p then
                    if col.type == "string" or col.type == "email" or col.type == "password" then
                        col.options.limit = tonumber(p)
                    elseif col.type == "decimal" then
                        if not col.options.precision then col.options.precision = tonumber(p)
                        else col.options.scale = tonumber(p) end
                    end
                end

                local def_val = options_str:match("default=([^,%s}]+)")
                if def_val then
                    if def_val == "true" then col.options.default = true
                    elseif def_val == "false" then col.options.default = false
                    elseif tonumber(def_val) then col.options.default = tonumber(def_val)
                    else col.options.default = def_val:gsub("^['\"]", ""):gsub("['\"]$", "") end
                end

                if options_str:find("unique=true") then col.options.unique = true end
                if options_str:find("polymorphic=true") then col.options.polymorphic = true end
                if options_str:find("has_one=true") then col.options.has_one = true end
            end
        end
    end
    return order, definitions
end

local generate_database_content -- Forward declaration

local function new_project(project_name, database_adapter, api_only)
    print("Creating new Rio project: " .. project_name .. (api_only and " (API-only)" or ""))

    create_dir_if_not_exists(project_name)

    -- Create core files
    write_file_content(project_name .. "/app.lua", [[
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
    write_file_content(project_name .. "/bootstrap.lua", [[
-- bootstrap.lua
-- Initializes the Rio environment and loads configurations.
-- This file is typically required by app.lua.
]])
    write_file_content(project_name .. "/README.md", "# " .. project_name .. "\n\nAn Rio project.")

    -- Create main directories and placeholder files
    local app_dir = project_name .. "/app"
    create_dir_if_not_exists(app_dir)
    create_dir_if_not_exists(app_dir .. "/controllers")
    create_dir_if_not_exists(app_dir .. "/mailers")
    create_dir_if_not_exists(app_dir .. "/models")

    -- Create default HomeController
    create_dir_if_not_exists(app_dir .. "/controllers")
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
    write_file_content(app_dir .. "/controllers/home_controller.lua", home_controller_content)

    -- Create default view
    if not api_only then
        create_dir_if_not_exists(app_dir .. "/views")
        create_dir_if_not_exists(app_dir .. "/views/home")
        write_file_content(app_dir .. "/views/home/index.etl", [[
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
    create_dir_if_not_exists(config_dir)
    create_dir_if_not_exists(config_dir .. "/initializers")
    local app_name_human = camel_case(project_name)
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
    version = "1.0.0",
    api_format = "json", -- Options: "json", "jsonapi"

    -- Documentation settings
    -- openapi_path = "/docs",           -- Changes the UI path from /docs to your preference
    -- openapi_json_path = "/openapi.json" -- Changes the JSON spec path
}
]], tostring(api_only), app_name_human, app_name_human)

    write_file_content(config_dir .. "/application.lua", application_content)

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

    write_file_content(config_dir .. "/middlewares.lua", middlewares_content)
    local database_content = generate_database_content(database_adapter, project_name)
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
    write_file_content(config_dir .. "/database.lua", database_content)
    write_file_content(config_dir .. "/routes.lua", [[
-- config/routes.lua
-- Defines the application's routes using the Rio router.

return function(app)
    -- Format: "ControllerName@actionName" enables auto-documentation
    app:get("/", "Home@index")
end
]])

    local db_dir = project_name .. "/db"
    create_dir_if_not_exists(db_dir)
    create_dir_if_not_exists(db_dir .. "/migrate")
    write_file_content(db_dir .. "/seeds.lua", [[
-- db/seeds.lua
-- This file is used to seed the database with initial data.
-- Example:
-- local Product = require("app.models.product")
-- Product:create({ name = "Default Product", price = 100 })
]])

    local lib_dir = project_name .. "/lib"
    create_dir_if_not_exists(lib_dir)
    create_dir_if_not_exists(lib_dir .. "/tasks")

    create_dir_if_not_exists(project_name .. "/log")
    create_dir_if_not_exists(project_name .. "/public")

    local test_dir = project_name .. "/test"
    create_dir_if_not_exists(test_dir)
    create_dir_if_not_exists(test_dir .. "/controllers")
    create_dir_if_not_exists(test_dir .. "/fixtures")
    create_dir_if_not_exists(test_dir .. "/models")

    -- Create test/spec_helper.lua
    write_file_content(test_dir .. "/spec_helper.lua", [[
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

    print("Project '" .. project_name .. "' created successfully!")
    print("To run your application, navigate to the project directory and run: lua app.lua or rio server")
end

-- Generator functions
local function generate_channel(channel_name)
    local underscored_name = underscore(channel_name)
    local channel_path = "app/channels/" .. underscored_name .. "_channel.lua"
    local camel_name = camel_case(channel_name)
    
    create_dir_if_not_exists("app/channels")
    print("Generating WebSocket channel: " .. channel_path)
    
    local content = {
        "local " .. camel_name .. "Channel = {}",
        "",
        "function " .. camel_name .. "Channel:subscribed()",
        "    -- self:stream_from(\"chat_room\")",
        "end",
        "",
        "function " .. camel_name .. "Channel:speak(data)",
        "    -- require(\"rio\").broadcast(\"chat_room\", { message = data.message })",
        "end",
        "",
        "return " .. camel_name .. "Channel"
    }
    write_file_content(channel_path, table.concat(content, "\n"))

    local routes_file = "config/routes.lua"
    local f = io.open(routes_file, "r")
    if f then
        local routes_content = f:read("*a")
        f:close()
        local ws_route = "    app:ws(\"/cable/" .. underscored_name .. "\", \"" .. camel_name .. "Channel\")"
        if not routes_content:find(ws_route, 1, true) then
            local modified = routes_content:gsub("(.-)end%s*$", "%1" .. ws_route .. "\nend")
            write_file_content(routes_file, modified)
            print("WebSocket route added to config/routes.lua: /cable/" .. underscored_name)
        end
    end
end

local function generate_controller(controller_name, actions, api_only)
    local path = "app/controllers/" .. underscore(controller_name) .. "_controller.lua"
    print("Generating controller: " .. path .. (api_only and " (API-only)" or ""))

    local content = {}
    local camelControllerName = camel_case(controller_name)
    table.insert(content, "local " .. camelControllerName .. "Controller = {}")
    table.insert(content, "")

    for _, action in ipairs(actions) do
        table.insert(content, "function " .. camelControllerName .. "Controller." .. action .. "(context)")
        table.insert(content, "    -- Implement " .. action .. " logic here")
        if api_only then
            table.insert(content, "    return context:json({ message = \"Hello from " .. camelControllerName .. "#" .. action .. "!\" })")
        else
            table.insert(content, "    return \"Hello from " .. camelControllerName .. "#" .. action .. "!\"")
        end
        table.insert(content, "end")
        table.insert(content, "")
    end

    table.insert(content, "return " .. camelControllerName .. "Controller")

    write_file_content(path, table.concat(content, "\n"))
    print("Controller '" .. controller_name .. "' generated successfully.")

    -- Generate test file for the controller
    local test_path = "test/controllers/" .. underscore(controller_name) .. "_test.lua"
    print("Generating controller test: " .. test_path)
    local test_content = {}
    table.insert(test_content, "local " .. camelControllerName .. "Controller = require(\"app.controllers." .. underscore(controller_name) .. "_controller\")")

    table.insert(test_content, "")
    table.insert(test_content, "describe(\"" .. camelControllerName .. "Controller\", function()")
    table.insert(test_content, "    it(\"should exist\", function()")
    table.insert(test_content, "        assert.is_table(" .. camelControllerName .. "Controller)")
    table.insert(test_content, "    end)")
    table.insert(test_content, "end)")

    write_file_content(test_path, table.concat(test_content, "\n"))
    print("Controller test '" .. controller_name .. "_test' generated successfully.")
end

local function generate_migration(migration_name, fields, table_name_hint)
    -- Check if migration already exists
    local underscored_name = underscore(migration_name)
    local handle_check = io.popen("ls db/migrate/*_" .. underscored_name .. ".lua 2>/dev/null")
    if handle_check then
        local existing = handle_check:read("*l")
        handle_check:close()
        if existing and existing ~= "" then
            print(colors.yellow .. "Notice: Migration '" .. migration_name .. "' already exists at " .. existing .. colors.reset)
            return existing:match("db/migrate/(.+)")
        end
    end

    local timestamp = os.date("%Y%m%d%H%M%S")
    local file_name = timestamp .. "_" .. underscore(migration_name) .. ".lua"
    local path = "db/migrate/" .. file_name
    print("Generating migration: " .. path)

    local content = {}
    table.insert(content, "local Migration = require(\"rio.database.migrate\").Migration")
    table.insert(content, "")
    table.insert(content, "local " .. camel_case(migration_name) .. " = Migration:extend()")
    table.insert(content, "")
    table.insert(content, "function " .. camel_case(migration_name) .. ":up()")
    
    if #fields > 0 then
        local target_table_name
        if table_name_hint then
            target_table_name = pluralize(table_name_hint)
        else
            -- For direct 'generate migration' calls, try to infer from migration_name
            target_table_name = pluralize(underscore(migration_name:gsub("^Add", ""):gsub("^Create", "")))
            if target_table_name == "" then target_table_name = pluralize(underscore(migration_name)) end
        end
        
        -- Detect if it's an "Add" or "Change" migration to use change_table
        local is_change = migration_name:match("^Add") or migration_name:match("^Change")
        
        if is_change then
            table.insert(content, "    self:change_table(\"" .. target_table_name .. "\", function(t)")
        else
            table.insert(content, "    self:create_table(\"" .. target_table_name .. "\", function(t)")
        end

        local column_order, column_definitions = parse_fields(fields)

        for _, name in ipairs(column_order) do
            local col = column_definitions[name]
            local extra_args = ""
            local opt_parts = {}
            
            -- Sort keys for consistent output
            local keys = {}
            for k in pairs(col.options) do table.insert(keys, k) end
            table.sort(keys)

            for _, k in ipairs(keys) do
                local v = col.options[k]
                if type(v) == "string" then
                    table.insert(opt_parts, k .. " = \"" .. v .. "\"")
                else
                    table.insert(opt_parts, k .. " = " .. tostring(v))
                end
            end

            if #opt_parts > 0 then
                extra_args = ", { " .. table.concat(opt_parts, ", ") .. " }"
            end

            local db_type = col.type or "string"
            -- Map HTML5 specific types to database 'string' (VARCHAR)
            local html5_types = { email=true, url=true, tel=true, color=true, password=true }
            if html5_types[db_type] then db_type = "string" end

            if col.type == "references" then
                table.insert(content, "        t:references(\"" .. name .. "\"" .. extra_args .. ")")
            else
                table.insert(content, "        t:" .. db_type .. "(\"" .. name .. "\"" .. extra_args .. ")")
            end
        end
        
        if not is_change then
            table.insert(content, "        t:timestamps()")
        end
        table.insert(content, "    end)")
    else
        table.insert(content, "    -- self:create_table(\"table_name\", function(t) ... end)")
    end
    table.insert(content, "end")
    table.insert(content, "")
    table.insert(content, "function " .. camel_case(migration_name) .. ":down()")
    if #fields > 0 then
        local target_table_name
        if table_name_hint then
            target_table_name = pluralize(table_name_hint)
        else
            target_table_name = pluralize(underscore(migration_name:gsub("^Add", ""):gsub("^Create", "")))
            if target_table_name == "" then target_table_name = pluralize(underscore(migration_name)) end
        end
        
        local is_change = migration_name:match("^Add") or migration_name:match("^Change")
        if is_change then
            for _, field in ipairs(fields) do
                local name = field:match("([^:]+)")
                table.insert(content, "    self:remove_column(\"" .. target_table_name .. "\", \"" .. name .. "\")")
            end
        else
            table.insert(content, "    self:drop_table(\"" .. target_table_name .. "\")")
        end
    else
        table.insert(content, "    -- self:drop_table(\"table_name\")")
    end
    table.insert(content, "end")
    table.insert(content, "")
    table.insert(content, "return " .. camel_case(migration_name))

    write_file_content(path, table.concat(content, "\n"))
    print("Migration '" .. migration_name .. "' generated successfully.")
end

local function generate_model(model_name, fields)
    local path = "app/models/" .. underscore(model_name) .. ".lua"
    print("Generating model: " .. path)

    local content = {}
    local camelModelName = camel_case(model_name)
    local pluralTableName = pluralize(underscore(model_name))

    local column_order, column_definitions = parse_fields(fields)
    
    -- Generate fillable table
    local fillable_parts = {}
    for _, name in ipairs(column_order) do
        local col = column_definitions[name]
        if col.type == "references" then
            table.insert(fillable_parts, "\"" .. name .. "_id\"")
        else
            table.insert(fillable_parts, "\"" .. name .. "\"")
        end
    end

    table.insert(content, "local " .. camelModelName .. " = require(\"rio.database.model\"):extend({")
    table.insert(content, "    table_name = \"" .. pluralTableName .. "\",")
    table.insert(content, "    fillable = { " .. table.concat(fillable_parts, ", ") .. " }")
    table.insert(content, "})")
    table.insert(content, "" )

    table.insert(content, "-- Define validations, relationships, etc. here" )
    table.insert(content, "-- " .. camelModelName .. ".validates = {" )
    table.insert(content, "--     title = { presence = true }" )
    table.insert(content, "-- }" )
    
    local all_references = {}

    -- Auto-generate relations based on 'references' fields
    for _, name in ipairs(column_order) do
        local col = column_definitions[name]
        if col.type == "references" then
            table.insert(all_references, name)
            if col.options.polymorphic then
                table.insert(content, camelModelName .. ":belongs_to(\"" .. name .. "\", { polymorphic = true })")
            else
                table.insert(content, camelModelName .. ":belongs_to(\"" .. name .. "\")")
                
                -- INJECTION: Try to add association to the parent model automatically
                local parent_model_path = "app/models/" .. underscore(name) .. ".lua"
                local parent_file = io.open(parent_model_path, "r")
                if parent_file then
                    local parent_content = parent_file:read("*a")
                    parent_file:close()
                    
                    local rel_type = "has_many"
                    local target_name = pluralTableName
                    if col.options.has_one then
                        rel_type = "has_one"
                        target_name = underscore(model_name)
                    end

                    local inverse_rel = string.format("%s:%s(\"%s\")", camel_case(name), rel_type, target_name)
                    
                    -- Only inject if not already there
                    if not parent_content:find(target_name) then
                        local new_parent_content = parent_content:gsub("(.-)return%s+([%w_]+)%s*$", "%1" .. inverse_rel .. "\n\nreturn %2")
                        if new_parent_content ~= parent_content then
                            write_file_content(parent_model_path, new_parent_content)
                            print("Injected inverse relationship '" .. inverse_rel .. "' into " .. parent_model_path)
                        end
                    end
                end
            end
        end
    end

    -- N:M INJECTION: If this model has multiple references, it might be a join table
    if #all_references >= 2 then
        for i, ref_a in ipairs(all_references) do
            for j, ref_b in ipairs(all_references) do
                if i ~= j then
                    local parent_model_path = "app/models/" .. underscore(ref_a) .. ".lua"
                    local parent_file = io.open(parent_model_path, "r")
                    if parent_file then
                        local parent_content = parent_file:read("*a")
                        parent_file:close()
                        
                        local target_plural = pluralize(underscore(ref_b))
                        local through_name = pluralTableName
                        local through_rel = string.format("%s:has_many(\"%s\", { through = \"%s\" })", camel_case(ref_a), target_plural, through_name)
                        
                        if not parent_content:find("through = \"" .. through_name .. "\"") then
                            local new_parent_content = parent_content:gsub("(.-)return%s+([%w_]+)%s*$", "%1" .. through_rel .. "\n\nreturn %2")
                            if new_parent_content ~= parent_content then
                                write_file_content(parent_model_path, new_parent_content)
                                print("Injected N:M relationship '" .. through_rel .. "' into " .. parent_model_path)
                            end
                        end
                    end
                end
            end
        end
    end

    table.insert(content, "" )
    table.insert(content, "return " .. camelModelName)

    write_file_content(path, table.concat(content, "\n"))
    print("Model '" .. model_name .. "' generated successfully.")

    -- Generate test file for the model
    local test_path = "test/models/" .. underscore(model_name) .. "_test.lua"
    print("Generating model test: " .. test_path)
    local test_content = {}
    table.insert(test_content, "local " .. camelModelName .. " = require(\"app.models." .. underscore(model_name) .. "\")")

    table.insert(test_content, "")
    table.insert(test_content, "describe(\"" .. camelModelName .. " Model\", function()")
    table.insert(test_content, "    it(\"should exist\", function()")
    table.insert(test_content, "        assert.is_table(" .. camelModelName .. ")")
    table.insert(test_content, "    end)")
    table.insert(test_content, "end)")

    write_file_content(test_path, table.concat(test_content, "\n"))
    print("Model test '" .. model_name .. "_test' generated successfully.")
    
    -- Also generate a migration for creating the table
    local migration_full_name = "Create" .. camel_case(pluralize(model_name))
    generate_migration(migration_full_name, fields, underscore(model_name)) -- Pass singular underscored model name for correct pluralization
end

local function generate_scaffold_controller(resource_name, fields)
    local singular_name = underscore(resource_name)
    local plural_name = pluralize(singular_name)
    local controller_class_name = camel_case(plural_name) .. "Controller"
    local model_name = camel_case(singular_name)
    local path = "app/controllers/" .. plural_name .. "_controller.lua"
    
    print("Generating scaffold controller: " .. path)

    local content = {}
    table.insert(content, "local " .. model_name .. " = require(\"app.models." .. singular_name .. "\")")
    table.insert(content, "local " .. controller_class_name .. " = {}")
    table.insert(content, "")

    -- index
    table.insert(content, "function " .. controller_class_name .. ":index(ctx)")
    table.insert(content, "    local items = " .. model_name .. ":all()")
    table.insert(content, "    return ctx:view(\"" .. plural_name .. "/index\", { " .. plural_name .. " = items })")
    table.insert(content, "end")
    table.insert(content, "")

    -- show
    table.insert(content, "function " .. controller_class_name .. ":show(ctx)")
    table.insert(content, "    local item = " .. model_name .. ":find(ctx.params.id)")
    table.insert(content, "    if not item then return ctx:text(\"Not Found\", 404) end")
    table.insert(content, "    return ctx:view(\"" .. plural_name .. "/show\", { " .. singular_name .. " = item })")
    table.insert(content, "end")
    table.insert(content, "")

    -- new
    table.insert(content, "function " .. controller_class_name .. ":new(ctx)")
    table.insert(content, "    return ctx:view(\"" .. plural_name .. "/new\", { " .. singular_name .. " = " .. model_name .. ":new() })")
    table.insert(content, "end")
    table.insert(content, "")

    -- edit
    table.insert(content, "function " .. controller_class_name .. ":edit(ctx)")
    table.insert(content, "    local item = " .. model_name .. ":find(ctx.params.id)")
    table.insert(content, "    if not item then return ctx:text(\"Not Found\", 404) end")
    table.insert(content, "    return ctx:view(\"" .. plural_name .. "/edit\", { " .. singular_name .. " = item })")
    table.insert(content, "end")
    table.insert(content, "")

    -- create
    table.insert(content, "function " .. controller_class_name .. ":create(ctx)")
    table.insert(content, "    local item = " .. model_name .. ":new(ctx.body)")
    table.insert(content, "    if item:save() then")
    table.insert(content, "        return ctx:redirect(\"/" .. plural_name .. "/\" .. item.id .. \"?notice=" .. camel_case(singular_name) .. " was successfully created.\")")
    table.insert(content, "    else")
    table.insert(content, "        return ctx:view(\"" .. plural_name .. "/new\", { " .. singular_name .. " = item, alert = \"Error creating " .. singular_name .. "\" })")
    table.insert(content, "    end")
    table.insert(content, "end")
    table.insert(content, "")

    -- update
    table.insert(content, "function " .. controller_class_name .. ":update(ctx)")
    table.insert(content, "    local item = " .. model_name .. ":find(ctx.params.id)")
    table.insert(content, "    if not item then return ctx:text(\"Not Found\", 404) end")
    table.insert(content, "    if item:update(ctx.body) then")
    table.insert(content, "        return ctx:redirect(\"/" .. plural_name .. "/\" .. item.id .. \"?notice=" .. camel_case(singular_name) .. " was successfully updated.\")")
    table.insert(content, "    else")
    table.insert(content, "        return ctx:view(\"" .. plural_name .. "/edit\", { " .. singular_name .. " = item, alert = \"Error updating " .. singular_name .. "\" })")
    table.insert(content, "    end")
    table.insert(content, "end")
    table.insert(content, "")

    -- destroy
    table.insert(content, "function " .. controller_class_name .. ":destroy(ctx)")
    table.insert(content, "    local item = " .. model_name .. ":find(ctx.params.id)")
    table.insert(content, "    if item then ")
    table.insert(content, "        item:delete()")
    table.insert(content, "        return ctx:redirect(\"/" .. plural_name .. "?notice=" .. camel_case(singular_name) .. " was successfully destroyed.\")")
    table.insert(content, "    end")
    table.insert(content, "    return ctx:redirect(\"/" .. plural_name .. "\")")
    table.insert(content, "end")
    table.insert(content, "")

    table.insert(content, "return " .. controller_class_name)

    write_file_content(path, table.concat(content, "\n"))
end

local function generate_api_scaffold_controller(resource_name, fields)
    local singular_name = underscore(resource_name)
    local plural_name = pluralize(singular_name)
    local controller_class_name = camel_case(plural_name) .. "Controller"
    local model_name = camel_case(singular_name)
    local path = "app/controllers/" .. plural_name .. "_controller.lua"
    
    print("Generating API scaffold controller: " .. path)

    local content = {}
    table.insert(content, "local " .. model_name .. " = require(\"app.models." .. singular_name .. "\")")
    table.insert(content, "local " .. controller_class_name .. " = {}")
    table.insert(content, "")

    -- index
    table.insert(content, "function " .. controller_class_name .. ":index(ctx)")
    table.insert(content, "    local items = " .. model_name .. ":all()")
    table.insert(content, "    return ctx:json(items)")
    table.insert(content, "end")
    table.insert(content, "")

    -- show
    table.insert(content, "function " .. controller_class_name .. ":show(ctx)")
    table.insert(content, "    local item = " .. model_name .. ":find(ctx.params.id)")
    table.insert(content, "    if not item then return ctx:json({ error = \"Not Found\" }, 404) end")
    table.insert(content, "    return ctx:json(item)")
    table.insert(content, "end")
    table.insert(content, "")

    -- create
    table.insert(content, "function " .. controller_class_name .. ":create(ctx)")
    table.insert(content, "    local item = " .. model_name .. ":new(ctx.body)")
    table.insert(content, "    if item:save() then")
    table.insert(content, "        return ctx:json(item, 201)")
    table.insert(content, "    else")
    table.insert(content, "        return ctx:json({ errors = item.errors:all() }, 422)")
    table.insert(content, "    end")
    table.insert(content, "end")
    table.insert(content, "")

    -- update
    table.insert(content, "function " .. controller_class_name .. ":update(ctx)")
    table.insert(content, "    local item = " .. model_name .. ":find(ctx.params.id)")
    table.insert(content, "    if not item then return ctx:json({ error = \"Not Found\" }, 404) end")
    table.insert(content, "    if item:update(ctx.body) then")
    table.insert(content, "        return ctx:json(item)")
    table.insert(content, "    else")
    table.insert(content, "        return ctx:json({ errors = item.errors:all() }, 422)")
    table.insert(content, "    end")
    table.insert(content, "end")
    table.insert(content, "")

    -- destroy
    table.insert(content, "function " .. controller_class_name .. ":destroy(ctx)")
    table.insert(content, "    local item = " .. model_name .. ":find(ctx.params.id)")
    table.insert(content, "    if item then ")
    table.insert(content, "        item:delete()")
    table.insert(content, "        return ctx:json({ message = \"" .. model_name .. " was successfully destroyed.\" })")
    table.insert(content, "    end")
    table.insert(content, "    return ctx:json({ error = \"Not Found\" }, 404)")
    table.insert(content, "end")
    table.insert(content, "")

    table.insert(content, "return " .. controller_class_name)

    write_file_content(path, table.concat(content, "\n"))
end

local function generate_scaffold_views(resource_name, fields)
    local singular_name = underscore(resource_name)
    local plural_name = pluralize(singular_name)
    local views_dir = "app/views/" .. plural_name
    create_dir_if_not_exists(views_dir)

    local flash_block = [[
<% if notice then %><div style="color: #155724; background-color: #d4edda; border: 1px solid #c3e6cb; padding: 12px; border-radius: 4px; margin-bottom: 20px;"><%= notice %></div><% end %>
<% if alert then %><div style="color: #721c24; background-color: #f8d7da; border: 1px solid #f5c6cb; padding: 12px; border-radius: 4px; margin-bottom: 20px;"><%= alert %></div><% end %>
]]

    -- index.etl
    local index_content = {
        flash_block,
        "<h1>" .. camel_case(plural_name) .. "</h1>",
        "<table style=\"width: 100%; border-collapse: collapse; margin-bottom: 20px;\">",
        "  <thead>",
        "    <tr style=\"background-color: #f8f9fa; border-bottom: 2px solid #dee2e6;\">"
    }
    local column_order, column_definitions = parse_fields(fields)

    for _, name in ipairs(column_order) do
        table.insert(index_content, "      <th style=\"padding: 12px; text-align: left;\">" .. camel_case(name) .. "</th>")
    end
    table.insert(index_content, "      <th colspan=\"3\" style=\"padding: 12px;\"></th>")
    table.insert(index_content, "    </tr>")
    table.insert(index_content, "  </thead>")
    table.insert(index_content, "  <tbody>")
    table.insert(index_content, "    <% for _, item in ipairs(" .. plural_name .. ") do %>")
    table.insert(index_content, "    <tr style=\"border-bottom: 1px solid #dee2e6;\">")
    for _, name in ipairs(column_order) do
        table.insert(index_content, "      <td style=\"padding: 12px;\"><%= item." .. name .. " %></td>")
    end
    table.insert(index_content, "      <td style=\"padding: 12px;\"><a href=\"/" .. plural_name .. "/<%= item.id %>\">Show</a></td>")
    table.insert(index_content, "      <td style=\"padding: 12px;\"><a href=\"/" .. plural_name .. "/<%= item.id %>/edit\">Edit</a></td>")
    table.insert(index_content, "      <td style=\"padding: 12px;\"><form action=\"/" .. plural_name .. "/<%= item.id %>\" method=\"POST\" style=\"display:inline\"><input type=\"hidden\" name=\"_method\" value=\"DELETE\"><button type=\"submit\" style=\"background: none; border: none; color: #dc3545; cursor: pointer; text-decoration: underline; padding: 0;\" onclick=\"return confirm('Are you sure?')\">Destroy</button></form></td>")
    table.insert(index_content, "    </tr>")
    table.insert(index_content, "    <% end %>")
    table.insert(index_content, "  </tbody>")
    table.insert(index_content, "</table>")
    table.insert(index_content, "<br>")
    table.insert(index_content, "<a href=\"/" .. plural_name .. "/new\" style=\"display: inline-block; background-color: #007bff; color: white; padding: 8px 16px; border-radius: 4px; text-decoration: none;\">New " .. camel_case(singular_name) .. "</a>")
    write_file_content(views_dir .. "/index.etl", table.concat(index_content, "\n"))

    -- show.etl
    local show_content = {
        flash_block,
        "<h1>" .. camel_case(singular_name) .. "</h1>"
    }
    for _, name in ipairs(column_order) do
        table.insert(show_content, "<p style=\"font-size: 1.1em; margin-bottom: 10px;\"><strong style=\"color: #495057;\">" .. camel_case(name) .. ":</strong> <%= " .. singular_name .. "." .. name .. " %></p>")
    end
    table.insert(show_content, "<div style=\"margin-top: 20px;\">")
    table.insert(show_content, "  <a href=\"/" .. plural_name .. "/<%= " .. singular_name .. ".id %>/edit\">Edit</a> |")
    table.insert(show_content, "  <a href=\"/" .. plural_name .. "\">Back to " .. plural_name .. "</a>")
    table.insert(show_content, "</div>")
    write_file_content(views_dir .. "/show.etl", table.concat(show_content, "\n"))

    -- new.etl
    local new_content = {
        flash_block,
        "<h1>New " .. camel_case(singular_name) .. "</h1>",
        "",
        "<% if " .. singular_name .. ".errors:any() then %>",
        "  <div id=\"error_explanation\" style=\"color: #721c24; background-color: #f8d7da; border: 1px solid #f5c6cb; padding: 12px; border-radius: 4px; margin-bottom: 20px;\">",
        "    <h2 style=\"margin-top: 0; font-size: 1.25em;\"><%= " .. singular_name .. ".errors:size() %> error(s) prohibited this " .. singular_name .. " from being saved:</h2>",
        "    <ul style=\"margin-bottom: 0;\">",
        "      <% for _, msg in ipairs(" .. singular_name .. ".errors:full_messages()) do %>",
        "        <li><%= msg %></li>",
        "      <% end %>",
        "    </ul>",
        "  </div>",
        "<% end %>",
        "",
        "<form action=\"/" .. plural_name .. "\" method=\"POST\" style=\"background-color: #f8f9fa; padding: 20px; border-radius: 8px; border: 1px solid #dee2e6;\">"
    }
    
    for _, name in ipairs(column_order) do
        local col = column_definitions[name]
        local type = col.type
        table.insert(new_content, "  <div style=\"margin-bottom: 15px;\">")
        table.insert(new_content, "    <label style=\"display: block; font-weight: bold; margin-bottom: 5px;\">" .. camel_case(name) .. "</label>")
        
        if type == "text" then
            table.insert(new_content, "    <textarea name=\"" .. name .. "\" style=\"width: 100%; max-width: 500px; height: 120px; padding: 8px; border: 1px solid #ced4da; border-radius: 4px;\"><%= " .. singular_name .. "." .. name .. " or '' %></textarea>")
        elseif type == "boolean" then
            table.insert(new_content, "    <input type=\"checkbox\" name=\"" .. name .. "\" value=\"1\" <%= " .. singular_name .. "." .. name .. " and 'checked' or '' %> style=\"width: 20px; height: 20px;\">")
        elseif type == "integer" or type == "float" or type == "decimal" then
            table.insert(new_content, "    <input type=\"number\" name=\"" .. name .. "\" step=\"" .. (type == "integer" and "1" or "any") .. "\" value=\"<%= " .. singular_name .. "." .. name .. " or '' %>\" style=\"width: 100%; max-width: 500px; padding: 8px; border: 1px solid #ced4da; border-radius: 4px;\">")
        else
            table.insert(new_content, "    <input type=\"text\" name=\"" .. name .. "\" value=\"<%= " .. singular_name .. "." .. name .. " or '' %>\" style=\"width: 100%; max-width: 500px; padding: 8px; border: 1px solid #ced4da; border-radius: 4px;\">")
        end
        table.insert(new_content, "  </div>")
    end
    table.insert(new_content, "  <button type=\"submit\" style=\"background-color: #28a745; color: white; border: none; padding: 10px 20px; border-radius: 4px; font-size: 1em; cursor: pointer;\">Create " .. camel_case(singular_name) .. "</button>")
    table.insert(new_content, "</form>")
    table.insert(new_content, "<br><a href=\"/" .. plural_name .. "\">Back to " .. plural_name .. "</a>")
    write_file_content(views_dir .. "/new.etl", table.concat(new_content, "\n"))

    -- edit.etl
    local edit_content = {
        flash_block,
        "<h1>Editing " .. camel_case(singular_name) .. "</h1>",
        "",
        "<% if " .. singular_name .. ".errors:any() then %>",
        "  <div id=\"error_explanation\" style=\"color: #721c24; background-color: #f8d7da; border: 1px solid #f5c6cb; padding: 12px; border-radius: 4px; margin-bottom: 20px;\">",
        "    <h2 style=\"margin-top: 0; font-size: 1.25em;\"><%= " .. singular_name .. ".errors:size() %> error(s) prohibited this " .. singular_name .. " from being saved:</h2>",
        "    <ul style=\"margin-bottom: 0;\">",
        "      <% for _, msg in ipairs(" .. singular_name .. ".errors:full_messages()) do %>",
        "        <li><%= msg %></li>",
        "      <% end %>",
        "    </ul>",
        "  </div>",
        "<% end %>",
        "",
        "<form action=\"/" .. plural_name .. "/<%= " .. singular_name .. ".id %>\" method=\"POST\" style=\"background-color: #f8f9fa; padding: 20px; border-radius: 8px; border: 1px solid #dee2e6;\">",
        "  <input type=\"hidden\" name=\"_method\" value=\"PUT\">"
    }
    
    for _, name in ipairs(column_order) do
        local col = column_definitions[name]
        local type = col.type
        table.insert(edit_content, "  <div style=\"margin-bottom: 15px;\">")
        table.insert(edit_content, "    <label style=\"display: block; font-weight: bold; margin-bottom: 5px;\">" .. camel_case(name) .. "</label>")
        
        if type == "text" then
            table.insert(edit_content, "    <textarea name=\"" .. name .. "\" style=\"width: 100%; max-width: 500px; height: 120px; padding: 8px; border: 1px solid #ced4da; border-radius: 4px;\"><%= " .. singular_name .. "." .. name .. " or '' %></textarea>")
        elseif type == "boolean" then
            table.insert(edit_content, "    <input type=\"checkbox\" name=\"" .. name .. "\" value=\"1\" <%= " .. singular_name .. "." .. name .. " and 'checked' or '' %> style=\"width: 20px; height: 20px;\">")
        elseif type == "integer" or type == "float" or type == "decimal" then
            table.insert(edit_content, "    <input type=\"number\" name=\"" .. name .. "\" step=\"" .. (type == "integer" and "1" or "any") .. "\" value=\"<%= " .. singular_name .. "." .. name .. " or '' %>\" style=\"width: 100%; max-width: 500px; padding: 8px; border: 1px solid #ced4da; border-radius: 4px;\">")
        else
            table.insert(edit_content, "    <input type=\"text\" name=\"" .. name .. "\" value=\"<%= " .. singular_name .. "." .. name .. " or '' %>\" style=\"width: 100%; max-width: 500px; padding: 8px; border: 1px solid #ced4da; border-radius: 4px;\">")
        end
        table.insert(edit_content, "  </div>")
    end
    table.insert(edit_content, "  <button type=\"submit\" style=\"background-color: #28a745; color: white; border: none; padding: 10px 20px; border-radius: 4px; font-size: 1em; cursor: pointer;\">Update " .. camel_case(singular_name) .. "</button>")
    table.insert(edit_content, "</form>")
    table.insert(edit_content, "<br><div style=\"margin-top: 10px;\"><a href=\"/" .. plural_name .. "/<%= " .. singular_name .. ".id %>\">Show</a> | " ..
    "<a href=\"/" .. plural_name .. "\">Back to " .. plural_name .. "</a></div>")
    write_file_content(views_dir .. "/edit.etl", table.concat(edit_content, "\n"))

    print("Scaffold views for '" .. plural_name .. "' generated successfully.")
end

local function generate_scaffold_tests(resource_name, fields, api_only)
    local singular_name = underscore(resource_name)
    local plural_name = pluralize(singular_name)
    local controller_class_name = camel_case(plural_name) .. "Controller"
    local model_name = camel_case(singular_name)
    local path = "test/controllers/" .. plural_name .. "_test.lua"
    
    print("Generating scaffold tests: " .. path .. (api_only and " (API-only)" or ""))

    local test_data = {}
    for _, field in ipairs(fields) do
        local name, type = field:match("([^:]+):(.+)")
        if not name then name = field; type = "string" end
        if type == "string" or type == "text" then
            if name:find("email") then test_data[name] = "test@example.com"
            elseif name:find("password") then test_data[name] = "password123"
            elseif name:find("url") or name:find("website") then test_data[name] = "https://example.com"
            elseif name:find("tel") or name:find("phone") then test_data[name] = "123456789"
            elseif name:find("color") then test_data[name] = "#FF0000"
            else test_data[name] = "Test " .. name
            end
        elseif type == "date" then
            test_data[name] = "2026-01-01"
        elseif type == "datetime" then
            test_data[name] = "2026-01-01T12:00:00"
        elseif type == "time" then
            test_data[name] = "12:00:00"
        elseif type == "integer" or type == "float" or type == "decimal" or type == "references" then
            test_data[name] = 1
        elseif type == "boolean" then
            test_data[name] = true
        else
            test_data[name] = "Test Value"
        end
    end

    local function table_to_lua(t)
        local parts = {}
        for k, v in pairs(t) do
            local val = v
            if type(v) == "string" then val = "\"" .. v .. "\"" end
            table.insert(parts, k .. " = " .. tostring(val))
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end

    local data_str = table_to_lua(test_data)
    local lines = {}
    local function add(line) table.insert(lines, line) end

    add("local " .. model_name .. " = require(\"app.models." .. singular_name .. "\")")
    add("local " .. controller_class_name .. " = require(\"app.controllers." .. plural_name .. "_controller\")")
    add("")
    add("describe(\"" .. controller_class_name .. "\", function()")
    add("    -- Mock context helper")
    add("    local function mock_ctx(params, body)")
    add("        return {")
    add("            params = params or {},")
    add("            body = body or {},")
    add("            view = function(self, path, data) return { type = \"view\", path = path, data = data } end,")
    add("            json = function(self, data, status) return { type = \"json\", data = data, status = status or 200 } end,")
    add("            redirect = function(self, url) return { type = \"redirect\", url = url } end,")
    add("            text = function(self, status, msg) return { type = \"text\", status = status, msg = msg } end")
    add("        }")
    add("    end")
    add("")
    add("    before_each(function()")
    add("        -- Clean database before each test")
    add("        " .. model_name .. ":raw(\"DELETE FROM \" .. " .. model_name .. ".table_name)")
    add("    end)")
    add("")
    add("    it(\"should list " .. plural_name .. "\", function()")
    add("        " .. model_name .. ":create(" .. data_str .. ")")
    add("        local ctx = mock_ctx()")
    add("        local res = " .. controller_class_name .. ":index(ctx)")
    if api_only then
        add("        assert.equals(\"json\", res.type)")
        add("        assert.is_table(res.data)")
        add("        assert.equals(1, #res.data)")
    else
        add("        assert.equals(\"view\", res.type)")
        add("        assert.equals(\"" .. plural_name .. "/index\", res.path)")
        add("        assert.is_table(res.data." .. plural_name .. ")")
        add("        assert.equals(1, #res.data." .. plural_name .. ")")
    end
    add("    end)")
    add("")
    add("    it(\"should show a " .. singular_name .. "\", function()")
    add("        local item = " .. model_name .. ":create(" .. data_str .. ")")
    add("        local ctx = mock_ctx({ id = item.id })")
    add("        local res = " .. controller_class_name .. ":show(ctx)")
    if api_only then
        add("        assert.equals(\"json\", res.type)")
        add("        assert.equals(tonumber(item.id), tonumber(res.data.id))")
    else
        add("        assert.equals(\"view\", res.type)")
        add("        assert.equals(\"" .. plural_name .. "/show\", res.path)")
        add("        assert.equals(tonumber(item.id), tonumber(res.data." .. singular_name .. ".id))")
    end
    add("    end)")
    add("")
    add("    it(\"should create a " .. singular_name .. "\", function()")
    add("        local ctx = mock_ctx({}, " .. data_str .. ")")
    add("        local res = " .. controller_class_name .. ":create(ctx)")
    if api_only then
        add("        assert.equals(\"json\", res.type)")
        add("        assert.equals(201, res.status)")
    else
        add("        assert.equals(\"redirect\", res.type)")
    end
    add("        ")
    add("        local item = " .. model_name .. ":first()")
    add("        assert.is_not_nil(item)")
    add("    end)")
    add("")
    add("    it(\"should update a " .. singular_name .. "\", function()")
    add("        local item = " .. model_name .. ":create(" .. data_str .. ")")
    add("        local ctx = mock_ctx({ id = item.id }, " .. data_str .. ")")
    add("        local res = " .. controller_class_name .. ":update(ctx)")
    if api_only then
        add("        assert.equals(\"json\", res.type)")
    else
        add("        assert.equals(\"redirect\", res.type)")
    end
    add("    end)")
    add("")
    add("    it(\"should destroy a " .. singular_name .. "\", function()")
    add("        local item = " .. model_name .. ":create(" .. data_str .. ")")
    add("        local ctx = mock_ctx({ id = item.id })")
    add("        local res = " .. controller_class_name .. ":destroy(ctx)")
    if api_only then
        add("        assert.equals(\"json\", res.type)")
    else
        add("        assert.equals(\"redirect\", res.type)")
    end
    add("        ")
    add("        assert.is_nil(" .. model_name .. ":find(item.id))")
    add("    end)")
    add("end)")
    add("")

    write_file_content(path, table.concat(lines, "\n"))
end


local function generate_scaffold(resource_name, fields, api_only)
    print("Generating scaffold: " .. resource_name .. (api_only and " (API-only)" or ""))
    
    -- 1. Generate Model, Migration and Model Test
    generate_model(resource_name, fields)
    
    -- 2. Generate CRUD Controller
    if api_only then
        generate_api_scaffold_controller(resource_name, fields)
    else
        generate_scaffold_controller(resource_name, fields)
        
        -- 3. Generate Views (Only for non-API projects)
        generate_scaffold_views(resource_name, fields)
    end

    -- 4. Generate Robust Controller Tests
    generate_scaffold_tests(resource_name, fields, api_only)
    
    -- 5. Update Routes
    local plural_name = pluralize(underscore(resource_name))
    local routes_path = "config/routes.lua"
    local f = io.open(routes_path, "r")
    if f then
        local content = f:read("*a")
        f:close()
        if not content:find("app:resources(\"" .. plural_name .. "\")") then
            local modified_content = content:gsub("(.-)end%s*$", "%1    app:resources(\"" .. plural_name .. "\")\nend")
            write_file_content(routes_path, modified_content)
            print("Resource routes added to config/routes.lua.")
        end
    end
end

local function generate_resource(resource_name, fields, api_only)
    local singular_name = underscore(resource_name)
    local plural_name = pluralize(singular_name)

    print("Generating resource: " .. resource_name .. (api_only and " (API-only)" or ""))

    -- 1. Generate Model (this also generates migration and model test)
    generate_model(resource_name, fields)

    -- 2. Generate Controller (pluralized name)
    generate_controller(plural_name, {}, api_only) -- empty actions

    -- 3. Add routes to config/routes.lua
    print("Updating config/routes.lua with resource routes...")
    local routes_path = "config/routes.lua"
    local f = io.open(routes_path, "r")
    if f then
        local content = f:read("*a")
        f:close()

        -- Check if resource already exists in routes
        if content:find("app:resources(\"" .. plural_name .. "\")") then
            print("Notice: Resource routes for '" .. plural_name .. "' already exist in config/routes.lua. Skipping.")
        else
            -- Insert before the last 'end' of the return function(app)
            -- This is a bit naive but works for standard generated routes.lua
            local modified_content = content:gsub("(.-)end%s*$", "%1    app:resources(\"" .. plural_name .. "\")\nend")
            
            if modified_content ~= content then
                write_file_content(routes_path, modified_content)
                print("Resource routes added to config/routes.lua.")
            else
                print("Warning: Could not automatically update config/routes.lua. Please add 'app:resources(\"" .. plural_name .. "\")' manually.")
            end
        end
    else
        print("Error: Could not find config/routes.lua.")
    end
end


local function is_api_only()
    local ok, app_config = pcall(require, "config.application")
    if ok and type(app_config) == "table" then
        return app_config.api_only == true
    end
    return false
end

local function run_server(server_options)
    local initial_port = tonumber(server_options.port) or 8080
    local host = server_options.binding or "0.0.0.0"
    local environment = server_options.environment or "development"
    local current_port = initial_port
    
    local effective_lua_path, effective_lua_cpath = get_lua_paths()

    local lua_bin = compat.get_lua_bin()
    -- Store command template
    local server_command_template = "LUA_PATH='%s' " ..
                                    "LUA_CPATH='%s' " ..
                                    "RIO_ENV='%s' " ..
                                    "RIO_BINDING='%s' " ..
                                    "RIO_PORT='%s' " ..
                                    lua_bin .. " app.lua"

    while true do
        if server_options.daemon then
            print(colors.cyan .. "Starting Rio server in background on port " .. current_port .. "..." .. colors.reset)
            local log_dir = "log"
            create_dir_if_not_exists(log_dir)
            local command_to_execute = string.format(server_command_template, effective_lua_path, effective_lua_cpath, environment, host, current_port)
            command_to_execute = command_to_execute .. " > " .. log_dir .. "/rio_server.log 2>&1 & echo $!"
            
            local handle = io.popen(command_to_execute)
            local pid = handle:read("*a"):gsub("%s+", "")
            handle:close()

            if pid and pid ~= "" then
                -- Store PID in file if requested
                if server_options.pid then
                    local pid_dir = server_options.pid:match("(.+)/[^/]+$")
                    if pid_dir then create_dir_if_not_exists(pid_dir) end
                    local f = io.open(server_options.pid, "w")
                    if f then
                        f:write(pid)
                        f:close()
                    end
                end

                os.execute("sleep 1")

                -- Check if it actually started
                if not is_port_free(current_port, host) then
                    print(colors.green .. "Server started in background on port " .. current_port .. " (PID: " .. pid .. ")" .. colors.reset)
                    return
                else
                    print(colors.red .. "Error: Server failed to start on port " .. current_port .. colors.reset)
                    return
                end
            else
                print(colors.red .. "Error: Failed to capture PID" .. colors.reset)
                return
            end
        else
            -- Foreground mode
            -- Check if port is busy before starting
            if not is_port_free(current_port, host) then
                print("\n" .. colors.yellow .. "⚠️  Port " .. current_port .. " is already in use by another process on " .. host .. "." .. colors.reset)
                
                -- Generate a random port between 8000 and 9999
                math.randomseed(os.time())
                local next_port = math.random(8000, 9999)
                
                io.write(colors.bold .. "Would you like to start another instance on a random port (" .. next_port .. ")? (y/N): " .. colors.reset)
                local answer = io.read()
                
                if answer and (answer:lower() == "y" or answer:lower() == "yes") then
                    current_port = next_port
                    -- loop continues to re-check the new random port
                else
                    print("Exiting...")
                    return
                end
            else
                local full_command_line = string.format(server_command_template, effective_lua_path, effective_lua_cpath, environment, host, current_port)
                print(colors.cyan .. string.format("Attempting to start server on http://%s:%d...", host, current_port) .. colors.reset)
                
                -- Execute normally in foreground (all output goes to terminal)
                os.execute(full_command_line)
                return
            end
        end
    end
end

local function run_console(console_options)
    -- Verify if we are inside an Rio project
    local ok_project = io.open("config/application.lua", "r")
    if ok_project then
        ok_project:close()
    else
        print(colors.red .. "Error: Not an Rio project. 'rio console' must be run from the project root." .. colors.reset)
        return
    end

    local env = console_options.environment or os.getenv("RIO_ENV") or "development"
    local sandbox = console_options.sandbox or false
    
    print(string.format("Loading %s environment%s...", env, sandbox and " in sandbox" or ""))
    if sandbox then
        print("Any modifications you make will be rolled back on exit")
    end

    local effective_lua_path, effective_lua_cpath = get_lua_paths()
    
    -- Gather models
    local models = {}
    local handle = io.popen("ls app/models/*.lua 2>/dev/null")
    if handle then
        for line in handle:lines() do
            local m = line:match("([^/]+)%.lua$")
            if m then table.insert(models, m) end
        end
        handle:close()
    end

    local temp_bootstrap_file = "rio_console_bootstrap.lua"
    local bootstrap_content = {
        "-- Console bootstrap script",
        "package.path = './app/?.lua;./app/?/init.lua;./config/?.lua;./lib/?.lua;' .. '" .. rio_framework_lib_path_global .. ";' .. package.path",
        "local rio = require('rio')",
        "local db_manager = require('rio.database.manager')",
        "local ok_db_config, db_config = pcall(require, 'config.database')",
        "",
        "-- Initialize Database",
        "local env = '" .. env .. "'",
        "if ok_db_config and db_config[env] then db_manager.initialize(db_config[env]) end",
        "",
        "-- Load Models into global scope",
    }
    
    for _, model in ipairs(models) do
        local class_name = camel_case(model)
        table.insert(bootstrap_content, string.format("pcall(function() %s = require('app.models.%s') end)", class_name, model))
    end
    
    if sandbox then
        table.insert(bootstrap_content, "if ok_db_config then db_manager.begin() end")
    end

    -- Add app and helper objects
    table.insert(bootstrap_content, [[
-- App object for route testing
local ok_app_config, app_config = pcall(require, "config.application")
if not ok_app_config or type(app_config) ~= "table" then
    app_config = { server = { port = 8080, host = "0.0.0.0" } }
end
app = rio.new(app_config)
local ok_routes, routes_fn = pcall(require, "config.routes")
if ok_routes then routes_fn(app) end

-- Helper object
helper = {}
function helper.link_to(text, url) return string.format('<a href="%s">%s</a>', url, text) end

-- Pretty print helper
function pp(val)
    local string_utils = require("rio.utils.string")
    local mt = getmetatable(val)
    if mt and mt.__tostring then
        print(tostring(val))
    else
        print(string_utils.inspect(val))
    end
end

-- Function wrapper to allow calling without parentheses
local function make_callable_without_parens(fn, name)
    return setmetatable({}, {
        __call = function(_, ...) return fn(...) end,
        __tostring = function() 
            local ok, res = pcall(fn)
            return "" -- Return empty string since the function handles its own printing
        end
    })
end

-- Reload helper
local function _reload()
    print("Reloading project modules...")
    for k, _ in pairs(package.loaded) do
        if k:match("^app%.") or k:match("^config%.") then
            package.loaded[k] = nil
        end
    end
    -- Re-require models
    local handle = io.popen("ls app/models/*.lua 2>/dev/null")
    if handle then
        for line in handle:lines() do
            local m = line:match("([^/]+)%.lua$")
            if m then
                local string_utils = require("rio.utils.string")
                local class_name = string_utils.camel_case(m)
                _G[class_name] = require("app.models." .. m)
            end
        end
        handle:close()
    end
    print("Done.")
end
reload = make_callable_without_parens(_reload, "reload")

-- Test helper
local function _test(args)
    local cmd = "']] .. rio_bin_path_global .. [[' test " .. (args or "")
    os.execute(cmd)
end
test = make_callable_without_parens(_test, "test")

-- DB helper: Quick access to database commands
db = {
    create = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:create") end),
    drop = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:drop") end),
    migrate = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:migrate") end),
    rollback = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:rollback") end),
    status = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:status") end),
    version = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:version") end),
    seed = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:seed") end),
    setup = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:setup") end),
    reset = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:reset") end),
    prepare = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:prepare") end)
}

-- Mailbox helper
mailbox = {
    install = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' mailbox:install") end),
    exim = make_callable_without_parens(function() print("Ingress requires stdin. Use: cat mail.eml | rio mailbox:ingress:exim") end),
    postfix = make_callable_without_parens(function() print("Ingress requires stdin. Use: cat mail.eml | rio mailbox:ingress:postfix") end),
    qmail = make_callable_without_parens(function() print("Ingress requires stdin. Use: cat mail.eml | rio mailbox:ingress:qmail") end)
}

-- General commands
server = make_callable_without_parens(function(args) 
    local cmd = "']] .. rio_bin_path_global .. [[' server " .. (args or "")
    if args and (args:find("-d") or args:find("--daemon")) then
        cmd = cmd .. " &"
    end
    os.execute(cmd) 
end)
routes = make_callable_without_parens(function(args) os.execute("']] .. rio_bin_path_global .. [[' routes " .. (args or "")) end)
middleware = make_callable_without_parens(function(args) os.execute("']] .. rio_bin_path_global .. [[' middleware " .. (args or "")) end)
about = make_callable_without_parens(function(args) os.execute("']] .. rio_bin_path_global .. [[' about " .. (args or "")) end)
initializers = make_callable_without_parens(function(args) os.execute("']] .. rio_bin_path_global .. [[' initializers " .. (args or "")) end)
help = make_callable_without_parens(function(cmd) os.execute("']] .. rio_bin_path_global .. [[' help " .. (cmd or "")) end)

local function _list_history()
    for i, cmd in ipairs(_G._history or {}) do
        print(string.format("%d  %s", i, cmd))
    end
end

history = setmetatable({
    clear = make_callable_without_parens(function()
        _G._history = {}
        print("Console history cleared.")
    end)
}, {
    __call = function()
        _list_history()
    end,
    __tostring = function()
        _list_history()
        return ""
    end
})
clear = make_callable_without_parens(function() os.execute("clear") end)

-- Generators
generate = function(type, name, ...)
    local extra = table.concat({...}, " ")
    os.execute(string.format("']] .. rio_bin_path_global .. [[' generate %s %s %s", type or "", name or "", extra))
end
g = generate

destroy = function(type, name)
    os.execute(string.format("']] .. rio_bin_path_global .. [[' destroy %s %s", type or "", name or ""))
end
]])

    table.insert(bootstrap_content, [[
-- Custom REPL logic to support automatic pretty-printing
local function start_repl()
    local string_utils = require("rio.utils.string")
    local linenoise_ok, linenoise = pcall(require, "linenoise")
    local env_name = ']] .. env .. [['
    
    -- Prompt colors based on environment
    local env_colors = {
        development = "\27[32m", -- Green
        test = "\27[34m",        -- Blue
        production = "\27[31m"   -- Red
    }
    local color = env_colors[env_name] or "\27[33m" -- Yellow as fallback
    local reset = "\27[0m"
    local prompt = string.format("%s%s> %s", color, env_name, reset)
    
    _G._history = {}
    
    if linenoise_ok then
        -- Standard Tab completion (Compatible with 0.9+)
        linenoise.setcompletion(function(c, s)
            local completions = {}
            local seen = {}
            
            -- Identify the part of the line being completed
            local prefix = s:match("[%w_%.%:]*$") or ""
            local context = s:sub(1, #s - #prefix)
            
            if #prefix > 0 then
                -- 1. Complete Global keys
                if not prefix:find("[%.:]") then
                    for k, v in pairs(_G) do
                        if type(k) == "string" and k:sub(1, 1) ~= "_" then
                            if k:sub(1, #prefix) == prefix then
                                local full = context .. k
                                if not seen[full] then table.insert(completions, full) seen[full] = true end
                            end
                        end
                    end
                else
                    -- 2. Complete Table members (e.g. User. or app:)
                    local t_name, sep, m_prefix = prefix:match("^([%w_]+)([%.:])([%w_]*)$")
                    if t_name and _G[t_name] and type(_G[t_name]) == "table" then
                        for k, v in pairs(_G[t_name]) do
                            if type(k) == "string" and k:sub(1, #m_prefix) == m_prefix then
                                local full = context .. t_name .. sep .. k
                                if not seen[full] then table.insert(completions, full) seen[full] = true end
                            end
                        end
                    end
                end
            end
            
            table.sort(completions)
            for _, cmd in ipairs(completions) do
                -- Use completion:add syntax as in the example
                if c.add then c:add(cmd) else linenoise.addcompletion(c, cmd) end
            end
        end)

        if linenoise.enableutf8 then linenoise.enableutf8(1) end
    end
    
    print(string.format("Rio console (%s) ready. Type 'exit' or Ctrl+D to quit.", env_name))
    
    while true do
        local input, err
        if linenoise_ok then
            -- Use the standard function name from example
            input, err = linenoise.linenoise(prompt)
            
            if not input and err and err ~= "" then
                print("\27[31mError: " .. tostring(err) .. "\27[0m")
                input = "" -- Continue loop
            end
        else
            io.write(prompt)
            -- Catch Ctrl+C (interrupt) silently
            local ok_read, read_input = pcall(io.read)
            if not ok_read or not read_input then 
                if not ok_read then print("") end -- New line after ^C
                break 
            end
            input = read_input
        end
        
        if not input or input == "exit" or input == "os.exit()" then 
            break 
        end
        
        if input ~= "" then
            -- Record history in memory
            table.insert(_G._history, input)
            if linenoise_ok then
                linenoise.historyadd(input)
            end

            -- Try to load with 'return ' prefix first for expressions
            local expr_input = input
            
            -- Auto-fix common mistakes before loading
            -- 1. Handle space-separated commands (CLI style in REPL)
            local cli_style_cmds = { "help", "test", "generate", "g", "destroy", "server", "routes", "middleware", "about", "initializers" }
            for _, cmd in ipairs(cli_style_cmds) do
                -- Match command followed by space and anything else
                local pattern = "^(" .. cmd:gsub(":", "%%:") .. ")%s+(.+)$"
                local found_cmd, args = expr_input:match(pattern)
                if found_cmd then
                    -- Convert 'cmd args' to 'cmd("args")'
                    expr_input = string.format("%s(\"%s\")", found_cmd, args:gsub("\"", "\\\""))
                    break
                end
            end

            -- 2. Convert .method to :method for common terminal methods
            local terminal_methods = { "all", "get", "first", "last", "count", "sum", "avg", "min", "max", "exists", "save", "update", "delete", "validate" }
            for _, m in ipairs(terminal_methods) do
                if expr_input:match("%." .. m .. "$") or expr_input:match("%." .. m .. "%s*%(") then
                    expr_input = expr_input:gsub("%.(" .. m .. ")", ":%1")
                end
            end
            
            -- 2. General Model.method to Model:method
            if expr_input:match("^[A-Z][%w_]+%.[%w_]+") then
                expr_input = expr_input:gsub("^([A-Z][%w_]+)%.([%w_]+)", "%1:%2")
            end

            local chunk, err = load("return " .. expr_input)
            
            -- If it's a colon call without parens (e.g. User:all), auto-append ()
            if not chunk and expr_input:match(":[%w_]+$") then
                local retry_input = "return " .. expr_input .. "()"
                local retry_chunk = load(retry_input)
                if retry_chunk then
                    chunk = retry_chunk
                end
            end

            if not chunk then
                -- Fallback to original input for statements (like 'x = 1')
                chunk, err = load(input)
            end
            
            if chunk then
                local success, result = pcall(chunk)
                if success then
                    if result ~= nil then
                        pp(result)
                    end
                else
                    print("Error: " .. tostring(result))
                end
            else
                print("Error: " .. tostring(err))
            end
        end
    end
end

start_repl()
os.exit()
]])

    -- Set environment variables for the current process
    os.execute(string.format("export RIO_ENV='%s'", env))
    package.path = effective_lua_path
    package.cpath = effective_lua_cpath

    local code = table.concat(bootstrap_content, "\n")
    local chunk, err = load(code)
    
    if chunk then
        chunk()
    else
        print(colors.red .. "Error loading console environment: " .. tostring(err) .. colors.reset)
    end
end

local function run_runner(runner_options, code_or_file, script_args)
    -- Verify if we are inside an Rio project
    local ok_project = io.open("config/application.lua", "r")
    if ok_project then
        ok_project:close()
    else
        print(colors.red .. "Error: Not an Rio project. 'rio runner' must be run from the project root." .. colors.reset)
        return
    end

    if not code_or_file then
        print(colors.red .. "Error: No code or file provided to 'rio runner'." .. colors.reset)
        return
    end

    local env = runner_options.environment or os.getenv("RIO_ENV") or "development"
    local skip_executor = runner_options.skip_executor or false
    
    local effective_lua_path, effective_lua_cpath = get_lua_paths()
    
    -- Set environment variables for the current process
    _G.RIO_ENV = env
    package.path = effective_lua_path
    package.cpath = effective_lua_cpath

    if not skip_executor then
        -- Gather models
        local models = {}
        local handle = io.popen("ls app/models/*.lua 2>/dev/null")
        if handle then
            for line in handle:lines() do
                local m = line:match("([^/]+)%.lua$")
                if m then table.insert(models, m) end
            end
            handle:close()
        end

        local bootstrap_content = {
            "-- Runner bootstrap",
            "package.path = './app/?.lua;./app/?/init.lua;./config/?.lua;./lib/?.lua;' .. '" .. rio_framework_lib_path_global .. ";' .. package.path",
            "local rio = require('rio')",
            "local db_manager = require('rio.database.manager')",
            "local ok_db_config, db_config = pcall(require, 'config.database')",
            "",
            "-- Initialize Database",
            "local env = '" .. env .. "'",
            "_G.RIO_ENV = env",
            "if ok_db_config and db_config[env] then db_manager.initialize(db_config[env]) end",
            "",
            "-- Set global 'arg' table for the runner script",
            "arg = " .. (function()
                local parts = {}
                for i, a in ipairs(script_args or {}) do
                    table.insert(parts, "[" .. i .. "] = \"" .. a:gsub("\"", "\\\"") .. "\"")
                end
                return "{" .. table.concat(parts, ", ") .. "}"
            end)(),
            "",
            "-- Load Models into global scope",
        }
        
        for _, model in ipairs(models) do
            local string_utils = require("rio.utils.string")
            local class_name = string_utils.camel_case(model)
            table.insert(bootstrap_content, string.format("pcall(function() %s = require('app.models.%s') end)", class_name, model))
        end
        
        -- Add app and helper objects
        table.insert(bootstrap_content, [[
-- App object for route testing
local ok_app_config, app_config = pcall(require, "config.application")
if not ok_app_config or type(app_config) ~= "table" then
    app_config = { server = { port = 8080, host = "0.0.0.0" } }
end
app = rio.new(app_config)
local ok_routes, routes_fn = pcall(require, "config.routes")
if ok_routes then routes_fn(app) end

-- Pretty print helper
function pp(val)
    local string_utils = require("rio.utils.string")
    local mt = getmetatable(val)
    if mt and mt.__tostring then
        print(tostring(val))
    else
        print(string_utils.inspect(val))
    end
end
]])

        local bootstrap_code = table.concat(bootstrap_content, "\n")
        local chunk, err = load(bootstrap_code)
        
        if chunk then
            local status, result = pcall(chunk)
            if not status then
                print(colors.red .. "Error during application bootstrap: " .. tostring(result) .. colors.reset)
                return
            end
        else
            print(colors.red .. "Error loading application environment: " .. tostring(err) .. colors.reset)
            return
        end
    else
        -- Still set the arg table even if skipping executor
        _G.arg = script_args
    end

    -- Now execute the runner code
    -- Check if it's a file
    local f = io.open(code_or_file, "r")
    if f then
        local file_content = f:read("*a")
        f:close()
        local runner_chunk, runner_err = load(file_content, "@" .. code_or_file)
        if runner_chunk then
            local status, result = pcall(runner_chunk)
            if not status then
                print(colors.red .. "Error executing file '" .. code_or_file .. "': " .. tostring(result) .. colors.reset)
            end
        else
            print(colors.red .. "Error loading file '" .. code_or_file .. "': " .. tostring(runner_err) .. colors.reset)
        end
    else
        -- Treat as a string of Lua code
        local runner_chunk, runner_err = load(code_or_file, "=(runner)")
        if runner_chunk then
            local status, result = pcall(runner_chunk)
            if not status then
                print(colors.red .. "Error executing code: " .. tostring(result) .. colors.reset)
            end
        else
            print(colors.red .. "Error loading code: " .. tostring(runner_err) .. colors.reset)
        end
    end
end


local function run_tests(test_args)
    print("Running Rio tests with Busted...")
    local effective_lua_path, effective_lua_cpath = get_lua_paths()

    -- Ensure busted executable is found in common luarocks bin folders
    local home = os.getenv("HOME") or os.getenv("USERPROFILE") or "."
    local busted_path_addition = home .. "/.luarocks/bin"
    
    local command_args_str = table.concat(test_args, " ")
    if command_args_str == "" then
        -- Default to running all tests in the 'test/' directory with _test.lua pattern
        command_args_str = "test/ --pattern=\"_test.lua$\""
    end

    local command = string.format(
        "LUA_PATH='%s;%s' LUA_CPATH='%s' RIO_ENV='test' RIO_HASH_ITERATIONS='1' PATH='%s:%s' busted --helper=test/spec_helper.lua %s",
        rio_framework_lib_path_global, effective_lua_path, effective_lua_cpath, busted_path_addition, os.getenv("PATH") or "", command_args_str
    )
    
    -- Execute the command
    os.execute(command)
end

function generate_database_content(database_adapter, project_name, config)
    config = config or {}
    local database_content = ""
    if database_adapter == "sqlite" or database_adapter == "sqlite3" then
        database_content = [[
-- config/database.lua
-- Database configurations for the Rio framework.
return {
    development = {
        adapter = "sqlite",
        database = "db/development.sqlite3"
    },
    test = {
        adapter = "sqlite",
        database = "db/test.sqlite3"
    },
    production = {
        adapter = "sqlite",
        database = "db/production.sqlite3"
    }
}
]]
    elseif database_adapter == "postgresql" or database_adapter == "postgres" then
        database_content = string.format([[
-- config/database.lua
-- Database configurations for the Rio framework.
return {
    development = {
        adapter = "postgres",
        host = "%s",
        port = %s,
        username = "%s",
        password = "%s",
        database = "%s",
        -- charset = "UTF8",
    },
    test = {
        adapter = "postgres",
        host = "%s",
        port = %s,
        username = "%s",
        password = "%s",
        database = "%s_test",
        -- charset = "UTF8",
    },
    production = {
        adapter = "postgres",
        host = "%s",
        port = %s,
        username = "%s",
        password = "%s",
        database = "%s_production",
        -- charset = "UTF8",
    }
}
]], 
    config.host or "localhost", config.port or 5432, config.username or "rio_dev", config.password or "password", config.database or (project_name .. "_development"),
    config.host or "localhost", config.port or 5432, config.username or "rio_dev", config.password or "password", project_name,
    config.host or "localhost", config.port or 5432, config.username or "rio_dev", config.password or "password", project_name)
    elseif database_adapter == "mysql" then
        database_content = string.format([[
-- config/database.lua
-- Database configurations for the Rio framework.
return {
    development = {
        adapter = "mysql",
        host = "%s",
        port = %s,
        username = "%s",
        password = "%s",
        database = "%s",
        -- engine = "InnoDB",
        -- charset = "utf8mb4",
    },
    test = {
        adapter = "mysql",
        host = "%s",
        port = %s,
        username = "%s",
        password = "%s",
        database = "%s_test",
        -- engine = "InnoDB",
        -- charset = "utf8mb4",
    },
    production = {
        adapter = "mysql",
        host = "%s",
        port = %s,
        username = "%s",
        password = "%s",
        database = "%s_production",
        -- engine = "InnoDB",
        -- charset = "utf8mb4",
    }
}
]], 
    config.host or "127.0.0.1", config.port or 3306, config.username or "root", config.password or "password", config.database or (project_name .. "_development"),
    config.host or "127.0.0.1", config.port or 3306, config.username or "root", config.password or "password", project_name,
    config.host or "127.0.0.1", config.port or 3306, config.username or "root", config.password or "password", project_name)
    end
    return database_content
end

local function interactive_db_setup()
    print("\n" .. colors.cyan .. "Rio Database Setup" .. colors.reset)
    print("--------------------")
    print("No database configuration found or config is empty.")
    print("Please choose a database adapter:")

    -- Dynamically list adapters from lib/rio/database/adapters/
    local adapter_dir = "lib/rio/database/adapters"
    -- Check relative path from current bin location
    local base_path = debug.getinfo(1, "S").source:match("@(.*/)") or ""
    local full_adapter_dir = base_path .. "../lib/rio/database/adapters"

    local handle = io.popen("ls " .. full_adapter_dir .. "/*.lua 2>/dev/null")
    local adapters = {}
    if handle then
        for file in handle:lines() do
            local name = file:match("([^/]+)%.lua$")
            if name and name ~= "base" then
                table.insert(adapters, name)
            end
        end
        handle:close()
    end

    if #adapters == 0 then
        -- Fallback to hardcoded defaults if directory scan fails
        adapters = {"sqlite", "postgres", "mysql"}
    end

    for i, name in ipairs(adapters) do
        local label = name:sub(1,1):upper() .. name:sub(2)
        if name == "sqlite" then label = "SQLite (recommended for development)" end
        print(string.format("%d) %s", i, label))
    end
    print("q) Cancel")
    
    io.write("\nSelection: ")
    local choice = io.read()
    
    if choice:lower() == "q" then
        print("Setup cancelled.")
        return nil
    end

    local choice_idx = tonumber(choice)
    local adapter = adapters[choice_idx]

    if not adapter then 
        print("Invalid selection. Setup cancelled.")
        return nil
    end
    
    local config = {}
    if adapter ~= "sqlite" then
        io.write("\nWould you like to configure connection details now? (y/N): ")
        local configure_now = io.read()
        if configure_now and (configure_now:lower() == "y" or configure_now:lower() == "yes") then
            local default_port = (adapter == "postgres") and 5432 or 3306
            local default_user = (adapter == "postgres") and "rio_dev" or "root"
            
            io.write("Host (default: localhost): ")
            config.host = io.read(); if config.host == "" then config.host = nil end
            
            io.write("Port (default: " .. default_port .. "): ")
            config.port = io.read(); if config.port == "" then config.port = nil end
            
            io.write("Username (default: " .. default_user .. "): ")
            config.username = io.read(); if config.username == "" then config.username = nil end
            
            io.write("Password (default: password): ")
            config.password = io.read(); if config.password == "" then config.password = nil end
            
            io.write("Database Name (leave empty for default): ")
            config.database = io.read(); if config.database == "" then config.database = nil end
        end
    end
    
    local project_name = "rio_app"
    -- Try to guess project name from current directory
    local current_dir = io.popen("basename $(pwd)"):read("*l")
    if current_dir then project_name = current_dir end
    
    local content = generate_database_content(adapter, project_name, config)
    if content ~= "" then
        create_dir_if_not_exists("config")
        write_file_content("config/database.lua", content)
        print(colors.green .. "\n✓ Created config/database.lua with " .. adapter .. " adapter." .. colors.reset)
        
        -- Reload config
        package.loaded["config.database"] = nil
        local original_package_path = package.path
        package.path = "./config/?.lua;" .. package.path
        local status, db_config = pcall(require, "config.database")
        package.path = original_package_path
        return status and db_config or nil
    end
    return nil
end

-- Database commands
local function load_database_config()
    local config_file = "config/database.lua"
    
    -- To load config.database, we need to ensure the current project's config directory is in LUA_PATH
    local original_package_path = package.path
    package.path = "./config/?.lua;" .. package.path

    local status, db_config = pcall(require, "config.database") -- require "config.database"
    package.path = original_package_path -- Restore original path

    if not status or type(db_config) ~= "table" or next(db_config) == nil then
        -- If config is missing, malformed or empty, trigger interactive setup
        return interactive_db_setup()
    end
    return db_config
end

local function get_database_full_path(db_config, env)
    local current_env_config = db_config[env]
    if not current_env_config then
        return nil, "Database configuration not found for environment: " .. env
    end

    if current_env_config.adapter ~= "sqlite" then
        return nil, "Unsupported adapter for file operations: " .. current_env_config.adapter
    end

    -- Assuming current_env_config.database already contains the full file path including extension
    return current_env_config.database
end

local function get_db_connection(db_config, env)
    local current_env_config = db_config[env]
    if not current_env_config then
        return nil, "Database configuration not found for environment: " .. env
    end

    local adapter_name = current_env_config.adapter
    local effective_lua_path, effective_lua_cpath = get_lua_paths()

    local adapter
    local ok, err_msg = pcall(function()
        local original_package_path = package.path
        local original_package_cpath = package.cpath
        package.path = effective_lua_path
        package.cpath = effective_lua_cpath
        
        adapter = require("rio.database.adapters." .. adapter_name)
        
        package.path = original_package_path
        package.cpath = original_package_cpath
    end)
    
    if not ok then
        return nil, "Could not load database adapter '" .. adapter_name .. "': " .. err_msg
    end

    -- Initialize the adapter
    if adapter.initialize then
        local original_package_cpath = package.cpath
        package.cpath = effective_lua_cpath
        adapter.initialize(current_env_config)
        package.cpath = original_package_cpath
    end

    local conn, err = adapter.get_connection()
    if not conn then
        return nil, "Failed to connect to database: " .. (err or "unknown error")
    end
    
    -- Enable autocommit for DML statements
    if conn.autocommit then
        conn:autocommit(true)
    end

    return conn, adapter -- Return both connection and adapter for further use
end


local function get_db_config_and_run(fn_name)
    local db_config = load_database_config()
    if not db_config then return end

    local env = os.getenv("RIO_ENV") or "development"
    local current_env_config = db_config[env]

    if not current_env_config then
        print("Error: Database configuration not found for environment: " .. env)
        return
    end

    -- Setup paths for the adapter and app models
    local effective_lua_path, effective_lua_cpath = get_lua_paths()
    local original_package_path = package.path
    local original_package_cpath = package.cpath
    
    -- Prepend project paths so migrations and seeds can require models
    package.path = "./app/?.lua;./app/?/init.lua;./config/?.lua;./lib/?.lua;" .. effective_lua_path .. ";" .. original_package_path
    package.cpath = effective_lua_cpath .. ";" .. original_package_cpath

    local Migrate = require("rio.database.migrate").Migrate
    local DB = require("rio.database.manager")
    
    -- Initialize the manager which will load the adapter
    local ok_init, err_init = pcall(DB.initialize, current_env_config)
    if not ok_init then
        print("Error initializing database: " .. tostring(err_init))
        package.path = original_package_path
        package.cpath = original_package_cpath
        return
    end

    -- Call the Migrate method
    if type(Migrate[fn_name]) == "function" then
        if fn_name == "create" or fn_name == "drop" or fn_name == "setup" or fn_name == "reset" then
            Migrate[fn_name](current_env_config)
        else
            Migrate[fn_name]()
        end
    else
        print("Error: Migration method '" .. fn_name .. "' not found.")
    end

    -- Restore paths
    package.path = original_package_path
    package.cpath = original_package_cpath
end

local function run_db_create() get_db_config_and_run("create") end
local function run_db_drop() get_db_config_and_run("drop") end
local function run_db_migrate() get_db_config_and_run("run") end
local function run_db_rollback() get_db_config_and_run("rollback") end
local function run_db_status() get_db_config_and_run("status") end
local function run_db_seed() get_db_config_and_run("seed") end
local function run_db_setup() get_db_config_and_run("setup") end
local function run_db_reset() get_db_config_and_run("reset") end

local function run_db_version()
    local db_config = load_database_config()
    if not db_config then return end

    local env = os.getenv("RIO_ENV") or "development"
    local current_env_config = db_config[env]

    if not current_env_config then
        print("Error: Database configuration not found for environment: " .. env)
        return
    end

    -- Setup paths for the adapter
    local effective_lua_path, effective_lua_cpath = get_lua_paths()
    local original_package_path = package.path
    local original_package_cpath = package.cpath
    
    package.path = "./app/?.lua;./app/?/init.lua;./config/?.lua;./lib/?.lua;" .. effective_lua_path .. ";" .. original_package_path
    package.cpath = effective_lua_cpath .. ";" .. original_package_cpath

    local DB = require("rio.database.manager")
    local Migrate = require("rio.database.migrate").Migrate
    
    local ok_init, err_init = pcall(DB.initialize, current_env_config)
    if not ok_init then
        print("Error initializing database: " .. tostring(err_init))
        package.path = original_package_path
        package.cpath = original_package_cpath
        return
    end

    local db_name = current_env_config.database or current_env_config.host or "unknown"
    local version = Migrate.version()

    print("")
    print("database: " .. db_name)
    print("Current version: " .. (version or "0"))
    print("")

    package.path = original_package_path
    package.cpath = original_package_cpath
end

local function run_db_seed_replant()
    print("Replanting seeds...")
    get_db_config_and_run("seed")
end

local function run_db_system_change(args)
    local to_adapter = nil
    for _, arg in ipairs(args) do
        to_adapter = arg:match("^%-%-to=(.+)$")
        if to_adapter then break end
    end

    if not to_adapter then
        print(colors.red .. "Error: 'db:system:change' requires a target adapter via --to=<adapter>." .. colors.reset)
        print("Example: rio db:system:change --to=postgresql")
        return
    end

    -- Validate adapter
    local valid_adapters = {
        postgresql = "postgres", postgres = "postgres",
        mysql = "mysql",
        sqlite = "sqlite", sqlite3 = "sqlite"
    }
    local normalized_adapter = valid_adapters[to_adapter:lower()]
    
    if not normalized_adapter then
        print(colors.red .. "Error: Invalid database adapter '" .. to_adapter .. "'." .. colors.reset)
        print("Supported adapters: postgresql, mysql, sqlite3")
        return
    end

    local config_file = "config/database.lua"
    if io.open(config_file, "r") then
        io.write(colors.yellow .. "Overwrite " .. config_file .. "? (y/N): " .. colors.reset)
        local answer = io.read()
        if not (answer and (answer:lower() == "y" or answer:lower() == "yes")) then
            print("Operation cancelled.")
            return
        end
    end

    local project_name = "rio_app"
    local current_dir = io.popen("basename $(pwd)"):read("*l")
    if current_dir then project_name = current_dir end

    local config = {}
    if normalized_adapter ~= "sqlite" then
        io.write("\nWould you like to configure connection details now? (y/N): ")
        local configure_now = io.read()
        if configure_now and (configure_now:lower() == "y" or configure_now:lower() == "yes") then
            local default_port = (normalized_adapter == "postgres") and 5432 or 3306
            local default_user = (normalized_adapter == "postgres") and "rio_dev" or "root"
            
            io.write("Host (default: localhost): ")
            config.host = io.read(); if config.host == "" then config.host = nil end
            
            io.write("Port (default: " .. default_port .. "): ")
            config.port = io.read(); if config.port == "" then config.port = nil end
            
            io.write("Username (default: " .. default_user .. "): ")
            config.username = io.read(); if config.username == "" then config.username = nil end
            
            io.write("Password (default: password): ")
            config.password = io.read(); if config.password == "" then config.password = nil end
            
            io.write("Database Name (leave empty for default): ")
            config.database = io.read(); if config.database == "" then config.database = nil end
        end
    end

    local content = generate_database_content(normalized_adapter, project_name, config)
    if content ~= "" then
        write_file_content(config_file, content)
        print(colors.green .. "✓ Updated " .. config_file .. " to use " .. normalized_adapter .. "." .. colors.reset)
    end
end

local function run_db_prepare()
    get_db_config_and_run("run")
end

-- Mailer commands
local function run_mailbox_install()
    print("Mailbox installation not yet implemented in the new architecture.")
end

local function run_mailbox_ingress(provider)
    print("Mailbox ingress for " .. provider .. " not yet implemented.")
end

local function run_tmp(subcommand, remaining_args)
    local function stop_server_by_pid(pid_path)
        local f = io.open(pid_path, "r")
        if f then
            local pid = f:read("*a"):gsub("%s+", "")
            f:close()
            if pid and pid ~= "" then
                print("Stopping server with PID " .. pid .. "...")
                -- Try to kill the process group (using negative PID) for a cleaner shutdown
                os.execute("kill -- -" .. pid .. " 2>/dev/null || kill " .. pid .. " 2>/dev/null")
                os.execute("sleep 1")
            end
            os.remove(pid_path)
        end
    end

    local function clear_dir(path)
        print("Clearing " .. path .. "...")
        if path == "tmp/pids" then
            -- Special handling for pids: stop servers first
            local handle = io.popen("ls tmp/pids/*.pid 2>/dev/null")
            if handle then
                for pid_file in handle:lines() do
                    stop_server_by_pid(pid_file)
                end
                handle:close()
            end
        else
            os.execute("rm -rf " .. path .. "/*")
        end
    end

    local function create_tmp_dirs()
        print("Creating tmp directories...")
        local dirs = { "tmp/cache", "tmp/sockets", "tmp/pids", "tmp/screenshots" }
        for _, dir in ipairs(dirs) do
            os.execute("mkdir -p " .. dir)
            print("  Created " .. dir)
        end
    end

    if subcommand == "create" then
        create_tmp_dirs()
    elseif subcommand == "clear" then
        clear_dir("tmp/cache")
        clear_dir("tmp/sockets")
        clear_dir("tmp/screenshots")
        clear_dir("tmp/pids")
    elseif subcommand == "cache:clear" then
        clear_dir("tmp/cache")
    elseif subcommand == "sockets:clear" then
        clear_dir("tmp/sockets")
    elseif subcommand == "screenshots:clear" then
        clear_dir("tmp/screenshots")
    elseif subcommand == "pids:clear" then
        clear_dir("tmp/pids")
    else
        print("Error: Unknown 'tmp' subcommand '" .. (subcommand or "") .. "'")
        -- show_tmp_help() -- will be called from cli.run if needed
    end
end

local function run_routes(options)
    options = options or {}
    print("Listing defined routes...")
    
    local effective_lua_path, effective_lua_cpath = get_lua_paths()
    local original_package_path = package.path
    local original_package_cpath = package.cpath
    
    -- We need to include the project directories to load config and routes
    package.path = "./?.lua;./app/?.lua;./app/?/init.lua;./config/?.lua;./lib/?.lua;" .. rio_framework_lib_path_global .. ";" .. effective_lua_path .. ";" .. original_package_path
    package.cpath = effective_lua_cpath .. ";" .. original_package_cpath

    local ok, rio = pcall(require, "rio")
    if not ok then
        print("Error: Could not load 'rio' framework: " .. tostring(rio))
        package.path = original_package_path
        package.cpath = original_package_cpath
        return
    end

    local ok_config, application_config = pcall(require, "config.application")
    if not ok_config or type(application_config) ~= "table" then
        application_config = { server = { port = 8080, host = "0.0.0.0" }, environment = "development" }
    end

    local server_config = application_config.server or { port = 8080, host = "0.0.0.0" }
    local app = rio.new({
        server = server_config,
        environment = application_config.environment or "development"
    })

    local ok_routes, routes_fn = pcall(require, "config.routes")
    if not ok_routes then
        print("Error: Could not load 'config/routes.lua': " .. tostring(routes_fn))
        package.path = original_package_path
        package.cpath = original_package_cpath
        return
    end

    -- Load the routes into the app instance
    local ok_exec, err_exec = pcall(routes_fn, app)
    if not ok_exec then
        print("Error executing 'config/routes.lua': " .. tostring(err_exec))
        package.path = original_package_path
        package.cpath = original_package_cpath
        return
    end

    local route_list = {}
    local METHODS = {"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"}
    
    -- Helper to extract code from file line
    local function extract_controller_action(source, line_num)
        if not source or source:sub(1,1) ~= "@" then return "unknown" end
        local path = source:sub(2)
        local f = io.open(path, "r")
        if not f then return "unknown" end
        
        local current_line = 0
        local content = nil
        for line in f:lines() do
            current_line = current_line + 1
            if current_line == line_num then
                content = line
                break
            end
        end
        f:close()
        
        if content then
            -- Try to match Controller:action or Controller.action
            local ctrl, action = content:match("([%w_]+Controller)[%.:]([%w_]+)")
            if ctrl and action then
                return ctrl .. "#" .. action
            end
            
            -- Try to match simple Controller call if aliased
            -- e.g. Home:index
            local c, a = content:match("([A-Z][%w_]+)[%.:]([%w_]+)")
            if c and a then
                return c .. "#" .. a
            end
        end
        return "anonymous"
    end

    for _, method in ipairs(METHODS) do
        local routes = app.router.routes[method] or {}
        for _, route in ipairs(routes) do
            local info = debug.getinfo(route.handler, "S")
            local line = debug.getinfo(route.handler, "l").currentline
            local source_loc = ""
            local controller_action = "anonymous"
            
            -- Check for Rio metadata (attached by resources() or other helpers)
            if type(route.handler) == "function" and app.routes_meta and app.routes_meta[route.handler] then
                local meta = app.routes_meta[route.handler]
                if meta.controller and meta.action then
                    controller_action = meta.controller .. "#" .. meta.action
                end
                if meta.source then
                    source_loc = meta.source
                end
            end
            
            -- Fallback to debug info if metadata is missing or incomplete
            if (source_loc == "" or controller_action == "anonymous") and info and info.source then
                local short_src = info.short_src
                if short_src:find(original_package_path) then
                    short_src = "..." .. short_src:sub(-30)
                end
                
                if source_loc == "" then
                    source_loc = string.format("%s:%d", short_src, line)
                end
                
                if controller_action == "anonymous" then
                    controller_action = extract_controller_action(info.source, line)
                end
            end

            local entry = {
                prefix = route.name or "",
                verb = method,
                uri = route.path,
                controller = controller_action,
                source = source_loc
            }
            
            -- Filtering logic
            local include = true
            
            if options.controller then
                local search = options.controller:lower()
                if not entry.controller:lower():find(search, 1, true) then
                    include = false
                end
            end
            
            if options.grep and include then
                local search = options.grep:lower()
                local found = false
                if entry.verb:lower():find(search, 1, true) then found = true end
                if entry.uri:lower():find(search, 1, true) then found = true end
                if entry.controller:lower():find(search, 1, true) then found = true end
                if entry.prefix:lower():find(search, 1, true) then found = true end
                if not found then include = false end
            end

            if include then
                table.insert(route_list, entry)
            end
        end
    end

    if #route_list == 0 then
        print("No routes found matching your criteria.")
        package.path = original_package_path
        package.cpath = original_package_cpath
        return
    end

    if options.expanded then
        for i, route in ipairs(route_list) do
            print(string.format("--[ Route %d ]%s", i, string.rep("-", 60)))
            print(string.format("%-20s | %s", "Prefix", route.prefix))
            print(string.format("%-20s | %s", "Verb", route.verb))
            print(string.format("%-20s | %s", "URI Pattern", route.uri))
            print(string.format("%-20s | %s", "Controller#Action", route.controller))
            print(string.format("%-20s | %s", "Source Location", route.source))
        end
    else
        -- Calculate column widths
        local w_prefix, w_verb, w_uri, w_ctrl = 6, 4, 10, 20
        for _, r in ipairs(route_list) do
            if #r.prefix > w_prefix then w_prefix = #r.prefix end
            if #r.verb > w_verb then w_verb = #r.verb end
            if #r.uri > w_uri then w_uri = #r.uri end
            if #r.controller > w_ctrl then w_ctrl = #r.controller end
        end
        
        local fmt = string.format("%%-%ds  %%-%ds  %%-%ds  %%s", w_prefix, w_verb, w_uri)
        
        print(string.format(fmt, "Prefix", "Verb", "URI Pattern", "Controller#Action"))
        -- print(string.rep("-", w_prefix + w_verb + w_uri + w_ctrl + 6))
        
        for _, r in ipairs(route_list) do
            print(string.format(fmt, r.prefix, r.verb, r.uri, r.controller))
        end
    end
    print("")

    package.path = original_package_path
    package.cpath = original_package_cpath
end

local function run_middleware()
    print(colors.cyan .. "Listing middlewares..." .. colors.reset)
    
    local effective_lua_path, effective_lua_cpath = get_lua_paths()
    local original_package_path = package.path
    local original_package_cpath = package.cpath
    
    -- We need to include the project directories to load config
    package.path = "./?.lua;./app/?.lua;./app/?/init.lua;./config/?.lua;./lib/?.lua;" .. rio_framework_lib_path_global .. ";" .. effective_lua_path .. ";" .. original_package_path
    package.cpath = effective_lua_cpath .. ";" .. original_package_cpath

    local ok, rio = pcall(require, "rio")
    if not ok then
        print(colors.red .. "Error: Could not load 'rio' framework: " .. tostring(rio) .. colors.reset)
        package.path = original_package_path
        package.cpath = original_package_cpath
        return
    end

    local ok_config, application_config = pcall(require, "config.application")
    if not ok_config or type(application_config) ~= "table" then
        application_config = { server = { port = 8080, host = "0.0.0.0" }, environment = "development" }
    end

    local server_config = application_config.server or { port = 8080, host = "0.0.0.0" }
    local app = rio.new({
        server = server_config,
        environment = application_config.environment or "development"
    })

    -- Load middlewares from config/middlewares.lua
    local ok_mw_config, middlewares_cfg = pcall(require, "config.middlewares")
    if ok_mw_config then
        local ok_mw, err_mw = pcall(function() app:load_middlewares(middlewares_cfg) end)
        if not ok_mw then
            print(colors.red .. "Warning: Error loading middlewares: " .. tostring(err_mw) .. colors.reset)
            print(colors.yellow .. "Check your config/middlewares.lua for errors." .. colors.reset)
        end
    end

    print("\n" .. colors.bold .. "Application Middleware Stack (Active)" .. colors.reset)
    print(string.rep("-", 85))
    
    local active_names = {}
    if #app.middlewares == 0 then
        print(colors.yellow .. "  (No middleware defined)" .. colors.reset)
    else
        for _, mw_entry in ipairs(app.middlewares) do
            local mw = mw_entry.handler
            local source_info = mw_entry.source
            
            local info = debug.getinfo(mw, "Sn")
            local name = "anonymous"
            local location = "unknown"
            
            if info then
                if info.short_src then
                    local src = info.short_src
                    -- Simplify Rio core middlewares (rio/middleware/logger.lua -> logger)
                    local mw_file = src:match("rio/middleware/(.+)%.lua")
                    if mw_file then
                        name = mw_file
                    else
                        -- Custom middleware (app/middleware/auth.lua -> auth)
                        name = src:match("([^/]+)%.lua$") or src
                    end
                    location = string.format("%s:%d", src:match("([^/]+)$") or src, info.linedefined)
                end
                
                if info.name and info.name ~= "" then
                    name = info.name
                end
            end
            
            active_names[name] = true

            -- Highlight if added in config/application.lua
            local source_display = source_info
            if source_info:find("application.lua") then
                source_display = colors.bold .. colors.white .. "config/" .. source_info .. colors.reset
            else
                source_display = colors.yellow .. source_info .. colors.reset
            end
            
            print(string.format("%suse %-20s%s %-35s %s(%s)%s", 
                colors.green, name, colors.reset, 
                source_display,
                colors.blue, location, colors.reset))
        end
    end
    print(string.rep("-", 85))
    print("Total Active: " .. #app.middlewares)

    -- Available Middlewares
    print("\n" .. colors.bold .. "Available Middlewares (Core & Local)" .. colors.reset)
    print(string.rep("-", 85))
    print(string.format("%-18s %-12s %-20s", colors.bold .. "Status" .. colors.reset, colors.bold .. "Type" .. colors.reset, colors.bold .. "Name" .. colors.reset))
    print(string.rep("-", 85))
    
    local available = {}
    
    -- 1. Scan Core Middlewares
    local framework_base = rio_framework_lib_path_global:match("([^;]+)"):gsub("%?%.lua", ""):gsub("%?$", "")
    local core_mw_path = framework_base .. "rio/middleware"
    local handle = io.popen("ls " .. core_mw_path .. "/*.lua 2>/dev/null")
    if handle then
        for file in handle:lines() do
            local mw_name = file:match("([^/]+)%.lua$")
            if mw_name then
                table.insert(available, { name = mw_name, type = "core" })
            end
        end
        handle:close()
    end

    -- 2. Scan Local Middlewares
    local local_mw_path = "app/middleware"
    handle = io.popen("ls " .. local_mw_path .. "/*.lua 2>/dev/null")
    if handle then
        for file in handle:lines() do
            local mw_name = file:match("([^/]+)%.lua$")
            if mw_name then
                table.insert(available, { name = mw_name, type = "local" })
            end
        end
        handle:close()
    end

    table.sort(available, function(a, b) return a.name < b.name end)

    for _, mw in ipairs(available) do
        local status_text = active_names[mw.name] and "ACTIVE" or "NOT USED"
        local status_color = active_names[mw.name] and colors.green or colors.yellow
        local status = status_color .. string.format("[%s]", status_text) .. colors.reset
        
        local type_text = mw.type == "core" and "rio" or "local"
        local type_color = mw.type == "core" and colors.cyan or colors.magenta
        local mw_type = type_color .. type_text .. colors.reset
        
        -- Try to get description
        local description = ""
        local mw_module_path = mw.type == "core" and ("rio.middleware." .. mw.name) or ("app.middleware." .. mw.name)
        local ok_load, mw_mod = pcall(require, mw_module_path)
        if ok_load and type(mw_mod) == "table" and mw_mod.description then
            description = colors.dim .. mw_mod.description .. colors.reset
        end
        
        print(string.format("%-27s %-21s %-20s %s", status, mw_type, colors.bold .. mw.name .. colors.reset, description))
    end
    print(string.rep("-", 85))
    print("Run " .. colors.bold .. "rio middleware:use <name>" .. colors.reset .. " to enable a middleware.\n")

    package.path = original_package_path
    package.cpath = original_package_cpath
end

local function generate_middleware(name)
    local core_middlewares = {
        logger = true,
        security = true,
        cors = true,
        auth = true,
        static = true
    }

    if core_middlewares[name:lower()] then
        print(colors.red .. "Error: '" .. name .. "' is a reserved Rio core middleware name." .. colors.reset)
        print("Please choose a different name for your custom middleware.")
        return
    end

    local mw_dir = "app/middleware"
    create_dir_if_not_exists(mw_dir)
    local file_path = mw_dir .. "/" .. underscore(name) .. ".lua"
    
    -- Prompt for description
    io.write(colors.cyan .. "Enter a brief description for this middleware: " .. colors.reset)
    local description = io.read()
    if not description or description == "" then
        description = "Custom middleware for " .. name
    end

    print(colors.cyan .. "Generating middleware: " .. colors.reset .. file_path)
    
    local content = [[
-- app/middleware/]] .. underscore(name) .. [[.lua

local M = {}

M.description = "]] .. description .. [["

function M.create(options)
    return function(ctx, next_fn)
        -- Pre-processing
        -- Example: print("Starting request...")
        
        local result, err = next_fn()
        
        -- Post-processing
        -- Example: print("Finished request.")
        
        return result, err
    end
end

return M
]]
    write_file_content(file_path, content)
    print(colors.green .. "Middleware '" .. name .. "' created successfully." .. colors.reset)
    print("To use it, run: " .. colors.bold .. "rio middleware:add " .. underscore(name) .. colors.reset)
end

local function get_middleware_line(name)
    local core_mappings = {
        logger = "app:use(rio.middleware.logger.basic())",
        security = "app:use(rio.middleware.security.headers())",
        cors = "app:use(rio.middleware.cors.default())",
        auth = "app:use(rio.auth.basic())",
        static = "app:use(rio.middleware.static.serve(\"public\"))"
    }
    
    if core_mappings[name] then
        return core_mappings[name]
    end
    
    -- Check if it's a local middleware in app/middleware/
    local local_mw_path = "app/middleware/" .. underscore(name) .. ".lua"
    local f = io.open(local_mw_path, "r")
    if f then
        f:close()
        return string.format("app:use(require(\"app.middleware.%s\"))", underscore(name))
    end
    
    -- If it's a module path like app.middleware.mine
    return string.format("app:use(require(\"%s\"))", name)
end

local function use_middleware(name)
    local config_file = "config/middlewares.lua"
    local f = io.open(config_file, "r")
    if not f then
        print(colors.red .. "Error: Could not find " .. config_file .. colors.reset)
        return
    end
    
    local content = f:read("*a")
    f:close()
    
    -- Clean the name
    local mw_name = name:match("([^/.]+)%.lua$") or name:match("([^/.]+)$") or name
    
    -- Avoid duplicate
    if content:find("\"" .. mw_name .. "\"", 1, true) or content:find("'" .. mw_name .. "'", 1, true) then
        print(colors.yellow .. "Notice: Middleware '" .. mw_name .. "' is already enabled." .. colors.reset)
        return
    end
    
    -- Find the return table block
    local pattern = "(return%s*{)(.-)(})"
    local head, body, tail = content:match(pattern)
    
    if not head then
        -- Fallback to old function style if still present
        print(colors.yellow .. "Notice: config/middlewares.lua is using old format. Converting to list format..." .. colors.reset)
        write_file_content(config_file, "return {\n    \"logger\",\n    \"security\",\n    \"cors\",\n    \"" .. mw_name .. "\"\n}\n")
        print(colors.green .. "Successfully enabled '" .. mw_name .. "'." .. colors.reset)
        return
    end
    
    -- Add to body
    local new_body = body:gsub("%s*$", "")
    if new_body ~= "" and not new_body:match(",%s*$") then
        new_body = new_body .. ","
    end
    new_body = new_body .. "\n    \"" .. mw_name .. "\"\n"
    
    local new_content = head .. new_body .. tail
    
    write_file_content(config_file, new_content)
    print(colors.green .. "Successfully enabled '" .. mw_name .. "' in " .. config_file .. colors.reset)
end

local function unuse_middleware(name)
    local config_file = "config/middlewares.lua"
    local f = io.open(config_file, "r")
    if not f then
        print(colors.red .. "Error: Could not find " .. config_file .. colors.reset)
        return
    end
    
    local content = f:read("*a")
    f:close()
    
    local mw_name = name:match("([^/.]+)%.lua$") or name:match("([^/.]+)$") or name
    
    local new_content, count = content:gsub("[\n%s]*\"" .. mw_name .. "\"%s*,?", "")
    if count == 0 then
        new_content, count = content:gsub("[\n%s]*'" .. mw_name .. "'%s*,?", "")
    end
    
    if count == 0 then
        print(colors.yellow .. "Notice: Middleware '" .. mw_name .. "' not found." .. colors.reset)
        return
    end

    -- Cleanup trailing commas
    new_content = new_content:gsub(",%s*}", "\n}")

    write_file_content(config_file, new_content)
    print(colors.green .. "Successfully disabled '" .. mw_name .. "' in " .. config_file .. colors.reset)
end

local function rm_middleware(name)
    local local_mw_path = "app/middleware/" .. underscore(name) .. ".lua"
    local f = io.open(local_mw_path, "r")
    if not f then
        print(colors.red .. "Error: Local middleware file not found: " .. local_mw_path .. colors.reset)
        return
    end
    f:close()

    io.write(colors.yellow .. "Are you sure you want to delete the file " .. local_mw_path .. "? (y/N): " .. colors.reset)
    local answer = io.read()
    if answer and (answer:lower() == "y" or answer:lower() == "yes") then
        -- Unuse it first while the file exists (so get_middleware_line knows it's a local MW)
        unuse_middleware(name)
        
        if os.remove(local_mw_path) then
            print(colors.green .. "File deleted: " .. local_mw_path .. colors.reset)
        else
            print(colors.red .. "Error: Could not delete " .. local_mw_path .. colors.reset)
        end
    else
        print("Operation cancelled.")
    end
end

local function run_about()
    print("About your application's environment")
    
    local effective_lua_path, effective_lua_cpath = get_lua_paths()
    local original_package_path = package.path
    local original_package_cpath = package.cpath
    
    package.path = "./?.lua;./app/?.lua;./app/?/init.lua;./config/?.lua;./lib/?.lua;" .. rio_framework_lib_path_global .. ";" .. effective_lua_path .. ";" .. original_package_path
    package.cpath = effective_lua_cpath .. ";" .. original_package_cpath

    -- Rio Version
    local ok_rio, rio = pcall(require, "rio")
    local rio_version = ok_rio and rio.VERSION or "Unknown"

    -- Lua version
    local lua_version = _VERSION

    -- LuaRocks version
    local handle = io.popen("luarocks --version 2>/dev/null", "r")
    local luarocks_output = handle:read("*l") or "Unknown"
    handle:close()
    local luarocks_version = luarocks_output:match("luarocks%s+([%d%.]+)") or luarocks_output

    -- Middleware
    local middleware_str = "None"
    local ok_mw, mw_config = pcall(require, "config.middlewares")
    if ok_mw and type(mw_config) == "table" then
        middleware_str = table.concat(mw_config, ", ")
    end

    -- Application root
    local app_root = io.popen("pwd"):read("*l") or "."

    -- Environment
    local environment = os.getenv("RIO_ENV") or "development"

    -- Database info (don't trigger interactive setup)
    local original_path_for_db = package.path
    package.path = "./config/?.lua;" .. original_path_for_db
    local db_config_status, db_config = pcall(require, "config.database")
    package.path = original_path_for_db

    local adapter = "None"
    local schema_version = "None"

    if db_config_status and type(db_config) == "table" and db_config[environment] then
        adapter = db_config[environment].adapter or "Unknown"
        
        -- Try to get schema version without triggering interactive setup
        local status_conn, conn, adapter_mod = pcall(get_db_connection, db_config, environment)
        if status_conn and conn then
            -- Note: In Rio, migrations are stored in 'migrations' table, 'migration' column
            local res_status, res = pcall(conn.execute, conn, "SELECT migration FROM migrations ORDER BY migration DESC LIMIT 1")
            if res_status and res and res.fetch then
                local row = res:fetch({}, "a")
                if row and row.migration then
                    -- Extract timestamp from "YYYYMMDDHHMMSS_name"
                    schema_version = row.migration:match("^(%d+)") or row.migration
                end
                res:close()
            end
            if adapter_mod and adapter_mod.release_connection then
                pcall(adapter_mod.release_connection, conn, nil)
            end
        end
    end

    print(string.format("%-25s %s", "Rio version", rio_version))
    print(string.format("%-25s %s", "Lua version", lua_version))
    print(string.format("%-25s %s", "LuaRocks version", luarocks_version))
    print(string.format("%-25s %s", "Middleware", middleware_str))
    print(string.format("%-25s %s", "Application root", app_root))
    print(string.format("%-25s %s", "Environment", environment))
    print(string.format("%-25s %s", "Database adapter", adapter))
    print(string.format("%-25s %s", "Database schema version", schema_version))

    package.path = original_package_path
    package.cpath = original_package_cpath
end

local function run_initializers()
    print("Application Initializers")
    print(string.rep("-", 40))
    
    local initializers_dir = "config/initializers"
    local handle = io.popen("ls " .. initializers_dir .. "/*.lua 2>/dev/null")
    local count = 0
    
    if handle then
        for file in handle:lines() do
            local name = file:match("([^/]+)$")
            if name then
                print(string.format("%02d. %s", count + 1, name))
                count = count + 1
            end
        end
        handle:close()
    end
    
    if count == 0 then
        print("No initializers found in config/initializers/")
    else
        print(string.rep("-", 40))
        print("Total: " .. count .. " initializer(s)")
    end
end

local function run_stats()
    local categories = {
        { name = "Controllers",      path = "app/controllers",      pattern = "%.lua$" },
        { name = "Middlewares",      path = "app/middleware",       pattern = "%.lua$" },
        { name = "Models",           path = "app/models",           pattern = "%.lua$" },
        { name = "Mailers",          path = "app/mailers",          pattern = "%.lua$" },
        { name = "Views",            path = "app/views",            pattern = "%.etl$" },
        { name = "Libraries",        path = "lib",                  pattern = "%.lua$" },
        { name = "Initializers",     path = "config/initializers",  pattern = "%.lua$" },
        { name = "Controller tests", path = "test/controllers",     pattern = "%.lua$" },
        { name = "Model tests",      path = "test/models",          pattern = "%.lua$" },
        { name = "Mailer tests",     path = "test/mailers",         pattern = "%.lua$" },
        { name = "Integration tests",path = "test/integration",     pattern = "%.lua$" },
    }

    local function analyze_file(file_path)
        local lines = 0
        local loc = 0
        local methods = 0
        local f = io.open(file_path, "r")
        if not f then return 0, 0, 0 end

        for line in f:lines() do
            lines = lines + 1
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed ~= "" and not trimmed:match("^%-%-") then
                loc = loc + 1
            end
            
            -- Detect methods/functions
            -- matches: function Name:method, function Name.method, local function name, name = function
            if line:match("function%s+[%w_%.%:]+") or line:match("[%w_%.%:]+%s*=%s*function") then
                methods = methods + 1
            end
        end
        f:close()
        return lines, loc, methods
    end

    local function scan_dir(cat_name, dir_path, pattern)
        local total_lines, total_loc, total_methods, total_files = 0, 0, 0, 0
        
        -- Special handling for Middlewares to count active ones in config
        if cat_name == "Middlewares" then
            local f_mw_path = "config/middlewares.lua"
            local f_mw = io.open(f_mw_path, "r")
            if f_mw then
                local content = f_mw:read("*a")
                f_mw:close()
                
                -- Count lines of the config file itself as application LOC
                local l, lc, m = analyze_file(f_mw_path)
                total_lines = total_lines + l
                total_loc = total_loc + lc
                
                -- Count active middlewares as "Modules" (logical units)
                for _ in content:gmatch("\"([%w_]+)\"") do
                    total_files = total_files + 1
                end
                for _ in content:gmatch("'([%w_]+)'") do
                    total_files = total_files + 1
                end
            end
        end

        local handle = io.popen("find " .. dir_path .. " -type f 2>/dev/null")
        if handle then
            for file in handle:lines() do
                if file:match(pattern) then
                    local l, lc, m = analyze_file(file)
                    total_lines = total_lines + l
                    total_loc = total_loc + lc
                    total_methods = total_methods + m
                    -- Only increment files if we didn't count them via config already 
                    if cat_name ~= "Middlewares" then
                        total_files = total_files + 1
                    end
                end
            end
            handle:close()
        end
        return total_lines, total_loc, total_methods, total_files
    end

    print("+----------------------+-------+-------+---------+---------+-----+-------+")
    print("| Name                 | Lines |   LOC | Modules |   Funcs | F/M | LOC/F |")
    print("+----------------------+-------+-------+---------+---------+-----+-------+")

    local grand_total = { lines = 0, loc = 0, files = 0, methods = 0 }
    local code_loc = 0
    local test_loc = 0

    for _, cat in ipairs(categories) do
        local l, lc, m, f = scan_dir(cat.name, cat.path, cat.pattern)
        if f > 0 or not cat.name:find("test") then
            local f_per_m = f > 0 and math.floor(m / f) or 0
            local loc_per_f = m > 0 and math.floor(lc / m) or 0
            
            print(string.format("| %-20s | %5d | %5d | %7d | %7d | %3d | %5d |", 
                cat.name, l, lc, f, m, f_per_m, loc_per_f))
            
            grand_total.lines = grand_total.lines + l
            grand_total.loc = grand_total.loc + lc
            grand_total.files = grand_total.files + f
            grand_total.methods = grand_total.methods + m
            
            if cat.name:lower():find("test") then
                test_loc = test_loc + lc
            else
                code_loc = code_loc + lc
            end
        end
    end

    print("+----------------------+-------+-------+---------+---------+-----+-------+")
    local total_f_per_m = grand_total.files > 0 and math.floor(grand_total.methods / grand_total.files) or 0
    local total_loc_per_f = grand_total.methods > 0 and math.floor(grand_total.loc / grand_total.methods) or 0
    print(string.format("| %-20s | %5d | %5d | %7d | %7d | %3d | %5d |", 
        "Total", grand_total.lines, grand_total.loc, grand_total.files, grand_total.methods, total_f_per_m, total_loc_per_f))
    print("+----------------------+-------+-------+---------+---------+-----+-------+")
    
    local ratio = code_loc > 0 and string.format("1:%.1f", test_loc / code_loc) or "N/A"
    print(string.format("  Code LOC: %d     Test LOC: %d     Code to Test Ratio: %s", code_loc, test_loc, ratio))
    print("")
end


-- Destroyer functions
local function destroy_controller(controller_name)
    local path = "app/controllers/" .. underscore(controller_name) .. "_controller.lua"
    print("Destroying controller: " .. path)
    if os.remove(path) then
        print("Controller '" .. controller_name .. "' destroyed successfully.")
    else
        print("Error: Could not destroy controller '" .. controller_name .. "'. File not found or permission denied.")
    end

    -- Destroy associated test file
    local test_path = "test/controllers/" .. underscore(controller_name) .. "_test.lua"
    print("Destroying controller test: " .. test_path)
    if os.remove(test_path) then
        print("Controller test destroyed successfully.")
    else
        print("No associated controller test found or could not be destroyed.")
    end
end

local function destroy_model(model_name)
    local underscored_model_name = underscore(model_name)
    local model_path = "app/models/" .. underscored_model_name .. ".lua"
    print("Destroying model: " .. model_path)
    if os.remove(model_path) then
        print("Model '" .. model_name .. "' destroyed successfully.")
    else
        print("Error: Could not destroy model '" .. model_name .. "'. File not found or permission denied.")
    end

    -- Destroy associated test file
    local test_path = "test/models/" .. underscored_model_name .. "_test.lua"
    print("Destroying model test: " .. test_path)
    if os.remove(test_path) then
        print("Model test destroyed successfully.")
    else
        print("No associated model test found or could not be destroyed.")
    end

    -- Find and destroy associated migration file
    local plural_underscored_model_name = pluralize(underscored_model_name)
    local migration_pattern = "_create_" .. plural_underscored_model_name .. ".lua"
    
    local found_migration_path = nil
    -- Need to list directory and match pattern
    local handle = io.popen("ls db/migrate", "r")
    for line in handle:lines() do
        if line:match(migration_pattern) then
            found_migration_path = "db/migrate/" .. line
            break
        end
    end
    handle:close()

    if found_migration_path then
        print("Destroying associated migration: " .. found_migration_path)
        if os.remove(found_migration_path) then
            print("Associated migration destroyed successfully.")
        else
            print("Error: Could not destroy associated migration.")
        end
    else
        print("No associated migration found for model '" .. model_name .. "'.")
    end
end

local function destroy_migration(migration_name)
    local underscored_migration_name = underscore(migration_name)
    local migration_pattern = "_" .. underscored_migration_name .. ".lua"

    local found_migration_path = nil
    local handle = io.popen("ls db/migrate", "r")
    for line in handle:lines() do
        if line:match(migration_pattern) then
            found_migration_path = "db/migrate/" .. line
            break
        end
    end
    handle:close()

    if found_migration_path then
        print("Destroying migration: " .. found_migration_path)
        if os.remove(found_migration_path) then
            print("Migration '" .. migration_name .. "' destroyed successfully.")
        else
            print("Error: Could not destroy migration '" .. migration_name .. "'.")
        end
    else
        print("Error: Migration '" .. migration_name .. "' not found.")
    end
end

local function show_general_help()
    print("Usage: rio <command> [subcommand] [arguments]")
    print("")
    print("Commands:")
    print("  new <project_name>             - Creates a new Rio project.")
    print("  server [options]               - Starts the Rio web server.")
    print("  console [options]              - Opens an interactive Rio console.")
    print("  runner [options] <code|file>   - Runs Lua code in the context of the Rio application.")
    print("  test [args]                    - Runs Busted tests for the application.")
    print("  routes [options]               - Lists defined routes (supports filtering and expanded view).")
    print("  middleware                     - Lists the application's middleware stack.")
    print("  middleware:create <name>       - Generates a new middleware file.")
    print("  middleware:use <name>          - Enables a middleware in config/middlewares.lua.")
    print("  middleware:unuse <name>        - Disables a middleware in config/middlewares.lua.")
    print("  middleware:rm <name>           - Deletes a local middleware file.")
    print("  about                          - Displays information about the application's environment.")
    print("  stats                          - Displays project statistics (LOC, methods).")
    print("  initializers                   - Lists all application initializers in invocation order.")
    print("  db:<subcommand> [...]          - Database management commands.")
    print("  tmp:<subcommand>               - Temporary files and directories management.")
    print("  mailbox:<subcommand> [...]     - Inbound email management commands.")
    print("  generate <type> <name> [...]   - Generates new resources (controller, model, migration).")
    print("  destroy <type> <name> [...]    - Destroys generated resources (controller, model, migration).")
    print("  help [command]                  - Displays help for a command or general help.")
    print("")
    print("Run 'rio help <command>' or 'rio help <command> [subcommand]' for more information.")
end

local function show_middleware_help()
    print("Usage: rio middleware[:subcommand] [args]")
    print("")
    print("Available subcommands:")
    print("  middleware                           - Lists the application's middleware stack.")
    print("  middleware:create <name>             - Generates a new middleware file in app/middleware/.")
    print("  middleware:use <name>                - Enables a middleware in config/middlewares.lua.")
    print("  middleware:unuse <name>              - Disables a middleware in config/middlewares.lua.")
    print("  middleware:rm <name>                 - Deletes a local middleware file.")
    print("")
    print("Core middleware names: logger, security, cors, auth, static")
    print("Example: rio middleware:create auth_check")
    print("Example: rio middleware:use logger")
    print("Example: rio middleware:unuse logger")
    print("Example: rio middleware:rm auth_check")
end

local function show_generate_help()
    print("Usage: rio generate <type> <name> [options]")
    print("")
    print("Available generators:")
    print("  generate controller <name> [action1 action2...] - Generates a new controller.")
    print("  generate channel <name> - Generates a WebSocket channel.")
    print("  generate model <name> [field1:type field2:type...] - Generates a new model and migration.")
    print("  generate migration <name> [field1:type field2:type...] - Generates a new migration.")
    print("  generate resource <name> [field1:type field2:type...] - Generates a new model, migration, controller, and routes.")
    print("  generate scaffold <name> [field1:type field2:type...] - Generates a full CRUD (model, migration, controller, views, and routes).")
    print("")
    print("Example: rio generate controller Users index show")
    print("Example: rio generate model Product name:string price:integer")
end

local function show_destroy_help()
    print("Usage: rio destroy <type> <name>")
    print("")
    print("Available destroyers:")
    print("  destroy controller <name>                 - Destroys a controller.")
    print("  destroy model <name>                      - Destroys a model and its associated migration.")
    print("  destroy migration <name>                  - Destroys a migration file.")
    print("")
    print("Example: rio destroy controller Users")
    print("Example: rio destroy model Product")
end

local function show_test_help()
    print("Usage: rio test [busted_options]")
    print("  Runs Busted tests for the Rio application.")
    print("  By default, it searches for `_test.lua` files in the `test/` directory.")
    print("  Any additional arguments are passed directly to the `busted` executable.")
    print("")
    print("Example: rio test test/controllers/user_test.lua")
    print("Example: rio test --verbose")
end

local function show_db_help()
    print("Usage: rio db:<subcommand> [options]")
    print("")
    print("Available database subcommands:")
    print("  db:create                            - Creates the database for the current environment.")
    print("  db:drop                              - Drops (deletes) the database for the current environment.")
    print("  db:migrate                           - Runs pending migrations.")
    print("  db:rollback                          - Reverts the last migration.")
    print("  db:status                            - Shows the status of all migrations.")
    print("  db:version                           - Retrieve the current schema version number.")
    print("  db:prepare                           - Run setup if database does not exist, or run migrations.")
    print("  db:setup                             - Create the database, load the schema, and initialize with the seed data.")
    print("  db:reset                             - Drop and recreate the database from its schema for the current environment and load the seed data.")
    print("  db:system:change --to=ADAPTER        - Switch the database adapter (postgresql, mysql, sqlite3).")
    print("  db:seed                              - Runs the seed file (db/seeds.lua).")
    print("  db:seed:replant                      - Truncate tables of each database for current environment and load the seed data.")
    print("")
    print("Example: rio db:create")
    print("Example: rio db:migrate")
    print("Example: rio db:rollback")
    print("Example: rio db:status")
    print("Example: rio db:seed")
    print("Example: rio db:system:change --to=postgresql")
end

local function show_mailbox_help()
    print("Usage: rio mailbox:<subcommand> [args]")
    print("")
    print("Available mailbox subcommands:")
    print("  mailbox:install                      - Installs the Mailbox system (folders and migrations).")
    print("  mailbox:ingress:exim                 - Relay an inbound email from Exim to Rio.")
    print("  mailbox:ingress:postfix              - Relay an inbound email from Postfix to Rio.")
    print("  mailbox:ingress:qmail                - Relay an inbound email from Qmail to Rio.")
    print("")
    print("Example: rio mailbox:install")
    print("Example: cat email.eml | rio mailbox:ingress:postfix")
end

local function show_tmp_help()
    print("Usage: rio tmp:<subcommand>")
    print("")
    print("Available tmp subcommands:")
    print("  tmp:create                           - Creates tmp directories for cache, sockets, and pids.")
    print("  tmp:clear                            - Clears all cache, sockets, and screenshot files.")
    print("  tmp:cache:clear                      - Clears tmp/cache.")
    print("  tmp:sockets:clear                    - Clears tmp/sockets.")
    print("  tmp:screenshots:clear                - Clears tmp/screenshots.")
    print("")
    print("Example: rio tmp:clear")
end

local function show_server_help()
    print("Usage: rio server [options]")
    print("")
    print("Options:")
    print("  -p, --port=PORT                - Binds to the specified port (default: 8080).")
    print("  -b, --binding=IP               - Binds to the specified IP address (default: 0.0.0.0).")
    print("  -e, --environment=ENVIRONMENT  - Sets the server environment (default: development).")
    print("  -d, --daemon                   - Runs the server in the background (daemon mode).")
    print("      --pid=PID_FILE             - Specifies the PID file for daemon mode (default: tmp/pids/server.pid).")
    print("")
    print("Example: rio server -p 3001 -b 127.0.0.1 -e production -d")
end


local function show_runner_help()
    print("Usage: rio runner [options] <code|file>")
    print("")
    print("  Runs Lua code in the context of the Rio application.")
    print("  You can provide a string of Lua code or a path to a Lua file.")
    print("")
    print("Options:")
    print("  -e, --environment=ENVIRONMENT  - Sets the environment (default: development).")
    print("      --skip-executor            - Skip loading models and connecting to the database.")
    print("")
    print("Example: rio runner \"print(User:count())\"")
    print("Example: rio runner scripts/one_off_task.lua")
end


function cli.run(args, framework_lib_path, bin_path) -- Receive framework_lib_path here
    rio_framework_lib_path_global = framework_lib_path -- Store it globally
    rio_bin_path_global = bin_path or "rio"

    local full_command_str = args[1]
    local command
    local subcommand
    local remaining_args = {}
    local has_help_flag = false
    
    -- Debug received arguments (uncomment if needed)
    -- print("DEBUG: cli.run args:", table.concat(args, ", "))

    -- Handle case where no arguments are provided to 'rio'
    if not full_command_str then
        show_general_help()
        return
    end

    local colon_pos = string.find(full_command_str, ":")
    if colon_pos then
        command = string.sub(full_command_str, 1, colon_pos - 1)
        subcommand = string.sub(full_command_str, colon_pos + 1)
    else
        command = full_command_str
    end

    for i = 2, #args do
        if args[i] == "--help" or args[i] == "-h" then
            has_help_flag = true
        else
            table.insert(remaining_args, args[i])
        end
    end

    -- Shift subcommand for 'generate' and 'destroy' if space-separated
    if (command == "generate" or command == "destroy") and not subcommand then
        if #remaining_args > 0 then
            subcommand = table.remove(remaining_args, 1)
        end
    end

    if command == "new" then
        local project_name = nil
        local database_adapter = "none" -- Default to none
        local api_only = false

        local current_remaining_args = {}
        for i = 1, #remaining_args do
            local arg = remaining_args[i]
            if arg:match("^%-%-database=(.+)$") then
                database_adapter = arg:match("^%-%-database=(.+)$")
            elseif arg == "--api" then
                api_only = true
            elseif not project_name then
                project_name = arg
            else
                table.insert(current_remaining_args, arg) -- Collect any other args, though 'new' typically only takes project name
            end
        end

        if has_help_flag then
            print("Usage: rio new <project_name> [--database=adapter] [--api]")
            print("  Creates a new Rio project with a default directory structure.")
            print("  Options:")
            print("    --database=adapter     - Specifies the database adapter (postgresql, mysql, sqlite3, none). Default is none.")
            print("    --api                  - Configure the application for API-only use.")
        elseif not project_name then
            print("Error: 'new' command requires a project name.")
            show_general_help()
            return
        else
            -- Validate database_adapter
            local valid_adapters = {["postgresql"]=true, ["mysql"]=true, ["sqlite3"]=true, ["none"]=true}
            if not valid_adapters[database_adapter] then
                print("Error: Invalid database adapter '" .. database_adapter .. "'. Supported adapters are: postgresql, mysql, sqlite3, none.")
                return
            end
            new_project(project_name, database_adapter, api_only)
        end
    elseif command == "server" then
        if has_help_flag then
            show_server_help()
            return
        else
            local server_options = {}
            local i = 1
            while i <= #remaining_args do
                local arg = remaining_args[i]
                if arg == "-p" or arg == "--port" then
                    i = i + 1
                    server_options.port = remaining_args[i]
                elseif arg:match("^%-%-port=(.+)$") then
                    server_options.port = arg:match("^%-%-port=(.+)$")
                elseif arg == "-b" or arg == "--binding" then
                    i = i + 1
                    server_options.binding = remaining_args[i]
                elseif arg:match("^%-%-binding=(.+)$") then
                    server_options.binding = arg:match("^%-%-binding=(.+)$")
                elseif arg == "-e" or arg == "--environment" then
                    i = i + 1
                    server_options.environment = remaining_args[i]
                elseif arg:match("^%-%-environment=(.+)$") then
                    server_options.environment = arg:match("^%-%-environment=(.+)$")
                elseif arg == "-d" or arg == "--daemon" then
                    server_options.daemon = true
                elseif arg == "--pid" then
                    i = i + 1
                    server_options.pid = remaining_args[i]
                elseif arg:match("^%-%-pid=(.+)$") then
                    server_options.pid = arg:match("^%-%-pid=(.+)$")
                else
                    print("Warning: Unknown server option: " .. arg)
                end
                i = i + 1
            end
            run_server(server_options)
        end
    elseif command == "console" then
        if has_help_flag then
            print("Usage: rio console [options]")
            print("  Opens an interactive Lua console with the Rio application environment loaded.")
            print("  Automatically loads all models into the global scope.")
            print("  Options:")
            print("    -e, --environment=ENV  - Specifies the environment (default: development).")
            print("    -s, --sandbox          - Rollback database changes on exit.")
        else
            local console_options = {}
            local i = 1
            while i <= #remaining_args do
                local arg = remaining_args[i]
                if arg == "-e" or arg == "--environment" then
                    i = i + 1
                    console_options.environment = remaining_args[i]
                elseif arg:match("^%-%-environment=(.+)$") then
                    console_options.environment = arg:match("^%-%-environment=(.+)$")
                elseif arg == "-s" or arg == "--sandbox" then
                    console_options.sandbox = true
                else
                    print("Warning: Unknown console option: " .. arg)
                end
                i = i + 1
            end
            run_console(console_options)
        end
    elseif command == "runner" then
        if has_help_flag then
            show_runner_help()
            return
        else
            local runner_options = {}
            local code_or_file = nil
            local script_args = {}
            local i = 1
            while i <= #remaining_args do
                local arg = remaining_args[i]
                if not code_or_file then
                    if arg == "-e" or arg == "--environment" then
                        i = i + 1
                        runner_options.environment = remaining_args[i]
                    elseif arg:match("^%-%-environment=(.+)$") then
                        runner_options.environment = arg:match("^%-%-environment=(.+)$")
                    elseif arg == "--skip-executor" then
                        runner_options.skip_executor = true
                    elseif arg:match("^%-") then
                        print("Warning: Unknown runner option: " .. arg)
                    else
                        code_or_file = arg
                    end
                else
                    table.insert(script_args, arg)
                end
                i = i + 1
            end
            run_runner(runner_options, code_or_file, script_args)
        end
    elseif command == "routes" then
        if has_help_flag then
            print("Usage: rio routes [options]")
            print("  Lists all defined routes in the application.")
            print("  Options:")
            print("    -c, --controller=NAME   - Filter routes by controller name.")
            print("    -g, --grep=PATTERN      - Filter routes by matching pattern.")
            print("    -E, --expanded          - Display detailed information in expanded format.")
        else
            local routes_options = {}
            local i = 1
            while i <= #remaining_args do
                local arg = remaining_args[i]
                if arg == "-c" or arg == "--controller" then
                    i = i + 1
                    routes_options.controller = remaining_args[i]
                elseif arg:match("^%-%-controller=(.+)$") then
                    routes_options.controller = arg:match("^%-%-controller=(.+)$")
                elseif arg == "-g" or arg == "--grep" then
                    i = i + 1
                    routes_options.grep = remaining_args[i]
                elseif arg:match("^%-%-grep=(.+)$") then
                    routes_options.grep = arg:match("^%-%-grep=(.+)$")
                elseif arg == "-E" or arg == "--expanded" then
                    routes_options.expanded = true
                else
                    print("Warning: Unknown routes option: " .. arg)
                end
                i = i + 1
            end
            run_routes(routes_options)
        end
    elseif command == "middleware" then
        if has_help_flag then
            show_middleware_help()
            return
        end
        if subcommand == "create" then
            if not remaining_args[1] then
                print(colors.red .. "Error: 'middleware:create' requires a name." .. colors.reset)
                show_middleware_help()
                return
            end
            generate_middleware(remaining_args[1])
        elseif subcommand == "use" or subcommand == "add" then
            if not remaining_args[1] then
                print(colors.red .. "Error: 'middleware:use' requires a name." .. colors.reset)
                show_middleware_help()
                return
            end
            if subcommand == "add" then
                print(colors.yellow .. "Warning: 'middleware:add' is deprecated. Please use 'middleware:use' instead." .. colors.reset)
            end
            use_middleware(remaining_args[1])
        elseif subcommand == "unuse" or subcommand == "remove" or subcommand == "delete" then
            if not remaining_args[1] then
                print(colors.red .. "Error: 'middleware:unuse' requires a name." .. colors.reset)
                show_middleware_help()
                return
            end
            if subcommand == "remove" or subcommand == "delete" then
                print(colors.yellow .. "Warning: 'middleware:" .. subcommand .. "' for disabling is deprecated. Please use 'middleware:unuse' instead." .. colors.reset)
                print(colors.yellow .. "If you want to delete the local file, use 'middleware:rm'." .. colors.reset)
            end
            unuse_middleware(remaining_args[1])
        elseif subcommand == "rm" then
            if not remaining_args[1] then
                print(colors.red .. "Error: 'middleware:rm' requires a name." .. colors.reset)
                show_middleware_help()
                return
            end
            rm_middleware(remaining_args[1])
        else
            run_middleware()
        end
    elseif command == "about" then
        if has_help_flag then
            print("Usage: rio about")
            print("  Displays information about the application's environment, including versions and database status.")
        else
            run_about()
        end
    elseif command == "stats" then
        if has_help_flag then
            print("Usage: rio stats")
            print("  Displays project statistics including Lines of Code (LOC) and methods.")
        else
            run_stats()
        end
    elseif command == "initializers" then
        if has_help_flag then
            print("Usage: rio initializers")
            print("  Lists all application initializers in the order they are invoked during boot.")
        else
            run_initializers()
        end
    elseif command == "test" then
        if has_help_flag then
            show_test_help()
            return
        else
            run_tests(remaining_args)
        end
    elseif command == "db" then
        if has_help_flag then
            show_db_help()
            return
        end

        if not subcommand then
            print("Error: 'db' command requires a subcommand (e.g., db:migrate).")
            show_db_help()
            return
        end

        if subcommand == "create" then
            run_db_create()
        elseif subcommand == "drop" then
            run_db_drop()
        elseif subcommand == "migrate" then
            run_db_migrate()
        elseif subcommand == "rollback" then
            run_db_rollback()
        elseif subcommand == "status" then
            run_db_status()
        elseif subcommand == "version" then
            run_db_version()
        elseif subcommand == "seed" then
            run_db_seed()
        elseif subcommand == "seed:replant" then
            run_db_seed_replant()
        elseif subcommand == "cache:clear" then
            print("Clearing database metadata cache...")
            -- Try to use the framework's cache system if possible
            local ok, rio = pcall(require, "rio")
            if ok then
                local app = rio.new()
                app.cache:clear()
                print("✓ Database cache cleared.")
            else
                -- Fallback manual
                os.execute("rm -f tmp/cache/*.cache")
                print("✓ Cache directory cleared manually.")
            end
        elseif subcommand == "setup" then
            run_db_setup()
        elseif subcommand == "reset" then
            run_db_reset()
        elseif subcommand == "prepare" then
            run_db_prepare()
        elseif subcommand == "system:change" then
            run_db_system_change(remaining_args)
        else
            print("Error: Unknown 'db' subcommand '" .. subcommand .. "'")
            show_db_help()
        end
    elseif command == "tmp" then
        if has_help_flag then
            show_tmp_help()
            return
        end

        if not subcommand then
            print("Error: 'tmp' command requires a subcommand (e.g., tmp:clear).")
            show_tmp_help()
            return
        end

        run_tmp(subcommand, remaining_args)
    elseif command == "mailbox" then
        if subcommand == "install" then
            run_mailbox_install()
        elseif subcommand == "ingress:exim" then
            run_mailbox_ingress("Exim")
        elseif subcommand == "ingress:postfix" then
            run_mailbox_ingress("Postfix")
        elseif subcommand == "ingress:qmail" then
            run_mailbox_ingress("Qmail")
        else
            print("Usage: rio mailbox:install | mailbox:ingress:<provider>")
        end
    elseif command == "scaffold" then
        if has_help_flag then
            show_generate_help()
            return
        end
        local generator_name = remaining_args[1]
        local generator_params = {}
        local api_only_flag = false
        for i = 2, #remaining_args do
            if remaining_args[i] == "--api" then
                api_only_flag = true
            else
                table.insert(generator_params, remaining_args[i])
            end
        end
        if not generator_name then
            print("Error: 'scaffold' command requires a name.")
            show_generate_help()
            return
        end
        local api_only = api_only_flag or is_api_only()
        generate_scaffold(generator_name, generator_params, api_only)
    elseif command == "resource" then
        if has_help_flag then
            show_generate_help()
            return
        end
        local generator_name = remaining_args[1]
        local generator_params = {}
        local api_only_flag = false
        for i = 2, #remaining_args do
            if remaining_args[i] == "--api" then
                api_only_flag = true
            else
                table.insert(generator_params, remaining_args[i])
            end
        end
        if not generator_name then
            print("Error: 'resource' command requires a name.")
            show_generate_help()
            return
        end
        local api_only = api_only_flag or is_api_only()
        generate_resource(generator_name, generator_params, api_only)
    elseif command == "generate" then
        if has_help_flag then
            show_generate_help()
            return
        end
        local generator_type = subcommand
        local generator_name = remaining_args[1]
        local generator_params = {}
        local api_only_flag = false
        for i = 2, #remaining_args do
            if remaining_args[i] == "--api" then
                api_only_flag = true
            else
                table.insert(generator_params, remaining_args[i])
            end
        end

        if not generator_type then
            print("Error: 'generate' command requires a generator type (e.g., generate controller).")
            show_generate_help()
            return
        end
        if not generator_name then
            print("Error: 'generate " .. generator_type .. "' command requires a name.")
            show_generate_help()
            return
        end

        local api_only = api_only_flag or is_api_only()

        if generator_type == "controller" then
            generate_controller(generator_name, generator_params, api_only)
        elseif generator_type == "channel" then
            generate_channel(generator_name)
        elseif generator_type == "model" then
            generate_model(generator_name, generator_params)
        elseif generator_type == "migration" then
            generate_migration(generator_name, generator_params)
        elseif generator_type == "resource" then
            generate_resource(generator_name, generator_params, api_only)
        elseif generator_type == "scaffold" then
            generate_scaffold(generator_name, generator_params, api_only)
        else
            print("Error: Unknown generator type '" .. generator_type .. "'")
            show_generate_help()
        end
    elseif command == "destroy" then
        if has_help_flag then
            show_destroy_help()
            return
        end
        local destroyer_type = subcommand
        local destroyer_name = remaining_args[1]

        if not destroyer_type then
            print("Error: 'destroy' command requires a destroyer type (e.g., destroy controller).")
            show_destroy_help()
            return
        end
        if not destroyer_name then
            print("Error: 'destroy " .. destroyer_type .. "' command requires a name.")
            show_destroy_help()
            return
        end

        if destroyer_type == "controller" then
            destroy_controller(destroyer_name)
        elseif destroyer_type == "model" then
            destroy_model(destroyer_name)
        elseif destroyer_type == "migration" then
            destroy_migration(destroyer_name)
        else
            print("Error: Unknown destroyer type '" .. destroyer_type .. "'")
            show_destroy_help()
        end
    elseif command == "help" or command == nil then
        if full_command_str == "help" and colon_pos then -- help for subcommand like "help db:migrate"
            local help_command = command
            local help_subcommand = subcommand
            if help_command == "db" then
                show_db_help()
            elseif help_command == "mailbox" then
                show_mailbox_help()
            elseif help_command == "generate" then
                show_generate_help()
            elseif help_command == "destroy" then
                show_destroy_help()
            elseif help_command == "server" then
                show_server_help()
            else
                print("Error: No specific help for '" .. help_command .. ":" .. help_subcommand .. "'")
                show_general_help()
            end
        elseif full_command_str == "help" then -- help for top-level command like "help db"
            local help_command = remaining_args[1] -- The command they want help for
            if help_command == "generate" then
                show_generate_help()
            elseif help_command == "destroy" then
                show_destroy_help()
            elseif help_command == "new" then
                print("Usage: rio new <project_name>")
                print("  Creates a new Rio project with a default directory structure.")
            elseif help_command == "server" then
                show_server_help()
            elseif help_command == "runner" then
                show_runner_help()
            elseif help_command == "console" then
                print("Usage: rio console [options]")
                print("  Opens an interactive Lua console with the Rio application environment loaded.")
                print("  Automatically loads all models into the global scope.")
                print("  Options:")
                print("    -e, --environment=ENV  - Specifies the environment (default: development).")
                print("    -s, --sandbox          - Rollback all database changes on exit.")
                print("  Objects available:")
                print("    app                    - The application instance for route testing.")
                print("    helper                 - View utilities and helpers.")
                print("    <ModelName>            - All your application models.")
            elseif help_command == "test" then
                show_test_help()
            elseif help_command == "routes" then
                print("Usage: rio routes [options]")
                print("  Lists all defined routes in the application, including HTTP methods, URI patterns, and handler source location.")
                print("  Options:")
                print("    -c, --controller=NAME   - Filter routes by controller name.")
                print("    -g, --grep=PATTERN      - Filter routes by matching pattern.")
                print("    -E, --expanded          - Display detailed information in expanded format.")
            elseif help_command == "middleware" then
                show_middleware_help()
            elseif help_command == "about" then
                print("Usage: rio about")
                print("  Displays detailed information about the application's environment, versions, and database status.")
            elseif help_command == "stats" then
                print("Usage: rio stats")
                print("  Displays project statistics including Lines of Code (LOC) and methods/functions per category.")
            elseif help_command == "initializers" then
                print("Usage: rio initializers")
                print("  Lists all application initializers defined in config/initializers/ in their invocation order.")
            elseif help_command == "db" then
                show_db_help()
            elseif help_command == "tmp" then
                show_tmp_help()
            elseif help_command == "mailbox" then
                show_mailbox_help()
            elseif not help_command then
                show_general_help()
            else
                print("Error: No help available for command '" .. tostring(help_command) .. "'")
                show_general_help()
            end
        else -- just "rio help" or invalid. Fall through to general help.
            show_general_help()
        end
    else
        print("Error: Unknown command '" .. command .. "'")
        show_general_help()
    end
end

return cli
