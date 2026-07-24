-- rio/lib/rio/cli/database.lua
-- Shared database services used by CLI commands without keeping DB logic in cli.lua.

local M = {}
local Service = {}
Service.__index = Service

function M.new(ctx)
    ctx = ctx or {}
    ctx.database_config = ctx.database_config or require("rio.cli.database_config")
    ctx.db_drivers = ctx.db_drivers or require("rio.database.drivers")
    assert(ctx.ui, "database services require ui")
    assert(ctx.colors, "database services require colors")
    assert(ctx.files, "database services require files")
    assert(ctx.get_lua_paths, "database services require get_lua_paths")
    return setmetatable(ctx, Service)
end

function Service:normalize_adapter(adapter, allow_none)
    if not adapter then return nil end
    local value = tostring(adapter):lower()
    if allow_none and value == "none" then return "none" end
    local spec = self.db_drivers.get(value)
    return spec and spec.adapter or nil
end

function Service:print_install_hint(adapter)
    local spec = self.db_drivers.get(adapter)
    if not spec then return end

    self.ui.status("Database driver", false, spec.label .. " is not installed")
    self.ui.box("Install Driver", function()
        self.ui.row("Rio command", "rio db:install " .. spec.adapter)
        self.ui.row("Native dependency", spec.native_dependency)
        for _, var in ipairs(spec.build_variables or {}) do
            self.ui.row("Build variable", var.name .. "=<include_dir>")
        end
    end)
end

function Service:is_driver_available(adapter)
    local effective_lua_path, effective_lua_cpath = self.get_lua_paths()
    return self.db_drivers.check(adapter, effective_lua_path, effective_lua_cpath)
end

function Service:ensure_driver_available(adapter)
    local normalized = self:normalize_adapter(adapter)
    if not normalized then
        self.ui.status("Database adapter", false, "Invalid adapter '" .. tostring(adapter) .. "'")
        self.ui.line("Supported adapters: " .. self.db_drivers.supported_names(), self.colors.dim)
        return false
    end

    if self:is_driver_available(normalized) then
        return true
    end

    self:print_install_hint(normalized)
    return false
end

function Service:core()
    if not self.db_core then
        self.db_core = require("rio.cli.commands.db_core").new({
            ui = self.ui,
            colors = self.colors,
            db_drivers = self.db_drivers,
            get_lua_paths = self.get_lua_paths,
            normalize_database_adapter = function(adapter, allow_none)
                return self:normalize_adapter(adapter, allow_none)
            end,
            is_database_driver_available = function(adapter)
                return self:is_driver_available(adapter)
            end,
            ensure_database_driver_available = function(adapter)
                return self:ensure_driver_available(adapter)
            end,
            print_driver_install_hint = function(adapter)
                return self:print_install_hint(adapter)
            end,
            create_dir_if_not_exists = function(path)
                self.files.ensure_dir(path)
            end,
            write_file_content = function(path, content)
                local ok = self.files.write(path, content)
                if not ok then
                    print("Error: Could not open file for writing: " .. path)
                end
            end,
            file_exists = function(path)
                return self.files.exists(path)
            end,
            database_config = self.database_config
        })
    end
    return self.db_core
end

function Service:generate_database_content(database_adapter, project_name, config)
    return self:core().generate_database_content(database_adapter, project_name, config)
end

function Service:get_connection(db_config, env)
    return self:core().get_connection(db_config, env)
end

function Service:context()
    return {
        db_drivers = self.db_drivers,
        database_config = self.database_config,
        normalize_database_adapter = function(adapter, allow_none)
            return self:normalize_adapter(adapter, allow_none)
        end,
        is_database_driver_available = function(adapter)
            return self:is_driver_available(adapter)
        end,
        ensure_database_driver_available = function(adapter)
            return self:ensure_driver_available(adapter)
        end,
        print_driver_install_hint = function(adapter)
            return self:print_install_hint(adapter)
        end,
        get_db_connection = function(db_config, env)
            return self:get_connection(db_config, env)
        end
    }
end

return M
