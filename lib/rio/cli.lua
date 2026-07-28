local cli = {}

local ui = require("rio.utils.ui")
local cli_parser = require("rio.cli.parser")
local cli_registry = require("rio.cli.registry")
local cli_context = require("rio.cli.context")

cli.colors = ui.colors
cli.ui = ui

function cli.run(args, framework_lib_path, bin_path)
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
        return true, 0
    end

    local registry = cli_registry.with_defaults()
    local handled, command_ok, exit_code = registry:dispatch(invocation, context)
    if handled then
        if command_ok == false then
            return false, exit_code or 1
        end
        return true, exit_code or 0
    end

    ui.status("CLI command", false, "Unknown command '" .. tostring(invocation.full_command) .. "'")
    context.show_general_help()
    return false, 1
end

return cli
