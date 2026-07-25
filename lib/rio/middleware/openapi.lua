-- lib/rio/middleware/openapi.lua
-- Auto-documenting OpenAPI Plugin for Rio

local compat = require("rio.utils.compat")
local path_utils = require("rio.utils.path")

local function rio_to_openapi_path(path)
    local openapi_path = path:gsub(":(%w+)", "{%1}")
    return openapi_path == "" and "/" or openapi_path
end

local function get_path_params(path)
    local params = {}
    for param in path:gmatch("%{([%w_]+)%}") do
        table.insert(params, {
            name = param,
            ["in"] = "path",
            required = true,
            schema = { type = "string" }
        })
    end
    for param in path:gmatch(":([%w_]+)") do
        table.insert(params, {
            name = param,
            ["in"] = "path",
            required = true,
            schema = { type = "string" }
        })
    end
    return params
end

local function upsert_parameter(parameters, new_param)
    for i, existing in ipairs(parameters) do
        if existing.name == new_param.name and existing["in"] == new_param["in"] then
            parameters[i] = new_param
            return
        end
    end
    table.insert(parameters, new_param)
end

local function normalize_api_version(version)
    if type(version) == "table" then
        version = version.version or version.name or version[1]
    end
    if version == nil then return nil end

    local v = tostring(version)
    v = v:gsub("^%s+", ""):gsub("%s+$", "")
    if v == "" then return nil end

    v = v:gsub("^/api/", ""):gsub("^/", "")
    if v:match("^%d+$") then v = "v" .. v end
    return v
end

local function starts_with_path(path, prefix)
    if not path or not prefix then return false end
    path = path_utils.normalize(path)
    prefix = path_utils.normalize(prefix)
    return path == prefix or path:sub(1, #prefix + 1) == (prefix .. "/")
end

local function configured_versions(app)
    local versions = {}
    for _, entry in ipairs(app.config.api_versions or {}) do
        local version = normalize_api_version(entry)
        if version then
            local api_prefix = type(entry) == "table" and (entry.api_prefix or entry.base_path) or nil
            api_prefix = api_prefix or app.config.api_prefix or "/api"
            local prefix = type(entry) == "table" and (entry.path or entry.prefix) or nil
            table.insert(versions, {
                version = version,
                name = type(entry) == "table" and (entry.label or entry.title or entry.name) or nil,
                prefix = path_utils.normalize(prefix or path_utils.join(api_prefix, version))
            })
        end
    end
    return versions
end

local function version_entry(app, requested_version)
    local requested = normalize_api_version(requested_version)
    if not requested then return nil end

    for _, entry in ipairs(configured_versions(app)) do
        if entry.version == requested then return entry end
    end

    return {
        version = requested,
        name = requested:upper(),
        prefix = path_utils.normalize(path_utils.join(app.config.api_prefix or "/api", requested))
    }
end

local function route_version(app, route)
    local meta = route.meta or {}
    local meta_version = normalize_api_version(meta.api_version or meta.version)
    if meta_version then return meta_version end

    for _, entry in ipairs(configured_versions(app)) do
        if starts_with_path(route.path, entry.prefix) then
            return entry.version
        end
    end

    local api_version = route.path:match("^/api/(v[%w_.%-]+)$") or route.path:match("^/api/(v[%w_.%-]+)/")
    if api_version then return normalize_api_version(api_version) end

    return normalize_api_version(route.path:match("^/(v%d[%w_.%-]*)$") or route.path:match("^/(v%d[%w_.%-]*)/"))
end

local function route_matches_version(app, route, selected_version)
    if not selected_version then return true end

    local found = route_version(app, route)
    if found then return found == selected_version end

    local include_global = app.config.openapi_include_global_routes
    if include_global == nil then include_global = true end
    return include_global
end

local function versioned_json_path(app, json_path, version)
    local entry = version_entry(app, version)
    if not entry then return nil end
    return path_utils.normalize(path_utils.join(entry.prefix, json_path))
end

local function match_versioned_json_path(app, json_path, request_path)
    local path = path_utils.normalize(request_path)
    for _, entry in ipairs(configured_versions(app)) do
        if path == path_utils.normalize(path_utils.join(entry.prefix, json_path)) then
            return entry.version
        end
    end
    return nil
end

local function js(value)
    return compat.json.encode(value)
end

local M = {}

function M.create(app, options)
    options = options or {}
    local docs_path = options.path or app.config.openapi_path or "/docs"
    local json_path = options.json_path or app.config.openapi_json_path or "/openapi.json"
    
    -- Support for both standard JSON and JSON:API
    local available_formats = {
        ["application/json"] = { schema = { type = "object" } },
        ["application/vnd.api+json"] = { schema = { type = "object" } }
    }

    local function build_spec(version_prefix)
        local selected_version = normalize_api_version(version_prefix)
        local spec = {
            openapi = "3.1.0",
            info = {
                title = app.config.title or app.config.app_name or "Rio Auto-API",
                version = selected_version or normalize_api_version(app.config.api_version) or app.config.version or "1.0.0",
                description = app.config.description or "Auto-generated documentation via route reflection."
            },
            paths = {},
            tags = {},
            components = { 
                schemas = {}, 
                securitySchemes = {
                    bearerAuth = { type = "http", scheme = "bearer", jwtFormat = "JWT" }
                }
            },
            security = { { bearerAuth = {} } }
        }

        local tags_found = {}

        if app.router and app.router.routes then
            for method, routes in pairs(app.router.routes) do
                local method_lower = method:lower()
                for _, route in ipairs(routes) do
                    local is_docs = (route.path == docs_path or route.path == json_path or match_versioned_json_path(app, json_path, route.path))
                    local matches_version = route_matches_version(app, route, selected_version)

                    if not is_docs and matches_version then
                        local path = rio_to_openapi_path(route.path)
                        
                        -- REFLECTION: Extract METADATA from Controller (_openapi)
                        local custom_meta = nil
                        local controller_name = nil
                        local action_name = nil

                        if app.routes_meta and app.routes_meta[route.handler] then
                            local meta = app.routes_meta[route.handler]
                            controller_name = meta.controller
                            action_name = meta.action

                            -- Attempt to load controller to find openapi table
                            local controller_module = controller_name:gsub("::", "."):lower()
                            if not controller_module:find("_controller$") then
                                controller_module = controller_module .. "_controller"
                            end

                            local ok, controller = pcall(require, "app.controllers." .. controller_module)
                            if ok and type(controller) == "table" and controller.openapi then
                                custom_meta = controller.openapi[action_name]
                            end
                        end

                        -- SKIP if hidden = true
                        if not (custom_meta and custom_meta.hidden) then
                            spec.paths[path] = spec.paths[path] or {}
                            
                            -- Grouping: Prefer Controller name
                            local tag = "default"
                            if controller_name then
                                tag = controller_name:lower():gsub("_?controller$", ""):gsub("^app%.controllers%.", "")
                            else
                                local first_segment = route.path:match("/([^/:]+)")
                                if first_segment then tag = first_segment:lower() end
                            end

                            local operation = {
                                summary = (custom_meta and custom_meta.summary) or (method:upper() .. " " .. path),
                                tags = { tag },
                                parameters = get_path_params(route.path),
                                security = { { bearerAuth = {} } },
                                responses = {
                                    ["200"] = { 
                                        description = "Success",
                                        content = available_formats,
                                        headers = {}
                                    }
                                }
                            }

                            -- Inject custom headers from app config as INPUT parameters (Request Headers)
                            if app.config.security and app.config.security.headers then
                                for h_name, h_value in pairs(app.config.security.headers) do
                                    -- Add to request parameters so Swagger UI shows an input field
                                    table.insert(operation.parameters, {
                                        name = h_name,
                                        ["in"] = "header",
                                        required = false,
                                        description = "Custom application header",
                                        schema = { type = "string", default = tostring(h_value) }
                                    })

                                    -- Also keep in response documentation
                                    operation.responses["200"].headers[h_name] = {
                                        description = "Response header",
                                        schema = { type = "string", example = tostring(h_value) }
                                    }
                                end
                            end

                            -- Default Request Body for POST/PUT/PATCH
                            if (method_lower == "post" or method_lower == "put" or method_lower == "patch") then
                                operation.requestBody = {
                                    required = true,
                                    content = available_formats
                                }
                            end

                            -- OVERRIDE with Custom Metadata if present
                            if custom_meta then
                                if custom_meta.summary then operation.summary = custom_meta.summary end
                                if custom_meta.description then operation.description = custom_meta.description end
                                if custom_meta.responses then operation.responses = custom_meta.responses end
                                if custom_meta.request_body then operation.requestBody = custom_meta.request_body
                                elseif custom_meta.requestBody then operation.requestBody = custom_meta.requestBody end
                                if custom_meta.parameters then
                                    for _, p in ipairs(custom_meta.parameters) do upsert_parameter(operation.parameters, p) end
                                end
                                if custom_meta.tags then operation.tags = custom_meta.tags end

                                -- Inject Route-Specific Headers from controller metadata
                                if custom_meta.headers then
                                    for h_name, h_desc in pairs(custom_meta.headers) do
                                        local description = type(h_desc) == "string" and h_desc or "Route-specific header"
                                        
                                        -- Add to request parameters
                                        table.insert(operation.parameters, {
                                            name = h_name,
                                            ["in"] = "header",
                                            required = true,
                                            description = description,
                                            schema = { type = "string" }
                                        })
                                    end
                                end
                            end

                            for _, t in ipairs(operation.tags) do tags_found[t] = true end

                            spec.paths[path][method_lower] = operation
                        end
                    end
                end
            end
        end

        local sorted_tags = {}
        for t in pairs(tags_found) do table.insert(sorted_tags, t) end
        table.sort(sorted_tags)
        for _, t in ipairs(sorted_tags) do table.insert(spec.tags, { name = t }) end

        return spec
    end

    return function(ctx, next_mw)
        local query = ctx.query or {}
        local path_version = match_versioned_json_path(app, json_path, ctx.path)

        if ctx.path == json_path or path_version then
            local version_prefix = path_version or query.v
            return ctx:json(build_spec(version_prefix))
        end
        
        if ctx.path == docs_path then
            local urls_json = ""
            local ui_layout = "BaseLayout"
            local presets = "[SwaggerUIBundle.presets.apis]"

            local versions = configured_versions(app)
            if #versions > 0 then
                local urls = {}
                for _, v in ipairs(versions) do
                    table.insert(urls, {
                        url = options.versioned_json_paths and versioned_json_path(app, json_path, v.version) or (json_path .. "?v=" .. v.version),
                        name = v.name or v.version:upper()
                    })
                end
                urls_json = "urls: " .. js(urls) .. ",\n        \"urls.primaryName\": " .. js((versions[1].name or versions[1].version:upper())) .. ","
                ui_layout = "StandaloneLayout"
                presets = "[SwaggerUIBundle.presets.apis, SwaggerUIStandalonePreset]"
            else
                urls_json = "url: " .. js(json_path) .. ","
            end

            -- Set specific CSP for Swagger UI to allow necessary CDNs
            ctx:setHeader("Content-Security-Policy", "default-src 'self' 'unsafe-inline' https://unpkg.com; img-src 'self' data: https://unpkg.com; frame-ancestors 'self'")

            return ctx:html([[
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>]] .. (app.config.title or "Rio API Documentation") .. [[</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
  <style>
    html { box-sizing: border-box; overflow-y: scroll; }
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
        plugins: [SwaggerUIBundle.plugins.DownloadUrl],
        layout: "]] .. ui_layout .. [[",
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
