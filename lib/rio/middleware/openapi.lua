-- lib/rio/middleware/openapi.lua
-- Auto-documenting OpenAPI Plugin for Rio

local compat = require("rio.utils.compat")

local function rio_to_openapi_path(path)
    local openapi_path = path:gsub(":(%w+)", "{%1}")
    return openapi_path == "" and "/" or openapi_path
end

local function get_path_params(path)
    local params = {}
    for param in path:gmatch(":(%w+)") do
        table.insert(params, {
            name = param,
            ["in"] = "path",
            required = true,
            schema = { type = "string" }
        })
    end
    return params
end

local M = {}

function M.create(app, options)
    options = options or {}
    local docs_path = options.path or app.config.openapi_path or "/docs"
    local json_path = options.json_path or app.config.openapi_json_path or "/openapi.json"
    
    -- Restored: Support for both standard JSON and JSON:API
    local available_formats = {
        ["application/json"] = { schema = { type = "object" } },
        ["application/vnd.api+json"] = { schema = { type = "object" } }
    }

    local function build_spec()
        local spec = {
            openapi = "3.1.0",
            info = {
                title = app.config.title or app.config.app_name or "Rio Auto-API",
                version = app.config.api_version or app.config.version or "1.0.0",
                description = app.config.description or "Auto-generated documentation via route reflection."
            },
            paths = {},
            tags = {},
            components = { 
                schemas = {}, 
                securitySchemes = {
                    bearerAuth = { type = "http", scheme = "bearer", jwtFormat = "JWT" }
                }
            }
        }

        local tags_found = {}

        if app.router and app.router.routes then
            for method, routes in pairs(app.router.routes) do
                local method_lower = method:lower()
                for _, route in ipairs(routes) do
                    if route.path ~= docs_path and route.path ~= json_path then
                        local path = rio_to_openapi_path(route.path)
                        spec.paths[path] = spec.paths[path] or {}
                        
                        -- REFRECTION: Extract METADATA from Controller (_openapi)
                        local custom_meta = nil
                        local controller_name = nil
                        if app.routes_meta and app.routes_meta[route.handler] then
                            local meta = app.routes_meta[route.handler]
                            controller_name = meta.controller
                            local action_name = meta.action

                            -- Attempt to load controller to find openapi table
                            local controller_module = controller_name:lower()
                            if not controller_module:find("_controller$") then
                                controller_module = controller_module .. "_controller"
                            end

                            local ok, controller = pcall(require, "app.controllers." .. controller_module)
                            if ok and type(controller) == "table" and controller.openapi then
                                custom_meta = controller.openapi[action_name]
                            end
                        end

                        -- Grouping: Prefer Controller name, fallback to path segment
                        local tag = "default"
                        if controller_name then
                            tag = controller_name:lower():gsub("_?controller$", ""):gsub("^app%.controllers%.", "")
                        else
                            local first_segment = route.path:match("/([^/:]+)")
                            if first_segment then tag = first_segment:lower() end
                        end
                        
                        tags_found[tag] = true

                        local operation = {
                            summary = custom_meta and custom_meta.summary or (method:upper() .. " " .. path),
                            tags = { tag },
                            parameters = get_path_params(route.path),
                            security = { { bearerAuth = {} } },
                            responses = {
                                ["200"] = { 
                                    description = "Success",
                                    content = available_formats
                                }
                            }
                        }

                        if custom_meta then
                            if custom_meta.description then operation.description = custom_meta.description end
                            
                            -- Map snake_case 'request_body' to OpenAPI' 'requestBody'
                            if custom_meta.request_body then
                                operation.requestBody = custom_meta.request_body
                            elseif custom_meta.requestBody then
                                operation.requestBody = custom_meta.requestBody
                            end
                            
                            if custom_meta.responses then operation.responses = custom_meta.responses end
                            if custom_meta.parameters then 
                                -- Merge parameters if they already exist from path
                                for _, p in ipairs(custom_meta.parameters) do
                                    table.insert(operation.parameters, p)
                                end
                            end
                            if custom_meta.tags then operation.tags = custom_meta.tags end
                        end

                        if method_lower == "post" or method_lower == "put" or method_lower == "patch" then
                            if not operation.requestBody then
                                operation.requestBody = {
                                    required = true,
                                    content = available_formats
                                }
                            end
                        end

                        spec.paths[path][method_lower] = operation
                    end
                end
            end
        end

        local sorted_tags = {}
        for t in pairs(tags_found) do table.insert(sorted_tags, t) end
        table.sort(sorted_tags)
        for _, t in ipairs(sorted_tags) do
            table.insert(spec.tags, { name = t })
        end

        return spec
    end

    return function(ctx, next_mw)
        if ctx.path == json_path then
            local spec = build_spec()
            return ctx:json(spec)
        end
        
        if ctx.path == docs_path then
            return ctx:html([[
<!DOCTYPE html>
<html>
<head>
  <title>Rio API Documentation</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script script>
    window.onload = () => {
      SwaggerUIBundle({
        url: ']] .. json_path .. [[',
        dom_id: '#swagger-ui',
        deepLinking: true,
        presets: [SwaggerUIBundle.presets.apis],
        layout: "BaseLayout",
        tagsSorter: "alpha",
        operationsSorter: "alpha"
      });
    };
  </script>
</body>
</html>]])
        end
        
        return next_mw()
    end
end

return M
