-- rio/lib/rio/cli/generators/core.lua
-- Shared implementation for Rio resource generators.

local M = {}

function M.new(ctx)
    local ui = ctx.ui
    local colors = ctx.colors
    local camel_case = ctx.camel_case
    local underscore = ctx.underscore
    local pluralize = ctx.pluralize
    local parse_fields = ctx.parse_fields
    local create_dir_if_not_exists = ctx.create_dir_if_not_exists
    local write_file_content = ctx.write_file_content

    -- Generator functions
    local function generate_channel(channel_name)
        local underscored_name = underscore(channel_name)
        local channel_path = "app/channels/" .. underscored_name .. "_channel.lua"
        local camel_name = camel_case(channel_name)
        
        create_dir_if_not_exists("app/channels")
        ui.alert_title("primary", "generate", "WebSocket channel: " .. channel_path)
        
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
                ui.info("/cable/" .. underscored_name, "WS ROUTE")
            end
        end
    end
    
    local function generate_controller(controller_name, actions, api_only)
        local underscored_name = underscore(controller_name:gsub("::", "/"))
        local path = "app/controllers/" .. underscored_name .. "_controller.lua"
        
        -- Ensure directory exists
        local dir = path:match("(.+)/")
        if dir then create_dir_if_not_exists(dir) end
        
        ui.alert_title("primary", "generate", "controller: " .. path .. (api_only and " (API-only)" or ""))
    
        local content = {}
        local camelControllerName = camel_case(controller_name:match("([^:]+)$") or controller_name)
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
    
        -- Generate test file for the controller
        local test_path = "test/controllers/" .. underscored_name .. "_test.lua"
        local test_dir = test_path:match("(.+)/")
        if test_dir then create_dir_if_not_exists(test_dir) end
        
        ui.alert_title("secondary", "generate", "controller test: " .. test_path)
        local test_content = {}
        table.insert(test_content, "local " .. camelControllerName .. "Controller = require(\"app.controllers." .. underscored_name .. "_controller\")")
    
        table.insert(test_content, "")
        table.insert(test_content, "describe(\"" .. camelControllerName .. "Controller\", function()")
        table.insert(test_content, "    it(\"should exist\", function()")
        table.insert(test_content, "        assert.is_table(" .. camelControllerName .. "Controller)")
        table.insert(test_content, "    end)")
        table.insert(test_content, "end)")
    
        write_file_content(test_path, table.concat(test_content, "\n"))
        ui.success("Controller '" .. controller_name .. "' generated successfully.")
    end
    
    local function generate_migration(migration_name, fields, table_name_hint)
        -- Check if migration already exists
        local underscored_name = underscore(migration_name)
        for _, existing in ipairs(require("rio.cli.files").list("db/migrate", { mode = "file", pattern = "_" .. underscored_name .. "%.lua$" })) do
                ui.warn("Migration '" .. migration_name .. "' already exists at " .. existing)
                return existing:match("db/migrate/(.+)")
        end
    
        local timestamp = os.date("%Y%m%d%H%M%S")
        local file_name = timestamp .. "_" .. underscore(migration_name) .. ".lua"
        local path = "db/migrate/" .. file_name
        ui.alert_title("primary", "generate", "migration: " .. path)
    
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
        ui.success("Migration '" .. migration_name .. "' generated successfully.")
    end
    
    local function generate_model(model_name, fields)
        -- Support namespaced models for require/class name but use singular path for file
        local resource_pure = model_name:match("([^:]+)$") or model_name
        local path = "app/models/" .. underscore(resource_pure) .. ".lua"
        ui.alert_title("primary", "generate", "model: " .. path)
    
        local content = {}
        local camelModelName = camel_case(resource_pure)
        local pluralTableName = pluralize(underscore(resource_pure))
    
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
                            target_name = underscore(resource_pure)
                        end
    
                        local inverse_rel = string.format("%s:%s(\"%s\")", camel_case(name), rel_type, target_name)
                        
                        -- Only inject if not already there
                        if not parent_content:find(target_name) then
                            local new_parent_content = parent_content:gsub("(.-)return%s+([%w_]+)%s*$", "%1" .. inverse_rel .. "\n\nreturn %2")
                            if new_parent_content ~= parent_content then
                                write_file_content(parent_model_path, new_parent_content)
                                ui.info(inverse_rel, "RELATION")
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
                                    ui.info(through_rel, "M:N RELATION")
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
    
        -- Generate test file for the model
        local test_path = "test/models/" .. underscore(resource_pure) .. "_test.lua"
        ui.alert_title("secondary", "generate", "model test: " .. test_path)
        local test_content = {}
        table.insert(test_content, "local " .. camelModelName .. " = require(\"app.models." .. underscore(resource_pure) .. "\")")
    
        table.insert(test_content, "")
        table.insert(test_content, "describe(\"" .. camelModelName .. " Model\", function()")
        table.insert(test_content, "    it(\"should exist\", function()")
        table.insert(test_content, "        assert.is_table(" .. camelModelName .. ")")
        table.insert(test_content, "    end)")
        table.insert(test_content, "end)")
    
        write_file_content(test_path, table.concat(test_content, "\n"))
        ui.success("Model '" .. resource_pure .. "' generated successfully.")
        
        -- Also generate a migration for creating the table
        local migration_full_name = "Create" .. camel_case(pluralize(resource_pure))
        generate_migration(migration_full_name, fields, underscore(resource_pure)) -- Pass singular underscored model name for correct pluralization
    end
    
    local function generate_scaffold_controller(resource_name, fields)
        local underscored_resource = underscore(resource_name:gsub("::", "/"))
        local singular_name = underscored_resource:match("([^/]+)$") or underscored_resource
        local plural_name = pluralize(singular_name)
        
        local controller_dir = underscored_resource:match("(.+)/")
        local controller_path = "app/controllers/" .. (controller_dir and (controller_dir .. "/") or "") .. plural_name .. "_controller.lua"
        
        local controller_class_name = camel_case(plural_name) .. "Controller"
        local model_name = camel_case(singular_name)
        
        if controller_dir then create_dir_if_not_exists("app/controllers/" .. controller_dir) end
        
        print("Generating scaffold controller: " .. controller_path)
    
        local content = {}
        table.insert(content, "local " .. model_name .. " = require(\"app.models." .. underscore(resource_name:match("([^:]+)$") or resource_name) .. "\")")
        table.insert(content, "local " .. controller_class_name .. " = {}")
        table.insert(content, "")
    
        -- index
        table.insert(content, "function " .. controller_class_name .. ":index(ctx)")
        table.insert(content, "    local items = " .. model_name .. ":all()")
        table.insert(content, "    return ctx:view(\"" .. (controller_dir and (controller_dir .. "/") or "") .. plural_name .. "/index\", { " .. plural_name .. " = items })")
        table.insert(content, "end")
    
        -- show
        table.insert(content, "function " .. controller_class_name .. ":show(ctx)")
        table.insert(content, "    local item = " .. model_name .. ":find(ctx.params.id)")
        table.insert(content, "    if not item then return ctx:text(\"Not Found\", 404) end")
        table.insert(content, "    return ctx:view(\"" .. (controller_dir and (controller_dir .. "/") or "") .. plural_name .. "/show\", { " .. singular_name .. " = item })")
        table.insert(content, "end")
    
        -- new
        table.insert(content, "function " .. controller_class_name .. ":new(ctx)")
        table.insert(content, "    return ctx:view(\"" .. (controller_dir and (controller_dir .. "/") or "") .. plural_name .. "/new\", { " .. singular_name .. " = " .. model_name .. ":new() })")
        table.insert(content, "end")
    
        -- edit
        table.insert(content, "function " .. controller_class_name .. ":edit(ctx)")
        table.insert(content, "    local item = " .. model_name .. ":find(ctx.params.id)")
        table.insert(content, "    if not item then return ctx:text(\"Not Found\", 404) end")
        table.insert(content, "    return ctx:view(\"" .. (controller_dir and (controller_dir .. "/") or "") .. plural_name .. "/edit\", { " .. singular_name .. " = item })")
        table.insert(content, "end")
    
        -- create
        table.insert(content, "function " .. controller_class_name .. ":create(ctx)")
        table.insert(content, "    local item = " .. model_name .. ":new(ctx.body)")
        table.insert(content, "    if item:save() then")
        table.insert(content, "        return ctx:redirect(\"/" .. (controller_dir and (controller_dir .. "/") or "") .. plural_name .. "/\" .. item.id .. \"?notice=" .. camel_case(singular_name) .. " was successfully created.\")")
        table.insert(content, "    else")
        table.insert(content, "        return ctx:view(\"" .. (controller_dir and (controller_dir .. "/") or "") .. plural_name .. "/new\", { " .. singular_name .. " = item, alert = \"Error creating " .. singular_name .. "\" })")
        table.insert(content, "    end")
        table.insert(content, "end")
    
        -- update
        table.insert(content, "function " .. controller_class_name .. ":update(ctx)")
        table.insert(content, "    local item = " .. model_name .. ":find(ctx.params.id)")
        table.insert(content, "    if not item then return ctx:text(\"Not Found\", 404) end")
        table.insert(content, "    if item:update(ctx.body) then")
        table.insert(content, "        return ctx:redirect(\"/" .. (controller_dir and (controller_dir .. "/") or "") .. plural_name .. "/\" .. item.id .. \"?notice=" .. camel_case(singular_name) .. " was successfully updated.\")")
        table.insert(content, "    else")
        table.insert(content, "        return ctx:view(\"" .. (controller_dir and (controller_dir .. "/") or "") .. plural_name .. "/edit\", { " .. singular_name .. " = item, alert = \"Error updating " .. singular_name .. "\" })")
        table.insert(content, "    end")
        table.insert(content, "end")
    
        -- destroy
        table.insert(content, "function " .. controller_class_name .. ":destroy(ctx)")
        table.insert(content, "    local item = " .. model_name .. ":find(ctx.params.id)")
        table.insert(content, "    if item then ")
        table.insert(content, "        item:delete()")
        table.insert(content, "        return ctx:redirect(\"/" .. (controller_dir and (controller_dir .. "/") or "") .. plural_name .. "?notice=" .. camel_case(singular_name) .. " was successfully destroyed.\")")
        table.insert(content, "    end")
        table.insert(content, "    return ctx:redirect(\"/" .. (controller_dir and (controller_dir .. "/") or "") .. plural_name .. "\")")
        table.insert(content, "end")
    
        table.insert(content, "return " .. controller_class_name)
    
        write_file_content(controller_path, table.concat(content, "\n"))
    end
    
    local function generate_api_scaffold_controller(resource_name, fields)
        local underscored_resource = underscore(resource_name:gsub("::", "/"))
        local singular_name = underscored_resource:match("([^/]+)$") or underscored_resource
        local plural_name = pluralize(singular_name)
        
        local controller_dir = underscored_resource:match("(.+)/")
        local controller_path = "app/controllers/" .. (controller_dir and (controller_dir .. "/") or "") .. plural_name .. "_controller.lua"
        
        local controller_class_name = camel_case(plural_name) .. "Controller"
        local model_name = camel_case(singular_name)
        
        if controller_dir then create_dir_if_not_exists("app/controllers/" .. controller_dir) end
        
        print("Generating API scaffold controller: " .. controller_path)
    
        local content = {}
        table.insert(content, "local " .. model_name .. " = require(\"app.models." .. underscore(resource_name:match("([^:]+)$") or resource_name) .. "\")")
        table.insert(content, "local " .. controller_class_name .. " = {}")
        table.insert(content, "")
    
        -- index
        table.insert(content, "function " .. controller_class_name .. ":index(ctx)")
        table.insert(content, "    local items = " .. model_name .. ":all()")
        table.insert(content, "    return ctx:json(items)")
        table.insert(content, "end")
    
        -- show
        table.insert(content, "function " .. controller_class_name .. ":show(ctx)")
        table.insert(content, "    local item = " .. model_name .. ":find(ctx.params.id)")
        table.insert(content, "    if not item then return ctx:json({ error = \"Not Found\" }, 404) end")
        table.insert(content, "    return ctx:json(item)")
        table.insert(content, "end")
    
        -- create
        table.insert(content, "function " .. controller_class_name .. ":create(ctx)")
        table.insert(content, "    local item = " .. model_name .. ":new(ctx.body)")
        table.insert(content, "    if item:save() then")
        table.insert(content, "        return ctx:json(item, 201)")
        table.insert(content, "    else")
        table.insert(content, "        return ctx:json({ errors = item.errors:all() }, 422)")
        table.insert(content, "    end")
        table.insert(content, "end")
    
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
    
        -- destroy
        table.insert(content, "function " .. controller_class_name .. ":destroy(ctx)")
        table.insert(content, "    local item = " .. model_name .. ":find(ctx.params.id)")
        table.insert(content, "    if item then ")
        table.insert(content, "        item:delete()")
        table.insert(content, "        return ctx:json({ message = \"" .. model_name .. " was successfully destroyed.\" })")
        table.insert(content, "    end")
        table.insert(content, "    return ctx:json({ error = \"Not Found\" }, 404)")
        table.insert(content, "end")
    
        table.insert(content, "return " .. controller_class_name)
    
        write_file_content(controller_path, table.concat(content, "\n"))
    end
    
    local function generate_scaffold_views(resource_name, fields)
        local underscored_resource = underscore(resource_name:gsub("::", "/"))
        local singular_name = underscored_resource:match("([^/]+)$") or underscored_resource
        local plural_name = pluralize(singular_name)
        local resource_path = (underscored_resource:match("(.+)/") and (underscored_resource:match("(.+)/") .. "/") or "") .. plural_name
        
        local views_dir = "app/views/" .. resource_path
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
        table.insert(index_content, "      <td style=\"padding: 12px;\"><a href=\"/" .. resource_path .. "/<%= item.id %>\">Show</a></td>")
        table.insert(index_content, "      <td style=\"padding: 12px;\"><a href=\"/" .. resource_path .. "/<%= item.id %>/edit\">Edit</a></td>")
        table.insert(index_content, "      <td style=\"padding: 12px;\"><form action=\"/" .. resource_path .. "/<%= item.id %>\" method=\"POST\" style=\"display:inline\"><input type=\"hidden\" name=\"_method\" value=\"DELETE\"><button type=\"submit\" style=\"background: none; border: none; color: #dc3545; cursor: pointer; text-decoration: underline; padding: 0;\" onclick=\"return confirm('Are you sure?')\">Destroy</button></form></td>")
        table.insert(index_content, "    </tr>")
        table.insert(index_content, "    <% end %>")
        table.insert(index_content, "  </tbody>")
        table.insert(index_content, "</table>")
        table.insert(index_content, "<br>")
        table.insert(index_content, "<a href=\"/" .. resource_path .. "/new\" style=\"display: inline-block; background-color: #007bff; color: white; padding: 8px 16px; border-radius: 4px; text-decoration: none;\">New " .. camel_case(singular_name) .. "</a>")
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
        table.insert(show_content, "  <a href=\"/" .. resource_path .. "/<%= " .. singular_name .. ".id %>/edit\">Edit</a> |")
        table.insert(show_content, "  <a href=\"/" .. resource_path .. "\">Back to " .. plural_name .. "</a>")
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
            "<form action=\"/" .. resource_path .. "\" method=\"POST\" style=\"background-color: #f8f9fa; padding: 20px; border-radius: 8px; border: 1px solid #dee2e6;\">"
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
        table.insert(new_content, "<br><a href=\"/" .. resource_path .. "\">Back to " .. plural_name .. "</a>")
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
            "<form action=\"/" .. resource_path .. "/<%= " .. singular_name .. ".id %>\" method=\"POST\" style=\"background-color: #f8f9fa; padding: 20px; border-radius: 8px; border: 1px solid #dee2e6;\">",
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
        table.insert(edit_content, "<br><div style=\"margin-top: 10px;\"><a href=\"/" .. resource_path .. "/<%= " .. singular_name .. ".id %>\">Show</a> | " ..
        "<a href=\"/" .. resource_path .. "\">Back to " .. plural_name .. "</a></div>")
        write_file_content(views_dir .. "/edit.etl", table.concat(edit_content, "\n"))
    
        print("Scaffold views for '" .. plural_name .. "' generated successfully.")
    end
    
    local function generate_scaffold_tests(resource_name, fields, api_only)
        local underscored_resource = underscore(resource_name:gsub("::", "/"))
        local singular_name = underscored_resource:match("([^/]+)$") or underscored_resource
        local plural_name = pluralize(singular_name)
        
        local test_dir = underscored_resource:match("(.+)/")
        local path = "test/controllers/" .. (test_dir and (test_dir .. "/") or "") .. plural_name .. "_test.lua"
        if test_dir then create_dir_if_not_exists("test/controllers/" .. test_dir) end
        
        local controller_class_name = camel_case(plural_name) .. "Controller"
        local model_name = camel_case(singular_name)
        
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
    
        add("local " .. model_name .. " = require(\"app.models." .. underscore(resource_name:match("([^:]+)$") or resource_name) .. "\")")
        add("local " .. controller_class_name .. " = require(\"app.controllers." .. underscored_resource .. "_controller\")")
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
            add("        assert.equals(\"" .. (test_dir and (test_dir .. "/") or "") .. plural_name .. "/index\", res.path)")
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
            add("        assert.equals(\"" .. (test_dir and (test_dir .. "/") or "") .. plural_name .. "/show\", res.path)")
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
        local underscored_resource = underscore(resource_name:gsub("::", "/"))
        local singular_name = underscored_resource:match("([^/]+)$") or underscored_resource
        local plural_name = pluralize(singular_name)
        local namespace = resource_name:match("^(.+)::")
        local controller_name = (namespace and (namespace .. "::") or "") .. camel_case(plural_name)
        
        local routes_path = "config/routes.lua"
        local f = io.open(routes_path, "r")
        if f then
            local content = f:read("*a")
            f:close()
            
            local resource_line
            if namespace then
                resource_line = "    app:resources(\"" .. (underscore(namespace) .. "/" .. plural_name) .. "\", \"" .. controller_name .. "\")"
            else
                resource_line = "    app:resources(\"" .. plural_name .. "\")"
            end
    
            if not content:find(resource_line, 1, true) then
                local modified_content = content:gsub("(.-)end%s*$", "%1" .. resource_line .. "\nend")
                write_file_content(routes_path, modified_content)
                print("Resource routes added to config/routes.lua.")
            end
        end
    end
    
    local function generate_resource(resource_name, fields, api_only)
        local resource_pure = resource_name:match("([^:]+)$") or resource_name
        local singular_name = underscore(resource_pure)
        local plural_name = pluralize(singular_name)
    
        print("Generating resource: " .. resource_name .. (api_only and " (API-only)" or ""))
    
        -- 1. Generate Model (this also generates migration and model test)
        generate_model(resource_name, fields)
    
        -- 2. Generate Controller (pluralized name)
        local namespace = resource_name:match("^(.+)::")
        local controller_full_name = (namespace and (namespace .. "::") or "") .. camel_case(plural_name)
        generate_controller(controller_full_name, {}, api_only) -- empty actions
    
        -- 3. Add routes to config/routes.lua
        print("Updating config/routes.lua with resource routes...")
        local routes_path = "config/routes.lua"
        local f = io.open(routes_path, "r")
        if f then
            local content = f:read("*a")
            f:close()
    
            local resource_route
            if namespace then
                 resource_route = "app:resources(\"" .. (underscore(namespace) .. "/" .. plural_name) .. "\", \"" .. controller_full_name .. "\")"
            else
                 resource_route = "app:resources(\"" .. plural_name .. "\")"
            end
    
            -- Check if resource already exists in routes
            if content:find(resource_route, 1, true) then
                print("Notice: Resource routes for '" .. plural_name .. "' already exist in config/routes.lua. Skipping.")
            else
                -- Insert before the last 'end' of the return function(app)
                local modified_content = content:gsub("(.-)end%s*$", "%1    " .. resource_route .. "\nend")
                
                if modified_content ~= content then
                    write_file_content(routes_path, modified_content)
                    print("Resource routes added to config/routes.lua.")
                else
                    print("Warning: Could not automatically update config/routes.lua. Please add '" .. resource_route .. "' manually.")
                end
            end
        else
            print("Error: Could not find config/routes.lua.")
        end
    end
    
    return {
        channel = generate_channel,
        controller = generate_controller,
        migration = generate_migration,
        model = generate_model,
        resource = generate_resource,
        scaffold = generate_scaffold
    }
end

return M
