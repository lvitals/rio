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

    local function build_spec(version_prefix)
        local spec = {
            openapi = "3.1.0",
            info = {
                title = app.config.title or app.config.app_name or "Rio Auto-API",
                version = version_prefix or app.config.api_version or app.config.version or "1.0.0",
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
                    -- Skip internal docs routes and filter by version prefix if provided
                    local is_docs = (route.path == docs_path or route.path == json_path)
                    
                    -- Check if route matches version filter
                    local matches_version = true
                    if version_prefix then
                        -- Normalize version prefix to have leading slash
                        local vp = version_prefix:sub(1,1) == "/" and version_prefix or ("/" .. version_prefix)
                        
                        -- A route matches versioning if:
                        -- 1. It is explicitly part of the version (e.g. /api/v1/...)
                        -- 2. It is a "global" route (not starting with /api/vX/ or /vX/)
                        local is_versioned = route.path:find("^/v%d+/") or 
                                            route.path:find("^/api/v%d+/") or
                                            route.path:match("^/v%d+$") or
                                            route.path:match("^/api/v%d+$")

                        if is_versioned then
                            matches_version = route.path:find("^" .. vp .. "/") or 
                                             route.path == vp or
                                             route.path:find("^/api" .. vp .. "/") or
                                             route.path == ("/api" .. vp)
                        else
                            -- Global routes (like /auth/login or /) are included in all version specs
                            matches_version = true
                        end
                    end

                    if not is_docs and matches_version then
                        local path = rio_to_openapi_path(route.path)
                        
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

                        -- SKIP if hidden = true
                        if custom_meta and custom_meta.hidden then
                            -- Skip this route
                        else
                            spec.paths[path] = spec.paths[path] or {}
                            
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
            local version_prefix = ctx.query.v
            local spec = build_spec(version_prefix)
            return ctx:json(spec)
        end
        
        if ctx.path == docs_path then
            local urls_json = ""
            local layout = "BaseLayout"
            local presets = "[SwaggerUIBundle.presets.apis]"

            if app.config.api_versions and #app.config.api_versions > 0 then
                local urls = {}
                for _, v in ipairs(app.config.api_versions) do
                    table.insert(urls, string.format('{url: "%s?v=%s", name: "%s"}', json_path, v, v:upper()))
                end
                urls_json = "urls: [" .. table.concat(urls, ", ") .. "],"
                layout = "StandaloneLayout"
                presets = "[SwaggerUIBundle.presets.apis, SwaggerUIStandalonePreset]"
            else
                urls_json = 'url: "' .. json_path .. '",'
            end

            return ctx:html([[
<!DOCTYPE html>
<html>
<head>
  <title>]] .. (app.config.title or "Rio API Documentation") .. [[</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
  <style>
    html { box-sizing: border-box; overflow: -moz-scrollbars-vertical; overflow-y: scroll; }
    *, *:before, *:after { box-sizing: inherit; }
    body { margin:0; background: #fafafa; }
  </style>
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-standalone-preset.js"></script>
  <script>
    window.onload = () => {
      window.ui = SwaggerUIBundle({
        ]] .. urls_json .. [[
        dom_id: '#swagger-ui',
        deepLinking: true,
        presets: ]] .. presets .. [[,
        plugins: [
          SwaggerUIBundle.plugins.DownloadUrl
        ],
        layout: "]] .. layout .. [[",
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
