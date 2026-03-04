-- rio/lib/rio/core/response.lua
-- Utilities for sending HTTP responses using Web Server Adapters.

local compat = require("rio.utils.compat")
local json = compat.json
local http_headers_ok, http_headers = pcall(require, "http.headers")
local etl = require("rio.utils.etl")

local M = {}

-- Helper to send the final response using an adapter
local function send_answer(adapter, headers, body)
    -- Ensure :status is present
    if not headers:get(":status") then
        headers:upsert(":status", "200")
    end

    -- end_stream should be true if there is no body
    local end_stream = (body == nil or body == "")
    local ok, err = adapter:write_headers(headers, end_stream)
    
    if not ok then
        local err_str = tostring(err)
        if not (err_str:find("Broken pipe") or err_str:find("connection reset")) then
            io.stderr:write("Error writing headers: " .. err_str .. "\n")
        end
        if adapter.close then pcall(adapter.close, adapter) end
        return
    end

    if not end_stream then
        ok, err = adapter:write_body(body)
        if not ok then
            local err_str = tostring(err)
            if not (err_str:find("Broken pipe") or err_str:find("connection reset")) then
                io.stderr:write("Error writing body: " .. err_str .. "\n")
            end
        end
    end
    
    -- Close the adapter if it has a close method (mostly for standalone/http streams)
    if adapter.close then
        pcall(adapter.close, adapter)
    end
end

-- Builds a headers object
local function build_headers(status, content_type, headers_obj)
    local h = headers_obj or (http_headers_ok and http_headers.new() or compat.new_headers())
    h:upsert(":status", tostring(status or 200))
    if content_type then h:upsert("content-type", content_type) end
    return h
end

-- Recursively converts objects (like Rio Models) to plain tables for JSON serialization
local function prepare_for_json(obj)
    if type(obj) ~= "table" then return obj end
    
    -- If it's a Rio Model instance, use toJSON or toTable
    if obj.toJSON and type(obj.toJSON) == "function" then
        obj = obj:toJSON()
    elseif obj.toTable and type(obj.toTable) == "function" then
        obj = obj:toTable()
    end
    
    -- Recurse through the table
    local cleaned = {}
    for k, v in pairs(obj) do
        if type(v) == "table" then
            cleaned[k] = prepare_for_json(v)
        else
            cleaned[k] = v
        end
    end
    return cleaned
end

-- Response methods
function M.json(adapter, status, obj, headers_obj)
    local content_type = "application/json; charset=utf-8"
    local headers = build_headers(status, content_type, headers_obj)
    
    -- Prepare object by converting models to plain tables
    local serializable_obj = prepare_for_json(obj)
    
    local ok, encoded = pcall(json.encode, serializable_obj)
    local body = ok and encoded or '{"error":"json encoding error"}'
    if not ok then 
        headers:upsert(":status", "500")
        -- print("DEBUG: JSON Encoding Error: " .. tostring(encoded))
    end
    send_answer(adapter, headers, body)
end

function M.text(adapter, status, str, headers_obj)
    local headers = build_headers(status, "text/plain; charset=utf-8", headers_obj)
    send_answer(adapter, headers, str or "")
end

function M.html(adapter, status, html, headers_obj)
    local headers = build_headers(status, "text/html; charset=utf-8", headers_obj)
    send_answer(adapter, headers, html or "")
end

function M.view(adapter, status, view_name, data, headers_obj)
    local html, err = etl.render_file("app/views/" .. view_name .. ".etl", data or {})
    if not html then
        return M.text(adapter, 500, "Template error: " .. tostring(err))
    end
    M.html(adapter, status, html, headers_obj)
end

function M.redirect(adapter, status, headers_obj)
    local headers = build_headers(status or 302, "text/plain", headers_obj)
    send_answer(adapter, headers)
end

return M
