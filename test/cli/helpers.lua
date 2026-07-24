local M = {}
local lfs = require("lfs")
local files = require("rio.cli.files")

function M.strip_ansi(value)
    return tostring(value or ""):gsub("\27%[[%d;?]*[mKhlABCDEFGJKST]", "")
end

function M.capture_prints(fn)
    local original_print = _G.print
    local lines = {}

    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            table.insert(parts, tostring(select(i, ...)))
        end
        table.insert(lines, table.concat(parts, "\t"))
    end

    local ok, err = pcall(fn)
    _G.print = original_print

    if not ok then error(err, 2) end
    return M.strip_ansi(table.concat(lines, "\n"))
end

function M.shell_quote(value)
    return "'" .. tostring(value):gsub("'", [['"'"']]) .. "'"
end

function M.run(command, cwd)
    local full_command = command .. " 2>&1"
    if cwd then
        full_command = "cd " .. M.shell_quote(cwd) .. " && " .. full_command
    end

    local handle = assert(io.popen(full_command, "r"))
    local output = handle:read("*a")
    local ok, _, code = handle:close()
    return {
        ok = ok == true,
        code = code or 0,
        output = M.strip_ansi(output)
    }
end

function M.repo_root()
    return assert(lfs.currentdir())
end

function M.bin_path()
    return M.repo_root() .. "/bin/rio"
end

function M.tmpdir(name)
    local base = os.getenv("TMPDIR") or "/tmp"
    local pid = tostring({}):match("0x(.+)$") or tostring(os.time())
    local path = base .. "/" .. name .. "_" .. pid
    files.remove_tree(path)
    files.ensure_dir(path)
    return path
end

function M.mkdir_p(path)
    return files.ensure_dir(path)
end

function M.remove_tree(path)
    return files.remove_tree(path)
end

function M.write(path, content)
    local file = assert(io.open(path, "w"))
    file:write(content)
    file:close()
end

function M.exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

return M
