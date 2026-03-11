-- lib/rio/utils/compat.lua
-- Compatibility layer for different Lua versions (5.1, 5.2, 5.3, 5.4)
-- Centralizes dependencies and provide fallbacks for missing libraries.

local M = {}

-- ANSI Colors for CLI
M.colors = {
    reset = "\27[0m",
    bold = "\27[1m",
    dim = "\27[2m",
    red = "\27[31m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    magenta = "\27[35m",
    cyan = "\27[36m",
    white = "\27[37m",
    gray = "\27[90m"
}

-- Lua version detection
local version = _VERSION:match("Lua (%d%.%d)")
M.lua_version = tonumber(version)

-- Returns the current Lua binary path or command
function M.get_lua_bin()
    -- Start with arg[-1] but try to find the lowest negative index in arg table, 
    -- skipping common Lua flags (-e, -v, -l, etc.) and wrappers to find the real interpreter.
    local bin = "lua"
    if arg then
        local i = -1
        while arg[i-1] do i = i - 1 end
        
        -- Search from the lowest index upwards to find the first non-flag argument
        -- which should be the Lua interpreter.
        local current = i
        while arg[current] and (arg[current]:match("^%-") or arg[current] == "luarocks" or arg[current] == "rock") do
            current = current + 1
        end
        bin = arg[current] or "lua"
    end
    
    -- DEBUG: Trace binary detection
    -- io.stderr:write("DEBUG: Detected bin: " .. tostring(bin) .. "\n")
    
    -- If the binary name looks like a complex path or contains suspicious characters
    -- (like code from a wrapper), we fallback to a version-specific binary name.
    if bin:find("[%(%);]") or #bin > 256 then
        if jit and jit.version then return "luajit" end
        local ver = _VERSION:match("Lua (%d%.%d)")
        if ver then
            local cmd = "lua" .. ver
            -- Check if the versioned command exists in the PATH
            local handle = io.popen("command -v " .. cmd .. " 2>/dev/null")
            if handle then
                local res = handle:read("*a")
                handle:close()
                -- Only use it if it's not a generic "not found" message
                if res and res ~= "" and not res:lower():find("not found") then 
                    return cmd 
                end
            end
        end
        return "lua"
    end
    
    return bin
end

-- table.unpack / unpack
M.unpack = table.unpack or unpack

-- load / loadstring
M.load = function(chunk, chunkname, mode, env)
    if M.lua_version <= 5.1 then
        local f, err = loadstring(chunk, chunkname)
        if f and env then setfenv(f, env) end
        return f, err
    else
        -- Lua 5.2+ load(chunk, chunkname, mode, env)
        -- If env is nil, we should explicitly use _G to avoid 
        -- "attempt to index a nil value (upvalue '_ENV')"
        return load(chunk, chunkname, mode, env or _G)
    end
end

-- Bitwise operations
local bit = nil
if M.lua_version >= 5.3 then
    local code = [[
        local M = {}
        function M.band(a, ...)
            local res = a
            for _, v in ipairs({...}) do res = res & v end
            return res
        end
        function M.bor(a, ...)
            local res = a
            for _, v in ipairs({...}) do res = res | v end
            return res
        end
        function M.bxor(a, ...)
            local res = a
            for _, v in ipairs({...}) do res = res ~ v end
            return res
        end
        function M.bnot(a) return ~a end
        function M.lshift(a, b) return a << b end
        function M.rshift(a, b) return a >> b end
        return M
    ]]
    local f = load(code)
    if f then bit = f() end
end

if not bit or type(bit) ~= "table" then
    local ok, b = pcall(require, "bit32")
    if ok then bit = b end
end

if not bit or type(bit) ~= "table" then
    local ok, b = pcall(require, "bit")
    if ok then bit = b end
end

if not bit or type(bit) ~= "table" then
    local function to_bits(n)
        local t = {}
        for i = 1, 32 do t[i] = n % 2; n = math.floor(n / 2) end
        return t
    end
    local function from_bits(t)
        local n = 0; local power = 1
        for i = 1, 32 do n = n + t[i] * power; power = power * 2 end
        return n
    end
    bit = {
        band = function(a, ...)
            local res = a % 4294967296; local args = { ... }
            for i = 1, #args do
                local b = args[i] % 4294967296
                local ta = to_bits(res); local tb = to_bits(b); local tres = {}
                for j = 1, 32 do tres[j] = (ta[j] == 1 and tb[j] == 1) and 1 or 0 end
                res = from_bits(tres)
            end
            return res
        end,
        bor = function(a, ...)
            local res = a % 4294967296; local args = { ... }
            for i = 1, #args do
                local b = args[i] % 4294967296
                local ta = to_bits(res); local tb = to_bits(b); local tres = {}
                for j = 1, 32 do tres[j] = (ta[j] == 1 or tb[j] == 1) and 1 or 0 end
                res = from_bits(tres)
            end
            return res
        end,
        bxor = function(a, ...)
            local res = a % 4294967296; local args = { ... }
            for i = 1, #args do
                local b = args[i] % 4294967296
                local ta = to_bits(res); local tb = to_bits(b); local tres = {}
                for j = 1, 32 do tres[j] = (ta[j] ~= tb[j]) and 1 or 0 end
                res = from_bits(tres)
            end
            return res
        end,
        bnot = function(a)
            local ta = to_bits(a % 4294967296); local res = {}
            for i = 1, 32 do res[i] = (ta[i] == 1) and 0 or 1 end
            return from_bits(res)
        end,
        lshift = function(a, b) return (a * (2 ^ b)) % 4294967296 end,
        rshift = function(a, b) return math.floor((a % 4294967296) / (2 ^ b)) end
    }
end

M.bit = bit
M.band, M.bor, M.bxor, M.bnot, M.lshift, M.rshift = bit.band, bit.bor, bit.bxor, bit.bnot, bit.lshift, bit.rshift

-- Path and environment compatibility
function M.get_runtime_paths(framework_lib_path)
    local lp = os.getenv("LUA_PATH") or ""
    local lcp = os.getenv("LUA_CPATH") or ""

    -- If LUA_PATH already seems to have LuaRocks or system paths, don't call luarocks
    if lp ~= "" and (lp:find("share/lua") or lp:find("luarocks")) then
        return (framework_lib_path or "") .. ";" .. lp, lcp
    end

    -- Try with --local first, but fallback to system-wide if it fails (common in Docker/root)
    local base_cmd = "luarocks path"
    if M.lua_version then
        base_cmd = "luarocks --lua-version=" .. M.lua_version .. " path"
    end
    
    local cmd = base_cmd .. " --local 2>/dev/null || " .. base_cmd .. " 2>/dev/null"

    local handle = io.popen(cmd, "r")
    local output = ""
    if handle then
        output = handle:read("*a")
        handle:close()
    end

    local lp_rocks = output:match("LUA_PATH=['\"]([^'\"]+)['\"]") or ""
    local lcp_rocks = output:match("LUA_CPATH=['\"]([^'\"]+)['\"]") or ""

    local final_lp = (framework_lib_path or "") .. ";" .. (lp_rocks ~= "" and lp_rocks or lp)
    -- Priority to LuaRocks for binary drivers to avoid loading obsolete local .so files
    local final_lcp = (lcp_rocks ~= "" and lcp_rocks .. ";" or "") .. lcp
    
    -- For Lua 5.1, we only append user-tree paths if HOME is explicitly set
    local home = os.getenv("HOME")
    if M.lua_version == 5.1 and home then
        local user_51_extra = home .. "/.luarocks/lib/lua/5.1/socket/?.so;" .. home .. "/.luarocks/lib/lua/5.1/mime/?.so;"
        if not final_lcp:find(user_51_extra, 1, true) then
            final_lcp = user_51_extra .. final_lcp
        end
    end

    return final_lp, final_lcp
end

-- JSON compatibility
local json_ok, cjson = pcall(require, "cjson")
if json_ok then
    -- Disable escaping forward slashes for better readability in API responses
    pcall(function() 
        cjson.encode_escape_forward_slash(false)
    end)
    M.json = cjson
else
    M.json = {
        encode = function(val)
            local function serialize(v)
                if type(v) == "table" then
                    local is_array = #v > 0; local parts = {}
                    if is_array then
                        for _, item in ipairs(v) do table.insert(parts, serialize(item)) end
                        return "[" .. table.concat(parts, ",") .. "]"
                    else
                        local keys = {}; for k in pairs(v) do table.insert(keys, k) end
                        table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
                        for _, k in ipairs(keys) do
                            table.insert(parts, string.format("%q:%s", tostring(k), serialize(v[k])))
                        end
                        return "{" .. table.concat(parts, ",") .. "}"
                    end
                elseif type(v) == "string" then return string.format("%q", v)
                elseif type(v) == "number" or type(v) == "boolean" then return tostring(v)
                else return "null" end
            end
            return serialize(val)
        end,
        decode = function() error("JSON decoding fallback not implemented.") end
    }
end

-- Signal compatibility
local sig_ok, posix_signal = pcall(require, "posix.signal")
if sig_ok then
    M.signal = posix_signal
else
    M.signal = { signal = function() end, SIGINT = 2, SIGTERM = 15 }
end

-- Header compatibility helper
local function create_header_obj(initial)
    local h = {}
    for k,v in pairs(initial or {}) do h[k:lower()] = v end
    local obj = {
        get = function(self, k) return h[k:lower()] end,
        upsert = function(self, k, v) h[k:lower()] = v end,
        append = function(self, k, v) h[k:lower()] = v end,
        each = function(self) return pairs(h) end
    }
    return obj
end
M.new_headers = create_header_obj

-- HTTP Server Fallback (LuaSocket based)
local http_ok, http_server = pcall(require, "http.server")
if http_ok then
    M.http_server = http_server
else
    M.http_server = {
        listen = function(options)
            local socket = require("socket")
            local url = require("net.url")
            local master = assert(socket.bind(options.host or "0.0.0.0", options.port or 8080))
            local ip, port = master:getsockname()
            print(string.format("Rio (LuaSocket fallback) listening on http://%s:%d", ip, port))
            while true do
                local client = master:accept()
                client:settimeout(10)
                local line = client:receive()
                if line then
                    local method, full_path = line:match("^(%S+)%s+(%S+)%s+HTTP/%d%.%d$")
                    if method then
                        local req_headers = {}
                        while true do
                            local h_line = client:receive()
                            if not h_line or h_line == "" then break end
                            local name, value = h_line:match("^(.-):%s*(.*)$")
                            if name then req_headers[name:lower()] = value end
                        end
                        local body = ""
                        local clen = tonumber(req_headers["content-length"])
                        if clen and clen > 0 then body = client:receive(clen) end
                        local stream = {
                            headers_sent = false,
                            get_headers = function()
                                local h = create_header_obj(req_headers)
                                h:upsert(":method", method)
                                h:upsert(":path", full_path)
                                return h
                            end,
                            write_headers = function(self, h)
                                self.headers_sent = true
                                client:send("HTTP/1.1 " .. (h:get(":status") or "200") .. " OK\r\n")
                                for k, v in h:each() do if k:sub(1,1) ~= ":" then client:send(k .. ": " .. v .. "\r\n") end end
                                client:send("\r\n"); return true
                            end,
                            write_body_from_string = function(self, d) client:send(d); return true end,
                            get_body_as_string = function() return body end,
                            close = function() client:close() end,
                            shutdown = function() client:close() end
                        }
                        xpcall(function() options.onstream(nil, stream) end, function(err)
                            print("Request Error: " .. tostring(err))
                            client:close()
                        end)
                    else client:close() end
                else client:close() end
            end
        end
    }
end

return M
