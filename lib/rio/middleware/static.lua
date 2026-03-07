-- rio/lib/rio/middleware/static.lua
-- Middleware for serving static files from a public directory.

local M = {}

M.description = "Serves static files from a public directory."

-- Returns the content-type based on the file extension.
local function get_content_type(file_path)
    local ext = file_path:match("%.([^.]+)$") or ""
    ext = ext:lower()
    
    local types = {
        css = "text/css",
        js = "application/javascript",
        json = "application/json",
        html = "text/html",
        htm = "text/html",
        png = "image/png",
        jpg = "image/jpeg",
        jpeg = "image/jpeg",
        gif = "image/gif",
        svg = "image/svg+xml",
        ico = "image/x-icon",
        txt = "text/plain",
        pdf = "application/pdf",
        woff = "font/woff",
        woff2 = "font/woff2",
        ttf = "font/ttf",
        eot = "application/vnd.ms-fontobject"
    }
    
    return types[ext] or "application/octet-stream"
end

-- Creates a middleware for serving static files.
-- @param options: The directory string or options table {root="public"}.
function M.create(app, options)
    local public_dir = "public"
    if type(options) == "string" then public_dir = options
    elseif type(options) == "table" then public_dir = options.root or "public" end
    
    return function(ctx, next)
        -- Only serve GET and HEAD requests.
        if ctx.method ~= "GET" and ctx.method ~= "HEAD" then
            return next()
        end
        
        -- Security: Prevent path traversal attacks.
        if ctx.path:find("..", 1, true) then
            return ctx:error(403, "Forbidden")
        end
        
        -- Strip leading slash and handle optional /public prefix
        local req_path = ctx.path:gsub("^/", "")
        
        -- If the URL starts with 'public/', we remove it because public_dir is usually 'public'
        -- This allows both /public/css/style.css and /css/style.css to work.
        if req_path:sub(1, 7) == "public/" then
            req_path = req_path:sub(8)
        end
        
        local file_path = public_dir .. "/" .. req_path
        
        -- Try to open the file in binary mode.
        local file, err = io.open(file_path, "rb")
        if not file then
            return next() -- File not found, continue to next middleware.
        end
        
        local content = file:read("*all")
        file:close()
        
        if not content then
            return next() -- Failed to read file content.
        end
        
        -- Set response headers.
        ctx:setHeader("Content-Type", get_content_type(file_path))
        ctx:setHeader("Content-Length", tostring(#content))
        ctx:setHeader("Cache-Control", "public, max-age=3600")
        
        -- For HEAD requests, send only headers (empty body).
        if ctx.method == "HEAD" then
            ctx:raw(200, "")
        else
            -- For GET requests, send the content.
            ctx:raw(200, content)
        end
        
        -- Stop the middleware chain as the response has been sent.
        return false
    end
end

return M
