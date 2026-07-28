-- rio/lib/rio/cli/commands/console.lua

local Command = require("rio.cli.command")
local project_paths = require("rio.cli.project_paths")

local M = {}

local LINE_EDITOR_MODULE = "bestline"

M.line_editor_module = LINE_EDITOR_MODULE

local function lua_string(value)
    return string.format("%q", tostring(value or ""))
end

local function parse_options(args, ui)
    local options = {}
    local i = 1
    while i <= #args do
        local arg = args[i]
        if arg == "-e" or arg == "--environment" then
            i = i + 1
            options.environment = args[i]
        elseif arg:match("^%-%-environment=(.+)$") then
            options.environment = arg:match("^%-%-environment=(.+)$")
        elseif arg == "-s" or arg == "--sandbox" then
            options.sandbox = true
        else
            ui.warn("Unknown console option: " .. arg)
        end
        i = i + 1
    end
    return options
end

function M.run(ctx, console_options)
    console_options = console_options or {}
    local colors = ctx.colors
    local get_lua_paths = ctx.get_lua_paths
    local camel_case = ctx.camel_case
    local rio_framework_lib_path_global = ctx.framework_lib_path
    local rio_bin_path_global = ctx.bin_path
    local project_lua_path = project_paths.lua_path()
    -- Verify if we are inside an Rio project
    local ok_project = io.open("config/application.lua", "r")
    if ok_project then
        ok_project:close()
    else
        print(colors.red .. "Error: Not an Rio project. 'rio console' must be run from the project root." .. colors.reset)
        return
    end

    local env = console_options.environment or os.getenv("RIO_ENV") or "development"
    local sandbox = console_options.sandbox or false
    
    print(string.format("Loading %s environment%s...", env, sandbox and " in sandbox" or ""))
    if sandbox then
        print("Any modifications you make will be rolled back on exit")
    end

    local effective_lua_path, effective_lua_cpath = get_lua_paths()
    
    -- Gather models
    local models = {}
    for _, path in ipairs(ctx.files.list("app/models", { mode = "file", pattern = "%.lua$" })) do
        local model = ctx.files.basename(path):match("(.+)%.lua$")
        if model then
            table.insert(models, model)
        end
    end

    local temp_bootstrap_file = "rio_console_bootstrap.lua"
    local bootstrap_content = {
        "-- Console bootstrap script",
        "package.path = " .. lua_string(project_lua_path .. ";" .. rio_framework_lib_path_global .. ";") .. " .. package.path",
        "local rio = require('rio')",
        "local db_manager = require('rio.database.manager')",
        "local ok_db_config, db_config = pcall(require, 'config.database')",
        "",
        "-- Initialize Database",
        "local env = '" .. env .. "'",
        "if ok_db_config and db_config[env] then db_manager.initialize(db_config[env]) end",
        "",
        "-- Load Models into global scope",
    }
    
    for _, model in ipairs(models) do
        local class_name = camel_case(model)
        table.insert(bootstrap_content, string.format("pcall(function() %s = require('app.models.%s') end)", class_name, model))
    end
    
    if sandbox then
        table.insert(bootstrap_content, "if ok_db_config then db_manager.begin() end")
    end

    -- Add app and helper objects
    table.insert(bootstrap_content, [[
-- App object for route testing
local ok_app_config, app_config = pcall(require, "config.application")
if not ok_app_config or type(app_config) ~= "table" then
    app_config = { server = { port = 8080, host = "0.0.0.0" } }
end
app = rio.new(app_config)
local ok_routes, routes_fn = pcall(require, "config.routes")
if ok_routes then routes_fn(app) end

-- Helper object
helper = {}
function helper.link_to(text, url) return string.format('<a href="%s">%s</a>', url, text) end

-- Pretty print helper
function pp(val)
    local string_utils = require("rio.utils.string")
    local mt = getmetatable(val)
    if mt and mt.__tostring then
        print(tostring(val))
    else
        print(string_utils.inspect(val))
    end
end

-- Function wrapper to allow calling without parentheses
local function make_callable_without_parens(fn, name)
    return setmetatable({}, {
        __call = function(_, ...) return fn(...) end,
        __tostring = function() 
            local ok, res = pcall(fn)
            return "" -- Return empty string since the function handles its own printing
        end
    })
end

-- Reload helper
local function _reload()
    print("Reloading project modules...")
    for k, _ in pairs(package.loaded) do
        if k:match("^app%.") or k:match("^config%.") then
            package.loaded[k] = nil
        end
    end
    -- Re-require models
    local ok_lfs, lfs = pcall(require, "lfs")
    if ok_lfs and lfs.attributes("app/models", "mode") == "directory" then
        for file in lfs.dir("app/models") do
            local m = file:match("(.+)%.lua$")
            if m then
                local string_utils = require("rio.utils.string")
                local class_name = string_utils.camel_case(m)
                _G[class_name] = require("app.models." .. m)
            end
        end
    end
    print("Done.")
end
reload = make_callable_without_parens(_reload, "reload")

-- Test helper
local function _test(args)
    local cmd = "']] .. rio_bin_path_global .. [[' test " .. (args or "")
    os.execute(cmd)
end
test = make_callable_without_parens(_test, "test")

-- DB helper: Quick access to database commands
db = {
    create = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:create") end),
    drop = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:drop") end),
    migrate = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:migrate") end),
    rollback = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:rollback") end),
    status = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:status") end),
    version = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:version") end),
    seed = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:seed") end),
    setup = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:setup") end),
    reset = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:reset") end),
    prepare = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' db:prepare") end)
}

-- Mailbox helper
mailbox = {
    install = make_callable_without_parens(function() os.execute("']] .. rio_bin_path_global .. [[' mailbox:install") end),
    exim = make_callable_without_parens(function() print("Ingress requires stdin. Use: cat mail.eml | rio mailbox:ingress:exim") end),
    postfix = make_callable_without_parens(function() print("Ingress requires stdin. Use: cat mail.eml | rio mailbox:ingress:postfix") end),
    qmail = make_callable_without_parens(function() print("Ingress requires stdin. Use: cat mail.eml | rio mailbox:ingress:qmail") end)
}

-- General commands
server = make_callable_without_parens(function(args) 
    local cmd = "']] .. rio_bin_path_global .. [[' server " .. (args or "")
    if args and (args:find("-d") or args:find("--daemon")) then
        cmd = cmd .. " &"
    end
    os.execute(cmd) 
end)
routes = make_callable_without_parens(function(args) os.execute("']] .. rio_bin_path_global .. [[' routes " .. (args or "")) end)
middleware = make_callable_without_parens(function(args) os.execute("']] .. rio_bin_path_global .. [[' middleware " .. (args or "")) end)
about = make_callable_without_parens(function(args) os.execute("']] .. rio_bin_path_global .. [[' about " .. (args or "")) end)
initializers = make_callable_without_parens(function(args) os.execute("']] .. rio_bin_path_global .. [[' initializers " .. (args or "")) end)
help = make_callable_without_parens(function(cmd) os.execute("']] .. rio_bin_path_global .. [[' help " .. (cmd or "")) end)

local function _list_history()
    for i, cmd in ipairs(_G._history or {}) do
        print(string.format("%d  %s", i, cmd))
    end
end

history = setmetatable({
    clear = make_callable_without_parens(function()
        _G._history = {}
        print("Console history cleared.")
    end)
}, {
    __call = function()
        _list_history()
    end,
    __tostring = function()
        _list_history()
        return ""
    end
})
clear = make_callable_without_parens(function() io.write("\27[2J\27[H") end)

-- Generators
generate = function(type, name, ...)
    local extra = table.concat({...}, " ")
    os.execute(string.format("']] .. rio_bin_path_global .. [[' generate %s %s %s", type or "", name or "", extra))
end
g = generate

destroy = function(type, name)
    os.execute(string.format("']] .. rio_bin_path_global .. [[' destroy %s %s", type or "", name or ""))
end
]])

    table.insert(bootstrap_content, [[
-- Custom REPL logic to support automatic pretty-printing
local function start_repl()
    local string_utils = require("rio.utils.string")
    local line_editor_ok, line_editor = pcall(require, ]] .. lua_string(LINE_EDITOR_MODULE) .. [[)
    local env_name = ']] .. env .. [['
    
    -- Prompt colors based on environment
    local env_colors = {
        development = "\27[32m", -- Green
        test = "\27[34m",        -- Blue
        production = "\27[31m"   -- Red
    }
    local color = env_colors[env_name] or "\27[33m" -- Yellow as fallback
    local reset = "\27[0m"
    local prompt = string.format("%s%s> %s", color, env_name, reset)
    
    _G._history = {}
    
    if line_editor_ok then
        -- Standard Tab completion (Compatible with 0.9+)
        line_editor.setcompletion(function(c, s)
            local completions = {}
            local seen = {}
            
            -- Identify the part of the line being completed
            local prefix = s:match("[%w_%.%:]*$") or ""
            local context = s:sub(1, #s - #prefix)
            
            if #prefix > 0 then
                -- 1. Complete Global keys
                if not prefix:find("[%.:]") then
                    for k, v in pairs(_G) do
                        if type(k) == "string" and k:sub(1, 1) ~= "_" then
                            if k:sub(1, #prefix) == prefix then
                                local full = context .. k
                                if not seen[full] then table.insert(completions, full) seen[full] = true end
                            end
                        end
                    end
                else
                    -- 2. Complete Table members (e.g. User. or app:)
                    local t_name, sep, m_prefix = prefix:match("^([%w_]+)([%.:])([%w_]*)$")
                    if t_name and _G[t_name] and type(_G[t_name]) == "table" then
                        for k, v in pairs(_G[t_name]) do
                            if type(k) == "string" and k:sub(1, #m_prefix) == m_prefix then
                                local full = context .. t_name .. sep .. k
                                if not seen[full] then table.insert(completions, full) seen[full] = true end
                            end
                        end
                    end
                end
            end
            
            table.sort(completions)
            for _, cmd in ipairs(completions) do
                -- Use completion:add syntax as in the example
                if c.add then c:add(cmd) else line_editor.addcompletion(c, cmd) end
            end
        end)

        if line_editor.enableutf8 then line_editor.enableutf8(1) end
    end
    
    print(string.format("Rio console (%s) ready. Type 'exit' or Ctrl+D to quit.", env_name))
    
    while true do
        local input, err
        if line_editor_ok then
            local read_line = line_editor.line or line_editor.bestline
            input, err = read_line(prompt)
            
            if not input and err and err ~= "" then
                print("\27[31mError: " .. tostring(err) .. "\27[0m")
                input = "" -- Continue loop
            end
        else
            io.write(prompt)
            -- Catch Ctrl+C (interrupt) silently
            local ok_read, read_input = pcall(io.read)
            if not ok_read or not read_input then 
                if not ok_read then print("") end -- New line after ^C
                break 
            end
            input = read_input
        end
        
        if not input or input == "exit" or input == "os.exit()" then 
            break 
        end
        
        if input ~= "" then
            -- Record history in memory
            table.insert(_G._history, input)
            if line_editor_ok then
                line_editor.historyadd(input)
            end

            -- Try to load with 'return ' prefix first for expressions
            local expr_input = input
            
            -- Auto-fix common mistakes before loading
            -- 1. Handle space-separated commands (CLI style in REPL)
            local cli_style_cmds = { "help", "test", "generate", "g", "destroy", "server", "routes", "middleware", "about", "initializers" }
            for _, cmd in ipairs(cli_style_cmds) do
                -- Match command followed by space and anything else
                local pattern = "^(" .. cmd:gsub(":", "%%:") .. ")%s+(.+)$"
                local found_cmd, args = expr_input:match(pattern)
                if found_cmd then
                    -- Convert 'cmd args' to 'cmd("args")'
                    expr_input = string.format("%s(\"%s\")", found_cmd, args:gsub("\"", "\\\""))
                    break
                end
            end

            -- 2. Convert .method to :method for common terminal methods
            local terminal_methods = { "all", "get", "first", "last", "count", "sum", "avg", "min", "max", "exists", "save", "update", "delete", "validate" }
            for _, m in ipairs(terminal_methods) do
                if expr_input:match("%." .. m .. "$") or expr_input:match("%." .. m .. "%s*%(") then
                    expr_input = expr_input:gsub("%.(" .. m .. ")", ":%1")
                end
            end
            
            -- 2. General Model.method to Model:method
            if expr_input:match("^[A-Z][%w_]+%.[%w_]+") then
                expr_input = expr_input:gsub("^([A-Z][%w_]+)%.([%w_]+)", "%1:%2")
            end

            local chunk, err = load("return " .. expr_input)
            
            -- If it's a colon call without parens (e.g. User:all), auto-append ()
            if not chunk and expr_input:match(":[%w_]+$") then
                local retry_input = "return " .. expr_input .. "()"
                local retry_chunk = load(retry_input)
                if retry_chunk then
                    chunk = retry_chunk
                end
            end

            if not chunk then
                -- Fallback to original input for statements (like 'x = 1')
                chunk, err = load(input)
            end
            
            if chunk then
                local success, result = pcall(chunk)
                if success then
                    if result ~= nil then
                        pp(result)
                    end
                else
                    print("Error: " .. tostring(result))
                end
            else
                print("Error: " .. tostring(err))
            end
        end
    end
end

start_repl()
os.exit()
]])

    -- Set environment variables for the current process
    package.path = effective_lua_path
    package.cpath = effective_lua_cpath

    local code = table.concat(bootstrap_content, "\n")
    local chunk, err = load(code)
    
    if chunk then
        chunk()
    else
        print(colors.red .. "Error loading console environment: " .. tostring(err) .. colors.reset)
    end
end


function M.command()
    return Command.new({
        name = "console",
        help = function(ctx)
            ctx.show_console_help()
        end,
        run = function(ctx, invocation)
            M.run(ctx, parse_options(invocation.args, ctx.ui))
            return true
        end
    })
end

return M
