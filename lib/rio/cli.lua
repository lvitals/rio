local cli = {}

local ui = require("rio.utils.ui")
local cli_parser = require("rio.cli.parser")
local cli_registry = require("rio.cli.registry")
local cli_context = require("rio.cli.context")

cli.colors = ui.colors
cli.ui = ui

function cli.run(args, framework_lib_path, bin_path) -- Receive framework_lib_path here
    local invocation = cli_parser.parse(args, {
        shift_subcommand_for = {
            generate = true,
            destroy = true
        }
    })
    local context = cli_context.build({
        framework_lib_path = framework_lib_path,
        bin_path = bin_path
    })

    if not invocation.command then
        context.show_general_help()
        return
    end

    local registry = cli_registry.with_defaults()
    if registry:dispatch(invocation, context) then
        return
    end

    ui.status("CLI command", false, "Unknown command '" .. tostring(invocation.full_command) .. "'")
    context.show_general_help()
end

return cli
