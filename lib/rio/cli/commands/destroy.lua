-- rio/lib/rio/cli/commands/destroy.lua

local Command = require("rio.cli.command")
local string_utils = require("rio.utils.string")
local files = require("rio.cli.files")

local M = {}
local underscore = string_utils.underscore
local pluralize = string_utils.pluralize

local DESTROY_HANDLERS = {
    controller = "controller",
    model = "model",
    migration = "migration"
}

function M.controller(controller_name)
    local path = "app/controllers/" .. underscore(controller_name) .. "_controller.lua"
    print("Destroying controller: " .. path)
    if os.remove(path) then
        print("Controller '" .. controller_name .. "' destroyed successfully.")
    else
        print("Error: Could not destroy controller '" .. controller_name .. "'. File not found or permission denied.")
    end

    local test_path = "test/controllers/" .. underscore(controller_name) .. "_test.lua"
    print("Destroying controller test: " .. test_path)
    if os.remove(test_path) then
        print("Controller test destroyed successfully.")
    else
        print("No associated controller test found or could not be destroyed.")
    end
end

function M.model(model_name)
    local underscored_model_name = underscore(model_name)
    local model_path = "app/models/" .. underscored_model_name .. ".lua"
    print("Destroying model: " .. model_path)
    if os.remove(model_path) then
        print("Model '" .. model_name .. "' destroyed successfully.")
    else
        print("Error: Could not destroy model '" .. model_name .. "'. File not found or permission denied.")
    end

    local test_path = "test/models/" .. underscored_model_name .. "_test.lua"
    print("Destroying model test: " .. test_path)
    if os.remove(test_path) then
        print("Model test destroyed successfully.")
    else
        print("No associated model test found or could not be destroyed.")
    end

    local migration_pattern = "_create_" .. pluralize(underscored_model_name) .. ".lua"
    local found_migration_path = nil
    for _, path in ipairs(files.list("db/migrate", { mode = "file" })) do
        if files.basename(path):match(migration_pattern) then
            found_migration_path = path
            break
        end
    end

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

function M.migration(migration_name)
    local migration_pattern = "_" .. underscore(migration_name) .. ".lua"
    local found_migration_path = nil
    for _, path in ipairs(files.list("db/migrate", { mode = "file" })) do
        if files.basename(path):match(migration_pattern) then
            found_migration_path = path
            break
        end
    end

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

function M.command()
    return Command.new({
        name = "destroy",
        help = function(ctx)
            ctx.show_destroy_help()
        end,
        run = function(ctx, invocation)
            local destroyer_type = invocation.subcommand
            local destroyer_name = invocation.args[1]

            if not destroyer_type then
                ctx.ui.status("Resource destruction", false, "Destroyer type is required")
                ctx.show_destroy_help()
                return true
            end
            if not destroyer_name then
                ctx.ui.status("Resource destruction", false, "'" .. destroyer_type .. "' requires a name")
                ctx.show_destroy_help()
                return true
            end

            local handler = M[DESTROY_HANDLERS[destroyer_type] or ""]
            if not handler then
                ctx.ui.status("Resource destruction", false, "Unknown destroyer type '" .. destroyer_type .. "'")
                ctx.show_destroy_help()
                return true
            end

            handler(destroyer_name)
            return true
        end
    })
end

return M
