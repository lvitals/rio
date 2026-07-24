-- rio/lib/rio/cli/generators/init.lua

local M = {}

local modules = {
    "rio.cli.generators.channel",
    "rio.cli.generators.controller",
    "rio.cli.generators.migration",
    "rio.cli.generators.model",
    "rio.cli.generators.resource",
    "rio.cli.generators.scaffold"
}

function M.load()
    local generators = {}
    for _, module_name in ipairs(modules) do
        local generator = require(module_name)
        generators[generator.name] = generator
    end
    return generators
end

return M
