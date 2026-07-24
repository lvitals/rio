-- rio/lib/rio/cli/command.lua
-- Small command object used by the CLI registry.

local Command = {}
Command.__index = Command

function Command.new(spec)
    spec = spec or {}
    assert(spec.name, "command name is required")
    assert(type(spec.run) == "function", "command run function is required")
    return setmetatable(spec, Command)
end

function Command:matches(name)
    if self.name == name then return true end
    for _, alias in ipairs(self.aliases or {}) do
        if alias == name then return true end
    end
    return false
end

function Command:execute(invocation, context)
    if invocation.help and self.help then
        self.help(context, invocation)
        return true
    end
    return self.run(context, invocation)
end

return Command
