-- rio/lib/rio/cli/files.lua
-- File helpers shared by CLI commands and generators.

local M = {}
local lfs = require("lfs")

local sep = package.config:sub(1, 1)

local function normalize(path)
    return tostring(path or ""):gsub("[/\\]+", sep)
end

local function join(left, right)
    left = tostring(left or "")
    right = tostring(right or "")
    if left == "" then return normalize(right) end
    if right == "" then return normalize(left) end
    if left:sub(-1) == "/" or left:sub(-1) == "\\" then
        return normalize(left .. right)
    end
    return normalize(left .. sep .. right)
end

local function is_dot_entry(name)
    return name == "." or name == ".."
end

local function sorted(values)
    table.sort(values)
    return values
end

function M.join(...)
    local result = ""
    for i = 1, select("#", ...) do
        result = join(result, select(i, ...))
    end
    return result
end

function M.current_dir()
    return lfs.currentdir()
end

function M.basename(path)
    return tostring(path or ""):gsub("[/\\]+$", ""):match("([^/\\]+)$")
end

function M.attributes(path, key)
    return lfs.attributes(path, key)
end

function M.exists(path)
    return lfs.attributes(path) ~= nil
end

function M.is_dir(path)
    return lfs.attributes(path, "mode") == "directory"
end

function M.ensure_dir(path)
    path = normalize(path)
    if path == "" or M.is_dir(path) then return true end

    local prefix = ""
    local rest = path
    local drive = rest:match("^%a:")
    if drive then
        prefix = drive
        rest = rest:sub(3)
    end
    if rest:sub(1, 1) == sep then
        prefix = prefix .. sep
        rest = rest:sub(2)
    end

    local current = prefix
    for part in rest:gmatch("[^/\\]+") do
        current = current == "" and part or join(current, part)
        local mode = lfs.attributes(current, "mode")
        if mode == nil then
            local ok, err = lfs.mkdir(current)
            if not ok then return nil, err end
        elseif mode ~= "directory" then
            return nil, current .. " exists and is not a directory"
        end
    end

    return true
end

function M.write(path, content)
    local file = io.open(path, "w")
    if not file then
        return false, "Could not open file for writing: " .. path
    end

    file:write(content)
    file:close()
    return true
end

function M.read(path)
    local file, err = io.open(path, "r")
    if not file then return nil, err end
    local content = file:read("*a")
    file:close()
    return content
end

function M.list(dir, options)
    options = options or {}
    local entries = {}
    if not M.is_dir(dir) then return entries end

    for name in lfs.dir(dir) do
        if not is_dot_entry(name) then
            local path = join(dir, name)
            local mode = lfs.attributes(path, "mode")
            if not options.mode or options.mode == mode then
                if not options.pattern or name:match(options.pattern) or path:match(options.pattern) then
                    table.insert(entries, options.names_only and name or path)
                end
            end
        end
    end

    return sorted(entries)
end

function M.find(dir, options)
    options = options or {}
    local results = {}
    if not M.is_dir(dir) then return results end

    local function walk(current)
        for _, path in ipairs(M.list(current)) do
            local mode = lfs.attributes(path, "mode")
            if mode == "directory" then
                if options.include_dirs and (not options.pattern or path:match(options.pattern)) then
                    table.insert(results, path)
                end
                walk(path)
            elseif mode == "file" and (not options.pattern or path:match(options.pattern)) then
                table.insert(results, path)
            end
        end
    end

    walk(dir)
    return sorted(results)
end

function M.remove_file(path)
    if M.attributes(path, "mode") == "file" then
        return os.remove(path)
    end
    return true
end

function M.remove_tree(path)
    local mode = M.attributes(path, "mode")
    if not mode then return true end
    if mode == "file" then return os.remove(path) end
    if mode ~= "directory" then return nil, "Unsupported file type: " .. tostring(mode) end

    for _, child in ipairs(M.list(path)) do
        local ok, err = M.remove_tree(child)
        if not ok then return nil, err end
    end
    return lfs.rmdir(path)
end

function M.clear_dir(path, options)
    options = options or {}
    M.ensure_dir(path)
    for _, child in ipairs(M.list(path)) do
        local name = M.basename(child)
        if not options.pattern or name:match(options.pattern) or child:match(options.pattern) then
            local ok, err = M.remove_tree(child)
            if not ok then return nil, err end
        end
    end
    return true
end

function M.remove_matching(dir, pattern)
    return M.clear_dir(dir, { pattern = pattern })
end

function M.make_executable(path)
    return M.exists(path)
end

return M
