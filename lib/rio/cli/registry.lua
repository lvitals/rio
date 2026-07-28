-- rio/lib/rio/cli/registry.lua
-- Command registry and dispatcher for Rio CLI.

local M = {}
local Registry = {}
Registry.__index = Registry

local CORE_COMMAND_MODULES = {
    "rio.cli.commands.new",
    "rio.cli.commands.server",
    "rio.cli.commands.console",
    "rio.cli.commands.runner",
    "rio.cli.commands.test",
    "rio.cli.commands.db",
    "rio.cli.commands.help",
    "rio.cli.commands.ui",
    "rio.cli.commands.routes",
    "rio.cli.commands.middleware",
    "rio.cli.commands.generate",
    "rio.cli.commands.destroy",
    "rio.cli.commands.initializers",
    "rio.cli.commands.stats",
    "rio.cli.commands.about",
    "rio.cli.commands.tmp",
    "rio.cli.commands.mailbox"
}

function M.new()
    return setmetatable({ commands = {}, order = {} }, Registry)
end

function Registry:register(command)
    self.commands[command.name] = command
    table.insert(self.order, command.name)
    for _, alias in ipairs(command.aliases or {}) do
        self.commands[alias] = command
    end
    return self
end

function Registry:register_modules(module_names)
    for _, module_name in ipairs(module_names or {}) do
        self:register(require(module_name).command())
    end
    return self
end

function Registry:register_defaults()
    return self:register_modules(CORE_COMMAND_MODULES)
end

function Registry:dispatch(invocation, context)
    if not invocation or not invocation.command then
        return false
    end

    local command = self.commands[invocation.command]
    if not command then
        return false
    end

    local ok, exit_code = command:execute(invocation, context)
    if ok == false then
        return true, false, exit_code
    end

    return true, true, exit_code or 0
end

function M.with_defaults(extra_modules)
    return M.new():register_defaults():register_modules(extra_modules)
end

return M
