-- rio/lib/rio/cli/generators/channel.lua

return {
    name = "channel",
    run = function(ctx, name)
        ctx.generate_channel(name)
    end
}
