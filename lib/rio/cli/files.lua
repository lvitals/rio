-- rio/lib/rio/cli/files.lua
-- File helpers shared by CLI commands and generators.

local M = {}

function M.ensure_dir(path)
    os.execute("mkdir -p " .. path)
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

function M.exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

function M.make_executable(path)
    os.execute("chmod +x " .. path)
end

return M
