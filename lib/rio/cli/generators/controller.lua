-- rio/lib/rio/cli/generators/controller.lua

return {
    name = "controller",
    run = function(ctx, name, params, options)
        ctx.generate_controller(name, params, options.api_only)
    end
}
