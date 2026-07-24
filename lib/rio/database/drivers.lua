-- rio/lib/rio/database/drivers.lua
-- Optional database driver metadata for CLI installation and diagnostics.

local M = {}

local specs = {
    sqlite = {
        adapter = "sqlite",
        label = "SQLite",
        aliases = { "sqlite", "sqlite3" },
        module = "luasql.sqlite3",
        rock = "luasql-sqlite3",
        native_dependency = "SQLite development headers and library (sqlite3.h, libsqlite3)",
        build_variables = {}
    },
    mysql = {
        adapter = "mysql",
        label = "MySQL/MariaDB",
        aliases = { "mysql", "mariadb", "maria" },
        module = "luasql.mysql",
        rock = "luasql-mysql",
        native_dependency = "MySQL or MariaDB client development headers and library (mysql.h, libmysqlclient or libmariadb)",
        build_variables = {
            {
                name = "MYSQL_INCDIR",
                header = "mysql.h"
            }
        }
    },
    postgres = {
        adapter = "postgres",
        label = "PostgreSQL",
        aliases = { "postgres", "postgresql", "pgsql" },
        module = "luasql.postgres",
        rock = "luasql-postgres",
        native_dependency = "PostgreSQL client development headers and library (libpq-fe.h, libpq)",
        build_variables = {
            {
                name = "PGSQL_INCDIR",
                header = "libpq-fe.h"
            }
        }
    }
}

local aliases = {}
for key, spec in pairs(specs) do
    aliases[key] = key
    for _, alias in ipairs(spec.aliases) do
        aliases[alias] = key
    end
end

function M.normalize(adapter)
    if not adapter then return nil end
    return aliases[tostring(adapter):lower()]
end

function M.get(adapter)
    local key = M.normalize(adapter)
    if not key then return nil end
    return specs[key]
end

function M.get_by_module(module_name)
    for _, spec in pairs(specs) do
        if spec.module == module_name then
            return spec
        end
    end
    return nil
end

function M.all()
    return {
        specs.sqlite,
        specs.mysql,
        specs.postgres
    }
end

function M.supported_names()
    return "sqlite3, mysql, mariadb, postgresql"
end

function M.install_command(adapter, opts)
    opts = opts or {}
    local spec = M.get(adapter)
    if not spec then return nil end

    local parts = { "luarocks" }
    if opts.local_install then
        table.insert(parts, "--local")
    end
    if opts.tree then
        table.insert(parts, "--tree=" .. opts.tree)
    end
    table.insert(parts, "install")
    table.insert(parts, spec.rock)
    if opts.extra_args then
        for _, arg in ipairs(opts.extra_args) do
            table.insert(parts, arg)
        end
    end
    return table.concat(parts, " ")
end

function M.remove_command(adapter, opts)
    opts = opts or {}
    local spec = M.get(adapter)
    if not spec then return nil end

    local parts = { "luarocks" }
    if opts.local_install then
        table.insert(parts, "--local")
    end
    if opts.tree then
        table.insert(parts, "--tree=" .. opts.tree)
    end
    table.insert(parts, "remove")
    table.insert(parts, spec.rock)
    if opts.extra_args then
        for _, arg in ipairs(opts.extra_args) do
            table.insert(parts, arg)
        end
    end
    return table.concat(parts, " ")
end

local function search_module_path(module_name, cpath)
    if package.searchpath then
        local path = package.searchpath(module_name, cpath or package.cpath)
        if path then return path end
    end

    local module_path = module_name:gsub("%.", "/")
    for pattern in tostring(cpath or package.cpath):gmatch("[^;]+") do
        local candidate = pattern:gsub("%?", module_path)
        local file = io.open(candidate, "r")
        if file then
            file:close()
            return candidate
        end
    end
    return nil
end

function M.module_path(adapter, lua_path, lua_cpath)
    local spec = M.get(adapter)
    if not spec then return nil end

    local original_path = package.path
    local original_cpath = package.cpath
    if lua_path then package.path = lua_path .. ";" .. package.path end
    if lua_cpath then package.cpath = lua_cpath .. ";" .. package.cpath end

    local path = search_module_path(spec.module, package.cpath)

    package.path = original_path
    package.cpath = original_cpath

    return path
end

function M.infer_tree_from_module_path(path)
    if not path then return nil end
    return path:match("^(.-)/lib/lua/%d+%.%d+/")
end

function M.infer_tree_from_cpath(cpath)
    local fallback = nil
    for entry in tostring(cpath or package.cpath):gmatch("[^;]+") do
        local tree = entry:match("^(.-)/lib/lua/%d+%.%d+/%?%.so$")
        if tree then
            if tree:find(".rock/versions", 1, true) or tree:find(".luarocks", 1, true) then
                return tree
            end
            fallback = fallback or tree
        end
    end
    return fallback
end

function M.check(adapter, lua_path, lua_cpath)
    local spec = M.get(adapter)
    if not spec then
        return false, "Unsupported database adapter: " .. tostring(adapter)
    end

    local original_path = package.path
    local original_cpath = package.cpath
    if lua_path then package.path = lua_path .. ";" .. package.path end
    if lua_cpath then package.cpath = lua_cpath .. ";" .. package.cpath end

    local ok, err = pcall(require, spec.module)

    package.path = original_path
    package.cpath = original_cpath

    if ok then return true end
    return false, err
end

return M
