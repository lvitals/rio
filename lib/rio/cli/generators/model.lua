-- rio/lib/rio/cli/generators/model.lua

return {
    name = "model",
    run = function(ctx, name, params)
        ctx.generate_model(name, params)
    end
}
