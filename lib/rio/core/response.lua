-- rio/lib/rio/core/response.lua
-- Utilities for sending HTTP responses using lua-http stream.

local compat = require("rio.utils.compat")
local json = compat.json
local http_headers_ok, http_headers = pcall(require, "http.headers")
local headers_utils = require("rio.utils.headers")
local etl = require("rio.utils.etl")

local M = {}

-- Helper to send the final response to the stream
local function send_answer(stream, headers, body)
    if stream.headers_sent then return end

    -- Ensure :status is present
    if not headers:get(":status") then
        headers:upsert(":status", "200")
    end

    local ok, err = stream:write_headers(headers, false)
    if not ok then
        -- We can't send an error response if headers failed, so we just log.
        print("Error writing headers: " .. tostring(err))
        return
    end

    if body then
        ok, err = stream:write_body_from_string(body)
        if not ok then
            print("Error writing body: " .. tostring(err))
        end
    end
end

-- Forward declaration for recursive serialization
local serialize_data

-- Serializes a single object into JSON API format
local function serialize_json_api_item(item)
    if not item or type(item) ~= "table" then return item end
    
    local id = item.id or item._attributes and item._attributes.id
    local type_name = "unknown"
    
    -- Try to guess type from table name if it's a model
    pcall(function() 
        if item.table_name then type_name = item.table_name 
        elseif item._table then type_name = item._table end
    end)

    local attributes = serialize_data(item)
    if attributes then attributes.id = nil end -- ID goes to top level in JSON API

    return {
        type = type_name,
        id = tostring(id or ""),
        attributes = attributes
    }
end

-- Serializes data according to JSON API spec
local function serialize_json_api(obj)
    if obj == nil then return { data = nil } end
    
    local result = { data = nil }
    
    if type(obj) == "table" and #obj > 0 then
        -- It's a collection
        result.data = {}
        for i, item in ipairs(obj) do
            result.data[i] = serialize_json_api_item(item)
        end
    else
        -- It's a single item
        result.data = serialize_json_api_item(obj)
    end
    
    return result
end

-- Serializes Model(s) to a plain table for JSON conversion.
serialize_data = function(obj)
    if obj == nil then return nil end
    
    local t = type(obj)
    if t ~= "table" then return obj end

    -- 1. Check if it is a Model (has toArray, toTable or toJSON)
    local is_model = false
    pcall(function() 
        is_model = type(obj.toArray) == "function" or 
                   type(obj.toTable) == "function" or 
                   type(obj.toJSON) == "function"
    end)
    
    if is_model then
        -- Models are special: we ONLY want their attributes.
        -- We get them and then recursively serialize that plain table.
        local data = {}
        if type(obj.toArray) == "function" then data = obj:toArray()
        elseif type(obj.toTable) == "function" then data = obj:toTable()
        elseif type(obj.toJSON) == "function" then data = obj:toJSON() end
        return serialize_data(data)
    end

    -- 2. It is a plain table (list or map)
    local result = {}
    
    -- Check for array (list)
    if #obj > 0 then
        for i, v in ipairs(obj) do
            result[i] = serialize_data(v)
        end
        return result
    end

    -- It is a map (object)
    for k, v in pairs(obj) do
        -- Skip Rio internal fields from raw tables (those starting with _)
        local skip = false
        if type(k) == "string" and k:sub(1,1) == "_" then
            skip = true
        end
        
        if not skip then
            result[k] = serialize_data(v)
        end
    end
    
    return result
end

-- Builds a headers object by cloning a base object and adding/overwriting essential headers.
local function build_headers(status, content_type, headers_obj)
    local h = headers_obj or (http_headers_ok and http_headers.new() or compat.new_headers())

    h:upsert(":status", tostring(status or 200))
    if content_type then
        h:upsert("content-type", content_type)
    end
    
    return h
end

-- Envia resposta JSON
function M.json(stream, status, obj, headers_obj, format)
    local content_type = "application/json; charset=utf-8"
    
    -- Check if it's a Model or collection of Models
    local is_model_data = false
    if type(obj) == "table" then
        local function check_model(o)
            return o and type(o) == "table" and (
                type(o.toArray) == "function" or 
                type(o.toTable) == "function" or 
                type(o.toJSON) == "function"
            )
        end
        
        if check_model(obj) then -- Single Model
            is_model_data = true
        elseif #obj > 0 and check_model(obj[1]) then -- List of Models
            is_model_data = true
        end
    end

    -- Only use JSON API if requested AND the data has Model structure
    local effective_format = "json"
    if format == "jsonapi" and is_model_data then
        effective_format = "jsonapi"
        content_type = "application/vnd.api+json; charset=utf-8"
    end

    local headers = build_headers(status, content_type, headers_obj)
    
    local serialized
    if effective_format == "jsonapi" then
        serialized = serialize_json_api(obj)
    else
        serialized = serialize_data(obj)
    end

    local ok, encoded = pcall(json.encode, serialized)
    
    local body
    if ok then
        body = encoded
    else
        headers:upsert(":status", "500")
        body = '{"error":"json encoding error"}'
    end
    
    send_answer(stream, headers, body)
end

-- Envia resposta de texto
function M.text(stream, status, str, headers_obj)
    local headers = build_headers(status, "text/plain; charset=utf-8", headers_obj)
    send_answer(stream, headers, str or "")
end

-- Envia resposta HTML
function M.html(stream, status, html, headers_obj)
    local headers = build_headers(status, "text/html; charset=utf-8", headers_obj)
    send_answer(stream, headers, html or "")
end

-- Renderiza e envia uma view (template)
function M.view(stream, status, view_name, data, headers_obj)
    local full_view_path = "app/views/" .. view_name .. ".etl"
    
    local render_data = data or {}
    -- Add render helper for partials
    if not render_data.render then
        render_data.render = function(partial_name, partial_data)
            local partial_path = "app/views/" .. partial_name .. ".etl"
            
            -- Merge parent data with partial data
            local merged_data = {}
            for k, v in pairs(render_data) do merged_data[k] = v end
            if type(partial_data) == "table" then
                for k, v in pairs(partial_data) do merged_data[k] = v end
            end
            
            local html, err = etl.render_file(partial_path, merged_data)
            return html or ("<!-- Error rendering partial " .. partial_name .. ": " .. tostring(err) .. " -->")
        end
    end

    local html, err = etl.render_file(full_view_path, render_data)
    
    if not html then
        M.error(stream, 500, "Template rendering error", nil, headers_obj)
        return
    end
    
    M.html(stream, status, html, headers_obj)
end

-- Envia erro padronizado
function M.error(stream, status, message, details, headers_obj, config)
    config = config or {}
    local env = os.getenv("RIO_ENV") or "development"
    local error_obj = {
        error = message or "internal error",
        status = status or 500
    }
    
    local is_db_error = false
    if details then
        if type(details) == "table" and details.type == "DatabaseError" then
            is_db_error = true
            -- Clean, structured database error
            error_obj.database_error = {
                message = details.message,
                suggestion = details.suggestion,
                command = details.command
            }
            -- Simplified details for JSON
            error_obj.details = details.message
        else
            -- Standard string error
            error_obj.details = tostring(details)
        end
    end
    
    -- If not API-only and it's a dev database error, try to show a nice HTML page
    local is_api = config.api_only == true
    if not is_api and env == "development" and is_db_error then
        local success, html = pcall(function()
            return etl.render([[
<!DOCTYPE html>
<html>
<head>
    <title>Database Error</title>
    <style>
        body { font-family: sans-serif; line-height: 1.6; color: #333; max-width: 800px; margin: 40px auto; padding: 20px; }
        .error-card { border: 1px solid #e74c3c; border-radius: 8px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .error-header { background: #e74c3c; color: white; padding: 15px 20px; margin: 0; }
        .error-body { padding: 20px; }
        .suggestion { background: #fdf2f2; border-left: 4px solid #e74c3c; padding: 15px; margin: 20px 0; }
        code { background: #f4f4f4; padding: 2px 5px; border-radius: 3px; font-family: monospace; }
        pre { background: #2c3e50; color: #ecf0f1; padding: 15px; border-radius: 5px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="error-card">
        <h1 class="error-header">Rio Database Error</h1>
        <div class="error-body">
            <p><strong>Message:</strong> <%= message %></p>
            <div class="suggestion">
                <strong>💡 Suggestion:</strong><br>
                <%= suggestion %>
            </div>
            <% if command then %>
                <p>Run this command to fix it:</p>
                <pre>$ <%= command %></pre>
            <% end %>
        </div>
    </div>
</body>
</html>
]], {
                message = details.message,
                suggestion = details.suggestion,
                command = details.command
            })
        end)
        if success then
            return M.html(stream, status, html, headers_obj)
        end
    end

    M.json(stream, status, error_obj, headers_obj)
end

-- Envia resposta de redirecionamento
function M.redirect(stream, status, headers_obj)
    local headers = build_headers(status or 302, "text/plain", headers_obj)
    send_answer(stream, headers)
end

-- Sends a raw response with a given body and content type.
function M.raw(stream, status, body, headers_obj)
    local headers = headers_obj or http_headers.new()
    headers:upsert(":status", tostring(status or 200))
    send_answer(stream, headers, body)
end

-- Envia resposta vazia (204 No Content)
function M.no_content(stream, headers_obj)
    local headers = build_headers(204, "text/plain", headers_obj)
    send_answer(stream, headers)
end

-- Define headers de segurança padrão
function M.set_security_headers(headers_obj)
    headers_obj:append("X-Content-Type-Options", "nosniff")
    headers_obj:append("X-Frame-Options", "DENY")
    headers_obj:append("X-XSS-Protection", "1; mode=block")
    headers_obj:append("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
end

-- Define headers CORS
function M.set_cors_headers(headers_obj, options)
    options = options or {}
    headers_obj:append("Access-Control-Allow-Origin", options.origin or "*")
    headers_obj:append("Access-Control-Allow-Methods", options.methods or "GET,POST,PUT,PATCH,DELETE,OPTIONS")
    headers_obj:append("Access-Control-Allow-Headers", options.headers or "Content-Type, Authorization")
    
    if options.credentials then
        headers_obj:append("Access-Control-Allow-Credentials", "true")
    end
    
    if options.max_age then
        headers_obj:append("Access-Control-Max-Age", tostring(options.max_age))
    end
end

return M
