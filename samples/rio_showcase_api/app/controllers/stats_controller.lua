local Project = require("app.models.project")
local User = require("app.models.user")
local Label = require("app.models.label")

local StatsController = {}

-- Definition MUST be outside the function for OpenAPI reflection to work
-- StatsController.openapi = {
--     index = {
--         summary = "Get System Stats",
--         headers = {
--             ["X-API-Key"] = "Chave de acesso restrita para estatísticas"
--         }
--     }
-- }

function StatsController:index(ctx)
    -- This calculation is cached for 600 seconds (10 minutes)
    -- Using the Application Cache (Level 2)
    local stats = ctx.app.cache:fetch("global_stats", 600, function()
        print("  [Cache MISS] Calculating expensive statistics...")
        return {
            total_users = User:count(),
            total_projects = Project:count(),
            total_labels = Label:count(),
            calculated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }
    end)

    return ctx:json({
        stats = stats,
        cache_info = "These stats are cached for 10 minutes."
    })
end

return StatsController
