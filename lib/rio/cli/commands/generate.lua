-- rio/lib/rio/cli/commands/generate.lua

local Command = require("rio.cli.command")
local generator_registry = require("rio.cli.generators")

local M = {}

local function split_generation_args(args)
    local name = args[1]
    local params = {}
    local api_only = false
    for i = 2, #args do
        if args[i] == "--api" then
            api_only = true
        else
            table.insert(params, args[i])
        end
    end
    return name, params, api_only
end

function M.command()
    return Command.new({
        name = "generate",
        aliases = { "scaffold", "resource" },
        help = function(ctx)
            ctx.show_generate_help()
        end,
        run = function(ctx, invocation)
            local generator_type = invocation.subcommand
            if invocation.command == "scaffold" or invocation.command == "resource" then
                generator_type = invocation.command
            end

            local generator_name, generator_params, api_only_flag = split_generation_args(invocation.args)
            if not generator_type then
                ctx.ui.status("Resource generation", false, "Generator type is required")
                ctx.show_generate_help()
                return true
            end
            if not generator_name then
                ctx.ui.status("Resource generation", false, "'" .. generator_type .. "' requires a name")
                ctx.show_generate_help()
                return true
            end

            local api_only = api_only_flag or ctx.is_api_only()
            local generators = generator_registry.load()
            local generator = generators[generator_type]
            if not generator then
                ctx.ui.status("Resource generation", false, "Unknown generator type '" .. generator_type .. "'")
                ctx.show_generate_help()
                return true
            end

            generator.run(ctx, generator_name, generator_params, { api_only = api_only })
            return true
        end
    })
end

return M
