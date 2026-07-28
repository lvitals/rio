-- rio/lib/rio/cli/commands/about.lua

local Command = require("rio.cli.command")
local project_paths = require("rio.cli.project_paths")

local M = {}

function M.run(ctx)
    ctx.ui.header("Application Environment")

    local effective_lua_path, effective_lua_cpath = ctx.get_lua_paths()
    local original_package_path = package.path
    local original_package_cpath = package.cpath

    package.path = project_paths.lua_path() .. ";" .. ctx.framework_lib_path .. ";" .. effective_lua_path .. ";" .. original_package_path
    package.cpath = effective_lua_cpath .. ";" .. original_package_cpath

    local ok_rio, rio = pcall(require, "rio")
    local rio_version = ok_rio and rio.VERSION or "Unknown"
    local lua_version = _VERSION

    local handle = io.popen("luarocks --version 2>/dev/null", "r")
    local luarocks_output = handle and handle:read("*l") or "Unknown"
    if handle then handle:close() end
    local luarocks_version = luarocks_output:match("luarocks%s+([%d%.]+)") or luarocks_output

    local middleware_str = "None"
    local ok_mw, mw_config = pcall(require, "config.middlewares")
    if ok_mw and type(mw_config) == "table" then
        middleware_str = table.concat(mw_config, ", ")
    end

    local app_root = ctx.files.current_dir() or "."

    local environment = os.getenv("RIO_ENV") or "development"

    local original_path_for_db = package.path
    package.path = project_paths.lua_path() .. ";" .. original_path_for_db
    local db_config_status, db_config = pcall(require, "config.database")
    package.path = original_path_for_db

    local adapter = "None"
    local schema_version = "None"

    if db_config_status and type(db_config) == "table" and db_config[environment] then
        adapter = db_config[environment].adapter or "Unknown"

        local status_conn, conn, adapter_mod = pcall(ctx.get_db_connection, db_config, environment)
        if status_conn and conn then
            local res_status, res = pcall(conn.execute, conn, "SELECT migration FROM migrations ORDER BY migration DESC LIMIT 1")
            if res_status and res and res.fetch then
                local row = res:fetch({}, "a")
                if row and row.migration then
                    schema_version = row.migration:match("^(%d+)") or row.migration
                end
                res:close()
            end
            if adapter_mod and adapter_mod.release_connection then
                pcall(adapter_mod.release_connection, conn, nil)
            end
        end
    end

    ctx.ui.box("Environment Details", function()
        ctx.ui.row("Rio version", rio_version)
        ctx.ui.row("Lua version", lua_version)
        ctx.ui.row("LuaRocks version", luarocks_version)
        ctx.ui.row("Middleware", middleware_str)
        ctx.ui.row("Application root", app_root)
        ctx.ui.row("Environment", environment)
        ctx.ui.row("Database adapter", adapter)
        ctx.ui.row("Schema version", schema_version)
    end)

    package.path = original_package_path
    package.cpath = original_package_cpath
end

function M.command()
    return Command.new({
        name = "about",
        help = function(ctx)
            ctx.show_about_help()
        end,
        run = function(ctx)
            M.run(ctx)
            return true
        end
    })
end

return M
