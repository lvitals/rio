-- rio/lib/rio/cli/generator_service.lua

local string_utils = require("rio.utils.string")
local generator_fields = require("rio.cli.generators.fields")

local M = {}
local Service = {}
Service.__index = Service

function M.new(ctx)
    ctx = ctx or {}
    assert(ctx.ui, "generator service requires ui")
    assert(ctx.colors, "generator service requires colors")
    assert(ctx.files, "generator service requires files")
    return setmetatable(ctx, Service)
end

function Service:create_dir_if_not_exists(path)
    self.files.ensure_dir(path)
end

function Service:write_file_content(path, content)
    local ok = self.files.write(path, content)
    if not ok then
        print("Error: Could not open file for writing: " .. path)
    end
end

function Service:file_exists(path)
    return self.files.exists(path)
end

function Service:is_api_only()
    local ok, app_config = pcall(require, "config.application")
    if ok and type(app_config) == "table" then
        return app_config.api_only == true
    end
    return false
end

function Service:core()
    if not self.generator_core then
        self.generator_core = require("rio.cli.generators.core").new({
            ui = self.ui,
            colors = self.colors,
            camel_case = string_utils.camel_case,
            underscore = string_utils.underscore,
            pluralize = string_utils.pluralize,
            parse_fields = generator_fields.parse,
            create_dir_if_not_exists = function(path)
                return self:create_dir_if_not_exists(path)
            end,
            write_file_content = function(path, content)
                return self:write_file_content(path, content)
            end
        })
    end
    return self.generator_core
end

function Service:context()
    return {
        camel_case = string_utils.camel_case,
        create_dir_if_not_exists = function(path)
            return self:create_dir_if_not_exists(path)
        end,
        write_file_content = function(path, content)
            return self:write_file_content(path, content)
        end,
        file_exists = function(path)
            return self:file_exists(path)
        end,
        is_api_only = function()
            return self:is_api_only()
        end,
        generate_channel = function(channel_name)
            return self:core().channel(channel_name)
        end,
        generate_controller = function(controller_name, actions, api_only)
            return self:core().controller(controller_name, actions, api_only)
        end,
        generate_model = function(model_name, fields)
            return self:core().model(model_name, fields)
        end,
        generate_migration = function(migration_name, fields, table_name_hint)
            return self:core().migration(migration_name, fields, table_name_hint)
        end,
        generate_resource = function(resource_name, fields, api_only)
            return self:core().resource(resource_name, fields, api_only)
        end,
        generate_scaffold = function(resource_name, fields, api_only)
            return self:core().scaffold(resource_name, fields, api_only)
        end
    }
end

return M
