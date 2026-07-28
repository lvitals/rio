-- rio/lib/rio/cli/project_paths.lua
-- Shared Lua module paths for commands executed from a Rio project root.

local M = {}

local templates = {
    "?.lua",
    "?/init.lua",
    "app/?.lua",
    "app/?/init.lua",
    "config/?.lua",
    "config/?/init.lua",
    "lib/?.lua",
    "lib/?/init.lua"
}

local function normalize_root(root)
    root = root or "."
    root = tostring(root)
    if root == "" then return "." end
    while #root > 1 and root:match("[/\\]$") and not root:match("^%a:[/\\]$") do
        root = root:sub(1, -2)
    end
    return root
end

local function join(root, path)
    if root == "." then
        return "./" .. path
    end
    if root:match("[/\\]$") then
        return root .. path
    end
    return root .. "/" .. path
end

function M.lua_path(root)
    root = normalize_root(root)
    local paths = {}
    for _, path in ipairs(templates) do
        table.insert(paths, join(root, path))
    end
    return table.concat(paths, ";")
end

return M
