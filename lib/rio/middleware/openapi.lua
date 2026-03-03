-- lib/rio/middleware/openapi.lua
-- Auto-documenting OpenAPI Plugin for Rio

local compat = require("rio.utils.compat")

local function rio_to_openapi_path(path)
    return path:gsub(":(%w+)", "{%1}")
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
    
    -- Define available formats for the Swagger dropdown
    local available_formats = {
        ["application/json"] = { schema = { type = "object" } },
        ["application/vnd.api+json"] = { schema = { type = "object" } }
    }

    local function build_spec()
        local spec = {
            openapi = "3.1.0",
            info = {
                title = app.config.title or app.config.app_name or "Rio Auto-API",
                version = app.config.version or app.config.app_version or "1.0.0",
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
            -- Router organizes routes by method: router.routes[METHOD] = { {path, handler}, ... }
            for method, routes in pairs(app.router.routes) do
                local method_lower = method:lower()
                for _, route in ipairs(routes) do
                    if route.path ~= docs_path and route.path ~= json_path then
                        local path = rio_to_openapi_path(route.path)
                        spec.paths[path] = spec.paths[path] or {}
                        
                        -- Group by the static part of the path (before any parameters)
                        -- e.g., /api/users/:id -> tag: api/users
                        local static_segments = {}
                        for s in route.path:gmatch("([^/]+)") do
                            if s:sub(1,1) == ":" then break end
                            table.insert(static_segments, s)
                        end
                        local tag = #static_segments > 0 and table.concat(static_segments, "/") or "default"
                        tags_found[tag] = true

                        local operation = {
                            summary = method:upper() .. " " .. path,
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

                        if method_lower == "post" or method_lower == "put" or method_lower == "patch" then
                            operation.requestBody = {
                                required = true,
                                content = available_formats
                            }
                        end

                        spec.paths[path][method_lower] = operation
                    end
                end
            end
        end

        -- Sort tags alphabetically
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
            -- When returning the spec itself, we might also want to respect the JSON:API header
            -- but usually openapi.json is application/json. 
            -- However, the user might want the API responses documented as jsonapi.
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
  <script>
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
