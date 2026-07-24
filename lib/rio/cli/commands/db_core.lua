-- rio/lib/rio/cli/commands/db_core.lua
-- Database command implementation for Rio CLI.

local M = {}
local files = require("rio.cli.files")

function M.new(ctx)
    local ui = ctx.ui
    local colors = ctx.colors
    local db_drivers = ctx.db_drivers
    local get_lua_paths = ctx.get_lua_paths
    local normalize_database_adapter = ctx.normalize_database_adapter
    local is_database_driver_available = ctx.is_database_driver_available
    local ensure_database_driver_available = ctx.ensure_database_driver_available
    local print_driver_install_hint = ctx.print_driver_install_hint
    local create_dir_if_not_exists = ctx.create_dir_if_not_exists
    local write_file_content = ctx.write_file_content
    local file_exists = ctx.file_exists
    local cli_database_config = ctx.database_config

    local function generate_database_content(database_adapter, project_name, config)
        return cli_database_config.generate(database_adapter, project_name, config)
    end
    
    local function interactive_db_setup()
        ui.header("Rio Database Setup")
        ui.info("No database configuration found or config is empty.")
    
        local adapter_specs = db_drivers.all()
        ui.box("Choose Adapter", function()
            for i, spec in ipairs(adapter_specs) do
                local label = spec.label
                if spec.adapter == "sqlite" then label = label .. " (recommended for development)" end
                ui.row(tostring(i), label)
            end
            ui.row("q", "Cancel")
        end)
        
        io.write("\nSelection: ")
        local choice = io.read()
        
        if choice:lower() == "q" then
            ui.info("Setup cancelled.")
            return nil
        end
    
        local choice_idx = tonumber(choice)
        local adapter_spec = adapter_specs[choice_idx]
        local adapter = adapter_spec and adapter_spec.adapter
    
        if not adapter then 
            ui.status("Database setup", false, "Invalid selection")
            return nil
        end
        
        local config = {}
        if adapter ~= "sqlite" then
            io.write("\nWould you like to configure connection details now? (y/N): ")
            local configure_now = io.read()
            if configure_now and (configure_now:lower() == "y" or configure_now:lower() == "yes") then
                local default_port = (adapter == "postgres") and 5432 or 3306
                local default_user = (adapter == "postgres") and "rio_dev" or "root"
                
                io.write("Host (default: localhost): ")
                config.host = io.read(); if config.host == "" then config.host = nil end
                
                io.write("Port (default: " .. default_port .. "): ")
                config.port = io.read(); if config.port == "" then config.port = nil end
                
                io.write("Username (default: " .. default_user .. "): ")
                config.username = io.read(); if config.username == "" then config.username = nil end
                
                io.write("Password (default: password): ")
                config.password = io.read(); if config.password == "" then config.password = nil end
                
                io.write("Database Name (leave empty for default): ")
                config.database = io.read(); if config.database == "" then config.database = nil end
            end
        end
        
        local project_name = "rio_app"
        -- Try to guess project name from current directory
        local current_dir = files.basename(files.current_dir())
        if current_dir then project_name = current_dir end
        
        local content = generate_database_content(adapter, project_name, config)
        if content ~= "" then
            create_dir_if_not_exists("config")
            write_file_content("config/database.lua", content)
            ui.status("Database configuration", true, "Created config/database.lua with " .. adapter .. " adapter")
            if not is_database_driver_available(adapter) then
                print_driver_install_hint(adapter)
            end
            
            -- Reload config
            package.loaded["config.database"] = nil
            local original_package_path = package.path
            package.path = "./config/?.lua;" .. package.path
            local status, db_config = pcall(require, "config.database")
            package.path = original_package_path
            return status and db_config or nil
        end
        return nil
    end
    
    -- Database commands
    local function load_database_config()
        local config_file = "config/database.lua"
        
        -- To load config.database, we need to ensure the current project's config directory is in LUA_PATH
        local original_package_path = package.path
        package.path = "./config/?.lua;" .. package.path
    
        local status, db_config = pcall(require, "config.database") -- require "config.database"
        package.path = original_package_path -- Restore original path
    
        if not status or type(db_config) ~= "table" or next(db_config) == nil then
            -- If config is missing, malformed or empty, trigger interactive setup
            return interactive_db_setup()
        end
        return db_config
    end
    
    local function read_database_config()
        local original_package_path = package.path
        package.path = "./config/?.lua;" .. package.path
    
        local status, db_config = pcall(require, "config.database")
        package.path = original_package_path
    
        if not status or type(db_config) ~= "table" or next(db_config) == nil then
            return nil
        end
        return db_config
    end
    
    local function get_database_full_path(db_config, env)
        local current_env_config = db_config[env]
        if not current_env_config then
            return nil, "Database configuration not found for environment: " .. env
        end
    
        if current_env_config.adapter ~= "sqlite" then
            return nil, "Unsupported adapter for file operations: " .. current_env_config.adapter
        end
    
        -- Assuming current_env_config.database already contains the full file path including extension
        return current_env_config.database
    end
    
    local function is_safe_luarocks_arg(arg)
        return type(arg) == "string"
            and arg ~= ""
            and arg:match("^[%w_%.%-%+/=:@]+$") ~= nil
    end
    
    local function has_luarocks_variable(args, name)
        for _, arg in ipairs(args or {}) do
            if tostring(arg):match("^" .. name .. "=") then
                return true
            end
        end
        return false
    end

    local function add_luarocks_variable(args, name, value)
        if not value or value == "" or has_luarocks_variable(args, name) then
            return false
        end
        local arg = name .. "=" .. value
        if not is_safe_luarocks_arg(arg) then
            return false
        end
        table.insert(args, arg)
        return true
    end

    local function parse_luarocks_variable(arg)
        local name, value = tostring(arg):match("^([%w_]+)=(.+)$")
        return name, value
    end

    local function shell_capture(command)
        if type(command) ~= "string" or command == "" then return nil end
        local handle = io.popen(command .. " 2>/dev/null", "r")
        if not handle then return nil end
        local output = handle:read("*a")
        handle:close()
        output = output and output:gsub("%s+$", "") or nil
        if output == "" then return nil end
        return output
    end

    local function extract_flag_value(output, flag)
        if not output then return nil end
        if not flag then
            return output:match("^%s*(.-)%s*$")
        end
        for token in output:gmatch("%S+") do
            local value = token:match("^" .. flag:gsub("%-", "%%-") .. "(.+)$")
            if value and value ~= "" then
                return value
            end
        end
        return nil
    end

    local function normalize_build_args(spec, opts)
        opts.extra_args = opts.extra_args or {}

        local function find_header_dir(root, header)
            if not root or not header then return nil end
            if file_exists(root .. "/" .. header) then return root end
            for _, path in ipairs(files.find(root, { pattern = header .. "$" })) do
                local dir = path:match("^(.*)[/\\][^/\\]+$")
                if dir then return dir end
            end
            return nil
        end

        for index, arg in ipairs(opts.extra_args) do
            local name, value = parse_luarocks_variable(arg)
            if name == "MYSQL_DIR" and value then
                local header_dir = find_header_dir(value, "mysql.h")
                if value:match("[/\\]include$") or header_dir then
                    opts.extra_args[index] = "MYSQL_INCDIR=" .. (header_dir or value)
                    ui.info("Using MYSQL_INCDIR because MYSQL_DIR appends an extra /include.")
                elseif file_exists(value .. "/mysql.h") then
                    opts.extra_args[index] = "MYSQL_INCDIR=" .. value
                    ui.info("Using MYSQL_INCDIR because the value points directly at mysql.h.")
                end
            elseif name == "PGSQL_DIR" and value then
                local header_dir = find_header_dir(value, "libpq-fe.h")
                if value:match("[/\\]include$") or header_dir then
                    opts.extra_args[index] = "PGSQL_INCDIR=" .. (header_dir or value)
                    ui.info("Using PGSQL_INCDIR because PGSQL_DIR appends an extra /include.")
                elseif file_exists(value .. "/libpq-fe.h") then
                    opts.extra_args[index] = "PGSQL_INCDIR=" .. value
                    ui.info("Using PGSQL_INCDIR because the value points directly at libpq-fe.h.")
                end
            end
        end
    end
    
    local function add_detected_build_variables(spec, opts)
        opts.extra_args = opts.extra_args or {}

        for _, tool in ipairs(spec.config_tools or {}) do
            if not has_luarocks_variable(opts.extra_args, tool.variable) then
                local output = shell_capture(tool.command)
                local value = extract_flag_value(output, tool.flag)
                add_luarocks_variable(opts.extra_args, tool.variable, value)
            end
        end
    end
    
    local function run_db_drivers()
        ui.header("Database Drivers")
    
        for _, spec in ipairs(db_drivers.all()) do
            local available = is_database_driver_available(spec.adapter)
            local status = available and "installed" or "missing"
            ui.row(spec.label, status .. " (" .. spec.module .. ")")
        end
    
        ui.line("Install example: rio db:install sqlite", colors.dim)
    end
    
    local function run_db_install(args)
        args = args or {}
    
        local adapter = nil
        local opts = {
            local_install = false,
            extra_args = {}
        }
        local explicit_tree = false
    
        for _, arg in ipairs(args) do
            local named_adapter = arg:match("^%-%-adapter=(.+)$") or arg:match("^%-%-to=(.+)$")
            local tree = arg:match("^%-%-tree=(.+)$")
    
            if named_adapter then
                adapter = named_adapter
            elseif tree then
                if not is_safe_luarocks_arg(tree) then
                    ui.status("Database driver install", false, "Unsafe --tree value")
                    return
                end
                opts.tree = tree
                opts.local_install = false
                explicit_tree = true
            elseif arg == "--local" then
                opts.local_install = true
                explicit_tree = true
            elseif arg == "--system" then
                opts.local_install = false
                explicit_tree = true
            elseif arg:match("^%-") then
                if not is_safe_luarocks_arg(arg) then
                    ui.status("Database driver install", false, "Unsafe LuaRocks option '" .. tostring(arg) .. "'")
                    return
                end
                table.insert(opts.extra_args, arg)
            elseif not adapter then
                adapter = arg
            else
                if not is_safe_luarocks_arg(arg) then
                    ui.status("Database driver install", false, "Unsafe LuaRocks argument '" .. tostring(arg) .. "'")
                    return
                end
                table.insert(opts.extra_args, arg)
            end
        end
    
        if not adapter then
            local db_config = read_database_config()
            local env = os.getenv("RIO_ENV") or "development"
            adapter = db_config and db_config[env] and db_config[env].adapter
        end
    
        local normalized = normalize_database_adapter(adapter)
        if not normalized then
            local detail = adapter and ("Invalid adapter '" .. tostring(adapter) .. "'") or "Adapter is required"
            ui.status("Database driver install", false, detail)
            ui.line("Usage: rio db:install <sqlite|mysql|mariadb|postgresql>", colors.yellow)
            return
        end
    
        local spec = db_drivers.get(normalized)
        local already_available = is_database_driver_available(normalized)
        if already_available then
            ui.status("Database driver", true, spec.label .. " is already installed (" .. spec.module .. ")")
            return
        end
    
        if not explicit_tree then
            opts.tree = db_drivers.infer_tree_from_cpath(package.cpath)
        end
        normalize_build_args(spec, opts)
        add_detected_build_variables(spec, opts)
    
        ui.header("Database Driver Install")
        ui.box(spec.label, function()
            ui.row("LuaRocks package", spec.rock)
            ui.row("Native dependency", spec.native_dependency)
            if opts.tree then ui.row("Target tree", opts.tree) end
            for _, arg in ipairs(opts.extra_args or {}) do
                if arg:match("^[%w_]+=") then ui.row("Build option", arg) end
            end
        end)
    
        local command = db_drivers.install_command(normalized, opts)
        ui.line("Running: " .. command, colors.dim)
        local result = os.execute(command)
        local ok = (result == true or result == 0)
    
        if not ok then
            ui.status("Database driver install", false, "LuaRocks could not install " .. spec.rock)
            ui.info("Install the native dependency listed above, then run the same command again.")
            ui.info("Rio uses mysql_config, mariadb_config or pg_config when available.")
            ui.info("For custom paths, pass LuaRocks variables such as MYSQL_INCDIR=/path/that/contains/mysql.h and MYSQL_LIBDIR=/path/to/libs.")
            return
        end
    
        package.loaded[spec.module] = nil
        if is_database_driver_available(normalized) then
            ui.status("Database driver install", true, spec.label .. " driver installed")
        else
            ui.status("Database driver install", false, "Rio still cannot load " .. spec.module)
            ui.info("Run `eval $(luarocks path)` or check your LUA_PATH/LUA_CPATH.")
        end
    end
    
    local function run_db_uninstall(args)
        args = args or {}
    
        local adapter = nil
        local opts = {
            local_install = false,
            extra_args = {}
        }
        local explicit_tree = false
        local force_requested = false
    
        for _, arg in ipairs(args) do
            local named_adapter = arg:match("^%-%-adapter=(.+)$") or arg:match("^%-%-from=(.+)$")
            local tree = arg:match("^%-%-tree=(.+)$")
    
            if named_adapter then
                adapter = named_adapter
            elseif tree then
                if not is_safe_luarocks_arg(tree) then
                    ui.status("Database driver uninstall", false, "Unsafe --tree value")
                    return
                end
                opts.tree = tree
                opts.local_install = false
                explicit_tree = true
            elseif arg == "--local" then
                opts.local_install = true
                explicit_tree = true
            elseif arg == "--system" then
                opts.local_install = false
                explicit_tree = true
            elseif arg == "--force" or arg == "--force-fast" then
                force_requested = true
                table.insert(opts.extra_args, arg)
            elseif arg:match("^%-") then
                if not is_safe_luarocks_arg(arg) then
                    ui.status("Database driver uninstall", false, "Unsafe LuaRocks option '" .. tostring(arg) .. "'")
                    return
                end
                table.insert(opts.extra_args, arg)
            elseif not adapter then
                adapter = arg
            else
                if not is_safe_luarocks_arg(arg) then
                    ui.status("Database driver uninstall", false, "Unsafe LuaRocks argument '" .. tostring(arg) .. "'")
                    return
                end
                table.insert(opts.extra_args, arg)
            end
        end
    
        if not adapter then
            local db_config = read_database_config()
            local env = os.getenv("RIO_ENV") or "development"
            adapter = db_config and db_config[env] and db_config[env].adapter
        end
    
        local normalized = normalize_database_adapter(adapter)
        if not normalized then
            local detail = adapter and ("Invalid adapter '" .. tostring(adapter) .. "'") or "Adapter is required"
            ui.status("Database driver uninstall", false, detail)
            ui.line("Usage: rio db:uninstall <sqlite|mysql|mariadb|postgresql>", colors.yellow)
            return
        end
    
        local spec = db_drivers.get(normalized)
        if not is_database_driver_available(normalized) then
            ui.status("Database driver", true, spec.label .. " is already absent (" .. spec.module .. ")")
            return
        end
    
        local db_config = read_database_config()
        local env = os.getenv("RIO_ENV") or "development"
        local current_adapter = db_config and db_config[env] and normalize_database_adapter(db_config[env].adapter)
        if current_adapter == normalized and not force_requested then
            ui.status("Database driver uninstall", false, "Current project uses " .. spec.label)
            ui.line("Change config/database.lua or run: rio db:uninstall " .. spec.adapter .. " --force", colors.dim)
            return
        end
    
        local effective_lua_path, effective_lua_cpath = get_lua_paths()
        local module_path = db_drivers.module_path(normalized, effective_lua_path, effective_lua_cpath)
        if not explicit_tree and module_path then
            opts.tree = db_drivers.infer_tree_from_module_path(module_path)
        end
    
        ui.header("Database Driver Uninstall")
        ui.box(spec.label, function()
            ui.row("LuaRocks package", spec.rock)
            ui.row("Module", spec.module)
            if module_path then ui.row("Loaded from", module_path) end
            if opts.tree then ui.row("Target tree", opts.tree) end
        end)
    
        local command = db_drivers.remove_command(normalized, opts)
        ui.line("Running: " .. command, colors.dim)
        local result = os.execute(command)
        local ok = (result == true or result == 0)
    
        if not ok then
            ui.status("Database driver uninstall", false, "LuaRocks could not remove " .. spec.rock)
            ui.info("If another rock depends on it, rerun with --force after checking that dependency.")
            return
        end
    
        package.loaded[spec.module] = nil
        if not is_database_driver_available(normalized) then
            ui.status("Database driver uninstall", true, spec.label .. " driver removed")
        else
            ui.status("Database driver uninstall", false, "Rio can still load " .. spec.module)
            ui.info("Check other LuaRocks trees with `luarocks list " .. spec.rock .. "`.")
        end
    end
    
    local function get_db_connection(db_config, env)
        local current_env_config = db_config[env]
        if not current_env_config then
            return nil, "Database configuration not found for environment: " .. env
        end
    
        local adapter_name = current_env_config.adapter
        if not ensure_database_driver_available(adapter_name) then
            return nil, "Database driver is not installed."
        end
    
        local effective_lua_path, effective_lua_cpath = get_lua_paths()
    
        local adapter
        local ok, err_msg = pcall(function()
            local original_package_path = package.path
            local original_package_cpath = package.cpath
            package.path = effective_lua_path
            package.cpath = effective_lua_cpath
            
            adapter = require("rio.database.adapters." .. adapter_name)
            
            package.path = original_package_path
            package.cpath = original_package_cpath
        end)
        
        if not ok then
            return nil, "Could not load database adapter '" .. adapter_name .. "': " .. err_msg
        end
    
        -- Initialize the adapter
        if adapter.initialize then
            local original_package_cpath = package.cpath
            package.cpath = effective_lua_cpath
            adapter.initialize(current_env_config)
            package.cpath = original_package_cpath
        end
    
        local conn, err = adapter.get_connection()
        if not conn then
            return nil, "Failed to connect to database: " .. (err or "unknown error")
        end
        
        -- Enable autocommit for DML statements
        if conn.autocommit then
            conn:autocommit(true)
        end
    
        return conn, adapter -- Return both connection and adapter for further use
    end
    
    
    local function get_db_config_and_run(fn_name)
        local db_config = load_database_config()
        if not db_config then return end
    
        local env = os.getenv("RIO_ENV") or "development"
        local current_env_config = db_config[env]
    
        if not current_env_config then
            ui.status("Database configuration", false, "Not found for environment: " .. env)
            return
        end
    
        if not ensure_database_driver_available(current_env_config.adapter) then
            return
        end
    
        -- Setup paths for the adapter and app models
        local effective_lua_path, effective_lua_cpath = get_lua_paths()
        local original_package_path = package.path
        local original_package_cpath = package.cpath
        
        -- Prepend project paths so migrations and seeds can require models
        package.path = "./app/?.lua;./app/?/init.lua;./config/?.lua;./lib/?.lua;" .. effective_lua_path .. ";" .. original_package_path
        package.cpath = effective_lua_cpath .. ";" .. original_package_cpath
    
        local Migrate = require("rio.database.migrate").Migrate
        local DB = require("rio.database.manager")
        
        -- Initialize the manager which will load the adapter
        local ok_init, err_init = pcall(DB.initialize, current_env_config)
        if not ok_init then
            ui.status("Database initialization", false, tostring(err_init))
            package.path = original_package_path
            package.cpath = original_package_cpath
            return
        end
    
        -- Call the Migrate method
        if type(Migrate[fn_name]) == "function" then
            ui.header("Database Operation: " .. fn_name)
            if fn_name == "create" or fn_name == "drop" or fn_name == "setup" or fn_name == "reset" or fn_name == "run" then
                Migrate[fn_name](current_env_config)
            else
                Migrate[fn_name]()
            end
        else
            ui.status("Database command execution", false, "Method '" .. fn_name .. "' not found.")
        end
    
        -- Restore paths
        package.path = original_package_path
        package.cpath = original_package_cpath
    end
    
    local function run_db_create() get_db_config_and_run("create") end
    local function run_db_drop() get_db_config_and_run("drop") end
    local function run_db_migrate() get_db_config_and_run("run") end
    local function run_db_rollback() get_db_config_and_run("rollback") end
    local function run_db_status() get_db_config_and_run("status") end
    local function run_db_seed() get_db_config_and_run("seed") end
    local function run_db_setup() get_db_config_and_run("setup") end
    local function run_db_reset() get_db_config_and_run("reset") end
    
    local function run_db_version()
        local db_config = load_database_config()
        if not db_config then return end
    
        local env = os.getenv("RIO_ENV") or "development"
        local current_env_config = db_config[env]
    
        if not current_env_config then
            ui.status("Database configuration", false, "Not found for environment: " .. env)
            return
        end
    
        if not ensure_database_driver_available(current_env_config.adapter) then
            return
        end
    
        -- Setup paths for the adapter
        local effective_lua_path, effective_lua_cpath = get_lua_paths()
        local original_package_path = package.path
        local original_package_cpath = package.cpath
        
        package.path = "./app/?.lua;./app/?/init.lua;./config/?.lua;./lib/?.lua;" .. effective_lua_path .. ";" .. original_package_path
        package.cpath = effective_lua_cpath .. ";" .. original_package_cpath
    
        local DB = require("rio.database.manager")
        local Migrate = require("rio.database.migrate").Migrate
        
        local ok_init, err_init = pcall(DB.initialize, current_env_config)
        if not ok_init then
            ui.status("Database initialization", false, tostring(err_init))
            package.path = original_package_path
            package.cpath = original_package_cpath
            return
        end
    
        local db_name = current_env_config.database or current_env_config.host or "unknown"
        local version = Migrate.version()
    
        ui.header("Database Version")
        ui.row("Database", db_name)
        ui.row("Current version", version or "0")
    
        package.path = original_package_path
        package.cpath = original_package_cpath
    end
    
    local function run_db_seed_replant()
        ui.header("Seed Replant")
        ui.info("Replanting seeds...")
        get_db_config_and_run("seed")
    end
    
    local function run_db_system_change(args)
        local to_adapter = nil
        for _, arg in ipairs(args) do
            to_adapter = arg:match("^%-%-to=(.+)$")
            if to_adapter then break end
        end
    
        if not to_adapter then
            ui.status("Database system change", false, "Target adapter is required")
            ui.line("Example: rio db:system:change --to=postgresql", colors.dim)
            return
        end
    
        local normalized_adapter = normalize_database_adapter(to_adapter)
        
        if not normalized_adapter then
            ui.status("Database adapter", false, "Invalid adapter '" .. to_adapter .. "'")
            ui.line("Supported adapters: " .. db_drivers.supported_names(), colors.dim)
            return
        end
    
        local config_file = "config/database.lua"
        if io.open(config_file, "r") then
            io.write(colors.yellow .. "Overwrite " .. config_file .. "? (y/N): " .. colors.reset)
            local answer = io.read()
            if not (answer and (answer:lower() == "y" or answer:lower() == "yes")) then
                ui.info("Operation cancelled.")
                return
            end
        end
    
        local project_name = "rio_app"
        local current_dir = files.basename(files.current_dir())
        if current_dir then project_name = current_dir end
    
        local config = {}
        if normalized_adapter ~= "sqlite" then
            io.write("\nWould you like to configure connection details now? (y/N): ")
            local configure_now = io.read()
            if configure_now and (configure_now:lower() == "y" or configure_now:lower() == "yes") then
                local default_port = (normalized_adapter == "postgres") and 5432 or 3306
                local default_user = (normalized_adapter == "postgres") and "rio_dev" or "root"
                
                io.write("Host (default: localhost): ")
                config.host = io.read(); if config.host == "" then config.host = nil end
                
                io.write("Port (default: " .. default_port .. "): ")
                config.port = io.read(); if config.port == "" then config.port = nil end
                
                io.write("Username (default: " .. default_user .. "): ")
                config.username = io.read(); if config.username == "" then config.username = nil end
                
                io.write("Password (default: password): ")
                config.password = io.read(); if config.password == "" then config.password = nil end
                
                io.write("Database Name (leave empty for default): ")
                config.database = io.read(); if config.database == "" then config.database = nil end
            end
        end
    
        local content = generate_database_content(normalized_adapter, project_name, config)
        if content ~= "" then
            write_file_content(config_file, content)
            ui.status("Database configuration", true, "Updated " .. config_file .. " to use " .. normalized_adapter)
            if not is_database_driver_available(normalized_adapter) then
                print_driver_install_hint(normalized_adapter)
            end
        end
    end
    
    local function run_db_prepare()
        get_db_config_and_run("run")
    end

    local function run_db_cache_clear()
        ui.info("Clearing database metadata cache...")
        local ok, rio = pcall(require, "rio")
        if ok then
            local app = rio.new()
            app.cache:clear()
            ui.status("Database cache", true, "Cleared")
        else
            files.remove_matching("tmp/cache", "%.cache$")
            ui.status("Database cache", true, "Cache directory cleared manually")
        end
    end

    return {
        generate_database_content = generate_database_content,
        interactive_setup = interactive_db_setup,
        load_config = load_database_config,
        read_config = read_database_config,
        database_full_path = get_database_full_path,
        get_connection = get_db_connection,
        drivers = run_db_drivers,
        install = run_db_install,
        uninstall = run_db_uninstall,
        remove = run_db_uninstall,
        create = run_db_create,
        drop = run_db_drop,
        migrate = run_db_migrate,
        rollback = run_db_rollback,
        status = run_db_status,
        version = run_db_version,
        seed = run_db_seed,
        ["seed:replant"] = run_db_seed_replant,
        ["cache:clear"] = run_db_cache_clear,
        setup = run_db_setup,
        reset = run_db_reset,
        prepare = run_db_prepare,
        ["system:change"] = run_db_system_change
    }
end

return M
