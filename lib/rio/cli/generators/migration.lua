-- rio/lib/rio/cli/generators/migration.lua

return {
    name = "migration",
    run = function(ctx, name, params)
        ctx.generate_migration(name, params)
    end
}
