-- rio/lib/rio/cli/generators/resource.lua

return {
    name = "resource",
    run = function(ctx, name, params, options)
        ctx.generate_resource(name, params, options.api_only)
    end
}
