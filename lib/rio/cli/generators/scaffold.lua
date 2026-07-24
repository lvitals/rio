-- rio/lib/rio/cli/generators/scaffold.lua

return {
    name = "scaffold",
    run = function(ctx, name, params, options)
        ctx.generate_scaffold(name, params, options.api_only)
    end
}
